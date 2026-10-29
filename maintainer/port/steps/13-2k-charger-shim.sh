#!/bin/sh
# Phase 2k: "battery may not be genuine" dialog fixed, on top of 2j (system_ext only).
#
# SystemUI's NotificationUtil.isBatteryOriginal() is OplusBatteryManager.getPsyBatteryHmac() != 0, answered by the
# charger shim (pipa_port, the original developer's binary-only chargershim.jar), which returned 0 for
# getPsyBatteryHmac and getBattAuthenticate. port-rom/pipa_port/chargershim.jar is now patched to return 1
# (maintainer/chargershim/patch_auth.py, original kept as chargershim-orig.jar). BUGS-TODO 12.
#
# Old layer script: build_beta5_2k.sh
#NEEDS: "$ROM/pipa_port/chargershim.jar"
set -eu
. "$PORT/lib.sh"

SE=$T/system_ext

echo "== pipa_port charger shim"
J=$SE/pipa_port/chargershim.jar
# The old layer stopped here when the jar was already the patched one. In one tree, step 2e has copied
# the CURRENT port-rom (patched jar) already, so equal is the normal case: only say so, then write it.
if cmp -s "$ROM/pipa_port/chargershim.jar" "$J"; then echo "note: tree jar already equals port-rom (2e copied the current port-rom)"; fi
cat "$ROM/pipa_port/chargershim.jar" > "$J"   # in place: owner, mode and SELinux label stay
md5sum "$J"

