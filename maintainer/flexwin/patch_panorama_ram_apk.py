#!/usr/bin/env python3
"""BUGS 217 (step 9w): the app-side twins of the oplus-services panorama RAM test (step 9v).

OPPO decides "tablet panorama" in three places, each with its own RAM test. pipa has 8 GB (the kernel reports
7.41 GiB). 9v lowered the system_server test (oplus-services) to 6 GiB; the two apps still said "low RAM", so in
v10.1 (pt181) Recents drew the floating windows on top of the cards and the shell transitions took the fold path
(tester report 2026-11-27). This patch lowers the two app tests the same way (one constant each, same size):
  * OplusLauncher: com.oplus.quickstep.panorama.a.h() lazy (class op/h on the C.07 donor): RAM rounded up to
    whole GB (fp/f, MemoryInfoManager) > 8 -> > 6. Used by a.w() (Recents panorama layout, app transitions).
  * SystemUI (WM Shell): FullscreenTaskWindowDecorController.<init>: sRamSizeSupport = totalMem / 2^30 > 8.0 -> 6.0.
    Used by OplusPanoramaWorkBranchAnimController.isFunctionEnable() / isFoldPanoramaWorkEnable().
The dex is stored, so it is patched in place: only the dex checksum/SHA-1 and the zip CRCs change, OPPO's platform
signature block stays (Android does not verify system APKs at boot; same method as cts/patch_launcher_cts.py).
usage: patch_panorama_ram_apk.py <OplusLauncher.apk|SystemUI.apk> <out.apk>   (needs androguard: jar-edits/venv)"""
import hashlib, io, struct, sys, zipfile, zlib
from androguard.core.dex import DEX

# (class, method name, sanity bytes that must be in the method, old bytes, new bytes)
TARGETS = [
    # div-long/2addr v0, v2; long-to-int v4, v0; const/16 v0, 0x8; if-le v4, v0   (after const-wide/32 v2, 1 GiB)
    ('Lop/h;', 'invoke', bytes.fromhex('170200000040'),
     bytes.fromhex('be2084041300080037 04'.replace(' ', '')), bytes.fromhex('be2084041300060037 04'.replace(' ', ''))),
    # const-wide/high16 v4, 1.073741824E9; div-double/2addr v2, v4; const-wide/high16 v4, 8.0 (-> 6.0); cmpl-double
    ('Lcom/android/wm/shell/windowdecor/FullscreenTaskWindowDecorController;', '<init>', b'',
     bytes.fromhex('1904d041ce42190420402f020204'), bytes.fromhex('1904d041ce42190418402f020204')),
]


def patch_dex(d, targets):
    dex = bytearray(d)
    done = []
    for c in DEX(bytes(dex)).get_classes():
        for cls, name, sanity, old, new in targets:
            if c.get_name() != cls:
                continue
            hits = []
            for m in c.get_methods():
                if m.get_name() != name or m.get_code() is None:
                    continue
                code = m.get_code()
                a = code.get_off() + 16
                body = bytes(dex[a:a + 2 * code.get_insns_size()])
                if new in body and old not in body:
                    sys.exit(f'{cls}->{name}: already patched')
                if body.count(old) == 1 and sanity in body:
                    hits.append(a + body.index(old))
            assert len(hits) == 1, f'{cls}->{name}: RAM compare found in {len(hits)} methods (want 1)'
            dex[hits[0]:hits[0] + len(old)] = new
            done.append(cls)
    if done:
        dex[12:32] = hashlib.sha1(dex[32:]).digest()
        dex[8:12] = struct.pack('<I', zlib.adler32(bytes(dex[12:])))
    return bytes(dex), done


def main(src, dst):
    apk = bytearray(open(src, 'rb').read())
    z = zipfile.ZipFile(io.BytesIO(apk))
    patched = []
    for info in z.infolist():
        if not (info.filename.endswith('.dex') and info.compress_type == 0):
            continue
        data = z.read(info.filename)
        want = [t for t in TARGETS if t[0][1:-1].encode() in data]
        if not want:
            continue
        new, done = patch_dex(data, want)
        if not done:
            continue
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
        print(f'{info.filename}: RAM threshold 8 -> 6 in {", ".join(done)} (in place, crc32 {crc:08x})')
        patched += done
    assert len(patched) == 1, f'patched {patched} (want exactly one target per APK)'
    open(dst, 'wb').write(apk)


if __name__ == '__main__':
    if len(sys.argv) != 3:
        sys.exit(__doc__)
    main(sys.argv[1], sys.argv[2])
