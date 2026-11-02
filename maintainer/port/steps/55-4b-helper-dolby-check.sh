#!/bin/sh
# Phase 4b: pipa helper 0.7: Dolby (MiSound DAP) comes back without a screen-off/on (BUGS-TODO 42, public bug doc
# 2026-11-02: "Dolby Atmos sometimes falls back to Xiaomi Sound"; system only).
#
# DolbyKeeper checked the global DAP effect only at screen-on: after an audioserver restart or an output change with
# the screen on, Dolby stayed off. 0.7 also checks on each audio device change and every 60 s while the screen is on.
# Live test 2026-11-02 (bind mount, audioserver restart with the screen on): DAP recreated and on after 48 s.
# The helper APK is a persistent priv-app: new ro.pipa.port.layer, so early.sh clears the package cache.
#NEEDS: "$HERE/../helper/out/PipaHelper.apk"
set -eu
. "$PORT/lib.sh"
STEP=4b

APK=$HERE/../helper/out/PipaHelper.apk
python3 -I - "$APK" <<'PY'
import sys, zipfile
d = zipfile.ZipFile(sys.argv[1]).read("classes.dex")
assert b"registerAudioDeviceCallback" in d, "PipaHelper.apk: not 0.7 (no audio device callback in DolbyKeeper)"
PY
S=$T/system
cat "$APK" > "$S/system/priv-app/PipaHelper/PipaHelper.apk"   # in place: owner, mode and SELinux label stay
rm -rf "$S/system/priv-app/PipaHelper/oat"
md5sum "$S/system/priv-app/PipaHelper/PipaHelper.apk"
set_layer "$STEP"
