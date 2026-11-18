#!/bin/sh
# Phase 7v (beta9 clean flash 2026-11-18, BUGS 135): Gboard default keyboard after the setup wizard.
#
# * 5u installs Gboard in the first minute and set it as the default keyboard at once. On the beta9 clean flash
#   (pt125) this happened while the setup wizard ran: OplusInputMethodCustomizeHelper put its config default
#   (Sogou) back 20 ms after the write, and Sogou stayed. beta7.1 (pt61) was OK (timing).
# * Live test on pt125 after the setup (user_setup_complete=1): the same settings write stays.
# * service.sh: new gboard_default(). The Gboard install sets the marker gboard_pending; the default is written
#   only when user_setup_complete=1 and the default is still Sogou or none (a dirty flash keeps the user's
#   keyboard), and read back. The main loop retries every 10 s (screen on) until it is done.
#NEEDS: "$ROM/pipa_port/service.sh"
set -eu
. "$PORT/lib.sh"
STEP=7v

SE=$T/system_ext
[ -f "$SE/pipa_port/service.sh" ] || die "no system_ext/pipa_port/service.sh"
cat "$ROM/pipa_port/service.sh" > "$SE/pipa_port/service.sh"   # in place: owner, mode and label stay
need_grep '^gboard_default() {$' "$SE/pipa_port/service.sh"
need_grep 'gboard_pending' "$SE/pipa_port/service.sh"
echo "service.sh: Gboard default after the setup wizard"
set_layer "$STEP"
