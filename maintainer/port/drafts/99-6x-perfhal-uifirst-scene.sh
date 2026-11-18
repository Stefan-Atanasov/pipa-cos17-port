#!/bin/sh
# Step 6x (audit 2026-11-15, BUGS 113): the OPPO perf HAL owns the UI First scene as on stock (A/B vs the 2l SF_BIG_CORES write).
# rules_6x_vendor.cil: allow the perf HAL write (5j dontaudit stays harmless). rules_6x_system_ext.cil: nandswap loop scheduler.
# secilc on the tablet exit 0; neverallow 76.
#NEEDS: "$HERE/sepolicy/rules_6x_system_ext.cil" "$HERE/sepolicy/rules_6x_vendor.cil"
set -eu
. "$PORT/lib.sh"
STEP=6x

SE=$T/system_ext/etc/selinux
for f in system_ext_sepolicy.cil system_ext_sepolicy_debug.cil; do
    [ -f "$SE/$f" ] || continue
    forbid_grep "pipa port 6x" "$SE/$f"
    { cat "$SE/$f"; cat "$HERE/sepolicy/rules_6x_system_ext.cil"; } > "$R/$f.new"
    cat "$R/$f.new" > "$SE/$f"; rm -f "$R/$f.new"   # same inode
    echo "edited  system_ext/etc/selinux/$f"
done
need_grep "pipa port 6x" "$SE/system_ext_sepolicy.cil"

CIL=$T/vendor/etc/selinux/vendor_sepolicy.cil
forbid_grep "pipa port 6x" "$CIL"
{ cat "$CIL"; cat "$HERE/sepolicy/rules_6x_vendor.cil"; } > "$R/vendor_sepolicy.cil.new"
cat "$R/vendor_sepolicy.cil.new" > "$CIL"; rm -f "$R/vendor_sepolicy.cil.new"
need_grep "pipa port 6x" "$CIL"
echo "edited  vendor/etc/selinux/vendor_sepolicy.cil"

set_layer "$STEP"
