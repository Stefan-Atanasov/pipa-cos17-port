#!/bin/sh
# Phase 2j: idle drain + the KSU test scripts of 2026-10-24 folded into the ROM, on top of 2i. Run as root:
#
#   sudo sh build_beta5_2j.sh
#
# * pipa_port keyboard guard (port-rom/pipa_port/service.sh + config.prop KEYBOARD_GUARD): xiaomi-keyboard runs only
#   while the nanosic MCU reports the keyboard connected. Without it the daemon polls the accelerometer ~7x/s all
#   night (the driver's virtual "Xiaomi Keyboard" devices always exist), the SLPI sleeps 27 % and the SoC never
#   reaches AOSD/CXSD.
# * loc_sys_service `disabled`: it is `class main`, so commenting out its early-boot start (2a) never stopped it; it
#   retries the missing GNSS HAL once a second (replaces /data/adb/service.d/pipa-noloc.sh).
# * system_ext build.prop: debug.sf.enable_layer_caching=1, debug.sf.predict_hwc_composition_strategy=1 (smoothness
#   A/B 2026-10-24: small gain, no power cost; replaces /data/adb/post-fs-data.d/pipa-sf-test.sh).
# * product build.prop: drop the donor's traced.relay_producer_port=vsock://-1:2010 (our kernel has no vsock, so
#   traced dies at start and Perfetto does not work).
#
# Input: port-work/${TAG}-2i/tree/{system,system_ext}, port-work/${TAG}-2i/img. Output: port-work/${TAG}-2j/.
set -eu
TAG=${TAG:-beta5}
[ "$(id -u)" = 0 ] || { echo "run with sudo"; exit 1; }
P=${PIPA_ROOT:-/home/stefan/Documents/pipa}/port-work
IMGSRC=$P/${TAG}-2i/img
W=$P/${TAG}-2j
HERE=$(cd "$(dirname "$0")" && pwd)
ROM=$HERE/../port-rom
OWNER=${PIPA_OWNER:-stefan:stefan}
[ -f "$IMGSRC/super.img" ] || { echo "run build_beta5_2i.sh first"; exit 1; }

rm -rf "$W/tree"; mkdir -p "$W/tree" "$W/img" "$W/report"
exec > "$W/report/build.log" 2>&1
cp -a --reflink=auto "$P/${TAG}-2i/tree/system" "$P/${TAG}-2i/tree/system_ext" "$W/tree/"
SE=$W/tree/system_ext
echo "== product: extract"
fsck.erofs --extract="$W/tree/product" --xattrs --preserve "$IMGSRC/product.img"
PR=$W/tree/product

# in place (cat >): owner, mode and SELinux label stay
echo "== pipa_port"
for f in service.sh config.prop; do
    cat "$ROM/pipa_port/$f" > "$SE/pipa_port/$f"
    echo "updated system_ext/pipa_port/$f"
done
grep -q kb_guard "$SE/pipa_port/service.sh"

echo "== loc_sys_service disabled"
RC=$SE/etc/init/loc_sys_service.rc
grep -q '^    disabled' "$RC" && { echo "already patched"; exit 1; }
sed 's|^    oneshot$|    oneshot\n    disabled|' "$RC" > "$W/report/loc.rc"
cat "$W/report/loc.rc" > "$RC"
grep -q '^    disabled' "$RC"

echo "== system_ext build.prop: SurfaceFlinger"
BP=$SE/etc/build.prop
grep -q 'debug.sf.enable_layer_caching' "$BP" && { echo "already patched"; exit 1; }
printf '\n# pipa port: layer caching + HWC strategy prediction (smoothness A/B 2026-10-24)\ndebug.sf.enable_layer_caching=1\ndebug.sf.predict_hwc_composition_strategy=1\n' >> "$BP"

echo "== product build.prop: no vsock traced relay"
BP=$PR/etc/build.prop
grep -q '^traced.relay_producer_port=' "$BP"
grep -v '^traced.relay_producer_port=' "$BP" > "$W/report/product.prop"
cat "$W/report/product.prop" > "$BP"

echo "== label check"
for t in system_ext product; do
    python3 -I "$HERE/tree_manifest.py" "$W/tree/$t" > "$W/report/$t.tsv"
    n=$(awk -F'\t' '$7 !~ /security.selinux/' "$W/report/$t.tsv" | wc -l)
    echo "$t: $(wc -l < "$W/report/$t.tsv") entries, $n without a SELinux label"
    [ "$n" = 0 ] || exit 1
done

echo "== mkfs (system_ext, product)"
for t in system_ext product; do
    mkfs.erofs -zlz4hc -C65536 -T0 "$W/img/$t.img" "$W/tree/$t" > "$W/report/mkfs_$t.log" 2>&1
done
for p in system vendor odm; do cp --reflink=auto "$IMGSRC/$p.img" "$W/img/$p.img"; done
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
