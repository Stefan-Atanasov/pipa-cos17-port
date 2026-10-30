#!/bin/bash
# BUGS-TODO 34b: OplusBatteryService log spam (E "getDataFromHalByOldInterface" every 2-3 s while charging, ~11 s on
# battery). OplusBatteryService reads "chargerInfoUpdateSupported" (getChgConfig 31) once in its constructor. The
# charger shim registers later, so the value is empty, and the service uses the old interface (one HAL call per
# value; the shim answers all of them). This is not a failure: the old path logs its own name at error level each
# time. The patch removes that one Slog.e in getDataFromHalByOldInterface(J)V (oplus-services.jar classes.dex).
# The data path does not change. ("Charger voltage : 0" in dumpsys battery is only set by the debug command
# "chargervol", also on OPPO devices.)
#   patch_battery_log.sh <oplus-services.jar in> <oplus-services.jar out>
# Needs JDK 21, ~/Android/Sdk build-tools 37, tools/smali (2.5.2). Stops on any surprise. smali/baksmali with -j 1.
set -euo pipefail
IN=$(realpath "$1"); OUT=$(realpath -m "$2")
HERE=$(cd "$(dirname "$0")" && pwd)
SMALI=$HERE/../../../tools/smali
SDK=${ANDROID_HOME:-$HOME/Android/Sdk}; BT=$SDK/build-tools/37.0.0
W=$(mktemp -d); trap 'rm -rf "$W"' EXIT
CLS=com/android/server/OplusBatteryService.smali

unzip -q "$IN" classes.dex -d "$W"
java -jar "$SMALI/baksmali-2.5.2.jar" d -j 1 -a 36 "$W/classes.dex" -o "$W/sm"
[ -f "$W/sm/$CLS" ] || { echo "no OplusBatteryService in classes.dex"; exit 1; }
python3 - "$W/sm/$CLS" <<'PY'
import re, sys
p = sys.argv[1]; s = open(p).read()
head = '.method private getDataFromHalByOldInterface(J)V\n'
assert s.count(head) == 1, "getDataFromHalByOldInterface(J)V not found once"
a = s.index(head); b = s.index('.end method', a)
body = s[a:b]
pat = re.compile(r'\n    sget-object v1, Lcom/android/server/OplusBatteryService;->TAG:Ljava/lang/String;\n\n'
                 r'(    \.line \d+\n)?\s*const-string/jumbo v2, "getDataFromHalByOldInterface"\n\n'
                 r'(    \.line \d+\n)?\s*invoke-static \{v1, v2\}, Landroid/util/Slog;->e\(Ljava/lang/String;Ljava/lang/String;\)I\n')
m = list(pat.finditer(body))
assert len(m) == 1, "Slog.e block in getDataFromHalByOldInterface does not look as expected (%d matches)" % len(m)
body = body[:m[0].start()] + '\n' + body[m[0].end():]
# v1/v2 are written again before the next read (sget-object v1 DEFAULT, const/4 v2 0x0)
assert re.search(r'\n\s*sget-object v1, Lcom/android/server/IOplusBatteryServiceFeature;->DEFAULT', body[:600]), "next use of v1 moved"
open(p, 'w').write(s[:a] + body + s[b:])
PY
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
