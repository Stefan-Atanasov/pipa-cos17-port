#!/bin/sh
# 6k (tester, beta8, 2026-11-12): the keyboard cover still types when it is folded behind the tablet.
#
# Cause: xiaomi-keyboard computes the cover angle and writes 32 FF 00/01 to /dev/nanodev0, and our kernel dropped
# that write (the driver forwarded only 66-byte MCU frames). Kernel walt-r20 acts on it (debounced, see the commit
# "nanosic: act on the fold request of xiaomi-keyboard") and has /proc/nanokbd, which exists exactly while the keypad
# is attached. Stock HyperOS does the same job in miui-services (angle 45..185 degrees, InputManager disables the
# keyboard, consumer and touchpad devices).
# * vendor/bin/xiaomi-keyboard: the "keypad present" path /dev/input/event12 (rodata 0xbe5) becomes /proc/nanokbd.
#   The 2b branch patch stays: flag missing = 3 s sleep, no accelerometer read. So the daemon samples the
#   accelerometer only while a keypad is attached (also if the keyboard guard is off), whatever the event numbers
#   are, and it still sees the unfold after the kernel removed the input devices. With a kernel before walt-r20 the
#   flag never exists: no fold detection (it did nothing there anyway) and no sampling.
# * pipa_port service.sh + config.prop (KEYBOARD_FOLD_REMOVE=1): one write of fold_remove=1 at service start; the
#   event12 link is skipped on walt-r20+.
# * No layer change (no APK or jar changes).
# NOT TESTED when written (2026-11-12, offline, the maintainer has no keyboard cover). Check with the cover:
# `cat /proc/nanokbd` (attached=1), fold behind: after ~1 s `fold_off=1`, `dumpsys input` has no Xiaomi devices,
# keys do nothing, the on-screen keyboard works; unfold: devices back at once. Screen off/on and a power button
# press with the cover open must not remove the devices. Without the cover: `pgrep xiaomi-keyboard` empty.
#NEEDS: "$ROM/pipa_port/service.sh" "$ROM/pipa_port/config.prop"
set -eu
. "$PORT/lib.sh"

SE=$T/system_ext
V=$T/vendor

echo "== 6k xiaomi-keyboard: keypad present flag /proc/nanokbd"
python3 -I - "$V/bin/xiaomi-keyboard" <<'PY'
import hashlib, sys
p = sys.argv[1]
d = open(p, 'rb').read()
assert hashlib.md5(d).hexdigest() == '928a34ad6be0cd09f227e5649d9edf90', 'unexpected xiaomi-keyboard md5 (want 2b)'
off, old, new = 0xbe5, b'/dev/input/event12\0', b'/proc/nanokbd\0'
assert d[off:off + len(old)] == old and d.count(old) == 1
with open(p, 'r+b') as f:                            # same inode: label kept
    f.seek(off); f.write(new.ljust(len(old), b'\0'))
print('patched xiaomi-keyboard', hashlib.md5(open(p, 'rb').read()).hexdigest())
PY

echo "== 6k pipa_port: fold_remove on walt-r20+"
for f in service.sh config.prop; do
    cat "$ROM/pipa_port/$f" > "$SE/pipa_port/$f"
    echo "updated system_ext/pipa_port/$f"
done
need_grep 'KB_FOLD=/sys/module/nanosic_driver_v2/parameters/fold_remove' "$SE/pipa_port/service.sh"
need_grep '^KEYBOARD_FOLD_REMOVE=1$' "$SE/pipa_port/config.prop"
