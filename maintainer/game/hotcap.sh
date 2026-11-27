#!/system/bin/sh
# BUGS 175 match logger (light: no top/dumpsys per sample). On the tablet as root, PUBG running:
#   adb push hotcap.sh /data/local/tmp/; adb shell "su -c 'nohup sh /data/local/tmp/hotcap.sh [samples] [main tid] >/dev/null 2>&1 &'"
# Out: /data/local/tmp/hot_cap.txt. T lines every 2 s (cur/max freq cpu0/4/7, GPU cur/max/busy, sconfig, battery
# 0.1 C, cpu of the main thread); W blocks every 30 s = SurfaceFlinger timestats present2present histogram of that window.
OUT=/data/local/tmp/hot_cap.txt; N=${1:-900}
P=$(pidof com.tencent.ig) || { echo "PUBG not running"; exit 1; }
M=${2:-$(for t in /proc/$P/task/*; do [ "$(cat $t/comm)" = UEGameThread ] && echo "$(cut -d" " -f14 $t/stat) $(basename $t)"; done | sort -n | tail -1 | cut -d" " -f2)}
echo "pid $P main $M" > $OUT
dumpsys SurfaceFlinger --timestats -disable -clear >/dev/null; dumpsys SurfaceFlinger --timestats -enable >/dev/null
i=0
while [ $i -lt $N ] && [ -d /proc/$P ]; do
  c=$(sed 's/.*) //' /proc/$P/task/$M/stat | cut -d' ' -f37)
  echo "T $(date +%T) f $(cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_cur_freq /sys/devices/system/cpu/cpu4/cpufreq/scaling_cur_freq /sys/devices/system/cpu/cpu7/cpufreq/scaling_cur_freq | tr '\n' ' ')max $(cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_max_freq /sys/devices/system/cpu/cpu4/cpufreq/scaling_max_freq /sys/devices/system/cpu/cpu7/cpufreq/scaling_max_freq | tr '\n' ' ')gpu $(cat /sys/class/kgsl/kgsl-3d0/devfreq/cur_freq /sys/class/kgsl/kgsl-3d0/devfreq/max_freq /sys/class/kgsl/kgsl-3d0/gpu_busy_percentage | tr '\n' ' ')sc $(cat /sys/class/thermal/thermal_message/sconfig) bat $(cat /sys/class/power_supply/battery/temp) main $c" >> $OUT
  i=$((i+1))
  if [ $((i % 15)) = 0 ]; then
    echo "W $(date +%T)" >> $OUT
    dumpsys SurfaceFlinger --timestats -dump -maxlayers 1 | grep -A1 -E "layerName|^present2present histogram" | grep -E "layerName|^0ms" >> $OUT
    dumpsys SurfaceFlinger --timestats -clear >/dev/null
  fi
  sleep 2
done
dumpsys SurfaceFlinger --timestats -disable -clear >/dev/null
echo "end $(date +%T)" >> $OUT
