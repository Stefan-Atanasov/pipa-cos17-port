# Testing

This document gives the procedures to check a build on the tablet, and the checklist for a release.

## 1. Before you start

1. Connect the tablet with USB.
2. Root (SukiSU) is necessary for all scripts in this document. After a clean flash, open the SukiSU manager one time
   and give root to the shell first.
3. Run the scripts from the repository root. Give the USB serial in the variable `ADB` to each script:
   `ADB="adb -s <serial>" sh maintainer/<script>`. The default serials in the scripts are the maintainer's tablet.
4. Unlock the tablet.
5. After a boot or an unlock, wait 60 seconds before you measure. The ROM does start-up work in this time.
6. For a test series, keep the screen on: `$ADB shell svc power stayon usb`.
7. After the series, set it back: `$ADB shell svc power stayon false`.

The reports go to `port-work/` below `PIPA_ROOT` (default `~/Documents/pipa/port-work`), not into this repository.

NOTE: Do each measurement two times or more. The difference between two runs with the same settings can be some
percent.

## 2. Kinds of test results

The release notes and [KNOWN-ISSUES.md](KNOWN-ISSUES.md) use these kinds. Do not write "tested" without evidence.

| Kind | Meaning | Example |
|---|---|---|
| Verified on the device | A person did the test on the tablet and saw the result. Give the date and the build. | Pen dock capsule, 3u, 2026-10-30 |
| Automated | A script checked it (`device_check.sh`, `kernel_check.sh`). Give the pass/fail count. | beta6: 58 pass, 0 fail, 0 warn |
| Probe | A software check shows the condition, but not the user result. | Netflix Widevine L1 (HD playback not checked) |
| User report | A tester reported it. The maintainer did not check it. | |
| Implemented, not tested | The build has the change. No test was done. | SukiSU 4.2.1 → 4.3.0 update |
| Experimental | Optional build or step. Not for normal use. | `beta6-noenc` (3x), 3k |

## 3. Regression check (automated)

```sh
ADB="adb -s <serial>" sh maintainer/device_check.sh <tag>
```

- The script is read-only.
- The report is in `port-work/device-checks/<date>-<tag>.txt`.
- If `port-work/<tag>/report/` exists (a `port.sh` build on this PC), the script also compares the file md5 values on
  the tablet with the build manifests.
- Expected result for beta6: 58 pass, 0 fail, 0 warn.

The script checks, among other items:

- `getenforce` shows `Enforcing`.
- The face HAL is in `service list`.
- `xiaomi-keyboard` does not run when no keyboard is attached.
- The `pipa_port` services run and have no SELinux denials.

NOTE: `ro.pipa.port.layer` shows the last step that set it (beta6: `3t`). It does not tell 3t from 3w. Use the md5
checks to identify the build.

### 3.1 Manual checks

`device_check.sh` does not check these items. Do them by hand:

- Colours: Natural and Vivid are different. Minimum brightness is low but not black. Auto-brightness changes.
- Audio: left and right are correct in all rotations.
- Touch log: `dmesg | grep NVT-ts` shows `Update firmware success`.
- Display log: `dmesg` does not show `esd check failed report PANEL_DEAD` again and again.

## 4. Smoothness test

`maintainer/heavy_mix.sh` opens and closes apps, does flings, opens the shade, the quick settings and the app
drawer. It uses real touch input through `maintainer/kgest/kgest`. This binary is not in the repository: build it
with `maintainer/kgest/build.sh` (Android NDK).

```sh
ADB="adb -s <serial>" POWER=1 OPEN=0.4 FL=0.2 GAP=0.2 sh maintainer/heavy_mix.sh <label> 10
```

- `POWER=1` stops charging during the test and gives the mean power.
- The script shows the janky frames (gfxinfo) of the launcher, SystemUI and the test apps.
- `INVALID` means that a test app did not open correctly. In an invalid run, use only the launcher and SystemUI
  values.
- Each run adds one line to `port-work/perf-ab/heavy.csv`.

## 5. Frame timing test (Perfetto)

The frame timing test shows the frames that the user sees late. Use it to compare two builds or two settings.

1. Make the Python environment one time:

```sh
python3 -m venv ~/Documents/pipa/port-work/perfetto-venv
~/Documents/pipa/port-work/perfetto-venv/bin/pip install perfetto
```

2. Record a trace during one smoothness run:

```sh
ADB="adb -s <serial>" sh maintainer/perfetto/traced_heavy.sh <label>
```

- The trace is in `port-work/traces/<label>.pftrace` (about 400 MB).
- `maintainer/perfetto/frame_summary.py` gives the SurfaceFlinger frames by result, the launcher results and the
  long display commits.
- `maintainer/perfetto/analyse.py <trace> <process>` shows why the frames of a process are late.
- The script sets `persist.traced.enable` back to 0 at the end.

### 5.1 Reference values

These values come from the beta5 test builds (2026-10-24). They were not measured again on beta6.

| Value | Reference |
|---|---|
| SurfaceFlinger frames on time | about 94 % |
| SurfaceFlinger dropped frames | about 1 % |
| Launcher gfxinfo janky frames (Material blur off) | 6 % to 8 % |

## 6. Kernel check (automated)

```sh
ADB="adb -s <serial>" sh maintainer/kernel/kernel_check.sh <label>
ADB="adb -s <serial>" sh maintainer/kernel/oplus_check.sh
```

`kernel_check.sh` checks root, susfs, input, display and battery. The output is in
`port-work/kernel/checks/<label>.txt`. `oplus_check.sh` checks the OPPO kernel nodes and the UX threads.

## 7. Battery check

1. Reset the statistics: `$ADB shell dumpsys batterystats --reset`.
2. Disconnect the tablet and leave the screen off for 8 hours or more.
3. Read `dumpsys batterystats` (wakelocks, wakeup reasons).
4. Read `/sys/power/system_sleep/stats` (AOSD and CXSD counts) and `/sys/power/rpmh_stats/master_stats`
   (sleep time of each subsystem, root).

Reference: test build pt18 (before beta6), 13 h screen off, Wi-Fi and Bluetooth on: 0.21 %/h (18 mA).

## 8. Release checklist

Do these checks before you publish a release package. Record the result of each check with its kind (section 2).

### 8.1 Risks

WARNING: A clean flash ("y" in `FlashLinux.sh` / `FlashWindows.bat`) erases `userdata` and `metadata`. All data on
the tablet is lost. Make a backup first.

WARNING: The flash scripts write the firmware (bootloader, modem, `vbmeta`, `vendor_boot`) to both slots also in a
dirty flash. Only the data stays. A damaged package can make the tablet not boot.

WARNING: A change between an encrypted build (`beta6`) and an unencrypted build (`beta6-noenc`, step 3x) needs a
clean flash. A dirty flash between them does not boot correctly.

CAUTION: After a flash, `/data` uses f2fs `checkpoint=disable` until a boot completes. In a bootloop, the next reboot
removes all writes to `/data` (also `/data/adb`).

CAUTION: The first boot after a flash takes about 1 minute longer (the framework is compiled again). Do not reboot
during this time.

Recovery: the boot image has TWRP (Power + Volume up, with slot B active). TWRP ADB has root and a decrypted `/data`.
To go back, flash the previous package or `sh maintainer/flash_super.sh -y <name>` (maintainer images), and the
previous boot image (`maintainer/kernel/flash_kernel.sh flash <img>`).

### 8.2 Before the flash

1. Check the free space on the PC: `df -h`.
2. Check the package: `sha256sum -c SHA256SUMS` in the package folder.
3. Keep the previous package (or image) for a rollback.

### 8.3 Flash paths

Test each path on a tablet with a backup, or on a spare install:

| Path | Check after the boot |
|---|---|
| Dirty flash ("keep data") from the previous release | Root works, SukiSU manager updated, apps and settings stay. |
| Clean flash ("y") | Setup wizard, on-screen keyboard, root on the first boot, face enroll in portrait and landscape. |
| "Keep data" with a second system in slot A | `boot_a` and `dtbo_a` are not changed (compare their md5 before and after). |
| Rollback to the previous release | The tablet boots, data stays. |
| `beta6-noenc` (only with a clean flash) | `getprop ro.crypto.state` shows `unencrypted`. |

### 8.4 After each boot

1. Wait 60 seconds.
2. Run `device_check.sh <tag>` (section 3) and `kernel_check.sh` (section 6).
3. Check by hand: Wi-Fi, Bluetooth, pen (buttons, dock capsule), magnetic case, face unlock, keyboard case (if
   available), phone link (Wi-Fi off), HDR video, Game Filter, privacy password.
4. For a performance change: the smoothness test (section 4) and the frame timing test (section 5). Compare with the
   previous build.
5. For a power change: a night battery check (section 7).
