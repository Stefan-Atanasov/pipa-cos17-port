# Porting guide: ColorOS on a non-OPPO device (handoff for a person or an AI agent)

This document tells how the ColorOS 17 port for the Xiaomi Pad 6 (`pipa`, SM8250) is made, in a form that you can
use for another device. It is a summary of what worked and what failed from October to November 2026. Read it
first, then the detail documents that each section names. Most of the maintainer work was done by an AI agent
(Claude Code) together with the maintainer, on one real tablet.

## 1. The model of a port

A port joins two halves that come from different ROMs:

| Half | Partitions | Source on pipa | Rule |
|---|---|---|---|
| Device side | firmware, `vendor`, `odm`, `vendor_boot`, `dtbo`, kernel | a working base for the device (here the beta4 port by 梦归zzz, which has the HyperOS vendor) | Change as little as possible. Pin the images by md5. |
| System side | `system`, `system_ext`, `product`, OPPO `my_*` partitions | an OPPO donor OTA (here OPD2515 OPPO Pad Mini, `17.0.0.104(CN01)`) | Take it as a whole. Fix it with small, scripted edits. |

Everything you add on top is one of these:

- **Build steps:** scripts that edit the extracted tree before the images are made (section 4).
- **A runtime service:** a shell service in the ROM with its own SELinux domain. It does the work that must happen on
  the device: hardware switches, settings once per install, app installs, watchdogs. On pipa: `pipa_port`
  (`port-rom/`).
- **A helper app:** a persistent priv-app for work that needs an app context: Quick Settings tiles, audio effect
  handles, the assistant service. On pipa: `helper/`.
- **The kernel:** your own kernel tree when the base kernel lacks what the donor userspace expects (OPPO nodes,
  KernelSU, drivers). On pipa: a separate repository (`KERNEL.md`).

The guiding rule: **restore the stock OPPO behaviour**. When something does not work, find what the OPPO userspace
expects (a node, a property, a HAL, a config) and give it that. Do not add workarounds that only hide the symptom.

## 2. Choose the donor and the base

- **Donor:** same Android version as your target, and the closest OPPO/OnePlus device class (a tablet donor for a
  tablet: layouts, multi-window, pen code). A CN build has more OPPO features; a global build has Google apps.
  Query OPPO's OTA servers for full OTA zips (on pipa: the OPlus-Tracker tool). Keep the zip and its sha256.
- **Base for the device side:** a working ROM for your device whose vendor matches its kernel and firmware (stock
  firmware, HyperOS/MIUI vendor, or an earlier port). If a port exists already, start from it: it has solved the
  first boot.
- Check the SoC difference. The donor's system code calls OPPO HALs and kernel nodes that a Xiaomi (or other)
  vendor does not have. Each missing one is a hang, a crash or a dead feature (section 5).

## 3. Host, tools and the device

- **Host:** Linux. 100 GB+ free SSD for builds (one build tree + images is about 30 GB; `super.img` about 7 GB).
  A second disk for references, traces and old builds. A full SSD silently truncates `super.img`: stop below 20 GB.
- **Tools** (versions used on pipa, `BUILD.md` section 1.1): `erofs-utils` 1.9.x, `android-tools` (`lpmake`,
  `lpunpack`, `simg2img`, `adb`, `fastboot`), Python 3, `attr` (`getfattr`/`setfattr`), `rsync`, `7z`, OpenJDK 21,
  Android SDK build-tools 37.0.0 + platform android-37.0 (`aapt2`, `d8`, `zipalign`, `apksigner`), smali/baksmali 2.5.2
  (run with `-j 1`), apktool, `jadx` (to read code), NDK (native helpers), AOSP clang (kernel).
- **The test device:** unlocked bootloader, a `vbmeta` with verity and verification off (flags 3), a recovery with
  root ADB (TWRP) for rescue, root in Android (KernelSU / SukiSU) for live tests. USB ADB, and the lock-screen PIN
  stored only in a private file on the host.
- **References:** extract each related ROM once and keep it: stock device ROM (HyperOS), the donor, other ports
  (PixelOS, other ColorOS ports). Most fixes come from comparing what stock does.

## 4. The build pipeline

`maintainer/port/port.sh` makes `super.img` in one run (`ARCHITECTURE.md` section 2, `maintainer/port/README.md`):

1. **Preflight:** tools, inputs, md5 of the pinned device images, free space (`--check`).
2. **Extract** the donor partitions and the pinned base `vendor`/`odm` as root with
   `fsck.erofs --extract=<dir> --xattrs --preserve` (the images are EROFS, not ext4). Every file must keep its
   `security.selinux` label.
3. **Run the steps** `steps/NN-<id>-<name>.sh` in order. Each step is one fix with a header comment (why, which bug).
   A step edits files in place (`cat new > old`, never `sed -i`: that drops the label), finds its edit by a pattern
   that must match exactly once, and stops the build if the pattern is missing. A step that changes an app or a jar
   sets the layer property (`set_layer`), so the device clears its package cache.
4. **Check labels** of all files, then **pack**: `mkfs.erofs -zlz4hc` per partition and `lpmake` for `super.img`.
5. **Flash only `super`** for tests (`maintainer/flash_super.sh <name>`, md5 check, no wipe). A release package
   flashes firmware + kernel + `super` and can wipe (`maintainer/build_release.sh`).

Rules that saved time:

- **A new fix is a new step file.** Never edit the images by hand. The whole ROM is reproducible from git.
- **Pin the base images and the donor by hash.** A new donor goes through a check script (`REBASE.md`).
- **Name each test build** (`pt1`, `pt2`, ...) and keep a list of what it contains and its md5.

## 5. Order of work

Work in this order. Do not start the next phase while the one before is unstable.

### 5.1 First boot

Typical blockers, with the evidence to collect:

| Symptom | Cause found on pipa | How to see it |
|---|---|---|
| Boot hangs, watchdog reset | `system_server` or SurfaceFlinger calls `waitForService` for an OPPO HAL that the vendor lacks | `/data/anr/traces_SystemServer_WDT*`, `/sys/fs/pstore/`, `debuggerd -b <pid>` |
| `servicemanager` stops at boot | one service name has two labels in the `service_contexts` files | `logcat -b all` of servicemanager; check all five files |
| Boot loop after a jar edit | prebuilt boot image no longer matches `framework.jar` | artd log; remove the whole prebuilt boot image, odrefresh rebuilds it |
| Grey screen after a clean flash | the setup wizard needs an app that you removed | dropbox `system_app_crash` (TWRP can read it) |

Patch `waitForService` calls to `checkService` (binary patch by pattern) or provide the service. A dirty flash
never runs the setup wizard: **test every release with a clean flash**.

### 5.2 SELinux

- Keep the device enforcing. Your service gets its own domain with rules in a CIL file.
- Find rules from a full capture: `setprop persist.logd.audit.rate 2000`, reboot, use the feature, list the denials,
  then reset the property. init property checks are silent: test property rules with a boot.
- **Compile every policy change on the device** with `/system/bin/secilc` and all policy inputs before you build.
- Never change policy live on a running device (on pipa a live patch hung the big cores).

### 5.3 Hardware

Go through each component and compare with the stock ROM: display and refresh rate, touch, pen, audio (HAL,
effects, mic, echo canceller), sensors, camera, face unlock, Wi-Fi/Bluetooth, charging, USB-C (monitor, audio
accessory), keyboard cover. Patterns found on pipa:

- **Vendor overlays are not in the port.** Values the stock ROM set in `vendor/overlay` (for example
  `config_useDevInputEventForAudioJack`) must come back as your own static overlay.
- **OPPO sensor type numbers collide with the device's own private types.** A wrong match can run an expensive
  algorithm on the sensor hub all the time (battery drain). Check `dumpsys sensorservice` and SLPI sleep stats.
- **SurfaceFlinger properties** go in `product/etc/build.prop` (the vendor build.prop loads late and overrides).
- **Libraries:** never rename a vendor HAL library (other code loads it by name); keep sets of gralloc/mapper
  libraries together.
- **Kernel:** OPPO userspace reads OPPO kernel nodes (`/proc/oplus_*`, touchpanel nodes, memory nodes). Port the
  driver from an OPPO kernel of the same SoC when the feature matters; check first what the consumer really expects
  (an empty or absent node can be the correct answer).

### 5.4 OPPO features and performance

Turn on what OPPO's own firmware would set: app features (`com.oplus.app-features.xml`), refresh-rate rules, memory
setup (zram, swappiness, RAM expansion from OPPO's scripts, not from vendor scripts), animation and blur tiers, game
services. Measure every performance change: same boot A/B, FrameTimeline traces (perfetto), several runs, one change
at a time. Measure battery with a night drain (`dumpsys batterystats`).

### 5.5 Release

Device check script (`maintainer/device_check.sh`), clean flash test, release notes and changelog, package
(firmware + kernel + `super` + flash scripts for Linux/Windows/macOS), upload, public repo sync, known issues list.

## 6. Techniques

| Need | Technique | Example on pipa |
|---|---|---|
| Change a framework config value | static RRO overlay on `android` in `product/overlay` | step 6i, `maintainer/overlays/framework` |
| Change code in a system app signed with the platform key | patch the dex **in place with the same size**, keep the signature block, delete `oat/` | `maintainer/ipe-fluid/patch_ipemanager.py`, `maintainer/displaysize/` |
| Change a framework jar | smali/baksmali edit, rebuild the jar, then remove the prebuilt boot image | steps 3o, 4h, 4z |
| Stop an app update from replacing a patched app | raise its versionCode in the ROM copy | step 7l |
| Run code on the device | init service in its own SELinux domain; stdin/stdout/stderr of `cmd`/`settings`/`am` to `/dev/null` | `port-rom/pipa_port.rc`, `service.sh` |
| Per-user switch | helper Quick Settings tile writes a global setting; the service applies it | Logs tile, Live blur tile |
| Test a script or an APK without a build | bind-mount the new file over the ROM file (init mount namespace), restart the user; a reboot removes it | `GOTCHAS.md` |
| Optional extras for users | a KernelSU/Magisk module that sets a service override | `module/pen-always-on` |

## 7. Gotchas that cost the most time

1. A dirty flash hides setup-wizard crashes. Clean-flash each release.
2. `sed -i` on a ROM file drops its SELinux label and makes a new inode (a bind mount stays on the old file).
3. `dump.erofs --ls` on a missing path returns exit 0: check its output.
4. Boot image packing tools that change the header patch level give a silent black screen. Use one known-good tool.
5. `pgrep -f`/`pkill -f <pattern>` from a shell finds its own command line and kills your shell.
6. `setprop persist.x ""` does not delete a property: it stores an empty value that hides the ROM default.
7. A UI test that taps fixed screen positions breaks on another home-screen layout (it moved the user's icons).
8. Apps freeze in the background: thaw them before `dumpsys gfxinfo`. `monkey` injects a rotation: use `am start`.
9. Many ColorOS components read a property only when they start (SystemUI blur, animation tier): restart them
   or reboot after a change before you judge it.
10. OPPO cloud configs (RUS) and system app updates (SOTA) do not arrive on a port: the server does not know the
    product name, and SOTA stops when verified boot is off.

The full list is `GOTCHAS.md` (with the date and the evidence of each entry).

## 8. Working with an AI agent

What made the AI-assisted work reliable on pipa:

- **Instruction file at the repo root** (`AGENTS.md` / `CLAUDE.md`): what the folder is, read order, device access,
  hard rules (ask before a wipe; never run the wipe script; never store the PIN; never commit the signing key;
  never replace the KernelSU daemon), and an index of gotchas.
- **State documents that the agent keeps current:** a short status page (`MAINTAINER-STATUS.md`), a "next session"
  prompt with the tablet state, the rollback and the open items, a device-state log of every live change, a bug
  table with cause, evidence and status, and a work log (`HISTORY.md`). A new session reads these instead of
  guessing.
- **Skills / checklists** for repeated work: ROM build, kernel build, tablet test, tester bug triage.
- **One change per test build**, a rollback named before each flash, and a record of each flash.
- **Verify before claiming.** A screenshot or a log line, not "it should work". Check that a capture really shows
  what you think (the panel was open, the app was in front, the video was playing).
- **Delegate reading, not decisions:** large decompiles and log comparisons can go to a sub-agent; the main agent
  checks the result before acting.
- **Ask the user** for taste decisions (density, animations, blur, names) and before outward actions (publish,
  upload, push).

## 9. Where to read next in this repository

| Topic | Document |
|---|---|
| Build, flash, roll back | `BUILD.md` |
| ROM layers, service, helper, SELinux, every step | `ARCHITECTURE.md` |
| New donor version | `REBASE.md` |
| Kernel | `KERNEL.md` (and the kernel repository) |
| Tests | `TESTING.md` |
| All gotchas with evidence | `GOTCHAS.md` |
| Rules for agents in this repo | `AGENTS.md` |
| Bugs and their analyses | `BUGS.md`, `maintainer/bugs/` |
| Why the ROM code is as it is | `ROM-BACKGROUND.md` |
