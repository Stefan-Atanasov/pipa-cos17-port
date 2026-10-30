// B7: square crop for the face enrollment preview, LD_PRELOADed into facehal-rs.
//
// ColorOS Settings shows the preview in a square SurfaceView (740x740), but facehal-rs fills
// the surface with the full 3:4 camera frame (480x640 or 640x480 depending on rotation), so
// SurfaceFlinger stretches it to the square. This wraps ANativeWindow_setBuffersGeometry and
// adds a centred square crop (NATIVE_WINDOW_SET_CROP), which the Surface applies to every
// queued buffer. facehal-rs is closed source, so the crop cannot go into the HAL itself.
//
// Build: helper-free, see build_facecrop.sh (NDK clang, aarch64).
#include <android/log.h>
#include <android/native_window.h>
#include <dlfcn.h>
#include <stdint.h>

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

typedef int32_t (*geometry_fn)(ANativeWindow*, int32_t, int32_t, int32_t);

int32_t ANativeWindow_setBuffersGeometry(ANativeWindow* window, int32_t w, int32_t h, int32_t format) {
    static geometry_fn real;
    if (!real) real = (geometry_fn)dlsym(RTLD_NEXT, "ANativeWindow_setBuffersGeometry");
    if (!real) return -1;
    int32_t ret = real(window, w, h, format);
    struct native_window* nw = (struct native_window*)window;
    if (ret != 0 || w <= 0 || h <= 0 || w == h || nw->common.magic != NATIVE_WINDOW_MAGIC) return ret;

    int32_t s = w < h ? w : h;
    struct native_rect crop = {(w - s) / 2, (h - s) / 2, (w - s) / 2 + s, (h - s) / 2 + s};
    int r = nw->perform(nw, NATIVE_WINDOW_SET_CROP, &crop);
    __android_log_print(ANDROID_LOG_INFO, TAG, "preview %dx%d -> crop [%d,%d,%d,%d] = %d", w, h,
                        crop.left, crop.top, crop.right, crop.bottom, r);
    return ret;
}
