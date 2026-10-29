#!/bin/sh
# Phase 2x: SurfaceFlinger does not wait for OPPO display HALs (Game Filter freeze), on top of 2w (system +
# system_ext).
#
# * system/bin/surfaceflinger: Game tools "Game Filter" froze the tablet. The SurfaceFlinger main thread waited
#   forever for vendor.oplus.hardware.display.MixLut3D.IMixLut3D/default (fetchPanelLuts), which pipa does not have.
#   module/tools/patch_sf_waits.py changes the 4 unguarded waitForService calls (IMixLut3D, IDisplayColorFeature x2,
#   pixelworks IIris) to checkService. The code after each call already handles a null binder.
# * system_ext/etc/build.prop: ro.pipa.port.layer=2x (early.sh clears the package cache).
#
# Old layer script: build_beta5_2x.sh
#NEEDS: "$TOOLS/patch_sf_waits.py"
set -eu
. "$PORT/lib.sh"
STEP=2x

S=$T/system
SE=$T/system_ext

echo "== surfaceflinger: no waits for OPPO display HALs"
F=$S/system/bin/surfaceflinger
python3 -I "$TOOLS/patch_sf_waits.py" "$F" "$R/surfaceflinger.new"
cat "$R/surfaceflinger.new" > "$F"   # in place (cat >): owner, mode and SELinux label stay
md5sum "$F"
getfattr -n security.selinux --only-values "$F"; echo

echo "== system_ext build.prop: ro.pipa.port.layer=$STEP"
set_layer "$STEP"

