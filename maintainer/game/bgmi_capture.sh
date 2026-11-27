#!/system/bin/sh
# BGMI hot-drop capture (run on the tablet as root, before the match starts).
# About every 1.5 s: top 12 BGMI threads (TID, core, %CPU of one core, name), per-core clocks, GPU clock/busy,
# thermal scene, skin temp. Output: /data/local/tmp/bgmi_cap.txt. Stops after N samples (default 600 = 20 min).
N=${1:-600}; PKG=${PKG:-com.pubg.imobile}; OUT=/data/local/tmp/bgmi_cap.txt
P=$(pidof $PKG) || { echo "start BGMI first"; exit 1; }
: > $OUT
i=0
while [ $i -lt $N ] && [ -d /proc/$P ]; do
  {
    echo "== $(date +%T)"
    printf 'freq'; for c in 0 1 2 3 4 5 6 7; do printf ' %s' $(( $(cat /sys/devices/system/cpu/cpu$c/cpufreq/scaling_cur_freq) / 1000 )); done; echo
    echo "gpu $(( $(cat /sys/class/kgsl/kgsl-3d0/devfreq/cur_freq) / 1000000 )) MHz busy $(cat /sys/class/kgsl/kgsl-3d0/gpu_busy_percentage) sc=$(cat /sys/class/thermal/thermal_message/sconfig 2>/dev/null) bat=$(cat /sys/class/power_supply/battery/temp)"
    top -H -b -n 2 -d 1 -m 12 -p $P -o TID,CPU,%CPU,NAME | awk "/TID/{n++} n==2"   # 2nd frame = real 1 s sample
  } >> $OUT
  i=$((i+1))
done
echo "done: $OUT"
