#!/bin/sh
# 6i (BUGS-TODO 88, tester 2026-11-09): passive USB-C earphones (no DAC) give no sound.
#
# pipa has the analog path: FSA4480 switch + wcd938x MBHC (dts qcom,msm-mbhc-usbc-audio-supported = <1>,
# CONFIG_QCOM_FSA4480_I2C=y), mixer paths "headphones" / "headset-mic", and "Wired Headset" / "Wired Headphones" in
# the audio policy. The kernel reports the plug as input switch events (SW_HEADPHONE_INSERT ...). Android listens
# to them only with config_useDevInputEventForAudioJack=true. framework-res has false. Stock HyperOS sets true in
# vendor/overlay/FrameworksResTarget.apk; the port vendor has no /vendor/overlay at all, so Android never saw an
# analog headset. Earphones with a DAC are USB audio devices (another path) and work.
# * product/overlay/PipaFrameworkOverlay/PipaFrameworkOverlay.apk: static RRO on "android" with the one value
#   (source maintainer/overlays/framework; as the 4f overlay).
# * system_ext/etc/build.prop: ro.pipa.port.layer=6i (new overlay: the package cache must be cleared).
# Build the APK first: sh maintainer/overlays/framework/build.sh
# NOT TESTED when written (2026-11-10, offline). Check on the tablet: `dumpsys input` shows the "Headset Jack"
# device, `cmd overlay list android` shows the overlay enabled, plug in: `dumpsys audio` shows a wired headset
# device and the sound moves to the earphones; unplug: sound back on the speakers.
#NEEDS: "$HERE/overlays/framework/out/PipaFrameworkOverlay.apk"
set -eu
. "$PORT/lib.sh"
STEP=6i

O=$T/product/overlay
[ -d "$O" ] || die "no $O"
SIB=$(ls "$O"/*.apk | head -1)
D=$O/PipaFrameworkOverlay
[ -e "$D" ] && die "$D exists already"
mkdir "$D"
chmod 755 "$D"
setfattr -n security.selinux -v "$(getfattr --only-values -n security.selinux "$O")" "$D"
F=$D/PipaFrameworkOverlay.apk
cp -p "$SIB" "$F"                       # owner, mode (cp -p keeps no SELinux label: set below)
cat "$HERE/overlays/framework/out/PipaFrameworkOverlay.apk" > "$F"
setfattr -n security.selinux -v "$(getfattr --only-values -n security.selinux "$SIB")" "$F"
echo "added   product/overlay/PipaFrameworkOverlay/PipaFrameworkOverlay.apk"
md5sum "$F"
set_layer "$STEP"
