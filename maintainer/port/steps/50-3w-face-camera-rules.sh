#!/bin/sh
# Phase 3w: face enrollment and face unlock work with pipa_port enforcing (system_ext only).
#
# The face HAL starts a camera worker in the pipa_port domain (cameraserver, graphics allocator/mapper over HIDL,
# display service). The 3g rule capture never ran it: since 3g the enroll preview was black, "Add now" hung and face
# unlock failed. sepolicy/pipa_port_rules.cil has 27 rules (block ";; 3w"): 19 from a permissive window on 2026-10-30
# (enroll + unlock worked, onAuthenticated true), 5 from an enforcing boot with audit rate 2000 (pen_keys `input`,
# face worker extras, enroll preview buffers to Settings = system_app binder transfer, preview fences from
# SurfaceFlinger and the composer: the preview froze after a rotation).
# * port-rom keys.conf: pen back button (PAGEUP = STYLUS_BUTTON_SECONDARY in the vendor .kl) pageup=none: the AOSP
#   stylus button for apps, no screenshot (user wish). Copied by the earlier port-rom steps; checked here. Step 3g puts the whole rule file into the CIL; this step
# checks that the 3w block is there. Compiled on the tablet with secilc (exit 0).
#NEEDS: "$HERE/sepolicy/pipa_port_rules.cil" "$ROM/pipa_port/keys.conf"
set -eu
. "$PORT/lib.sh"

CIL=$T/system_ext/etc/selinux/system_ext_sepolicy.cil
need_grep "(allow pipa_port hwservicemanager_prop (file (getattr map open read)))" "$CIL"
need_grep "(allow pipa_port cameraserver (binder (call transfer)))" "$CIL"
need_grep "(allow pipa_port fwk_camera_hwservice (hwservice_manager (find)))" "$CIL"
need_grep "(allow pipa_port system_app (binder (call transfer)))" "$CIL"
need_grep "(allow pipa_port input_service (service_manager (find)))" "$CIL"
need_grep "(allow pipa_port surfaceflinger (fd (use)))" "$CIL"
cat "$ROM/pipa_port/keys.conf" > "$T/system_ext/pipa_port/keys.conf"
need_grep "^pageup=none" "$T/system_ext/pipa_port/keys.conf"
echo "face camera worker rules are in system_ext_sepolicy.cil"
