# minimal payload.bin extractor (full OTA): python3 -I extract.py payload.bin outdir part [part...]
import sys, struct, lzma, bz2, zipfile
def varint(b, i):
    r = s = 0
    while True:
        c = b[i]; i += 1; r |= (c & 0x7f) << s; s += 7
        if c < 0x80: return r, i
def fields(b):
    i = 0; out = []
    while i < len(b):
        k, i = varint(b, i); f, t = k >> 3, k & 7
        if t == 0: v, i = varint(b, i)
        elif t == 2: n, i = varint(b, i); v = b[i:i+n]; i += n
        elif t == 1: v = b[i:i+8]; i += 8
        elif t == 5: v = b[i:i+4]; i += 4
        else: raise ValueError(t)
        out.append((f, v))
    return out
src, outdir, want = sys.argv[1], sys.argv[2], set(sys.argv[3:])
import os
Z = int(os.environ.get('ZOFF', '0'))
class F:
    def __init__(s, p): s.f = open(p, 'rb'); s.f.seek(Z)
    def read(s, n): return s.f.read(n)
    def seek(s, o): s.f.seek(Z + o)
fp = F(src)
assert fp.read(4) == b'CrAU'
ver, msize = struct.unpack('>QQ', fp.read(16)); sigsize = struct.unpack('>I', fp.read(4))[0] if ver >= 2 else 0
man = fp.read(msize); base = 24 + msize + sigsize if ver >= 2 else 20 + msize
mf = fields(man); bs = next((v for f, v in mf if f == 3), 4096)
for f, v in mf:
    if f != 13: continue
    p = fields(v); name = next(x for g, x in p if g == 1).decode()
    if name not in want: continue
    ops = [fields(x) for g, x in p if g == 8]
    print(name, len(ops), 'ops', flush=True)
    with open(f'{outdir}/{name}.img', 'wb') as o:
        for op in ops:
            d = dict((g, x) for g, x in op if g in (1, 2, 3))
            typ = d.get(1, 0); off = d.get(2, 0); ln = d.get(3, 0)
            ext = [dict(fields(x)) for g, x in op if g == 6]
            fp.seek(base + off); data = fp.read(ln)
            if typ == 8: data = lzma.decompress(data)
            elif typ == 1: data = bz2.decompress(data)
            elif typ == 0: pass
            elif typ == 6:
                for e in ext: o.seek(e.get(1, 0) * bs); o.write(b'\0' * (e.get(2, 0) * bs))
                continue
            else: raise SystemExit(f'op type {typ} not handled')
            pos = 0
            for e in ext:
                n = e.get(2, 0) * bs; o.seek(e.get(1, 0) * bs); o.write(data[pos:pos+n]); pos += n
    print('done', name, flush=True)
