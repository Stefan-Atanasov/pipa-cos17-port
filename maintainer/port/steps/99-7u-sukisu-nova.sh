#!/bin/sh
# Phase 7u (user 2026-11-18): SukiSU Nova manager v3.0.0 (com.sukisu.nova, 35000) for kernel walt-hi9.
#
# * SukiSU-Ultra was renamed SukiSU Nova (2026-11-15). walt-hi9 has the Nova builtin branch (4bec532d, version 30691)
#   and accepts only the manager package com.sukisu.nova (same signing certificate 947ae944...). The old bundled
#   manager (5m, com.sukisu.ultra 41140) cannot talk to it.
# * system_ext/pipa_port/SukiSU.apk + SukiSU.version: the Nova APK (GitHub release v3.0.0, arm64-v8a, sha256 below).
# * service.sh: ksu_manager installs com.sukisu.nova once and then removes an old com.sukisu.ultra manager (dirty
#   flash). The Nova manager installs its own ksud 3.0.0 (do not copy ksud by hand).
#NEEDS: "$HERE/../kernel/sukisu-nova-3.0.0/SukiSU_Nova_v3.0.0_35000-arm64-v8a-release.apk" "$ROM/pipa_port/service.sh"
set -eu
. "$PORT/lib.sh"
STEP=7u

KSU_APK=$HERE/../kernel/sukisu-nova-3.0.0/SukiSU_Nova_v3.0.0_35000-arm64-v8a-release.apk
KSU_VER=35000
[ "$(sha256sum "$KSU_APK" | cut -d' ' -f1)" = 1202adb835a64d8b3df703da7884a2966f8728c131cffb29fb5f48d31d81ac85 ] || die "Nova APK: wrong sha256"
SE=$T/system_ext
[ -f "$SE/pipa_port/SukiSU.apk" ] || die "no system_ext/pipa_port/SukiSU.apk (step 2w missing?)"
cat "$KSU_APK" > "$SE/pipa_port/SukiSU.apk"      # in place: owner, mode and label stay
echo "$KSU_VER" > "$R/SukiSU.version"; cat "$R/SukiSU.version" > "$SE/pipa_port/SukiSU.version"; rm -f "$R/SukiSU.version"
cat "$ROM/pipa_port/service.sh" > "$SE/pipa_port/service.sh"   # in place
need_grep '^KSU_PKG=com.sukisu.nova$' "$SE/pipa_port/service.sh"
need_grep 'pm install -r "$MODDIR/SukiSU.apk"' "$SE/pipa_port/service.sh"
[ "$(sha256sum "$SE/pipa_port/SukiSU.apk" | cut -d' ' -f1)" = 1202adb835a64d8b3df703da7884a2966f8728c131cffb29fb5f48d31d81ac85 ] || die "SukiSU.apk copy: wrong sha256"
echo "SukiSU.apk = Nova v3.0.0 ($KSU_VER)"
set_layer "$STEP"
