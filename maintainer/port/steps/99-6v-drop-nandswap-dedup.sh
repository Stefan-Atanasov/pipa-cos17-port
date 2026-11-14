#!/bin/sh
# Step 6v (BUGS-TODO 89, user 2026-11-14): remove pipa_port's nandswap_dedup. It removed extra loop swap areas that the
# beta4 porter's odm mm-sys.sh attached after each zygote restart. Since 6t OPPO's own init.oplus.nandswap.sh runs: it
# stops at sys.oplus.nandswap.init=true on a second run (no second zram or loop setup), its rc removes /data/nandswap at
# every boot, and with walt-r24 the eswap file is used by hybridswap, not as a swap area (/proc/swaps has no loop).
# service.sh comes from port-rom (step 07 copies it); this step checks it and sets the layer.
set -eu
. "$PORT/lib.sh"
STEP=6v
forbid_grep 'nandswap_dedup' "$T/system_ext/pipa_port/service.sh"
echo "checked service.sh: no nandswap_dedup"
set_layer "$STEP"
