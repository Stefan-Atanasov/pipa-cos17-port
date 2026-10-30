#!/bin/sh
# Phase 3v: pipa_port main loop (pen capsule/buttons/120 Hz lock, keyboard guard, lid) starts ~1 s after boot_completed
# instead of ~24 s (system_ext only).
#
# * The colour/adaptive/Bedtime restore (it waits 15 s for the boot reset of ColorOS and Eye Protect) runs in a
#   background subshell with its own sget file. The loop saves the display choice only after the restore
#   (/data/misc/pipa_port/display.restored), so the boot reset is never saved as the user's choice.
# * system_ux() reads the system_server thread names with the builtin read (one cat per thread took ~6 s).
# Live test 2026-10-30 (bind mount + ctl.restart): pen state 24 s -> 1-3 s after the start; restore at +16 s.
# * system_ext/pipa_port/service.sh from port-rom (the earlier steps copy the same file; this step checks it).
#NEEDS: "$ROM/pipa_port/service.sh"
set -eu
. "$PORT/lib.sh"

SE=$T/system_ext
cat "$ROM/pipa_port/service.sh" > "$SE/pipa_port/service.sh"
grep -q 'DISP_DONE=$STATE/display.restored' "$SE/pipa_port/service.sh" || die "service.sh: restore not in the background"
if grep -q 'cat /proc/$p/task/$t/comm' "$SE/pipa_port/service.sh"; then die "service.sh: old system_ux cat loop"; fi
echo "updated system_ext/pipa_port/service.sh (fast start)"
