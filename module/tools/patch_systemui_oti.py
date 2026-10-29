#!/usr/bin/env python3
# Stop SystemUI from leaving ColorOS touch idle (OTI) paused after a screen-off (BUGS-TODO B11 follow-up).
#
#   python3 -I patch_systemui_oti.py in/SystemUI.apk out/SystemUI.apk
#
# SmoothTransitionController.disableAdfrOtiPwAndAutoResume(reason) sends notifyDisableAdfrOtiPwStatus (source 5,
# keyguard) to oplus_vrr_service and posts the "resume" 1.5 s later, but not when reason == "power_off" (going to
# sleep): then only notifyStartedWakingUp resumes. That path ignores a wake-up while SystemUI still has isScreenON
# (going to sleep started, but the screen did not turn off), so OTI stays paused (TouchIdleShouldPauseForce true,
# VrrState source 5 = 1) and the panel stays at 120/144 Hz until the next real screen-off. pipa is LCD without AOD,
# so the resume can also run after power_off: the edit changes `goto :return` after the equals() check to `nop nop`.
#
# The site is located by pattern: const-string/jumbo vA, "power_off"; invoke-virtual equals; move-result;
# if-eqz +3; goto (28 xx). It must occur exactly once in the dex files that have SmoothTransitionController. The dex is
# changed in place with the same size (it must be stored, not deflated); only the zip CRCs change, the signing
# block stays (see CLAUDE.md "Patching a system app"). Delete the prebuilt oat/ next to the APK.
# Verified on donor C.06 (SystemUI classes3.dex, method at 0x49cf7c).
import hashlib, re, struct, sys, zipfile, zlib

src, dst = sys.argv[1], sys.argv[2]
CLS = b'Lcom/oplus/systemui/aod/display/SmoothTransitionController;'


def uleb(b, o):
    r = s = 0
    while True:
        x = b[o]; o += 1
        r |= (x & 0x7f) << s; s += 7
        if x < 0x80:
            return r, o


def string_idx(d, s):
    n, so = struct.unpack_from('<II', d, 0x38)
    for i in range(n):
        off = struct.unpack_from('<I', d, so + 4 * i)[0]
        _, o = uleb(d, off)
        if d[o:o + len(s) + 1] == s + b'\0':
            return i
    sys.exit('string not in dex: %r' % s)


apk = bytearray(open(src, 'rb').read())
z = zipfile.ZipFile(src)
found, done = [], []
for n in z.namelist():
    if not re.fullmatch(r'classes\d*\.dex', n):
        continue
    b = z.read(n)
    if CLS not in b or b'power_off' not in b:
        continue
    d = bytearray(b)
    idx = string_idx(d, b'power_off')
    # 1b vA idx32 | 6e 20 meth16 regs16 | 0a vA | 38 vA 03 00 | 28 xx (goto) or 00 00 (patched)
    head = b'\x1b.' + re.escape(struct.pack('<I', idx)) + b'\x6e\x20....\x0a(.)\x38\\1\x03\x00'
    found += [(n, d, m.end() - 2) for m in re.finditer(head + b'\\x28.', d, re.S)]
    done += [n for m in re.finditer(head + b'\x00\x00', d, re.S)]
if not found and done:
    sys.exit('%s already patched' % done[0])
if len(found) != 1:
    sys.exit('%d power_off goto sites, expected 1' % len(found))
name, d, at = found[0]
hits = [at]
info = z.getinfo(name)
if info.compress_type != zipfile.ZIP_STORED:
    sys.exit('%s is deflated; an in-place patch needs a stored dex' % name)
d[hits[0]:hits[0] + 2] = b'\x00\x00'
d[12:32] = hashlib.sha1(d[32:]).digest()
d[8:12] = struct.pack('<I', zlib.adler32(bytes(d[12:])) & 0xffffffff)

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
print('%s: goto at +0x%x -> nop nop, crc32 %08x' % (info.filename, hits[0], crc))
