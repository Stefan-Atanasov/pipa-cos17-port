#!/bin/sh
# AOD experiment (notes/PHASE2-ROM-INTEGRATION.md A9): can a framework doze-brightness overlay replace
# pipa_core's AodBacklightDaemon?
#
# Why it might: ColorOS's DozeBrightnessStrategyExtImpl.updateBrightness(f) only returns
# f * maxBrightness. With classic AOD the doze override is NaN, and AOSP then falls back to the
# framework config doze brightness (config_screenBrightnessDoze, 1/255 by default) -> almost 0 ->
# black AOD on the LCD. Raising that config with a fabricated overlay (cmd overlay fabricate, no APK
# needed) may give a visible AOD without the daemon. If it works, bake a real RRO into the ROM and
# drop the daemon and the power-tune AOD freeze.
#
#   sh aod_overlay_test.sh lookup            read-only: current values, overlay state, daemon state
#   sh aod_overlay_test.sh apply [1-255]     fabricate + enable the overlay (default 20), then reboot
#   sh aod_overlay_test.sh freeze-daemon     SIGSTOP AodBacklightDaemon so only the overlay acts
#   sh aod_overlay_test.sh resume-daemon     SIGCONT it again
#   sh aod_overlay_test.sh revert            disable the overlay, then reboot
#
# Test: lookup -> apply 20 -> reboot -> enable AOD -> freeze-daemon -> lock the screen and look
# (dark room and daylight). Try other values if it is too dim/bright. Then resume-daemon and
# revert (or keep it if it works). Live-only except the overlay, which persists until reverted.
set -eu
ADB=${ADB:-adb -s 192.168.0.37:5555}
NAME=pipa_doze
OV=com.android.shell:$NAME
sh_() { $ADB shell "$@" | tr -d '\r'; }

case ${1:-lookup} in
lookup)
    for r in android:integer/config_screenBrightnessDoze android:dimen/config_screenBrightnessDozeFloat \
             android:bool/config_allowAutoBrightnessWhileDozing android:bool/config_dozeAlwaysOnDisplayAvailable; do
        echo "$r = $(sh_ "cmd overlay lookup android $r" 2>&1)"
    done
    echo "--- overlay"; sh_ "cmd overlay list android" | grep -i -E "$NAME|pipa" || echo "(no pipa overlay)"
    echo "--- display power"; sh_ "dumpsys display" | grep -i -E "doze|mScreenBrightnessDozeConfig|dozeScreenBrightness" | head -12
    echo "--- AOD switch: $(sh_ settings get secure Setting_AodSwitchEnable)"
    for p in $(sh_ "pgrep -f AodBacklightDaemon"); do echo "AodBacklightDaemon pid $p state $(sh_ "awk '{print \$3}' /proc/$p/stat")"; done
    ;;
apply)
    v=${2:-20}
    [ "$v" -ge 1 ] && [ "$v" -le 255 ] || { echo "value 1-255"; exit 1; }
    hex=$(printf '0x%x' "$v")
    sh_ "cmd overlay fabricate --target android --name $NAME android:integer/config_screenBrightnessDoze 0x10 $hex"
    sh_ "cmd overlay enable --user 0 $OV"
    sh_ "cmd overlay list android" | grep "$NAME"
    echo "config_screenBrightnessDoze -> $v/255. Reboot for the display power controller to read it."
    ;;
freeze-daemon)
    for p in $(sh_ "pgrep -f AodBacklightDaemon"); do sh_ "su -c 'kill -STOP $p'" && echo "stopped $p"; done ;;
resume-daemon)
    for p in $(sh_ "pgrep -f AodBacklightDaemon"); do sh_ "su -c 'kill -CONT $p'" && echo "resumed $p"; done ;;
revert)
    sh_ "cmd overlay disable --user 0 $OV" && echo "disabled $OV; reboot to apply" ;;
*) sed -n '2,25p' "$0"; exit 1 ;;
esac
