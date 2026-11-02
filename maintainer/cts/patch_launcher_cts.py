#!/usr/bin/env python3
"""BUGS-TODO 49 (step 4e): Circle to Search on a long press of the gesture bar in the ColorOS CN launcher.

OplusLauncher has Circle to Search (navigation handle long press, Settings "circle_to_search_enable_navi"), but
FeatureOption.isSupportCircleToSearch is `isExp && hasSystemFeature("com.google.android.feature.CONTEXTUAL_SEARCH")`;
isExp is false on the CN donor. This patch removes only the isExp test there and in OplusHideNavHandleController.isSupportCircleToSearchHandle (the\ngesture-bar path; if-eqz v0 -> 2 nops, same size);
the feature test stays (step 4e adds the feature). The dex is stored, so it is patched in place: only the zip CRCs
change, OPPO's platform signature block stays (Android does not verify system APKs at boot).
usage: patch_launcher_cts.py <OplusLauncher.apk> <out.apk>   (needs androguard: maintainer/jar-edits/venv)"""
import hashlib, io, struct, sys, zipfile, zlib
from androguard.core.dex import DEX

# (class, method): each starts with "sget-boolean v0, FeatureOption.isExp; if-eqz v0, ..." -> the if-eqz becomes 2 nops
TARGETS = [('Lcom/android/common/config/FeatureOption;', 'isSupportCircleToSearch_delegate$lambda$10'),
           ('Lcom/android/launcher3/circlesearch/OplusHideNavHandleController$INSTANCE;', 'isSupportCircleToSearchHandle')]


def patch_dex(d, want):
    """Patch the TARGETS that are in this dex; returns (new dex, names patched)."""
    dex = bytearray(d)
    done = []
    for c in DEX(bytes(dex)).get_classes():
        for cls, name in want:
            if c.get_name() != cls:
                continue
            ms = [m for m in c.get_methods() if m.get_name() == name and m.get_descriptor() == '()Z']
            assert len(ms) == 1, f'{name} found {len(ms)} times'
            ins = ms[0].get_code().get_off() + 16
            assert dex[ins] == 0x63 and dex[ins + 1] == 0x00, (name, dex[ins:ins + 8].hex())  # sget-boolean v0
            if dex[ins + 4:ins + 8] == b'\0\0\0\0':
                sys.exit(f'{name}: already patched')
            assert dex[ins + 4] == 0x38 and dex[ins + 5] == 0x00, (name, dex[ins:ins + 8].hex())  # if-eqz v0
            dex[ins + 4:ins + 8] = b'\0\0\0\0'          # nop; nop
            done.append(name)
    if done:
        dex[12:32] = hashlib.sha1(dex[32:]).digest()
        dex[8:12] = struct.pack('<I', zlib.adler32(bytes(dex[12:])))
    return bytes(dex), done


def main(src, dst):
    apk = bytearray(open(src, 'rb').read())
    z = zipfile.ZipFile(io.BytesIO(apk))
    todo = list(TARGETS)
    for info in z.infolist():
        if not (info.filename.endswith('.dex') and info.compress_type == 0):
            continue
        data = z.read(info.filename)
        want = [t for t in todo if t[0][1:-1].encode() in data and t[1].encode() in data]
        if not want:
            continue
        new, done = patch_dex(data, want)
        if not done:
            continue
        todo = [t for t in todo if t[1] not in done]
        lh = info.header_offset
        assert apk[lh:lh + 4] == b'PK\x03\x04'
        n, x = struct.unpack_from('<HH', apk, lh + 26)
        off = lh + 30 + n + x
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
        print(f'{info.filename}: patched {", ".join(done)} in place, crc32 {crc:08x}')
    assert not todo, f'not found: {todo}'
    open(dst, 'wb').write(apk)


if __name__ == '__main__':
    if len(sys.argv) != 3:
        sys.exit(__doc__)
    main(sys.argv[1], sys.argv[2])
