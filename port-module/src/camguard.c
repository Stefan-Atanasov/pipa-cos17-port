// Face HAL camera worker: no abort when the worker hands an ANativeWindow to the vendor camera NDK.
//
// facehal-rs (camera worker v2) tries a camera first with window=native-handle
// (AImageReader_getWindowNativeHandle). If that candidate gives no usable frame (a dark room or a
// covered camera: only blank warm-up frames), the HAL starts a new worker with window=standard
// ("using standard ANativeWindow ABI"): it passes AImageReader_getWindow()'s ANativeWindow* to
// ACaptureSessionOutput_create / ACameraOutputTarget_create. The vendor libcamera2ndk_vendor.so
// takes ACameraWindowType as a native_handle_t*, so ACameraDevice_createCaptureSession clones
// garbage: "Failed to clone native_handle in hidl_handle: Bad file descriptor" -> SIGABRT,
// tombstone, and OPPO's crash log collector (debuglog `ps -A -T`) runs. Seen 2026-11-03 and
// 2026-11-05 (tombstone_26..28).
//
// This library interposes both create calls (LD_PRELOAD, the HAL imports them through the PLT)
// and returns ACAMERA_ERROR_INVALID_PARAMETER for a pointer that is not a native_handle_t. The
// worker then logs "startup failed window=standard" and the HAL reports "camera open failed",
// the same result as before, without the crash.
//
// Build: build_camguard.sh. Load order: LD_PRELOAD=...facecrop.so:...eyeguard.so:...camguard.so
#define _GNU_SOURCE
#include <dlfcn.h>
#include <fcntl.h>
#include <stdint.h>
#include <stdio.h>

#ifdef __ANDROID__
#include <android/log.h>
#define TAG "pipa_camguard"
#define LOGW(...) __android_log_print(ANDROID_LOG_WARN, TAG, __VA_ARGS__)
#else
#define LOGW(...) (fprintf(stderr, "pipa_camguard: " __VA_ARGS__), fputc('\n', stderr))
#endif

#define ACAMERA_ERROR_INVALID_PARAMETER (-10001)
#define MAX_FDS 1024
#define MAX_INTS 1024

struct nh {          // native_handle_t
    int version;     // sizeof(native_handle_t) = 12
    int numFds;
    int numInts;
    int data[];
};

typedef int (*create_fn)(void* window, void** out);

static int valid_handle(const void* p) {
    const struct nh* h = (const struct nh*)p;
    if (!h || ((uintptr_t)h & 3)) return 0;
    if (h->version != (int)sizeof(struct nh)) return 0;   // ANativeWindow starts with magic '_wnd'
    if (h->numFds < 0 || h->numFds > MAX_FDS || h->numInts < 0 || h->numInts > MAX_INTS) return 0;
    for (int i = 0; i < h->numFds; i++)
        if (fcntl(h->data[i], F_GETFD) < 0) return 0;
    return 1;
}

static int guarded(const char* name, create_fn* real, void* window, void** out) {
    if (!*real) *real = (create_fn)dlsym(RTLD_NEXT, name);
    if (!valid_handle(window)) {
        const int* w = (const int*)window;
        LOGW("%s: window %p is not a native handle (first word 0x%08x): refused",
             name, window, w && !((uintptr_t)w & 3) ? (unsigned)w[0] : 0u);
        if (out) *out = NULL;
        return ACAMERA_ERROR_INVALID_PARAMETER;
    }
    if (!*real) return ACAMERA_ERROR_INVALID_PARAMETER;
    return (*real)(window, out);
}

__attribute__((visibility("default")))
int ACaptureSessionOutput_create(void* window, void** out) {
    static create_fn real;
    return guarded("ACaptureSessionOutput_create", &real, window, out);
}

__attribute__((visibility("default")))
int ACameraOutputTarget_create(void* window, void** out) {
    static create_fn real;
    return guarded("ACameraOutputTarget_create", &real, window, out);
}

// 2026-11-18: in a dark room the worker rejects the blank frames and calls abortCaptures. The vendor NDK's flush()
// then deadlocks with its own result callback (main thread in BpHwCameraDeviceUser::flush holding the device lock,
// HwBinder callback thread waiting for it) until the HAL kills the worker 25 s later: the camera stays on after
// keyguard cancelled face auth, and 13 min when the tablet suspends in between (night 2026-11-17). stopRepeating
// ends the stream without flush(); the worker then closes the session and device as usual.
typedef int (*session_fn)(void* session);

__attribute__((visibility("default")))
int ACameraCaptureSession_abortCaptures(void* session) {
    static session_fn stop;
    if (!stop) stop = (session_fn)dlsym(RTLD_NEXT, "ACameraCaptureSession_stopRepeating");
    LOGW("ACameraCaptureSession_abortCaptures: stopRepeating instead (vendor NDK flush deadlock)");
    return stop ? stop(session) : 0;
}

// 2026-11-27 (BUGS 214): in a dark room the worker also tries camera "3" (a second, logical front camera). The QTI
// CHI override maps its 640x480 YUV stream to UsecaseVTCam, whose session has no input stream ("Input and Output
// Stream cannot be NULL m_pInputYuvStream 0x0"): camera.provider SIGSEGV in CamX::Session::Initialize (fault addr
// 0x20), the provider restarts. Camera "1" is the front camera that face unlock uses. Refuse "3" with an error code:
// the worker reports "camera open failed" and goes on with its next candidate, as for any camera that fails to open.
typedef int (*open_fn)(void* mgr, const char* id, void* callbacks, void** device);

__attribute__((visibility("default")))
int ACameraManager_openCamera(void* mgr, const char* id, void* callbacks, void** device) {
    static open_fn real;
    if (!real) real = (open_fn)dlsym(RTLD_NEXT, "ACameraManager_openCamera");
    if (id && id[0] == '3' && id[1] == '\0') {
        LOGW("ACameraManager_openCamera: camera 3 refused (VTCam usecase crashes the camera provider)");
        return ACAMERA_ERROR_INVALID_PARAMETER;
    }
    return real ? real(mgr, id, callbacks, device) : ACAMERA_ERROR_INVALID_PARAMETER;
}
