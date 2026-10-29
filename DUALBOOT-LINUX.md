# Dual boot with Linux: Android storage and SELinux

This page answers a common question: "Can Linux in a dual boot read the internal storage of the ColorOS 17 port?"

## Short answer

- **No.** Linux cannot read the encrypted `/data` of this port.
- **SELinux permissive does not help.** SELinux does not hold or make encryption keys.
- `androidboot.selinux=permissive` on the kernel command line does nothing on this port. This is a `user` build.
  Android init uses that value only when it is built with `ALLOW_PERMISSIVE_SELINUX` (userdebug and eng builds).
- To share files between Android and Linux, use a separate drive or copy the files over the network.

## Why Linux cannot read `/data`

The port uses the encryption settings of the pipa vendor (`/vendor/etc/fstab.qcom`):

```
/data  f2fs  inlinecrypt  fileencryption=aes-256-xts:aes-256-cts:v2+inlinecrypt_optimized+wrappedkey_v0,
                          metadata_encryption=aes-256-xts:wrappedkey_v0,keydirectory=/metadata/vold/metadata_encryption
```

- There are two layers of encryption:
  1. **Metadata encryption** encrypts the full partition below f2fs. You cannot mount the raw `userdata` partition.
  2. **File-based encryption (FBE) v2** encrypts the file names and the file contents in f2fs.
- Both layers use **hardware-wrapped keys** (`wrappedkey_v0`). The raw keys never exist in software. Only the
  Qualcomm TEE (keymaster 4.0) and the inline crypto engine (ICE) of the SoC can use them. The keys for user data
  (credential-encrypted storage) also need your lock-screen credential.
- AOSP says that the legacy format `wrappedkey_v0` is not compatible with the upstream Linux kernel. The new
  hardware-wrapped key support in Linux 6.16 is for a different format.
- TWRP in the port's boot image can decrypt `/data`, because TWRP runs the Android keymaster in the TEE. A normal
  Linux system does not have this stack.

We know of no Linux project for pipa that can unlock this storage.

## What works

### 1. Separate shared storage (recommended)

- Use a USB drive or a separate partition with a file system that both systems can use (for example exFAT or ext4).
- Or copy files over the network: MTP, ADB, Syncthing, SMB. Copy them while Android runs and is unlocked.

Android stays encrypted. This is the safe choice.

### 2. A ROM without encryption (not available, not tested)

It is possible to remove `fileencryption=`, `metadata_encryption=` and `keydirectory=` from the fstab. Then:

- You must **format `userdata`**. All data is lost. A change of the fstab does not decrypt old files.
- All copies of the fstab must agree (vendor and first-stage ramdisk).
- Android requires FBE since Android 10. We do not know if ColorOS 17 works without it: the lock screen, the work
  profile and some apps can fail.
- Anybody with the tablet can then read all your data, for example with TWRP.
- Linux must also support the f2fs features that Android uses (for example casefold and compression).

The port does not offer this variant now. If you want to test it, ask in the group.

## Partition layout of the port (for dual boot)

Checked on the maintainer's tablet (2026-10-29, 128 GB model):

| Partition | Content |
|---|---|
| Active slot | **B**. The port boots from slot B. |
| Firmware (`abl`, `xbl`, `tz`, `modem`, `dsp`, `keymaster`, `bluetooth`, ...), `vendor_boot`, `dtbo` | **The same on slot A and slot B.** `FlashLinux.sh` writes the `_ab` targets, which writes both slots. |
| `boot_b` (192 MB) | The port kernel + TWRP. Do not replace it. |
| `boot_a` (192 MB) | The release kernel (beta5: walt-r6). The port does not boot from it. **This is the place for a Linux or UEFI boot image.** |
| `super` (8.5 GB) | The ROM, only in the slot B logical partitions. |
| `userdata` (106.6 GB) | Android data, encrypted. It uses all the remaining space. There is no free space for Linux. |
| `vm-linux_a/b`, `rawdump` | Not free space. Do not use them. |

## Dual boot methods that people use on pipa

These methods are documented by the pipa Linux community. **We did not test them with this port.**

1. **Linux boot image in the other slot** (TheMojoMan `xiaomi-pipa`). Flash the Linux boot image to `boot_a`, erase
   `dtbo_a` (mainline Linux needs an empty DTBO), then select slot A to boot Linux. Select slot B to boot ColorOS.
2. **UEFI in the other slot** (TheMojoMan `pipa-multiboot`, Mu-Qcom / edk2-msm). Flash the pipa UEFI image to `boot_a`.
   UEFI shows a rEFInd menu and starts Linux (or Windows) from an EFI system partition.
3. **`fastboot boot`** of a Linux image from a PC. Nothing is written to the boot partitions, and the next normal boot
   starts ColorOS again. Linux must have its root file system on USB storage or in RAM.

Switch slots in the bootloader: `fastboot set_active a` (Linux) and `fastboot set_active b` (ColorOS).

**Linux needs its own partition for its root file system.** The encrypted `userdata` cannot hold it. Thus, an
installed dual boot needs a smaller `userdata` and a GPT change. This **formats all Android data**. Make a file-level
backup first (on the tablet, while Android is unlocked). Use the sector values of your own tablet, never the
values from a guide for another storage size.

### Encryption and other ROMs

- **You do not need to turn off Android encryption for dual boot.** Linux boots from its own boot image and its own
  root partition. Encryption only stops Linux from reading the Android files.
- The same methods are used with HyperOS (reported in TheMojoMan issue 7). We found no verified reports for
  LineageOS, crDroid, PixelOS, Evolution X or this port. The method does not depend on the ROM name. What matters is
  which partitions the ROM installer and updater write.

### Updating the port when Linux is on slot A

- **`FlashLinux.sh` / `FlashWindows.bat` of the release overwrite Linux.** They flash `boot_ab` and `dtbo_ab` (both
  slots), also for a dirty flash ("keep data"). After a port update, flash your Linux boot image to `boot_a` again
  and erase `dtbo_a` again. Keep copies of them.
- On Android ROMs with A/B OTA updates, an OTA writes the inactive slot (= the Linux slot) and switches to it. HyperOS
  users reported Linux boot failures after updates. This port has no OTA updater.
- Before an update, keep a copy of your Linux boot image, the EFI files and your partition table.

### Never do this

- Do not replace `boot_b` or erase `dtbo_b`: ColorOS and TWRP boot from them.
- Do not erase `persist`, `modemst1`, `modemst2`, `fsg`, `fsc`, `metadata` or other calibration and key partitions.
- Do not flash a generic SM8250 image or an image for another tablet.
- Do not run a rootfs flasher that writes to `userdata` while you want to keep Android.
- Do not restore a stock GPT over a changed partition layout.
- Do not relock the bootloader.
- Do not use `qbootctl` (a reported endless fastboot loop on pipa).

## Why a rebuilt vendor image can bootloop

A rebuilt EROFS image must keep:

- the SELinux label (`security.selinux`) of each file,
- the file capabilities, the owner, the group and the mode of each file,
- the symbolic links.

Also, the vbmeta / AVB state must agree with the new image. The port build (`maintainer/port/port.sh`) extracts the
images with `fsck.erofs --extract --xattrs --preserve` and checks the labels before it makes the images.

## Sources

- AOSP, file-based encryption: https://source.android.com/docs/security/features/encryption/file-based
- AOSP, metadata encryption: https://source.android.com/docs/security/features/encryption/metadata
- AOSP, hardware-wrapped keys (`wrappedkey_v0` and upstream Linux): https://source.android.com/docs/security/features/encryption/hw-wrapped-keys
- Linux kernel, fscrypt: https://docs.kernel.org/filesystems/fscrypt.html
- Linux kernel, inline encryption: https://docs.kernel.org/block/inline-encryption.html
- AOSP init, SELinux mode: https://android.googlesource.com/platform/system/core/+/refs/heads/main/init/selinux.cpp
- Linux kernel, f2fs: https://docs.kernel.org/filesystems/f2fs.html
- TheMojoMan, pipa Linux images and slot install: https://github.com/TheMojoMan/xiaomi-pipa
- TheMojoMan, pipa EFI multiboot: https://github.com/TheMojoMan/xiaomi-pipa/blob/main/pipa-multiboot.md
- edk2-msm (pipa UEFI target): https://github.com/edk2-porting/edk2-msm
- Close-to-mainline pipa kernel: https://github.com/MollySophia/linux-mainline-pipa
- postmarketOS pipa page: https://wiki.postmarketos.org/wiki/Xiaomi_Pad_6_(xiaomi-pipa)
- AOSP, A/B slots: https://source.android.com/docs/core/ota/ab/ab_implement
- HyperOS dual boot and update reports (TheMojoMan issue 7): https://github.com/TheMojoMan/xiaomi-pipa/issues/7
- Fedora on pipa, dual-boot guide: https://github.com/greed0802/pipa-fedora-builder-43/blob/main/DUALBOOT.md
