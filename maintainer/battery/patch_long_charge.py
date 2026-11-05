#!/usr/bin/env python3
"""Stop ColorOS's "Set charging limit to 80%" pop-up after each boot (beta7.1, user 2026-11-05).

OPPO Battery (com.oplus.battery, /system_ext/app/Battery) reacts to the charger notify code in its battery event
handler (C.07: x8/k.d(int, Intent), event 0xe5): bit 28 (0x10000000, NOTIFY_CODE_LONG_CHARGE_LEVEL_ONE) shows the
"Set charging limit to 80%" dialog, bit 29 (0x20000000) sets the charging limit to 80 % by itself. OPPO's charger
driver sets these bits. On pipa the notify code comes from our charger shim, which always reports 0, but at boot the
handler gets one value with the bits set (the dialog came at every boot, notifyCode = 0 after that). The bits can
never be real on pipa, so the patch makes both masks 0:
    const/high16 vX, 0x10000000 ; and-int/2addr  ->  const/high16 vX, 0x0
    const/high16 vX, 0x20000000 ; and-int/2addr  ->  const/high16 vX, 0x0
The user's own charging limit (Settings > Battery) is not changed.

Usage (plain python3): patch_long_charge.py <Battery.apk in> <Battery.apk out>
In place, same size, in the stored dex; only the zip CRCs change and OPPO's signature block stays (as
../wallpapers/patch_blur_entry.py). Stops if the code is not exactly as expected.
"""
import importlib.util
import io
import os
import struct
import sys
import zipfile
import zlib

_spec = importlib.util.spec_from_file_location(
    'patch_ipemanager', os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', 'ipe-fluid', 'patch_ipemanager.py'))
_ipe = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(_ipe)
Dex = _ipe.Dex

CLS = 'Lx8/k;'
NAME = 'd'
SIG = '(ILandroid/content/Intent;)V'


def patch_dex(data):
    d = Dex(data)
    co = d.code_off(CLS, NAME, SIG)
    insns = struct.unpack_from('<I', d.b, co + 12)[0]
    start = co + 16
    code = bytes(d.b[start:start + 2 * insns])
    s_nc = d.find_string('notifycode')
    s_l1 = d.find_string('NOTIFY_CODE_LONG_CHARGE_LEVEL_ONE')
    for s in (s_nc, s_l1):
        assert s <= 0xffff
        assert any(code[i] == 0x1a and code[i + 2:i + 4] == struct.pack('<H', s) for i in range(0, len(code) - 3, 2)), \
            f'string {d.string(s)} not used in {CLS}->{NAME}'
    done = []
    for hi in (0x1000, 0x2000):
        hits = [i for i in range(0, len(code) - 5, 2)
                if code[i] == 0x15 and code[i + 2:i + 4] == struct.pack('<H', hi) and code[i + 4] == 0xb5]
        assert len(hits) == 1, f'const/high16 0x{hi:04x}0000 + and-int/2addr found {len(hits)} times'
        i = hits[0]
        d.b[start + i + 2:start + i + 4] = b'\x00\x00'
        done.append(f'0x{hi:04x}0000 at 0x{start + i:x}')
    d.fix_header()
    print(f'{CLS}->{NAME} code at 0x{co:x}: masks -> 0: ' + ', '.join(done))
    return bytes(d.b)


def main(src, dst):
    apk = bytearray(open(src, 'rb').read())
    z = zipfile.ZipFile(io.BytesIO(apk))
    info = None
    for i in z.infolist():
        if i.filename.endswith('.dex') and CLS[1:-1].encode() in z.read(i.filename):
            try:
                Dex(z.read(i.filename)).code_off(CLS, NAME, SIG)
            except SystemExit:
                continue
            assert info is None, 'code in two dex files'
            info = i
    assert info, f'no dex with {CLS}->{NAME}'
    assert info.compress_type == 0, f'{info.filename} is deflated'
    lh = info.header_offset
    assert apk[lh:lh + 4] == b'PK\x03\x04'
    n, x = struct.unpack_from('<HH', apk, lh + 26)
    off = lh + 30 + n + x
    old = bytes(apk[off:off + info.file_size])
    new = patch_dex(old)
    assert len(new) == len(old)
    apk[off:off + len(new)] = new
    crc = zlib.crc32(new) & 0xffffffff
    struct.pack_into('<I', apk, lh + 14, crc)
    eocd = apk.rfind(b'PK\x05\x06')
    p = struct.unpack_from('<I', apk, eocd + 16)[0]
    while apk[p:p + 4] == b'PK\x01\x02':
        fn, ex, cm = struct.unpack_from('<HHH', apk, p + 28)
        if struct.unpack_from('<I', apk, p + 42)[0] == lh:
            struct.pack_into('<I', apk, p + 16, crc)
            break
        p += 46 + fn + ex + cm
    else:
        raise SystemExit('central directory entry not found')
    open(dst, 'wb').write(apk)
    print(f'{info.filename}: patched in place, crc32 {crc:08x}')


if __name__ == '__main__':
    if len(sys.argv) != 3:
        sys.exit(__doc__)
    main(sys.argv[1], sys.argv[2])
