# Build the ROM and the kernel

This document gives the procedures to build, flash and roll back the ROM and the kernel. It also gives the
procedure to make a release package. For the parts of the ROM, refer to [ARCHITECTURE.md](ARCHITECTURE.md).

The public release **beta6** is a `port.sh` run with the default options (last active step 3w) and kernel
`walt-r8kpm`.

NOTE: The scripts were made and tested on one PC (the maintainer's). Section 1.4 tells how they find their folders.

## 1. Prepare the host

### 1.1 Host and tools

Use a Linux host. The maintainer uses CachyOS (Arch Linux based). Install these tools:

| Tool | Version used | Use |
|---|---|---|
| `erofs-utils` (`mkfs.erofs`, `fsck.erofs`, `dump.erofs`) | 1.9.4 | Extract and make the partition images. |
| `android-tools` (`lpmake`, `lpunpack`, `simg2img`, `fastboot`, `adb`) | 37.0.0 | Make and read `super.img`. Flash and control the tablet. |
| Python 3 | 3.14 | `port.sh` and the build steps. |
| `attr` (`getfattr`, `setfattr`), `rsync`, `unzip`, `7z` (7-Zip) | | SELinux labels, file copies, archives. |
| JDK (`java`, `javac`, `keytool`) | OpenJDK 21 | Steps 3f, 3o, 3s, 3t (jar patches), the helper app, `cryptoeng.jar`. |
| Android SDK: build-tools **37.0.0** and platform **android-37.0** | exactly these | `d8`, `zipalign`, `aapt2`, `apksigner`, `android.jar`. The scripts use these two version names. |
| smali and baksmali | 2.5.2 | Jar patches. Put them in `<PIPA_ROOT>/tools/smali/`. |
| apktool | 2.12.1 | Step 3o (`framework.jar`). Put it in `<PIPA_ROOT>/tools/apktool/apktool.jar`. |
| Android NDK | 30 | Only for `maintainer/kgest/` (test tool) and the face HAL add-ons (`port-module/src/`). |
| AOSP clang r547379 (clang 20) | | Only for the kernel. |

The Android SDK must be in `~/Android/Sdk` of the build user, or in `ANDROID_HOME`. The steps run as root: give
`ANDROID_HOME` through `sudo` if you use it.

Optional, only for the analysis tools in `maintainer/jar-edits/` (not for the build):

```sh
python3 -m venv maintainer/jar-edits/venv && maintainer/jar-edits/venv/bin/pip install androguard
```

### 1.2 Folder layout

The scripts expect this layout below one root folder (`PIPA_ROOT`):

| Path | Contents |
|---|---|
| `COS17/` | This repository. |
| `COS17/work/parts/` | The `lpunpack` output of the beta4 `super` (section 1.3). |
| `COS17/port-overlay/` | The beta4 files for the port edit list (section 1.3). |
| `donor/OPD2515_11.C.06/img/` | The donor images (section 1.3). |
| `port-work/` | Build output (about 30 GB for each run). `port.sh` makes this folder. |
| `port-work/donor-c06-vendor/` | The C.06 `vendor.img` and `odm.img` (section 1.3). |
| `tools/smali/`, `tools/apktool/` | smali, baksmali and apktool jars. |

### 1.3 Inputs

Get these inputs. They are not in this repository.

| Input | Path below `PIPA_ROOT` | Check |
|---|---|---|
| Original release `ColorOS17 Port for pipa-beta4-20261017.7z` (by 梦归zzz) | `COS17/` | sha256 `31893e62835843a63f73b96fc095545cefded76aca684161295c15cd2490f78f` (5489788484 bytes) |
| Donor OTA `OPD2515_11.C.06_1060_202610061842.zip` (OPPO Pad Mini, `17.0.0.103(CN01)`) | `donor/OPD2515_11.C.06/` | sha256 `aeeb3029c64f3a7251bf861325a21388c1817739c8684155ba7daa71f6beb8d5` |
| SukiSU-Ultra manager `SukiSU_v4.3.0_41100-release.apk` (step 2w, release package) | `COS17/kernel/sukisu-v4.3.0/` | md5 `4dc76f1eae7bd2e6d975261d9d08baf6` |
| SukiSU-Ultra manager `SukiSU_v4.2.1-r1_41049-release.apk` (only for the optional step 2u, `PORT_WITH_2U=1`) | `COS17/kernel/sukisu-v4.2.1-r1/` | md5 `3d7698ff8f58824d1718594366f5876b` |
| Proprietary files (face HAL, charger shim, pen-wake helper, patched module files, boot animations) | their paths in this repository | [BLOBS.md](BLOBS.md) |

Prepare them in this sequence:

1. Extract the beta4 release in `COS17/`. Then extract the partitions of its `super` (slot B):

```sh
cd $PIPA_ROOT/COS17
7z x "ColorOS17 Port for pipa-beta4-20261017.7z"
mkdir -p work/parts
simg2img "ColorOS17 Port for pipa-beta4-20261017/super/super.img" work/super_raw.img
lpunpack work/super_raw.img work/parts
md5sum work/parts/vendor_b.img work/parts/odm_b.img
```

   The md5 values must be `b601a907363d01e78697cd5d4f60edf6` (`vendor_b.img`) and
   `8e25ab23745ad3d9abb7a3312abe3e23` (`odm_b.img`). `port.sh` checks them. The `_a` images are empty.

2. Extract `payload.bin` from the donor zip. Then extract the donor images. The output folder must exist:

```sh
cd $PIPA_ROOT/donor/OPD2515_11.C.06
unzip OPD2515_11.C.06_1060_202610061842.zip payload.bin
mkdir -p img ../../port-work/donor-c06-vendor
python3 -I ../../COS17/maintainer/payload_extract.py payload.bin img system system_ext product my_product my_manifest my_stock my_region my_heytap my_bigball my_carrier my_engineering
python3 -I ../../COS17/maintainer/payload_extract.py payload.bin ../../port-work/donor-c06-vendor vendor odm
```

   Step 3d takes files from the C.06 `odm` and `vendor`. Optional step 3k also uses them.

3. Make the `port-overlay` folder. It holds the beta4 files that the edit list
   `maintainer/c06-vs-beta4/PORT-EDITS.tsv` takes (rows with the action `carry`: face unlock, MiSound, OppoCamera,
   the pen library, overlays, properties, CIL files):
   1. Extract the beta4 `system` and `system_ext` as root:
      `sudo fsck.erofs --extract=<dir> --xattrs --preserve work/parts/system_b.img` (and `system_ext_b.img`).
   2. Copy the files that the `carry` rows name into `COS17/port-overlay/system/` and `COS17/port-overlay/system_ext/`.
      Keep the paths, the owners, the modes and the SELinux labels (`cp -a` as root).
   3. Compare the folder with the list: `cd COS17/port-overlay && sudo md5sum -c ../maintainer/c06-vs-beta4/port-overlay.md5`.
      Use `sudo`: some files can be read only by root.

4. Get the tools (section 1.1) into `tools/smali/` and `tools/apktool/`.

5. Build the parts that the steps take from this repository:

```sh
sh helper/build.sh                  # helper/out/PipaHelper.apk (steps 2d, 2e, 2p)
sh maintainer/cryptoeng/build.sh    # maintainer/cryptoeng/cryptoeng.jar (step 3a)
```

   WARNING: `helper/build.sh` makes a new signing key in `helper/keys/` if there is no key. Keep this key. The ROM
   and all later helper updates must use the same key. Do not share `helper/keys/`: with this key, a person can sign
   a helper update that the ROM accepts.

The `vendor` and `odm` partitions stay at beta4. The donor and the other known ROMs have no matching files for them.

### 1.4 Root folder, owner and the HDD check

- Put this repository at `<root>/COS17`. The scripts find `<root>` from their own location. You can also set
  `PIPA_ROOT` to `<root>`.
- The build steps give the output files to the owner of the `COS17` folder. Set `PIPA_OWNER` to `user:group` to use
  a different owner.
- The build steps run as root. Give variables to `sudo` with `sudo env NAME=value ...` (section 2.1).
- The kernel scripts use `K` (default `<root>/port-work/kernel`) and `BK` (default
  `<root>/COS17/kernel/backup-partitions-20261023`). Refer to section 4.
- The maintainer keeps large inputs on a second disk (`/mnt/reference`) behind symbolic links. The `port.sh`
  preflight checks that this disk is mounted only if an input links to it.

### 1.5 Disk space

- A `port.sh` run needs about 30 GB in `port-work/`: the tree (13 to 23 GB) and the images (about 13 GB with
  `super.img`). The preflight asks for 40 GB free. Before `mkfs.erofs` and before `lpmake`, `port.sh` stops if less than 20 GB
  is free.
- `port.sh` deletes the tree after a good run, unless you give `--keep-tree`. After a failed run, the tree stays.
- The old layer scripts add about 7 GB of images for each layer.

WARNING: A full disk can give a short `super.img`. `port.sh` stops on an `lpmake` error and checks the free space.
Do not flash an image from a run that stopped.

## 2. Build the ROM

### 2.1 Build all steps

`maintainer/port/port.sh` is the main build. It uses one tree. It extracts the donor and the pinned beta4 base one
time, runs the steps `maintainer/port/steps/NN-<step>-<name>.sh` in order (`00-base` to `51-3x`), checks the SELinux
labels, makes one image for each partition and makes `super.img`. A run takes about 4 minutes (beta6: 235 s).

1. Go to the root folder. Do the preflight check. It builds nothing:

```sh
cd $PIPA_ROOT
sh COS17/maintainer/port/port.sh --check mybuild donor/OPD2515_11.C.06/img
```

2. Build all steps. Use a new tag for each run: the run deletes `port-work/<tag>/`.

```sh
sudo sh COS17/maintainer/port/port.sh mybuild donor/OPD2515_11.C.06/img
```

Options:

| Option | Function |
|---|---|
| `--until <step>` | Stop after this step, for example `--until 3h`. |
| `--keep-tree` | Keep the tree `port-work/<tag>/tree` after a good run. |
| `PORT_OVERLAY_SRC=<dir>` | A different `port-overlay` folder. It must have `system/` and `system_ext/`. |
| `PORT_WITH_2U=1` | Also apply step 2u (SukiSU preload). Not used for releases. |
| `PORT_ODM_C06=1` | Also apply step 3k (`odm` interconnect stack from C.06). Built, not tested. |
| `PORT_NOENCRYPT=1` | Also apply step 3x (`/data` without encryption, `beta6-noenc`). Experimental. Clean flash only. |

Without options, steps 2u, 3k and 3x do nothing. Thus the default build ends at 3w (beta6). Give the variables
through `sudo env`, for example `sudo env PORT_NOENCRYPT=1 sh COS17/maintainer/port/port.sh ...`.

The output is in `port-work/<tag>/`:

| Path | Content |
|---|---|
| `img/super.img` | The flashable image and the partition images. |
| `report/PORT-REPORT.txt` | Time of each step, image sizes, md5. |
| `report/<partition>.tsv` | File manifest of each partition (path, mode, owner, md5, labels). |
| `report/steps/*.log` | Output of each step. |

Reference sizes of the beta6 run: `super.img` 6832974396 bytes; `system.img` 5072203776, `system_ext.img` 1047322624,
`product.img` 146210816, `vendor.img` 550653952, `odm.img` 16515072 bytes.

NOTE: `mkfs.erofs` puts a random UUID in each image. Two builds with the same content have different image md5 values.
To compare two builds, compare the `report/<partition>.tsv` manifests (made by `tree_manifest.py`), not the image md5.
To flash a new build, take its md5 from the end of the `port.sh` output or from `PORT-REPORT.txt`.

NOTE: On a new donor, the first steps stop at their md5 checks. This is correct. Refer to [REBASE.md](REBASE.md). The
full description of `port.sh` is in `maintainer/port/README.md`.

### 2.2 Common failures

| Message | Cause | Remedy |
|---|---|---|
| `HDD /mnt/reference NOT MOUNTED (an input links to it)` | An input is a link to the second disk, and the disk is not mounted. | Mount the disk, or copy the input to its folder. |
| `free space on port-work ... 40 GB needed` | Not enough space. | Make space. |
| `MISSING input of <step>` | A file from section 1.3 or [BLOBS.md](BLOBS.md) is missing. | Get or build the file. |
| `vendor_b.img md5 ..., expected ...` | Wrong beta4 `super`, or slot A image. | Section 1.3, item 1. |
| A step stops at an md5 check or an anchor | The donor or the input file is different. | [REBASE.md](REBASE.md). |

There is no resume. After a fix, start the run again from the beginning.

### 2.3 Add a fix

1. Change the source: `port-rom/`, `helper/` or an edit list.
2. Write a new step file in `maintainer/port/steps/`. The procedure is in `maintainer/port/README.md` ("How to add a
   step").
3. Build with `port.sh`. Test with `--until <step> --keep-tree` first.

### 2.4 Old method: add a ROM layer (history)

The layer scripts `maintainer/build_beta5_<step>.sh` (the last is `build_beta5_3j.sh`) and `maintainer/build_port.sh`
stay in the repository as history. A layer script reads the images of the previous layer in
`port-work/<tag>-<previous step>/`. Most of these old images are deleted. Use `port.sh --until <step> --keep-tree`
instead. New fixes are step files only.

## 3. Flash the ROM

WARNING: Make a backup of your data before you flash.

`maintainer/flash_super.sh` flashes only `super` to slot B and sets slot B active. It does not write `boot`,
`vbmeta` or the firmware, and it does not erase data. It checks the md5 first.

1. Flash a new build. Give the path and the md5:

```sh
sh maintainer/flash_super.sh -y port-work/<tag>/img/super.img <md5>
```

2. Wait for the first boot. It takes some minutes (about 1 minute more for the framework compile).
3. If the tablet does not boot, flash the previous image with the same script. `sh maintainer/flash_super.sh -y beta4`
   flashes the original beta4 `super`. The other names in the script are the maintainer's images.

- `-y` answers the confirmation question. It is necessary when there is no terminal.
- `flash_super.sh` cannot change the encryption of `/data`. For `beta6-noenc` (step 3x), use the release package and
  a clean flash (section 5).
- The kernel must agree with the ROM. Refer to [KERNEL.md](KERNEL.md), section 4.

NOTE: If the first `fastboot` command shows "Device does not support slots", do `fastboot reboot` and try again.

CAUTION: After a flash, `/data` uses f2fs `checkpoint=disable` until a boot completes. If the tablet does not boot,
the next reboot removes all changes to `/data` (also `/data/adb`).

## 4. Build and flash the kernel

The kernel repository has its own build script. Refer to its `README.md`:
https://github.com/Stefan-Atanasov/kernel_xiaomi_pipa_cos17 (branch `oppo`). It packs the kernel into your own
`boot.img` (`pack-boot.sh`). Use it if you do not have the maintainer's files below.

The scripts in `maintainer/kernel/` are the maintainer's scripts. They need files that are not in this repository:

| Variable | Default | Contents |
|---|---|---|
| `K` | `<root>/port-work/kernel` | Kernel trees, `clang-r547379/`, `bootimg/magiskboot` |
| `BK` | `<root>/COS17/kernel/backup-partitions-20261023` | Backup of `boot_b`, `vendor_boot_b`, `dtbo_b` of the maintainer's tablet (TWRP ramdisk, boot header v3) |
| `SERIAL` | the maintainer's tablet | `fastboot` serial for `flash_kernel.sh` |

`prepare_tree_walt.sh` also needs `COS17/kernel/walt-own.bundle` (the own commits). The public kernel repository has
the same commits.

1. Get the trees. The script clones the upstream sources and applies the own commits from the bundle:

```sh
bash maintainer/kernel/prepare_tree_walt.sh
```

2. Build the kernel with the OPPO UI First code:

```sh
TREE=$K/walt-oppo bash maintainer/kernel/build_walt.sh
```

3. For KPM (`walt-r8kpm`), patch the `Image` with KernelPatch `kptools` (kernel `README.md`). The scripts do not do
   this step.
4. Make a trimmed test image and boot it one time. This writes nothing to the tablet:

```sh
TRIM=1 bash maintainer/kernel/mkboot.sh <tree>/out/arch/arm64/boot/Image $K/bootimg/boot-X-trim.img ""
SERIAL=<serial> bash maintainer/kernel/flash_kernel.sh test $K/bootimg/boot-X-trim.img
```

5. Make the full image and flash it to `boot_b`:

```sh
bash maintainer/kernel/mkboot.sh <tree>/out/arch/arm64/boot/Image $K/bootimg/boot-X.img ""
SERIAL=<serial> bash maintainer/kernel/flash_kernel.sh flash $K/bootimg/boot-X.img
```

6. To roll back, flash the previous boot image with `flash_kernel.sh flash`.

WARNING: `flash_kernel.sh flash` writes `boot_b` at once. It does not ask for a confirmation. Keep the previous boot
image before you flash.

WARNING: Do not pack the kernel with `magiskboot repack` only. It changes the patch level in the boot header.
The bootloader then refuses the kernel and the screen stays black. Use `mkboot.sh` or `pack-boot.sh`.

CAUTION: Use only trimmed images (`TRIM=1`) with `fastboot boot`. The full 196 MB image can stop `fastboot boot`.

CAUTION: Do not replace `/data/adb/ksud`. Update ksud only with a matching kernel, through the SukiSU manager.

NOTE: If the tablet does not boot, use TWRP (Power + Volume up, slot B active). TWRP gives root ADB and a decrypted
`/data`. `maintainer/kernel/flash_kernel.sh restore` writes the partition backups (`BK`).

## 5. Make a release package

```sh
bash maintainer/build_release.sh <tag> --pkg <name> --boot <boot.img> --name "<version text>" --7z
```

- `<tag>`: the `port.sh` tag. The script takes `port-work/<tag>/img/super.img`.
- `--pkg`: the package name, for example `beta6` (default: the tag). The script takes the release notes
  `COS17/RELEASE-NOTES-<pkg>.md`. If this file does not exist, the script stops.
- `--boot`: the kernel image. Without it, the package has the beta4 kernel.
- `--no-super`: no `super.img` (to test the packaging).

The script needs the extracted beta4 release in `COS17/` (section 1.3), the SukiSU manager APK (`KSU_APK`, default
the v4.3.0 APK) and `COS17/pipa-susfs-v1.0.zip`. `--7z` needs `7z`.

The output is `<root>/port-work/release/ColorOS17-Port-pipa-<pkg>-<date>/` and a `.7z` file. The package
contains the beta4 flash scripts (with changes) and firmware, the new `super.img`, the new `boot.img`,
`RELEASE-NOTES.md`, `README-FLASH.txt`, `extras/` (SukiSU manager, susfs module) and `SHA256SUMS`.

The user runs `FlashLinux.sh` or `FlashWindows.bat`. The script asks one question:

| Answer | Flash | Data |
|---|---|---|
| `y` (clean flash) | All firmware, `boot`, `dtbo`, `vendor_boot`, `vbmeta` to both slots, `super`. Slot B active. | Erases `metadata` and `userdata`. |
| Enter (dirty flash) | All firmware, `vendor_boot` and `vbmeta` to both slots; `boot` and `dtbo` only to slot B; `super`. Slot B active. | Stays. |

WARNING: A dirty flash also writes the firmware (bootloader, modem, `vbmeta`). Only the data stays.

WARNING: A change between an encrypted and an unencrypted (`PORT_NOENCRYPT=1`) build needs a clean flash.

Before you publish a package, do the release checklist in [TESTING.md](TESTING.md), section 8.

## 6. Publish

| Item | Command |
|---|---|
| Public repository (no proprietary files, no signing key) | `sh maintainer/sync_port_repo.sh "<message>"` |
| Private kit for a co-maintainer (with proprietary files, no signing key) | `sh maintainer/make_port_kit.sh` |
| Kernel source (maintainer) | Cherry-pick the commit onto `pub/oppo` in `port-work/kernel/walt-own`, then `git push origin pub/oppo:oppo` |

`sync_port_repo.sh` copies the documents in `COS17/docs/` to the repository root. Edit the sources in `COS17`, not
the copies.
