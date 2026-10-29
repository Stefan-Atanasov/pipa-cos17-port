#!/bin/sh
# Phase 2v: animation blur off in the once-per-install smoothness defaults, on top of 2t (system_ext only).
#
# Fixes from the clean-flash test of beta5 (2026-10-25):
# * pipa_port first-boot defaults also set animationBlurrySwitch=0 (ColorOS writes 1 itself before the service runs, so
#   BLUR_DEFAULT never applied) and show_ime_with_hard_keyboard=1 (the nanosic driver always registers "Xiaomi
#   Keyboard" input devices, so Android hid the on-screen keyboard).
# * face_rotation_sync reads the display rotation from `cmd display get-displays` into a file. `$(dumpsys display ...)`
#   never worked in the service domain (pipe; and dump() fails with FAILED_TRANSACTION even into a file), so the face
#   preview was rotated in landscape on a clean install.
# * system_ext/etc/build.prop: ro.pipa.port.layer=2v.
#
# Old chain lineage: 2v took its system_ext from 2t, NOT from 2u. In one tree this is the same, because
# step 2u is skipped by default.
#
# Old layer script: build_beta5_2v.sh
#NEEDS: "$ROM/pipa_port/service.sh" "$ROM/pipa_port/pen_keys.sh" "$ROM/pipa_port/early.sh" "$ROM/pipa_port/config.prop"
set -eu
. "$PORT/lib.sh"
STEP=2v

SE=$T/system_ext

echo "== pipa_port: clean-flash fixes (defaults, face rotation)"
for f in service.sh pen_keys.sh early.sh config.prop; do
    cat "$ROM/pipa_port/$f" > "$SE/pipa_port/$f"   # in place (cat >): owner, mode and SELinux label stay
    echo "updated system_ext/pipa_port/$f"
done
need_grep 'SGET_F=' "$SE/pipa_port/service.sh"
need_grep 'settings put system animationBlurrySwitch 0$' "$SE/pipa_port/service.sh"
need_grep 'settings put secure show_ime_with_hard_keyboard 1$' "$SE/pipa_port/service.sh"
need_grep 'cmd display get-displays' "$SE/pipa_port/service.sh"
if grep -v '^[[:space:]]*#' "$SE/pipa_port/service.sh" | grep -q 'dumpsys display'; then echo 'dumpsys display cannot work in the service'; exit 1; fi
if grep -q qs_tile_add "$SE/pipa_port/service.sh"; then echo "qs_tile_add is still in service.sh"; exit 1; fi
need_grep anim_check "$SE/pipa_port/service.sh"
need_grep "^sget()" "$SE/pipa_port/service.sh"
# `set -e` ignores a negated command (`! grep`): use if
if grep -v '^[[:space:]]*#' "$SE/pipa_port/service.sh" | grep -q '$(settings get'; then echo '$(settings get ...) cannot work in the service'; exit 1; fi
echo "== system_ext build.prop: ro.pipa.port.layer=$STEP"
set_layer "$STEP"

