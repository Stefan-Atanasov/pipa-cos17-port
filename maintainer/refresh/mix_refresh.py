#!/usr/bin/env python3
"""Refresh "mix" (BUGS-TODO 110, user decision 2026-11-14): OPPO engine and OPPO per-app rules, HyperOS-like Auto.

  python3 -I mix_refresh.py <base refresh_rate_config.xml> <hyperos_pipa_fps.txt> <out.xml> [report.txt]

<base> = the ROM's file BEFORE step 2o (donor rules + porter 144 Hz config). rateId columns (OPPO,
OplusRefreshRateConstants): Auto-90Hz-60Hz-120Hz-144Hz setting modes; values 0 unspecified, 1 = 90, 2 = 60, 3 = 120,
4 = 144 Hz.
* Auto column: OPPO's value (video/music/news 60, many apps 90, games 144), except apps in the stock HyperOS pipa
  "Default (recommended)" list (smart60/90/120), which get HyperOS's value. Unlisted apps: defaultRateId Auto = 4
  (HyperOS default 144 for apps without a rule).
* Fixed setting modes (90/60/120/144): every app-wide rule gets the selected rate (user wish: "High" means all apps).
* Unchanged: per-activity rules (video players, live streams: avoid 30 fps content at 144 Hz) and CTS entries.
* HyperOS smart-list apps without an OPPO rule are added.
"""
import re, sys

ID = {'60': '2', '90': '1', '120': '3', '144': '4'}
# HyperOS runs its launcher (com.miui.home) and SystemUI at the 144 Hz default (no list entry): same for ours.
UNLISTED_144 = {'com.android.launcher': '4', 'com.android.systemui': '4'}
base, lists, out = sys.argv[1:4]
rep = sys.argv[4] if len(sys.argv) > 4 else None
smart = {}
for line in open(lists, encoding='utf-8'):
    if line.startswith('#') or not line.strip():
        continue
    tag, pkg = line.split()
    m = re.fullmatch(r'smart(\d+)', tag)
    if m:
        smart[pkg] = ID[m.group(1)]

s = open(base, encoding='utf-8', errors='surrogateescape').read()
nl = '\r\n' if '\r\n' in s else '\n'
seen, changes = set(), []

def fix(m):
    line = m.group(0)
    pkg = re.search(r'package="([^"]+)"', line).group(1)
    if 'activity=' in line or '.cts' in pkg:
        return line
    seen.add(pkg)
    def rid(r):
        f = r.group(1).split('-')
        if len(f) < 4:
            return r.group(0)
        old = '-'.join(f)
        auto = smart.get(pkg, UNLISTED_144.get(pkg, f[0]))
        new = f'{auto}-1-2-3-4'
        if new != old:
            changes.append(f'{pkg} {old} -> {new}' + (' (HyperOS)' if pkg in smart else ''))
        return f'rateId="{new}"'
    return re.sub(r'rateId="([0-9-]+)"', rid, line, count=1)

s2 = re.sub(r'^[ \t]*<item package="[^"]+"[^\r\n]*', fix, s, flags=re.M)
# add HyperOS smart-list apps that OPPO has no rule for, after the last <item>
add = [f'  <item package="{p}" rateId="{a}-1-2-3-4" />  <!--HyperOS pipa smart list-->'
       for p, a in sorted(smart.items()) if p not in seen]
last = list(re.finditer(r'^[ \t]*<item [^\r\n]*', s2, flags=re.M))[-1]
s2 = s2[:last.end()] + ''.join(nl + x for x in add) + s2[last.end():]
changes += [f'{x.split(chr(34))[1]} added {x.split(chr(34))[3]}' for x in add]
# unlisted apps: Auto 144 (HyperOS default), fixed modes = the selected rate
s2, n = re.subn(r'defaultRateId="[0-9-]+"', 'defaultRateId="4-1-2-3-4"', s2, count=1)
if n != 1:
    sys.exit('no defaultRateId in <config>: format changed?')
open(out, 'w', encoding='utf-8', errors='surrogateescape', newline='').write(s2)
if rep:
    open(rep, 'w').write('\n'.join(changes) + '\n')
print(f'{len(changes)} changes ({len(add)} added), {sum(1 for p in smart if p in seen)} HyperOS apps matched OPPO rules')
