#!/usr/bin/env python3
"""BUGS-TODO 49 (step 4e): the ColorOS CN SystemUI starts no assistant (and no Circle to Search) from the gesture bar.

AssistManager.startAssist: `if (!isExpRegion() && !OpUtils.sIsClosedSuperFirewall) return;` (super firewall = OPPO test
mode). This patch turns the `goto :return` after the sIsClosedSuperFirewall test into a nop, so the AOSP path runs and
starts the user's assistant (Google: Circle to Search; Breeno stays reachable through its own entry points).
In place in the stored dex (only the zip CRCs change; the platform signature block stays).
usage: patch_systemui_assist.py <SystemUI.apk> <out.apk>   (needs androguard: maintainer/jar-edits/venv)"""
import hashlib, io, struct, sys, zipfile, zlib
from androguard.core.dex import DEX

CLS, NAME = 'Lcom/android/systemui/assist/AssistManager;', 'startAssist$1'


def patch_dex(d):
    dex = bytearray(d)
    ms = [m for c in DEX(bytes(dex)).get_classes() if c.get_name() == CLS
          for m in c.get_methods() if m.get_name() == NAME and m.get_descriptor() == '(Landroid/os/Bundle;)V']
    assert len(ms) == 1, f'{NAME} found {len(ms)} times'
    m = ms[0]
    base = m.get_code().get_off() + 16
    ins = list(m.get_instructions())
    off, hit = 0, None
    for i, x in enumerate(ins):
        if x.get_name() == 'sget-boolean' and 'sIsClosedSuperFirewall' in x.get_output():
            assert ins[i + 1].get_name() == 'if-nez', ins[i + 1].get_name()
            g = ins[i + 2]
            assert g.get_name() == 'goto', g.get_name()
            hit = base + off + ins[i].get_length() + ins[i + 1].get_length()
            glen = g.get_length()
            break
        off += x.get_length()
    assert hit, 'sIsClosedSuperFirewall test not found'
    if dex[hit:hit + glen] == b'\0' * glen:
        sys.exit('already patched')
    assert dex[hit] == 0x28 and glen == 2, (dex[hit:hit + 4].hex(), glen)   # goto +AA
    dex[hit:hit + 2] = b'\0\0'                                                # nop
    dex[12:32] = hashlib.sha1(dex[32:]).digest()
    dex[8:12] = struct.pack('<I', zlib.adler32(bytes(dex[12:])))
    return bytes(dex)


def main(src, dst):
    apk = bytearray(open(src, 'rb').read())
    z = zipfile.ZipFile(io.BytesIO(apk))
    info = [i for i in z.infolist() if i.filename.endswith('.dex') and i.compress_type == 0
            and b'sIsClosedSuperFirewall' in z.read(i.filename) and b'invocation_phone_state' in z.read(i.filename)]
    assert len(info) == 1, [i.filename for i in info]
    info = info[0]
    lh = info.header_offset
    assert apk[lh:lh + 4] == b'PK\x03\x04'
    n, x = struct.unpack_from('<HH', apk, lh + 26)
    off = lh + 30 + n + x
    new = patch_dex(bytes(apk[off:off + info.file_size]))
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
    print(f'{info.filename}: patched {NAME} in place, crc32 {crc:08x}')


if __name__ == '__main__':
    if len(sys.argv) != 3:
        sys.exit(__doc__)
    main(sys.argv[1], sys.argv[2])
