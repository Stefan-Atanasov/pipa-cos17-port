#!/bin/bash
# BUGS-TODO 22: Game Filter / colour enhancement as a SurfaceFlinger colour matrix (src/com/oplus/vrr/PipaGameFilter.java).
# Adds PipaGameFilter to classes3.dex of oplus-services.jar and calls PipaGameFilter.set(mode) at the start of
# OPlusSurfaceFlingerController.setGameFilter(int). The original SF transaction 22031 stays (it does nothing on pipa).
#   patch_gamefilter.sh <oplus-services.jar in> <oplus-services.jar out>
# Needs JDK 21, ~/Android/Sdk (build-tools 37, platform 37.0), tools/smali (2.5.2). Stops on any surprise.
# smali/baksmali run with -j 1: with threads the dex layout (not the code) changes on each run (2026-10-29).
set -euo pipefail
IN=$(realpath "$1"); OUT=$(realpath -m "$2")
HERE=$(cd "$(dirname "$0")" && pwd)
SMALI=$HERE/../../../tools/smali
SDK=${ANDROID_HOME:-$HOME/Android/Sdk}; BT=$SDK/build-tools/37.0.0; JAR=$SDK/platforms/android-37.0/android.jar
W=$(mktemp -d); trap 'rm -rf "$W"' EXIT
CLS=com/oplus/vrr/OPlusSurfaceFlingerController.smali

mkdir -p "$W/stub" "$W/cls" "$W/dex"
javac --release 17 -nowarn -cp "$JAR" -d "$W/stub" $(find "$HERE/stubs" -name '*.java')
javac --release 17 -nowarn -cp "$JAR:$W/stub" -d "$W/cls" "$HERE/src/com/oplus/vrr/PipaGameFilter.java"
"$BT/d8" --release --min-api 35 --lib "$JAR" --classpath "$W/stub" --output "$W/dex" "$W"/cls/com/oplus/vrr/*.class
java -jar "$SMALI/baksmali-2.5.2.jar" d -j 1 -a 36 "$W/dex/classes.dex" -o "$W/new"

unzip -q "$IN" classes3.dex -d "$W"
java -jar "$SMALI/baksmali-2.5.2.jar" d -j 1 -a 36 "$W/classes3.dex" -o "$W/sm"
[ -f "$W/sm/$CLS" ] || { echo "no $CLS in classes3.dex"; exit 1; }
[ ! -e "$W/sm/com/oplus/vrr/PipaGameFilter.smali" ] || { echo "already patched"; exit 1; }
cp "$W"/new/com/oplus/vrr/*.smali "$W/sm/com/oplus/vrr/"
python3 - "$W/sm/$CLS" <<'PY'
import sys
p = sys.argv[1]; s = open(p).read()
head = '.method public setGameFilter(I)V\n    .registers 8\n    .param p1, "gameFilterMode"    # I\n'
assert s.count(head) == 1, "setGameFilter(I)V does not look as expected"
s = s.replace(head, head + '\n    invoke-static {p1}, Lcom/oplus/vrr/PipaGameFilter;->set(I)V\n')
open(p, 'w').write(s)
PY
java -jar "$SMALI/smali-2.5.2.jar" a -j 1 -a 36 "$W/sm" -o "$W/classes3.dex"

# new jar: same entries in the same order, classes3.dex replaced, same compression per entry
python3 - "$IN" "$OUT" "$W/classes3.dex" <<'PY'
import sys, zipfile
src, dst, dex = sys.argv[1:]
with zipfile.ZipFile(src) as zi, zipfile.ZipFile(dst + ".tmp", "w") as zo:
    for e in zi.infolist():
        data = open(dex, "rb").read() if e.filename == "classes3.dex" else zi.read(e)
        n = zipfile.ZipInfo(e.filename, e.date_time); n.compress_type = e.compress_type; n.external_attr = e.external_attr
        zo.writestr(n, data)
PY
"$BT/zipalign" -f -p 4 "$OUT.tmp" "$OUT"; rm -f "$OUT.tmp"
"$BT/zipalign" -c -p 4 "$OUT" >/dev/null && echo "ok: $OUT $(md5sum < "$OUT" | cut -c1-32)"
