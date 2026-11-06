#!/usr/bin/env python3
"""BUGS-TODO 39 (step 4h): log lines that ColorOS writes on every touch, in place in the stored dex of a jar.

* oplus-framework.jar UAHAdaptHelper.getAidlService(): looks up OPPO's urcc HAL (absent on pipa) on every touch and
  logs "getAidlService uah urcc service =  null". Patch: return false at once (no lookup, no log).
* NOPLOG: the log call after a fixed message becomes nops. The message is built but not written; the rest of the
  method is unchanged (no move-result follows the call, so the verifier sees the same registers).
* RET (5x): the method returns a constant at once (const/4 v0 + return v0 over its first instruction, the rest of that
  instruction becomes nops; the old code after it is dead but stays valid).
usage: patch_logspam.py <jar> <out.jar> [4h|5x]   (table set, default 4h; the jar's file name selects the table; an
       unpatched jar for 4h, the 4h output for 5x; needs androguard: maintainer/jar-edits/venv)"""
import hashlib, io, os, struct, sys, zipfile, zlib
from androguard.core.dex import DEX, HiddenApiClassDataItem

# androguard 4 knows no newer hidden-API domain flags (oplus-framework: 4) and stops; they do not matter here
HiddenApiClassDataItem.DomapiApiFlag._missing_ = classmethod(lambda cls, v: list(cls)[0])

LOGGERS = ('Landroid/util/Log;->', 'Landroid/util/Slog;->', 'Lcom/android/server/oplus/osense/logger/OsenseLogger;->')
# jar -> [(kind, class, method, descriptor or None, message)]
TABLE = {
    'oplus-framework.jar': [
        ('uah', 'Lcom/oplus/uah/UAHAdaptHelper;', 'getAidlService', '()Z', None),
    ],
    'oplus-services.jar': [
        ('nolog', 'Lcom/android/server/oplus/osense/OsenseResManagerService$3;', None, None,
         'osenseSetSceneAction: action is not SCENE_SPECIAL_REQUEST'),
        ('nolog', 'Lcom/android/server/wm/WindowStateExtImpl;', 'isForceUpdateWallpaperScale', '()Z',
         'isForceUpdateWallpaperScale: '),
    ],
    'services.jar': [
        ('nolog', 'Lcom/android/server/power/PowerManagerService;', 'userActivityNoUpdateLocked', None,
         'userActivityNoUpdateLocked: groupId='),
    ],
}


# 5x (beta7.2, tester report 2026-11-06, BUGS 79): what 4h left
TABLE_5X = {
    'oplus-framework.jar': [
        # native UahEventAcquire / UahGetFeatureStatus look up the absent urcc HAL each time and log 2 errors
        # ("Urcc is not declared", "uah_get_urcc_hal_and_link_to_death error:-1"): ~115 pairs per minute of use.
        ('ret', 'Lcom/oplus/uah/UAHPerfManager;', 'uahEventAcquire', None, -1),
        ('ret', 'Lcom/oplus/uah/UAHPerfManager;', 'getFeatureStatus', '(I)I', 0),
        ('ret', 'Lcom/oplus/uah/UAHPerfManager;', 'tansSa2Event', None, -1),   # the same native call (window events)
    ],
    'oplus-services.jar': [
        # QoS scenes 2 and 5 (masks 4, 32) have no rule in OPPO's own sys_osense_scene_event_config.xml (stock
        # behaviour, the scheduler works): one warning per window change.
        ('nolog', 'Lcom/android/server/oplus/osense/feature/uaf/qos/QosSchedulerManager;', 'getScenario', None,
         'getScenario failed! scenarios is null, mask='),
        ('nolog', 'Lcom/android/server/oplus/osense/feature/uaf/qos/QosSchedulerManager;', 'executeSceneQosStrategy',
         None, 'executeSceneQosStrategy get scenario failed! scenario is null'),
        ('nolog', 'Lcom/android/server/oplus/osense/feature/uaf/scene/list/SmartWindowScene;', 'updateWindowState',
         None, 'updateWindowState fail! invalid window type: '),
    ],
}
TABLES = {'4h': TABLE, '5x': TABLE_5X}


def is_msg(x, msg):
    """const-string prints the value in quotes, const-string/jumbo without"""
    return x.get_name().startswith('const-string') and x.get_output().split(', ', 1)[1].strip('"') == msg


def code_off(m):
    return m.get_code().get_off() + 16          # code_item header is 16 bytes


def find_methods(dex, cls, name, desc, msg):
    out = []
    for c in dex.get_classes():
        if c.get_name() != cls:
            continue
        for m in c.get_methods():
            if name and m.get_name() != name or desc and m.get_descriptor() != desc or not m.get_code():
                continue
            if msg and not any(is_msg(x, msg) for x in m.get_instructions()):
                continue
            out.append(m)
    return out


def patch_uah(buf, m):
    """At the HAL lookup (sget-object HAL_INSTANCE_NAME, 4 bytes): const/4 v1, 0; return v1."""
    off = code_off(m)
    for x in m.get_instructions():
        if x.get_name() == 'sget-object' and 'HAL_INSTANCE_NAME' in x.get_output():
            assert buf[off] == 0x62 and x.get_length() == 4, buf[off:off + 4].hex()
            buf[off:off + 4] = b'\x12\x01\x0f\x01'
            return 'returns false (no urcc lookup)'
        off += x.get_length()
    raise SystemExit('UAH: HAL_INSTANCE_NAME lookup not found')


def patch_ret(buf, m, val):
    """const/4 v0, val; return v0 over the first whole instructions (>= 4 bytes); the rest of them becomes nops"""
    assert -8 <= val <= 7 and m.get_code().get_registers_size() >= 1
    ln, off = 0, code_off(m)
    for x in m.get_instructions():          # whole instructions until 4 bytes; all new code is 2-byte units, so
        ln += x.get_length()                # every old instruction start stays an instruction start
        if ln >= 4:
            break
    assert ln >= 4 and ln % 2 == 0, ln
    buf[off:off + ln] = bytes([0x12, (val & 0xf) << 4, 0x0f, 0x00]) + b'\0' * (ln - 4)
    return f'returns {val} at once'


def patch_nolog(buf, m, msg):
    off, seen = code_off(m), False
    ins = list(m.get_instructions())
    for i, x in enumerate(ins):
        n = x.get_name()
        if is_msg(x, msg):
            seen = True
        elif seen and n.startswith('invoke-static') and any(l in x.get_output() for l in LOGGERS):
            assert i + 1 < len(ins) and not ins[i + 1].get_name().startswith('move-result'), 'result used'
            ln = x.get_length()
            assert buf[off] in (0x71, 0x77), buf[off:off + ln].hex()        # invoke-static(/range)
            buf[off:off + ln] = b'\0' * ln
            return f'log call removed ({ln // 2} nops)'
        off += x.get_length()
    raise SystemExit(f'no log call after "{msg}"')


def patch_dex(d, targets, done):
    dex, buf, notes = None, bytearray(d), []
    for t in targets:
        kind, cls, name, desc, msg = t
        if cls.encode()[1:-1] not in d:
            continue
        dex = dex or DEX(d)
        ms = find_methods(dex, cls, name, desc, msg if kind == 'nolog' else None)
        if not ms:
            continue
        assert len(ms) == 1, f'{cls}->{name}: {len(ms)} methods'
        r = (patch_uah(buf, ms[0]) if kind == 'uah' else patch_ret(buf, ms[0], msg) if kind == 'ret'
             else patch_nolog(buf, ms[0], msg))
        notes.append(f'{cls.split("/")[-1][:-1]}.{ms[0].get_name()}: {r}')
        done.add(t)
    if not notes:
        return None, notes
    buf[12:32] = hashlib.sha1(buf[32:]).digest()
    buf[8:12] = struct.pack('<I', zlib.adler32(bytes(buf[12:])))
    return bytes(buf), notes


def main(src, dst, table='4h'):
    targets = TABLES[table][os.path.basename(src)]
    jar = bytearray(open(src, 'rb').read())
    z = zipfile.ZipFile(io.BytesIO(jar))
    done = set()
    eocd = jar.rfind(b'PK\x05\x06')
    for info in z.infolist():
        if not info.filename.endswith('.dex'):
            continue
        assert info.compress_type == 0, f'{info.filename} is compressed'
        lh = info.header_offset
        n, x = struct.unpack_from('<HH', jar, lh + 26)
        off = lh + 30 + n + x
        new, notes = patch_dex(bytes(jar[off:off + info.file_size]), targets, done)
        if new is None:
            continue
        jar[off:off + len(new)] = new
        crc = zlib.crc32(new) & 0xffffffff
        struct.pack_into('<I', jar, lh + 14, crc)
        p = struct.unpack_from('<I', jar, eocd + 16)[0]
        while jar[p:p + 4] == b'PK\x01\x02':
            fn, ex, cm = struct.unpack_from('<HHH', jar, p + 28)
            if struct.unpack_from('<I', jar, p + 42)[0] == lh:
                struct.pack_into('<I', jar, p + 16, crc)
                break
            p += 46 + fn + ex + cm
        else:
            raise SystemExit('central directory entry not found')
        for s in notes:
            print(f'{info.filename}: {s}')
    missing = [t for t in targets if t not in done]
    assert not missing, f'not found: {missing}'
    zipfile.ZipFile(io.BytesIO(jar)).testzip()
    open(dst, 'wb').write(jar)


if __name__ == '__main__':
    if len(sys.argv) not in (3, 4):
        sys.exit(__doc__)
    main(*sys.argv[1:])
