#!/bin/sh
# Phase 7x (user 2026-11-18): "Live blur" Quick Settings tile (helper 2.2), default off.
#
# * ColorOS SystemUI (PlatformBlurManagerImpl.useMotionBlur) re-blurs the shade background 60 times a second
#   (MOTION_60) only at Gaussian level 1 (tier 1 phones) or with persist.sys.oplus.systemui.dynamic_blur=true; at
#   our level 2 it uses STATIC (one captured frame: a playing video freezes behind Quick Settings). This is stock.
# * A/B 2026-11-18 (QS open/close x15 over a playing video, 2 rounds each): SystemUI janky frames live 21.4/19.7 %,
#   static 4.0/3.8 %; p50 13 vs 10-11 ms. So: off by default, the user can turn it on.
# * helper 2.2: BlurTile writes global pipa_live_blur; service.sh blur_check sets the property (pipa_port may set
#   system_prop, rule in pipa_port_rules.cil). SystemUI reads it at its start: reboot to apply.
# * disable_window_blurs (2q) is not related: the shade blur is SystemUI's own.
#NEEDS: "$HERE/../helper/out/PipaHelper.apk" "$ROM/pipa_port/service.sh"
set -eu
. "$PORT/lib.sh"
STEP=7x
python3 -I - "$HERE/../helper/out/PipaHelper.apk" <<'PY'
import sys, zipfile
d = zipfile.ZipFile(sys.argv[1]).read('classes.dex')
assert b'BlurTile' in d and b'pipa_live_blur' in d, 'PipaHelper.apk is not 2.2 (no BlurTile)'
PY
SE=$T/system_ext
cat "$ROM/pipa_port/service.sh" > "$SE/pipa_port/service.sh"   # in place: owner, mode and label stay
need_grep '^blur_check() {$' "$SE/pipa_port/service.sh"
need_grep 'gboard_default' "$SE/pipa_port/service.sh"
echo "service.sh: live blur tile; helper 2.2"
set_layer "$STEP"
