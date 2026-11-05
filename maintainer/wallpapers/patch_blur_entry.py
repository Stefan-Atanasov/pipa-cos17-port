#!/usr/bin/env python3
"""Show "Textured visual effects" (blur switches) in Personalization > More at animation tier 3 (step 5t).

OPPO Wallpapers (com.oplus.wallpapers, /my_stock/priv-app/Wallpapers) builds the Personalization "More" list in
MoreNewPersonalViewModel.p(Context, List). For the item page_blurred_texture_key it skips the item when
DeviceInfoUtilsKt.b() (persist.sys.oplus.anim_level, cached per process) is > 2:
    invoke-static {}, DeviceInfoUtilsKt;->b()I ; move-result v11 ; if-le v11, v10 (=2), :keep ; goto :skip
The patch changes "if-le v11, v10, +off" (37 ab off) into "goto/16 +off" (29 00 off): same size, same target, so the
item is always kept. The page itself (com.oplus.uxdesign BlurredTextureActivity) has no tier check.

Usage (plain python3): patch_blur_entry.py <Wallpapers.apk in> <Wallpapers.apk out>
In place, same size, in the stored dex; only the zip CRCs change and OPPO's signature block stays
(as ../oshare/patch_oshare.py). Stops if the code is not exactly as expected.
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

VM = 'Lcom/oplus/wallpapers/business/personalize/viewmodel/MoreNewPersonalViewModel;'
SIG = '(Landroid/content/Context;Ljava/util/List;)V'
DIU = 'Lcom/oplus/wallpapers/rely/utils/DeviceInfoUtilsKt;'
KEY = 'page_blurred_texture_key'


def patch_dex(data):
    d = Dex(data)
    co = d.code_off(VM, 'p', SIG)
    insns = struct.unpack_from('<I', d.b, co + 12)[0]
    start = co + 16
    code = bytes(d.b[start:start + 2 * insns])
    m_b = d.find_method(DIU, 'b', '()I')
    s_key = d.find_string(KEY)
    assert s_key <= 0xffff, 'string index needs const-string/jumbo'
    # invoke-static {}, b()I ; move-result v11 ; if-le v11, v10, +off
    pat = bytes([0x71, 0x00]) + struct.pack('<H', m_b) + bytes([0x00, 0x00, 0x0a, 0x0b, 0x37, 0xab])
    a = code.find(pat)
    assert a >= 0 and code.find(pat, a + 1) < 0, 'tier check not found exactly once'
    # the item key compare right before it: const-string v12, "page_blurred_texture_key"
    ks = bytes([0x1a, 0x0c]) + struct.pack('<H', s_key)
    k = code.rfind(ks, 0, a)
    assert 0 <= k and a - k <= 24, 'page_blurred_texture_key compare not right before the tier check'
    i = start + a + 8
    off = struct.unpack_from('<h', d.b, i + 2)[0]
    assert off > 0, 'unexpected branch direction'
    d.b[i:i + 2] = b'\x29\x00'                                   # goto/16 +off (same target)
    d.fix_header()
    print(f'p() code at 0x{co:x}: if-le v11, v10, +{off} at 0x{i:x} -> goto/16 +{off}')
    return bytes(d.b)


def main(src, dst):
    apk = bytearray(open(src, 'rb').read())
    z = zipfile.ZipFile(io.BytesIO(apk))
    info = None
    for i in z.infolist():
        if i.filename.endswith('.dex') and VM[1:-1].encode() in z.read(i.filename):
            try:
                Dex(z.read(i.filename)).code_off(VM, 'p', SIG)
            except SystemExit:
                continue
            assert info is None, 'p() code in two dex files'
            info = i
    assert info, 'no dex with MoreNewPersonalViewModel.p'
    assert info.compress_type == 0, f'{info.filename} is deflated (needs a stored dex)'
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
