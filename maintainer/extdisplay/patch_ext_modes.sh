#!/bin/bash
# BUGS-TODO 54: external display stays at 60 Hz. Android 17 LocalDisplayAdapter.LocalDisplayDevice
# .updateDisplayModesLocked() gives every mode of a non-first display FLAG_SIZE_OVERRIDE (0x2) when the SurfaceFlinger
# flag synced_resolution_switch is off (it is not in this build's aconfig storage, so it reads false). For a mode with
# that flag, DisplayModeDirector.updateUserSettingDisplayPreferredMode() votes only a render rate range (0..rate), no
# physical refresh rate and no size, so the user preferred mode (e.g. 2560x1440@120) never wins over the 60 Hz default.
# The patch sets sizeOverrideEnabled to false (the Android 16 behaviour): the preferred-mode vote is physical rate +
# size again. Internal display: not changed (it never had the flag).
#   patch_ext_modes.sh <services.jar in> <services.jar out>
# Needs JDK 21, ~/Android/Sdk build-tools 37, tools/smali (2.5.2). Stops on any surprise. smali/baksmali with -j 1.
set -euo pipefail
IN=$(realpath "$1"); OUT=$(realpath -m "$2")
HERE=$(cd "$(dirname "$0")" && pwd)
SMALI=$HERE/../../../tools/smali
SDK=${ANDROID_HOME:-$HOME/Android/Sdk}; BT=$SDK/build-tools/37.0.0
W=$(mktemp -d); trap 'rm -rf "$W"' EXIT
CLS='com/android/server/display/LocalDisplayAdapter$LocalDisplayDevice.smali'

unzip -q "$IN" 'classes*.dex' -d "$W"
DEX=
for d in "$W"/classes*.dex; do
    java -jar "$SMALI/baksmali-2.5.2.jar" d -j 1 -a 36 "$d" -o "$W/sm_$(basename "$d" .dex)"
    [ -f "$W/sm_$(basename "$d" .dex)/$CLS" ] && DEX=$(basename "$d")
done
[ -n "$DEX" ] || { echo "no LocalDisplayDevice in services.jar"; exit 1; }
SM=$W/sm_${DEX%.dex}
python3 - "$SM/$CLS" <<'PY'
import re, sys
p = sys.argv[1]; s = open(p).read()
head = '.method private updateDisplayModesLocked(Landroid/view/SurfaceControl$DynamicDisplayInfo;Landroid/view/SurfaceControl$DesiredDisplayModeSpecs;Z)Z\n'
assert s.count(head) == 1, "updateDisplayModesLocked not found once"
a = s.index(head); b = s.index('.end method', a); body = s[a:b]
pat = re.compile(r'(invoke-static \{\}, Lcom/android/internal/hidden_from_bootclasspath/com/android/graphics/surfaceflinger/flags/Flags;->syncedResolutionSwitch\(\)Z\n\n'
                 r'\s*move-result (v\d+)\n\n\s*if-nez \2, :cond_\w+\n\n(?:\s*\.line \d+\n)?\s*const/4 \2, )0x1\n')
m = list(pat.finditer(body))
assert len(m) == 1, "sizeOverride block not as expected (%d matches)" % len(m)
body = body[:m[0].start()] + m[0].group(1) + '0x0\n' + body[m[0].end():]
# the register must go to createMode(...ZZ) as the 4th argument later in the method
assert 'DisplayModeFactory;->createMode(Landroid/view/SurfaceControl$DisplayMode;[FZZ)' in body, "createMode call moved"
open(p, 'w').write(s[:a] + body + s[b:])
print("patched: sizeOverrideEnabled = false (" + m[0].group(2) + ")")
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
