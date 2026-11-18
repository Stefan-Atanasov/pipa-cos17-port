#!/bin/sh
# Step 7m (BUGS 93, tester + user 2026-11-17: "Display size needs a Large option, most good ports have it"):
# ColorOS Settings shows only Small/Standard on devices with oplus.software.windowmode.compact (stock OPPO tablets too).
# The feature also drives the real compact-window mode, so it stays; only Settings' Display-size code is told "no
# compact window" (maintainer/displaysize/patch_settings_display_large.py: 10 call sites -> const 0, same size, in place:
# ScreenZoom* page/radio/preview, FontDisplayModel, SettingsUtils.normalizeScreenZoomSettingsIndex). Then the phone
# path applies: Small / Standard / Large = ro.density.screenzoom[mid-1], [mid], [last]. 6g's 5-value list would make
# Large = 450 (+22 %); this step sets 340,370,410 (Large = 410 = old 7g size, near HyperOS 400).
# Live-tested 2026-11-17 on pt112 (bind mount): Large -> forced density 410, index 2 kept after reopening; Standard -> 370.
# The launcher lays out from the boot density (ro.sf.lcd_density 370), so Large does not bring back BUGS 125.
#NEEDS: "$HERE/displaysize/patch_settings_display_large.py" "$HERE/jar-edits/venv/bin/python"
set -eu
. "$PORT/lib.sh"
STEP=7m
echo "== 7m Display size: Large option"
A=$T/system_ext/priv-app/Settings/Settings.apk
[ -f "$A" ] || die "no $A"
"$HERE/jar-edits/venv/bin/python" -I "$HERE/displaysize/patch_settings_display_large.py" "$A" "$R/Settings.7m.apk" \
    > "$R/7m.log" 2>&1 || { grep -v DEBUG "$R/7m.log"; die "Settings patch failed"; }
grep -v DEBUG "$R/7m.log"
grep -q "total 10 call sites patched" "$R/7m.log" || die "expected 10 call sites (other Settings version?)"
cat "$R/Settings.7m.apk" > "$A"   # in place: owner, mode and SELinux label stay
rm -f "$R/Settings.7m.apk" "$R/7m.log"
rm -rf "$T/system_ext/priv-app/Settings/oat"

BP=$T/product/etc/build.prop
OLDV=310,340,370,410,450; NEWV=340,370,410
need_grep "^ro.density.screenzoom=$OLDV\$" "$BP"
sed "s/^ro.density.screenzoom=$OLDV\$/ro.density.screenzoom=$NEWV/" "$BP" > "$R/build.prop.new"
cat "$R/build.prop.new" > "$BP"   # same inode: label, owner and mode kept
need_grep "^ro.density.screenzoom=$NEWV\$" "$BP"
echo "edited  product/etc/build.prop ro.density.screenzoom=$NEWV"
set_layer "$STEP"
