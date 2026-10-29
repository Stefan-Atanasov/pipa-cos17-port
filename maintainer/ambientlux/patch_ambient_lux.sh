#!/bin/bash
# Adaptive tone gets a continuous colour stream with real lux, like on OPPO devices (user wish 2026-10-29; research
# port-work/codex/adaptive-tone-answer.md).
# ColorOS's OplusColorAmbientAdapter wants OPPO's colour sensor: a stream with values [CCT, .., x(7), y(8), lux(9),
# confidence(10)]. patch_framework.sh rerouted it to Xiaomi front_cct (33171088): an ON-CHANGE sensor with
# [CCT, x, y, 0...]. Its few events never filled SensorDataFilter (it needs 10 stable samples: sensorDataValid stayed
# false), and slot 9 (lux) was 0: patch_framework.sh fed a constant 100 lx to the filter only, the lux average
# (low-light lock, animation speed) stayed 0 (30 s animations).
# The same tcs3701 has a CONTINUOUS sensor front_cct_strm (33171089, 1-2000 Hz). Its event (seen 2026-10-29):
# [lux, CCT, R, G, B, C, 1000, 512, 100, CCT, 0, 0, CCT, 0, 0, 0].
# This patch in OplusColorAmbientAdapter (oplus-services.jar classes.dex):
#   * registerSensor(): registers 33171089 (SENSOR_DELAY_NORMAL, 5 Hz) instead of 33171088.
#   * handleSensorChange(): 33171089 -> new onPipaStream(): rewrites the event to the OPPO layout (CCT -> 0,
#     lux -> 9, x/y 7/8 = 0, confidence 10 = 1) and calls onSingleSensorChanged().
#   * onSingleSensorChanged(): the patch_framework.sh constant 100 lx before feedFilter() is a read of values[9] again.
#   * DefaultConfig.YS: a stronger DEFAULT curve (edit_adapter.py STRENGTH; stock was too weak next to an OPPO phone).
#   * Bedtime: night curve = adaptive - 600 K (min 3400 K), day = min(stock, adaptive), dark lock 5100 -> 3600 K.
#   * $1.onSensorChanged(): the queued SensorEvent gets a copy of the values array (the sensor framework reuses it,
#     and onPipaStream() writes into it).
#   patch_ambient_lux.sh <oplus-services.jar in> <oplus-services.jar out>
# Needs JDK 21, ~/Android/Sdk build-tools 37, tools/smali (2.5.2). Stops on any surprise. smali/baksmali with -j 1.
set -euo pipefail
IN=$(realpath "$1"); OUT=$(realpath -m "$2")
HERE=$(cd "$(dirname "$0")" && pwd)
SMALI=$HERE/../../../tools/smali
SDK=${ANDROID_HOME:-$HOME/Android/Sdk}; BT=$SDK/build-tools/37.0.0
W=$(mktemp -d); trap 'rm -rf "$W"' EXIT
C=com/android/server/display/color/control

unzip -q "$IN" classes.dex -d "$W"
java -jar "$SMALI/baksmali-2.5.2.jar" d -j 1 -a 36 "$W/classes.dex" -o "$W/sm"
[ -f "$W/sm/$C/OplusColorAmbientAdapter.smali" ] || { echo "no OplusColorAmbientAdapter in classes.dex"; exit 1; }
python3 "$HERE/edit_adapter.py" "$W/sm/$C/OplusColorAmbientAdapter.smali" "$W/sm/$C/OplusColorAmbientAdapter\$1.smali" \
    "$W/sm/com/android/server/display/color/model/DefaultConfig.smali" "$W/sm/com/android/server/display/color/model/ModelConfig.smali" \
    "$W/sm/com/android/server/display/color/config/EyeProtectConfig.smali"
java -jar "$SMALI/smali-2.5.2.jar" a -j 1 -a 36 "$W/sm" -o "$W/classes.dex"

# new jar: same entries in the same order, classes.dex replaced, same compression per entry
python3 - "$IN" "$OUT" "$W/classes.dex" <<'PY'
import sys, zipfile
src, dst, dex = sys.argv[1:]
with zipfile.ZipFile(src) as zi, zipfile.ZipFile(dst + ".tmp", "w") as zo:
    for e in zi.infolist():
        data = open(dex, "rb").read() if e.filename == "classes.dex" else zi.read(e)
        n = zipfile.ZipInfo(e.filename, e.date_time); n.compress_type = e.compress_type; n.external_attr = e.external_attr
        zo.writestr(n, data)
PY
"$BT/zipalign" -f -p 4 "$OUT.tmp" "$OUT"; rm -f "$OUT.tmp"
"$BT/zipalign" -c -p 4 "$OUT" >/dev/null && echo "ok: $OUT $(md5sum < "$OUT" | cut -c1-32)"
