#!/bin/sh
# Repeatable memory-pressure test for BUGS 89 / 99 (game stutter and audio cuts below ~1 GB free).
#
#   sh maintainer/mem_load.sh [label]        default label: run
#   TARGET_MB=900 HOLD=60 sh maintainer/mem_load.sh pt93-base
#
# Start the game first (PUBG lobby: 3D + music), screen on. The script fills RAM with incompressible tmpfs data
# until MemAvailable < TARGET_MB, holds it for HOLD s (tops up every 5 s), samples once per second, then frees it.
# Per second: MemAvailable, SwapFree, PSI memory some/full avg10, frames composed (SurfaceFlinger flip count),
# direct reclaim (allocstall, pgsteal_direct). Before/after: audio_flinger underrun lines.
# Live only: nothing persistent. The tmpfs is unmounted at the end (also on error/interrupt). lmkd may kill
# background apps while RAM is full. Report: <PIPA_ROOT>/port-work/mem-checks/<date>-load-<label>.txt
set -eu
ADB=${ADB:-adb -s 83836a90}
LABEL=${1:-run}
case $LABEL in */* | .*) echo "bad label: $LABEL"; exit 2 ;; esac
TARGET_MB=${TARGET_MB:-900}
HOLD=${HOLD:-60}
HOG=${HOG:-mix}     # mix = 1/3 random + 2/3 text per chunk (about 3:1, like app memory); rand = incompressible
CHURN=${CHURN:-0}   # 1 = each second free the oldest 128 MB chunk and write a new one (allocation churn, like a match)
PIPA_ROOT=${PIPA_ROOT:-$HOME/Documents/pipa}
OUT=$PIPA_ROOT/port-work/mem-checks
mkdir -p "$OUT"
REPORT=$OUT/$(date +%Y%m%d-%H%M%S)-load-$LABEL.txt

$ADB shell "su -c 'TARGET_MB=$TARGET_MB HOLD=$HOLD CHURN=$CHURN HOG=$HOG sh'" > "$REPORT.raw" 2>&1 <<'TABLET' || echo "tablet script exit $?" >> "$REPORT.raw"
H=/data/local/tmp/pipa_hog
mi() { awk -v k="$1:" '$1==k{print int($2/1024)}' /proc/meminfo; }
vs() { awk -v k="$1" '$1==k{print $2}' /proc/vmstat; }
psi() { awk -v w="$1" '$1==w{split($2,a,"="); print a[2]}' /proc/pressure/memory; }
G=$(dumpsys activity activities | grep -m1 topResumedActivity | grep -o "u0 [^/ ]*" | cut -c4-)
ts() { dumpsys SurfaceFlinger --timestats -dump | grep -A40 "layerName = .*SurfaceView\[$G" ; }
flips() { ts | awk '/totalFrames/{print $3; exit}'; }
afu() { dumpsys media.audio_flinger 2>/dev/null | grep -i -E 'underrun|UndFrmCnt|delayed writes|Output thread|^ +[0-9]+ +(yes|no) ' ; }
cleanup() { umount $H 2>/dev/null; rmdir $H 2>/dev/null; }
trap cleanup EXIT INT TERM
echo "==== start $(date +%T) target=${TARGET_MB}MB hog=$HOG churn=$CHURN hold=${HOLD}s fg=$(dumpsys activity activities | grep -m1 topResumedActivity | awk '{print $3}')"
echo "==== audio before"; afu
a0=$(( $(vs allocstall_normal) + $(vs allocstall_movable) )); d0=$(vs pgsteal_direct)
mkdir -p $H && mount -t tmpfs -o size=8g tmpfs $H
n=0
chunk() { if [ "$HOG" = rand ]; then head -c 134217728 /dev/urandom; else
  head -c 44739242 /dev/urandom; yes "pipa ram test $n 0123456789 abcdefghijklmnopqrstuvwxyz ABCDEFGHIJKLMNOPQRSTUVWXYZ" | head -c 89478486; fi; }
fill() { while [ "$(mi MemAvailable)" -gt "$TARGET_MB" ] && [ $n -lt 60 ]; do
  n=$((n+1)); chunk > $H/c$n; done; }
t=$(date +%s); fill; echo "==== filled $((n*128)) MB in $(( $(date +%s) - t )) s"
echo "t avail_mb swapfree_mb psi_some10 psi_full10 frames allocstall pgsteal_direct"
dumpsys SurfaceFlinger --timestats -enable -clear >/dev/null; sleep 1
f0=$(flips); f0=${f0:-0}; i=0
while [ $i -lt "$HOLD" ]; do
  [ "$CHURN" = 1 ] && { o=$(ls $H | head -1); rm -f $H/$o; n=$((n+1)); chunk > $H/c$(date +%s%N); }
  sleep 1; i=$((i+1)); f1=$(flips); f1=${f1:-0}
  a=$(( $(vs allocstall_normal) + $(vs allocstall_movable) ))
  echo "$i $(mi MemAvailable) $(mi SwapFree) $(psi some) $(psi full) $((f1-f0)) $((a-a0)) $(( $(vs pgsteal_direct) - d0 ))"
  f0=$f1; [ $((i % 5)) -eq 0 ] && fill
done
echo "==== hog $((n*128)) MB at end"
echo "==== game layer timestats"; ts | grep -E "totalFrames|droppedFrames|[jJ]ank|present2present" | head -20
dumpsys SurfaceFlinger --timestats -disable >/dev/null
echo "==== audio after"; afu
echo "==== lmkd kills"; logcat -d -b all -t 2000 | grep -E 'lowmemorykiller.*[Kk]ill|lmkd.*kill' | tail -20
echo "==== end $(date +%T)"
TABLET

# summary on the host
awk '
/^t avail_mb/ {s=1; next} /^==== hog/ {s=0}
s && NF==8 {n++; fr[n]=$6; if(min==""||$2<min)min=$2; if($4>ps)ps=$4; if($5>pf)pf=$5; as=$7; pd=$8}
END {
  if(!n){print "no samples"; exit}
  for(i=1;i<=n;i++){t+=fr[i]; c[i]=fr[i]} m=t/n
  for(i=1;i<=n;i++) if(fr[i]<0.8*m) low++
  printf "SUMMARY samples=%d fps_avg=%.1f seconds_below_80pct=%d min_avail_mb=%d psi_some_max=%.2f psi_full_max=%.2f allocstall=%d pgsteal_direct=%d\n", n, m, low, min, ps, pf, as, pd
}' "$REPORT.raw" > "$REPORT"
cat "$REPORT.raw" >> "$REPORT" && rm "$REPORT.raw"
echo "report: $REPORT"; head -1 "$REPORT"
