#!/bin/sh
# Step 6u (BUGS-TODO 89/99, 111; 2026-11-14):
# * 3 kswapd threads at boot_completed (port-rom/pipa_port.rc). Kernel walt-r23 brings OPPO's stock MULTI_KSWAPD and
#   ZRAM_OPT (swappiness 200 / direct 60 from OPPO's init.oplus.nandswap.sh, step 6t). With one kswapd, swappiness 200
#   (zstd) gave 5-6x more direct reclaim stalls in the PUBG Training Ground + RAM churn test; with 3: 935 avg (r22 at
#   60: 1091), frames/audio clean in all runs (port-work/mem-checks/*-load-r2[23]-*). The stock setter of
#   vm.kswapd_threads is not in our refs (OPPO apps/services do not write it).
# * pipa_port pen input only while the pen is connected over BT (service.sh PEN_BT_ONLY): "pen on" at connect and at
#   screen-on while connected, "pen off" at disconnect (was: "pen on" after every screen-on).
# Both files come from port-rom (step 07 copies them); this step checks them and sets the layer.
set -eu
. "$PORT/lib.sh"
STEP=6u
need_grep 'write /proc/sys/vm/kswapd_threads 3' "$T/system_ext/etc/init/pipa_port.rc"
need_grep 'PEN_BT_ONLY' "$T/system_ext/pipa_port/service.sh"
need_grep '^PEN_BT_ONLY=1$' "$T/system_ext/pipa_port/config.prop"
echo "checked pipa_port.rc (kswapd_threads 3), service.sh + config.prop (PEN_BT_ONLY)"
set_layer "$STEP"
