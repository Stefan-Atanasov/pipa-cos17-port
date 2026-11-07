#!/bin/sh
# Phase 5z (beta8, Dolby 1:1 with HyperOS): the stock HyperOS 2 libhwdap (Dolby DAP effect library).
#
# beta4's vendor ships libhwdap patched by its porter: the status DMS returns is dropped and 0 is returned instead,
# in DapEffectContext::setDapParameter (32-bit, "ldr r4,[sp,#0x1c]" -> "movs r4,#0") and getDapParameter (32-bit
# "ldr r0,[sp,#4]" -> "movs r0,#0"; 64-bit "ldr w0,[sp,#4]" -> "mov w0,wzr"). So a real DMS error never reaches
# MiSound / DolbyAudioEffect. Test 2026-11-06 (pt70, stock 32-bit library bind-mounted into the 32-bit audio HAL):
# DS on, profile, GEQ on and the 20 GEQ gains get/set the way MiSound sends them all return success, no DMS error.
# The patch is not needed; this step restores the stock files (OS2.0.16, identical in OS2.0.13), lib and lib64.
#NEEDS: "$HERE/../../port-inputs/dolby-5z/SHA256SUMS"
set -eu
. "$PORT/lib.sh"
STEP=5z

IN=$HERE/../../port-inputs/dolby-5z
(cd "$IN" && sha256sum -c --quiet SHA256SUMS) || die "port-inputs/dolby-5z: checksum mismatch"
V=$T/vendor
# Only replace the exact porter-patched copies of beta4.
for x in "lib 3d0f075f3bde11440ea4d2949e2931b1" "lib64 b4e449181006cc140445c2058a77f9ec"; do
    b=${x% *}; m=${x#* }
    f=$V/$b/soundfx/libhwdap.so
    [ "$(md5sum < "$f" | cut -d' ' -f1)" = "$m" ] || die "vendor/$b/soundfx/libhwdap.so: not the beta4 patched copy"
    LABEL=$(getfattr -n security.selinux --only-values "$f")
    cat "$IN/vendor/$b/soundfx/libhwdap.so" > "$f"    # same inode, owner, mode and label
    [ "$(getfattr -n security.selinux --only-values "$f")" = "$LABEL" ] || die "label changed: $f"
    echo "edited  vendor/$b/soundfx/libhwdap.so"
done
md5sum "$V/lib/soundfx/libhwdap.so" "$V/lib64/soundfx/libhwdap.so"
set_layer "$STEP"
