#!/bin/sh
# Step 9n (BUGS-TODO 203, tester 2026-11-26 "back gesture stopped working"): back swipe from the right edge at
# Settings > Display > Screen resolution Low (9g regression since pt164).
# * system/framework/oplus-services.jar: maintainer/services/patch_invalid_region.sh. The gesture touch zones from
#   SystemUI/launcher (logical coordinates) are scaled to panel coordinates in InputManagerServiceExtImpl.
#   updateInvalidRegion when a forced display size is active (Low: x1.25); native resolution unchanged.
# Live test 2026-11-26 on pt167 (bind mount + zygote restart): landscape, right edge at 3 heights + left edge:
# Low before 000/1, after 111/1; High 111/1; Low again 111/1. No prebuilt oat for oplus-services in the image.
#NEEDS: "$HERE/services/patch_invalid_region.sh"
set -eu
. "$PORT/lib.sh"
STEP=9n
echo "== 9n gesture zones under a forced display size (Low resolution back swipe)"

J=$T/system/system/framework/oplus-services.jar
[ -f "$J" ] || die "no $J"
if ls "$T/system/system/framework/oat"/*/oplus-services.* >/dev/null 2>&1; then die "prebuilt oat for oplus-services exists"; fi
ANDROID_HOME=${ANDROID_HOME:-/home/${OWNER%%:*}/Android/Sdk} bash "$HERE/services/patch_invalid_region.sh" "$J" "$R/oplus-services.jar.new"
[ -s "$R/oplus-services.jar.new" ] || die "patch failed"
cat "$R/oplus-services.jar.new" > "$J"   # in place: owner, mode and SELinux label stay
rm -f "$R/oplus-services.jar.new"
md5sum "$J"
set_layer "$STEP"
