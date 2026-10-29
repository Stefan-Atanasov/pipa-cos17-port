#!/bin/sh
# Phase 2o: 120 Hz for apps in ColorOS's Auto refresh mode, on top of 2n (system only).
#
# system/my_product/etc/refresh_rate_config.xml caps many apps in Auto mode (rateId "auto-90-60-120", values
# 1 = 90 Hz, 2 = 60 Hz, 3 = 120 Hz): music apps at 60 Hz, others at 60/90. With an animation boost Spotify ran at 90 Hz
# and the panel switched 90 <-> 120 in the middle of every open/close animation (stutter; 2026-10-24 trace: SF frames
# on time 83 % -> 90 % with Spotify at 120). This step sets field 1 (Auto) and field 4 (120 Hz mode) of every
# app-wide rule to 3 (120 Hz). Per-activity rules (video players, live streams), CTS entries and the 90/60 Hz setting
# modes stay as OPPO set them; other fullscreen video drops through Android's content detection.
#
# Old layer script: build_beta5_2o.sh
set -eu
. "$PORT/lib.sh"


echo "== refresh_rate_config: app-wide rules -> 120 Hz in Auto and 120 Hz modes"
python3 -I - "$T/system/my_product/etc/refresh_rate_config.xml" "$R/refresh_rate_changes.txt" <<'PY'
import re, sys
path, rep = sys.argv[1:]
s = open(path, encoding='utf-8', errors='surrogateescape').read()
changed = []
def fix(m):
    line = m.group(0)
    if 'activity=' in line or '.cts' in line:
        return line
    def rid(r):
        f = r.group(1).split('-')
        if len(f) < 4:
            return r.group(0)
        old = '-'.join(f)
        f[0] = '3'; f[3] = '3'
        new = '-'.join(f)
        if new != old:
            changed.append(f"{re.search(r'package=\"([^\"]+)\"', line).group(1)} {old} -> {new}")
        return f'rateId="{new}"'
    return re.sub(r'rateId="([0-9-]+)"', rid, line)
s2 = re.sub(r'^\s*<item package="[^"]+"[^\n]*$', fix, s, flags=re.M)
if not changed:
    sys.exit("no rule changed: format changed?")
with open(path, 'r+', encoding='utf-8', errors='surrogateescape') as f:   # same inode: label kept
    f.write(s2); f.truncate()
open(rep, 'w').write('\n'.join(changed) + '\n')
print(f"{len(changed)} app rules changed")
PY
need_grep 'package="com.spotify.music" rateId="3-' "$T/system/my_product/etc/refresh_rate_config.xml"

