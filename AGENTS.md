# AGENTS.md

Guidance for an AI coding agent working in this workspace. It is not a software
repository and not a git repo. It is an audit/maintenance workspace for the
**ColorOS 17 port on a Xiaomi Pad 6 (`pipa`)**. Since beta5-2e the runtime fixes are part of
the ROM (see "Runtime in the ROM"); the KernelSU modules built earlier are reference or optional.

If you are Claude Code, `CLAUDE.md` is the same material with Claude-specific
wording. Keep the two in sync when facts change. Doc map (every doc, purpose,
audience): `MAINTAINER-STATUS.md` "Doc map" (current state, build chain, next steps; full log: `HISTORY.md`).

## Read first

1. `MAINTAINER-STATUS.md` — roadmap, build decisions, artifacts on disk, session
   plan, doc map. Start here.
2. `HANDOFF.md` — short index of the fixes and where the detail lives.
3. `README.md` — full device audit, findings ranked by idle-drain impact,
   evidence, what was changed live, reproduce commands.
4. `module/README.md` — per-fix developer write-up (evidence → root cause →
   workaround → proper fix). This is the main technical document.
5. `HANDOFF-adaptive-bedtime.md` — the CCT-sensor reroute for Adaptive colour /
   Bedtime mode, including exact beta4 dex offsets and limitations.

For rebasing onto a new donor build see `PORT-MAINTAINER.md` and
`PATCH-INVENTORY.md`.

## Layout

- `ColorOS17 Port for pipa-beta4-20261017.7z` — original release. Keep it; it is
  the source of truth.
- `ColorOS17 Port for pipa-beta4-20261017/` — extracted release (`firmware/`,
  `super/super.img`, `bin/Linux` with bundled `fastboot`/`adb`/`magiskboot`,
  `FlashLinux.sh`).
- `work/parts/*_b.img` — `lpunpack` output. Only slot **B** has content; `_a`
  images are empty.
- `helper/` — pipa helper app (persistent system app since beta5-2d: Dolby keeper B10, pen pill B3; `sh helper/build.sh`, JDK 21 + `~/Android/Sdk`).
- `port-rom/` — `pipa_port` as ROM files (`/system_ext/pipa_port`, init rc); `port-module/` — the same as a KernelSU module (v1.3, used on 2d); `susfs-module/` — optional root-hiding module.
- `module/` — older `pipa_cos17_power_tune` module source (v0.15, used up to beta5-2d; its `README.md` and `tools/` remain the main technical reference):
  - `module.prop`, `config.prop`, `post-fs-data.sh`, `service.sh`,
    `customize.sh`, `uninstall.sh`, `README.md`
  - `system/vendor/etc/qdcm_calib_data_xiaomi_m82_*.xml` — colour fix
  - `system/system_ext/etc/display_brightness_config_default.xml` — brightness
  - `system/vendor/etc/audio_policy_volumes.xml` — USB/A2DP volume curves
  - `framework/<base-md5>.jar` — adaptive/bedtime sensor reroute, one patched
    jar per ROM build (beta4 `3316594f…`, C.06 `2175feb9…`; see below);
    `framework/aliases` maps other ROM jars to one of them
  - `system/system_ext/{lib,lib64}/` — beta4 `libupdateprof.qti.so` and
    `libtrigger-handler.so` (C.06 boot-hang fix; no-op where identical)
  - `tools/` — regenerate the replaced files (`patch_qdcm.py`,
    `gen_brightness_table.py`, `patch_framework.sh`, `patch_audio_volumes.py`)
- Current zips: `pipa-port-v1.3.zip`, `pipa-susfs-v1.0.zip`, `pipa-cos17-power-tune-v0.15.zip`,
  `pipa_core-v1.10.zip` (the original developer's, keep) and `-v1.12.zip`; older ones are in
  `archive/module-zips/`. `pipa-perf-test-v0.1.zip` is the separate A/B test
  module. Older zips are predecessors (listed in the `MAINTAINER-STATUS.md` doc
  map). `pipa_core-v1.10.zip` is the saved `pipa_core` copy.
- `HANDOFF.md`, `HANDOFF-adaptive-bedtime.md`, `README.md`, `CLAUDE.md`,
  `AGENTS.md`. Superseded notes are in `archive/`.

## Device access

```sh
ADB="adb -s 192.168.0.37:5555"     # TCP; USB serial is 83836a90
$ADB shell "su -c '<cmd>'"         # root via KernelSU 4.2.0
```

The device is the user's real tablet. **Ask before** flashing, wiping,
`pm uninstall`, or making persistent changes. Live-only changes (kill/SIGSTOP,
`setprop ctl.*`) reset on reboot. Record live changes in `README.md`'s "What was
changed on the device" table.

Display and framework files are read only at boot, so changes need a reboot: **tell the user before you reboot**.

**Do not `kill -9 system_server` on this device.** It triggers
`sysrq_trigwarmd_crash` (kernel panic / warm reset) instead of a soft framework
restart. Use a module install + reboot for framework changes.

Another agent may be attached over wireless ADB. Check `pgrep -af opencode` and
coordinate before live changes.

The build/check scripts default to the TCP serial; after a flash or reboot TCP ADB is
usually off, so run them with `ADB="adb -s 83836a90"` over USB. Since beta5, ADB is
authenticated (`ro.adb.secure=1`); this PC's key is already trusted. The tablet has a
lock-screen PIN (the user gives it when needed; never store it); unlock once after a reboot.

## Storage

Since 2026-10-22: bulky read-mostly data lives on the 1 TB HDD `/mnt/reference` (ext4, fstab by UUID with `nofail`) and is reached through symlinks, so every path in the docs still works: `../reference`, `../donor`, `../Pixelos`, both iqraOS folders, `../New Folder`, `COS17/work`, the extracted beta4 release folder, and `../port-work/roundtrip/img`. If the HDD is not mounted those paths break (builds need `work/parts` and `donor/`); check `mountpoint /mnt/reference` first. `port-work/` (build trees, images) stays on the NVMe for speed and btrfs reflinks. Build inputs are back on the SSD for speed (2026-10-22 18:12, checksum-verified; the HDD keeps a second copy): `COS17/work/parts/` and `donor/OPD2515_11.C.06/{img/,*.zip}` are real SSD folders; the rest of `work/` and `donor/` entries are symlinks to the HDD. The drive's head parking is handled by `69-hdparm.rules` (`hdparm -B 254 -S 0`).

## Inspecting images

`system_b.img`/`vendor_b.img` etc. are **EROFS**, not ext4. `debugfs` and
`mount -t ext4` do not work. Use:

```sh
dump.erofs --ls --path=/etc/init work/parts/vendor_b.img
dump.erofs --cat --path=/system/build.prop work/parts/system_b.img
fsck.erofs --extract=<dir> work/parts/vendor_b.img
```

Everything is already extracted under `../reference/<rom>/<partition>/`
(`hyperos1-stock`, `iqraos3.1`, `iqraos_v1.0`, `pixelos`, `cos17`,
`device/pipa_core`, `analysis`). Diff those instead of re-extracting.

Dex analysis uses the androguard venv `maintainer/jar-edits/venv` (184 MB,
regenerable; no Java on the host). `work/super_raw.img` and the duplicate `super.img` can be
deleted with the user's approval.

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

Since beta5-2e the ROM does all of this; the notes below still explain the reasons behind the ROM code.

Build: edit `module/`, bump `version`/`versionCode` in `module.prop`, zip the
contents at the archive root (no top-level folder). There is no `zip` binary on
the host; use Python's `zipfile`. Install:

```sh
$ADB push <zip> /data/local/tmp/
$ADB shell "su -c 'ksud module install /data/local/tmp/<zip>'"
```

KernelSU stages in `/data/adb/modules_update/` and applies on reboot. The
runtime copy does not include `customize.sh`/`README.md`; that is expected.

**This KernelSU build has no module mount provider** (`ksud module list` shows
`"mount": "false"`). `post-fs-data.sh` bind-mounts the replaced files itself.
KernelSU moves `system/vendor` and `system/system_ext` to the module root on
install. The framework jar lives in `framework/<md5 of the ROM jar>.jar` at the
module root; `post-fs-data.sh` binds only the one matching the running ROM jar.
The binds are hidden from
`/proc/*/mounts` by `pipa_core`'s susfs `hide-sus-mnts`; verify with `md5sum`.

Display files and the framework jar are read only at boot (composer,
`system_server`): any change needs a **reboot, and tell the user before you
reboot**.

`service.sh` is a single long-running guard (pidfile singleton at
`/data/local/tmp/pipa_power_tune.pid`). It exits unless `ro.product.device=pipa`,
waits for `sys.boot_completed`, sleeps 20 s so `pipa_core` can start its
daemons, then loops every `POLL` (5 s). Log:
`/data/local/tmp/pipa_power_tune.log`, trimmed at 256 KB.

Flags in `config.prop`: `KEYBOARD_GUARD`, `KB_EVENT_LINK`, `AOD_GATE`,
`FACE_WATCHDOG`, `LEGACY_FACE_APP`, `COLOR_MODE_RESTORE`, `ADAPTIVE_RESTORE`,
`FRAMEWORK_SENSOR_REROUTE`, `FRAMEWORK_ALLOW_ODEX`, `POLL`.

### Design constraints (keep them)

- **Non-destructive only.** Works alongside `pipa_core` and never patches it. On 2026-10-22 the original developer said patching or merging `pipa_core` is fine; a merged single module is a planned later step, so until then keep the two separate.
- `xiaomi-keyboard` is gated with `setprop ctl.start|stop` and runs only while
  `Xiaomi Keyboard` / `Xiaomi Consumer Control` / `Xiaomi Touchpad` is present.
  Never remove it unconditionally. Pen devices and `xiaomi keyboard WakeUp` must
  not count as a keyboard.
- `AodBacklightDaemon` is **SIGSTOP/SIGCONT, not killed**, because `pipa_core`
  respawns it 5 s after exit.
- The face HAL watchdog starts the HAL only when neither init nor `pipa_core` has
  one running, with the same binary path, `LD_LIBRARY_PATH` and OpenCL loader as
  `pipa_core/service.sh`.
- `com.pipa.faceunlock` is disabled only while `/data/system/facehal_socket` is
  absent; re-enabled otherwise.
- `uninstall.sh` must undo every runtime effect.

## The framework jar reroute (v0.5, per-ROM jars since v0.9)

Adaptive colour / Bedtime need the CCT sensor: the framework asks for OPPO type
33171001, pipa exposes Xiaomi type **33171088**. `module/framework/<base-md5>.jar`
(one per ROM build: beta4 `3316594f…` → `00b9218b…`, C.06 `2175feb9…` →
`8810ad00…`) is the ROM's `oplus-services.jar` with four dex edits (sensor
type, reordered sparse-switch, fixed 100.0 lx, and the IEngineer boot-hang fix). Exact offsets (beta4 only) are in
`HANDOFF-adaptive-bedtime.md`; current behaviour is in `module/README.md` §12.

- `module/tools/patch_framework.sh` finds the edit sites by pattern (verified on
  beta4 `3316594f…` and C.06 `2175feb9…`) and aborts if a count differs. For a
  new ROM build run it on that build's own jar and save the output as
  `framework/<md5 of input>.jar`.
- A diff of the beta4 jar against C.06 found no port-author code edit
  (`maintainer/jar-edits/REPORT.md`); the port's repack (`PATCH-INVENTORY.md` S17)
  is the only difference.
- `post-fs-data.sh` binds `framework/<md5 of /system/framework/oplus-services.jar>.jar`
  over the ROM jar only if it exists, after `chcon` to `u:object_r:system_file:s0`
  (system_server cannot read `shell_data_file`). C.06 stock ships
  `oat/arm64/oplus-services.{odex,vdex,art}`; beta5 removes it, and
  `post-fs-data.sh` skips the bind if a prebuilt `.odex` exists unless
  `FRAMEWORK_ALLOW_ODEX=1`. `FRAMEWORK_SENSOR_REROUTE=0` disables.
- Module v0.15 is current (v0.10 + pen watcher, `BUGS-TODO.md` B6; v0.15 adds `pipa_pen_state` and the helper grants); since v0.10 it also carries the C.06 boot fixes, so even the original
  beta5 image boots with it. v0.9 and older lack them; v0.7 and older bind the beta4
  jar on C.06 (likely bootloop). See `module/README.md` §12.
- The Eye Protect app resets its settings to 0 at boot; `service.sh` saves and
  restores them (`adaptive_state` / `bedtime_state`).

## Display facts

Details in `module/README.md` §6–7 and §12.

- **Colour:** QDCM modes ship PCC/gamut disabled; the module enables PCC in
  `standard` (Natural) and `hal_srgb` with HyperOS `miLut_2` (`tools/patch_qdcm.py`).
- **Brightness:** ColorOS `<level>P,B,N,K</level>` table generated by
  `tools/gen_brightness_table.py`; keep min >= 20. Don't drive the QS slider with
  downward swipes (it closes Quick Settings); use
  `settings put system screen_brightness <level>` and restore auto afterwards.
- **Adaptive colour / Bedtime:** framework key
  `setting_enable_color_temperature_regulation` applies the tint; see
  `module/README.md` §12. The 100 lx is a workaround, real ALS lux is not bridged.

## USB audio and speakers (v0.6/v0.7, details in `module/README.md` §13-14)

The module ships USB_HEADSET/A2DP volume curves (`tools/patch_audio_volumes.py`) so
USB DACs no longer play at full scale, and a patched 32-bit audio HAL
(`tools/patch_audio_hal.py`) that fixes swapped speaker L/R. The audio policy can
be re-read by restarting `audioserver` (safe, unlike `system_server`). A2DP curves
are untested with a non-absolute-volume BT headset.

## Flashing

`FlashLinux.sh` sets the active slot to **B**, flashes firmware + `super.img`,
and optionally wipes userdata/metadata (interactive). Only the user runs it.
Never run it yourself.

`maintainer/flash_super.sh [-y] <name>` (names = the `case` list in the script, newest `beta5-2n`; regenerate deleted ones with `build_port.sh`) (all build steps in one go, or for a new donor: `sudo sh maintainer/build_port.sh <tag> <donor-img-dir>`; every step script honours `TAG` and `DONOR_IMG`; layered builds: `build_beta5_baked.sh` → `_1c` → `_2a` → … → `_2g`, earlier text: `_2b`, each `sudo`) flashes **only `super`** to slot B (md5 check first, no firmware, no wipe; `-y` is needed when run without a terminal). The user may run it or explicitly ask you to. After a flash, `/data` is mounted with f2fs `checkpoint=disable` until a boot completes: in a bootloop every write to `/data` (including `/data/adb`) is rolled back at the next reboot. `vdc checkpoint commitChanges` keeps them. The bundled `bin/Linux/fastboot` lost its exec bit when unpacked; use the system `fastboot`.

## Known gotchas

- **Software update false "storage less than 262.30 MB".** `com.oplus.ota`
  checks `/data/ota_package/OTA`; if missing, `StatFs` throws and free space is
  treated as 0. The `262.30 MB` is the package size, not a threshold. Fix (done
  live): `mkdir -p`, `chown system:cache`, `chmod 0770`, `restorecon`.
- **Do not install the offered OTA.** It is a 262.30 MB SOTA bundle for donor
  model OPD2515, not pipa; installing can overwrite port-patched apps. The rebuilt
  beta5 images remove the updater (`com.oplus.ota`, `com.oplus.sau`, `com.oplus.sauhelper`;
  Settings hides the entry, tested). Keep `com.oplus.romupdate` (feature configs).
- **SELinux denials never reach dmesg/logcat**: the kernel has no audit core (stale `/proc/config.gz`). Use
  `maintainer/avc_trace.sh start`, use the feature, then `avc_trace.sh dump <label>` (kprobes, live only).
- Read the "What was changed on the device" table before live changes so you do
  not undo another session's fixes.
- Killing `system_server` reboots the device (sysrq warm reset). Use reboot.
- **C.06 boot hangs (fixed in the rebuilt beta5 images and module v0.10).** C.06
  waits forever for HALs pipa lacks: `OplusEngineerFwService` calls
  `waitForService(IEngineer)` unless `!ro.adb.secure`, and
  `system_ext/{lib,lib64}/libupdateprof.qti.so` / `libtrigger-handler.so`
  switched `checkService` -> `waitForService` (QSPM). Each hangs system_server
  until its watchdog panics the device. Fixes: `patch_framework.sh` edit 4 and
  the four beta4 libs carried via `PORT-EDITS.tsv`. On a new donor, scan changed
  libs for new `waitForService` imports before flashing. Diagnose bootloops from
  `/data/anr/traces_SystemServer_WDT*` and `/sys/fs/pstore/dmesg-ramoops-0`.

## pipa_port services (beta5-2e+)

Never let `cmd`-based tools (`input`, `am`, `settings`, `pm`, `cmd`) inherit a pipe or a file of
your own as stdin/stdout/stderr in a service of the `pipa_port` domain. They hand those fds to
system_server over binder; if system_server may not use the fd's label the call fails with
`Failed transaction (2147483646)` and nothing is logged (dontaudit). Redirect all three to
`/dev/null`. The old module ran in the unconfined `ksu` domain and never hit this. SELinux trace:
`maintainer/avc_trace.sh`.

## Root (ksud) and kernel work

Never replace `/data/adb/ksud` (no wrapper, no switch). On 2026-10-23 a compiled switch there made the
joeyzhu kernel hang on the Mi logo. Update ksud only together with a matching kernel, through the SukiSU
manager. Rescue when the tablet does not boot: the boot image contains TWRP 3.7.1 (Power + Volume up, or it
starts by itself after failed boots); TWRP adb is root and `/data` is decrypted. Partition backups:
`maintainer/kernel/flash_kernel.sh restore`.

Previous own kernel (boot_b 2026-10-23 until 21:40, now the rollback: E404 r2 + SukiSU builtin + susfs 2.3.0): **Since 18:16 r2b** (+ `uclamp_boost.c` touch boost, boot header cmdline `ramoops_memreserve=4M` = pstore; E404 has no built-in ramoops cmdline). Test with **trimmed** images (header+kernel+ramdisk; a full 196 MB `fastboot boot` hung the bootloader twice). Measure smoothness with `KTAP=1 maintainer/stress_switch.sh`: `input tap` bypasses kernel input handlers, so in-kernel touch boosts look useless with it. ColorOS boosts through the QTI perf HAL (WALT `sched_boost`), not the power HAL (it gets no hints). `kernel/KERNEL-RESEARCH.md`
(status, evidence). Rebuild for a new E404/SukiSU commit: `maintainer/kernel/prepare_tree.sh <dir> [E404_REF]
[SUKISU_REF]`, `build_kernel.sh`, pack only with `mkboot.sh` (`magiskboot unpack -h`/`repack` corrupts the boot
header patch level and the bootloader then refuses the kernel silently: black screen, no log), test with
`flash_kernel.sh test` (`fastboot boot`, nothing written), `flash_kernel.sh flash|restore`. After a SukiSU update
re-check every hook `extern` type and that `susfs_set_batch_sid()` runs on 4.19. `adb shell su` needs Shell
granted in the SukiSU manager (release build, not DEBUG).

**Own WALT kernel (on boot_b since 2026-10-23 21:40; now `walt-r5` since 2026-10-24 14:25 = walt-r3 (SurfaceFlinger on the top GPU ringbuffer) + r4 (SF RenderEngine off the little cores, `is_sf()`) + r5 (sysctl `kernel.ux_prefer_big`=1: heavy UX threads on the big cluster without the slide scene; `kernel.frame_rate` default 120); rollbacks `boot-walt-r4.img`, `boot-walt-r3.img`, E404 r2b):** Lineage 24 core + liyafe's pipa drivers +
E404's display/touch + SukiSU/susfs, branch `own` in `port-work/kernel/walt-own` (OPPO UI First on branch `oppo`,
worktree `walt-oppo`). Recipe, rebuild from scratch (`maintainer/kernel/prepare_tree_walt.sh`, our commits are in
`kernel/walt-own.bundle`; save it with `--save` after committing), checks and updating: **`kernel/WALT-KERNEL.md`**.
Build `maintainer/kernel/build_walt.sh` (config = Lineage fragment chain + `xiaomi/pipa-cos17.config`; `DBG=1` = boot
watchdog + lockup panics), test only with `TRIM=1 mkboot.sh` images. Lessons: never `pkill -f build_walt.sh` from a
command that contains that string (kills itself); do not edit `build_walt.sh` while it runs; a 10 s power press is a
hard reset (pstore lost), DBG builds warm-reset by themselves; E404 cannot decode the WALT kernel's pstore console
record but `unused-ramoops-0` holds the text; A17 never mounts schedtune (cpu cgroup + uclamp is what ColorOS uses).

**Idle drain / keyboard guard (2026-10-24):** the nanosic driver creates its virtual "Xiaomi Keyboard" input devices whether or not a keyboard is attached, so an input-name check always says "attached". pipa_port (`KEYBOARD_GUARD`, beta5-2j) asks the MCU instead (`echo 1 > /sys/devices/virtual/nanodev/nanodev0/_version176x`, `Connected=[1]`) and runs `xiaomi-keyboard` only then; without it the daemon's accelerometer loop keeps the SLPI awake and the SoC never power-collapses. Idle checks: `dumpsys batterystats` (wakelocks, wakeup reasons), `/sys/power/system_sleep/stats` (aosd/cxsd counts), `/sys/power/rpmh_stats/master_stats` (per-subsystem sleep, 19.2 MHz ticks).

**Sharing (2026-10-24):** kernel source = GitHub `kernel_xiaomi_pipa_cos17` (branch `oppo`; publish by cherry-picking onto `pub/oppo` in `port-work/kernel/walt-own`, then `git push origin pub/oppo:oppo`); port scripts/docs = GitHub `pipa-cos17-port` via `sh maintainer/sync_port_repo.sh "msg"` (no proprietary blobs, no signing key; fails closed); private co-maintainer kit = `maintainer/make_port_kit.sh`; user package = `maintainer/build_release.sh`. The helper keystore password is in `helper/keys/keystore.pass` (never commit or share `helper/keys/`). Scripts take `PIPA_ROOT`/`PIPA_OWNER`.

**Smoothness fixes in the ROM (2l) and how to measure:** SurfaceFlinger props must go into `product/etc/build.prop`: pipa's vendor build.prop sets HyperOS SF values (`-4 ms` offsets, `predict_hwc_composition_strategy=0`) and loads after system/system_ext. The UI First kernel keeps SurfaceFlinger off the little cores only while a sched_assist scene is set, and on pipa nothing sets it (OPPO's vendor daemon does), so pipa_port `SF_BIG_CORES` writes `echo 384 > /proc/sys/kernel/sched_assist_scene` (bit 7 = SA_SCENE_OPT_SET; without it a write clears bits). Duration-model SF timing (`use_phase_offsets_as_durations=1`) aborts SurfaceFlinger while any `*phase_offset_ns` prop exists (boot hangs). Measure visible stutter with `maintainer/perfetto/traced_heavy.sh <label>` (FrameTimeline: SF on time, dropped, stuffing), not gfxinfo alone; wait 60 s after unlock; judge on >= 2 runs.

**Smoothness testing (since 2026-10-23 night):** `maintainer/heavy_mix.sh` (clean start, real touch via `maintainer/kgest`, Spotify live alert, apps + flings, shade/QS, pill, drawer, fast bursts; run twice, spread ±3 %). Perfetto works since beta5-2j (2i and older: the donor's `traced.relay_producer_port=vsock://...` killed `traced`, our kernel has no vsock): `setprop persist.traced.enable 1` before tracing and back to 0 afterwards. atrace/tracefs also work; atrace's "runnable" totals are inflated by its overhead, use the raw tracefs script `maintainer/perfetto/ktrace.sh` for scheduler numbers. Analysis notes: `kernel/KERNEL-RESEARCH.md` "2026-10-23 midnight".

## Current state

See `MAINTAINER-STATUS.md` (roadmap and session plan). As of 2026-10-23 evening the tablet
runs beta5-2g with the joeyzhu kernel (own E404R kernel built, not flashed), module `pipa_susfs` only; check `ksud module list`. Open product issues: charger info path,
`crop_eyes` crash, thermal mapping, keyboard case test.
