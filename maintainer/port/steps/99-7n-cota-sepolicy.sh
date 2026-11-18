#!/bin/sh
# Phase 7n: COTA data rules from the donor vendor policy (BUGS 127, 2026-11-18).
#
# * The donor vendor policy lets priv_app (com.oplus.cota) use /data/cota (data_cota_file). Our vendor is Xiaomi's, so
#   these OPPO vendor lines are missing. sepolicy/rules_7n_system_ext.cil adds the same two rules (unversioned) to
#   system_ext. SOTA app/opex/data paths otherwise need no extra rules (static check 2026-11-18: all types declared,
#   file labels as stock, 0 denials). Not added: platform_app -> ota_package_file (only com.oplus.ota, removed) and
#   vnd_opex_postinstall (its script exists neither on stock nor here). Compile check: sepolicy/secil_test.sh.
#NEEDS: "$HERE/sepolicy/rules_7n_system_ext.cil"
set -eu
. "$PORT/lib.sh"
STEP=7n

SE=$T/system_ext
for f in system_ext_sepolicy.cil system_ext_sepolicy_debug.cil; do
    [ -f "$SE/etc/selinux/$f" ] || continue
    forbid_grep "pipa port 7n" "$SE/etc/selinux/$f"
    { cat "$SE/etc/selinux/$f"; cat "$HERE/sepolicy/rules_7n_system_ext.cil"; } > "$R/$f.new"
    cat "$R/$f.new" > "$SE/etc/selinux/$f"; rm -f "$R/$f.new"
    need_grep "pipa port 7n" "$SE/etc/selinux/$f"
done
echo "system_ext sepolicy: cota rules (7n)"

set_layer "$STEP"
