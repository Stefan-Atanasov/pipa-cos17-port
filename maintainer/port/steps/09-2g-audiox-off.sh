#!/bin/sh
# Phase 2g: the AudioX disable moves into the ROM, on top of 2f (system_ext only).
#
# ColorOS's sound service (com.oplus.audio.effectcenter, ro.oplus.audio.effect.type=audiox_merge) starts
# AudioxService at boot, which tries to create OPPO's AudioX effect 41f6c0f4-5d8f-11ec-bf63-0242ac130002.
# pipa's vendor has only Xiaomi's Dolby effect (dap), so every attempt fails and is retried every 3 s
# forever ("Failed to recreate AudioxEffect ... Error: -3"): wasted wakeups. Until now it was only disabled
# live on the tablet (pm disable), which a clean flash loses.
#
# Fix: a sysconfig <component-override>. SystemConfig parses it and
# ScanPackageUtils.configurePackageComponents applies it to the parsed component's default state at
# every package scan (read from the ROM's services.jar), so it holds after a clean flash and a dirty flash
# alike, and a later `pm enable` by the user still works. The Sound effects page only offers Xiaomi Sound
# and Dolby Atmos on this device (maintainer confirmed), so nothing visible is lost.
#
# Old layer script: build_beta5_2g.sh
set -eu
. "$PORT/lib.sh"
LABEL=u:object_r:system_file:s0

SE=$T/system_ext

echo "== sysconfig component-override (AudioX)"
F=$SE/etc/sysconfig/pipa-component-overrides.xml
[ -d "$SE/etc/sysconfig" ] || { echo "system_ext/etc/sysconfig missing"; exit 1; }
cat > "$F" <<'EOF'
<?xml version="1.0" encoding="utf-8"?>
<!-- pipa port: ColorOS's AudioxService retries OPPO's AudioX effect (absent on pipa) every 3 s forever -->
<config>
    <component-override package="com.oplus.audio.effectcenter">
        <component class="com.oplus.audio.effectcenter.service.AudioxService" enabled="false" />
    </component-override>
</config>
EOF
chown 0:0 "$F"; chmod 644 "$F"
setfattr -n security.selinux -v "$LABEL" "$F"
echo "added   system_ext/etc/sysconfig/pipa-component-overrides.xml"

