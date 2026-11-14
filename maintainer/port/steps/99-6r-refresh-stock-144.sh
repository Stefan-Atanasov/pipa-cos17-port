#!/bin/sh
# Step 6r (BUGS-TODO 110, user 2026-11-14 "refresh as OPPO intends"): stock OPPO refresh rules + the 144 Hz column, and
# touch idle also in dark mode. Replaces step 2o (removed: it set ~1900 app rules to 120 Hz in Auto, against OPPO's
# per-app choices; e.g. Documents 120 instead of 90 = BUGS 109 jank).
#
# * system/my_product/etc/refresh_rate_config.xml: rateId columns are the setting modes Auto-90-60-High120-FPSMax144
#   (values 1 = 90, 2 = 60, 3 = 120, 4 = 144 Hz). OPPO's app rules have 4 columns; the porter's 144 Hz config
#   (maxrefreshsettings 4, defaultMaxRate 144) only gave launcher/settings/systemui a 5th one, so with Settings > Screen
#   refresh rate > High > "FPS Max 144 Hz" (secure oplus_customize_screen_refresh_rate=8) apps stayed at 120. This step
#   appends "-4" to every app-wide 4-column rule (not per-activity video rules, not CTS entries). Live 2026-11-14:
#   Auto = OPPO (Documents 90, Spotify 60, Play 120); FPS Max 144 = 144; "Supported apps" switch Off -> 120.
# * system/my_product/etc/oplus_vrr_config.json: touch_idle "darkmode_enable": true. OPPO's HW idle strategy (panel to
#   60 Hz) is off in dark mode (OLED low-refresh flicker guard; SF dumpsys --oplus "DarkModeEnable: false",
#   "darkModeIsOff 0"); pipa is LCD. Same kind of LCD glue as 2z (nit gate). Live: dark mode, Settings 120 -> 60,
#   Documents 90 -> 60 about 1 s after the last touch.
set -eu
. "$PORT/lib.sh"
STEP=6r
X=$T/system/my_product/etc/refresh_rate_config.xml
J=$T/system/my_product/etc/oplus_vrr_config.json
need_grep 'maxrefreshsettings="4"' "$X"
need_grep 'package="andes.oplus.documentsreader" rateId="1-2-2-3"' "$X"   # stock rule: 2o must be gone

echo "== 6r refresh_rate_config: 144 Hz column for app-wide rules"
python3 -I - "$X" "$R/refresh_rate_6r.txt" <<'PY'
import re, sys
path, rep = sys.argv[1:]
s = open(path, encoding='utf-8', errors='surrogateescape').read()
done = []
def fix(m):
    line = m.group(0)
    pkg = re.search(r'package="([^"]+)"', line).group(1)
    if 'activity=' in line or '.cts' in pkg:
        return line
    def rid(r):
        if len(r.group(1).split('-')) != 4:
            return r.group(0)
        done.append(pkg)
        return f'rateId="{r.group(1)}-4"'
    return re.sub(r'rateId="([0-9-]+)"', rid, line, count=1)
s2 = re.sub(r'^[ \t]*<item package="[^"]+"[^\r\n]*', fix, s, flags=re.M)
if len(done) < 1500:
    sys.exit(f"only {len(done)} rules changed: format changed?")
with open(path, 'r+', encoding='utf-8', errors='surrogateescape', newline='') as f:   # same inode: label kept
    f.write(s2); f.truncate()
open(rep, 'w').write('\n'.join(done) + '\n')
print(f"{len(done)} app rules got the 144 Hz column")
PY
need_grep 'package="andes.oplus.documentsreader" rateId="1-2-2-3-4"' "$X"

echo "== 6r oplus_vrr_config: touch idle in dark mode (LCD)"
forbid_grep '"darkmode_enable"' "$J"
replace_once "$J" '"touch_idle": true,' '"touch_idle": true,
        "darkmode_enable": true,'
python3 -I -c 'import json,sys; json.load(open(sys.argv[1]))' "$J"
getfattr -n security.selinux --only-values "$X"; echo

echo "== system_ext build.prop: ro.pipa.port.layer=$STEP"
set_layer "$STEP"
