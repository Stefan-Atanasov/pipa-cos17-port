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

# 9m (BUGS-TODO 198): persistent error log for Collect logs. The logd RAM buffers (8 MB each, ~25 min) are lost at
# every restart. One logcat reader waits on logd (blocking read, no polling) and keeps priority E and up of the main,
# system and crash buffers (Java crashes, native crash dumps, ANRs) plus Watchdog warnings in
# /data/misc/pipa_logs/err.log (2 MB, 3 rotated copies: ~3 h of errors on a busy tablet). It survives a restart.
# Started before boot_completed, so a crash during boot is in it too. A restart of this service stops the old reader.
ERRLOG=/data/misc/pipa_logs/err.log
if [ "${ERR_LOG:-1}" = 1 ]; then   # ERR_LOG=0 in /data/misc/pipa_port/config.prop turns it off
    o=; read -r o < "$STATE/errlog.pid" 2>/dev/null
    [ -n "$o" ] && tr '\0' ' ' < "/proc/$o/cmdline" 2>/dev/null | grep -q 'pipa_logs/err.log' && kill "$o" 2>/dev/null
    echo "== $(date '+%Y-%m-%d %H:%M:%S') pipa_port start, boot $(cat /proc/sys/kernel/random/boot_id 2>/dev/null)" >> "$ERRLOG"
    # SettingsState (aconfig "invalid flag name" bursts at boot and config sync) and QC2V4l2Codec (one line per frame while screen recording) filled 4 MB in 10 min on a tester boot (2026-11-27): left out
    logcat -b main,system,crash -v threadtime -f "$ERRLOG" -r 2048 -n 3 'Watchdog:W' 'SettingsState:S' 'QC2V4l2Codec:S' '*:E' </dev/null >/dev/null 2>&1 &
    echo $! > "$STATE/errlog.pid"
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
# Since walt-hi3 the kernel does this itself (sched_assist_common.gpu_comp_static=1: SA_GPU_COMPOSITION always true)
# and OPPO's perf HAL (7e) owns the scene like stock, so the userspace pin is skipped there (2026-11-17, plan item 3).
SA_SCENE=/proc/sys/kernel/sched_assist_scene
GCS=/sys/module/sched_assist_common/parameters/gpu_comp_static
if [ "$(cat "$GCS" 2>/dev/null)" = 1 ]; then
    log "gpu_comp_static=1: kernel keeps SurfaceFlinger on big cores, no scene pin"
elif [ "${SF_BIG_CORES:-1}" = 1 ] && [ -w "$SA_SCENE" ]; then
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

face_start() {   # prepares and runs the HAL in the foreground (returns when it exits)
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
    log "facehal started ($cl)"
    LD_PRELOAD=$pre LD_LIBRARY_PATH=$FACE/lib64:$FACE "$FACE_BIN" </dev/null >>/data/local/tmp/facehal.log 2>&1
}

if [ "${FACE_HAL:-1}" = 1 ]; then
    (
        face_install
        sleep 6
        setprop ctl.stop vendor.facehal
        for p in $(pgrep -f android.hardware.biometrics.face-service.facehal); do kill -9 "$p"; done
        sleep 1
        # 110 (2026-11-20): supervisor instead of the 15 s face_running poll of the main loop (getprop + pgrep):
        # the HAL runs in the foreground here and is started again when it exits; a crash loop backs off.
        n=0
        while :; do
            t0=$(date +%s)
            face_start
            r=$?
            [ $(( $(date +%s) - t0 )) -gt 60 ] && n=0
            n=$((n + 1))
            log "facehal exited ($r), restart $n"
            if [ $n -gt 5 ]; then sleep 60; else sleep 2; fi
            setprop ctl.stop vendor.facehal
        done
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
# BUGS 167: the helper's Pen buttons test screen sets global pipa_pen_test 1 while open and 0 when it closes; a reboot
# with the screen open left it at 1 and every pen action went to the (closed) test screen. Nothing is open at boot.
if [ "$(sget global pipa_pen_test)" = 1 ]; then
    settings put global pipa_pen_test 0 </dev/null >/dev/null 2>&1 && log "pipa_pen_test was left at 1 -> 0"
fi
if [ "${STYLUS_BUTTONS_DEFAULT:-1}" = 1 ] && [ "$(sget secure stylus_buttons_enabled)" = null ]; then
    settings put secure stylus_buttons_enabled 1
    touch "$STATE/stylus_default_set"
    log "stylus_buttons_enabled default -> 1"
fi
# 9q (user 2026-11-27): Screen resolution Low (9g) is removed. A tablet left on Low keeps OPPO's forced size 1440x2304
# and density x0.8 in the WindowManager settings with no switch left to undo it: back to High once, same Display size
# (Low 272/296/328 = High 340/370/410). Runs only while OPPO's setting still says Low (2); it then says High (3).
if [ -z "$(getprop ro.oplus.resolution.low)" ] && [ "$(sget secure oplus_customize_screen_resolution_adjust)" = 2 ]; then
    LD=$(sget secure display_density_forced)
    case "$LD" in 272) HD=340 ;; 296) HD=370 ;; 328) HD=410 ;; *) HD= ;; esac
    wm size reset </dev/null >/dev/null 2>&1
    if [ "$HD" = 370 ]; then wm density reset </dev/null >/dev/null 2>&1
    elif [ -n "$HD" ]; then wm density "$HD" </dev/null >/dev/null 2>&1; fi
    settings put secure oplus_customize_screen_resolution_adjust 3 </dev/null >/dev/null 2>&1
    settings put secure oplus_customize_screen_resolution_backup 3 </dev/null >/dev/null 2>&1
    log "screen resolution Low removed: size reset, density $LD -> ${HD:-unchanged}"
fi
# 7m (BUGS 93): Settings > Display size checks the radio from Settings.System display_density_index_manual, an index
# into ro.density.screenzoom. Older builds had other lists (pt82-pt112: 310..450, Standard = index 2; before: the AOSP
# list), so after a dirty flash the saved index can name another size (2 = Large on 340,370,410). Make the index follow
# the real density: no override -> Standard (middle index); an override in the list -> its index; else leave it.
# Only a saved index is touched (never set = Settings uses Standard), and only when it differs.
if [ "${SCREENZOOM_SYNC:-1}" = 1 ]; then
    ZL=$(getprop ro.density.screenzoom)
    ZI=$(sget system display_density_index_manual)
    if [ -n "$ZL" ] && [ "$ZI" != null ]; then
        ZF=$(sget secure display_density_forced)
        ZN=0; ZW=
        for d in $(echo "$ZL" | tr ',' ' '); do
            [ "$d" = "$ZF" ] && ZW=$ZN
            ZN=$((ZN + 1))
        done
        [ "$ZF" = null ] && ZW=$((ZN / 2))
        if [ -n "$ZW" ] && [ "$ZW" != "$ZI" ]; then
            settings put system display_density_index_manual "$ZW" </dev/null >/dev/null 2>&1
            log "display size index $ZI -> $ZW (forced density $ZF, list $ZL)"
        fi
    fi
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
        # (until 6l: show_ime_with_hard_keyboard=1 here, for the phantom "Xiaomi Keyboard" devices of kernels
        # before walt-r7ov; see the keyboard fold block)
    } </dev/null >/dev/null 2>&1
    touch "$STATE/smooth_default_set"
    log "first-boot defaults: window blur off, visual blur + contour glow on, animation blur off"
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
# 7s (helper 2.0): the helper is a VoiceInteractionService now. The role is set again once (remove + add) so the
# system re-reads the helper package and binds the service; skipped when the user chose another assistant.
cts_assistant() {
    [ "${CTS_ASSISTANT:-1}" = 1 ] && [ ! -e "$STATE/cts_assistant_v2" ] || return 0
    pm path com.google.android.googlequicksearchbox </dev/null >/dev/null 2>&1 || return 1
    if [ -e "$STATE/cts_assistant_set" ]; then
        cmd role get-role-holders android.app.role.ASSISTANT </dev/null >"$STATE/role.txt" 2>/dev/null
        if ! grep -qx com.port.pipa.helper "$STATE/role.txt"; then
            touch "$STATE/cts_assistant_v2"; log "assistant: user choice kept ($(cat "$STATE/role.txt"))"; return 0
        fi
        cmd role remove-role-holder android.app.role.ASSISTANT com.port.pipa.helper 0 </dev/null >/dev/null 2>&1
    fi
    cmd role add-role-holder android.app.role.ASSISTANT com.port.pipa.helper 0 </dev/null >/dev/null 2>&1 && \
        touch "$STATE/cts_assistant_set" "$STATE/cts_assistant_v2" && \
        log "assistant: pipa helper (long press: Circle to Search, corner swipe: Gemini)"
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
# 7l (BUGS 127): the same for every other app the port patches (SOTA / store updates would drop the patches).
# 8m: SAU itself (patched so it updates built-in apps).
# The ROM copies also carry raised versionCodes (5r, 7l), so this only fires for an update installed before.
if [ "${OSHARE_ROLLBACK:-1}" = 1 ] && [ "${PATCHED_ROLLBACK:-1}" = 1 ]; then
    for P in com.coloros.oshare com.android.systemui com.android.settings com.android.launcher com.oplus.battery \
             com.oplus.eyeprotect com.oplus.wallpapers com.oplus.ipemanager com.oplus.sau; do
        : > "$SGET_F"
        pm path "$P" </dev/null >"$SGET_F" 2>/dev/null
        if grep -q '^package:/data/' "$SGET_F"; then
            pm uninstall-system-updates "$P" </dev/null >/dev/null 2>&1
            log "$P: an app update replaced the patched ROM copy; update removed (7l)"
        fi
    done
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
# 7u (2026-11-18): SukiSU-Ultra became SukiSU Nova (package com.sukisu.nova, same signing key); the walt-hi9 kernel
# accepts only that package. After the Nova manager is in, the old com.sukisu.ultra manager (dirty flash) is removed
# once: it cannot talk to the new kernel. Our pin and the user's grants are kept by the kernel (/data/adb/ksu).
KSU_WANT=$(cat "$MODDIR/SukiSU.version" 2>/dev/null)
KSU_PKG=com.sukisu.nova
KSU_OLD_PKG=com.sukisu.ultra
KSU_TRY=0
ksu_manager() {
    [ "$(cat "$STATE/ksu_manager_set" 2>/dev/null)" != "$KSU_WANT" ] || return 0
    KSU_TRY=$((KSU_TRY + 1))
    : > "$SGET_F"
    pm list packages --show-versioncode "$KSU_PKG" </dev/null >"$SGET_F" 2>/dev/null
    have=$(sed -n "s/^package:$KSU_PKG versionCode:\([0-9]*\).*/\1/p" "$SGET_F")
    if [ -n "$have" ] && [ "$have" -ge "$KSU_WANT" ]; then
        log "SukiSU manager $have already installed"
    elif pm install -r "$MODDIR/SukiSU.apk" </dev/null >"$SGET_F" 2>&1; then
        log "SukiSU manager ${have:-none} -> $KSU_WANT installed (try $KSU_TRY)"
    else
        log "SukiSU manager install failed (try $KSU_TRY): $(tail -n 1 "$SGET_F" 2>/dev/null)"
        return 1
    fi
    echo "$KSU_WANT" > "$STATE/ksu_manager_set"
    : > "$SGET_F"
    pm list packages "$KSU_OLD_PKG" </dev/null >"$SGET_F" 2>/dev/null
    if grep -qx "package:$KSU_OLD_PKG" "$SGET_F"; then
        if pm uninstall "$KSU_OLD_PKG" </dev/null >/dev/null 2>&1; then
            log "old SukiSU-Ultra manager removed"
        else
            log "old SukiSU-Ultra manager: uninstall failed"
        fi
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
            # 7v (beta9 clean flash 2026-11-18): set the default after the setup wizard (gboard_default).
            [ "$pkg" = "$GBOARD" ] && { touch "$STATE/gboard_pending"; gboard_default || :; }
        else
            log "$pkg install failed (try $APPS_TRY): $(tail -n 1 "$SGET_F" 2>/dev/null)"
            rc=1
        fi
    done
    return $rc
}
# 7v: Gboard as the default keyboard, once, after the setup wizard. During the setup OplusInputMethodCustomizeHelper
# puts its config default (Sogou) back right after our write (beta9 clean flash: Sogou stayed). After
# user_setup_complete=1 the same write stays. Marker gboard_pending: set at the Gboard install; the main loop retries.
gboard_default() {
    [ -e "$STATE/gboard_pending" ] || return 0
    [ "$(sget secure user_setup_complete)" = 1 ] || return 0
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
            settings put secure default_input_method "$GBOARD_IME" </dev/null >/dev/null 2>&1
            [ "$(sget secure default_input_method)" = "$GBOARD_IME" ] || { log "Gboard default: not kept, retry"; return 1; }
            log "Gboard is the default keyboard (after setup)" ;;
        *) log "Gboard installed; the user's default keyboard stays" ;;
    esac
    rm -f "$STATE/gboard_pending"
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

# B7 / BUGS 147: the face enrollment preview rotation (persist.vendor.facehal.rotation) comes from
# libpipa_facecrop (LD_PRELOAD in the HAL): it reads the preview window's transform hint before the first
# frame. The old rotation sync of this service (pidof every 3 s, cmd display while a camera worker ran) set
# it up to 3 s late: the first preview was rotated, or squashed after a flip.

# B14: magnetic case. The hall is a SW_LID switch (gpio_keys hall_key), so Android's lid
# handling works, but PhoneWindowManager only sleeps on close with global lid_behavior=1 and
# SettingsProvider seeds 0 (config_lidControlsSleep=false). ColorOS's own "smart case" switch
# (global device_case_enabled) waits for an OPPO hall sensor pipa lacks, so it does nothing:
# let that switch drive lid_behavior instead.
LIDB=$(sget global lid_behavior)
# Settings are persisted to this file within ~2 s of a change; a stat per second is cheap, a
# sget (`settings get`, a process) is not, so read the switch only when the file changed.
GLOBAL_XML=/data/system/users/0/settings_global.xml
# Launcher animation tier (OplusLauncher reads persist.sys.oplus.anim_level). 3 = wallpaper zoom off and lighter
# interruption handling: SF dropped frames 2.7 -> 0.3 %, GPU deadline misses 116 -> 10 per run (2026-10-24, traced_heavy);
# 2 keeps every parallel-animation path (dropped 1.5 %); 4 = light animations, no full-scene continuity. Tier 3 is fixed
# since helper 1.9 (user 2026-11-18: the Fast/Slow tile is gone; 7p keeps the lock -> home clock animation at tier 3).
# ANIM_LEVEL in /data/misc/pipa_port/config.prop still overrides it (testing); the launcher restarts to apply a change.
ANIM_STAMP=/data/misc/pipa_port/anim.stamp
rm -f "$ANIM_STAMP"
ANIM_FIRST=1
anim_check() {
    [ -e "$ANIM_STAMP" ] && ! [ "$GLOBAL_XML" -nt "$ANIM_STAMP" ] && return
    # helper 2.5 (Pipa Helper > Effects > Animation style): global pipa_anim_level 2/3/4; else the config (3)
    want=$(sget global pipa_anim_level) || return   # a failed read: try again next time
    : > "$ANIM_STAMP"
    case $want in 2|3) ;; *) want=${ANIM_LEVEL:-3} ;; esac   # helper 2.8: Rich 2 / Smooth 3 (a stored Light 4 -> the default)
    case $want in 1|2|3|4) ;; *) want=3 ;; esac
    first=$ANIM_FIRST; ANIM_FIRST=0
    [ "$(getprop persist.sys.oplus.anim_level)" = "$want" ] && return
    setprop persist.sys.oplus.anim_level "$want"
    # 8s (BUGS 165): a change from the helper waits for its Apply button (pipa_fx_restart: SystemUI + launcher restart,
    # fx_check); only the first check after boot (config override) restarts the launcher itself.
    if [ "$first" = 1 ]; then
        am force-stop com.android.launcher </dev/null >/dev/null 2>&1
        am start -a android.intent.action.MAIN -c android.intent.category.HOME </dev/null >/dev/null 2>&1
        log "launcher animation tier -> $want (boot, launcher restarted)"
    else
        log "launcher animation tier -> $want (applied with the helper's Apply or at the next launcher start)"
    fi
}
# Log level (5x, beta7.2, tester report 2026-11-06). Quiet (default): persist.log.tag=I, liblog drops debug and verbose
# lines in the writing process (no logd work, no framework edits; errors, warnings, crashes and ANRs stay). The helper's
# Logs tile (or `settings put global pipa_verbose_logs 1`) switches to Verbose = the property cleared (Android's
# default; "V" would also turn on the isLoggable(VERBOSE) code paths). Per-tag log.tag.<TAG> properties still win.
LOG_STAMP=/data/misc/pipa_port/log.stamp
rm -f "$LOG_STAMP"
log_check() {
    [ -e "$LOG_STAMP" ] && ! [ "$GLOBAL_XML" -nt "$LOG_STAMP" ] && return
    v=$(sget global pipa_verbose_logs) || return   # a failed read: try again next time
    : > "$LOG_STAMP"
    case $v in 1) want= ;; *) want=I ;; esac
    [ "$(getprop persist.log.tag)" = "$want" ] && return
    setprop persist.log.tag "$want"
    log "log level -> ${want:-default (verbose)}"
}
# 7x (user 2026-11-18): live or static shade/Quick Settings blur. The helper tile "Live blur" writes global
# pipa_live_blur (0/1, default 0); SystemUI uses its live MOTION_60 blur only with
# persist.sys.oplus.systemui.dynamic_blur=true (else STATIC: a playing video freezes behind the panel). SystemUI reads it
# once at its start: the change applies after a reboot. Measured: SystemUI janky frames 20 % live vs 4 % static.
BLUR_STAMP=/data/misc/pipa_port/blur.stamp
blur_check() {
    [ -e "$BLUR_STAMP" ] && ! [ "$GLOBAL_XML" -nt "$BLUR_STAMP" ] && return
    v=$(sget global pipa_live_blur) || return   # a failed read: try again next time
    : > "$BLUR_STAMP"
    case $v in 1) want=true ;; *) want=false ;; esac
    [ "$(getprop persist.sys.oplus.systemui.dynamic_blur)" = "$want" ] && return
    setprop persist.sys.oplus.systemui.dynamic_blur "$want"
    log "live blur -> $want (SystemUI uses it after a reboot)"
}
# Pen settings of the helper (2.5), read only when settings_global.xml changed (one builtin test per tick, as
# blur_check; no polling in pen_keys.sh):
# * BUGS 154, Pen > "Pens without Bluetooth": global pipa_pen_always = 1 keeps pen input on in the touch IC, also
#   without a Bluetooth pen (Lenovo Precision Pen and other active pens with no link). Default 0 = stock (6u, as
#   HyperOS: only while the Xiaomi pen is connected). PEN_BT_ONLY=0 in /data/misc/pipa_port/config.prop (the old
#   "pen always on" module) still wins.
# * BUGS 153, Pen > Buttons: global pipa_pen_buttons = "<far_mode> <long_ms> <actions...>" -> the kernel filter
#   (walt-hi12 pipa_pen_buttons.c). double_ms only when a double press has an action (else a short press is instant).
#   pen_keys.sh reads the actions itself at each press.
PEN_BT_CFG=${PEN_BT_ONLY:-1}
PPB=/sys/module/pipa_pen_buttons/parameters
PEN_SET_STAMP=/data/misc/pipa_port/pen_settings.stamp
# kernel hi13+ (nanosic driver). A fixed path: pipa_port may not list /sys/module (a glob found nothing, pt136 test)
KB_SUPER_P=/sys/module/nanosic_driver_v2/parameters/super_alone; [ -e "$KB_SUPER_P" ] || KB_SUPER_P=
rm -f "$PEN_SET_STAMP"
pen_settings_check() {
    [ -e "$PEN_SET_STAMP" ] && ! [ "$GLOBAL_XML" -nt "$PEN_SET_STAMP" ] && return
    v=$(sget global pipa_pen_always) || return   # a failed read: try again next time
    if [ -d "$PPB" ]; then
        c=$(sget global pipa_pen_buttons) || return
        [ "$c" = null ] && c="1 500"   # v9.3: default long press 380 -> 500 ms (BUGS 169)
        set -f; set -- $c; set +f
        case "$1" in 0|1|2|3) [ "$(cat $PPB/far_mode)" = "$1" ] || echo "$1" > $PPB/far_mode ;; esac
        case "$2" in [2-8][0-9][0-9]) [ "$(cat $PPB/long_ms)" = "$2" ] || echo "$2" > $PPB/long_ms ;; esac
        d=0; [ "$1" = 3 ] && { [ "${7:-none}" != none ] || [ "${8:-none}" != none ]; } && d=300
        [ "$(cat $PPB/double_ms)" = "$d" ] || echo "$d" > $PPB/double_ms
    fi
    # BUGS 155: Super key alone -> action only when the user chose one (else stock)
    if [ -n "$KB_SUPER_P" ]; then
        k=$(sget global pipa_kb_super) || return
        case "$k" in null|default) k=0 ;; *) k=1 ;; esac
        [ "$(cat "$KB_SUPER_P")" = "$k" ] || echo "$k" > "$KB_SUPER_P"
    fi
    : > "$PEN_SET_STAMP"
    [ "$conn" = 1 ] && ipe_state 2
    if [ "$PEN_BT_CFG" = 0 ] || [ "$v" = 1 ]; then n=0; else n=1; fi
    [ "$n" = "${PEN_BT_ONLY:-1}" ] && return
    PEN_BT_ONLY=$n
    if [ $n = 0 ]; then
        armed=0; log "pen input: always on (pens without Bluetooth)"
    elif [ "$conn" != 1 ] && [ -x "$IOCTL" ]; then
        "$IOCTL" pen off >/dev/null 2>&1; armed=0
        echo "$(date) pen off (always-on switch off, not connected)" >> "$PEN_LOG"
        log "pen input: only with the Bluetooth pen"
    fi
}
# BUGS 170 (helper 3.0, kernel hi16): pen near mode. The helper sets global pipa_pen_near = 1 while an app of its
# "Apps made for the Xiaomi pen" list is in the foreground (or always, "as on HyperOS"); the kernel then sends a near
# pen press as the page key (near_mode 1), as stock HyperOS. Same gate as game_check: read only when
# settings_global.xml changed. Kernels before hi16 have no near_mode: nothing to do.
PEN_NEAR_STAMP=/data/misc/pipa_port/pen_near.stamp
rm -f "$PEN_NEAR_STAMP"
pen_near_check() {
    [ -e "$PPB/near_mode" ] || return
    [ -e "$PEN_NEAR_STAMP" ] && ! [ "$GLOBAL_XML" -nt "$PEN_NEAR_STAMP" ] && return
    n=$(sget global pipa_pen_near) || return
    : > "$PEN_NEAR_STAMP"
    case "$n" in 1) ;; *) n=0 ;; esac
    [ "$(cat $PPB/near_mode)" = "$n" ] && return
    echo "$n" > $PPB/near_mode && log "pen near mode -> $n"
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
    g=$(sget global pipa_game_fg) || return
    # helper 2.5 (Pipa Helper > Games > Performance profile): global pipa_game_scene 20/13/10, 0 = off; else the config
    sc=$(sget global pipa_game_scene) || return
    : > "$GAME_STAMP"   # after the reads: a failed read is tried again next second
    case $sc in 0|10|13|20) ;; *) sc=${GAME_THERMAL_SCENE:-20} ;; esac
    if [ "$g" = 1 ] && [ "$sc" != 0 ]; then game_scene "$sc"; else game_scene -1; fi
}
# helper 2.5 (Pipa Helper > Effects > Apply / Reset): blur and contour glow are read by SystemUI and the launcher at
# their start. The helper sets global pipa_fx_restart = 1; this restarts both once (as the beta7.1 once-step) and
# sets it back to 0. No reboot.
FX_STAMP=/data/misc/pipa_port/fx.stamp
rm -f "$FX_STAMP"
# 9r peak_check (pt175-pt176) removed in 9s: the 144 Hz lock screen came from OPPO's keyguard vote, now fixed in the
# ROM config (step 9s); OPPO's own peak_refresh_rate is right in each mode.
rm -f /data/misc/pipa_port/peak.stamp
fx_check() {
    [ -e "$FX_STAMP" ] && ! [ "$GLOBAL_XML" -nt "$FX_STAMP" ] && return
    v=$(sget global pipa_fx_restart) || return
    : > "$FX_STAMP"
    [ "$v" = 1 ] || return
    settings put global pipa_fx_restart 0 </dev/null >/dev/null 2>&1
    kill -9 $(pidof com.android.systemui) 2>/dev/null
    am force-stop com.android.launcher </dev/null >/dev/null 2>&1
    am start -a android.intent.action.MAIN -c android.intent.category.HOME </dev/null >/dev/null 2>&1
    log "effects applied: SystemUI + launcher restarted (helper)"
}
# 8n (helper 2.6, Pipa Helper > System > Optimise apps): global pipa_dexopt = 1 -> ART's background dexopt job runs
# once, now (`pm bg-dexopt-job`: the stock job Android runs when the tablet is idle and charging). After a ROM update
# most apps run from "verify" (interpreter + JIT) until that night job. Only on the user's request: no automatic run.
# 2 while it runs, 0 after; global pipa_dexopt_last = end time (epoch s). A 2 left by a reboot is reset.
DEXOPT_STAMP=/data/misc/pipa_port/dexopt.stamp
DEXOPT_RUN=/data/misc/pipa_port/dexopt.run   # exists while the job runs (a PID test would also see a zombie)
rm -f "$DEXOPT_STAMP" "$DEXOPT_RUN"
dexopt_check() {
    [ -e "$DEXOPT_STAMP" ] && ! [ "$GLOBAL_XML" -nt "$DEXOPT_STAMP" ] && return
    v=$(sget global pipa_dexopt) || return
    : > "$DEXOPT_STAMP"
    [ -e "$DEXOPT_RUN" ] && return
    if [ "$v" = 2 ]; then settings put global pipa_dexopt 0 </dev/null >/dev/null 2>&1; return; fi
    [ "$v" = 1 ] || return
    : > "$DEXOPT_RUN"
    settings put global pipa_dexopt 2 </dev/null >/dev/null 2>&1
    log "optimise apps: background dexopt job started (helper)"
    (
        t0=$(date +%s)
        pm bg-dexopt-job </dev/null >/dev/null 2>&1; r=$?
        t1=$(date +%s)
        settings put global pipa_dexopt_last "$t1" </dev/null >/dev/null 2>&1
        rm -f "$DEXOPT_RUN"
        settings put global pipa_dexopt 0 </dev/null >/dev/null 2>&1
        log "optimise apps: done (exit $r, $((t1 - t0)) s)"
    ) &
}
# 8q (helper 2.7, Pipa Helper > System > Collect logs): global pipa_logs = 1 -> collect_logs.sh once (redacted tar.gz
# in /data/misc/pipa_logs, type pipa_logs_file); 2 while it runs, 0 after; global pipa_logs_file = the file name (the
# helper copies it into Downloads and offers to share it). A 2 left by a reboot is reset.
LOGS_STAMP=/data/misc/pipa_port/logs.stamp
LOGS_RUN=/data/misc/pipa_port/logs.run
rm -f "$LOGS_STAMP" "$LOGS_RUN"
logs_check() {
    [ -e "$LOGS_STAMP" ] && ! [ "$GLOBAL_XML" -nt "$LOGS_STAMP" ] && return
    v=$(sget global pipa_logs) || return
    : > "$LOGS_STAMP"
    [ -e "$LOGS_RUN" ] && return
    if [ "$v" = 2 ]; then settings put global pipa_logs 0 </dev/null >/dev/null 2>&1; return; fi
    [ "$v" = 1 ] || return
    : > "$LOGS_RUN"
    settings put global pipa_logs 2 </dev/null >/dev/null 2>&1
    log "collect logs: started (helper)"
    (
        f=$(sh "$MODDIR/collect_logs.sh" </dev/null 2>/dev/null)
        [ -n "$f" ] && settings put global pipa_logs_file "$f" </dev/null >/dev/null 2>&1
        rm -f "$LOGS_RUN"
        settings put global pipa_logs 0 </dev/null >/dev/null 2>&1
        log "collect logs: done (${f:-failed})"
    ) &
}
# 9d (BUGS 193, helper 3.4 "Install update"): global pipa_ota = 1 -> update_engine_client installs the A/B payload in
# global pipa_ota_payload ("url|offset|size|headers", ';' between the header lines) into the other slot. 2 while it runs
# (pipa_ota_progress = "<update_engine status> <percent>"), 3 = done, the helper offers the restart, 4 = failed
# (pipa_ota_error = the last update_engine line). update_engine checks the payload signature (step 9c: port OTA key
# only). Only https:// URLs or files in /data/ota_package. Event driven like logs_check; the progress loop runs only
# during an install. A 2 left by a reboot becomes 4.
OTA_STAMP=/data/misc/pipa_port/ota.stamp
OTA_RUN=/data/misc/pipa_port/ota.run
OTA_LOG=/data/misc/pipa_port/ota.log
OTA_SLOT=/data/misc/pipa_port/ota.slot   # "<slot> <boot_id>" when an install finished (3): checked after the restart
rm -f "$OTA_STAMP" "$OTA_RUN"
ota_set() { settings put global "$1" "$2" </dev/null >/dev/null 2>&1; }
# Dual-boot guard: the install overwrites boot of the other slot (docs/DUALBOOT-LINUX.md keeps Linux/UEFI in boot_a).
# OK = empty (first 4 KiB zero), a port boot image (ANDROID!, os_version bytes 3c060020 as mkboot.sh keeps them,
# header v3) or a 4.19 port kernel. Read only (rules_9d).
ota_boot_ok() {
    [ -r "$1" ] || return 1
    [ -z "$(head -c 4096 "$1" | tr -d '\000' | head -c 1)" ] && return 0
    if [ "$(head -c 8 "$1")" = "ANDROID!" ] && [ "$(head -c 20 "$1" | tail -c 4 | od -An -tx1 | tr -d ' \n')" = 3c060020 ] &&
        [ "$(head -c 44 "$1" | tail -c 4 | od -An -tu4 | tr -d ' \n')" = 3 ]; then
        return 0
    fi
    head -c 67108864 "$1" | grep -aq 'Linux version 4\.19\.'
}
ota_check() {
    [ -e "$OTA_STAMP" ] && ! [ "$GLOBAL_XML" -nt "$OTA_STAMP" ] && return
    v=$(sget global pipa_ota) || return
    : > "$OTA_STAMP"
    [ -e "$OTA_RUN" ] && return
    if [ "$v" = 2 ]; then ota_set pipa_ota_error "interrupted (restart during the install)"; ota_set pipa_ota 4; return; fi
    if [ "$v" = 3 ] && [ -f "$OTA_SLOT" ]; then
        read -r s0 b0 < "$OTA_SLOT"; b1=$(cat /proc/sys/kernel/random/boot_id)
        [ "$b0" = "$b1" ] && return     # no restart yet
        rm -f "$OTA_SLOT"
        if [ "$s0" != "$(getprop ro.boot.slot_suffix)" ]; then
            ota_set pipa_ota 0; log "ota: running the new system (slot $(getprop ro.boot.slot_suffix))"
        else
            ota_set pipa_ota_error "the new system did not start; the tablet is back on the old one"; ota_set pipa_ota 4
            log "ota: still on slot $s0 after the restart (fallback)"
        fi
        return
    fi
    [ "$v" = 1 ] || return
    p=$(sget global pipa_ota_payload) || return
    # 9h (2026-11-25): one or more payloads, '^' between them, in the order to try (helper: the delta for the
    # installed build first, then the full payload). Each "url[ url ...]|offset|size|headers": the same file on
    # several mirrors (helper: fastest first, space between). On a failure: the next mirror, then the next payload.
    # update_engine resumes a partly downloaded payload from another mirror (same payload hash). Each attempt is
    # safe: update_engine writes only the other slot and switches slots only after a verified, complete install.
    rest=$p; n=0
    while [ -n "$rest" ]; do
        e=${rest%%"^"*}; case $rest in *"^"*) rest=${rest#*"^"} ;; *) rest= ;; esac
        # mksh: an unquoted | in a pattern is an alternation (empty fields, test 2026-11-25): quote it
        us=${e%%"|"*}; r=${e#*"|"}; off=${r%%"|"*}; r=${r#*"|"}; size=${r%%"|"*}; hdr=${r#*"|"}
        case "$off$size" in ''|*[!0-9]*) n=-1; break ;; esac
        [ -n "$us" ] && [ -n "$hdr" ] && [ "$hdr" != "$r" ] || { n=-1; break; }
        while [ -n "$us" ]; do
            u=${us%%" "*}; case $us in *" "*) us=${us#*" "} ;; *) us= ;; esac
            case "$u" in https://*|file:///data/ota_package/*) ;; *) n=-1; break 2 ;; esac
        done
        n=$((n + 1))
    done
    if [ "$n" -lt 1 ]; then
        ota_set pipa_ota_error "bad payload data"; ota_set pipa_ota 4; log "ota: bad payload data"; return
    fi
    # the port payloads are built for encrypted /data: a -noenc build (step 3x, fstab without encryption) would get
    # an fstab that wants encryption on a plain /data and would not start
    if [ "$(getprop ro.crypto.state)" != encrypted ]; then
        ota_set pipa_ota_error "this build has no /data encryption (noenc): update with the PC scripts"
        ota_set pipa_ota 4; log "ota: refused, ro.crypto.state $(getprop ro.crypto.state)"; return
    fi
    # stock updater rule: 30 % battery, or the charger in (the install and the first start take a while)
    cap=; read -r cap < /sys/class/power_supply/battery/capacity 2>/dev/null
    inp=; read -r inp < /sys/class/power_supply/usb/present 2>/dev/null
    if [ "${cap:-0}" -lt 30 ] && [ "$inp" != 1 ]; then
        ota_set pipa_ota_error "battery below 30 %: connect the charger and try again"
        ota_set pipa_ota 4; log "ota: refused, battery ${cap:-?} %"; return
    fi
    case "$(getprop ro.boot.slot_suffix)" in _a) tgt=_b ;; *) tgt=_a ;; esac
    if ! ota_boot_ok "/dev/block/by-name/boot$tgt"; then
        ota_set pipa_ota_error "boot slot ${tgt#_} holds another system (Linux or UEFI dual boot?); the update would replace it. Update with the PC scripts instead"
        ota_set pipa_ota 4; log "ota: refused, boot$tgt is not a port boot image (dual boot?)"; return
    fi
    : > "$OTA_RUN"
    settings delete global pipa_ota_error </dev/null >/dev/null 2>&1
    ota_set pipa_ota_progress "0 0"
    ota_set pipa_ota 2
    log "ota: install started ($n payload(s))"
    (
        rest=$p; code=; e=; hard=; soft=
        while [ -n "$rest" ]; do
            x=${rest%%"^"*}; case $rest in *"^"*) rest=${rest#*"^"} ;; *) rest= ;; esac
            us=${x%%"|"*}; r=${x#*"|"}; off=${r%%"|"*}; r=${r#*"|"}; size=${r%%"|"*}
            hdr=$(echo "${r#*"|"}" | tr ';' '\n')
            while [ -n "$us" ]; do
                u=${us%%" "*}; case $us in *" "*) us=${us#*" "} ;; *) us= ;; esac
                if ota_try "$u" "$off" "$size" "$hdr"; then
                    echo "$(getprop ro.boot.slot_suffix) $(cat /proc/sys/kernel/random/boot_id)" > "$OTA_SLOT"
                    ota_set pipa_ota_progress "6 100"; ota_set pipa_ota 3; log "ota: installed, restart needed"
                    rm -f "$OTA_RUN"; exit 0
                fi
                e=$(grep -E 'onPayloadApplicationComplete|ERROR' "$OTA_LOG" | tail -1 | cut -c1-200)
                code=$(grep 'onPayloadApplicationComplete' "$OTA_LOG" | tail -1 | sed -n 's/.*(\([0-9]*\)))*$/\1/p')
                log "ota: attempt failed (${u%%\?*}): $e"
                # report the real cause: a signature, fit or space error wins over a mirror download error
                case "$code" in 9|10|11|21|32) soft=$code ;; *) hard=$code ;; esac
                # no space (60) or an older build (51): no other mirror or payload helps
                case "$code" in 60|51) break 2 ;; esac
            done
        done
        code=${hard:-$soft}
        ota_set pipa_ota_error "$(ota_why "$code") (error ${code:-?})"; ota_set pipa_ota 4; log "ota: failed: $e"
        rm -f "$OTA_RUN"
    ) &
}
# update_engine ErrorCode (common/error_code.h) -> text for Pipa Helper ("Install failed: <text> (error N)")
ota_why() {
    case "$1" in
        9) echo "download failed (network or server busy); try again later" ;;
        10|11|21|32) echo "the downloaded file is damaged or not the update; try again later" ;;
        12|18|24|25|26|33) echo "the update failed the signature check (not from this port, or damaged): nothing installed" ;;
        20|27|28|29) echo "the update does not fit the installed system: nothing installed" ;;
        51) echo "the update is older than the installed system" ;;
        60) echo "not enough free storage: free some space and try again" ;;
        48) echo "cancelled" ;;
        *) echo "update_engine error" ;;
    esac
}
# One update_engine install attempt; progress to pipa_ota_progress while it runs. 0 = installed.
ota_try() {
    update_engine_client --update --follow --payload="$1" --offset="$2" --size="$3" --headers="$4" \
        </dev/null >"$OTA_LOG" 2>&1 &
    uec=$!
    last=
    while kill -0 $uec 2>/dev/null; do
        sleep 3
        s=$(grep 'onStatusUpdate(' "$OTA_LOG" | tail -1 | sed -n 's/.*(\([0-9]*\)), \([0-9.]*\)).*/\1 \2/p')
        [ -n "$s" ] || continue
        f=${s#* }; case $f in 1|1.0*) pc=100 ;; 0.*) pc=$(echo "${f#0.}00" | cut -c1-2); pc=${pc#0} ;; *) pc=0 ;; esac
        n="${s%% *} ${pc:-0}"
        [ "$n" = "$last" ] || { ota_set pipa_ota_progress "$n"; last=$n; }
    done
    wait $uec
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

# ------------------------------------------------------------- keyboard fold
# 6k, kernel walt-r20+: the nanosic driver acts on the daemon's fold request (32 FF 00/01) and
# has /proc/nanokbd, which the ROM's xiaomi-keyboard uses as its "keypad present" flag (was
# /dev/input/event12). So the kernel may remove the keypad input devices while the cover is
# folded behind the tablet or closed (as stock HyperOS disables them): Android sees no hardware
# keyboard, the on-screen keyboard returns. Older kernels: parameter missing, nothing changes.
# One write at service start; nothing polls.
KB_FOLD=/sys/module/nanosic_driver_v2/parameters/fold_remove
KB_FOLD_KERNEL=0
if [ -e "$KB_FOLD" ]; then
    KB_FOLD_KERNEL=1                    # the event12 link below is not needed (and not wanted) any more
    if [ "${KEYBOARD_FOLD_REMOVE:-1}" = 1 ]; then
        echo 1 > "$KB_FOLD" 2>/dev/null && log "keyboard fold: kernel removes the keypad devices while folded"
    fi
    # 6l: the on-screen keyboard hides while the keyboard cover is in use and returns when it is folded away or
    # detached (Android default, as HyperOS). 2v had set show_ime_with_hard_keyboard=1 at the first boot for the
    # phantom keyboard devices (gone since walt-r7ov). Once per install, on walt-r20+ only; the user can switch
    # it on again (Settings: on-screen keyboard while a physical one is active).
    if [ ! -e "$STATE/hard_kb_ime_default_set" ]; then
        settings put secure show_ime_with_hard_keyboard 0 </dev/null >/dev/null 2>&1
        touch "$STATE/hard_kb_ime_default_set"
        log "on-screen keyboard hides while a hardware keyboard is active (show_ime_with_hard_keyboard=0, once)"
    fi
fi

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
# BUGS 153: OPPO apps take pencil clicks only while Global ipe_pencil_connect_state = 2 (IPeManager sets it for its own
# BLE pencils; Notes registers its PENCIL_DOUBLE_CLICK receiver then). 2 while the Xiaomi pen is connected, 0 when not.
ipe_state() {
    [ "$(sget global ipe_pencil_connect_state)" = "$1" ] && return
    settings put global ipe_pencil_connect_state "$1" </dev/null >/dev/null 2>&1
    log "ipe_pencil_connect_state=$1"
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
        nap 0.5   # 110: builtin wait, no sleep process (3 per screen-on before)
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
chg_wl=0; echo pipa_chg > /sys/power/wake_unlock 2>/dev/null   # 9o: no wake lock left from a service restart
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
    # 9o (BUGS-TODO 204): this check runs only while the CPU is awake. Screen off, the tablet sleeps between the fuel
    # gauge's 1 % wake-ups and could charge past the limit before the next check (stock OPPO checks in its kernel
    # charger driver). In the last 4 % before the limit (charger in, no hold yet) a wake lock keeps the check running
    # (~5-10 min, powered by the charger); once the hold is set the kernel keeps it while asleep. The lock has a 30 s
    # timeout and is re-armed on each check, so it ends by itself if this service stops.
    if [ "$v" != 0 ] && [ $lim -lt 100 ] && [ $want = 1 ] && [ "$c" -ge $((lim - 4)) ]; then
        echo "pipa_chg 30000000000" > "${WL_DIR:-/sys/power}/wake_lock" 2>/dev/null
        [ $chg_wl = 0 ] && log "charge hold: awake near the limit ($c %, limit $lim)"; chg_wl=1
    elif [ $chg_wl = 1 ]; then
        echo pipa_chg > "${WL_DIR:-/sys/power}/wake_unlock" 2>/dev/null; chg_wl=0; log "charge hold: wake lock released at $c %"
    fi
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
        # 9o: every pass while the charger is in (a few builtin reads), so a short 1 % wake-up near the limit is enough
        cin=; read -r cin 2>/dev/null < "$CHG_IN"
        if [ "$cin" = 1 ] || [ $((ctick % 5)) = 0 ]; then chg_hold; fi
    fi
    ctick=$((ctick + 1))
    if ! screen_on; then
        armed=0
        [ -n "$GAME_SC" ] && [ "$GAME_SC" != -1 ] && { game_scene -1; rm -f "$GAME_STAMP"; }
        nap 1
        continue
    fi
    # 6u (BUGS 111): pen input in the touch IC only while the pen is connected over BT (as HyperOS: the stylus
    # service enables pen mode on connect). Without it the panel scanned for a pen all the time and any active pen wrote.
    pen_settings_check
    if [ "${PEN_WAKE:-1}" = 1 ] && [ $armed = 0 ] && [ -x "$IOCTL" ] && { [ "${PEN_BT_ONLY:-1}" = 0 ] || [ "$conn" = 1 ]; }; then
        pen_wake && armed=1
    fi
    [ "${LID_SYNC:-1}" = 1 ] && lid_check
    [ "${ANIM_TIER:-1}" = 1 ] && anim_check
    [ "${LOG_QUIET:-1}" = 1 ] && log_check
    [ "${LIVE_BLUR_TILE:-1}" = 1 ] && blur_check
    if [ $KSU_RETRY = 1 ] && [ $((ctick % 60)) = 0 ]; then
        if ksu_manager; then KSU_RETRY=0; elif [ $KSU_TRY -ge 30 ]; then KSU_RETRY=0; log "SukiSU manager: no more tries"; fi
    fi
    if [ $APPS_RETRY = 1 ] && [ $((ctick % 60)) = 30 ]; then
        if bundled_apps; then APPS_RETRY=0; elif [ $APPS_TRY -ge 30 ]; then APPS_RETRY=0; log "bundled apps: no more tries"; fi
        cts_assistant
    fi
    [ $((ctick % 300)) = 150 ] && [ ! -e "$STATE/cts_assistant_v2" ] && cts_assistant
    [ $((ctick % 10)) = 5 ] && [ -e "$STATE/gboard_pending" ] && { gboard_default || :; }
    game_check
    pen_near_check
    fx_check
    [ "${DEXOPT_BUTTON:-1}" = 1 ] && dexopt_check
    [ "${LOGS_BUTTON:-1}" = 1 ] && logs_check
    [ "${OTA_BUTTON:-1}" = 1 ] && ota_check
    if [ "${PEN_WATCH:-1}" = 1 ]; then
        if pen_connected; then c=1; else c=0; fi
        # At boot ColorOS's pen manager is not ready at once (an early message was sometimes ignored and
        # Settings showed the stylus as not connected), so the first "connected" goes out once, 40 s after the
        # service start. Since 2p each present=1 also shows the live-alert capsule: one message, not three.
        # Later changes (Bluetooth connect/disconnect) go out at once.
        if [ "$c" != "$conn" ]; then
            if [ $c = 1 ]; then ipe_state 2; else ipe_state 0; fi
            if [ -z "$conn" ] && [ $c = 1 ]; then resend=0; else pen_present $c; resend=2; fi
            if [ "${PEN_BT_ONLY:-1}" = 1 ] && [ -x "$IOCTL" ]; then
                if [ $c = 1 ]; then armed=0   # pen on at the next tick
                else "$IOCTL" pen off >/dev/null 2>&1; armed=0; echo "$(date) pen off (not connected)" >> "$PEN_LOG"; log "pen input off (not connected over BT)"; fi
            fi
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
        if [ "${KB_EVENT_LINK:-1}" = 1 ] && [ $KB_FOLD_KERNEL = 0 ] && [ "$DEVS" != "$KB_DEVS" ]; then kb_link; KB_DEVS=$DEVS; fi
        [ "${KEYBOARD_GUARD:-1}" = 1 ] && [ -e "$KB_HALL" ] && kb_guard
    fi
    if [ $((tick % 15)) = 0 ]; then
        # 4 sget reads (`settings get` processes): only after a change of the system settings file
        if [ -e "$DISP_DONE" ] && { ! [ -e "$SYS_STAMP" ] || [ "$SYS_XML" -nt "$SYS_STAMP" ]; }; then : > "$SYS_STAMP"; remember_display; fi
        [ "${SYSTEM_UX:-1}" = 1 ] && [ -w "$UX_TASK" ] && system_ux
    fi
    tick=$((tick + 1))
    nap 1
done
