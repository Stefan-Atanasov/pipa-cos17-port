#!/bin/sh
# Step 8t (2026-11-21, BUGS 168): 32-bit apps draw again (32-bit Adreno set from stock HyperOS).
# The beta4 vendor pairs a 2025 64-bit Adreno driver (lib64/egl LA.VENDOR.12.3.11, 12.1.6) with an older 32-bit set
# (lib/egl LA.UM.9.14 2024-09, 10.0.7) that cannot start here: eglInitialize EGL_BAD_ALLOC, so every 32-bit app
# aborted in hwui at launch ("Failed to create context, error = EGL_NOT_INITIALIZED"; StarNote armeabi-v7a build).
# Stock HyperOS pipa (also PixelOS / iqraOS, identical md5) has a matched 2021 set (V@0502.0, 10/04/21). Only the
# 32-bit set changes (lib/, lib/egl, lib/hw); lib64, gralloc, mapper and 7h stay. Every NEEDED of the new files
# resolves in vendor/lib + system/lib (research port-work/codex/32bit-adreno-20261121/REPORT.md).
# Live test 2026-11-21 (pt150, bind mounts): app_process32 EGL test eglInitialize 1.5, GLES 3.2 context
# "Adreno (TM) 650" (with the beta4 set: no context).
#NEEDS: "$P/blobs/adreno32-hyperos/libgsl.so"
set -eu
. "$PORT/lib.sh"
STEP=8t
SRC=$P/blobs/adreno32-hyperos
echo "== 8t vendor/lib 32-bit Adreno set from stock HyperOS (BUGS 168)"
while read -r f old new; do
    [ -n "$f" ] || continue
    t=$T/vendor/lib/$f
    [ -f "$t" ] || die "missing $t"
    [ "$(md5sum < "$t" | cut -d' ' -f1)" = "$old" ] || die "$t: unexpected md5 (not the beta4 32-bit set)"
    [ "$(md5sum < "$SRC/$f" | cut -d' ' -f1)" = "$new" ] || die "$SRC/$f: wrong blob md5"
    cat "$SRC/$f" > "$t"   # same inode: label, owner and mode kept
    [ "$(md5sum < "$t" | cut -d' ' -f1)" = "$new" ] || die "$t: copy failed"
    echo "lib/$f -> $new"
done <<'LIST'
egl/libGLESv2_adreno.so de01847c04074c3b8894f79b4ab13550 714727e18f310a7487f7f810825f856a
egl/libGLESv1_CM_adreno.so e3c609b6e2e7a20b250a5366d2460830 f0a84008f57fb0e631f8bd78ed416399
egl/libEGL_adreno.so d3c593bc871bfcb047d37fe676b5c0e1 bcb429940f1de67aaae544aceec225fb
egl/eglSubDriverAndroid.so 830814e3ba993e2f63a3eebefd8cfcdd 613bbc3563be81416306c6c2e04f12a6
libgsl.so 0a06a9a095fd766e980cfb59635473ab 56e95990f230d800b659b31acf0b67ce
libadreno_utils.so 18def05618463c1e03dc8112774611f5 8697621d9df2f7ce3bbb3581ad3d474f
libllvm-glnext.so ea33ac2337fc5f8fa23373b7e556ccb9 da55aafa11e3824f8c513b4f8e319fd4
libCB.so 080d19ba6b87c33a2e1a0ad37c7a2156 01fb5c4a672c666b941bd58223d197f8
hw/vulkan.adreno.so 5c133ecbb3825a9e3431fc864310cbc8 10862b0f6ca43307c21a463ab93bdb4b
libOpenCL.so ddd0b62f1a420636b9a0dafe9bb0c2a5 2d748d0a9c30b28f58967f38047d079e
LIST
getfattr -n security.selinux --only-values "$T/vendor/lib/egl/libGLESv2_adreno.so"; echo
set_layer "$STEP"
