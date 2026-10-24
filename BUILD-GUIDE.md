# Build guide: ROM and kernel (pipa ColorOS 17 port)

How to build, test, flash and roll back both halves of the port. Short on purpose; each section links the long
document. Current versions: **ROM beta5-2n** + **kernel walt-r5** (2026-10-24).

| | ROM (`super.img`) | Kernel (`boot.img`) |
|---|---|---|
| Source | donor OPPO `OPD2515 17.0.0.103` (C.06) OS side + pipa vendor/odm/firmware + our layers | `port-work/kernel/walt-own`, branch `oppo` (= `own` + OPPO UI First); public on GitHub |
| Build | `sudo sh maintainer/build_port.sh <tag> <donor-img-dir>` or one layer `sudo sh maintainer/build_beta5_<step>.sh` | `maintainer/kernel/build_walt.sh` → `mkboot.sh` |
| Output | `port-work/<tag>-<step>/img/super.img` | `port-work/kernel/bootimg/boot-<name>.img` |
| Flash | `sh maintainer/flash_super.sh -y <tag-step>` (super slot B only, no wipe) | `bash maintainer/kernel/flash_kernel.sh flash <img>` |
| Rollback | flash the previous step (`flash_super.sh -y beta5-2m`) | `flash_kernel.sh flash bootimg/boot-walt-r4.img` |
| Long doc | `PORT-MAINTAINER.md`, `PHASE2-ROM-INTEGRATION.md` | `kernel/WALT-KERNEL.md`, `kernel/KERNEL-RESEARCH.md` |

ROM and kernel are linked in two places: ROM **2h** (gpuservice null guards) **2i** (UI First SELinux) and **2l** (SF scene, needs UI First) are needed
by our kernel, and the kernel's SukiSU (manager/ksud 4.2.1-r1) must match the manager on the tablet.

## 0. Before you build

- Host: Linux, `sudo`, `erofs-utils` (`mkfs.erofs`, `fsck.erofs`, `dump.erofs`), `lpmake`/`lpunpack`, `fastboot`/`adb`,
  python3, JDK 21 + `~/Android/Sdk` (helper app), NDK 30 (face crop add-on).
- `mountpoint /mnt/reference` must succeed (the HDD holds `donor/`, `work/` and the reference ROMs behind symlinks).
- Free space: `du` shows ~23 GB per layer in `port-work/`, but btrfs reflinks share most of it; keep ≥ 40 GB free.
- Tablet: `adb devices` shows `83836a90`. Flashing super keeps `/data`; until a boot completes `/data` runs with
  f2fs `checkpoint=disable` (writes roll back on a bootloop).

## 1. ROM

### 1.1 How the ROM is put together

A chain of scripts in `maintainer/`, each taking the previous step's tree/images and writing `port-work/<tag>-<step>/`:

```
base (build_beta5.sh: donor OS + PORT-EDITS.tsv) → baked → 1c → 2a → 2b → 2c → 2d → 2e → 2f → 2g → 2h → 2i → 2j → 2k → 2l → 2m → 2n
```

What each step does: header of `maintainer/build_port.sh`, details in each script's header. Runtime code that the
layers copy in: `port-rom/` (pipa_port service: face HAL, charger shim, pen, keyboard guard, colour restore),
`helper/` (pipa helper app), `maintainer/bootanim/`, `maintainer/uifirst-policy/`.

### 1.2 Build everything (new machine, new donor)

```sh
cd ~/Documents/pipa/COS17
sudo sh maintainer/build_port.sh beta5 <donor-img-dir>             # all steps; --check = preflight only
sudo sh maintainer/build_port.sh beta5 <donor-img-dir> 2e 2n       # resume from a step
```

On a **new donor** the first two steps stop on purpose at their stock-md5 checks (jar, brightness xml, odm script):
regenerate those files from the new donor (`module/tools/`), update the md5, resume. Also scan changed libs for new
`waitForService` imports (C.06 boot-hang lesson, `CLAUDE.md`). Full rebase recipe: `PORT-MAINTAINER.md`.

### 1.3 Change something = add a layer

1. Edit the source (`port-rom/…`, `helper/…`, or a new edit list).
2. Copy the newest layer script (`build_beta5_2n.sh`) to `build_beta5_2o.sh`: input `2n`, output `2o`. Only
   swap files in the copied tree: **edit in place with `cat new > old`** so owner, mode and SELinux xattr stay;
   rebuild only the partitions you touched (`mkfs.erofs -zlz4hc -C65536 -T0`), reflink the rest.
   A partition not kept as a tree (e.g. `product`): `fsck.erofs --extract=<dir> --xattrs --preserve <img>` as root.
3. The script's label check (`tree_manifest.py`: every entry needs `security.selinux`) must pass.
4. `sudo sh maintainer/build_beta5_2o.sh`; log in `port-work/beta5-2o/report/build.log`.
5. Add the name + md5 to `flash_super.sh` and the step to `build_port.sh` (`STEPS` + header).
6. Test pipa_port changes **before** building: bind-mount the new script over the ROM copy
   (`mount --bind /data/local/tmp/service.sh /system_ext/pipa_port/service.sh`, `chcon u:object_r:system_file:s0`),
   kill the old loop by its pid file (`/data/local/tmp/pipa_port.pid`), `setprop ctl.restart pipa_port`. Gone at reboot.

### 1.4 Flash, verify, roll back

```sh
sh maintainer/flash_super.sh -y beta5-2n       # reboots to fastboot, md5 check, super → slot B, reboot (~3 min)
```

After boot (unlock once): `getprop ro.build.display.id`, `tail /data/local/tmp/pipa_port.log`,
`sh maintainer/device_check.sh` (with `ADB="adb -s 83836a90"`). Bootloop: `/data/anr/traces_SystemServer_WDT*`,
`/sys/fs/pstore/`; rollback `flash_super.sh -y <previous>`; worst case TWRP (Power + Volume up) has root adb.

## 2. Kernel

### 2.1 What it is

Lineage `lineage-24.0` core (4.19.325, WALT) + liyafe's pipa drivers + E404's display/touch + SukiSU builtin/susfs
2.3.0 + uclamp + OPPO UI First (branch `oppo`) + our commits. Table and rules: `kernel/WALT-KERNEL.md`.
Trees: `port-work/kernel/walt-own` (branch `own`), worktree `walt-oppo` (branch `oppo`, **this is what we flash**).
Our commits are also in `COS17/kernel/walt-own.bundle`. Toolchain `port-work/kernel/clang-r547379`.

### 2.2 Rebuild from scratch

```sh
cd ~/Documents/pipa/COS17
bash maintainer/kernel/prepare_tree_walt.sh                                 # clones upstream, restores own/oppo from the bundle
TREE=~/Documents/pipa/port-work/kernel/walt-oppo bash maintainer/kernel/build_walt.sh      # ~15 min; DBG=1 = boot watchdog
```

### 2.3 Change, test, flash

```sh
# commit in walt-own (branch own), then: git -C ../walt-oppo merge own   (oppo-only work: commit in walt-oppo)
TREE=…/walt-oppo DBG=1 bash maintainer/kernel/build_walt.sh
I=~/Documents/pipa/port-work/kernel/walt-oppo/out/arch/arm64/boot/Image
TRIM=1 bash maintainer/kernel/mkboot.sh $I port-work/kernel/bootimg/boot-X-trim.img "pipa_bootdbg=150"
bash maintainer/kernel/flash_kernel.sh test port-work/kernel/bootimg/boot-X-trim.img     # fastboot boot, nothing written
# checks: maintainer/kernel/kernel_check.sh, oplus_check.sh, heavy_mix.sh (2 runs), drain test
bash maintainer/kernel/build_walt.sh  (without DBG) && bash maintainer/kernel/mkboot.sh $I port-work/kernel/bootimg/boot-X.img ""
bash maintainer/kernel/flash_kernel.sh flash port-work/kernel/bootimg/boot-X.img
```

Hard rules: **pack only with `mkboot.sh`** (`magiskboot -h` corrupts the header patch level → silent black screen);
test boots only with `TRIM=1` images (a full 196 MB `fastboot boot` hung the bootloader); never replace
`/data/adb/ksud`; never `pkill -f build_walt.sh` from a command containing that string; do not edit `build_walt.sh`
while it runs. Not booting: wait 3 min (DBG builds warm-reset, log in `/sys/fs/pstore`), else flash the rollback from
fastboot or use TWRP.

### 2.4 Save and publish

```sh
bash maintainer/kernel/prepare_tree_walt.sh --save                 # refresh kernel/walt-own.bundle
git -C port-work/kernel/walt-own push origin pub/own:own pub/oppo:oppo   # GitHub; commit/rebase onto pub/* first (no-reply author address)
```

Updating Lineage / SukiSU / susfs / OPPO later: `kernel/WALT-KERNEL.md` "Updating later".

## 3. Release package

```sh
bash maintainer/build_release.sh beta5-2n --boot ~/Documents/pipa/port-work/kernel/bootimg/boot-walt-r5.img --7z
```

Firmware + super + our boot.img + flash scripts in `port-work/release/`. Before publishing: a clean-flash test
(`FlashLinux.sh` with wipe, run by the user), release notes `RELEASE-NOTES-beta5.md`, kernel source link (GPL).
