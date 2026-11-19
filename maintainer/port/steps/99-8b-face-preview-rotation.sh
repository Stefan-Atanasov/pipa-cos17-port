#!/bin/sh
# Phase 8b (2026-11-19, BUGS 147): face enrollment preview upright from the first frame, also after a flip.
#
# * facehal-rs turns each preview frame by the camera orientation plus persist.vendor.facehal.rotation (B7). The
#   pipa_port service set that property from `cmd display` only after it saw the camera worker (pidof every 3 s, all
#   the time): the first preview after a clean flash or a flip was rotated for up to 3 s, with the buffer size of the
#   old rotation (squashed face).
# * libpipa_facecrop (port-module/src/facecrop.c) now connects the preview window as soon as the HAL receives it
#   (ANativeWindow_readFromParcel), reads its transform hint (the display orientation) and answers the HAL's read of
#   that property from it (and stores it). service.sh: the rotation sync is removed (no pidof poll any more).
# * Live test 2026-11-19 (pt130, /data copy, property set wrong to 0): landscape enrollment upright and not squashed
#   from the start (hint 4 -> 90, buffer 640x480); portrait enrollment right (hint 0 -> 0, 480x640).
# * VERSION has the new md5: the /data copy of the face HAL is refreshed at the next boot.
#NEEDS: "$ROM/pipa_port/facehal/lib64/libpipa_facecrop.so" "$ROM/pipa_port/facehal/VERSION" "$ROM/pipa_port/service.sh"
set -eu
. "$PORT/lib.sh"
STEP=8b
SE=$T/system_ext
F=$SE/pipa_port/facehal
[ -f "$F/lib64/libpipa_facecrop.so" ] || die "no $F/lib64/libpipa_facecrop.so"
strings -a "$ROM/pipa_port/facehal/lib64/libpipa_facecrop.so" | grep -q 'preview window connect' || die "libpipa_facecrop.so: not the BUGS 147 build"
cat "$ROM/pipa_port/facehal/lib64/libpipa_facecrop.so" > "$F/lib64/libpipa_facecrop.so"   # in place: label, owner, mode stay
cat "$ROM/pipa_port/facehal/VERSION" > "$F/VERSION"
need_grep "$(md5sum < "$F/lib64/libpipa_facecrop.so" | cut -c1-32)  ./lib64/libpipa_facecrop.so" "$F/VERSION"
cat "$ROM/pipa_port/service.sh" > "$SE/pipa_port/service.sh"
forbid_grep 'face_rotation_sync' "$SE/pipa_port/service.sh"
echo "facehal: libpipa_facecrop.so $(md5sum < "$F/lib64/libpipa_facecrop.so" | cut -c1-32), VERSION, service.sh"
set_layer "$STEP"
