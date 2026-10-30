// Item 8: keep the face HAL alive when the eye ROI falls outside the camera frame.
//
// libjni_stfaceunlock_api.so (OpenCV is linked into it statically, but its symbols are exported
// and every call goes through the PLT, so an LD_PRELOADed library wins the lookup) computes the
// eye boxes in crop_eyes() from face landmarks without clamping and builds
// cv::Mat::operator()(Rect) -> cv::Mat::Mat(const Mat&, const Rect&). Near the frame edge the
// ROI assert in that constructor fires, cv::error throws, and the HAL dies in the unwinder
// (SIGSEGV on facehal-auth).
//
// Two interposers:
//  1. cv::Mat::Mat(const Mat&, const Rect&)   - only while inside crop_eyes(): an invalid rect is
//     clamped to the source (min 1x1; 0x0 if the source is empty) so no exception is thrown, and
//     the event is remembered in a thread-local.
//  2. crop_eyes(...)                          - calls the real one; if a rect had to be clamped,
//     it clears both "crop this eye" flags (*left = *right = 0). crop_eyes itself already does
//     that when the eye box is too small, and FaceEngineNative::detectEyeStatus then skips
//     FaceEyeModel::detect for that eye, so this is an existing, supported "eyes unknown" result.
//
// Offsets used (read from the disassembly of the shipped library, VERSION md5 8105ae5d...):
//   cv::Mat: rows int @0x8, cols int @0xc;  cv::Rect_<int>: x@0 y@4 width@8 height@0xc.
//
// Build: see build_eyeguard.sh. Use together with libpipa_facecrop.so:
//   LD_PRELOAD=$FACE/lib64/libpipa_facecrop.so:$FACE/lib64/libpipa_eyeguard.so
#define _GNU_SOURCE
#include <dlfcn.h>
#include <link.h>
#include <stdint.h>
#include <stdio.h>
#include <string.h>

#ifdef __ANDROID__
#include <android/log.h>
#define TAG "pipa_eyeguard"
#define LOGW(...) __android_log_print(ANDROID_LOG_WARN, TAG, __VA_ARGS__)
#else
#define LOGW(...) (fprintf(stderr, "pipa_eyeguard: " __VA_ARGS__), fputc('\n', stderr))
#endif

#define SYM_MAT_RECT_C1 "_ZN2cv3MatC1ERKS0_RKNS_5Rect_IiEE"
#define SYM_MAT_RECT_C2 "_ZN2cv3MatC2ERKS0_RKNS_5Rect_IiEE"
#define SYM_CROP_EYES \
    "_Z9crop_eyesRN2cv3MatES1_S1_RNSt6__ndk16vectorINS3_IfNS2_9allocatorIfEEEENS4_IS6_EEEERiSA_"
#define ENGINE_LIB "libjni_stfaceunlock_api"

struct rect { int x, y, w, h; };

typedef void (*mat_rect_fn)(void*, const void*, const struct rect*);
typedef int (*crop_eyes_fn)(void*, void*, void*, void*, int*, int*);

static __thread int g_in_crop;   // inside crop_eyes() on this thread
static __thread int g_clamped;   // a rect was clamped during this crop_eyes() call
static unsigned g_events;

// ---- find the real functions in the engine library ----------------------------------------
struct find_ctx { char path[512]; };

static int phdr_cb(struct dl_phdr_info* info, size_t size, void* data) {
    (void)size;
    struct find_ctx* c = (struct find_ctx*)data;
    if (info->dlpi_name && strstr(info->dlpi_name, ENGINE_LIB)) {
        strncpy(c->path, info->dlpi_name, sizeof(c->path) - 1);
        return 1;
    }
    return 0;
}

static void* real_sym(const char* name) {
    void* p = dlsym(RTLD_NEXT, name);  // works if the engine was loaded RTLD_GLOBAL / is a NEEDED
    if (p) return p;
    struct find_ctx c;
    memset(&c, 0, sizeof(c));
    if (dl_iterate_phdr(phdr_cb, &c) && c.path[0]) {
        void* h = dlopen(c.path, RTLD_NOW | RTLD_NOLOAD);  // loaded RTLD_LOCAL by the HAL
        if (h) p = dlsym(h, name);
    }
    if (!p) LOGW("cannot resolve %s", name);
    return p;
}

// ---- clamp ----------------------------------------------------------------------------------
static int clampi(int64_t v, int64_t lo, int64_t hi) { return (int)(v < lo ? lo : v > hi ? hi : v); }

static void mat_rect(void* self, const void* m, const struct rect* r) {
    static mat_rect_fn real;
    if (!real) real = (mat_rect_fn)real_sym(SYM_MAT_RECT_C1);
    struct rect fixed;
    if (g_in_crop && m && r) {
        const int rows = ((const int*)m)[2], cols = ((const int*)m)[3];
        int64_t x = r->x, y = r->y, w = r->w, h = r->h;
        if (x < 0 || y < 0 || w < 0 || h < 0 || x + w > cols || y + h > rows) {
            if (cols <= 0 || rows <= 0) {
                fixed = (struct rect){0, 0, 0, 0};  // empty source: only an empty ROI is valid
            } else {
                int cx = clampi(x, 0, cols - 1), cy = clampi(y, 0, rows - 1);
                int cw = clampi(w, 1, cols - cx), ch = clampi(h, 1, rows - cy);
                fixed = (struct rect){cx, cy, cw, ch};
            }
            if (g_events++ < 20 || (g_events & 0x3f) == 0)
                LOGW("eye ROI [%d,%d %dx%d] outside %dx%d frame -> [%d,%d %dx%d], eyes skipped", r->x,
                     r->y, r->w, r->h, cols, rows, fixed.x, fixed.y, fixed.w, fixed.h);
            g_clamped = 1;
            r = &fixed;
        }
    }
    real(self, m, r);
}

// Constructor symbols used by the engine (C1 and C2 are the same address in the original).
__attribute__((visibility("default")))
void pipa_mat_rect_c1(void* self, const void* m, const struct rect* r) __asm__(SYM_MAT_RECT_C1);
void pipa_mat_rect_c1(void* self, const void* m, const struct rect* r) { mat_rect(self, m, r); }

__attribute__((visibility("default")))
void pipa_mat_rect_c2(void* self, const void* m, const struct rect* r) __asm__(SYM_MAT_RECT_C2);
void pipa_mat_rect_c2(void* self, const void* m, const struct rect* r) { mat_rect(self, m, r); }

__attribute__((visibility("default")))
int pipa_crop_eyes(void* frame, void* left, void* right, void* landmarks, int* left_flag,
                   int* right_flag) __asm__(SYM_CROP_EYES);
int pipa_crop_eyes(void* frame, void* left, void* right, void* landmarks, int* left_flag,
                   int* right_flag) {
    static crop_eyes_fn real;
    if (!real) real = (crop_eyes_fn)real_sym(SYM_CROP_EYES);
    if (!real) return 0;
    g_in_crop = 1;
    g_clamped = 0;
    int ret = real(frame, left, right, landmarks, left_flag, right_flag);
    g_in_crop = 0;
    if (g_clamped) {
        if (left_flag) *left_flag = 0;
        if (right_flag) *right_flag = 0;
        g_clamped = 0;
    }
    return ret;
}
