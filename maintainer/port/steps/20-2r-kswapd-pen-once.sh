#!/bin/sh
# Phase 2r: kswapd off the prime core + pen "connected" once at boot, on top of 2q (system_ext only).
#
# * pipa_port KSWAPD_NO_PRIME: kswapd (zram compression) on CPUs 0-6. It ran 19.7 s of 60 s on the prime core
#   (manual-2), more than the launcher; on CPUs 0-6 launcher frames > 120 ms 21 -> 4 (manual-3, 2026-10-24).
# * pipa_port pen watcher: the first "connected" goes out once, 40 s after the service start (was 0/+10/+40 s, each
#   showed the live-alert capsule since 2p).
# * system_ext/etc/build.prop: ro.pipa.port.layer=2r.
#
# Old layer script: build_beta5_2r.sh
#NEEDS: "$ROM/pipa_port/service.sh" "$ROM/pipa_port/pen_keys.sh" "$ROM/pipa_port/early.sh" "$ROM/pipa_port/config.prop"
set -eu
. "$PORT/lib.sh"
STEP=2r

SE=$T/system_ext

echo "== pipa_port: kswapd off the prime core, pen connected once"
for f in service.sh pen_keys.sh early.sh config.prop; do
    cat "$ROM/pipa_port/$f" > "$SE/pipa_port/$f"   # in place (cat >): owner, mode and SELinux label stay
    echo "updated system_ext/pipa_port/$f"
done
need_grep KSWAPD_NO_PRIME "$SE/pipa_port/service.sh"
need_grep '^KSWAPD_NO_PRIME=1' "$SE/pipa_port/config.prop"
need_grep 'goes out once, 40 s after' "$SE/pipa_port/service.sh"
need_grep nandswap_dedup "$SE/pipa_port/service.sh"
echo "== system_ext build.prop: ro.pipa.port.layer=$STEP"
set_layer "$STEP"

