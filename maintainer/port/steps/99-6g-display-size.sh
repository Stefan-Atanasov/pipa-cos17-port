#!/bin/sh
# 6g (BUGS-TODO 93, tester 2026-11-10): Settings > Display > Display size has more steps (also "Large").
#
# ColorOS Settings (FontDisplayModel.initDisplayDensityArray, SettingsUtils.getCustomDensityValue / isNumeric) reads
# ro.density.screenzoom: 3 or 5 integers with commas, the middle value = the default density. With 3 values the labels
# are small / default / large, with 5 values there are two steps on each side. Without the property Settings uses
# the AOSP DisplayDensityUtils list, which gives no larger step on pipa. The donor and beta4 have no such property.
# * product/etc/build.prop: ro.density.screenzoom=310,340,370,410,450. The middle value must be ro.sf.lcd_density
#   (370; this step checks it). 450 keeps the smallest width at 640 dp (1800 px), so the tablet layout stays.
#   The property has no entry in property_contexts (label default_prop): init loads product props with its own
#   context, and Settings (system_app) can read default_prop.
# * system_ext/etc/build.prop: ro.pipa.port.layer=6g.
# NOT TESTED on the tablet when written (2026-11-10, offline). Live test without a build:
#   su -c 'resetprop -n ro.density.screenzoom 310,340,370,410,450'; am force-stop com.android.settings
set -eu
. "$PORT/lib.sh"
STEP=6g

P_NAME=ro.density.screenzoom
VALUES=310,340,370,410,450
MID=370
echo "== 6g display size steps ($VALUES)"
need_grep "^ro.sf.lcd_density=$MID\$" "$T/system/system/build.prop"
for f in $(find "$T" -maxdepth 4 -name build.prop -type f); do
    forbid_grep "^$P_NAME" "$f"
done
BP=$T/product/etc/build.prop
[ -f "$BP" ] || die "no $BP"
{ cat "$BP"; printf '%s\n' "# pipa port 6g (BUGS-TODO 93): Display size steps for Settings (middle = default density)" \
    "$P_NAME=$VALUES"; } > "$R/build.prop.new"
cat "$R/build.prop.new" > "$BP"   # same inode: label, owner and mode kept
tail -2 "$BP"
need_grep "^$P_NAME=$VALUES\$" "$BP"
set_layer "$STEP"
