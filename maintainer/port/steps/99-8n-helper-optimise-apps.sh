#!/bin/sh
# Phase 8n (2026-11-20): Pipa Helper 2.6 > System > "Optimise apps". The helper sets global pipa_dexopt = 1; the
# pipa_port service (dexopt_check) runs ART's background dexopt job once (`pm bg-dexopt-job`, the stock job of the
# idle + charging maintenance window), sets 2 while it runs, 0 after, and pipa_dexopt_last = end time.
# Why: after a ROM update most apps run from "verify" until the night job (pt142 after the flash: 342 verify,
# 17 compiled). Idea from the Xiaomi Pad 5 ColorOS 17 port ("one-time background app optimization"); here only on the
# user's request (no automatic run, no battery cost otherwise). Uses the binder and settings rules that speed_compile
# and fx_check already need. The scripts come with the pipa_port folder (steps 2d/2f).
set -eu
. "$PORT/lib.sh"
STEP=8n
SE=$T/system_ext/pipa_port
need_grep 'dexopt_check' "$SE/service.sh"
need_grep 'pm bg-dexopt-job' "$SE/service.sh"
python3 -I - "$HERE/../helper/out/PipaHelper.apk" "$T/system/system/priv-app/PipaHelper/PipaHelper.apk" <<'PY'
import sys, zipfile, hashlib
src, img = sys.argv[1:]
d = b''.join(zipfile.ZipFile(src).read(n) for n in zipfile.ZipFile(src).namelist() if n.endswith('.dex'))
assert b'pipa_dexopt' in d, 'PipaHelper.apk without pipa_dexopt'
a = hashlib.md5(open(src, 'rb').read()).hexdigest(); b = hashlib.md5(open(img, 'rb').read()).hexdigest()
assert a == b, 'image helper %s != helper/out %s' % (b, a)
print('helper 2.6 (Optimise apps) in the image', a)
PY
set_layer "$STEP"
