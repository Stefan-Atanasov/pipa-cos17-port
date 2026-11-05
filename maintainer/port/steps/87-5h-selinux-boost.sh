#!/bin/sh
# Phase 5h: SELinux clean-up from the pt44 boot logs (user 2026-11-04: go through each denial, choose the best).
#
# * system_ext/etc/selinux/system_ext_sepolicy{,_debug}.cil + sepolicy/rules_5h_system_ext.cil: frame boost hints
#   for the photo picker, permission dialogs, media provider and mediaserver; read-only props (Play services Nearby,
#   system_server); small system_app reads. dontaudit for probes with no use (thread_info_ctrl: no effect in the 4.19
#   kernel), nandswap swap reads (silenced, not allowed: BUGS 70 swap A/B first), noatsecure on service starts.
# * vendor/etc/selinux/vendor_sepolicy.cil + sepolicy/rules_5h_vendor.cil: the OPPO part of the perf HAL may mark
#   system_server and cameraserver threads as UX (ux_state, UI First); dontaudit for the diag QRTR socket retries,
#   the factory Bluetooth MAC read (a new MAC breaks pen and keyboard pairing) and the bspFwUpdate firmware dir.
#   Compiled on the tablet with secilc (init flags, exit 0); neverallow check: no new violation (76 before and after,
#   all from the donor/base policy).
#NEEDS: "$HERE/sepolicy/rules_5h_system_ext.cil" "$HERE/sepolicy/rules_5h_vendor.cil"
set -eu
. "$PORT/lib.sh"
STEP=5h

SE=$T/system_ext/etc/selinux
for f in system_ext_sepolicy.cil system_ext_sepolicy_debug.cil; do
    [ -f "$SE/$f" ] || continue
    forbid_grep "pipa port 5h" "$SE/$f"
    { cat "$SE/$f"; cat "$HERE/sepolicy/rules_5h_system_ext.cil"; } > "$R/$f.new"
    cat "$R/$f.new" > "$SE/$f"; rm -f "$R/$f.new"   # same inode
    echo "edited  system_ext/etc/selinux/$f"
done
need_grep "pipa port 5h" "$SE/system_ext_sepolicy.cil"

CIL=$T/vendor/etc/selinux/vendor_sepolicy.cil
forbid_grep "pipa port 5h" "$CIL"
need_grep "^(type vendor_hal_perf_default)" "$CIL"
{ cat "$CIL"; cat "$HERE/sepolicy/rules_5h_vendor.cil"; } > "$R/vendor_sepolicy.cil.new"
cat "$R/vendor_sepolicy.cil.new" > "$CIL"; rm -f "$R/vendor_sepolicy.cil.new"
need_grep "pipa port 5h" "$CIL"
echo "edited  vendor/etc/selinux/vendor_sepolicy.cil"

set_layer "$STEP"
