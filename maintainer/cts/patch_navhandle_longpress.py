#!/usr/bin/env python3
"""BUGS-TODO 49 (step 4v): shorter long press on the gesture bar for Circle to Search.

OplusLauncher (gesture mode) times the nav-handle long press with its own copy of OPLUS NavigationGestureDetector
(obfuscated, C.07: Lcom/android/quickstep/r4;). Its constructor sets the long-press threshold field to a constant
800 ms (`const/16 vX, 0x320` + `iput vX, p0, <int field>`); OplusCuiInputConsumer then starts the assistant
(Circle to Search). No setting or DeviceConfig key feeds it. SystemUI has the same detector
(com.oplus.systemui.navigationbar.gesture.sidegesture.NavigationGestureDetector) for the handle animation.
This patch changes the constant in place in the stored dex (only the zip CRCs change; the platform signature block
stays). It finds the class by the "NavigationGestureDetector#init" string in its constructor (not by name).
usage: patch_navhandle_longpress.py <apk> <out.apk> <ms>   (needs androguard: maintainer/jar-edits/venv)"""
import hashlib, io, struct, sys, zipfile, zlib
from androguard.core.dex import DEX

OLD = 800
MARK = b'NavigationGestureDetector#init'


def patch_dex(d, ms):
    dex = bytearray(d)
    hits = []
    for c in DEX(bytes(dex)).get_classes():
        for m in c.get_methods():
            if m.get_name() != '<init>' or m.get_code() is None:
                continue
            ins = list(m.get_instructions())
            if not any(x.get_name() == 'const-string' and MARK.decode() in x.get_output() for x in ins):
                continue
            off = m.get_code().get_off() + 16
            for i, x in enumerate(ins):
                reg = x.get_output().split(',')[0]
                if x.get_name() == 'const/16' and x.get_output() == '%s, %d' % (reg, OLD) \
                        and ins[i + 1].get_name() == 'iput' and ins[i + 1].get_output().startswith(reg + ', ') \
                        and ins[i + 1].get_output().endswith(' I'):
                    hits.append((c.get_name(), off))
                off += x.get_length()
    assert len(hits) == 1, f'800 ms threshold found {len(hits)} times: {hits}'
    cls, o = hits[0]
    assert dex[o] == 0x13 and struct.unpack_from('<h', dex, o + 2)[0] == OLD, dex[o:o + 4].hex()   # const/16 (21s)
    struct.pack_into('<h', dex, o + 2, ms)
    dex[12:32] = hashlib.sha1(dex[32:]).digest()
    dex[8:12] = struct.pack('<I', zlib.adler32(bytes(dex[12:])))
    return bytes(dex), cls


def main(src, dst, ms):
    ms = int(ms)
    assert 300 <= ms < OLD, ms
    apk = bytearray(open(src, 'rb').read())
    z = zipfile.ZipFile(io.BytesIO(apk))
    info = [i for i in z.infolist() if i.filename.endswith('.dex') and MARK in z.read(i.filename)]
    assert len(info) == 1, [i.filename for i in info]
    info = info[0]
    assert info.compress_type == 0, 'dex is deflated'
    lh = info.header_offset
    assert apk[lh:lh + 4] == b'PK\x03\x04'
    n, x = struct.unpack_from('<HH', apk, lh + 26)
    off = lh + 30 + n + x
    new, cls = patch_dex(bytes(apk[off:off + info.file_size]), ms)
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
    print(f'{info.filename}: {cls} long press {OLD} -> {ms} ms in place, crc32 {crc:08x}')


if __name__ == '__main__':
    if len(sys.argv) != 4:
        sys.exit(__doc__)
    main(*sys.argv[1:])
