#!/bin/sh
# 6l (BUGS 95, 96; user 2026-11-12: "as good as HyperOS"): keyboard cover polish on top of 6k.
#
# * vendor/bin/xiaomi-keyboard: usable angle window 40..230 degrees -> 45..185, the stock HyperOS window for pipa
#   (miui-services AngleStateController + changeAngleIfNeed). Two sites (accelerometer thread 0x256c/0x2574, keypad
#   frame path 0x2998/0x29a4): sub w8,w0,#40 -> #45; cmp w8,#191 -> #140.
# * oplus-services.jar KeyGestureControllerExtlmpl.handleMetaKeyForOld(): Super/Meta alone sent key gesture 208
#   (Breeno) on CN; now 206, ColorOS's all-apps gesture (PixelOS: all apps; HyperOS: launcher dock). Meta+key
#   shortcuts are a different path. Same-size dex edit, patch_logspam.py table 6l. With Breeno switched off the key
#   did nothing (the hook consumes it). Codex analysis: port-work/codex/kb-superkey*-answer.md.
# * pipa_port service.sh: show_ime_with_hard_keyboard is no longer set to 1 at the first boot; on walt-r20+ it is
#   set to 0 once per install (also on a dirty flash), so the on-screen keyboard hides while the cover is in use.
# NOT TESTED when written (2026-11-12, offline). oplus-services is a system_server jar: boot check first (no boot
# loop, `logcat -b crash` empty). With the cover: Super alone opens the app drawer on the home screen and in an
# app; Super+D / other shortcuts as before; fold at ~185 degrees and under 45 disables.
#NEEDS: "$HERE/logspam/patch_logspam.py" "$HERE/jar-edits/venv/bin/python" "$ROM/pipa_port/service.sh"
set -eu
. "$PORT/lib.sh"
STEP=6l

SE=$T/system_ext
V=$T/vendor
F=$T/system/system/framework

echo "== 6l xiaomi-keyboard: angle window 45..185"
python3 -I - "$V/bin/xiaomi-keyboard" <<'PY'
import hashlib, struct, sys
p = sys.argv[1]
d = open(p, 'rb').read()
assert hashlib.md5(d).hexdigest() == 'f908f1b69efef9c4f52850b72ab7d296', 'unexpected xiaomi-keyboard md5 (want 6k)'
edits = [(0x256c, 0x5100a008, 0x5100b408), (0x2574, 0x7102fd1f, 0x7102311f),      # sub #40 -> #45, cmp #191 -> #140
         (0x2998, 0x5100a008, 0x5100b408), (0x29a4, 0x7102fd1f, 0x7102311f)]
with open(p, 'r+b') as f:                            # same inode: label kept
    for off, old, new in edits:
        assert struct.unpack_from('<I', d, off)[0] == old, hex(off)
        f.seek(off); f.write(struct.pack('<I', new))
print('patched xiaomi-keyboard', hashlib.md5(open(p, 'rb').read()).hexdigest())
PY

echo "== 6l oplus-services.jar: Meta alone = all apps"
j=oplus-services
"$HERE/jar-edits/venv/bin/python" -I "$HERE/logspam/patch_logspam.py" "$F/$j.jar" "$R/$j.jar" 6l 2>&1 | grep -v DEBUG
[ -s "$R/$j.jar" ] || die "patch_logspam 6l failed: $j.jar"
cat "$R/$j.jar" > "$F/$j.jar"   # in place (cat >): owner, mode and SELinux label stay
rm -f "$R/$j.jar"
for o in "$F/oat"/*/"$j".*; do if [ -e "$o" ]; then rm -v "$o"; fi; done

echo "== 6l pipa_port: on-screen keyboard default"
cat "$ROM/pipa_port/service.sh" > "$SE/pipa_port/service.sh"
need_grep 'hard_kb_ime_default_set' "$SE/pipa_port/service.sh"
forbid_grep 'show_ime_with_hard_keyboard 1' "$SE/pipa_port/service.sh"
set_layer "$STEP"
