#!/bin/sh
# Step 9h (2026-11-25, BUGS 193, user wish): OTA from several mirrors, delta updates first (Pipa Helper 3.6).
# latest.json "ota": {"payloads": [{"from": "<build tag>"?, "offset", "size", "headers", "urls": [...]}]}
# (maintainer/ota/latest_ota.py). The helper takes the delta whose "from" is the exact installed tag (variant included),
# then the full payload; it probes each mirror (1 MiB range request, must give 206 + payload magic CrAU) and sorts
# the mirrors by speed. service.sh ota_check tries each payload and each mirror in that order (update_engine resumes
# a partial download from another mirror). New guards in ota_check: no install on a -noenc build (ro.crypto.state is
# not "encrypted": the payload fstab wants encryption), and no install below 30 % battery without the charger.
# service.sh and the helper APK come from step 2e; this step checks that they hold the 9h code. No new SELinux rules:
# every domain reads vold_status_prop; the battery files are read by the charging code already.
set -eu
. "$PORT/lib.sh"
STEP=9h
SE=$T/system_ext
need_grep '^ota_try() {' "$SE/pipa_port/service.sh"
need_grep 'ro.crypto.state)" != encrypted' "$SE/pipa_port/service.sh"
need_grep 'battery below 30 %' "$SE/pipa_port/service.sh"
A=$T/system/system/priv-app/PipaHelper/PipaHelper.apk
[ -f "$A" ] || die "no $A"
python3 -I - "$A" <<'PY'
import sys, zipfile
z = zipfile.ZipFile(sys.argv[1])
dex = b"".join(z.read(n) for n in z.namelist() if n.endswith(".dex"))
for s in (b"pipa_update_ota", b"CrAU"):
    if s not in dex:
        sys.exit("helper APK without %s (helper 3.6 not built?)" % s.decode())
PY
echo "OTA mirrors + delta: service.sh ota_try and guards, helper 3.6 payload choice and mirror probe"
set_layer "$STEP"
