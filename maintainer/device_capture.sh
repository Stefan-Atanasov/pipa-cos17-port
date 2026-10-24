#!/bin/sh
# Collect the device data that STABILITY-PERF.md §4 asks for (D1–D17) in one go.
#
#   sh device_capture.sh [label] [--unhide-avc]
#   ADB="adb -s 83836a90" sh device_capture.sh beta5     (USB instead of the default TCP serial)
#
# Read-only by default: it pushes one script to /data/local/tmp, runs it as root, pulls the result
# and deletes both from the tablet. Output: ~/Documents/pipa/port-work/device-captures/<date>-<label>/
#
# --unhide-avc is the one exception. pipa_core enables susfs AVC-log spoofing at boot, which hides
# SELinux denials. This flag turns it off for the running boot only
# (`ksud susfs enable-avc-log-spoofing 0`); pipa_core turns it back on at the next boot. Use it,
# then use the tablet normally for 10-15 min (face unlock, pen, AOD, keyboard, sharing), then run the
# script again without the flag to capture the denials.
set -eu
ADB=${ADB:-adb -s 192.168.0.37:5555}
LABEL=run; UNHIDE=0
for a in "$@"; do case $a in --unhide-avc) UNHIDE=1 ;; *) LABEL=$a ;; esac; done
OUT=~/Documents/pipa/port-work/device-captures/$(date +%Y%m%d-%H%M)-$LABEL
$ADB get-state >/dev/null || { echo "no device on: $ADB"; exit 1; }

if [ "$UNHIDE" = 1 ]; then
    $ADB shell "su -c '/data/adb/ksud susfs enable-avc-log-spoofing 0'" && \
        echo "AVC spoofing off until the next reboot. Use the tablet for 10-15 min, then run: sh $0 $LABEL"
    exit 0
fi

mkdir -p "$OUT"
DEV=$(mktemp); trap 'rm -f "$DEV"' EXIT
cat > "$DEV" <<'DEVICE'
#!/system/bin/sh
O=/data/local/tmp/pipa_capture
rm -rf $O; mkdir -p $O; cd $O
sec() { echo; echo "######## $*"; }
run() { sec "$*"; sh -c "$*" 2>&1; }

{
run getenforce
run 'dmesg | grep -E "avc: +denied" | sed -E "s/.*avc: +denied +//; s/ pid=[0-9]+//; s/ ino=[0-9]+//" | sort | uniq -c | sort -rn | head -150'
run 'logcat -b all -d | grep -E "avc: +denied" | sed -E "s/.*avc: +denied +//; s/ pid=[0-9]+//; s/ ino=[0-9]+//" | sort | uniq -c | sort -rn | head -150'
} > D01-02-selinux.txt
run 'ps -AZ | grep -E "oplus|performance|facehal|subsys|qseecomd|keystore|vold|xiaomi|charger|app_process"' > D03-domains.txt
{
run 'dmesg | grep -E "init: .*(Could not|failed|exited|restarting|Unable)" | head -150'
run 'getprop | grep -E "init.svc\." | grep -v running'
} > D04-services.txt
{
run 'logcat -b crash -d | head -300'
run 'ls -lt /data/tombstones | head -20'
run 'ls -lt /data/system/dropbox | head -40'
} > D05-crashes.txt
{
run 'logcat -d | grep -i -E "vircomm|imsradio|subsys_radio|waiting for service" | sed -E "s/^[0-9-]+ [0-9:.]+ +[0-9]+ +[0-9]+ //" | sort | uniq -c | sort -rn | head -30'
run 'service list | grep -i -E "subsys|IFace|charger|power|perf"'
} > D06-hals.txt
run 'cat /proc/sys/kernel/hung_task_panic /proc/sys/kernel/softlockup_panic /proc/sys/kernel/panic; ls /metadata/port /metadata/bootcap /metadata/portdiag 2>&1 | head; df -h /metadata; pgrep -af "logcat.*metadata"' > D07-debug-leftovers.txt
{
run 'dumpsys android.hardware.thermal.IThermal/default | head -120'
run 'dumpsys thermalservice | head -80'
run 'for z in /sys/class/thermal/thermal_zone*; do echo "$(cat $z/type) $(cat $z/temp)"; done'
run 'cat /sys/class/thermal/thermal_message/sconfig'
run 'ls -l /vendor/etc/thermal-*.conf'
} > D08-thermal.txt
vm() {
    cat /proc/sys/vm/swappiness /proc/sys/vm/watermark_scale_factor /proc/sys/vm/watermark_boost_factor /proc/sys/vm/min_free_kbytes /proc/sys/vm/page-cluster 2>&1 | tr '\n' ' '; echo
    cat /proc/swaps; cat /sys/block/zram0/disksize /sys/block/zram0/comp_algorithm /sys/block/zram0/mm_stat 2>&1
    cat /proc/pressure/memory /proc/pressure/io /proc/pressure/cpu
    grep -E 'pgscan_direct|allocstall|pgsteal_kswapd|workingset_refault|compact_stall' /proc/vmstat
    grep -E 'MemTotal|MemFree|MemAvailable|Cached|SwapTotal|SwapFree' /proc/meminfo
}
{ sec "vm sample 1"; vm; sleep 60; sec "vm sample 2 (+60 s)"; vm; } > D09-memory.txt 2>&1 &
VMPID=$!
run 'for d in /sys/block/sda /sys/block/sdb /sys/block/dm-*; do [ -d $d/queue ] && echo "$d $(cat $d/queue/scheduler) nr=$(cat $d/queue/nr_requests) ra=$(cat $d/queue/read_ahead_kb)"; done' > D10-io.txt
{
run 'getprop | grep -i -E "perf-hal|vendor\.perf|powerhal|power\."'
run 'logcat -d | grep -i -E "perf-hal|PerfService|libqti-perfd|libperfmgr|PowerHAL|perfd" | tail -60'
run 'dumpsys android.hardware.power.IPower/default | head -80'
} > D11-perfhal.txt
{
run 'ls /dev/cpuctl/ /dev/cpuctl/top-app/ 2>&1 | head -40'
run 'for g in top-app foreground background system-background; do echo "$g min=$(cat /dev/cpuctl/$g/cpu.uclamp.min 2>&1) max=$(cat /dev/cpuctl/$g/cpu.uclamp.max 2>&1)"; done'
run 'ls /dev/stune 2>&1 | head -3'
run 'for p in 0 4 7; do d=/sys/devices/system/cpu/cpufreq/policy$p; echo "policy$p $(cat $d/scaling_governor) min=$(cat $d/scaling_min_freq) max=$(cat $d/scaling_max_freq) cur=$(cat $d/scaling_cur_freq)"; ls $d/$(cat $d/scaling_governor)/ 2>/dev/null | tr "\n" " "; echo; for f in $d/$(cat $d/scaling_governor)/*; do echo "  $(basename $f)=$(cat $f 2>/dev/null)"; done; done'
run 'ls /proc/sys/walt 2>&1 | head -40; ls /proc/sys/kernel | grep -i -E "sched|walt" | head -40'
run 'for c in top-app foreground background system-background restricted; do echo "$c $(cat /dev/cpuset/$c/cpus 2>&1)"; done'
run 'cat /sys/devices/system/cpu/cpu*/core_ctl/min_cpus 2>/dev/null; zcat /proc/config.gz 2>/dev/null | grep -E "UCLAMP|SCHED_WALT|SCHED_TUNE|ZRAM|PSI|LRU_GEN" '
} > D12-sched.txt
{
run 'dumpsys display | grep -E "mActiveModeId|DisplayModeRecord|renderFrameRate|mPeakRefreshRate|mMinRefreshRate|minimalPostProcessing" | head -30'
run 'settings get system peak_refresh_rate; settings get system min_refresh_rate; settings list system | grep -i -E "refresh|frame_rate|fps"'
run 'dumpsys SurfaceFlinger | grep -i -E "refresh|vsync|active mode|frame rate|HWC" | head -40'
} > D13-refresh.txt
{
run 'logcat -d | grep -i -E "kgsl|adreno|vulkan|gpu hang|GPU_FAULT|skia" | sed -E "s/^[0-9-]+ [0-9:.]+ +[0-9]+ +[0-9]+ //" | sort | uniq -c | sort -rn | head -40'
run 'dmesg | grep -i -E "kgsl|a6xx|adreno|gpu" | tail -40'
run 'getprop | grep -E "hwui|renderer|debug.sf|ro.surface_flinger"'
run 'dumpsys gfxinfo com.android.launcher | head -40; dumpsys gfxinfo com.android.systemui | head -40'
} > D14-gpu.txt
{
run 'getprop ro.secure; getprop ro.adb.secure; getprop ro.debuggable; getprop ro.build.tablet_type; getprop persist.sys.facehal.verbose; getprop ro.vendor.perf-hal.ver'
run 'getprop | grep -E "dalvik.vm|ro.build.(display.id|version.ota|fingerprint)|ro.product.(device|model)"'
} > D15-props.txt
{
run 'logcat -d | awk "{print \$6}" | sort | uniq -c | sort -rn | head -40'
run 'dumpsys batterystats --charged | grep -E "Wake lock|Kernel Wake|Estimated power|Screen off discharge" | head -60'
run 'cat /sys/kernel/debug/wakeup_sources 2>/dev/null | sort -k6 -rn | head -25'
} > D16-idle.txt
{
run 'dmesg | grep -i -E "selinux|SELinux: (policy|Loading)|secilc|Compiling" | head -40'
run 'logcat -b all -d | grep -E "init: .*(Loading SELinux|selinux_|Compil)" | head -20'
run 'for p in ro.boottime.init ro.boottime.init.selinux ro.boottime.init.first_stage ro.boottime.zygote ro.boottime.system_server ro.boottime.bootanim; do echo "$p=$(getprop $p)"; done; echo "uptime=$(cut -d" " -f1 /proc/uptime)"; logcat -b events -d | grep -E "boot_progress|sf_stop_bootanim" | head -30'
} > D17-boot.txt
wait $VMPID
logcat -b all -d > logcat-all.txt 2>&1
dmesg > dmesg.txt 2>&1
cd /data/local/tmp && tar czf pipa_capture.tgz pipa_capture && rm -rf $O
DEVICE

$ADB push "$DEV" /data/local/tmp/pipa_capture.sh >/dev/null
echo "capturing (about 70 s, D09 samples memory twice 60 s apart)..."
$ADB shell "su -c 'sh /data/local/tmp/pipa_capture.sh; rm -f /data/local/tmp/pipa_capture.sh; chmod 644 /data/local/tmp/pipa_capture.tgz'"
$ADB pull /data/local/tmp/pipa_capture.tgz "$OUT/" >/dev/null
$ADB shell "su -c 'rm -f /data/local/tmp/pipa_capture.tgz'"
tar xzf "$OUT/pipa_capture.tgz" -C "$OUT" --strip-components=1 && rm "$OUT/pipa_capture.tgz"
ls -l "$OUT"
echo "saved to $OUT"
