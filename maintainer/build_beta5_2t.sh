#!/bin/sh
# Phase 2t: cheaper settings reads in pipa_port, on top of 2s (system_ext only). Run as root:
#
#   sudo sh build_beta5_2t.sh
#
# * pipa_port sget(): `settings get` into a file in /data/local/tmp (0.03 s CPU per read) instead of `content query`
#   (Java, 0.28 s). The global settings file changes ~5 times a minute with the screen on, and each change makes the
#   animation-tier check read pipa_anim_level: ~2 % -> ~0.3 % of one core while the screen is on (nothing when off).
# * anim_check: a failed read leaves the tier as it is (it must not fall back to 3 against the user's choice).
# * The Quick Settings tile is not added by the service (ColorOS's editor offers it again after a removal).
# * system_ext/etc/build.prop: ro.pipa.port.layer=2t.
#
# Input: port-work/${TAG}-2s/tree/system_ext, port-work/${TAG}-2s/img. Output: port-work/${TAG}-2t/.
set -eu
TAG=${TAG:-beta5}
STEP=2t
[ "$(id -u)" = 0 ] || { echo "run with sudo"; exit 1; }
P=${PIPA_ROOT:-/home/stefan/Documents/pipa}/port-work
IMGSRC=$P/${TAG}-2s/img
W=$P/${TAG}-$STEP
HERE=$(cd "$(dirname "$0")" && pwd)
ROM=$HERE/../port-rom
OWNER=${PIPA_OWNER:-stefan:stefan}
[ -f "$IMGSRC/super.img" ] || { echo "run build_beta5_2s.sh first"; exit 1; }
[ -d "$P/${TAG}-2s/tree/system_ext" ] || { echo "the 2s tree is missing: rebuild 2s"; exit 1; }

rm -rf "$W/tree"; mkdir -p "$W/tree" "$W/img" "$W/report"
exec > "$W/report/build.log" 2>&1
cp -a --reflink=auto "$P/${TAG}-2s/tree/system_ext" "$W/tree/"
SE=$W/tree/system_ext

echo "== pipa_port: cheaper settings reads"
for f in service.sh pen_keys.sh early.sh config.prop; do
    cat "$ROM/pipa_port/$f" > "$SE/pipa_port/$f"   # in place (cat >): owner, mode and SELinux label stay
    echo "updated system_ext/pipa_port/$f"
done
grep -q 'SGET_F=' "$SE/pipa_port/service.sh"
if grep -q qs_tile_add "$SE/pipa_port/service.sh"; then echo "qs_tile_add is still in service.sh"; exit 1; fi
grep -q anim_check "$SE/pipa_port/service.sh"
grep -q "^sget()" "$SE/pipa_port/service.sh"
# `set -e` ignores a negated command (`! grep`): use if
if grep -v '^[[:space:]]*#' "$SE/pipa_port/service.sh" | grep -q '$(settings get'; then echo '$(settings get ...) cannot work in the service'; exit 1; fi
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
