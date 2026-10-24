#!/bin/sh
# Screen-off drain with USB attached and charging paused (input_suspend), for kernel A/B comparisons.
#   ADB="adb -s 83836a90" sh maintainer/kernel/drain_usb.sh <label> [minutes]     (default 40)
# USB keeps the SoC out of the deepest sleep, so the result (mAh/h) only compares with runs of this same
# method (joeyzhu kernel 2026-10-23: 71 mAh/h). Needs root; charging is re-enabled at the end and on Ctrl-C.
# Appends a row to port-work/perf-ab/drain.csv.
ADB=${ADB:-adb -s 83836a90}
L=${1:?label}; MIN=${2:-40}
S=/sys/class/power_supply/battery
r() { $ADB shell "su -c '$1'" | tr -d '\r'; }
cc() { r "cat $S/charge_counter"; }
resume() { r "echo 0 > $S/input_suspend"; }
trap 'resume; exit 1' INT TERM
r "echo 1 > $S/input_suspend"
sleep 5
$ADB shell 'input keyevent 223'
sleep 60                                   # let the screen-off transition settle
c0=$(cc); t0=$(date +%s); p0=$(r "cat $S/capacity")
echo "start $(date +%T) charge_counter=$c0 uAh capacity=$p0% (running $MIN min)"
sleep $((MIN * 60))
c1=$(cc); t1=$(date +%s); p1=$(r "cat $S/capacity")
resume
mah_h=$(awk -v a="$c0" -v b="$c1" -v s=$((t1 - t0)) 'BEGIN { printf "%.1f", (a - b) / 1000 / (s / 3600) }')
temp=$(r "cat $S/temp")
echo "end   $(date +%T) charge_counter=$c1 uAh capacity=$p1%  ->  $mah_h mAh/h"
mkdir -p ~/Documents/pipa/port-work/perf-ab
echo "$(date +%F_%T),$L,$MIN,$c0,$c1,$mah_h,$p0,$p1,$temp" >> ~/Documents/pipa/port-work/perf-ab/drain.csv
