/*
 * pipa_aec: audio HAL wrapper with a software echo canceller (BUGS-TODO 27).
 *
 * The pipa DSP echo canceller cancels nothing in the VoIP path (HISTORY 2026-10-29 and 2026-11-06).
 * This module is loaded as audio.primary.kona.so. It loads the real HAL
 * (audio.primary.kona_real.so), and patches the function pointers of the real device and of its
 * streams in place:
 *   - every PCM output stream copies what it writes (mono, 48 kHz) into a reference ring;
 *   - every VOICE_COMMUNICATION input stream (16-bit mono) runs the AOSP WebRTC AEC3
 *     (/vendor/lib/soundfx/libaudiopreprocessing.so) with the ring as the far-end reference.
 * Property persist.vendor.audio.pipa_aec: "0" = off (pass-through), else on. Read at input open.
 *
 * Copyright 2026 pipa COS17 port maintainers. Apache-2.0.
 */
#define LOG_TAG "pipa_aec"
#include <android/log.h>
#include <dlfcn.h>
#include <errno.h>
#include <math.h>
#include <pthread.h>
#include <stdlib.h>
#include <string.h>
#include <sys/system_properties.h>
#include <time.h>

#include <hardware/audio.h>
#include <hardware/audio_effect.h>
#include <system/audio_effects/effect_aec.h>

#define ALOGI(...) __android_log_print(ANDROID_LOG_INFO, LOG_TAG, __VA_ARGS__)
#define ALOGW(...) __android_log_print(ANDROID_LOG_WARN, LOG_TAG, __VA_ARGS__)
#define ALOGE(...) __android_log_print(ANDROID_LOG_ERROR, LOG_TAG, __VA_ARGS__)

#ifndef PIPA_REAL_HAL
#define PIPA_REAL_HAL "/vendor/lib/hw/audio.primary.kona.so"
#endif
#define PREPROC_LIB "/vendor/lib/soundfx/libaudiopreprocessing.so"
#define AEC_PARAM_MOBILE_MODE_ID 2 /* t_aec_params: ECHO_DELAY, PROPERTIES, MOBILE_MODE */

/* AOSP WebRTC AEC implementation uuid (libaudiopreprocessing). */
static const effect_uuid_t kAecImplUuid = {
        0xbb392ec0, 0x8d4d, 0x11e0, 0xa896, {0x00, 0x02, 0xa5, 0xd5, 0xc5, 0x1b}};
/* AOSP WebRTC AGC2 implementation uuid: fixed digital gain + limiter, runs after the AEC. */
static const effect_uuid_t kAgc2ImplUuid = {
        0x89f38e65, 0xd4d2, 0x4d64, 0xad0e, {0x2b, 0x3e, 0x79, 0x9e, 0xa8, 0x86}};
#define AGC2_PARAM_FIXED_GAIN_ID 0 /* agc2_params_t: FIXED_DIGITAL_GAIN (int32 dB in this lib) */
#define DEFAULT_GAIN_DB 24

/* ---------------- reference ring (mono float, 48 kHz, absolute sample positions) ------------ */
#define RING_RATE 48000
#define RING_SIZE (RING_RATE * 2)
#define RESYNC_OUT (RING_RATE * 3 / 10) /* 300 ms */
#define RESYNC_IN (RING_RATE / 4)       /* 250 ms */
#define MAX_AHEAD (RING_RATE * 8 / 10)  /* 800 ms */

static float g_ring[RING_SIZE];
static pthread_mutex_t g_ring_lock = PTHREAD_MUTEX_INITIALIZER;
static int g_aec_inputs; /* active AEC inputs; outputs copy only while > 0 */
static int64_t g_t0_ns;

static int64_t ts_pos(const struct timespec *ts) {
    int64_t ns = (int64_t)ts->tv_sec * 1000000000LL + ts->tv_nsec;
    return (ns - g_t0_ns) * RING_RATE / 1000000000LL;
}

static int64_t now_pos(void) {
    struct timespec ts;
    clock_gettime(CLOCK_MONOTONIC, &ts);
    int64_t ns = (int64_t)ts.tv_sec * 1000000000LL + ts.tv_nsec;
    if (g_t0_ns == 0) g_t0_ns = ns;
    return (ns - g_t0_ns) * RING_RATE / 1000000000LL;
}

/* ---------------- stream tables ---------------- */
#define MAX_OUT 24
#define MAX_IN 8

struct out_st {
    struct audio_stream_out *s;
    ssize_t (*write)(struct audio_stream_out *, const void *, size_t);
    uint32_t rate;
    int ch;
    audio_format_t fmt;
    int64_t cursor;
    float *tmp;
    size_t tmp_cap;
    unsigned long resyncs, timed;
    uint64_t written; /* frames accepted by the real write() */
    int64_t anchor;   /* ring position of this write's first frame from the HAL, 0 = unknown */
};

struct in_st {
    struct audio_stream_in *s;
    ssize_t (*read)(struct audio_stream_in *, void *, size_t);
    uint32_t rate;
    int f10;                /* frames in 10 ms */
    effect_handle_t aec, agc;
    unsigned hin[101], hout[101]; /* 10 ms RMS histograms, 1 dB bins, -100..0 dBFS */
    int16_t *qin, *qout;    /* FIFOs (input waiting, processed waiting) */
    int nin, nout, cap;
    int16_t *rev, *chunk_out;
    int64_t rcursor;
    int primed;
    unsigned long chunks, rev_energy_chunks, rresyncs;
};

static struct out_st g_out[MAX_OUT];
static struct in_st g_in[MAX_IN];
static pthread_mutex_t g_tab_lock = PTHREAD_MUTEX_INITIALIZER;

static int (*real_open_output)(struct audio_hw_device *, audio_io_handle_t, audio_devices_t,
                               audio_output_flags_t, struct audio_config *,
                               struct audio_stream_out **, const char *);
static void (*real_close_output)(struct audio_hw_device *, struct audio_stream_out *);
static int (*real_open_input)(struct audio_hw_device *, audio_io_handle_t, audio_devices_t,
                              struct audio_config *, struct audio_stream_in **,
                              audio_input_flags_t, const char *, audio_source_t);
static void (*real_close_input)(struct audio_hw_device *, struct audio_stream_in *);

static audio_effect_library_t *g_fxlib;
static int g_session = 0x7f00;

/* ---------------- helpers ---------------- */
static int fmt_bytes(audio_format_t f) {
    switch (f) {
        case AUDIO_FORMAT_PCM_16_BIT: return 2;
        case AUDIO_FORMAT_PCM_24_BIT_PACKED: return 3;
        case AUDIO_FORMAT_PCM_8_24_BIT:
        case AUDIO_FORMAT_PCM_32_BIT:
        case AUDIO_FORMAT_PCM_FLOAT: return 4;
        default: return 0;
    }
}

static float sample_at(const uint8_t *p, audio_format_t f) {
    switch (f) {
        case AUDIO_FORMAT_PCM_16_BIT: return *(const int16_t *)p / 32768.0f;
        case AUDIO_FORMAT_PCM_24_BIT_PACKED: {
            int32_t v = (p[0] << 8) | (p[1] << 16) | (p[2] << 24);
            return v / 2147483648.0f;
        }
        case AUDIO_FORMAT_PCM_8_24_BIT: return (*(const int32_t *)p << 8) / 2147483648.0f;
        case AUDIO_FORMAT_PCM_32_BIT: return *(const int32_t *)p / 2147483648.0f;
        case AUDIO_FORMAT_PCM_FLOAT: return *(const float *)p;
        default: return 0.f;
    }
}

static int aec_enabled_prop(void) {
    char v[PROP_VALUE_MAX] = "";
    __system_property_get("persist.vendor.audio.pipa_aec", v);
    return strcmp(v, "0") != 0;
}

static int gain_prop(void) {
    char v[PROP_VALUE_MAX] = "";
    if (__system_property_get("persist.vendor.audio.pipa_aec_gain", v) <= 0) return DEFAULT_GAIN_DB;
    int g = atoi(v);
    return g < 0 ? 0 : g > 30 ? 30 : g;
}

static int rms_bin(const int16_t *x, int n) {
    double e = 0;
    for (int i = 0; i < n; i++) e += (double)x[i] * x[i];
    double db = 10 * log10(e / n / (32768.0 * 32768.0) + 1e-12);
    int b = (int)lrint(-db);
    return b < 0 ? 0 : b > 100 ? 100 : b;
}

static int hist_pct(const unsigned *h, double pct) {
    unsigned long tot = 0, acc = 0;
    for (int i = 0; i <= 100; i++) tot += h[i];
    if (!tot) return -100;
    for (int i = 0; i <= 100; i++) { /* bin 0 = loudest */
        acc += h[i];
        if (acc >= tot * (1.0 - pct)) return -i;
    }
    return -100;
}

static struct out_st *find_out(struct audio_stream_out *s) {
    for (int i = 0; i < MAX_OUT; i++)
        if (g_out[i].s == s) return &g_out[i];
    return NULL;
}

static struct in_st *find_in(struct audio_stream_in *s) {
    for (int i = 0; i < MAX_IN; i++)
        if (g_in[i].s == s) return &g_in[i];
    return NULL;
}

/* ---------------- output side ---------------- */
/* Ring position where the first frame of the next write will be played, from the HAL's presentation
 * position (frames played + CLOCK_MONOTONIC time). 0 if the HAL cannot tell. */
static int64_t played_pos(struct out_st *o, uint64_t written_before) {
    uint64_t presented = 0;
    struct timespec ts;
    if (!o->s->get_presentation_position || o->s->get_presentation_position(o->s, &presented, &ts))
        return 0;
    if (written_before < presented) return 0;
    uint64_t pending = written_before - presented;
    if (pending > o->rate) return 0; /* more than 1 s queued: not plausible */
    return ts_pos(&ts) + (int64_t)(pending * RING_RATE / o->rate);
}

static void push_ref(struct out_st *o, const void *buf, size_t bytes) {
    int bps = fmt_bytes(o->fmt);
    if (!bps || o->ch <= 0 || o->rate == 0) return;
    size_t frame = (size_t)bps * o->ch;
    size_t frames = bytes / frame;
    if (!frames) return;
    /* frames at the ring rate (nearest neighbour for non-48 kHz outputs) */
    size_t n = (size_t)((uint64_t)frames * RING_RATE / o->rate);
    if (n == 0) return;
    if (o->tmp_cap < n) {
        float *t = realloc(o->tmp, n * sizeof(float));
        if (!t) return;
        o->tmp = t;
        o->tmp_cap = n;
    }
    const uint8_t *src = buf;
    for (size_t k = 0; k < n; k++) {
        size_t fi = (size_t)((uint64_t)k * o->rate / RING_RATE);
        if (fi >= frames) fi = frames - 1;
        const uint8_t *fp = src + fi * frame;
        float acc = 0.f;
        for (int c = 0; c < o->ch; c++) acc += sample_at(fp + c * bps, o->fmt);
        o->tmp[k] = acc / o->ch;
    }
    pthread_mutex_lock(&g_ring_lock);
    int64_t now = now_pos();
    /* A writer may run ahead of real time (buffers in the HAL/DSP): keep it continuous. Re-anchor
     * only at the start, after a gap (behind real time) or when it is too far ahead. */
    if (o->anchor) {
        /* Played-time anchor from the HAL: follow it, but keep continuity within 5 ms (jitter). */
        o->timed++;
        if (o->cursor == 0 || llabs(o->cursor - o->anchor) > RING_RATE / 200) {
            if (o->cursor) o->resyncs++;
            o->cursor = o->anchor;
        }
    } else if (o->cursor == 0 || o->cursor < now - RESYNC_OUT || o->cursor > now + MAX_AHEAD) {
        if (o->cursor) o->resyncs++;
        o->cursor = now;
    }
    for (size_t k = 0; k < n; k++) g_ring[(o->cursor + k) % RING_SIZE] += o->tmp[k];
    o->cursor += n;
    pthread_mutex_unlock(&g_ring_lock);
}

static ssize_t out_write_hook(struct audio_stream_out *s, const void *buf, size_t bytes) {
    pthread_mutex_lock(&g_tab_lock);
    struct out_st *o = find_out(s);
    ssize_t (*w)(struct audio_stream_out *, const void *, size_t) = o ? o->write : NULL;
    pthread_mutex_unlock(&g_tab_lock);
    if (!w) return -ENODEV;
    ssize_t r = w(s, buf, bytes);
    if (r > 0) {
        int bps = fmt_bytes(o->fmt);
        uint64_t before = o->written;
        if (bps && o->ch > 0) o->written += (uint64_t)r / ((size_t)bps * o->ch);
        if (__atomic_load_n(&g_aec_inputs, __ATOMIC_RELAXED) > 0) {
            o->anchor = played_pos(o, before);
            push_ref(o, buf, (size_t)r);
        }
    }
    return r;
}

static int open_output_hook(struct audio_hw_device *dev, audio_io_handle_t handle,
                            audio_devices_t devices, audio_output_flags_t flags,
                            struct audio_config *config, struct audio_stream_out **stream_out,
                            const char *address) {
    int r = real_open_output(dev, handle, devices, flags, config, stream_out, address);
    if (r != 0 || !*stream_out) return r;
    struct audio_stream_out *s = *stream_out;
    audio_format_t fmt = s->common.get_format(&s->common);
    if (!fmt_bytes(fmt) || (flags & (AUDIO_OUTPUT_FLAG_COMPRESS_OFFLOAD | AUDIO_OUTPUT_FLAG_DIRECT_PCM)))
        return r; /* compressed or offloaded: no PCM to copy */
    pthread_mutex_lock(&g_tab_lock);
    for (int i = 0; i < MAX_OUT; i++) {
        if (g_out[i].s) continue;
        memset(&g_out[i], 0, sizeof(g_out[i]));
        g_out[i].s = s;
        g_out[i].write = s->write;
        g_out[i].rate = s->common.get_sample_rate(&s->common);
        g_out[i].ch = audio_channel_count_from_out_mask(s->common.get_channels(&s->common));
        g_out[i].fmt = fmt;
        s->write = out_write_hook;
        ALOGI("output %d: rate %u ch %d fmt %#x flags %#x", handle, g_out[i].rate, g_out[i].ch,
              fmt, flags);
        break;
    }
    pthread_mutex_unlock(&g_tab_lock);
    return r;
}

static void close_output_hook(struct audio_hw_device *dev, struct audio_stream_out *s) {
    pthread_mutex_lock(&g_tab_lock);
    struct out_st *o = find_out(s);
    if (o) {
        s->write = o->write;
        free(o->tmp);
        memset(o, 0, sizeof(*o));
    }
    pthread_mutex_unlock(&g_tab_lock);
    real_close_output(dev, s);
}

/* ---------------- input side ---------------- */
static int fx_cmd(effect_handle_t h, uint32_t cmd, uint32_t size, void *data) {
    int reply = 0;
    uint32_t rsize = sizeof(reply);
    int r = (*h)->command(h, cmd, size, data, &rsize, &reply);
    return r ? r : reply;
}

static effect_handle_t aec_create(uint32_t rate, int *session_out) {
    if (!g_fxlib) {
        void *lib = dlopen(PREPROC_LIB, RTLD_NOW);
        if (!lib) { ALOGE("dlopen %s: %s", PREPROC_LIB, dlerror()); return NULL; }
        g_fxlib = dlsym(lib, AUDIO_EFFECT_LIBRARY_INFO_SYM_AS_STR);
        if (!g_fxlib) { ALOGE("no %s", AUDIO_EFFECT_LIBRARY_INFO_SYM_AS_STR); return NULL; }
    }
    effect_handle_t h = NULL;
    int session = __atomic_add_fetch(&g_session, 1, __ATOMIC_RELAXED);
    *session_out = session;
    if (g_fxlib->create_effect(&kAecImplUuid, session, session, &h) || !h) {
        ALOGE("create AEC failed");
        return NULL;
    }
    effect_config_t cfg;
    memset(&cfg, 0, sizeof(cfg));
    cfg.inputCfg.samplingRate = cfg.outputCfg.samplingRate = rate;
    cfg.inputCfg.channels = cfg.outputCfg.channels = AUDIO_CHANNEL_IN_MONO;
    cfg.inputCfg.format = cfg.outputCfg.format = AUDIO_FORMAT_PCM_16_BIT;
    cfg.inputCfg.accessMode = EFFECT_BUFFER_ACCESS_READ;
    cfg.outputCfg.accessMode = EFFECT_BUFFER_ACCESS_WRITE;
    cfg.inputCfg.mask = cfg.outputCfg.mask = EFFECT_CONFIG_ALL;
    int r1 = fx_cmd(h, EFFECT_CMD_INIT, 0, NULL);
    int r2 = fx_cmd(h, EFFECT_CMD_SET_CONFIG, sizeof(cfg), &cfg);
    int r3 = fx_cmd(h, EFFECT_CMD_SET_CONFIG_REVERSE, sizeof(cfg), &cfg);
    uint32_t pbuf[(sizeof(effect_param_t) + 8) / 4 + 1];
    effect_param_t *p = (effect_param_t *)pbuf;
    p->psize = 4;
    p->vsize = 4;
    ((int32_t *)p->data)[0] = AEC_PARAM_MOBILE_MODE_ID;
    ((int32_t *)p->data)[1] = 0; /* full AEC3, not the mobile AECM */
    int r4 = fx_cmd(h, EFFECT_CMD_SET_PARAM, sizeof(effect_param_t) + 8, p);
    int r5 = fx_cmd(h, EFFECT_CMD_ENABLE, 0, NULL);
    ALOGI("AEC rate %u: init %d config %d reverse %d mobile_off %d enable %d", rate, r1, r2, r3, r4,
          r5);
    if (r1 || r2 || r3 || r5) {
        g_fxlib->release_effect(h);
        return NULL;
    }
    return h;
}

static effect_handle_t agc_create(uint32_t rate, int session_id, int gain_db) {
    effect_handle_t h = NULL;
    if (gain_db <= 0 || !g_fxlib) return NULL;
    if (g_fxlib->create_effect(&kAgc2ImplUuid, session_id, session_id, &h) || !h) {
        ALOGE("create AGC2 failed");
        return NULL;
    }
    effect_config_t cfg;
    memset(&cfg, 0, sizeof(cfg));
    cfg.inputCfg.samplingRate = cfg.outputCfg.samplingRate = rate;
    cfg.inputCfg.channels = cfg.outputCfg.channels = AUDIO_CHANNEL_IN_MONO;
    cfg.inputCfg.format = cfg.outputCfg.format = AUDIO_FORMAT_PCM_16_BIT;
    cfg.inputCfg.accessMode = EFFECT_BUFFER_ACCESS_READ;
    cfg.outputCfg.accessMode = EFFECT_BUFFER_ACCESS_WRITE;
    cfg.inputCfg.mask = cfg.outputCfg.mask = EFFECT_CONFIG_ALL;
    int r1 = fx_cmd(h, EFFECT_CMD_INIT, 0, NULL);
    int r2 = fx_cmd(h, EFFECT_CMD_SET_CONFIG, sizeof(cfg), &cfg);
    uint32_t pbuf[(sizeof(effect_param_t) + 8) / 4 + 1];
    effect_param_t *p = (effect_param_t *)pbuf;
    p->psize = 4;
    p->vsize = 4;
    ((int32_t *)p->data)[0] = AGC2_PARAM_FIXED_GAIN_ID;
    ((int32_t *)p->data)[1] = gain_db;
    int r3 = fx_cmd(h, EFFECT_CMD_SET_PARAM, sizeof(effect_param_t) + 8, p);
    int r4 = fx_cmd(h, EFFECT_CMD_ENABLE, 0, NULL);
    ALOGI("AGC2 %d dB: init %d config %d gain %d enable %d", gain_db, r1, r2, r3, r4);
    if (r1 || r2 || r4) {
        g_fxlib->release_effect(h);
        return NULL;
    }
    return h;
}

/* Learned AEC state is kept after an input closes and is reused by the next input with the same
 * rate: the speaker-to-mic path of a tablet changes little between calls, so later calls start
 * converged (the first call after a HAL start needs some seconds). */
struct fx_cache {
    uint32_t rate;
    int session, gain, busy;
    effect_handle_t aec, agc;
};
#define MAX_CACHE 4
static struct fx_cache g_cache[MAX_CACHE];
static pthread_mutex_t g_cache_lock = PTHREAD_MUTEX_INITIALIZER;

static void agc_set_gain(effect_handle_t h, int gain_db) {
    uint32_t pbuf[(sizeof(effect_param_t) + 8) / 4 + 1];
    effect_param_t *p = (effect_param_t *)pbuf;
    p->psize = 4;
    p->vsize = 4;
    ((int32_t *)p->data)[0] = AGC2_PARAM_FIXED_GAIN_ID;
    ((int32_t *)p->data)[1] = gain_db;
    fx_cmd(h, EFFECT_CMD_SET_PARAM, sizeof(effect_param_t) + 8, p);
}

/* Returns 1 if the effects came from the cache. */
static int fx_get(uint32_t rate, int gain, effect_handle_t *aec, effect_handle_t *agc) {
    int reused = 0;
    pthread_mutex_lock(&g_cache_lock);
    struct fx_cache *c = NULL;
    for (int i = 0; i < MAX_CACHE; i++)
        if (g_cache[i].aec && !g_cache[i].busy && g_cache[i].rate == rate) { c = &g_cache[i]; break; }
    if (c) {
        if (gain != c->gain) {
            if (c->agc && gain > 0) agc_set_gain(c->agc, gain);
            else if (c->agc) { g_fxlib->release_effect(c->agc); c->agc = NULL; }
            else c->agc = agc_create(rate, c->session, gain);
            c->gain = gain;
        }
        c->busy = 1;
        *aec = c->aec;
        *agc = c->agc;
        reused = 1;
    } else {
        int session = 0;
        *aec = aec_create(rate, &session);
        *agc = *aec ? agc_create(rate, session, gain) : NULL;
        for (int i = 0; *aec && i < MAX_CACHE; i++)
            if (!g_cache[i].aec) {
                g_cache[i] = (struct fx_cache){rate, session, gain, 1, *aec, *agc};
                break;
            }
    }
    pthread_mutex_unlock(&g_cache_lock);
    return reused;
}

static int keep_prop(void) {
    char v[PROP_VALUE_MAX] = "";
    __system_property_get("persist.vendor.audio.pipa_aec_keep", v);
    return strcmp(v, "1") == 0;
}

static void fx_put(effect_handle_t aec, effect_handle_t agc) {
    int keep = keep_prop(); /* 2026-11-06 test: reuse gave more start echo than a fresh AEC */
    pthread_mutex_lock(&g_cache_lock);
    for (int i = 0; i < MAX_CACHE; i++)
        if (g_cache[i].aec == aec) {
            if (keep) {
                g_cache[i].busy = 0; /* keep the learned state */
                pthread_mutex_unlock(&g_cache_lock);
                return;
            }
            memset(&g_cache[i], 0, sizeof(g_cache[i]));
            break;
        }
    pthread_mutex_unlock(&g_cache_lock);
    g_fxlib->release_effect(aec);
    if (agc) g_fxlib->release_effect(agc);
}

/* Fill in->rev with 10 ms of reference at the input rate. */
static void pull_ref(struct in_st *in) {
    int step = RING_RATE / in->rate; /* 1, 3 or 6 */
    int n48 = in->f10 * step;
    pthread_mutex_lock(&g_ring_lock);
    int64_t now = now_pos();
    if (in->rcursor == 0 || llabs(in->rcursor + n48 - now) > RESYNC_IN) {
        if (in->rcursor) in->rresyncs++;
        in->rcursor = now - n48;
    }
    int nz = 0;
    for (int k = 0; k < in->f10; k++) {
        float acc = 0.f;
        for (int j = 0; j < step; j++) {
            int64_t pos = in->rcursor + (int64_t)k * step + j;
            float *slot = &g_ring[((pos % RING_SIZE) + RING_SIZE) % RING_SIZE];
            acc += *slot;
            *slot = 0.f;
        }
        acc /= step;
        if (acc > 1.f) acc = 1.f;
        if (acc < -1.f) acc = -1.f;
        in->rev[k] = (int16_t)lrintf(acc * 32767.f);
        if (in->rev[k]) nz = 1;
    }
    in->rcursor += n48;
    pthread_mutex_unlock(&g_ring_lock);
    if (nz) in->rev_energy_chunks++;
}

static void process_chunk(struct in_st *in, int16_t *chunk) {
    pull_ref(in);
    audio_buffer_t rb = {.frameCount = (size_t)in->f10, .s16 = in->rev};
    audio_buffer_t rbo = {.frameCount = (size_t)in->f10, .s16 = in->rev};
    if ((*in->aec)->process_reverse) (*in->aec)->process_reverse(in->aec, &rb, &rbo);
    in->hin[rms_bin(chunk, in->f10)]++;
    audio_buffer_t ib = {.frameCount = (size_t)in->f10, .s16 = chunk};
    audio_buffer_t ob = {.frameCount = (size_t)in->f10, .s16 = in->chunk_out};
    /* One APM run per 10 ms: it runs on the call that completes the set of enabled effects. */
    int r = (*in->aec)->process(in->aec, &ib, &ob);
    if (in->agc) r = (*in->agc)->process(in->agc, &ib, &ob);
    if (r == 0) memcpy(chunk, in->chunk_out, (size_t)in->f10 * 2);
    in->hout[rms_bin(chunk, in->f10)]++;
    if ((++in->chunks % 3000) == 0) {
        ALOGI("in %p: %lu chunks, %lu with reference; level p95/p50 in %d/%d out %d/%d dBFS", in->s,
              in->chunks, in->rev_energy_chunks, hist_pct(in->hin, 0.95), hist_pct(in->hin, 0.5),
              hist_pct(in->hout, 0.95), hist_pct(in->hout, 0.5));
        memset(in->hin, 0, sizeof(in->hin));
        memset(in->hout, 0, sizeof(in->hout));
    }
}

static ssize_t in_read_hook(struct audio_stream_in *s, void *buf, size_t bytes) {
    pthread_mutex_lock(&g_tab_lock);
    struct in_st *in = find_in(s);
    pthread_mutex_unlock(&g_tab_lock);
    if (!in) return -ENODEV;
    ssize_t r = in->read(s, buf, bytes);
    if (r <= 0 || !in->aec) return r;
    int n = (int)(r / 2);
    if (n > in->cap) return r; /* larger than expected: pass through */
    int16_t *pcm = buf;
    /* Reads that are whole 10 ms blocks go straight through; others use the FIFOs. */
    if (!in->primed && n % in->f10 == 0 && in->nin == 0 && in->nout == 0) {
        for (int off = 0; off < n; off += in->f10) process_chunk(in, pcm + off);
        return r;
    }
    if (!in->primed) {
        memset(in->qout, 0, (size_t)in->f10 * 2); /* one block of latency */
        in->nout = in->f10;
        in->primed = 1;
    }
    memcpy(in->qin + in->nin, pcm, (size_t)n * 2);
    in->nin += n;
    while (in->nin >= in->f10) {
        process_chunk(in, in->qin);
        memcpy(in->qout + in->nout, in->qin, (size_t)in->f10 * 2);
        in->nout += in->f10;
        in->nin -= in->f10;
        memmove(in->qin, in->qin + in->f10, (size_t)in->nin * 2);
    }
    int take = n < in->nout ? n : in->nout;
    memcpy(pcm, in->qout, (size_t)take * 2);
    if (take < n) memset(pcm + take, 0, (size_t)(n - take) * 2);
    in->nout -= take;
    memmove(in->qout, in->qout + take, (size_t)in->nout * 2);
    return r;
}

static int open_input_hook(struct audio_hw_device *dev, audio_io_handle_t handle,
                           audio_devices_t devices, struct audio_config *config,
                           struct audio_stream_in **stream_in, audio_input_flags_t flags,
                           const char *address, audio_source_t source) {
    int r = real_open_input(dev, handle, devices, config, stream_in, flags, address, source);
    if (r != 0 || !*stream_in || source != AUDIO_SOURCE_VOICE_COMMUNICATION) return r;
    struct audio_stream_in *s = *stream_in;
    uint32_t rate = s->common.get_sample_rate(&s->common);
    int ch = audio_channel_count_from_in_mask(s->common.get_channels(&s->common));
    audio_format_t fmt = s->common.get_format(&s->common);
    if (!aec_enabled_prop()) { ALOGI("input %d: AEC off by property", handle); return r; }
    if (fmt != AUDIO_FORMAT_PCM_16_BIT || ch != 1 ||
        (rate != 8000 && rate != 16000 && rate != 48000)) {
        ALOGW("input %d: unsupported rate %u ch %d fmt %#x, no AEC", handle, rate, ch, fmt);
        return r;
    }
    effect_handle_t aec = NULL, agc = NULL;
    int reused = fx_get(rate, gain_prop(), &aec, &agc);
    if (!aec) return r;
    pthread_mutex_lock(&g_tab_lock);
    struct in_st *in = NULL;
    for (int i = 0; i < MAX_IN; i++)
        if (!g_in[i].s) { in = &g_in[i]; break; }
    if (in) {
        memset(in, 0, sizeof(*in));
        in->s = s;
        in->read = s->read;
        in->rate = rate;
        in->f10 = (int)(rate / 100);
        in->aec = aec;
        in->agc = agc;
        in->cap = (int)rate; /* 1 s */
        in->qin = calloc((size_t)in->cap + in->f10, 2);
        in->qout = calloc((size_t)in->cap + 2 * in->f10, 2);
        in->rev = calloc((size_t)in->f10, 2);
        in->chunk_out = calloc((size_t)in->f10, 2);
        if (!in->qin || !in->qout || !in->rev || !in->chunk_out) {
            free(in->qin); free(in->qout); free(in->rev); free(in->chunk_out);
            memset(in, 0, sizeof(*in));
            in = NULL;
        } else {
            s->read = in_read_hook;
        }
    }
    pthread_mutex_unlock(&g_tab_lock);
    if (!in) {
        fx_put(aec, agc);
        return r;
    }
    pthread_mutex_lock(&g_ring_lock);
    if (__atomic_add_fetch(&g_aec_inputs, 1, __ATOMIC_RELAXED) == 1)
        memset(g_ring, 0, sizeof(g_ring));
    pthread_mutex_unlock(&g_ring_lock);
    ALOGI("input %d: software AEC on (rate %u, devices %#x, %s state)", handle, rate, devices,
          reused ? "learned" : "new");
    return r;
}

static void close_input_hook(struct audio_hw_device *dev, struct audio_stream_in *s) {
    effect_handle_t aec = NULL, agc = NULL;
    pthread_mutex_lock(&g_tab_lock);
    struct in_st *in = find_in(s);
    if (in) {
        s->read = in->read;
        aec = in->aec;
        agc = in->agc;
        unsigned long ors = 0, timed = 0;
        for (int i = 0; i < MAX_OUT; i++) { ors += g_out[i].resyncs; timed += g_out[i].timed; }
        ALOGI("input closed: %lu chunks, %lu with reference, reader resyncs %lu, writer resyncs %lu, "
              "timed writes %lu", in->chunks, in->rev_energy_chunks, in->rresyncs, ors, timed);
        free(in->qin); free(in->qout); free(in->rev); free(in->chunk_out);
        memset(in, 0, sizeof(*in));
    }
    pthread_mutex_unlock(&g_tab_lock);
    if (aec) {
        __atomic_sub_fetch(&g_aec_inputs, 1, __ATOMIC_RELAXED);
        fx_put(aec, agc);
    }
    real_close_input(dev, s);
}

/* ---------------- module ---------------- */
static int wrap_open(const hw_module_t *module, const char *name, hw_device_t **device) {
    (void)module;
    void *h = dlopen(PIPA_REAL_HAL, RTLD_NOW);
    if (!h) { ALOGE("dlopen %s: %s", PIPA_REAL_HAL, dlerror()); return -ENOENT; }
    struct hw_module_t *rm = dlsym(h, HAL_MODULE_INFO_SYM_AS_STR);
    if (!rm || !rm->methods || !rm->methods->open) { ALOGE("real HAL has no module"); return -ENOENT; }
    rm->dso = h;
    int r = rm->methods->open(rm, name, device);
    if (r || !*device) return r;
    struct audio_hw_device *d = (struct audio_hw_device *)*device;
    real_open_output = d->open_output_stream;
    real_close_output = d->close_output_stream;
    real_open_input = d->open_input_stream;
    real_close_input = d->close_input_stream;
    d->open_output_stream = open_output_hook;
    d->close_output_stream = close_output_hook;
    d->open_input_stream = open_input_hook;
    d->close_input_stream = close_input_hook;
    ALOGI("wrapper on %s (device version %#x)", PIPA_REAL_HAL, d->common.version);
    return 0;
}

static struct hw_module_methods_t wrap_methods = {.open = wrap_open};

__attribute__((visibility("default"))) struct audio_module HAL_MODULE_INFO_SYM = {
        .common =
                {
                        .tag = HARDWARE_MODULE_TAG,
                        .module_api_version = AUDIO_MODULE_API_VERSION_0_1,
                        .hal_api_version = HARDWARE_HAL_API_VERSION,
                        .id = AUDIO_HARDWARE_MODULE_ID,
                        .name = "pipa AEC wrapper",
                        .author = "pipa COS17 port",
                        .methods = &wrap_methods,
                },
};
