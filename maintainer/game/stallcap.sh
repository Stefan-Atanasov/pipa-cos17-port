#!/system/bin/sh
# BUGS 175 (2026-11-27): PUBG stutters (200-300 ms frames) vs memory. On the tablet as root, PUBG running:
#   adb push stallcap.sh /data/local/tmp/; adb shell "su -c 'nohup sh /data/local/tmp/stallcap.sh [windows] >/dev/null 2>&1 &'"
# Every 5 s one line: game frames, frames >= 100 ms (SurfaceFlinger timestats present2present), memory PSI some/full
# stall (ms), swap in/out and major faults (pages), kswapd0 CPU (ticks), cpu4/cpu7 MHz, GPU busy %, DDR latency/bandwidth
# votes (MB/s, stock max: lat 10437, bw 6881 = Qualcomm post_boot), cpu7 L3 MHz (samples at the window end). Out: /data/local/tmp/stall_cap.txt
OUT=/data/local/tmp/stall_cap.txt; TS=/data/local/tmp/stall_ts.txt; N=${1:-240}
P=$(pidof com.tencent.ig) || { echo "PUBG not running"; exit 1; }
K=$(ps -A -o PID,NAME | awk '$2 ~ /^kswapd0/{print $1; exit}'); [ -n "$K" ] || K=1
vm() { awk -v k="$1" '$1==k{print $2}' /proc/vmstat; }
psi() { awk -v k="$1" '$1==k{split($5,a,"="); print a[2]}' /proc/pressure/memory; }
kt() { awk '{print $14+$15}' /proc/$K/stat; }
D=/sys/class/devfreq; DL="$D/soc:qcom,cpu4-llcc-ddr-lat/cur_freq"; DB="$D/soc:qcom,cpu-llcc-ddr-bw/cur_freq"; L3="$D/18590000.qcom,devfreq-l3:qcom,cpu7-cpu-l3-lat/cur_freq"
echo "time frames long100 psi_some_ms psi_full_ms swpin swpout majflt kswapd cpu4 cpu7 gpu ddr_lat ddr_bw l3_cpu7" > $OUT
dumpsys SurfaceFlinger --timestats -enable >/dev/null
ps0=$(psi some); pf0=$(psi full); si0=$(vm pswpin); so0=$(vm pswpout); mf0=$(vm pgmajfault); k0=$(kt)
dumpsys SurfaceFlinger --timestats -clear >/dev/null
i=0
while [ $i -lt $N ] && [ -d /proc/$P ]; do
  sleep 5
  dumpsys SurfaceFlinger --timestats -dump > $TS
  dumpsys SurfaceFlinger --timestats -clear >/dev/null
  fl=$(awk '/layerName = .*SurfaceView\[com.tencent.ig/{f=1} f&&/^totalFrames/{t=$3} f&&/present2present histogram/{getline; n=split($0,b," "); for(j=1;j<=n;j++){split(b[j],c,"="); ms=c[1]; sub("ms","",ms); if(ms+0>=100) l+=c[2]}; print t+0, l+0; exit}' $TS)
  ps=$(psi some); pf=$(psi full); si=$(vm pswpin); so=$(vm pswpout); mf=$(vm pgmajfault); k=$(kt)
  echo "$(date +%T) ${fl:-0 0} $(((ps-ps0)/1000)) $(((pf-pf0)/1000)) $((si-si0)) $((so-so0)) $((mf-mf0)) $((k-k0)) $(($(cat /sys/devices/system/cpu/cpu4/cpufreq/scaling_cur_freq)/1000)) $(($(cat /sys/devices/system/cpu/cpu7/cpufreq/scaling_cur_freq)/1000)) $(cat /sys/class/kgsl/kgsl-3d0/gpu_busy_percentage | tr -d ' %') $(cat $DL) $(cat $DB) $(($(cat $L3)/1000000))" >> $OUT
  ps0=$ps; pf0=$pf; si0=$si; so0=$so; mf0=$mf; k0=$k
  i=$((i+1))
done
rm -f $TS
