#!/bin/sh
# Phase 3u: pen dock capsule without the 3-4 s delay, and the dock seen with the pen either way round (system_ext only).
#
# The dock has two hall sensors, fuda/reverse_chg_hall3 and reverse_chg_hall4 (one for each pen orientation). The
# service read only hall4: with the pen on the hall3 magnet it saw "not docked" (no capsule, pen 120 Hz lock on).
# The 2026-10-29 "hall reads out for 2 s" capsule was the pen on the other magnet, so the 3-read debounce of pt18
# (3-4 s delay) is replaced: docked = one of the halls reads 0; "in" counts at once, "out" after a second read 0.5 s
# later. Live test 2026-10-30 (bind mount): dock 0.4-1.3 s, undock 0.8-1.7 s, pen moved across the magnets: no flicker.
# * system_ext/pipa_port/service.sh from port-rom (the earlier steps copy the same file; this step checks it).
#NEEDS: "$ROM/pipa_port/service.sh"
set -eu
. "$PORT/lib.sh"

SE=$T/system_ext
cat "$ROM/pipa_port/service.sh" > "$SE/pipa_port/service.sh"
grep -q 'PEN_HALL3=/sys/class/power_supply/fuda/reverse_chg_hall3' "$SE/pipa_port/service.sh" || die "service.sh: no hall3 read"
if grep -q 'dn -ge 3' "$SE/pipa_port/service.sh"; then die "service.sh: old 3-read dock debounce"; fi
echo "updated system_ext/pipa_port/service.sh (dock = hall3 or hall4)"
