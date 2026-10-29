#!/bin/sh
# Phase 2y (test layer): Xiaomi's colour HAL "displayfeature" from stock HyperOS, on top of 2x (vendor + system_ext).
# Run as root:
#
#   sudo sh build_beta5_2y.sh
#
# * vendor: vendor.xiaomi.hardware.displayfeature@1.0-service + impl + displayfeature.default.so (the colour engine),
#   the libraries it needs that the port vendor lacks (Xiaomi libs, and old VNDK libs from HyperOS's VNDK apex),
#   the panel calibration files (miLut_0..17.txt, miLutInfo.txt, mdss_dsi_m82_*_mi.xml) and a VINTF fragment
#   (hwservicemanager registers only declared HIDL services). libgui_vendor.so is patched to load libui_compat30.so
#   (6 Android 11 libui symbols; maintainer/displayfeature/ui_compat30.cpp). The per-unit factory LUTs stay in
#   /mnt/vendor/persist/display (already on the device). Research: notes/DISPLAYFEATURE-RESEARCH.md.
# * system_ext: pipa_port.rc service pipa_displayfeature (system:graphics, seclabel pipa_port = permissive, so no
#   Xiaomi SELinux policy), service.sh/config.prop DISPLAYFEATURE=1 starts it after boot. Nothing calls it yet; test
#   client: maintainer/displayfeature/DfCall.java.
# * system_ext/etc/build.prop: ro.pipa.port.layer=2y.
#
# Input: port-work/${TAG}-2x/{tree/system,tree/system_ext,img/vendor.img}, port-work/${TAG}-2t/img (product, odm),
# reference/hyperos1-stock. Output: port-work/${TAG}-2y/.
set -eu
TAG=${TAG:-beta5}
STEP=2y
[ "$(id -u)" = 0 ] || { echo "run with sudo"; exit 1; }
ROOT=${PIPA_ROOT:-/home/stefan/Documents/pipa}
P=$ROOT/port-work
H=$ROOT/reference/hyperos1-stock
IMGSRC=$P/${TAG}-2t/img
W=$P/${TAG}-$STEP
HERE=$(cd "$(dirname "$0")" && pwd)
ROM=$HERE/../port-rom
OWNER=${PIPA_OWNER:-stefan:stefan}
UICOMPAT_MD5=85627c77f39a671b827225e96a4e1a67   # maintainer/displayfeature/libui_compat30.so (built from ui_compat30.cpp, NDK r30)
[ -f "$IMGSRC/super.img" ] || { echo "run build_beta5_2t.sh first"; exit 1; }
[ -f "$P/${TAG}-2x/img/vendor.img" ] && [ -d "$P/${TAG}-2x/tree/system_ext" ] || { echo "2x is missing: rebuild 2x"; exit 1; }
[ -f "$H/vendor/bin/hw/vendor.xiaomi.hardware.displayfeature@1.0-service" ] || { echo "HyperOS reference missing: $H"; exit 1; }

rm -rf "$W/tree" "$W/vndk"; mkdir -p "$W/tree" "$W/img" "$W/report" "$W/vndk"
exec > "$W/report/build.log" 2>&1
cp -a --reflink=auto "$P/${TAG}-2x/tree/system" "$P/${TAG}-2x/tree/system_ext" "$W/tree/"
echo "== vendor: extract (2x vendor.img)"
fsck.erofs --extract="$W/tree/vendor" --xattrs --preserve "$P/${TAG}-2x/img/vendor.img"
V=$W/tree/vendor
SE=$W/tree/system_ext

echo "== old VNDK libs from HyperOS's VNDK apex (com.android.vndk.current = v34)"
python3 -I -c "import sys, zipfile; open(sys.argv[2], 'wb').write(zipfile.ZipFile(sys.argv[1]).read('apex_payload.img'))" \
    "$H/system/system/apex/com.android.vndk.current.apex" "$W/vndk/payload.img"
VNDK="android.hardware.graphics.bufferqueue@1.0.so android.hardware.graphics.bufferqueue@2.0.so android.hidl.token@1.0.so android.hidl.token@1.0-utils.so android.hardware.media@1.0.so"
for l in $VNDK; do
    debugfs -R "dump /lib64/$l $W/vndk/$l" "$W/vndk/payload.img"
    [ -s "$W/vndk/$l" ] || { echo "not in the VNDK apex: $l"; exit 1; }
done

# add <src> <dst under vendor> <mode> <label>: new files only (never replace a vendor file)
add() {
    [ -e "$V/$2" ] && { echo "already in vendor: $2"; exit 1; }
    cp "$1" "$V/$2"
    chown 0:"$( [ "$3" = 755 ] && echo 2000 || echo 0 )" "$V/$2"
    chmod "$3" "$V/$2"
    setfattr -n security.selinux -v "u:object_r:$4:s0" "$V/$2"
    echo "added   vendor/$2"
}
echo "== displayfeature HAL"
add "$H/vendor/bin/hw/vendor.xiaomi.hardware.displayfeature@1.0-service" bin/hw/vendor.xiaomi.hardware.displayfeature@1.0-service 755 vendor_file
for l in vendor.xiaomi.hardware.displayfeature@1.0-impl.so displayfeature.default.so; do
    add "$H/vendor/lib64/hw/$l" "lib64/hw/$l" 644 vendor_file
done
for l in vendor.xiaomi.hardware.displayfeature@1.0.so libclient2slpi.notifier.so libtinyxml.so \
         vendor.xiaomi.hardware.citsensorservice@1.0.so vendor.xiaomi.hardware.citsensorservice@1.1.so; do
    add "$H/vendor/lib64/$l" "lib64/$l" 644 vendor_file
done
# libgui_vendor.so (VNDK v30) needs 6 symbols the port's libui.so lacks: libui_compat30.so provides them, and one
# unused DT_NEEDED of libgui_vendor.so now names it (no patchelf here). Without this, dlopen of the module fails.
python3 -I "$HERE/../module/tools/patch_gui_vendor.py" "$H/vendor/lib64/libgui_vendor.so" "$W/report/libgui_vendor.so"
add "$W/report/libgui_vendor.so" lib64/libgui_vendor.so 644 vendor_file
[ "$(md5sum "$HERE/displayfeature/libui_compat30.so" | cut -d' ' -f1)" = "$UICOMPAT_MD5" ] || { echo "libui_compat30.so md5 differs"; exit 1; }
add "$HERE/displayfeature/libui_compat30.so" lib64/libui_compat30.so 644 vendor_file
add "$H/system/system/lib64/android.frameworks.sensorservice@1.0.so" lib64/android.frameworks.sensorservice@1.0.so 644 vendor_file
for l in $VNDK; do add "$W/vndk/$l" "lib64/$l" 644 vendor_file; done
echo "== panel calibration (HyperOS vendor/etc)"
n=0
for f in "$H"/vendor/etc/miLut*.txt "$H"/vendor/etc/mdss_dsi_m82_*_mi.xml; do
    add "$f" "etc/${f##*/}" 644 vendor_configs_file; n=$((n + 1))
done
[ $n = 21 ] || { echo "expected 21 calibration files, got $n"; exit 1; }
echo "== VINTF fragment"
cat > "$W/report/pipa_displayfeature.xml" <<'EOF'
<!-- pipa port 2y: Xiaomi displayfeature HAL from HyperOS (hwservicemanager registers only declared HIDL services) -->
<manifest version="1.0" type="device">
    <hal format="hidl">
        <name>vendor.xiaomi.hardware.displayfeature</name>
        <transport>hwbinder</transport>
        <fqname>@1.0::IDisplayFeature/default</fqname>
    </hal>
</manifest>
EOF
add "$W/report/pipa_displayfeature.xml" etc/vintf/manifest/pipa_displayfeature.xml 644 vendor_configs_file

echo "== system_ext: pipa_port.rc, service.sh, config.prop"
cat "$ROM/pipa_port.rc" > "$SE/etc/init/pipa_port.rc"
for f in service.sh config.prop; do cat "$ROM/pipa_port/$f" > "$SE/pipa_port/$f"; done
grep -q '^service pipa_displayfeature ' "$SE/etc/init/pipa_port.rc"
grep -q 'ctl.start pipa_displayfeature' "$SE/pipa_port/service.sh"
grep -q '^DISPLAYFEATURE=1$' "$SE/pipa_port/config.prop"
if grep -v '^[[:space:]]*#' "$SE/pipa_port/service.sh" | grep -q '$(settings get'; then echo '$(settings get ...) cannot work in the service'; exit 1; fi

echo "== system_ext build.prop: ro.pipa.port.layer=$STEP"
BP=$SE/etc/build.prop
sed "s/^ro.pipa.port.layer=.*/ro.pipa.port.layer=$STEP/" "$BP" > "$W/report/build.prop.new"
cat "$W/report/build.prop.new" > "$BP"
grep "^ro.pipa.port.layer=$STEP\$" "$BP"

echo "== label check"
for t in vendor system_ext; do
    python3 -I "$HERE/tree_manifest.py" "$W/tree/$t" > "$W/report/$t.tsv"
    n=$(awk -F'\t' '$7 !~ /security.selinux/' "$W/report/$t.tsv" | wc -l)
    echo "$t: $(wc -l < "$W/report/$t.tsv") entries, $n without a SELinux label"
    [ "$n" = 0 ] || exit 1
done

echo "== mkfs (vendor, system_ext); system from 2x"
for t in vendor system_ext; do
    mkfs.erofs -zlz4hc -C65536 -T0 "$W/img/$t.img" "$W/tree/$t" > "$W/report/mkfs_$t.log" 2>&1
done
cp --reflink=auto "$P/${TAG}-2x/img/system.img" "$W/img/system.img"
for p in product odm; do cp --reflink=auto "$IMGSRC/$p.img" "$W/img/$p.img"; done
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
rm -rf "$W/vndk"
chown -R "$OWNER" "$W/img" "$W/report"
echo "== done"
