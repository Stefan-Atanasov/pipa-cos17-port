#!/system/bin/sh
# Night drain capture (BUGS battery): waits until the battery discharges (tablet unplugged), then writes a snapshot
# at once and every 30 min until it charges again or 14 h pass. Output: /data/local/tmp/nightcap/snap-<n>.txt
# Start (root, detached):  adb push nightcap.sh /data/local/tmp/ && adb shell "su -c 'setsid sh /data/local/tmp/nightcap.sh </dev/null >/dev/null 2>&1 &'"
# Analyse on the PC: python3 -I maintainer/battery/nightcap_diff.py <dir pulled from /data/local/tmp/nightcap>
O=/data/local/tmp/nightcap; mkdir -p $O; rm -f $O/snap-*.txt
B=/sys/class/power_supply/battery
while [ "$(cat $B/status)" = Charging ] || [ "$(cat $B/status)" = Full ]; do sleep 60; done
snap() {
	{ echo "date $(date +%s)"; echo "uptime $(cut -d' ' -f1 /proc/uptime)"
	  echo "capacity $(cat $B/capacity)"; echo "charge_counter $(cat $B/charge_counter)"; echo "status $(cat $B/status)"
	  echo "suspend_success $(cat /sys/power/suspend_stats/success)"; echo "suspend_fail $(cat /sys/power/suspend_stats/fail)"
	  echo "== system_sleep"; cat /sys/power/system_sleep/stats; echo "== master_stats"; cat /sys/power/rpmh_stats/master_stats
	  echo "== wakeup name active_count event_count wakeup_count total_time_ms"
	  for w in /sys/class/wakeup/*; do echo "ws $(cat $w/name) $(cat $w/active_count) $(cat $w/event_count) $(cat $w/wakeup_count) $(cat $w/total_time_ms)"; done
	  echo "== hybridswap"; head -3 /sys/block/zram0/hybridswap_stat_snap 2>/dev/null; grep -E 'pswpin|pswpout' /proc/vmstat
	  for p in $(pidof hybridswapd kswapd0 2>/dev/null); do echo "cpu $p $(cut -d' ' -f2,14,15 /proc/$p/stat)"; done
	  for p in $(ps -A -o PID,NAME | grep -E 'hybridswapd|kswapd' | awk '{print $1}'); do echo "kcpu $p $(cut -d' ' -f2,14,15 /proc/$p/stat)"; done
	  echo "== irq"; cat /proc/interrupts | awk 'NR>1{s=0; for(i=2;i<=9;i++) s+=$i; if (s>0) print $1, s, $NF}'
	} > $O/snap-$1.txt
}
n=0; snap $n; end=$(( $(date +%s) + 50400 ))
while [ "$(date +%s)" -lt $end ]; do
	sleep 1800; n=$((n+1)); snap $n
	s=$(cat $B/status); [ "$s" = Charging ] && break
done
