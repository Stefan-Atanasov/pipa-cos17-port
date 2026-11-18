#!/usr/bin/env python3
"""Raise android:versionCode of a system APK in place, so that a vendor store never offers it an "update".

Usage: bump_version.py <in.apk> <out.apk> <old_versionCode> <new_versionCode>

Why: the OPPO App Market updates some preinstalled OPPO apps (BUGS-TODO 74). An update in /data/app replaces the
port's patched copy (e.g. OShare, step 4k). With a higher versionCode in the system copy the store sees no newer
version, and Android drops an older /data/app update at boot.

How: AndroidManifest.xml (binary XML, deflated) is inflated, the android:versionCode attribute of <manifest> (found by its
resource id 0x0101021b, must be TYPE_INT_DEC = old) is changed to new, and the entry is deflated
again with libdeflate level 12 (`libdeflate-gzip`; zlib -9 is larger than OPPO's original). The local entry keeps its
total length: the bytes saved go into the local header's extra field (a 0xD935 padding record, as zipalign writes).
So every later offset, the central directory offset and OPPO's APK signing block stay where they are; the CRC32 and
the compressed size change in both headers (Android does not verify APKs on system partitions at boot, the same as
the in-place dex patches of 2p and 4k).
"""
import struct
import subprocess
import sys
import zlib


def deflate_best(data):
    """Raw deflate stream of `data` from libdeflate level 12 (gzip wrapper removed)."""
    g = subprocess.run(['libdeflate-gzip', '-12', '-n', '-c'], input=data, capture_output=True, check=True).stdout
    raw = g[10:-8]
    assert zlib.decompress(raw, -15) == data
    return raw


VERSION_CODE_ATTR = 0x0101021b      # android:versionCode


def version_code_offset(man):
    """Offset of the Res_value (size, res0, type, data) of android:versionCode on <manifest> in binary XML.
    Found by the attribute's resource id, so a value that also occurs elsewhere (e.g. 37 = an SDK level) is no problem."""
    assert struct.unpack_from('<HH', man, 0) == (0x0003, 8), 'not binary XML'
    p, end, strings, resmap = 8, len(man), None, []
    while p < end:
        typ, hsz, size = struct.unpack_from('<HHI', man, p)
        if typ == 0x0001:                                              # string pool
            n, _, flags, sstart = struct.unpack_from('<IIII', man, p + 8)
            offs = struct.unpack_from(f'<{n}I', man, p + hsz)
            base = p + sstart

            def get(i, offs=offs, base=base, utf8=bool(flags & 0x100)):
                q = base + offs[i]
                if utf8:
                    q += 2 if man[q] & 0x80 else 1                     # utf16 length
                    ln = man[q] & 0x7f if not man[q] & 0x80 else ((man[q] & 0x7f) << 8) | man[q + 1]
                    q += 2 if man[q] & 0x80 else 1
                    return man[q:q + ln].decode('utf-8')
                ln, = struct.unpack_from('<H', man, q)
                return man[q + 2:q + 2 + 2 * ln].decode('utf-16-le')
            strings = get
        elif typ == 0x0180:                                            # resource map
            resmap = list(struct.unpack_from(f'<{(size - hsz) // 4}I', man, p + hsz))
        elif typ == 0x0102:                                            # start element
            name, = struct.unpack_from('<I', man, p + 20)
            astart, asize, acount = struct.unpack_from('<HHH', man, p + 24)
            if strings(name) == 'manifest':
                for k in range(acount):
                    a = p + 16 + astart + k * asize
                    an, = struct.unpack_from('<I', man, a + 4)
                    if an < len(resmap) and resmap[an] == VERSION_CODE_ATTR:
                        return a + 12
                raise AssertionError('no android:versionCode on <manifest>')
        p += size
    raise AssertionError('no <manifest> element')


def main(src, dst, old, new):
    apk = bytearray(open(src, 'rb').read())
    eocd = apk.rfind(b'PK\x05\x06')
    p = struct.unpack_from('<I', apk, eocd + 16)[0]
    cd = None
    while apk[p:p + 4] == b'PK\x01\x02':
        fn, ex, cm = struct.unpack_from('<HHH', apk, p + 28)
        if bytes(apk[p + 46:p + 46 + fn]) == b'AndroidManifest.xml':
            cd = p
            break
        p += 46 + fn + ex + cm
    assert cd is not None, 'AndroidManifest.xml not in the central directory'
    method, = struct.unpack_from('<H', apk, cd + 10)
    csize, usize = struct.unpack_from('<II', apk, cd + 20)
    lh, = struct.unpack_from('<I', apk, cd + 42)
    assert apk[lh:lh + 4] == b'PK\x03\x04' and method == 8, 'manifest is not deflated'
    n, x = struct.unpack_from('<HH', apk, lh + 26)
    off = lh + 30 + n + x
    man = zlib.decompress(bytes(apk[off:off + csize]), -15)
    assert len(man) == usize
    at = version_code_offset(man)
    assert man[at:at + 4] == b'\x08\x00\x00\x10' and struct.unpack_from('<I', man, at + 4)[0] == old, \
        f'manifest versionCode is not {old}'
    man2 = man[:at + 4] + struct.pack('<I', new) + man[at + 8:]
    comp = deflate_best(man2)
    d = csize - len(comp)
    assert d >= 4, f'new deflate stream is not smaller ({len(comp)} vs {csize})'
    assert x + d <= 0xffff
    pad = struct.pack('<HH', 0xD935, d - 4) + bytes(d - 4)      # one extra record of d bytes
    entry = bytes(apk[lh + 30:lh + 30 + n + x]) + pad + comp      # name, old extra, padding, data
    assert len(entry) == n + x + csize
    apk[lh + 30:off + csize] = entry
    crc = zlib.crc32(man2) & 0xffffffff
    struct.pack_into('<I', apk, lh + 14, crc)
    struct.pack_into('<I', apk, lh + 18, len(comp))
    struct.pack_into('<H', apk, lh + 28, x + d)
    flags, = struct.unpack_from('<H', apk, lh + 6)
    if flags & 8:                                                  # data descriptor after the data: crc, csize, usize
        dd = off + csize
        q = dd + 4 if apk[dd:dd + 4] == b'PK\x07\x08' else dd
        assert struct.unpack_from('<I', apk, q + 4)[0] == csize, 'data descriptor not found'
        struct.pack_into('<II', apk, q, crc, len(comp))
    struct.pack_into('<I', apk, cd + 16, crc)
    struct.pack_into('<I', apk, cd + 20, len(comp))
    open(dst, 'wb').write(apk)
    print(f'AndroidManifest.xml: versionCode {old} -> {new}, deflate {csize} -> {len(comp)} + {d} bytes extra padding, crc32 {crc:08x}')


if __name__ == '__main__':
    if len(sys.argv) != 5:
        sys.exit(__doc__)
    main(sys.argv[1], sys.argv[2], int(sys.argv[3]), int(sys.argv[4]))
