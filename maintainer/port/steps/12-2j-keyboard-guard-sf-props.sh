#!/bin/sh
# Phase 2j: idle drain + the KSU test scripts of 2026-10-24 folded into the ROM, on top of 2i.
#
# * pipa_port keyboard guard (port-rom/pipa_port/service.sh + config.prop KEYBOARD_GUARD): xiaomi-keyboard runs only
#   while the nanosic MCU reports the keyboard connected. Without it the daemon polls the accelerometer ~7x/s all
#   night (the driver's virtual "Xiaomi Keyboard" devices always exist), the SLPI sleeps 27 % and the SoC never
#   reaches AOSD/CXSD.
# * loc_sys_service `disabled`: it is `class main`, so commenting out its early-boot start (2a) never stopped it; it
#   retries the missing GNSS HAL once a second (replaces /data/adb/service.d/pipa-noloc.sh).
# * system_ext build.prop: debug.sf.enable_layer_caching=1, debug.sf.predict_hwc_composition_strategy=1 (smoothness
#   A/B 2026-10-24: small gain, no power cost; replaces /data/adb/post-fs-data.d/pipa-sf-test.sh).
# * product build.prop: drop the donor's traced.relay_producer_port=vsock://-1:2010 (our kernel has no vsock, so
#   traced dies at start and Perfetto does not work).
#
# Old layer script: build_beta5_2j.sh
#NEEDS: "$ROM/pipa_port/service.sh" "$ROM/pipa_port/config.prop"
set -eu
. "$PORT/lib.sh"

SE=$T/system_ext
PR=$T/product

# in place (cat >): owner, mode and SELinux label stay
echo "== pipa_port"
for f in service.sh config.prop; do
    cat "$ROM/pipa_port/$f" > "$SE/pipa_port/$f"
    echo "updated system_ext/pipa_port/$f"
done
need_grep kb_guard "$SE/pipa_port/service.sh"

echo "== loc_sys_service disabled"
RC=$SE/etc/init/loc_sys_service.rc
grep -q '^    disabled' "$RC" && { echo "already patched"; exit 1; }
sed 's|^    oneshot$|    oneshot\n    disabled|' "$RC" > "$R/loc.rc"
cat "$R/loc.rc" > "$RC"
need_grep '^    disabled' "$RC"

echo "== system_ext build.prop: SurfaceFlinger"
BP=$SE/etc/build.prop
grep -q 'debug.sf.enable_layer_caching' "$BP" && { echo "already patched"; exit 1; }
printf '\n# pipa port: layer caching + HWC strategy prediction (smoothness A/B 2026-10-24)\ndebug.sf.enable_layer_caching=1\ndebug.sf.predict_hwc_composition_strategy=1\n' >> "$BP"

echo "== product build.prop: no vsock traced relay"
BP=$PR/etc/build.prop
need_grep '^traced.relay_producer_port=' "$BP"
grep -v '^traced.relay_producer_port=' "$BP" > "$R/product.prop"
cat "$R/product.prop" > "$BP"

