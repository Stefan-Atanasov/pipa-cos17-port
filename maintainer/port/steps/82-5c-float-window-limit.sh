#!/bin/sh
# Phase 5c: more than one floating window also with launcher animation tier 3/4 (user 2026-11-04; system only).
#
# * system/framework/oplus-services.jar: maintainer/flexwin/patch_float_limit.sh. With persist.sys.oplus.anim_level 3
#   or 4 (pipa_port ANIM_LEVEL / pipa_anim_level) ColorOS takes the "light OS" path, and
#   FlexibleWindowManagerService.getMaxWinNum(I) returns 1: a second floating window closes the first. The patch
#   ignores IS_LIGHT_OS there only; the animation tier stays. Tested live 2026-11-04 (bind mount, tier 3).
# * system_ext/etc/build.prop: ro.pipa.port.layer=5c (changed jar: early.sh clears the package cache).
set -eu
. "$PORT/lib.sh"
STEP=5c
#NEEDS: "$HERE/flexwin/patch_float_limit.sh" "$PIPA_ROOT/tools/smali/baksmali-2.5.2.jar"

echo "== oplus-services: floating window limit independent of the animation tier"
J=$T/system/system/framework/oplus-services.jar
ANDROID_HOME=${ANDROID_HOME:-/home/${OWNER%%:*}/Android/Sdk} bash "$HERE/flexwin/patch_float_limit.sh" "$J" "$R/oplus-services.jar.new"
cat "$R/oplus-services.jar.new" > "$J"   # in place (cat >): owner, mode and SELinux label stay
rm -f "$R/oplus-services.jar.new"
if ls "$T/system/system/framework/oat"/*/oplus-services.* >/dev/null 2>&1; then die "prebuilt oat for oplus-services exists"; fi
md5sum "$J"   # on the pt40 jar: 87362496e6d33c26cf2f52f54744dc58

echo "== system_ext build.prop: ro.pipa.port.layer=$STEP"
set_layer "$STEP"
