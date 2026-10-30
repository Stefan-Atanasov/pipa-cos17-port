#!/bin/sh
# Phase 3t: no OplusBatteryService log spam (BUGS-TODO 34b; system only).
#
# * system/framework/oplus-services.jar: maintainer/batterylog/patch_battery_log.sh. OplusBatteryService logged
#   E "getDataFromHalByOldInterface" each battery update (every 2-3 s while charging). It is not a failure: the
#   service reads the charger flag before the charger shim registers, so it uses the old interface (one call per
#   value, the shim answers all). The patch removes only that Slog.e; the data path stays.
# * system_ext/etc/build.prop: ro.pipa.port.layer=3t (changed jar: early.sh clears the package cache).
set -eu
. "$PORT/lib.sh"
STEP=3t
#NEEDS: "$HERE/batterylog/patch_battery_log.sh" "$PIPA_ROOT/tools/smali/baksmali-2.5.2.jar"

echo "== oplus-services: no getDataFromHalByOldInterface error log"
J=$T/system/system/framework/oplus-services.jar
ANDROID_HOME=${ANDROID_HOME:-/home/${OWNER%%:*}/Android/Sdk} bash "$HERE/batterylog/patch_battery_log.sh" "$J" "$R/oplus-services.jar.new"
cat "$R/oplus-services.jar.new" > "$J"   # in place (cat >): owner, mode and SELinux label stay
rm -f "$R/oplus-services.jar.new"
if ls "$T/system/system/framework/oat"/*/oplus-services.* >/dev/null 2>&1; then die "prebuilt oat for oplus-services exists"; fi
md5sum "$J"   # on the pt18 jar: 1fd71578af596fad228475014fc15924

echo "== system_ext build.prop: ro.pipa.port.layer=$STEP"
set_layer "$STEP"
