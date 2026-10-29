#!/usr/bin/env python3
# Stop oplus-services.jar from holding Xiaomi's knuckle sensor (idle drain, BUGS-TODO 24).
#
#   python3 -I patch_foldtouch.py in/oplus-services.jar out/oplus-services.jar
#
# OplusIgnoreFoldTouch.initial() asks getDefaultSensor(33171038), OPPO's fold-angle sensor (foldable phones). On
# pipa that type number is Xiaomi's "knuckle" sensor, so system_server keeps a knuckle algorithm running on the
# sensor hub all the time: the SLPI sleeps only 1-40 % with the screen off (2026-10-28, ~50 mA in deep doze).
# The edit changes the literal to 33179999 (no sensor has this type), so getDefaultSensor() returns null and
# registerListener() fails ("sensor or listener is null"); setAngleSensor() already checks for null.
# Live test 2026-10-28 (bind mount + zygote restart): knuckle no longer active, SLPI asleep ~100 % with the screen off.
#
# The site is located by pattern: `const vA, 33171038` (31i) followed by `const/4` and `invoke-virtual`
# (getDefaultSensor(IZ)) must occur exactly once in the dex that has the OplusIgnoreFoldTouch class. The other user of
# the literal, OplusFoldingAngleManager$FolderAngleSensorEventListener.<init> (another dex in C.06), is not changed:
# it only stores the type. Any other count aborts. Then the dex signature/checksum are recomputed.
# Verified on donor C.06 (beta5 jar 8810ad00…, classes2.dex +0x13be2c).
import hashlib, re, struct, sys, zipfile, zlib

src, out = sys.argv[1], sys.argv[2]
OLD, NEW = 33171038, 33179999
CLS = b'Lcom/android/server/oplus/input/exinputservice/globalgesture/OplusIgnoreFoldTouch;'
pat = re.compile(re.escape(b'\x14') + b'(.)' + re.escape(struct.pack('<I', OLD)) + b'\x12.\x6e', re.S)

zin = zipfile.ZipFile(src)
dexes = [n for n in zin.namelist() if re.fullmatch(r'classes\d*\.dex', n) and CLS in zin.read(n)]
if len(dexes) != 1:
    sys.exit('OplusIgnoreFoldTouch found in %d dex files, expected 1' % len(dexes))
name = dexes[0]
d = bytearray(zin.read(name))
if d.count(struct.pack('<I', NEW)):
    sys.exit('%s already has %d; already patched?' % (name, NEW))
hits = [m.start() for m in pat.finditer(d)]
if len(hits) != 1:
    sys.exit('%s: %d getDefaultSensor(%d) sites, expected 1' % (name, len(hits), OLD))
o = hits[0]
d[o + 2:o + 6] = struct.pack('<I', NEW)
d[12:32] = hashlib.sha1(d[32:]).digest()
d[8:12] = struct.pack('<I', zlib.adler32(d[12:]) & 0xffffffff)

with zipfile.ZipFile(out, 'w') as zout:
    for info in zin.infolist():
        data = bytes(d) if info.filename == name else zin.read(info.filename)
        zi = zipfile.ZipInfo(info.filename, date_time=info.date_time)
        zi.compress_type = info.compress_type
        zi.external_attr = info.external_attr
        zi.internal_attr = info.internal_attr
        zi.create_system = info.create_system
        zout.writestr(zi, data)
print('patched %s +0x%x: getDefaultSensor(%d) -> %d; wrote %s' % (name, o, OLD, NEW, out))
