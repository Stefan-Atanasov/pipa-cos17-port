#!/bin/sh
# Step 6w (audit 2026-11-15, port-work/codex/audit-20261115/REPORT.md): restore stock OPPO functions blocked by SELinux.
# * rules_6w_vendor.cil: the OPPO perf HAL pauses hybridswapd during app launches (hybridswap_swapd_pause, sysfs_zram)
#   and reads /proc/oplus_healthinfo. Both were denied since walt-r24 (hybridswap) / always (healthinfo).
# * rules_6w_system_ext.cil: OPPO init.oplus.nandswap.sh capabilities (chmod of hybridswap nodes) and loop sysfs reads.
#   secilc on the tablet (secil_test.sh) exit 0; neverallow count 76 (same as before).
#NEEDS: "$HERE/sepolicy/rules_6w_system_ext.cil" "$HERE/sepolicy/rules_6w_vendor.cil"
set -eu
. "$PORT/lib.sh"
STEP=6w

SE=$T/system_ext/etc/selinux
for f in system_ext_sepolicy.cil system_ext_sepolicy_debug.cil; do
    [ -f "$SE/$f" ] || continue
    forbid_grep "pipa port 6w" "$SE/$f"
    { cat "$SE/$f"; cat "$HERE/sepolicy/rules_6w_system_ext.cil"; } > "$R/$f.new"
    cat "$R/$f.new" > "$SE/$f"; rm -f "$R/$f.new"   # same inode
    echo "edited  system_ext/etc/selinux/$f"
done
need_grep "pipa port 6w" "$SE/system_ext_sepolicy.cil"

CIL=$T/vendor/etc/selinux/vendor_sepolicy.cil
forbid_grep "pipa port 6w" "$CIL"
{ cat "$CIL"; cat "$HERE/sepolicy/rules_6w_vendor.cil"; } > "$R/vendor_sepolicy.cil.new"
cat "$R/vendor_sepolicy.cil.new" > "$CIL"; rm -f "$R/vendor_sepolicy.cil.new"
need_grep "pipa port 6w" "$CIL"
echo "edited  vendor/etc/selinux/vendor_sepolicy.cil"

set_layer "$STEP"
