# ColorOS 17 port for Xiaomi Pad 6 (pipa)

This repository contains the build scripts, sources and documents for the ColorOS 17 port on the Xiaomi Pad 6
(code name `pipa`, Snapdragon 870). The scripts make the ROM from the original beta4 release and an OPPO donor
build. The main build is one command, `maintainer/port/port.sh`.

> Most of the maintainer work (builds, fixes, documents) was done with an AI assistant (Claude) and tested on one
> tablet. Back up first, and report problems in the group.

## Overview

| Item | Value |
|---|---|
| Device | Xiaomi Pad 6 (`pipa`), SM8250 / SD870. Tested on one 8 GB tablet. Other models are not supported. |
| ROM | ColorOS 17 (Android 17) |
| Current release | **v10.1** (2026-11-27, over the air from v10 in Pipa Helper > System > Updates: full OPPO tablet multi-window, up to 5 floating windows and the four-finger gestures; ROM pt181, step 9v; no new PC package: clean installs flash v10, then update). **v10** (2026-11-27: updates without a PC in Pipa Helper, smoother unlock and wake, up to 4 floating windows, no more warm tablet with a second user, pen buttons in Notein and StarNote, hotspot 5 GHz and dual Wi-Fi; update from v9, v9.1, v9.2 or v9.3 with "keep data". v10 is the base for the over-the-air updates): `port.sh` default build (last step 9u, pt180) + kernel `walt-hi17` (SukiSU Nova 3.0.0), Pipa Helper 3.7. Download: https://sourceforge.net/projects/pipa-cos17-port/files/Releases/ (also Google Drive, Pixeldrain and Gofile: [DOWNLOADS.md](DOWNLOADS.md)). Notes: [RELEASE-NOTES.md](RELEASE-NOTES.md), changelog since beta7.1: [CHANGELOG.md](CHANGELOG.md). |
| Next | No build in progress. Ideas and open items: WebRTC noise suppression for calls, dock-drag and setup-wizard layout items (see [BUGS.md](BUGS.md)). |
| Experimental | `v9.3-noenc` (2026-11-23, based on v9.3; there is no v10-noenc): v9.3 without `/data` encryption, for Linux dual boot (step 3x). Not booted by the maintainer. Clean flash only (`2`, then `ERASE`). In the Drive folder. |
| Previous releases | v9.3 (2026-11-21, pt151 + `walt-hi15`, pen buttons in StarNotes, 32-bit apps), v9.2 (2026-11-21, pt150 + `walt-hi13`), v9.1 (2026-11-19, pt132 + `walt-hi9`, audio hotfix), v9 (2026-11-18, pt128 + `walt-hi9`, first stable), beta7.2 (2026-11-06, pt68 + `walt-r17`, root SukiSU-Ultra v4.3.0-r1), beta7.1 (2026-11-05), beta6 (2026-10-30). beta7 was withdrawn (grey screen after a clean flash). beta 8 was a tester zip only (pt81 + r17), never a release. |
| Donor (system side) | OPPO Pad Mini OPD2515 `17.0.0.104(CN01)` (C.07, security patch 2026-09-01) |
| Device side | pipa `vendor`, `odm` and firmware from the original beta4 release |
| Kernel | Own kernel (Linux 4.19.325), separate repository. `walt-hi17`: SukiSU Nova 3.0.0 (builtin), susfs, OPPO memory (hybridswap), touch and display fixes (hi10: display clock for every refresh rate change, no white flash; hi11: keyboard Caps Lock LED; hi14/hi15: pen buttons in StarNotes and drawing apps; hi16: pen buttons in Notein and StarNote as on HyperOS; hi17: no short stutter after a wake). |
| Original port | 梦归zzz (beta4) |
| Maintainer | Stefan-Atanasov |

**Porting to another device?** Start with [PORTING-GUIDE.md](PORTING-GUIDE.md) (model, tools, pipeline, order of work, gotchas, working with an AI agent). To rebuild the whole setup on a new PC, step by step (also for a local AI model), and to make the beta4 base from stock: [HANDOFF-FROM-ZERO.md](HANDOFF-FROM-ZERO.md).

## Download and install

- **All links in one page (to share):** [DOWNLOADS.md](DOWNLOADS.md)
- **Builds (SourceForge, recommended):** https://sourceforge.net/projects/pipa-cos17-port/files/Releases/ (one folder per release, e.g. `v10/`)
- **v10 on Pixeldrain (fast):** https://pixeldrain.com/u/7igGZUfx
- **v10 on Gofile (fast, temporary):** https://gofile.io/d/BXHw34tc (Gofile deletes files after some time without downloads: if the link has expired, use SourceForge or Drive)
- **v9.3-noenc on Gofile (experimental, no /data encryption, clean install only):** https://gofile.io/d/Fqn9Po3L
- **Builds (Google Drive mirror):** https://drive.google.com/drive/folders/1Kd7b5rWhc0WC5Io_fCQKGUZ7yncnyech?usp=sharing
- **Modules: none needed.** v10 has everything built in: root (SukiSU Nova), the Dolby speaker EQ, pen input always on for pens without Bluetooth (Pipa Helper > Pen) and all fixes. Do not install old pipa modules or performance modules (Uperf and similar): they fight the ColorOS settings, and we cannot help with bugs that they cause. **Optional:** `pipa-susfs-v1.0.zip` (in the package `extras/` and in the Drive folder `modules/`): root hiding with the kernel susfs (hides `/data/adb`, module mounts and SELinux log traces from apps). The Drive modules `pipa-dolby-speaker-eq-module` and `pipa-pen-always-on-module` are only for beta7.x; the EQ module refuses to install on newer builds.
- **Support group:** https://t.me/cosforpipa

Screenshots of the ROM and Pipa Helper (v9.2): https://drive.google.com/drive/folders/1StUhuz_dL07ydvdHJ1SriYAR-_zObTJ5

The package `ColorOS17-Port-pipa-v10-20261127.7z` has `FlashLinux.sh`, `FlashWindows.bat` and `FlashMac.sh` (macOS; a user flashed with it successfully, 2026-11-20), and `extras/pipa-susfs-v1.0.zip`. Read `RELEASE-NOTES.md` and `README-FLASH.txt` in the package
first. The flash script asks one question:

- `1` (Update): keep your apps and data. Use it for an update from an older version of this port (v9.x, beta7.2,
  beta7.1, beta7, beta6).
- `2` (Clean install): **all data on the tablet is erased** (the script asks you to type `ERASE`). Use it for the first
  install and when you come from a different ROM (HyperOS, crDroid, LineageOS, other ports). You do not need to flash
  HyperOS first: the package has the full HyperOS 2 firmware for pipa.

The same choice is in `FlashLinux.sh`, `FlashMac.sh` and `FlashWindows.bat`.

Clean flash from a different ROM: the flash scripts also erase `frp` (since 2026-10-30, 17:00). If `frp` is not
erased, the screen lock of the old ROM stays there, and ColorOS cannot set a new PIN ("Screen lock was already
changed"). The beta7 and beta7.1 scripts erase `frp`. If you used an older script for a clean flash, erase `frp` one time
(your data stays):

```
adb reboot bootloader
fastboot erase frp
fastboot reboot
```

You can also do it before you start the flash script (the tablet is already in fastboot mode): `fastboot erase frp`.

WARNING: An unlocked bootloader is necessary. Make a backup of your data before you flash. The flash scripts also
write the firmware (bootloader, modem, `vbmeta`) in a dirty flash.

WARNING: The first boot takes about 1 minute longer than usual. Do not reboot during this time.

Release paths that are tested for v10 (clean install, update in Pipa Helper) and the paths that are not tested: refer to
[KNOWN-ISSUES.md](KNOWN-ISSUES.md), "For maintainers".

## Known issues and bug reports

- Open problems and workarounds: [KNOWN-ISSUES.md](KNOWN-ISSUES.md).
- **Report a bug:** https://github.com/Stefan-Atanasov/pipa-cos17-port/issues/new/choose (GitHub Issues; Pipa Helper > System > Report a bug opens the same page). Right after the
  bug, use Pipa Helper > System > **Collect logs** and attach the file. The form asks for the build, the install type,
  the steps, and what you expected and what happened.

## Documents

For users:

| Document | Contents |
|---|---|
| [DOWNLOADS.md](DOWNLOADS.md) | All download links in one page: ROM builds, md5, extras, help. |
| [RELEASE-NOTES.md](RELEASE-NOTES.md) | What the current release changes, how to install it, the tests. |
| [TEST-NOTES.md](TEST-NOTES.md) | Notes for testers: test builds (none at the moment), updates in Pipa Helper, how to report a problem. |
| [KNOWN-ISSUES.md](KNOWN-ISSUES.md) | Open problems, workarounds and status. |
| [CHANGELOG.md](CHANGELOG.md) | All changes since beta7.1, in short. |
| [FLASH-WITHOUT-PC.md](FLASH-WITHOUT-PC.md) | Flash from a second Android phone (Bugjaeger) instead of a PC. Not tested by the maintainer. |
| [DUALBOOT-LINUX.md](DUALBOOT-LINUX.md) | Dual boot with Linux: partitions, encryption, what the flash scripts write. |
| [CREDITS.md](CREDITS.md) | Where each part and each tweak of the port comes from; people and projects. |

For developers and co-maintainers:

| Document | Contents |
|---|---|
| [BUILD.md](BUILD.md) | Host, inputs, build, flash and roll back the ROM and the kernel. Make a release package. |
| [ARCHITECTURE.md](ARCHITECTURE.md) | How the port is put together: partitions, build steps, `pipa_port` service, helper app, SELinux, kernel. |
| [ROM-BACKGROUND.md](ROM-BACKGROUND.md) | Why the ROM code does what it does. |
| [KERNEL.md](KERNEL.md) | The kernel: parts, branches, settings, build. |
| [TESTING.md](TESTING.md) | Check a build: regression check, smoothness test, kernel check, release checklist. |
| [REBASE.md](REBASE.md) | Move the port to a new OPPO donor build. |
| [GOTCHAS.md](GOTCHAS.md) | Traps found during the work and how to avoid them. |
| [BUGS.md](BUGS.md) | The maintainer bug list: cause, evidence and next step for each bug. |
| [BLOBS.md](BLOBS.md) | Files that are not in this repository and where to get them. |
| [PORTING-GUIDE.md](PORTING-GUIDE.md) | Port ColorOS to another device: model, tools, pipeline, order of work. |
| [HANDOFF-FROM-ZERO.md](HANDOFF-FROM-ZERO.md) | Rebuild the whole setup on a new PC, step by step. |
| [AGENTS.md](AGENTS.md) | Instructions for AI coding agents (`CLAUDE.md` imports it; more in [CLAUDE-REFERENCE.md](CLAUDE-REFERENCE.md)). |
| `maintainer/port/README.md` | Full description of `port.sh`, the step list and how to add a step. |
| `maintainer/port/NOTES-3k-odm-c06.md` | The optional step 3k. |
| `maintainer/bugs/` | Old offline analyses of bugs (historical). |
| `module/README.md` | The old module and the tools that the build still uses (historical). |

## Repository contents

| Folder | Contents |
|---|---|
| `maintainer/` | Flash scripts, release script, test and analysis tools. The old layer scripts (`build_beta5*.sh`, `build_port.sh`) are history. |
| `maintainer/port/` | The main ROM build: `port.sh` and the steps in `steps/`. |
| `maintainer/kernel/` | Kernel tree setup, build, boot image packing and flash scripts. |
| `maintainer/perfetto/` | Frame timing trace and analysis tools. |
| `maintainer/sepolicy/`, `maintainer/uifirst-policy/` | SELinux rules of the `pipa_port` domain and the UI First kernel nodes. |
| `port-rom/` | The `pipa_port` service (scripts, init file, settings) that the ROM includes. |
| `helper/` | Source of the pipa helper app. |
| `port-module/src/` | Source of the face HAL add-ons (`libpipa_facecrop.so`, `libpipa_eyeguard.so`). |
| `module/` | Tools and files of the older module. The baked build step uses them. |

## Not in this repository

- Proprietary binaries. [BLOBS.md](BLOBS.md) lists them and their source.
- Images, the original beta4 release and the donor files. [BUILD.md](BUILD.md), section 1.3, tells how to get and
  prepare them.
- The `port-overlay` folder. It holds the beta4 files that the port edit list needs. You must make it yourself from
  the beta4 release ([BUILD.md](BUILD.md), section 1.3).
- The signing key of the pipa helper app. `helper/build.sh` makes a new key on the first build.

NOTE: Without these files, the build does not run.

## Kernel

The kernel source is in https://github.com/Stefan-Atanasov/kernel_xiaomi_pipa_cos17 (branch `oppo`).
Refer to [KERNEL.md](KERNEL.md).

## Contributing

- Report bugs in GitHub Issues (section "Known issues and bug reports") or in the group.
- For a change to the ROM, write a new step file (`maintainer/port/README.md`, "How to add a step") and update the
  documents. Write the documents in ASD-STE100 (Simplified Technical English).
- Do not add proprietary binaries, images or keys to this repository.

## License

The own scripts, sources and documents in this repository are under the Apache License 2.0 ([LICENSE](LICENSE)).

- The license does not cover the proprietary files that the build needs ([BLOBS.md](BLOBS.md)). They belong to their
  owners and are not in this repository.
- The kernel is a separate repository under GPL-2.0.

## Credits

- 梦归zzz ([t.me/joeyzhu1](https://t.me/joeyzhu1)): the original ColorOS 17 port for pipa (beta4) and the `pipa_core` module.
- Stefan-Atanasov: maintenance since beta5, ROM fixes, kernel, pipa helper.
- suga ([t.me/Megalodonzs](https://t.me/Megalodonzs)), LineageOS, liyafe1997, kvsnr113 (E404R), OPPO, Xiaomi, SukiSU Nova, susfs and others.

Where each part and each tweak comes from: [CREDITS.md](CREDITS.md).
