#!/bin/sh
# Phase 5e: a USB-C monitor keeps its native size and gets a desktop density (BUGS-TODO 54; system only).
#
# * system/framework/oplus-services.jar: maintainer/extdisplay/patch_ext_density.sh (after 5c, same jar). ColorOS
#   RootWindowContainerExtImpl.setForcedDisplayInfoIfNeed() gave the extended screen the tablet density (370) and a
#   forced size with >= 720 dp (2560x1440 -> 2960x1668: too big, scaled, cropped). Now: native size, density =
#   physical short side * 200 / 1440 (1440p -> 200 = user choice, Windows 125 %; 1080p -> 150; 2160p -> 300; >= 120).
#   Tested live 2026-11-04 (GO27Q24: 2560x1440, 200 dpi, 120 Hz with 5a and kernel r15).
# * system_ext/etc/build.prop: ro.pipa.port.layer=5e (changed jar: early.sh clears the package cache).
set -eu
. "$PORT/lib.sh"
STEP=5e
#NEEDS: "$HERE/extdisplay/patch_ext_density.sh" "$PIPA_ROOT/tools/smali/baksmali-2.5.2.jar"

echo "== oplus-services: external display native size + density from its resolution"
J=$T/system/system/framework/oplus-services.jar
ANDROID_HOME=${ANDROID_HOME:-/home/${OWNER%%:*}/Android/Sdk} bash "$HERE/extdisplay/patch_ext_density.sh" "$J" "$R/oplus-services.jar.new"
cat "$R/oplus-services.jar.new" > "$J"   # in place (cat >): owner, mode and SELinux label stay
rm -f "$R/oplus-services.jar.new"
md5sum "$J"   # on the pt40 jar after 5c: 60ba905fe49edf9b9ba8f40bb382c8d7

echo "== system_ext build.prop: ro.pipa.port.layer=$STEP"
set_layer "$STEP"
