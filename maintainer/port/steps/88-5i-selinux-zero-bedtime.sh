#!/bin/sh
# Phase 5i: SELinux round 2 (user 2026-11-04: "needs to be 0") and the Bedtime restore fix.
#
# * rules_5i_system_ext.cil / rules_5i_vendor.cil from a full capture of pt45 (persist.logd.audit.rate 2000: boot,
#   heavy_mix, cold starts, shade, app starts, screen off/on, idle, a user session). Allow: OPPO UI First and frame
#   boost hints for SurfaceFlinger, bootanim, mediaserver, audioserver, cameraserver and more app domains (the set
#   platform_app/priv_app have), perf HAL ux_state for mediaserver, OPPO game service GPU clock reads, read-only
#   props. dontaudit: diag, debug toggles, df/meminfo probes, third-party app probes (FK Kernel Manager), init -> su
#   (KernelSU). Not allowed on purpose: nandswap reads and page-cluster (swap A/B first), camera perf service calls.
#   Compiled on the tablet with secilc (init flags) exit 0; neverallow check: the same 76 as before.
#   Left: system_server -> ksu setsched (SukiSU's own type, not in the ROM policy).
# * pipa_port service.sh: each Bedtime key is saved and restored on its own. Before, "either key is 1" restored both
#   keys; the Settings switch writes only comfortable_rhythm, so the leftover rhythm_health = 1 made the Eye Protect
#   app switch Bedtime on again when the user left its page.
#NEEDS: "$HERE/sepolicy/rules_5i_system_ext.cil" "$HERE/sepolicy/rules_5i_vendor.cil" "$ROM/pipa_port/service.sh"
set -eu
. "$PORT/lib.sh"
STEP=5i

SE=$T/system_ext/etc/selinux
for f in system_ext_sepolicy.cil system_ext_sepolicy_debug.cil; do
    [ -f "$SE/$f" ] || continue
    forbid_grep "pipa port 5i" "$SE/$f"
    { cat "$SE/$f"; cat "$HERE/sepolicy/rules_5i_system_ext.cil"; } > "$R/$f.new"
    cat "$R/$f.new" > "$SE/$f"; rm -f "$R/$f.new"   # same inode
    echo "edited  system_ext/etc/selinux/$f"
done
need_grep "pipa port 5i" "$SE/system_ext_sepolicy.cil"

CIL=$T/vendor/etc/selinux/vendor_sepolicy.cil
forbid_grep "pipa port 5i" "$CIL"
{ cat "$CIL"; cat "$HERE/sepolicy/rules_5i_vendor.cil"; } > "$R/vendor_sepolicy.cil.new"
cat "$R/vendor_sepolicy.cil.new" > "$CIL"; rm -f "$R/vendor_sepolicy.cil.new"
need_grep "pipa port 5i" "$CIL"
echo "edited  vendor/etc/selinux/vendor_sepolicy.cil"

cat "$ROM/pipa_port/service.sh" > "$T/system_ext/pipa_port/service.sh"   # same inode
need_grep 'BEDTIME_STATE.$k' "$T/system_ext/pipa_port/service.sh"
echo "updated system_ext/pipa_port/service.sh (Bedtime keys restored one by one)"

set_layer "$STEP"
