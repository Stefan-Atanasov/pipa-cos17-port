# Pipa COS17 Power & Polish Tune (v0.10)

Companion module for the **ColorOS 17 port for Xiaomi Pad 6 (`pipa`)**, beta4 `OPD2515_17.0.0.102(CN01)`
(2026-10-17) and beta5 (C.06 base, `17.0.0.103`); v0.10 supports both (see sections 12 and 15). It runs next to `pipa_core` v1.10 (梦归zzz) and **does not modify `pipa_core`**.
Each fix below is a workaround for a problem that can be fixed properly in the ROM. The
**"Proper fix"** lines are meant for the port developer.

Everything is reversible: set a flag to `0` in `config.prop`, delete a replaced file from the
module's `system/` folder, or remove the module, then reboot.

**Mounting note.** The KernelSU 4.2.0 build on this port has no module mount provider
(`ksud module list` shows `"mount": "false"` for every module), so files under `system/` are
**not** mounted automatically. `post-fs-data.sh` bind-mounts them itself, before the composer and
`system_server` start. It handles both the KernelSU layout (`vendor/`, `system_ext/` at the module
root) and the Magisk layout (`system/vendor`, `system/system_ext`). The binds don't show up in
`/proc/mounts` because `pipa_core` enables susfs `hide-sus-mnts-for-non-su-procs`, so verify
with `md5sum` (see below).

| # | Problem | Module workaround | Type |
|---|---|---|---|
| 1 | `xiaomi-keyboard` polls the accelerometer ~6.7×/s forever without a keyboard (main idle drain) | run the daemon only while the case is attached | runtime (`KEYBOARD_GUARD`) |
| 2 | `xiaomi-keyboard` fold-back auto-disable never works on pipa (hard-coded `event12`) | symlink `event12` to the real keyboard node while attached | runtime (`KB_EVENT_LINK`) |
| 3 | `AodBacklightDaemon` polls every 300 ms even with AOD off | `SIGSTOP` while AOD is off, `SIGCONT` when on | runtime (`AOD_GATE`) |
| 4 | face HAL is started once; after a crash face unlock is dead and the framework retries 1×/s | watchdog restarts the HAL | runtime (`FACE_WATCHDOG`) |
| 5 | `com.pipa.faceunlock` retries a socket that no longer exists every 3 s | disable it while the socket is absent | runtime (`LEGACY_FACE_APP`) |
| 6 | colours oversaturated; "Natural" changes nothing | Natural mode gets HyperOS's sRGB gamut matrix (`miLut_2`) | file: `system/vendor/etc/qdcm_calib_data_xiaomi_m82_*.xml` |
| 6b | ColorOS sometimes resets the colour mode to 256 (Vivid) at boot | remember the user's mode, restore it after boot | runtime (`COLOR_MODE_RESTORE`) |
| 7 | minimum brightness ~19 nits; slider linear (all change in bottom ~15 %); auto off | brightness table with the AOSP/HyperOS slider curve in the column ColorOS actually uses, min ~1 nit | file: `system/system_ext/etc/display_brightness_config_default.xml` |
| 12 | Adaptive colour and Bedtime mode never change the tint (ColorOS wants OPPO's CCT sensor type 33171001, which pipa does not have) | patched framework jar registers Xiaomi's tcs3701 `front_cct` sensor (33171088) instead and feeds a fixed 100 lx into the ambience filter | file: `framework/<base-md5>.jar` |
| 13 | USB DAC / headset volume stuck at max | USB_HEADSET/A2DP curves | file: `system/vendor/etc/audio_policy_volumes.xml` |
| 14 | speakers L/R swapped (rotation 270) | 32-bit audio HAL 270 -> spin_270 | file: `system/vendor/lib/hw/audio.primary.kona.so` |
| 15 | C.06 bootloop / UI restarts: system_server waits forever for the IEngineer and QSPM HALs | jar edit 4 (`isRootVersion` branch -> nops) + beta4 `libupdateprof.qti.so`/`libtrigger-handler.so` | `framework/*.jar`, files: `system/system_ext/{lib,lib64}/` |

Not fixed by the module, documented below: charger info path (8), face HAL crash (9), small items (10). Eye comfort and reader mode work on the stock port; adaptive colour and Bedtime mode are fixed in (12).

---

## 1. `xiaomi-keyboard` accelerometer loop (main idle drain)

**Evidence.** `dumpsys sensorservice` showed 143 accelerometer enable/disable pairs from
`/vendor/bin/xiaomi-keyboard` in 23 s. That produced ~100 log lines/s from `SensorService` and
`sensors-hal`, kept `system_server` at 8–16 % and total CPU at ~11.5 % with the screen off.
With the daemon stopped, CPU dropped to **~2.75 %** and the log rate to ~20 lines/s.
`batterystats` before the fix: 53.4 mAh/h deep idle.

**Root cause (from disassembly of the 18 KB binary).** Stock HyperOS doesn't ship this
daemon; it uses the event-driven `vendor.xiaomi.hardware.keyboardnanoapp@1.0-service`, which
blocks on `/dev/nanodev0`. The COS17 vendor has a Lineage-style `xiaomi-keyboard` instead:

```
init:   open("/dev/nanodev0"); kb_state = access("/dev/input/event12") == 0
thread: loop {
          if (access("/dev/input/event12") == -1 && kb_state == 1) { usleep(3 s); continue; }
          wait while "sleap" (screen-off event from nanodev);
          enable accel; usleep(150 ms); read one event; disable accel;   // ~6.7 Hz
          angle = f(pad accel, keyboard accel from nanodev);
          new = (40 <= angle < 231);
          if (new != kb_state) { kb_state = new; write(nanodev, {0x32, 0xff, new}); }
        }
```

Without a keyboard `kb_state` stays 0, so the 3 s back-off never triggers and the loop runs at
full rate forever. `/dev/input/event12` is only used as a presence flag through `access()`; it is
never opened.

**Module.** `setprop ctl.stop xiaomi-keyboard` while no device named `Xiaomi Keyboard` /
`Xiaomi Consumer Control` / `Xiaomi Touchpad` is in `/proc/bus/input/devices`, and
`ctl.start` within 5 s of one appearing. `xiaomi keyboard WakeUp` (pogo GPIO, always present)
and the pen devices are excluded.

**Proper fix.** Use the stock `keyboardnanoapp` HAL, or fix the daemon: back off whenever the
keyboard is absent (not only when `kb_state == 1`), detect the keyboard by name instead of
`event12`, and sleep ≥ 1 s between angle samples.

## 2. Fold-back auto-disable broken (`event12`)

**Root cause.** pipa already uses `event0`–`event10` without the case, so an attached keyboard
gets `event11` or higher, never `event12`. The daemon then switches the keyboard on once,
sets `kb_state = 1`, and sleeps forever on the "absent" branch, so folding the keyboard behind
the pad never disables it.

**Module.** While the keyboard is attached, `/dev/input/event12` becomes a symlink to its real
node (only when nothing else owns that name; label `input_device`). The link is removed when the
keyboard detaches.

**Status.** Logic was tested with synthetic `/proc/bus/input/devices` data (`event11` picked;
pen and WakeUp ignored). It has **not been tested with a real keyboard case**.

## 3. `AodBacklightDaemon` 300 ms poll

**Evidence.** `pipa_core/aod_bl.jar`: `main()` loops `isInteractive()` → `maybeApply()` →
`Thread.sleep(300)` forever. `maybeApply()` rereads `settings_secure.xml` (64 KB) at most every
60 s. `Setting_AodSwitchEnable=0` on the test device, yet the binder poll ran 3.3×/s.

**Module.** `SIGSTOP` while `Setting_AodSwitchEnable != 1`, `SIGCONT` when it is 1. Killing it
would not stick, because `pipa_core`'s `run_aod` respawns the daemon 5 s after it exits.

**Proper fix.** Exit early when AOD is off, and listen for display-state changes instead of
polling (or poll ≥ 2 s).

## 4. Face HAL started once, no restart

**Evidence.** `/vendor/etc/init/android.hardware.biometrics.face-service.facehal.rc` has no
`interface aidl android.hardware.biometrics.face.IFace/default` line and is `disabled`.
`pipa_core/service.sh` starts the HAL from `/data` exactly once. After a SIGSEGV
(see 9), the framework logged `ctl.interface_start ... IFace/default` failures **once per second
for hours** (1046 in one buffer).

**Module.** Every 15 s: if neither init nor `pipa_core` has a HAL running, start it the same way
`pipa_core` does (same binary, `LD_LIBRARY_PATH`, OpenCL loader choice). Verified: `kill -9` →
re-registered within one tick.

**Proper fix.** Wrap `start_face` in a restart loop in `pipa_core`, and fix the crash (9).

## 5. `com.pipa.faceunlock` socket retry

**Evidence.** The PERSISTENT system app connects to `/data/system/facehal_socket` every 3 s
(350 stack traces in one buffer). That socket doesn't exist with the current AIDL
`facehal-rs` HAL; the binary doesn't even contain the string.

**Module.** `pm disable-user` plus `SIGSTOP` of the live process, only while the socket is absent.
It is re-enabled automatically if the socket exists.

**Proper fix.** Remove `/system/app/FaceUnlock` from the image. `pipa_core`'s own comment says
it was already removed, but it is still present in beta4.

## 6. Oversaturated colours; Natural does nothing

**Evidence.** HWC switches modes correctly (`SDM: SetPreferredColorModeInternal: Applying mode:
standard` / `hal_native`). In both `qdcm_calib_data_xiaomi_m82_36_02_0a/42_02_0b_*.xml` (identical
to stock HyperOS), however, the modes `standard` (ModeID 0, used by **Natural**), `hal_srgb` (18)
and `hal_native` (16, the default mode 256) all have **PCC (FeatureType 2) and the 3D gamut LUT
(FeatureType 3) disabled** with identity data. They share the same IGC/GC gamma tables, so every
mode shows the raw panel gamut.

The stock panel colour matrix (`lcm_array`, XYZ → panel RGB, in HyperOS
`/vendor/etc/mdss_dsi_m82_*_mi.xml`) gives these primaries:

| | x | y |
|---|---|---|
| R | 0.679 | 0.310 |
| G | 0.287 | 0.665 |
| B | 0.150 | 0.037 |
| native white | 0.296 | 0.316 (~7400 K) |

That is roughly DCI-P3, so sRGB content is stretched. HyperOS corrects it in
`vendor.xiaomi.hardware.displayfeature@1.0-service` + `ppd` + `qdcmss`, none of which the COS17
vendor ships (it is the PixelOS-style display stack).

**What HyperOS and PixelOS do.** Stock HyperOS doesn't use these QDCM modes for colour. Its
`displayfeature.default.so` loads one of 18 17³ 3D LUTs (`/vendor/etc/miLut_0..17.txt`, 12-bit)
into the DSPP gamut block. Each LUT is a linear 3×3 to within ~0.002. `miLut_2` (sRGB content,
native white) fits

```
[0.7917 0.1906 0.0116]
[0.0356 0.9400 0.0099]
[0.0106 0.0613 0.8933]
```

That is the textbook sRGB → Display-P3 matrix (Xiaomi treats the panel as exact P3) with small
leakage terms. PixelOS gets the same result from SurfaceFlinger colour management
(`ro.surface_flinger.has_wide_color_display=true`, `persist.sys.sf.native_mode=258`). COS17 sets
`has_wide_color_display=false` on purpose (port comment: HDR issues), so it gets no gamut mapping
at all.

**Module.** Replaces both calibration XMLs with copies where **ModeID 0 (`standard`) and 18
(`hal_srgb`) have PCC enabled** with HyperOS's **`miLut_2`** matrix, each row normalised to 1, so
native white (~7400 K) and peak are kept exactly. Only those two `<Feature>` lines differ from the
original. PCC sits between IGC (linearise) and GC (re-gamma), so it works in linear light:

```
R' = 0.7966 R + 0.1918 G + 0.0117 B
G' = 0.0361 R + 0.9538 G + 0.0100 B
B' = 0.0110 R + 0.0635 G + 0.9255 B
```

Vivid/default (`hal_native`, 256) is left native on purpose. **Settings → Display → Screen colour
→ Natural** now matches HyperOS's sRGB look (`miLut_2`). The PCC stage combines with ColorOS's own
transforms (night light, eye protection) instead of being overwritten by them, which a SurfaceFlinger
`service call SurfaceFlinger 1015` matrix would be. Generated by `tools/patch_qdcm.py` (PCC payload
layout documented there).

Not determined: which `miLut` index HyperOS's default scheme selects. `miLut_0` (same mapping,
~6800 K white) was tried on the test device and judged too yellow. It is kept in
`tools/patch_qdcm.py` as `HYPEROS_LUT0` (use with `WHITE = "lut"`). An earlier v0.2 build used
a matrix from the exact `lcm_array` primaries; it over-corrected compared with HyperOS and PixelOS.

**Colour mode reset (6b).** After some boots `ColorDisplayService: setColorModeExt mode=256` runs
even though the user had picked Natural (0); after others it keeps 0. The trigger was not found.
The module stores the user's `display_color_mode` in `$MODDIR/color_mode` (checked every 15 s) and
writes it back once ~20 s after boot. Writing the setting makes ColorDisplayService re-apply it
(verified: HWC logs `Applying mode: standard`).

**Proper fix.** Ship these calibration files in the vendor image, or port Xiaomi's displayfeature
stack. `standard_p3` (ModeID 4) has no PCC block at all; the panel is close to P3 so it was left alone.

## 7. Brightness: minimum too high, slider and auto-brightness wrong

**How ColorOS uses the table** (`oplus-services.jar`, beta4). The file has one line per UI level
`i` = 0…10239 (the line index is the slider value): `<level>P, B, N, K</level>`.

- `OplusDisplayBrightnessModeStrategy.sniffDisplayBrightnessModel` returns score 1
  (`score = 1` in logcat) when `N[10] > 0`, `N[20] > 0` and `N[20] - N[10] < 1`. Score 1 selects
  `OplusDisplayBrightnessExponentModel`; 0 or 2 select the Linear model and 3 the Second model.
- `ExponentModel.getBacklightFromBrightness(i)` returns `P[i] / P[last]`
  (`CurveConfig.traversalPanelMaps(arr, 0)`, column **P**). That float goes to the composer, and on
  pipa the Qualcomm HWC writes `float × 4095` to `panel0-backlight` **linearly**. OPPO kernels apply
  their own panel curve; pipa's Xiaomi kernel doesn't.
- The slider (`OplusQsBrightnessSliderController`, `setMax(10239)`) writes its progress straight
  through as the level, so it is linear in `i`.
- Auto-brightness works in nits: lux → target nits → level, through a spline over **(P, N)**. So it
  uses column **P as the level axis**, and `getNitFromBrightness(level)` reads the same spline
  (animation, thermal limits, logs).
- Levels at or below `OplusBrightnessConstants.AOD_BRIGHTNESS` bypass the table: level 1 gave
  backlight 1, which is black.

**Evidence (port table, version 20261006).** Column P is simply `0…10239`, and the curved values sit
in column B, which this model never reads. Measured: level 393 → backlight 158 (= 393 × 4095 / 10239),
and equal slider steps add a constant ~620 levels each. Results:

- minimum 222 → backlight 89 ≈ 19 nits;
- 25 % slider ≈ 225 nits, 50 % ≈ 450 nits, so all perceived change sits in the bottom ~15 %;
- COS17 also lacks a pipa framework overlay: `config_screenBrightnessSettingMinimumFloat` = 0.016
  (`mBacklightMinimum=0.016`, ~14 nits), while stock HyperOS ships **0.00171** (7/4095, ~1 nit) in
  `AospFrameworkResOverlay.apk`.

**Module.** Replaces the file with a table generated by `tools/gen_brightness_table.py`:

```
hw(i) = 7 + 4088 * gamma_to_linear(i / 10239)    # AOSP SettingsLib BrightnessUtils curve (= HyperOS slider)
P[i]  = round(hw(i) * 10239 / 4095)              # what ExponentModel sends, P[last] = 10239
B[i]  = round(hw(i))                             # informational
N[i]  = nits(hw(P[i]))                           # physical nits of level = P[i] (auto uses P as level)
K     = unchanged,  min = 20 (stays above AOD_BRIGHTNESS; backlight 8, ~1 nit)
```

Nits come from pipa's own `displayconfig` map (1 nit @ 0.0017, 450 @ 0.49976, 550 @ 1.0). Measured on
the test device after the change:

| slider | backlight | ~nits | before |
|---|---|---|---|
| bottom | 8 | 1 | 19 |
| 25 % | 92 | 20 | ~225 |
| 50 % | 348 | 76 | ~450 |
| 75 % | 1091 | 240 | ~500 |
| top | 4095 | 550 | 550 |

Auto-brightness at ~10 lux: ~63 nits (pipa's stock AOSP curve gives ~53). The first attempt used
`N[i]` = nits of row `i`; auto then applied the curve twice and landed at ~1 nit, so N must be keyed
to P. The user confirmed the slider, the low end (backlight 8: no flicker) and auto feel right.

**Proper fix.** Ship this table (or one built the same way) in `system_ext`. Add a pipa framework
overlay with `config_screenBrightnessSettingMinimumFloat=0.00171`. Note that OPPO's own panels get
their curve from the kernel, which pipa's kernel doesn't provide.

## 8. Charger info (not changed, diagnosis only)

`OplusBatteryService.<init>` reads `getChgConfig(31, "30", 0)` **once** to set
`mChargerInfoUpdateSupported`. Empty → `-1` → `getDataFromHalByOldInterface()` for the rest of
the boot. `pipa_core` registers its `ICharger` shim **after** `sys.boot_completed`, long after
`system_server` constructed the service, so the old path is always used. The repeating
`E OplusBatteryService: getDataFromHalByOldInterface` (~every 11 s) is that method logging its own
name. It is noise, not a failure. `Charger voltage : 0` follows from this: `mChargerVoltage` is
only written in `dumpAddition`, never on the old path.

**Proper fix.** Register the shim before `system_server` starts (early boot, `post-fs-data` /
an init service), return a numeric string for `getChgConfig(31, …)`, and implement the JSON
`getChgConfig(30, "Update", 1)` that `getDataFromHalByUpdate()` parses. The shim currently returns
"0"/"1" for everything.

## 9. Face HAL crash (not changed)

`SIGSEGV SEGV_ACCERR` on `facehal-auth`: `st_manager_image_process → st_tee_eyestate →
crop_eyes → cv::Mat::Mat(const Mat&, Rect)` in `libjni_stfaceunlock_api.so`, an eye ROI outside
the frame. Clamp the rect to the frame (or skip the frame) before cropping. The watchdog (4) only
hides this.

## 10. Smaller items (not changed)

- `com.oplus.midas` crashes at boot: `NumberFormatException: "show"` in
  `QualityProtectService.c`.
- `ro.build.tablet_type=pad` is set by `pipa_core` with `resetprop` every boot; bake it into
  `build.prop`.
- Thermal: COS17 uses the CAF AIDL `android.hardware.thermal-service.qti`; 32 of 43
  `thermal-*.conf` differ from stock (same length, identical prefix; the files are Xiaomi-encrypted,
  so the actual change, trip points or sensor names, is unverified). `dumpsys thermalservice` CPU values
  (60–70 °C) don't match the raw zones (26–31 °C). Probably a sensor-name mismatch; not verified.
- Software update offers a 262 MB SOTA bundle for donor model OPD2515. Don't install it. The
  false "storage less than 262.30 MB" error comes from the missing `/data/ota_package/OTA`.

## 11. Eye comfort / bedtime tint (warm tint open; adaptive colour solved in 12)

**Eye comfort / bedtime (warm tint).** The framework side runs. Log from toggling it on the test
device (2026-10-21):

```
OplusFeatureCustomEyeProtect: postProcess: Eye protect enabled, CCT=2700 ...
AnimationCoordinator: Starting CCT animation: 7900 → 2700, duration=2000
hwservicemanager: getTransport: Cannot find entry
    vendor.oplus.hardware.displaypanelfeature@1.0::IDisplayPanelFeature/default in either framework or device VINTF manifest.
E HidlDisplayPanelFeature: getHidlDisplayPanelFeatureService error
```

ColorOS sends the CCT / RGB gains to OPPO's `IDisplayPanelFeature` HIDL HAL, and pipa has none. So
the tint is computed and dropped. `dumpsys color_display` shows night display and global saturation
inactive.

**Adaptive colour** ("intelligent colour temperature"):

```
W OplusColorAmbientAdapter: registerSensor: 33171001 sensor is null
D OplusFeatureAmbientEyeprotect: skip the first process before valid sensor data arrives
```

ColorOS wants an OPPO CCT sensor of type 33171001. pipa's tcs3701 exposes its CCT channel only as
Xiaomi types `xiaomi.sensor.front_cct` (33171088) and `front_cct_strm` (33171089).

**Possible fixes (not attempted):**
1. **`IDisplayPanelFeature` shim.** Same idea as `pipa_core`'s `chargershim.jar`, but this one is
   HIDL. Implement the calls ColorOS makes for eye protection and apply them as a colour transform:
   a SurfaceFlinger matrix through `DisplayTransformManager`'s level scheme, or PCC through
   `vendor.display.color@1.0`. First disassemble `HidlDisplayPanelFeature` in `oplus-services.jar`
   (`/home/stefan/Documents/pipa/reference/analysis/oplus-services/`) to get the method IDs and the
   payload format.
2. **Adaptive colour.** Either expose the tcs3701 CCT under type 33171001 in the sensors HAL config,
   or feed ColorOS CCT values another way. Check `fake_cct_sensor_value` / `mCctSensorFakeValue`
   in `oplus-services.jar` classes3.dex for a debug injection path. Also verify that the Xiaomi
   sensor's value format (CCT K vs raw RGBC) matches what ColorOS expects.
3. Android's own colour-matrix path **works** on this port. Tested: accessibility colour correction
   (`accessibility_display_daltonizer=0`, monochromacy) turned the screen grey. So a shim for (1)
   can apply the eye-comfort tint as a ColorDisplayService / SurfaceFlinger colour matrix; on this
   stack HWC applies it on top of the QDCM PCC.

---

## 12. Adaptive colour and Bedtime mode (v0.3; per-ROM jars and odex guard since v0.9)

**Symptom.** Eye comfort and reader mode work on the stock port, but **Adaptive colour**
(Display settings) and the Eye Care app's **Bedtime mode** switch do nothing.

**Root cause.** `OplusColorAmbientAdapter` registers sensor type **33171001** (OPPO's CCT
sensor). pipa's tcs3701 exposes the CCT channel only as Xiaomi types
`xiaomi.sensor.front_cct` (33171088) and `front_cct_strm` (33171089);
`getDefaultSensor(33171001)` returns null. `OplusColorContext.sensorDataValid` therefore
stays false, and both `OplusFeatureAmbientColor` (adaptive colour) and
`OplusFeatureAmbientEyeprotect` (Bedtime) skip every frame.

Bedtime has two settings, and they are not equivalent:

- `oplus_customize_rhythm_health_enable=1` → `rhythmEnabled`. This is the **standalone**
  Bedtime path: it warms the screen (5263 K in the test) with Adaptive colour and Eye
  Comfort both off.
- `oplus_customize_comfortable_rhythm_enable=1` → `comfortableRhythmEnabled`. This is the
  Eye Comfort-dependent variant; it requires `oplus_customize_eye_protect_enable=1` and
  otherwise logs `Comfortable rhythm is not enabled…` and skips.

With Adaptive colour and Bedtime both on during the day, `OplusFeatureAmbientEyeprotect`
computes its point (5263 K) but deliberately defers to Adaptive colour
(`OplusFeatureAmbientColor`, 6338 K); at night the Bedtime point applies. This matches the
donor's behaviour.

**Base jars.** beta4: the port-shipped repacked jar (`3316594f…`; the port author repacked it on
2026-09-26, see `notes/PATCH-INVENTORY.md` S17). C.06: donor stock (`2175feb9…`). A diff found no port
code edit (`maintainer/jar-edits/REPORT.md`), so the same `patch_framework.sh` output applies to
both.

**Version guard (since v0.9).** The module ships one patched jar per ROM build, named after the md5 of
that build's own `oplus-services.jar`: `framework/3316594ff6f45d015c61b1181c3b5e97.jar` (beta4,
patched `00b9218b…`) and `framework/2175feb9d4b03eb2859e73e71cfb854d.jar` (donor C.06
`17.0.0.103`, patched `8810ad00…`; v0.9 shipped `06c5c303…` / `8c211ca5…` without the section 15
edit). `framework/aliases` maps other ROM jars to one of these (`<rom md5> <base md5>`): the
rebuilt beta5 ships C.06 with only the section 15 edit (`7afeadb1…`) and uses the C.06 jar.
`post-fs-data.sh` hashes the running jar and binds only the matching file. On any other build it logs `framework jar: no patched jar for base md5 …, reroute
skipped` and leaves the framework alone, because mixing framework versions bootloops
`system_server`. To support a new build, run `tools/patch_framework.sh` on its jar and save the
output as `framework/<md5 of the input>.jar`.

**Prebuilt odex guard (since v0.9).** C.06 ships `oat/arm64/oplus-services.{odex,vdex,art}` for the
stock jar; beta4 does not (the port deleted them), and the beta5 build drops them again. If an
`oplus-services.odex` exists, the bind is skipped and logged (`prebuilt oplus-services.odex
present`), because a patched jar under a stale odex is untested. `FRAMEWORK_ALLOW_ODEX=1` in
`config.prop` overrides this for testing (ART should reject the stale odex and run from the jar).

**Reroute.** `oplus-services.jar` is patched in three places: the type constant in
`OplusColorAmbientAdapter.registerSensor()`, the `SENSOR_COLOR_TEMPERATURE` static field in
`EyeProtectConstant`, and the `sparse-switch` key in `handleSensorChange()`. The switch
key/target pairs are reordered because DEX requires the keys to be sorted; without that
the verifier rejects the class (`VerifyError: unordered keys`). The adapter now registers
the Xiaomi sensor and receives its event: **16 floats**, `[CCT, x, y, 0…]`.

**Lux gap.** The Xiaomi event has no lux in OPPO's slot: `values[9]` is always 0. With
`sensorLux=0` the framework stays in low-light lock and pins the CCT to 5300 K even under
a 6000 lx lamp. The patched `onSingleSensorChanged()` replaces the `aget values[9]` with a
float constant **100.0 lx** (`const/high16`). Adaptive colour then follows the CCT sensor;
brightness-based ambient adaptation is lost (the ALS value is not bridged into this
event).

**Enable/test.**

```sh
# adaptive colour
settings put system oplus_customize_comfort_color_temperature_enable 1
settings put system setting_enable_color_temperature_regulation 1
# standalone bedtime, no Eye Comfort needed
settings put system oplus_customize_rhythm_health_enable 1
# optional Eye Comfort-dependent bedtime variant
settings put system oplus_customize_comfortable_rhythm_enable 1
dumpsys color_display | grep -E 'sensorCCT|sensorLux|sensorDataValid|rhythmEnabled|currentCCT'
```

`setting_enable_color_temperature_regulation` is the key the framework actually reads;
the `oplus_customize_...` key is the Settings-app switch. Turn the feature off again with
`0` in both.

**Boot reset.** The eyeprotect app writes both keys back to 0 on every boot (it checks
OPPO's sensor type directly and cannot see the framework reroute). `ADAPTIVE_RESTORE=1`
in `config.prop` makes `service.sh` remember the user's last value in
`$MODDIR/adaptive_state` / `$MODDIR/bedtime_state` and write it back once, after the CCT
sensor has produced its first event. Turning a switch off is remembered too, so the guard
does not fight the user.

**Caveat.** This is the ROM's own 30 MB framework jar with three dex edits, bind-mounted from
`framework/<md5>.jar` by `post-fs-data.sh`. It needs a reboot; the
jar has no `.odex` on beta4/beta5, so ART does not need a matching prebuilt image (see the odex guard). Set
`FRAMEWORK_SENSOR_REROUTE=0` in `config.prop` (or delete the jar) to restore the stock
framework on the next boot.

---

## 13. USB DAC / USB headset volume stuck at maximum (v0.6)

**Symptom:** with a USB-C DAC (tested: FiiO JadeAudio JA11, `2972:0102`) the volume slider moves
but the headphone level stays at full scale.

**Evidence:** `dumpsys audio` tracks the music index for `usb_headset` normally (e.g. 130/160) and
USB is not in `mFixedVolumeDevices`. The JA11 exposes `PCM Playback Volume` (0–100) and it stays at
100 — the output is a normal MIXER thread, so volume is software. `dumpsys media.audio_policy` shows
music on the `usb_device output` at **0.000 dB** at every index, and each volume step logs:

```
APM_AudioPolicyManager: setVolumeCurveIndex device 04000000, index 150, muted 0
APM::VolumeCurve: Invalid device category 6 for Volume Curve
```

**Root cause:** ColorOS adds two device categories to the audio policy, `DEVICE_CATEGORY_A2DP` (5) and
`DEVICE_CATEGORY_USB_HEADSET` (6), and maps USB headsets/DACs to 6 (strings in
`libaudiopolicycomponents.so` / `libaudiopolicyextimpl.so`). The port's
`/vendor/etc/audio_policy_volumes.xml` is Xiaomi's and only has the five AOSP categories. With no
curve, `VolumeCurves::volIndexToDb()` logs the error and returns 0 dB, i.e. full scale.

**Workaround:** `system/vendor/etc/audio_policy_volumes.xml` = stock file (md5 `be96e8f8…`) plus a
`DEVICE_CATEGORY_USB_HEADSET` and a `DEVICE_CATEGORY_A2DP` copy of every `DEVICE_CATEGORY_HEADSET`
curve (14 streams each), so USB and Bluetooth headsets use the wired-headset curves (AOSP files A2DP
under HEADSET too). The engine imports the `device_category` converter table from
`libaudiopolicycomponents`, which knows the OPLUS name, so the legacy parser accepts it. Generated by
`tools/patch_audio_volumes.py` (output md5 `6cfda1fd…`); bind-mounted by `post-fs-data.sh` like the
display files. Verified live: index 120 → -13 dB on the USB output, no more category errors.

Bluetooth (category 5) has the same gap. With absolute volume the policy index is pinned to max
anyway, so it only shows on headsets without absolute volume (or with it disabled), where the
volume would also be stuck at full scale. The A2DP curves were checked to parse live; not yet
tested with a Bluetooth headset.

**Proper fix:** ship `DEVICE_CATEGORY_USB_HEADSET` and `DEVICE_CATEGORY_A2DP` curves in the port's
vendor volume table, as OPPO devices do.

## 14. Speakers: left/right swapped in the flipped landscape orientation (v0.7)

**Symptom:** with the tablet in landscape the "other way round" (display rotation 270), left and
right are swapped on the speakers; normal landscape (rotation 90) is correct. In games this breaks
directional audio (reported for Delta Force on ColorOS beta4).

**Evidence:** AudioFlinger receives `rotation=0/90/180/270` (`dumpsys media.audio_flinger`, System
setParameters). The running HAL is the 32-bit `/vendor/lib/hw/audio.primary.kona.so`; on each
rotation and stream start it logs `set_eight_channel_each_speaker: AUDIO_ROTATION_x` and sets the
four Awinic amps' `aw882xx_spin_switch` (`tinymix -D 1`): 0→spin_0, 90→spin_270, 180→spin_180,
270→spin_90. Listening test with left-only noise: rotation 90 + spin_270 left (correct);
rotation 90 + spin_0 left pair; rotation 90 + spin_90 the portrait-bottom pair (right);
rotation 270 + spin_90 right (**wrong**); rotation 270 + spin_270 left (correct).

**Root cause:** the HAL's rotation table maps 270 to spin_90. Stock HyperOS ships the identical
table (same instruction at the same offset), so Xiaomi's framework presumably compensates through
its `Mi3DAudio` rotation parameter, which ColorOS never sends.

**Workaround:** `system/vendor/lib/hw/audio.primary.kona.so` = stock port HAL (md5 `8725bcea…`)
with the 270 branch's `mov r5, #1` (VA `0x41990`, file offset `0x40990`) changed to `mov r5, #3`
(md5 `90c5b882…`). Generated by `tools/patch_audio_hal.py`; bind-mounted by `post-fs-data.sh`
(label `vendor_file`). Verified live: rotation 270 now sets spin_270 and the left channel plays on
the left. Portrait (0/180) is unchanged and untested.

**Proper fix:** correct the rotation→spin table in the HAL (or send the Mi3DAudio rotation from the
framework).

## 15. C.06 boot hangs: system_server waits forever for HALs pipa lacks (v0.10)

**Symptom.** The first beta5 image (C.06 rebase) bootlooped: "Optimizing apps 99 %", then a reboot
every ~5 minutes. Later a UI that froze and restarted shortly after boot.

**Evidence.** `/data/anr/traces_SystemServer_WDT*` (ADB with root works during the loop) and
`/sys/fs/pstore/dmesg-ramoops-0` (`sysrq: Trigger a crash`, `Comm: watchdog`): system_server's
watchdog saw the same thread blocked for 60 s three times and panicked the kernel on purpose.

**Root cause.** Three blocking `waitForService` calls on HALs that do not exist on pipa:
1. `OplusEngineerFwService.getEngineerService()` (boot phase 480, main thread):
   `if (isRootVersion()) { initHalService(); ... }` else `waitForService("vendor.oplus.hardware.engineer.IEngineer/default")`.
   `isRootVersion()` is `!ro.adb.secure`. beta4 had deleted `ro.adb.secure` (U17), so it took the
   non-blocking path; beta5 restores `ro.adb.secure=1` and hangs. The code is identical in beta4 and C.06.
2. `system_ext/{lib,lib64}/libupdateprof.qti.so` (`GameGpuControlPanel` → QSPM profile, on the
   `android.display` thread) and 3. `libtrigger-handler.so`: C.06 switched the import
   `AServiceManager_checkService` → `AServiceManager_waitForService`; that is the only difference
   from the beta4 (C.05) copies (same size, same exports).

**Workaround (module).** `tools/patch_framework.sh` edit 4 turns the `if-eqz isRootVersion()` branch
into two nops, so the method always takes beta4's non-blocking path (2 bytes; in both framework jars).
The beta4 copies of the four libraries are in `system/system_ext/{lib,lib64}/` and bound with
`system_lib_file` (no-op where the ROM already has them). With v0.10 even the original beta5
image boots with `ro.adb.secure=1`.

**Proper fix (done in the rebuilt beta5 images).** Carry the four beta4 libraries
(`maintainer/c06-vs-beta4/PORT-EDITS.tsv`) and apply `PATCH=engineer tools/patch_framework.sh` to the
ROM jar (`maintainer/build_beta5.sh`). On a new donor build, scan changed libraries for new
`waitForService` imports before flashing.

## Install / check / remove

```sh
ksud module install pipa-cos17-power-tune-v0.10.zip   # or flash in KernelSU / Magisk, then reboot
```

```sh
cat /data/local/tmp/pipa_power_tune.log
getprop init.svc.xiaomi-keyboard                      # stopped without keyboard
ls -l /dev/input/event12                              # symlink only while the keyboard is attached
ps -A -o PID,STAT,NAME | grep -E 'AodBacklight|facehal'   # AOD pid in state T while AOD is off
service list | grep IFace/default                     # face HAL registered
md5sum /vendor/etc/qdcm_calib_data_xiaomi_m82_42_02_0b_*.xml   # 1e2ab685… = colour fix mounted (stock 151b5080…)
grep bind /data/local/tmp/pipa_power_tune.log         # post-fs-data bind results
grep 'brightness_table' /system_ext/etc/display_brightness_config_default.xml   # min="20"
dumpsys display | grep mScreenBrightnessRangeMinimum  # 20.0
dumpsys color_display | grep -E 'sensorCCT|sensorDataValid|currentCCT'  # adaptive/bedtime input
md5sum /vendor/etc/audio_policy_volumes.xml          # 6cfda1fd… = USB/A2DP volume curves (stock be96e8f8…)
md5sum /vendor/lib/hw/audio.primary.kona.so          # 90c5b882… = speaker rotation fix (stock 8725bcea…)
```

The runtime flags are in `/data/adb/modules/pipa_cos17_power_tune/config.prop`. Removing the
module restores everything on the next boot. `uninstall.sh` re-enables `com.pipa.faceunlock`,
resumes the AOD daemon and removes the `event12` link right away.

## Files

```
module.prop  config.prop  post-fs-data.sh  service.sh  (color_mode: runtime state)  customize.sh  uninstall.sh  README.md
system/vendor/etc/qdcm_calib_data_xiaomi_m82_36_02_0a_video_mode_dual_dsi_dphy_panel.xml
system/vendor/etc/qdcm_calib_data_xiaomi_m82_42_02_0b_video_mode_dual_dsi_dphy_panel.xml
system/system_ext/etc/display_brightness_config_default.xml
system/vendor/etc/audio_policy_volumes.xml   stock table + USB_HEADSET/A2DP volume curves (see 13)
system/vendor/lib/hw/audio.primary.kona.so   port HAL with rotation 270 -> spin_270 (see 14)
framework/<base-md5>.jar                     ROM jar + CCT sensor reroute + IEngineer fix, one per ROM build (see 12, 15)
framework/aliases                            other ROM jar md5s -> base md5 (see 12)
system/system_ext/{lib,lib64}/libupdateprof.qti.so, libtrigger-handler.so   beta4 copies (see 15)
tools/patch_qdcm.py            regenerate the colour files from the beta4 originals
tools/gen_brightness_table.py  regenerate the brightness table (MIN_LEVEL at the top)
tools/patch_framework.sh       regenerate a patched jar from a ROM's own oplus-services.jar
tools/patch_audio_volumes.py   regenerate audio_policy_volumes.xml from the stock table
tools/patch_audio_hal.py       regenerate the patched 32-bit audio HAL
tools/mitouch/                 xiaomi-touch ioctl get/set helper (diagnostics, not shipped)
```

The display files were generated from beta4 originals (input md5 `151b5080…` for 42_02_0b,
`c5794bfe…` for 36_02_0a, `4714aaab…` for the brightness config). If a newer port build changes
those files, regenerate them with the tools instead of reusing these copies.
