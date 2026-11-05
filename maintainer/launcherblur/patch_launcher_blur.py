#!/usr/bin/env python3
"""NOT USED IN THE ROM. Let COUI widgets in OplusLauncher keep their material blur at animation tier 3.

Result of the live test (2026-11-04): this patch alone changed nothing on the home screen. The dock and folder blur
has its own gate, BlurUtils.isMaterialBlurJumpSupported() (tier 1-2, or the app feature
com.oplus.blur.support_upgrade_anim_material_blur). Step 5g sets that feature (config, no code edit). Keep this
script only for a later test of COUI widgets (pop-up menus, all-apps tabs) at tier 3.

COUI (com.coui.appcompat.COUIMaterialStateManager.h()Z) allows the material blur only for
1 <= persist.sys.oplus.anim_level < 3. The port runs the launcher at tier 3 (fast animations), so the home screen
had no blur (user 2026-11-04). The patch changes the upper bound of that one check from 3 to 4:

    const/4 v3, 0x3   (12 33)  ->  const/4 v3, 0x4   (12 43)      followed by  if-ge v0, v3

Tier 4 (light animations) still has no blur. Other COUI checks of the tier are not changed.

Usage (plain python3):  patch_launcher_blur.py <OplusLauncher.apk in> <OplusLauncher.apk out>
In place, same size, in the stored dex that has the class; only the dex checksum/SHA-1 and the zip CRC32 change.
The platform signature block stays (Android does not verify APKs on system partitions at boot). Do not re-sign.
Stops if the code is not exactly as expected (other launcher version).
"""
import io
import os
import struct
import sys
import zipfile
import zlib

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', 'ipe-fluid'))
from patch_ipemanager import Dex  # noqa: E402  (dex helpers: find_method, code_off, fix_header)

CLS = 'Lcom/coui/appcompat/COUIMaterialStateManager;'


def patch_dex(data):
    d = Dex(data)
    m_c = d.find_method(CLS, 'c', '()I')
    co = d.code_off(CLS, 'h', '()Z')
    regs, ins_n, outs, tries, _, insns = struct.unpack_from('<4HII', d.b, co)
    start = co + 16
    code = bytes(d.b[start:start + 2 * insns])
    # expected start: invoke-static {}, c()I ; move-result v0 ; const/4 v1,0 ; const/4 v2,1 ; if-gt v2, v0, +X
    head = bytes([0x71, 0x00]) + struct.pack('<HH', m_c, 0) + bytes([0x0a, 0x00, 0x12, 0x01, 0x12, 0x12, 0x36, 0x02])
    assert code.startswith(head), 'h() does not start as expected: ' + code[:16].hex()
    # then: const/4 v3, 3 ; if-ge v0, v3, +Y
    pat = bytes([0x12, 0x33, 0x35, 0x30])
    i = code.find(pat)
    assert i > 0 and code.find(pat, i + 1) < 0, 'const/4 v3, 3 + if-ge v0, v3 not found exactly once'
    d.b[start + i + 1] = 0x43
    d.fix_header()
    print(f'patched h()Z at dex offset 0x{start + i:x}: upper tier bound 3 -> 4')
    return bytes(d.b)


def main(src, dst):
    apk = bytearray(open(src, 'rb').read())
    z = zipfile.ZipFile(io.BytesIO(apk))
    hits = [i for i in z.infolist() if i.filename.endswith('.dex') and CLS[1:-1].encode() in z.read(i.filename)]
    # the class can be referenced from several dex files; patch the one that defines h()
    info = None
    for i in hits:
        try:
            Dex(z.read(i.filename)).code_off(CLS, 'h', '()Z')
            info = i
            break
        except SystemExit:
            continue
    assert info, 'no dex defines COUIMaterialStateManager.h()'
    assert info.compress_type == 0, 'dex is deflated: in-place patch not possible'
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
