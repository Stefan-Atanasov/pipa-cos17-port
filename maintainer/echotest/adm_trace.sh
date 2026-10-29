#!/system/bin/sh
# Trace the ADSP ADM opens and the EC reference setup (BUGS-TODO 27). Run as root on the tablet:
#   sh adm_trace.sh start; <run a test>; sh adm_trace.sh dump; sh adm_trace.sh stop
# Live only: a reboot removes the probes.
T=/sys/kernel/tracing
stop() {
    for e in admo ecid ecch ecsr; do
        echo 0 > $T/events/kprobes/$e/enable 2>/dev/null
        echo "-:$e" >> $T/kprobe_events 2>/dev/null
    done
}
case $1 in
start)
    stop
    echo "p:admo adm_open port=%x0:x32 path=%x1:s32 rate=%x2:s32 ch=%x3:s32 topo=%x4:x32 perf=%x5:s32 bw=%x6:u16 app=%x7:s32" >> $T/kprobe_events
    echo "p:ecid adm_ec_ref_rx_id port=%x0:x32" >> $T/kprobe_events
    echo "p:ecch adm_num_ec_ref_rx_chans n=%x0:s32" >> $T/kprobe_events
    echo "p:ecsr adm_ec_ref_rx_sampling_rate r=%x0:s32" >> $T/kprobe_events
    echo > $T/trace
    for e in admo ecid ecch ecsr; do echo 1 > $T/events/kprobes/$e/enable; done
    echo 1 > $T/tracing_on
    ;;
dump) grep -E "admo|ecid|ecch|ecsr" $T/trace | sed -E 's/^ +//; s/ +\[[0-9]+\] [^ ]+ / /' ;;
stop) stop ;;
esac
