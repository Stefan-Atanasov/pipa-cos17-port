#!/usr/bin/env python3
"""facehal-rs: HardwareAuthToken clock-skew tolerance 5 s -> 65 s (BUGS 132, 2026-11-18).
The HAT check (resetLockout; fn at 0x2da20) reads /proc/uptime and rejects a token whose timestamp is more than
5000 ms in the future. pipa's gatekeeper clock counts from power-on (bootloader included) and runs ~5.8 s ahead of
/proc/uptime, so every PIN token failed: resetLockout -> UNABLE_TO_PROCESS, face stayed locked out until a new
enrollment. One MOVZ immediate: mov w9, #0x1388 -> mov w9, #0xffff (65535 ms). The 10 min age limit stays.
usage: patch_hat_skew.py <in> <out>"""
import struct, sys
VA = 0x2e078
OFF = VA - 0x4000                       # text segment: file offset 0x22640 at VA 0x26640
OLD = 0x52800000 | 0x1388 << 5 | 9      # movz w9, #0x1388
NEW = 0x52800000 | 0xffff << 5 | 9      # movz w9, #0xffff
d = bytearray(open(sys.argv[1], 'rb').read())
cur, nxt = struct.unpack_from('<II', d, OFF)
assert nxt == 0xf9401a68, hex(nxt)     # ldr x8, [x19, #0x30] (HAT timestamp)
if cur == NEW:
    sys.exit('already patched')
assert cur == OLD, hex(cur)
struct.pack_into('<I', d, OFF, NEW)
open(sys.argv[2], 'wb').write(d)
print('facehal: HAT future skew 5000 -> 65535 ms')
