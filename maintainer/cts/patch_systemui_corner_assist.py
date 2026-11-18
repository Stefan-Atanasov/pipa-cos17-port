#!/usr/bin/env python3
"""BUGS-TODO 98 (step 7s, user 2026-11-18): corner swipe -> default assistant (helper 2.0 routes it to Gemini).

SystemUI NavBarUtils.isAssistantAvailable(Context,int,int) returns false at once on CN builds (`if (!isExpRegion())
goto :return_false`) and when Circle to Search is supported (`if (sIsSupportCircleToSearch) goto :return_false`; stock
export ColorOS has no way to have both). Then the launcher never gets onAssistantAvailable(true) and the corner region
does not exist. Both goto/16 become nops; the AOSP checks after them stay (gesture mode, assistant component not Breeno,
Settings.Secure assist_touch_gesture_enabled).
In place in the stored dex (only the zip CRCs change; the platform signature block stays).
usage: patch_systemui_corner_assist.py <SystemUI.apk> <out.apk>   (needs androguard: maintainer/jar-edits/venv)"""
import hashlib, io, struct, sys, zipfile, zlib
from androguard.core.dex import DEX

CLS, NAME = 'Lcom/oplus/systemui/navigationbar/utils/NavBarUtils;', 'isAssistantAvailable'


def patch_dex(d):
    dex = bytearray(d)
    ms = [m for c in DEX(bytes(dex)).get_classes() if c.get_name() == CLS
          for m in c.get_methods() if m.get_name() == NAME and m.get_descriptor() == '(Landroid/content/Context; I I)Z'.replace('; ', ';')]
    if not ms:
        ms = [m for c in DEX(bytes(dex)).get_classes() if c.get_name() == CLS
              for m in c.get_methods() if m.get_name() == NAME and m.get_descriptor().replace(' ', '') == '(Landroid/content/Context;II)Z']
    assert len(ms) == 1, f'{NAME} found {len(ms)} times'
    m = ms[0]
    base = m.get_code().get_off() + 16
    ins, offs, o = list(m.get_instructions()), [], 0
    for x in ins:
        offs.append(base + o)
        o += x.get_length()
    sites = []
    for i, x in enumerate(ins[:-2]):
        out = x.get_output()
        if (x.get_name() == 'move-result' and 'isExpRegion' in ins[i - 1].get_output()) or \
           (x.get_name() == 'sget-boolean' and 'sIsSupportCircleToSearch' in out):
            j = i + 1
            while ins[j].get_name() not in ('if-nez', 'if-eqz'):
                j += 1
            g = ins[j + 1]
            if g.get_name() == 'nop':
                sys.exit('already patched')
            assert g.get_name() == 'goto/16', g.get_name()
            sites.append(offs[j + 1])
    assert len(sites) == 2, sites
    for p in sites:
        if dex[p:p + 4] == b'\0' * 4:
            sys.exit('already patched')
        assert dex[p] == 0x29 and dex[p + 1] == 0, dex[p:p + 4].hex()   # goto/16 +AAAA
        dex[p:p + 4] = b'\0' * 4                                       # nop, nop
    dex[12:32] = hashlib.sha1(dex[32:]).digest()
    dex[8:12] = struct.pack('<I', zlib.adler32(bytes(dex[12:])))
    return bytes(dex)

def main(src, dst):
    apk = bytearray(open(src, 'rb').read())
    z = zipfile.ZipFile(io.BytesIO(apk))
    info = [i for i in z.infolist() if i.filename.endswith('.dex') and i.compress_type == 0
            and b'NavBarUtils-->assist touch gesture disabled' in z.read(i.filename)]
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
