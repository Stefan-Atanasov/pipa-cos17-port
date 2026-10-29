#!/usr/bin/env python3
# Let the panel drop to 60 Hz when the screen is idle (BUGS-TODO B11).
#
#   python3 -I patch_vrr_config.py in/oplus_vrr_config.json out/oplus_vrr_config.json
#
# ColorOS "touch idle" (OTI) lowers the rate 2.5 s after the last touch. It has two strategies: SW lowers only the
# render rate (the panel stays at 120 Hz), HW switches the panel mode to 60 Hz. system_server enables HW only when
# the backlight is bright enough, an OLED flicker guard: hw_nit_limit 110, and with histogram_enable the
# hw_nit_lower_limit_light/_dark tables (up to 110 nits light, 2000 nits dark) replace that limit
# (OPlusExternalRefreshRateManager.handleBacklightChange / isSupportHwWithHistogram). pipa's LCD does not flicker at
# low rates, and the ColorOS nit estimate is low (95 nits at brightness 5691), so HW was off nearly always.
# The edit sets hw_nit_limit and hw_nit_limit_pwm to -1 (TouchIdleBean.IGNORE_VALUE) and removes histogram_enable
# (then OPlusOnlineConfigManager builds no nit tables; the composer refuses content sampling anyway).
# Live test 2026-10-29 (bind mount + zygote restart): idle home screen at 60 Hz mode, a swipe gives 120 Hz.
#
# Text edits, so the file layout stays. Each old text must occur exactly once in the touch_idle block; any other count
# aborts. Verified on donor C.06 (oplus_vrr_config.json version 20260224).
import json, sys

src, out = sys.argv[1], sys.argv[2]
EDITS = [
    ('"hw_nit_limit":110,', '"hw_nit_limit":-1,'),
    ('"hw_nit_limit_pwm": 110,', '"hw_nit_limit_pwm": -1,'),
    ('        "histogram_enable": true,\n', ''),
]

s = open(src, encoding='utf-8').read()
for old, new in EDITS:
    n = s.count(old)
    if n != 1:
        sys.exit('%r found %d times, expected 1' % (old, n))
    s = s.replace(old, new)

j = json.loads(s)
ti = [b for b in j if isinstance(b, dict) and b.get('touch_idle')]
if len(ti) != 1:
    sys.exit('%d touch_idle blocks, expected 1' % len(ti))
ti = ti[0]
if ti.get('hw_nit_limit') != -1 or ti.get('hw_nit_limit_pwm') != -1 or 'histogram_enable' in ti:
    sys.exit('the edits did not land in the touch_idle block')
if any('histogram_enable' in b for b in j if isinstance(b, dict)):
    sys.exit('histogram_enable is still in another block')
open(out, 'w', encoding='utf-8').write(s)
print('ok: hw_nit_limit=-1 hw_nit_limit_pwm=-1, histogram_enable removed')
