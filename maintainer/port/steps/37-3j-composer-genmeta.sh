#!/bin/sh
# Phase 3j: YouTube HDR without glitches (BUGS-TODO 29), on top of 3i (vendor only).
#
# With wide colour (3i) the ColorOS SurfaceFlinger sends SET_LAYER_GENERIC_METADATA (0x040e0000) every frame during
# HDR. The PixelOS composer has no handler for it; parse() then drops the rest of the frame (glitches, no response).
# * vendor/bin/hw/vendor.qti.hardware.display.composer-service: module/tools/patch_composer_genmeta.py (md5-gated;
#   unknown commands are skipped, parsed=true). A changed vendor service cannot be tested from /data (nosuid).
#
# Old layer script: build_beta5_3j.sh
set -eu
. "$PORT/lib.sh"
#NEEDS: "$TOOLS/patch_composer_genmeta.py"

C=$T/vendor/bin/hw/vendor.qti.hardware.display.composer-service

echo "== 29: composer skips SET_LAYER_GENERIC_METADATA"
python3 -I "$TOOLS/patch_composer_genmeta.py" "$C" "$R/composer-service.new"
cat "$R/composer-service.new" > "$C"   # same inode: owner, mode, label stay
md5sum "$C"
