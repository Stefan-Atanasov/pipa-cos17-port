#!/usr/bin/env python3
"""BUGS-TODO 200: show Settings > Additional settings > Google (Google Mobile Services switch) again.

Settings shows the entry only if SettingsUtils.isGoogleAccountSupport() (= hasSystemFeature("cn.google.services"))
and SysFeatureUtils.isGmsControlSupport() (= oplus feature oplus.software.disable_cn_gms) are true
(GoogleSettingPreferenceController / OplusGoogleSettingsPreferenceController.isPreferenceAvailable). Step 4l removed
cn.google.services (with it GMS treats the tablet as a China device and turns Quick Share off, BUGS 53), so the
switch was hidden. This patch makes isGoogleAccountSupport return true (same size, in place):
    invoke-static {}, SettingsApplicationEx->getAppContext   ->   const/4 v0, 1
                                                                return v0     (the old code after it is dead)
In place in the stored dex (only the zip CRCs change; the platform signature block stays).
usage: patch_settings_google_switch.py <Settings.apk> <out.apk>   (needs androguard: maintainer/jar-edits/venv)"""
import hashlib, io, struct, sys, zipfile, zlib
from androguard.core.dex import DEX

CLS = 'Lcom/oplus/settings/utils/SettingsUtils;'
NAME = 'isGoogleAccountSupport'
WANT = ['invoke-static', 'move-result-object', 'invoke-virtual', 'move-result-object', 'const-string',
        'invoke-virtual', 'move-result', 'return']


def patch_dex(d):
    dex = bytearray(d)
    ms = [m for c in DEX(bytes(dex)).get_classes() if c.get_name() == CLS
          for m in c.get_methods() if m.get_name() == NAME]
    assert len(ms) == 1, f'{NAME} found {len(ms)} times'
    m = ms[0]
    base = m.get_code().get_off() + 16
    ins = list(m.get_instructions())
    names = [x.get_name() for x in ins]
    if names[:2] == ['const/4', 'return']:
        sys.exit('already patched')
    assert names == WANT, f'other code: {names}'
    assert '"cn.google.services"' in ins[4].get_output(), ins[4].get_output()
    assert 'hasSystemFeature' in ins[5].get_output(), ins[5].get_output()
    assert dex[base] == 0x71, 'not invoke-static'
    dex[base:base + 4] = bytes([0x12, 0x10, 0x0f, 0x00])   # const/4 v0, 1 ; return v0
    dex[12:32] = hashlib.sha1(dex[32:]).digest()
    dex[8:12] = struct.pack('<I', zlib.adler32(bytes(dex[12:])))
    return bytes(dex)


def main(src, dst):
    apk = bytearray(open(src, 'rb').read())
    z = zipfile.ZipFile(io.BytesIO(apk))
    info = [i for i in z.infolist() if i.filename.endswith('.dex')
            and b'isGoogleAccountSupport' in z.read(i.filename) and b'cn.google.services' in z.read(i.filename)]
    info = [i for i in info if CLS[1:-1].encode() in z.read(i.filename)]
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
    print(f'{info.filename}: {NAME} returns true, crc32 {crc:08x}')


if __name__ == '__main__':
    if len(sys.argv) != 3:
        sys.exit(__doc__)
    main(sys.argv[1], sys.argv[2])
