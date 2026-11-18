#!/bin/sh
# PARKED 2026-11-15 (wrong premise): COSA wants incell_panel EMPTY or missing (oiface returns "" = multi touch rate
# supported; "3" = delayed writes; anything else = unsupported, UI hidden, no node 26 writes). Kernel hi2 ("1") made it
# worse; reverted (wt-healthinfo 6a6774cafe33). pt102 contains this step but it is inert without the node.
# Step 7b (BUGS 117, PUBG touch delay at 120 fps): Game Space "Touch sampling rate: Ultra" did nothing on the port.
# COSA (com.oplus.cosa) writes the touch rate node (26 -> touchshim 4o -> Xiaomi game mode 0) only if oiface can read
# /proc/touchpanel/incell_panel, a stock OPPO touch driver node. Kernel walt-hi2 adds it to nt36532 ("1");
# this step labels it and lets oiface read it. secil_test.sh on the tablet: exit 0, neverallow count 76 (unchanged).
#NEEDS: "$HERE/sepolicy/rules_7b_system_ext.cil"
set -eu
. "$PORT/lib.sh"
STEP=7b

SE=$T/system_ext/etc/selinux
for f in system_ext_sepolicy.cil system_ext_sepolicy_debug.cil; do
    [ -f "$SE/$f" ] || continue
    forbid_grep "pipa port 7b" "$SE/$f"
    { cat "$SE/$f"; cat "$HERE/sepolicy/rules_7b_system_ext.cil"; } > "$R/$f.new"
    cat "$R/$f.new" > "$SE/$f"; rm -f "$R/$f.new"   # same inode
    echo "edited  system_ext/etc/selinux/$f"
done
need_grep "pipa port 7b" "$SE/system_ext_sepolicy.cil"

set_layer "$STEP"
