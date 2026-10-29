#!/bin/sh
# Phase 3g: fixes for 3f's enforcing pipa_port (BUGS-TODO 12), on top of 3f (system_ext only).
#
# 3f booted enforcing and showed rules the capture could not see:
# * init checks property sets in user space and logs nothing for a permissive domain: ctl.stop$xiaomi-keyboard and
#   ctl.stop$vendor.facehal were denied (the keyboard daemon kept running: idle drain). Now set rules for ctl_*,
#   vendor_radio_prop, vendor_default_prop, system_prop.
# * one-time paths: early.sh package-cache clear (denied in 3f), face HAL copy to /data, idmap, /metadata cleanup.
#   Tested live under enforcing 2026-10-28 (ksud rules; the property rules can only be checked by a boot).
# * system_ext/pipa_port/facehal/VERSION includes libpipa_eyeguard.so: the /data copy of the face HAL is refreshed and
#   the eye-ROI guard (item 8) is loaded (3f did not refresh the copy).
# * system_ext/etc/build.prop: ro.pipa.port.layer=3g.
#
# Old layer script: build_beta5_3g.sh
#NEEDS: "$HERE/sepolicy/pipa_port_enforce.py" "$HERE/sepolicy/pipa_port_rules.cil" "$ROM/pipa_port/facehal/VERSION" "$ROM/pipa_port/service.sh"
set -eu
. "$PORT/lib.sh"
STEP=3g

SE=$T/system_ext

echo "== 12: pipa_port enforcing (rules from sepolicy/pipa_port_rules.cil, on the 3e CIL)"
for f in etc/selinux/system_ext_sepolicy.cil etc/selinux/system_ext_sepolicy_debug.cil; do
    [ -f "$SE/$f" ] || { echo "skip    $f (absent)"; continue; }
    # the old 3g read the 3e tree; step 3f saved that state in $ORIG
    [ -f "$ORIG/${f##*/}" ] || die "no $ORIG/${f##*/}: step 3f did not run in this tree"
    cat "$ORIG/${f##*/}" > "$SE/$f"   # same inode: label kept
    if grep -q "(type pipa_port)" "$SE/$f"; then python3 -I "$HERE/sepolicy/pipa_port_enforce.py" "$SE/$f"; fi
done
if grep -q "(typepermissive pipa_port)" "$SE/etc/selinux/system_ext_sepolicy.cil"; then echo "still permissive"; exit 1; fi
need_grep "ctl_stop_prop (property_service" "$SE/etc/selinux/system_ext_sepolicy.cil"

echo "== 8: face HAL VERSION (refreshes the /data copy)"
cat "$ROM/pipa_port/facehal/VERSION" > "$SE/pipa_port/facehal/VERSION"
need_grep libpipa_eyeguard.so "$SE/pipa_port/facehal/VERSION"
cmp -s "$ROM/pipa_port/service.sh" "$SE/pipa_port/service.sh" || die "service.sh differs from port-rom (3f copied it)"

echo "== system_ext build.prop: ro.pipa.port.layer=$STEP"
set_layer "$STEP"

