# ColorOS 17 port for Xiaomi Pad 6 (`pipa`) — audit findings

> **2026-10-23: this file is the original audit of beta4, kept as the evidence record.** The tablet now
> runs ROM **beta5-2g** (see `MAINTAINER-STATUS.md`), where almost every fix below is built into the ROM and
> no KernelSU module is needed. Findings and evidence below are still valid; statements about modules and
> the "current" state are historical. The table "What was changed on the device" starts with a summary of
> what is still in place today.

Date: 2026-10-21
Device: Xiaomi Pad 6 (`pipa`), 8 GB RAM, boot slot `_b`
ROM: ColorOS 17 port beta4 (2026-10-17), `OPD2515_17.0.0.102(CN01)`
Fingerprint: `OPPO/OPD2515/OP6548L1:17/CP2A.260605.016/B.3b6223c-156ee02-15799c7:user/release-keys`
Kernel: `4.19.325-cip136-st20-N0-kernel++ #8 SMP PREEMPT Sat Oct 17 07:50:36 UTC 2026 aarch64`
Root: KernelSU **4.2.0-1-g904c60d1**; only module installed originally: `pipa_core` v1.10
ADB: USB serial `83836a90`, plus TCP `192.168.0.37:5555` (enabled during the audit so the cable could be pulled for idle measurements)

Everything below was observed live unless marked as a hypothesis. Commands are in
[Reproduce](#reproduce).

---

## TL;DR — ranked

1. **`/vendor/bin/xiaomi-keyboard` re-arms the accelerometer ~6×/second forever**, even with no keyboard
   attached. It is the dominant idle-drain source: ~100 log lines/s, sensors HAL 2.6–3.5 % CPU,
   `system_server` 8–16 % CPU while the screen was off. It also reads a hard-coded
   `/dev/input/event12`, which does not exist on pipa without the keyboard case.
2. **The face HAL is broken by design on this build**: its init `.rc` has no
   `interface aidl android.hardware.biometrics.face.IFace/default`, the service is `disabled`, and
   `pipa_core` starts the HAL exactly once from `/data`. When it crashed (SIGSEGV in `crop_eyes`),
   face unlock stayed dead and the framework retried `ctl.interface_start` **once per second for hours**.
3. **`AodBacklightDaemon` polls `isInteractive()` every 300 ms forever**, even though AOD is disabled.
4. **`com.pipa.faceunlock` (PERSISTENT) retries a socket that no longer exists every 3 s** — a leftover
   client for the old `/data/system/facehal_socket` stack.
5. **Measured deep-idle drain was ~53 mAh/h** (`batterystats`: 781 min deep non-interactive → 695 mAh)
   before the fixes. Screen-off CPU dropped from ~11.5 % to **~2.75 %** after stopping (1)/(3) and
   keeping the face HAL alive. A fresh unplugged measurement is still pending (see
   [Open items](#open-items)).

---

## Artifacts in this folder

| Path | What |
|---|---|
| `ColorOS17 Port for pipa-beta4-20261017.7z` | original 5.2 GB release (sparse `super.img` inside) |
| `ColorOS17 Port for pipa-beta4-20261017/` | fully extracted release (7.1 GB): `bin/`, `firmware/`, `super/super.img`, `FlashLinux.sh` |
| `work/super/super.img` | extracted sparse super image (6.4 GB) |
| `work/super_raw.img` | unsparsed super image (8.5 GB, `simg2img` intermediate) |
| `work/parts/` | `lpunpack` output: `system_b.img` (5.3 GB, erofs), `vendor_b.img`, `product_b.img`, `system_ext_b.img`, `odm_b.img` (all `_a` partitions are empty) |
| `work/FlashLinux.sh` | release flash script (flashes slot B, optional userdata/metadata wipe) |
| `pipa-cos17-power-tune-v0.9.zip` | companion module, current version (older zips are predecessors; `pipa-perf-test-v0.1.zip` is the separate A/B test module) |

Disk note: the extracted release and `work/` together use ~28 GB; ~22 GB free on `/home` at the time of
writing. `work/super_raw.img` and the duplicate `ColorOS17 Port .../super/super.img` can be deleted once
`work/parts/` is extracted (keep the sparse original `.7z`).

`system_b.img`/`vendor_b.img` are **EROFS**, not ext4. `debugfs` cannot read them; use
`dump.erofs --ls/--cat` (available on the audit host) or `fsck.erofs --extract`.

---

## Findings

### 1. `xiaomi-keyboard` — ~6 Hz accelerometer loop (primary idle drain)

Evidence:

- `dumpsys sensorservice`, previous registrations for `aidl_client_pid_1461` (`/vendor/bin/xiaomi-keyboard`):
  143 `+ 0x0000002b` / `- 0x0000002b` pairs in **23 s** (~6.2 Hz). Each cycle:
  `batch()` → `activate(en=1)` → event → `activate(en=0)`, logged at `I/` by the sensors HAL.
- Buffer snapshot: **83,817 `D/SensorService`** and **43,726 `I/sensors-hal`** lines out of 334,541
  total. At the time the device was writing **~170 log lines/s**.
- `top -b -n 2` with screen off: `android.hardware.sensors@1.0-service` 2.6–3.5 %,
  `system_server` 8–16 %, total CPU busy ~11.5 %.
- The binary (18 KB, stripped ELF) contains `ASensorEventQueue_enableSensor` /
  `ASensorEventQueue_disableSensor` and `sleep`/`usleep`, plus `Angle: %d, status: %d`,
  `Got sleap event`, `set_kb called`, and the hard-coded string `/dev/input/event12`.
- On pipa without the keyboard:
  `/dev/input/event12` **does not exist**. Present devices: `event7` = `xiaomi keyboard WakeUp`
  (pogo GPIO), `event6` = `Xiaomi Smart Pen Keyboard`, `event9` = `NVTCapacitivePen`,
  `event10` = `Xiaomi Smart Pen`, `event0/1/2/8` = touch/PMIC/gpio.
- The daemon is a `oneshot`/`disabled` init service started by `on boot` in
  `/vendor/etc/init/hw/init.device.rc`; it never exits, so it polls whether or not a keyboard is attached.
- Provenance: the binary and its `start` line are byte-identical to PixelOS (LineageOS device tree).
  Stock HyperOS has no `xiaomi-keyboard`; it uses the event-driven
  `vendor.xiaomi.hardware.keyboardnanoapp@1.0-service`, which the port's vendor dropped.

Impact: ~6 wakeups/s (≈540 k/day) plus ~100 log lines/s; keeps the sensor DSP, HAL, `system_server`
and `logd` busy. Killing it dropped screen-off CPU to **2.75 %** and log rate to ~20 lines/s.

Recommendation:
- Start it only while a keyboard is attached (input device names `Xiaomi Keyboard` /
  `Xiaomi Consumer Control`, per `/vendor/usr/idc/Xiaomi_Keyboard.idc`), or
- fix the sleep interval (≥1 s) and the hard-coded `event12`, and stop the sensor loop as soon as the
  keyboard node disappears.

The companion module implements the first option and restarts the daemon within 5 s of the keyboard
appearing, so keyboard users keep working. **Do not remove the daemon unconditionally.**

### 2. Face HAL — missing init interface, one-shot start, crash, 1 Hz retry

Evidence:

- `/vendor/etc/init/android.hardware.biometrics.face-service.facehal.rc` (both on device and inside
  `vendor_b.img`):
  ```text
  service vendor.facehal /vendor/bin/hw/android.hardware.biometrics.face-service.facehal
      class late_start
      user system
      group system camera input graphics root
      disabled
  ```
  No `interface aidl android.hardware.biometrics.face.IFace/default` line. `init.svc.vendor.facehal`
  was `stopped` for the whole boot.
- `pipa_core/service.sh` starts the HAL once (`start_face`, 6 s after boot) from
  `/data/adb/modules/pipa_core/facehal`, as root, with `LD_LIBRARY_PATH`. There is **no watchdog**.
- Crash buffer:
  ```text
  F/libc: Fatal signal 11 (SIGSEGV), code 2 (SEGV_ACCERR) in tid ... (facehal-auth)
  Process: /data/adb/modules/pipa_core/facehal/android.hardware.biometrics.face-service.facehal
  #09 cv::Mat::Mat(cv::Mat const&, cv::Rect_<int> const&)
  #11 crop_eyes(cv::Mat&, cv::Mat&, cv::Mat&, ...)
  #13 st_tee_eyestate
  #15 st_manager_image_process
  ```
  i.e. an out-of-range eye ROI passed to `cv::Mat::operator()(Rect)` in `libjni_stfaceunlock_api.so`.
  The HAL died at 21:00 and was never restarted.
- With no HAL registered, the framework logged **exactly one failure per second**:
  ```text
  W/libc: Unable to set property "ctl.interface_start" to
          "aidl/android.hardware.biometrics.face.IFace/default": PROP_ERROR_HANDLE_CONTROL_MESSAGE (0x20)
  W/libbinder.ServiceManagerCppClient: Waited one second for android.hardware.biometrics.face.IFace/default
  ```
  1046 occurrences in the captured buffer, still ongoing at 11:04:15.
- Starting the HAL manually (same command as `pipa_core`) immediately registered
  `android.hardware.biometrics.face.IFace/default` (servicemanager id 29) and the 1 Hz loop stopped.
- `/data/vendor_de/0/facedata/facehal/templates` is **empty** → no face was enrolled; face unlock was
  not functional even before the crash.

Recommendation:
1. Add the `interface aidl ...` declaration and test whether init can start it (the port authors say
   `hal_face_default` lacks camera/GPU permissions — verify before relying on it), **or**
2. keep the root start but wrap it in a restart loop (2–5 s backoff) so a crash cannot leave the
   framework retrying forever. The companion module does this.
3. Fix `crop_eyes`: clamp the eye rectangle to the frame bounds (and skip the frame) before the TEE
   feature call. A watchdog only masks the crash.

### 3. `AodBacklightDaemon` — 300 ms poll even with AOD off

Evidence:

- Decompiled `pipa_core/aod_bl.jar` (raw dex, `app_process`):
  `main()` → if `!isInteractive()` → `maybeApply()` → `Thread.sleep(300)` → loop. `maybeApply()` reads
  `/data/system/users/0/settings_secure.xml` (64 KB) at most once per 60 s and writes
  `/sys/class/backlight/4-0011/brightness` = 333 if AOD is on.
- `Setting_AodSwitchEnable=0` (AOD off) on this device, yet the daemon polls `isInteractive()` over
  binder **3.3×/s** forever. `4-0011/brightness` was 333 while `panel0-backlight` was 0 (screen off).
- The daemon is restarted by `pipa_core`'s `run_aod` loop 5 s after it exits, so `kill -9` does not stick.

Recommendation: poll ≥2 s (or listen to display/screen-state changes) and return immediately when AOD
is disabled. The companion module freezes it with `SIGSTOP` while `Setting_AodSwitchEnable != 1` and
`SIGCONT`s it when AOD is enabled.

### 4. `com.pipa.faceunlock` — obsolete socket client

Evidence:

- Package `com.pipa.faceunlock` (`/system/app/FaceUnlock/FaceUnlock.apk`, v2.0, `SYSTEM`,
  `PERSISTENT`, `ALLOW_CLEAR_USER_DATA`) runs `ax.nd.faceunlock.FaceUnlockService` from a boot
  receiver. It connects to `/data/system/facehal_socket` in a loop:
  ```text
  E/FaceUnlockService: java.io.IOException: No such file or directory
  E/FaceUnlockService: Socket session ended, retrying in 3000 ms
  ```
  350 stack traces in the captured buffer (one every 3 s).
- `/data/system/facehal_socket` and `/data/system/facedata_system` **do not exist**.
- The current AIDL `facehal-rs` binary (`/vendor/bin/hw/...facehal`, Rust strings
  `crates/face/src/aidl/...`) does not contain `facehal_socket`; its strings are
  `failed to register Face HAL` / `FaceHAL preview: enrollment surface received`.
  So the app is a leftover from the previous socket-based implementation.

Recommendation: remove it from the image or disable it (the companion module disables it only when
`/data/system/facehal_socket` is absent, and re-enables it if the socket stack is in use).

### 5. Idle drain baseline

`dumpsys batterystats` (battery capacity reported as 8644 mAh):

```text
Deep    NonIntr:  781m   695mAh ( 9%)   53.4mAh/h
Light   NonIntr:   10m    14mAh ( 0%)   82.9mAh/h
NonDoze NonIntr:    6m     8mAh ( 0%)   85.6mAh/h
Intr:              21m   252mAh ( 3%)  712.5mAh/h
```

The 53.4 mAh/h in deep non-interactive matches the loops above. After stopping the keyboard daemon,
freezing the AOD daemon and starting the face HAL, screen-off CPU was ~2.75 % (778/800 idle) with
`system_server` at 1.2 %. A fresh unplugged measurement was not completed (USB keeps the pad charging;
a 6 min `/sys/class/power_supply/battery/current_now` sample is the next step).

### 6. Charging HAL mismatch (cosmetic + log spam)

- `E/OplusBatteryService: getDataFromHalByOldInterface` appears **5178 times over 16 h** (~every 11 s).
- `dumpsys battery` reports `Charger voltage : 0`, `ChargerTechnology: 0`, and the current sign flips
  (`Battery current: +182128` then `-325683`).
- The shim (`pipa_core/chargershim.jar`, `shim.ShimHost`/`ShimRegister`) registers
  `vendor.oplus.hardware.charger.ICharger/default` (servicemanager id 361) and its log is clean, but
  ColorOS also calls an older interface the shim does not implement.

Impact: wrong charging info in the UI, continuous error logging. Not a large drain but definitely
unpolished. Recommendation: implement the legacy method in the shim (or silence the caller) and
report a sane charger voltage.

### 7. `com.oplus.midas` boot crash

```text
E/AndroidRuntime: FATAL EXCEPTION: healthinfo
Process: com.oplus.midas
java.lang.NumberFormatException: For input string: "show"
    at com.oplus.qualityprotect.QualityProtectService.c(SourceFile:52)
```

Likely a ColorOS setting/property expected to be numeric but containing the string `show`.
One-shot at boot; worth checking in the donor/port diff.

### 8. Memory pressure / bloat

- `Mem: 7,787,072K total, 7,509,500K used, 281,572K free`; zram swap 16 GB with **~690–720 MB used**;
  `kswapd0` and several `kworker/*-memlat_wq` / `ufs_clkscaling` threads active even with screen off.
- `pm list packages -s | grep -cE 'com\.(oplus|heytap|coloros|oppo|pipa)'` = **176** OPPO-family system
  packages, plus GMS and Play Store. `com.android.vending` was repeatedly restarting
  (PIDs 24836 → 24979 → 6359) and burning 3–5 % CPU in bursts.
- This is a major source of background wakeups and jank on an 8 GB tablet. A debloat list (or
  `pm disable-user` set) would help both idle and memory; do not remove packages the ColorOS UI
  depends on (Athena, SystemUI overlays, etc.).

### 9. Location / Wi-Fi scanning

- `settings get global wifi_scan_always_enabled` = **1**, `location_mode` = **3** (high accuracy).
- `dumpsys location`: GMS has active `fused_location_provider` (`BALANCED`) and
  `network_location_provider` (passive) requests; 77 fixes over 16 h.
- On a Wi-Fi-only tablet this adds scan wakeups. Optional: turn off Wi-Fi/Bluetooth scanning in
  Location settings or set `wifi_scan_always_enabled=0` if the user does not need network location.

### 10. Thermal sensor mapping (hypothesis)

`dumpsys thermalservice` reports `CPU0 60.0 °C … CPU4 70.1 °C` while the raw thermal zones read
**26–31 °C** and thermal status is 0. That looks like a donor/thermal-zone name mismatch. It did not
throttle during the audit, but wrong CPU temperatures can trigger throttling or misleading UI later.
Check `/vendor/etc/thermal-*.conf` mappings. 32 of the 43 profiles differ from stock (= PixelOS), with the
same length and an identical prefix, but they are Xiaomi-encrypted, so what changed (sensor names or trip
points) is not readable without decrypting them (`PATCH-INVENTORY.md` U2).

### 11. Software update falsely reports "storage space is less than 262.30 MB"

Reported symptom: **Settings → Software update** shows
`Available storage space is less than 262.30 MB. Unable to download.` while `/data` has ~91 GB free.

Root cause: the OTA app (`com.oplus.ota`) checks free space on its download directory
**`/data/ota_package/OTA`**. That directory was **missing** on this install. `StatFs` on a nonexistent
path throws; `Lhd/e;->f(String)` catches it and returns `0`, so the check compares `0` against the
package size. The `262.30 MB` is the update size, not a threshold: the OTA prefs contain
`shelf_pkg_total_size=275043374` bytes = **262.30 MiB** exactly. `/data` itself is fine
(`Data-Free: 89,232,192K / 111,761,388K`), and the configured low-space threshold is
`sys_flash_low_threshold=7,340,032,000` (7.34 GB) — the real check would pass.

Fix that worked: create the directory with the expected ownership/label:

```sh
mkdir -p /data/ota_package/OTA
chown system:cache /data/ota_package/OTA
chmod 0770 /data/ota_package/OTA
restorecon /data/ota_package/OTA
```

After reopening Software update the dialog is gone and the update page renders normally with a
**Download & install** button.

**Do not install the offered package.** It is a **262.30 MB SOTA app bundle for the donor model
OPD2515** (15 OPPO apps: Phone Manager, OSee, Content Portal, remotecontrol, encryption, …), not a
pipa build. It can overwrite port-patched system apps. The OTA updater should ideally be disabled on
the port (or at least never used to install).

Persistence: the directory survives reboots but not a data wipe. If desired, add the `mkdir`/`chown`/
`chmod`/`restorecon` block to `pipa_core`'s `service.sh` (or the companion module) so it is recreated
after a factory reset.

### 12. Smaller polish items

- `ro.build.tablet_type` is **not** in `system/build.prop`; `pipa_core/post-fs-data.sh` sets it with
  `resetprop` every boot (`pad`). Bake it into `build.prop` when building the next system image.
- `persist.sys.facehal.verbose=true` is set; with the HAL alive this can add log volume. Consider
  `false` for release.
- Peak refresh rate setting is `144.0` (`settings get system peak_refresh_rate`); fine for the panel,
  but worth exposing a 60/120/144 choice.
- Rounded-corner overlay is healthy: `com.port.pipa.overlay.corners` → `STATE_ENABLED`, mapping
  `dimen/rounded_corner_radius*`; the `post-fs-data.sh` idmap fallback worked.
- Product identity is donor OPPO: `ro.product.model=OPD2515`, `ro.product.system.device=ossi`.
  Expected for the port, but it is what Settings/About shows.

---

## What was changed on the device during the audit

### What is in place on the tablet today (2026-10-23, beta5-2g)

| Item | Where | Notes |
|---|---|---|
| ROM beta5-2g flashed to slot B | `super` partition | `maintainer/flash_super.sh beta5-2g`; rollback by flashing an older name |
| OTA updater packages removed, `/data/ota_package/OTA` created | ROM + `/data` | the directory is recreated by a ROM init rc |
| Settings: `device_case_enabled`, `lid_behavior`, `stylus_buttons_enabled`, `settings_enable_oppo_pencil`, `pipa_pen_state`, `animationBlurrySwitch`, colour/adaptive/bedtime values | `/data/system/users/0/settings_*.xml` | written by the pipa helper / `pipa_port` service; lost on a data wipe, rewritten on the next boot |
| `pm disable com.oplus.audio.effectcenter/.service.AudioxService` (stops an endless retry loop for an effect pipa lacks) | package state in `/data` | in the ROM since beta5-2g (sysconfig `component-override`, verified); earlier builds had only the live disable, lost on a data wipe |
| `persist.vendor.facehal.rotation` | persist prop | managed by `pipa_port` |
| Test leftovers | none | `/data/local/tmp` cleaned on 2026-10-23 (old module zips, patched jars, captures); `post-fs-data.d` scripts, bind mounts, `/data/adb/pipa-bootlogo`, test loops and helper test installs were removed on 2026-10-22/23 |
| Kernel A/B test leftovers (2026-10-23, `kernel/KERNEL-RESEARCH.md`) | `/data/adb` | `ksud` is the **original 4.2.0 again** (restored from TWRP). Unused copies: `ksud-4.2.0`, `ksud-4.2.1`, `ksud-switch` (the ELF switch; the current kernel did not boot with it, do not reuse), empty `modules_update/`, `post-fs-data.d/`. Manager = v4.2.0 backup (new uid). Nothing flashed |
| **Own WALT kernel flashed to `boot_b`** (2026-10-23 21:40, `port-work/kernel/bootimg/boot-walt-r1.img`, md5 `50e0c829…`, commit `2c31004cc27a`) | `boot_b` | Lineage 24 + pipa + E404 display/touch + SukiSU/susfs, `kernel/WALT-KERNEL.md`; rollback `maintainer/kernel/flash_kernel.sh flash port-work/kernel/bootimg/boot-e404-r2b.img`; ksud/manager 4.2.1-r1 match both |
| **Kernel walt-r3 flashed to `boot_b`** (2026-10-24 01:00, `port-work/kernel/bootimg/boot-walt-r3.img`, md5 `9a167e41…`, commit `920120643a03` on `oppo`) | `boot_b` | walt-r2 + kgsl: SurfaceFlinger GPU contexts priority 1, SystemUI 4. Rollback: `flash_kernel.sh flash …/boot-walt-r2.img` |
| **Taskbar on + material blur off (2026-10-24 afternoon, user choice; replaces "taskbar off")** | `settings put system enable_launcher_taskbar 1`, `system_material_blur_enable 0` (persistent) | smoothest measured: launcher 7 % janky; folders/taskbar without frosted glass. Set blur back with `system_material_blur_enable 1` |
| **Launcher taskbar off (2026-10-24, user choice)** | `settings put system enable_launcher_taskbar 0` (persistent) | launcher App Deadline misses -70 % in the heavy test; set 1 to get the dock bar in apps back |
| **KSU boot scripts (retired 2026-10-24, now in ROM beta5-2j)** | moved to `/data/local/tmp/ksu-retired/` | were: SF `enable_layer_caching=1` + `predict_hwc_composition_strategy=1`; `setprop ctl.stop loc_sys_service`. Move back only when rolling back to 2i |
| **Live, smoothness session 2026-10-23 night** (reset by reboot unless noted) | runtime | `loc_sys_service` stopped (`setprop ctl.stop`); `traced.relay_producer_port` and `ro.traced.hypervisor` deleted with `resetprop -d`; `persist.traced.enable` **persistent**: set back to 0 after tracing, otherwise `traced` crash-loops every 5 s after the next boot until beta5-2j. Test files in `/data/local/tmp`: `kgest`, `ktap.sh`, `ktrace.sh`, `jank.cfg`, `ft.cfg`, traces (`*.atrace`, `*.pftrace`, `ktrace.txt`, `sde.txt`; delete when done). Peak refresh rate and CPU/GPU min clocks were changed for A/B tests and restored (144 Hz, policy min 1171200/710400/844800, GPU `min_pwrlevel` 6) |
| KernelSU modules | `pipa_susfs` (root hiding, installed 2026-10-23, applied since the 00:13 reboot) | root = SukiSU Ultra v4.2.0; backups of its manager APK and `ksud` in `kernel/sukisu-backup/` |

The long table below is the history of live changes during the audit and the module era; most rows
are reverted or replaced by the ROM.


Live only (unless noted), reversible by reboot:

| Change | Persistence |
|---|---|
| killed `xiaomi-keyboard` (pid 1461) | until reboot (`oneshot` init service starts again) |
| started the face HAL from `pipa_core/facehal` as root; `IFace/default` registered | until reboot / next crash (no watchdog in `pipa_core`) |
| `pm disable-user com.pipa.faceunlock` + `kill -STOP` on the live process | package state persists; process state until reboot |
| froze `AodBacklightDaemon` (`SIGSTOP`, AOD off) | `pipa_core`'s loop restarts it after a kill, but SIGSTOP sticks until a `SIGCONT`/reboot |
| installed `pipa_cos17_power_tune` **v0.2** (2026-10-21 12:02) + 2 reboots; `post-fs-data.sh` bind-mounts the sRGB QDCM calibration and the linear brightness table (min 20) | until the module is removed (see `module/README.md`) |
| created `/data/ota_package/OTA` (`system:cache 0770`, `ota_package_file`) | persists until a data wipe; fixes the false "storage space is less than 262.30 MB" dialog |
| enabled ADB TCP `:5555` | `service.adb.tcp.port=5555`; USB debugging untouched |
| 2026-10-21 21:10: bind-mounted `/data/local/tmp/apv_test.xml` (USB_HEADSET volume curves) over `/vendor/etc/audio_policy_volumes.xml` and restarted `audioserver` (USB DAC volume fix, `module/README.md` §13); 21:15 replaced with `apv_test2.xml` (+A2DP curves) | until reboot (superseded by v0.6) |
| 2026-10-21 22:24: bind-mounted `/data/local/tmp/audio.primary.kona.patched.so` over `/vendor/lib/hw/audio.primary.kona.so`, restarted `android.hardware.audio.service`; amp `aw882xx_spin_switch` set by hand during listening tests | until reboot (v0.7 makes it permanent) |
| installed `pipa_cos17_power_tune` **v0.6** (2026-10-21 ~21:17) + reboot; adds the USB/A2DP volume table bind; carried `adaptive_state`/`bedtime_state`/`color_mode` into the update | until the module is removed |
| 2026-10-22 16:12: `ksud susfs enable-avc-log-spoofing 0` for the SELinux capture (parked: kernel AVCs reach no log anyway) | until reboot (reverted by the reboot at 16:19) |
| 2026-10-22 16:19: installed module **v0.9** on beta4 + reboot | superseded by v0.10 |
| 2026-10-22 16:31: **flashed** the round-trip super (beta4 rebuilt by our pipeline, `090e5a32…`), slot B, no wipe | replaced by the beta5 flash |
| 2026-10-22 16:38: **flashed beta5** (`adde65cf…`, first image): bootloop (three C.06 `waitForService` hangs, `module/README.md` §15). Temporary workaround `/data/adb/post-fs-data.d/pipa_adb_secure.sh` + `/data/adb/pipa_fix/` (beta4 libs); `vdc checkpoint commitChanges` so `/data` writes survived the loop | workaround removed 17:12 |
| 2026-10-22 17:12: installed module **v0.10** (carries the hang fixes) | until the module is removed |
| 2026-10-22 17:24: **flashed beta5-baked** (`47de4c68…`, hang fixes in the ROM), slot B, no wipe. **Current ROM.** | until the next flash |
| 2026-10-22 17:59: `pm uninstall --user 0` of `com.oplus.ota`, `com.oplus.sau`, `com.oplus.sauhelper` (live test for the ROM removal; Settings hides the update entry) | until undone with `cmd package install-existing <pkg>`, or moot once a build without them is flashed |
| 2026-10-22 18:10: flashed rebuilt **beta5-baked** (`52d9b870…`, updater removed); 18:21: flashed **beta5-1c** (`aeda43d3…`). **Current ROM: beta5-1c.** | until the next flash |
| 2026-10-22 17:37: pen test: `am startservice … PENCIL_STATUS_CHANGE` (present 1), `settings put global ipe_pencil_battery_level 100`; reverted with present 0 + `settings delete` (`BUGS-TODO.md` B3). Left behind: `ipe_pencil_mac_addr`, `ipe_pencil_bt_device_name` (harmless) | reverted |
| 2026-10-22 18:29–21:30 (this session): kprobe-based AVC tracing (`maintainer/avc_trace.sh`), `setprop ctl.restart logd` once | live only, gone at reboot |
| 2026-10-22 18:45: **flashed beta5-2a** (`b739a96c…`); 19:01 installed **pipa_core v1.11**; 19:15 **flashed beta5-2b** (`6149c1d9…`) | superseded |
| 2026-10-22 19:46: installed **pipa_core v1.12** and **power-tune v0.11**, then v0.12 (20:08), v0.13 (20:23), **v0.14** (21:18) | until the modules are removed |
| 2026-10-22 20:32–20:41: `pipa_core/keys.conf` on the device: `pageup=120` (back button = screenshot), `pagedown=none` (front button free for apps); backup `/data/local/tmp/keys.conf.bak` | persists |
| 2026-10-22 20:34: `settings put secure stylus_buttons_enabled 1` (pen buttons reach apps, B12) | persists until a data wipe |
| 2026-10-22 20:47–21:13: idle-refresh test: `/data/adb/post-fs-data.d/99-pipa-vrr-test.sh` bound a modified `oplus_vrr_config.json` (hw_enable/refreshrate_director false); removed again; `/data/local/tmp/oplus_vrr_config.json` may remain (inert) | removed |
| 2026-10-22 21:13: **flashed beta5-2c** (`f607d89d…`). **Current ROM: beta5-2c** | until the next flash |
| power-tune v0.14 manages global `settings_enable_oppo_pencil` (pen out of the dock = 1) and sends the IPeManager pen-present intent; `secure oplus_customize_screen_refresh_rate` = 8 (user's 144 Hz choice) | while the module is installed |
| 2026-10-22 21:45 (B10): `pm disable com.oplus.audio.effectcenter/.service.AudioxService` (stops the endless 3 s AudioX retry loop), then `kill` of the persistent `com.oplus.persist.multimedia` (restarted by AM, no side effects seen; Dolby `DAP_offload` stayed active). Undo: `pm enable com.oplus.audio.effectcenter/.service.AudioxService` + reboot | **persistent** (package state, survives reboot; lost on a data wipe) |
| 2026-10-22 21:54 (B10): installed **pipa helper 0.1** (`com.port.pipa.helper`, user app, `helper/out/PipaHelper.apk` md5 `4795ccec…`) and `settings put global hidden_api_blacklist_exemptions "Landroid/media/audiofx/AudioEffect;"` (test only: user apps may not call AudioEffect's hidden setParameter; the ROM build uses a sysconfig `hidden-api-whitelisted-app` entry instead). Undo: `pm uninstall com.port.pipa.helper`, `settings delete global hidden_api_blacklist_exemptions` | **persistent** |
| 2026-10-22 22:13–22:16: test helper uninstalled, global hidden-api exemption deleted; power-tune **v0.15** installed; **flashed beta5-2d** (`3dfbe181…`, helper as system app). **Current ROM: beta5-2d** | until the next flash |
| 2026-10-22 22:26: power-tune + pipa_core removed, **pipa_port v1.0** installed (merged module) | until changed |
| 2026-10-22 22:38 (B13): `/data/adb/post-fs-data.d/99-pipa-padorient-test.sh` (`resetprop ro.panel.pad_orientation 90`). Remove after 2e | **persistent** (file) |
| 2026-10-22 22:55 (B14): `settings put global lid_behavior 1` (pipa_port v1.2 now keeps it in step with `device_case_enabled`); 22:45 (B7): `setprop persist.vendor.facehal.rotation` (managed by v1.2) | **persistent** (settings / persist prop) |
| 2026-10-22 23:13 (B13 logo): `/data/adb/post-fs-data.d/98-pipa-bootlogo-test.sh` binds `/data/adb/pipa-bootlogo/{,r}bootanimation.zip` over `/my_product/media/bootanimation/`. Remove after 2e | **persistent** (files) |
| 2026-10-22 23:30: removed module pipa_port, test scripts (rotation, logo) and `/data/adb/pipa-bootlogo`; **flashed beta5-2e** (`3340aae2…`). **Current ROM: beta5-2e** | until the next flash |
| 2026-10-22 23:42–23:50 (B12 debug): `mount --bind /data/local/tmp/pen_keys_dbg.sh /system_ext/pipa_port/pen_keys.sh` (fixed listener, `</dev/null`), `avc_trace.sh start` armed, `stop/start pipa_port` | live only, gone at reboot |
| 2026-10-22 23:18: pipa_port **v1.3** service.sh + module.prop copied into `/data/adb/modules/pipa_port/` and the loop restarted live (lid sync on settings file change) | until changed |
| 2026-10-22 23:07: **pipa_port v1.2** installed (B7 crop + rotation, B14 lid sync); B7 test loop and files removed | until changed |

Module state: the table above is in the order the changes were made, not strictly by date. The
module version installed on the tablet is not tracked here; check `ksud module list`. As of
2026-10-22 21:30 the tablet runs **beta5-2c** with power-tune **v0.14** and `pipa_core` **v1.12**. The OTA
updater apps are uninstalled for user 0 (and removed from the rebuilt images, roadmap row 1);
`device_capture.sh --unhide-avc` (roadmap row 12) is a boot-only change that a reboot undoes.

No user data was wiped. Partitions flashed: only `super` (slot B), on 2026-10-22 (round trip, beta5, beta5-baked; see the table).

---

## Companion module: `pipa_cos17_power_tune` v0.1

> (historical, v0.1; superseded by v0.9, see `module/README.md` for the current module and
> `module/config.prop` for its flags.) Current build: `pipa-cos17-power-tune-v0.9.zip`
> (md5 `4d479de1…`). The text below describes the original v0.1 only.

Path in this folder: `pipa-cos17-power-tune-v0.1.zip` (md5 `1c8f066c5cb025a3c1153435e8cc73f9`; old zip, not the current build).
Installed with `ksud module install` (KernelSU 4.2.0) and enabled alongside `pipa_core`.
It is a normal Magisk/KSU module (`module.prop`, `service.sh`, `customize.sh`, `uninstall.sh`,
`config.prop`, `README.md`). KernelSU stages it in `/data/adb/modules_update/` and applies it on reboot;
KSU's installer does not copy `customize.sh`/`README.md` into the runtime folder, which is expected.

Behaviour (all flags in `config.prop`):

- `KEYBOARD_GUARD=1` — `xiaomi-keyboard` runs **only while** a Xiaomi pogo keyboard is present
  (`Name="Xiaomi Keyboard"`, `Xiaomi Consumer Control`, `Xiaomi Touchpad`). It is started/stopped with
  `setprop ctl.start|stop xiaomi-keyboard`; pen devices and `xiaomi keyboard WakeUp` are excluded.
- `AOD_GATE=1` — `SIGSTOP` the AOD daemon while `Setting_AodSwitchEnable != 1`, `SIGCONT` when on.
  Freezing avoids fighting `pipa_core`'s 5 s restart loop.
- `FACE_WATCHDOG=1` — restart the HAL from `pipa_core/facehal` (same `LD_LIBRARY_PATH` and OpenCL
  loader choice) when neither init nor `pipa_core` has one running; logs each restart.
- `LEGACY_FACE_APP=1` — disable `com.pipa.faceunlock` only when `/data/system/facehal_socket` is
  absent; re-enable it when the socket exists. Live process is `SIGSTOP`ped to stop the 3 s retry loop.
- `uninstall.sh` re-enables the face app, resumes the AOD daemon and removes the pidfile.

Verified live (2026-10-21):

- `kill -9` on the face HAL → log `facehal was not running -> started pid=…`; `IFace/default`
  re-registered within one tick.
- AOD 1 → `aod on -> resumed pid=…` (state `S`); AOD 0 → `aod off -> suspended pid=…` (state `T`).
- Started `xiaomi-keyboard` manually → `keyboard absent -> xiaomi-keyboard stopped`.
- Regex checked against synthetic `/proc/bus/input/devices` lists containing keyboard, pen and
  `xiaomi keyboard WakeUp` entries.
- Second instance exits immediately via pidfile singleton.
- `ksud module install` → *Module installed successfully*; module listed enabled.

Log: `/data/local/tmp/pipa_power_tune.log`. The guard waits for `sys.boot_completed`, sleeps 20 s
(to let `pipa_core` start its daemons), then polls every 5 s (AOD/face every 15 s).

**Caveat:** the keyboard guard matches input device names. If another SKU enumerates differently,
add its name to `kb_attached()`; without a match the daemon stays stopped, so test with the actual
keyboard before shipping. The physical attach path was not tested here (no keyboard case available);
only the stop path and the `ctl.start` start path were exercised.

## Memory / zram (checked 2026-10-21)

- zram0 8 GiB, lz4 (zstd available), priority 32758; plus **nandswap** (set up by the port author's
  `/odm/etc/init.oplus.mm-sys.sh`, called from ColorOS's `init.oplus.nandswap.sh` hook): an 8 GiB
  `/data/nandswap/swapfile` on `loop48`, priority 2020 (`persist.sys.oplus.nandswap*`). 16 GiB of
  swap on 7.4 GiB RAM. zram is always used first, so the flash swapfile only takes overflow; it costs
  8 GiB of storage and flash writes once zram fills.
- The port kernel has **no hybridswap / zram writeback** (`CONFIG_ZRAM_WRITEBACK` unset, no
  `hybridswap_*` nodes). OPPO's userspace still expects it: `PerformanceService` (vendor) logs
  `open file /sys/block/zram0/hybridswap_swapd_pause failed` twice every 20 s, and `Athena`
  (`HybridSwap: bootCompress: pidMap is empty`). Harmless log noise, no functional loss beyond the
  missing feature.
- `swappiness=60`, `page-cluster=3` (0 is the usual choice for zram), PSI memory pressure low
  (avg300 ≈ 1.3 % some), lmkd PSI mode, no kill storms seen. Nothing actionable without a load test.

## Bug sweep (2026-10-21, v0.6, after reboot)

- **Crashes since boot:** none. Older tombstones: face HAL (`crop_eyes`, known) and two
  `android.hardware.audio.service` aborts at 13:10/13:11 in `BatteryListenerImpl::~` caused by the
  `system_server` restarts during the framework-jar work that afternoon. App crashes:
  `com.oplus.midas` / `qualityprotect` `NumberFormatException: "show"` (OPLUS bug, harmless) and one
  SystemUI keyguard transition NPE.
- **Quad-speaker rotation works.** The running HAL is the 32-bit `/vendor/lib/hw/audio.primary.kona.so`
  (the 64-bit one lacks the Xiaomi rotation code but is not used). AudioFlinger receives
  `rotation=0/90/180/270`; during playback the HAL logs `set_eight_channel_each_speaker:
  AUDIO_ROTATION_x` and sets the Awinic amps' `aw882xx_spin_switch` (0→spin_0, 90→spin_270,
  180→spin_180, 270→spin_90). With nothing playing the spin is not updated (expected). The internal
  card is card 1 after this boot (`tinymix -D 1`). Speakers are 4× aw882xx (`0-0036/37`, `2-0034/35`).
- **ColorOS sound effects (Audiox) cannot work:** `AudioEffectCenter` (`com.oplus.audio.effectcenter`,
  process `com.oplus.persist.multimedia`) starts `AudioxService` because
  `ro.oplus.audio.effect.type=audiox_merge` (`/my_product/build.prop`) and the feature flags in
  `/my_product/etc/permissions/oplus.product.features_audiox.xml`, but no Audiox effect library
  (type `41f6c0f4-5d8f-11ec-bf63-0242ac130002`) exists in the port; the vendor effects are Xiaomi's
  (Dolby DAX3 `libswdap/libhwdap/libswgamedap`, `misoundfx`). `AudioxService.t()` retries every 3 s
  forever (log spam while awake). Clearing the prop live and restarting the app did not stop it (the
  service is started regardless); a proper test needs `resetprop` in post-fs-data + reboot. Not fixed.
- **Dolby (Xiaomi MiSound):** the port ships `com.miui.misound` (+ `PipaMiSoundOverlay`) and
  `vendor.dolby.hardware.dms@2.0-service`; open via Settings → Sound → Sound effects
  (`com.miui.misound/.HeadsetSettingsActivity`, no launcher icon). It attaches `DAP_offload` to the
  global mix (session 0) and reports `dolby` as the enabled effect. `system_dolby=0` is an unused
  ColorOS key. Harmless noise: `DiracUtils NoSuchFieldException IS_MI2A/IS_HONGMI_*` (old MIUI model
  checks) and `EffectMiSound ... Unsupported device speaker 3DSURROUND` (3D surround mode is not
  available on the speakers). User reports enabling is "sometimes finicky"; not reproduced, left open.
- **Log noise, harmless:** `SchedAssist binderSetThreadUxFlagByIoctl` (~230/min, OPLUS kernel feature
  missing), `PerformanceService ... hybridswap_swapd_pause` (no hybridswap), `SettingsState invalid
  flag name` (device_config sync), `OplusBatteryService getDataFromHalByOldInterface` (finding #6).
- **Delta Force directional audio report (third party):** not reproduced; speaker mapping follows
  rotation correctly, the Android spatializer is off (`isSpatializerEnabled:false`), and no default
  effect is inserted on music (only volume listeners). Reporter uses speakers. Listening test
  (2026-10-21, both landscape orientations, stereo noise bursts L-only / R-only / centre / centre with
  R phase-inverted): left and right on the correct sides in both orientations, centre in the middle,
  inverted reference audibly different. Speaker channel mapping and phase are correct; the front/back
  confusion is most likely the game's 3D/HRTF rendering on speakers (game setting), not the port.
  **Correction:** that test was in normal landscape only. Flipped (rotation 270) left/right **are
  swapped**: HAL bug, fixed in v0.7 (`module/README.md` §14).

## Thermals under load (tested 2026-10-21)

8-core busy loop, 180 s per run, tablet charging, logging every 5 s (`scaling_max_freq`,
prime-core `scaling_cur_freq`, hottest `cpu-1-*-usr` zone, battery):

| `sconfig` | caps written by `mi_thermald` | hottest core | prime core | battery |
|---|---|---|---|---|
| `-1` (port default, nothing writes it) | none | 84–85 °C | 2.55–3.19 GHz, mostly ~2.75 | 31→34 °C |
| `10` (benchmark/no-limits, LineageOS value) | none | 84–85 °C | similar, dips to 1.4–1.9 GHz late (warm start) | 32→34 °C |

`mi_thermald` never lowered a frequency cap; the prime core is held at ~85 °C by the SoC's own
limiter below cpufreq. Changing the profile or stopping `mi_thermald` gives no CPU gain. LineageOS
(sm8250-common parts) writes per-app profiles to `/sys/class/thermal/thermal_message/sconfig`:
0 default, 8 dialer, 9 gaming, 10 benchmark, 11 browser, 12 camera, 14 streaming. The thermal
configs in `/vendor/etc/thermal-*.conf` are encrypted. GPU load was not tested.

## Touch sampling rate (tested 2026-10-21)

Finger input is `event8` (`NVTCapacitiveTouchScreen`); `event0` (`xiaomi-touch`) is only the
control device. Measured from raw `getevent -t` SYN_REPORT timestamps while circling a finger,
display at 120 Hz: **120 Hz** (8.31 ms), unchanged with the Novatek firmware game mode on
(`xiaomi-touch` mode 0 → register `0x7A`, set with `module/tools/mitouch`). User observations with a
sampling app: 60 Hz display → 120, 90 → 180, 120 → 120, 144 → 144; the same on HyperOS with Game
Turbo. The NT36xxx is a TDDI controller that scans in sync with the panel (2× per frame at 60/90 Hz,
1× at 120/144 Hz). The driver (LineageOS `nt36523/nt36xxx.c`) has no report-rate control; mode 9
`Touch_Report_Rate` is never sent to the firmware. 240 Hz finger sampling is not reachable from
software; the highest finger rate is 180 Hz at a 90 Hz refresh. Pen measured the same way
(`event9` `NVTCapacitivePen`, 20 s, display 120 Hz): **240 Hz** (4.17 ms, 4800 reports), i.e. two
pen reports per frame. The active pen signal is sensed separately from the finger
(mutual-capacitance) scan, so this does not show that finger scanning could go faster.
`event11` (`Xiaomi Smart Pen`) carried no events while drawing.

## Alternative kernel (E404R, received 2026-10-21, not flashed)

`kernel/RE404-MI_PAD6-BPF-261010-1613-fix.zip` (+ `KowSU_v3.2.5…apk` manager): AnyKernel3, Linux
`4.19.404R` (Project113, Neutron Clang 24, 2026-10-10), "PIPA touch/display fix v3". It flashes the
kernel into `boot`, the dtb into `vendor_boot`, **and replaces `dtbo`**. Compared with the port
kernel (`4.19.325-cip136-st20-N0-kernel++`, built 2026-10-17 for this port):

- root: KernelSU built in, managed by **KowSU** instead of the current KSU 4.2.0 manager;
- **no susfs** (port kernel: 82 susfs strings, E404R: 0). `pipa_core/post-fs-data.sh` uses
  `ksud susfs` (avc-log spoofing, `hide-sus-mnts`, hide `/data/adb`); root hiding would be lost;
- no `xiaomi_touch` strings (port kernel has them; pen/touch-mode path may differ), far fewer
  zstd strings, no WALT string;
- no hybridswap either, so no memory win from that side.

Restore path verified: `boot_b`, `vendor_boot_b`, `dtbo_b` on the tablet are byte-identical to the
port's `firmware/boot.img` (`bbd8c682…`), `vendor_boot.img` (`0afd42d0…`), `dtbo.img` (`c15d9d5d…`).

---

## Open items

1. **Idle current after the fixes — measured 2026-10-21 (module v0.5):** batterystats history,
   screen off 18:27:40 → 20:57:50 (2 h 30 min), charge counter 6989 → 6883 mAh = **106 mAh ≈
   42 mAh/h ≈ 0.5 %/h** (baseline 53.4 mAh/h, −21 %). Software side is quiet: 46 s CPU uptime in
   2 h 33 min of deep doze, wakeups only `pm8xxx_rtc_alarm` (28×, ~every 5 min, ~1 s each),
   `msoc-delta` (2×), one aborted suspend. The remaining draw happens while the AP is suspended,
   so it is a hardware/rail floor, not a daemon. It can't be broken down further on this kernel
   (no debugfs/RPMh stats; batterystats `vmin`/`vlow` counters read 0). Next step would be a kernel
   with `qcom_stats`/rpmh_stats to see whether the SoC reaches AOSD/CXSD.
2. **Keyboard attach path on real hardware** — confirm `Xiaomi Keyboard` appears and the guard starts
   the daemon; confirm the daemon's hard-coded `event12` actually matches the attached keyboard (if
   not, the daemon is broken for everyone and should be patched, not just gated). Note: the daemon is
   the LineageOS/PixelOS-tree `xiaomi-keyboard` (byte-identical to PixelOS); stock HyperOS doesn't ship
   it and uses `vendor.xiaomi.hardware.keyboardnanoapp@1.0` instead.
3. **Face enrollment** — start the HAL, enroll a face, reboot, unlock; watchdog restarts should be
   transparent. Then fix `crop_eyes` upstream.
4. **Charging UI** — implement the legacy interface the ColorOS battery service calls; verify
   `Charger voltage` is non-zero.
5. **Debloat** — build a safe disable list for the 176 OPPO-family packages and measure the memory /
   idle effect.
6. **Thermal mapping** — verify `/vendor/etc/thermal-*.conf` against pipa's thermal zones.

---

### Handoff (2026-10-21, after module v0.2)

> (historical, v0.2; superseded by v0.9. Item 1 below was fixed by module v0.3/v0.5, see
> `module/README.md` §12. Current status: `MAINTAINER-STATUS.md`; open items: `HANDOFF.md`
> "Not fixed / open".)

Status: module v0.2 is installed and verified. The developer write-up is
`module/README.md`, zip `pipa-cos17-power-tune-v0.2.zip`. Done and confirmed by the user: idle loops
(keyboard / AOD / face / legacy app), Natural colour = HyperOS `miLut_2`, HyperOS-style brightness
slider, ~1 nit minimum, auto-brightness, colour-mode restore. Next:

1. **Eye comfort / bedtime tint and adaptive colour don't work.** Missing OPPO
   `IDisplayPanelFeature` HAL, and ColorOS wants CCT sensor type 33171001. Evidence and fix ideas are
   in `module/README.md` §11.
2. **One-day battery test** with the module. Reset with `dumpsys batterystats --reset`, unplug,
   then compare against the 53.4 mAh/h deep-idle baseline (§5 above).
3. **Keyboard case test:** v0.2 `event12` link and fold-back disable (Open item 2).
4. Charger info path and the face crash need `pipa_core` / ROM fixes (`module/README.md` §8–9).

## Reproduce

```sh
ADB="adb -s 192.168.0.37:5555"          # or USB serial 83836a90

# sensor/keyboard loop
$ADB shell dumpsys sensorservice | grep -E "0x0000002b|Previous Registrations" | head
$ADB shell "su -c 'top -b -n 2 -d 4 -m 12'"

# face HAL state + retry loop
$ADB shell "su -c 'getprop init.svc.vendor.facehal; service list | grep IFace/default'"
$ADB shell 'logcat -d -v time | grep -c ctl.interface_start'

# AOD daemon
$ADB shell "su -c 'pgrep -af AodBacklightDaemon; cat /sys/class/backlight/4-0011/brightness; settings get secure Setting_AodSwitchEnable'"

# legacy face app
$ADB shell "su -c 'ls -l /data/system/facehal_socket; logcat -d -v brief | grep -c FaceUnlockService'"

# charging HAL errors
$ADB shell "su -c 'logcat -d -v time | grep getDataFromHalByOldInterface | wc -l; dumpsys battery'"

# image inspection (host)
cd work/parts
dump.erofs --cat --path=/system/build.prop system_b.img | grep -E 'tablet_type|characteristics|model'
dump.erofs --cat --path=/etc/init/android.hardware.biometrics.face-service.facehal.rc vendor_b.img
```

Useful device files:

- `/data/local/tmp/pipa_power_tune.log` — companion guard log
- `/data/local/tmp/facehal.log` — HAL stdout
- `/data/local/tmp/pipa_pen.log`, `/data/local/tmp/aod_bl_daemon.log`,
  `/data/local/tmp/chargershim.log`, `/data/local/tmp/qti_radio.log` — `pipa_core` daemon logs
- `/data/adb/modules/pipa_core/` — face HAL, AOD jar, charger shim, pen scripts, `service.sh`
