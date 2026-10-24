#!/system/bin/sh
# ktrace.sh start|stop <out>: focused kernel trace (scheduler placement/migration/isolation) via tracefs, no traced needed.
T=/sys/kernel/tracing
case $1 in
start)
	echo 0 > $T/tracing_on; echo > $T/trace; echo 65536 > $T/buffer_size_kb
	echo 0 > $T/events/enable
	for e in sched/sched_switch sched/sched_wakeup sched/sched_waking sched/sched_migrate_task sched/sched_isolate \
	         sched/core_ctl_eval_need sched/core_ctl_set_busy sched/sched_set_boost sched/sched_boost_cpu \
	         power/cpu_frequency power/cpu_idle; do
		[ -e $T/events/$e/enable ] && echo 1 > $T/events/$e/enable
	done
	echo 1 > $T/tracing_on ;;
stop)
	echo 0 > $T/tracing_on; cat $T/trace > "${2:-/data/local/tmp/ktrace.txt}"; echo 0 > $T/events/enable; echo > $T/trace ;;
esac
