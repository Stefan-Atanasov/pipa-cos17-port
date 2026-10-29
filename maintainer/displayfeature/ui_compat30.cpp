// libui_compat30.so: the 6 symbols that HyperOS's vendor libgui_vendor.so (built for VNDK v30) needs from the
// Android 11 libui.so, and that the port's newer vendor libui.so no longer exports. Only for the displayfeature HAL
// (ROM layer 2y); module/tools/patch_gui_vendor.py points one unused DT_NEEDED of libgui_vendor.so at this library.
//
// ui::Size::INVALID has its Android 11 value. The other five are only used for HDR capabilities and debug dumps;
// they are safe stubs (no data, INVALID_OPERATION).
//
// Build (NDK): aarch64-linux-android30-clang++ -shared -fPIC -O2 -nostdlib++ -Wl,-soname,libui_compat30.so
#include <stddef.h>
#include <stdint.h>

namespace android {

struct Rect;

namespace ui {
struct Size {
    int32_t width;
    int32_t height;
    static const Size INVALID;
};
__attribute__((visibility("default"))) const Size Size::INVALID{-1, -1};
}  // namespace ui

class __attribute__((visibility("default"))) HdrCapabilities {
public:
    ~HdrCapabilities();
    size_t getFlattenedSize() const;
    int32_t flatten(void* buffer, size_t size) const;
    int32_t unflatten(void const* buffer, size_t size);
};

HdrCapabilities::~HdrCapabilities() {}
size_t HdrCapabilities::getFlattenedSize() const { return 0; }
int32_t HdrCapabilities::flatten(void*, size_t) const { return -38; }    // INVALID_OPERATION
int32_t HdrCapabilities::unflatten(void const*, size_t) { return -38; }  // INVALID_OPERATION

}  // namespace android

// std::string to_string(const android::Rect&): libc++'s std::string is 24 bytes and is returned through x8 like any
// composite larger than 16 bytes; all zero bytes are an empty short string.
struct EmptyString {
    void* words[3];
};
__attribute__((visibility("default"))) EmptyString to_string(const android::Rect&) { return EmptyString{}; }
