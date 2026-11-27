# CLAUDE.md reference (text tightened out of CLAUDE.md on 2026-11-14, verbatim, original order)

This folder is the maintainer workspace for the **ColorOS 17 port for the Xiaomi Pad 6 (`pipa`)**. It is a local git
repository (no remote, no blobs): commit each change. The original port is beta4 (2026-10-17) by 梦归zzz. Since 2026-10-22 the user (Stefan) maintains the
port. The tablet runs **pt180 + walt-hi17 (v10, 2026-11-27; see MAINTAINER-STATUS)**; before: **pt81 (2026-11-07)** = beta7.2 (pt68) + 5z stock libhwdap + 6a measured speaker EQ + 6b sound effects page + 6c no DSP voice wake-up + Ultra touch (touch shim node 26) + helper 1.6 (Dolby/MiSound per output). Last release: **v10 = pt180 + walt-hi17** (2026-11-27; v9.3 = pt151 + walt-hi15). First stable: **v9 = pt128 + walt-hi9** (2026-11-19; SukiSU Nova 3.0.0, helper 2.2). Before: **beta7.2 = pt68** (2026-11-06). Before: **pt63 = beta7.1** (clean flash of pt61 2026-11-05, then dirty pt62/pt63; `port.sh` up to 5v on donor **C.07** 17.0.0.104; 2026-11-04/05: 5a-5e USB-C monitor + PC Extend, 5f-5k SELinux clean-up + Bedtime fix, 5g blur at animation tier 3, 5l game thermal profile, 5m SukiSU manager r1, 5n face worker guard, 5r OShare store guard, 5t blur switches/defaults + SukiSU retry, 5u Play Store/Gboard/Google app + Fast/blur once on every install, 5v no charging-limit pop-up) + kernel **walt-r17** (SukiSU-Ultra v4.3.0-r1, KSU 41140; that was the kernel of beta7.1 to beta7.2). Earlier public releases: **beta7.2** (pt68 + walt-r17, 2026-11-06; no noenc package) and **beta7.1** (pt63 + walt-r17, 2026-11-05; also `beta7.1-noenc`). "beta 8" (pt81 + r17) was a tester zip only. beta7 (pt56) was withdrawn: grey screen after a clean flash. Before: beta6 = 3w + walt-r8kpm.
| `maintainer/` | Build, flash, test and publish scripts. **Main build since 2026-10-29: `maintainer/port/port.sh`** (one tree, steps in `maintainer/port/steps/`). The old ROM layers are `build_beta5*.sh`. |
| `port-overlay/` | Frozen files from beta4 that the base step needs (`PORT_OVERLAY_SRC`). Private blobs: never publish. |
| `helper/` | The pipa helper app, version 3.7 in v10 (persistent priv-app: Dolby keeper, pen pill, lock with cover, Logs, Dolby, Hotspot and Extra dim tiles, Collect logs, Updates, assistant service). |
| `kernel/` | Kernel docs (`WALT-KERNEL.md`, `KERNEL-RESEARCH.md`), `walt-own.bundle`, partition and SukiSU backups. |
| `docs/` | Public docs for the GitHub port repo (STE100, no session history). |
| `notes/` | Old notes from the beta4 audit and the module period. They are records, not instructions. |
| `module/` | Source of the old `pipa_cos17_power_tune` module (up to beta5-2d). `module/README.md` explains each fix; `module/tools/` makes the patched display, audio and framework files that the ROM build uses. |
| `port-module/`, `susfs-module/` | `pipa_port` as a KernelSU module (old, v1.3), and the optional root-hiding module. |
| `ColorOS17 Port for pipa-beta4-20261017/` | The extracted beta4 release (firmware, `super.img`, flash scripts). Keep it. Its `.7z` is the source of truth. |
| `work/parts/*_b.img` | `lpunpack` output of the beta4 super. Only slot **B** has content. |
| `archive/` | Superseded files and old module zips. |
- ADB uses authorisation (`ro.adb.secure=1`). This PC's key is trusted.
  password. Type it
  through adb stdin (`echo 'input text ...' | adb shell`), not as a command argument: adbd logs each command line in
  logcat, and log captures then contain the PIN (2026-11-05). The host has passwordless sudo.
- After a reboot, unlock the tablet one time, so that apps run normally.
- Live-only changes (kill, SIGSTOP, `setprop ctl.*`) stop at the next reboot.
The partition images are **EROFS**, not ext4. `debugfs` and `mount -t ext4` do not work. Use:
- **2026-11-05 clean-up:** the HDD copies of beta5-2l…3j, beta6/beta6-noenc images, pt3-pt50, pt56-madb, smooth, tmp-61, tmp-desk and the old scratch archive are deleted (688 GB free). Links below that name them are gone; rebuild an image from git if needed.
- Large data that does not change is on the 1 TB HDD `/mnt/reference` (ext4, fstab by UUID with `nofail`). Symlinks
  keep all paths in the docs correct: `../reference`, `../donor`, `../Pixelos`, the iqraOS folders, `../New Folder`,
  `COS17/work`, the extracted beta4 release and `../port-work/roundtrip/img`. Since 2026-10-25 also (links in
  `port-work/`): `traces`, `beta5-2l` … `beta5-2s`, `kernel/liyafe`, `kernel/e404-own`, `donor-c06-vendor`; since 2026-10-30 also `pt12`, `pt13`, `pt14`, `pt18`, `beta5-2v`, `beta5-3g`, `beta5-3j`, `beta6-noenc`, `roundtrip`; since 2026-11-05 also `pt47`-`pt50`, old boot images (`kernel/bootimg/` links to `kernel/bootimg-old`), the beta6 7z (`release-old`) and old session scratch (`tmp-scratch-archive-20261105`; the HDD is 97 % full: 28 GB free); since 2026-11-04 also `pt38`, `pt40`, `pt41`, `pt42`, `kernel/walt-dptest`, `smooth`, `tmp-61`, `tmp-desk`, `release/` beta7-rc1 and beta6-noenc; old
  packages are in `/mnt/reference/pipa/port-work/release-old/`.
- If the HDD is not mounted, these paths are broken and builds fail. Before a build, do `mountpoint /mnt/reference`.
- `port-work/` (build trees, images) is on the NVMe, for speed and btrfs reflinks. `COS17/work/parts/` and
  `donor/OPD2515_11.C.07/{img/,*.zip}` are also real folders on the SSD (the HDD has a second copy).
- The HDD head parking is set by `69-hdparm.rules` (`hdparm -B 254 -S 0`).
- Extracted reference ROMs are in `../reference/<rom>/<partition>/`. Compare these. Do not extract again:
  `hyperos1-stock/` (HyperOS `OS1.0.15.0.UMZMIXM`), `iqraos3.1/`, `iqraos_v1.0/`, `pixelos/` (PixelOS 17), `cos17/`
  (this port), `device/pipa_core/`, `analysis/` (dex work). Each ROM folder has `img/` with the raw images.
- For dex analysis, use androguard in `maintainer/jar-edits/venv` (you can make it again). The host has JDK 21 (`java`, `javac`) for the jar steps and the helper.
- To change the runtime: edit `port-rom/`, add a new step file in `maintainer/port/steps/`
  (`maintainer/port/README.md`), build with `port.sh` and flash.
- State: `/data/misc/pipa_port`. Log: `/data/local/tmp/pipa_port.log`. User overrides:
  `/data/misc/pipa_port/config.prop`.
- The SELinux domain `pipa_port` is in `system_ext_sepolicy.cil` (+ `_debug.cil`), from `build_beta5_2e.sh`. It is
  **enforcing since 3f** (3g and 3w added rules): rules in `maintainer/sepolicy/pipa_port_rules.cil`, applied by
  `pipa_port_enforce.py`. A new access in the service needs a rule there. **No live `ksud sepolicy` test on
  walt-r8kpm** (it hangs the kernel, see Known gotchas): compile with `secilc` and test with a ROM build.
- Before you build a policy change, compile it on the tablet: `/system/bin/secilc` with the 8 inputs (plat cil,
  mapping + compat, system_ext cil + mapping, product, vendor `plat_pub_versioned` + `vendor_sepolicy`, odm). An
  error gives a non-zero exit code.
- Pen buttons: the vendor `Xiaomi_Smart_Pen_Keyboard.kl` maps the front button (`KEY_PAGEDOWN`) to
  `STYLUS_BUTTON_PRIMARY` and the back button (`KEY_PAGEUP`) to `STYLUS_BUTTON_SECONDARY`; Android fuses both into the
  pen events (AOSP default, apps decide). `pen_keys.sh` can add a global action per key (`keys.conf`); since 3w both
  are `none` (before: back = screenshot through `input`, which needs the `input_service` rule).
- **pipa_port is enforcing: a feature that runs code in the service (face HAL and its camera worker, `input`, ...)
  needs its rules in `maintainer/sepolicy/pipa_port_rules.cil`.** The 3g capture covered only a boot; the face camera
  worker was blocked until 3w. To find rules: `setprop persist.logd.audit.rate 2000` + `persist.logd.size 16M`,
  reboot, use the feature, list `scontext=u:r:pipa_port` denials (each enforcing test shows only the first block of a
  path; a short `setenforce 0` window with the user's OK shows all at once). Reset both properties after.
- **To test a changed ROM script live:** bind-mount a copy on it
  (`mount --bind /data/local/tmp/x.sh /system_ext/pipa_port/x.sh`; a reboot removes it).
  - `sed -i` makes a **new inode**, and the bind mount stays on the old file. Edit with `cat new > old`, or do
    `umount -l` and bind again.
  - Stop a service child by its pid file. Never use `pgrep -f <path>` in `su -c`: the pattern also finds your own
    command line and kills your shell.
- The helper: `sh helper/build.sh` (aapt2, javac, d8, zipalign, apksigner; JDK 21, `~/Android/Sdk` build-tools 37 and
  platform 37.0; no Gradle).
  - You **cannot update a persistent app with `adb install`**. To test a new version, do `pm uninstall` and install
    it as a normal app, or flash a ROM layer.
  - Keep `helper/keys/pipa-helper.jks`. The ROM and the helper updates must use the same key. The keystore password
    is in `helper/keys/keystore.pass`. Never commit or share `helper/keys/`.
  - Hidden-API access for system apps: a `hidden-api-whitelisted-app` sysconfig entry.

Original section headings (their bodies are in docs/GOTCHAS.md and docs/ROM-BACKGROUND.md):

## Known gotchas

## Background: why the ROM code does what it does
