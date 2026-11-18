#!/bin/sh
# Step 7j (BUGS 126, tester 2026-11-17, maintainer chose "change the ROM"): sideloaded APKs that the CN cloud virus
# scan flags (e.g. repacked games via SAI) hit com.oplus.appdetail's "High-risk app ... Unable to install" page with
# no way past it. OPPO's own switches, no APK patching (OppoPackageInstaller decompiled 2026-11-17):
#  - app feature com.oplus.packageinstaller.skip_appdetail=true: m1.c returns reason 9, the installer keeps its own
#    install page instead of redirecting to appdetail ("startAppdetail: false reason: 9").
#  - component-override disables phonemanager's AutoTestScanApksService (only handler of
#    oplus.intent.action.CHECK_APK_VIRUS): OPlusPackageInstallerActivity.A2() then takes OPPO's own no-service path,
#    ScanResult.SAFE, plain Install button. Rest of Phone Manager (cleanup, background scans) untouched.
# Trade-off accepted by maintainer: no install-time virus verdict for anyone. Rollback: drop this step;
# live undo: pm enable com.coloros.phonemanager/com.oplus.phonemanager.virusdetect.service.AutoTestScanApksService
# Verified live 2026-11-17 on pt107 (bind-mounted xml + pm disable): echotest reinstall via OPPO page, INSTALL_SUCCEEDED.
set -eu
. "$PORT/lib.sh"
STEP=7j
echo "== 7j installer: skip appdetail risk page + no install-time virus block"
A=$T/system/my_product/etc/extension/com.oplus.app-features.xml
FEAT=com.oplus.packageinstaller.skip_appdetail
[ -f "$A" ] || die "$A not found"
forbid_grep "$FEAT" "$A"
replace_once "$A" '</extend_features>' "	<app_feature name=\"$FEAT\" args=\"boolean:true\"/>\n</extend_features>"
need_grep "<app_feature name=\"$FEAT\" args=\"boolean:true\"/>" "$A"
echo "edited  my_product/etc/extension/com.oplus.app-features.xml (+ $FEAT=true)"

F=$T/system_ext/etc/sysconfig/pipa-component-overrides.xml
SVC=com.oplus.phonemanager.virusdetect.service.AutoTestScanApksService
[ -f "$F" ] || die "$F not found (step 2g)"
forbid_grep "$SVC" "$F"
replace_once "$F" '</config>' "    <component-override package=\"com.coloros.phonemanager\">\n        <component class=\"$SVC\" enabled=\"false\" />\n    </component-override>\n</config>"
need_grep "$SVC" "$F"
echo "edited  system_ext/etc/sysconfig/pipa-component-overrides.xml (- AutoTestScanApksService)"
set_layer "$STEP"
