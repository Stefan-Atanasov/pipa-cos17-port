#!/usr/bin/env python3
"""Rewrite ColorOS's brightness_table so pipa's slider scales like HyperOS.

How ColorOS uses the table (oplus-services.jar, beta4):
  <level>P, B, N, K</level>  one line per UI level i = 0..10239 (line index = slider value)
  - OplusDisplayBrightnessModeStrategy picks OplusDisplayBrightnessExponentModel when
    N[10] > 0, N[20] > 0 and N[20] - N[10] < 1 ("score = 1" in logcat).
  - ExponentModel.getBacklightFromBrightness(i) = P[i] / P[last]  (column 0, via
    CurveConfig.traversalPanelMaps(arr, 0)). That float goes to HWC, and on pipa the
    Qualcomm composer writes float * 4095 to panel0-backlight. OPPO kernels add their own
    curve; pipa's doesn't.
  - N is used for nits estimates (auto-brightness, animation, thermal limits).

The port's table has P[i] = i (linear), so the slider position maps linearly to backlight and
almost all perceived change sits in the bottom ~15 % of the slider. The curved numbers are in
column B, which this model never reads.

This script writes:
  hw(i) = HW_MIN + (HW_MAX - HW_MIN) * gamma_to_linear(i / 10239)   (AOSP BrightnessUtils curve,
          the same slider curve HyperOS uses; HW_MIN = 7, the HyperOS
          config_screenBrightnessSettingMinimumFloat 0.00171 floor, about 1 nit)
  P = hw * 10239 / 4095 (so P[last] = 10239)
  B = hw (informational)
  N = physical nits of level = P (auto-brightness and nit estimates use P as the level axis),
      from pipa's displayconfig map (1 nit @ 0.0017, 450 @ 0.49976, 550 @ 1.0)
  K unchanged, min = MIN_LEVEL.

usage: gen_brightness_table.py <in.xml> <out.xml>
"""
import math
import re
import sys

MAX_LEVEL = 10239
HW_MAX = 4095
HW_MIN = 7
MIN_LEVEL = 20  # must stay above OplusBrightnessConstants.AOD_BRIGHTNESS: ExponentModel passes levels <= it through raw (level 1 -> backlight 1)
NITS_MAP = [(0.001709819 * HW_MAX, 1.0), (0.49975574 * HW_MAX, 450.0), (1.0 * HW_MAX, 550.0)]

# frameworks/base/packages/SettingsLib/src/com/android/settingslib/display/BrightnessUtils.java
R, A, B, C = 0.5, 0.17883277, 0.28466892, 0.55991073


def gamma_to_linear(v):
    ret = (v / R) ** 2 if v <= R else math.exp((v - C) / A) + B
    return min(max(ret / 12.0, 0.0), 1.0)


def nits(bl):
    if bl <= 0:
        return 0.0
    (x0, y0) = NITS_MAP[0]
    if bl <= x0:
        return y0 * bl / x0
    for (xa, ya), (xb, yb) in zip(NITS_MAP, NITS_MAP[1:]):
        if bl <= xb:
            return ya + (yb - ya) * (bl - xa) / (xb - xa)
    return NITS_MAP[-1][1]


def hw_for(level):
    if level == 0:
        return 0.0
    return HW_MIN + (HW_MAX - HW_MIN) * gamma_to_linear(level / MAX_LEVEL)


def row(match):
    level, k = int(match.group(2)), match.group(5).strip()
    hw = hw_for(level)
    p = round(hw * MAX_LEVEL / HW_MAX)
    # Auto-brightness inverts nits -> "level" with a spline over (P, N), i.e. it treats column P
    # as the level axis, and getNitFromBrightness(level) reads the same spline. So N must be the
    # physical nits of *level = P*, not of this row, or the curve gets applied twice (auto at
    # 10 lux then lands at ~1 nit instead of ~32).
    return "%s%-4d,%-4d,%-7.5f,%s</level>" % (match.group(1), p, round(hw), nits(hw_for(p)), k)


if __name__ == "__main__":
    src, dst = sys.argv[1], sys.argv[2]
    with open(src, encoding="utf-8", newline="") as f:
        xml = f.read()
    xml, n = re.subn(r'(<level>)\s*(\d+)\s*,\s*(\d+)\s*,\s*([\d.]+)\s*,\s*([\d.]+)\s*</level>', row, xml)
    if n != MAX_LEVEL + 1:
        sys.exit("expected %d levels, got %d" % (MAX_LEVEL + 1, n))
    xml, n = re.subn(r'<brightness_table max="%d" min="\d+">' % MAX_LEVEL,
                     '<brightness_table max="%d" min="%d">' % (MAX_LEVEL, MIN_LEVEL), xml)
    if n != 1:
        sys.exit("brightness_table header not found")
    xml = xml.replace("<!-- add for brightness level of nit look up tables.  -->",
                      "<!-- add for brightness level of nit look up tables.  -->\r\n"
                      "    <!-- pipa_cos17_power_tune: column 1 = AOSP/HyperOS slider curve"
                      " (backlight %d..%d), see module README. -->" % (HW_MIN, HW_MAX), 1)
    with open(dst, "w", encoding="utf-8", newline="") as f:
        f.write(xml)
    for lv in (1, 20, 1024, 2560, 5120, 7680, 10239):
        print("level %5d (%3d%%) -> backlight %6.1f  ~%5.1f nits" % (lv, round(lv * 100 / MAX_LEVEL), hw_for(lv), nits(hw_for(lv))))
