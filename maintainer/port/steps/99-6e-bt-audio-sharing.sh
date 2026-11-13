#!/bin/sh
# 6e (BUGS-TODO 90, user 2026-11-09): audio sharing to two Bluetooth headphones (classic A2DP, software SBC).
#
# WirelessSettings, Bluetooth and SystemUI read ro.oplus.audio.support.audio_sharing. The flag is absent on the
# port, so the control in the media output picker is hidden. Live test on pt81 (resetprop -n, Bluetooth and SystemUI
# restarted): two headphones play at the same time (notes/BT-AUDIO-SHARING-20261109.md). No HAL, codec library,
# kernel or audio-policy change is needed. This is not LE Audio / Auracast (the controller has no ISO support).
# * product/etc/build.prop: ro.oplus.audio.support.audio_sharing=true (init loads product props with its own
#   context, so the property label does not matter for the load).
# * system_ext/etc/build.prop: ro.pipa.port.layer=6e.
set -eu
. "$PORT/lib.sh"
STEP=6e

P_NAME=ro.oplus.audio.support.audio_sharing
echo "== 6e Bluetooth audio sharing flag"
# one effective value: the flag must not exist in a build.prop of the tree
for f in $(find "$T" -maxdepth 4 -name build.prop -type f); do
    forbid_grep "^$P_NAME=" "$f"
done
BP=$T/product/etc/build.prop
[ -f "$BP" ] || die "no $BP"
{ cat "$BP"; printf '%s\n' "# pipa port 6e (BUGS-TODO 90): audio sharing to two Bluetooth headphones (classic A2DP)" \
    "$P_NAME=true"; } > "$R/build.prop.new"
cat "$R/build.prop.new" > "$BP"   # same inode: label, owner and mode kept
tail -2 "$BP"
need_grep "^$P_NAME=true\$" "$BP"
set_layer "$STEP"
