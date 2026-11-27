#!/bin/bash
# oplus-services.jar patch (2026-11-26, BUGS 203): back gesture from the far screen edge at Low resolution.
# SystemUI (InvalidRegionControl) and the launcher send their gesture touch zones through
# OplusWindowManager.updateInvalidRegion -> InputManagerServiceExtImpl.updateInvalidRegion -> native
# (nativeUpdateInvalidRegion), in logical display coordinates. The native check compares them with panel (physical)
# coordinates. With a forced display size (9g Low = wm size 1440x2304 on the 1800x2880 panel) a zone at the origin side
# still matches, a zone at the far side does not (logical 1440/2304 vs physical 1800/2880): in landscape the right-edge
# back swipe never starts (portrait: right edge and bottom too). Stock OPPO switches resolution by a real display mode
# (logical = physical), so it never sees this.
# Patch: updateInvalidRegion first calls the new static pipaScaleRegion(List): if the default display's physical size
# differs from its logical size, every RectF is scaled by physical/logical (one factor; Low = 1.25). Native
# resolution: no change. Runs only when a zone list is sent (config/rotation changes), not per touch.
#   patch_invalid_region.sh <oplus-services.jar in> <oplus-services.jar out>
# Needs JDK 21, ~/Android/Sdk build-tools 37, tools/smali (2.5.2). Stops on any surprise. smali/baksmali with -j 1.
set -euo pipefail
IN=$(realpath "$1"); OUT=$(realpath -m "$2")
HERE=$(cd "$(dirname "$0")" && pwd)
SMALI=$HERE/../../../tools/smali
SDK=${ANDROID_HOME:-$HOME/Android/Sdk}; BT=$SDK/build-tools/37.0.0
W=$(mktemp -d); trap 'rm -rf "$W"' EXIT
CLS=com/android/server/input/InputManagerServiceExtImpl.smali
unzip -q "$IN" 'classes*.dex' -d "$W"
DEX=
for d in "$W"/classes*.dex; do
    n=$(basename "$d" .dex)
    java -jar "$SMALI/baksmali-2.5.2.jar" d -j 1 -a 36 "$d" -o "$W/sm_$n"
    if [ -f "$W/sm_$n/$CLS" ]; then DEX=$n; break; fi
    rm -rf "$W/sm_$n"
done
[ -n "$DEX" ] || { echo "InputManagerServiceExtImpl not found"; exit 1; }
python3 -I - "$W/sm_$DEX/$CLS" <<'PY'
import sys
f = sys.argv[1]
s = open(f).read()
assert 'pipaScaleRegion' not in s, 'already patched'
head = '.method public updateInvalidRegion(Ljava/lang/String;Ljava/util/List;ZZLandroid/os/Bundle;)Z\n'
assert s.count(head) == 1, 'updateInvalidRegion not found once'
a = s.index(head); e = s.index('.end method', a)
p = s.index('    .end annotation\n', a); assert p < e, 'no annotation end in updateInvalidRegion'
p += len('    .end annotation\n')
call = ('\n    # pipa (BUGS 203): zones in logical coordinates -> panel coordinates under a forced display size\n'
        '    invoke-static/range {p2 .. p2}, Lcom/android/server/input/InputManagerServiceExtImpl;->pipaScaleRegion(Ljava/util/List;)V\n')
s = s[:p] + call + s[p:]
assert s.count('nativeUpdateInvalidRegion(JLjava/lang/String;Landroid/os/Bundle;[Landroid/graphics/RectF;ZZ)Z') >= 2
helper = '''
.method private static pipaScaleRegion(Ljava/util/List;)V
    .registers 7

    if-eqz p0, :pipa_done

    :try_start_pipa
    const-class v0, Landroid/hardware/display/DisplayManagerInternal;
    invoke-static {v0}, Lcom/android/server/LocalServices;->getService(Ljava/lang/Class;)Ljava/lang/Object;
    move-result-object v0
    check-cast v0, Landroid/hardware/display/DisplayManagerInternal;
    if-eqz v0, :pipa_done
    const/4 v1, 0x0
    invoke-virtual {v0, v1}, Landroid/hardware/display/DisplayManagerInternal;->getDisplayInfo(I)Landroid/view/DisplayInfo;
    move-result-object v0
    if-eqz v0, :pipa_done
    iget v1, v0, Landroid/view/DisplayInfo;->logicalWidth:I
    iget v2, v0, Landroid/view/DisplayInfo;->logicalHeight:I
    invoke-static {v1, v2}, Ljava/lang/Math;->max(II)I
    move-result v1
    invoke-virtual {v0}, Landroid/view/DisplayInfo;->getMode()Landroid/view/Display$Mode;
    move-result-object v0
    if-eqz v0, :pipa_done
    invoke-virtual {v0}, Landroid/view/Display$Mode;->getPhysicalWidth()I
    move-result v2
    invoke-virtual {v0}, Landroid/view/Display$Mode;->getPhysicalHeight()I
    move-result v3
    invoke-static {v2, v3}, Ljava/lang/Math;->max(II)I
    move-result v2
    if-lez v1, :pipa_done
    if-eq v1, v2, :pipa_done
    int-to-float v2, v2
    int-to-float v1, v1
    div-float/2addr v2, v1
    invoke-interface {p0}, Ljava/util/List;->iterator()Ljava/util/Iterator;
    move-result-object v3

    :pipa_loop
    invoke-interface {v3}, Ljava/util/Iterator;->hasNext()Z
    move-result v4
    if-eqz v4, :pipa_done
    invoke-interface {v3}, Ljava/util/Iterator;->next()Ljava/lang/Object;
    move-result-object v4
    check-cast v4, Landroid/graphics/RectF;
    if-eqz v4, :pipa_loop
    iget v5, v4, Landroid/graphics/RectF;->left:F
    mul-float/2addr v5, v2
    iput v5, v4, Landroid/graphics/RectF;->left:F
    iget v5, v4, Landroid/graphics/RectF;->top:F
    mul-float/2addr v5, v2
    iput v5, v4, Landroid/graphics/RectF;->top:F
    iget v5, v4, Landroid/graphics/RectF;->right:F
    mul-float/2addr v5, v2
    iput v5, v4, Landroid/graphics/RectF;->right:F
    iget v5, v4, Landroid/graphics/RectF;->bottom:F
    mul-float/2addr v5, v2
    iput v5, v4, Landroid/graphics/RectF;->bottom:F
    goto :pipa_loop
    :try_end_pipa
    .catch Ljava/lang/Exception; {:try_start_pipa .. :try_end_pipa} :pipa_done

    :pipa_done
    return-void
.end method
'''
s = s.rstrip('\n') + '\n' + helper
open(f, 'w').write(s)
print('InputManagerServiceExtImpl: pipaScaleRegion added')
PY
java -jar "$SMALI/smali-2.5.2.jar" a -j 1 -a 36 "$W/sm_$DEX" -o "$W/$DEX.dex.new"
python3 -I - "$IN" "$OUT" "$W" "$DEX" <<'PY'
import sys, zipfile, os
src, dst, w, name = sys.argv[1:]
new = {name + '.dex': os.path.join(w, name + '.dex.new')}
with zipfile.ZipFile(src) as zi, zipfile.ZipFile(dst + '.tmp', 'w') as zo:
    for e in zi.infolist():
        data = open(new[e.filename], 'rb').read() if e.filename in new else zi.read(e)
        n = zipfile.ZipInfo(e.filename, e.date_time); n.compress_type = e.compress_type; n.external_attr = e.external_attr
        zo.writestr(n, data)
PY
"$BT/zipalign" -f -p 4 "$OUT.tmp" "$OUT"; rm -f "$OUT.tmp"
"$BT/zipalign" -c -p 4 "$OUT" >/dev/null && echo "ok: $OUT $(md5sum < "$OUT" | cut -c1-32)"
