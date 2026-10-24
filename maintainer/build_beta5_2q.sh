#!/bin/sh
# Phase 2q: less background CPU and smoother defaults, on top of 2p (system_ext only). Run as root:
#
#   sudo sh build_beta5_2q.sh
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
# Input: port-work/${TAG}-2p/tree/system_ext, port-work/${TAG}-2p/img. Output: port-work/${TAG}-2q/.
set -eu
TAG=${TAG:-beta5}
STEP=2q
[ "$(id -u)" = 0 ] || { echo "run with sudo"; exit 1; }
P=${PIPA_ROOT:-/home/stefan/Documents/pipa}/port-work
IMGSRC=$P/${TAG}-2p/img
W=$P/${TAG}-$STEP
HERE=$(cd "$(dirname "$0")" && pwd)
ROM=$HERE/../port-rom
OWNER=${PIPA_OWNER:-stefan:stefan}
[ -f "$IMGSRC/super.img" ] || { echo "run build_beta5_2p.sh first"; exit 1; }
[ -d "$P/${TAG}-2p/tree/system_ext" ] || { echo "the 2p tree is missing: rebuild 2p"; exit 1; }

rm -rf "$W/tree"; mkdir -p "$W/tree" "$W/img" "$W/report"
exec > "$W/report/build.log" 2>&1
cp -a --reflink=auto "$P/${TAG}-2p/tree/system_ext" "$W/tree/"
SE=$W/tree/system_ext

echo "== pipa_port: loop CPU, smoothness defaults, package cache"
for f in service.sh pen_keys.sh early.sh config.prop; do
    cat "$ROM/pipa_port/$f" > "$SE/pipa_port/$f"   # in place (cat >): owner, mode and SELinux label stay
    echo "updated system_ext/pipa_port/$f"
done
grep -q 'nap()' "$SE/pipa_port/service.sh"
grep -q SMOOTH_DEFAULT "$SE/pipa_port/service.sh"
grep -q pkgcache_layer "$SE/pipa_port/early.sh"
grep -q oiface_fg "$SE/pipa_port/early.sh"
grep -q nandswap_dedup "$SE/pipa_port/service.sh"

echo "== system_ext build.prop: ro.pipa.port.layer=$STEP"
BP=$SE/etc/build.prop
if grep -q '^ro.pipa.port.layer=' "$BP"; then
    sed "s/^ro.pipa.port.layer=.*/ro.pipa.port.layer=$STEP/" "$BP" > "$W/report/build.prop.new"
else
    { cat "$BP"; printf '\n# pipa port ROM layer (early.sh clears the package cache when it changes)\nro.pipa.port.layer=%s\n' "$STEP"; } > "$W/report/build.prop.new"
fi
cat "$W/report/build.prop.new" > "$BP"
grep "^ro.pipa.port.layer=$STEP\$" "$BP"

echo "== label check"
python3 -I "$HERE/tree_manifest.py" "$SE" > "$W/report/system_ext.tsv"
n=$(awk -F'\t' '$7 !~ /security.selinux/' "$W/report/system_ext.tsv" | wc -l)
echo "system_ext: $(wc -l < "$W/report/system_ext.tsv") entries, $n without a SELinux label"
[ "$n" = 0 ] || exit 1

echo "== mkfs (system_ext)"
mkfs.erofs -zlz4hc -C65536 -T0 "$W/img/system_ext.img" "$SE" > "$W/report/mkfs_system_ext.log" 2>&1
for p in system product vendor odm; do cp --reflink=auto "$IMGSRC/$p.img" "$W/img/$p.img"; done
ls -l "$W/img"

echo "== super"
cd "$W/img"
set --
for p in system system_ext product vendor odm; do set -- "$@" --partition "${p}_a:readonly:0:qti_dynamic_partitions_a"; done
for p in system system_ext product vendor odm; do
    set -- "$@" --partition "${p}_b:readonly:$(stat -c %s $p.img):qti_dynamic_partitions_b" --image "${p}_b=$p.img"
done
lpmake --metadata-size 65536 --super-name super --metadata-slots 2 --virtual-ab \
    --device super:9126805504 \
    --group qti_dynamic_partitions_a:9126805504 --group qti_dynamic_partitions_b:9126805504 \
    "$@" --sparse --output super.img 2>&1 | grep -v -e 'will resize' -e 'Invalid sparse' || true
ls -l super.img
md5sum super.img
chown -R "$OWNER" "$W/img" "$W/report"
echo "== done"
