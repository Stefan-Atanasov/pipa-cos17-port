#!/system/bin/sh
# pipa COS17 power/polish companion module.
#
# Every change here is deliberately non-destructive:
#   * the keyboard daemon is only *stopped while no keyboard is attached* and
#     is started again as soon as a Xiaomi keyboard shows up on the input bus;
#   * the AOD daemon is frozen, not killed, so pipa_core's restart loop does
#     not respawn it and SIGCONT resumes it instantly;
#   * the face HAL watchdog only starts a HAL when neither init nor pipa_core
#     has one running;
#   * the legacy face app is only touched when /data/system/facehal_socket is
#     absent (the AIDL facehal-rs stack does not create that socket).
#
# The display fixes (sRGB calibration, brightness table) are plain file
# replacements under system/ and need no runtime code; see README.md.
#
# Log: /data/local/tmp/pipa_power_tune.log

MODDIR=${0%/*}
LOG=/data/local/tmp/pipa_power_tune.log
CONF="$MODDIR/config.prop"
[ -f "$CONF" ] && . "$CONF"

KEYBOARD_GUARD=${KEYBOARD_GUARD:-1}
KB_EVENT_LINK=${KB_EVENT_LINK:-1}
AOD_GATE=${AOD_GATE:-1}
FACE_WATCHDOG=${FACE_WATCHDOG:-1}
LEGACY_FACE_APP=${LEGACY_FACE_APP:-1}
COLOR_MODE_RESTORE=${COLOR_MODE_RESTORE:-1}
ADAPTIVE_RESTORE=${ADAPTIVE_RESTORE:-1}
PEN_REFRESH_CAP=${PEN_REFRESH_CAP:-1}
PEN_PRESENT=${PEN_PRESENT:-1}
PEN_PUBLISH=${PEN_PUBLISH:-1}
STYLUS_BUTTONS_DEFAULT=${STYLUS_BUTTONS_DEFAULT:-1}
POLL=${POLL:-5}

log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') $*" >> "$LOG"
}

# singleton: never run two guards (manual test + boot instance)
PIDF=/data/local/tmp/pipa_power_tune.pid
if [ -f "$PIDF" ]; then
    old=$(cat "$PIDF" 2>/dev/null)
    if [ -n "$old" ] && [ "$old" != "$$" ] && [ -r "/proc/$old/cmdline" ] && \
       tr '\0' ' ' < "/proc/$old/cmdline" 2>/dev/null | grep -q 'pipa_cos17_power_tune/service.sh'; then
        exit 0
    fi
fi
echo $$ > "$PIDF"
trap 'rm -f "$PIDF"' EXIT

# keep the log bounded (device may run for weeks)
if [ -f "$LOG" ] && [ "$(wc -c < "$LOG" 2>/dev/null || echo 0)" -gt 262144 ]; then
    tail -n 400 "$LOG" > "$LOG.tmp" 2>/dev/null && mv -f "$LOG.tmp" "$LOG"
fi

# ---------------------------------------------------------------- device guard
case "$(getprop ro.product.device)" in
    pipa) ;;
    *)
        log "not pipa (device=$(getprop ro.product.device)), exiting"
        exit 0
        ;;
esac

# Wait for a real boot. pipa_core starts its daemons 6-8 s after boot_completed.
i=0
until [ "$(getprop sys.boot_completed)" = "1" ]; do
    sleep 2
    i=$((i + 1))
    [ "$i" -gt 150 ] && exit 0
done
sleep 20

log "start (device=$(getprop ro.product.device) build=$(getprop ro.build.display.id))"

# ------------------------------------------------------------------- keyboard
# Xiaomi pogo keyboard presents input devices named "Xiaomi Keyboard" /
# "Xiaomi Consumer Control" (see /vendor/usr/idc/Xiaomi_Keyboard.idc).
# Must NOT match:
#   "xiaomi keyboard WakeUp"  (always present, pogo GPIO)
#   "Xiaomi Smart Pen Keyboard" / "Xiaomi Smart Pen" (pen)
kb_attached() {
    grep -qiE 'Name="(Xiaomi|Mi) (Keyboard|Consumer( Control)?|Touchpad)"' \
        /proc/bus/input/devices 2>/dev/null
}

kb_running() {
    [ "$(getprop init.svc.xiaomi-keyboard)" = "running" ]
}

# xiaomi-keyboard only access()es /dev/input/event12 as its "keyboard present"
# flag (all real I/O is /dev/nanodev0). On pipa event0-10 are already taken, so
# the case never lands on event12: the daemon enables the keyboard once and then
# sleeps forever, i.e. no fold-back auto-disable. While the keyboard is attached
# we point event12 at its real node (only if nothing else owns that name).
KB_LINK=/dev/input/event12

kb_node() {
    awk '/^N: Name=/ { kb = ($0 ~ /Name="(Xiaomi|Mi) (Keyboard|Consumer( Control)?|Touchpad)"/) }
         /^H: Handlers=/ && kb { if (match($0, /event[0-9]+/)) { print substr($0, RSTART, RLENGTH); exit } }' \
        /proc/bus/input/devices 2>/dev/null
}

kb_link_set() {
    [ "$KB_EVENT_LINK" = "1" ] || return
    node=$(kb_node)
    [ -n "$node" ] && [ "$node" != "event12" ] || return
    if [ -L "$KB_LINK" ]; then
        [ "$(readlink "$KB_LINK")" = "$node" ] && return
        rm -f "$KB_LINK"
    elif [ -e "$KB_LINK" ]; then
        return
    fi
    ln -s "$node" "$KB_LINK" && chcon -h u:object_r:input_device:s0 "$KB_LINK" 2>/dev/null
    log "keyboard on $node -> $KB_LINK linked"
}

kb_link_clear() {
    [ -L "$KB_LINK" ] || return
    rm -f "$KB_LINK" && log "keyboard gone -> $KB_LINK link removed"
}

# ------------------------------------------------------------------------ AOD
aod_enabled() {
    [ "$(settings get secure Setting_AodSwitchEnable 2>/dev/null)" = "1" ]
}

aod_pid() {
    pgrep -f 'app_process /system/bin AodBacklightDaemon' 2>/dev/null | head -n 1
}

proc_state() {
    awk '{print $3}' "/proc/$1/stat" 2>/dev/null
}

# ----------------------------------------------------------------------- face
face_running() {
    [ "$(getprop init.svc.vendor.facehal)" = "running" ] && return 0
    pgrep -f 'android.hardware.biometrics.face-service.facehal' >/dev/null 2>&1
}

start_face() {
    F=/data/adb/modules/pipa_core/facehal
    BIN=$F/android.hardware.biometrics.face-service.facehal
    [ -x "$BIN" ] || return 1

    # mirror pipa_core's OpenCL loader selection
    if [ -f /vendor/Khronos/OpenCL/vendors/adreno.icd ] && \
       [ -f /vendor/lib64/libOpenCL_adreno.so ]; then
        chosen=libOpenCL.so.819
    else
        chosen=libOpenCL.so.stock
    fi
    if [ -f "$F/lib64/$chosen" ]; then
        cp -f "$F/lib64/$chosen" "$F/lib64/libOpenCL.so" 2>/dev/null
    fi

    mkdir -p /data/vendor_de/0/facedata/facehal/templates 2>/dev/null
    LD_LIBRARY_PATH=$F/lib64:$F nohup "$BIN" >>/data/local/tmp/facehal.log 2>&1 &
    log "facehal was not running -> started pid=$!"
    sleep 5
    return 0
}

# ------------------------------------------------------------- legacy face app
legacy_state=""

legacy_face_app() {
    # The old socket stack is in use -> make sure its client is available.
    if [ -e /data/system/facehal_socket ]; then
        if [ "$legacy_state" != "enabled" ]; then
            pm enable com.pipa.faceunlock >/dev/null 2>&1
            log "facehal_socket present -> com.pipa.faceunlock enabled"
            legacy_state=enabled
        fi
        return
    fi

    # AIDL facehal-rs stack: the socket client would retry forever.
    if [ "$legacy_state" != "disabled" ]; then
        pm list packages 2>/dev/null | grep -q '^package:com.pipa.faceunlock$' || return
        pm disable-user --user 0 com.pipa.faceunlock >/dev/null 2>&1
        log "AIDL face HAL in use -> com.pipa.faceunlock disabled"
        legacy_state=disabled
    fi

    # the package is PERSISTENT; kill -STOP stops the retry loop without giving
    # the framework a reason to restart it
    for p in $(pgrep -f 'com.pipa.faceunlock' 2>/dev/null); do
        [ "$(proc_state "$p")" = "T" ] || kill -STOP "$p" 2>/dev/null
    done
}

# ------------------------------------------------------------------------ pen
# Xiaomi Smart Pen on ColorOS (BUGS-TODO.md B3, B6, pen dead on the lockscreen).
# * The panel senses the pen only at 60 or 120 Hz, not at 144/90/30
#   (dsi_panel_match_fps_pen_setting logs every switch; no pen events at 144,
#   e.g. on the ColorOS lockscreen). HyperOS keeps the normal range while the pen
#   is docked and 60/120 while it is out. Here: out of the dock = fixed 120 Hz
#   (a 60-120 range would let VRR pick 90). Dock = fuda/reverse_chg_hall4, 0 while
#   docked (hall3 stays 1). Only while the pen is connected over BT (its input
#   device exists): without a pen the hall reads 1 too. ColorOS's own choice
#   (secure oplus_customize_screen_refresh_rate, 8 = 144 Hz, 3 = 120 Hz) outranks
#   peak_refresh_rate, so it is switched to 3 as well; all three are saved.
# * ColorOS only knows OPPO pens. Send IPeManager the "pencil present" intent
#   that OplusExSystemService sends for an OPPO pen, so Settings shows the
#   stylus as connected (all extras are strings; macAddr without colons).
PEN_RR_STATE="$MODDIR/pen_refresh_saved"
PEN_HALL=/sys/class/power_supply/fuda/reverse_chg_hall4
PEN_SOC=/sys/class/power_supply/wireless/reverse_pen_soc
PEN_PEAK=120.00001
PEN_MIN=120.00001
PEN_OPLUS=3
# beta5-2c+: refresh_rate_config.xml has ipePencilRateId="3", so ColorOS locks 120 Hz itself while
# global settings_enable_oppo_pencil is 1 (OplusRefreshRatePolicyImpl). Then only that flag is set
# and the user's refresh settings are never touched; older ROMs use the settings method below.
PEN_NATIVE=0
grep -q 'ipePencilRateId="' /my_product/etc/refresh_rate_config.xml 2>/dev/null && PEN_NATIVE=1

pen_connected() {
    grep -q 'Name="Xiaomi Smart Pen"' /proc/bus/input/devices 2>/dev/null
}

pen_docked() {
    [ "$(cat "$PEN_HALL" 2>/dev/null)" = "0" ]
}

pen_mac() {
    awk '/^\[/ { m = $0 } /^Name = Xiaomi Smart Pen$/ { m = substr(m, 2, length(m) - 2); gsub(/:/, "", m); print tolower(m); exit }' \
        /data/misc/bluedroid/bt_config.conf 2>/dev/null
}

pen_present() {
    mac=$(pen_mac)
    am startservice --user 0 -a com.oplus.ipemanager.action.PENCIL_STATUS_CHANGE \
        -p com.oplus.ipemanager --es present "$1" --es macAddr "$mac" --es pencilId 1 >/dev/null 2>&1
    log "pen present=$1 (mac=${mac:-unknown})"
}

pen_cap_on() {
    if [ "$PEN_NATIVE" = "1" ]; then
        settings put global settings_enable_oppo_pencil 1
        log "pen out of dock -> ColorOS stylus lock on (settings_enable_oppo_pencil=1)"
        return
    fi
    [ -f "$PEN_RR_STATE" ] && return
    echo "$(settings get system peak_refresh_rate 2>/dev/null) $(settings get system min_refresh_rate 2>/dev/null) $(settings get secure oplus_customize_screen_refresh_rate 2>/dev/null)" > "$PEN_RR_STATE"
    settings put secure oplus_customize_screen_refresh_rate "$PEN_OPLUS"
    settings put system peak_refresh_rate "$PEN_PEAK"
    settings put system min_refresh_rate "$PEN_MIN"
    log "pen out of dock -> refresh fixed 120 Hz (saved: $(cat "$PEN_RR_STATE"))"
}

pen_cap_off() {
    if [ "$PEN_NATIVE" = "1" ] && [ "$(settings get global settings_enable_oppo_pencil 2>/dev/null)" = "1" ]; then
        settings put global settings_enable_oppo_pencil 0
        log "pen docked or gone -> ColorOS stylus lock off"
    fi
    [ -f "$PEN_RR_STATE" ] || return
    read -r peak min oplus < "$PEN_RR_STATE"
    # a value the user changed meanwhile is left alone
    if [ "$(settings get system peak_refresh_rate 2>/dev/null)" = "$PEN_PEAK" ]; then
        case "$peak" in ''|null) settings delete system peak_refresh_rate ;; *) settings put system peak_refresh_rate "$peak" ;; esac
    fi
    if [ "$(settings get system min_refresh_rate 2>/dev/null)" = "$PEN_MIN" ]; then
        case "$min" in ''|null) settings delete system min_refresh_rate ;; *) settings put system min_refresh_rate "$min" ;; esac
    fi
    if [ "$(settings get secure oplus_customize_screen_refresh_rate 2>/dev/null)" = "$PEN_OPLUS" ]; then
        case "$oplus" in ''|null) ;; *) settings put secure oplus_customize_screen_refresh_rate "$oplus" ;; esac
    fi
    rm -f "$PEN_RR_STATE"
    log "pen docked or gone -> refresh restored ($peak $min $oplus)"
}

# For the pipa helper app (PenKeeper: battery notification), which cannot read the vendor sysfs
# nodes: global pipa_pen_state = "<connected> <docked> <soc>", or "0" without a pen. The soc is
# the reverse-charger reading, so it only updates while the pen is docked. Written on change only.
pen_publish() {
    settings put global pipa_pen_state "$1"
}

# 1 s poll while the screen is on (an undocked pen must work at once), 5 s while off.
pen_watch() {
    conn=; mode=; pub=
    pen_cap_off     # left over from a reboot with the pen out of the dock
    while true; do
        if [ "$(cat /sys/class/backlight/panel0-backlight/brightness 2>/dev/null)" = "0" ]; then
            sleep 5
            continue
        fi
        if pen_connected; then c=1; else c=0; fi
        if [ "$c" != "$conn" ]; then
            [ "$PEN_PRESENT" = "1" ] && pen_present "$c"
            conn=$c
        fi
        if [ "$c" = "1" ] && ! pen_docked; then m=out; else m=idle; fi
        if [ "$c" = "1" ]; then
            if [ "$m" = "out" ]; then d=0; else d=1; fi
            p="1 $d $(cat "$PEN_SOC" 2>/dev/null)"
        else
            p=0
        fi
        if [ "$p" != "$pub" ] && [ "$PEN_PUBLISH" = "1" ]; then
            pen_publish "$p"
            pub=$p
        fi
        if [ "$m" != "$mode" ] && [ "$PEN_REFRESH_CAP" = "1" ]; then
            if [ "$m" = "out" ]; then pen_cap_on; else pen_cap_off; fi
        fi
        mode=$m
        sleep 1
    done
}

# B12: let Android merge the pen's HID buttons into its MotionEvents (drawing apps see
# STYLUS_BUTTON_PRIMARY/SECONDARY). Only set when unset, so a user choice is kept.
if [ "$STYLUS_BUTTONS_DEFAULT" = "1" ] && [ "$(settings get secure stylus_buttons_enabled 2>/dev/null)" = "null" ]; then
    settings put secure stylus_buttons_enabled 1
    touch "$MODDIR/stylus_default_set"
    log "stylus_buttons_enabled default -> 1"
fi

# pipa helper app (ROM 2d+, or installed by hand): its notification permission and overlay appop.
# The ROM's default-permissions entry only applies on a first boot, so grant both as root.
if pm path com.port.pipa.helper >/dev/null 2>&1; then
    pm grant com.port.pipa.helper android.permission.POST_NOTIFICATIONS >/dev/null 2>&1
    appops set com.port.pipa.helper SYSTEM_ALERT_WINDOW allow >/dev/null 2>&1
    log "pipa helper: notification + overlay granted"
fi

if [ "$PEN_REFRESH_CAP" = "1" ] || [ "$PEN_PRESENT" = "1" ] || [ "$PEN_PUBLISH" = "1" ]; then
    pen_watch &
fi

# ------------------------------------------------------------------ main loop
# ----------------------------------------------------------------- colour mode
# ColorOS sometimes re-applies the default colour mode 256 (Vivid, raw panel
# gamut) at boot even when the user picked Natural (0). Remember the user's
# choice and put it back once after boot; writing display_color_mode makes
# ColorDisplayService re-apply the mode (verified: HWC logs "Applying mode").
COLOR_STATE="$MODDIR/color_mode"

color_mode() {
    settings get system display_color_mode 2>/dev/null
}

if [ "$COLOR_MODE_RESTORE" = "1" ] && [ -f "$COLOR_STATE" ]; then
    want=$(cat "$COLOR_STATE" 2>/dev/null)
    now=$(color_mode)
    if [ -n "$want" ] && [ "$want" != "$now" ]; then
        settings put system display_color_mode "$want" && log "colour mode $now -> $want restored"
    fi
fi

# Adaptive colour / Bedtime mode: the eyeprotect app resets both settings to 0
# on every boot (it checks the OPPO CCT sensor type directly and does not see
# the reroute). Remember the user's last choice and put it back once, after the
# CCT sensor has produced its first event.
ADAPTIVE_STATE="$MODDIR/adaptive_state"
BEDTIME_STATE="$MODDIR/bedtime_state"

if [ "$ADAPTIVE_RESTORE" = "1" ]; then
    if [ "$(cat "$ADAPTIVE_STATE" 2>/dev/null)" = "1" ]; then
        [ "$(settings get system setting_enable_color_temperature_regulation 2>/dev/null)" = "1" ] || \
            settings put system setting_enable_color_temperature_regulation 1
        [ "$(settings get system oplus_customize_comfort_color_temperature_enable 2>/dev/null)" = "1" ] || \
            settings put system oplus_customize_comfort_color_temperature_enable 1
        log "adaptive colour state restored"
    fi
    if [ "$(cat "$BEDTIME_STATE" 2>/dev/null)" = "1" ]; then
        for k in oplus_customize_rhythm_health_enable oplus_customize_comfortable_rhythm_enable; do
            [ "$(settings get system "$k" 2>/dev/null)" = "1" ] || settings put system "$k" 1
        done
        log "bedtime mode state restored"
    fi
fi

tick=0
while true; do
    if [ "$KEYBOARD_GUARD" = "1" ]; then
        if kb_attached; then
            kb_link_set
            if ! kb_running; then
                setprop ctl.start xiaomi-keyboard
                log "keyboard attached -> xiaomi-keyboard started"
            fi
        else
            if kb_running; then
                setprop ctl.stop xiaomi-keyboard
                log "keyboard absent -> xiaomi-keyboard stopped"
            fi
            kb_link_clear
        fi
    fi

    if [ "$AOD_GATE" = "1" ] && [ $((tick % 3)) -eq 0 ]; then
        p=$(aod_pid)
        if [ -n "$p" ]; then
            st=$(proc_state "$p")
            if aod_enabled; then
                if [ "$st" = "T" ]; then
                    kill -CONT "$p" 2>/dev/null && log "aod on -> resumed pid=$p"
                fi
            else
                if [ "$st" != "T" ]; then
                    kill -STOP "$p" 2>/dev/null && log "aod off -> suspended pid=$p"
                fi
            fi
        fi
    fi

    if [ "$LEGACY_FACE_APP" = "1" ] && [ $((tick % 3)) -eq 1 ]; then
        legacy_face_app
    fi

    if [ "$COLOR_MODE_RESTORE" = "1" ] && [ $((tick % 3)) -eq 0 ]; then
        cm=$(color_mode)
        case "$cm" in
            ''|null) ;;
            *) [ "$cm" = "$(cat "$COLOR_STATE" 2>/dev/null)" ] || echo "$cm" > "$COLOR_STATE" ;;
        esac
    fi

    if [ "$ADAPTIVE_RESTORE" = "1" ] && [ $((tick % 3)) -eq 0 ]; then
        av=$(settings get system setting_enable_color_temperature_regulation 2>/dev/null)
        case "$av" in
            0|1) [ "$av" = "$(cat "$ADAPTIVE_STATE" 2>/dev/null)" ] || echo "$av" > "$ADAPTIVE_STATE" ;;
        esac
        # Bedtime is "on" if either the standalone rhythm switch or the
        # Eye Comfort-dependent comfortable-rhythm switch is on.
        rv=$(settings get system oplus_customize_rhythm_health_enable 2>/dev/null)
        bv=$(settings get system oplus_customize_comfortable_rhythm_enable 2>/dev/null)
        case "$rv$bv" in
            *1*) want=1 ;;
            *0*) want=0 ;;
            *) want="" ;;
        esac
        if [ -n "$want" ] && [ "$want" != "$(cat "$BEDTIME_STATE" 2>/dev/null)" ]; then
            echo "$want" > "$BEDTIME_STATE"
        fi
    fi

    if [ "$FACE_WATCHDOG" = "1" ] && [ $((tick % 3)) -eq 2 ]; then
        if ! face_running; then
            start_face
        fi
    fi

    tick=$((tick + 1))
    sleep "$POLL"
done
