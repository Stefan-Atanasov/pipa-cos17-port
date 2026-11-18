#!/bin/sh
# Phase 7q: animation tier 3 from the first boot (tester report 2026-11-18: "glow effect on lock screen was there after
# the first flash, after a restart it vanished").
#
# * The pipa_port service sets persist.sys.oplus.anim_level=3 only after boot (anim_check), and restarts only the
#   launcher. SystemUI reads the property once, at its start. After a clean flash the property was unset at that
#   time, so SystemUI ran tier 1 (glow, rubber lock screen) until the next reboot.
# * system_ext build.prop now sets persist.sys.oplus.anim_level=3. init loads it before zygote; a value in
#   /data/property (persistent) still wins. anim_check stays (ANIM_LEVEL override for tests).
set -eu
. "$PORT/lib.sh"
STEP=7q
BP=$T/system_ext/etc/build.prop
forbid_grep '^persist.sys.oplus.anim_level=' "$BP"
{ cat "$BP"; printf '\n# pipa port 7q: animation tier 3 (Fast) from the first boot\npersist.sys.oplus.anim_level=3\n'; } > "$R/bp.7q"
cat "$R/bp.7q" > "$BP"; rm -f "$R/bp.7q"
need_grep '^persist.sys.oplus.anim_level=3$' "$BP"
echo "system_ext build.prop: persist.sys.oplus.anim_level=3 (7q)"
set_layer "$STEP"
