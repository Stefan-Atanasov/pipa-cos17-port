# Handoff: rebuild the whole pipa port setup from zero (runbook for a person or a local AI model)

This runbook tells how to make the full maintainer setup of the ColorOS 17 port for the Xiaomi Pad 6 (`pipa`) on a new
Linux PC: tools, inputs, kernel, ROM build, the first flash of a tablet, tests, release and publish. It is written
for a local AI model with a small context window. `PORTING-GUIDE.md` explains *why* the port is made this way; this
file tells *what to do, in which order, and how to check each result*.

Status: 2026-11-19, release v9 (ROM build pt128 = `port.sh` up to step 7x, kernel `walt-hi9`).

- **Part A** rebuilds the current port from its pinned inputs (the normal case).
- **Part B** tells how to make the base that Part A starts from (beta4) when you do not have it, or for another
  device.

## How to use this file (read this first)

1. Read section 0 (rules). Then do one phase at a time. Do not read ahead into later phases: they need the results
   of the earlier ones.
2. Each phase has: **Goal**, **Needs**, **Do**, **Done when** (a check you must run), **If it fails**.
3. Do not start the next phase until every "Done when" check of the current phase passes. Write the result of each
   check in `HISTORY.md` (date, phase, command, result).
4. When a command fails, stop. Read the error. Look for it in "If it fails", then in `docs/GOTCHAS.md` (search for a
   word of the error). Do not guess a fix that changes the tablet. **After two failed tries, stop and report to the
   person:** the command, the last 20 lines of its output and what you tried. Never "fix" a failure with `--force`,
   `PORT_FORCE=1`, changed hashes or more `sudo`.
5. **In the public repository** (`pipa-cos17-port`) the documents are at the root (not in `docs/`), the bug table is
   `BUGS.md`, and the state files (`HISTORY.md`, `MAINTAINER-STATUS.md`, `DEVICE-STATE.md`, `NEXT-SESSION-PROMPT.md`)
   do not exist. Make them (empty) at the start. The private repository and the kit have all of them.
6. Placeholders used below:

| Name | Meaning | Maintainer value |
|---|---|---|
| `$ROOT` | the root folder of the setup | `~/Documents/pipa` |
| `$C` | the repository folder, `$ROOT/COS17` | |
| `$K` | the kernel folder, `$ROOT/port-work/kernel` | |
| `$B4` | the extracted beta4 release, `$C/ColorOS17 Port for pipa-beta4-20261017` | |
| `<serial>` | the USB serial of the tablet (`adb devices`) | not given here |

**Set the variables at the start of every shell.** An AI agent gets a new shell for each command: put this block in
front of every command (or in a file that you `.` (source) each time):

```sh
export ROOT="$HOME/Documents/pipa" C="$HOME/Documents/pipa/COS17" K="$HOME/Documents/pipa/port-work/kernel"
export B4="$C/ColorOS17 Port for pipa-beta4-20261017"     # the name has spaces: always write "$B4" in quotes
export SERIAL=<serial> ADB="adb -s <serial>"                # after A8, when the tablet is known
```

The scripts find `$ROOT` from their own location when the repository is at `$ROOT/COS17`. If it is somewhere else, give
`PIPA_ROOT` to each command (`sudo env PIPA_ROOT="$ROOT" sh ...`).

## 0. Rules (always)

These rules come from `AGENTS.md` and `CLAUDE.md`. A local model must follow them exactly.

1. **The tablet is a real device with the owner's data.** Ask the person before each flash, wipe, reboot,
   `pm uninstall` or other persistent change. Say what you will do and how to undo it (the rollback). (This is
   stricter than the maintainer's own rule, which allows test flashes with a one-line "what + rollback". Keep the
   strict rule until the person says otherwise.)
2. **Never run `FlashLinux.sh`, `FlashWindows.bat` or `FlashMac.sh`.** Only the person runs them (they can erase
   all data).
3. **Never store passwords, PINs or keys** in files, logs, commits or notes. The one exception: the tablet PIN is in
   `~/.config/pipa/tablet-pin` (mode 600), written by the person, read only by `maintainer/tab.sh`.
4. **Never commit or share `helper/keys/`** (the helper signing key).
5. **No proprietary binaries in the public repository** (`*.so`, `*.jar`, `*.apk`, images). `BLOBS.md` lists them.
6. **Never replace `/data/adb/ksud`** on the tablet. The SukiSU Nova manager updates it.
7. **One change per test build.** Name the rollback before each flash. Record each tablet change in
   `DEVICE-STATE.md`.
8. **Verify before you claim.** A check command or a screenshot, not "it should work".
9. **Restore stock OPPO behaviour.** A fix gives the OPPO userspace what it expects. Do not add hacks that hide a
   symptom.
10. **A new fix is a new step file** (`maintainer/port/steps/`). Never edit images by hand.
11. Commit each change in `$C` with a short message. No AI attribution lines in commit messages (the owner's rule).
12. Write documents in simple, short sentences (ASD-STE100 style), like the existing docs.
13. **Never `sed -i` (or `mv`) a file in a ROM tree.** It drops the SELinux label. Write with `cat new > old`.
14. **Never install the donor OTA on the tablet.** Never kill `system_server` (reboot instead). Never read files
    named `*keybox*`. Never run a live `ksud sepolicy patch` (it hung the kernel).
15. **Only one agent uses the tablet at a time.** Before a live change, check that no other agent or tool is
    connected to it (on the maintainer PC: `pgrep -af opencode`).
16. Use the system `fastboot` and `adb` (from `android-tools`). The copies in the release `bin/` folders have no
    exec bit.
17. Test each new `pipa_port` service command in its SELinux domain first:
    `su -c 'runcon u:r:pipa_port:s0 <cmd> </dev/null >/data/local/tmp/out 2>&1'`.

---

# Part A: rebuild the current port from its inputs

## A1. Host and tools

**Goal:** a Linux PC that can build the ROM and the kernel.

**Needs:** Linux (the maintainer uses CachyOS, Arch based), 100 GB free on an SSD, internet, a user with `sudo`.

**Do:**

1. Install the packages. Arch:

```sh
sudo pacman -S --needed erofs-utils android-tools python attr rsync unzip 7zip jdk21-openjdk git \
  bc bison flex openssl cpio lz4 make gcc perl libelf pahole rclone github-cli
```

   Debian/Ubuntu (names differ; `erofs-utils` must be 1.9 or newer, build it from source if the distribution has an
   older one):

```sh
sudo apt install erofs-utils android-sdk-libsparse-utils adb fastboot python3 attr rsync unzip 7zip \
  openjdk-21-jdk git bc bison flex libssl-dev cpio lz4 make gcc perl libelf-dev dwarves rclone gh
```

   `lpmake`, `lpunpack` and `simg2img` must be on the `PATH` (Arch: in `android-tools`). Versions used: erofs-utils
   1.9.4, android-tools 37.0.0, Python 3.14, OpenJDK 21.

2. Install the Android SDK command-line tools (from developer.android.com, "Command line tools only") into
   `~/Android/Sdk/cmdline-tools/latest/`. Then:

```sh
~/Android/Sdk/cmdline-tools/latest/bin/sdkmanager "build-tools;37.0.0" "platforms;android-37.0" "ndk;30.0.16248370"
```

   The scripts use exactly `build-tools/37.0.0` and `platforms/android-37.0`. The NDK is only for test tools and the
   face add-ons.

3. Make the root folder and get smali, baksmali and apktool:

```sh
mkdir -p $ROOT/tools/smali $ROOT/tools/apktool $ROOT/port-work
cd $ROOT/tools/smali
curl -LO https://bitbucket.org/JesusFreke/smali/downloads/smali-2.5.2.jar
curl -LO https://bitbucket.org/JesusFreke/smali/downloads/baksmali-2.5.2.jar
curl -L -o $ROOT/tools/apktool/apktool.jar \
  https://github.com/iBotPeaches/Apktool/releases/download/v2.12.1/apktool_2.12.1.jar
```

4. Get the kernel compiler (AOSP clang r547379 = clang 20, about 1 GB unpacked):

```sh
mkdir -p $K/clang-r547379 && cd $K/clang-r547379
curl -L https://android.googlesource.com/platform/prebuilts/clang/host/linux-x86/+archive/refs/heads/main/clang-r547379.tar.gz | tar xz
```

   This link answered on 2026-11-19. Google removes old compilers from `main` after some time. If the link gives an
   error page (404, or `tar` says "not in gzip format"), open
   https://android.googlesource.com/platform/prebuilts/clang/host/linux-x86/+refs, take a release branch or tag that
   still has the folder `clang-r547379`, and use it in place of `refs/heads/main`.

**Done when:**

```sh
mkfs.erofs --version; fsck.erofs --version; lpmake --help 2>&1 | head -1; simg2img 2>&1 | head -1
java -version 2>&1 | head -1                                    # 21
ls ~/Android/Sdk/build-tools/37.0.0/apksigner ~/Android/Sdk/platforms/android-37.0/android.jar
ls $ROOT/tools/smali/*.jar $ROOT/tools/apktool/apktool.jar
cat $K/clang-r547379/AndroidVersion.txt                         # "20.0.0" and "based on r547379"
df -h $ROOT                                                     # 100 GB or more free
```

**If it fails:** Debian and Ubuntu have no `lpmake`/`lpunpack` package. Build `android-tools` from source
(https://github.com/nmeum/android-tools, it has `lpmake`, `lpunpack`, `simg2img`) or use an Arch container.

## A2. The repository and the private files

**Goal:** `$C` has the repository with all files that the build needs.

There are three sources. Use the first one you have:

| Source | What it has | How to get it |
|---|---|---|
| Private kit `pipa-cos17-port-kit-<date>.tar.gz` | docs, scripts, sources, proprietary files; with `KIT_INPUTS=1` also `port-overlay`, Google apps, smali/apktool, SukiSU APKs (about 860 MB) | from the maintainer (made with `sh maintainer/make_port_kit.sh`) |
| Private GitHub repository `pipa-cos17-private` | the full maintainer workspace in git | the maintainer must give you access |
| Public repository `pipa-cos17-port` | docs and sources, **no** proprietary files, no signing key | `git clone https://github.com/Stefan-Atanasov/pipa-cos17-port` |

**Do:**

1. Put the repository at `$C`:
   - Kit: `mkdir -p "$ROOT" && tar xzf <kit> -C "$ROOT"`, then rename the kit folder to `COS17`. A kit made with
     `KIT_INPUTS=1` also has `port-inputs/` and `tools/`: **move these two next to `COS17/`** (to `$ROOT/port-inputs`
     and `$ROOT/tools`). `port-overlay/` and `kernel/sukisu-*/` stay in `COS17/`. Read `KIT-README.md` in the kit.
   - Git: `git clone <url> "$C"`.
2. With the public repository only: get each file in `BLOBS.md` (columns "Path", "What", "Where from"; in the
   private repository it is `maintainer/port-repo/BLOBS.md`) and put it at its path. Most
   come from the beta4 release or the original developer's `pipa_core` module; some you build (`build_facecrop.sh`,
   `build_eyeguard.sh`, `patch_qdcm.py`, ...). Without them, `port.sh --check` names the missing ones.
3. Never take the maintainer's `helper/keys/`. You make your own key in A5.

**Done when:** `ls $C/maintainer/port/port.sh $C/maintainer/port/steps | head` works and
`ls $C/maintainer/port/steps | wc -l` shows 144 (v9).

## A3. The inputs

**Goal:** all large inputs are in their folders with the correct hashes.

| Input | Put it in | Check |
|---|---|---|
| beta4 release `ColorOS17 Port for pipa-beta4-20261017.7z` (by 梦归zzz, Coolapk) | `$C/` | sha256 `31893e62835843a63f73b96fc095545cefded76aca684161295c15cd2490f78f` |
| donor OTA `OPD2515_11.C.07_1070_202610201803.zip` (OPPO Pad Mini, CN) | `$ROOT/donor/OPD2515_11.C.07/` | sha256 `e23488a76e16c1a9c3f7e2a804cb9f2b8c540b8b4166dbbdfc56c70cc2dac42d` |
| donor OTA `OPD2515_11.C.06_1060_202610061842.zip` (its `vendor` and `odm` only, step 3d) | `$ROOT/donor/OPD2515_11.C.06/` | sha256 `aeeb3029c64f3a7251bf861325a21388c1817739c8684155ba7daa71f6beb8d5` |
| SukiSU Nova manager `SukiSU_Nova_v3.0.0_35000-arm64-v8a-release.apk` (step 7u, release) | `$C/kernel/sukisu-nova-3.0.0/` | sha256 `1202adb835a64d8b3df703da7884a2966f8728c131cffb29fb5f48d31d81ac85`; https://github.com/SukiSU-Nova/SukiSU-Nova/releases/download/v3.0.0/SukiSU_Nova_v3.0.0_35000-arm64-v8a-release.apk |
| SukiSU-Ultra manager `SukiSU_v4.3.0_41100-release.apk` (step 2w; later steps replace it) | `$C/kernel/sukisu-v4.3.0/` | sha256 `a928eb57ad34b105233f92dcd55e54dd883482e417970276329a7d0f0979e212` |
| SukiSU-Ultra manager `SukiSU_v4.3.0-r1_41140-release.apk` (step 5m) | `$C/kernel/sukisu-v4.3.0-r1/` | sha256 `79a0db803e1f0bb952760f19250e5fc92566e2569581e4123c9db0b5e3c46bb9` |
| Google apps, 4 packages: Play Store `com.android.vending`, Gboard `com.google.android.inputmethod.latin`, Google app `com.google.android.googlequicksearchbox`, Gemini `com.google.android.apps.bard` (base APK + splits) | `$ROOT/port-inputs/apps-5u/<package>/` (next to `COS17/`, not in it) | `SHA256SUMS` in the folder |
| stock `libhwdap` files (step 5z) | `$ROOT/port-inputs/dolby-5z/` | from the kit (`SHA256SUMS`) |
| `pipa-susfs-v1.0.zip` (release extras only) | `$C/` | from the maintainer or the Drive folder `modules/` (the kit has only its source, `susfs-module/`) |

**Do:**

1. The beta4 release: get it from the maintainer or the author's channel. If you cannot get it, go to Part B.
2. The donor OTAs: OPPO's servers give a signed link for about 10 minutes. The maintainer uses OPlus-Tracker
   (third-party code: read it first):

```sh
git clone https://github.com/Deuteriunt/OPlus-Tracker "$ROOT/tools/OPlus-Tracker" && cd "$ROOT/tools/OPlus-Tracker"
python3 -m venv venv && venv/bin/pip install -r requirements.txt
venv/bin/python tomboy_pro.py OPD2515_11.C cn        # prints the link of the newest full OTA
mkdir -p "$ROOT/donor/OPD2515_11.C.07" && curl -C - -o "$ROOT/donor/OPD2515_11.C.07/<file>.zip" "<link>"
```

   Old versions (C.06) can disappear from the server: keep your copies.
3. The Google apps: on any tablet with Google Play, install the four apps, then pull them
   (`docs/BUILD.md` section 1.3, item 5).
4. Check every hash: `sha256sum <file>`.

**Done when:** every hash in the table matches.

**If it fails:** a different donor version needs a rebase (`docs/REBASE.md`). Do not change the pinned hashes to
make the check pass.

## A4. Prepare the inputs

**Goal:** the folders that `port.sh` reads exist.

**Do:** follow `docs/BUILD.md` section 1.3, items 1 to 3, exactly. In short:

```sh
cd $C && 7z x "ColorOS17 Port for pipa-beta4-20261017.7z"
mkdir -p work/parts && simg2img "$B4/super/super.img" work/super_raw.img && lpunpack work/super_raw.img work/parts
cd $ROOT/donor/OPD2515_11.C.07 && unzip OPD2515_11.C.07_1070_202610201803.zip payload.bin && mkdir -p img
python3 -I $C/maintainer/payload_extract.py payload.bin img system system_ext product my_product my_manifest \
  my_stock my_region my_heytap my_bigball my_carrier my_engineering
cd ../OPD2515_11.C.06 && unzip OPD2515_11.C.06_1060_202610061842.zip payload.bin && mkdir -p ../../port-work/donor-c06-vendor
python3 -I $C/maintainer/payload_extract.py payload.bin ../../port-work/donor-c06-vendor vendor odm
```

Then make `$C/port-overlay/` (skip this if the kit with `KIT_INPUTS=1` gave it to you). The list of its 49 files is
`maintainer/c06-vs-beta4/port-overlay.md5`: a path `./system/<p>` comes from the root of the beta4 `system` image, a
path `./system_ext/<p>` from the root of the beta4 `system_ext` image. Copy them as root with owners, modes and SELinux
labels:

```sh
X="$ROOT/port-work/b4x"; mkdir -p "$X"
sudo fsck.erofs --extract="$X/system" --xattrs --preserve "$C/work/parts/system_b.img"
sudo fsck.erofs --extract="$X/system_ext" --xattrs --preserve "$C/work/parts/system_ext_b.img"
cd "$C" && sudo mkdir -p port-overlay/system port-overlay/system_ext && for part in system system_ext; do
  awk -v p="./$part/" 'index($2,p)==1 {print substr($2,length(p)+1)}' maintainer/c06-vs-beta4/port-overlay.md5 > "$X/list-$part"
  sudo rsync -aX --files-from="$X/list-$part" "$X/$part/" "port-overlay/$part/"
done
sudo rm -rf "$X"        # about 8 GB; only after the md5 check below passes
```

**Done when:**

```sh
md5sum $C/work/parts/vendor_b.img $C/work/parts/odm_b.img
#   b601a907363d01e78697cd5d4f60edf6  vendor_b.img
#   8e25ab23745ad3d9abb7a3312abe3e23  odm_b.img
cd $C/port-overlay && sudo md5sum -c --quiet ../maintainer/c06-vs-beta4/port-overlay.md5 && echo overlay OK
ls $ROOT/donor/OPD2515_11.C.07/img/system.img $ROOT/port-work/donor-c06-vendor/vendor.img
```

`payload_extract.py` needs only the Python standard library. It checks the SHA-256 of each operation.

**Final check of all inputs** (after A5, because it also checks the helper APK and `cryptoeng.jar`). It runs as the
normal user and builds nothing:

```sh
cd "$ROOT" && sh COS17/maintainer/port/port.sh --check check1 donor/OPD2515_11.C.07/img
```

It must end with `preflight ok (nothing built)`. Each `MISSING input of <step>` line names a file that you still
need: get it, then run the check again.

## A5. Build the parts from the repository (helper app, cryptoeng)

**Goal:** the helper APK and `cryptoeng.jar` exist, signed with **your** key.

**Do:**

```sh
cd $C
sh helper/build.sh                  # makes helper/keys/ (new RSA key) the first time; output helper/out/PipaHelper.apk
sh maintainer/cryptoeng/build.sh    # output maintainer/cryptoeng/cryptoeng.jar
```

**Done when:** `~/Android/Sdk/build-tools/37.0.0/apksigner verify --print-certs helper/out/PipaHelper.apk` shows
`CN=pipa port helper`, and `ls maintainer/cryptoeng/cryptoeng.jar` works.

WARNING: Back up `helper/keys/` to a private place (not git, not the cloud without encryption). All later ROM builds
and helper updates must use the same key.

NOTE: Your helper has a different signature than the maintainer's. After a dirty flash of your build over the
maintainer's release (or the reverse), Android can keep the old helper or drop its data. Use a clean flash when you
change keys, and check `adb shell dumpsys package com.port.pipa.helper | grep versionName`.

## A6. Build the kernel

**Goal:** a boot image with the `walt-hi9` kernel (Linux 4.19.325, SukiSU Nova 3.0.0 built in, susfs 2.3.0).

**Needs:** A1 (clang), the beta4 release (for the base `boot.img` with TWRP and for `magiskboot`).

**Do:** (the public route; the maintainer's scripts in `maintainer/kernel/` do the same with their own paths)

```sh
git clone -b oppo https://github.com/Stefan-Atanasov/kernel_xiaomi_pipa_cos17 $K/walt-oppo
cd $K/walt-oppo
CLANG=$K/clang-r547379 ./build-pipa-cos17.sh          # about 15 min; output out/arch/arm64/boot/Image
mkdir -p $K/bootimg && cp "$B4/bin/Linux/magiskboot" $K/bootimg/ && chmod +x $K/bootimg/magiskboot
export PATH=$K/bootimg:$PATH
TRIM=1 ./pack-boot.sh out/arch/arm64/boot/Image "$B4/firmware/boot.img" $K/bootimg/boot-mine-trim.img
./pack-boot.sh out/arch/arm64/boot/Image "$B4/firmware/boot.img" $K/bootimg/boot-mine.img
```

The beta4 `firmware/boot.img` is the correct base: it is the same image as the maintainer's partition backup
(`kernel/backup-partitions-20261023/boot_b.img`, same kernel, TWRP 3.7.1 ramdisk, header v3, patch level
2099-12). The `dtbo.img` and `vendor_boot.img` of beta4 are also the same as the backup. To use the maintainer
scripts (`mkboot.sh`, `flash_kernel.sh restore`), make a folder with these three files named `boot_b.img`,
`dtbo_b.img`, `vendor_boot_b.img` and set `BK=<that folder>`.

**Done when:**

```sh
ls -l $K/bootimg/boot-mine.img                         # 201326592 bytes (192 MiB)
head -c 20 $K/bootimg/boot-mine.img | tail -c 4 | od -An -tx1    # 3c 06 00 20 (same as the base)
```

**If it fails:**

- Black screen after a flash and no log: the patch level bytes are wrong. Never pack with `magiskboot repack`
  alone. Use `pack-boot.sh` or `mkboot.sh`.
- `fastboot boot` hangs: you used the full image. Use the `TRIM=1` image for `fastboot boot`.
- `unifdef` is not needed by `build-pipa-cos17.sh`. Only the maintainer's `maintainer/kernel/oppo_extract.sh` (a
  research tool) uses `$K/tools/unifdef`.
- Do not use `pipa_defconfig`. The script merges `kona-perf_defconfig` and the `xiaomi/*.config` fragments.

## A7. Build the ROM

**Goal:** `port-work/<tag>/img/super.img`, the same content as v9 (pt128).

**Do:**

```sh
cd $ROOT
sh COS17/maintainer/port/port.sh --check mybuild1 donor/OPD2515_11.C.07/img        # preflight, builds nothing
sudo sh COS17/maintainer/port/port.sh mybuild1 donor/OPD2515_11.C.07/img            # about 4 min, 40 GB free needed
```

Use a new tag for each run (the run deletes `port-work/<tag>/`). The default build applies all steps to 7x and leaves
out the optional steps 2u, 3k, 3x and 5s. Never publish a build with `PORT_MAINTAINER_ADB=1` (step 5s).

**Done when:**

- The output ends with the `super.img` path and its md5. Write the md5 down.
- `port-work/mybuild1/report/PORT-REPORT.txt` lists every step with no error.
- To compare with the maintainer's pt128, compare the manifests `report/<partition>.tsv` (path, mode, owner, md5,
  label), not the image md5 (each image has a random UUID). Your helper APK and files signed with your key differ;
  all other rows must match.

**If it fails:** `docs/BUILD.md` section 2.2. There is no resume: fix, then run again from the start. Do not flash an
image from a run that stopped.

## A8. Prepare the tablet (one time)

**Goal:** a tablet with an unlocked bootloader, the port flashed, USB debugging and root for the shell.

**Needs:** a Xiaomi Pad 6 (`pipa`), a USB-C data cable, the person (the AI cannot press buttons or run the flash
scripts).

**Do (the person):**

1. **Unlock the bootloader** on stock HyperOS. This is Xiaomi's own procedure and not part of this repository: in
   Settings, turn on Developer options and bind the Xiaomi account in "Mi Unlock status", then use the official Mi
   Unlock tool in fastboot mode. Xiaomi sets a wait time and rules that change. All data is erased. Never relock the
   bootloader with a port on the tablet.
2. **First flash:** use a release package: the public `ColorOS17-Port-pipa-v9-<date>.7z`, or your own package
   (A11 step 2 makes it; you can run that step before this one). `flash_super.sh` (A9) cannot do the first flash: it
   writes only `super`.
   Extract it. Put the tablet in fastboot mode (Power + Volume down). Run `FlashLinux.sh` (Linux),
   `FlashWindows.bat` (Windows) or `FlashMac.sh` and answer `y` (clean flash). The script writes the firmware, `boot`,
   `dtbo`, `vendor_boot`, `vbmeta` and `vbmeta_system` to both slots (the beta4 `vbmeta.img` has flags 3: verity and verification
   off), writes `super` (slot B only), sets slot B active and erases `userdata` and `metadata`.
3. Wait for the first boot (some minutes). Do the setup wizard.
4. Turn on USB debugging: Settings > About tablet (or About device) > Version > tap "Build number" 7 times; then Developer options >
   USB debugging. Connect USB, accept the RSA key prompt. Cancel the "Use USB for" dialog.
5. Root for the shell: open the SukiSU Nova manager (the ROM installs it) > Superuser > allow "Shell".
6. Write the lock-screen PIN for `tab.sh` (the person types it; never put it in a command line that is logged):
   `mkdir -p ~/.config/pipa && install -m 600 /dev/null ~/.config/pipa/tablet-pin`, then edit the file and put only the PIN digits in it.

**Done when (the AI can run these):**

```sh
adb devices                                       # <serial>  device
adb -s <serial> shell su -c id                    # uid=0(root)
adb -s <serial> shell getprop ro.product.device   # pipa
SERIAL=<serial> bash $C/maintainer/tab.sh unlock  # the screen unlocks
```

**Rescue:** if the tablet does not boot, hold Power + Volume up (slot B active) for TWRP. TWRP gives root ADB and a
decrypted `/data`. See `docs/GOTCHAS.md` and `maintainer/kernel/flash_kernel.sh restore`. Never replace
`/data/adb/ksud`.

## A9. Test your builds on the tablet

**Goal:** flash a test build safely and roll back if it fails.

**Do (ask the person first, name the rollback):**

```sh
sh $C/maintainer/flash_super.sh -y $ROOT/port-work/mybuild1/img/super.img <md5>   # only super, slot B, no wipe
SERIAL=<serial> bash $C/maintainer/kernel/flash_kernel.sh test $K/bootimg/boot-mine-trim.img   # boot once, writes nothing
SERIAL=<serial> bash $C/maintainer/kernel/flash_kernel.sh flash $K/bootimg/boot-mine.img       # writes boot_b
```

- Rollback of the ROM: flash the previous `super.img` with `flash_super.sh` (`-y beta4` flashes the original beta4).
- Rollback of the kernel: `flash_kernel.sh flash <previous boot.img>`. Keep the previous image before you flash.
- Add each image you keep to the `case` list in `maintainer/flash_super.sh` (name, path, md5).
- `flash_super.sh` cannot change the `/data` encryption. A dirty flash never runs the setup wizard: test each
  release with a clean flash (the person runs the release script).

**Done when:** the tablet boots, `adb shell su -c id` works, and A10 passes.

## A10. Verify

**Do:**

```sh
ADB="adb -s <serial>" sh $C/maintainer/device_check.sh mybuild1     # read-only; report in port-work/device-checks/
```

**Done when:** 0 FAIL. The v9 reference after a clean flash: 57 pass, 0 fail, 2 warnings (`logd` capture properties at
the default; `sensorCCT` 0 because adaptive colour is off after a clean flash). After a new kernel also run
`ADB="adb -s <serial>" sh $C/maintainer/kernel/kernel_check.sh <label>`.

Then do the release checklist in `docs/TESTING.md` section 8 (8.2 before the flash, 8.3 flash paths, 8.4 after each
boot: setup wizard, keyboard, root, SukiSU Nova manager, Play Store, Gboard, Google app, face enroll, Wi-Fi,
Bluetooth, pen, ...). The v9 clean-flash test also checked: Gboard is the default keyboard after setup, Settings >
Sound effects shows Dolby Atmos, the Quick Settings tiles Logs and Live blur exist, 0 SELinux denials of the port, 0
crashes.

Other test tools: `maintainer/tab.sh` (unlock, screen cycles, screenshots, refresh rate), perfetto traces
(`docs/TESTING.md`, venv: `python3 -m venv $ROOT/port-work/perfetto-venv && $ROOT/port-work/perfetto-venv/bin/pip install perfetto`).

## A11. Release and publish

**Do:**

1. Write `$C/RELEASE-NOTES-<pkg>.md` and the changelog (copy the form of `RELEASE-NOTES-v9.md`).
2. Make the package. `build_release.sh` also makes `FlashMac.sh` and stops if the macOS platform-tools are
   missing, so unpack them first (the zip has a folder `platform-tools/`, which must land in `darwin/`):

```sh
mkdir -p "$ROOT/port-work/release-tools/darwin" && cd "$ROOT/port-work/release-tools/darwin"
curl -LO https://dl.google.com/android/repository/platform-tools-latest-darwin.zip && unzip -o platform-tools-latest-darwin.zip
ls platform-tools/fastboot
KSU_APK=$C/kernel/sukisu-nova-3.0.0/SukiSU_Nova_v3.0.0_35000-arm64-v8a-release.apk \
  bash $C/maintainer/build_release.sh mybuild1 --boot $K/bootimg/boot-mine.img --pkg <pkg> --name "<text>" --7z
```

3. Clean-flash test of the package (the person runs `FlashLinux.sh`, answer `y`), then A10.
4. Publish (ask the person before each one; these are outward actions):
   - Public repository: `sh maintainer/sync_port_repo.sh "<message>"`. It copies the files into
     `$ROOT/port-work/port-repo` and pushes from there. One time before: `git clone <your public repo url>
     "$ROOT/port-work/port-repo"` (or `git init` there and `git remote add origin <url>`). Change in the script the
     release-notes file names (two lines) and the git name and e-mail.
   - Private backup: `git remote add backup <your private repo url>` one time in `$C`, then `git push backup main`.
   - Kernel source: push your kernel branch to your own GitHub repository.
   - Package upload: `rclone copy <file.7z> gdrive: --drive-root-folder-id <your folder id> -P` (make the remote once
     with `rclone config`; the person logs in).

## A12. Day-to-day work (the fix loop)

1. A bug arrives (tester report or own test). Add a row to `BUGS-TODO.md` (symptom, evidence, status).
2. Find the cause with evidence: logs (`logcat -b all`, `dmesg`, dropbox, ANR traces), and compare with what stock
   OPPO and stock HyperOS do (extract each reference ROM once and keep it).
3. Write the fix as a new step (`maintainer/port/README.md`, "How to add a step"): `cat new > old` (never `sed -i`,
   it drops the SELinux label), one exact anchor that must match once (`replace_once`, `need_grep`), `set_layer` if
   an app or jar changes. Test a new `pipa_port` command in its domain: `su -c 'runcon u:r:pipa_port:s0 <cmd>'`.
4. Build with a new tag (`--until <step> --keep-tree` first if you want to look at the tree).
5. Ask, flash (A9), verify (A10), and write the result.
6. Record: `DEVICE-STATE.md` (what is on the tablet), `HISTORY.md` (what you did), `BUGS-TODO.md` (status),
   `MAINTAINER-STATUS.md` (current build chain), `NEXT-SESSION-PROMPT.md` (where the next session starts). Commit.

State files an agent reads at the start of each session, in this order: `MAINTAINER-STATUS.md`,
`NEXT-SESSION-PROMPT.md`, `BUGS-TODO.md`, `DEVICE-STATE.md`. Skills for Claude Code are in `.claude/skills/`
(`pipa-rom-build`, `pipa-kernel`, `pipa-tablet`, `pipa-tester-bug`, `pipa-delegate`); a local model can read them as
checklists.

## A13. Values to change on a new PC

| Value | Where | Change to |
|---|---|---|
| Tablet USB serial `83836a90` | about 30 test scripts, `tab.sh`, `flash_kernel.sh`, skills | set `SERIAL=<serial>` or `ADB="adb -s <serial>"` for each run |
| Tablet TCP address `192.168.0.37:5555` | `device_check.sh` and 5 other scripts (default `ADB`) | set `ADB="adb -s <serial>"` |
| `/home/stefan/...` | old layer scripts (`build_beta5*.sh`), `.claude/settings.local.json` | not used by `port.sh`; set `PIPA_ROOT` if a script needs it |
| `/mnt/reference` | `port.sh` preflight | only checked when an input is a link to that disk |
| GitHub name, e-mail, repository URLs | `sync_port_repo.sh`, `make_port_kit.sh`, git remotes | your own |
| Release-notes file names | `sync_port_repo.sh` | the new release |
| Drive folder | rclone command (A11) | your own folder |
| Helper key | `helper/keys/` | your own (A5) |

## A14. Known gaps

- The beta4 download link is not in the repository (the author's channel). Part B tells how to make an equivalent
  base.
- The bootloader unlock is Xiaomi's procedure; the repository has no copy of it.
- The OPlus-Tracker tool is third-party code: read it before you run it, and run it in a venv.

---

# Part B: from stock to the beta4 base (without the beta4 download)

Part A takes the device side (firmware, `boot`, `vendor_boot`, `dtbo`, `vbmeta`, `vendor`, `odm`) from the beta4
release. This part tells where each beta4 piece comes from and how to make it from stock or public sources. It is
also the model for a port to another device.

Status (2026-11-19): **offline research only.** The sources below were found by md5 and content compares
(`maintainer/fromstock/`). No from-stock build was flashed yet. Each piece has a status:

- **stock:** a byte-identical file exists in a stock or public ROM.
- **stock + patch:** a stock or public file plus a small, known edit.
- **blob:** made by the beta4 author; no source is known. Keep the beta4 (or `pipa_core`) file.

## B1. What beta4 is made of

| Piece | What it is | From-stock source | Status |
|---|---|---|---|
| Firmware (abl, xbl, xbl_config, aop, tz, hyp, modem, dsp, bluetooth, keymaster, cmnlib*, devcfg, featenabler, imagefv, qupfw, uefisecapp) | HyperOS 2 CN firmware (xbl `BOOT.XF.3.2-00304`, tz `TZ.XF.5.8-00226`, aop `AOP.HO.2.0-00187`, modem `MPSS.HI.2.0.c7`, 2025-08 builds) | `firmware-update/` of iqraOS 3.1 CN 3.0.303: 17 images byte-identical. Official: a HyperOS 2.0.x CN fastboot ROM (`OS2.0.*.UMZCNXM`; the exact version is not identified) | stock, except `abl` |
| `abl` | signed Xiaomi ELF (cert 2025-04-27), differs from iqraOS in 41819 bytes (payload too) | unknown | blob |
| `vbmeta`, `vbmeta_system` | avbtool 1.4.0, AOSP test key (`testkey_rsa4096`, pubkey sha1 `2597c218…`), `vbmeta` flags 3 (verity and verification off), stale descriptors of the Lineage pipa build | rebuild with `avbtool` (B3) | stock + patch (not tested) |
| `boot` kernel | author's build `4.19.325-cip136-st20-N0-kernel++` (Ubuntu clang 20.1.8), KernelSU | **our kernel** (A6). The port uses its own kernel since beta5 (walt-r6) | replaced |
| `boot` ramdisk | TWRP `3.7.1_16-16.0` (`twrp_pipa`, Android 16 base, eng/test-keys, built 2026-10-05 by the author) | no public pipa TWRP found. Alternative: the PixelOS `boot.img` ramdisk (plain first-stage init, same header v3 layout), then there is no TWRP, only the Lineage recovery in `vendor_boot` | blob / alternative |
| `vendor_boot` ramdisk | Lineage recovery (`lineage_pipa`, Android 17, built 2026-08-22, the same build as `vendor`) | PixelOS `vendor_boot` ramdisk is the closest (232 files the same, 160 different) | stock + patch (not tested) |
| `vendor_boot` dtb | kona/pipa dtb, nearly the PixelOS dtb: no `ion-heap@20` (CAMERA), `noirqdebug` in bootargs | PixelOS dtb with these two edits, or our kernel tree's dtb without `kona-coresight.dtsi` and the CAMERA heap, plus `noirqdebug` | stock + patch (not tested) |
| `vendor_boot` cmdline | PixelOS cmdline + `buildvariant=user init_fatal_panic boot_timeout=1800 androidboot.selinux=enforcing ignore_loglevel` | PixelOS cmdline + these words | stock + patch |
| `dtbo` | 13 entries; 12 are md5-identical to PixelOS; the pipa entry adds a GPU `qcom,min-pwrlevel = <0>` fragment | PixelOS `dtbo.img` + that fragment | stock + patch (not tested) |
| `vendor`, `odm` | LineageOS-family Android 17 source build of `device/xiaomi/pipa` + `sm8250-common` (2026-08-22), props changed to OPPO OPD2515, port additions | section B6 | see B6 |
| `super` layout | 9126805504 bytes, metadata 65536, 2 slots, Virtual A/B, groups `qti_dynamic_partitions_a/_b`; only slot B is filled; **no `my_*` partitions** (the donor's `my_*` are folders in `system`) | `port.sh` makes it (`docs/REBASE.md`) | done |
| `system`, `system_ext`, `product` | OPPO OPD2515 donor (beta4 used C.05; the port now uses C.07) + 81 edits (`maintainer/c06-vs-beta4/PORT-EDITS.tsv`: 34 carry, 22 remove, 12 re-apply, 3 re-derive, 4 drop, 6 unsure) | `port.sh` re-applies all of them as steps from the donor; only the carried files (B7) come from beta4 | done, except B7 |

## B2. Firmware

1. Take the `firmware-update/` images of a HyperOS 2 CN build for pipa. The iqraOS 3.1 CN 3.0.303 package has the
   same 17 images as beta4. An official HyperOS 2.0.x CN fastboot ROM is the clean source: download one
   (xmfirmwareupdater.com lists OS2.0.8, OS2.0.11, OS2.0.12 `UMZCNXM`) and compare md5 with
   `maintainer/fromstock/boot/fw-md5.tsv` to find the matching version.
2. Keep `abl` from beta4 until a stock `abl` is tested.
3. The beta4 flash script has no anti-rollback check. A stock `flash_all.sh` compares `images/anti_version.txt` with
   `fastboot getvar anti`. Do this check yourself before you flash older firmware than the tablet has.

## B3. vbmeta

The beta4 images use the public AOSP test key. To make your own (not tested on pipa):

```sh
avbtool make_vbmeta_image --flags 3 --padding_size 4096 --output vbmeta.img
```

This makes an unsigned `vbmeta` with flags 3 (verity and verification off). Keep the beta4 `vbmeta_system.img` (flags
0, test key) until a rebuilt one is tested: with verification off in `vbmeta`, the chained `vbmeta_system` is
probably not checked, but this is not tested on pipa.

Or flash a stock `vbmeta.img` with `fastboot --disable-verity --disable-verification flash vbmeta_ab vbmeta.img`. A
stock `vbmeta` chains `vbmeta_system` with Xiaomi's key; then `vbmeta_system` must also be stock. Check the result
with `avbtool info_image --image <file>` (`Flags: 3`).

## B4. Boot image and recovery

- Kernel: build ours (A6).
- Ramdisk, choice 1: keep the beta4 TWRP ramdisk (A6 uses the beta4 `boot.img` as the base). The TWRP props and
  `twrp.flags` are saved in `maintainer/fromstock/boot/evidence/` for a future TWRP device tree.
- Ramdisk, choice 2 (from stock): use the PixelOS `boot.img` as the base for `pack-boot.sh`. You lose TWRP. Recovery
  is then the Lineage recovery in `vendor_boot` (check that it gives adb and can mount `/data` before you depend on
  it).

## B5. vendor_boot and dtbo

- `vendor_boot` (header v3) = vendor ramdisk + dtb + cmdline. Start from the PixelOS `vendor_boot`, keep its ramdisk,
  apply the dtb edits and the cmdline words of B1, repack with `mkbootimg --header_version 3 --vendor_boot ...` (`unpack_bootimg --format mkbootimg` prints the
  full command with the PixelOS offsets).
- `dtbo` = PixelOS `dtbo.img` with the GPU fragment `qcom,min-pwrlevel = <0>` added to the pipa entry (`mkdtboimg`
  to unpack and pack, `dtc` to edit).
- Our kernel tree can make the dtb and a one-entry pipa `dtbo` too, but they differ from beta4 (coresight nodes,
  fragment numbers). Use the PixelOS route first; it is closer.

## B6. vendor and odm

The beta4 `vendor` is a LineageOS-family **source build** for Android 17 (build id `CP2A.260605.016`, `user`,
2026-08-22), the same family as PixelOS 17 for pipa (`PixelOS_pipa-17.0-20260805`, same build id, `userdebug`). The
author changed the props to OPPO OPD2515, added the port files and took 96 Xiaomi files back from stock HyperOS.

Recipe (no root, makes a tree, not an image): `maintainer/fromstock/vendor/make_vendor_from_stock.sh` and
`make_odm_from_stock.sh`. Full method and lists: `maintainer/fromstock/vendor/REPORT.md`.

1. Make the reference trees. `REF` is a folder with one subfolder for each ROM, and each has the **extracted**
   `vendor/` and `odm/` trees (not images): `pixelos/`, `hyperos1-stock/`, `iqraos3.1/`, `iqraos_v1.0/`. Get the
   images: PixelOS `PixelOS_pipa-17.0-20260805-1810.zip` (`payload.bin` → `payload_extract.py ... vendor odm`), the
   stock HyperOS fastboot ROM and the iqraOS packages (`super.img` → `simg2img` if sparse → `lpunpack`). Extract each
   EROFS image with `fsck.erofs --extract=<REF>/<rom>/vendor --no-preserve <vendor.img>` (for a real image build: as
   root, with `--xattrs --preserve`). An ext4 image needs `debugfs -R "rdump / <dir>" <img>` instead.
2. Extract the donor C.06 `vendor` and `odm` (A4 made the images):

```sh
X="$ROOT/port-work/fromstock/x"; mkdir -p "$X"
fsck.erofs --extract="$X/c06v" --no-preserve "$ROOT/port-work/donor-c06-vendor/vendor.img"
fsck.erofs --extract="$X/c06o" --no-preserve "$ROOT/port-work/donor-c06-vendor/odm.img"
```

   (`extract_trees.sh` does this too, but it also extracts the beta4 `vendor`/`odm` and stops if you do not have
   them.)
3. Make the tree. `OUT` must not exist or must be empty:

```sh
cd "$C/maintainer/fromstock/vendor"
OUT="$ROOT/port-work/fromstock/vendor-tree" REF=<your REF folder> C06V="$X/c06v" C06O="$X/c06o" \
  sh make_vendor_from_stock.sh     # without B4=<beta4 vendor tree>: STANDIN=1, the nearest stock file for each beta4-only binary
OUT="$ROOT/port-work/fromstock/odm-tree" REF=<your REF folder> C06V="$X/c06v" C06O="$X/c06o" sh make_odm_from_stock.sh
```

The steps: copy the PixelOS tree; remove the 36 paths that beta4 removed; add the files with a byte-identical stock
source (HyperOS 1, iqraOS, donor C.06, `pipa_core`); apply the 36 text patches (`patches/vendor/`, byte-exact, `patch
--binary -p1`: build.prop port block, `portenforce.rc`, face HAL rc and vintf, audio XML, camx, powerhint, idc/kl,
SELinux files; the patches hold vendor config text, so they are only in the private repository and the kit, not
in the public one); then the beta4-only binaries from a beta4 tree (`B4=<tree>`) or stand-ins.

| Partition | Paths | Same as PixelOS | From stock with the recipe | Only in beta4 |
|---|---|---|---|---|
| `vendor` | 2161 (1870 files + 291 links) | 1681 | 1827 (84.5 %) | 334 (331 binaries rebuilt from source + 3 text) |
| `odm` | 95 | 10 | 28 | 67 (the OPPO virtual-modem stack of donor C.05, author scripts, `precompiled_sepolicy`) |

What only beta4 has (the vendor gaps):

1. About 306 binaries of the author's Android 17 source build that differ from the PixelOS build at the same path
   (118 `android.*` interface libraries, display and gralloc, Adreno, audio, the boot, health, light, power,
   thermal and Wi-Fi HALs; IPower v7 where PixelOS has v6).
2. The Adreno 2025 stack (`vulkan.adreno.so` with a 40-byte patch, GLES/EGL, `libllvm-qgl`, `libkcl`, a650
   firmware), `vulkan.turnip.so`, `gralloc.qcom.so`.
3. The OPPO performance and stability HAL binaries (from a community "C17 power-key fix" package), camera service
   compat libraries, `android.hidl.manager`.
4. The 32 edited (Xiaomi-encrypted) `thermal-*.conf`, the recompiled `vendor_sepolicy.cil` (user build), the
   `mac_permissions` signer, 4 re-signed apps.
5. `odm`: the C.05 virtual-modem stack. Donor C.06 has a different version (step 3k swaps it in; built, not
   tested). The C.07 `payload.bin` may have a closer `odm` (not extracted yet).

Three ways to get a `vendor`:

| Way | Result | Status |
|---|---|---|
| beta4 `vendor`/`odm` (Part A) | known good | the release way |
| Recipe with `STANDIN=1` (all PixelOS build binaries, no beta4) | one consistent PixelOS build + port files; 15 binaries missing, so their rc/vintf entries are dropped and the IPower manifest stays v6 | not tested (B8, test 1) |
| Build the vendor from source (LineageOS `device/xiaomi/pipa` + `sm8250-common` + `vendor/xiaomi` for Android 17, `user` build, OPPO props), as the author did | the real from-zero way | not tried; needs a full Android source checkout and build |

Rules for a vendor that is not beta4:

- Never mix single libraries of two builds. The display chain (composer, mapper, gralloc, Adreno) stays together.
- The IPower (and every HAL) version in the vintf manifest must match the binary.
- Do not mix `vendor_sepolicy.cil` and `vendor_file_contexts` from different builds.
- Labels: extract PixelOS as root with `fsck.erofs --extract=<dir> --xattrs --preserve`. Give each added or
  replaced file the label of its path in the new `vendor_file_contexts` (`setfattr -n security.selinux`) before
  `mkfs.erofs`. A HAL with a wrong label fails without a clear error.
- `odm` without `precompiled_sepolicy` works, but `init` compiles the policy at each boot (slower).
- With the C.06 modem stack, the AIDL manifest change of steps 3d/3k is necessary.

## B7. Carried system files and the pipa_core files

The 34 `carry` rows of `PORT-EDITS.tsv` (now in `port-overlay/`):

| Files | Source |
|---|---|
| `libFaceDetectCA.so`, `libMegviiUnlock.so`, `libMegviiUnlock-jni-1.2.so`, `libmegface.so` | stock: PixelOS `system/lib64` |
| VNDK v33 apex | stock: HyperOS 1 `system_ext` |
| `etc/media_profiles.xml` | stock: `vendor/etc/media_profiles_kona.xml` of any pipa ROM |
| `panorama_mgb` | an empty file |
| MiSound app and libs, `miuicamera` XMLs, VNDK v30-v32 apexes | stock apps or apexes with changes (another md5 than stock) |
| `FaceUnlock.apk`, `pipa_faceunlock.xml`, `OppoCamera.apk` (Fossify Camera based), 4 `Pipa*Overlay` RROs, `libxiaomipen.so`, `telephony.gsm.xml`, root `build.prop` | author-made: blob |
| `etc/face/model_file` (21 MB Megvii model) | not found anywhere: blob |
| `libupdateprof.qti.so`, `libtrigger-handler.so` | the OPPO donor C.05 copies (C.06 and later wait for a missing service and hang) |

The `pipa_core` module files that the ROM ships in `port-rom/pipa_port/` (Rust face HAL `facehal-rs` with the
SenseTime face libraries, `xiaomi_touch_ioctl` (Rust), `chargershim.jar`, `aod_bl.jar`) are author-made blobs. Only
`libcamera2ndk_vendor.so` and `libc++_shared.so` match stock files.

## B8. Test plan on a tablet (not done yet)

Do one change at a time. Each test needs the person's approval and a named rollback. Back up `/data` first (TWRP
backup or a full copy): a change of `vendor` can make `/data` unreadable.

| # | Test | Rollback |
|---|---|---|
| 1 | ROM build with the from-stock `vendor`/`odm` (B6, `STANDIN=1`), clean flash | `flash_super.sh` the previous build |
| 2 | PixelOS `dtbo` + GPU fragment | flash the beta4 `dtbo` to `dtbo_b` |
| 3 | PixelOS `vendor_boot` + dtb edits + cmdline | flash the beta4 `vendor_boot` |
| 4 | Rebuilt `vbmeta` / `vbmeta_system` (flags 3) | flash the beta4 files |
| 5 | Stock `abl` | flash the beta4 `abl` from fastboot (if fastboot still starts; this is the riskiest test, do it last) |
| 6 | PixelOS boot ramdisk (no TWRP) | flash the previous `boot.img` |
| 7 | Face unlock with the PixelOS Megvii libraries | previous build |

## B9. Unknowns (the real gaps)

- The source of the author's TWRP, `abl`, kernel, and the `vendor` build tree (a LineageOS-family tree, maybe
  EvolutionX or PixelOS; the build props say the graphics settings were "aligned to AOSPA").
- The exact official HyperOS 2 version of the firmware (one download and an md5 compare will tell).
- The origin of the Megvii face model file and of the author-made apps and libraries (B7).
- Whether the PixelOS boot chain pieces (B4, B5) work with the ColorOS system: not tested.
