#!/bin/sh
# Phase 4w: bypass charging hysteresis at a low level (BUGS-TODO 63 candidate; system_ext only).
#
# * pipa_port service.sh chg_hold: below 15 % the tablet charges at full current (4p). Before, the bypass cap came
#   back at 15 %: under a game load (tester: Roblox at 1-20 %, "sounds") the state switched cap/charge at 14/15 %
#   every few minutes. Now the cap comes back only at 20 %. Tested on the host with fake sysfs files (2026-11-03):
#   16 cap, 14 charge, 15-19 charge, 20 cap, 15 cap, 14 charge.
#NEEDS: "$ROM/pipa_port/service.sh"
set -eu
. "$PORT/lib.sh"
STEP=4w

SE=$T/system_ext
cat "$ROM/pipa_port/service.sh" > "$SE/pipa_port/service.sh"
need_grep 'chg_low=1' "$SE/pipa_port/service.sh"
set_layer "$STEP"
