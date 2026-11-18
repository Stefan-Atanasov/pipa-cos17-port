#!/bin/sh
# Step 7h (BUGS 121, 2026-11-16): camera RAW10/RAW12 buffers (GCam HDR+, any app that asks for RAW10) work again.
# Our vendor libgrallocutils.so (beta4 base, md5 670fd5fd / lib 77c02122) treats formats 0x24-0x26 (RAW_OPAQUE,
# RAW10, RAW12) as Qualcomm camera custom formats and asks libcamxexternalformatutils for the stride. That lib only
# knows 0x24 and 0x113+ and returns 1: gralloc logs "Failed to get the aligned width for camera custom format" and
# the allocation fails. The PixelOS libgrallocutils (same CAF sm8250 source, same exports, offsets, one fewer
# dependency) and the HyperOS one treat only 0x24 as custom, so RAW10 uses the normal gralloc path (= stock).
# Only the utils lib changes; core, mapper and allocator stay. Live test 2026-11-16 (KSU bind module on pt105):
# boot OK, no crash, GCam RAW_HDRPLUS stream allocates. Report: port-work/codex/raw10-gralloc-20261116/REPORT.md.
#NEEDS: "$P/blobs/grallocutils-pixelos/lib64/libgrallocutils.so"
#NEEDS: "$P/blobs/grallocutils-pixelos/lib/libgrallocutils.so"
set -eu
. "$PORT/lib.sh"
STEP=7h
SRC=$P/blobs/grallocutils-pixelos
echo "== 7h vendor libgrallocutils from PixelOS (RAW10 camera buffers)"
for a in "lib64 670fd5fd751483b3bf8846bb17d42964 926727b931026e7c95417fbb5f93b8cd" \
         "lib 77c02122bf23371296bb728f2645d4c4 3be4847e527216b43d9246f513a34734"; do
    set -- $a
    f=$T/vendor/$1/libgrallocutils.so
    [ -f "$f" ] || die "missing $f"
    [ "$(md5sum < "$f" | cut -d' ' -f1)" = "$2" ] || die "$f: unexpected md5 (not the beta4 lib)"
    [ "$(md5sum < "$SRC/$1/libgrallocutils.so" | cut -d' ' -f1)" = "$3" ] || die "$SRC/$1: wrong blob md5"
    cat "$SRC/$1/libgrallocutils.so" > "$f"   # same inode: label, owner and mode kept
    [ "$(md5sum < "$f" | cut -d' ' -f1)" = "$3" ] || die "$f: copy failed"
    echo "$1/libgrallocutils.so -> $3"
done
