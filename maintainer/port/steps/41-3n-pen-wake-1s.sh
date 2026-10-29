#!/bin/sh
# Phase 3n: pen ready ~1 s after screen-on (system_ext only).
#
# The pipa_port main loop slept 5 s per round while the screen was off, so "pen on" (touch panel pen mode) went out
# up to 5 s after screen-on. Now 1 s also with the screen off. The screen check is one builtin read, and in suspend
# the timer does not run: no extra wakeups. Live test 2026-10-29 (bind mount): pen on ~0.7-1 s after the wake key.
# * system_ext/pipa_port/service.sh from port-rom (the earlier steps copy the same file; this step checks it).
#NEEDS: "$ROM/pipa_port/service.sh"
set -eu
. "$PORT/lib.sh"

SE=$T/system_ext
cat "$ROM/pipa_port/service.sh" > "$SE/pipa_port/service.sh"
grep -q '^        nap 1$' "$SE/pipa_port/service.sh" || die "service.sh: screen-off nap is not 1 s"
grep -q '^        nap 5$' "$SE/pipa_port/service.sh" && die "service.sh: old 5 s screen-off nap"
echo "updated system_ext/pipa_port/service.sh (screen-off loop 1 s)"
