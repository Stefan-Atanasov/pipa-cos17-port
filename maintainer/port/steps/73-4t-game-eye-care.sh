#!/bin/sh
# Phase 4t: Game Eye Care works (BUGS-TODO 64; system only).
#
# * system/framework/oplus-services.jar: maintainer/gameeyecare/patch_gameeyecare.sh. Game Eye Care (Games app) sent
#   only IDisplayPanelFeature id 228: OPPO panels filter in their firmware; on pipa the 4r panel shim only stores the
#   value, so nothing changed. OplusFeatureGameEyeCare.updateGameEyeCareStatus() now also calls PipaGameEyeCare.set():
#   a warm, slightly darker DisplayTransformManager level (152, after Game Filter 151) while the switch is on and a
#   game is in full screen. Tested live 2026-11-03 (user: works).
# * system_ext/etc/build.prop: ro.pipa.port.layer=4t (changed jar: early.sh clears the package cache).
set -eu
. "$PORT/lib.sh"
STEP=4t
#NEEDS: "$HERE/gameeyecare/patch_gameeyecare.sh" "$PIPA_ROOT/tools/smali/baksmali-2.5.2.jar"

echo "== oplus-services: Game Eye Care as a colour matrix"
J=$T/system/system/framework/oplus-services.jar
ANDROID_HOME=${ANDROID_HOME:-/home/${OWNER%%:*}/Android/Sdk} bash "$HERE/gameeyecare/patch_gameeyecare.sh" "$J" "$R/oplus-services.jar.new"
cat "$R/oplus-services.jar.new" > "$J"   # in place (cat >): owner, mode and SELinux label stay
rm -f "$R/oplus-services.jar.new"
if ls "$T/system/system/framework/oat"/*/oplus-services.* >/dev/null 2>&1; then die "prebuilt oat for oplus-services exists"; fi
md5sum "$J"   # on the pt31 jar (C.07): 549c0e89412ca9c82ed63b86adf0f3b4

echo "== system_ext build.prop: ro.pipa.port.layer=$STEP"
set_layer "$STEP"
