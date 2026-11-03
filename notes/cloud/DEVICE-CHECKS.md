# Device checks for the cloud branches (2026-11-03)

The cloud session had no tablet. Each check below is read-only (no flash, no reboot, no write), unless it says so.
Use `ADB="adb -s <serial>"`. Root commands run through `su -c`. The results decide which shims to build.

## 1. Blocked waits (decide the gameopt stub and confirm 4q)

1. Start a game from the Games app. Wait 30 s.
2. `$ADB shell "su -c 'debuggerd -b \$(pidof oiface)'" | grep -B2 -A12 -i waitForService`
   - A thread in `AServiceManager_waitForService` with `gameopt` = oiface is blocked: build the gameopt stub
     (`notes/cloud/GAMEOPT.md`). No hit = skip the stub.
3. `$ADB shell getprop ro.oplus.os_type` and `$ADB logcat -d | grep -i -E "ISensorFeature|isDeclared"`
4. `$ADB shell "su -c 'debuggerd -b \$(pidof system_server)'" | grep -B3 -A12 -i -E "SensorFeature|Urcc"`
   - A blocked thread confirms the need for step 4q (`notes/cloud/OPLUSSENSOR.md`). 4q is cheap; keep it either way.
5. `$ADB shell "su -c 'grep -l liboplus-uah-client /proc/[0-9]*/maps'"` (which process loads the urcc client).

## 2. Display features (decide the Java colour-matrix patch)

1. `$ADB shell setprop log.tag.HidlDisplayPanelFeature V`, then `$ADB logcat -c`.
2. Turn on, one after the other: Eye Protect, Read Mode, Reduce White Point, Game Eye Care (Games app).
3. `$ADB logcat -d | grep -E "setDisplayPanelFeatureValue|HidlDisplayPanelFeature"`: write down the ids for each switch.
4. For Read Mode and Reduce White Point: does the picture change? (photo with the switch off and on.)
   No change = add it to the Java patch (`notes/cloud/DISPLAY-HALS.md` 4.3).
5. `$ADB logcat -d | grep -c "displayPanelFeature is NULL"` after 1 minute of normal use (cost of the missing HAL).
6. `$ADB logcat -d | grep -i "using Hidl MiscService"` (the misc fallback; expected: no hang).
7. Set the log tag back: `$ADB shell setprop log.tag.HidlDisplayPanelFeature ""`.

## 3. Bypass charging (branch `cloud/bypass-4p`, after a build)

`maintainer/chargershim/patch_record.py` must run first (the shim jar is not in git). Then build to 4p, flash, and use
`notes/cloud/CHARGER-HAL.md` section E.4.

## 4. DP test kernel (kernel repo, branch `cloud/dp-test`)

`fastboot boot` only (writes nothing). Steps and dmesg guide: `notes/DP-TEST.md` in the kernel repo.

## 5. Bug 36 (stuck 120 Hz)

Only when it happens again: the capture checklist in `notes/cloud/BUG36-OTI.md` section 5, before any restart.

## 6. HAL shims (branch `cloud/halshims`, step 4r, after a build)

0. **Before the build:** compile the policy on the tablet with `/system/bin/secilc` and all 8 inputs plus
   `maintainer/halshims/halshims.cil` (AGENTS.md). The cloud session could not run a secilc for Android 17 CIL (the
   host secilc is too old for `nlmsg`, and a source build was not allowed). By hand: every type and attribute that
   the file uses exists in the donor policy (`hal_gameopt_aidl_client` in system_ext; `service_manager_type`,
   `system_server`, `surfaceflinger`, `platform_app` in the platform policy). A non-zero exit means an error.
1. `$ADB shell "su -c 'cat /data/local/tmp/halshims.log'"`: `pipa HAL host ready: gameopt,panel,misc,touch` and four
   `registered` lines. No `pipa.touch.TouchHost` process runs (`ps -A | grep -c TouchHost` = 0); the 4o touch tests
   (rotation, game mode) still work. `service check vendor.oplus.hardware.gameopt.IGameOptHalService/default` = found.
2. SELinux: `$ADB logcat -d | grep -E "avc.*pipa_hal_"` must be empty (else add the `find` rule for that domain).
3. gameopt: start a game from the Games app. Then
   `$ADB shell "su -c 'cat /data/misc/pipa_port/gameopt_leases'"` lists the boosted threads (pid tid start bit), and
   for one tid `$ADB shell "su -c 'cat /proc/<pid>/task/<tid>/ux_state'"` has bit 1 or 2 set.
4. gameopt reset: go home (game in the background). The lease file is empty and the `ux_state` bit is clear.
5. oiface: `$ADB shell "su -c 'debuggerd -b \$(pidof oiface)'" | grep -c waitForService` = 0.
6. Smoothness of a game before and after (`maintainer/perfetto/traced_heavy.sh <label>`, 2 runs or more, AGENTS.md).
7. RAM: `$ADB shell "su -c 'dumpsys meminfo \$(pgrep -f pipa.hal.HalHost | head -1)'" | grep TOTAL`.

## 7. RAM: persistent apps (step 4s)

1. Before the build: `$ADB shell pm list features | grep -i -E "nfc|se\.omapi"` must be empty (no NFC, no OMAPI).
2. Before and after a build with 4s: `$ADB shell dumpsys meminfo -s | head -40` (persistent processes and total), and
   `$ADB shell dumpsys activity processes | grep -c "persistent"`. Expected: com.android.nfc, com.android.se and
   com.qti.qcc gone, about 40-70 MB less PSS.
3. Settings > Connections: no NFC entry (as before), Wallet/tap-to-pay not offered.
