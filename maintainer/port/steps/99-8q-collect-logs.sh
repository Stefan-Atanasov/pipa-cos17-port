#!/bin/sh
# Phase 8q (2026-11-20): Pipa Helper 2.7 "Collect logs" + Wi-Fi failure notice + Games list fix.
# * Helper > System > Collect logs sets Global pipa_logs = 1; service.sh logs_check runs pipa_port/collect_logs.sh once:
#   build info, logcat (all buffers), dmesg, port logs and the 8p Wi-Fi snapshots, redacted with pipa_port/redact.sed
#   (emails, MAC addresses, phone numbers, IMEIs, Wi-Fi names and passwords, account/device names, coordinates; checked
#   on the maintainer tablet: none of its personal strings left), into /data/misc/pipa_logs/pipa-logs-<time>.tar.gz.
#   The helper (LogsKeeper) copies it into Downloads via MediaStore and posts a share notification.
# * New type pipa_logs_file (maintainer/sepolicy/rules_8q_system_ext.cil): the helper (priv_app) may read only it.
#   On-device secilc compile OK, neverallow count 76 = donor base.
# * b1_capture.sh (8p) sets Global pipa_b1_last: the helper shows "Wi-Fi problem logged".
# * GameKeeper: a game added to the list while it is open gets the game profile at once.
# The scripts come with the pipa_port folder (step 2e copies it).
set -eu
. "$PORT/lib.sh"
STEP=8q
SE=$T/system_ext
need_grep 'logs_check' "$SE/pipa_port/service.sh"
[ -f "$SE/pipa_port/collect_logs.sh" ] || die "no collect_logs.sh"
[ -f "$SE/pipa_port/redact.sed" ] || die "no redact.sed"
need_grep 'pipa_b1_last' "$SE/pipa_port/b1_capture.sh"
for f in system_ext_sepolicy.cil system_ext_sepolicy_debug.cil; do
    [ -f "$SE/etc/selinux/$f" ] || continue
    forbid_grep "pipa port 8q" "$SE/etc/selinux/$f"
    { cat "$SE/etc/selinux/$f"; cat "$HERE/sepolicy/rules_8q_system_ext.cil"; } > "$R/$f.new"
    cat "$R/$f.new" > "$SE/etc/selinux/$f"; rm -f "$R/$f.new"
    need_grep "pipa port 8q" "$SE/etc/selinux/$f"
done
FC=$SE/etc/selinux/system_ext_file_contexts
[ -f "$FC" ] || die "no $FC"
forbid_grep 'pipa_logs_file' "$FC"
[ -z "$(tail -c 1 "$FC")" ] || echo >> "$FC"   # last line must end with a newline
printf '%s\n' '/data/misc/pipa_logs(/.*)?      u:object_r:pipa_logs_file:s0' >> "$FC"
need_grep '^/data/misc/pipa_logs' "$FC"
echo "system_ext_file_contexts: /data/misc/pipa_logs -> pipa_logs_file"
python3 -I - "$HERE/../helper/out/PipaHelper.apk" "$T/system/system/priv-app/PipaHelper/PipaHelper.apk" <<'PY'
import sys, zipfile, hashlib
src, img = sys.argv[1:]
d = b''.join(zipfile.ZipFile(src).read(n) for n in zipfile.ZipFile(src).namelist() if n.endswith('.dex'))
for s in (b'pipa_logs_uri', b'pipa_b1_last'):
    assert s in d, 'PipaHelper.apk without %s' % s.decode()
a = hashlib.md5(open(src, 'rb').read()).hexdigest(); b = hashlib.md5(open(img, 'rb').read()).hexdigest()
assert a == b, 'image helper %s != helper/out %s' % (b, a)
print('helper 2.7 (Collect logs) in the image', a)
PY
set_layer "$STEP"
