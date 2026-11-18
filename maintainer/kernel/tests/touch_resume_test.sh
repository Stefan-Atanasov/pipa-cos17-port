#!/bin/bash
# BUGS 128 touch resume test matrix (walt-hi5). Usage: touch_resume_test.sh <phase...> (USB adb, root, tablet unlocked)
# soak | levels | back | offset | rapid | retry | retrygame
T=/system_ext/pipa_port/xiaomi_touch_ioctl
TAB="bash $HOME/Documents/pipa/COS17/maintainer/tab.sh"
r() { adb shell "su -c '$1'" </dev/null; }
cyc() { $TAB off >/dev/null 2>&1; sleep "${1:-3}"; $TAB on >/dev/null 2>&1; sleep 4; }
modes() { local m o=""; for m in 0 2 3 4 5 7; do o="$o $m=$(r "$T get $m" | grep -o 'value=[0-9]*' | cut -d= -f2)"; done; echo "get:$o"; }
setm() { local a; for a in "$@"; do r "$T set ${a%=*} ${a#*=}" >/dev/null; done; sleep 1; }
report() {  # sends since last clear, error lines, pen lines, resume ends
    local d; d=$(r "dmesg")
    echo "sent: $(echo "$d" | grep -o 'set mode:[0-9]* = [0-9]*' | sed 's/set mode://; s/ = /=/' | tr '\n' ' ')"
    echo "resume ends: $(echo "$d" | grep -c 'nvt_ts_resume.*end')  fw ok: $(echo "$d" | grep -c 'Update firmware success')"
    echo "pen: $(echo "$d" | grep -o 'game_mode_enable [01], [A-Z]* pen' | sort | uniq -c | tr '\n' ' ')"
    echo "$d" | grep -i -E 'fail|IC state may error|r21:|error|timeout|retry|escalat' | grep -v -E 'fw_fail_test' | cut -c15-150 | tail -8
}
clr() { r "dmesg -C"; }
DEF="0=0 2=2 3=2 4=2 5=2 7=0"
LEV="0=1 2=4 3=0 4=4 5=0 7=1"
for p in "$@"; do
    echo "=== $p"
    case $p in
    soak)   setm $DEF; clr; for i in $(seq 1 12); do cyc 3; done; report; modes ;;
    levels) setm $LEV; clr; for i in 1 2 3; do cyc 3; echo "-- cycle $i"; report; clr; done; modes ;;
    back)   setm $DEF; clr; for i in 1 2 3; do cyc 3; done; report; modes ;;
    offset) setm $DEF; clr; $TAB off >/dev/null 2>&1; sleep 3; setm 2=4 0=1; $TAB on >/dev/null 2>&1; sleep 4
            echo "-- set while screen off, after on:"; report; modes; clr; cyc 3; echo "-- next cycle:"; report; setm $DEF ;;
    offgame) setm $DEF 0=1; clr; $TAB off >/dev/null 2>&1; sleep 3; setm 0=0; $TAB on >/dev/null 2>&1; sleep 4
            echo "-- game mode off while screen off (pen must follow game_mode_enable 0):"; report; modes; setm $DEF ;;
    rapid)  setm $LEV; clr; for i in $(seq 1 10); do $TAB off >/dev/null 2>&1; sleep 1; $TAB on >/dev/null 2>&1; sleep 1; done
            sleep 3; report; modes; setm $DEF ;;
    retry)  setm $DEF 2=4 4=0; clr; r "echo 1 > /sys/module/nt36xxx/parameters/fw_fail_test"; cyc 3; sleep 6; report; modes; setm $DEF ;;
    retrygame) setm $DEF 0=1 2=4; clr; r "echo 1 > /sys/module/nt36xxx/parameters/fw_fail_test"; cyc 3; sleep 6; report; modes; setm $DEF ;;
    esac
done
