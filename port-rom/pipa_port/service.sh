#!/system/bin/sh
# pipa_port runtime (after boot), started by init (/system_ext/etc/init/pipa_port.rc) as the
# pipa_port service. Same code as the pipa_port module v1.3, with ROM paths: code read-only in
# /system_ext/pipa_port, state in /data/misc/pipa_port. Merged from pipa_core 1.12 (face HAL, charger shim, pen wake
# and keys, blur default) and power-tune v0.15 (face watchdog, pen watcher, colour/adaptive
# restore, helper grants, keyboard event12 link). Everything beta5-2d has built in is gone.
#
# Log: /data/local/tmp/pipa_port.log (face/charger/pen daemons keep their own logs).
MODDIR=/system_ext/pipa_port
STATE=/data/misc/pipa_port
LOG=/data/local/tmp/pipa_port.log
. "$MODDIR/config.prop"
[ -f "$STATE/config.prop" ] && . "$STATE/config.prop"   # user overrides

log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') $*" >> "$LOG"
}

# Read a setting: sget system|secure|global <key> (prints the value or "null"; fails if the read fails). `settings get`
# cannot write to a pipe of the pipa_port domain ("Failed transaction"), so `$(settings get ...)` returned the error
# text from 2e to 2r (the colour state file got it, and its "1" turned Bedtime on at each boot). A file in
# /data/local/tmp works: 0.03 s CPU per read (`content query`, Java: 0.28 s).
SGET_F=/data/local/tmp/pipa_port.sget
sget() {
    : > "$SGET_F"
    settings get "$1" "$2" </dev/null >"$SGET_F" 2>/dev/null || return 1
    v=; read -r v < "$SGET_F"
    echo "${v:-null}"
}

[ "$(getprop ro.product.device)" = pipa ] || exit 0

# singleton (a manual test run must not double the watchers)
PIDF=/data/local/tmp/pipa_port.pid
old=$(cat "$PIDF" 2>/dev/null)
if [ -n "$old" ] && [ "$old" != "$$" ] && \
   tr '\0' ' ' < "/proc/$old/cmdline" 2>/dev/null | grep -q 'pipa_port/service.sh'; then
    exit 0
fi
echo $$ > "$PIDF"

if [ -f "$LOG" ] && [ "$(wc -c < "$LOG" 2>/dev/null || echo 0)" -gt 262144 ]; then
    tail -n 400 "$LOG" > "$LOG.tmp" 2>/dev/null && mv -f "$LOG.tmp" "$LOG"
fi

until [ "$(getprop sys.boot_completed)" = 1 ]; do sleep 2; done
log "start (build=$(getprop ro.build.display.id))"

# ------------------------------------------------------------ SurfaceFlinger on big cores
# Our kernel's OPPO UI First keeps SurfaceFlinger + RenderEngine (realtime) off the little cores only while a
# sched_assist scene is set; on OPPO phones their vendor perf daemon sets it, pipa's Xiaomi vendor never does, so SF
# composed on A55 cores and missed vblanks (2026-10-24 FrameTimeline: SF dropped frames -58 %, GPU-deadline misses
# -52 %, +2 % power under heavy use). Set SA_GPU_COMPOSITION (1<<8) with SA_SCENE_OPT_SET (1<<7) once; it only
# affects SF/RE placement. No such node on other kernels.
SA_SCENE=/proc/sys/kernel/sched_assist_scene
if [ "${SF_BIG_CORES:-1}" = 1 ] && [ -w "$SA_SCENE" ]; then
    echo 384 > "$SA_SCENE" && log "sched_assist scene -> $(cat "$SA_SCENE") (SurfaceFlinger off the little cores)"
fi

# ------------------------------------------------------------ kswapd off the prime core
# Under memory pressure kswapd (zram lz4 compression) ran 19.7 s of 60 s on cpu7, more than the launcher (10.3 s) and
# SurfaceFlinger (7.1 s) there (2026-10-24 trace manual-2). On CPUs 0-6 (manual-3): launcher frames > 120 ms 21 -> 4,
# prime idle 10.3 -> 20.5 s, no more reclaim stalls. Once: kswapd does not restart.
if [ "${KSWAPD_NO_PRIME:-1}" = 1 ]; then
    for c in /proc/[0-9]*/comm; do
        read -r n < "$c" 2>/dev/null || continue
        case $n in
            kswapd*) p=${c#/proc/}; p=${p%/comm}
                     taskset -p 7f "$p" >/dev/null 2>&1 && log "kswapd $p -> CPUs 0-6"; break ;;
        esac
    done
fi

# ------------------------------------------------------------ system_server animation threads as UX
# android.anim holds the WindowManager lock while it animates (QS collapse, app launch): Settings waited 466 ms per 4
# launches on it, and android.display waited for a CPU longer than it ran. ColorOS sets UX for app threads only;
# mark these as animator UX (5.10 value 128|4) through the UI First ux_task node. Checked again in the main loop in
# case system_server restarts.
UX_TASK=/proc/oplus_scheduler/sched_assist/ux_task
SS_PID=
system_ux() {
    p=$(pidof system_server) || return
    [ "$p" = "$SS_PID" ] && return
    for t in $(ls /proc/$p/task 2>/dev/null); do
        case "$(cat /proc/$p/task/$t/comm 2>/dev/null)" in
            android.anim|android.display|android.ui) echo "p $t 132" > "$UX_TASK" 2>/dev/null ;;
        esac
    done
    SS_PID=$p
    log "system_server $p: android.anim/display/ui -> UX"
}
[ "${SYSTEM_UX:-1}" = 1 ] && [ -w "$UX_TASK" ] && system_ux

# ------------------------------------------------------------ full AOT compile of the UI apps
# bg-dexopt compiles speed-profile (hot methods only); first showings (QS panel, Settings, launcher) then run partly
# interpreted. dalvik.vm.systemuicompilerfilter=speed (product build.prop) keeps SystemUI at speed in later dexopts;
# compile these once per ROM build, 3 minutes after boot, in the background. ART does not downgrade a speed compile in bg-dexopt.
SPEED_STATE=$STATE/speed_compiled
speed_compile() {
    fp=$(getprop ro.build.fingerprint)$(getprop ro.system_ext.build.date.utc)
    [ "$(cat "$SPEED_STATE" 2>/dev/null)" = "$fp" ] && return
    sleep 180
    for p in ${SPEED_APPS:-com.android.systemui com.android.settings com.oplus.wirelesssettings com.android.launcher}; do
        cmd package compile -m speed -f "$p" </dev/null >/dev/null 2>&1 && log "compiled $p (speed)"
    done
    echo "$fp" > "$SPEED_STATE"
}
[ "${SPEED_COMPILE:-1}" = 1 ] && ( speed_compile ) &

BL=/sys/class/backlight/panel0-backlight/brightness
# nap: wait without a sleep process (each toybox start costs ~17 ms CPU here): mksh `read -t` on a FIFO that
# nobody writes. Falls back to sleep if the FIFO cannot be made.
NAP_FIFO=/data/misc/pipa_port/nap.fifo
rm -f "$NAP_FIFO"
if mkfifo "$NAP_FIFO" 2>/dev/null && exec 7<>"$NAP_FIFO"; then
    nap() { read -t "$1" -u7 _ 2>/dev/null; }
else
    nap() { sleep "$1"; }
fi
screen_on() {   # shell builtins only in the per-second loop (no cat/grep/stat processes): 2q
    b=; read -r b < "$BL" 2>/dev/null
    [ -n "$b" ] && [ "$b" != 0 ]
}

# ------------------------------------------------------------------- face HAL
# facehal-rs lives in the module (/data) and runs with LD_LIBRARY_PATH: from /vendor/lib64
# it would land in the vendor linker namespace and miss /system/lib64 deps of
# libcamera2ndk_vendor.so. init's hal_face_default domain has no camera/GPU access, so it
# runs as root. OpenCL: the 819 libs need the Khronos ICD loader + the vendor ICD manifest,
# stock vendor needs the old monolithic loader; a mismatch makes TFLite fall back to GL,
# which is single-thread only, and the HAL dies.
# The HAL runs from a /data copy, exactly as from the module: the system linker namespace
# permits /data but not arbitrary /system_ext subdirectories for LD_LIBRARY_PATH. Refreshed
# when the ROM copy changes (VERSION = md5 list made at build time).
FACE=$STATE/facehal
FACE_BIN=$FACE/android.hardware.biometrics.face-service.facehal
face_install() {
    cmp -s "$MODDIR/facehal/VERSION" "$FACE/VERSION" && return
    rm -rf "$FACE"
    cp -a "$MODDIR/facehal" "$FACE" && log "facehal copied to $FACE"
}

face_running() {
    [ "$(getprop init.svc.vendor.facehal)" = running ] && return 0
    pgrep -f android.hardware.biometrics.face-service.facehal >/dev/null 2>&1
}

face_start() {
    if [ -f /vendor/Khronos/OpenCL/vendors/adreno.icd ] && [ -f /vendor/lib64/libOpenCL_adreno.so ]; then
        cl=libOpenCL.so.819
    else
        cl=libOpenCL.so.stock
    fi
    [ -f "$FACE/lib64/$cl" ] && cp -f "$FACE/lib64/$cl" "$FACE/lib64/libOpenCL.so"
    mkdir -p /data/vendor_de/0/facedata/facehal/templates
    chmod 0770 /data/vendor_de/0/facedata
    chmod 0700 /data/vendor_de/0/facedata/facehal
    chmod 0755 "$FACE_BIN" 2>/dev/null
    # B7: libpipa_facecrop crops the enrollment preview to the square ColorOS view (src/facecrop.c)
    # 8 (3f): libpipa_eyeguard clamps an eye ROI outside the frame in crop_eyes (src/eyeguard.c): no SIGSEGV
    pre=$FACE/lib64/libpipa_facecrop.so
    [ -f "$FACE/lib64/libpipa_eyeguard.so" ] && pre=$pre:$FACE/lib64/libpipa_eyeguard.so
    LD_PRELOAD=$pre LD_LIBRARY_PATH=$FACE/lib64:$FACE \
        nohup "$FACE_BIN" >>/data/local/tmp/facehal.log 2>&1 &
    log "facehal started pid=$! ($cl)"
}

if [ "${FACE_HAL:-1}" = 1 ]; then
    (
        face_install
        sleep 6
        setprop ctl.stop vendor.facehal
        for p in $(pgrep -f android.hardware.biometrics.face-service.facehal); do kill -9 "$p"; done
        sleep 1
        face_start
    ) &
fi

# --------------------------------------------------------------- charger shim
# No vendor.oplus.hardware.charger.ICharger on pipa: ColorOS reads -1 everywhere and reports
# an abnormal charger. ShimHost serves values from the qcom power_supply nodes; servicemanager
# refuses a local binder for a VINTF-declared AIDL name, so ShimRegister registers it through
# a cross-process proxy.
if [ "${CHARGER_SHIM:-1}" = 1 ] && ! pgrep -f shim.ShimHost >/dev/null 2>&1; then
    (
        sleep 4
        L=/data/local/tmp/chargershim.log
        HALJAR=/system_ext/framework/vendor.oplus.hardware.charger-V12-java.jar
        while true; do
            ( sleep 3; CLASSPATH=$MODDIR/chargershim.jar:$HALJAR \
                app_process /system/bin shim.ShimRegister >> $L 2>&1 ) &
            CLASSPATH=$MODDIR/chargershim.jar:$HALJAR app_process /system/bin shim.ShimHost >> $L 2>&1
            echo "$(date) charger shim host exited, restart in 5s" >> $L
            sleep 5
        done
    ) &
fi

# ------------------------------------------------------------ cryptoeng shim
# No vendor.oplus.hardware.cryptoeng.ICryptoeng on pipa (OPPO keeps the privacy password in a TEE app), so the
# privacy password, app lock and hidden apps failed without a message. CryptoEngShim (maintainer/cryptoeng) answers
# the same commands and keeps the records in $STATE/cryptoeng (root only). Only uid 1000 and root may call it.
if [ "${CRYPTOENG:-1}" = 1 ] && ! pgrep -f CryptoEngShim >/dev/null 2>&1; then
    (
        L=/data/local/tmp/cryptoeng.log
        while true; do
            CLASSPATH=$MODDIR/cryptoeng.jar app_process /system/bin CryptoEngShim "$STATE/cryptoeng" </dev/null >> $L 2>&1
            echo "$(date) cryptoeng shim exited, restart in 5s" >> $L
            sleep 5
        done
    ) &
fi

# ------------------------------------------------------------------- defaults
# Written only when unset, so the user's own choice wins.
if [ "${BLUR_DEFAULT:-1}" = 1 ] && [ "$(sget system animationBlurrySwitch)" = null ]; then
    settings put system animationBlurrySwitch 0 && log "animation blur default -> 0"
fi
if [ "${STYLUS_BUTTONS_DEFAULT:-1}" = 1 ] && [ "$(sget secure stylus_buttons_enabled)" = null ]; then
    settings put secure stylus_buttons_enabled 1
    touch "$STATE/stylus_default_set"
    log "stylus_buttons_enabled default -> 1"
fi
# 2q smoothness defaults, once per install (state file; the user can change them back in Developer options):
# window blur off (SurfaceFlinger forces GPU composition of every layer below a blur: A/B -25 % dropped frames,
# -35 % GPU misses), material blur off (launcher jank about -40 %). Animation scales stay at 1.0 since 2s (user choice).
if [ "${SMOOTH_DEFAULT:-1}" = 1 ] && [ ! -e "$STATE/smooth_default_set" ]; then
    {
        settings put global disable_window_blurs 1
        settings put system system_material_blur_enable 0
        # ColorOS writes animationBlurrySwitch=1 itself on a first boot (before BLUR_DEFAULT sees "null"), 2v
        settings put system animationBlurrySwitch 0
        # The nanosic driver always registers "Xiaomi Keyboard" input devices, so Android thinks a hardware keyboard is
        # attached and hides the on-screen keyboard (clean flash, 2026-10-25). Keep it visible; with the real
        # keyboard cover the user can switch it off (Settings: on-screen keyboard while a physical one is active).
        settings put secure show_ime_with_hard_keyboard 1
    } </dev/null >/dev/null 2>&1
    touch "$STATE/smooth_default_set"
    log "first-boot defaults: window blur off, material blur off, animation blur off, on-screen keyboard on"
fi
# The ROM's default-permissions entry only applies on a first boot.
if [ "${HELPER_GRANTS:-1}" = 1 ] && pm path com.port.pipa.helper >/dev/null 2>&1; then
    pm grant com.port.pipa.helper android.permission.POST_NOTIFICATIONS >/dev/null 2>&1
    appops set com.port.pipa.helper SYSTEM_ALERT_WINDOW allow >/dev/null 2>&1
    log "pipa helper: notification + overlay granted"
fi
# SukiSU-Ultra manager, once per install (2w). KernelSU finds its manager only under /data/app (the system preload of
# 2u gave no root), so install the APK that matches the kernel (4.2.1-r1) as a normal app. `pm install` from this
# domain works (tested 2026-10-28). The user can update or uninstall it: the state file stops a second install.
if [ "${KSU_MANAGER:-1}" = 1 ] && [ ! -e "$STATE/ksu_manager_set" ] && [ -f "$MODDIR/SukiSU.apk" ]; then
    if pm path com.sukisu.ultra </dev/null >/dev/null 2>&1; then
        touch "$STATE/ksu_manager_set"
        log "SukiSU manager already installed"
    elif pm install "$MODDIR/SukiSU.apk" </dev/null >/dev/null 2>&1; then
        touch "$STATE/ksu_manager_set"
        log "SukiSU manager installed"
    else
        log "SukiSU manager install failed (next boot tries again)"
    fi
fi

# ------------------------------------------------- colour / adaptive / bedtime
# ColorOS re-applies Vivid (256) at boot, and the Eye Protect app resets adaptive colour and
# Bedtime (it checks OPPO's CCT sensor type, not the rerouted Xiaomi one). Remember the
# user's choice in the loop below and put it back once here.
COLOR_STATE=$STATE/color_mode
ADAPTIVE_STATE=$STATE/adaptive_state
BEDTIME_STATE=$STATE/bedtime_state
sleep 15
if [ "${COLOR_MODE_RESTORE:-1}" = 1 ] && [ -f "$COLOR_STATE" ]; then
    want=$(cat "$COLOR_STATE"); now=$(sget system display_color_mode)
    case $want in ''|*[!0-9]*) want= ; rm -f "$COLOR_STATE" ;; esac   # 2e-2r stored an error text here
    [ -n "$want" ] && [ "$want" != "$now" ] && \
        settings put system display_color_mode "$want" && log "colour mode $now -> $want restored"
fi
if [ "${ADAPTIVE_RESTORE:-1}" = 1 ]; then
    if [ "$(cat "$ADAPTIVE_STATE" 2>/dev/null)" = 1 ]; then
        for k in setting_enable_color_temperature_regulation oplus_customize_comfort_color_temperature_enable; do
            [ "$(sget system $k)" = 1 ] || settings put system $k 1
        done
        log "adaptive colour restored"
    fi
    if [ "$(cat "$BEDTIME_STATE" 2>/dev/null)" = 1 ]; then
        for k in oplus_customize_rhythm_health_enable oplus_customize_comfortable_rhythm_enable; do
            [ "$(sget system $k)" = 1 ] || settings put system $k 1
        done
        log "bedtime mode restored"
    fi
fi

SYS_XML=/data/system/users/0/settings_system.xml
SYS_STAMP=/data/misc/pipa_port/display.stamp
rm -f "$SYS_STAMP"
remember_display() {
    if [ "${COLOR_MODE_RESTORE:-1}" = 1 ]; then
        cm=$(sget system display_color_mode)
        case "$cm" in ''|null) ;; *) [ "$cm" = "$(cat "$COLOR_STATE" 2>/dev/null)" ] || echo "$cm" > "$COLOR_STATE" ;; esac
    fi
    if [ "${ADAPTIVE_RESTORE:-1}" = 1 ]; then
        av=$(sget system setting_enable_color_temperature_regulation)
        case "$av" in 0|1) [ "$av" = "$(cat "$ADAPTIVE_STATE" 2>/dev/null)" ] || echo "$av" > "$ADAPTIVE_STATE" ;; esac
        # Bedtime is on if either the standalone or the Eye Comfort-dependent switch is on
        case "$(sget system oplus_customize_rhythm_health_enable)$(sget system oplus_customize_comfortable_rhythm_enable)" in
            *1*) bt=1 ;; *0*) bt=0 ;; *) bt= ;;
        esac
        [ -n "$bt" ] && [ "$bt" != "$(cat "$BEDTIME_STATE" 2>/dev/null)" ] && echo "$bt" > "$BEDTIME_STATE"
    fi
}

# B7: facehal-rs adds persist.vendor.facehal.rotation to the camera orientation for every
# preview frame but ignores the display rotation; on pipa the right extra turn is
# 90 x display rotation. Only while a camera worker (a second facehal process) runs.
# pidof scans all of /proc (and logs an SELinux denial for each foreign process while the domain
# is permissive), so it runs every 3rd tick, and every tick only while a worker was seen in the last 10 s.
FROT=$(getprop persist.vendor.facehal.rotation)
FACE_SEEN=-100
face_rotation_sync() {
    [ $((tick - FACE_SEEN)) -lt 10 ] || [ $((tick % 3)) = 0 ] || return
    set -- $(pidof android.hardware.biometrics.face-service.facehal)
    [ $# -gt 1 ] || return
    FACE_SEEN=$tick
    # The display rotation from `cmd display get-displays` into a file (first display = the panel). `dumpsys display`
    # fails in this domain (FAILED_TRANSACTION, also into a file), and $(...) pipes fail for every system_server tool,
    # so from 2e to 2u the preview turn was never set (clean flash 2026-10-25: rotated in landscape).
    cmd display get-displays </dev/null >"$SGET_F" 2>/dev/null || return
    r=$(grep -m1 -oE 'rotation [0-3]' "$SGET_F")
    r=${r#rotation }
    [ -n "$r" ] && [ "$((r * 90))" != "$FROT" ] || return
    FROT=$((r * 90))
    setprop persist.vendor.facehal.rotation $FROT
    log "face preview rotation -> $FROT"
}

# B14: magnetic case. The hall is a SW_LID switch (gpio_keys hall_key), so Android's lid
# handling works, but PhoneWindowManager only sleeps on close with global lid_behavior=1 and
# SettingsProvider seeds 0 (config_lidControlsSleep=false). ColorOS's own "smart case" switch
# (global device_case_enabled) waits for an OPPO hall sensor pipa lacks, so it does nothing:
# let that switch drive lid_behavior instead.
LIDB=$(sget global lid_behavior)
# Settings are persisted to this file within ~2 s of a change; a stat per second is cheap, a
# sget (`settings get`, a process) is not, so read the switch only when the file changed.
GLOBAL_XML=/data/system/users/0/settings_global.xml
# A zygote restart (system_server crash, soft reboot) sets sys.boot_completed again, and OPPO's
# init.oplus.nandswap.sh then attaches /data/nandswap/swapfile once more (seen 3x on one file: if zram ever fills,
# the swap areas would overwrite each other). Keep the first loop swap, remove the others.
nandswap_dedup() {
    n=0
    while read -r dev rest; do
        case $dev in
            /dev/block/loop*)
                n=$((n + 1))
                if [ $n -gt 1 ]; then swapoff "$dev" 2>/dev/null && losetup -d "$dev" 2>/dev/null; log "nandswap: removed duplicate swap $dev"; fi ;;
        esac
    done < /proc/swaps
}
# Launcher animation tier (OplusLauncher reads persist.sys.oplus.anim_level). 3 = wallpaper zoom off and lighter
# interruption handling: SF dropped frames 2.7 -> 0.3 %, GPU deadline misses 116 -> 10 per run (2026-10-24, traced_heavy);
# 2 keeps every parallel-animation path (dropped 1.5 %); 4 = light animations, no full-scene continuity. The helper's
# Quick Settings tile (or `settings put global pipa_anim_level N`) picks the tier; the launcher restarts to apply it.
ANIM_STAMP=/data/misc/pipa_port/anim.stamp
rm -f "$ANIM_STAMP"
anim_check() {
    [ -e "$ANIM_STAMP" ] && ! [ "$GLOBAL_XML" -nt "$ANIM_STAMP" ] && return
    : > "$ANIM_STAMP"
    want=$(sget global pipa_anim_level) || return   # a failed read must not reset the tier
    case $want in 1|2|3|4) ;; *) want=${ANIM_LEVEL:-3} ;; esac
    [ "$(getprop persist.sys.oplus.anim_level)" = "$want" ] && return
    setprop persist.sys.oplus.anim_level "$want"
    am force-stop com.android.launcher </dev/null >/dev/null 2>&1
    am start -a android.intent.action.MAIN -c android.intent.category.HOME </dev/null >/dev/null 2>&1
    log "launcher animation tier -> $want"
}
LID_STAMP=/data/misc/pipa_port/lid.stamp
rm -f "$LID_STAMP"
lid_check() {   # [ -nt ] is a builtin test: no stat process per second
    [ -e "$LID_STAMP" ] && ! [ "$GLOBAL_XML" -nt "$LID_STAMP" ] && return
    : > "$LID_STAMP"
    lid_sync
}
lid_sync() {
    case "$(sget global device_case_enabled)" in 0) want=0 ;; *) want=1 ;; esac
    [ "$want" = "$LIDB" ] && return
    settings put global lid_behavior $want
    LIDB=$want
    log "smart case switch -> lid_behavior $want"
}

# ------------------------------------------------------------- keyboard link
# xiaomi-keyboard only access()es /dev/input/event12 as its "keyboard present" flag; on pipa
# the case never lands on event12, so link it there while attached.
KB_LINK=/dev/input/event12
kb_node() {
    awk '/^N: Name=/ { kb = ($0 ~ /Name="(Xiaomi|Mi) (Keyboard|Consumer( Control)?|Touchpad)"/) }
         /^H: Handlers=/ && kb { if (match($0, /event[0-9]+/)) { print substr($0, RSTART, RLENGTH); exit } }' \
        /proc/bus/input/devices 2>/dev/null
}
kb_link() {
    node=$(kb_node)
    if [ -n "$node" ] && [ "$node" != event12 ]; then
        if [ -L "$KB_LINK" ]; then
            [ "$(readlink "$KB_LINK")" = "$node" ] && return
            rm -f "$KB_LINK"
        elif [ -e "$KB_LINK" ]; then
            return
        fi
        ln -s "$node" "$KB_LINK" && chcon -h u:object_r:input_device:s0 "$KB_LINK" 2>/dev/null
        log "keyboard on $node -> $KB_LINK linked"
    elif [ -z "$node" ] && [ -L "$KB_LINK" ]; then
        rm -f "$KB_LINK" && log "keyboard gone -> $KB_LINK removed"
    fi
}

# ------------------------------------------------------------ keyboard guard
# The nanosic driver registers its "Xiaomi Keyboard" input devices at probe, attached or not,
# so xiaomi-keyboard always runs and polls the accelerometer ~7x/s: the SLPI never sleeps
# and the SoC never reaches full power collapse (2026-10-24: SLPI asleep 27 % overnight).
# Run it only while the MCU reports the keyboard connected (bit 0 of the keypad hall status,
# asked for by a write to _version176x). Typing works without the daemon; it only does
# the fold-behind auto-disable.
KB_HALL=/sys/devices/virtual/nanodev/nanodev0/_version176x
kb_attached() {
    echo 1 > "$KB_HALL" 2>/dev/null || return 1
    nap 0.1
    case $(< "$KB_HALL") in *'Connected=[1]'*) return 0 ;; esac
    return 1
}
kb_guard() {
    if kb_attached; then want=running; else want=stopped; fi
    now=$(getprop init.svc.xiaomi-keyboard)
    [ -z "$now" ] || [ "$now" = "$want" ] && return
    if [ $want = running ]; then setprop ctl.start xiaomi-keyboard; else setprop ctl.stop xiaomi-keyboard; fi
    log "keyboard $( [ $want = running ] && echo attached || echo absent ) -> xiaomi-keyboard $want"
}
[ "${KEYBOARD_GUARD:-1}" = 1 ] && [ -e "$KB_HALL" ] && kb_guard

# ------------------------------------------------------------------------ pen
# * Touch driver: novatek opens the NVTCapacitivePen input only with Touch_Pen_ENABLE set,
#   and the flag must be re-armed after every screen-on.
# * Buttons: pen_keys.sh maps the HID keys to actions (keys.conf).
# * ColorOS only knows OPPO pens: send IPeManager the "pencil present" intent (strings, mac
#   without colons), and while the pen is out of the dock set settings_enable_oppo_pencil so
#   ColorOS's own stylus lock holds 120 Hz (ipePencilRateId in the ROM; the panel senses the
#   pen only at 60/120 Hz). Dock = fuda/reverse_chg_hall4, 0 while docked, meaningful only
#   while the pen is connected over BT.
# * pipa_pen_state "<connected> <docked> <soc>" (or "0") for the pipa helper's pen pill; the
#   soc is the reverse charger's reading, fresh only while docked.
PEN_HALL=/sys/class/power_supply/fuda/reverse_chg_hall4
PEN_SOC=/sys/class/power_supply/wireless/reverse_pen_soc
IOCTL=$MODDIR/xiaomi_touch_ioctl
PEN_LOG=/data/local/tmp/pipa_pen.log

DEVS=
pen_connected() {   # also keeps /proc/bus/input/devices in DEVS for kb_link
    DEVS=$(< /proc/bus/input/devices)
    case $DEVS in *'Name="Xiaomi Smart Pen"'*) return 0 ;; esac
    return 1
}
pen_docked() { h=; read -r h < "$PEN_HALL" 2>/dev/null; [ "$h" = 0 ]; }
pen_mac() {
    awk '/^\[/ { m = $0 } /^Name = Xiaomi Smart Pen$/ { m = substr(m, 2, length(m) - 2); gsub(/:/, "", m); print tolower(m); exit }' \
        /data/misc/bluedroid/bt_config.conf 2>/dev/null
}
pen_present() {
    am startservice --user 0 -a com.oplus.ipemanager.action.PENCIL_STATUS_CHANGE \
        -p com.oplus.ipemanager --es present "$1" --es macAddr "$(pen_mac)" --es pencilId 1 >/dev/null 2>&1
    log "pen present=$1"
}
# ColorOS live-alert pen capsule (2p: IPeManager patched by maintainer/ipe-fluid/patch_ipemanager.py, which shows its
# fluid-cloud battery card on a present event, with the level from ipe_pencil_battery_level). Shown on dock and undock;
# the capsule hides by itself after a few seconds. pipa_pen_fluid=1 tells the pipa helper to skip its own pill.
pen_fluid() {
    [ "${PEN_FLUID:-1}" = 1 ] || return 0
    case $1 in ''|*[!0-9]*) ;; *) settings put global ipe_pencil_battery_level "$1" </dev/null >/dev/null 2>&1 ;; esac
    pen_present 1
}
LOCK=
pen_lock() {   # cached: no settings call unless the state changes
    [ "$LOCK" = "$1" ] && return
    settings put global settings_enable_oppo_pencil "$1"
    LOCK=$1
    log "pen stylus lock -> $1"
}
pen_wake() {
    ok=1
    for i in 1 2 3; do
        "$IOCTL" pen on >/dev/null 2>&1 || ok=0
        sleep 0.5
    done
    echo "$(date) pen on applied ok=$ok" >> "$PEN_LOG"
    [ $ok = 1 ]
}
pen_keys_alive() {   # mksh drops the NUL bytes of cmdline: "sh/system_ext/pipa_port/pen_keys.sh"
    p=; read -r p < /data/local/tmp/pipa_pen_keys.pid 2>/dev/null
    [ -n "$p" ] && [ -r "/proc/$p/cmdline" ] || return 1
    case $(< "/proc/$p/cmdline") in *pen_keys.sh*) return 0 ;; esac
    return 1
}
pen_keys_start() {
    pen_keys_alive && return
    for p in $(pgrep -f 'getevent -lt /dev/input'); do kill -9 "$p" 2>/dev/null; done
    nohup sh "$MODDIR/pen_keys.sh" >/dev/null 2>&1 &
    echo "$(date) started pen_keys.sh" >> "$PEN_LOG"
}

[ "${PEN_WATCH:-1}" = 1 ] && pen_lock 0   # left over from a reboot with the pen out

# ------------------------------------------------------------------ main loop
# 1 s while the screen is on (an undocked pen must work at once), 5 s while it is off.
armed=0; conn=; pub=; tick=0; resend=2; ct=0; dk=; KB_DEVS=-
settings put global pipa_pen_fluid "${PEN_FLUID:-1}" </dev/null >/dev/null 2>&1
while true; do
    if ! screen_on; then
        armed=0
        nap 5
        continue
    fi
    if [ "${PEN_WAKE:-1}" = 1 ] && [ $armed = 0 ] && [ -x "$IOCTL" ]; then
        pen_wake && armed=1
    fi
    [ "${FACE_HAL:-1}" = 1 ] && face_rotation_sync
    [ "${LID_SYNC:-1}" = 1 ] && lid_check
    [ "${ANIM_TIER:-1}" = 1 ] && anim_check
    if [ "${PEN_WATCH:-1}" = 1 ]; then
        if pen_connected; then c=1; else c=0; fi
        # At boot ColorOS's pen manager is not ready at once (an early message was sometimes ignored and
        # Settings showed the stylus as not connected), so the first "connected" goes out once, 40 s after the
        # service start. Since 2p each present=1 also shows the live-alert capsule: one message, not three.
        # Later changes (Bluetooth connect/disconnect) go out at once.
        if [ "$c" != "$conn" ]; then
            if [ -z "$conn" ] && [ $c = 1 ]; then resend=0; ct=$tick; else pen_present $c; resend=2; fi
            conn=$c
        fi
        if [ $c = 1 ] && [ $resend = 0 ] && [ $((tick - ct)) -ge 40 ]; then pen_present 1; resend=2; fi
        if [ $c = 1 ]; then
            if pen_docked; then d=1; pen_lock 0; else d=0; pen_lock 1; fi
            soc=; read -r soc < "$PEN_SOC" 2>/dev/null
            p="1 $d $soc"
            [ -n "$dk" ] && [ "$d" != "$dk" ] && pen_fluid "$soc"
            dk=$d
        else
            p=0; pen_lock 0; dk=
        fi
        if [ "$p" != "$pub" ]; then settings put global pipa_pen_state "$p"; pub=$p; fi
    fi
    if [ $((tick % 3)) = 0 ]; then
        [ "${PEN_KEYS:-1}" = 1 ] && pen_keys_start
        # kb_link runs awk + readlink: only when the input device list changed
        [ "${PEN_WATCH:-1}" = 1 ] || DEVS=$(< /proc/bus/input/devices)
        if [ "${KB_EVENT_LINK:-1}" = 1 ] && [ "$DEVS" != "$KB_DEVS" ]; then kb_link; KB_DEVS=$DEVS; fi
        [ "${KEYBOARD_GUARD:-1}" = 1 ] && [ -e "$KB_HALL" ] && kb_guard
    fi
    if [ $((tick % 15)) = 0 ]; then
        # 4 sget reads (`settings get` processes): only after a change of the system settings file
        if ! [ -e "$SYS_STAMP" ] || [ "$SYS_XML" -nt "$SYS_STAMP" ]; then : > "$SYS_STAMP"; remember_display; fi
        [ "${FACE_HAL:-1}" = 1 ] && [ $tick -gt 15 ] && ! face_running && face_start
        [ "${SYSTEM_UX:-1}" = 1 ] && [ -w "$UX_TASK" ] && system_ux
        nandswap_dedup
    fi
    tick=$((tick + 1))
    nap 1
done
