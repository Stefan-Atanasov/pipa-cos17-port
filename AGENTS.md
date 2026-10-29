# AGENTS.md

This file gives instructions to AI coding agents (Claude Code, Codex, opencode, Cursor and others) that work in this
repository. Human readers: start at [README.md](README.md).

Style of all docs: ASD-STE100 (Simplified Technical English). Use short sentences, active voice, and one
instruction in each sentence. Keep technical names (files, properties, commands) as they are.

## What this repository is

This repository has the build scripts and sources of the **ColorOS 17 port for the Xiaomi Pad 6 (`pipa`, SM8250 /
SD870)**. The scripts make the ROM (`super.img`) from the original beta4 release and an OPPO OPD2515 donor build
(C.06). The kernel is in a separate repository: https://github.com/Stefan-Atanasov/kernel_xiaomi_pipa_cos17
(branch `oppo`).

Read in this order:
1. [README.md](README.md): overview and contents.
2. [BUILD.md](BUILD.md): build, flash and roll back the ROM and the kernel.
3. [ARCHITECTURE.md](ARCHITECTURE.md): the ROM layers, the `pipa_port` service, the helper app, SELinux.
4. [BUGS.md](BUGS.md): open bugs with cause, evidence and next step (table at the top). Offline analyses:
   `maintainer/bugs/*.md`.
5. [KNOWN-ISSUES.md](KNOWN-ISSUES.md), [TESTING.md](TESTING.md), [REBASE.md](REBASE.md), [KERNEL.md](KERNEL.md).

| Path | Content |
|---|---|
| `maintainer/` | Flash, release, test and analysis scripts. The old layer scripts (`build_beta5*.sh`, `build_port.sh`) are history and the test path |
| `maintainer/port/` | The main ROM build: `port.sh` and `steps/NN-<step>-<name>.sh` |
| `maintainer/kernel/` | Kernel tree setup, build, boot image packing, flash |
| `port-rom/` | The `pipa_port` service as ROM files (`/system_ext/pipa_port/`, init rc) |
| `helper/` | Source of the pipa helper app (persistent priv-app: Dolby, pen pill, lock with cover) |
| `module/` | Tools of the old module. `module/tools/` makes the patched display, audio and framework files that the build uses |

Proprietary binaries, images, donor files and the helper signing key are not in this repository
([BLOBS.md](BLOBS.md)).

## Rules for agents

- **The tablet is a real device that a person uses.** Ask before you flash, wipe, reboot, `pm uninstall`, or make a
  persistent change. Say what you will flash and how to roll back.
- **Never run `FlashLinux.sh` / `FlashWindows.bat`.** They can wipe user data. Only the person runs them.
- `maintainer/flash_super.sh [-y] <name>` flashes only `super` to slot B, after an md5 check. It does not wipe.
- Never store passwords, PINs or keys in files, logs or commit messages.
- Never commit or share `helper/keys/` (the helper signing key and `keystore.pass`). With it, a person can sign a
  helper update that the ROM accepts.
- Do not add proprietary binaries (`*.so`, `*.jar`, `*.apk`, images) to this repository.
- Before a large investigation, say in one line why it matters for the user. If it becomes a side task, record it
  in `BUGS.md` and ask before you continue.
- When you change a fact, change the docs in the same work. Write them in STE100.

## Paths and tools

- The scripts use `PIPA_ROOT` (the folder that holds this repository as `COS17/`, plus `port-work/` and `donor/`) and
  `PIPA_OWNER` (user:group of the build output). The build scripts run as root. Give the variables through sudo:
  `sudo PIPA_ROOT=$PWD PIPA_OWNER=$USER:$USER sh COS17/maintainer/port/port.sh ...`.
- Host tools: `erofs-utils`, `lpmake`/`lpunpack`, `fastboot`/`adb`, python3, JDK 21 + Android SDK build-tools 37
  (helper), NDK 30 (face crop add-on), AOSP clang r547379 (kernel).
- The partition images are **EROFS**, not ext4. Use `dump.erofs --ls|--cat --path=<p> <img>` and
  `fsck.erofs --extract=<dir> --xattrs --preserve <img>` (as root, to keep the SELinux labels).
- Device access: `adb -s <serial> shell "su -c '<cmd>'"` (root through SukiSU / KernelSU). Many scripts read the
  `ADB` variable, for example `ADB="adb -s <serial>" sh maintainer/device_check.sh`.

## How to change the ROM

- The main build is `sudo sh maintainer/port/port.sh <tag> <donor-img-dir> [--until <step>] [--keep-tree]`
  (`--check` = preflight). It builds in one tree and runs the steps `maintainer/port/steps/NN-<step>-<name>.sh` in order.
- **A new fix is a new step file** in `maintainer/port/steps/`. Do not write a new layer script. The procedure is in
  `maintainer/port/README.md` ("How to add a step"). Set `STEP`: it writes `ro.pipa.port.layer`.
- You can test a fix as a quick layer on top of the last image ([BUILD.md](BUILD.md) "Old method"). Then move it into a step.
- To compare two builds, compare the `report/<partition>.tsv` manifests. The image md5 differs on each run (random
  `mkfs.erofs` UUID).
- Before a new donor: `sudo bash maintainer/donor_check.sh <old-img-dir> <new-img-dir>` ([REBASE.md](REBASE.md)).
- Only replace files in the copied tree. Write in place with `cat new > old`, so that the owner, the mode and the
  SELinux xattr stay. Each file must have `security.selinux` (`tree_manifest.py` checks it).
- Each text edit must find its anchor exactly one time. If the anchor is not found, stop. Do not guess.
- Add the new name and its md5 to `maintainer/flash_super.sh`.
- **To test a changed `pipa_port` script before a build:** bind-mount a copy on the ROM file
  (`mount --bind /data/local/tmp/x.sh /system_ext/pipa_port/x.sh`, `chcon u:object_r:system_file:s0`). A reboot
  removes it. `sed -i` makes a new inode and the bind mount stays on the old file: write with `cat new > old`.
- Stop a service child by its pid file. Never use `pgrep -f <path>` in `su -c`: the pattern also finds your own
  command line and kills your shell.
- You cannot update the persistent helper app with `adb install`. Flash a ROM layer, or `pm uninstall` and install it
  as a normal app for a test.

## Known gotchas

- **`cmd` tools in the `pipa_port` domain.** `input`, `am`, `settings`, `pm` and `cmd` send their stdin, stdout and
  stderr to system_server over binder. If system_server cannot use the label of a descriptor, the call fails with
  `Failed transaction (2147483646)` and no log. In `pipa_port` scripts, redirect all three to `/dev/null`. Thus
  `$(settings get ...)` cannot work there: use `sget` in `service.sh` (`settings get` into a
  file in `/data/local/tmp`).
- **SELinux denials are in logcat (tag `auditd`) and dmesg** (the WALT kernel has `CONFIG_AUDIT=y`). The default audit
  rate (5/s) drops most denials: for a capture, set `persist.logd.audit.rate` to 2000 and reboot. init checks property
  sets in user space and logs nothing for a permissive domain: test property rules with a boot.
- The `pipa_port` domain is **enforcing since 3g**. Its rules are in `maintainer/sepolicy/pipa_port_rules.cil`. A new
  access in the service needs a rule there.
- Before you build a policy change, compile it on the tablet with `/system/bin/secilc` and all 8 policy inputs.
- **Donor boot hangs.** C.06 waits for HALs that pipa does not have (`waitForService` in `oplus-services.jar` and in
  two QSPM libs). Each one stops system_server until the watchdog panics the device. On a new donor, scan changed libs
  for new `waitForService` imports before you flash. A bootloop: read `/data/anr/traces_SystemServer_WDT*` and
  `/sys/fs/pstore/`.
- After a flash, `/data` uses f2fs `checkpoint=disable` until a boot completes. In a bootloop, the next reboot removes
  each write to `/data`. `vdc checkpoint commitChanges` keeps them.
- **OPPO sensor type numbers collide with Xiaomi's (2w).** ColorOS asks for OPPO's private sensor types (3317xxxx)
  with `getDefaultSensor(type)`. pipa's sensor HAL uses the same range for Xiaomi sensors. 33171001 (OPPO CCT) is
  absent (rerouted to Xiaomi 33171088 by `patch_framework.sh`). 33171038 (OPPO fold angle) is Xiaomi `knuckle`.
  33171037 is Xiaomi `screen_down`. A wrong match can run an expensive algorithm on the sensor hub all the time:
  `knuckle` kept the SLPI asleep only 1-40 % with the screen off (~50 mA in deep doze), fixed by
  `module/tools/patch_foldtouch.py`. To find such a drain: SLPI sleep in `/sys/power/rpmh_stats/master_stats`
  (19.2 MHz ticks, root), active sensors and their clients in `dumpsys sensorservice`.
  `dumpsys sensorservice restrict <pkg>` turns off all sensors at the HAL (an all-or-nothing test only;
  `dumpsys sensorservice enable` restores).
- **Live test of a framework jar:** copy the patched jar to `/data/local/tmp`, `chcon u:object_r:system_file:s0`, bind-mount
  it in init's mount namespace (`nsenter -t 1 -m -- mount --bind ...`), then `setprop ctl.restart zygote` (worked
  on 2026-10-28; a reboot removes the mount).
- **SurfaceFlinger waits for OPPO display HALs (fixed in 2x).** C.06 `surfaceflinger` calls `waitForService` for
  `IMixLut3D`, `IDisplayColorFeature` and pixelworks `IIris` when a feature needs them (Game Filter: the main thread
  hangs, the picture freezes, touch is dead). `module/tools/patch_sf_waits.py` changes them to `checkService`. On a
  new donor, list the `bl <AServiceManager_waitForService@plt>` sites again (`llvm-objdump -d`). A frozen screen
  with working ADB: `debuggerd -b $(pidof surfaceflinger)` shows the blocked call.
- **A system binary that init starts as a service cannot be tested from `/data` by bind mount.** `/data` is
  `nosuid`, so SELinux refuses the domain change (`nosuid_transition`, e.g. init -> surfaceflinger) and the service
  does not start. Test such a binary with a ROM layer. (Jars and APKs work by bind mount.)
- **SurfaceFlinger properties go into `product/etc/build.prop`.** pipa's vendor build.prop loads after system and
  system_ext and sets HyperOS values.
- **Kernel images: pack only with `maintainer/kernel/mkboot.sh`.** `magiskboot` repack changes the header patch level,
  and the bootloader then refuses the kernel with no message (black screen). For `fastboot boot` tests, use trimmed
  images (`TRIM=1`).
- **Do not run a live `ksud sepolicy patch` on kernel walt-r8kpm (SukiSU 4.3 builtin).** On 2026-10-29 two live
  rules (an `allow` and a `dontaudit`) hung the big cores; the watchdog reset the tablet 20 s later (pstore:
  `Watchdog bark`, cpu alive mask 0f). Compile a policy change on the tablet with `secilc` and test it with a ROM build.
- **Never replace `/data/adb/ksud`.** Update it only with a kernel that agrees with it, through the SukiSU manager.
- **If the device does not boot:** the boot image has TWRP (Power + Volume up). TWRP ADB has root and a decrypted
  `/data`.
- **Patching a system app (APK).** Many OPPO system apps (for example IPeManager) are signed with the platform key.
  Do not re-sign them: they lose their platform-signature permissions. Android does not verify APKs on system
  partitions at boot (it only reads the certificate), so patch the dex **in place with the same size** in the original
  APK (the dex must be stored, not deflated), update only the zip CRCs, and keep the signing block
  (`maintainer/ipe-fluid/patch_ipemanager.py` is the model: pattern-based, stops on a different version). Delete the
  prebuilt `oat/` next to the APK. To test live: bind-mount the patched APK over the original in init's mount namespace
  (`nsenter -t 1 -m -- mount --bind ...`) and `am force-stop` the app; a reboot removes it.
- **Each zygote or composer restart attaches one more 8 GB OPPO swap file.** Its old file is deleted but stays open,
  so `/data` fills up (72 GB after a day of UI-restart tests). `pipa_port` `nandswap_dedup` removes the extra loop
  swaps (it needs `sys_admin` and the loop ioctls, in the rules since pt18). By hand: `swapoff` and `losetup -d` each
  `loop` that `losetup` shows on `/data/nandswap/swapfile` and `/proc/swaps` does not list. Prefer a reboot.
- **Live test of a display calibration:** bind the QDCM XML over `/vendor/etc/qdcm_calib_data_*.xml` in init's
  namespace, then `setprop ctl.restart display-color-hal-1-0` and `vendor.qti.hardware.display.composer` (the UI
  restarts). Do `umount` before a new bind: stacked binds keep the old file. A SurfaceFlinger matrix preview
  (`su -c 'service call SurfaceFlinger 1015 i32 1 <16 floats>'`, `i32 0` resets) acts weaker than the same matrix in
  the PCC.
- **Adaptive tone** uses the continuous Xiaomi colour stream `front_cct_strm` (33171089) since 3s
  (`maintainer/ambientlux/`). Check it with `dumpsys color_display` (`sensorDataValid`, `sensorLux`, `targetCCT`).
- **`dump.erofs --ls --path=<missing>` returns exit code 0.** Check its output for "read inode failed".
- **Run smali and baksmali with `-j 1`.** With threads, the dex layout changes on each run (same code, other md5).
- Do not kill `system_server` to apply framework changes (it causes a warm-reset crash). Reboot.
- **Smoothness:** measure with `maintainer/perfetto/traced_heavy.sh <label>` (FrameTimeline), not only gfxinfo. Wait
  60 s after unlock and do 2 runs or more. `input tap` goes around the kernel input handlers; use real touch through
  `maintainer/kgest`.
