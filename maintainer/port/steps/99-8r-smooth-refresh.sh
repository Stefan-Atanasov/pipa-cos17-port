#!/bin/sh
# Step 8r (2026-11-21, BUGS 110 / tester "v9 less smooth than beta 8"): fewer refresh mode switches during interaction.
#
# Evidence (pt147, traced_heavy + maintainer/perfetto/switch_jank.py, port-work/codex/switch-jank-20261120/REPORT.md):
#   real jank is 18 % of frames within +-100 ms of a display mode switch vs 5 % elsewhere; 22 % in the 300 ms after a
#   window transition when a switch lands there vs 3 % without. pipa's LCD changes rate by porch (seamless in the
#   driver), but SurfaceFlinger re-times VSYNC on every mode change ("ModeChange in progress" frames). OPPO tunes this
#   config for its LTPO OLED devices (adfr), where the switches cost nothing.
# Changes (all OPPO keys; research: port-work/codex/vrr-timing-20261120, vrr-lcd-online-20261121, ports-diff-*):
# * refresh_rate_config.xml <config>: animatingDelayTime="300". OplusRefreshRatePolicyImpl.checkDelayTimeAfterAnition
#   keeps the animation rate this long after a transition ends (stock 0 = the per-app rate lands on the first frames
#   of the new app). HyperOS on pipa holds its max rate until the animation end + 20-500 ms. OPPO uses per-app values
#   (300/360 ms) on other devices. Live A/B: switches in the 300 ms after a transition 6 -> 0.
# * App-wide rules: Auto column 90/60 Hz -> 120 Hz (as beta 8 step 2o and Danda's SM8250 port), except
#   - video/streaming apps (KEEP_60 below, plus apps that OPPO and stock HyperOS pipa both run at 60: long playback
#     stays at 60 Hz for battery; leaving them still switches once, after the delay),
#   - document/office apps (KEEP_OPPO: BUGS 109, documentsreader janks at 120: 44 % vs 31 % at 90).
#   Per-activity rules (video players), CTS entries and the 90/60/High/144 setting columns stay OPPO's. Battery: 120 vs
#   Auto measured 4.51 vs 4.53 W in use (pt147, heavy_mix POWER=1); touch idle still drops the panel to 60 Hz.
# * oplus_vrr_config.json touch_idle timeout 2500 -> 3500 ms (idle drop after the last finger lift; OPPO's LCD phones
#   ship 2500-3500, e.g. realme RMX3430 3000, RE602CL1 3500): fewer 60 <-> 120 switches between swipes, reading still
#   idles. hw_enable stays true (OPPO LCD default; the only public A/B with touch idle off, a Lenovo LCD tablet on
#   ColorOS 16, saw no jank gain). special_timeout is declared but never parsed in COS17 (dead key), so it is not used.
set -eu
. "$PORT/lib.sh"
STEP=8r
X=$T/system/my_product/etc/refresh_rate_config.xml
J=$T/system/my_product/etc/oplus_vrr_config.json
H=$HERE/refresh/hyperos_pipa_fps.txt
[ -f "$H" ] || die "no $H"
need_grep 'package="andes.oplus.documentsreader" rateId="1-2-2-3-4"' "$X"   # 6r ran, 2o is gone
forbid_grep 'animatingDelayTime=' "$X"

echo "== 8r refresh_rate_config: animatingDelayTime 300, Auto 120 Hz for app-wide rules (video and office keep theirs)"
replace_once "$X" 'appSwitchBoostMaxTemperature="47"/>' 'appSwitchBoostMaxTemperature="47" animatingDelayTime="300"/>'
python3 -I - "$X" "$H" "$R/refresh_rate_8r.txt" <<'PY'
import re, sys
path, hyper, rep = sys.argv[1:]
KEEP_60 = {   # video / streaming / short video: keep OPPO's rule (60 or 90 Hz in Auto; playback content rate)
    'com.google.android.youtube', 'com.google.android.apps.youtube.kids', 'com.google.android.apps.youtube.music',
    'app.revanced.android.youtube', 'app.morphe.android.youtube', 'com.vanced.android.youtube',
    'com.netflix.mediaclient', 'com.amazon.avod.thirdpartyclient', 'com.disney.disneyplus', 'com.wbd.stream',
    'com.hbo.hbonow', 'com.google.android.videos', 'tv.twitch.android.app', 'com.zhiliaoapp.musically',
    'com.ss.android.ugc.trill', 'com.ss.android.ugc.aweme', 'com.ss.android.ugc.aweme.lite', 'org.videolan.vlc',
    'com.mxtech.videoplayer.ad', 'com.mxtech.videoplayer.pro', 'org.xbmc.kodi', 'com.plexapp.android',
    'com.crunchyroll.crunchyroid', 'com.hulu.plus', 'tv.pluto.android', 'com.dazn', 'com.peacocktv.peacockandroid',
    'com.cbs.app', 'com.instagram.barcelona', 'com.coloros.video', 'com.heytap.yoli', 'com.oplus.video',
}
KEEP_OPPO = {   # documents / office: keep OPPO's own rule (BUGS 109)
    'andes.oplus.documentsreader', 'cn.wps.moffice_eng', 'cn.wps.moffice_i18n', 'cn.wps.xiaomi.abroad.lite',
    'cn.wps.moffice', 'com.microsoft.office.word', 'com.microsoft.office.excel', 'com.microsoft.office.powerpoint',
    'com.microsoft.office.officehubrow', 'com.microsoft.office.onenote', 'com.google.android.apps.docs.editors.docs',
    'com.google.android.apps.docs.editors.sheets', 'com.google.android.apps.docs.editors.slides', 'com.adobe.reader',
    'com.adobe.scan.android', 'com.yozo.office', 'com.yozo.office.en',
}
hyper60 = {l.split()[1] for l in open(hyper) if l.startswith('smart60 ')}
s = open(path, encoding='utf-8', errors='surrogateescape').read()
up, kept60, keptoff = [], [], []
def fix(m):
    line = m.group(0)
    pkg = re.search(r'package="([^"]+)"', line).group(1)
    if 'activity=' in line or '.cts' in pkg:
        return line
    def rid(r):
        cols = r.group(1).split('-')
        if len(cols) != 5 or cols[0] not in ('1', '2'):
            return r.group(0)
        if pkg in KEEP_OPPO:
            keptoff.append(pkg); return r.group(0)
        if pkg in KEEP_60 or (cols[0] == '2' and pkg in hyper60):   # video: OPPO's rule (60 or 90)
            kept60.append(pkg); return r.group(0)
        up.append(f'{pkg} {cols[0]}->3')
        return 'rateId="' + '-'.join(['3'] + cols[1:]) + '"'
    return re.sub(r'rateId="([0-9-]+)"', rid, line, count=1)
s2 = re.sub(r'^[ \t]*<item package="[^"]+"[^\r\n]*', fix, s, flags=re.M)
if len(up) < 1000:
    sys.exit(f"only {len(up)} rules changed: format changed?")
with open(path, 'r+', encoding='utf-8', errors='surrogateescape', newline='') as f:   # same inode: label kept
    f.write(s2); f.truncate()
open(rep, 'w').write('\n'.join(up + ['# kept 60: ' + ' '.join(kept60), '# kept OPPO: ' + ' '.join(keptoff)]) + '\n')
print(f"{len(up)} app rules -> Auto 120; kept at 60 (video): {len(kept60)}; kept OPPO (office): {len(keptoff)}")
PY
need_grep 'animatingDelayTime="300"' "$X"
need_grep 'package="andes.oplus.documentsreader" rateId="1-2-2-3-4"' "$X"
need_grep 'package="com.google.android.youtube" disableViewOverride="true" rateId="2-2-2-2-4"' "$X"
need_grep 'package="com.spotify.music" rateId="3-2-2-1-4"' "$X"
python3 -I -c 'import sys, xml.dom.minidom; xml.dom.minidom.parse(sys.argv[1])' "$X"

echo "== 8r oplus_vrr_config: touch idle timeout 2500 -> 3500 ms"
replace_once "$J" '"timeout": 2500,' '"timeout": 3500,'
python3 -I -c 'import json,sys; json.load(open(sys.argv[1]))' "$J"
getfattr -n security.selinux --only-values "$X"; echo
getfattr -n security.selinux --only-values "$J"; echo

echo "== system_ext build.prop: ro.pipa.port.layer=$STEP"
set_layer "$STEP"
