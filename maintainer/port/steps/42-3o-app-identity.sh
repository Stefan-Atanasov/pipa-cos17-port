#!/bin/sh
# Phase 3o: per-app device identity (BUGS-TODO 28), system only.
#
# * system/framework/framework.jar: propspoof/patch_propspoof.sh adds com.android.internal.util.pipa.PipaAppIdentity
#   (classes6.dex) and calls it at the start of both Instrumentation.newApplication methods (classes.dex). Netflix
#   (com.netflix.mediaclient) sees a Pixel 6: Netflix sends Widevine L1 only to whitelisted models, and pipa's
#   Widevine is real L1. Google Photos (com.google.android.apps.photos) sees a Pixel XL (unlimited original-quality
#   backup). All other apps see the real Build values. Live test 2026-10-29 (bind mount): Netflix keySecLevel
#   WIDEVINE_L1, ESN NFANDROID1-PXA-T-GOOGLPIXEL=6-28440 (after a Netflix data clear; old L3 state stays cached).
# * The prebuilt boot image in system/framework no longer matches framework.jar. odrefresh compiles the boot image
#   into /data/misc/apexdata/com.android.art on the first boot (the same as after an OTA; first boot is slower).
# * system_ext/etc/build.prop: ro.pipa.port.layer=3o.
#NEEDS: "$HERE/propspoof/patch_propspoof.sh" "$HERE/propspoof/src/com/android/internal/util/pipa/PipaAppIdentity.java" "$PIPA_ROOT/tools/apktool/apktool.jar"
set -eu
. "$PORT/lib.sh"
STEP=3o

J=$T/system/system/framework/framework.jar
[ -f "$J" ] || die "no $J"
echo "== 28: framework.jar per-app identity"
ANDROID_HOME=${ANDROID_HOME:-/home/${OWNER%%:*}/Android/Sdk} bash "$HERE/propspoof/patch_propspoof.sh" "$J" "$R/framework.jar.new"
cat "$R/framework.jar.new" > "$J"   # in place (cat >): owner, mode and SELinux label stay
if ls "$T/system/system/framework/oat"/*/framework.* >/dev/null 2>&1; then die "prebuilt oat for framework.jar exists"; fi
md5sum "$J"

echo "== system_ext build.prop: ro.pipa.port.layer=$STEP"
set_layer "$STEP"
