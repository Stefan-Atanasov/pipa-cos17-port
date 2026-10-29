#!/bin/sh
# Phase 3s: adaptive tone works like on OPPO devices (user wish 2026-10-29; system only).
#
# * system/framework/oplus-services.jar: maintainer/ambientlux/patch_ambient_lux.sh. ColorOS's ambient colour now reads
#   the continuous Xiaomi sensor front_cct_strm (33171089: lux and CCT, 5 Hz) instead of the on-change front_cct
#   (33171088, step 01 reroute), mapped to OPPO's event layout (CCT slot 0, real lux slot 9). Before, the filter
#   never got 10 stable samples (sensorDataValid=false: adaptive tone did nearly nothing) and lux was 0 (30 s
#   animations). Also a stronger DEFAULT curve (room 4000 K -> 4737 K, was 5395 K). Live test 2026-10-29 (bind mount
#   + zygote restart): sensorDataValid=true, real lux, user: "now good" next to an OPPO phone with adaptive tone.
#   Bedtime (comfortable rhythm) day/night curves were cooler than the new adaptive curve (bedtime made the screen
#   cooler): night = adaptive - 600 K (min 3400), day = min(stock, adaptive), dark lock 5100 -> 3600 K, stream CCT kept in 1000..10000 K (dark: 100000+ K or 0; below 1000 -> 3000 K). Live map
#   2026-10-29 (room 3525 K): off 7900, adaptive 4420, bedtime 3820 K. At night with adaptive on, bedtime locks with
#   the LUT values (stock 0 without a LUT config = white in a dark room): default to the night lock (dark: 3600 K).
#   Research: port-work/codex/adaptive-tone-answer.md.
# * system_ext/etc/build.prop: ro.pipa.port.layer=3s (changed jar: early.sh clears the package cache).
set -eu
. "$PORT/lib.sh"
STEP=3s
#NEEDS: "$HERE/ambientlux/patch_ambient_lux.sh" "$HERE/ambientlux/edit_adapter.py" "$PIPA_ROOT/tools/smali/baksmali-2.5.2.jar"

echo "== adaptive tone: colour stream sensor, real lux, stronger curve"
J=$T/system/system/framework/oplus-services.jar
ANDROID_HOME=${ANDROID_HOME:-/home/${OWNER%%:*}/Android/Sdk} bash "$HERE/ambientlux/patch_ambient_lux.sh" "$J" "$R/oplus-services.jar.new"
cat "$R/oplus-services.jar.new" > "$J"   # in place (cat >): owner, mode and SELinux label stay
rm -f "$R/oplus-services.jar.new"
if ls "$T/system/system/framework/oat"/*/oplus-services.* >/dev/null 2>&1; then die "prebuilt oat for oplus-services exists"; fi
md5sum "$J"   # on the pt14 jar (c853323...): 5bdab603d0023282bc52f23b76e7e587 = the live-tested jar (bedtime, locks 3600 K, CCT 1000..10000)

echo "== system_ext build.prop: ro.pipa.port.layer=$STEP"
set_layer "$STEP"
