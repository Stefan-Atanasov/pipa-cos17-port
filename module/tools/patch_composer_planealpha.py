#!/usr/bin/env python3
"""Clamp the layer plane alpha in the pipa composer instead of refusing it (BUGS 48, step 8c).

vendor.qti.hardware.display.composer-service (sdm HWC2, hwc_layers.cpp):

    HWC2::Error HWCLayer::SetLayerPlaneAlpha(float alpha) {
      if (alpha < 0.0f || alpha > 1.0f) return HWC2::Error::BadParameter;
      uint8_t plane_alpha = static_cast<uint8_t>(std::round(255.0f * alpha));

The ColorOS SurfaceFlinger sends values just outside 0..1 for 10-20 s after each screen rotation (an animation
overshoot): ~20 per second of `command 0x4080000 generated error 4` (SET_LAYER_PLANE_ALPHA, BAD_PARAMETER) in logcat,
and the layer keeps its old alpha for that frame. The patch replaces the two range checks with a clamp, same size:

    fcmp s0,#0.0 ; mov w8,#4 ; b.mi err ; fmov s1,#1.0 ; fcmp s0,s1 ; b.gt err
 -> movi d1,#0   ; fmaxnm s0,s0,s1      ; fmov s1,#1.0 ; fminnm s0,s0,s1 ; nop ; nop

w8 is set again by the next instruction (mov w8,#0x437f0000 = 255.0f). NaN gives 0 as before (fmaxnm(NaN, 0) = 0;
the old code let NaN through and fcvtas made it 0). Pattern based: exactly one site, both branches to the same
`mov w0, w8` error exit; stops on any other layout.

    python3 -I patch_composer_planealpha.py <composer-service in> <out>
"""
import hashlib
import struct
import sys

FCMP_S0_0 = 0x1E202008
MOV_W8_4 = 0x52800088
FMOV_S1_1 = 0x1E2E1001
FCMP_S0_S1 = 0x1E212000
MOV_W8_255F = 0x52A86FE8
MOV_W0_W8 = 0x2A0803E0
NEW = [0x2F00E401, 0x1E216800, FMOV_S1_1, 0x1E217800, 0xD503201F, 0xD503201F]


def bcond(word, pc):
    """(cond, target) of a b.cond, or None."""
    if word & 0xFF000010 != 0x54000000:
        return None
    imm = (word >> 5) & 0x7FFFF
    if imm & 0x40000:
        imm -= 0x80000
    return word & 0xF, pc + imm * 4


def main(src, dst):
    d = bytearray(open(src, 'rb').read())
    n = len(d) // 4
    w = struct.unpack_from(f'<{n}I', d)
    new = [i for i in range(n - 6) if list(w[i:i + 6]) == NEW and w[i + 6] == MOV_W8_255F]
    if new:
        sys.exit(f'already patched at {hex(new[0] * 4)}')
    sites = []
    for i in range(n - 7):
        if (w[i], w[i + 1], w[i + 3], w[i + 4], w[i + 6]) != (FCMP_S0_0, MOV_W8_4, FMOV_S1_1, FCMP_S0_S1, MOV_W8_255F):
            continue
        mi, gt = bcond(w[i + 2], (i + 2) * 4), bcond(w[i + 5], (i + 5) * 4)
        if not mi or not gt or mi[0] != 0x4 or gt[0] != 0xC or mi[1] != gt[1]:
            continue
        if w[mi[1] // 4] != MOV_W0_W8:
            continue
        sites.append(i)
    if len(sites) != 1:
        sys.exit(f'SetLayerPlaneAlpha range check found {len(sites)} times (want 1): other composer build?')
    i = sites[0]
    struct.pack_into('<6I', d, i * 4, *NEW)
    open(dst, 'wb').write(d)
    print(f'plane alpha clamp at {hex(i * 4)}; md5 {hashlib.md5(d).hexdigest()}')


if __name__ == '__main__':
    if len(sys.argv) != 3:
        sys.exit(__doc__)
    main(sys.argv[1], sys.argv[2])
