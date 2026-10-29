#!/bin/sh
# Phase 2p: Xiaomi pen battery in the ColorOS live alert (fluid cloud), on top of 2o.
#
# * my_product/priv-app/IPeManager: OPPO's pen app shows its own fluid-cloud battery capsule only after its OPPO BLE
#   link to the pen works (the Xiaomi pen does not have it). ipe-fluid/patch_ipemanager.py changes k0.h0 so that a
#   present event shows the capsule with the level from global ipe_pencil_battery_level (in-place dex patch, same
#   size; OPPO's platform signature block is kept, Android does not verify system-partition APKs at boot). The
#   prebuilt oat/ (vdex of the old dex) is removed; ART compiles the app on the device.
# * pipa_port PEN_FLUID: on each dock and undock, write ipe_pencil_battery_level and send the present event; sets
#   global pipa_pen_fluid=1.
# * pipa helper 0.5: no own pen pill while pipa_pen_fluid=1 (the low-battery notification stays).
# 2026-10-24 live test (bind mounts): capsule with pen icon and battery % on each dock/undock; hides by itself.
#
# Old layer script: build_beta5_2p.sh
#NEEDS: "$HERE/../helper/out/PipaHelper.apk" "$HERE/ipe-fluid/patch_ipemanager.py" "$ROM/pipa_port/service.sh" "$ROM/pipa_port/config.prop"
set -eu
. "$PORT/lib.sh"
APK=$HERE/../helper/out/PipaHelper.apk
IPE_STOCK_MD5=4bb067823603d6cb992e16c273229114   # C.06 (17.0.0.103) IPeManager 17.4.0
[ -f "$APK" ] || die "build the helper first: sh helper/build.sh"

S=$T/system
SE=$T/system_ext

echo "== IPeManager: fluid-cloud pen capsule"
IPE=$S/my_product/priv-app/IPeManager
md5=$(md5sum "$IPE/IPeManager.apk" | cut -d' ' -f1)
# patch_ipemanager.py finds every site by pattern (exactly once) and stops on another layout, so a new donor can try it.
[ "$md5" = "$IPE_STOCK_MD5" ] || echo "NOTE IPeManager.apk $md5 is not C.06: the pattern-checked patch decides; test the pen capsule"
python3 -I "$HERE/ipe-fluid/patch_ipemanager.py" "$IPE/IPeManager.apk" "$R/IPeManager.patched.apk"
cat "$R/IPeManager.patched.apk" > "$IPE/IPeManager.apk"   # in place (cat >): owner, mode and SELinux label stay
rm -rf "$IPE/oat"
md5sum "$IPE/IPeManager.apk"

echo "== pipa helper 0.5"
cat "$APK" > "$S/system/priv-app/PipaHelper/PipaHelper.apk"
md5sum "$S/system/priv-app/PipaHelper/PipaHelper.apk"

echo "== pipa_port: PEN_FLUID"
for f in service.sh config.prop; do
    cat "$ROM/pipa_port/$f" > "$SE/pipa_port/$f"
    echo "updated system_ext/pipa_port/$f"
done
need_grep pen_fluid "$SE/pipa_port/service.sh"
need_grep '^PEN_FLUID=1' "$SE/pipa_port/config.prop"

