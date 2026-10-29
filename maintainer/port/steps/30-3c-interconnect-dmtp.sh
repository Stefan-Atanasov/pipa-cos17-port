#!/bin/sh
# Phase 3c: interconnect network/call/SMS sharing reaches the phone (BUGS-TODO B9), on top of 3b (system +
# system_ext).
#
# * system_ext sepolicy: com.oplus.subsys (system_app) was denied binder call to commcenterd (hal_radio_default,
#   IDmtpService), so its DMTP client never registered (forbid bit 128, no virtual comm link). Four rules in the
#   pipa block: system_app <-> hal_radio_default binder call/transfer, fd use, find hal_radio_service.
# * system_ext/etc/init/pipa_port.rc: persist.radio.multisim.config=dsds and persist.vendor.radio.virtualcomm=1 at
#   post-fs-data (the OPPO odm sets them; pipa's odm does not). With one phone slot com.android.phone crashed in a
#   loop (OplusVmServiceStateOberser.updateVoiceRegstateResult, index 1 of length 1).
# * system_ext/etc/build.prop: ro.pipa.port.layer=3c (early.sh clears the package cache).
# Still missing for network sharing: the OPPO kernel netdev "ovnet" (ip link add ovnet0 type ovnet bind p2p0 ...).
#
# Old layer script: build_beta5_3c.sh
#NEEDS: "$ROM/pipa_port.rc"
set -eu
. "$PORT/lib.sh"
STEP=3c

S=$T/system
SE=$T/system_ext

echo "== B9: pipa_port.rc (dual virtual SIM slots)"
cat "$ROM/pipa_port.rc" > "$SE/etc/init/pipa_port.rc"
need_grep '^    setprop persist.radio.multisim.config dsds$' "$SE/etc/init/pipa_port.rc"
echo "updated system_ext/etc/init/pipa_port.rc"

echo "== B9: system_app <-> commcenterd (DMTP)"
for f in etc/selinux/system_ext_sepolicy.cil etc/selinux/system_ext_sepolicy_debug.cil; do
    [ -f "$SE/$f" ] || { echo "skip    $f (absent)"; continue; }
    python3 -I - "$SE/$f" <<'PY'
import sys
p = sys.argv[1]
a = '(allow bluetooth ISubsysService (service_manager (find)))\n'
b = (';; B9 (3c): com.oplus.subsys (system_app) registers its DMTP client at commcenterd (hal_radio_default)\n'
     '(allow system_app hal_radio_default (binder (call transfer)))\n'
     '(allow hal_radio_default system_app (binder (call transfer)))\n'
     '(allow hal_radio_default system_app (fd (use)))\n'
     '(allow system_app hal_radio_service (service_manager (find)))\n')
s = open(p, encoding='utf-8', errors='surrogateescape').read()
if s.count(a) != 1:
    sys.exit(f'{p}: anchor found {s.count(a)} times, expected 1')
with open(p, 'r+', encoding='utf-8', errors='surrogateescape') as f:   # same inode: label kept
    f.write(s.replace(a, a + b)); f.truncate()
PY
    echo "edited  system_ext/$f"
done

echo "== system_ext build.prop: ro.pipa.port.layer=$STEP"
set_layer "$STEP"

# Step 3f must start from the same system tree as the old 3c (3d and 3e do not touch system). The old 3f
# checked that with `cmp 3c/img/system.img 3e/img/system.img`. There is no per-step image now, so record a
# fingerprint (names, sizes, times, owners, modes; no file content) here and let 3f compare it.
mkdir -p "$ORIG"
fingerprint "$T/system" > "$ORIG/system.fp-after-3c"
echo "system fingerprint after 3c: $(cat "$ORIG/system.fp-after-3c")"

