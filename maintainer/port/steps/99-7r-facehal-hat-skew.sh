#!/bin/sh
# Phase 7r: face unlock works again after the PIN once it was locked out (BUGS 132, user 2026-11-18: "fail face twice,
# it wants the password, and face stays disabled even after the password; must re-add face").
#
# * facehal-rs resetLockout checks the HardwareAuthToken timestamp against /proc/uptime and rejects one more than
#   5 s in the future. pipa's gatekeeper clock counts from power-on and runs ~5.8 s ahead (keystore2 add_auth_token
#   timestamp vs /proc/uptime, 2026-11-18), so every PIN token failed: "FaceResetLockoutClient: Error during
#   resetLockout: 2"; only a new enrollment cleared lockout.bin.
# * maintainer/facehal/patch_hat_skew.py: one MOVZ, 5000 -> 65535 ms (the 10 min age limit stays). port-rom/ is
#   gitignored (blobs), so the patch is applied here to the tree copy (already-patched input is accepted). The VERSION
#   line gets the new md5, so face_install refreshes the /data copy on first boot.
#NEEDS: "$HERE/facehal/patch_hat_skew.py"
set -eu
. "$PORT/lib.sh"
STEP=7r
D=$T/system_ext/pipa_port/facehal
F=$D/android.hardware.biometrics.face-service.facehal
N=./android.hardware.biometrics.face-service.facehal
[ -f "$F" ] || die "no $F"
if out=$(python3 -I "$HERE/facehal/patch_hat_skew.py" "$F" "$R/facehal.7r" 2>&1); then
    cat "$R/facehal.7r" > "$F"; rm -f "$R/facehal.7r"     # in place: owner, mode and label stay
    echo "$out"
else
    [ "$out" = "already patched" ] || die "facehal HAT skew patch: $out"
    echo "facehal: HAT skew patch already in the binary"
fi
m=$(md5sum "$F" | cut -d' ' -f1)
need_grep "  $N\$" "$D/VERSION"
awk -v m="$m" -v n="$N" '$2 == n { $0 = m "  " n } { print }' "$D/VERSION" > "$R/VERSION.7r"
cat "$R/VERSION.7r" > "$D/VERSION"; rm -f "$R/VERSION.7r"
need_grep "^$m  $N\$" "$D/VERSION"
echo "facehal: VERSION $m (7r)"
set_layer "$STEP"
