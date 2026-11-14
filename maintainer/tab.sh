#!/bin/bash
# Tablet helpers over USB adb (saves re-writing the same adb lines each session).
#   bash maintainer/tab.sh unlock            wake + swipe + PIN (from ~/.config/pipa/tablet-pin, sent via stdin, never echoed)
#   bash maintainer/tab.sh off | on | home
#   bash maintainer/tab.sh cycle [N] [S]     N screen off/on cycles, S s off (default 3, 4)
#   bash maintainer/tab.sh dmesg [REGEX]     root dmesg, filtered (default: touch/display lines)
#   bash maintainer/tab.sh refresh           current SurfaceFlinger mode (vsync rate)
#   bash maintainer/tab.sh idle [PKG]        open PKG (default Settings), scroll, panel Hz for 4 s + OTI request
#                                            (screen must be ON and unlocked: an off screen keeps its last mode)
#   bash maintainer/tab.sh shot FILE.png     screenshot
#   bash maintainer/tab.sh boot              wait for sys.boot_completed
# SERIAL=<serial> overrides the USB serial.
S=${SERIAL:-83836a90}
a() { adb -s "$S" "$@"; }
unlock() {
	a shell input keyevent 224; sleep 1
	a shell input swipe 1200 1700 1200 500 200; sleep 1
	echo "input text $(cat ~/.config/pipa/tablet-pin); input keyevent 66" | a shell >/dev/null; sleep 2
}
case "$1" in
unlock) unlock ;;
off) a shell input keyevent 26 ;;
on) a shell input keyevent 224 ;;
home) a shell input keyevent 3 ;;
cycle) for _ in $(seq 1 "${2:-3}"); do a shell input keyevent 26; sleep "${3:-4}"; a shell input keyevent 224; sleep 3; done ;;
dmesg) a shell 'su -c dmesg' | grep -a -E "${2:-NVT-ts|r2[0-9]:|PANEL_DEAD|vregs|power_mode}" ;;
idle) a shell monkey -p "${2:-com.android.settings}" -c android.intent.category.LAUNCHER 1 >/dev/null 2>&1; sleep 2
	a shell input swipe 1400 1500 1400 600 300; for t in 0.3 1 1 1 1; do sleep $t; printf '%s ' "$("$0" refresh)"; done; echo
	a shell 'dumpsys SurfaceFlinger --oplus 2>/dev/null' | grep -a -E 'darkModeIsOff|BestRequest|DarkModeEnable' | grep -o -E 'darkModeIsOff [01]|DarkModeEnable: [a-z]+|fps=[0-9]+' | tr '\n' ' '; echo ;;
refresh) a shell "dumpsys SurfaceFlinger 2>/dev/null | grep -a -m1 activeMode" | grep -o "vsyncRate=[0-9.]* Hz" ;;
shot) a exec-out screencap -p > "${2:?file}" ;;
boot) a wait-for-device; until [ "$(a shell getprop sys.boot_completed 2>/dev/null | tr -d '\r')" = 1 ]; do sleep 2; done ;;
*) sed -n 2,10p "$0"; exit 1 ;;
esac
