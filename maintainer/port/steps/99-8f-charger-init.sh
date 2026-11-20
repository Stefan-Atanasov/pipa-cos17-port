#!/bin/sh
# Phase 8f (2026-11-20, BUGS 152): offline charging animation, part 2. 8d alone did nothing (pt133 test: Mi logo).
#
# * OPPO's /system/bin/init decides the charger boot in SecondStageMain itself (pt133 disassembly, OPPO init of the
#   C.07 donor): with ro.bootmode=charger it queues the AOSP "charger" trigger only on MediaTek (ro.soc.manufacturer
#   "Mediatek" and ro.boot.charger.mode != quickboot); on every other SoC `cbz w19, <late-init>` queues "late-init"
#   (OPPO QuickBoot: full boot without zygote; OPPO's /system_ext/bin/quickboot then draws the charge screen). On pipa
#   quickboot cannot draw (it looks for OPPO charger sysfs nodes; pstore: avc denials on "dc", "battery", "pc_port"), so
#   the bootloader logo stays, with the whole system running. pstore: device-captures/charger-mode-pt133/.
# * Fix: that one branch goes to the "charger" trigger instead (the same code path MediaTek uses), as stock HyperOS
#   (AOSP init: charger mode = `on charger` only). 8d's `class_start charger` then starts vendor.charger (Xiaomi health
#   HAL --charger, images in /vendor/etc/res/images/charger). Only a charger boot reaches this code: the branch is
#   inside `if (ro.bootmode == "charger")`; normal boots do not run it.
# * init.rc: OPPO's quickboot and bspFwUpdate (OPPO accessory firmware) are not started in charger mode on qcom.
# * Holding Power in the charger UI reboots into Android (AOSP charger, ro.enable_boot_charger_mode unset).
set -eu
. "$PORT/lib.sh"
STEP=8f
INIT=$T/system/system/bin/init
RC=$T/system/system/etc/init/hw/init.rc
[ -f "$INIT" ] || die "no $INIT"
python3 -I - "$INIT" "$R/init.charger" <<'PY'
import struct, sys
src, out = sys.argv[1], sys.argv[2]
b = bytearray(open(src, 'rb').read())
assert b[:4] == b'\x7fELF' and b[4] == 2, 'init: not ELF64'
phoff, = struct.unpack_from('<Q', b, 0x20)
phentsize, phnum = struct.unpack_from('<HH', b, 0x36)
def off(va):
    for i in range(phnum):
        p = phoff + i * phentsize
        ptype, _, poff, pva, _, pfs = struct.unpack_from('<IIQQQQ', b, p)
        if ptype == 1 and pva <= va < pva + pfs:
            return poff + va - pva
    raise SystemExit('va %x not in a LOAD segment' % va)
BR, CHARGER, LATE = 0xdde94, 0xded34, 0xddf0c
def cbz_w19(frm, to):
    return 0x34000000 | ((((to - frm) >> 2) & 0x7ffff) << 5) | 19
o = off(BR)
cur, = struct.unpack_from('<I', b, o)
want_old, want_new = cbz_w19(BR, LATE), cbz_w19(BR, CHARGER)
if cur == want_new:
    print('init: charger branch already patched')
else:
    assert cur == want_old, 'init: unexpected instruction %08x at %x (other init build?)' % (cur, BR)
    # the target must be the "charger" trigger: mov w8,#0xe (SSO length 7); mov w9,#0x6863 ("ch")
    t = off(CHARGER)
    assert struct.unpack_from('<II', b, t) == (0x528001c8, 0x528d0c69), 'init: charger trigger code not at %x' % CHARGER
    assert b.find(b'boot_charger_mode: ') > 0 and b.find(b'late-init\0') > 0, 'init: strings missing'
    struct.pack_into('<I', b, o, want_new)
    print('init: %x cbz w19 -> charger trigger (%08x -> %08x)' % (BR, want_old, want_new))
open(out, 'wb').write(b)
PY
cat "$R/init.charger" > "$INIT"   # in place: owner, mode, SELinux label stay

python3 -I - "$RC" "$R/init.rc.8f" <<'PY'
import sys
src, out = sys.argv[1], sys.argv[2]
s = open(src).read()
def comment(block_head, line):
    global s
    i = s.find(block_head)
    assert i >= 0 and s.count(block_head) == 1, 'init.rc: block not found once: ' + block_head
    j = s.find('\n\n', i)
    blk = s[i:j]
    if '# pipa (8f)' in blk:
        return
    assert blk.count(line) == 1, 'init.rc: %r not in %r' % (line, block_head)
    s = s[:i] + blk.replace(line, '\n    # pipa (8f): not on pipa (OPPO charge screen / OPPO accessory firmware)\n#' + line.lstrip('\n')) + s[j:]
comment('on property:ro.boot.hardware=qcom && property:ro.bootmode=charger\n', '\n    start quickboot')
comment('on property:ro.bootmode=charger\n  start bspFwUpdate', '\n  start bspFwUpdate')
open(out, 'w').write(s)
print('init.rc: quickboot and bspFwUpdate not started in charger mode')
PY
cat "$R/init.rc.8f" > "$RC"
grep -n -A3 '^on property:ro.boot.hardware=qcom && property:ro.bootmode=charger' "$RC"
grep -n -A3 '^on property:ro.bootmode=charger$' "$RC"
grep -q 'pipa (8d): stock charger UI' "$RC" || die "8d block missing (class_start charger)"
set_layer "$STEP"
