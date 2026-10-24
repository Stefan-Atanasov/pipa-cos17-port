#!/usr/bin/env python3
"""Patch the original developer's chargershim.jar (binary only): getPsyBatteryHmac() and getBattAuthenticate()
return 1 instead of 0. SystemUI's NotificationUtil.isBatteryOriginal() is `getPsyBatteryHmac() != 0`; 0 shows the
"battery may not be genuine" dialog and turns off some charging features (BUGS-TODO 12).

usage: patch_auth.py <in.jar> <out.jar>   (needs androguard: maintainer/jar-edits/venv)"""
import sys, zipfile, zlib, hashlib, struct
from androguard.core.dex import DEX

src, dst = sys.argv[1], sys.argv[2]
dex = bytearray(zipfile.ZipFile(src).read('classes.dex'))
d = DEX(bytes(dex))
done = 0
for c in d.get_classes():
    for m in c.get_methods():
        if m.get_name() not in ('getPsyBatteryHmac', 'getBattAuthenticate') or m.get_descriptor() != '()I':
            continue
        code = m.get_code()
        if code is None:
            continue
        ins = code.get_off() + 16                 # code_item header is 16 bytes
        if dex[ins:ins + 4] == b'\x12\x10\x0f\x00':
            print('already patched', c.get_name(), m.get_name()); done += 1; continue
        assert dex[ins:ins + 4] == b'\x12\x00\x0f\x00', (m.get_name(), dex[ins:ins + 4].hex())  # const/4 v0,0; return v0
        dex[ins + 1] = 0x10                        # const/4 v0, 1
        print('patched', c.get_name(), m.get_name()); done += 1
assert done == 2, done
dex[12:32] = hashlib.sha1(dex[32:]).digest()
dex[8:12] = struct.pack('<I', zlib.adler32(bytes(dex[12:])))
with zipfile.ZipFile(dst, 'w', zipfile.ZIP_DEFLATED) as z:
    z.writestr(zipfile.ZipInfo('classes.dex', (1980, 1, 1, 0, 0, 0)), bytes(dex))
