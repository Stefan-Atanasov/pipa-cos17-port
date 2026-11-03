#!/bin/sh
# Phase 4q: no VINTF declaration for OPPO HALs that nothing serves on pipa (system).
#
# The donor system manifest (/system/etc/vintf/manifest.xml) declares three OPPO vendor HALs. On the donor the odm
# side serves them; pipa has no server for them (no system process either). A declared name makes
# AServiceManager_isDeclared true, and the following AServiceManager_waitForService waits with no timeout:
#   vendor.oplus.hardware.oplusSensor.ISensorFeature/default   libsensorserviceextimpl.so (sensorservice: boot hook
#       triggerSensorFeatureOnBoot, OPPO fusion light activate) -> a blocked sensorservice or binder thread
#   vendor.oplus.hardware.urcc.IUrcc/default                     liboplus-uah-client.so
#   vendor.oplus.hardware.hummingbird.IOplusHmbirdService/default  (system_server osense: Java getService only)
# Without the declaration the clients get null at once and log "not declared". Static analysis:
# notes/cloud/OPLUSSENSOR.md, notes/cloud/HAL-INVENTORY.md. compatibility_matrix.device.xml lists what the vendor
# side must give; it does not check the framework manifest, so these removals do not change a VINTF check.
set -eu
. "$PORT/lib.sh"
STEP=4q

M=system/system/etc/vintf/manifest.xml
for n in 'hummingbird</name>\n        <fqname>IOplusHmbirdService/default' \
         'oplusSensor</name>\n        <fqname>ISensorFeature/default' \
         'urcc</name>\n        <fqname>IUrcc/default'; do
    replace_once "$M" "    <hal format=\"aidl\">\n        <name>vendor.oplus.hardware.$n</fqname>\n    </hal>\n" ""
done
forbid_grep 'ISensorFeature' "$T/$M"
forbid_grep 'IUrcc/default' "$T/$M"
forbid_grep 'IOplusHmbirdService' "$T/$M"
