#!/usr/bin/env python3
# Make HyperOS's vendor libgui_vendor.so load on the port (displayfeature HAL, ROM layer 2y).
#
#   python3 -I patch_gui_vendor.py in/libgui_vendor.so out/libgui_vendor.so
#
# libgui_vendor.so was built for VNDK v30 and needs 6 symbols that the port's newer vendor libui.so does not
# export (ui::Size::INVALID, to_string(Rect), 4 x HdrCapabilities): dlopen fails with
# 'cannot locate symbol "_ZN7android2ui4Size7INVALIDE"'. maintainer/displayfeature/ui_compat30.cpp provides them.
# There is no patchelf here, so instead of adding a DT_NEEDED this reuses one: the DT_NEEDED string
# "android.hardware.graphics.common@1.1.so" becomes "libui_compat30.so" (NUL-padded, same offset). That library
# supplies no symbol to libgui_vendor.so, and common@1.2 still loads it. The string must have exactly one reference
# in .dynstr (that DT_NEEDED): no symbol, version-need or other dynamic entry may point into it.
import hashlib, struct, sys

src, out = sys.argv[1], sys.argv[2]
STOCK_MD5 = '43f402b0160811fa006dc102c0999e53'   # HyperOS OS1.0.15.0.UMZMIXM vendor/lib64/libgui_vendor.so
OLD, NEW = b'android.hardware.graphics.common@1.1.so', b'libui_compat30.so'

d = bytearray(open(src, 'rb').read())
md5 = hashlib.md5(d).hexdigest()
if md5 != STOCK_MD5:
    sys.exit('libgui_vendor.so md5 %s, expected %s' % (md5, STOCK_MD5))

shoff, = struct.unpack_from('<Q', d, 0x28)
shentsize, shnum, shstrndx = struct.unpack_from('<HHH', d, 0x3a)
secs = [struct.unpack_from('<IIQQQQIIQQ', d, shoff + i * shentsize) for i in range(shnum)]
def name(s):
    o = secs[shstrndx][4] + s[0]
    return d[o:d.index(b'\0', o)].decode()
S = {name(s): s for s in secs}
dstr, dsize = S['.dynstr'][4], S['.dynstr'][5]
pos = d.find(OLD + b'\0', dstr, dstr + dsize)
if pos < 0 or d.count(OLD + b'\0', dstr, dstr + dsize) != 1:
    sys.exit('%s not found once in .dynstr' % OLD.decode())
start, end = pos - dstr, pos - dstr + len(OLD)

refs = []
dyn = S['.dynamic']
for k in range(dyn[5] // 16):
    tag, val = struct.unpack_from('<qQ', d, dyn[4] + 16 * k)
    if tag in (1, 14, 15, 29):   # NEEDED, SONAME, RPATH, RUNPATH
        refs.append((tag, val))
ds = S['.dynsym']
for k in range(ds[5] // 24):
    refs.append(('sym', struct.unpack_from('<I', d, ds[4] + 24 * k)[0]))
vn = S.get('.gnu.version_r')
if vn:
    o = vn[4]
    while True:
        _, cnt, vfile, aux, nxt = struct.unpack_from('<HHIII', d, o)
        refs.append(('vn_file', vfile))
        a = o + aux
        for _ in range(cnt):
            _, _, _, vname, anext = struct.unpack_from('<IHHII', d, a)
            refs.append(('vna_name', vname))
            a += anext
        if not nxt:
            break
        o += nxt
inside = [r for r in refs if start <= r[1] <= end]
if inside != [(1, start)]:
    sys.exit('unexpected references into the string: %s' % inside)

d[pos:pos + len(OLD)] = NEW + b'\0' * (len(OLD) - len(NEW))
open(out, 'wb').write(d)
print('libgui_vendor.so: DT_NEEDED %s -> %s; md5 %s; wrote %s'
      % (OLD.decode(), NEW.decode(), hashlib.md5(d).hexdigest(), out))
