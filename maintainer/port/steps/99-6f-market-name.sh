#!/bin/sh
# 6f (BUGS-TODO 92, tester 2026-11-10): the device name is "Xiaomi Pad 6", not "OPPO Pad Mini".
#
# The beta4 "board overrides" block in system/build.prop sets ro.vendor.oplus.market.name=OPPO Pad Mini (the donor's
# name). ColorOS shows this value as the device name (Settings > About device; default Bluetooth / share name).
# * Every build.prop that sets ro.vendor.oplus.market.name=OPPO Pad Mini gets "Xiaomi Pad 6": /system/build.prop
#   (porter block) and the donor's my_manifest/build.prop (two lines). The load order of the OPPO my_* files is not
#   known for sure, so no old value stays.
# * NOT changed: ro.product.brand / manufacturer / model (OPPO, OPD2515). The preinstalled HeyTap/OPPO apps, the
#   OPPO feature configs, interconnect and the Netflix identity (3o) need them.
# * NOT changed: ro.product.odm.marketname and ro.product.vendor.marketname. init never loads them (label
#   default_prop, vendor_init has no "set"; BUGS-TODO 83, check of 2026-11-10).
# * A dirty flash keeps the name that Settings stored at the first boot; the user changes it one time in Settings.
# * system_ext/etc/build.prop: ro.pipa.port.layer=6f.
set -eu
. "$PORT/lib.sh"
STEP=6f

echo "== 6f market name Xiaomi Pad 6"
OLD='ro.vendor.oplus.market.name=OPPO Pad Mini'
NEW='ro.vendor.oplus.market.name=Xiaomi Pad 6'
n_files=0
for f in $(grep -rIl --include=build.prop "^$OLD\$" "$T"); do
    c=$(grep -c "^$OLD\$" "$f")
    replace_all "$f" "$OLD" "$NEW" "$c"     # replace_all does not decode \n: plain text, count = line count
    forbid_grep "^$OLD\$" "$f"
    n_files=$((n_files + 1))
done
[ "$n_files" -ge 1 ] || die "no build.prop sets $OLD"
need_grep "^$NEW\$" "$T/system/system/build.prop"
echo "other lines with the old name (not changed):"
grep -rIn --include=build.prop 'OPPO Pad Mini' "$T" 2>/dev/null | grep -v '^[^:]*:[0-9]*:#' | sed "s|^$T/|   |" || true
set_layer "$STEP"
