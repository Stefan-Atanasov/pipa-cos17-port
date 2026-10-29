#!/bin/sh
# Phase 2t: cheaper settings reads in pipa_port, on top of 2s (system_ext only).
#
# * pipa_port sget(): `settings get` into a file in /data/local/tmp (0.03 s CPU per read) instead of `content query`
#   (Java, 0.28 s). The global settings file changes ~5 times a minute with the screen on, and each change makes the
#   animation-tier check read pipa_anim_level: ~2 % -> ~0.3 % of one core while the screen is on (nothing when off).
# * anim_check: a failed read leaves the tier as it is (it must not fall back to 3 against the user's choice).
# * The Quick Settings tile is not added by the service (ColorOS's editor offers it again after a removal).
# * system_ext/etc/build.prop: ro.pipa.port.layer=2t.
#
# Old layer script: build_beta5_2t.sh
#NEEDS: "$ROM/pipa_port/service.sh" "$ROM/pipa_port/pen_keys.sh" "$ROM/pipa_port/early.sh" "$ROM/pipa_port/config.prop"
set -eu
. "$PORT/lib.sh"
STEP=2t

SE=$T/system_ext

echo "== pipa_port: cheaper settings reads"
for f in service.sh pen_keys.sh early.sh config.prop; do
    cat "$ROM/pipa_port/$f" > "$SE/pipa_port/$f"   # in place (cat >): owner, mode and SELinux label stay
    echo "updated system_ext/pipa_port/$f"
done
need_grep 'SGET_F=' "$SE/pipa_port/service.sh"
if grep -q qs_tile_add "$SE/pipa_port/service.sh"; then echo "qs_tile_add is still in service.sh"; exit 1; fi
need_grep anim_check "$SE/pipa_port/service.sh"
need_grep "^sget()" "$SE/pipa_port/service.sh"
# `set -e` ignores a negated command (`! grep`): use if
if grep -v '^[[:space:]]*#' "$SE/pipa_port/service.sh" | grep -q '$(settings get'; then echo '$(settings get ...) cannot work in the service'; exit 1; fi
echo "== system_ext build.prop: ro.pipa.port.layer=$STEP"
set_layer "$STEP"

