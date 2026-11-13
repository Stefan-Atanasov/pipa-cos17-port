#!/bin/sh
# Live A/B profiles for the RAM work (BUGS 89, 99; plan: notes/RAM-RESEARCH-20261112.md). Run over ADB, root.
#
#   sh mem_ab.sh save            store the current values on the tablet (do this once, 5 min after a boot)
#   sh mem_ab.sh show            current values
#   sh mem_ab.sh <profile>       apply one profile on top of the saved base (live; a reboot removes it)
#   sh mem_ab.sh restore         back to the saved base values
#
# Profiles change ONE thing each, so that an A/B run shows what that one thing does:
#   pc0      page-cluster 0                    (no 8-page swap-in readahead)
#   sw60     swappiness 60                     (compare with the base 100 that mm-sys.sh asks for)
#   wsf50    watermark_scale_factor 50         (kswapd starts earlier; min/extra free unchanged)
#   wsf100   watermark_scale_factor 100
#   lmk      lmkd: psi_partial 50, psi_complete 150, thrashing_limit 50, swap_free_low 20, kill_heaviest
#   lmk6     as lmk with thrashing_limit 30    (6 GB)
#   nocompact  framework app compaction off (device_config, live)
# Not here (needs a reboot): RAM expansion off = Settings > RAM expansion off (persist.sys.oplus.nandswap=false),
# zram size (mm-sys.sh at boot). The ro.lmk.* changes use resetprop and `lmkd --reinit`.
# Measure each with `SAMPLE=60 sh maintainer/mem_check.sh <profile>` in the same game session (A/B rule in the note).
set -eu
ADB=${ADB:-adb -s 192.168.0.37:5555}
cmd=${1:?usage: mem_ab.sh save|show|restore|<profile>}
VM="swappiness page-cluster watermark_scale_factor min_free_kbytes extra_free_kbytes"
LMK="ro.lmk.psi_partial_stall_ms ro.lmk.psi_complete_stall_ms ro.lmk.thrashing_limit ro.lmk.swap_free_low_percentage ro.lmk.kill_heaviest_task"
BASE=/data/local/tmp/mem_ab_base.txt

run() { $ADB shell "su -c 'sh'"; }

case $cmd in
save)
    run <<EOF
{ for k in $VM; do echo "vm \$k \$(cat /proc/sys/vm/\$k 2>/dev/null)"; done
  for p in $LMK; do echo "prop \$p \$(getprop \$p)"; done
  echo "dc use_compaction \$(device_config get activity_manager use_compaction)"; } > $BASE
cat $BASE
EOF
    ;;
show)
    run <<EOF
for k in $VM; do printf '%-26s %s\n' \$k "\$(cat /proc/sys/vm/\$k)"; done
for p in $LMK; do printf '%-36s %s\n' \$p "\$(getprop \$p)"; done
echo "use_compaction \$(device_config get activity_manager use_compaction)"
EOF
    ;;
restore)
    run <<EOF
[ -s $BASE ] || { echo "no saved base: run save first"; exit 1; }
while read t k v; do
    case \$t in
    vm) [ -n "\$v" ] && echo "\$v" > /proc/sys/vm/\$k ;;
    prop) if [ -n "\$v" ]; then resetprop -n \$k "\$v"; else resetprop -d \$k 2>/dev/null || true; fi ;;
    dc) if [ "\$v" = null ] || [ -z "\$v" ]; then device_config delete activity_manager use_compaction >/dev/null; else device_config put activity_manager use_compaction "\$v"; fi ;;
    esac
done < $BASE
lmkd --reinit 2>/dev/null || true
echo restored
EOF
    ;;
pc0|sw60|wsf50|wsf100|lmk|lmk6|nocompact)
    run <<EOF
[ -s $BASE ] || { echo "no saved base: run save first"; exit 1; }
case $cmd in
pc0)    echo 0 > /proc/sys/vm/page-cluster ;;
sw60)   echo 60 > /proc/sys/vm/swappiness ;;
wsf50)  echo 50 > /proc/sys/vm/watermark_scale_factor ;;
wsf100) echo 100 > /proc/sys/vm/watermark_scale_factor ;;
lmk|lmk6)
    t=50; [ $cmd = lmk6 ] && t=30
    resetprop -n ro.lmk.psi_partial_stall_ms 50; resetprop -n ro.lmk.psi_complete_stall_ms 150
    resetprop -n ro.lmk.thrashing_limit \$t; resetprop -n ro.lmk.swap_free_low_percentage 20
    resetprop -n ro.lmk.kill_heaviest_task true
    lmkd --reinit ;;
nocompact) device_config put activity_manager use_compaction false ;;
esac
echo "applied $cmd (live; restore or reboot to undo)"
EOF
    ;;
*) echo "unknown: $cmd"; exit 2 ;;
esac
