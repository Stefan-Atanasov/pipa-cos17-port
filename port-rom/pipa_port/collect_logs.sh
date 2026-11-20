#!/system/bin/sh
# 8q (Pipa Helper > System > Collect logs): the pipa_port service runs this once per request (global pipa_logs = 1).
# Build info, logcat (all buffers), dmesg, the port logs and the Wi-Fi failure snapshots (8p) go into
# /data/misc/pipa_logs/pipa-logs-<time>.tar.gz after redact.sed removed emails, MAC addresses, phone numbers, IMEIs,
# Wi-Fi names, account names and coordinates. The helper copies the file into Downloads (MediaStore) and offers to
# share it. Type pipa_logs_file: the helper (priv_app) may read only this (maintainer/sepolicy/rules_8q_system_ext.cil).
D=/data/misc/pipa_logs
W=$D/work
SED=/system_ext/pipa_port/redact.sed
mkdir -p "$D"   # init creates it with the pipa_logs_file label at boot (pipa_port.rc + system_ext_file_contexts)
rm -rf "$W"; mkdir -p "$W"
ts=$(date +%Y%m%d-%H%M%S)
{
    echo "== pipa logs $ts"
    for p in ro.build.display.id ro.pipa.port.layer ro.product.model ro.boot.slot_suffix ro.boot.verifiedbootstate \
             ro.build.version.release ro.build.version.security_patch persist.sys.locale; do
        echo "$p=$(getprop $p)"
    done
    echo "kernel: $(uname -r) $(uname -v)"
    echo "uptime: $(cat /proc/uptime)"
    echo "== memory"; head -n 5 /proc/meminfo
    echo "== storage /data (free / total, MB)"; stat -f -c "%a %b %S" /data 2>&1 | while read -r a b s; do m=$((1048576 / s)); echo "$((a / m)) / $((b / m))"; done   # mksh: 32-bit maths, divide first
} > "$W/info.txt" 2>&1
logcat -d -b all -v threadtime </dev/null > "$W/logcat.txt" 2>&1
dmesg > "$W/dmesg.txt" 2>&1
cp /data/local/tmp/pipa_port.log "$W/pipa_port.log" 2>/dev/null
tail -n 3000 /data/local/tmp/facehal.log > "$W/facehal.log" 2>/dev/null
for f in /data/misc/pipa_port/b1-*.txt; do [ -f "$f" ] && cp "$f" "$W/"; done
for f in "$W"/*; do sed -E -i -f "$SED" "$f"; done
out=pipa-logs-$ts.tar.gz
tar -czf "$D/$out" -C "$W" . 2>/dev/null
rm -rf "$W"
chmod 0644 "$D/$out"
ls -t "$D"/pipa-logs-*.tar.gz 2>/dev/null | tail -n +3 | while read -r o; do rm -f "$o"; done
[ -s "$D/$out" ] && echo "$out"
