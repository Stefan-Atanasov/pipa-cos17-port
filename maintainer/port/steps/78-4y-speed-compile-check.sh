#!/bin/sh
# Phase 4y: the UI apps are compiled (speed) again after each flash (BUGS-TODO 65 health check; system_ext only).
#
# * pipa_port service.sh speed_compile: 3 minutes after boot, compile SystemUI, Settings, wireless settings and the
#   launcher with `cmd package compile -m speed` when `pm art dump` does not show status=speed. Before, the check was
#   "build fingerprint + system_ext build date changed"; port builds keep both (donor values), so after pt28 no build
#   compiled them. The boot jar edits (3o framework.jar, 4h oplus-framework.jar) make the prebuilt odex of all apps
#   invalid (ART uses only the vdex: status=verify / run-from-apk), and a dirty flash with the same fingerprint gets no
#   boot-time SystemUI compile. Measured on pt37 (8 app launches, FrameTimeline): launcher janky frames 35 % -> 16 %,
#   AppDeadline 38 -> 9; SystemUI main thread at rest 35 -> 16 ticks in 20 s.
#NEEDS: "$ROM/pipa_port/service.sh"
set -eu
. "$PORT/lib.sh"
STEP=4y

SE=$T/system_ext
cat "$ROM/pipa_port/service.sh" > "$SE/pipa_port/service.sh"
need_grep 'arm64: \\\[status=speed\\\]' "$SE/pipa_port/service.sh"
set_layer "$STEP"
