#!/bin/sh
# snapshot.sh: read-only "same as before?" snapshot of the tablet, to compare two builds (BUGS 141: fs1a vs v9).
#   ADB="adb -s <serial>" sh maintainer/fromstock/snapshot.sh <label>        -> <root>/port-work/snapshots/<label>/
#   sh maintainer/fromstock/snapshot.sh --diff <labelA> <labelB>               -> what differs, short
# Take both snapshots the same way: reboot, unlock, wait until 3 minutes after boot_completed, then run.
# Needs root for dmesg (SukiSU: shell allowed). Changes nothing on the tablet.
set -eu
HERE=$(cd "$(dirname "$0")" && pwd); ROOT=${PIPA_ROOT:-$(cd "$HERE/../../.." && pwd)}
S=$ROOT/port-work/snapshots
if [ "${1:-}" = --diff ]; then
	A=$S/$2; B=$S/$3
	for f in $(cd "$A" && ls); do
		[ -f "$B/$f" ] || { echo "== $f: only in $2"; continue; }
		if ! cmp -s "$A/$f" "$B/$f"; then
			echo "== $f ($(diff "$A/$f" "$B/$f" | grep -c '^[<>]') lines differ; < $2, > $3)"
			diff "$A/$f" "$B/$f" | grep '^[<>]' | head -25
		fi
	done
	exit 0
fi
L=${1:?label}; O=$S/$L; mkdir -p "$O"
ADB=${ADB:-adb -s ${SERIAL:-83836a90}}
a() { $ADB shell "$@" < /dev/null 2>/dev/null | tr -d '\r'; }
[ "$(a getprop sys.boot_completed)" = 1 ] || { echo "tablet not booted"; exit 1; }
up=$(a cut -d. -f1 /proc/uptime); [ "$up" -ge 180 ] || echo "WARN: uptime ${up}s (< 180 s): wait, then run again for a fair compare"
a getprop | grep -v -E 'boottime|time\]|_ts\]|\.uuid|serialno|session|count\]|timestamp|ro\.pipa\.port\.(apps|layer)|bootcount|crash|wifi\.interface|\.pid\]|last_' | sort > "$O/props.txt"
a service list | sed -n 's/^[0-9]*[[:space:]]*\([^:]*\):.*/\1/p' | sort > "$O/services.txt"
a lshal --neat -i 2>/dev/null | awk '{print $1}' | sort -u > "$O/hidl.txt" || :
a dumpsys -l | sed 's/^ *//' | sort > "$O/dumpsys-l.txt"
a ps -A -o LABEL,NAME | awk 'NR>1{print $1, $2}' | grep -v -E 'kworker|ksoftirq|migration|irq/|cpuhp|rcu|kthread|\[' | sort -u > "$O/procs.txt"
a logcat -b all -d > "$O/logcat.raw" 2>/dev/null || :
grep -E 'FATAL EXCEPTION|Fatal signal|ANR in|tombstone|crashed|died, restarting|Service .* died' "$O/logcat.raw" | sed -E 's/^.{19}//; s/[0-9]{2,}/N/g' | sort | uniq -c | sort -rn > "$O/crashes.txt" || :
grep -o 'avc:  *denied  *{[^}]*} for .*scontext=[^ ]* tcontext=[^ ]* tclass=[^ ]*' "$O/logcat.raw" | sed -E 's/ (pid|ino|dev)=[^ ]*//g; s/name="[^"]*"//' | sort | uniq -c | sort -rn > "$O/denials.txt" || :
awk '$5=="E" || $5=="F" {$1=$2=$3=$4=""; print}' "$O/logcat.raw" | sed -E 's/^ +//; s/[0-9]{3,}/N/g; s/0x[0-9a-f]+/H/g' | sort | uniq -c | sort -rn | head -200 > "$O/errors-top.txt" || :
a su -c dmesg | grep -i -E 'error|fail|fatal|panic|warn|underrun|timeout' | sed -E 's/^\[[ 0-9.]+\] //; s/[0-9]{3,}/N/g' | sort | uniq -c | sort -rn | head -150 > "$O/dmesg-errors.txt" || :
{
	echo "wifi: $(a dumpsys wifi | grep -m1 -E '^Wi-Fi is' )"
	echo "bt: $(a settings get global bluetooth_on)"
	echo "audio devices: $(a dumpsys media.audio_flinger | grep -c 'Output thread')"
	echo "audio policy hw modules: $(a dumpsys media.audio_policy | grep -m1 -i 'Hardware modules')"
	echo "cameras: $(a dumpsys media.camera | grep -m1 'Number of camera devices')"
	echo "sensors: $(a dumpsys sensorservice | grep -c '^0x')"
	echo "display modes: $(a dumpsys display | grep -o -E 'fps=[0-9]+' | sort -u | tr '\n' ' ')"
	echo "input devices: $(a dumpsys input | sed -n '/Event Hub State/,/Input Reader State/p' | grep -E '^ +-?[0-9]+: [A-Za-z]' | sed 's/^ *-\{0,1\}[0-9]*: //' | sort | tr '\n' ';')"
	for h in power.IPower health.IHealth light.ILights thermal.IThermal boot.IBootControl wifi.IWifi vibrator.IVibrator graphics.composer3.IComposer; do
		echo "hal $h: $(a service check android.hardware.$h/default | sed 's/.*: //')"
	done
	echo "thermal hal: $(a dumpsys thermalservice | grep -m1 -i 'HAL Ready')"
	echo "battery: $(a dumpsys battery | grep -E 'status|health|present|technology' | tr -s ' ' | tr '\n' ' ')"
	echo "gpu: $(a dumpsys SurfaceFlinger | grep -m1 -E 'GLES:')"
	echo "selinux: $(a getenforce)"
	echo "root: $(a su -c id | cut -c1-20)"
} > "$O/state.txt"
gzip -f "$O/logcat.raw"      # kept for a closer look
echo "snapshot $L: $(ls "$O" | wc -l) files in $O (uptime ${up}s)"
