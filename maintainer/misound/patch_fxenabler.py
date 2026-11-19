#!/usr/bin/env python3
"""Stop the beta4 porter's "PipaFxEnabler" thread in MiSound.apk (BUGS 145).

beta4 added classes2.dex to MiSound with a stub miui.os.Build. Its static initializer starts a thread
"PipaFxEnabler": 3 s after each MiSound process start it opens priority 0 handles on session 0 for DAP and the
MiSound effect, enables both and keeps them for the life of the process. Stock HyperOS has no such code.
Effects: one MiSound DSP reset (audible blip) 3 s after MiSound starts, the MiSound effect enabled in the chain with
Dolby selected, and the pipa helper's effect holders without control while MiSound runs. The helper (DolbyKeeper)
does the boot job the stock way.

Patch: the Thread.start() call in Build.<clinit> becomes 3 nops (same size). The rest of the stub stays (MiSound
needs the class). The dex checksum and SHA-1 are recomputed. The zip entry keeps its total size (the shorter
deflate stream is balanced in the local header extra field), so all offsets, the central directory and the
porter's v3 signing block stay as they are; only the CRC and the sizes of the entry change. Android does not verify
the content of an APK on a system partition (it only reads the certificate), as for patch_ipemanager.py.
Pattern based: stops if the code is not the expected one.

    python3 -I patch_fxenabler.py <MiSound.apk in> <MiSound.apk out>
"""
import hashlib
import struct
import sys
import zlib

ENTRY = 'classes2.dex'


def uleb(b, o):
    r = s = 0
    while True:
        c = b[o]; o += 1
        r |= (c & 0x7f) << s; s += 7
        if c < 0x80:
            return r, o


def dex_methods(d):
    u32 = lambda o: struct.unpack_from('<I', d, o)[0]
    def string(i):
        o = u32(u32(0x3C) + 4 * i); _, o = uleb(d, o)
        return d[o:d.index(b'\0', o)].decode('utf-8', 'replace')
    types = [string(u32(u32(0x44) + 4 * i)) for i in range(u32(0x40))]
    shorty = [string(u32(u32(0x4C) + 12 * i)) for i in range(u32(0x48))]
    m = {}
    for i in range(u32(0x58)):
        cls, proto, name = struct.unpack_from('<HHI', d, u32(0x5C) + 8 * i)
        m.setdefault((types[cls], string(name), shorty[proto]), i)
    return m


def patch_dex(d):
    d = bytearray(d)
    assert d[:4] == b'dex\n', 'not a dex'
    assert b'PipaFxEnabler' in d and b'Lmiui/os/Build;' in d, 'no PipaFxEnabler stub: other MiSound build?'
    m = dex_methods(d)
    start = m.get(('Ljava/lang/Thread;', 'start', 'V'))
    daemon = m.get(('Ljava/lang/Thread;', 'setDaemon', 'VZ'))
    assert start is not None and daemon is not None, 'Thread.start/setDaemon not referenced'
    # invoke-virtual {v0, v1}, Thread.setDaemon(Z) ; invoke-virtual {v0}, Thread.start() ; return-void
    pat = (b'\x6e\x20' + struct.pack('<H', daemon) + b'\x10\x00'
           + b'\x6e\x10' + struct.pack('<H', start) + b'\x00\x00' + b'\x0e\x00')
    n = d.count(pat)
    if n == 0 and d.count(b'\x6e\x20' + struct.pack('<H', daemon) + b'\x10\x00' + b'\x00' * 6 + b'\x0e\x00') == 1:
        sys.exit('already patched')
    assert n == 1, f'start() pattern found {n} times (want 1)'
    o = d.index(pat) + 6
    d[o:o + 6] = b'\0' * 6                     # 3 x nop
    d[12:32] = hashlib.sha1(d[32:]).digest()
    d[8:12] = struct.pack('<I', zlib.adler32(bytes(d[12:])))
    return bytes(d)


def main(src, dst):
    a = bytearray(open(src, 'rb').read())
    # central directory entry of ENTRY
    eocd = a.rindex(b'PK\x05\x06')
    cd_off = struct.unpack_from('<I', a, eocd + 16)[0]
    p = cd_off; cde = None
    while a[p:p + 4] == b'PK\x01\x02':
        nl, el, cl = struct.unpack_from('<HHH', a, p + 28)
        if a[p + 46:p + 46 + nl].decode() == ENTRY:
            cde = p
            break
        p += 46 + nl + el + cl
    assert cde is not None, f'{ENTRY} not in the central directory'
    meth, = struct.unpack_from('<H', a, cde + 10)
    crc, csize, usize = struct.unpack_from('<III', a, cde + 16)
    lho, = struct.unpack_from('<I', a, cde + 42)
    assert meth == 8, 'entry is not deflated'
    assert a[lho:lho + 4] == b'PK\x03\x04'
    flag, = struct.unpack_from('<H', a, lho + 6)
    assert not flag & 8, 'data descriptor: not handled'
    lnl, lel = struct.unpack_from('<HH', a, lho + 26)
    data_off = lho + 30 + lnl + lel
    total = lel + csize                        # extra + data: kept constant
    old = zlib.decompress(bytes(a[data_off:data_off + csize]), -15)
    assert len(old) == usize and zlib.crc32(old) == crc, 'entry CRC mismatch'
    new = patch_dex(old)
    best = None
    for lvl in range(9, 0, -1):
        for mem in (9, 8):
            for strat in (zlib.Z_DEFAULT_STRATEGY, zlib.Z_FILTERED):
                c = zlib.compressobj(lvl, zlib.DEFLATED, -15, mem, strat)
                z = c.compress(new) + c.flush()
                pad = total - len(z)
                if pad == 0 or pad >= 4:
                    if best is None or len(z) > len(best):
                        best = z               # the longest fit = the smallest extra field
    assert best is not None, 'no deflate stream fits the old entry size'
    pad = total - len(best)
    extra = b'' if pad == 0 else struct.pack('<HH', 0xD935, pad - 4) + b'\0' * (pad - 4)
    ncrc = zlib.crc32(new)
    # local header: crc, sizes, extra length; then name, extra, data (same total length)
    struct.pack_into('<III', a, lho + 14, ncrc, len(best), len(new))
    struct.pack_into('<H', a, lho + 28, len(extra))
    name_end = lho + 30 + lnl
    a[name_end:name_end + total] = extra + best
    struct.pack_into('<III', a, cde + 16, ncrc, len(best), len(new))
    out = bytes(a)
    assert len(out) == len(open(src, 'rb').read())
    open(dst, 'wb').write(out)
    print(f'{ENTRY}: Thread.start() -> nop; deflate {csize} -> {len(best)} + extra {pad}; '
          f'md5 {hashlib.md5(out).hexdigest()}')


if __name__ == '__main__':
    if len(sys.argv) != 3:
        sys.exit(__doc__)
    main(sys.argv[1], sys.argv[2])
