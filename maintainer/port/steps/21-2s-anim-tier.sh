#!/bin/sh
# Phase 2s: launcher animation tier 3 + Quick Settings tile, no animation 0.8 default, on top of 2r (system +
# system_ext).
#
# * pipa_port ANIM_TIER: persist.sys.oplus.anim_level from global pipa_anim_level, default ANIM_LEVEL=3 (traced_heavy
#   2026-10-24: SF dropped frames 2.7 -> 0.3 %, GPU deadline misses 116 -> 10; 2 = 1.5 %, keeps every parallel-
#   animation path). A change restarts the launcher.
# * pipa helper 0.6: Quick Settings tile "Animations" (tap order 3 -> 2 -> 1 -> 4) writes pipa_anim_level.
# * pipa_port SMOOTH_DEFAULT: no animation scales 0.8 any more (they stay at 1.0, user choice).
# * pipa_port sget(): settings reads through `content query`. `settings get` failed in the service domain since 2e
#   (colour state got the error text, Bedtime was turned on at each boot).
# * system_ext/etc/build.prop: ro.pipa.port.layer=2s (early.sh clears the package cache: the helper manifest changed).
#
# Old layer script: build_beta5_2s.sh
#NEEDS: "$HERE/../helper/out/PipaHelper.apk" "$ROM/pipa_port/service.sh" "$ROM/pipa_port/pen_keys.sh" "$ROM/pipa_port/early.sh" "$ROM/pipa_port/config.prop"
set -eu
. "$PORT/lib.sh"
STEP=2s
APK=$HERE/../helper/out/PipaHelper.apk
[ -f "$APK" ] || die "build the helper first: sh helper/build.sh"

S=$T/system
SE=$T/system_ext

echo "== pipa helper 0.6 (animation tile)"
cat "$APK" > "$S/system/priv-app/PipaHelper/PipaHelper.apk"   # in place (cat >): owner, mode and SELinux label stay
rm -rf "$S/system/priv-app/PipaHelper/oat"
md5sum "$S/system/priv-app/PipaHelper/PipaHelper.apk"

echo "== pipa_port: animation tier, smoothness defaults"
for f in service.sh pen_keys.sh early.sh config.prop; do
    cat "$ROM/pipa_port/$f" > "$SE/pipa_port/$f"
    echo "updated system_ext/pipa_port/$f"
done
need_grep anim_check "$SE/pipa_port/service.sh"
need_grep "^sget()" "$SE/pipa_port/service.sh"
# (2s had `! grep -q "settings get " service.sh` here: a no-op under set -e, and wrong for the current service.sh,
#  because 2t went back to `settings get` into a file. Not checked.)
need_grep '^ANIM_LEVEL=3' "$SE/pipa_port/config.prop"
need_grep KSWAPD_NO_PRIME "$SE/pipa_port/service.sh"
forbid_grep 'settings put global $k 0.8' "$SE/pipa_port/service.sh"

echo "== system_ext build.prop: ro.pipa.port.layer=$STEP"
set_layer "$STEP"

