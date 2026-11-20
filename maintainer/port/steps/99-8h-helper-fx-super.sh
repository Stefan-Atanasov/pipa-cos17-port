#!/bin/sh
# Phase 8h (2026-11-20): Pipa Helper app round 2 (user review): Effects page (animation style -> service anim_check
# reads global pipa_anim_level; animation speed; visual blur, contour glow, live/window/animation blur; Apply =
# global pipa_fx_restart -> service restarts SystemUI + launcher), Games (performance profile = global
# pipa_game_scene 20/13/10/0; identity list of all apps), Keyboard > Super key (BUGS 155: global pipa_kb_super ->
# kernel nanosic super_alone, walt-hi13; pen_keys.sh runs the action on KEY_F18). Battery, Sound and Display pages
# removed (only links to ColorOS settings). The scripts come with the pipa_port folder (steps 2d/2f).
set -eu
. "$PORT/lib.sh"
STEP=8h
SE=$T/system_ext/pipa_port
need_grep 'fx_check' "$SE/service.sh"
need_grep 'pipa_game_scene' "$SE/service.sh"
need_grep 'KB_SUPER_P' "$SE/service.sh"
need_grep 'kb_super' "$SE/pen_keys.sh"
python3 -I - "$HERE/../helper/out/PipaHelper.apk" "$T/system/system/priv-app/PipaHelper/PipaHelper.apk" <<'PY'
import sys, zipfile, hashlib
src, img = sys.argv[1:]
d = b''.join(zipfile.ZipFile(src).read(n) for n in zipfile.ZipFile(src).namelist() if n.endswith('.dex'))
for s in (b'pipa_fx_restart', b'pipa_kb_super', b'pipa_game_scene'):
    assert s in d, 'PipaHelper.apk without %s' % s.decode()
a = hashlib.md5(open(src, 'rb').read()).hexdigest(); b = hashlib.md5(open(img, 'rb').read()).hexdigest()
assert a == b, 'image helper %s != helper/out %s' % (b, a)
print('helper (effects, games, Super key) in the image', a)
PY
# Effects > "Reboot to apply fully" after an animation style change: PowerManager.reboot needs REBOOT (privileged)
X=$T/system/system/etc/permissions/privapp-permissions-pipa-helper.xml
[ -f "$X" ] || die "no $X"
if ! grep -q 'android.permission.REBOOT' "$X"; then
    python3 -I - "$X" "$R/privapp-pipa-helper.xml" <<'PY'
import sys
s = open(sys.argv[1]).read()
o = '        <permission name="android.permission.WRITE_SECURE_SETTINGS" />\n'
assert s.count(o) == 1, 'privapp xml: WRITE_SECURE_SETTINGS line not found'
s = s.replace(o, o + '        <permission name="android.permission.REBOOT" />\n')
open(sys.argv[2], 'w').write(s)
PY
    cat "$R/privapp-pipa-helper.xml" > "$X"
fi
grep -n 'permission name' "$X"
set_layer "$STEP"
