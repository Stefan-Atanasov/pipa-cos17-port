# B3 / B4 investigation (offline, read-only)

> **Historical analysis (2026-10-22, module period).** Current status in `BUGS.md`: B3 fixed (beta5-2d/2f, pen dock
> in 3u); B4 improved (blur off by default since 2q). Paths below are the maintainer's PC.

Trees: `/home/stefan/Documents/pipa/reference/{cos17,hyperos1-stock}`. "cos17" = the port as built (vendor has
`debug.hwui.renderer=skiavk`). Tools: androguard venv, `python -I`. Items marked (GUESS) are not proven offline.

---------------------------------------------------------------------------------------------------

## B3 - Xiaomi Smart Pen 2 not shown while charging, no battery %

### Summary
ColorOS has no generic "stylus battery" UI. The whole pen UI (capsule, battery %, charging state, My Devices card) lives in
`com.oplus.ipemanager` (IPeManager) and is built around an OPPO/OnePlus Pencil that is a BLE GATT device with OPPO UUIDs.
The pen-present trigger is a kernel uevent from a device the pipa kernel does not have, and the battery number comes
over BLE GATT, not from any sysfs node. On HyperOS the same job is done by MIUI code (`MiuiBatteryServiceImpl`) that reads the Xiaomi
sysfs nodes. That code is not in the ColorOS OS side. So nothing consumes `reverse_pen_soc` / `reverse_pen_chg_state` on the port.
This is not a permission bug; the pipa_core chown only makes the nodes writable/readable, it feeds no consumer.

### Evidence - ColorOS side (what it expects)
1. `system_ext/priv-app/OplusExSystemService/OplusExSystemService.apk` (package `com.oplus.exsystemservice`), class `z8/c` (IPeService):
   - registers `UEventObserver` on `DEVPATH=/devices/virtual/oplus_wireless/pencil`. `onUEvent` reads the keys
     `pencil_status`, `pencil_addr`, `pencil_id`, `pencil_mislocated`.
   - then sends `com.oplus.ipemanager.action.PENCIL_STATUS_CHANGE` (extras `present`, `macAddr`, `pencilId`) to `com.oplus.ipemanager`
     via `startServiceAsUser` (method `b0`, log tag `IPeService`, "pencilHallHandle present = ...").
   - same class also watches `DEVPATH=/devices/virtual/pogopin/pogo_keyboard` (keyboard; keys `pogopin_status`, `mac_addr`, `report_sn`) and
     `DEVPATH=/devices/platform/soc/soc:oplus,chg_wls` ("Failed to register wireless charging UEvent observer").
   - other pen bits in that APK: sensor `qti.sensor.trestle_hall` (stylus case position, "checkStylusCasePositionOnBoot"),
     settings `ipe_stylus_charging_connect_state`, `ipe_stylus_charging_config_trigger`, `ipe_pencil_smart_charging`,
     `ipe_pencil_low_battery_protection`, `flag_disable_wireleseReverse_function`.
2. `system/my_product/priv-app/IPeManager/IPeManager.apk`:
   - `btadsorb/CoreService.d` ("pencilNodeChange present = ... macAddr = ...") handles that intent: writes Settings `ipe_pencil_present`,
     `ipe_pencil_charging_state`, then starts BLE: `ble/k0` (PencilBleManager) `h0(mac)`, `w0()`.
   - battery/charging come from GATT: Battery Service `0000180f`, `00002a19` (level), `00002a1a` (power state), plus OPPO custom UUIDs
     `18092dbc-/18093046-/...-2a69-11ec-8d3d-0242ac130003`, `5768d878-b436-11ee-a506-0242ac120002`, `58480000-5a6a-1122-3300-004095112200`.
     k0.e writes Settings `ipe_pencil_battery_level` (Global), `ipe_pencil_charging_state`, `pencil_sp_*`.
   - UI: capsules `capsule_id_pencil_battery`, `capsule_pencil_low_battery`; pencil panel / My Devices card (`createPencilFluidData: chargingState=`).
   - names it knows: `OPPO Pencil`, `OPPO Pencil 2/2R/3/Pro`, `OnePlus Pencil ...`; assets for iceland/ivy/pad pencil. No Xiaomi.
   - writes touch-panel enable nodes through `com.oplus.touchnode.OplusTouchNodeManager` ("iceland or ivy, write node 1", `writePencilEnableNodeByFwVersion`).
3. `system/system/framework/oplus-services.jar`: `OplusNoBTPencilPolicy` (Settings `ipe_pencil_connect_state`, `ipe_pencil_present`;
   "NOBT_PENCIL_SUPPORT"), `OplusFloorRefreshRateController` (VRR when pen present), `OplusPencilCopyPasteController`,
   `OplusLaserPointerController.switchPenConnectState`, `com.oplus.ipemanager.sdk.PencilManager`.
   `OplusBatteryService.setWirelessEnableTx(String)` sets `mWirelessReserve` (1 charging, 2 enable, 3 disable) from the OPPO charger HAL
   (strings "charging"/"enable"/"disable") and puts `wireless_reverse_chg_type` in `ADDITIONAL_BATTERY_CHANGED`. That is the OPPO charger HAL
   path (`vendor.oplus.hardware.charger.ICharger`, which `chargershim` stubs with zeros), not the Xiaomi sysfs.
4. `system/my_product/build.prop`: `persist.bluetooth.stylus_sleep_state_enabled=true`, `persist.sys.bluetooth.ble.hid.pen=true`,
   `ro.oplus.vrr.pencil.support=1`; app-features `pencil_adsorption_position=middle`. No SystemUI plugin needed: capsule is posted by IPeManager UIService.
5. Port kernel: no `oplus_wireless` class (the Xiaomi driver exposes `power_supply/fuda`, `power_supply/wireless`). I did not grep a kernel
   source tree (none in repo, `COS17/kernel` only holds KernelSU apk + a zip). (GUESS that no oplus_wireless uevent exists; confirm on device, below.)

### Evidence - Xiaomi side (what pipa provides, what consumes it on HyperOS)
- HyperOS `system_ext/framework/miui-services.jar` -> `com.android.server.MiuiBatteryServiceImpl$BatteryHandler$BatteryUEventObserver.onUEvent` reads uevent key
  `POWER_SUPPLY_REVERSE_PEN_CHG_STATE` (also `POWER_SUPPLY_REVERSE_CHG_STATE/MODE`, `TX_ADAPTER`, ...). `handleMessage` then sends the STICKY broadcast
  `miui.intent.action.ACTION_PEN_REVERSE_CHARGE_STATE` with int extras `miui.intent.extra.ACTION_PEN_REVERSE_CHARGE_STATE` and
  `miui.intent.extra.REVERSE_PEN_SOC` (value from `getPSValue()`; reads the SoC, most likely sysfs `wireless/reverse_pen_soc`, GUESS).
  `BroadcastQueueModernStubImpl` whitelists `com.android.settings.stylus.STYLUS_BATTERY_NOTIFY`. Pen battery card in MIUI Settings/SystemUI consumes these.
- HyperOS vendor `vendor.xiaomi.hardware.micharge@1.0-impl.so` / service: strings `/sys/class/power_supply/wireless/reverse_pen_soc`, `.../wireless/bt_state`,
  `/sys/class/qcom-battery/reverse_chg_mode`; `odm/etc/cit_param_config.json` mentions pen nodes. Init rc chowns `wireless/reverse_chg_mode`, `bt_state`, `rx_cr` to system.
- The cos17 vendor has no `micharge` HAL and no MIUI services, so no component turns the nodes into a framework-visible signal.
- pipa_core already chowns `/sys/class/power_supply/fuda/{reverse_chg_mode,reverse_pen_soc}` and `/sys/class/power_supply/wireless/{pen_mac,reverse_pen_chg_state}`
  (post-fs-data.sh lines 54-72). Note the HyperOS nodes live under `wireless/` for soc/chg_mode and the port module uses `fuda/` for those: sysfs layout differs
  between kernels (confirm which really exists on device, see commands).

### Gap
| ColorOS expects | pipa has | consequence |
|---|---|---|
| uevent `DEVPATH=/devices/virtual/oplus_wireless/pencil` with `pencil_status/pencil_addr/pencil_id` | none; Xiaomi nodes `wireless/pen_mac`, `reverse_pen_chg_state` and uevent `POWER_SUPPLY_REVERSE_PEN_CHG_STATE` on the battery/wireless supply | exsystemservice never sends PENCIL_STATUS_CHANGE -> `ipe_pencil_present` stays 0 -> no capsule, no card |
| BLE GATT pen with OPPO UUIDs/name | Xiaomi Smart Pen 2 (own BLE/HID protocol; HID shows as `Xiaomi Smart Pen`/`Smart Pen Keyboard`) | even with a present event, IPeManager cannot read level/charging from the pen (GATT service discovery fails, GUESS: Xiaomi pen has Battery Service 0x180f but not the OPPO vendor services IPeManager waits for) |
| pen state through OPPO charger HAL (`ICharger`, `wireless_reverse_chg_type`) | chargershim returns 0 | no "reverse charging" state either |

### Ranked options
1. **Own tiny pen-battery notifier (recommended, medium-low effort, low risk).** New small system APK (or app run as system via the existing module
   chargershim approach) that: UEventObserver on `POWER_SUPPLY_REVERSE_PEN_CHG_STATE` (or polls sysfs while screen on every 2-5 s only when
   `reverse_pen_chg_state != 0`, cheaper: poll when `pen_mac` non-empty), reads `reverse_pen_soc` (needs the sysfs read permission pipa_core already gives; for the
   ROM: ueventd.rc lines, inventory A2 + SELinux read for the app domain - system_server domain does it more easily), and posts a notification/ongoing
   notification "Xiaomi Smart Pen 85% charging" plus the standard `android.hardware.input` `InputManager.getInputDeviceBatteryState` (not available for non-BLE).
   Effort: 1-2 days. Risk: low (additive). Result: battery % visible, but not in ColorOS' own pencil capsule.
2. **Feed ColorOS' pencil UI (high effort, high risk).** (a) emit the uevent: needs kernel change (add a `oplus_wireless/pencil` class device) or a
   userspace emulation. UEventObserver only sees kernel netlink uevents, so userspace cannot fake it, but the same intent can be sent directly:
   `am startservice -n com.oplus.ipemanager/.btadsorb.CoreService -a com.oplus.ipemanager.action.PENCIL_STATUS_CHANGE --es present 1 --es macAddr <pen_mac> --es pencilId 1`
   (root daemon reading `wireless/pen_mac`, `reverse_pen_chg_state`). That reaches `pencilNodeChange` and sets `ipe_pencil_present`. (b) battery: the BLE manager
   would try GATT to the Xiaomi pen and fail/disconnect; to avoid that, patch IPeManager or write Settings.Global `ipe_pencil_battery_level` and
   `ipe_pencil_charging_state` directly from the daemon (the capsule reads those, GUESS: k0.B0 reads the cached level). Fragile (BLE manager will overwrite), app
   behaviour unknown for a non-OPPO MAC. Effort: days of smali + device iteration. Risk: medium (bond/ble services, VRR `ipe_pencil_present` also changes refresh policy
   via `OplusFloorRefreshRateController`, which may even be beneficial: smartpen VRR).
3. **Port MIUI battery path**: copy `MiuiBatteryServiceImpl` pen handling into oplus-services (jar edit) and add a receiver app: rejected, miui-services dependencies are heavy and
   there is still no ColorOS consumer for the MIUI intent.
4. Do nothing in OS and document: pen works for input, charges magnetically; battery % only via `cat /sys/class/power_supply/fuda/reverse_pen_soc`. 

Reasonable plan: ship option 1 first (user-visible fix for "no battery percentage"), then try the intent injection (2a) in the perf-test module to see
whether the ColorOS capsule shows presence when charging. Sidenote: "pen not shown while charging" may also just be that `pen_keys.sh` / `pen on` (pipa_core) handles
input only; presence/charge icons never existed on the port.

### Read-only device commands to confirm
```
adb shell ls /sys/class/power_supply/            # fuda? wireless? 
adb shell 'for n in fuda wireless; do for f in /sys/class/power_supply/$n/*; do echo "$f: $(cat $f 2>/dev/null)"; done; done' | grep -i -E 'pen|rev|mac|soc|chg'
adb shell 'ls -la /sys/class/power_supply/fuda /sys/class/power_supply/wireless | head -40'
adb shell ls /sys/devices/virtual | grep -i -E 'oplus|pencil|wireless|pogo'     # expect none
adb shell settings list global | grep -i ipe_            # ipe_pencil_present / battery_level / charging_state
adb shell dumpsys bluetooth_manager | grep -i -E 'pen|stylus|bonded' ; adb shell dumpsys input | grep -i -A6 -E 'Xiaomi Smart Pen'
adb shell pm list packages | grep -i -E 'ipemanager|exsystem'; adb shell dumpsys activity services com.oplus.ipemanager | head -40
adb logcat -d | grep -i -E 'IPeService|pencilNodeChange|PencilBle|ipemanager' | tail -50
adb shell getevent -lp | grep -i -B1 -A3 pen
# with the pen attached and charging, watch uevents (root):
adb shell su -c 'cat /sys/class/power_supply/fuda/uevent; cat /sys/class/power_supply/wireless/uevent'
adb shell su -c 'logcat -b events -d | grep -i power_supply' 
```
Expected if analysis is right: no `IPeService ... pencilHallHandle` lines when attaching the pen, `ipe_pencil_present` null/0.

---------------------------------------------------------------------------------------------------

## B4 / B5 - blur animation lag, "smoother and lighter"

### How ColorOS decides blur (evidence)
- `persist.sys.oplus.anim_level` is the master "animation grade". Port `system/my_product/build.prop` sets `persist.sys.oplus.anim_level=1` (lines 82, 99, 105, 189; the donor
  value; donor family `ro.build.device_family=OPSM8845`, i.e. a current flagship class SoC, GUESS: Snapdragon 8 Elite-class, much more GPU than SD870).
  Read by framework.jar, oplus-framework.jar, oplus-services.jar, services.jar, SystemUI, Launcher, Settings (`COUIMaterialStateManager.getAnimLevelVersion`,
  `RoundCornerUtil.isSmoothRoundRectOn`), OplusExSystemService (string "Machines below V do not support setting blurred backgrounds or current animLevel is too low or is in third party theme").
- SettingsProvider `SettingsUtils.getAnimationLevel()` = `persist.sys.oplus.anim_level`. In `onUpgradeLocked` (runs on fresh data / OS upgrade only; inserts values):
  level 1 ("A+") -> `system_material_blur_enable=1`, `animationBlurrySwitch=1`; level 2 ("A") -> both `0`. Also `persist.sys.oplus.material_blur_switch` (default true)
  gates "old material blur".
- Three user-visible toggles in UXDesign (Settings -> Display "Blurred texture" screen; `Ld9/a`): Settings.System `animationBlurrySwitch` (blur during
  animations: launcher/app open, gesture UI, battery UI, keyguard widgets), `system_material_blur_enable` (frosted-glass materials in SystemUI/Settings), `system_material_stroke_enable`
  (+ `saved_material_stroke_value`). Readers of `animationBlurrySwitch`: OplusLauncher `MaterialBlurSettingHandler.checkAnimBlurEnable`, SystemUI keyguard
  (`KeyguardAffordanceHelper.refreshMaterialBlurEnabled`, style widgets), OplusGestureUI, UXDesign, Battery.apk, SettingsProvider.
- Background blur is done by `ro.surface_flinger.supports_background_blur=1` (set in the port, same as stock HyperOS: also 1) via SurfaceFlinger GPU blur +
  `system_ext/priv-app/BlurService` (lib `librenderkit.so`, `blurBuffers`, `blur_buffers_radius`) for window blur drawables. Both burn GPU on every animated frame.
- Port-specific cost multipliers (from notes/STABILITY-PERF.md and the trees):
  - 144 Hz panel, `peak_refresh_rate=144`: frame budget 6.9 ms; blur passes need to finish inside it.
  - `debug.hwui.renderer=skiavk` + `ro.hwui.use_vulkan=true` on a hand-patched `vulkan.adreno.so` (inventory 4.1-8): stock HyperOS uses default skiagl (`ro.hwui.use_vulkan` empty).
    HWUI blur (RenderEffect/backdrop) under Vulkan on A650 is a plausible slow path (GUESS; no measurement).
  - powerhint `EXPENSIVE_RENDERING` was modified by the port (floors DDR/L3); and KGSL: vendor post_boot `max_pwrlevel`/`min_pwrlevel` are the same as stock HyperOS
    (diff of init.qcom.rc / post_boot grep identical), so there is no GPU governor regression versus stock. Stock MIUI runs blur on the same GPU at
    60 Hz default fps (`ro.vendor.display.default_fps=60`) - the port animates at 120/144 so the same blur costs 2-2.4x per second.
  - `ro.launcher.blur.appLaunch=0` is already set (same as stock), so app-launch blur in the launcher is already off by this prop; the lag is in other animated blur (gestures, folder/recents, shade, keyguard).
  - persist.sys.oplus.anim_level=1 also enables smooth round rects, higher-cost transitions in Settings/SystemUI (Settings `isSmoothRoundRectOn`).

### Current mitigation
pipa_core `set_blur_default` (service.sh 63-74): `settings put system animationBlurrySwitch 0` only if unset. Weaknesses: runs only with the module; does not touch
`system_material_blur_enable` (frosted glass in shade/recents/keyguard stays on); does not touch `anim_level`; user can see the toggle ON in UXDesign after a
factory reset before module runs.

### Ranked proposals (test in perf-test module first, then ROM)
Test order is cheapest/safest first. Measure with `dumpsys gfxinfo <pkg> framestats` (jank %), `dumpsys SurfaceFlinger --latency`, Perfetto, and `cat /sys/class/kgsl/kgsl-3d0/gpu_busy_percentage` during a
launcher swipe / shade pull.

1. **Settings keys, no reboot, zero risk** (module `service.sh` or ROM SettingsProvider default):
   `settings put system animationBlurrySwitch 0` (already), `settings put system system_material_blur_enable 0`, optionally `system_material_stroke_enable 0`.
   ROM place: fresh-data defaults come from SettingsProvider `onUpgradeLocked` keyed on `persist.sys.oplus.anim_level` (see next item) - easier than patching the APK.
   Effort S.
2. **`persist.sys.oplus.anim_level=2`** (ROM `my_product/build.prop`, the four occurrences; for testing `resetprop` + wipe-free: set `animationBlurrySwitch`/`system_material_blur_enable` by hand
   since `onUpgradeLocked` only runs at upgrade). Effect: blur defaults 0 on fresh install, and lower grade in COUI/Settings/SystemUI (smooth rounded rects etc.). Risk: low-medium; level semantics
   inferred from SettingsProvider (1="A+", 2="A"); other levels/side-effects not enumerated (GUESS), a few apps treat "level too low" as hiding blur settings in UXDesign (the user then cannot re-enable
   blur). Check UXDesign UI remains. Effort S.
3. **Renderer A/B**: `debug.hwui.renderer=skiagl` + `ro.hwui.use_vulkan=false` (vendor build.prop; test with module `resetprop` + `stop; start` zygote or reboot). Expect: less blur cost if the vk path is the
   slow one, plus eliminates the highest-risk driver patch (STABILITY-PERF D14/#13). Risk: skiagl blur on A650 is usually fine (HyperOS stock does it); medium effort to validate apps.
4. **SurfaceFlinger blur off globally** (last resort): `ro.surface_flinger.supports_background_blur=0` (read-only, ROM/vendor build.prop or `resetprop` before zygote) -
   removes shade/dialog background blur in every app. (`persist.sys.sf.disable_blurs=1`/`ro.sf.blurs_are_expensive` are AOSP props; I found no match for them in the port's
   props; whether the donor SF honours them is unverified - GUESS.) Risk: low visual loss.
5. **Cap refresh rate for animation-heavy cases**: keep Auto (120) instead of fixed 144 (`settings put system peak_refresh_rate 120`), `min_refresh_rate` default; per STABILITY-PERF "Refresh rate" row.
6. **Power hint trim**: restore PixelOS `EXPENSIVE_RENDERING` and shorten `LAUNCH` (STABILITY-PERF items 4/10): GPU min freq is also raised in powerhint (`GPUMinFreq`, `GPUForceClkOn`) - blur lag can be GPU clock ramp latency, not throughput (GUESS).
7. **Animation scales** (generic, settings only): `settings put global window_animation_scale 0.7`, `transition_animation_scale 0.7`, `animator_duration_scale 0.7` (shorter transitions = fewer blurred frames; 0.5 feels snappier). Reduce transparency does not exist as a stock Android key; the equivalents here are items 1.
8. **Smoother/lighter, non-blur**: trim EXPENSIVE_RENDERING (above); zram 4096 and nandswap off (STABILITY-PERF); stop respawn loops. Out of scope for this file.

Where to set: toggles 1 and level 2 -> ROM `my_product/build.prop` (anim_level) + SettingsProvider default (only first boot); for existing installs a one-shot in
`pipa_core`/ROM init `settings put` is the only way since values persist in `/data/system/users/0/settings_system.xml`. Props 3/4 -> `vendor/build.prop`; for tests use
perf-test-module `config.prop` + `service.sh` (`resetprop`).

### Read-only device commands to confirm
```
adb shell getprop persist.sys.oplus.anim_level; adb shell getprop persist.sys.oplus.material_blur_switch
adb shell 'for k in animationBlurrySwitch system_material_blur_enable system_material_stroke_enable peak_refresh_rate min_refresh_rate; do echo $k=$(settings get system $k); done'
adb shell 'getprop | grep -i -E "hwui|renderer|blur|surface_flinger|sf\.|vulkan"'
adb shell dumpsys SurfaceFlinger | grep -i -E 'blur|supportsBackgroundBlur|GLES|Vulkan|renderengine|Active mode|refresh' | head -30
adb shell dumpsys gfxinfo com.android.systemui | grep -i -E 'Janky|percentile|Pipeline'     # then repeat for the launcher package after a few swipes
adb shell dumpsys gfxinfo com.android.launcher framestats | head   # package: cmd package resolve-activity -a android.intent.action.MAIN -c android.intent.category.HOME
adb shell cat /sys/class/kgsl/kgsl-3d0/{gpu_busy_percentage,devfreq/cur_freq,max_pwrlevel,min_pwrlevel,gpuclk}
adb shell dumpsys display | grep -i -E 'mActiveModeId|renderFrameRate|PeakRefresh'
adb logcat -d | grep -i -E 'BlurService|renderkit|skia|vulkan|gpu hang|kgsl' | tail -40
# A/B, run while swiping recents, shade, launcher folder: toggle each key and compare gfxinfo jank%
```

### Notes / caveats
- I did not decompile BlurService/librenderkit (native) nor measure anything on device; all causes in B4 are static inference.
- Settings key names verified in UXDesign (`Ld9/a`), SettingsProvider (`SettingsUtils`, `onUpgradeLocked`), OplusLauncher (`MaterialBlurSettingHandler`), SystemUI (`KeyguardAffordanceHelper`).
