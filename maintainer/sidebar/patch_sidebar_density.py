#!/usr/bin/env python3
"""BUGS-TODO 206: Smart Sidebar 2x too big at Settings > Display > Screen resolution Low (9g).
SmartSideBar (com.coloros.smartsidebar) ignores the user density: SurfaceConfigurationUtil.resetDisplayDensity()
takes the initial density and the base display size from WindowManager, then checkDensity() looks the base width up
in WIDTH_DENSITY {1080: 480, 1440: TABLET_SW 640}. At Low the base width is 1440 (wm size 1440x2304), so the sidebar
draws at 640 dpi instead of 296 (x2.16). At High (1800) there is no entry: initial density 370, correct.
This patch changes the key 1440 to 1441 (no real display width) in SurfaceConfigurationUtil.<clinit> (same size,
in place):  const/16 v2, 1440 (13 02 a0 05)  ->  const/16 v2, 1441 (13 02 a1 05)
In place in the stored dex (only the zip CRCs change; the signature block stays).
usage: patch_sidebar_density.py <SmartSideBar.apk> <out.apk>   (needs androguard: maintainer/jar-edits/venv)"""
import hashlib, io, struct, sys, zipfile, zlib
from androguard.core.dex import DEX
CLS = 'Lcom/coloros/edgepanel/utils/SurfaceConfigurationUtil;'
WANT = [('const/16', 'v1, 480'), ('const/16', 'v2, 1080'), ('const/16', 'v1, 640'), ('const/16', 'v2, 1440')]
def patch_dex(d):
    dex = bytearray(d)
    ms = [m for c in DEX(bytes(dex)).get_classes() if c.get_name() == CLS
          for m in c.get_methods() if m.get_name() == '<clinit>']
    assert len(ms) == 1, f'<clinit> found {len(ms)} times'
    m = ms[0]
    base = m.get_code().get_off() + 16
    off, consts = 0, []
    for x in m.get_instructions():
        if x.get_name() == 'const/16':
            consts.append((off, x.get_name(), x.get_output()))
        off += x.get_length()
    got = [(n, o) for _, n, o in consts]
    if got and got[-1] == ('const/16', 'v2, 1441'):
        sys.exit('already patched')
    assert got == WANT, f'other code: {got}'
    o = base + consts[3][0]
    assert bytes(dex[o:o + 4]) == bytes([0x13, 0x02, 0xa0, 0x05]), bytes(dex[o:o + 4]).hex()
    dex[o + 2:o + 4] = bytes([0xa1, 0x05])
    dex[12:32] = hashlib.sha1(dex[32:]).digest()
    dex[8:12] = struct.pack('<I', zlib.adler32(bytes(dex[12:])))
    return bytes(dex)
def main(src, dst):
    apk = bytearray(open(src, 'rb').read())
    z = zipfile.ZipFile(io.BytesIO(apk))
    info = [i for i in z.infolist() if i.filename.endswith('.dex') and CLS[1:-1].encode() in z.read(i.filename)]
    info = [i for i in info if any(c.get_name() == CLS for c in DEX(z.read(i.filename)).get_classes())]   # defines it
    assert len(info) == 1, [i.filename for i in info]
    info = info[0]
    assert info.compress_type == 0, f'{info.filename} is compressed: no in-place patch'
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
    print(f'{info.filename}: WIDTH_DENSITY key 1440 -> 1441, crc32 {crc:08x}')


if __name__ == '__main__':
    if len(sys.argv) != 3:
        sys.exit(__doc__)
    main(sys.argv[1], sys.argv[2])
