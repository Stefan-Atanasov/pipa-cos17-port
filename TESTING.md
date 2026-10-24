# Testing

This document gives the procedures to check a build on the tablet.

## 1. Before you start

1. Connect the tablet with USB. Use the USB serial for all scripts: `ADB="adb -s <serial>"`.
2. Unlock the tablet.
3. After a boot or an unlock, wait 60 seconds before you measure. The ROM does start-up work in this time.
4. For a test series, keep the screen on: `adb shell svc power stayon usb`.
5. After the series, set it back: `adb shell svc power stayon false`.

NOTE: Do each measurement two times or more. The difference between two runs with the same settings can be some
percent.

## 2. Regression check

```sh
ADB="adb -s <serial>" sh maintainer/device_check.sh <label>
```

The script is read-only. The report is in `port-work/device-checks/<date>-<label>.txt`.

Make sure that:

- `getenforce` shows `Enforcing`.
- The face HAL is in `service list`.
- `xiaomi-keyboard` does not run when no keyboard is attached.
- Colours, minimum brightness and auto-brightness are correct.
- Audio channels are correct in all rotations.

## 3. Smoothness test

`maintainer/heavy_mix.sh` opens and closes apps, does flings, opens the shade, the quick settings and the app
drawer. It uses real touch input (`maintainer/kgest`).

```sh
ADB="adb -s <serial>" POWER=1 OPEN=0.4 FL=0.2 GAP=0.2 sh maintainer/heavy_mix.sh <label> 10
```

- `POWER=1` stops charging during the test and gives the mean power.
- The script shows the janky frames (gfxinfo) of the launcher, SystemUI and the test apps.
- `INVALID` means that a test app did not open correctly. In an invalid run, use only the launcher and SystemUI
  values.

## 4. Frame timing test (Perfetto)

The frame timing test shows the frames that the user sees late. Use it to compare two builds or two settings.

```sh
ADB="adb -s <serial>" sh maintainer/perfetto/traced_heavy.sh <label>
```

- The script records a Perfetto trace during one smoothness run.
- `maintainer/perfetto/frame_summary.py` gives the SurfaceFlinger frames by result, the launcher results and the
  long display commits.
- `maintainer/perfetto/analyse.py <trace> <process>` shows why the frames of a process are late.
- The trace is in `port-work/traces/<label>.pftrace`.

### 4.1 Good values

| Value | Good result |
|---|---|
| SurfaceFlinger frames on time | about 94 % |
| SurfaceFlinger dropped frames | about 1 % |
| Launcher gfxinfo janky frames (Material blur off) | 6 % to 8 % |
| Mean power during the test | about 7 W |

## 5. Kernel check

```sh
ADB="adb -s <serial>" sh maintainer/kernel/kernel_check.sh <label>
sh maintainer/kernel/oplus_check.sh
```

`kernel_check.sh` checks root, susfs, input, display and battery. `oplus_check.sh` checks the OPPO kernel nodes
and the UX threads.

Make sure that:

- The touch log (`dmesg | grep NVT-ts`) shows `Update firmware success`.
- The display log does not show `esd check failed report PANEL_DEAD` again and again.

## 6. Battery check

1. Reset the statistics: `adb shell dumpsys batterystats --reset`.
2. Disconnect the tablet and leave the screen off for some hours.
3. Read `dumpsys batterystats` (wakelocks, wakeup reasons).
4. Read `/sys/power/system_sleep/stats` (AOSD and CXSD counts) and `/sys/power/rpmh_stats/master_stats`
   (sleep time of each subsystem).
