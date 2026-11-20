#!/bin/sh
# Phase 8j (2026-11-20): services.jar, maintainer/services/patch_back_wfd.sh.
# * BUGS 157: two-pane Settings, search keyboard open, back from the left edge closed all of Settings. OPPO skips
#   predictive back there (keyboard + activity embedding) and injects KEYCODE_BACK; AOSP PhoneWindowManager then calls
#   WindowManagerService.moveFocusToAdjacentEmbeddedWindow, which moved focus to the other pane (no keyboard check).
#   Patch: no focus move while the keyboard shows for the focused window. Live test pt137: both edges close only the
#   keyboard; without the keyboard, back leaves two-pane Settings as before.
# * BUGS 158: Miracast to Windows did not reconnect until the saved Wi-Fi Direct group was deleted (Windows makes a
#   new key each session; PSK failure; the leftover group in p2p_supplicant.conf blocks the fresh pairing).
#   Patch: WifiDisplayController connects with WifiP2pConfig.netId = -1 (temporary group, nothing saved).
# * No prebuilt oat for services.jar in the image (checked in the step).
set -eu
. "$PORT/lib.sh"
STEP=8j
J=$T/system/system/framework/services.jar
[ -f "$J" ] || die "no $J"
if ls "$T/system/system/framework/oat"/*/services.* >/dev/null 2>&1; then die "prebuilt oat for services exists"; fi
ANDROID_HOME=${ANDROID_HOME:-/home/${OWNER%%:*}/Android/Sdk} bash "$HERE/services/patch_back_wfd.sh" "$J" "$R/services.jar.new"
cat "$R/services.jar.new" > "$J"   # in place: owner, mode and SELinux label stay
rm -f "$R/services.jar.new"
md5sum "$J"
set_layer "$STEP"
