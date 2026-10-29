#!/bin/sh
# Phase 2b: two vendor-side fixes on top of beta5-2a (notes/PHASE2-ROM-INTEGRATION.md A2 redo, B1).
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
# Old layer script: build_beta5_2b.sh
set -eu
. "$PORT/lib.sh"

V=$T/vendor

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

