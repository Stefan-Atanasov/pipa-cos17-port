#!/bin/sh
# Phase 5a: external display can use its high refresh modes (BUGS-TODO 54; system only).
#
# * system/framework/services.jar: maintainer/extdisplay/patch_ext_modes.sh. Android 17 marks all modes of an external
#   display FLAG_SIZE_OVERRIDE while the SurfaceFlinger flag synced_resolution_switch is off (not in this build), and
#   then the user preferred mode votes only a render rate: the GO27Q24 stayed at 2560x1440@60 although @120 is listed.
#   The patch turns the size override off (Android 16 behaviour). The internal display does not change.
# * system_ext/etc/build.prop: ro.pipa.port.layer=5a (changed jar: early.sh clears the package cache).
set -eu
. "$PORT/lib.sh"
STEP=5a
#NEEDS: "$HERE/extdisplay/patch_ext_modes.sh" "$PIPA_ROOT/tools/smali/baksmali-2.5.2.jar"

echo "== services: no FLAG_SIZE_OVERRIDE on external display modes"
J=$T/system/system/framework/services.jar
ANDROID_HOME=${ANDROID_HOME:-/home/${OWNER%%:*}/Android/Sdk} bash "$HERE/extdisplay/patch_ext_modes.sh" "$J" "$R/services.jar.new"
cat "$R/services.jar.new" > "$J"   # in place (cat >): owner, mode and SELinux label stay
rm -f "$R/services.jar.new"
if ls "$T/system/system/framework/oat"/*/services.* >/dev/null 2>&1; then die "prebuilt oat for services exists"; fi
md5sum "$J"   # on the pt40 jar: 5e1a14cd3cecd3aacbc2fa367dae8fd7

echo "== system_ext build.prop: ro.pipa.port.layer=$STEP"
set_layer "$STEP"
