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
| Current release | **beta6** (2026-10-30): `port.sh` default build (last active step 3w) + kernel `walt-r8kpm` |
| Experimental | `beta6-noenc`: beta6 without `/data` encryption, for Linux dual boot (step 3x). Not tested. Clean flash only. |
| Previous release | beta5 (2026-10-25, layer 2v + kernel `walt-r6`) |
| Donor (system side) | OPPO Pad Mini OPD2515 `17.0.0.103(CN01)` (C.06) |
| Device side | pipa `vendor`, `odm` and firmware from the original beta4 release |
| Kernel | Own kernel (Linux 4.19.325), separate repository. `walt-r8kpm`: SukiSU-Ultra v4.3.0, susfs, KPM. |
| Original port | 梦归zzz (beta4) |
| Maintainer | Stefan-Atanasov |

## Download and install

- **Builds:** https://drive.google.com/drive/folders/1Kd7b5rWhc0WC5Io_fCQKGUZ7yncnyech?usp=sharing
- **Support group:** https://t.me/cosforpipa

The package has `FlashLinux.sh` and `FlashWindows.bat`. Read `RELEASE-NOTES.md` and `README-FLASH.txt` in the package
first. The flash script asks one question:

- `y`: clean flash. **All data on the tablet is erased.** Use it when you come from a different ROM.
- Enter: dirty flash ("keep data"). Use it for an update from beta5.

Clean flash from a different ROM: the beta6 flash scripts do not erase `frp`. The screen lock of the old ROM stays
there, and ColorOS cannot set a new PIN ("Screen lock was already changed"). After the clean flash, erase `frp` one
time (your data stays):

```
adb reboot bootloader
fastboot erase frp
fastboot reboot
```

You can also do it before you start the flash script (the tablet is already in fastboot mode): `fastboot erase frp`.

WARNING: An unlocked bootloader is necessary. Make a backup of your data before you flash. The flash scripts also
write the firmware (bootloader, modem, `vbmeta`) in a dirty flash.

WARNING: The first boot takes about 1 minute longer than usual. Do not reboot during this time.

Release paths that are not tested yet for beta6: refer to [KNOWN-ISSUES.md](KNOWN-ISSUES.md), "For maintainers".

## Known issues and bug reports

- Open problems and workarounds: [KNOWN-ISSUES.md](KNOWN-ISSUES.md).
- **Report a bug:** https://docs.google.com/document/d/1nCv448YX7-I_X9f0O-01NkF6mV-mJFdkRph2O8JJM7c/edit?usp=sharing
  Write the build, clean or dirty flash, the steps to reproduce, what you expected and what happened.

## Documents

| Document | Contents |
|---|---|
| [RELEASE-NOTES.md](RELEASE-NOTES.md) | What the current release changes, how to install it, the tests. |
| [KNOWN-ISSUES.md](KNOWN-ISSUES.md) | Open problems, workarounds and status. |
| [BUILD.md](BUILD.md) | Host, inputs, build, flash and roll back the ROM and the kernel. Make a release package. |
| [ARCHITECTURE.md](ARCHITECTURE.md) | How the port is put together: partitions, build steps, `pipa_port` service, helper app, SELinux, kernel. |
| [TESTING.md](TESTING.md) | Check a build: regression check, smoothness test, kernel check, release checklist. |
| [REBASE.md](REBASE.md) | Move the port to a new OPPO donor build. |
| [KERNEL.md](KERNEL.md) | The kernel: parts, branches, settings, build. |
| [DUALBOOT-LINUX.md](DUALBOOT-LINUX.md) | Dual boot with Linux: partitions, encryption, what the flash scripts write. |
| [BUGS.md](BUGS.md) | The maintainer bug list: cause, evidence and next step for each bug. |
| [BLOBS.md](BLOBS.md) | Files that are not in this repository and where to get them. |
| [AGENTS.md](AGENTS.md) | Instructions for AI coding agents (`CLAUDE.md` imports it). |
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

- Report bugs in the bug report document or in the group.
- For a change to the ROM, write a new step file (`maintainer/port/README.md`, "How to add a step") and update the
  documents. Write the documents in ASD-STE100 (Simplified Technical English).
- Do not add proprietary binaries, images or keys to this repository.

## License

The own scripts, sources and documents in this repository are under the Apache License 2.0 ([LICENSE](LICENSE)).

- The license does not cover the proprietary files that the build needs ([BLOBS.md](BLOBS.md)). They belong to their
  owners and are not in this repository.
- The kernel is a separate repository under GPL-2.0.

## Credits

- 梦归zzz: the original ColorOS 17 port for pipa and the `pipa_core` module.
- Stefan-Atanasov: maintenance, beta5 and beta6, ROM fixes, kernel.
- LineageOS, liyafe1997, kvsnr113 (E404 kernel), SukiSU-Ultra, susfs, KernelPatch, OPPO (open-source kernel).
