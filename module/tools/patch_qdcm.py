#!/usr/bin/env python3
"""Enable a colorimetric PCC (gamut) matrix in pipa's QDCM calibration modes.

Why: in the m82 calibration XMLs every sRGB/P3/native mode ships PCC (FeatureType 2) and the
3D gamut LUT (FeatureType 3) *disabled*, with identity data. Only IGC/GC (gamma) are active.
So "standard" (Natural), "hal_srgb" and "hal_native" (Vivid) all show the raw panel gamut,
which is ~DCI-P3, and sRGB content is visibly oversaturated. Stock HyperOS hides this with
Xiaomi's displayfeature/ppd services, which the COS17 port does not ship.

The PCC block sits between IGC (linearise) and GC (re-gamma) in the SDE DSPP, so a linear
3x3 matrix is correct there.

Matrix choice: stock HyperOS doesn't use QDCM for this. Its displayfeature HAL loads 17^3 3D LUTs
(/vendor/etc/miLut_0..17.txt, 12-bit, 4096 = 1.0) into the DSPP gamut block. Each LUT is a
linear 3x3 to within ~0.002. LUT 2 (sRGB content, native white) fits
    [0.7917 0.1906 0.0116; 0.0356 0.9400 0.0099; 0.0106 0.0613 0.8933]
which is the textbook sRGB -> Display-P3 matrix (Xiaomi models the panel as exact P3) with small
leakage terms. PixelOS gets the same result from SurfaceFlinger colour management
(has_wide_color_display=true). COS17 sets that prop false on purpose, so it is done here instead.
With WHITE = "native" each row is normalised to 1, so the panel's native ~7400 K white and peak
are kept exactly. WHITE = "lut" keeps the LUT's own white instead (LUT 0: ~6800 K, judged too yellow
on the test device). An earlier
version used the exact lcm_array primaries; that over-corrected compared with HyperOS and PixelOS.

PCC payload layout (DataSize 272): 8-byte header, then 3 output channels x 11 little-endian
doubles: [c, r, g, b, rg, gb, rb, rgb, rr, gg, bb]. Identity = r/g/b coefficient 1.0 on the
diagonal. Only c=0 and the r, g, b terms are written here.

usage: patch_qdcm.py <in.xml> <out.xml>
"""
import re
import struct
import sys

# HyperOS miLut_0 (sRGB, warmer white: row sums 0.995 / 0.945 / 0.849, ~6800 K) least-squares
# 3x3 fit (mean error 0.0017). Tried on the test device and judged too yellow; kept as an option.
HYPEROS_LUT0 = [
    [0.8047, 0.1859, 0.0042],
    [0.0300, 0.9094, 0.0059],
    [0.0085, 0.0581, 0.7824],
]

# HyperOS miLut_2 (sRGB, native ~7400 K white) fit (mean error 0.0044). Default.
HYPEROS_LUT2 = [
    [0.7917, 0.1906, 0.0116],
    [0.0356, 0.9400, 0.0099],
    [0.0106, 0.0613, 0.8933],
]

# ModeID -> matrix. "standard" = Natural (sRGB render intent 0), hal_srgb = 257.
# Vivid (hal_native, 256) is deliberately left native. standard_p3 (4) has no PCC block.
TARGETS = {"0": HYPEROS_LUT2, "18": HYPEROS_LUT2}


# "native": normalise each row to 1 -> panel's native white exactly (the look chosen on the test
#           device). "lut": scale so the largest row sums to 1 -> the LUT's own white balance.
WHITE = "native"


def pcc_matrix(m):
    if WHITE == "native":
        return [[v / sum(row) for v in row] for row in m]
    peak = max(sum(row) for row in m)
    return [[v / peak for v in row] for row in m]


def pcc_payload(m):
    vals = []
    for row in m:
        vals += [0.0, row[0], row[1], row[2]] + [0.0] * 7
    return (bytes(8) + struct.pack("<33d", *vals)).hex().upper()


def patch(xml):
    for mode_id, target in TARGETS.items():
        mode = re.search(r'<Mode ModeID="%s" .*?</Mode>' % mode_id, xml, re.S)
        if not mode:
            sys.exit("ModeID %s not found" % mode_id)
        blk = mode.group(0)
        feat = re.search(r'<Feature FeatureType="2" Disable="true" DataSize="272">[0-9A-Fa-f\s]*</Feature>', blk)
        if not feat:
            sys.exit("ModeID %s: disabled PCC feature not found (already patched?)" % mode_id)
        new_feat = '<Feature FeatureType="2" Disable="false" DataSize="272">%s</Feature>' % pcc_payload(pcc_matrix(target))
        xml = xml.replace(blk, blk.replace(feat.group(0), new_feat), 1)
        print("ModeID %s: PCC enabled %s" % (mode_id, [[round(v, 4) for v in r] for r in pcc_matrix(target)]))
    return xml


if __name__ == "__main__":
    src, dst = sys.argv[1], sys.argv[2]
    with open(src, encoding="utf-8", newline="") as f:
        out = patch(f.read())
    with open(dst, "w", encoding="utf-8", newline="") as f:
        f.write(out)
