#!/bin/bash
# Floating windows (user 2026-11-04): with persist.sys.oplus.anim_level 3 or 4 (our launcher animation tier, pipa_port
# ANIM_LEVEL) ColorOS sets AdaptiveSmoothAnimUtils.LIGHT_OS_ANIM_LEVEL = FlexibleWindowUtils$LightOsSpec.IS_LIGHT_OS, and
# FlexibleWindowManagerService.getMaxWinNum(I) returns 1 on a tablet with "light OS": a second floating window closes
# the first. The patch ignores IS_LIGHT_OS there only (the animation uses stay): the window limit is the tablet value
# for every animation tier.
#   patch_float_limit.sh <oplus-services.jar in> <oplus-services.jar out>
# Needs JDK 21, ~/Android/Sdk build-tools 37, tools/smali (2.5.2). Stops on any surprise. smali/baksmali with -j 1.
set -euo pipefail
IN=$(realpath "$1"); OUT=$(realpath -m "$2")
HERE=$(cd "$(dirname "$0")" && pwd)
SMALI=$HERE/../../../tools/smali
SDK=${ANDROID_HOME:-$HOME/Android/Sdk}; BT=$SDK/build-tools/37.0.0
W=$(mktemp -d); trap 'rm -rf "$W"' EXIT
CLS=com/android/server/wm/FlexibleWindowManagerService.smali

unzip -q "$IN" 'classes*.dex' -d "$W"
DEX=
for d in "$W"/classes*.dex; do
    n=$(basename "$d" .dex)
    java -jar "$SMALI/baksmali-2.5.2.jar" d -j 1 -a 36 "$d" -o "$W/sm_$n"
    [ -f "$W/sm_$n/$CLS" ] && DEX=$n.dex
done
[ -n "$DEX" ] || { echo "no FlexibleWindowManagerService in oplus-services.jar"; exit 1; }
SM=$W/sm_${DEX%.dex}
python3 - "$SM/$CLS" <<'PY'
import re, sys
p = sys.argv[1]; s = open(p).read()
head = '.method public getMaxWinNum(I)I\n'
assert s.count(head) == 1, "getMaxWinNum(I)I not found once"
a = s.index(head); b = s.index('.end method', a); body = s[a:b]
pat = re.compile(r'sget-boolean (v\d+), Lcom/android/server/wm/FlexibleWindowUtils\$LightOsSpec;->IS_LIGHT_OS:Z\n')
m = list(pat.finditer(body))
assert len(m) == 1, "IS_LIGHT_OS read in getMaxWinNum not found once (%d)" % len(m)
body = body[:m[0].start()] + 'const/4 %s, 0x0\n' % m[0].group(1) + body[m[0].end():]
open(p, 'w').write(s[:a] + body + s[b:])
print("patched: getMaxWinNum ignores IS_LIGHT_OS (" + m[0].group(1) + ")")
PY
java -jar "$SMALI/smali-2.5.2.jar" a -j 1 -a 36 "$SM" -o "$W/$DEX.new"
python3 - "$IN" "$OUT" "$W/$DEX.new" "$DEX" <<'PY'
import sys, zipfile
src, dst, dex, name = sys.argv[1:]
with zipfile.ZipFile(src) as zi, zipfile.ZipFile(dst + ".tmp", "w") as zo:
    for e in zi.infolist():
        data = open(dex, "rb").read() if e.filename == name else zi.read(e)
        n = zipfile.ZipInfo(e.filename, e.date_time); n.compress_type = e.compress_type; n.external_attr = e.external_attr
        zo.writestr(n, data)
PY
"$BT/zipalign" -f -p 4 "$OUT.tmp" "$OUT"; rm -f "$OUT.tmp"
"$BT/zipalign" -c -p 4 "$OUT" >/dev/null && echo "ok: $OUT $(md5sum < "$OUT" | cut -c1-32)"
