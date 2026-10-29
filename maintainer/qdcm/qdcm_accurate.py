#!/usr/bin/env python3
"""Xiaomi factory-accurate colour for ColorOS's QDCM modes (BUGS-TODO 29: HDR white looks green).

ColorOS uses the QDCM modes "standard" (SDR, Natural) and "standard_hdr" (HDR, render intent 257). Grey axis of the
3D LUTs (FeatureType 3, 17^3 entries, output R/G at grey 4/8/12/16 of 16) in the stock panel 42 file:
  expert_srgb (HyperOS Professional, factory calibrated)  0.965 0.986 0.992 0.996
  standard_hdr                                            0.925 0.955 0.977 0.995  (about twice as green)
  standard (LUT off = raw panel, step 01 sRGB matrix)     1.000 1.000 1.000 1.000  (a little pink)
1. "standard" gets the expert_srgb features 1:1 (factory sRGB gamut and white).
2. The standard_hdr LUT gets a 1D curve on its R and B outputs so that its grey axis has the expert_srgb ratios
   (STRENGTH 1.0; 0.0 = unchanged); the colours keep their gamut mapping.

With a per-device factory LUT (/mnt/vendor/persist/display/LUT_sRGB_D65_0.txt: 4913 lines "r g b R G B", r fastest,
the same order as the QDCM LUT) the "standard" 3D LUT is that LUT, and the HDR grey follows its ratios (this unit
2026-10-29: R/G 1.000, B/G 0.925 at mid grey; the panel is blue, x 0.306 y 0.323 in input_XYZ.txt).

Usage: qdcm_accurate.py <in.xml> <out.xml> [strength] [unit_lut.txt]
"""
import re
import struct
import sys

N = 17


def curve(src, dst):
    """Piecewise-linear map through the points (src[i] -> dst[i]), src increasing."""
    def f(v):
        if v <= src[0]:
            return dst[0] * (v / src[0]) if src[0] else dst[0]
        for i in range(1, len(src)):
            if v <= src[i]:
                t = (v - src[i - 1]) / (src[i] - src[i - 1])
                return dst[i - 1] + t * (dst[i] - dst[i - 1])
        return dst[-1]
    return f


def entries(lut_hex):
    body = bytes.fromhex(lut_hex)[16:]
    return [list(struct.unpack('<6I', body[k * 24:k * 24 + 24])) for k in range(N ** 3)]


def grey_axis(ent):
    return [ent[i * N * N + i * N + i][3:] for i in range(N)]


def patch(lut_hex, ref_grey, strength):
    b = bytearray(bytes.fromhex(lut_hex))
    head, body = b[:16], b[16:]
    assert struct.unpack('<I', head[12:16])[0] == N ** 3, "not a 17^3 LUT"
    ent = [list(struct.unpack('<6I', body[k * 24:k * 24 + 24])) for k in range(N ** 3)]
    grey = grey_axis(ent)
    maps = []
    for c in (0, 2):  # R, B outputs -> G output times the reference ratio of the same grey step
        src = [g[c] for g in grey]
        dst = [g[c] + strength * (g[1] * (r[c] / r[1] if r[1] else 1) - g[c]) for g, r in zip(grey, ref_grey)]
        assert all(src[i] < src[i + 1] for i in range(1, N - 1)), "grey axis not increasing"
        maps.append(curve(src, dst))
    for e in ent:
        e[3] = min(4095, max(0, round(maps[0](e[3]))))
        e[5] = min(4095, max(0, round(maps[1](e[5]))))
    out = bytes(head) + b''.join(struct.pack('<6I', *e) for e in ent) + bytes(body[N ** 3 * 24:])
    return out.hex().upper()


LUT = re.compile(r'(<Feature FeatureType="3" Disable="false" DataSize="117928">)([0-9A-F]+)(</Feature>)')


def mode_span(lines, name):
    start = [i for i, l in enumerate(lines) if '<Mode ' in l and f'Name="{name}"' in l]
    assert len(start) == 1, f"mode {name} not found once"
    end = next(i for i in range(start[0] + 1, len(lines)) if '</Mode>' in lines[i])
    return start[0], end


def unit_lut(path, head_hex):
    rows = [l.split() for l in open(path) if len(l.split()) == 6]
    assert len(rows) == N ** 3, "unit LUT is not 17^3"
    ent = []
    for k, r in enumerate(rows):
        v = [int(float(x)) for x in r]
        assert (k % N, k // N % N, k // (N * N)) == tuple(min(16, (x + 128) // 256) for x in v[:3]), "unit LUT order"
        ent.append([0, 0, 0] + v[3:])
    return head_hex + b''.join(struct.pack('<6I', *e) for e in ent).hex().upper(), grey_axis(ent)


def main(src, dst, strength=1.0, unit=None):
    lines = open(src, encoding='utf-8').read().split('\n')
    # 1. standard <- expert_srgb features (same feature list: checked)
    es, ee = mode_span(lines, 'expert_srgb')
    ss, se = mode_span(lines, 'standard')
    ftype = lambda l: re.findall(r'FeatureType="(\d+)"', l)
    assert [ftype(l) for l in lines[es + 1:ee]] == [ftype(l) for l in lines[ss + 1:se]], "feature lists differ"
    ref = None
    for l in lines[es + 1:ee]:
        m = LUT.search(l)
        if m:
            ref = grey_axis(entries(m.group(2)))
    assert ref, "expert_srgb 3D LUT not found"
    lines[ss + 1:se] = lines[es + 1:ee]
    if unit:
        for i in range(ss + 1, se):
            m = LUT.search(lines[i])
            if m:
                new, ref = unit_lut(unit, m.group(2)[:32])
                assert len(new) == len(m.group(2))
                lines[i] = lines[i][:m.start(2)] + new + lines[i][m.end(2):]
    # 2. standard_hdr grey axis -> expert_srgb ratios
    hs, he = mode_span(lines, 'standard_hdr')
    done = 0
    for i in range(hs + 1, he):
        m = LUT.search(lines[i])
        if m:
            lines[i] = lines[i][:m.start(2)] + patch(m.group(2), ref, strength) + lines[i][m.end(2):]
            done += 1
    assert done == 1, "standard_hdr 3D LUT not found"
    open(dst, 'w', encoding='utf-8').write('\n'.join(lines))
    what = 'unit LUT' if unit else 'expert_srgb'
    print(f"{dst}: standard = {what}, standard_hdr grey = {what} (strength {strength})")


if __name__ == '__main__':
    main(sys.argv[1], sys.argv[2], float(sys.argv[3]) if len(sys.argv) > 3 else 1.0,
         sys.argv[4] if len(sys.argv) > 4 else None)
