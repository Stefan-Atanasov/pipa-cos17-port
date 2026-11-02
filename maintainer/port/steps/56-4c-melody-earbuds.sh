#!/bin/sh
# Phase 4c: OPPO earbuds pop-up and earbuds settings work (BUGS-TODO 38, public bug doc 2026-11-02; system only).
#
# The earbuds pop-up and the earbuds control page come from OPPO's "Wireless earphones" app Melody
# (my_stock/del-app/Melody). The beta4 edit list removes it as debloat (PORT-EDITS.tsv "/my_stock/del-app/Melody
# remove debloat"); a user found that the pop-up works after an install from the OPPO store. This step puts the donor
# APK back. del-app = preinstalled at the first boot, the user can uninstall it. On a dirty flash ColorOS may not
# install it: then install "Wireless earphones" from the App Market once.
#NEEDS: "$DONOR_IMG/my_stock.img"
set -eu
. "$PORT/lib.sh"

D=$T/system/my_stock/del-app
[ -d "$D" ] || die "no $D"
[ -e "$D/Melody" ] && die "$D/Melody exists already (base step changed?)"
python3 -I - "$DONOR_IMG/my_stock.img" "$D" <<'PY'
import os, subprocess, sys
img, d = sys.argv[1:]
r = subprocess.run(['dump.erofs', '--cat', '--path=/del-app/Melody/Melody.apk', img], capture_output=True)
if r.returncode != 0 or r.stdout[:2] != b'PK':
    sys.exit('cannot read /del-app/Melody/Melody.apk from the donor my_stock image')
# owner, mode and label from another del-app (dir and its APK)
sib = next(n for n in sorted(os.listdir(d)) if os.path.isfile(os.path.join(d, n, n + '.apk')))
sd, sf = os.path.join(d, sib), os.path.join(d, sib, sib + '.apk')
def same(dst, src):
    st = os.stat(src)
    os.chown(dst, st.st_uid, st.st_gid)
    os.chmod(dst, st.st_mode & 0o7777)
    os.setxattr(dst, 'security.selinux', os.getxattr(src, 'security.selinux'))
md = os.path.join(d, 'Melody')
os.mkdir(md)
same(md, sd)
f = os.path.join(md, 'Melody.apk')
open(f, 'wb').write(r.stdout)
same(f, sf)
print(f'added my_stock/del-app/Melody/Melody.apk ({len(r.stdout)} bytes, label from {sib})')
PY
