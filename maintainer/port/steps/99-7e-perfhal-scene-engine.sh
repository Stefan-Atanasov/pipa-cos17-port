#!/bin/sh
# Step 7e (audit 2 2026-11-16, BUGS 113): the OPPO perf HAL is the UI First scene engine, as on stock OPPO.
# * rules_7e_system_ext.cil: labels the 4.19 boost sysctls the HAL writes (/proc/sys/kernel/{slide_boost_enabled,
#   input_boost_enabled, frame_rate, cpu_multi_thread}; were plain `proc`).
# * rules_7e_vendor.cil: the HAL writes the scene, boost and frame_rate nodes. 6x (scene only) was worse: its other
#   writes failed and it cleared SF's scene bit. With all of them it keeps bit 8 and adds LAUNCH/ANIM.
#   A/B live (traced_heavy x2 after reboot, pt103 vs pt103 + this access): SF Stuffing 68/30 vs 105/174,
#   SF dropped 28/20 vs 29/26, long DRM commits 1953/2398 vs 2222/2602 ms, launcher/SystemUI gfx neutral.
#NEEDS: "$HERE/sepolicy/rules_7e_system_ext.cil" "$HERE/sepolicy/rules_7e_vendor.cil"
set -eu
. "$PORT/lib.sh"
STEP=7e

SE=$T/system_ext/etc/selinux
for f in system_ext_sepolicy.cil system_ext_sepolicy_debug.cil; do
    [ -f "$SE/$f" ] || continue
    forbid_grep "pipa port 7e" "$SE/$f"
    { cat "$SE/$f"; cat "$HERE/sepolicy/rules_7e_system_ext.cil"; } > "$R/$f.new"
    cat "$R/$f.new" > "$SE/$f"; rm -f "$R/$f.new"   # same inode
    echo "edited  system_ext/etc/selinux/$f"
done
need_grep "pipa port 7e" "$SE/system_ext_sepolicy.cil"

CIL=$T/vendor/etc/selinux/vendor_sepolicy.cil
forbid_grep "pipa port 7e" "$CIL"
{ cat "$CIL"; cat "$HERE/sepolicy/rules_7e_vendor.cil"; } > "$R/vendor_sepolicy.cil.new"
cat "$R/vendor_sepolicy.cil.new" > "$CIL"; rm -f "$R/vendor_sepolicy.cil.new"
need_grep "pipa port 7e" "$CIL"
echo "edited  vendor/etc/selinux/vendor_sepolicy.cil"

set_layer "$STEP"
