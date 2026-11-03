#!/bin/sh
# Phase 4z: a boot image that matches our boot jars (BUGS-TODO 65 health check; system only).
#
# The donor's prebuilt boot image is a chain: boot.* (ART module jars) -> boot-framework.* (framework.jar,
# oplus-framework.jar, ...) -> boot-framework-{graphics,location,nfc,telecom,ondeviceintelligence,adservices}.*.
# Steps 3o (framework.jar) and 4h (oplus-framework.jar) change boot jars. ART then rejects boot-framework.oat at
# runtime ("dex file checksum 0x60e6b8f6 does not match checksum 0x6e87c06e of external dex file framework.jar") and
# with it the rest of the chain: the framework code of every app and of SystemUI runs without AOT code (interpreter +
# JIT). This is so since 3o (pt11, beta6). odrefresh does not see it (its --check said "ok"), so odsign never compiled a
# new boot image; it only compiled services.jar and oplus-services.jar.
# * system/framework/{,arm/,arm64/}boot*: the whole prebuilt boot image is removed (one primary image of ~17
#   components; boot-oplus-framework is also stale since 4h). odrefresh then finds "incomplete primary boot image on
#   /system" and compiles the primary boot image and the mainline extension into /data/misc/apexdata/com.android.art
#   at the first boot (odsign signs them). Manual test 2026-11-03 (odrefresh --force-compile, primary image first):
#   20 s. pt39 removed only boot-framework*: then odrefresh compiled only the adservices extension on top of the
#   incomplete system image, and dex2oat aborted (InitWithoutImage, "Check failed: new_exception != nullptr").
set -eu
. "$PORT/lib.sh"

F=$T/system/system/framework
[ -f "$F/arm64/boot-framework.oat" ] || die "no $F/arm64/boot-framework.oat (donor without a prebuilt boot image?)"
n=0
for f in "$F"/boot* "$F"/arm/boot* "$F"/arm64/boot*; do
    [ -e "$f" ] || [ -L "$f" ] || continue
    rm -f "$f"; n=$((n + 1))
done
echo "removed $n prebuilt boot image files (our boot jars invalidate them; odrefresh compiles a boot image on /data)"
if ls "$F"/arm64/boot* "$F"/arm/boot* "$F"/boot* >/dev/null 2>&1; then die "boot image files left"; fi
ls "$F/arm64" "$F/arm" 2>/dev/null | head -3
