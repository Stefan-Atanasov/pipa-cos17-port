#!/usr/bin/env python3
"""BUGS-TODO 98 (step 6n): hide Settings > System navigation > "Digital assistant from Google" (corner swipe).

The swipe cannot work on the port: SystemUI NavBarUtils.isAssistantAvailable() returns false on CN builds and when
Circle to Search is supported (stock export ColorOS also turns the swipe off then), and the default assistant is the
pipa helper (Circle to Search, step 4g). User decision 2026-11-13: keep Circle to Search, hide the switch.

NavigationBarSettingsFragment.initPreferenceView keeps one of two corner-swipe switches (Google or Yandex) and removes
the other. In the branch that keeps the Google switch it runs
    iget-object vA, p0, ->mGestureCircleToSearchWakeAssistPref
    iget-object vB, p0, ->mCircleToSearchListener
    invoke-virtual {vA, vB}, Preference->setOnPreferenceChangeListener
This patch makes it (same size, in place)
    iget-object vA, p0, ->mGestureCircleToSearchWakeAssistPref
    iget-object vB, p0, ->mGestureCircleToSearchPref            (field ref copied from the method)
    invoke-virtual {vB, vA}, PreferenceGroup->removePreference   (method ref copied from the method)
so the Google switch is removed too. The Yandex branch and the Circle to Search switch do not change.
In place in the stored dex (only the zip CRCs change; the platform signature block stays).
usage: patch_settings_corner_assist.py <Settings.apk> <out.apk>   (needs androguard: maintainer/jar-edits/venv)"""
import hashlib, io, struct, sys, zipfile, zlib
from androguard.core.dex import DEX

CLS = 'Lcom/oplus/settings/feature/navbar/NavigationBarSettingsFragment;'
NAME = 'initPreferenceView'
F_ASSIST = 'mGestureCircleToSearchWakeAssistPref'
F_LISTENER = 'mCircleToSearchListener'
F_CATEGORY = '->mGestureCircleToSearchPref '
M_REMOVE = 'Landroidx/preference/PreferenceGroup;->removePreference(Landroidx/preference/Preference;)Z'
M_SETLISTENER = '->setOnPreferenceChangeListener('


def patch_dex(d):
    dex = bytearray(d)
    ms = [m for c in DEX(bytes(dex)).get_classes() if c.get_name() == CLS
          for m in c.get_methods() if m.get_name() == NAME]
    assert len(ms) == 1, f'{NAME} found {len(ms)} times'
    m = ms[0]
    base = m.get_code().get_off() + 16
    ins = list(m.get_instructions())
    offs, o = [], 0
    for x in ins:
        offs.append(base + o)
        o += x.get_length()
    cat_field = rm_meth = None
    for i, x in enumerate(ins):          # refs that the method already uses
        if x.get_name() == 'iget-object' and F_CATEGORY in x.get_output() + ' ' and cat_field is None:
            cat_field = bytes(dex[offs[i] + 2:offs[i] + 4])
        if x.get_name() == 'invoke-virtual' and M_REMOVE in x.get_output() and rm_meth is None:
            rm_meth = bytes(dex[offs[i] + 2:offs[i] + 4])
    assert cat_field and rm_meth, (cat_field, rm_meth)
    hits = [i for i in range(len(ins) - 2)
            if ins[i].get_name() == 'iget-object' and F_ASSIST in ins[i].get_output()
            and ins[i + 1].get_name() == 'iget-object' and F_LISTENER in ins[i + 1].get_output()
            and ins[i + 2].get_name() == 'invoke-virtual' and M_SETLISTENER in ins[i + 2].get_output()]
    if not hits:
        done = [i for i in range(len(ins) - 2)
                if ins[i].get_name() == 'iget-object' and F_ASSIST in ins[i].get_output()
                and F_CATEGORY in ins[i + 1].get_output() + ' ' and M_REMOVE in ins[i + 2].get_output()]
        sys.exit('already patched' if done else 'pattern not found (other Settings version?)')
    assert len(hits) == 1, f'pattern found {len(hits)} times'
    i = hits[0]
    a = dex[offs[i] + 1] & 0x0f                      # iget-object vA, p0 (22c: B|A)
    g1 = offs[i + 1]
    b = dex[g1 + 1] & 0x0f
    assert dex[g1] == 0x54 and dex[offs[i]] == 0x54, 'not iget-object'
    inv = offs[i + 2]
    assert dex[inv] == 0x6e and dex[inv + 1] >> 4 == 2, 'not invoke-virtual with 2 args'
    regs = struct.unpack_from('<H', dex, inv + 4)[0]
    assert regs & 0xf == a and (regs >> 4) & 0xf == b, (hex(regs), a, b)
    dex[g1 + 2:g1 + 4] = cat_field                   # vB = mGestureCircleToSearchPref
    dex[inv + 2:inv + 4] = rm_meth                   # PreferenceGroup.removePreference
    struct.pack_into('<H', dex, inv + 4, (regs & 0xff00) | (a << 4) | b)   # {vB, vA}
    dex[12:32] = hashlib.sha1(dex[32:]).digest()
    dex[8:12] = struct.pack('<I', zlib.adler32(bytes(dex[12:])))
    return bytes(dex)


def main(src, dst):
    apk = bytearray(open(src, 'rb').read())
    z = zipfile.ZipFile(io.BytesIO(apk))
    info = [i for i in z.infolist() if i.filename.endswith('.dex') and i.compress_type == 0
            and b'circle_to_search_gesture_wake_assistance_key' in z.read(i.filename)
            and F_ASSIST.encode() in z.read(i.filename)]
    assert len(info) == 1, [i.filename for i in info]
    info = info[0]
    lh = info.header_offset
    assert apk[lh:lh + 4] == b'PK\x03\x04'
    n, x = struct.unpack_from('<HH', apk, lh + 26)
    off = lh + 30 + n + x
    new = patch_dex(bytes(apk[off:off + info.file_size]))
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
    open(dst, 'wb').write(apk)
    print(f'{info.filename}: corner-swipe switch removed in {NAME}, crc32 {crc:08x}')


if __name__ == '__main__':
    if len(sys.argv) != 3:
        sys.exit(__doc__)
    main(sys.argv[1], sys.argv[2])
