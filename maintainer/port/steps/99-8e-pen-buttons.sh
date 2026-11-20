#!/bin/sh
# Phase 8e (2026-11-20, BUGS 153): Xiaomi Smart Pen buttons, one press = one action, near and away from the screen.
#
# * Kernel walt-hi12 (pipa_pen_buttons.c) owns the pen's Bluetooth keys: a press with the pen near the screen is a
#   stylus button in the pen events (the display reports it); a press with the pen away goes to the virtual input
#   device "pipa_pen_buttons": page keys (HyperOS default), stylus buttons or custom actions, plus F19-F24 for the
#   double/short/long actions that pipa_port/pen_keys.sh runs. A short stylus-button press also gives F13/F14:
#   pen_keys.sh sends it to the OPPO apps as an OPPO pencil click (IPeManager broadcasts; Notes: pen <-> eraser), and
#   service.sh sets ipe_pencil_connect_state = 2 while the pen is connected (Notes takes the clicks only then).
# * pipa_pen_buttons.kl: only the keys apps may see (page down/up, stylus buttons). Generic.kl would turn F13-F24
#   into real F keys for the focused app; unmapped here, Android drops them and only pen_keys.sh (evdev) reads them.
# * helper 2.5: launcher entry "Pen buttons" (settings, live test, app picker), global pipa_pen_buttons;
#   PenActionReceiver (flashlight). pen_keys.sh comes with the pipa_port folder (step 2d).
set -eu
. "$PORT/lib.sh"
STEP=8e
label() { setfattr -n security.selinux -v u:object_r:system_file:s0 "$@"; }
KL=$T/system/system/usr/keylayout/pipa_pen_buttons.kl
cat > "$KL" <<'KLEOF'
# pipa (8e, BUGS 153): virtual device of the kernel pen-button filter (pipa_pen_buttons.c).
# Only what apps may see; F13, F14, F19-F24 (pen actions) stay unmapped: pipa_port/pen_keys.sh reads them from evdev.
key 104   PAGE_UP
key 109   PAGE_DOWN
key 331   STYLUS_BUTTON_PRIMARY
key 332   STYLUS_BUTTON_SECONDARY
KLEOF
chown 0:0 "$KL"; chmod 644 "$KL"; label "$KL"
python3 -I - "$HERE/../helper/out/PipaHelper.apk" "$T/system/system/priv-app/PipaHelper/PipaHelper.apk" <<'PY'
import sys, zipfile, hashlib
src, img = sys.argv[1:]
d = zipfile.ZipFile(src).read('classes.dex')
assert b"pipa_pen_buttons" in d, "PipaHelper.apk: older than 2.5 (no pen settings)"
a = hashlib.md5(open(src, 'rb').read()).hexdigest(); b = hashlib.md5(open(img, 'rb').read()).hexdigest()
assert a == b, f'image helper {b} != helper/out {a} (step 2d ran with an older APK?)'
print('helper 2.5 in the image', a)
PY
grep -q 'pipa_pen_buttons' "$T/system_ext/pipa_port/pen_keys.sh" || die "pen_keys.sh without the kernel pen-button loop"
grep -q 'ipe_pencil_connect_state' "$T/system_ext/pipa_port/service.sh" || die "service.sh without the OPPO pencil state"
# the build tag for the Pipa Helper home screen ("Build pt133")
B=$T/system_ext/pipa_port/build
echo "$TAG" > "$B"; chown 0:0 "$B"; chmod 644 "$B"; label "$B"
set_layer "$STEP"
