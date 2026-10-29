#!/bin/sh
# Phase 2q: less background CPU and smoother defaults, on top of 2p (system_ext only).
#
# * pipa_port loop: shell builtins instead of a cat/grep/stat/tr/awk/sleep process per second, `settings get` x4 only
#   after settings_system.xml changed, pidof for the face worker every 3rd tick. Idle home screen: 14.7 % -> 2.3 % of
#   one CPU core (2026-10-24 traces idle-home-2p, idle-home-2q-loop4). pen_keys.sh: the pen node awk only when the
#   input device list changed, nap instead of sleep.
# * pipa_port SMOOTH_DEFAULT (once per install): window blur off (A/B: -25 % dropped frames, -35 % SF GPU misses),
#   material blur off, animation scales 0.8.
# * early.sh: clears /data/system/package_cache once when ro.pipa.port.layer changes (BUGS-TODO 14: with mkfs.erofs
#   -T0 and the same fingerprint, PackageManager kept the cached manifest of changed system APKs).
# * early.sh: /dev/cpuset/oiface_fg, oiface_fg+, oiface_bg for OPPO OIFace (made by OPPO's vendor init; missing on pipa).
# * pipa_port nandswap_dedup: a zygote restart re-ran OPPO's nandswap script and attached the swap file again.
# * system_ext/etc/build.prop: ro.pipa.port.layer=2q. Each later layer must set its own name (sed below).
#
# Old layer script: build_beta5_2q.sh
#NEEDS: "$ROM/pipa_port/service.sh" "$ROM/pipa_port/pen_keys.sh" "$ROM/pipa_port/early.sh" "$ROM/pipa_port/config.prop"
set -eu
. "$PORT/lib.sh"
STEP=2q

SE=$T/system_ext

echo "== pipa_port: loop CPU, smoothness defaults, package cache"
for f in service.sh pen_keys.sh early.sh config.prop; do
    cat "$ROM/pipa_port/$f" > "$SE/pipa_port/$f"   # in place (cat >): owner, mode and SELinux label stay
    echo "updated system_ext/pipa_port/$f"
done
need_grep 'nap()' "$SE/pipa_port/service.sh"
need_grep SMOOTH_DEFAULT "$SE/pipa_port/service.sh"
need_grep pkgcache_layer "$SE/pipa_port/early.sh"
need_grep oiface_fg "$SE/pipa_port/early.sh"
need_grep nandswap_dedup "$SE/pipa_port/service.sh"

echo "== system_ext build.prop: ro.pipa.port.layer=$STEP"
set_layer "$STEP"

