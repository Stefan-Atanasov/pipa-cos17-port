#!/bin/sh
# Phase 2a: the two "easy" runtime pieces leave pipa_core / power-tune (PHASE2-ROM-INTEGRATION.md
# A4, A9). Layered on the phase 1c build; run as root after build_beta5_1c.sh:
#
#   sudo sh build_beta5_2a.sh
#
# A4 system/app/FaceUnlock: the legacy socket face client (com.pipa.faceunlock, R4). Confirmed on
#    beta5-1c (2026-10-22): /data/system/facehal_socket never exists; the facehal-rs AIDL HAL is
#    used and power-tune disables the app every boot.
# A9 AOD off for good (maintainer decision 2026-10-22, LCD panel): the AOD feature flags are
#    commented out in my_product's display feature list, so Settings hides AOD as on other LCD
#    ColorOS devices. pipa_core's AodBacklightDaemon (and power-tune's AOD freeze, B3) then have
#    nothing to do; remove them from the modules once this image is verified.
#
# Input: port-work/${TAG}-1c/{tree,img}. Output: port-work/${TAG}-2a/{tree,img,report}.
set -eu
TAG=${TAG:-beta5}   # base name: work dirs are port-work/$TAG, $TAG-baked, $TAG-2f, ... (build_port.sh sets it)
[ "$(id -u)" = 0 ] || { echo "run with sudo"; exit 1; }
SRC=${PIPA_ROOT:-/home/stefan/Documents/pipa}/port-work/${TAG}-1c
W=${PIPA_ROOT:-/home/stefan/Documents/pipa}/port-work/${TAG}-2a
HERE=$(cd "$(dirname "$0")" && pwd)
OWNER=${PIPA_OWNER:-stefan:stefan}
[ -f "$SRC/img/super.img" ] || { echo "run build_beta5_1c.sh first"; exit 1; }

rm -rf "$W/tree"; mkdir -p "$W/tree" "$W/img" "$W/report"
exec > "$W/report/build.log" 2>&1
# 1c only copied the partitions it changed; system comes from the baked tree
SYS=$SRC/tree/system; [ -d "$SYS" ] || SYS=$SRC/../${TAG}-baked/tree/system
cp -a --reflink=auto "$SYS" "$W/tree/"

replace_once() {
    python3 -I - "$W/tree/$1" "$2" "$3" <<'PY'
import sys
p, old, new = sys.argv[1:]
old, new = old.encode().decode('unicode_escape'), new.encode().decode('unicode_escape')
s = open(p, encoding='utf-8', errors='surrogateescape').read()
n = s.count(old)
if n != 1:
    sys.exit(f"{p}: anchor found {n} times, expected 1")
with open(p, 'r+', encoding='utf-8', errors='surrogateescape') as f:   # same inode: label kept
    f.write(s.replace(old, new)); f.truncate()
PY
    [ $? = 0 ] || exit 1
    echo "edited  $1"
}

echo "== A4 drop FaceUnlock"
[ -d "$W/tree/system/system/app/FaceUnlock" ] || { echo "FaceUnlock not found"; exit 1; }
rm -rf "$W/tree/system/system/app/FaceUnlock"

echo "== A9 AOD feature off"
F=system/my_product/etc/permissions/oplus.product.display_features.xml
for f in aod_support aod_prevent_burn_support lcd_aod_mode; do
    replace_once $F "    <oplus-feature name=\"oplus.software.display.$f\"/>\n" \
        "    <!-- pipa port: AOD off (LCD) <oplus-feature name=\"oplus.software.display.$f\"/> -->\n"
done

echo "== label check"
python3 -I "$HERE/tree_manifest.py" "$W/tree/system" > "$W/report/system.tsv"
n=$(awk -F'\t' '$7 !~ /security.selinux/' "$W/report/system.tsv" | wc -l)
echo "system: $(wc -l < "$W/report/system.tsv") entries, $n without a SELinux label"
[ "$n" = 0 ] || exit 1

echo "== mkfs (system)"
mkfs.erofs -zlz4hc -C65536 -T0 "$W/img/system.img" "$W/tree/system" > "$W/report/mkfs_system.log" 2>&1
for p in system_ext product vendor odm; do cp --reflink=auto "$SRC/img/$p.img" "$W/img/$p.img"; done
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
