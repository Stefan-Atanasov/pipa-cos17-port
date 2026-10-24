#!/bin/sh
# Phase 2g: the AudioX disable moves into the ROM, on top of 2f (system_ext only). Run as root:
#
#   sudo sh build_beta5_2g.sh
#
# ColorOS's sound service (com.oplus.audio.effectcenter, ro.oplus.audio.effect.type=audiox_merge) starts
# AudioxService at boot, which tries to create OPPO's AudioX effect 41f6c0f4-5d8f-11ec-bf63-0242ac130002.
# pipa's vendor has only Xiaomi's Dolby effect (dap), so every attempt fails and is retried every 3 s
# forever ("Failed to recreate AudioxEffect ... Error: -3"): wasted wakeups. Until now it was only disabled
# live on the tablet (pm disable), which a clean flash loses.
#
# Fix: a sysconfig <component-override>. SystemConfig parses it and
# ScanPackageUtils.configurePackageComponents applies it to the parsed component's default state at
# every package scan (read from the ROM's services.jar), so it holds after a clean flash and a dirty flash
# alike, and a later `pm enable` by the user still works. The Sound effects page only offers Xiaomi Sound
# and Dolby Atmos on this device (maintainer confirmed), so nothing visible is lost.
#
# Input: port-work/${TAG}-2f/tree/{system,system_ext}, port-work/${TAG}-2f/img. Output: port-work/${TAG}-2g/.
set -eu
TAG=${TAG:-beta5}   # base name: work dirs are port-work/$TAG, $TAG-baked, $TAG-2g, ... (build_port.sh sets it)
[ "$(id -u)" = 0 ] || { echo "run with sudo"; exit 1; }
P=${PIPA_ROOT:-/home/stefan/Documents/pipa}/port-work
IMGSRC=$P/${TAG}-2f/img
W=$P/${TAG}-2g
HERE=$(cd "$(dirname "$0")" && pwd)
OWNER=${PIPA_OWNER:-stefan:stefan}
LABEL=u:object_r:system_file:s0
[ -f "$IMGSRC/super.img" ] || { echo "run build_beta5_2f.sh first"; exit 1; }

rm -rf "$W/tree"; mkdir -p "$W/tree" "$W/img" "$W/report"
exec > "$W/report/build.log" 2>&1
cp -a --reflink=auto "$P/${TAG}-2f/tree/system" "$P/${TAG}-2f/tree/system_ext" "$W/tree/"
SE=$W/tree/system_ext

echo "== sysconfig component-override (AudioX)"
F=$SE/etc/sysconfig/pipa-component-overrides.xml
[ -d "$SE/etc/sysconfig" ] || { echo "system_ext/etc/sysconfig missing"; exit 1; }
cat > "$F" <<'EOF'
<?xml version="1.0" encoding="utf-8"?>
<!-- pipa port: ColorOS's AudioxService retries OPPO's AudioX effect (absent on pipa) every 3 s forever -->
<config>
    <component-override package="com.oplus.audio.effectcenter">
        <component class="com.oplus.audio.effectcenter.service.AudioxService" enabled="false" />
    </component-override>
</config>
EOF
chown 0:0 "$F"; chmod 644 "$F"
setfattr -n security.selinux -v "$LABEL" "$F"
echo "added   system_ext/etc/sysconfig/pipa-component-overrides.xml"

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
