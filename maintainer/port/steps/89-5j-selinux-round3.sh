#!/bin/sh
# Phase 5j: SELinux round 3 from the pt46 capture (user 2026-11-04: "needs to be 0").
#
# * rules_5j_system_ext.cil: UI First ux_task_app for cameraserver and the media provider app, network MTU read,
#   dex2oat dir search in /data; dontaudit for priv app cgroup quota reads (a neverallow forbids the allow), nandswap
#   df on firmware mounts, third-party emulator/root checks.
# * rules_5j_vendor.cil: dontaudit for the perf HAL UI First scene writes (~2/s since 5h). Not allowed: pipa_port owns
#   the node (SF_BIG_CORES); allowing it is an A/B test for later (BUGS 70).
#   secilc on the tablet (init flags) exit 0; neverallow check: the same 76 as before.
#NEEDS: "$HERE/sepolicy/rules_5j_system_ext.cil" "$HERE/sepolicy/rules_5j_vendor.cil"
set -eu
. "$PORT/lib.sh"
STEP=5j

SE=$T/system_ext/etc/selinux
for f in system_ext_sepolicy.cil system_ext_sepolicy_debug.cil; do
    [ -f "$SE/$f" ] || continue
    forbid_grep "pipa port 5j" "$SE/$f"
    { cat "$SE/$f"; cat "$HERE/sepolicy/rules_5j_system_ext.cil"; } > "$R/$f.new"
    cat "$R/$f.new" > "$SE/$f"; rm -f "$R/$f.new"   # same inode
    echo "edited  system_ext/etc/selinux/$f"
done
need_grep "pipa port 5j" "$SE/system_ext_sepolicy.cil"

CIL=$T/vendor/etc/selinux/vendor_sepolicy.cil
forbid_grep "pipa port 5j" "$CIL"
{ cat "$CIL"; cat "$HERE/sepolicy/rules_5j_vendor.cil"; } > "$R/vendor_sepolicy.cil.new"
cat "$R/vendor_sepolicy.cil.new" > "$CIL"; rm -f "$R/vendor_sepolicy.cil.new"
need_grep "pipa port 5j" "$CIL"
echo "edited  vendor/etc/selinux/vendor_sepolicy.cil"

set_layer "$STEP"
