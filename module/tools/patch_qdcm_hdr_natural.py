#!/usr/bin/env python3
"""QDCM standard_hdr = the Natural ("standard") processing with a P3 matrix (BUGS-TODO 29: HDR white looks green).

ColorOS shows HDR in the SDM mode standard_hdr (render intent 257). The stock Xiaomi standard_hdr uses its own 3D LUT
and HDR-only stages; on the port (PixelOS composer, no Xiaomi displayfeature) HDR whites came out green and warm next
to Natural (grey test clip, 2026-10-29). "standard" (Natural, step 01) is the raw panel gamma and white with an sRGB
PCC matrix. This gives standard_hdr the same features as "standard" (3D LUTs off, same IGC/GC), with the PCC matrix
from P3 to the panel instead of sRGB; only the HDR control block (FeatureType 28) stays. The user saw no tint (HDR
grey clip and YouTube, live bind-mount test 2026-10-29).

The P3 matrix is from the factory measurement of one panel 42 unit (/mnt/vendor/persist/display/input_XYZ.txt,
primaries at 255; rows scaled to sum 1 so the panel white stays, like the step 01 sRGB matrix). The panel is close
to P3, so the matrix is close to identity; it is used for both panel variants.

Usage: patch_qdcm_hdr_natural.py <in.xml> <out.xml>
"""
import hashlib
import re
import struct
import sys

# input md5 (step 01 output) -> expected output md5
KNOWN = {
    'c102c20fd2fe7cf8ee35c2e5b9e71be5': '11a43ffcb7d3f3960a0e87d7cf645af9',   # panel 36 (not tested on a device)
    '1e2ab685745fa4a6c246c1653be2fc91': 'fc0d72bee9ed3ad5b2346f09c8bdeffa',   # panel 42 (tested)
}
P3 = [[0.9438, 0.0212, 0.0351],
      [0.0101, 0.9995, -0.0096],
      [-0.0020, -0.0021, 1.0041]]
ROWS = (2, 13, 24)   # PCC payload: 34 doubles, the r/g/b coefficients of each output row start here


def span(lines, name):
    s = [i for i, l in enumerate(lines) if '<Mode ' in l and f'Name="{name}"' in l]
    assert len(s) == 1, f"mode {name} not found once"
    e = next(i for i in range(s[0] + 1, len(lines)) if '</Mode>' in lines[i])
    return s[0], e


def ftype(line):
    return re.search(r'FeatureType="(\d+)"', line).group(1)


def main(src, dst):
    data = open(src, 'rb').read()
    md5 = hashlib.md5(data).hexdigest()
    assert md5 in KNOWN, f"{src}: unknown input md5 {md5} (not the step 01 output)"
    lines = data.decode('utf-8').split('\n')
    ss, se = span(lines, 'standard')
    hs, he = span(lines, 'standard_hdr')
    std = {ftype(l): l for l in lines[ss + 1:se]}
    assert re.search(r'FeatureType="2" Disable="false"', std['2']), "standard has no active PCC (step 01 missing)"
    new = []
    for l in lines[hs + 1:he]:
        t = ftype(l)
        if t not in std:
            assert t == '28', f"unexpected HDR-only feature {t}"
            new.append(l)
            continue
        l = std[t]
        if t == '2':
            m = re.search(r'>([0-9A-F]+)<', l)
            d = list(struct.unpack('<34d', bytes.fromhex(m.group(1))))
            for row, base in zip(P3, ROWS):
                d[base:base + 3] = row
            l = l[:m.start(1)] + struct.pack('<34d', *d).hex().upper() + l[m.end(1):]
        new.append(l)
    lines[hs + 1:he] = new
    out = '\n'.join(lines).encode('utf-8')
    want = KNOWN[md5]
    got = hashlib.md5(out).hexdigest()
    assert want is None or got == want, f"unexpected output md5 {got}"
    open(dst, 'wb').write(out)
    print(f"{dst}: standard_hdr = standard + P3 matrix ({md5[:8]} -> {got[:8]})")


if __name__ == '__main__':
    main(sys.argv[1], sys.argv[2])
