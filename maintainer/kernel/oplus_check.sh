#!/bin/sh
# Check that ColorOS "UI First" talks to the kernel (OPPO sched_assist / frame_boost / im on our WALT kernel). Read-only.
#   ADB="adb -s 83836a90" sh maintainer/kernel/oplus_check.sh
# Shows the OPLUS procfs nodes and sysctls, how many threads ColorOS has marked as UX (/proc/<pid>/task/<tid>/ux_state)
# with a sample of them, and the PerformanceService/SchedAssist open errors left in logcat (ENOENT = node missing).
ADB=${ADB:-adb -s 83836a90}
r() { $ADB shell "su -c '$1'" 2>&1 | tr -d '\r'; }
echo "== procfs";  r 'ls /proc/oplus_scheduler/sched_assist /proc/oplus_frame_boost /proc/oplus_locking 2>&1 | tr "\n" " "'; echo
echo "== sysctl";  r 'for f in /proc/sys/kernel/sched_assist_enabled /proc/sys/kernel/sched_assist_scene /proc/sys/kernel/uxchain_v2 /proc/sys/kernel/slide_boost_enabled /proc/sys/kernel/input_boost_enabled; do echo "$f=$(cat $f 2>&1)"; done'
echo "== ux threads (ux_state != 0)"
r 'n=0; t=0; for f in /proc/[0-9]*/task/[0-9]*/ux_state; do v=$(sed -n "s/.*ux_state=0x\\([0-9a-f]*\\).*/\\1/p" $f 2>/dev/null); t=$((t+1)); [ -n "$v" ] && [ "$v" != 00000000 ] && { n=$((n+1)); [ $n -le 25 ] && echo "  $v $(cat ${f%ux_state}comm) (${f#/proc/})"; }; done; echo "  $n of $t threads are UX"'
echo "== im_flag (sample)"; r 'grep -l -v "^0 " /proc/[0-9]*/task/[0-9]*/im_flag 2>/dev/null | head -8 | while read f; do echo "  $(cat $f) $(cat ${f%im_flag}comm)"; done'
echo "== logcat open errors"
r 'logcat -d | grep -E "PerformanceService|SchedAssist|OplusUIFirst" | grep -iE "fail|error|No such" | sed -E "s/^[0-9-]+ [0-9:.]+ +[0-9]+ +[0-9]+ //" | sort | uniq -c | sort -rn | head -8'
echo "== dmesg"; r 'dmesg | grep -iE "sched_assist|frame_boost|oplus_lock|ux_" | grep -iE "fail|error|warn" | head -5'
