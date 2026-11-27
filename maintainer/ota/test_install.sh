#!/bin/bash
# BUGS 193 maintainer test: install an OTA payload from port-work/ota/<tag>/ on the tablet with root update_engine_client
# (no helper, no pipa_port). The zip goes to /data/ota_package (label ota_package_file), update_engine writes the other
# slot (Virtual A/B snapshots in /data); afterwards: reboot into the other slot by hand.
#   bash maintainer/ota/test_install.sh <tag> [adb serial]
# Cancel a running install: adb shell "su -c 'update_engine_client --cancel'"; undo a finished one before the reboot:
# adb shell "su -c 'update_engine_client --reset_status'".
set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
P=$(cd "$HERE/../../.." && pwd)
TAG=$1
S=${2:-$(adb get-serialno)}
a() { adb -s "$S" "$@"; }
D=$P/port-work/ota/$TAG
Z=$D/ota-$TAG.zip
[ -s "$Z" ] && [ -s "$D/ota-$TAG.txt" ] || { echo "no $Z (make_payload.sh first)"; exit 1; }
OFF=$(sed -n 's/^offset=//p' "$D/ota-$TAG.txt")
SIZE=$(sed -n 's/^size=//p' "$D/ota-$TAG.txt")
HDR=$(tr -d '\r' < "$D/payload_properties.txt")
echo "== slot now: $(a shell getprop ro.boot.slot_suffix | tr -d '\r'), build $(a shell cat /system_ext/pipa_port/build | tr -d '\r')"
echo "== push $(du -h "$Z" | cut -f1) to the tablet"
a push "$Z" /data/local/tmp/ota.zip
a shell "su -c 'mv /data/local/tmp/ota.zip /data/ota_package/ota-$TAG.zip && chown system:cache /data/ota_package/ota-$TAG.zip && chmod 0644 /data/ota_package/ota-$TAG.zip && restorecon /data/ota_package/ota-$TAG.zip && ls -lZ /data/ota_package/'"
echo "== update_engine_client (log: port-work/ota/$TAG/install.log)"
printf '%s\n' "$HDR" > "$D/headers.txt"
a push "$D/headers.txt" /data/local/tmp/ota_headers.txt >/dev/null
a shell "su -c 'update_engine_client --update --follow --payload=file:///data/ota_package/ota-$TAG.zip --offset=$OFF --size=$SIZE --headers=\"\$(cat /data/local/tmp/ota_headers.txt)\"'" 2>&1 \
    | tee "$D/install.log" | grep --line-buffered -E 'onStatusUpdate\(UPDATE_STATUS_(DOWNLOADING|FINALIZING|UPDATED)|onPayloadApplicationComplete|ERROR' \
    | awk -F', ' '{ s = $0; if (s ~ /DOWNLOADING/) { p = int($2 * 100); if (p == last) next; last = p } print s; fflush() }'
rc=${PIPESTATUS[0]}
a shell "su -c 'rm -f /data/local/tmp/ota_headers.txt'"
echo "== update_engine_client exit $rc"
grep -E 'onPayloadApplicationComplete' "$D/install.log" | tail -1
