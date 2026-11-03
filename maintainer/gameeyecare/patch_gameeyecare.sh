#!/bin/bash
# BUGS-TODO 64: Game Eye Care as a SurfaceFlinger colour matrix (src/.../PipaGameEyeCare.java).
# Adds PipaGameEyeCare to the dex of oplus-services.jar that has OplusFeatureGameEyeCare and calls
# PipaGameEyeCare.set(status) right after the panel call (id 0xe4) in updateGameEyeCareStatus(). The panel call stays.
#   patch_gameeyecare.sh <oplus-services.jar in> <oplus-services.jar out>
# Needs JDK 21, ~/Android/Sdk (build-tools 37, platform 37.0), tools/smali (2.5.2). Stops on any surprise.
set -euo pipefail
IN=$(realpath "$1"); OUT=$(realpath -m "$2")
HERE=$(cd "$(dirname "$0")" && pwd)
SMALI=$HERE/../../../tools/smali
SDK=${ANDROID_HOME:-$HOME/Android/Sdk}; BT=$SDK/build-tools/37.0.0; JAR=$SDK/platforms/android-37.0/android.jar
W=$(mktemp -d); trap 'rm -rf "$W"' EXIT
PKG=com/android/server/display/color/feature
CLS=$PKG/OplusFeatureGameEyeCare.smali

mkdir -p "$W/stub" "$W/cls" "$W/dex"
javac --release 17 -nowarn -cp "$JAR" -d "$W/stub" $(find "$HERE/stubs" -name '*.java')
javac --release 17 -nowarn -cp "$JAR:$W/stub" -d "$W/cls" "$HERE/src/$PKG/PipaGameEyeCare.java"
"$BT/d8" --release --min-api 35 --lib "$JAR" --classpath "$W/stub" --output "$W/dex" "$W"/cls/$PKG/*.class
java -jar "$SMALI/baksmali-2.5.2.jar" d -j 1 -a 36 "$W/dex/classes.dex" -o "$W/new"

DEX=
for d in $(unzip -Z1 "$IN" | grep -E '^classes[0-9]*\.dex$'); do
    unzip -q -o "$IN" "$d" -d "$W/in"
    if grep -q "L$PKG/OplusFeatureGameEyeCare;" "$W/in/$d" 2>/dev/null || strings "$W/in/$d" | grep -q "L$PKG/OplusFeatureGameEyeCare;"; then DEX=$d; break; fi
done
[ -n "$DEX" ] || { echo "OplusFeatureGameEyeCare not found"; exit 1; }
java -jar "$SMALI/baksmali-2.5.2.jar" d -j 1 -a 36 "$W/in/$DEX" -o "$W/sm"
[ -f "$W/sm/$CLS" ] || { echo "no $CLS in $DEX"; exit 1; }
[ ! -e "$W/sm/$PKG/PipaGameEyeCare.smali" ] || { echo "already patched"; exit 1; }
cp "$W"/new/$PKG/*.smali "$W/sm/$PKG/"
python3 - "$W/sm/$CLS" <<'PY'
import sys
p = sys.argv[1]; s = open(p).read()
m0 = s.index('.method private updateGameEyeCareStatus()V'); m1 = s.index('.end method', m0)
body = s[m0:m1]
call = '    invoke-static {v1, v0}, Lcom/android/server/display/util/OplusDisplayPanelFeatureHelper;->setDisplayPanelFeatureValue(II)V\n'
assert body.count('const/16 v1, 0xe4') == 1 and body.count(call) == 1, "updateGameEyeCareStatus() does not look as expected"
body = body.replace(call, call + '\n    invoke-static {v0}, Lcom/android/server/display/color/feature/PipaGameEyeCare;->set(I)V\n')
open(p, 'w').write(s[:m0] + body + s[m1:])
PY
java -jar "$SMALI/smali-2.5.2.jar" a -j 1 -a 36 "$W/sm" -o "$W/$DEX"

python3 - "$IN" "$OUT" "$W/$DEX" "$DEX" <<'PY'
import sys, zipfile
src, dst, dex, name = sys.argv[1:]
with zipfile.ZipFile(src) as zi, zipfile.ZipFile(dst + ".tmp", "w") as zo:
    for e in zi.infolist():
        data = open(dex, "rb").read() if e.filename == name else zi.read(e)
        n = zipfile.ZipInfo(e.filename, e.date_time); n.compress_type = e.compress_type; n.external_attr = e.external_attr
        zo.writestr(n, data)
PY
"$BT/zipalign" -f -p 4 "$OUT.tmp" "$OUT"; rm -f "$OUT.tmp"
"$BT/zipalign" -c -p 4 "$OUT" >/dev/null && echo "ok: $OUT ($DEX) $(md5sum < "$OUT" | cut -c1-32)"
