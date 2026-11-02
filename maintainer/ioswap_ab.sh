#!/bin/sh
# A/B test of the I/O scheduler and the zram setup (BUGS-TODO 46, 55). Live only: a reboot restores the ROM values.
#   ADB="adb -s 83836a90" sh maintainer/ioswap_ab.sh [order]      (default order "A B C C B A")
# Setups: A = cfq, zram 8 GB, swappiness 60 (ROM default); B = deadline, rest as A; C = deadline, zram 4 GB lz4,
# swappiness 100. Each run:
#   1. cold app starts: force-stop, drop caches, `am start -W` (TotalTime ms), 5 apps; once idle and once while a
#      2 GB fsync write runs in the background (reads under write load: the case an I/O scheduler changes);
#   2. mem_fill.sh (real-use memory pressure), then heavy_mix.sh without a clean start (gfxinfo row in heavy.csv).
# Results: ~/Documents/pipa/port-work/perf-ab/ioswap.csv (one row per run) and heavy.csv (label ioswap-<setup><n>).
# Screen on, unlocked, landscape, hands off. `svc power stayon usb` during the series, false at the end.
set -u
ADB=${ADB:-adb -s 83836a90}
HERE=$(cd "$(dirname "$0")" && pwd)
OUT=$HOME/Documents/pipa/port-work/perf-ab/ioswap.csv
ORDER=${1:-"A B C C B A"}
LAPPS=${LAPPS:-"com.android.settings com.coloros.gallery3d com.spotify.music com.google.android.youtube com.coloros.note"}
su_() { $ADB shell "su -c '$1'"; }

setup() {   # <A|B|C>
    case $1 in
        A) sched=cfq; zram=8589934592; swp=60 ;;
        B) sched=deadline; zram=8589934592; swp=60 ;;
        C) sched=deadline; zram=4294967296; swp=100 ;;
    esac
    su_ "for q in /sys/block/sd*/queue/scheduler; do echo $sched > \$q; done"
    if [ "$(su_ 'cat /sys/block/zram0/disksize' | tr -d '\r')" != "$zram" ]; then
        su_ "swapoff /dev/block/zram0 && echo 1 > /sys/block/zram0/reset && echo lz4 > /sys/block/zram0/comp_algorithm && \
echo $zram > /sys/block/zram0/disksize && mkswap /dev/block/zram0 >/dev/null && swapon -p 32758 /dev/block/zram0" \
            || { echo "zram resize failed"; exit 1; }
    fi
    su_ "echo $swp > /proc/sys/vm/swappiness"
    echo "setup $1: $(su_ 'cat /sys/block/sda/queue/scheduler' | tr -d '\r') zram=$(su_ 'cat /sys/block/zram0/disksize' | tr -d '\r') swappiness=$(su_ 'cat /proc/sys/vm/swappiness' | tr -d '\r')"
}

launch() {   # cold start of each app; prints the sum of TotalTime (ms)
    sum=0
    for p in $LAPPS; do
        act=$($ADB shell "cmd package resolve-activity --brief -c android.intent.category.LAUNCHER $p" | tail -1 | tr -d '\r')
        $ADB shell "am force-stop $p" >/dev/null 2>&1
        su_ "sync; echo 3 > /proc/sys/vm/drop_caches"
        sleep 1
        t=$($ADB shell "am start -W -n $act" 2>/dev/null | sed -n 's/^TotalTime: \([0-9]*\).*/\1/p' | tr -d '\r')
        sum=$((sum + ${t:-0}))
        $ADB shell "input keyevent 3" >/dev/null; sleep 1.5
    done
    echo "$sum"
}

[ -f "$OUT" ] || echo "time,label,sched,zram,swappiness,launch_idle_ms,launch_write_ms,psi_some_avg300" > "$OUT"
$ADB shell "svc power stayon usb"
n_A=0; n_B=0; n_C=0
for s in $ORDER; do
    eval "n=\$((n_$s + 1)); n_$s=\$n"
    label=ioswap-$s$n
    echo "== $label"
    setup "$s"
    idle=$(launch)
    su_ "dd if=/dev/zero of=/data/local/tmp/ioswap_dd bs=1M count=2000 conv=fsync >/dev/null 2>&1 &"
    sleep 2
    write=$(launch)
    su_ "while pgrep -x dd >/dev/null; do sleep 1; done; rm -f /data/local/tmp/ioswap_dd"
    ADB="$ADB" sh "$HERE/mem_fill.sh" >/dev/null 2>&1
    NOCLEAN=1 ADB="$ADB" sh "$HERE/heavy_mix.sh" "$label" 10 | tail -3
    psi=$(su_ 'cat /proc/pressure/memory' | sed -n 's/^some.*avg300=\([0-9.]*\).*/\1/p' | tr -d '\r')
    echo "$(date +%F_%T),$label,$sched,$zram,$swp,$idle,$write,$psi" | tee -a "$OUT"
done
$ADB shell "svc power stayon false"
setup A
echo "done; ROM defaults set again (setup A)"
