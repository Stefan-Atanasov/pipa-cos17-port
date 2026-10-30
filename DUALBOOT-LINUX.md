# Dual boot with Linux: what you must know first

This page tells you how the ColorOS 17 port for the Xiaomi Pad 6 (`pipa`) uses the storage, the boot slots and the
kernel, and what this means for a dual boot with Linux (or Windows). Read all of it before you change a partition.

All values come from the maintainer's tablet (128 GB model, 2026-10-29), unless a source is given. **We did not
install a dual boot on this port ourselves.** The methods below are from the pipa Linux community.

> **Not tested, AI-written.** This page was written with an AI assistant (Claude) from measurements on the
> maintainer's tablet and the community documents linked below. Nobody has done a dual boot with this port yet.
> Check each step yourself and back up first. Reports are welcome.

## 1. Short answers

- **Can Linux read the internal storage of the port?** Not with the normal build: `/data` is encrypted with keys
  that only the TEE of the tablet can use (section 4). An **experimental build without encryption** exists
  (`beta6-noenc`, section 4); it is not tested.
- **Do I need SELinux permissive?** No. SELinux does not hold encryption keys. `androidboot.selinux=permissive` on the
  kernel command line also does nothing: this is a `user` build, and the vendor boot image sets
  `androidboot.selinux=enforcing`.
- **Do I need to turn off Android encryption for dual boot?** No. Linux uses its own boot image and its own root
  partition.
- **Is dual boot possible?** Yes, with the community methods (section 6). It needs a **format of all Android data**,
  because `userdata` uses all the free space.
- **What is the easy way to share files?** A USB drive, or the network (MTP, ADB, Syncthing, SMB).

## 2. Storage layout (UFS)

The UFS storage has several logical units (LUNs). Linux sees them as `sda` ... `sdf`.

| LUN | Contents |
|---|---|
| `sda` (~117 GB) | `persist`, `metadata`, `misc`, `frp`, `cust`, `rawdump`, `rescue`, `super` (`sda29`, 8.5 GB) and **`userdata` (`sda34`, 106.6 GB) = the last partition** |
| `sdb`, `sdc` | `xbl_a` + `xbl_config_a`, and `xbl_b` + `xbl_config_b` (primary bootloader) |
| `sdd` | `cdt`, `ddr` (board data, DDR training) |
| `sde` (2.1 GB) | The A/B firmware and boot partitions: `abl`, `aop`, `tz`, `hyp`, `keymaster`, `modem`, `dsp`, `bluetooth`, `boot`, `vendor_boot`, `dtbo`, `vbmeta`, `vm-linux`, ... (each with `_a` and `_b`) |
| `sdf` | Modem storage: `modemst1`, `modemst2`, `fsg`, `fsc` |

- `userdata` is the last partition on `sda`. To make space, shrink `userdata` from the end and add new partitions
  after it (`sda35`, `sda36`, ...). The Windows-on-pipa guides use the same layout.
- There is **no `recovery` partition**. Recovery (TWRP) is in the boot image.
- `vm-linux_a/b`, `rawdump`, `rescue`, `cust` are **not** free space. Do not use them.

## 3. Boot chain, slots and kernel

| Item | The port |
|---|---|
| Bootloader | Xiaomi ABL, unlocked. Verified boot state `orange`. |
| Active slot | **B** (`androidboot.slot_suffix=_b`). All flash scripts set slot B. |
| Firmware (`abl`, `xbl`, `tz`, `hyp`, `keymaster`, `modem`, `dsp`, `bluetooth`, `aop`, ...) | **The same on slot A and slot B.** The release scripts flash these with `_ab`. |
| `vbmeta`, `vbmeta_system`, `vendor_boot`, `dtbo` | The same on slot A and slot B. |
| `boot_b` (192 MB) | **The port kernel + TWRP 3.7.1** (boot image header v3). Never replace it. |
| `boot_a` (192 MB) | The kernel of the last clean flash. The port never boots from it. **This is the place for a Linux or UEFI image.** |
| `vendor_boot` (96 MB, header v3) | The device tree (DTB) and the base kernel command line (`androidboot.hardware=qcom ... androidboot.selinux=enforcing`). The bootloader loads `vendor_boot` of the active slot. |
| `dtbo` | Device tree overlays (`androidboot.dtbo_idx=9`). Mainline Linux needs an **empty** `dtbo` in its slot. |
| `super` | The ROM (system, system_ext, product, vendor, odm, my_*), only in the slot B logical partitions. Slot A has no ROM. |

The kernel:

- The port uses its own kernel (Linux **4.19**, SM8250 WALT): https://github.com/Stefan-Atanasov/kernel_xiaomi_pipa_cos17
  (branch `oppo`). Root: SukiSU-Ultra (built in), susfs, KPM. It is an Android kernel. It cannot boot a Linux
  distribution.
- A Linux distribution needs a **mainline pipa kernel** (for example the kernels of TheMojoMan's images, or
  https://github.com/MollySophia/linux-mainline-pipa). Each OS has its own kernel in its own boot slot.
- Do not flash the port kernel to `boot_a`, and do not flash a mainline kernel to `boot_b`.

## 4. Encryption of `/data`

```
/data  f2fs  inlinecrypt  fileencryption=aes-256-xts:aes-256-cts:v2+inlinecrypt_optimized+wrappedkey_v0,
                          metadata_encryption=aes-256-xts:wrappedkey_v0,keydirectory=/metadata/vold/metadata_encryption
```

- There are two layers: **metadata encryption** (the full partition, below f2fs) and **file-based encryption v2**
  (file names and contents).
- Both use **hardware-wrapped keys** (`wrappedkey_v0`). Only the Qualcomm TEE (keymaster 4.0) and the inline crypto
  engine of the SoC can use them. User data also needs your lock-screen credential.
- AOSP says that `wrappedkey_v0` is not compatible with the upstream Linux kernel. TWRP in the port can decrypt
  `/data` because it runs the Android keymaster in the TEE.
- **Keep `metadata` and `persist`.** If you erase `metadata`, Android cannot open `/data` again (format needed).
- **Experimental build without encryption: `beta6-noenc`** (2026-10-30, port step 3x, `PORT_NOENCRYPT=1`). Its
  `vendor/etc/fstab.qcom` has no `fileencryption=`, `metadata_encryption=`, `keydirectory=` and `inlinecrypt` on
  `/data`, so Android formats `/data` without encryption. Then Linux can read it (f2fs).
  - **Not tested.** Nobody has booted it yet.
  - **Clean flash only** (flash script, answer `y`). "Keep data" over an encrypted install does not work. To go back
    to the normal build, flash it with `y` again.
  - Check after the first boot: `adb shell getprop ro.crypto.state` must show `unencrypted`.
  - No protection at rest: anyone with the tablet in the bootloader or TWRP can read your files.

## 5. What the flash scripts write

| Script | Writes |
|---|---|
| `FlashLinux.sh` / `FlashWindows.bat`, **clean flash** ("y") | All firmware `_ab`, `boot_ab`, `dtbo_ab`, `vendor_boot_ab`, `vbmeta_ab`, `super`; erases `metadata` and `userdata`. **Overwrites a Linux image in `boot_a` and `dtbo_a`.** |
| Same, **dirty flash** (Enter), **build 6 and later** | Firmware, `vendor_boot` and `vbmeta` `_ab` (unchanged content), **`boot_b` and `dtbo_b` only**, `super`. **Slot A keeps your Linux image.** |
| Same, dirty flash, **beta5 and older** | Like a clean flash without the erase: `boot_ab` and `dtbo_ab`. Flash your Linux image to `boot_a` again after the update, and erase `dtbo_a` again. |

- No script changes the partition table (GPT).
- The port has no OTA updater. (On ROMs with A/B OTA, an update writes the inactive slot = the Linux slot. HyperOS
  users reported Linux boot failures after updates.)

## 6. Dual boot methods used on pipa

1. **Linux boot image in slot A** (TheMojoMan `xiaomi-pipa`): flash the Linux boot image to `boot_a`, erase `dtbo_a`,
   put the Linux root image on its own partition.
2. **UEFI in slot A** (TheMojoMan `pipa-multiboot`, Mu-Qcom / edk2-msm): flash `pipa_dualrole.img` to `boot_a`. UEFI
   shows a rEFInd menu and starts Linux (or Windows) from an EFI system partition (`esp`).
3. **`fastboot boot`** of a Linux image from a PC: nothing is written to the boot partitions. Linux must have its
   root file system on USB storage or in RAM.

Switch the OS in the bootloader: `fastboot set_active a` (Linux), `fastboot set_active b` (ColorOS). Do not use
`qbootctl` (reported fastboot loop on pipa).

### Typical steps (methods 1 and 2)

1. Make a file-level backup of your Android data (on the tablet, while it is unlocked). Copy it to a PC.
2. Back up the partition table and `boot_a`, `dtbo_a` (for example with TWRP or `dd`).
3. In TWRP (or a Linux live system), shrink `userdata` (`sda34`) from the end with `parted`, and create the Linux
   root partition (and `esp` for method 2) after it. Use the values of **your** tablet. Never copy values from a
   guide for another storage size (the guides show 256 GB values).
4. Boot ColorOS (slot B). It formats the new, smaller `/data`. All Android data is lost at this point.
5. Write the Linux root image to the new partition.
6. Flash the Linux boot image (or the UEFI image) to `boot_a`. Erase `dtbo_a`.
7. `fastboot set_active a` to start Linux. `fastboot set_active b` to go back.

## 7. If something goes wrong

- ColorOS does not start: in fastboot, `fastboot set_active b`. Then reboot.
- TWRP: Power + Volume up **with slot B active** (TWRP is only in `boot_b`).
- Bootloop after a port update: flash the release again with "keep data" (Enter).
- Linux does not start after a port update (beta5 or older scripts): flash your Linux boot image to `boot_a` again and
  erase `dtbo_a` again.

## 8. Never do this

- Do not replace `boot_b` or erase `dtbo_b`: ColorOS and TWRP boot from them.
- Do not erase `persist`, `modemst1`, `modemst2`, `fsg`, `fsc`, `metadata`, `devinfo`, `keystore`, `frp` or other
  calibration and key partitions.
- Do not flash firmware (`xbl`, `abl`, `tz`, `keymaster`, ...) from another device or another ROM to get a boot menu.
- Do not flash a generic SM8250 image or an image for another tablet.
- Do not run a rootfs flasher that writes to `userdata` (for example the default postmarketOS flasher) if you want to
  keep Android.
- Do not restore a stock partition table over a changed layout: it removes the Linux partitions.
- Do not use `rawdump`, `rescue`, `cust` or `vm-linux_a/b` as Linux storage.
- Do not relock the bootloader.

## 9. Why a rebuilt vendor image can bootloop

A rebuilt EROFS image must keep the SELinux label (`security.selinux`), the file capabilities, the owner, the group
and the mode of each file, and the symbolic links. The vbmeta / AVB state must also agree with the new image. The
port build (`maintainer/port/port.sh`) extracts the images with `fsck.erofs --extract --xattrs --preserve` and checks
the labels before it makes the images.

## Sources

- AOSP, file-based encryption: https://source.android.com/docs/security/features/encryption/file-based
- AOSP, metadata encryption: https://source.android.com/docs/security/features/encryption/metadata
- AOSP, hardware-wrapped keys (`wrappedkey_v0` and upstream Linux): https://source.android.com/docs/security/features/encryption/hw-wrapped-keys
- AOSP, A/B slots and updates: https://source.android.com/docs/core/ota/ab
- AOSP init, SELinux mode: https://android.googlesource.com/platform/system/core/+/refs/heads/main/init/selinux.cpp
- Linux kernel, fscrypt: https://docs.kernel.org/filesystems/fscrypt.html
- TheMojoMan, pipa Linux images and slot install: https://github.com/TheMojoMan/xiaomi-pipa
- TheMojoMan, pipa EFI multiboot: https://github.com/TheMojoMan/xiaomi-pipa/blob/main/pipa-multiboot.md
- HyperOS dual boot and update reports (TheMojoMan issue 7): https://github.com/TheMojoMan/xiaomi-pipa/issues/7
- Fedora on pipa, dual-boot guide: https://github.com/greed0802/pipa-fedora-builder-43/blob/main/DUALBOOT.md
- edk2-msm (pipa UEFI target): https://github.com/edk2-porting/edk2-msm
- Close-to-mainline pipa kernel: https://github.com/MollySophia/linux-mainline-pipa
- postmarketOS pipa page: https://wiki.postmarketos.org/wiki/Xiaomi_Pad_6_(xiaomi-pipa)
- Windows on pipa: https://github.com/arisfadillahh/windows-pipa
