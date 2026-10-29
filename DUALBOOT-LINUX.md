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
