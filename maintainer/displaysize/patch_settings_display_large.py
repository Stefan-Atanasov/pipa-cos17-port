#!/usr/bin/env python3
"""BUGS-TODO 93 (step 7m): Settings > Display > Display size gets a "Large" option on pipa.

ColorOS Settings shows only Smaller/Default on devices with the oplus feature oplus.software.windowmode.compact
(ScreenZoomSettingsFragment.SCREEN_ZOOM_KEYS_LARGE_SCREEN; stock OPPO tablets have no Large either). Without the
feature it uses the phone path: Smaller / Default / Larger = ro.density.screenzoom[mid-1], [mid], [last]
(FontDisplayModel.initDisplayDensityArray; step 6g sets the list). The feature also drives the real compact-window
mode in the system, so it stays on; only the Display-size code in Settings is told "no compact window":

    invoke-static {}, L.../SysFeatureUtils;->isSupportCompactWindow()Z     (or CompatWindowUtil)
    move-result vX
becomes (same size, 8 bytes)
    const/4 vX, 0        (or const/16 for vX >= 16)
    nop ...

in every method of the classes CLASS_PREFIXES (Display-size page, its radio/preview controllers, FontDisplayModel)
and in SettingsUtils.normalizeScreenZoomSettingsIndex (else the saved choice "Large" is reset to Standard).
FontAndDisplaySettingsFragment (the Font & display page layout) is NOT patched: it keeps the tablet layout.
In place in the stored dex (only the zip CRCs change; the signature block stays).
usage: patch_settings_display_large.py <Settings.apk> <out.apk>   (needs androguard: maintainer/jar-edits/venv)"""
import hashlib, io, struct, sys, zipfile, zlib
from androguard.core.dex import DEX

CLASS_PREFIXES = ('Lcom/oplus/settings/feature/display/zoom/ScreenZoom',
                  'Lcom/oplus/settings/feature/display/font/FontDisplayModel;')
# single methods outside those classes (method-scoped, the rest of the class keeps the real value)
METHODS = (('Lcom/oplus/settings/utils/SettingsUtils;', 'normalizeScreenZoomSettingsIndex'),)
TARGETS = (';->isSupportCompactWindow()Z',)
OWNERS = ('SysFeatureUtils;', 'CompatWindowUtil;')


def patch_dex(d):
    dex = bytearray(d)
    hits = done = 0
    for c in DEX(bytes(dex)).get_classes():
        whole = c.get_name().startswith(CLASS_PREFIXES)
        names = [mn for cn, mn in METHODS if cn == c.get_name()]
        if not whole and not names:
            continue
        for m in c.get_methods():
            if not whole and m.get_name() not in names:
                continue
            code = m.get_code()
            if code is None:
                continue
            base = code.get_off() + 16
            ins = list(m.get_instructions())
            off = 0
            offs = []
            for x in ins:
                offs.append(base + off)
                off += x.get_length()
            for i, x in enumerate(ins[:-1]):
                out = x.get_output()
                if x.get_name() != 'invoke-static' or not any(t in out for t in TARGETS) \
                        or not any(o in out for o in OWNERS):
                    continue
                nxt = ins[i + 1]
                assert nxt.get_name() == 'move-result', (c.get_name(), m.get_name(), nxt.get_name())
                p, q = offs[i], offs[i + 1]
                assert dex[p] == 0x71 and dex[p + 1] >> 4 == 0 and q == p + 6 and dex[q] == 0x0a
                reg = dex[q + 1]
                if reg < 16:
                    new = bytes([0x12, reg]) + b'\x00' * 6                 # const/4 vX, 0 ; nop x3
                else:
                    new = bytes([0x13, reg, 0, 0]) + b'\x00' * 4           # const/16 vX, 0 ; nop x2
                dex[p:p + 8] = new
                hits += 1
            # already patched? (const/4 or const/16 ... 0 followed by nops is not detectable reliably; count none)
    if hits == 0:
        sys.exit('no isSupportCompactWindow call found in the Display-size classes (already patched or other version?)')
    dex[12:32] = hashlib.sha1(dex[32:]).digest()
    dex[8:12] = struct.pack('<I', zlib.adler32(bytes(dex[12:])))
    return bytes(dex), hits


def main(src, dst):
    apk = bytearray(open(src, 'rb').read())
    z = zipfile.ZipFile(io.BytesIO(apk))
    total = 0
    for info in z.infolist():
        if not info.filename.endswith('.dex'):
            continue
        data = z.read(info.filename)
        if b'isSupportCompactWindow' not in data or not (any(p[1:-1].encode() in data for p in CLASS_PREFIXES)
                                                          or b'normalizeScreenZoomSettingsIndex' in data):
            continue
        assert info.compress_type == 0, f'{info.filename} is compressed'
        lh = info.header_offset
        assert apk[lh:lh + 4] == b'PK\x03\x04'
        n, x = struct.unpack_from('<HH', apk, lh + 26)
        off = lh + 30 + n + x
        try:
            new, hits = patch_dex(bytes(apk[off:off + info.file_size]))
        except SystemExit:
            continue
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
        print(f'{info.filename}: {hits} isSupportCompactWindow call(s) -> false, crc32 {crc:08x}')
        total += hits
    if total == 0:
        sys.exit('nothing patched')
    open(dst, 'wb').write(apk)
    print(f'total {total} call sites patched')


if __name__ == '__main__':
    if len(sys.argv) != 3:
        sys.exit(__doc__)
    main(sys.argv[1], sys.argv[2])
