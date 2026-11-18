#!/bin/sh
# PARKED 2026-11-15: user chose stock 5 ms after research (Google moved 4 -> 5 ms on purpose; 4 ms gain <= 1 ms; nobody
# documents tuning it; 2 ms felt "maybe a tiny bit more jittery"). pt104 was built with it (4 ms), never flashed.
# Step 7d (user 2026-11-15, game touch latency; BUGS 120): input resample delay 4 ms instead of 5 ms.
# OPPO OplusLatencyOptimizerManager (oplus-services, LOMRusHelper) reads /data/system/sys_lom_config_list.xml (cloud RUS)
# or else /odm/etc/sys_lom_config_list.xml (prebuilt) and sets sys.input.resample.latency; OPPO's
# libinputextensionsimpl.so (InputTransportExtImpl::initResampleLatency) reads it in every app. Built-in defaults:
# version 2023012024, input thread sched on, resample on, 5 ms. The donor odm has no such file, so stock = defaults.
# This file keeps the defaults and only sets 4 ms: finger movement (aim, swipes) reaches apps ~1 ms sooner, taps
# unchanged (ACTION_DOWN is not batched). Trade-off (120 Hz touch = 8.3 ms reports, prediction capped at half of that):
# share of frames at the prediction cap 5 ms 0 %, 4 ms ~2 %, 3 ms ~14 %, 2 ms ~26 % (uneven steps on flicks).
# User live test 2026-11-15: 2 ms "better" in PUBG but "maybe a tiny bit more jittery"; 4 ms = no visible
# cost (AOSP: 5 ms "reduces the impact of mispredicted touch positions"; nobody documents tuning this online).
# Same version as the defaults: a newer OPPO cloud config wins.
set -eu
. "$PORT/lib.sh"
STEP=7d

E=$T/odm/etc
SIB=$E/gps_modem.cfg
[ -f "$SIB" ] || die "no $SIB (label template)"
F=$E/sys_lom_config_list.xml
[ -e "$F" ] && die "$F exists already (check what ships it)"
cp -p "$SIB" "$F"                       # owner, mode; label below
setfattr -n security.selinux -v "$(getfattr --only-values -n security.selinux "$SIB")" "$F"
cat > "$F" <<'XML'
<?xml version="1.0" encoding="utf-8"?>
<!-- pipa port 7d: OPPO latency optimizer defaults, input resample delay 4 ms (default 5) -->
<filter-conf>
    <version>2023012024</version>
    <inputThreadSchedConfig inputThreadSchedEnable="true"/>
    <inputResampleConfig inputResampleEnable="true" inputResampleLatency="4"/>
</filter-conf>
XML
need_grep 'inputResampleLatency="4"' "$F"
echo "created odm/etc/sys_lom_config_list.xml (resample 4 ms)"

set_layer "$STEP"
