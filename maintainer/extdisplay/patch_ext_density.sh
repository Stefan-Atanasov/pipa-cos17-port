#!/bin/bash
# BUGS-TODO 54 (user 2026-11-04): ColorOS RootWindowContainerExtImpl.setForcedDisplayInfoIfNeed() gives a connected
# (extended) display the tablet density (370 on pipa) and then a forced logical size with >= 720 dp on the short side
# (a 2560x1440 monitor became 2960x1668 @370: everything too big and scaled). The patch keeps the native size
# (clearForcedDisplaySize) and sets a density from the physical short side: short * 200 / 1440 (1080p -> 150,
# 1440p -> 200, 2160p -> 300; at least 120), like Windows 125 % on a 27" 1440p screen (user choice).
#   patch_ext_density.sh <oplus-services.jar in> <oplus-services.jar out>
# Needs JDK 21, ~/Android/Sdk build-tools 37, tools/smali (2.5.2). Stops on any surprise. smali/baksmali with -j 1.
set -euo pipefail
IN=$(realpath "$1"); OUT=$(realpath -m "$2")
HERE=$(cd "$(dirname "$0")" && pwd)
SMALI=$HERE/../../../tools/smali
SDK=${ANDROID_HOME:-$HOME/Android/Sdk}; BT=$SDK/build-tools/37.0.0
W=$(mktemp -d); trap 'rm -rf "$W"' EXIT
CLS=com/android/server/wm/RootWindowContainerExtImpl.smali

unzip -q "$IN" 'classes*.dex' -d "$W"
DEX=
for d in "$W"/classes*.dex; do
    n=$(basename "$d" .dex)
    java -jar "$SMALI/baksmali-2.5.2.jar" d -j 1 -a 36 "$d" -o "$W/sm_$n"
    [ -f "$W/sm_$n/$CLS" ] && DEX=$(basename "$d")
done
[ -n "$DEX" ] || { echo "no RootWindowContainerExtImpl in oplus-services.jar"; exit 1; }
SM=$W/sm_${DEX%.dex}
python3 - "$SM/$CLS" <<'PY'
import re, sys
p = sys.argv[1]; s = open(p).read()
head = '.method public setForcedDisplayInfoIfNeed(Lcom/android/server/wm/WindowManagerService;Landroid/hardware/display/DisplayManagerInternal;I)V\n'
assert s.count(head) == 1, "setForcedDisplayInfoIfNeed not found once"
a = s.index(head); b = s.index('.end method', a); body = s[a:b]
assert '.registers 24\n' in body, "register count changed"
# externalDisplayInfo is saved in v18 just before; v0 = WMS, v2 = displayId, v7 = density, v5 = -2 (USER_CURRENT)
pat = re.compile(r'(move-object/from16 v18, v5\n(?:\s*\.line \d+\n|\s*\n|\s*\.local[^\n]*\n)*)'
                 r'((?:.*\n){0,40}?)'
                 r'(\s*)invoke-virtual \{v0, v2, v7, v5\}, Lcom/android/server/wm/WindowManagerService;->setForcedDisplayDensityForUser\(III\)V\n'
                 r'((?:\s*\.line \d+\n|\s*\n)*)'
                 r'\s*invoke-virtual \{v0, v2, v1, v4\}, Lcom/android/server/wm/WindowManagerService;->setForcedDisplaySize\(III\)V\n')
m = list(pat.finditer(body))
assert len(m) == 1, "force block not as expected (%d matches)" % len(m)
mid = m[0].group(2)
assert 'const/4 v5, -0x2' in mid and 'v11' not in mid and 'v12' not in mid, "unexpected code before the calls"
ind = m[0].group(3).strip('\n')
new = ''.join(ind + l + '\n' for l in [
    'move-object/from16 v11, v18',
    'invoke-virtual {v11}, Landroid/view/DisplayInfo;->getMode()Landroid/view/Display$Mode;',
    'move-result-object v11',
    'invoke-virtual {v11}, Landroid/view/Display$Mode;->getPhysicalWidth()I',
    'move-result v12',
    'invoke-virtual {v11}, Landroid/view/Display$Mode;->getPhysicalHeight()I',
    'move-result v11',
    'invoke-static {v11, v12}, Ljava/lang/Math;->min(II)I',
    'move-result v11',
    'mul-int/lit8 v11, v11, 0x5',
    'div-int/lit8 v11, v11, 0x24',
    'const/16 v12, 0x78',
    'invoke-static {v11, v12}, Ljava/lang/Math;->max(II)I',
    'move-result v7',
    'invoke-virtual {v0, v2, v7, v5}, Lcom/android/server/wm/WindowManagerService;->setForcedDisplayDensityForUser(III)V',
    'invoke-virtual {v0, v2}, Lcom/android/server/wm/WindowManagerService;->clearForcedDisplaySize(I)V',
])
body = body[:m[0].start()] + m[0].group(1) + mid + new + body[m[0].end():]
# v11/v12 must not be read after this point in the method
tail = body[body.index('clearForcedDisplaySize(I)V'):]
code = '\n'.join(l for l in tail.split('\n') if not l.strip().startswith(('.end local', '.local', '.restart local')))
assert not re.search(r'\b(v11|v12)\b', code), "v11/v12 used later"
open(p, 'w').write(s[:a] + body + s[b:])
print("patched: native size + density from the physical short side")
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
