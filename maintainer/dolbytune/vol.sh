#!/bin/bash
# vol.sh N : set music volume (index 0..160, steps of 10) with volume keys; also select the stock tuning for that level
want=$1
for i in $(seq 20); do cur=$(adb -s 83836a90 shell 'cmd media_session volume --stream 3 --get' 2>/dev/null | grep -o 'volume is [0-9]*' | grep -o '[0-9]*$')
  [ "$cur" = "$want" ] && break; if [ "$cur" -lt "$want" ]; then k=24; else k=25; fi; adb -s 83836a90 shell input keyevent $k; sleep 0.3; done
if [ "$want" -gt 106 ]; then t=speaker_volume_high; else t=speaker_volume_low; fi
adb -s 83836a90 shell "CLASSPATH=/data/local/tmp/ctl.dex app_process /system/bin Ctl tune=0:$t" 2>&1 | grep -v WARN
echo "volume $cur tuning $t"
