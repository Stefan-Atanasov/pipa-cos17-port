#!/usr/bin/env python3
"""QDCM hal_native (ColorOS "Standard") = Natural, a little warmer and less saturated (user wish 2026-10-29).

ColorOS Standard (display_color_mode 256) uses the SDM mode hal_native: the raw panel (PCC off), so sRGB content is
shown stretched to the panel's near-P3 gamut (oversaturated, panel-native blue white). The user wanted it like the
Standard mode of an OPPO phone: the saturation of Natural, a slightly warmer white. The values were chosen by eye on
the tablet (live bind mount + composer restart, next to an OPPO phone with adaptive tone off, 2026-10-29): saturation
1.0 (= Natural; 0.85 and 0.92 were too pale, the PCC acts stronger than a SurfaceFlinger preview matrix), channel gains
R 1.0, G 0.99, B 0.962. SAT stays as a knob (luminance weights 0.231/0.715/0.054, as ColorDisplayService).

hal_native gets the PCC of "standard" (step 01 sRGB matrix) times gains times saturation; its other features are the
same as in "standard" already (checked: only PCC and the disabled FeatureType 29 differ).

Usage: patch_qdcm_standard_warm.py <in.xml> <out.xml>
"""
import hashlib
import re
import struct
import sys

# input md5 (step 3q output) -> expected output md5
KNOWN = {
    '11a43ffcb7d3f3960a0e87d7cf645af9': '88997e568383dfd3613f9ef365934eee',   # panel 36 (not tested on a device)
    'fc0d72bee9ed3ad5b2346f09c8bdeffa': '4b9362aefa1aed355a1bc99e52c2ae50',   # panel 42 (tested)
}
SAT = 1.0
GAIN = (1.0, 0.99, 0.962)
LUM = (0.231, 0.715, 0.054)
ROWS = (2, 13, 24)   # PCC payload: 34 doubles, the r/g/b coefficients of each output row start here


def span(lines, name):
    s = [i for i, l in enumerate(lines) if '<Mode ' in l and f'Name="{name}"' in l]
    assert len(s) == 1, f"mode {name} not found once"
    e = next(i for i in range(s[0] + 1, len(lines)) if '</Mode>' in lines[i])
    return s[0], e


def pcc_line(lines, name):
    s, e = span(lines, name)
    i = [k for k in range(s + 1, e) if 'FeatureType="2"' in lines[k]]
    assert len(i) == 1, f"{name}: PCC not found once"
    return i[0]


def matmul(a, b):
    return [[sum(a[r][k] * b[k][c] for k in range(3)) for c in range(3)] for r in range(3)]


def main(src, dst):
    data = open(src, 'rb').read()
    md5 = hashlib.md5(data).hexdigest()
    assert md5 in KNOWN, f"{src}: unknown input md5 {md5} (not the step 3q output)"
    lines = data.decode('utf-8').split('\n')
    std = lines[pcc_line(lines, 'standard')]
    assert 'Disable="false"' in std, "standard has no active PCC (step 01 missing)"
    m = re.search(r'>([0-9A-F]+)<', std)
    d = list(struct.unpack('<34d', bytes.fromhex(m.group(1))))
    srgb = [d[b:b + 3] for b in ROWS]
    i = 1 - SAT
    sat = [[LUM[c] * i + (SAT if r == c else 0) for c in range(3)] for r in range(3)]
    gain = [[GAIN[r] if r == c else 0 for c in range(3)] for r in range(3)]
    new = matmul(srgb, matmul(gain, sat))
    for row, b in zip(new, ROWS):
        d[b:b + 3] = row
    k = pcc_line(lines, 'hal_native')
    lines[k] = std[:m.start(1)] + struct.pack('<34d', *d).hex().upper() + std[m.end(1):]
    out = '\n'.join(lines).encode('utf-8')
    got = hashlib.md5(out).hexdigest()
    assert KNOWN[md5] in (None, got), f"unexpected output md5 {got}"
    open(dst, 'wb').write(out)
    print(f"{dst}: hal_native = Natural x gains {GAIN} x saturation {SAT} ({md5[:8]} -> {got[:8]})")
    print("  PCC rows:", [[round(x, 4) for x in r] for r in new])


if __name__ == '__main__':
    main(sys.argv[1], sys.argv[2])
