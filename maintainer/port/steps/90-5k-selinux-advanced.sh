#!/bin/sh
# Phase 5k: last SELinux items from the pt47 advanced capture (camera, recording, split screen, toggles).
#
# * rules_5k_system_ext.cil: frame boost sys_ctrl for HeyTap cloud backup; dontaudit for the OPPO media list service scan of
#   /proc. rules_5k_vendor.cil: dontaudit for the Wi-Fi HAL tombstone dir. secilc exit 0, neverallow: the same 76.
#   Result on pt47 + 5k rules: no denial from ROM domains, apps or root in the normal and advanced captures.
#NEEDS: "$HERE/sepolicy/rules_5k_system_ext.cil" "$HERE/sepolicy/rules_5k_vendor.cil"
set -eu
. "$PORT/lib.sh"
STEP=5k

SE=$T/system_ext/etc/selinux
for f in system_ext_sepolicy.cil system_ext_sepolicy_debug.cil; do
    [ -f "$SE/$f" ] || continue
    forbid_grep "pipa port 5k" "$SE/$f"
    { cat "$SE/$f"; cat "$HERE/sepolicy/rules_5k_system_ext.cil"; } > "$R/$f.new"
    cat "$R/$f.new" > "$SE/$f"; rm -f "$R/$f.new"   # same inode
    echo "edited  system_ext/etc/selinux/$f"
done
need_grep "pipa port 5k" "$SE/system_ext_sepolicy.cil"

CIL=$T/vendor/etc/selinux/vendor_sepolicy.cil
forbid_grep "pipa port 5k" "$CIL"
{ cat "$CIL"; cat "$HERE/sepolicy/rules_5k_vendor.cil"; } > "$R/vendor_sepolicy.cil.new"
cat "$R/vendor_sepolicy.cil.new" > "$CIL"; rm -f "$R/vendor_sepolicy.cil.new"
need_grep "pipa port 5k" "$CIL"
echo "edited  vendor/etc/selinux/vendor_sepolicy.cil"

set_layer "$STEP"
