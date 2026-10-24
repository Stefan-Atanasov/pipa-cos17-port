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
| `maintainer/` | Build steps (`build_beta5*.sh`, `build_port.sh`), flash, release, test and analysis scripts |
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
  `PIPA_OWNER` (user:group of the build output). The layer scripts run as root. Give the variables through sudo:
  `sudo PIPA_ROOT=$PWD PIPA_OWNER=$USER:$USER sh COS17/maintainer/build_port.sh ...`.
- Host tools: `erofs-utils`, `lpmake`/`lpunpack`, `fastboot`/`adb`, python3, JDK 21 + Android SDK build-tools 37
  (helper), NDK 30 (face crop add-on), AOSP clang r547379 (kernel).
- The partition images are **EROFS**, not ext4. Use `dump.erofs --ls|--cat --path=<p> <img>` and
  `fsck.erofs --extract=<dir> --xattrs --preserve <img>` (as root, to keep the SELinux labels).
- Device access: `adb -s <serial> shell "su -c '<cmd>'"` (root through SukiSU / KernelSU). Many scripts read the
  `ADB` variable, for example `ADB="adb -s <serial>" sh maintainer/device_check.sh`.

## How to change the ROM

- Each change is a new **layer script** on top of the newest step (now `build_beta5_2o.sh` → `build_beta5_2p.sh`).
  The procedure is in [BUILD.md](BUILD.md) "Add a ROM layer".
- Only replace files in the copied tree. Write in place with `cat new > old`, so that the owner, the mode and the
  SELinux xattr stay. Each file must have `security.selinux` (`tree_manifest.py` checks it).
- Each text edit must find its anchor exactly one time. If the anchor is not found, stop. Do not guess.
- Add the new name and its md5 to `maintainer/flash_super.sh`, and the step to `STEPS` in `maintainer/build_port.sh`.
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
  `Failed transaction (2147483646)` and no log. In `pipa_port` scripts, redirect all three to `/dev/null`.
- **SELinux denials do not go to dmesg or logcat** (the kernel has no audit core). Use `maintainer/avc_trace.sh start`,
  use the feature, then `avc_trace.sh dump <label>`. The `pipa_port` domain is permissive until its rules are
  collected.
- Before you build a policy change, compile it on the tablet with `/system/bin/secilc` and all 8 policy inputs.
- **Donor boot hangs.** C.06 waits for HALs that pipa does not have (`waitForService` in `oplus-services.jar` and in
  two QSPM libs). Each one stops system_server until the watchdog panics the device. On a new donor, scan changed libs
  for new `waitForService` imports before you flash. A bootloop: read `/data/anr/traces_SystemServer_WDT*` and
  `/sys/fs/pstore/`.
- After a flash, `/data` uses f2fs `checkpoint=disable` until a boot completes. In a bootloop, the next reboot removes
  each write to `/data`. `vdc checkpoint commitChanges` keeps them.
- **SurfaceFlinger properties go into `product/etc/build.prop`.** pipa's vendor build.prop loads after system and
  system_ext and sets HyperOS values.
- **Kernel images: pack only with `maintainer/kernel/mkboot.sh`.** `magiskboot` repack changes the header patch level,
  and the bootloader then refuses the kernel with no message (black screen). For `fastboot boot` tests, use trimmed
  images (`TRIM=1`).
- **Never replace `/data/adb/ksud`.** Update it only with a kernel that agrees with it, through the SukiSU manager.
- **If the device does not boot:** the boot image has TWRP (Power + Volume up). TWRP ADB has root and a decrypted
  `/data`.
- Do not kill `system_server` to apply framework changes (it causes a warm-reset crash). Reboot.
- **Smoothness:** measure with `maintainer/perfetto/traced_heavy.sh <label>` (FrameTimeline), not only gfxinfo. Wait
  60 s after unlock and do 2 runs or more. `input tap` goes around the kernel input handlers; use real touch through
  `maintainer/kgest`.
