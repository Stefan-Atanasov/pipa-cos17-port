#!/bin/sh
# RAM state snapshot for BUGS 89 / 99 (notes/RAM-RESEARCH-20261112.md), run over ADB.
#
#   sh mem_check.sh [label]                 one snapshot (about 5 s)
#   SAMPLE=60 sh mem_check.sh game          + 60 one-second /proc/vmstat and PSI samples (run during a game)
#   ADB="adb -s <serial>" sh mem_check.sh   other device (default: the maintainer tablet over TCP)
#
# Read-only: nothing is set, started or stopped on the tablet. Needs root (su). The report goes to
# <PIPA_ROOT>/port-work/mem-checks/<date>-<label>.txt. Sections: what the ROM asked for vs what the kernel runs
# (VM values are overwritten by vendor scripts: compare with odm/etc/init.oplus.mm-sys.sh), which OPPO memory
# features have kernel nodes (most should be missing on walt-r20), swap layout, memory and PSI, lmkd mode, the
# processes that matter for the audio cuts, and recent memory-manager log lines.
set -eu
ADB=${ADB:-adb -s 192.168.0.37:5555}
LABEL=${1:-run}
case $LABEL in */* | .*) echo "bad label: $LABEL"; exit 2 ;; esac
SAMPLE=${SAMPLE:-0}
PIPA_ROOT=${PIPA_ROOT:-$HOME/Documents/pipa}
OUT=$PIPA_ROOT/port-work/mem-checks
mkdir -p "$OUT"
REPORT=$OUT/$(date +%Y%m%d-%H%M%S)-$LABEL.txt

$ADB shell "su -c 'SAMPLE=$SAMPLE sh'" > "$REPORT" 2>&1 <<'TABLET'
h() { printf '\n==== %s\n' "$*"; }
v() { for f in "$@"; do printf '%-48s %s\n' "$f" "$(cat "$f" 2>/dev/null | tr '\n' ' ' || echo '-')"; done; }
has() { if [ -e "$1" ]; then echo "present  $1"; else echo "MISSING  $1"; fi; }

h build
getprop ro.build.display.id; getprop ro.pipa.port.layer; uname -r; cat /proc/uptime

h "vm settings (kernel now)"
v /proc/sys/vm/swappiness /proc/sys/vm/page-cluster /proc/sys/vm/watermark_scale_factor \
  /proc/sys/vm/min_free_kbytes /proc/sys/vm/extra_free_kbytes /proc/sys/vm/compaction_proactiveness \
  /proc/sys/vm/vfs_cache_pressure /proc/sys/vm/dirty_ratio /proc/sys/vm/dirty_background_ratio \
  /sys/kernel/mm/transparent_hugepage/enabled

h swap layout
cat /proc/swaps
v /sys/block/zram0/disksize /sys/block/zram0/comp_algorithm /sys/block/zram0/max_comp_streams \
  /sys/block/zram0/backing_dev /sys/block/zram0/mm_stat /sys/block/zram0/bd_stat
losetup -a 2>/dev/null; ls -l /data/nandswap 2>/dev/null
getprop | grep -iE "nandswap|hybridswap|zram|swap" | head -20

h OPPO memory features: kernel nodes
for p in /sys/block/zram0/hybridswap_enable /sys/block/zram0/hybridswap_swapd_pause /proc/nandswap/fn_enable \
         /proc/oplus_mem/swappiness_para /proc/oplus_mem/dynamic_swappiness /proc/oplus_mem/fragmentation_index \
         /proc/osvelte /sys/kernel/oplus_mm /proc/sys/vm/direct_swappiness /proc/oplus_healthinfo \
         /dev/memcg /dev/memcg/memory.zram_used_limit_mb /dev/memcg/apps /sys/fs/cgroup/apps \
         /sys/fs/cgroup/memory.zram_used_limit_mb /dev/cpuset/kswapd-like /proc/pressure/memory; do has "$p"; done
mount | grep -E "cgroup|memcg"
ls /dev/memcg 2>/dev/null | head -30

h memory
head -25 /proc/meminfo
h PSI
for r in memory io cpu; do echo "$r:"; cat /proc/pressure/$r; done
h zones
grep -E "^Node|pages free|  min |  low |  high " /proc/zoneinfo | head -40
h vmstat
grep -E "^(allocstall|pgscan|pgsteal|pswp|pgmajfault|workingset_refault|compact_|kswapd|oom_kill|pgskip)" /proc/vmstat

h lmkd
getprop | grep -E "ro\.lmk\.|lmkd|persist\.device_config\.lmkd" | head -40
logcat -d -b all 2>/dev/null | grep -iE "lowmemorykiller|lmkd" | tail -20

h kswapd and key processes
for n in kswapd0 audioserver android.hardware.audio.service vendor.audio-hal surfaceflinger; do
    for p in $(pidof $n 2>/dev/null); do
        printf '%s pid %s cpus %s\n' "$n" "$p" "$(grep Cpus_allowed_list /proc/$p/status | cut -f2)"
        grep -E "VmRSS|VmSwap|VmLck" /proc/$p/status; cat /proc/$p/cgroup 2>/dev/null | head -5
    done
done
cat /proc/loadavg

h "memory manager logs (last lines)"
logcat -d -b all 2>/dev/null | grep -E "OsenseMemory|SwappinessHelper|hybridswap|DynamicZram|nandswap|init_oplus_mm|CriticalMemory|OplusHans|ActivityManager: Kill" | tail -40

h app compaction
device_config get activity_manager use_compaction 2>/dev/null
dumpsys activity settings 2>/dev/null | grep -iE "compact" | head -10

if [ "${SAMPLE:-0}" -gt 0 ]; then
    h "samples: 1 s deltas of vmstat + PSI memory total (us), $SAMPLE s"
    keys="allocstall_normal allocstall_movable pgscan_direct pgscan_kswapd pswpin pswpout pgmajfault workingset_refault_anon workingset_refault_file compact_stall"
    snap() { for k in $keys; do grep "^$k " /proc/vmstat | cut -d' ' -f2; done | tr '\n' ' '; sed -n 's/^some.*total=//p' /proc/pressure/memory; }
    echo "t $keys psi_mem_some_total_us"
    prev=$(snap); i=0
    while [ $i -lt "$SAMPLE" ]; do
        sleep 1; cur=$(snap); i=$((i + 1))
        echo "$prev|$cur" | awk -v t=$i -F'|' '{n=split($1,a," "); split($2,b," "); s=t; for(j=1;j<=n;j++) s=s" "(b[j]-a[j]); print s}'
        prev=$cur
    done
    grep -E "MemAvailable|SwapFree" /proc/meminfo
fi
echo; echo "== end"
TABLET

grep -q '^== end' "$REPORT" || { echo "check did not finish: $REPORT"; exit 1; }
echo "report: $REPORT"
grep -E "^MISSING|^present" "$REPORT" | sed 's/^/  /'
