#!/usr/bin/env python3
# Stop the Eye Protect app (com.oplus.eyeprotect) from zeroing the user's Bedtime / adaptive-colour settings at
# every process start (BUGS-TODO 13, replaces the ADAPTIVE_RESTORE / BEDTIME_STATE part of pipa_port service.sh).
#
#   python3 -I patch_eyeprotect.py in/OplusEyeProtect.apk out/OplusEyeProtect.apk [--legacy-switch]
#
# DRAFT, found by static analysis of the C.06 APK only. NOT tested on the tablet.
#
# OplusEyeProtectApp.onCreate posts a Runnable (s7/f) that calls OplusEyeProtectApp.j(app) on the main thread. The app
# process starts at every boot (TimeChangeReceiver gets LOCKED_BOOT_COMPLETED / BOOT_COMPLETED). j() does:
#   if (!hasFeature("oplus.software.display.intelligent_color_temperature_support"))   g8.h.D1(cr, false)
#         -> settings system setting_enable_color_temperature_regulation = 0   (adaptive colour; the framework key)
#   if (a1() || I0())                                                                  g8.h.E1(cr, false)
#         -> settings system oplus_customize_comfort_color_temperature_enable = 0      (no reader in the app)
#   if (I0()) { if (!Y(cr)) F1(cr, x0(cr)); g8.h.f2(cr, false); }
#         -> settings system oplus_customize_rhythm_health_enable = 0                  (standalone Bedtime; the
#            framework reads it in EyeProtectSettingsHelper.isRhythmOpen)
# pipa declares the feature (my_product/etc/permissions/oplus.product.display_features.xml), so the D1 call is skipped
# and f2(false) runs: that is the Bedtime reset. The D1 call is neutralised too (no cost, it only guards a missing
# feature). The E1 call is only changed with --legacy-switch (nothing in the app reads that key).
# Edit: each `invoke-static {v0, v2}, Lg8/h;->f2(ContentResolver,Z)V` (and D1 / E1) inside OplusEyeProtectApp.j is
# replaced by nops (same size). DO NOT make Lg8/h;->a1() return true: UmsServiceProvider.checkColorTemperature then
# zeroes the adaptive setting.
#
# The dex is changed in place, same size (it must be stored, not deflated); only the dex checksum/SHA-1 and the zip
# CRCs change, the signing block stays (CLAUDE.md "Patching a system app"). Delete the prebuilt oat/ next to the APK.
# The sites are found by structure (method ids resolved from the dex), not by offset; any other count aborts.
import hashlib, struct, sys, zipfile, zlib

args = [a for a in sys.argv[1:] if not a.startswith('--')]
legacy = '--legacy-switch' in sys.argv
src, dst = args
APP = 'Lcom/oplus/eyeprotect/OplusEyeProtectApp;'
HELP = 'Lg8/h;'
SIG = '(Landroid/content/ContentResolver;Z)V'


def uleb(b, o):
    r = s = 0
    while True:
        x = b[o]; o += 1
        r |= (x & 0x7f) << s; s += 7
        if x < 0x80:
            return r, o


class Dex:
    def __init__(self, d):
        self.d = d
        self.stro = struct.unpack_from('<I', d, 0x3c)[0]
        self.typo = struct.unpack_from('<I', d, 0x44)[0]
        self.protoo = struct.unpack_from('<I', d, 0x4c)[0]
        self.nmeth, self.metho = struct.unpack_from('<II', d, 0x58)
        self.ncls, self.clso = struct.unpack_from('<II', d, 0x60)

    def string(self, i):
        off = struct.unpack_from('<I', self.d, self.stro + 4 * i)[0]
        _, o = uleb(self.d, off)
        return bytes(self.d[o:self.d.index(b'\0', o)]).decode('utf8', 'replace')

    def type(self, i):
        return self.string(struct.unpack_from('<I', self.d, self.typo + 4 * i)[0])

    def proto(self, i):
        _, ret, params = struct.unpack_from('<III', self.d, self.protoo + 12 * i)
        ps = ''
        if params:
            n = struct.unpack_from('<I', self.d, params)[0]
            ps = ''.join(self.type(struct.unpack_from('<H', self.d, params + 4 + 2 * k)[0]) for k in range(n))
        return '(%s)%s' % (ps, self.type(ret))

    def method(self, i):
        c, p, n = struct.unpack_from('<HHI', self.d, self.metho + 8 * i)
        return self.type(c), self.string(n), self.proto(p)


def body_of_j(x):
    """(insns offset, insns byte length) of OplusEyeProtectApp.j(OplusEyeProtectApp)V"""
    d = x.d
    for ci in range(x.ncls):
        cls, _, _, _, _, _, cdata, _ = struct.unpack_from('<8I', d, x.clso + 32 * ci)
        if x.type(cls) != APP or not cdata:
            continue
        o = cdata
        sf, o = uleb(d, o); inf, o = uleb(d, o); dm, o = uleb(d, o); vm, o = uleb(d, o)
        for _ in range(sf + inf):
            _, o = uleb(d, o); _, o = uleb(d, o)
        idx = 0
        for _ in range(dm + vm):
            diff, o = uleb(d, o); _, o = uleb(d, o); code, o = uleb(d, o)
            idx += diff
            if code and x.method(idx) == (APP, 'j', '(%s)V' % APP):
                return code + 16, 2 * struct.unpack_from('<I', d, code + 12)[0]
    sys.exit('OplusEyeProtectApp.j not found')


def main():
    z = zipfile.ZipFile(src)
    name = None
    for n in z.namelist():
        if n.startswith('classes') and n.endswith('.dex') and APP.encode() in z.read(n):
            name = n
            break
    if not name:
        sys.exit('OplusEyeProtectApp not found')
    info = z.getinfo(name)
    if info.compress_type != zipfile.ZIP_STORED:
        sys.exit('%s is deflated; an in-place patch needs a stored dex' % name)
    d = bytearray(z.read(name))
    x = Dex(d)
    want = ['f2', 'D1'] + (['E1'] if legacy else [])
    mid = {}
    for i in range(x.nmeth):
        c, n, p = x.method(i)
        if c == HELP and n in want and p == SIG:
            mid[n] = i
    if set(mid) != set(want):
        sys.exit('g8.h methods missing: %s' % sorted(set(want) - set(mid)))
    ins, ln = body_of_j(x)
    patched = []
    for n, m in sorted(mid.items()):
        # f2 / E1 are static: invoke-static {vX, v2} = 71 20 <idx16> <regs16>; D1 is virtual: invoke-virtual
        # {v0, vX, v2} = 6e 30 <idx16> <regs16>. The register numbers are not fixed, the method id is.
        op, cnt = (0x6e, 3) if n == 'D1' else (0x71, 2)
        hits = [p for p in range(ins, ins + ln - 5, 2)
                if d[p] == op and d[p + 1] == cnt << 4 and struct.unpack_from('<H', d, p + 2)[0] == m]
        if len(hits) == 1:
            patched.append((n, hits[0]))
        else:
            sys.exit('%s: %d call sites in OplusEyeProtectApp.j, expected 1 (already patched?)' % (n, len(hits)))
    for n, p in patched:
        d[p:p + 6] = b'\x00' * 6                      # 3 x nop, same size as the 35c invoke
    d[12:32] = hashlib.sha1(d[32:]).digest()
    d[8:12] = struct.pack('<I', zlib.adler32(bytes(d[12:])) & 0xffffffff)

    apk = bytearray(open(src, 'rb').read())
    lh = info.header_offset
    fn, ex = struct.unpack_from('<HH', apk, lh + 26)
    start = lh + 30 + fn + ex
    assert len(d) == info.file_size and apk[start:start + 4] == b'dex\n'
    apk[start:start + len(d)] = d
    crc = zlib.crc32(d) & 0xffffffff
    struct.pack_into('<I', apk, lh + 14, crc)
    eocd = apk.rfind(b'PK\x05\x06')
    p = struct.unpack_from('<I', apk, eocd + 16)[0]
    while apk[p:p + 4] == b'PK\x01\x02':
        f, e, c = struct.unpack_from('<HHH', apk, p + 28)
        if struct.unpack_from('<I', apk, p + 42)[0] == lh:
            struct.pack_into('<I', apk, p + 16, crc)
            break
        p += 46 + f + e + c
    else:
        sys.exit('central directory entry not found')
    open(dst, 'wb').write(apk)
    for n, p in patched:
        print('%s: g8.h.%s call in OplusEyeProtectApp.j at +0x%x -> nop nop nop' % (name, n, p))
    print('crc32 %08x; wrote %s' % (crc, dst))


main()
