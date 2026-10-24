# Maintainer status (current state)

Short and kept up to date. The full work log (every step, md5s, evidence) is `HISTORY.md`.
Last updated: 2026-10-24 14:30 (kernel **walt-r5** + ROM **beta5-2n**; release prep). Before: 2026-10-24 12:15 (**kernel walt-r4** + ROM **beta5-2l**: stutter fixes, SF frames on time 59 -> 92 %; see kernel/KERNEL-RESEARCH.md "2026-10-24 midday"). Before: 2026-10-24 09:25 (**ROM beta5-2j** flashed: keyboard guard = overnight idle fix, loc_sys_service disabled, SF layer caching/HWC prediction in the ROM, Perfetto works; KSU scripts retired). Before: 2026-10-24 01:10 (kernel walt-r3 = SurfaceFlinger GPU priority fix, pushed; smoothness session, see "To do" 0/1). Before: 2026-10-23 22:50 (walt-r2 + ROM 2i, UI First works, kernel source on GitHub). Before that: 2026-10-23 21:45 (**own WALT kernel flashed** on boot_b: Lineage 24 core + liyafe pipa drivers + E404 display/touch + SukiSU/susfs + uclamp; battery 62.5 mAh/h vs E404 98.7; recipe `kernel/WALT-KERNEL.md`; next: ColorOS 17 UI First interface on branch `oppo`).

## What runs on the tablet

- Kernel **walt-r5** on boot_b (flashed 2026-10-24 14:25, `bootimg/boot-walt-r5.img`, md5 `bbc576523eb15649520b3ccd97200c15`, branch `oppo` 07c07a536bc1 / public `oppo` 14710e930108) = walt-r4 + sysctl `kernel.ux_prefer_big` (default 1: heavy UX UI threads on the big cluster outside the slide scene; launcher gfxinfo 7.4-7.9 -> 5.8-6.7 %, App Deadline -24 %, power 6.99 -> 6.74-6.79 W) + `kernel.frame_rate` default 120 (was 60). Rollback `bootimg/boot-walt-r4.img`.
- Previous kernel walt-r4 (12:10-14:25, md5 `e1dc8fece8bbe41031597bebfadd7a3d`) = walt-r3 + SF RenderEngine off the little cores.
- **ROM beta5-2n** (flashed 2026-10-24 13:07, super md5 `ece2e9e11c2506b86efde8e6fb28d8df`) = 2l + **2m** (SF layer
  caching off again: it made the screen glitch in Settings search; md5 `989d94be82b18fb8db5aa41e6632f9f6`) + **2n**
  (system_server animation threads as UX, UI apps fully compiled: faster QS -> Settings). Rollback `flash_super.sh -y
  beta5-2m` / `beta5-2l`. Launcher taskbar is off on the tablet (user choice, live setting).
- ROM beta5-2l (flashed 2026-10-24 11:20, super md5 `b517e27b3445b9449f4d0fbb1d12449f`, `build_beta5_2l.sh`) =
  2k + smoothness fix: pipa_port `SF_BIG_CORES` sets the UI First kernel scene (SurfaceFlinger/RenderEngine off the
  little cores) + product build.prop SF early/earlyGl offsets -6.5 ms, early app -1.5 ms, predict_hwc 1. SF frames on
  time 59 -> 88 %, dropped 6.5 -> 2.2 %. Evidence: `kernel/KERNEL-RESEARCH.md` "2026-10-24 midday" and "morning".
  Rollback `flash_super.sh -y beta5-2k`. No KSU boot scripts (test scripts in `/data/local/tmp/ksu-retired/`).
- ROM beta5-2k (09:31-11:20, md5 `c4d337575af8daa4f18621ce6e01ada7`) = 2j + charger shim reports the battery genuine
  (BUGS-TODO 12).
- **ROM beta5-2j** (flashed 2026-10-24 09:18, super md5 `f5c63fabc1bc224d34494c42680fe9fb`, `maintainer/build_beta5_2j.sh`)
  on kernel **walt-r3** (`bootimg/boot-walt-r3.img`; rollback `boot-walt-r2.img`): 2i + pipa_port **keyboard guard**
  (`xiaomi-keyboard` runs only while the nanosic MCU reports the keyboard connected; it polled the accelerometer ~7x/s
  all night: SLPI asleep 27 %, AOSD 0x / CXSD 1x in 8 h), `loc_sys_service` `disabled` (it is `class main`; the 2a
  comment-out never stopped it), `debug.sf.enable_layer_caching=1` + `debug.sf.predict_hwc_composition_strategy=1` in
  system_ext build.prop, product build.prop without `traced.relay_producer_port` (Perfetto works with
  `setprop persist.traced.enable 1`). The KSU boot scripts are retired (moved to `/data/local/tmp/ksu-retired/`).
  Rollback: `flash_super.sh -y beta5-2i` (then restore the two KSU scripts from there).
- **Own WALT kernel `walt-r2`** on `boot_b` (flashed 2026-10-23 22:45, `port-work/kernel/bootimg/boot-walt-r2.img`, md5
  `320f1f956dd7d774308fce865674d8ef`, branch `oppo` commit `fab615b575b3`): walt-r1 + OPPO UI First (ColorOS 17 interface)
  + WALT frequency/colocation fix. Needs ROM **beta5-2i** (flashed 22:15, super md5 `d9c5bb8adf7644dc45726e9fb7bbc546`,
  = 2h + UI First SELinux; rollback `flash_super.sh -y beta5-2h`). Kernel rollback: `boot-walt-r1.img` (below).
  **Source public:** https://github.com/Stefan-Atanasov/kernel_xiaomi_pipa_cos17 (fork of LineageOS sm8250; branches
  `own`, `oppo`). Push from `port-work/kernel/walt-own`: commits there use the GitHub no-reply address (repo config);
  the older commits were rewritten to it on `pub/own`/`pub/oppo` before the first push, so push future work as
  `git push origin oppo` only after rebasing onto `pub/*` (or keep committing on `pub/*`).
- **Own WALT kernel `walt-r1`** on `boot_b` (flashed 2026-10-23 21:40, `port-work/kernel/bootimg/boot-walt-r1.img`, md5
  `50e0c82921fb0b5502e040a4784221ec`, `port-work/kernel/walt-own` commit `2c31004cc27a`, version string
  `4.19.325-cip136-st20-perf-g2c31004cc27a`): Lineage `lineage-24.0` core (WALT, BPF backports) + liyafe's pipa drivers
  + E404's display/touch + SukiSU builtin 7f1c299a/susfs 2.3.0 + uclamp + audit. Recipe/rebuild/update:
  `kernel/WALT-KERNEL.md`. Rollback: `bash maintainer/kernel/flash_kernel.sh flash port-work/kernel/bootimg/boot-e404-r2b.img`
  (E404 r2b, the line below). Manager/ksud 4.2.1-r1 fit both kernels.
- Previous kernel, **E404 r2b** (on `boot_b` 2026-10-23 18:16–21:40, md5 `c6f3ea5da83eebe47af93f1124c0f21e`, `port-work/kernel/bootimg/boot-e404-r2b.img` = r2 + `kernel/sched/uclamp_boost.c` (touch boost for CASS: top-app/foreground uclamp.min 40 % while touching; Spotify-spam jank 21–32 % → 13–16 %, as good as the old WALT kernel) + boot header cmdline `ramoops_memreserve=4M` (pstore). Rollbacks: `boot-e404-r2p.img` (no boost, md5 `3d2f2a5f…`), `boot-e404-r2.img` (no pstore, md5 `30f33b6c…`)): E404R staging-bpf + SukiSU builtin (uapi 6) + susfs 2.3.0 + audit + pstore. SukiSU manager **v4.2.1-r1**, ksud 4.2.1-r1 (installed by the manager), Shell granted, `pipa_susfs` active. Rebuild: `maintainer/kernel/prepare_tree.sh` → `build_kernel.sh` → `mkboot.sh` (never pack with `magiskboot -h` alone, see `kernel/KERNEL-RESEARCH.md`). Rollback: `maintainer/kernel/flash_kernel.sh restore` (old joeyzhu kernel; then reinstall manager 4.2.0 so ksud matches uapi 2).
- **ROM beta5-2h** (flashed 2026-10-23 15:04, md5 `82c48b0496d9e1f1f7619b2c84462295`): 2g + null guards in OPPO's gpuservice extension (`maintainer/patch_gpuserviceext.py`), needed with our kernel. Rollback: `flash_super.sh -y beta5-2g`.
- ROM beta5-2g (on the tablet 2026-10-23 00:30 – 15:04): donor OPD2515 `17.0.0.103(CN01)` (C.06) `system` + `system_ext` + `product`, pipa `vendor`/`odm`/firmware/kernel unchanged. `super.img` md5 `79add8ff20ff98d62981f3247901bbc0` (`port-work/beta5-2g/img/super.img`, `maintainer/flash_super.sh beta5-2g`). Boots in ~40 s, SELinux enforcing. = 2f + the AudioX disable in the ROM (`system_ext/etc/sysconfig/pipa-component-overrides.xml`, applied at every package scan by `ScanPackageUtils.configurePackageComponents`); verified: after `pm default-state` on the service it stays disabled (`query-services` empty, 0 `AEC.AudioxService` log lines).
- Previous builds for rollback: `beta5-2f` (md5 `bcf016f7d68fb51851f95e5885d68076`, without the AudioX entry), `beta5-2e` (`3340aae245fcc14143d6bea544ed5150`), `beta5-2d` (`3dfbe1816afec27f519ee0fed5b86145`); flash with `maintainer/flash_super.sh -y <name>`.
- **No KernelSU module is needed.** Everything the port needs is in the ROM:
  - `/system_ext/pipa_port/` + `/system_ext/etc/init/pipa_port.rc`: init services `pipa_port` (service.sh:
    face HAL + crop add-on + rotation, charger shim, pen wake/buttons/watcher, colour/adaptive/bedtime
    restore, defaults) and `pipa_subsys0/1` (virtual modem HALs for interconnect), early boot `early.sh`.
    Domain `pipa_port` is **permissive** (rules still to be collected).
  - **pipa helper app** (`com.port.pipa.helper`, persistent priv-app): Dolby keeper (B10), pen pill and
    low-battery notification (B3), "lock with cover" switch → `lid_behavior` (B14).
  - Image fixes: boot rotation + centred boot logo (B13), traced off, native pen 120 Hz lock, OTA updater
    removed, Dolby/audio/QDCM/brightness files baked (see `PATCH-INVENTORY.md`, `HISTORY.md`).
- **Root extra:** `pipa-susfs-v1.0.zip` (module `pipa_susfs`): enables susfs root hiding at boot (AVC log
  spoofing, hide module mounts, hide `/data/adb`), three `ksud susfs` calls. **Installed 2026-10-23 and applied at every boot
  since the reboot at 00:13 (log `pipa_susfs: susfs applied`).** The effect can only be judged from a real app process: tests from
  `adb shell` or through `su` are not valid (susfs does not hide from su-ed processes). A root-only feature, so it stays a module. Rule: fixes the port needs go in the ROM
  build scripts; a module only holds root extras, so a new base never needs anything re-baked into it.
- **Root = SukiSU Ultra** (manager `com.sukisu.ultra` v4.2.0, `ksud 4.2.0-1`, kernel part built into the kernel
  and reporting 40900 = same version, uapi 2). The kernel has susfs (variant NON-GKI: sus_path, sus_mount,
  sus_kstat, uname/cmdline spoof, open redirect, sus_map) and `kernel_umount` is on, so module mounts are
  hidden from non-root apps by default. SukiSU's own `ksud susfs module install` only persists the toggles of the
  manager's SuSFS page and defaults to everything **off** (it writes `avc-log-spoofing 0`, `hide-mounts 0`), so it
  is not used (it would fight with `pipa_susfs`). Not hidden by susfs: the unlocked bootloader
  (`ro.boot.verifiedbootstate=orange`; Play Integrity needs PIF/TrickyStore). Backups of the working manager and
  daemon: `kernel/sukisu-backup/` (APK + `ksud`). A new manager version may need a newer kernel part; the kernel
  (built by the original developer, no source here; `kernel/RE404-…zip` is a different kernel) is not rebuilt
  by us, so do not update the manager blindly.

## Build chain (each step is a script on top of the previous image)

`build_beta5.sh` (plain C.06 rebase) → `build_beta5_baked.sh` → `_1c` → `_2a` → `_2b` → `_2c` → `_2d` →
`_2e` → `_2f` → `_2g` → `_2h` → `_2i` → `_2j` in `maintainer/`, each `sudo sh …`, output in `~/Documents/pipa/port-work/<step>/`.
Sources the later steps copy in: `helper/` (`sh helper/build.sh`, JDK 21 + `~/Android/Sdk`),
`port-rom/` (pipa_port as ROM files), `maintainer/bootanim/`, `port-module/src/facecrop.c`
(`src/build_facecrop.sh`, NDK 30). Port edit list for the rebase: `maintainer/c06-vs-beta4/PORT-EDITS.tsv`.
Every text edit needs its anchor exactly once and the build stops otherwise.

**One command for all steps / a new base:** `sudo sh maintainer/build_port.sh <tag> <donor-img-dir> [first] [last]`
(`--check` = preflight only). It runs base → … → 2g with `TAG`/`DONOR_IMG` set (every step script takes both,
defaults unchanged = beta5/C.06), stops on the first error and prints the checklist of donor-dependent things to
re-verify. On a new donor the first two steps stop at their stock-md5 checks on purpose (jar, brightness xml, odm
script): regenerate from the new files, update the md5, resume with the first-step argument. Regression-tested
2026-10-23: step 2f built under a throwaway tag has a file manifest identical to the flashed 2f (4,089 entries;
the image md5 differs only by erofs' random UUID).

Flash: `sh maintainer/flash_super.sh -y beta5-2j` (super to slot B, md5 checked, no wipe).
Rollback: `flash_super.sh beta5-2f` (or `beta5-2e`, `beta5-2d`). If the first `fastboot` call says "Device does not
support slots", `fastboot reboot` and retry.

## Bugs (details and evidence: `BUGS-TODO.md`)

| Status | Items |
|---|---|
| Fixed in the ROM (verified on the tablet) | B3 pen pill/battery and "stylus connected" in Settings (2f), B6 pen 120 Hz, B7 face preview (rotation + crop), B10 Dolby at boot, B12 pen buttons incl. back-button screenshot (2f), B13 boot rotation + logo, B14 magnetic case, interconnect HAL rule (B9 part) |
| Open | **B9** network sharing (needs phone logs), **B8** privacy password / app lock (needs an `ICryptoeng` shim), B1 Wi-Fi recovery, B2 UI behind navbar, B4/B5 blur lag and smoothness, B11 idle refresh rate (parked), face enrollment `crop_eyes` crash |

## Start of a session (2 minutes)

1. `adb devices` (USB serial `83836a90`); `mountpoint /mnt/reference` (builds need the HDD); `adb shell "su -c 'ls /data/adb/modules'"` should list only `pipa_susfs`.
2. `adb -s 83836a90 shell getprop ro.build.display.id` and `ls ~/Documents/pipa/port-work/` to see which build is current (beta5-2g).
3. Read this page, then `BUGS-TODO.md` ("Open" table at the top). Passwords and the lock PIN are asked again every session and never stored.
4. Kernel: `adb shell cat /proc/version` (ours = `4.19.325-cip136-st20-perf-g<commit>` (WALT), uname shows 5.10.325; E404 rollback = `4.19.404R`; joeyzhu = `4.19.325-cip136-st20-N0-kernel++`), `su -c "/data/adb/ksud -V"` must match the kernel's SukiSU (4.2.1-r1/uapi 6 on ours, 4.2.0/uapi 2 on joeyzhu). If the tablet does not boot: TWRP (Power + Volume up) has root adb and decrypted `/data`; `maintainer/kernel/flash_kernel.sh restore` writes the partition backups.

## To do (prioritised; bug details in `BUGS-TODO.md`)

**Next session (in this order)**
0. **Idle drain (2026-10-24):** night 01:03-09:05 on 2i/walt-r3 = 78 -> 75 % (307 mAh screen off, 7h56m, awake 1.8 %,
   deep doze 97 %). Root cause of the high floor: `xiaomi-keyboard` (no keyboard) kept the SLPI awake -> fixed in 2j.
   Other costs: Xiaomi Smart Pen BLE link (367 `hs_uart_wakeup`, ~35 mAh Bluetooth, normal for a connected pen),
   `com.heytap.accessory` BLE scans (13 min/night, small; candidate to restrict), `deviceidle_maint`.
   **Next:** batterystats reset 09:21 at 75 % on 2j; compare the next night (expect much lower; check
   `/sys/power/system_sleep/stats` aosd/cxsd counts and SLPI in `/sys/power/rpmh_stats/master_stats`).
1. **Smoothness (in progress, `kernel/KERNEL-RESEARCH.md` "2026-10-23 midnight"):** test `maintainer/heavy_mix.sh`
   (walt-r2 baseline 19-25 % janky); ruled out: clocks, 120 Hz, SystemUI UX, GNSS loop. Next: perfetto FrameTimeline
   of the heavy test (jank type per frame: app vs SurfaceFlinger vs buffer stuffing), then fix by evidence.
   Perfetto works on 2j (`setprop persist.traced.enable 1`, back to 0 afterwards).
2. **UI First leftovers:** ddl_task (deadline scheduler, sm8750 `sa_ddl.c`), `/dev/sched_boost` lock boost, binder
   ux ioctl, async_perf_ctrl (last three not in OPPO's published sources); OPPO game_opt for games.
3. **Leftover bugs** (`BUGS-TODO.md`): B9 network sharing, B8 privacy password/app lock, B1, B2, face `crop_eyes`, B11.
4. **Release package** (`maintainer/build_release.sh`; ROM beta5-2j + our walt-r3 boot.img; publish the kernel source (GPL), e.g. GitHub) + clean-flash test.
5. **Companion app v0.5** (`helper/COMPANION-APP-PROPOSAL.md`).

**Later**
4. B9 network sharing (needs logs from the phone while a share is attempted), B8 privacy password/app lock (`ICryptoeng` shim; same problem blocks ColorOS app lock), B1 Wi-Fi recovery (`gEnableForceTargetAssert`), B2 UI behind the navigation bar, face enrollment `crop_eyes` crash, B11 idle refresh (needs an `IDisplayPanelFeature` shim).
5. Enforcing SELinux for `pipa_port`: boot trace with `avc_trace.sh` (the tracer starts only after boot; arm it as early as possible, restart the services to re-trigger), write the rules, drop `typepermissive` in `build_beta5_2e.sh`'s policy block.
6. Colour/adaptive/bedtime restore into the ROM (find and patch the resetters), OPPO Notes pen bridge, the first untested rebase on a real new donor with `build_port.sh`.
7. Root extras: Play Integrity stays BASIC (see above); nothing to do.

### Kernel (research first, build only if there is a clear win)
**Research done 2026-10-23: see `kernel/KERNEL-RESEARCH.md`** (E404R / N0 / liyafe all build here; recommendation E404R `staging-bpf` + SukiSU builtin + susfs 2.3.0 + `CONFIG_AUDIT`; do not update the SukiSU manager on the current kernel, uapi 2 vs 6). The note below that E404R refuses this ROM is wrong: it only aborts on Dandaa's `OemPorts10T` files, which we do not have.
Facts (2026-10-23): the running kernel is `4.19.325-cip136-st20-N0-kernel++ #8` built 2026-10-17 by `joeyzhu@ubuntu` with clang 20.1.8, **SukiSU Ultra v4.2.0 + susfs built in** (non-GKI), shipped as `boot.img` in the beta4 release. The device's `boot_b`, `vendor_boot_b`, `dtbo_b`, `vbmeta_b`, `vbmeta_system_b` are byte-identical to the release firmware; a full backup is in `kernel/backup-partitions-20261023/` (restore: `fastboot flash boot_b boot_b.img` etc., or the original release script). **We have no source for it.** `/proc/config.gz` of the running kernel is stale (claims `CONFIG_AUDIT=y`, but the kernel has no audit core), so it cannot tell us the real config. `kernel/RE404-MI_PAD6-BPF-261010-1613-fix.zip` is another community kernel (AnyKernel3: `PIPA-Image`, `PIPA-dtb`, `PIPA-dtbo.img`, "E404R by Project 113, PIPA touch/display fix v3") whose installer refuses this ROM ("OPLUS Port ROM by Dandaa no longer supported"); `kernel/KowSU_*.apk` is a KernelSU-fork manager from the same folder. `magiskboot` in the release lost its exec bit (`chmod +x`).
Questions for the research: (1) who built the running kernel and where is its source/defconfig (ask the original developer; he said patching is fine); (2) public sources for pipa/sm8250 4.19 (Xiaomi open-source `pipa` branch, LineageOS/other `sm8250` kernels) and what the port needs from the kernel (Xiaomi `nanodev`, `fuda`/reverse-charge nodes, hall keys, touch/display, audio, SukiSU + susfs patches); (3) what a better kernel would actually give: a working audit core (SELinux denials in logs, needed for enforcing `pipa_port`), scheduler/governor and thermal tuning for battery, newer SukiSU/susfs; (4) can we build it on this PC (Arch, clang + LLD, `make O=out`, then `magiskboot repack` of `boot.img` with the new `Image`/dtb/dtbo, flash `boot_b`; recovery = flash the backed-up images or the release script). A kernel build is a bigger project than a ROM layer: decide after the research.

### Companion app (research, idea)
**Research done 2026-10-23: `helper/COMPANION-APP-PROPOSAL.md`** (closest model PipaControls; v0.5 = separate non-persistent priv-app with Pen / Display / Status pages, Settings.Global `pipa_*` keys whitelisted in `service.sh`; check `settings get` in the `pipa_port` domain first).
Today the pipa helper app has no UI. A settings app for the port would let users switch things without root: pen button actions (now `keys.conf`), pen 120 Hz lock and the pen pill (+ low-battery threshold), lock-with-cover (ColorOS's own switch already drives it), keyboard-case behaviour, refresh-rate modes (B11 option B, interaction-based like Adaptive-Hz), performance/battery profiles (the `perf-test-module` flags), colour/adaptive restore, Dolby default, and a status page (pen battery, face HAL, services). Architecture question for the research: the helper is an ordinary-uid priv-app with `WRITE_SECURE_SETTINGS`, so the channel to the root service `pipa_port/service.sh` is `Settings.Global` keys (`pipa_*`) that the script reads (it already reads `pipa_pen_state` the other way); `/data/misc/pipa_port` is root-only. Also check what community apps exist (`~/Documents/pipa/pipa_pen_fix_v1.3.zip` is one).

### Release package (plan, from the beta4 flash scripts)
The beta4 release (`ColorOS17 Port for pipa-beta4-20261017/`) already has the scripts we need: `FlashLinux.sh` and `FlashWindows.bat`
(Windows script is GBK encoded, Chinese + English text, bundled `bin/Linux/fastboot` and `bin/Windows/fastboot.exe`). One script covers both
modes by asking "Erase metadata and userdata? (y / Enter)": **Enter = dirty flash** (keeps data), **y = clean flash**. It flashes all
firmware partitions (`abl aop bluetooth boot cmnlib cmnlib64 devcfg dsp dtbo featenabler hyp imagefv keymaster modem qupfw tz uefisecapp
vbmeta vbmeta_system vendor_boot xbl xbl_config`, all `_ab`), `super`, with `set_active b` before and after, then optionally erases
`metadata` and `userdata`. Firmware and kernel (`boot.img`) are unchanged from beta4, so the package = the same tree with our `super/super.img`
(`port-work/beta5-2g/img/super.img`, sparse 6.8 GB), the version text in the banner updated and the original credit kept (Coolapk @梦归zzz)
plus a maintainer line, a user README (unlocked bootloader needed, back up first, what changed, known bugs, Play Integrity BASIC only,
rollback = flash the old package) and `RELEASE-NOTES-beta5.md`. The bundled Linux `fastboot` needs `chmod +x` after unpacking (use the system one).
`maintainer/flash_super.sh` stays the developer shortcut (super only, md5 check).
**Script (2026-10-23):** `bash maintainer/build_release.sh <tag> [--boot <our boot.img>] [--name "beta5 …"] [--7z]` builds
`port-work/release/ColorOS17-Port-pipa-<tag>-<date>/` (beta4 bin/firmware, our super, banner + maintainer line in both
scripts, Windows kept GBK/CRLF, Linux script chmods/falls back to the system fastboot, README-FLASH.txt, RELEASE-NOTES,
SHA256SUMS). Tested with `--no-super`; the maintainer name is `MAINTAINER=` (default "stefan", ask before publishing).
Kernel scripts: `maintainer/kernel/` (`build_kernel.sh`, `flash_kernel.sh test|flash|restore`, `kernel_check.sh`).

## Rebuild everything from scratch (new machine or lost work trees)

1. **Inputs:** this COS17 folder (scripts, ROM sources `port-rom/`, `helper/`, patches, `kernel/walt-own.bundle`,
   `kernel/backup-partitions-20261023/`), the beta4 release 7z (firmware) and the donor OPD2515 C.06 images
   (`../donor/OPD2515_11.C.06/`; HDD `/mnt/reference` holds a second copy).
2. **ROM:** `sudo sh maintainer/build_port.sh <tag> <donor-img-dir>` runs every layer (base → baked → 1c → 2a … 2h) and
   prints the checklist; `maintainer/flash_super.sh -y <tag>` flashes super to slot B. Details: `PORT-MAINTAINER.md`.
3. **Kernel (own WALT):** `bash maintainer/kernel/prepare_tree_walt.sh` (clones Lineage + liyafe, restores our branches
   from the bundle), `build_walt.sh`, `mkboot.sh`, `flash_kernel.sh` (all in `kernel/WALT-KERNEL.md`). The E404 r2b
   fallback: `maintainer/kernel/prepare_tree.sh` + `build_kernel.sh` (E404 + `e404-pipa.patch` + `sukisu-pipa.patch`).
4. **Root extras:** SukiSU manager v4.2.1-r1 (`kernel/sukisu-backup/`), `pipa-susfs-v1.0.zip`.
5. Save the kernel bundle after every kernel commit session: `bash maintainer/kernel/prepare_tree_walt.sh --save`.

## Disk and artifacts (cleaned 2026-10-23)

- `port-work/`: `beta5-2g/` and `beta5-2f/` complete (tree, images, report; base of the next layer), `beta5-2d/` and `beta5-2e/` keep only `img/super.img` (rollback), older steps keep only `report/` (logs, file manifests); `roundtrip/src` is the beta4 base the rebase reads. Everything else is regenerated by `build_port.sh`. `port-work/avc`, `device-captures`, `device-checks`, `perf-ab` are reports.
- `flash_super.sh` names that still exist: `roundtrip`, `beta4`, `beta5-2d`, `beta5-2e`, `beta5-2f`, `beta5-2g`.
- Tablet `/data/local/tmp` holds only live service logs and system files (cleaned 2026-10-23).

## Device state and rules

- ADB over USB `83836a90` (TCP `192.168.0.37:5555` after enabling). Root via KernelSU. See `CLAUDE.md`.
- Ask before flashing, wiping or other persistent changes; tell the user before rebooting. Sudo password and
  PIN: ask each session, never store them.
- `README.md` ("What was changed on the device") lists every live change and its persistence.
- Downloads, archives and scratch: HDD `/mnt/reference` (symlinks); builds in `~/Documents/pipa/port-work/`.
  Check `mountpoint /mnt/reference` before builds.

## Doc map

| Doc | Purpose |
|---|---|
| `BUILD-GUIDE.md` | build, test, flash and roll back the ROM and the kernel (start here for any build) |
| `MAINTAINER-STATUS.md` | this page |
| `NEXT-SESSION-PROMPT.md` | ready-to-paste first message for the next session (plan, rules, what to read) |
| `kernel/WALT-KERNEL.md` | recipe for our own WALT kernel: sources, rebuild from scratch, checks, updating |
| `kernel/KERNEL-RESEARCH.md` | kernel research, test results and evidence (E404, liyafe, WALT, OPPO) |
| `HISTORY.md` | full log of 2026-10-22/23: roadmap rows with md5s, artifacts, session notes |
| `BUGS-TODO.md` | bug list with causes, tests and fixes; `maintainer/bugs/*.md` offline analyses |
| `CLAUDE.md` / `AGENTS.md` | guidance for AI agents (keep the two consistent) |
| `PORT-MAINTAINER.md` | how to rebase on a new donor build (layer model, erofs/super parameters, checks) |
| `PATCH-INVENTORY.md` | what the port changed vs the donor (S/U/R/M IDs) |
| `PHASE2-ROM-INTEGRATION.md` | design notes for moving runtime fixes into the ROM (done through 2e) |
| `STABILITY-PERF.md` | stability/performance plan, captures D1–D17 |
| `RELEASE-NOTES-beta5.md` | draft release notes |
| `README.md` | the original device audit (kept as record) with the device-changes table |
| `module/README.md` | developer write-up of every fix (display, audio, adaptive colour, pen); the main technical document |
| `HANDOFF*.md`, `perf-test-module/README.md`, `maintainer/jar-edits/REPORT.md` | reference |
| `archive/` | superseded files and old module zips (power-tune, pipa_core 1.11, pipa_port 1.0–1.2) |
