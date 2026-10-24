#!/system/bin/sh
# Undo the persistent bits before the module is removed.
# The keyboard daemon, AOD behaviour and the replaced display files return to
# stock on the next boot.

pm enable com.pipa.faceunlock >/dev/null 2>&1

for p in $(pgrep -f 'app_process /system/bin AodBacklightDaemon' 2>/dev/null); do
    kill -CONT "$p" 2>/dev/null
done

[ -L /dev/input/event12 ] && rm -f /dev/input/event12

# pen refresh cap: put back the values saved when the pen left the dock
S=${0%/*}/pen_refresh_saved
if [ -f "$S" ]; then
    read -r peak min oplus < "$S"
    case "$peak" in ''|null) settings delete system peak_refresh_rate ;; *) settings put system peak_refresh_rate "$peak" ;; esac
    case "$min" in ''|null) settings delete system min_refresh_rate ;; *) settings put system min_refresh_rate "$min" ;; esac
    case "$oplus" in ''|null) ;; *) settings put secure oplus_customize_screen_refresh_rate "$oplus" ;; esac
    rm -f "$S"
fi
settings put global settings_enable_oppo_pencil 0
am startservice --user 0 -a com.oplus.ipemanager.action.PENCIL_STATUS_CHANGE \
    -p com.oplus.ipemanager --es present 0 --es pencilId 1 >/dev/null 2>&1

settings delete global pipa_pen_state
# stylus button default: only undo it if this module set it
[ -f "${0%/*}/stylus_default_set" ] && settings delete secure stylus_buttons_enabled

rm -f /data/local/tmp/pipa_power_tune.pid
