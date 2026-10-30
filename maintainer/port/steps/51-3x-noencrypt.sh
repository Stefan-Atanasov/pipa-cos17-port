#!/bin/sh
# Phase 3x (OPTIONAL, runs only with PORT_NOENCRYPT=1): /data without encryption (vendor only), for Linux dual boot.
#
# A Linux on the same tablet can read the Android /data only when it is not encrypted (FBE + metadata encryption on
# pipa). The /data line of vendor/etc/fstab.qcom loses fileencryption=, metadata_encryption=, keydirectory= and the
# inlinecrypt mount option. Android then formats /data without encryption on the first boot after a CLEAN flash
# (FlashLinux.sh "y"). A dirty flash over an encrypted /data does not boot correctly: always wipe when you change
# between the normal and this build. /metadata stays (f2fs checkpoint). Lock screen PIN and apps work; the data is
# readable by anyone with the tablet in the bootloader (no protection at rest).
#OPTIONAL: PORT_NOENCRYPT
#NEEDS: "$PORT/lib.sh"
set -eu
. "$PORT/lib.sh"
STEP=3x

if [ "${PORT_NOENCRYPT:-0}" != 1 ]; then
    echo "skipped (PORT_NOENCRYPT is not 1): /data stays encrypted (FBE + metadata encryption)"
    exit 0
fi
F=$T/vendor/etc/fstab.qcom
need_grep "fileencryption=" "$F"
python3 - "$F" <<'PY'
import re, sys
p = sys.argv[1]; s = open(p).read()
out = []; n = 0
for l in s.split("\n"):
    f = l.split()
    if len(f) >= 5 and f[1] == "/data":
        f[3] = ",".join(o for o in f[3].split(",") if o != "inlinecrypt")
        f[4] = ",".join(o for o in f[4].split(",") if not re.match(r"(fileencryption|metadata_encryption|keydirectory)=", o))
        l = "%-55s %-22s %-7s %s %s" % tuple(f[:5]); n += 1
    out.append(l)
assert n == 1, "expected one /data line, found %d" % n
open(p, "w").write("\n".join(out))
PY
forbid_grep "fileencryption=" "$F"
forbid_grep "metadata_encryption=" "$F"
grep -E "[[:space:]]/data[[:space:]]" "$F"
echo "== vendor/etc/fstab.qcom: /data without encryption (clean flash needed)"
