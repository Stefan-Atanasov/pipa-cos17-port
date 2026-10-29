#!/bin/sh
# Phase 3g: fixes for 3f's enforcing pipa_port (BUGS-TODO 12), on top of 3f (system_ext only). Run as root:
#
#   sudo sh build_beta5_3g.sh
#
# 3f booted enforcing and showed rules the capture could not see:
# * init checks property sets in user space and logs nothing for a permissive domain: ctl.stop$xiaomi-keyboard and
#   ctl.stop$vendor.facehal were denied (the keyboard daemon kept running: idle drain). Now set rules for ctl_*,
#   vendor_radio_prop, vendor_default_prop, system_prop.
# * one-time paths: early.sh package-cache clear (denied in 3f), face HAL copy to /data, idmap, /metadata cleanup.
#   Tested live under enforcing 2026-10-28 (ksud rules; the property rules can only be checked by a boot).
# * system_ext/pipa_port/facehal/VERSION includes libpipa_eyeguard.so: the /data copy of the face HAL is refreshed and
#   the eye-ROI guard (item 8) is loaded (3f did not refresh the copy).
# * system_ext/etc/build.prop: ro.pipa.port.layer=3g.
#
# Input: port-work/${TAG}-3f/{tree/system_ext,img}, the 3e system_ext tree (original CIL). Output: port-work/${TAG}-3g/.
set -eu
TAG=${TAG:-beta5}
STEP=3g
[ "$(id -u)" = 0 ] || { echo "run with sudo"; exit 1; }
P=${PIPA_ROOT:-/home/stefan/Documents/pipa}/port-work
PREV=$P/${TAG}-3f
W=$P/${TAG}-$STEP
HERE=$(cd "$(dirname "$0")" && pwd)
ROM=$HERE/../port-rom
OWNER=${PIPA_OWNER:-stefan:stefan}
[ -d "$PREV/tree/system_ext" ] && [ -f "$PREV/img/system.img" ] && [ -d "$P/${TAG}-3e/tree/system_ext" ] || { echo "3f or 3e is missing"; exit 1; }
free=$(df --output=avail -k "$P" | tail -1)
[ "$free" -gt $((20 * 1024 * 1024)) ] || { echo "less than 20 GB free in $P: a full disk truncates super.img"; exit 1; }

rm -rf "$W/tree"; mkdir -p "$W/tree" "$W/img" "$W/report"
exec > "$W/report/build.log" 2>&1
cp -a --reflink=auto "$PREV/tree/system_ext" "$W/tree/"
SE=$W/tree/system_ext

echo "== 12: pipa_port enforcing (rules from sepolicy/pipa_port_rules.cil, on the 3e CIL)"
for f in etc/selinux/system_ext_sepolicy.cil etc/selinux/system_ext_sepolicy_debug.cil; do
    [ -f "$SE/$f" ] || { echo "skip    $f (absent)"; continue; }
    cat "$P/${TAG}-3e/tree/system_ext/$f" > "$SE/$f"   # same inode: label kept
    if grep -q "(type pipa_port)" "$SE/$f"; then python3 -I "$HERE/sepolicy/pipa_port_enforce.py" "$SE/$f"; fi
done
if grep -q "(typepermissive pipa_port)" "$SE/etc/selinux/system_ext_sepolicy.cil"; then echo "still permissive"; exit 1; fi
grep -q "ctl_stop_prop (property_service" "$SE/etc/selinux/system_ext_sepolicy.cil"

echo "== 8: face HAL VERSION (refreshes the /data copy)"
cat "$ROM/pipa_port/facehal/VERSION" > "$SE/pipa_port/facehal/VERSION"
grep -q libpipa_eyeguard.so "$SE/pipa_port/facehal/VERSION"
cmp "$ROM/pipa_port/service.sh" "$SE/pipa_port/service.sh"

echo "== system_ext build.prop: ro.pipa.port.layer=$STEP"
BP=$SE/etc/build.prop
sed "s/^ro.pipa.port.layer=.*/ro.pipa.port.layer=$STEP/" "$BP" > "$W/report/build.prop.new"
cat "$W/report/build.prop.new" > "$BP"
grep "^ro.pipa.port.layer=$STEP\$" "$BP"

echo "== label check"
for t in system_ext; do
    python3 -I "$HERE/tree_manifest.py" "$W/tree/$t" > "$W/report/$t.tsv"
    n=$(awk -F'\t' '$7 !~ /security.selinux/' "$W/report/$t.tsv" | wc -l)
    echo "$t: $(wc -l < "$W/report/$t.tsv") entries, $n without a SELinux label"
    [ "$n" = 0 ] || exit 1
done

echo "== mkfs (system_ext); system, product, vendor, odm from 3f"
for t in system_ext; do
    mkfs.erofs -zlz4hc -C65536 -T0 "$W/img/$t.img" "$W/tree/$t" > "$W/report/mkfs_$t.log" 2>&1
done
for p in system product vendor odm; do cp --reflink=auto "$PREV/img/$p.img" "$W/img/$p.img"; done
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
    "$@" --sparse --output super.img > "$W/report/lpmake.log" 2>&1 || { cat "$W/report/lpmake.log"; echo "lpmake failed"; rm -f super.img; exit 1; }
grep -v -e 'will resize' -e 'Invalid sparse' "$W/report/lpmake.log" || true
ls -l super.img
md5sum super.img
chown -R "$OWNER" "$W/img" "$W/report"
echo "== done"
