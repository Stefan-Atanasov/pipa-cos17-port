#!/bin/sh
# Quick hardware/root check after booting a kernel (test boot or flash). Read-only.
#   ADB="adb -s 83836a90" sh maintainer/kernel/kernel_check.sh <label>
# Prints one line per check; saves the raw output to port-work/kernel/checks/<label>.txt
ADB=${ADB:-adb -s 83836a90}
L=${1:-check}
OUT=~/Documents/pipa/port-work/kernel/checks; mkdir -p "$OUT"
r() { $ADB shell "su -c '$1'" 2>&1 | tr -d '\r'; }
{
echo "== kernel";      $ADB shell 'uname -r; cat /proc/version' | tr -d '\r'
echo "== boot";        $ADB shell 'getprop sys.boot_completed; getprop ro.boot.slot_suffix; uptime' | tr -d '\r'
echo "== root";        r 'id; /data/adb/ksud -V'
echo "== susfs";       r 'dmesg | grep -m3 -i susfs'
echo "== audit";       r 'dmesg | grep -m3 -E "audit|avc:"'; r 'ls /proc/self/loginuid 2>&1'
echo "== input";       r 'grep -E "^N: Name" /proc/bus/input/devices'
echo "== display";     $ADB shell 'dumpsys SurfaceFlinger | grep -m1 activeMode; dumpsys display | grep -m1 -oE "xDpi=[0-9.]+"' | tr -d '\r'
echo "== wifi";        $ADB shell 'cmd wifi status 2>/dev/null | head -2' | tr -d '\r'
echo "== bluetooth";   $ADB shell 'settings get global bluetooth_on; dumpsys bluetooth_manager | grep -m1 -E "state:"' | tr -d '\r'
echo "== audio";       $ADB shell 'dumpsys media.audio_flinger | grep -m3 -E "Output thread|HAL"' | tr -d '\r'
echo "== battery";     r 'cd /sys/class/power_supply/battery; cat status capacity current_now temp; ls /sys/class/power_supply | tr "\n" " "'
echo "== pen nodes";   r 'cat /sys/class/power_supply/wireless/reverse_pen_soc /sys/class/power_supply/fuda/reverse_chg_hall4 2>&1'
echo "== camera/face"; r 'pidof cameraserver; pgrep -f facehal | head -2'
echo "== services";    r 'getprop init.svc.pipa_port; getprop init.svc.pipa_subsys0; tail -3 /data/local/tmp/pipa_port.log'
echo "== sched";       r 'cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_governor; cat /proc/sys/kernel/sched_cass* 2>/dev/null | head -2'
echo "== crashes";     r 'dmesg | grep -m8 -iE "panic|oops|BUG:|Unable to handle|call trace|watchdog"'; r 'ls -t /data/tombstones | head -3'
echo "== modules";     r 'ls /data/adb/modules; cat /data/local/tmp/pipa_susfs.log 2>/dev/null | tail -3'
} > "$OUT/$L.txt" 2>&1
cat "$OUT/$L.txt"
