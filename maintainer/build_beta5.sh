#!/bin/sh
# Build a C.06-based port ("beta5"): donor OS side + curated port edits + beta4 vendor/odm.
# Run as root: sudo sh build_beta5.sh   (writes only under $W; inputs are read-only)
set -eu
TAG=${TAG:-beta5}   # base name: work dirs are port-work/$TAG, $TAG-baked, $TAG-2f, ... (build_port.sh sets it)
[ "$(id -u)" = 0 ] || { echo "run with sudo"; exit 1; }

HERE=$(cd "$(dirname "$0")" && pwd)
DONOR=${DONOR_IMG:-${PIPA_ROOT:-/home/stefan/Documents/pipa}/donor/OPD2515_11.C.06/img}
BETA4_SRC=${PIPA_ROOT:-/home/stefan/Documents/pipa}/port-work/roundtrip/src       # root-extracted beta4
PARTS="$HERE/../work/parts"                                         # beta4 vendor/odm images
W=${PIPA_ROOT:-/home/stefan/Documents/pipa}/port-work/${TAG}
OWNER=${PIPA_OWNER:-stefan:stefan}

rm -rf "$W/tree"; mkdir -p "$W/tree" "$W/img" "$W/report"
exec > "$W/report/build.log" 2>&1

echo "== extract donor"
fsck.erofs --extract="$W/tree/system" --xattrs --preserve "$DONOR/system.img"
fsck.erofs --extract="$W/tree/system_ext" --xattrs --preserve "$DONOR/system_ext.img"
for m in my_product my_manifest my_stock my_region my_heytap my_bigball my_carrier my_engineering; do
    [ -d "$W/tree/system/$m" ] || { echo "missing mount point /$m"; exit 1; }
    rm -rf "$W/tmp_$m"
    fsck.erofs --extract="$W/tmp_$m" --xattrs --preserve "$DONOR/$m.img"
    # move the contents into the (labelled) mount point; the image's own root dir is dropped
    find "$W/tmp_$m" -mindepth 1 -maxdepth 1 -exec mv -t "$W/tree/system/$m/" {} +
    rm -rf "$W/tmp_$m"
done

echo "== apply port edits"
python3 -I "$HERE/apply_port_edits.py" "$HERE/c06-vs-beta4/PORT-EDITS.tsv" "$BETA4_SRC" "$W/tree"

echo "== IEngineer fix in oplus-services.jar (C.06 hangs system_server with ro.adb.secure=1)"
J="$W/tree/system/system/framework/oplus-services.jar"
[ "$(md5sum < "$J" | cut -c1-32)" = 2175feb9d4b03eb2859e73e71cfb854d ] || { echo "oplus-services.jar is not stock C.06"; exit 1; }
PATCH=engineer sh "$HERE/../module/tools/patch_framework.sh" "$J" "$W/eng.jar"
cat "$W/eng.jar" > "$J"; rm -f "$W/eng.jar"                        # same inode: label, owner, mode kept
[ "$(md5sum < "$J" | cut -c1-32)" = 7afeadb12583df3b1fdd92490e2e76cc ] || { echo "engineer patch gave an unexpected jar"; exit 1; }

echo "== label check"
for p in system system_ext; do
    python3 -I "$HERE/tree_manifest.py" "$W/tree/$p" > "$W/report/$p.tsv"
    n=$(awk -F'\t' '$7 !~ /security.selinux/' "$W/report/$p.tsv" | wc -l)
    echo "$p: $(wc -l < "$W/report/$p.tsv") entries, $n without a SELinux label"
    [ "$n" = 0 ] || { awk -F'\t' '$7 !~ /security.selinux/' "$W/report/$p.tsv" | head; exit 1; }
done

echo "== mkfs"
mkfs.erofs -zlz4hc -C65536 -T0 "$W/img/system.img" "$W/tree/system" > "$W/report/mkfs_system.log" 2>&1
mkfs.erofs -zlz4hc -C65536 -T0 "$W/img/system_ext.img" "$W/tree/system_ext" > "$W/report/mkfs_system_ext.log" 2>&1
cp "$DONOR/product.img" "$W/img/product.img"
cp "$PARTS/vendor_b.img" "$W/img/vendor.img"
cp "$PARTS/odm_b.img" "$W/img/odm.img"
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
