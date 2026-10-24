# Build the ROM and the kernel

This document gives the procedures to build, flash and roll back the ROM and the kernel. It also gives the
procedure to make a release package.

## 1. Prepare the host

### 1.1 Tools

Install these tools on a Linux host:

| Tool | Use |
|---|---|
| `erofs-utils` (`mkfs.erofs`, `fsck.erofs`, `dump.erofs`) | Extract and make the partition images. |
| `lpmake`, `lpunpack`, `lpdump` | Make and read `super.img`. |
| `fastboot`, `adb` | Flash and control the tablet. |
| Python 3, `rsync` | Build steps and tools. |
| JDK 21 and Android SDK build-tools 37 (`~/Android/Sdk`) | Build the pipa helper app. |
| Android NDK 30 | Build the face crop add-on. |
| AOSP clang r547379 (clang 20) | Build the kernel. |

For work on `.jar` files, make the androguard environment:

```sh
python3 -m venv maintainer/jar-edits/venv && maintainer/jar-edits/venv/bin/pip install androguard
```

### 1.2 Inputs

Get these inputs. They are not in this repository.

| Input | Path below `PIPA_ROOT` |
|---|---|
| Original release `ColorOS17 Port for pipa-beta4-20261017.7z` (firmware, `super`) | `COS17/` |
| Partition images of the beta4 `super` (`lpunpack`, slot B) | `COS17/work/parts/*_b.img` |
| Root-extracted beta4 tree | `port-work/roundtrip/src` |
| Donor OPD2515 `17.0.0.103(CN01)` images | `donor/OPD2515_11.C.06/img` |
| Proprietary files listed in `BLOBS.md` | their paths in this repository |

### 1.3 Folder and owner

The scripts use `/home/stefan/Documents/pipa` as the default root folder. To use a different folder:

1. Put this repository at `<root>/COS17`.
2. Set `PIPA_ROOT` to `<root>`.
3. Set `PIPA_OWNER` to your `user:group`. The build steps give the output files to this owner.
4. Give the variables to `sudo`, because the build steps run as root:

```sh
sudo PIPA_ROOT=$PWD PIPA_OWNER=$USER:$USER sh COS17/maintainer/build_port.sh beta5 <donor-img-dir>
```

### 1.4 Disk space

Each ROM layer adds about 7 GB of images. Keep at least 40 GB free in `port-work/`.

## 2. Build the ROM

### 2.1 Build all steps

1. Do the preflight check. It builds nothing.

```sh
sh maintainer/build_port.sh --check beta5 <donor-img-dir>
```

2. Build all steps:

```sh
sudo sh maintainer/build_port.sh beta5 <donor-img-dir>
```

3. To continue from a step, give the first step and the last step:

```sh
sudo sh maintainer/build_port.sh beta5 <donor-img-dir> 2e 2o
```

The output of each step is in `port-work/<tag>-<step>/` (`tree/`, `img/`, `report/`). The flashable image is
`port-work/<tag>-<last step>/img/super.img`.

NOTE: On a new donor, the first two steps stop at their md5 checks. This is correct. Refer to
[REBASE.md](REBASE.md).

### 2.2 Add a ROM layer

1. Change the source: `port-rom/`, `helper/` or an edit list.
2. Copy the newest step script, for example `maintainer/build_beta5_2o.sh`, to the next name (`build_beta5_2p.sh`).
3. In the new script, set the input to the previous step and the output to the new step.
4. Only replace files in the copied tree. Write each file in place with `cat new > old`.
   This keeps the owner, the mode and the SELinux label.
5. Make again only the images that you changed: `mkfs.erofs -zlz4hc -C65536 -T0`.
6. To change a partition that the previous step did not keep as a tree (for example `product`), extract it as
   root: `fsck.erofs --extract=<dir> --xattrs --preserve <img>`.
7. Make sure that the label check (`tree_manifest.py`) passes. Each file must have `security.selinux`.
8. Run the new step: `sudo sh maintainer/build_beta5_<step>.sh`.
9. Add the name and the md5 of the new `super.img` to `maintainer/flash_super.sh`.
10. Add the step to `STEPS` in `maintainer/build_port.sh`.

### 2.3 Build the helper app

```sh
sh helper/build.sh
```

The output is `helper/out/PipaHelper.apk`.

WARNING: Do not share `helper/keys/` (`pipa-helper.jks`, `keystore.pass`). With this key, a person can sign a
helper update that the ROM accepts.

NOTE: The ROM and helper updates must use the same key. A build with a different key cannot update the
helper of another build.

## 3. Flash the ROM

WARNING: Make a backup of your data before you flash.

1. Flash `super` to slot B. The script checks the md5 first. It does not erase data.

```sh
sh maintainer/flash_super.sh -y <name>
```

2. To flash an image that is not in the list, give the path and the md5:

```sh
sh maintainer/flash_super.sh -y <path-to-super.img> <md5>
```

3. Wait for the first boot. It takes some minutes.
4. If the tablet does not boot, flash the previous step with the same script.

NOTE: If the first `fastboot` command shows "Device does not support slots", do `fastboot reboot` and try again.

NOTE: After a flash, `/data` uses f2fs `checkpoint=disable` until a boot completes. If the tablet does not
boot, the next reboot removes all changes to `/data`.

## 4. Build and flash the kernel

The kernel repository has its own build script. Refer to its `README.md`:
https://github.com/Stefan-Atanasov/kernel_xiaomi_pipa_cos17 (branch `oppo`).

To use the scripts in this repository:

1. Get the trees. The script clones the upstream sources and puts the own commits from the bundle:

```sh
bash maintainer/kernel/prepare_tree_walt.sh
```

2. Build the kernel with the OPPO UI First code:

```sh
TREE=$PIPA_ROOT/port-work/kernel/walt-oppo bash maintainer/kernel/build_walt.sh
```

3. Make a test image and boot it once. This writes nothing to the tablet:

```sh
TRIM=1 bash maintainer/kernel/mkboot.sh <tree>/out/arch/arm64/boot/Image port-work/kernel/bootimg/boot-X-trim.img ""
bash maintainer/kernel/flash_kernel.sh test port-work/kernel/bootimg/boot-X-trim.img
```

4. Make the full image and flash it to `boot_b`:

```sh
bash maintainer/kernel/mkboot.sh <tree>/out/arch/arm64/boot/Image port-work/kernel/bootimg/boot-X.img ""
bash maintainer/kernel/flash_kernel.sh flash port-work/kernel/bootimg/boot-X.img
```

5. To roll back, flash the previous boot image with `flash_kernel.sh flash`.

WARNING: Do not pack the kernel with `magiskboot repack` only. It changes the patch level in the boot header.
The bootloader then refuses the kernel and the screen stays black. Use `mkboot.sh` or `pack-boot.sh`.

CAUTION: Use only trimmed images (`TRIM=1`) with `fastboot boot`. The full 196 MB image stops `fastboot boot`.

CAUTION: Do not replace `/data/adb/ksud`. Update ksud only with a matching kernel, through the SukiSU manager.

NOTE: If the tablet does not boot, use TWRP (Power + Volume up). TWRP gives root ADB and a decrypted `/data`.
`maintainer/kernel/flash_kernel.sh restore` writes the partition backups.

## 5. Make a release package

```sh
bash maintainer/build_release.sh <tag> --boot <boot.img> --name "<version text>" --7z
```

The output is `port-work/release/ColorOS17-Port-pipa-<tag>-<date>/` and a `.7z` file. The package contains
the beta4 flash scripts and firmware, the new `super.img`, the new `boot.img`, `RELEASE-NOTES.md` and
`SHA256SUMS`.

The user runs `FlashLinux.sh` or `FlashWindows.bat`. The script asks one question:

- `y`: clean flash. The script erases `metadata` and `userdata`.
- Enter: dirty flash. The data stays.

Test a clean flash of the package before you publish it.

## 6. Publish

| Item | Command |
|---|---|
| Public repository (no proprietary files, no signing key) | `sh maintainer/sync_port_repo.sh "<message>"` |
| Private kit for a co-maintainer (with proprietary files, no signing key) | `sh maintainer/make_port_kit.sh` |
| Kernel source | Cherry-pick the commit onto `pub/oppo` in `port-work/kernel/walt-own`, then `git push origin pub/oppo:oppo` |
