#!/bin/sh
# Phase 2b: two vendor-side fixes on top of beta5-2a (PHASE2-ROM-INTEGRATION.md A2 redo, B1).
# Run as root after build_beta5_2a.sh:
#
#   sudo sh build_beta5_2b.sh
#
# A2 redo: the 1c ueventd.rc lines never apply because the fuda power_supply fails its coldboot
#    synthetic uevent ("driver failed to report pin_enabled"), so the pen nodes stayed root-owned
#    and only pipa_core's chown fixed them. Now a vendor init rc chowns/chmods them on boot (runs as
#    vendor_init), with one vendor policy rule letting vendor_init setattr vendor_sysfs_battery_supply
#    files. The ueventd lines stay; they are harmless.
# B1 xiaomi-keyboard drain: with no /dev/input/event12 the daemon re-reads the accelerometer every
#    150 ms unless an internal flag is set. One branch is patched (vaddr 0x2504: tbnz w8,#0,0x24e0 ->
#    b 0x24e0) so a missing event12 always means the 3 s sleep. With a keyboard attached and the
#    module's event12 link the daemon behaves as before. Untested with a real keyboard (the
#    maintainer has none): if a keyboard user reports it broken, ask for logs and revisit.
#
# Input: port-work/${TAG}-1c/tree/vendor, port-work/${TAG}-2a/img. Output: port-work/${TAG}-2b/.
set -eu
TAG=${TAG:-beta5}   # base name: work dirs are port-work/$TAG, $TAG-baked, $TAG-2f, ... (build_port.sh sets it)
[ "$(id -u)" = 0 ] || { echo "run with sudo"; exit 1; }
SRC=${PIPA_ROOT:-/home/stefan/Documents/pipa}/port-work/${TAG}-1c
IMGSRC=${PIPA_ROOT:-/home/stefan/Documents/pipa}/port-work/${TAG}-2a/img
W=${PIPA_ROOT:-/home/stefan/Documents/pipa}/port-work/${TAG}-2b
HERE=$(cd "$(dirname "$0")" && pwd)
OWNER=${PIPA_OWNER:-stefan:stefan}
[ -f "$IMGSRC/super.img" ] || { echo "run build_beta5_2a.sh first"; exit 1; }

rm -rf "$W/tree"; mkdir -p "$W/tree" "$W/img" "$W/report"
exec > "$W/report/build.log" 2>&1
cp -a --reflink=auto "$SRC/tree/vendor" "$W/tree/"
V=$W/tree/vendor

echo "== A2 pen sysfs permissions via vendor init"
RC=$V/etc/init/pipa_port_pen.rc
[ -e "$RC" ] && { echo "$RC already exists"; exit 1; }
TEMPLATE=$(ls "$V"/etc/init/*.rc | head -n 1)
cp -a "$TEMPLATE" "$RC"          # label, owner and mode of a vendor init rc
cat > "$RC" <<'EOF'
# pipa port: pen wireless charger nodes written by system_server. ueventd.rc cannot set them: the
# fuda power_supply fails its coldboot synthetic uevent, so ueventd never sees the node.
on boot
    chown system system /sys/class/power_supply/fuda/reverse_chg_mode
    chown system system /sys/class/power_supply/fuda/reverse_pen_soc
    chown system system /sys/class/power_supply/wireless/pen_mac
    chown system system /sys/class/power_supply/wireless/reverse_pen_chg_state
    chmod 0664 /sys/class/power_supply/fuda/reverse_chg_mode
    chmod 0664 /sys/class/power_supply/fuda/reverse_pen_soc
    chmod 0664 /sys/class/power_supply/wireless/pen_mac
    chmod 0664 /sys/class/power_supply/wireless/reverse_pen_chg_state
EOF
echo "added   vendor/etc/init/pipa_port_pen.rc (label from ${TEMPLATE##*/})"
CIL=$V/etc/selinux/vendor_sepolicy.cil
grep -q '^(allow vendor_init_202604 ' "$CIL" || { echo "vendor_init_202604 not used in $CIL"; exit 1; }
grep -q '^(type vendor_sysfs_battery_supply)' "$CIL" || { echo "vendor_sysfs_battery_supply not declared"; exit 1; }
grep -q 'pipa_port_pen' "$CIL" && { echo "vendor cil already has the pen rule"; exit 1; }
cat >> "$CIL" <<'EOF'
; ---- pipa port 2026-10-22: pen charger nodes, chown/chmod from pipa_port_pen.rc (vendor_init) ----
(allow vendor_init_202604 vendor_sysfs_battery_supply (file (getattr setattr)))
EOF
echo "edited  vendor/etc/selinux/vendor_sepolicy.cil"

echo "== B1 xiaomi-keyboard branch patch"
python3 -I - "$V/bin/xiaomi-keyboard" <<'PY'
import hashlib, struct, sys
p = sys.argv[1]
d = open(p, 'rb').read()
assert hashlib.md5(d).hexdigest() == '448e8809e88466022e06c16b40e84c5a', 'unexpected xiaomi-keyboard md5'
off, old, new = 0x2504, 0x3707fee8, 0x17fffff7     # tbnz w8,#0,0x24e0 -> b 0x24e0
assert struct.unpack_from('<I', d, off)[0] == old
with open(p, 'r+b') as f:                            # same inode: label kept
    f.seek(off); f.write(struct.pack('<I', new))
print('patched xiaomi-keyboard', hashlib.md5(open(p, 'rb').read()).hexdigest())
PY

echo "== label check"
python3 -I "$HERE/tree_manifest.py" "$V" > "$W/report/vendor.tsv"
n=$(awk -F'\t' '$7 !~ /security.selinux/' "$W/report/vendor.tsv" | wc -l)
echo "vendor: $(wc -l < "$W/report/vendor.tsv") entries, $n without a SELinux label"
[ "$n" = 0 ] || exit 1

echo "== mkfs (vendor)"
mkfs.erofs -zlz4hc -C65536 -T0 "$W/img/vendor.img" "$V" > "$W/report/mkfs_vendor.log" 2>&1
for p in system system_ext product odm; do cp --reflink=auto "$IMGSRC/$p.img" "$W/img/$p.img"; done
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
