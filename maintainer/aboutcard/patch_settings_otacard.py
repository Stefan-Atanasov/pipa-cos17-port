#!/usr/bin/env python3
"""BUGS-TODO 61 (step 4u): show the ColorOS banner card in Settings > About device, without an update action.

The ROM removes com.oplus.ota (OTA updater, see CLAUDE.md). OtaUpdateController.getAvailabilityStatus() then returns
CONDITIONALLY_UNAVAILABLE, and Settings hides the card "key_ota_update" (AboutDeviceOtaUpdatePreference: ColorOS logo,
model, version). Two edits in place in the stored dex (only the zip CRCs change; the platform signature block stays):
  1. getAvailabilityStatus: the last `if-eqz p0, :cond_57` (com.oplus.ota enabled?) becomes a nop -> AVAILABLE (0).
     The tests before it (not system user, GOTA, isOTANotSupport, isDisableOTA) stay.
  2. handlePreferenceTreeClick: for the card's own key, the `iget-boolean v0, p0, mGotaUpdateSupport` after the key
     test becomes `return v1` (v1 = true) + nop: the tap is consumed and starts nothing. The easter-egg test before
     it stays.
The card's update counter comes from SettingsUtils.getOtaData() (0 without the OTA app), so the card shows the
"no update" text and no "new version" button.
usage: patch_settings_otacard.py <Settings.apk> <out.apk>   (needs androguard: maintainer/jar-edits/venv)"""
import hashlib, io, struct, sys, zipfile, zlib
from androguard.core.dex import DEX

CLS = 'Lcom/oplus/settings/feature/deviceinfo/controller/OtaUpdateController;'


def find(dex, name, desc):
    ms = [m for c in dex.get_classes() if c.get_name() == CLS
          for m in c.get_methods() if m.get_name() == name and m.get_descriptor() == desc]
    assert len(ms) == 1, f'{name} found {len(ms)} times'
    return ms[0]


def walk(m):
    """(file offset, instruction) for each instruction of m"""
    off = m.get_code().get_off() + 16
    for x in m.get_instructions():
        yield off, x
        off += x.get_length()


def patch_dex(d):
    dex = bytearray(d)
    parsed = DEX(bytes(dex))

    # 1. getAvailabilityStatus: isApplicationInfoEnabled("com.oplus.ota") -> ... -> booleanValue; if-eqz p0 -> return 3
    m = find(parsed, 'getAvailabilityStatus', '()I')
    ins = list(walk(m))
    hits = [i for i, (o, x) in enumerate(ins) if x.get_name() == 'invoke-virtual' and 'booleanValue' in x.get_output()]
    assert len(hits) == 1, f'booleanValue calls: {len(hits)}'
    i = hits[0]
    assert 'isApplicationInfoEnabled' in ''.join(x.get_output() for _, x in ins[:i]), 'no com.oplus.ota test'
    (o1, mr), (o2, br), (o3, ret) = ins[i + 1], ins[i + 2], ins[i + 3]
    assert mr.get_name() == 'move-result', mr.get_name()
    if dex[o2:o2 + 4] == b'\0' * 4:
        sys.exit('already patched')
    assert br.get_name() == 'if-eqz' and br.get_length() == 4 and dex[o2] == 0x38, (br.get_name(), dex[o2:o2 + 4].hex())
    assert ret.get_name() == 'return' and 'v1' in ret.get_output(), (ret.get_name(), ret.get_output())
    dex[o2:o2 + 4] = b'\0' * 4                                                  # nop nop

    # 2. handlePreferenceTreeClick: key test, then iget-boolean mGotaUpdateSupport -> return v1 (true)
    m = find(parsed, 'handlePreferenceTreeClick', '(Landroidx/preference/Preference;)Z')
    ins = list(walk(m))
    hits = [i for i, (o, x) in enumerate(ins) if x.get_name() == 'iget-boolean' and 'mGotaUpdateSupport' in x.get_output()]
    assert len(hits) == 1, f'mGotaUpdateSupport reads: {len(hits)}'
    i = hits[0]
    assert ins[i - 1][1].get_name() == 'if-eqz' and 'TextUtils;->equals' in ins[i - 3][1].get_output(), 'no key test'
    assert any(x.get_name() == 'const/4' and x.get_output() == 'v1, 1' for _, x in ins[:i]), 'v1 is not true'
    o, x = ins[i]
    assert x.get_length() == 4 and dex[o] == 0x55, dex[o:o + 4].hex()        # iget-boolean (22c)
    dex[o:o + 4] = bytes([0x0f, 0x01, 0, 0])                                    # return v1 ; nop

    dex[12:32] = hashlib.sha1(dex[32:]).digest()
    dex[8:12] = struct.pack('<I', zlib.adler32(bytes(dex[12:])))
    return bytes(dex)


def main(src, dst):
    apk = bytearray(open(src, 'rb').read())
    z = zipfile.ZipFile(io.BytesIO(apk))
    key = CLS[1:-1].encode()
    info = [i for i in z.infolist() if i.filename.endswith('.dex') and key in z.read(i.filename)
            and b'getAvailabilityStatus' in z.read(i.filename) and b'mIsOtaEnabled' in z.read(i.filename)]
    assert len(info) == 1, [i.filename for i in info]
    info = info[0]
    assert info.compress_type == 0, 'dex is deflated'
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
    print(f'{info.filename}: OtaUpdateController patched in place (card visible, tap does nothing), crc32 {crc:08x}')


if __name__ == '__main__':
    if len(sys.argv) != 3:
        sys.exit(__doc__)
    main(sys.argv[1], sys.argv[2])
