#!/usr/bin/env python3
"""Patch OPPO OShare so that tablet -> phone sharing works without the interconnect (BUGS-TODO 53).

Without the interconnect, OShare checks the receiver over BLE: com.oplus.oshare.utils.b0.y(info, sign, salt, ...)
asks the TEE (ICryptoeng, "GukManager") for a key that only genuine OPPO TEEs can derive, and compares an HMAC.
pipa has no such TEE app (our CryptoEngShim cannot know the OPPO secret), so the call throws
TAInterfaceException, y() returns false, and OShare shows "Recipient's transfer channel occupied".

This patch changes only the exception path of y(): the catch block starts with "move-exception p0" (0d 03); it
becomes "const/4 v0, 0x1" (12 10), so the final "return v0" returns true. The log call in the catch block stays (p0
still holds a String or byte[]). A real answer from a TEE (match or mismatch) is not changed.
Cost: the tablet no longer checks that the receiver is a genuine OPPO device. The transfer itself stays encrypted.

Usage (plain python3):
    patch_oshare.py <OShare.apk in> <OShare.apk out>
In place, same size, in the stored dex; only the zip CRCs change and OPPO's signature block stays (as
ipe-fluid/patch_ipemanager.py, whose Dex reader this uses). Stops if the code is not exactly as expected.
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

B0 = 'Lcom/oplus/oshare/utils/b0;'
SIG = '(Ljava/lang/String;Ljava/lang/String;Ljava/lang/String;Ljava/lang/String;)Z'


def patch_dex(data):
    d = Dex(data)
    s_tag = d.find_string('EncryptOrDecryptUtil')
    assert s_tag <= 0xffff, 'string index needs const-string/jumbo'
    co = d.code_off(B0, 'y', SIG)
    regs, ins_n, outs, tries, _, insns = struct.unpack_from('<4HII', d.b, co)
    assert (regs, ins_n, tries) == (7, 4, 1), (regs, ins_n, tries)   # .locals 3, 4 params (p0 = v3), one try block
    start = co + 16
    code = bytes(d.b[start:start + 2 * insns])
    # catch: move-exception v3 ; const-string v4, "EncryptOrDecryptUtil"
    pat = bytes([0x0d, 0x03, 0x1a, 0x04]) + struct.pack('<H', s_tag)
    a = code.find(pat)
    assert a > 0 and code.find(pat, a + 1) < 0, 'catch block not found exactly once'
    assert code[-2:] == b'\x0f\x00', 'method does not end with return v0'
    assert code[:2] == b'\x12\x00', 'method does not start with const/4 v0, 0x0'
    d.b[start + a:start + a + 2] = b'\x12\x10'                       # const/4 v0, 0x1
    d.fix_header()
    print(f'y() code at 0x{co:x}: catch at 0x{start + a:x}: move-exception p0 -> const/4 v0, 0x1')
    return bytes(d.b)


def main(src, dst):
    apk = bytearray(open(src, 'rb').read())
    z = zipfile.ZipFile(io.BytesIO(apk))
    info = None
    for i in z.infolist():
        if i.filename.endswith('.dex') and i.compress_type == 0 and B0[1:-1].encode() in z.read(i.filename):
            try:                                    # other dex files only refer to b0; take the one that has its code
                Dex(z.read(i.filename)).code_off(B0, 'y', SIG)
            except SystemExit:
                continue
            assert info is None, 'b0.y code in two dex files'
            info = i
    assert info, 'no stored dex with b0'
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
