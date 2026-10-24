# ColorOS 17 port for Xiaomi Pad 6 (pipa)

This repository contains the build scripts, sources and documents for the ColorOS 17 port on the Xiaomi Pad 6
(code name `pipa`, Snapdragon 870). Use it to build the ROM from the original release and an OPPO donor build.

## Overview

| Item | Value |
|---|---|
| Device | Xiaomi Pad 6 (`pipa`), SM8250 / SD870 |
| ROM | ColorOS 17 (Android 17), port release beta5 |
| Donor (system side) | OPPO Pad Mini OPD2515 `17.0.0.103(CN01)` (C.06) |
| Device side | pipa `vendor`, `odm` and firmware from the original beta4 release |
| Kernel | Own kernel `walt-r5` (Linux 4.19), separate repository |
| Original port | 梦归zzz (beta4) |
| Maintainer | Stefan-Atanasov |

## Documents

| Document | Contents |
|---|---|
| [BUILD.md](BUILD.md) | Build, flash and roll back the ROM and the kernel. Make a release package. |
| [ARCHITECTURE.md](ARCHITECTURE.md) | How the port is put together: ROM layers, `pipa_port` service, helper app, SELinux, kernel. |
| [REBASE.md](REBASE.md) | Move the port to a new OPPO donor build. |
| [TESTING.md](TESTING.md) | Check a build: regression check, smoothness test, kernel check. |
| [KERNEL.md](KERNEL.md) | The kernel: parts, branches, settings, build. |
| [KNOWN-ISSUES.md](KNOWN-ISSUES.md) | Open problems, workarounds and status. |
| [RELEASE-NOTES.md](RELEASE-NOTES.md) | What the current release changes, how to install it, known issues. |
| [BLOBS.md](BLOBS.md) | Files that are not in this repository and where to get them. |

## Repository contents

| Folder | Contents |
|---|---|
| `maintainer/` | Build steps (`build_beta5*.sh`, `build_port.sh`), flash scripts, release script, test and analysis tools. |
| `maintainer/kernel/` | Kernel tree setup, build, boot image packing and flash scripts. |
| `maintainer/perfetto/` | Frame timing trace and analysis tools. |
| `maintainer/uifirst-policy/` | SELinux policy for the UI First kernel nodes. |
| `port-rom/` | The `pipa_port` service (scripts, init file, settings) that the ROM includes. |
| `helper/` | Source of the pipa helper app. |
| `module/` | Tools and files of the older module. The baked build step uses them. |

## Not in this repository

- Proprietary binaries. [BLOBS.md](BLOBS.md) lists them and their source.
- Images, the original beta4 release and the donor files.
- The signing key of the pipa helper app. `helper/build.sh` makes a new key on the first build.

## Kernel

The kernel source is in https://github.com/Stefan-Atanasov/kernel_xiaomi_pipa_cos17 (branch `oppo`).
Refer to [KERNEL.md](KERNEL.md).

## Credits

- 梦归zzz: the original ColorOS 17 port for pipa and the `pipa_core` module.
- Stefan-Atanasov: maintenance, beta5 rebase, ROM fixes, kernel.
- LineageOS, liyafe1997, kvsnr113 (E404 kernel), SukiSU-Ultra, susfs, OPPO (open-source kernel).
