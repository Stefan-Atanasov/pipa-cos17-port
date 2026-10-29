#!/bin/sh
# Phase 2z: the panel drops to 60 Hz when the screen is idle (BUGS-TODO B11), on top of 2x (system + system_ext).
#
# * system/my_product/etc/oplus_vrr_config.json: ColorOS touch idle (OTI) switched only the render rate to 60 (the
#   panel stayed at 120 Hz), because its HW strategy needs 110+ nits (an OLED flicker guard; the ColorOS nit estimate
#   on pipa is low). module/tools/patch_vrr_config.py sets hw_nit_limit/hw_nit_limit_pwm to -1 and removes
#   histogram_enable (the nit tables). Then the panel goes to the 60 Hz mode 2.5 s after the last touch.
# * system_ext/etc/build.prop: ro.pipa.port.layer=2z (early.sh clears the package cache).
#
# Old layer script: build_beta5_2z.sh
#NEEDS: "$TOOLS/patch_vrr_config.py"
set -eu
. "$PORT/lib.sh"
STEP=2z

S=$T/system
SE=$T/system_ext

echo "== oplus_vrr_config.json: touch idle may switch the panel mode at any brightness"
F=$S/my_product/etc/oplus_vrr_config.json
python3 -I "$TOOLS/patch_vrr_config.py" "$F" "$R/oplus_vrr_config.json.new"
cat "$R/oplus_vrr_config.json.new" > "$F"   # in place (cat >): owner, mode and SELinux label stay
md5sum "$F"
getfattr -n security.selinux --only-values "$F"; echo

echo "== system_ext build.prop: ro.pipa.port.layer=$STEP"
set_layer "$STEP"

