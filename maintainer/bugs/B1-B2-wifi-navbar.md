# B1 (Wi-Fi sometimes does not turn on) and B2 (UI behind the navigation bar): offline analysis

Method: read-only comparison of `reference/{cos17,hyperos1-stock,iqraos3.1,pixelos}` plus overlay/ARSC inspection.
Caveat: androguard ARSC value decoding was unreliable for framework-res, so only resource names and IDs are trusted there.
Overlay APKs from `my_product/overlay` decoded sanely, but values are still marked "(decoded)". No device data exists
(`port-work/device-captures` and `device-checks` are empty). Everything below is therefore a hypothesis list, not a verdict.

Items marked GUESS are not backed by a file.

---------------------------------------------------------------------------------------------------

## B1: Wi-Fi sometimes does not turn on

### Facts established (all paths under /home/stefan/Documents/pipa/reference/)

1. Chip is QCA6390 over PCIe (cnss2), not WCN6855/icnss.
   - `cos17/vendor/etc/init/hw/init.target.rc:97` writes `/sys/devices/platform/soc/b0000000.qcom,cnss-qca6390/fs_ready`.
   - sepolicy genfscon refers to `b0000000.qcom,cnss-qca6390`.
   - Stock ships `qca_cld3_qca6390.ko` and `qca_cld3_qca6490.ko`, with per-chip dirs `vendor/firmware/wlan/qca_cld/qca6390/`.
2. The cos17 Wi-Fi vendor stack is the Lineage-family (PixelOS) one, not HyperOS stock.
   - `diff -rq cos17/vendor/etc/wifi pixelos/vendor/etc/wifi` shows no differences.
   - `libwifi-hal*.so`, wpa_supplicant, hostapd and cnss-daemon are byte-identical to pixelos.
   - Only `android.hardware.wifi-service` differs (495192 vs 491072 bytes), a newer rebuild.
   - HAL AIDL versions match the COS17 `compatibility_matrix.202604.xml`: IWifi v4 (matrix 2-4), ISupplicant v5 (4-5), IHostapd v3 (2-3). So the HAL set is VINTF-consistent and not an obvious break.
3. No wlan driver module in the vendor tree.
   - `cos17/vendor/lib/modules` holds only gspca_main, rmnet_perf, rmnet_shs and modules.*.
   - `modules.load` has no wlan or cld entry; pixelos is the same.
   - `cos17/vendor/vendor_dlkm` and `odm_dlkm` contain only `etc/`.
   - So the driver (`wlan` module, `/sys/module/wlan/parameters/fwpath`, `/dev/wlan`, cnss2) is built into the kernel or lives in a partition not in this tree.
   - Driver loading therefore depends entirely on the boot image the user flashed (the `RE404-MI_PAD6` kernel zip in `COS17/kernel/`).
   - There is no `insmod` for wlan in any rc. `init.qcom.rc:537` only has the FTM `pronto_wlan.ko` path, which is irrelevant.
4. Bring-up path (HAL-driven, on demand).
   - `libwifi-hal.so` strings contain `/dev/wlan`, `/sys/module/wlan/parameters/fwpath`, `wifi_wait_for_driver_ready` and `wifi_change_driver_state`.
   - `cos17/vendor/etc/init/android.hardware.wifi-service.rc` starts `vendor.wifi_hal_legacy` as `class hal` with `SYS_MODULE`.
   - `android.hardware.wifi-service` has the string "Waiting for the driver ready".
   - Order: framework WifiService calls the HAL `start()`, which writes `ON` to `/dev/wlan` and polls for `wlan0`. The first call can race kernel/cnss/firmware readiness.
   - `cnss-daemon` is `class late_start` (`init.qcom.rc:539`). Same as stock.
   - `fs_ready` is written in post-fs-data (`init.target.rc:97`). Same as stock.
5. Differences between the pixelos-derived `WCNSS_qcom_cfg.ini` and the HyperOS stock `qca6390/WCNSS_qcom_cfg.ini`. cos17 `vendor/etc/wifi/WCNSS_qcom_cfg.ini` vs stock:
   - `gEnableForceTargetAssert=1` (SSR enable) is absent. Firmware crashes then do not self-recover, which fits "sometimes dead until reboot".
   - `g11dSupportEnabled=0` (stock 1).
   - `gIPAConfig=0x7d` (stock 0x00).
   - `gEnablefwlog=0` (stock 1).
   - `nan_separate_iface_support=1` is added.
   - `etsi13_srd_chan_in_master_mode=1` (stock 3).
   - `roam_data_rssi_threshold_triggers=0` is absent.
   - `gEnableConcurrentSTA=wlan1` is commented out.
   - These are Lineage defaults, identical on PixelOS. They only matter if the kernel is stock-based.
   - The ini is reached via the symlink `vendor/firmware/wlan/qca_cld/WCNSS_qcom_cfg.ini -> /vendor/etc/wifi/WCNSS_qcom_cfg.ini`, and `wlan_mac.bin -> /mnt/vendor/persist/wlan/wlan_mac.bin`.
   - Stock instead uses `qca_cld/qca6390/` and `qca6490/` subdirs. A stock-pathed kernel looking in `qca6390/` would find nothing under the pixelos layout.
   - Stock `vendor/etc/wifi/qca6390/WCNSS_qcom_cfg.ini` and `fstman.ini`, `icm.conf`, `passpointProfile.conf` are not present in cos17.
6. Country code.
   - `cos17/vendor/etc/init/hw/init.device.rc:9` sets `ro.boot.wificountrycode US`. `g11dSupportEnabled=0` and `gCountryCodePriority=1` are in effect.
   - No regdb file is shipped under vendor/etc or vendor/firmware.
7. SELinux.
   - `vendor_file_contexts` has the full QCA wifi labels (hal_wifi_default_exec, vendor_wlan_device `/dev/wlan`, cnss-daemon -> vendor_wcnss_service_exec, wpa/hostapd sockets).
   - `vendor_sepolicy.cil:7510`: `allow hal_wifi vendor_wlan_device (chr_file ...)`.
   - The port boots permissive and flips to enforcing at `sys.boot_completed=1` (`vendor/etc/init/portenforce.rc`). The pipa port block in the cil (line 20969 on) contains no Wi-Fi rules.
   - Denials that only appear after the flip (HAL, wificond, cnss-daemon, ColorOS `u:r:su:s0` helper) would hit the first Wi-Fi toggle after boot, not during boot.
8. ColorOS-side Wi-Fi pieces present on cos17.
   - `system_ext/etc/init/init.sys.oplus.connectivity.rc`: OPPO Wi-Fi switch watchdog. On `sys.oplus.wifi.coldreset=1` it starts `wifi_cool_reset`, which runs `init.sys.oplus.wifi.debug.sh wifi_cold_reset` with `seclabel u:r:su:s0`.
   - That script is `[ ! -e /sys/module/icnss2 ] && echo 2 > /sys/module/cnss2/parameters/pci_reset`.
   - It is ColorOS's recovery for "Wi-Fi switch stuck" on QCA6390 PCIe. It needs three things: the `su` domain to exist, enforcing policy to allow it, and the kernel to export `cnss2.pci_reset`.
   - `system_ext/etc/init/wificond.rc` runs `/system_ext/bin/wificond`.
   - `system/my_product/build.prop:7`: `ro.product.oplus.wlan.ko=/vendor/lib/modules/qca_cld3_wlan.ko`. That file does not exist on cos17. I could not find a reader of the prop in readable files (GUESS: ColorOS Wi-Fi code may try to check or load it).
   - `my_product/build.prop:11`: `vendor.oplus.sap.interface=wlan2`.
   - `my_product/build.prop:12`: `persist.sys.oplus.wlan.atpc.qcom_use_iw=true`.
   - Dangling service `rusWifiBootCheck` (the script `init.sys.oplus.wifi.RusUpgrade.sh` is missing) is already logged as ST18. It is cosmetic.
   - No OPPO-specific Wi-Fi HAL (no vendor.oplus.hardware.wifi) is required by the rc or manifests. No missing OPPO Wi-Fi HAL was found.
9. Donor Wi-Fi capability RRO `product/overlay/WifiResCommon_Sys.apk` (decoded, flagged unreliable):
   - config_wifi6ghzSupport, config_wifiSoftap6ghzSupported, config_wifiSoftapIeee80211axSupported, config_wifi_report_he_ready, config_wifiSaeH2eSupported and similar are all true.
   - Plus `FrameworksResCommon_Sys.apk` with config_wifi_dual_band_support, config_wifi_softap_ieee80211ac_supported and config_wifi_softap_acs_supported (also decoded as true).
   - These come from the donor chipset and are not pipa-specific. QCA6390 is 2.4/5 GHz Wi-Fi 6, so 6 GHz would be wrong (GUESS on the exact pipa SKU).
   - HyperOS stock overlays (`AospWifiResOverlay`) were not carried over.

### Cause candidates (ranked)

| # | Candidate | Evidence | Confidence |
|---|-----------|----------|------------|
| 1 | Driver/firmware not ready or crashed, and nothing recovers it. HAL "ON" races kernel or cnss firmware boot; QCA6390 PCIe can fail link or firmware boot (after suspend or early boot). SSR enable is missing in the ini; ColorOS's `cnss2.pci_reset` cold-reset helper may be unable to run. | Facts 3, 4, 5 (no `gEnableForceTargetAssert`), 8 (`wifi_cold_reset` uses `su` seclabel plus `cnss2` param) | medium (plausible; needs logs) |
| 2 | Kernel/vendor layout mismatch. The wlan driver is not in the vendor tree; ini/mac paths follow the Lineage layout (`qca_cld/WCNSS_qcom_cfg.ini`, no `qca6390/` subdir). A user on a stock/other-base kernel, or a mixed kernel+vendor+modem-firmware, gets intermittent or no Wi-Fi. | Facts 3 and 5. "Other port users" likely use differing kernels. | medium for the cases that are reproducible per kernel; low for pure "sometimes" |
| 3 | SELinux denial that appears only after enforcing flips at boot_completed (HAL, wificond, cnss-daemon or the OPPO `su` script). Wi-Fi works only if toggled before the flip or when denials are cached. | Fact 7, `portenforce.rc`, no Wi-Fi rules in the port cil block. Real denials not seen. | low-medium; cheap to check |
| 4 | Donor Wi-Fi capability RRO (6 GHz, softap 6 GHz, 11ax) disagrees with what the HAL/driver reports. WifiService can misbehave or fail to bring up after capability mismatch. Usually causes band or SoftAP problems, not total failure. | Fact 9 | low |
| 5 | `ro.product.oplus.wlan.ko` points to a missing file; ColorOS may attempt a module path that does not exist. | Fact 8 | low (GUESS) |
| 6 | Wi-Fi "sometimes" tied to airplane mode, `wifi_scan_always_enabled=1` (README says set), or ColorOS Wi-Fi switch watchdog quirks. | README.md:234 | low |

Not an issue (checked): wifi HAL/supplicant/hostapd rc files are the same as PixelOS and AIDL-correct; vintf versions match the COS17 matrix; `/data/vendor/wifi/*` dirs are created in `init.qcom.rc:261-268`; `wifi.interface=wlan0` set at `init.qcom.rc:152`; wificond is present in system_ext.

### Device confirmation (read-only)

```
adb shell getprop | grep -i -E 'wifi|wlan|cnss|ro.boot.wificountrycode|oplus.wifi|init.svc.*(wifi|wpa|hostapd|cnss)'
adb shell dmesg | grep -i -E 'cnss|wlan|qca|pci|fw ready|fw_ready|firmware|SSR|subsys|bdwlan|amss|wlan: |Failed to'
adb logcat -b all -d | grep -i -E 'wifi_hal|WifiHal|android.hardware.wifi|wificond|WifiNative|WifiService|WifiController|wpa_supplicant|cnss-daemon|DriverTool|/dev/wlan|fwpath|oplus.wifi|wifi_cold|coldreset'
adb logcat -b all -d | grep -E 'avc: +denied' | grep -i -E 'wifi|wlan|wpa|cnss|wificond|hostapd|su:s0'
adb shell getenforce; adb shell ls -l /dev/wlan /sys/module/wlan/parameters/fwpath
adb shell 'ls -l /sys/module | grep -i -E "wlan|cnss"; ls /sys/module/cnss2/parameters'
adb shell 'cat /sys/module/wlan/parameters/fwpath; ip link show wlan0'
adb shell cmd wifi status; adb shell dumpsys wifi | grep -i -E 'WifiState|Wi-Fi is|mVerboseLoggingLevel|Start|failed'
adb shell ls -l /vendor/firmware/wlan/qca_cld /mnt/vendor/persist/wlan
adb shell 'cmd overlay list android | grep -i wifi; cmd overlay list com.android.wifi.resources'
adb shell uname -a    # which kernel is the user running
```

Key signals:
- `Waiting for the driver ready` timeouts or `Failed to start Wifi HAL` mean candidate 1.
- cnss `FW ready` missing, or `PCIe link` / `mhi` errors, point at the PCIe/firmware side.
- `avc: denied ... hal_wifi_default / su` points at candidate 3.
- `wifi.interface` / `ip link` missing `wlan0` means the driver did not come up.
- Run the same capture on the first failure and again after toggling.

### Proposed fixes

- A (low risk, ROM vendor). Add `gEnableForceTargetAssert=1` (SSR) and, if the kernel supports it, `g11dSupportEnabled=1` to `vendor/etc/wifi/WCNSS_qcom_cfg.ini` (also fixes stock-parity gaps). Needs a device test: some Lineage kernels ignore it.
- B (module or ROM, low risk). Make `wifi_cold_reset` workable. Verify `/sys/module/cnss2/parameters/pci_reset` exists on the kernel. If SELinux denies the `su` seclabel, add an allow or a vendor service with a proper domain. Caveat: no sysfs label work is possible without a device capture.
- C (ROM or module, medium risk). Add a watchdog service. If `wlan0` is absent N seconds after `sys.boot_completed`, or Wi-Fi fails to enable, trigger `sys.oplus.wifi.coldreset=1`. This only helps if B works.
- D (ROM vendor, low risk). Align wifi RROs with the hardware: ship a small `com.port.pipa.overlay.wifi` that sets `config_wifi6ghzSupport=false` and `config_wifiSoftap6ghzSupported=false` (only if the SKU lacks 6 GHz; verify from stock `qca6390` cfg). Priority above `WifiResCommon_Sys` (see PipaCornersOverlay 9999).
- E (ROM). Create `/vendor/lib/modules/qca_cld3_wlan.ko` only if a reader is found; otherwise drop `ro.product.oplus.wlan.ko` from `my_product/build.prop`. Low value, do not do blindly.
- F (documentation). Pin the supported kernel in the release notes. Fact 3 means Wi-Fi is the most kernel-sensitive subsystem here.

---------------------------------------------------------------------------------------------------

## B2: UI drawn behind the navigation bar

### Facts established

1. The port ships no navbar or inset resource override of its own. The only inset-adjacent port or donor items are:
   - Donor `android_framework_res_overlay.display.product.25928.apk` (target `android`, priority 700, decoded):
     - `status_bar_height_portrait`/`landscape` = 40dip, `rounded_corner_radius` = 46px.
     - `config_mainBuiltInDisplayCutout` and `config_mainBuiltInDisplayCutoutRectApproximation` empty (good, pipa has no cutout).
     - `config_defaultRefreshRate` = 0.
   - Port `PipaCornersOverlay.apk` (`com.port.pipa.overlay.corners`, priority 9999, target `android`): `rounded_corner_radius`, `_top`, `_bottom` = 46px.
   - `PipaLauncherOverlay.apk` (target `com.android.launcher`, priority 9999): `oplusLayoutHotseatMarginBottomGestureDp=20`, `oplusLayoutWorkspacePaddingHorBigScreenDp=150`.
   - No `navigation_bar_*`, `taskbar_*` or `config_navBarInteractionMode` is overridden by any of them. Defaults come from ColorOS framework-res (resource IDs exist: `navigation_bar_height` 0x1050283, `navigation_bar_frame_height` 0x105027e, `navigation_bar_gesture_height` 0x1050281, `taskbar_frame_height` 0x1050395, `config_navBarInteractionMode` 0x10e00ff). Their values could not be decoded.
2. Navigation mode.
   - `product/overlay/NavigationBarModeGestural` sets `config_navBarInteractionMode`=2 (decoded); `NavigationBarMode3Button` sets 0.
   - `cos17/vendor/build.prop:455`: `ro.boot.vendor.overlay.theme=com.android.internal.systemui.navbar.gestural;com.google.android.systemui.gxoverlay_gms`, a Lineage-origin leftover. That mechanism enables the gestural overlay by default. `gxoverlay_gms` does not exist on ColorOS (GUESS: harmless).
   - The Pipa launcher overlay hotseat margin for "Gesture" suggests gestural was assumed.
3. Density.
   - Effective `ro.sf.lcd_density` is 370: `system/system/build.prop:333` and `system/my_product/build.prop:154` set 370.
   - `vendor/build.prop:418-419` sets `ro.sf.lcd_density=360` and `vendor.display.lcd_density=360`. The system value wins for `ro.*` (loaded first), while `vendor.display.lcd_density` stays 360. This 360-vs-370 mismatch is odd but minor.
   - Stock pipa density is 400 (hyperos `product/etc/build.prop:34`, iqraos, pixelos vendor). The port lowered it to 370 (PATCH-INVENTORY line 359: "density 420 -> 370"; 420 was the inherited donor value). Panel is 1800x2880, giving smallest width about 778dp at 370 versus 720dp at 400. The donor 8.8" panel is much smaller in dp.
4. Display natural orientation and cutout.
   - `ro.surface_flinger.primary_display_orientation=ORIENTATION_0` (`vendor/build.prop:356`) with a 1800x2880 panel, so portrait-native panel. Bootanim is forced 90 degrees.
   - Port removed the donor `ro.oplus.display.screenhole.positon` and `screen.heteromorphism` (`my_product/build.prop:158-161`), but the feature flags `oplus.software.display.screen_heteromorphism` and `origin_roundcorner_support` (`my_product/etc/permissions/oplus.product.display_features.xml:22,48`) remain.
5. Tablet taskbar / dock.
   - `my_product/etc/extension/com.oplus.app-features.xml:5`: `com.android.launcher.TASKBAR_ENABLE`.
   - `extension/com.oplus.oplus-feature.xml:27`: `oplus.software.systemui.navbar_pick_color`.
   - `system_ext/oplus/sys_navbar_color_white_list.xml` exists (per-app navbar colour and edge policies: `enforce_edge_activity`, `activity_black_list`).
   - `product.characteristics=tablet`, `ro.oplus.image.system_ext.device_type=tablet`.
   - `oplus_vrr_config.json:199-204` lists "Taskbar" and "DecorNavBarBg" layers.
   - The taskbar is hosted by the launcher: with `TASKBAR_ENABLE` the Launcher publishes the nav/taskbar insets. If the launcher is not running, crashed, or is a third-party home (this is a commonly seen port situation), or uses a different display size than the donor, those insets disappear and apps draw under the dock/bar.
6. HyperOS stock pipa had its own `AospFrameworkResOverlay` with `config_showNavigationBar` and its own SystemUI overlay. COS17 has no pipa framework overlay (module README lines ~223-225 confirm for brightness). `FrameworksResCommon_Sys.apk` has `config_showNavigationBar` (decoded true).
7. The SystemUI RRO from the donor (`com.android.SystemUIResOverlay.25928.apk`) is a three-key (alert slider) layout (`config_isThreeKeySystemUI`) and does not touch insets.

### Cause candidates (ranked)

| # | Candidate | Evidence | Confidence |
|---|-----------|----------|------------|
| 1 | Android 15/16 edge-to-edge enforcement. Apps targeting SDK 35+ (and ColorOS 17 on A16/A17 ignoring opt-out on large screens) draw behind system bars unless they apply insets. ColorOS's per-app `sys_navbar_color_white_list.xml` / `enforce_edge_activity` policy is tuned for the donor, and many CN apps are listed. This is largely not a port bug and would also occur on the donor. | Fact 5; general platform behaviour | medium-high as a baseline; it explains "some apps" but not "all UI" |
| 2 | Taskbar/navbar inset provider broken or absent on this device: launcher (taskbar host) not providing the insets, or in the wrong mode for the 1800x2880 panel at density 370 (taskbar/gesture state chosen by dp thresholds). Content then draws under the dock or bar. | Fact 5; port edits PipaLauncherOverlay (hotseat gesture margin and workspace padding 150dp tuned by hand) | medium |
| 3 | Nav mode inconsistency: gestural default forced through `ro.boot.vendor.overlay.theme` (Lineage leftover) while the Oplus overlay and launcher margins assume otherwise, or the setting flips between 3-button and gestural, giving wrong bottom inset for one mode. | Fact 2 | low-medium |
| 4 | Density/dimension assumptions: 370 vs 360 vs stock 400 and donor tuned dp dimens (status bar 40dip, navbar dimens from donor framework-res). Navbar frame height in px is based on the donor's design, with rounding or rounded-corner px overlays of 46 px fixed. A mismatch between the inset height SystemUI reports and the window it draws would make UI sit behind the bar. | Fact 3, 1 | low-medium (GUESS on mechanism) |
| 5 | Orientation: native portrait 1800x2880 used in landscape, bootanim forced 90 degrees. After rotation, `navigation_bar_height_landscape` / `config_navBarCanMove` (sw600dp) handling might give a navbar at the side or an inset on the wrong edge. | Fact 4; framework IDs exist | low |
| 6 | Leftover heteromorphism or round-corner features (`screen_heteromorphism`, `origin_roundcorner_support`) cause ColorOS to compute extra insets or compat padding as on a punch-hole display. Port already removed the hole props for the status bar clock bug. | Fact 4 | low |

### Device confirmation (read-only)

```
adb shell wm size; adb shell wm density; adb shell getprop ro.sf.lcd_density; adb shell getprop vendor.display.lcd_density
adb shell settings get secure navigation_mode             # 0=3-button, 1=2-button, 2=gestural
adb shell cmd overlay list android | grep -i -E 'navbar|NavigationBar|display.product|corners'
adb shell cmd overlay list com.android.systemui
adb shell cmd overlay lookup android android:dimen/navigation_bar_height
adb shell cmd overlay lookup android android:dimen/navigation_bar_frame_height
adb shell cmd overlay lookup android android:dimen/navigation_bar_gesture_height
adb shell cmd overlay lookup android android:dimen/taskbar_frame_height
adb shell cmd overlay lookup android android:integer/config_navBarInteractionMode
adb shell dumpsys window displays | grep -i -E 'mInsetsStatesInfo|DisplayFrames|navigationBar|taskbar|mNavigationBar|stableInsets|Rounded'
adb shell dumpsys window | grep -i -E 'InsetsSource|type=navigationBars|type=tappableElement|extraNavigationBar|mTaskbar'
adb shell dumpsys activity activities | grep -i -E 'Insets|Taskbar'
adb shell dumpsys SurfaceFlinger --displays | head -40
adb shell dumpsys activity service com.android.systemui | grep -i -E 'navigation|taskbar'
adb shell dumpsys display | grep -i -E 'mBaseDisplayInfo|densityDpi|cutout|roundedCorners'
adb shell pm list packages | grep -i launcher; adb shell cmd package resolve-activity -a android.intent.action.MAIN -c android.intent.category.HOME
adb shell getprop | grep -i -E 'taskbar|navbar|navigation|oplus.display|persist.wm'
adb logcat -b all -d | grep -i -E 'Taskbar|NavigationBar|InsetsController|InsetsSource|navbar_pick_color'
```

Reproduce with one stock-targeting app (e.g. Settings, which is edge-to-edge-aware) and one legacy app, in both modes. Compare `wm size` and `wm density` before and after switching. Record `dumpsys window displays` insets for navigationBars and whether a taskbar source exists.

### Proposed fixes

- A (ROM, low risk). Fix density consistency: remove the `vendor.display.lcd_density=360` / `ro.sf.lcd_density=360` lines in `vendor/build.prop` or make them 370 to match the system. Re-evaluate 370 vs 400 (stock): 400 yields 720dp and a stock-like UI. Either decide deliberately. Side effect: UI scale change (users will see layouts shift).
- B (ROM, low-medium risk). Remove `ro.boot.vendor.overlay.theme=...gestural;...gxoverlay_gms` from `vendor/build.prop:455`, and set the default navigation mode explicitly through a default setting. First check what the donor first-boot default is.
- C (ROM, medium risk). If the taskbar inset provider is the problem, a fabricated or static RRO can set `navigation_bar_frame_height` / `navigation_bar_height` / `taskbar_frame_height` and `config_navBarInteractionMode` to explicit values. Choose values only after reading the live `dumpsys` numbers; do not guess them.
- D (module). A runtime `cmd overlay fabricate` equivalent (see `maintainer/aod_overlay_test.sh` for the pattern) to test dimen overrides without a ROM rebuild before committing to C.
- E (ROM). Check launcher side: confirm `PipaLauncherOverlay` values (`oplusLayoutHotseatMarginBottomGestureDp=20`, `oplusLayoutWorkspacePaddingHorBigScreenDp=150`) do not fight the taskbar insets; revert them if inset reports are fine without them.
- F. For app-specific cases (baseline edge-to-edge), accept as upstream behaviour or extend `sys_navbar_color_white_list.xml` entries with `activity_black_list`. Low value.

---------------------------------------------------------------------------------------------------

## Summary

B1 (Wi-Fi): the Wi-Fi stack is the identical PixelOS/Lineage vendor stack with AIDL HAL versions matching the COS17 vintf matrix, so no obviously missing HAL or rc piece was found. The driver is not in the vendor tree, so behaviour hinges on the kernel in use. Top suspects: (1) no firmware-crash recovery (SSR missing in the ini, and ColorOS's `cnss2.pci_reset` cold-reset helper runs under `su` seclabel and may not work), (2) kernel/vendor/firmware layout mismatch for users on other kernels, (3) denials that only appear once enforcing flips at boot_completed. Next step is a device capture of dmesg cnss/wlan lines, HAL "driver ready" logs and avc denials on the first failure.

B2 (navbar): the port overrides no navbar/taskbar/inset resources. Baseline suspects: (1) Android 15/16 edge-to-edge enforcement with donor-tuned ColorOS per-app policies, (2) the launcher-hosted tablet taskbar (`TASKBAR_ENABLE`) not publishing the right insets for this panel, (3) a leftover Lineage gestural-default prop and a 360/370/400 density inconsistency. Confirm with `wm density`, `settings get secure navigation_mode`, `cmd overlay lookup` for the navigation_bar dimens and `dumpsys window` InsetsSource dumps. Cheapest fixes are explicit density/nav-mode alignment, then a navbar-dimen RRO once real values are known.
