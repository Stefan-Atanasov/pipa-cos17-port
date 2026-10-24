#!/usr/bin/env python3
"""Fix left/right on the speakers in the flipped landscape orientation (rotation 270).

Why: pipa has four Awinic aw882xx amps; the audio HAL (32-bit /vendor/lib/hw/audio.primary.kona.so,
the one android.hardware.audio.service loads) maps the display rotation that AudioService sends as
`rotation=` to the amps' `aw882xx_spin_switch` in set_eight_channel_each_speaker():
    0 -> 0 (spin_0)   90 -> 3 (spin_270)   180 -> 2 (spin_180)   270 -> 1 (spin_90)
Listening tests on the device (left-only noise): rotation 90 + spin_270 = correct; rotation 270 +
spin_90 = left/right swapped; rotation 270 + spin_270 = correct. Stock HyperOS ships the same table,
so Xiaomi's framework presumably compensates (Mi3DAudio rotation parameter); ColorOS does not.

Patch: the `mov r5, #1` of the 270 branch (VA 0x41990, file offset 0x40990) becomes `mov r5, #3`.
Portrait (0/180) is unchanged and untested.

usage: patch_audio_hal.py <in.so> <out.so>      (input md5 8725bcea7b5061fe84cc57b85e2f5266)
"""
import hashlib
import sys

STOCK_MD5 = "8725bcea7b5061fe84cc57b85e2f5266"
OFFSET = 0x40990
OLD = bytes.fromhex("0150a0e3")  # mov r5, #1
NEW = bytes.fromhex("0350a0e3")  # mov r5, #3


def main():
    if len(sys.argv) != 3:
        raise SystemExit(__doc__)
    data = bytearray(open(sys.argv[1], "rb").read())
    md5 = hashlib.md5(data).hexdigest()
    if md5 != STOCK_MD5:
        raise SystemExit(f"unexpected input md5 {md5} (expected {STOCK_MD5})")
    if data[OFFSET:OFFSET + 4] != OLD:
        raise SystemExit(f"unexpected bytes at {OFFSET:#x}: {data[OFFSET:OFFSET + 4].hex()}")
    data[OFFSET:OFFSET + 4] = NEW
    open(sys.argv[2], "wb").write(data)
    print("patched, md5", hashlib.md5(data).hexdigest())


if __name__ == "__main__":
    main()
