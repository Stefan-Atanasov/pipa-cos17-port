#!/usr/bin/env python3
"""Step 7p (user 2026-11-18): lock -> home "one shot" clock animation also at the port's Fast animation tier 3.
OplusLauncher and SystemUI switch the one-shot off for persist.sys.oplus.anim_level 3 and 4; the port default is 3
(Fast). Stock tier 1/2 runs it (live test 2026-11-18 at tier 2: works). Two same-size in-place dex edits:
  launcher  Lcom/android/common/util/s6;->h()Z (one-shot disabled flag):
      invoke-static {}, Lii/h;->j()Z ; move-result v0     (j() = tier 3 or 4)
   -> const/4 v0, 0 ; nop x3                              (only here; j() keeps gating the other animations)
  launcher  Lcom/android/keyguardservice/b;->f(FIII)I (one-shot spring duration / delay picker, user 2026-11-18:
      "plain fast movement" at tier 3): invoke-static {}, Lii/h;->b()Z ; move-result v3   (b() = tier 3/4: 850 ms
      springs -> 510-637 ms, delays 200 -> 120-150 ms)  -> const/4 v3, 0 ; nop x3: tier-2 timing for the one-shot only.
  systemui  Lcom/oplus/systemui/keyguard/oneshot/OneShotAnimState;->isOneShotEnabled()Z:
      const/4 v2, 2   (if animLevelOverride > 2: off)  -> const/4 v2, 3   (tier 4 still off)
      v2 is also the "platformGaussianLevel < 2" limit, used only when anim_level is unset (the ROM always sets it).
  clocks    KeyguardPersonalityClocks CommonUtils.isLowGaussianLevel (lazy): anim_level >= 3 = low. Low skips the
      digital clock render pipeline in SystemUI (PipelineHandlerRegistration: SceneTransitionHandler keyguard ->
      launcher = the clock flight), so the one-shot ended after ~20 ms (cut, no flight; log 2026-11-18).
      const/4 v0, 3 (if-lt) -> const/4 v0, 4: low only at tier 4, as the SystemUI limit.
In place in the stored dex (only the zip CRCs change; the signature block stays).
usage: patch_oneshot_fast.py launcher|systemui|clocks <in.apk> <out.apk>   (needs androguard: maintainer/jar-edits/venv)"""
import hashlib, io, struct, sys, zipfile, zlib
from androguard.core.dex import DEX

TARGETS = {   # app -> [(class, method, descriptor, edit)]; edit = call replaced by false, or a const/4 edit
    # (register, old value, branch name at +skip, skip, new value): the level limit before the compare
    'launcher': [('Lcom/android/common/util/s6;', 'h', '()Z', 'Lii/h;->j()Z'),
                 ('Lcom/android/keyguardservice/b;', 'f', '(F I I I)I', 'Lii/h;->b()Z')],
    'systemui': [('Lcom/oplus/systemui/keyguard/oneshot/OneShotAnimState;', 'isOneShotEnabled', '()Z',
                  (2, 2, 'if-gt', 2, 3))],
    'clocks':   [('Lcom/oplus/keyguard/clock/common/util/CommonUtils$isLowGaussianLevel$2;', 'invoke',
                  '()Ljava/lang/Boolean;', (0, 3, 'if-lt', 1, 4))],
}


def method_ins(dex, cls, meth, desc):
    for c in DEX(bytes(dex)).get_classes():
        if c.get_name() != cls:
            continue
        for m in c.get_methods():
            if m.get_name() == meth and m.get_descriptor().replace(' ', '') == desc.replace(' ', ''):
                code = m.get_code()
                base = code.get_off() + 16
                out, off = [], 0
                for x in m.get_instructions():
                    out.append((base + off, x))
                    off += x.get_length()
                return out
    return None


def patch_dex(d, which):
    dex = bytearray(d)
    hits = 0
    sites = []   # parse all methods first: the dex checksum is only valid before the first edit
    for cls, meth, desc, call in TARGETS[which]:
        ins = method_ins(dex, cls, meth, desc)
        if ins is None:
            return None if not sites else sys.exit(f'{which}: {cls}->{meth} not found')
        sites.append((ins, call))
    for ins, call in sites:
        hits += patch_method(dex, ins, call)
    if hits != len(TARGETS[which]):
        sys.exit(f'{which}: expected {len(TARGETS[which])} sites, found {hits} (already patched or other version?)')
    dex[12:32] = hashlib.sha1(dex[32:]).digest()
    dex[8:12] = struct.pack('<I', zlib.adler32(bytes(dex[12:])))
    return bytes(dex)


def patch_method(dex, ins, call):
    hits = 0
    if isinstance(call, str):
        for i, (p, x) in enumerate(ins[:-1]):
            if x.get_name() == 'invoke-static' and call in x.get_output():
                q, nxt = ins[i + 1]
                assert nxt.get_name() == 'move-result' and q == p + 6 and dex[p] == 0x71 and dex[q] == 0x0a
                reg = dex[q + 1]
                assert reg < 16
                dex[p:p + 8] = bytes([0x12, reg]) + b'\x00' * 6       # const/4 vX, 0 ; nop x3
                hits += 1
    else:
        reg, val, br, skip, newval = call
        names = [x.get_name() for _, x in ins]
        for i, (p, x) in enumerate(ins):
            if x.get_name() == 'const/4' and x.get_output() == f'v{reg}, {val}' and names[i + skip] == br:
                assert dex[p] == 0x12 and dex[p + 1] == (val << 4 | reg), hex(dex[p + 1])   # 0x12 = const/4, B|A
                dex[p + 1] = newval << 4 | reg
                hits += 1
    return hits


def main(which, src, dst):
    apk = bytearray(open(src, 'rb').read())
    z = zipfile.ZipFile(io.BytesIO(apk))
    cls = TARGETS[which][0][0][1:-1].encode()
    done = 0
    for info in z.infolist():
        if not info.filename.endswith('.dex'):
            continue
        data = z.read(info.filename)
        if cls not in data:
            continue
        assert info.compress_type == 0, f'{info.filename} is compressed'
        lh = info.header_offset
        assert apk[lh:lh + 4] == b'PK\x03\x04'
        n, x = struct.unpack_from('<HH', apk, lh + 26)
        off = lh + 30 + n + x
        new = patch_dex(bytes(apk[off:off + info.file_size]), which)
        if new is None:
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
        print(f'{which}: {info.filename} patched, crc32 {crc:08x}')
        done += 1
    if done != 1:
        sys.exit(f'{which}: patched {done} dex files, expected 1')
    open(dst, 'wb').write(apk)
    print(f'{which}: one-shot at tier 3 patched')


if __name__ == '__main__':
    if len(sys.argv) != 4 or sys.argv[1] not in TARGETS:
        sys.exit(__doc__)
    main(*sys.argv[1:])
