#!/bin/sh
# Phase 3p: Google Photos sees an original Pixel (product only).
#
# Step 3o gives Google Photos a Pixel XL identity (Build.MODEL etc.), but Photos does not detect the 2016 Pixel by
# model: its device-type enum maps PIXEL_2016 to the system feature com.google.android.apps.photos.NEXUS_PRELOAD (newer
# Pixels: PIXEL_20xx_PRELOAD / PIXEL_20xx_EXPERIENCE). Real Pixel XL images declare it in a sysconfig file.
# * product/etc/sysconfig/pipa-photos.xml: the feature (and the old lowercase name). Only Photos reads these names.
#   Live test 2026-10-29 (bind mount + zygote restart): Backup quality shows Original quality, free unlimited.
# * system_ext/etc/build.prop: ro.pipa.port.layer=3p.
set -eu
. "$PORT/lib.sh"
STEP=3p

D=$T/product/etc/sysconfig
F=$D/pipa-photos.xml
[ -f "$D/google.xml" ] || die "no $D/google.xml (label source)"
[ ! -e "$F" ] || die "$F exists already"
if grep -rq "com.google.android.apps.photos.NEXUS_PRELOAD" "$D"; then die "a sysconfig file declares NEXUS_PRELOAD already"; fi
cat > "$F" <<'EOF'
<?xml version="1.0" encoding="utf-8"?>
<!-- pipa port 3p: Google Photos sees an original Pixel (PIXEL_2016: free original-quality backup). -->
<config>
    <feature name="com.google.android.apps.photos.NEXUS_PRELOAD" />
    <feature name="com.google.android.apps.photos.nexus_preload" />
</config>
EOF
chown 0:0 "$F"; chmod 644 "$F"
setfattr -n security.selinux -v "$(getfattr --only-values -n security.selinux "$D/google.xml")" "$F"
echo "added   product/etc/sysconfig/pipa-photos.xml ($(getfattr --only-values -n security.selinux "$F"))"

echo "== system_ext build.prop: ro.pipa.port.layer=$STEP"
set_layer "$STEP"
