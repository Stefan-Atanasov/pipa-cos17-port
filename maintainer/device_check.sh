#!/bin/sh
# Regression checklist for the pipa COS17 ROM (port.sh builds, pipa_port runtime), run over ADB.
#
#   sh device_check.sh [tag]          e.g.  sh device_check.sh pt3
#   ADB="adb -s 83836a90" sh device_check.sh pt3    (USB instead of the default TCP serial)
#   PIPA_ROOT=<dir> overrides ~/Documents/pipa
#
# The tag names the report file and, when port-work/<tag>/report/{system,system_ext,product,vendor}.tsv
# exist (tree manifests of the build), also the expected build: the md5 of key files on the tablet is
# compared with the manifest. Without a tag the build-identity compare is skipped.
#
# Read-only: the check script goes to the tablet over stdin (`su -c 'eval "$(cat)"'`). Nothing is written to
# the tablet, and nothing is started, stopped, set or enabled. Needs root (SukiSU) for logcat -b all, /data and
# /proc/<pid>. Run time about 10 s. The report is saved under
# <PIPA_ROOT>/port-work/device-checks/<date>-<tag>.txt so that runs can be diffed.
#
# Result lines: PASS / FAIL (a real fault) / WARN (check by hand or a known issue) / INFO (no verdict).
# Exit status: 1 if there is a FAIL (or the check script did not finish), else 0.
#
# What the ROM runs (port-rom/pipa_port.rc, early.sh, service.sh; MAINTAINER-STATUS "What runs on the tablet"):
# init services pipa_port, pipa_subsys0/1 in the SELinux domain pipa_port (enforcing since 3g), the face HAL
# from /data/misc/pipa_port/facehal, charger and cryptoeng shims, the keyboard guard, pen watcher, SF/kswapd
# tuning. Feature switches come from config.prop (ROM) and /data/misc/pipa_port/config.prop (user): a switch
# that is 0 there skips its check. The module era (pipa_core, power tune, beta4 jar md5) is gone.
set -eu
ADB=${ADB:-adb -s 192.168.0.37:5555}
TAG=${1:-}
LABEL=${TAG:-run}
case $LABEL in */* | .*) echo "bad tag: $LABEL"; exit 2 ;; esac
PIPA_ROOT=${PIPA_ROOT:-$HOME/Documents/pipa}
OUT=$PIPA_ROOT/port-work/device-checks
REPD=$PIPA_ROOT/port-work/$TAG/report
mkdir -p "$OUT"
REPORT="$OUT/$(date +%Y%m%d-%H%M)-$LABEL.txt"

$ADB get-state >/dev/null 2>&1 || { echo "no device on: $ADB"; exit 1; }
$ADB shell "su -c id" 2>/dev/null | grep -q 'uid=0' || { echo "no root (su) on: $ADB"; exit 1; }

# ---- expected md5 of key files from the build's tree manifests (path, type, mode, uid, gid, md5, xattrs).
# system.tsv paths are full ("/system/...", "/my_product/..."); the other partitions' paths start at their root.
KEYFILES="
/system/framework/oplus-services.jar
/system/bin/surfaceflinger
/system_ext/priv-app/SystemUI/SystemUI.apk
/my_product/priv-app/IPeManager/IPeManager.apk
/vendor/bin/hw/vendor.qti.hardware.display.composer-service
/system_ext/pipa_port/service.sh
/system_ext/pipa_port/early.sh
/system_ext/pipa_port/config.prop
/system_ext/pipa_port/cryptoeng.jar
/system_ext/etc/init/pipa_port.rc
/system_ext/etc/build.prop
/product/etc/build.prop
/system/priv-app/PipaHelper/PipaHelper.apk
"
manifest_md5() {
    case $1 in
        /system_ext/*) t=system_ext; p=${1#/system_ext} ;;
        /vendor/*)     t=vendor;     p=${1#/vendor} ;;
        /product/*)    t=product;    p=${1#/product} ;;
        /odm/*)        t=odm;        p=${1#/odm} ;;
        *)             t=system;     p=$1 ;;
    esac
    awk -F'\t' -v p="$p" '$1 == p && $2 == "f" { print $6; exit }' "$REPD/$t.tsv"
}
TAGSTATE=none
MANIFEST=
if [ -n "$TAG" ]; then
    TAGSTATE=ok
    for t in system system_ext product vendor; do [ -r "$REPD/$t.tsv" ] || TAGSTATE=missing; done
    if [ $TAGSTATE = ok ]; then
        for f in $KEYFILES; do
            m=$(manifest_md5 "$f" || true)
            MANIFEST="$MANIFEST$f ${m:--}
"
        done
    fi
fi

DEV=$(mktemp)
trap 'rm -f "$DEV"' EXIT
cat > "$DEV" <<'DEVICE'
pass() { echo "PASS  $1${2:+  ($2)}"; }
fail() { echo "FAIL  $1${2:+  ($2)}"; }
warn() { echo "WARN  $1${2:+  ($2)}"; }
info() { echo "INFO  $1${2:+  ($2)}"; }
# chk <name> <rc> [detail] [warn]: rc 0 = PASS, else FAIL (WARN when the 4th argument is "warn")
chk()  { if [ "$2" = 0 ]; then pass "$1" "${3:-}"; elif [ "${4:-}" = warn ]; then warn "$1" "${3:-}"; else fail "$1" "${3:-}"; fi; }
ind()  { sed 's/^/      /'; }
# cfg <KEY> <default>: feature switch, the user file /data/misc/pipa_port/config.prop wins over the ROM file
cfg()  { v=$(cat /system_ext/pipa_port/config.prop /data/misc/pipa_port/config.prop 2>/dev/null | sed -n "s/^$1=\([0-9]*\).*/\1/p" | tail -n 1); echo "${v:-$2}"; }

SL=$(service list 2>/dev/null </dev/null)
now=$(date +%s); up=$(cut -d. -f1 /proc/uptime); boot=$((now - up))
BL=/sys/class/backlight/panel0-backlight/brightness
bri=$(cat $BL 2>/dev/null)

echo "== build"
slot=$(getprop ro.boot.slot_suffix)
[ "$slot" = _b ]; chk "slot b active" $? "ro.boot.slot_suffix=${slot:-empty}"
bc=$(getprop sys.boot_completed)
[ "$bc" = 1 ]; chk "boot completed" $? "sys.boot_completed=${bc:-empty}"
layer=$(getprop ro.pipa.port.layer)
[ -n "$layer" ]; chk "ROM layer property set (last step with set_layer, the package-cache key)" $? "ro.pipa.port.layer=${layer:-empty}"
dv=$(getprop ro.product.device)
[ "$dv" = pipa ]; chk "device is pipa" $? "$dv"
info "display id"   "$(getprop ro.build.display.id)"
info "oplus ver"    "$(getprop ro.build.version.ota)"
info "kernel"       "$(uname -r)"
info "uptime"       "${up}s, boot reason $(getprop sys.boot.reason)"
info "ro.adb.secure/ro.secure/ro.debuggable" "$(getprop ro.adb.secure)/$(getprop ro.secure)/$(getprop ro.debuggable) (expect 1/1/0)"
case $TAGSTATE in
    none)    info "image compare" "no tag given: pass one (sh device_check.sh pt3) to compare key files with port-work/<tag>/report/*.tsv" ;;
    missing) warn "image compare" "port-work/$TAG/report/{system,system_ext,product,vendor}.tsv not found: skipped" ;;
    ok)
        if command -v md5sum >/dev/null 2>&1; then
            echo "$MANIFEST" | while read -r f m; do
                [ -n "$f" ] || continue
                if [ "$m" = - ]; then info "image $f" "not in the $TAG manifest"; continue; fi
                if [ ! -e "$f" ]; then fail "image $f" "missing on the tablet"; continue; fi
                d=$(md5sum "$f" 2>/dev/null | cut -c1-32)
                if [ "$d" = "$m" ]; then pass "image $f" "= $TAG"; else fail "image $f" "tablet ${d:-none}, $TAG $m: flashed build is not $TAG"; fi
            done
        else
            warn "image compare" "no md5sum on the tablet"
        fi ;;
esac

echo "== SELinux"
e=$(getenforce 2>/dev/null)
[ "$e" = Enforcing ]; chk "SELinux enforcing" $? "${e:-getenforce failed}"
# match only audit records: adbd also logs the text of shell commands (and so our own grep)
AV=$(logcat -d -b all 2>/dev/null </dev/null | grep 'avc: ' | grep 'denied' | grep -v 'adbd *:')
pn=$(echo "$AV" | grep -cE 'avc: +denied.*scontext=u:r:pipa_port:s0 .*tclass=')
[ "$pn" = 0 ]; chk "no avc denial from pipa_port since boot" $? "$pn in the logcat buffer"
if [ "$pn" != 0 ]; then echo "$AV" | grep -E 'avc: +denied.*scontext=u:r:pipa_port:s0 .*tclass=' | head -3 | cut -c1-220 | ind; fi
info "avc denials in the logcat buffer (all domains)" "$(echo "$AV" | grep -c .)"
echo "      top source domains (count, domain):"
echo "$AV" | sed -n 's/.*scontext=u:r:\([A-Za-z0-9_]*\):.*/\1/p' | sort | uniq -c | sort -rn | head -4 | ind

echo "== pipa_port runtime"
for s in pipa_port pipa_subsys0 pipa_subsys1; do
    st=$(getprop init.svc.$s)
    [ "$st" = running ]; chk "init service $s running" $? "${st:-no such service}"
done
spid=$(cat /data/local/tmp/pipa_port.pid 2>/dev/null)
if [ -n "$spid" ] && tr '\0' ' ' < /proc/$spid/cmdline 2>/dev/null | grep -q 'pipa_port/service.sh'; then
    pass "service.sh main loop alive" "pid $spid"
    dom=$(cat /proc/$spid/attr/current 2>/dev/null | tr -d '\0 ')
    [ "$dom" = u:r:pipa_port:s0 ]; chk "service.sh runs in u:r:pipa_port:s0" $? "${dom:-unreadable}"
else
    fail "service.sh main loop alive" "pid file /data/local/tmp/pipa_port.pid: '${spid:-empty}'"
fi
LOG=/data/local/tmp/pipa_port.log
if [ -f "$LOG" ]; then
    lm=$(stat -c %Y "$LOG" 2>/dev/null || echo 0)
    [ "$lm" -ge "$boot" ]; chk "pipa_port.log written after boot" $? "$((now - lm))s ago, $(wc -l < "$LOG") lines; last: $(tail -n 1 "$LOG" | cut -c1-90)"
    # lines since the last "start (build=" line = this boot's service run
    bad=$(awk '/ start \(build=/ { n = 0 } { l[n++] = $0 } END { for (i = 0; i < n; i++) print l[i] }' "$LOG" | grep -iE 'fail|error|denied')
    [ -z "$bad" ]; chk "no failure in pipa_port.log since service start" $? "$(echo "$bad" | head -n 1 | cut -c1-120)" warn
else
    fail "pipa_port.log written after boot" "$LOG missing"
fi
echo "$SL" | grep -q 'ISubsys/default';    chk "ISubsys/default registered" $?
echo "$SL" | grep -q 'ISubsysRadio/slot1'; chk "ISubsysRadio/slot1 registered" $?
if [ "$(cfg FACE_HAL 1)" = 1 ]; then
    fp=$(pidof android.hardware.biometrics.face-service.facehal)
    if [ -n "$fp" ]; then
        pass "face HAL running" "pid $fp"
        exe=$(readlink /proc/${fp%% *}/exe 2>/dev/null)
        case $exe in /data/misc/pipa_port/facehal/*) pass "face HAL runs from /data/misc/pipa_port/facehal" ;; *) fail "face HAL runs from /data/misc/pipa_port/facehal" "exe ${exe:-unreadable}" ;; esac
    else
        fail "face HAL running" "no process android.hardware.biometrics.face-service.facehal"
    fi
    echo "$SL" | grep -q 'biometrics.face.IFace/default'; chk "face HAL IFace/default registered" $?
    cmp -s /system_ext/pipa_port/facehal/VERSION /data/misc/pipa_port/facehal/VERSION; chk "face HAL /data copy = ROM copy (VERSION)" $?
    n=$(logcat -d -v epoch 2>/dev/null </dev/null | grep 'ctl.interface_start.*IFace' | awk -v t=$((now - 60)) '$1 > t' | wc -l)
    [ "$n" -lt 5 ]; chk "no IFace interface_start spam" $? "$n lines in the last 60 s (boot retries are older)" warn
else
    info "face HAL" "FACE_HAL=0 in config.prop: skipped"
fi
if [ "$(cfg CHARGER_SHIM 1)" = 1 ]; then
    echo "$SL" | grep -q 'vendor.oplus.hardware.charger.ICharger/default'; chk "charger shim: ICharger/default registered" $?
fi
if [ "$(cfg CRYPTOENG 1)" = 1 ]; then
    echo "$SL" | grep -q 'vendor.oplus.hardware.cryptoeng.ICryptoeng/default'; chk "cryptoeng shim: ICryptoeng/default registered" $?
fi
if [ "$(cfg PEN_KEYS 1)" = 1 ]; then
    kp=$(cat /data/local/tmp/pipa_pen_keys.pid 2>/dev/null)
    # service.sh starts it from the main loop, which idles while the screen is off: after a boot with the screen
    # never on it is not running yet
    [ -n "$kp" ] && tr '\0' ' ' < /proc/$kp/cmdline 2>/dev/null | grep -q 'pen_keys.sh'
    chk "pen_keys.sh running" $? "pid ${kp:-none}$([ "${bri:-0}" = 0 ] && echo ', screen off: starts at the first screen-on')" warn
fi
# keyboard guard (service.sh kb_guard): xiaomi-keyboard runs only while the MCU reports the case connected
KB_HALL=/sys/devices/virtual/nanodev/nanodev0/_version176x
kst=$(getprop init.svc.xiaomi-keyboard)
if [ "$(cfg KEYBOARD_GUARD 1)" != 1 ]; then
    info "keyboard guard" "KEYBOARD_GUARD=0 in config.prop: skipped"
elif [ ! -e "$KB_HALL" ]; then
    warn "keyboard guard" "$KB_HALL missing (other kernel?)"
else
    hall=$(cat "$KB_HALL" 2>/dev/null)
    kbdev=$(grep -cE '^N: Name="(Xiaomi|Mi) (Keyboard|Consumer( Control)?|Touchpad)"' /proc/bus/input/devices)
    case $hall in *'Connected=[1]'*) att=1 ;; *) att=0 ;; esac
    if [ $att = 1 ]; then
        [ "$kst" = running ]; chk "xiaomi-keyboard running with the case attached" $? "$kst, $hall" warn
    elif [ "$kst" != running ]; then
        pass "xiaomi-keyboard stopped without the case (keyboard guard)" "${kst:-no service}, $hall"
    elif [ "$kbdev" -gt 0 ] || [ -z "$bri" ] || [ "$bri" = 0 ]; then
        warn "xiaomi-keyboard running without the case" "$hall; keyboard input devices $kbdev, screen $([ "${bri:-0}" = 0 ] && echo off || echo on): a keyboard may be attached or the guard idles with the screen off"
    else
        fail "xiaomi-keyboard running without the case" "$hall, screen on: the keyboard guard did not stop it (idle drain)"
    fi
fi
# the pipa helper app: persistent system priv-app
hp=$(pm path com.port.pipa.helper </dev/null 2>/dev/null)
if [ -z "$hp" ]; then
    fail "pipa helper installed" "package com.port.pipa.helper not found"
else
    hd=$(dumpsys package com.port.pipa.helper </dev/null 2>/dev/null)
    hv=$(echo "$hd" | sed -n 's/.*versionName=//p' | head -n 1)
    case $hp in package:/system/priv-app/*) echo "$hd" | grep -m1 'pkgFlags=' | grep -q 'SYSTEM' && echo "$hd" | grep -m1 'pkgFlags=' | grep -q 'PERSISTENT'; chk "pipa helper is a persistent system priv-app" $? "v$hv, ${hp#package:}" ;;
        *) warn "pipa helper is a persistent system priv-app" "installed outside /system/priv-app: ${hp#package:} (test build?)" ;;
    esac
    hpid=$(pidof com.port.pipa.helper)
    [ -n "$hpid" ]; chk "pipa helper process running" $? "pid ${hpid:-none}" warn
fi

echo "== performance setup"
SA=/proc/sys/kernel/sched_assist_scene
if [ "$(cfg SF_BIG_CORES 1)" != 1 ]; then
    info "SF_BIG_CORES" "off in config.prop: skipped"
elif [ -e "$SA" ]; then
    # service.sh writes 384 (SA_SCENE_OPT_SET 1<<7 | SA_GPU_COMPOSITION 1<<8); the node reads back 256 because
    # bit 7 is only the "set" command flag, so the scene bit to look for is 1<<8
    sv=$(cat "$SA" 2>/dev/null)
    [ $((${sv:-0} & 256)) != 0 ]; chk "sched_assist_scene has SF big-cores bit (SF_BIG_CORES)" $? "value $sv (service.sh writes 384, node reads 256)"
else
    warn "sched_assist_scene" "no $SA (kernel without UI First?)"
fi
if [ "$(cfg KSWAPD_NO_PRIME 1)" = 1 ]; then
    nk=0; bk=0
    for c in /proc/[0-9]*/comm; do
        { read -r n < "$c"; } 2>/dev/null || continue
        case $n in kswapd*)
            p=${c#/proc/}; p=${p%/comm}
            m=$(sed -n 's/^Cpus_allowed:[[:space:]]*//p' /proc/$p/status 2>/dev/null | tr -d ',')
            nk=$((nk + 1))
            [ -n "$m" ] && [ $((0x$m & 128)) != 0 ] && bk=$((bk + 1)) ;;
        esac
    done
    if [ $nk = 0 ]; then warn "kswapd off CPU 7 (KSWAPD_NO_PRIME)" "no kswapd process found"
    else [ $bk = 0 ]; chk "kswapd off CPU 7 (KSWAPD_NO_PRIME)" $? "$nk kswapd, $bk with CPU 7 allowed"; fi
fi
hdr=$(getprop ro.surface_flinger.has_HDR_display)
[ "$hdr" = true ]; chk "ro.surface_flinger.has_HDR_display=true (3h)" $? "${hdr:-empty}" warn
wcg=$(getprop ro.surface_flinger.has_wide_color_display)
[ "$wcg" = true ]; chk "ro.surface_flinger.has_wide_color_display=true (3i)" $? "${wcg:-empty}" warn
sc=$(getprop dalvik.vm.systemuicompilerfilter)
[ "$sc" = speed ]; chk "dalvik.vm.systemuicompilerfilter=speed" $? "${sc:-empty}" warn
al=$(getprop persist.sys.oplus.anim_level)
case $al in 1|2|3|4) pass "persist.sys.oplus.anim_level set" "$al" ;; *) warn "persist.sys.oplus.anim_level set" "'${al}' (service.sh sets it 3 at boot)" ;; esac
ar=$(getprop persist.logd.audit.rate)$(getprop persist.logd.size)
[ -z "$ar" ]; chk "logd capture properties back to default" $? "persist.logd.audit.rate/size='${ar}'" warn
grep -q zram0 /proc/swaps; chk "zram0 active" $?
# nandswap is a swapfile on a loop device; the dedup in service.sh keeps one
nl=$(grep -c '^/dev/block/loop' /proc/swaps)
[ "$nl" = 1 ]; chk "one nandswap loop swap" $? "$nl loop swap area(s)" warn
c=$(dumpsys color_display </dev/null 2>/dev/null | grep -m1 -o 'sensorCCT[^,]*')
echo "$c" | awk -F= '{ exit !($2 + 0 > 0) }'; chk "adaptive colour gets a CCT value (jar reroute)" $? "${c:-no sensorCCT line}" warn
info "colour mode" "$(settings get system display_color_mode </dev/null 2>/dev/null), brightness min $(dumpsys display </dev/null 2>/dev/null | grep -m1 -o 'mScreenBrightnessRangeMinimum=[0-9.]*')"

echo "== health"
CR=$(logcat -d -b crash 2>/dev/null </dev/null)
sig=$(echo "$CR" | grep 'Fatal signal' | sed -n 's/.*pid [0-9]* (\(.*\))$/\1/p')
nsig=$(echo "$sig" | grep -c .)
# the first zygote64 aborts in preload at each boot and restarts at once (BUGS-TODO 30): 1 is expected
nzy=$(echo "$sig" | grep -cE '^(main|zygote|zygote64)$')
nother=$((nsig - nzy))
[ "$nzy" -le 1 ]; chk "boot zygote abort at most once (BUGS-TODO 30)" $? "$nzy zygote-like Fatal signal(s)" warn
[ "$nother" = 0 ]; chk "no other native crash since boot" $? "$nother Fatal signal(s)" warn
if [ "$nother" != 0 ]; then echo "$sig" | grep -vE '^(main|zygote|zygote64)$' | sort | uniq -c | sort -rn | head -5 | ind; fi
jx=$(echo "$CR" | grep -c 'FATAL EXCEPTION')
[ "$jx" = 0 ]; chk "no Java FATAL EXCEPTION since boot" $? "$jx in the crash buffer" warn
if [ "$jx" != 0 ]; then echo "$CR" | grep -o 'Process: [^,]*' | sort | uniq -c | sort -rn | head -5 | ind; fi
ss=$(pidof system_server | cut -d' ' -f1)
if [ -n "$ss" ]; then
    hz=$(getconf CLK_TCK 2>/dev/null); hz=${hz:-100}
    sst=$(( $(awk '{print $22}' /proc/$ss/stat) / hz ))
    [ "$sst" -le 90 ]; chk "system_server not restarted" $? "pid $ss started ${sst}s after boot (uptime ${up}s)" warn
else
    fail "system_server running" "no process"
fi
anr=$(find /data/anr -type f -mmin -$((up / 60 + 1)) 2>/dev/null)
[ -z "$anr" ]; chk "no ANR trace newer than boot" $? "$(echo "$anr" | grep -c .) file(s)$([ -n "$anr" ] && echo ": $(echo "$anr" | head -n 2 | tr '\n' ' ')")" warn
[ -d /data/ota_package/OTA ]; chk "/data/ota_package/OTA exists (R11)" $?
op=$(pm list packages </dev/null 2>/dev/null | grep -E '^package:com\.oplus\.(ota|sau|sauhelper)$')
[ -z "$op" ]; chk "OTA updater packages removed" $? "${op:+still installed: }$(echo "$op" | tr '\n' ' ')"
[ -e /system/framework/oat/arm64/oplus-services.odex ]; [ $? != 0 ]; chk "no prebuilt oplus-services.odex" $?

echo "== root (SukiSU)"
info "ksud" "$(/data/adb/ksud --version 2>/dev/null || echo 'not found')"
info "SukiSU manager" "$(pm path com.sukisu.ultra </dev/null 2>/dev/null | cut -c1-60 | grep -q . && echo installed || echo 'not installed')"
MD=/data/adb/modules
nm=0
if [ -d "$MD" ]; then
    for m in $(ls -1 "$MD" 2>/dev/null); do
        nm=$((nm + 1))
        mv=$(sed -n 's/^version=//p' "$MD/$m/module.prop" 2>/dev/null | head -n 1)
        off=; [ -e "$MD/$m/disable" ] && off=", disabled"
        case $m in
            pipa_susfs) info "module pipa_susfs (root hiding, optional)" "v${mv:-?}$off" ;;
            pipa_core | pipa_cos17_power_tune | pipa_port) fail "module-era module $m present" "v${mv:-?}$off: the ROM already runs its code; remove /data/adb/modules/$m" ;;
            *) info "module $m" "v${mv:-?}$off" ;;
        esac
    done
fi
[ -d "$MD/pipa_core" ] || [ -d "$MD/pipa_cos17_power_tune" ] || [ -d "$MD/pipa_port" ]; [ $? != 0 ]; chk "no pipa_core / power tune / pipa_port module" $? "$nm module(s) installed"

echo "== battery"
info "level/current" "$(cat /sys/class/power_supply/battery/capacity 2>/dev/null)% / $(cat /sys/class/power_supply/battery/current_now 2>/dev/null) uA"
echo "== end"
DEVICE

{
    printf "TAG='%s'\nTAGSTATE='%s'\nMANIFEST='%s'\n" "$TAG" "$TAGSTATE" "$MANIFEST"
    cat "$DEV"
} | $ADB shell "su -c 'eval \"\$(cat)\"'" | tr -d '\r' | tee "$REPORT"
grep -q '^== end' "$REPORT" || echo "FAIL  check script did not reach its end (adb or su problem)" | tee -a "$REPORT"
echo
np=$(grep -c '^PASS' "$REPORT" || true)
nf=$(grep -c '^FAIL' "$REPORT" || true)
nw=$(grep -c '^WARN' "$REPORT" || true)
echo "summary: $np pass, $nf fail, $nw warn -> $REPORT"
[ "$nf" = 0 ]
