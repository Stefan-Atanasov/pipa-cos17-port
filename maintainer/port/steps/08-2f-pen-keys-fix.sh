#!/bin/sh
# Phase 2f: fixes for the first beta5-2e boot, on top of 2e (system_ext only).
#
# * pen_keys.sh: `input keyevent` ran with the getevent pipe as stdin; `cmd` hands the caller's
#   stdin to system_server over binder, system_server may not use a pipe labelled pipa_port, and the
#   call died with "Failed transaction (2147483646)" (nothing in the AVC trace: dontaudit). The
#   back-button screenshot did nothing. Every action now gets plain /dev/null streams.
# * service.sh: the "pen connected" message to IPeManager is sent again 10 s and 40 s after the
#   pen connects (the one at boot was sometimes ignored: Settings showed the stylus as not
#   connected until the message was sent again).
# The pipa_port domain is still PERMISSIVE; the enforcing rules come with a boot trace in a later build.
#
# Old layer script: build_beta5_2f.sh
#NEEDS: "$ROM/pipa_port/pen_keys.sh" "$ROM/pipa_port/service.sh"
set -eu
. "$PORT/lib.sh"
LABEL=u:object_r:system_file:s0

SE=$T/system_ext

echo "== pipa_port scripts"
for f in pen_keys.sh service.sh; do
    cmp -s "$ROM/pipa_port/$f" "$SE/pipa_port/$f" && { echo "unchanged $f"; continue; }
    install -o 0 -g 0 -m 644 "$ROM/pipa_port/$f" "$SE/pipa_port/$f"
    setfattr -n security.selinux -v "$LABEL" "$SE/pipa_port/$f"
    echo "updated  system_ext/pipa_port/$f ($(md5sum < "$ROM/pipa_port/$f" | cut -c1-8))"
done
need_grep '</dev/null >/dev/null 2>&1' "$SE/pipa_port/pen_keys.sh"
need_grep 'resend' "$SE/pipa_port/service.sh"

