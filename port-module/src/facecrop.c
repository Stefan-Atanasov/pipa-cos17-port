// B7: square crop for the face enrollment preview, LD_PRELOADed into facehal-rs.
//
// ColorOS Settings shows the preview in a square SurfaceView (740x740), but facehal-rs fills
// the surface with the full 3:4 camera frame (480x640 or 640x480 depending on rotation), so
// SurfaceFlinger stretches it to the square. This wraps ANativeWindow_setBuffersGeometry and
// adds a centred square crop (NATIVE_WINDOW_SET_CROP), which the Surface applies to every
// queued buffer. facehal-rs is closed source, so the crop cannot go into the HAL itself.
//
//
// BUGS 147: preview rotation from the window. facehal-rs turns each preview frame by the camera
// orientation plus persist.vendor.facehal.rotation, which it reads with __system_property_get (also
// before the first frame, for the buffer size). The pipa_port service set that property only after
// it saw the camera worker (up to 3 s late; unset after a clean flash), so the first enrollment
// preview was rotated. This file now notes the preview window (ANativeWindow_readFromParcel),
// connects it at once (only a connect brings the transform hint = the display orientation that
// SurfaceFlinger reports for the surface) and answers that one property read from the hint: right
// from the first frame and after a flip, with no polling. No window or no hint: the real property.
//
// Build: helper-free, see build_facecrop.sh (NDK clang, aarch64).
#include <android/log.h>
#include <android/native_window.h>
#include <dlfcn.h>
#include <sched.h>
#include <stdatomic.h>
#include <stdint.h>
#include <stdio.h>
#include <string.h>

#define TAG "pipa_facecrop"

// ABI-stable layout of the platform ANativeWindow (system/window.h), up to perform().
struct android_native_base {
    int magic;
    int version;
    void* reserved[4];
    void (*incRef)(struct android_native_base*);
    void (*decRef)(struct android_native_base*);
};
struct native_window {
    struct android_native_base common;
    const uint32_t flags;
    const int minSwapInterval;
    const int maxSwapInterval;
    const float xdpi;
    const float ydpi;
    intptr_t oem[4];
    int (*setSwapInterval)(struct native_window*, int);
    int (*dequeueBuffer_DEPRECATED)(struct native_window*, void**);
    int (*lockBuffer_DEPRECATED)(struct native_window*, void*);
    int (*queueBuffer_DEPRECATED)(struct native_window*, void*);
    int (*query)(const struct native_window*, int, int*);
    int (*perform)(struct native_window*, int, ...);
};
struct native_rect {
    int32_t left, top, right, bottom;
};

#define NATIVE_WINDOW_MAGIC 0x5f776e64  // '_wnd'
#define NATIVE_WINDOW_SET_CROP 3
#define NATIVE_WINDOW_TRANSFORM_HINT 8
#define NATIVE_WINDOW_SET_USAGE 0
#define NATIVE_WINDOW_API_CONNECT 13
#define NATIVE_WINDOW_API_CPU 2
#define SW_READ_WRITE_OFTEN 0x33  // GRALLOC_USAGE_SW_READ_OFTEN | SW_WRITE_OFTEN, as Surface::lock sets it
#define ROT_PROP "persist.vendor.facehal.rotation"

// The current preview window (no own reference: the HAL owns it; the release hook below clears it
// and waits for a reader). g_connected: this file connected it, so its transform hint is valid.
static _Atomic(struct native_window*) g_win;
static atomic_int g_connected;
static atomic_int g_readers;
static atomic_int g_last = -1;

// Transform hint (rotation part) -> the extra turn facehal-rs needs: 90 x display rotation (B7).
static int hint_degrees(int hint) {
    switch (hint & 7) {
        case 0: return 0;
        case 4: return 90;   // NATIVE_WINDOW_TRANSFORM_ROT_90
        case 3: return 180;  // ROT_180
        case 7: return 270;  // ROT_270
        default: return -1;  // a flip: not a display rotation
    }
}

// The rotation of the current window, or -1. A hint of 0 counts only on a window this file
// connected (before the HAL's first ANativeWindow_lock, a Surface reports 0 for every rotation).
static int window_degrees(void) {
    atomic_fetch_add(&g_readers, 1);
    struct native_window* w = atomic_load(&g_win);
    int hint = 0, deg = -1;
    if (w && w->common.magic == NATIVE_WINDOW_MAGIC && w->query && w->query(w, NATIVE_WINDOW_TRANSFORM_HINT, &hint) == 0) {
        deg = hint_degrees(hint);
        if (deg == 0 && !atomic_load(&g_connected)) deg = -1;
    }
    atomic_fetch_sub(&g_readers, 1);
    if (deg >= 0 && atomic_exchange(&g_last, deg) != deg) {
        // also into the property: the HAL's reads after the window is gone, and the next session
        typedef int (*propset_fn)(const char*, const char*);
        static propset_fn set;
        if (!set) set = (propset_fn)dlsym(RTLD_DEFAULT, "__system_property_set");
        char v[8];
        snprintf(v, sizeof v, "%d", deg);
        int r = set ? set(ROT_PROP, v) : -1;
        __android_log_print(ANDROID_LOG_INFO, TAG, "rotation from window: hint %d -> %d (property set %d)", hint, deg, r);
    }
    return deg;
}

// BUGS 147: facehal-rs reads the rotation and sets the buffer size from it before its first
// ANativeWindow_lock, which connects the Surface; only a connect brings the transform hint. So the
// window is connected here as the CPU producer, with the usage that Surface::lock would set (lock
// then skips its own connect). If the connect fails, the HAL connects later, as before.
static void track_window(ANativeWindow* win, int connect) {
    struct native_window* w = (struct native_window*)win;
    if (!w || w->common.magic != NATIVE_WINDOW_MAGIC || atomic_load(&g_win) == w) return;
    atomic_store(&g_connected, 0);
    atomic_store(&g_win, w);
    if (connect && w->perform) {
        int r = w->perform(w, NATIVE_WINDOW_API_CONNECT, NATIVE_WINDOW_API_CPU);
        if (r == 0) {
            w->perform(w, NATIVE_WINDOW_SET_USAGE, SW_READ_WRITE_OFTEN);
            atomic_store(&g_connected, 1);
        }
        __android_log_print(ANDROID_LOG_INFO, TAG, "preview window connect = %d", r);
        window_degrees();
    }
}

typedef int32_t (*parcel_fn)(const void*, ANativeWindow**);

int32_t ANativeWindow_readFromParcel(const void* parcel, ANativeWindow** out) {
    static parcel_fn real;
    if (!real) real = (parcel_fn)dlsym(RTLD_NEXT, "ANativeWindow_readFromParcel");
    if (!real) return -1;
    int32_t ret = real(parcel, out);
    if (ret == 0 && out) track_window(*out, 1);
    return ret;
}

typedef void (*release_fn)(ANativeWindow*);

void ANativeWindow_release(ANativeWindow* win) {
    static release_fn real;
    if (!real) real = (release_fn)dlsym(RTLD_NEXT, "ANativeWindow_release");
    struct native_window* expect = (struct native_window*)win;
    if (win && atomic_compare_exchange_strong(&g_win, &expect, NULL)) {
        while (atomic_load(&g_readers) > 0) sched_yield();
    }
    if (real) real(win);
}

typedef int (*propget_fn)(const char*, char*);

int __system_property_get(const char* name, char* value) {
    static propget_fn real;
    if (!real) real = (propget_fn)dlsym(RTLD_NEXT, "__system_property_get");
    if (name && value && strcmp(name, ROT_PROP) == 0) {
        int deg = window_degrees();
        if (deg >= 0) return snprintf(value, 92, "%d", deg);  // PROP_VALUE_MAX = 92
    }
    return real ? real(name, value) : 0;
}

typedef int32_t (*geometry_fn)(ANativeWindow*, int32_t, int32_t, int32_t);

int32_t ANativeWindow_setBuffersGeometry(ANativeWindow* window, int32_t w, int32_t h, int32_t format) {
    static geometry_fn real;
    if (!real) real = (geometry_fn)dlsym(RTLD_NEXT, "ANativeWindow_setBuffersGeometry");
    if (!real) return -1;
    int32_t ret = real(window, w, h, format);
    struct native_window* nw = (struct native_window*)window;
    if (ret == 0) track_window(window, 0);
    if (ret != 0 || w <= 0 || h <= 0 || w == h || nw->common.magic != NATIVE_WINDOW_MAGIC) return ret;

    int32_t s = w < h ? w : h;
    struct native_rect crop = {(w - s) / 2, (h - s) / 2, (w - s) / 2 + s, (h - s) / 2 + s};
    int r = nw->perform(nw, NATIVE_WINDOW_SET_CROP, &crop);
    __android_log_print(ANDROID_LOG_INFO, TAG, "preview %dx%d -> crop [%d,%d,%d,%d] = %d", w, h,
                        crop.left, crop.top, crop.right, crop.bottom, r);
    return ret;
}
