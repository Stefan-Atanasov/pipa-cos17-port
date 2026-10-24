# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

> Agent-agnostic copy: **`AGENTS.md`**. Keep the two in sync when facts change.
> Start at **`MAINTAINER-STATUS.md`** (current state, build chain, next steps, doc map; the full log is `HISTORY.md`). Build/flash/rollback of ROM and kernel: **`BUILD-GUIDE.md`**. Fix index: **`HANDOFF.md`**; CCT reroute detail: **`HANDOFF-adaptive-bedtime.md`**.

## What this folder is

Not a software project and not a git repo. It is an audit workspace for the **ColorOS 17 port (beta4, 2026-10-17) on a Xiaomi Pad 6 (`pipa`)**, plus one companion KernelSU/Magisk module built during that audit. `README.md` holds the complete audit: findings ranked by idle-drain impact, evidence, what was changed live on the device, open items, and reproduce commands. Read it before doing anything here, and keep it up to date when findings change.

Layout:
- `ColorOS17 Port for pipa-beta4-20261017.7z` is the original release. Keep it; it is the source of truth.
- `ColorOS17 Port for pipa-beta4-20261017/` is the extracted release (`firmware/`, `super/super.img`, `bin/Linux` with bundled `fastboot`/`adb`/`magiskboot`, and `FlashLinux.sh`).
- `work/parts/*_b.img` comes from `lpunpack` of the unsparsed super. Only slot **B** has content; the `_a` images are empty.
- **Runtime layer (since beta5-2e it is part of the ROM, no module needed):** `port-rom/` = `pipa_port` as ROM files (`/system_ext/pipa_port`, init rc), `helper/` = the pipa helper app (persistent priv-app: Dolby, pen pill, lock-with-cover), `port-module/` = the same code as a KernelSU module (v1.3, used on 2d), `susfs-module/` = optional root-hiding module. See the "Runtime in the ROM" section.
- `module/` is the older `pipa_cos17_power_tune` module's source (v0.15, used up to beta5-2d). `module/README.md` is the developer-facing write-up of every fix (evidence, root cause, workaround, proper fix) and is still the main technical document. `module/tools/` regenerates the replaced display files, the audio volume table and the patched framework jar from a ROM's own `oplus-services.jar` (the ROM build bakes their output). Current zips next to it: `pipa-port-v1.3.zip`, `pipa-susfs-v1.0.zip`, `pipa-cos17-power-tune-v0.15.zip`, `pipa_core-v1.10.zip` (the original developer's, keep) and `-v1.12.zip`, `pipa-perf-test-v0.1.zip`; older ones are in `archive/module-zips/`.

## Device access

```sh
ADB="adb -s 192.168.0.37:5555"     # TCP, already enabled; USB serial is 83836a90
$ADB shell "su -c '<cmd>'"         # root via KernelSU 4.2.0
```

The build/check scripts default to the TCP serial; after a flash or reboot TCP ADB is usually off, so run them with `ADB="adb -s 83836a90"` over USB. Since beta5, ADB is authenticated (`ro.adb.secure=1`); this PC's key is already trusted. The tablet has a lock-screen PIN (the user gives it when needed; never store it). After a reboot, unlock once so apps run normally.

The device is the user's real tablet. Ask before you flash, wipe, `pm uninstall`, or make persistent changes. Live-only changes (kill/SIGSTOP, `setprop ctl.*`) reset on reboot. Record anything you change in the README's "What was changed on the device" table.

## Inspecting images

`system_b.img`/`vendor_b.img` etc. are **EROFS**, not ext4, so `debugfs`/`mount -t ext4` will not work. Use:

```sh
dump.erofs --ls --path=/etc/init work/parts/vendor_b.img
dump.erofs --cat --path=/system/build.prop work/parts/system_b.img
fsck.erofs --extract=<dir> work/parts/vendor_b.img
```

Disk space: ~140 GB free on `/home` after moving the bulky data to the HDD (2026-10-22).

**Storage (since 2026-10-22):** bulky read-mostly data lives on the 1 TB HDD `/mnt/reference` (ext4, fstab by UUID with `nofail`) and is reached through symlinks, so every path in the docs still works: `../reference`, `../donor`, `../Pixelos`, both iqraOS folders, `../New Folder`, `COS17/work`, the extracted beta4 release folder, and `../port-work/roundtrip/img`. If the HDD is not mounted those paths break (builds need `work/parts` and `donor/`); check `mountpoint /mnt/reference` first. `port-work/` (build trees, images) stays on the NVMe for speed and btrfs reflinks. Build inputs are back on the SSD for speed (2026-10-22 18:12, checksum-verified; the HDD keeps a second copy): `COS17/work/parts/` and `donor/OPD2515_11.C.06/{img/,*.zip}` are real SSD folders; the rest of `work/` and `donor/` entries are symlinks to the HDD. The drive's head parking is handled by `69-hdparm.rules` (`hdparm -B 254 -S 0`).

Everything is already extracted under `../reference/<rom>/<partition>/`. Diff these instead of re-extracting:
- `hyperos1-stock/` (HyperOS `OS1.0.15.0.UMZMIXM`, from the fastboot images in `../New Folder/`),
- `iqraos3.1/` and `iqraos_v1.0/` (HyperOS-based ports),
- `pixelos/` (PixelOS 17),
- `cos17/` (this port),
- `device/pipa_core/` (`pipa_core` copied off the tablet),
- `analysis/` (dex and disassembly work).

Each ROM folder has `img/` with its raw partition images. Dex analysis works with androguard in `maintainer/jar-edits/venv` (184 MB, regenerable; no Java on the host). `work/super_raw.img` and the duplicate `super.img` in the extracted release can be deleted. Check with the user first.

## Maintainership (from 2026-10-22)

The original port developer (梦归zzz) has stopped updating the port; the user (stefan) now maintains it.
- **Start at `MAINTAINER-STATUS.md`**: roadmap, artifacts on disk, session plan, script index and the doc map.
- Rebase procedure: `PORT-MAINTAINER.md`; what the port changed: `PATCH-INVENTORY.md`; ROM-side fix design: `PHASE2-ROM-INTEGRATION.md`; stability/perf plan: `STABILITY-PERF.md`; draft release notes: `RELEASE-NOTES-beta5.md`.
- Scripts live in `maintainer/` (build, `device_check.sh`, `device_capture.sh`, `port_diff.py`, ...); `perf-test-module/` builds `pipa-perf-test-v0.1.zip`. `pipa_core-v1.10.zip` is the saved `pipa_core` copy.
- Only the OS side (system + folded `my_*`, system_ext, product) comes from the donor; vendor, odm and firmware carry over unchanged.

## Runtime in the ROM (beta5-2e+)

- `port-rom/pipa_port/` → `/system_ext/pipa_port/` (read-only; `service.sh`, `early.sh`, `pen_keys.sh`, `config.prop`, face HAL, charger shim, `xiaomi_touch_ioctl`) and `port-rom/pipa_port.rc` → `/system_ext/etc/init/pipa_port.rc` (services `pipa_port`, `pipa_subsys0/1`, all `seclabel u:r:pipa_port:s0`). Changing any of it = edit `port-rom/`, add a `build_beta5_<next>.sh` layer (see `build_beta5_2g.sh`: it only swaps files in the previous tree) and flash. State lives in `/data/misc/pipa_port`; log `/data/local/tmp/pipa_port.log`; user overrides in `/data/misc/pipa_port/config.prop`.
- The `pipa_port` SELinux domain is declared in `system_ext_sepolicy.cil` (+ `_debug.cil`) by `build_beta5_2e.sh` and is **permissive** until its rules are collected with `maintainer/avc_trace.sh`. Test-compile any policy change on the tablet before building: `/system/bin/secilc` with the 8 inputs (plat cil, mapping + compat, system_ext cil + mapping, product, vendor `plat_pub_versioned` + `vendor_sepolicy`, odm) exits non-zero on an error.
- Pen buttons and `stylus_buttons_enabled`: the front button (`STYLUS_BUTTON_PRIMARY`) is merged into the pen events by Android; the back button (`KEY_PAGEUP`) is read by `pen_keys.sh` and injected as key 120 (screenshot) via `input`. See the gotcha about `cmd` tools and file descriptors below.
- **Live-testing a script that is in the ROM:** bind-mount a copy over it (`mount --bind /data/local/tmp/x.sh /system_ext/pipa_port/x.sh`, gone at reboot). `sed -i` creates a **new inode**, and the bind keeps pointing at the old (deleted) file; edit in place (`cat new > old`) or `umount -l` and bind again. Kill a service child by pid file, never with `pgrep -f <path>` inside `su -c` (the pattern matches your own command line and kills your shell).
- The helper (`helper/`): `sh helper/build.sh` (aapt2 + javac + d8 + zipalign + apksigner, JDK 21, `~/Android/Sdk` build-tools 37 + platform 37.0; no Gradle). A persistent app **cannot be updated with `adb install`**; test a new version with `pm uninstall` + install as a normal app, or flash the ROM layer. Keep `helper/keys/pipa-helper.jks`: ROM and updates must share the key. Hidden-API access for system apps: a `hidden-api-whitelisted-app` sysconfig entry.

## Older module (`pipa_cos17_power_tune`, up to beta5-2d; reference only)

Since beta5-2e the ROM does all of this; the notes below describe the module-era design and still explain the reasons behind the ROM code (keyboard gating, AOD, face watchdog, pen).

Edit `module/`, bump `version`/`versionCode` in `module.prop`, and zip the contents at the archive root (no top-level folder). There's no `zip` binary on the host, so use Python's `zipfile`. Install with:

```sh
$ADB push <zip> /data/local/tmp/ && $ADB shell "su -c 'ksud module install /data/local/tmp/<zip>'"
```

KSU stages it in `/data/adb/modules_update/` and applies it on reboot. The runtime copy does not include `customize.sh`/`README.md`; that is expected.

**This KernelSU build has no module mount provider** (`ksud module list` shows `"mount": "false"`). `post-fs-data.sh` therefore bind-mounts the module's `vendor/` and `system_ext/` files itself (KSU moves `system/vendor` etc. to the module root on install). The framework jar lives in `framework/<md5 of the ROM jar>.jar` at the module root and only the one matching the running ROM jar is bound. The binds are hidden from `/proc/*/mounts` by `pipa_core`'s susfs `hide-sus-mnts`, so verify with `md5sum` instead. Display files are read only at boot (composer, `system_server`): any change to them needs a **reboot, and tell the user before you reboot**.

How `service.sh` works: a single long-running guard (pidfile singleton at `/data/local/tmp/pipa_power_tune.pid`). It exits unless `ro.product.device=pipa`, waits for `sys.boot_completed`, then sleeps 20 s so `pipa_core` can start its daemons first. After that it loops every `POLL` (5 s) and checks AOD/face/colour mode every 3rd tick. Each feature is a flag in `config.prop` (`KEYBOARD_GUARD`, `KB_EVENT_LINK`, `AOD_GATE`, `FACE_WATCHDOG`, `LEGACY_FACE_APP`, `COLOR_MODE_RESTORE`, `ADAPTIVE_RESTORE`, `FRAMEWORK_SENSOR_REROUTE`, `FRAMEWORK_ALLOW_ODEX`; see `module/config.prop`). Log: `/data/local/tmp/pipa_power_tune.log`, trimmed at 256 KB.

Design constraints, all deliberate. Keep them:
- **Non-destructive only.** The module works alongside `pipa_core` (`/data/adb/modules/pipa_core/`, by the port author) and never patches it. On 2026-10-22 the original developer said patching or merging `pipa_core` is fine; a merged single module is a planned later step, so until then keep the two separate.
- `xiaomi-keyboard` is gated with `setprop ctl.start|stop` and runs only while the input device name `Xiaomi Keyboard` / `Xiaomi Consumer Control` / `Xiaomi Touchpad` is present. Never remove it unconditionally. Pen devices and `xiaomi keyboard WakeUp` must not count as a keyboard.
- `AodBacklightDaemon` is **frozen with SIGSTOP/SIGCONT, not killed**, because `pipa_core`'s `run_aod` loop respawns it 5 s after it exits.
- The face HAL watchdog starts the HAL only when neither init nor `pipa_core` has one running. It must use the same binary path, `LD_LIBRARY_PATH` and OpenCL loader as `pipa_core/service.sh`.
- `com.pipa.faceunlock` is disabled only while `/data/system/facehal_socket` is absent, and re-enabled otherwise.
- `uninstall.sh` must undo every runtime effect.

The keyboard attach path has not been tested on real hardware (README, open item 2).

How `xiaomi-keyboard` actually behaves (from disassembly; stock HyperOS doesn't ship it and instead uses the event-driven `vendor.xiaomi.hardware.keyboardnanoapp@1.0-service` on `/dev/nanodev0`):
- All I/O goes through `/dev/nanodev0`. `/dev/input/event12` is only checked with `access()` as a "keyboard present" flag and never opened.
- Each loop iteration: if `event12` is absent **and** the keyboard state is already 1, it sleeps 3 s. Otherwise it enables the accelerometer, waits 150 ms, reads, and disables it again. That is the ~6.7 Hz loop when no keyboard is attached, because the state stays 0.
- The tilt angle maps to on/off (40°–230° → 1), and changes are written to `nanodev0` as `32 ff <state>`. This is the auto-disable when the keyboard is folded behind the pad.
- On pipa, `event0`–`event10` are already taken, so an attached keyboard likely won't be `event12`. v0.2 symlinks `/dev/input/event12` to the keyboard's real node while it is attached (untested with a real case).

## Display (details in `module/README.md` §6–7 and §12)

- **Colour:** QDCM modes ship PCC/gamut disabled; the module enables PCC in `standard` (Natural) and `hal_srgb` with HyperOS `miLut_2` (`module/tools/patch_qdcm.py`). Vivid stays native.
- **Brightness:** ColorOS `<level>P,B,N,K</level>` table generated by `module/tools/gen_brightness_table.py`; levels <= AOD_BRIGHTNESS go raw (level 1 = black), so keep min >= 20.
- Don't drive the QS brightness slider with downward swipes: they close Quick Settings. Use `settings put system screen_brightness <level>` (manual mode) for measurements, and restore auto mode afterwards.

## Adaptive colour / Bedtime (details in `module/README.md` §12, offsets in `HANDOFF-adaptive-bedtime.md`)

- The framework asks for OPPO CCT sensor type 33171001; pipa exposes Xiaomi type **33171088**. `module/framework/<base-md5>.jar` (one per ROM build: beta4 `3316594f…` → `00b9218b…`, C.06 `2175feb9…` → `8810ad00…`; `framework/aliases` maps the rebuilt beta5 jar `7afeadb1…` to the C.06 one) is the ROM's `oplus-services.jar` with four dex edits (three for the reroute, one for the IEngineer boot hang), regenerated by `module/tools/patch_framework.sh` (pattern-based; verified on beta4 and C.06; for a new build run it on that build's own jar).
- A diff against C.06 found no port-author code edit (`maintainer/jar-edits/REPORT.md`); the port's repack (`PATCH-INVENTORY.md` S17) is the only difference.
- `post-fs-data.sh` binds only the jar named after the running ROM jar's md5 (after `chcon` to `system_file`), and skips the bind if a prebuilt `oat/arm64/oplus-services.odex` exists unless `FRAMEWORK_ALLOW_ODEX=1`. `FRAMEWORK_SENSOR_REROUTE=0` disables it. C.06 stock ships an odex; beta5 removes it.
- The patched `oplus-services.jar` is baked into the ROM since `beta5-baked` (module v0.10+ also carried it, harmless no-op on baked ROMs). Since v0.10 the module also carried the C.06 boot fixes (IEngineer jar edit, beta4 `libupdateprof.qti.so`/`libtrigger-handler.so`); those are in the ROM too, so v0.9 and older only matter for rollbacks to old images (v0.7 and older bind the beta4 jar on C.06: likely bootloop).
- The Eye Protect app resets the settings at boot; `service.sh` saves/restores them (`adaptive_state`, `bedtime_state`). The 100 lx is a workaround; real ALS lux is not bridged.
- Do not kill `system_server` to apply framework changes: it triggers `sysrq_trigwarmd_crash`; reboot instead.

## USB audio and speakers (v0.6/v0.7, details in `module/README.md` §13-14)

The module ships USB_HEADSET/A2DP volume curves (`module/tools/patch_audio_volumes.py`) so USB DACs no longer play at full scale, and a patched 32-bit audio HAL (`module/tools/patch_audio_hal.py`) that fixes swapped speaker L/R. The audio policy can be re-read by restarting `audioserver` (safe, unlike `system_server`). A2DP curves are untested with a non-absolute-volume BT headset.

## Flashing

`FlashLinux.sh` uses the bundled `bin/Linux/fastboot`, sets the active slot to **B**, flashes the firmware plus `super.img`, and optionally wipes userdata/metadata (interactive prompt). Only the user runs it. Never run it on your own.

`maintainer/flash_super.sh [-y] <name>` (names = the `case` list in the script, newest `beta5-2n`; regenerate deleted ones with `build_port.sh`) (layered builds: `build_beta5_baked.sh` → `_1c` → `_2a` → … → `_2n`, each `sudo`; recipe in `BUILD-GUIDE.md`); all steps in one go or for a new donor: `sudo sh maintainer/build_port.sh <tag> <donor-img-dir>` (every step script honours `TAG` and `DONOR_IMG`) flashes **only `super`** to slot B (md5 check first, no firmware, no wipe; `-y` is needed when run without a terminal). The user may run it or explicitly ask you to. After a flash, `/data` is mounted with f2fs `checkpoint=disable` until a boot completes: in a bootloop every write to `/data` (including `/data/adb`) is rolled back at the next reboot. `vdc checkpoint commitChanges` keeps them. The bundled `bin/Linux/fastboot` lost its exec bit when unpacked; use the system `fastboot`.

## Known port gotchas

- **C.06 boot hangs (fixed in the rebuilt beta5 images and module v0.10).** C.06 waits forever for HALs pipa lacks: `OplusEngineerFwService.getEngineerService()` calls `waitForService(IEngineer)` unless `isRootVersion()` (= `!ro.adb.secure`), and `system_ext/{lib,lib64}/libupdateprof.qti.so` / `libtrigger-handler.so` switched `checkService` -> `waitForService` (QSPM). Each hangs system_server until its watchdog panics the device. Fixes: `patch_framework.sh` edit 4, and the four beta4 libs carried via `PORT-EDITS.tsv`. On a new donor, scan changed libs for new `waitForService` imports before flashing. Diagnose a bootloop from `/data/anr/traces_SystemServer_WDT*` (ADB with root works during the loop) and `/sys/fs/pstore/dmesg-ramoops-0`.

- **Software update shows a false "storage space is less than 262.30 MB" dialog.** The OTA app
  (`com.oplus.ota`) checks free space on its download directory `/data/ota_package/OTA`. If that
  directory is missing, `StatFs` throws and the app treats free space as **0**, even though `/data`
  has ~90 GB free. The `262.30 MB` in the message is the update package size
  (`shelf_pkg_total_size=275043374` bytes), not a threshold. Fix (done on 2026-10-21):
  ```sh
  mkdir -p /data/ota_package/OTA
  chown system:cache /data/ota_package/OTA
  chmod 0770 /data/ota_package/OTA
  restorecon /data/ota_package/OTA
  ```
  It persists across reboots but not across a data wipe. Full analysis: README finding #11.

- **Do not install the offered OTA.** It is a 262.30 MB **SOTA app bundle for donor model OPD2515**,
  not pipa (Phone Manager, OSee, Content Portal, remotecontrol, encryption, … — 15 OPPO apps).
  Installing it can overwrite port-patched system apps. The rebuilt beta5 images remove the updater
  (`com.oplus.ota`, `com.oplus.sau`, `com.oplus.sauhelper`; Settings then hides the entry, tested). Keep
  `com.oplus.romupdate`: it fetches OPPO feature configs, not updates.

- **SELinux denials never reach dmesg/logcat**: the kernel has no audit core (stale `/proc/config.gz`). Use `maintainer/avc_trace.sh start`, use the feature, then `avc_trace.sh dump <label>` (kprobes, live only). Only servicemanager's own `find`/`add` denials appear in logcat (tag `auditd`, pid of servicemanager).

- Read the README's "What was changed on the device during the audit" table before making live
  changes, so you do not undo another session's fixes (keyboard daemon stopped, AOD frozen, face HAL
  running, legacy face app disabled).

- **Services in the `pipa_port` domain (beta5-2e+): never let `cmd`-based tools (`input`, `am`, `settings`, `pm`, `cmd`) inherit a pipe or a file of your own as stdin/stdout/stderr.** They hand those fds to system_server over binder; if system_server may not use the fd's label the call fails with `Failed transaction (2147483646)` and nothing is logged (dontaudit). Redirect all three to `/dev/null`. The old module ran in the unconfined `ksu` domain and never hit this. SELinux trace: `maintainer/avc_trace.sh`.

- **Never replace `/data/adb/ksud` (no wrapper, no switch).** On 2026-10-23 a compiled switch there made the joeyzhu kernel hang on the Mi logo. Update ksud only together with a matching kernel, through the SukiSU manager. **Rescue when the tablet does not boot:** the boot image contains TWRP 3.7.1 (Power + Volume up, or it starts by itself after failed boots); TWRP adb is root and `/data` is decrypted. Partition backups: `maintainer/kernel/flash_kernel.sh restore`.

- **Previous own kernel (boot_b 2026-10-23 until 21:40, now the rollback: E404 r2 + SukiSU builtin + susfs 2.3.0)**: **Since 18:16 r2b** (+ `uclamp_boost.c` touch boost, boot header cmdline `ramoops_memreserve=4M` = pstore; E404 has no built-in ramoops cmdline). Test with **trimmed** images (header+kernel+ramdisk; a full 196 MB `fastboot boot` hung the bootloader twice). Measure smoothness with `KTAP=1 maintainer/stress_switch.sh`: `input tap` bypasses kernel input handlers, so in-kernel touch boosts look useless with it. ColorOS boosts through the QTI perf HAL (WALT `sched_boost`), not the power HAL (it gets no hints). `kernel/KERNEL-RESEARCH.md` (status, evidence). Rebuild for a new E404/SukiSU commit: `maintainer/kernel/prepare_tree.sh <dir> [E404_REF] [SUKISU_REF]`, `build_kernel.sh`, **pack only with `mkboot.sh`** (`magiskboot unpack -h`/`repack` corrupts the boot header patch level and the bootloader then refuses the kernel silently: black screen, no log), test with `flash_kernel.sh test` (`fastboot boot`, nothing written), `flash_kernel.sh flash|restore`. After a SukiSU update re-check every hook `extern` type and that `susfs_set_batch_sid()` runs on 4.19. Root for `adb shell su` needs Shell granted in the SukiSU manager (release build, not DEBUG).

- **Own WALT kernel (on boot_b since 2026-10-23 21:40; now `walt-r5` since 2026-10-24 14:25 = walt-r3 (SurfaceFlinger on the top GPU ringbuffer) + r4 (SF RenderEngine off the little cores, `is_sf()`) + r5 (sysctl `kernel.ux_prefer_big`=1: heavy UX threads on the big cluster without the slide scene; `kernel.frame_rate` default 120); rollbacks `boot-walt-r4.img`, `boot-walt-r3.img`, E404 r2b):** Lineage 24 core + liyafe's pipa drivers +
  E404's display/touch + SukiSU/susfs, branch `own` in `port-work/kernel/walt-own` (OPPO UI First on branch `oppo`,
  worktree `walt-oppo`). Recipe, rebuild from scratch (`maintainer/kernel/prepare_tree_walt.sh`, our commits are in
  `kernel/walt-own.bundle`; save it with `--save` after committing), checks and updating: **`kernel/WALT-KERNEL.md`**.
  Build `maintainer/kernel/build_walt.sh` (config = Lineage fragment chain + `xiaomi/pipa-cos17.config`; `DBG=1` = boot
  watchdog + lockup panics), test only with `TRIM=1 mkboot.sh` images. Lessons: never `pkill -f build_walt.sh` from a
  command that contains that string (kills itself); do not edit `build_walt.sh` while it runs; a 10 s power press is a
  hard reset (pstore lost), DBG builds warm-reset by themselves; E404 cannot decode the WALT kernel's pstore console
  record but `unused-ramoops-0` holds the text; A17 never mounts schedtune (cpu cgroup + uclamp is what ColorOS uses).

- **Idle drain / keyboard guard (2026-10-24):** the nanosic driver creates its virtual "Xiaomi Keyboard" input devices whether or not a keyboard is attached, so an input-name check always says "attached". pipa_port (`KEYBOARD_GUARD`, beta5-2j) asks the MCU instead (`echo 1 > /sys/devices/virtual/nanodev/nanodev0/_version176x`, `Connected=[1]`) and runs `xiaomi-keyboard` only then; without it the daemon's accelerometer loop keeps the SLPI awake and the SoC never power-collapses. Idle checks: `dumpsys batterystats` (wakelocks, wakeup reasons), `/sys/power/system_sleep/stats` (aosd/cxsd counts), `/sys/power/rpmh_stats/master_stats` (per-subsystem sleep, 19.2 MHz ticks).
- **Sharing (2026-10-24):** kernel source = GitHub `kernel_xiaomi_pipa_cos17` (branch `oppo`; publish by cherry-picking onto `pub/oppo` in `port-work/kernel/walt-own`, then `git push origin pub/oppo:oppo`); port scripts/docs = GitHub `pipa-cos17-port` via `sh maintainer/sync_port_repo.sh "msg"` (no proprietary blobs, no signing key; fails closed); private co-maintainer kit = `maintainer/make_port_kit.sh`; user package = `maintainer/build_release.sh`. The helper keystore password is in `helper/keys/keystore.pass` (never commit or share `helper/keys/`). Scripts take `PIPA_ROOT`/`PIPA_OWNER`.
- **Smoothness fixes in the ROM (2l) and how to measure:** SurfaceFlinger props must go into `product/etc/build.prop`: pipa's vendor build.prop sets HyperOS SF values (`-4 ms` offsets, `predict_hwc_composition_strategy=0`) and loads after system/system_ext. The UI First kernel keeps SurfaceFlinger off the little cores only while a sched_assist scene is set, and on pipa nothing sets it (OPPO's vendor daemon does), so pipa_port `SF_BIG_CORES` writes `echo 384 > /proc/sys/kernel/sched_assist_scene` (bit 7 = SA_SCENE_OPT_SET; without it a write clears bits). Duration-model SF timing (`use_phase_offsets_as_durations=1`) aborts SurfaceFlinger while any `*phase_offset_ns` prop exists (boot hangs). Measure visible stutter with `maintainer/perfetto/traced_heavy.sh <label>` (FrameTimeline: SF on time, dropped, stuffing), not gfxinfo alone; wait 60 s after unlock; judge on >= 2 runs.
- **Smoothness testing (since 2026-10-23 night):** `maintainer/heavy_mix.sh` (clean start, real touch via `maintainer/kgest`, Spotify live alert, apps + flings, shade/QS, pill, drawer, fast bursts; run twice, spread ±3 %). Perfetto works since beta5-2j (2i and older: the donor's `traced.relay_producer_port=vsock://...` killed `traced`, our kernel has no vsock): `setprop persist.traced.enable 1` before tracing and back to 0 afterwards. atrace/tracefs also work; atrace's "runnable" totals are inflated by its overhead, use the raw tracefs script `maintainer/perfetto/ktrace.sh` for scheduler numbers. Analysis notes: `kernel/KERNEL-RESEARCH.md` "2026-10-23 midnight".

- Another agent (opencode) may also be attached to the tablet over wireless ADB. Check `pgrep -af opencode` and coordinate before making live changes.
