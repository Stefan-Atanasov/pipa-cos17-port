#!/bin/sh
# Phase 5n: no face camera worker crash in a dark room; no audit noise from OPPO's crash log collection (beta7).
#
# * facehal/lib64/libpipa_camguard.so (port-module/src/camguard.c), LD_PRELOADed by service.sh face_start: when the
#   first camera candidate gives only blank frames, facehal-rs retries with window=standard and hands an ANativeWindow
#   to libcamera2ndk_vendor, which wants a native_handle_t: "Failed to clone native_handle in hidl_handle: Bad file
#   descriptor", SIGABRT, tombstone (2026-11-03, 2026-11-05 x2). The guard returns ACAMERA_ERROR_INVALID_PARAMETER for
#   a pointer that is not a native handle: the HAL then reports "camera open failed" (the same result) without the
#   crash. Tested live 2026-11-05: normal unlock works, a forced refusal of all candidates ends cleanly.
# * facehal/VERSION includes the new library: face_install refreshes the /data copy.
# * rules_5n_system_ext.cil: dontaudit for OPPO crashbox/gaia log collection (debuglog `ps -A -T` sys_ptrace and
#   pid_max, the system_server dcs_env.txt fd) and system_app tombstone dir search. secilc exit 0, neverallow 76.
#NEEDS: "$ROM/pipa_port/facehal/lib64/libpipa_camguard.so" "$ROM/pipa_port/facehal/VERSION" "$ROM/pipa_port/service.sh" "$HERE/sepolicy/rules_5n_system_ext.cil"
set -eu
. "$PORT/lib.sh"
STEP=5n

SE=$T/system_ext
F=$SE/pipa_port/facehal
[ -f "$F/lib64/libpipa_eyeguard.so" ] || die "no $F/lib64/libpipa_eyeguard.so (step 3g missing?)"
install -o 0 -g 0 -m 644 "$ROM/pipa_port/facehal/lib64/libpipa_camguard.so" "$F/lib64/libpipa_camguard.so"
L=$(getfattr --only-values -n security.selinux "$F/lib64/libpipa_eyeguard.so" 2>/dev/null | tr -d '\0')
[ -n "$L" ] || die "no SELinux label on libpipa_eyeguard.so"
setfattr -n security.selinux -v "$L" "$F/lib64/libpipa_camguard.so"
cat "$ROM/pipa_port/facehal/VERSION" > "$F/VERSION"
need_grep libpipa_camguard.so "$F/VERSION"
cat "$ROM/pipa_port/service.sh" > "$SE/pipa_port/service.sh"
need_grep 'libpipa_camguard.so' "$SE/pipa_port/service.sh"
echo "facehal: libpipa_camguard.so ($L), VERSION, service.sh"

for f in system_ext_sepolicy.cil system_ext_sepolicy_debug.cil; do
    [ -f "$SE/etc/selinux/$f" ] || continue
    forbid_grep "pipa port 5n" "$SE/etc/selinux/$f"
    { cat "$SE/etc/selinux/$f"; cat "$HERE/sepolicy/rules_5n_system_ext.cil"; } > "$R/$f.new"
    cat "$R/$f.new" > "$SE/etc/selinux/$f"; rm -f "$R/$f.new"
    need_grep "pipa port 5n" "$SE/etc/selinux/$f"
done

set_layer "$STEP"
