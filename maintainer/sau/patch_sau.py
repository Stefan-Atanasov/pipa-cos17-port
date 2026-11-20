#!/usr/bin/env python3
"""SAU app updates on the port (BUGS 160/161, 2026-11-20).

ColorOS SAU (com.oplus.sau, system_ext/app/SystemAppUpdateService) updates built-in OPPO apps (MSP com.heytap.htms,
account, ...). On the port it never asks the server:
  * SAUAppService.onStartCommand returns at once when i3.c.e0() is true ("verity is disable, only exit"); e0() is
    true unless ro.boot.veritymode=enforcing (or eio + vbmeta locked). The port runs without dm-verity.
  * Query_Update sends productName = i3.c.K() = ro.product.name (pipa; stock OPPO: = model, OPD2515).
Patch (as toraidl/coloros_port patches the check in the app, not a global verity/lock spoof):
  a) onStartCommand: the `if-eqz v2` after e0() becomes `goto/16` to the same target: only the APK update service
     goes on. e0() itself is unchanged, so every other user (opex system patches, w2/a, ...) stays blocked.
  b) i3.c.K() returns android.os.Build.MODEL (ro.product.model = OPD2515 for system apps) instead of ro.product.name.

Usage (plain python3): patch_sau.py <SystemAppUpdateService.apk in> <out>
In place, same size, in the stored dex; only the zip CRCs change and OPPO's signature block stays (as
../battery/patch_long_charge.py). Stops if the code is not exactly as expected.
"""
import importlib.util
import os
import struct
import sys

_spec = importlib.util.spec_from_file_location(
    'patch_ipemanager', os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', 'ipe-fluid', 'patch_ipemanager.py'))
_ipe = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(_ipe)
Dex = _ipe.Dex


def code(d, cls, name, sig):
    co = d.code_off(cls, name, sig)
    insns = struct.unpack_from('<I', d.b, co + 12)[0]
    return co + 16, insns


def patch_dex(data):
    d = Dex(data)
    # a) the verity gate in SAUAppService.onStartCommand
    start, n = code(d, 'Lcom/oplusos/sau/service/SAUAppService;', 'onStartCommand', '(Landroid/content/Intent;II)I')
    c = bytes(d.b[start:start + 2 * n])
    e0 = d.find_method('Li3/c;', 'e0', '()Z')
    s_tag = d.find_string('SAUAppService')
    s_msg = d.find_string('verity is disable, only exit')
    # invoke-static {}, e0 (71 00 idx16 0000) ; move-result v2 (0a 02) ; const-string v10 "SAUAppService" (1a 0a idx16) ;
    # if-eqz v2, +off (38 02 off16) ; const-string v0 "verity is disable, only exit" (1a 00 idx16)
    pat = (b'\x71\x00' + struct.pack('<H', e0) + b'\x00\x00' + b'\x0a\x02' + b'\x1a\x0a' + struct.pack('<H', s_tag) + b'\x38\x02')
    hits = [i for i in range(0, len(c) - len(pat), 2) if c[i:i + len(pat)] == pat]
    assert len(hits) == 1, f'verity gate pattern found {len(hits)} times'
    i = hits[0] + len(pat) - 2                         # the if-eqz instruction
    off = struct.unpack_from('<h', c, i + 2)[0]
    assert c[i + 4:i + 6] == b'\x1a\x00' and struct.unpack_from('<H', c, i + 6)[0] == s_msg, 'exit message does not follow'
    assert off > 0, 'if-eqz target is not forward'
    d.b[start + i:start + i + 2] = b'\x29\x00'          # goto/16 +off (same offset, same size)
    print(f'onStartCommand: if-eqz v2,+{off} -> goto/16 +{off} at 0x{start + i:x} (verity gate skipped for app updates)')

    # b) i3.c.K(): ro.product.name -> Build.MODEL
    start, n = code(d, 'Li3/c;', 'K', '()Ljava/lang/String;')
    assert n == 9, f'K() has {n} code units, expected 9'
    c = bytes(d.b[start:start + 18])
    s_name = d.find_string('ro.product.name')
    get = d.find_method('Landroid/os/SystemProperties;', 'get', '(Ljava/lang/String;Ljava/lang/String;)Ljava/lang/String;')
    assert c[0:4] == b'\x1a\x00' + struct.pack('<H', s_name), 'K(): const-string v0 "ro.product.name" expected'
    assert c[4:6] == b'\x1a\x01' and c[8:10] == b'\x71\x20' and struct.unpack_from('<H', c, 10)[0] == get, \
        'K(): SystemProperties.get call expected'
    assert c[14:18] == b'\x0c\x00\x11\x00', 'K(): move-result-object v0 ; return-object v0 expected'
    model = d.find_field('Landroid/os/Build;', 'MODEL')
    new = b'\x62\x00' + struct.pack('<H', model) + b'\x11\x00' + b'\x00\x00' * 6
    d.b[start:start + 18] = new
    print(f'K(): returns Build.MODEL (field {model}) instead of ro.product.name')
    d.fix_header()
    return bytes(d.b)


def main():
    src, dst = sys.argv[1:3]
    _patch_apk(src, dst)


def _patch_apk(src, dst):
    # same-size rewrite of the stored classes.dex entry (as ../battery/patch_long_charge.py)
    import zipfile
    import zlib
    b = bytearray(open(src, 'rb').read())
    with zipfile.ZipFile(src) as z:
        e = z.getinfo('classes.dex')
        assert e.compress_type == zipfile.ZIP_STORED, 'classes.dex is not stored'
        lh = e.header_offset
        assert b[lh:lh + 4] == b'PK\x03\x04'
        fn_len, ex_len = struct.unpack_from('<HH', b, lh + 26)
        data_off = lh + 30 + fn_len + ex_len
        old = bytes(b[data_off:data_off + e.file_size])
    new = patch_dex(old)
    assert len(new) == len(old)
    b[data_off:data_off + len(new)] = new
    crc = zlib.crc32(new) & 0xffffffff
    struct.pack_into('<I', b, lh + 14, crc)
    cd = b.rfind(b'PK\x05\x06')
    cd_off = struct.unpack_from('<I', b, cd + 16)[0]
    p = cd_off
    while b[p:p + 4] == b'PK\x01\x02':
        nl, xl, cl = struct.unpack_from('<HHH', b, p + 28)
        name = bytes(b[p + 46:p + 46 + nl])
        if name == b'classes.dex':
            struct.pack_into('<I', b, p + 16, crc)
        p += 46 + nl + xl + cl
    open(dst, 'wb').write(b)
    print(f'ok: {dst}')


if __name__ == '__main__':
    main()
