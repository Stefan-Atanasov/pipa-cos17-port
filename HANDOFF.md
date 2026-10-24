# Pipa COS17 port — handoff index (module v0.10)

Device: Xiaomi Pad 6 (`pipa`), 8 GB, active slot **B**.
ROM: the tablet runs **beta5-baked** (C.06 base, `OPD2515_17.0.0.103(CN01)`, maintainer
build, 2026-10-22); the original release was beta4 `OPD2515_17.0.0.102(CN01)` (2026-10-17).
See `MAINTAINER-STATUS.md`.
Root: KernelSU **4.2.0**, with `pipa_core` v1.10 (`pipa_core-v1.10.zip`).
Companion module: **`pipa-cos17-power-tune-v0.10.zip`** (md5 `ec6e3425…`;
non-destructive; works alongside `pipa_core` and never modifies it). v0.10 is
required with beta5; it ships one patched framework jar per ROM build and the
C.06 boot-hang fixes (`module/README.md` §15).

This file is a one-page index. It was written for the original developer in the
module v0.7 era and refreshed on 2026-10-22; the per-fix detail lives in
`module/README.md`, the status in `MAINTAINER-STATUS.md`.

## Read in this order

1. **`MAINTAINER-STATUS.md`**: from 2026-10-22 the original developer no longer updates the
   port, and the user maintains it. Roadmap, status, session plan and the doc map.
2. **`PORT-MAINTAINER.md`** and **`PATCH-INVENTORY.md`**: how to rebase onto a new donor
   build, and what the port changed.
3. **`README.md`** — the full device audit: findings ranked by idle-drain impact,
   evidence, reproduce commands, and what was changed live.
4. **`module/README.md`** — per-fix write-up: evidence, root cause, workaround,
   proper ROM fix. This is the main developer document.
5. **`HANDOFF-adaptive-bedtime.md`** — the CCT-sensor reroute for Adaptive
   colour / Bedtime mode (includes the exact beta4 dex edits).
6. **`AGENTS.md`** — instructions for an AI coding agent working on this
   workspace (device access, module build, constraints, gotchas).

## Fix matrix

| # | Symptom | Root cause | Module workaround | Proper fix |
|---|---|---|---|---|
| 1 | Screen-off drain ~53 mAh/h, CPU ~11.5 %, ~100 log lines/s | `/vendor/bin/xiaomi-keyboard` re-arms the accelerometer ~6.7×/s forever, even with no keyboard | start the daemon only while a Xiaomi pogo keyboard is present; `event12` symlink for fold detection | use stock `keyboardnanoapp`, or fix the daemon (back off when absent, detect by name, sleep ≥1 s) |
| 2 | AOD daemon polls `isInteractive()` every 300 ms with AOD off | `AodBacklightDaemon` loop in `pipa_core/aod_bl.jar` | `SIGSTOP` while `Setting_AodSwitchEnable != 1`, `SIGCONT` when on | exit early when AOD is off; listen for display state |
| 3 | Face unlock dead after one crash; framework retries 1×/s for hours | face HAL init `.rc` lacks `interface aidl …`, is `disabled`; `pipa_core` starts it once; `crop_eyes` SIGSEGV | face HAL watchdog restarts it every 15 s with the same binary/env | add the interface line, wrap `start_face` in a restart loop, fix `crop_eyes` |
| 4 | `com.pipa.faceunlock` retries a deleted socket every 3 s | leftover client for the old `/data/system/facehal_socket` stack | disable it while the socket is absent; `SIGSTOP` the live process | remove `/system/app/FaceUnlock` from the image |
| 5 | Colours oversaturated; "Natural" changes nothing | QDCM calibration ships PCC + gamut LUT disabled; COS17 has no Xiaomi displayfeature stack | PCC enabled in `standard` / `hal_srgb` with HyperOS `miLut_2`, row-normalised | ship corrected QDCM XMLs in vendor, or port Xiaomi's displayfeature stack |
| 6 | Minimum brightness ~19 nits, slider linear, auto wrong | table puts the curve in column B; ColorOS ExponentModel uses column P; no pipa framework overlay | generated table: AOSP/HyperOS gamma curve in P, `N` keyed to `P`, min 20 (~1 nit) | ship the table in `system_ext`, add `config_screenBrightnessSettingMinimumFloat=0.00171` |
| 7 | Adaptive colour / Bedtime do nothing | framework asks for OPPO CCT sensor 33171001; pipa exposes Xiaomi 33171088; Eye Protect app resets the switch | patched `oplus-services.jar` registers 33171088, fixed 100 lx, settings restored after boot | map the type in the framework, add a CCT+lux sensor in the vendor HAL, fix the app's `a1()` |
| 8 | Charging UI shows voltage 0, `getDataFromHalByOldInterface` spam | `pipa_core`'s charger shim registers after `system_server` reads `getChgConfig` | none (diagnosis only) | register the shim before `system_server`, implement the legacy JSON method |
| 9 | Face HAL SIGSEGV in `crop_eyes` | eye ROI outside the frame in `libjni_stfaceunlock_api.so` | watchdog hides it | clamp the rect / skip the frame |
| 10 | OTA says "storage less than 262.30 MB" | `/data/ota_package/OTA` missing; `StatFs` throws → free space treated as 0 | created the directory live (persists until data wipe) | create it in `pipa_core/service.sh`; never install the donor OTA |
| 11 | Thermal UI shows 60–70 °C while zones read 26–31 °C | donor/thermal-zone name mismatch (hypothesis) | none | verify `thermal-*.conf` mappings |
| 12 | Memory pressure, 176 OPPO packages | bloat | none yet | safe debloat list + measurement |
| 13 | USB-C DAC/headset volume stuck at max | ColorOS maps USB headsets to OPLUS `DEVICE_CATEGORY_USB_HEADSET` (6); Xiaomi volume table has no curve → 0 dB | v0.6: `audio_policy_volumes.xml` + USB_HEADSET/A2DP copies of the HEADSET curves | ship USB_HEADSET (and A2DP) curves in the vendor table |
| 14 | Speakers L/R swapped in flipped landscape (rotation 270) | HAL maps rotation 270 → `aw882xx_spin_switch` spin_90 (same table as stock; Xiaomi framework compensates) | v0.7: 32-bit `audio.primary.kona.so` with 270 → spin_270 (1 instruction) | fix the HAL rotation table |

## Idle drain (the original problem)

Before the fixes, `batterystats` showed **53.4 mAh/h** deep idle. The dominant
cause was the keyboard daemon: 143 accelerometer enable/disable pairs in 23 s,
83,817 `SensorService` + 43,726 `sensors-hal` lines in one buffer, `system_server`
8–16 % CPU, total ~11.5 %. Stopping it, freezing the AOD daemon and starting the
face HAL dropped screen-off CPU to **~2.75 %** and log rate to ~20 lines/s.

The module implements all three, plus the legacy face app, without killing
anything: the keyboard daemon is only stopped while no keyboard is attached,
the AOD daemon is frozen (not killed, `pipa_core` would respawn it), and the
face HAL is restarted by a watchdog.

## Face unlock

`pipa_core` starts the AIDL HAL from `/data/adb/modules/pipa_core/facehal` 6 s
after boot, as root, with `LD_LIBRARY_PATH` and the OpenCL loader. The init
service is `disabled` and has no `interface` line, so init never starts it. The
HAL crashed once with SIGSEGV in `crop_eyes` and was never restarted; the
framework then logged one `ctl.interface_start` failure per second for hours.
The watchdog starts the HAL only when neither init nor `pipa_core` has one
running; it uses the same binary/env. Face enrollment was **not** tested (the
templates directory was empty).

## Colours

Both QDCM XMLs (`qdcm_calib_data_xiaomi_m82_36_02_0a…`, `42_02_0b…`) ship with
PCC (FeatureType 2) and the 3D gamut LUT (FeatureType 3) disabled, so every mode
shows the raw ~DCI-P3 panel gamut. The module replaces them with copies where
`standard` (ModeID 0, Natural) and `hal_srgb` (18) enable PCC using HyperOS
`miLut_2` (sRGB→P3), each row normalised to 1 so native white/peak are kept.
Vivid (`hal_native`, 256) stays native. Generated by `tools/patch_qdcm.py`.

Colour mode can reset to 256 at boot; `service.sh` remembers `display_color_mode`
and restores it once.

## Brightness

ColorOS reads `<level>P,B,N,K</level>` and, for this panel, uses
`P[level]/P[last]` (ExponentModel) as the backlight; auto-brightness uses P as
the level axis and N as the nits at that level. The stock port put the curve in
B (never read) and P was linear, so the bottom ~15 % of the slider held all the
change and the minimum was ~19 nits. The module's table uses the AOSP/HyperOS
gamma curve in P, `N = nits(P[i])`, and `K` min 20. Measured: bottom ~1 nit,
25 % ≈20 nits, 50 % ≈76 nits, top 550 nits; auto ~63 nits at 10 lux. Generated
by `tools/gen_brightness_table.py`.

## Adaptive colour / Bedtime (v0.5; per-ROM jars since v0.9)

The framework's `OplusColorAmbientAdapter` asks for OPPO sensor type **33171001**;
pipa's tcs3701 only exposes **33171088**. The module's patched
`oplus-services.jar` (v0.9: `framework/<base-md5>.jar`, one per ROM build) registers 33171088, retargets the event switch (keys must be
sorted), and feeds a fixed **100 lx** because the Xiaomi event has no lux slot.
Adaptive colour then follows ambient CCT (~6100 K in the test); standalone
Bedtime (`oplus_customize_rhythm_health_enable`) warms to ~5263 K; with both on,
Adaptive wins during the day and Bedtime applies at night. The Eye Protect app
resets the settings at boot, so `service.sh` saves/restores them.

Full detail, exact offsets and limitations: `HANDOFF-adaptive-bedtime.md`;
current per-ROM behaviour and the odex guard: `module/README.md` §12.

## Not fixed / open

1. **Charger info** — the legacy `ICharger` interface and early shim registration
   (`pipa_core` issue; diagnosis in `module/README.md` §8).
2. **`crop_eyes` crash** — needs a clamp in `libjni_stfaceunlock_api.so` (§9).
3. **Thermal mapping** — name mismatch hypothesis (§10).
4. **Debloat** — no safe list yet (§10).
5. **Keyboard case** — the attach path and `event12` link were never tested on
   real hardware.
6. **Adaptive colour** — fixed 100 lx; real ALS lux is not bridged, so ambient
   brightness adaptation is lost.
7. **Idle drain after the fixes** — measured with v0.5 (not re-measured with v0.9):
   ~42 mAh/h (~0.5 %/h) screen off, vs 53.4 mAh/h before. CPU is asleep 99.5 % of the time; the rest is a
   hardware floor that this kernel can't break down (no RPMh stats).
8. **ColorOS sound effects (Audiox)** — `AudioEffectCenter` retries a missing Audiox
   effect every 3 s forever (`ro.oplus.audio.effect.type=audiox_merge`, no library in
   the port). Not fixed (audit "Bug sweep").

## USB DAC / Bluetooth volume (v0.6)

With a USB-C DAC (FiiO JA11) the volume slider did nothing: output stayed at full
scale. ColorOS files USB headsets under its own `DEVICE_CATEGORY_USB_HEADSET` (6)
and Bluetooth under `DEVICE_CATEGORY_A2DP` (5); the port's Xiaomi
`audio_policy_volumes.xml` has no curves for either, so the policy logs
`Invalid device category 6 for Volume Curve` and applies 0 dB. The module ships
the table with copies of the HEADSET curves for both categories. Verified on the
JA11 (index 120 → -13 dB); A2DP parses but is untested with a headset lacking
absolute volume. Detail: `module/README.md` §13.

## Speaker left/right in flipped landscape (v0.7)

In landscape rotation 270 the speakers played left and right swapped (rotation 90
was correct). The 32-bit HAL `/vendor/lib/hw/audio.primary.kona.so` maps rotation
270 to `aw882xx_spin_switch` = spin_90; listening tests show spin_270 is correct.
Stock HyperOS has the identical table, so Xiaomi's framework presumably compensates.
The module ships the HAL with one instruction changed (`mov r5,#1` → `#3` at file
offset `0x40990`). Detail: `module/README.md` §14.

## Install / verify / remove

```sh
# install (KernelSU / Magisk), then reboot
ksud module install pipa-cos17-power-tune-v0.10.zip

# verify
cat /data/local/tmp/pipa_power_tune.log
getprop init.svc.xiaomi-keyboard                  # stopped without keyboard
ps -A -o PID,STAT,NAME | grep -E 'AodBacklight|facehal'
service list | grep IFace/default
md5sum /vendor/etc/qdcm_calib_data_xiaomi_m82_42_02_0b_*.xml   # 1e2ab685…
dumpsys display | grep mScreenBrightnessRangeMinimum            # 20.0
md5sum /system/framework/oplus-services.jar                     # 00b9218b… (beta4 + module), 8810ad00… (C.06 + module, or beta5-baked)
dumpsys color_display | grep -E 'sensorCCT|sensorDataValid|currentCCT'
md5sum /vendor/etc/audio_policy_volumes.xml                    # 6cfda1fd…
md5sum /vendor/lib/hw/audio.primary.kona.so                    # 90c5b882…
logcat -d | grep 'Invalid device category'                     # empty
```

Remove the module (or set flags to 0 in `config.prop`) and reboot to restore
stock. `uninstall.sh` re-enables `com.pipa.faceunlock`, resumes the AOD daemon
and removes the `event12` link immediately.

## Files

```
pipa-cos17-power-tune-v0.10.zip     installable module (KSU/Magisk)
pipa-perf-test-v0.1.zip             separate A/B perf test module
pipa_core-v1.10.zip                 saved copy of the port author's pipa_core
README.md                           full audit
module/README.md                    per-fix developer write-up
module/tools/patch_framework.sh     regenerate the patched oplus-services.jar from a ROM jar
module/tools/patch_audio_volumes.py regenerate audio_policy_volumes.xml from stock
module/tools/patch_audio_hal.py     regenerate the patched 32-bit audio HAL
HANDOFF-adaptive-bedtime.md         CCT reroute detail + dex offsets (beta4)
MAINTAINER-STATUS.md                roadmap, status, doc map
AGENTS.md / CLAUDE.md               instructions for an AI agent
archive/                            superseded notes (MESSAGE.md, *.bak)
```

The live workspace also contains the original 5.2 GB ROM, extracted images, and
the `reference/` trees.
