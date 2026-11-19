#!/bin/sh
# Phase 8c (2026-11-19, BUGS 48): the composer clamps a layer's plane alpha to 0..1 instead of refusing it.
#
# * After each screen rotation the ColorOS SurfaceFlinger sends plane alpha values just outside 0..1 for 10-20 s
#   (~20 per second of `command 0x4080000 generated error 4` = SET_LAYER_PLANE_ALPHA, BAD_PARAMETER; also on the home
#   screen). The sdm HWC2 (HWCLayer::SetLayerPlaneAlpha) refuses them and the layer keeps its old alpha: a candidate
#   for the short white flash testers see (not proven).
# * module/tools/patch_composer_planealpha.py: the two range checks become a clamp (fmaxnm/fminnm, same size;
#   pattern checked, one site). On top of 3j (genmeta) in the same binary.
# * A changed vendor service cannot be tested from /data (nosuid): test with this build.
#NEEDS: "$TOOLS/patch_composer_planealpha.py"
set -eu
. "$PORT/lib.sh"
C=$T/vendor/bin/hw/vendor.qti.hardware.display.composer-service
[ -f "$C" ] || die "no $C"
python3 -I "$TOOLS/patch_composer_planealpha.py" "$C" "$R/composer.planealpha"
cat "$R/composer.planealpha" > "$C"   # in place: owner, mode and SELinux label stay
md5sum "$C"
