#!/system/bin/sh
# pipa_port runtime (after boot), started by init (/system_ext/etc/init/pipa_port.rc) as the
# pipa_port service. Started as the pipa_port module v1.3, with ROM paths: code read-only in
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

# Maintainer test builds only (optional step 5s sets ro.pipa.maintainer_adb=1 next to the host's adb key): ColorOS
# turns USB to charge-only at the first setup, so turn USB debugging on here. Release builds do not have the property.
if [ "$(getprop ro.pipa.maintainer_adb)" = 1 ]; then
    for i in 1 2 3 4 5 6; do
        settings put global development_settings_enabled 1 </dev/null >/dev/null 2>&1
        settings put global adb_enabled 1 </dev/null >/dev/null 2>&1
        [ "$(getprop init.svc.adbd)" = running ] && break
        sleep 5
    done
    log "maintainer build: adb_enabled=1 (adbd $(getprop init.svc.adbd))"
fi

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
    # builtin check first: while the last system_server pid is alive, no pidof process (every 15 s)
    if [ -n "${SS_PID:-}" ] && [ -r "/proc/$SS_PID/cmdline" ]; then
        case $(< "/proc/$SS_PID/cmdline") in system_server*) return ;; esac
    fi
    p=$(pidof system_server) || return
    [ "$p" = "$SS_PID" ] && return
    for d in /proc/$p/task/*; do   # builtin read: one cat per thread (~300) took ~6 s at each start (3v)
        n=; read -r n < "$d/comm" 2>/dev/null
        case "$n" in
            android.anim|android.display|android.ui) echo "p ${d##*/} 132" > "$UX_TASK" 2>/dev/null ;;
        esac
    done
    SS_PID=$p
    log "system_server $p: android.anim/display/ui -> UX"
}
[ "${SYSTEM_UX:-1}" = 1 ] && [ -w "$UX_TASK" ] && system_ux

# ------------------------------------------------------------ full AOT compile of the UI apps
# bg-dexopt compiles speed-profile (hot methods only); first showings (QS panel, Settings, launcher) then run partly
# interpreted. dalvik.vm.systemuicompilerfilter=speed (product build.prop) keeps SystemUI at speed in later dexopts;
# compile them 3 minutes after boot, in the background, when ART does not report status=speed. ART does not downgrade a
# speed compile in bg-dexopt. 4y (2026-11-03): the check was "fingerprint + system_ext date changed", but port builds
# keep both (donor values), so no build after pt28 compiled: SystemUI, launcher and Settings ran from the APK (JIT) after
# each dirty flash (launch test: launcher janky frames 35 % -> 16 % after the compile). Now the check reads the ART
# state of each app (`pm art dump` into a file: no pipes in this domain).
speed_compile() {
    sleep 180
    for p in ${SPEED_APPS:-com.android.systemui com.android.settings com.oplus.wirelesssettings com.android.launcher}; do
        pm art dump "$p" </dev/null >"$SGET_F.art" 2>/dev/null
        if grep -q 'arm64: \[status=speed\]' "$SGET_F.art" 2>/dev/null; then continue; fi
        cmd package compile -m speed -f "$p" </dev/null >/dev/null 2>&1 && log "compiled $p (speed)"
    done
    rm -f "$SGET_F.art"
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
# facehal-rs runs from its /data copy (/data/misc/pipa_port/facehal, face_install) with LD_LIBRARY_PATH: from /vendor/lib64
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
    # 5n: libpipa_camguard refuses the worker's window=standard fallback (an ANativeWindow given to the vendor camera
    # NDK, which wants a native handle: SIGABRT in a dark room) with an error code (src/camguard.c)
    [ -f "$FACE/lib64/libpipa_camguard.so" ] && pre=$pre:$FACE/lib64/libpipa_camguard.so
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

# --------------------------------------------------------------- touch shim
# 4o (BUGS-TODO 51): no vendor.oplus.hardware.touch.IOplusTouch on pipa. TouchHost (maintainer/touchshim) maps the
# OPPO touch nodes for game mode, sensitivity, edge rejection and direction to Xiaomi touch modes through
# xiaomi_touch_ioctl; the registrar adds it through a cross-process proxy, as for the charger.
# 4r: with "touch" in HAL_SHIMS the shared HAL host serves it (one app_process less); this block is then skipped.
HAL_SHIMS=$(printf '%s' "${HAL_SHIMS:-}" | tr -d ' \t\r')
case ",${HAL_SHIMS:-}," in *,touch,*) [ -f $MODDIR/halshims.jar ] && TOUCH_SHIM=0 ;; esac
start_touch_loop() {
    [ -f $MODDIR/touchshim.jar ] || return 0
    pgrep -f pipa.touch.TouchHost >/dev/null 2>&1 && return 0
    (
        sleep 4
        L=/data/local/tmp/touchshim.log
        while true; do
            ( sleep 3; CLASSPATH=$MODDIR/touchshim.jar app_process /system/bin pipa.touch.TouchHost register >> $L 2>&1 ) &
            CLASSPATH=$MODDIR/touchshim.jar app_process /system/bin pipa.touch.TouchHost >> $L 2>&1
            echo "$(date) touch shim host exited, restart in 5s" >> $L
            sleep 5
        done
    ) &
}
[ "${TOUCH_SHIM:-1}" = 1 ] && start_touch_loop

# ----------------------------------------------------------------- HAL shims
# 4r: own-code OPPO HAL shims (maintainer/halshims) in ONE host process (HAL_SHIMS = comma list of gameopt, panel,
# misc, touch): gameopt gives game key threads sched_assist UX and resets it; panel and misc answer like the donor
# HALs; touch is the 4o touch shim (built into the same jar).
# The registrar adds the official names through a cross-process proxy, as for the charger and touch shims, and
# leaves a name alone that already has a server.
if [ -n "${HAL_SHIMS:-}" ] && [ -f $MODDIR/halshims.jar ] && ! pgrep -f pipa.hal.HalHost >/dev/null 2>&1; then
    (
        sleep 4
        L=/data/local/tmp/halshims.log
        quick=0
        while [ $quick -lt 5 ]; do
            ( sleep 3; CLASSPATH=$MODDIR/halshims.jar app_process /system/bin pipa.hal.HalHost register "$HAL_SHIMS" >> $L 2>&1 ) &
            t0=$(date +%s)
            CLASSPATH=$MODDIR/halshims.jar app_process /system/bin pipa.hal.HalHost host "$HAL_SHIMS" >> $L 2>&1
            if [ $(( $(date +%s) - t0 )) -lt 60 ]; then quick=$((quick + 1)); else quick=0; fi
            echo "$(date) HAL shim host exited ($quick quick exits), restart in 5s" >> $L
            sleep 5
        done
        echo "$(date) HAL shim host: 5 quick exits, stopped (see the lines above)" >> $L
        # touch was served by this host: fall back to the stand-alone touch shim (4o)
        case ",$HAL_SHIMS," in *,touch,*) echo "$(date) starting the stand-alone touch shim" >> $L; start_touch_loop ;; esac
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
# beta8: OPPO's secure keyboard for password fields off, once per install (user, 2026-11-05). CN builds default to on,
# export builds to off (Settings SettingsUtils.isDefaultCloseSecurityKeyboard = isExpVersion). Key Settings.Secure
# security_window, read by Settings and oplus-services; 0 = password fields use the normal keyboard (Gboard etc.).
# The user can turn it on again: Settings > Additional settings > Keyboard & input method > Secure keyboard.
if [ "${SECURE_KEYBOARD_OFF:-1}" = 1 ] && [ ! -e "$STATE/secure_keyboard_off_set" ]; then
    settings put secure security_window 0 </dev/null >/dev/null 2>&1
    touch "$STATE/secure_keyboard_off_set"
    log "secure keyboard for passwords off (security_window=0, once)"
fi
# 2q smoothness defaults, once per install (state file; the user can change them back in Developer options):
# window blur off (SurfaceFlinger forces GPU composition of every layer below a blur: A/B -25 % dropped frames,
# -35 % GPU misses); material blur and contour glow on since 5t. Animation scales stay at 1.0 since 2s (user choice).
if [ "${SMOOTH_DEFAULT:-1}" = 1 ] && [ ! -e "$STATE/smooth_default_set" ]; then
    {
        settings put global disable_window_blurs 1
        # Visual blur + Contour glow ON (5t, user 2026-11-05: tier 3 + blur + contour glow; 5g measured no cost at
        # tier 3). The 2q "material blur off" default (launcher jank -40 %) was from before tier 3 and 5g.
        settings put system system_material_blur_enable 1
        settings put system system_material_stroke_enable 1
        # ColorOS writes animationBlurrySwitch=1 itself on a first boot (before BLUR_DEFAULT sees "null"), 2v
        settings put system animationBlurrySwitch 0
        # The nanosic driver always registers "Xiaomi Keyboard" input devices, so Android thinks a hardware keyboard is
        # attached and hides the on-screen keyboard (clean flash, 2026-10-25). Keep it visible; with the real
        # keyboard cover the user can switch it off (Settings: on-screen keyboard while a physical one is active).
        settings put secure show_ime_with_hard_keyboard 1
    } </dev/null >/dev/null 2>&1
    touch "$STATE/smooth_default_set"
    log "first-boot defaults: window blur off, visual blur + contour glow on, animation blur off, on-screen keyboard on"
fi
# beta7.1 (user 2026-11-05): "Fast" animations (tier 3) + Visual blur + Contour glow once on EVERY install, also on a dirty
# flash from beta6/beta7 (2q had set material blur 0 at their first boot, and ColorOS hid the switch at tier 3). The
# user can change all three again (Animations tile, Personalization > More > Textured visual effects).
# SystemUI and the launcher read the blur setting at their start: restart both once when something changed (dirty
# flash). A clean flash has the same values already (first-boot defaults above): no restart.
if [ "${BLUR_TIER_ONCE:-1}" = 1 ] && [ ! -e "$STATE/blur_tier_71_set" ]; then
    old="$(sget global pipa_anim_level) $(sget system system_material_blur_enable) $(sget system system_material_stroke_enable)"
    {
        settings put global pipa_anim_level 3
        settings put system system_material_blur_enable 1
        settings put system system_material_stroke_enable 1
    } </dev/null >/dev/null 2>&1
    touch "$STATE/blur_tier_71_set"
    case "$old" in
        "null 1 1"|"3 1 1") log "beta7.1 once: Fast + visual blur + contour glow already set" ;;
        *)  kill -9 $(pidof com.android.systemui) 2>/dev/null
            am force-stop com.android.launcher </dev/null >/dev/null 2>&1
            am start -a android.intent.action.MAIN -c android.intent.category.HOME </dev/null >/dev/null 2>&1
            log "beta7.1 once: animations Fast (tier 3), visual blur + contour glow on (was: $old); SystemUI + launcher restarted" ;;
    esac
fi
# 4g Circle to Search (BUGS-TODO 49): the gesture-bar long press starts the default assistant; the pipa helper's
# ACTION_ASSIST activity starts Circle to Search through the contextual_search service. Once per install, and only when
# the Google app is installed (else there is no Circle to Search); the user can choose another assistant later.
# 5u: also after the bundled install (below) and every 5 minutes until the Google app is there (a clean flash had no
# Google app at boot, so the check never ran again).
cts_assistant() {
    [ "${CTS_ASSISTANT:-1}" = 1 ] && [ ! -e "$STATE/cts_assistant_set" ] || return 0
    pm path com.google.android.googlequicksearchbox </dev/null >/dev/null 2>&1 || return 1
    cmd role add-role-holder android.app.role.ASSISTANT com.port.pipa.helper 0 </dev/null >/dev/null 2>&1 && \
        touch "$STATE/cts_assistant_set" && log "Circle to Search: pipa helper is the default assistant"
}
cts_assistant
# 4l Quick Share (BUGS-TODO 53): the ROM no longer declares cn.google.services, so GMS treats the tablet as a
# global device. GMS disabled its Quick Share components while the flag was there (dirty flash from 4k or older):
# turn the 13 core ones on once; GMS manages them after that (it turned its Samsung-only and migration screens off
# again by itself in the live test, 2026-11-02). `pm enable` from this domain works (tested with runcon).
QS_PARTS="ReceiveSurfaceService main.MainActivityUnifiedAlias DirectShareService SharingSliceProvider
NotificationActionActivity GcmBroadcastReceiver main.MainActivity SharingTileService SharingSyncService
RemoteCopyShareSheetActivity main.SettingsMainActivity receive.ReceiveActivity suw2.SetupWizardActivity"
if [ "${QUICK_SHARE:-1}" = 1 ] && [ ! -e "$STATE/quick_share_set" ] && \
   pm path com.google.android.gms </dev/null >/dev/null 2>&1; then
    for c in $QS_PARTS; do
        pm enable "com.google.android.gms/com.google.android.gms.nearby.sharing.$c" </dev/null >/dev/null 2>&1
    done
    touch "$STATE/quick_share_set" && log "Quick Share: GMS components enabled once"
fi
# 5b external display (BUGS-TODO 54): ColorOS extends to a USB-C monitor (own screen with taskbar) instead of a mirror.
# The ROM sets persist.wm.debug.enforce_display_extended_mode (the ColorOS mode needs >= 12 GB RAM or that prop);
# Android mirrors while Settings.Secure mirror_built_in_display is 1. Once per install; the user can set it back.
if [ "${EXT_DISPLAY:-1}" = 1 ] && [ ! -e "$STATE/ext_display_set" ]; then
    settings put secure mirror_built_in_display 0 </dev/null >/dev/null 2>&1 && \
        touch "$STATE/ext_display_set" && log "external display: extend (mirror_built_in_display 0) once"
fi
# 4k OShare: the ROM copy is patched (tablet -> OPPO phone without the interconnect). An OPPO App Market update
# installs an unpatched copy in /data/app; remove the update, so the patched ROM copy is used again.
if [ "${OSHARE_ROLLBACK:-1}" = 1 ]; then
    : > "$SGET_F"
    pm path com.coloros.oshare </dev/null >"$SGET_F" 2>/dev/null
    if grep -q '^package:/data/' "$SGET_F"; then
        pm uninstall-system-updates com.coloros.oshare </dev/null >/dev/null 2>&1
        log "OShare: an app update replaced the patched ROM copy (4k); update removed"
    fi
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
# The marker holds the versionCode of the bundled APK (empty file = 2w-3o, 4.2.1-r1). A newer bundled manager (a new
# kernel needs it) is installed over an older one; a newer manager that the user installed stays.
# pt58: on a clean flash the first `pm install` (about 90 s after boot, 1 s after user 0 unlock, setup wizard open)
# failed and the next try was only at the next boot. Now the main loop tries again every 60 s (screen on, at most 30 tries), and pm's message
# goes to the log.
KSU_WANT=$(cat "$MODDIR/SukiSU.version" 2>/dev/null)
KSU_TRY=0
ksu_manager() {
    [ "$(cat "$STATE/ksu_manager_set" 2>/dev/null)" != "$KSU_WANT" ] || return 0
    KSU_TRY=$((KSU_TRY + 1))
    : > "$SGET_F"
    pm list packages --show-versioncode com.sukisu.ultra </dev/null >"$SGET_F" 2>/dev/null
    have=$(sed -n 's/^package:com\.sukisu\.ultra versionCode:\([0-9]*\).*/\1/p' "$SGET_F")
    if [ -n "$have" ] && [ "$have" -ge "$KSU_WANT" ]; then
        echo "$KSU_WANT" > "$STATE/ksu_manager_set"
        log "SukiSU manager $have already installed"
    elif pm install -r "$MODDIR/SukiSU.apk" </dev/null >"$SGET_F" 2>&1; then
        echo "$KSU_WANT" > "$STATE/ksu_manager_set"
        log "SukiSU manager ${have:-none} -> $KSU_WANT installed (try $KSU_TRY)"
    else
        log "SukiSU manager install failed (try $KSU_TRY): $(tail -n 1 "$SGET_F" 2>/dev/null)"
        return 1
    fi
}
KSU_RETRY=0
if [ "${KSU_MANAGER:-1}" = 1 ] && [ -f "$MODDIR/SukiSU.apk" ] && [ -n "$KSU_WANT" ]; then
    ksu_manager || KSU_RETRY=1
fi

# 5u: Play Store, Gboard and the Google app (Circle to Search) as normal apps / updates, once per install (user
# 2026-11-05). The APKs (base + splits, stable versions from Play) are in $MODDIR/apps/<package>/ with the versionCode
# in "version"; Play Store updates them later (same Google signature). The ROM's Play Store is only an old updater stub
# (my_product GooglePlayServicesUpdater, 82275402; before, the OPPO App Market had to install the real one), so an
# older installed version is updated; the same or a newer one is not touched. An app the user uninstalls is not
# installed again (state file). Gboard becomes the default keyboard after its install. Retried like the manager.
APPS_DIR=$MODDIR/apps
GBOARD=com.google.android.inputmethod.latin
GBOARD_IME=$GBOARD/com.android.inputmethod.latin.LatinIME
APPS_TRY=0
bundled_apps() {
    [ -d "$APPS_DIR" ] || return 0
    rc=0
    for d in "$APPS_DIR"/*; do
        [ -d "$d" ] || continue
        pkg=${d##*/}
        [ -e "$STATE/app_$pkg" ] && continue
        want=$(cat "$d/version" 2>/dev/null)
        : > "$SGET_F"
        pm list packages --show-versioncode "$pkg" </dev/null >"$SGET_F" 2>/dev/null
        have=$(sed -n "s/^package:$pkg versionCode:\([0-9]*\).*/\1/p" "$SGET_F")
        if [ -n "$have" ] && [ -n "$want" ] && [ "$have" -ge "$want" ]; then
            touch "$STATE/app_$pkg"
            log "$pkg $have already installed"
            continue
        fi
        APPS_TRY=$((APPS_TRY + 1))
        if pm install -r "$d"/*.apk </dev/null >"$SGET_F" 2>&1; then
            touch "$STATE/app_$pkg"
            log "$pkg ${have:-none} -> $want installed (try $APPS_TRY)"
            if [ "$pkg" = "$GBOARD" ]; then
                # `ime` cannot find input_method in the pipa_port domain (no service_manager rule): use the settings,
                # which InputMethodManagerService follows (tested in the domain with runcon, 2026-11-05).
                # Default only over ColorOS's own keyboard (Sogou) or none: a dirty flash keeps the user's keyboard.
                case "$(sget secure default_input_method)" in
                    null|com.sohu.inputmethod.sogouoem/*)
                        cur=$(sget secure enabled_input_methods)
                        case ":$cur:" in
                            *":$GBOARD_IME:"*|*":$GBOARD_IME;"*) ;;
                            *) [ "$cur" = null ] && cur=$GBOARD_IME || cur="$cur:$GBOARD_IME"
                               settings put secure enabled_input_methods "$cur" </dev/null >/dev/null 2>&1 ;;
                        esac
                        settings put secure default_input_method "$GBOARD_IME" </dev/null >/dev/null 2>&1 && \
                            log "Gboard is the default keyboard" ;;
                    *) log "Gboard installed; the user's default keyboard stays" ;;
                esac
            fi
        else
            log "$pkg install failed (try $APPS_TRY): $(tail -n 1 "$SGET_F" 2>/dev/null)"
            rc=1
        fi
    done
    return $rc
}
APPS_RETRY=0
[ "${BUNDLED_APPS:-1}" = 1 ] && { bundled_apps || APPS_RETRY=1; }
cts_assistant

# ------------------------------------------------- colour / adaptive / bedtime
# ColorOS re-applies Vivid (256) at boot, and the Eye Protect app resets adaptive colour and
# Bedtime (it checks OPPO's CCT sensor type, not the rerouted Xiaomi one). Remember the
# user's choice in the loop below and put it back once here.
COLOR_STATE=$STATE/color_mode
ADAPTIVE_STATE=$STATE/adaptive_state
BEDTIME_STATE=$STATE/bedtime_state   # + .<key>: one file per Bedtime key (5i); the old combined file is removed
rm -f "$BEDTIME_STATE"
# In the background (3v): the main loop (pen, keyboard guard, lid) starts at once, not 15 s later. The loop saves
# the display choice only after this restore ($DISP_DONE), so the boot reset is never saved as the user's choice.
DISP_DONE=$STATE/display.restored
rm -f "$DISP_DONE"
(
SGET_F=$SGET_F.restore   # own file: the main loop also uses sget
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
    # Each Bedtime key is restored on its own (5i). Before, "either key is 1" set both keys to 1: the Settings
    # switch writes only comfortable_rhythm, so the restored rhythm_health stayed 1 and the Eye Protect app
    # switched Bedtime on again each time the user left its page (user 2026-11-04).
    for k in oplus_customize_rhythm_health_enable oplus_customize_comfortable_rhythm_enable; do
        [ "$(cat "$BEDTIME_STATE.$k" 2>/dev/null)" = 1 ] || continue
        [ "$(sget system $k)" = 1 ] || { settings put system $k 1; log "bedtime $k restored"; }
    done
fi
rm -f "$SGET_F"
: > "$DISP_DONE"
) &

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
        for k in oplus_customize_rhythm_health_enable oplus_customize_comfortable_rhythm_enable; do
            bt=$(sget system $k)
            case "$bt" in 0|1) [ "$bt" = "$(cat "$BEDTIME_STATE.$k" 2>/dev/null)" ] || echo "$bt" > "$BEDTIME_STATE.$k" ;; esac
        done
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
                # each zygote restart attaches one more 8 GB swap file (its file is deleted but stays open: the
                # space is gone). Before 3r the policy had no sys_admin: swapoff failed, the log still said "removed".
                if [ $n -gt 1 ]; then
                    if swapoff "$dev" 2>/dev/null && losetup -d "$dev" 2>/dev/null; then
                        log "nandswap: removed duplicate swap $dev"
                    elif [ "$NANDSWAP_FAIL" != "$dev" ]; then
                        log "nandswap: cannot remove duplicate swap $dev"; NANDSWAP_FAIL=$dev
                    fi
                fi ;;
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
# Xiaomi thermal scene (5l). mi_thermald picks its profile from thermal_message/sconfig; on HyperOS PowerKeeper sets
# it, on ColorOS nobody does (-1 = daily profile: CPU caps from 38 C skin). The helper sets global pipa_game_fg = 1
# while an app with appCategory "game" is in the foreground; then the game profile GAME_THERMAL_SCENE is used
# (measured 2026-11-04: 20 = no CPU caps below 46 C skin, 13 = below 48 C, 10 = below 51 C). Screen off = daily.
SCONFIG=/sys/devices/virtual/thermal/thermal_message/sconfig   # real path: /sys/class/thermal/... is a sysfs symlink
GAME_STAMP=/data/misc/pipa_port/game.stamp
rm -f "$GAME_STAMP"
GAME_SC=
game_scene() {   # $1 = scene; builtin echo only
    [ "$1" = "$GAME_SC" ] && return
    echo "$1" > "$SCONFIG" 2>/dev/null || return
    GAME_SC=$1
    log "thermal scene -> $1"
}
game_check() {
    [ -e "$GAME_STAMP" ] && ! [ "$GLOBAL_XML" -nt "$GAME_STAMP" ] && return
    : > "$GAME_STAMP"
    g=$(sget global pipa_game_fg) || return
    if [ "$g" = 1 ]; then game_scene "${GAME_THERMAL_SCENE:-20}"; else game_scene -1; fi
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
    # getprop is a process: only when the wanted state changes, and every 60 screen-on seconds to catch a start or
    # stop from outside (was every 3 s, ~1200 processes an hour with the screen on)
    [ "$want" = "${KB_WANT:-}" ] && [ $((tick - ${KB_CHECKED:-0})) -lt 60 ] && return
    KB_WANT=$want; KB_CHECKED=$tick
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
PEN_HALL3=/sys/class/power_supply/fuda/reverse_chg_hall3   # second dock magnet (pen the other way round)
PEN_SOC=/sys/class/power_supply/wireless/reverse_pen_soc
IOCTL=$MODDIR/xiaomi_touch_ioctl
PEN_LOG=/data/local/tmp/pipa_pen.log

DEVS=
pen_connected() {   # also keeps /proc/bus/input/devices in DEVS for kb_link
    DEVS=$(< /proc/bus/input/devices)
    case $DEVS in *'Name="Xiaomi Smart Pen"'*) return 0 ;; esac
    return 1
}
pen_docked() { h=; h3=; read -r h < "$PEN_HALL" 2>/dev/null; read -r h3 < "$PEN_HALL3" 2>/dev/null; [ "$h" = 0 ] || [ "$h3" = 0 ]; }
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

# ------------------------------------------------------------------ charge hold
# 3z (BUGS-TODO 50): ColorOS "Custom charging limit" and "Smart charging" send setChgConfig to the OPPO charger HAL,
# and the OPPO kernel holds the level. The charger shim only records the calls in /data/misc/pipa_port:
#   chg_cfg14 = "2++<on>+<level>" (charging limit; UI test 2026-11-02: "2++1+90" on, "2++0+90" off)
#   chg_cfg5  = "4++<stop>+<level>+<mode>+<level>" (Battery app SmartChargeProtectionController: stop 1 = hold,
#               0 = release; mode 0 = smart charging (level 80; the app releases by alarm before the predicted
#               unplug time, from OplusDeepThinker), mode 1 = charging limit). Only <stop> starts a hold.
# Here: stop charging at the lowest active level with battery_charging_enabled=0 (the tablet runs from the charger,
# the battery level stays), charge again at <level>-3.
# 4p bypass charging (notes/cloud/CHARGER-HAL.md section E): the Battery app (BypassChargeController) sends
#   chg_cfg25 = "1+switch=1" (switch on, plugged, level >= its threshold, screen on) and "1+switch=0" (screen off,
#   unplug, below the threshold, boot). The shim returns 1, so the app sends switch=1 again every 180 s.
#   Bypass is NOT battery_charging_enabled=0: with charging off the smb5 runs the tablet mostly from the battery
#   (wall PD charger 2026-11-03: input 0.2-0.4 A, battery still +0.45 A, = unplugged). Bypass = charging on with the
#   charge current capped by qcom-battery restrict_chg/restrict_cur at 100 mA (the smallest cap that keeps the input
#   on; 0 and 50 mA cut the input too): the charger powers the tablet, the battery takes <= 0.1 A.
#   A chg_cfg25 older than 5-10 min (awake time) is a dead app: ignored.
#   Safety: charge below 15 %, and (4w) no bypass cap again before 20 %. Unplugged (usb/present 0): charging enabled again, so the next plug-in charges.
# Every 5 s, also with the screen off; only builtins (read, test -nt, : >).
CHG_EN=/sys/class/power_supply/battery/battery_charging_enabled
CHG_CAP=/sys/class/power_supply/battery/capacity
CHG_IN=/sys/class/power_supply/usb/present   # not online: a PC port gives online 0 (pc_port is online), present 1
CHG_REF=$STATE/chg_ref   # chg_ref0/1: rewritten in turn every 300 ticks; the older one is the freshness limit
: > "${CHG_REF}0" 2>/dev/null; : > "${CHG_REF}1" 2>/dev/null; chg_par=0
CHG_RC=/sys/class/qcom-battery/restrict_chg
CHG_RI=/sys/class/qcom-battery/restrict_cur
CHG_BYPASS_UA=100000
# chg_held: 0 = normal, 1 = charging off (charge limit), 2 = charge current capped (bypass)
chg_low=0   # 4w: 1 = the level was below 15 %: no bypass cap before 20 %
chg_held=0; v=; read -r v < "$CHG_EN" 2>/dev/null; [ "$v" = 0 ] && chg_held=1
chg_ri=; read -r chg_ri < "$CHG_RI" 2>/dev/null
v=; read -r v < "$CHG_RC" 2>/dev/null
if [ "$v" = 1 ] && [ "$chg_ri" = "$CHG_BYPASS_UA" ]; then chg_held=2; chg_ri=1000000; fi   # our cap from before a restart
chg_uncap() { echo 0 > "$CHG_RC"; [ -n "$chg_ri" ] && echo "$chg_ri" > "$CHG_RI"; }
chg_capon() { read -r chg_ri < "$CHG_RI" 2>/dev/null; echo "$CHG_BYPASS_UA" > "$CHG_RI" && echo 1 > "$CHG_RC"; }
chg_limit() {   # <on> <level>: keep the lowest active level in $lim
    case $1 in 1) ;; *) return ;; esac
    case $2 in ""|*[!0-9]*) return ;; esac
    [ "$2" -ge 20 ] && [ "$2" -lt "$lim" ] && lim=$2
}
chg_hold() {
    [ -w "$CHG_EN" ] || return
    local v= c= want=1 why= bp=0 IFS=+
    lim=100
    v=; read -r v 2>/dev/null < "$STATE/chg_cfg25"
    case $v in "1+switch=1"*) [ "$STATE/chg_cfg25" -nt "${CHG_REF}$((1 - chg_par))" ] && bp=1 ;; esac
    v=
    read -r v < "$STATE/chg_cfg14" 2>/dev/null
    case $v in 2++*) set -- ${v#2++}; chg_limit "$1" "$2" ;; esac
    v=; read -r v < "$STATE/chg_cfg5" 2>/dev/null
    case $v in 4++*) set -- ${v#4++}; chg_limit "$1" "$2" ;; esac
    read -r c < "$CHG_CAP" 2>/dev/null
    case $c in ''|*[!0-9]*) return ;; esac
    # limit: above it charging off (the battery drains slowly); at it, or held and less than 3 % below it, the charge
    # current is capped (the charger powers the tablet, the battery takes <= 0.1 A); without the cap node: off
    if [ $lim -lt 100 ]; then
        if [ "$c" -gt $lim ]; then want=0
        elif [ "$c" -ge $lim ] || { [ $chg_held != 0 ] && [ "$c" -gt $((lim - 3)) ]; }; then want=2; fi
        [ $want = 2 ] && [ ! -w "$CHG_RI" ] && want=0
        [ $want != 1 ] && why="limit $lim"
    fi
    # want: 1 = charge, 0 = charging off (limit reached), 2 = bypass (cap); the limit wins over bypass
    # 4w (BUGS-TODO 63): hysteresis. Below 15 % full charge; the bypass cap comes back only at 20 % (before: at
    # 15 %, so under a game load it switched cap/charge at 14/15 % every few minutes).
    [ "$c" -lt 15 ] && chg_low=1
    [ "$c" -ge 20 ] && chg_low=0
    if [ $want = 1 ] && [ $bp = 1 ] && [ "$c" -ge 15 ] && [ -w "$CHG_RI" ]; then
        if [ $chg_low = 0 ]; then want=2; why=bypass; else why="bypass after low level: charge to 20 %"; fi
    fi
    v=; read -r v 2>/dev/null < "$CHG_IN"
    [ "$v" = 0 ] && want=1 && why=unplugged
    local t=$want; case $want in 1) t=0 ;; 0) t=1 ;; esac   # the chg_held value that this want gives
    [ "$t" = "$chg_held" ] && return
    case $chg_held in 1) echo 1 > "$CHG_EN" ;; 2) chg_uncap ;; esac
    case $want in
        0) echo 0 > "$CHG_EN" && chg_held=1 && log "charge hold: stop at $c % ($why)" ;;
        2) chg_capon && chg_held=2 && log "charge hold: cap at $c % ($why, charge current $CHG_BYPASS_UA uA)" ;;
        *) chg_held=0; log "charge hold: charge again at $c % (${why:-no hold})" ;;
    esac
}

[ "${PEN_WATCH:-1}" = 1 ] && pen_lock 0   # left over from a reboot with the pen out

# ------------------------------------------------------------------ main loop
# 1 s, also while the screen is off: "pen on" goes out at most ~1 s after screen-on (5 s before 3n). The check is
# one builtin read; in suspend the timer does not run, so the shorter sleep costs no wakeups.
armed=0; conn=; pub=; tick=0; resend=2; dk=; KB_DEVS=-
settings put global pipa_pen_fluid "${PEN_FLUID:-1}" </dev/null >/dev/null 2>&1
ctick=0
while true; do
    if [ "${CHARGE_HOLD:-1}" = 1 ]; then
        if [ $((ctick % 300)) = 299 ]; then chg_par=$((1 - chg_par)); : > "${CHG_REF}$chg_par" 2>/dev/null; fi
        [ $((ctick % 5)) = 0 ] && chg_hold
    fi
    ctick=$((ctick + 1))
    if ! screen_on; then
        armed=0
        [ -n "$GAME_SC" ] && [ "$GAME_SC" != -1 ] && { game_scene -1; rm -f "$GAME_STAMP"; }
        nap 1
        continue
    fi
    if [ "${PEN_WAKE:-1}" = 1 ] && [ $armed = 0 ] && [ -x "$IOCTL" ]; then
        pen_wake && armed=1
    fi
    [ "${FACE_HAL:-1}" = 1 ] && face_rotation_sync
    [ "${LID_SYNC:-1}" = 1 ] && lid_check
    [ "${ANIM_TIER:-1}" = 1 ] && anim_check
    if [ $KSU_RETRY = 1 ] && [ $((ctick % 60)) = 0 ]; then
        if ksu_manager; then KSU_RETRY=0; elif [ $KSU_TRY -ge 30 ]; then KSU_RETRY=0; log "SukiSU manager: no more tries"; fi
    fi
    if [ $APPS_RETRY = 1 ] && [ $((ctick % 60)) = 30 ]; then
        if bundled_apps; then APPS_RETRY=0; elif [ $APPS_TRY -ge 30 ]; then APPS_RETRY=0; log "bundled apps: no more tries"; fi
        cts_assistant
    fi
    [ $((ctick % 300)) = 150 ] && [ ! -e "$STATE/cts_assistant_set" ] && cts_assistant
    case "${GAME_THERMAL_SCENE:-20}" in ''|0) ;; *) game_check ;; esac
    if [ "${PEN_WATCH:-1}" = 1 ]; then
        if pen_connected; then c=1; else c=0; fi
        # At boot ColorOS's pen manager is not ready at once (an early message was sometimes ignored and
        # Settings showed the stylus as not connected), so the first "connected" goes out once, 40 s after the
        # service start. Since 2p each present=1 also shows the live-alert capsule: one message, not three.
        # Later changes (Bluetooth connect/disconnect) go out at once.
        if [ "$c" != "$conn" ]; then
            if [ -z "$conn" ] && [ $c = 1 ]; then resend=0; else pen_present $c; resend=2; fi
            conn=$c
        fi
        # The 40 s count from the service start (screen-on seconds), not from the connect: a pen that connects
        # later (first screen-on after boot) gets its message at once, not 40 s later as a "random" capsule.
        if [ $c = 1 ] && [ $resend = 0 ] && [ $tick -ge 40 ]; then pen_present 1; resend=2; fi
        if [ $c = 1 ]; then
            # Two dock halls (hall3, hall4: one for each pen orientation); docked = one of them reads 0. The
            # 2026-10-29 "out for 2 s" capsule came from hall4 alone (pen on the other magnet). "In" counts at
            # once; "out" only when a second read 0.5 s later agrees (was 3 reads = 3-4 s delay, 3u).
            if pen_docked; then d=1; else d=0; fi
            if [ -n "$dk" ] && [ $dk = 1 ] && [ $d = 0 ]; then nap 0.5; pen_docked && d=1; fi
            if [ $d = 1 ]; then pen_lock 0; else pen_lock 1; fi
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
        if [ -e "$DISP_DONE" ] && { ! [ -e "$SYS_STAMP" ] || [ "$SYS_XML" -nt "$SYS_STAMP" ]; }; then : > "$SYS_STAMP"; remember_display; fi
        [ "${FACE_HAL:-1}" = 1 ] && [ $tick -gt 15 ] && ! face_running && face_start
        [ "${SYSTEM_UX:-1}" = 1 ] && [ -w "$UX_TASK" ] && system_ux
        nandswap_dedup
    fi
    tick=$((tick + 1))
    nap 1
done
