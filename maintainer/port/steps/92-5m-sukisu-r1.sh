#!/bin/sh
# Phase 5m: SukiSU-Ultra manager v4.3.0-r1 (41140) on the first boot, the same level as kernel walt-r17 (beta7).
#
# * system_ext/pipa_port/SukiSU.apk + SukiSU.version: pipa_port installs the manager once as a normal app and over an
#   older manager (service.sh KSU_MANAGER, from 2w). The release sha256 of the APK was checked against the GitHub
#   release (79a0db80...) and its signing certificate is the same as v4.3.0 (947ae944...).
# * A new ro.pipa.port.layer: early.sh clears the package cache, so a dirty flash over a test build with the same
#   layer does not keep a stale parsed manifest (the pt49 -> pt50 helper permission case).
#NEEDS: "$HERE/../kernel/sukisu-v4.3.0-r1/SukiSU_v4.3.0-r1_41140-release.apk"
set -eu
. "$PORT/lib.sh"
STEP=5m

KSU_APK=$HERE/../kernel/sukisu-v4.3.0-r1/SukiSU_v4.3.0-r1_41140-release.apk
KSU_VER=41140
[ "$(sha256sum "$KSU_APK" | cut -d' ' -f1)" = 79a0db803e1f0bb952760f19250e5fc92566e2569581e4123c9db0b5e3c46bb9 ] || die "SukiSU r1 APK: wrong sha256"
SE=$T/system_ext
[ -f "$SE/pipa_port/SukiSU.apk" ] || die "no system_ext/pipa_port/SukiSU.apk (step 2w missing?)"
cat "$KSU_APK" > "$SE/pipa_port/SukiSU.apk"      # in place: owner, mode and label stay
echo "$KSU_VER" > "$R/SukiSU.version"; cat "$R/SukiSU.version" > "$SE/pipa_port/SukiSU.version"
need_grep "^$KSU_VER\$" "$SE/pipa_port/SukiSU.version"
echo "SukiSU.apk -> v4.3.0-r1 ($KSU_VER)"
set_layer "$STEP"
