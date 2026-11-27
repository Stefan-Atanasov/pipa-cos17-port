#!/bin/bash
# Tablet panorama on 8 GB (user 2026-11-27, BUGS 216): OplusPanoramaWorkBranchController.onAmsReady sets
# OplusPanoramaWorkBranchUtil.sRamSizeSupport = (MemoryInfo.totalMem / 2^30 > 8.0). pipa has 8 GB, the kernel reports
# 7.41 GiB, so ColorOS takes the "low RAM tablet" path: hasFoldPanoramaWorkFeature() is true, the fold variant of
# panorama runs, FlexibleWindowUtils.getMaxFlexibleTaskNum() = 2 floating windows. The patch lowers the threshold to
# 6.0 GiB (one const-wide/high16, same size): pipa takes OPPO's tablet panorama path (4 floating windows and the
# four-finger gestures, like the OPPO Pad / Find N tablets with more RAM).
#   patch_panorama_ram.sh <oplus-services.jar in> <oplus-services.jar out>
# Needs JDK 21, ~/Android/Sdk build-tools 37, tools/smali (2.5.2). Stops on any surprise. smali/baksmali with -j 1.
set -euo pipefail
IN=$(realpath "$1"); OUT=$(realpath -m "$2")
HERE=$(cd "$(dirname "$0")" && pwd)
SMALI=$HERE/../../../tools/smali
SDK=${ANDROID_HOME:-$HOME/Android/Sdk}; BT=$SDK/build-tools/37.0.0
W=$(mktemp -d); trap 'rm -rf "$W"' EXIT
CLS=com/android/server/wm/OplusPanoramaWorkBranchController.smali

unzip -q "$IN" 'classes*.dex' -d "$W"
DEX=
for d in "$W"/classes*.dex; do
    n=$(basename "$d" .dex)
    java -jar "$SMALI/baksmali-2.5.2.jar" d -j 1 -a 36 "$d" -o "$W/sm_$n"
    [ -f "$W/sm_$n/$CLS" ] && DEX=$n.dex
done
[ -n "$DEX" ] || { echo "no OplusPanoramaWorkBranchController in oplus-services.jar"; exit 1; }
SM=$W/sm_${DEX%.dex}
python3 - "$SM/$CLS" <<'PY'
import re, sys
p = sys.argv[1]; s = open(p).read()
head = '.method public onAmsReady(Landroid/app/IActivityManager;)V\n'
assert s.count(head) == 1, "onAmsReady(IActivityManager) not found once"
a = s.index(head); b = s.index('.end method', a); body = s[a:b]
assert 'OplusPanoramaWorkBranchUtil;->setRamSizeSupport(Z)V' in body, "setRamSizeSupport call not in onAmsReady"
assert body.count('Landroid/app/ActivityManager$MemoryInfo;->totalMem:J') == 2, "totalMem reads changed"
pat = re.compile(r'const-wide/high16 (v\d+), 0x4020000000000000L(\s*# 8\.0)?\n(\s*)cmpl-double ')
m = list(pat.finditer(body))
assert len(m) == 1, "8.0 GiB compare in onAmsReady not found once (%d)" % len(m)
new = 'const-wide/high16 %s, 0x4018000000000000L    # 6.0\n%scmpl-double ' % (m[0].group(1), m[0].group(3))
body = body[:m[0].start()] + new + body[m[0].end():]
open(p, 'w').write(s[:a] + body + s[b:])
print("patched: onAmsReady RAM threshold 8.0 -> 6.0 GiB (" + m[0].group(1) + ")")
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
