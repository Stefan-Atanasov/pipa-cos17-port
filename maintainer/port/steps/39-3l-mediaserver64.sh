#!/bin/sh
# Phase 3l: 64-bit mediaserver (BUGS-TODO 33), product only.
#
# The pinned beta4 vendor has two Adreno builds: lib64/egl LA.VENDOR.12.3.11 (2025-08) and lib/egl LA.UM.9.14
# (2024-09). The 32-bit set cannot start (eglInitialize EGL_BAD_ALLOC), so the 32-bit mediaserver aborts in frame
# capture ("no suitable EGLConfig found") on each new video: no video thumbnails. No matching 32-bit set exists.
# The donor's mediaserverwrapper starts /system/bin/mediaserver64 when ro.mediaserver.64b.enable=true, else the
# 32-bit /system/bin/mediaserver. Tested live 2026-10-29 with resetprop: mediaserver64, thumbnails of an SDR and an
# HDR10 clip, no tombstone.
# * product/etc/build.prop: ro.mediaserver.64b.enable=true.
set -eu
. "$PORT/lib.sh"

BP=$T/product/etc/build.prop

echo "== 33: ro.mediaserver.64b.enable=true"
if grep -q "^ro.mediaserver.64b.enable=" "$BP"; then echo "product build.prop already sets ro.mediaserver.64b.enable"; exit 1; fi
{ cat "$BP"; printf '%s\n' "# pipa port 3l (BUGS-TODO 33): 64-bit mediaserver (the 32-bit Adreno set cannot start)" "ro.mediaserver.64b.enable=true"; } > "$R/build.prop.new"
cat "$R/build.prop.new" > "$BP"   # same inode: label kept
tail -2 "$BP"
