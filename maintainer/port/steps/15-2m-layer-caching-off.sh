#!/bin/sh
# Phase 2m: SurfaceFlinger layer caching off again, on top of 2l (system_ext only).
#
# 2j put debug.sf.enable_layer_caching=1 into system_ext/etc/build.prop (small gain in the 2026-10-24 night A/B). With
# it on, the user saw the screen glitch in Settings while searching (keyboard + split layout); `service call
# SurfaceFlinger 1040 i32 0` (caching off live, "Planner is disabled") fixed it. Drop the line; AOSP default is off.
#
# Old layer script: build_beta5_2m.sh
set -eu
. "$PORT/lib.sh"

SE=$T/system_ext

echo "== system_ext build.prop: layer caching off"
BP=$SE/etc/build.prop
grep -q '^debug.sf.enable_layer_caching=1' "$BP" || { echo "layer caching line not found"; exit 1; }
grep -v '^debug.sf.enable_layer_caching=' "$BP" > "$R/system_ext.prop"
cat "$R/system_ext.prop" > "$BP"   # in place: owner, mode and SELinux label stay
grep -n 'debug.sf' "$BP"

