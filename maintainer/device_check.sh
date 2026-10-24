#!/bin/sh
# Regression checklist for a pipa COS17 build (notes/PORT-MAINTAINER.md §8), run over ADB.
#
#   sh device_check.sh [label]        e.g.  sh device_check.sh beta5-first-boot
#   ADB="adb -s 83836a90" sh device_check.sh    (USB instead of the default TCP serial)
#
# Read-only: it pushes one script to /data/local/tmp, runs it as root and deletes it. Nothing is
# started, stopped, set or enabled on the tablet. The report is saved under
# ~/Documents/pipa/port-work/device-checks/<date>-<label>.txt so runs can be diffed.
set -eu
ADB=${ADB:-adb -s 192.168.0.37:5555}
LABEL=${1:-run}
OUT=~/Documents/pipa/port-work/device-checks
mkdir -p "$OUT"
REPORT="$OUT/$(date +%Y%m%d-%H%M)-$LABEL.txt"

$ADB get-state >/dev/null || { echo "no device on: $ADB"; exit 1; }

DEV=$(mktemp)
trap 'rm -f "$DEV"' EXIT
cat > "$DEV" <<'DEVICE'
#!/system/bin/sh
pass() { echo "PASS  $1${2:+  ($2)}"; }
fail() { echo "FAIL  $1${2:+  ($2)}"; }
info() { echo "INFO  $1${2:+  ($2)}"; }
chk()  { if [ "$2" = 0 ]; then pass "$1" "$3"; else fail "$1" "$3"; fi; }

echo "== build"
info "display id"   "$(getprop ro.build.display.id)"
info "oplus ver"    "$(getprop ro.build.version.ota)"
info "device"       "$(getprop ro.product.device)"
info "uptime"       "$(cut -d' ' -f1 /proc/uptime)s"
info "boot reason"  "$(getprop sys.boot.reason)"

echo "== security"
e=$(getenforce); [ "$e" = Enforcing ]; chk "SELinux enforcing" $? "$e"
s=$(getprop ro.adb.secure); d=$(getprop ro.debuggable)
info "ro.adb.secure/ro.secure/ro.debuggable" "$s/$(getprop ro.secure)/$d (beta5 expects 1/1/0; empty = deleted, U17)"
n=$(logcat -d -b all 2>/dev/null | grep -c 'avc: *denied'); info "AVC denials in logcat buffer" "$n"

echo "== HALs / pipa_core"
sl=$(service list 2>/dev/null)
echo "$sl" | grep -qi 'ISubsys/default';     chk "ISubsys/default registered" $?
echo "$sl" | grep -qi 'ISubsysRadio/slot1';  chk "ISubsysRadio/slot1 registered" $?
echo "$sl" | grep -q 'biometrics.face.IFace/default'; chk "face HAL IFace/default registered" $?
# last 60 s only: the framework retries ~15 times at boot until pipa_core starts the HAL, which is fine
n=$(logcat -d -v epoch 2>/dev/null | grep 'ctl.interface_start.*IFace' | awk -v t=$(($(date +%s) - 60)) '$1 > t' | wc -l); [ "$n" -lt 5 ]; chk "no 1 Hz IFace interface_start spam (R2)" $? "$n lines in the last 60 s"
[ -d /data/adb/modules/pipa_core ] && [ ! -f /data/adb/modules/pipa_core/disable ]; chk "pipa_core installed and enabled" $? "$(grep ^version= /data/adb/modules/pipa_core/module.prop 2>/dev/null)"
# beta5-2a removes AOD (aod_support commented out); pipa_core 1.11 then does not start the daemon
if grep -qE '^[[:space:]]*<oplus-feature name="oplus.software.display.aod_support"' \
        /my_product/etc/permissions/oplus.product.display_features.xml 2>/dev/null; then
    pgrep -f AodBacklightDaemon >/dev/null; chk "AodBacklightDaemon running (pipa_core)" $?
else
    ! pgrep -f AodBacklightDaemon >/dev/null; chk "no AodBacklightDaemon (ROM without AOD, A9)" $?
fi

echo "== power tune module"
M=/data/adb/modules/pipa_cos17_power_tune
[ -d $M ] && [ ! -f $M/disable ]; chk "power tune installed and enabled" $? "$(grep ^version= $M/module.prop 2>/dev/null)"
pgrep -f 'pipa_cos17_power_tune/service.sh' >/dev/null || [ -f /data/local/tmp/pipa_power_tune.pid ]; chk "runtime guard running" $?
kb=$(grep -l -E 'Xiaomi (Keyboard|Consumer Control|Touchpad)' /sys/class/input/input*/name 2>/dev/null | wc -l)
st=$(getprop init.svc.xiaomi-keyboard)
if [ "$kb" = 0 ]; then [ "$st" != running ]; chk "xiaomi-keyboard stopped without keyboard (R1/M1)" $? "$st"
else [ "$st" = running ]; chk "xiaomi-keyboard running with keyboard attached" $? "$st"; fi
aod=$(settings get secure Setting_AodSwitchEnable 2>/dev/null)
for p in $(pgrep -f AodBacklightDaemon); do
    stt=$(awk '{print $3}' /proc/$p/stat)
    info "AOD daemon pid $p state $stt" "AOD switch=$aod (expect T while AOD off)"
done
# every file the module bind-mounts must match the module copy (binds are hidden from mountinfo)
for part in vendor system_ext; do
    for base in $M/$part $M/system/$part; do
        [ -d "$base" ] && [ ! -L "$base" ] || continue
        for f in $(cd "$base" && find . -type f); do
            f=${f#./}; cmp -s "$base/$f" "/$part/$f"; chk "bind /$part/$f" $?
        done
    done
done
j=$(md5sum /system/framework/oplus-services.jar | cut -c1-32)
case $j in
    00b9218b14719af039a7c8f5e34efe5d) pass "framework jar patched (beta4, module v0.10)" ;;
    8810ad003920900595276db5c9d05e5a) pass "framework jar patched (C.06, module v0.10 or beta5-baked)" ;;
    06c5c30317965509952881d9e712027f) pass "framework jar patched (beta4, module v0.9: no IEngineer fix)" ;;
    8c211ca5ba320bee8161ee62b1897921) pass "framework jar patched (C.06, module v0.9: no IEngineer fix)" ;;
    7afeadb12583df3b1fdd92490e2e76cc) fail "framework jar patched" "plain beta5 jar (IEngineer fix only): CCT reroute not bound" ;;
    *) fail "framework jar patched" "md5 $j" ;;
esac
grep 'framework jar' /data/local/tmp/pipa_power_tune.log 2>/dev/null | tail -2 | while read -r l; do info "log" "$l"; done
[ -e /system/framework/oat/arm64/oplus-services.odex ]; [ $? != 0 ]; chk "no prebuilt oplus-services.odex" $?
c=$(dumpsys color_display 2>/dev/null | grep -m1 -o 'sensorCCT[^,]*'); info "adaptive colour input" "${c:-no sensorCCT line}"
info "colour mode" "$(settings get system color_mode 2>/dev/null) / display_color_mode $(settings get system display_color_mode 2>/dev/null)"
info "brightness min" "$(dumpsys display 2>/dev/null | grep -m1 -o 'mScreenBrightnessRangeMinimum=[0-9.]*')"

echo "== memory"
grep -q zram0 /proc/swaps; chk "zram0 active" $?
# nandswap is a swapfile on a loop device, so /proc/swaps lists /dev/block/loopN, not the file
grep -qE 'nandswap|/loop[0-9]+ ' /proc/swaps; chk "nandswap swapfile active" $?
sed 's/^/      /' /proc/swaps

echo "== OTA"
if [ -d /data/ota_package/OTA ]; then pass "/data/ota_package/OTA exists (R11)"
else st=$(pm list packages -d 2>/dev/null | grep -c com.oplus.ota); [ "$st" -gt 0 ]; chk "/data/ota_package/OTA exists or com.oplus.ota disabled (R11)" $?; fi

echo "== crashes since boot"
n=$(logcat -d -b crash 2>/dev/null | grep -c 'FATAL EXCEPTION\|Fatal signal'); info "crash buffer entries" "$n"
logcat -d -b crash 2>/dev/null | grep -E 'Process: |Fatal signal' | sort | uniq -c | sort -rn | head -8 | sed 's/^/      /'

echo "== battery (for the 30-min screen-off drain check)"
info "level/current" "$(cat /sys/class/power_supply/battery/capacity 2>/dev/null)% / $(cat /sys/class/power_supply/battery/current_now 2>/dev/null) uA"
DEVICE

$ADB push "$DEV" /data/local/tmp/pipa_device_check.sh >/dev/null
$ADB shell "su -c 'sh /data/local/tmp/pipa_device_check.sh; rm -f /data/local/tmp/pipa_device_check.sh'" | tr -d '\r' | tee "$REPORT"
echo
echo "summary: $(grep -c '^PASS' "$REPORT") pass, $(grep -c '^FAIL' "$REPORT") fail -> $REPORT"
