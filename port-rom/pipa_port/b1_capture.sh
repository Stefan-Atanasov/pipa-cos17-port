#!/system/bin/sh
# 8p (BUGS B1): one Wi-Fi failure snapshot per trigger, rate limited (10 min). Started only by init property triggers
# (pipa_port.rc: ColorOS cold reset / framework stuck, Wi-Fi HAL or wificond restart, sys.pipa.b1capture). Rules: maintainer/sepolicy/rules_8p_system_ext.cil.
# Output: /data/misc/pipa_port/b1-<time>.txt (newest 5 kept). No cmd/settings/dumpsys (binder tools: fd gotcha).
D=/data/misc/pipa_port
LOG=/data/local/tmp/pipa_port.log
STAMP=$D/b1.stamp
MIN_GAP=600
now=$(date +%s)   # wall clock: an uptime value from the last boot blocked captures after a reboot
last=0; [ -r "$STAMP" ] && read -r last < "$STAMP"
# a clock set back (last > now) counts as old
[ "$last" -gt "$now" ] 2>/dev/null && last=0
[ "$last" -gt 0 ] && [ $((now - last)) -lt $MIN_GAP ] && exit 0
echo "$now" > "$STAMP"
sleep 3   # let the failing start finish logging (oneshot service, one sleep, not a poll)
f=$D/b1-$(date +%Y%m%d-%H%M%S).txt
{
    echo "== uptime $(cut -d. -f1 /proc/uptime)s  wlan0: $([ -e /sys/class/net/wlan0 ] && echo present || echo ABSENT)  nets: $(for n in /sys/class/net/*; do printf "%s " "${n##*/}"; done)"
    for p in init.svc.vendor.wifi_hal_legacy init.svc.wificond init.svc.wpa_supplicant init.svc.cnss-daemon \
             sys.oplus.wifi.coldreset sys.oplus.wifi.trace sys.oplus.wifi.reloaddriver wifi.interface \
             vendor.oplus.wifi.switch.bdfLoadSuccess vendor.oplus.wifi.switch.regdbLoadSuccess; do
        echo "$p=$(getprop $p)"
    done
    echo "== dmesg (cnss|wlan|qmi|wlfw|hif|timeout|mhi|pci|assert|recovery|fw)"
    dmesg 2>&1 | grep -iE 'cnss|wlan|qca6390|qmi|wlfw|hif|mhi|pcie|timeout|assert|recovery|firmware|bdf|wifi' | tail -n 400
    echo "== logcat -b all (wifi slice)"
    logcat -d -b all -v threadtime -t 15000 </dev/null 2>&1 | \
        grep -iE 'wifi|wlan|cnss|wificond|supplicant|WifiHal|WifiNative|ActiveModeWarden|ClientModeImpl|OplusWifi|avc: +denied' | tail -n 1500
} > "$f" 2>&1
chmod 0660 "$f"
ls -t "$D"/b1-*.txt | tail -n +6 | while read -r o; do rm -f "$o"; done
echo "$(date '+%Y-%m-%d %H:%M:%S') b1 capture -> $f" >> "$LOG"
# 8q: the helper shows "Wi-Fi problem logged" (observer on this key)
settings put global pipa_b1_last "$(date +%s)" </dev/null >/dev/null 2>&1
