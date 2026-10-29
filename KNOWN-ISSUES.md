# Known issues

This document lists the problems of the public release **beta5** (ROM layer 2v + kernel walt-r6) and their status in
the development build (ROM `port.sh` up to step 3p + kernel walt-r8kpm, not released yet). Each entry gives the
symptom, a workaround if there is one, and the status. Updated 2026-10-29.

## For users

### Fixed in the next build (not released yet)

| Problem in beta5 | Fix |
|---|---|
| Battery drain in standby: the sensor hub never sleeps. | 2w (OPPO fold sensor type = Xiaomi knuckle sensor). Night test: 0.26 %/h. |
| No root after a clean flash (SukiSU manager). | 2w: the manager installs into `/data/app` on the first boot. |
| Game Filter and colour enhancement freeze the screen. | 2x (no freeze) and 3f (the filters work as a colour matrix). |
| The refresh rate stays at 120 Hz on a static screen. | 2z and 3b: the panel drops to 60 Hz when idle. |
| The privacy password and the ColorOS app lock do not work. | 3a: `ICryptoeng` shim. |
| Network, call and SMS sharing with a phone (interconnect) do not work. | 3c, 3d and kernel walt-r7ov. The far end can hear an echo in calls (parked). |
| Face enrollment can crash near the edge of the camera frame. | 3f: eye guard in the face HAL. |
| Bedtime / Eye Protect settings reset at each boot. | 3f: Eye Protect patch. |
| A "Xiaomi Keyboard configured" notification shows without a keyboard. Games show a controller. | Kernel walt-r7ov. |
| Wi-Fi is slow to connect after a reboot. | Kernel walt-r6-nvmac and later. |
| HDR video plays as SDR; YouTube HDR glitches. | 3h (HDR display), 3i (wide colour), 3j (composer patch). An occasional glitch can stay. |
| HDR whites look green; HDR photos are dark; the brightness jumps at the start and end of HDR. | 3q: HDR uses the Natural calibration with a P3 matrix; the OPPO HDR brightness boost (EDR) is off (it does not work on this LCD). |
| The "Standard" colour mode is oversaturated. | 3r: correct sRGB colours with a slightly warmer white. |
| Game Filter colours do not match their names ("Vivid" is pale); colour enhancement is not visible. | Next build: new filter matrices from the app descriptions. |
| Adaptive tone (and Bedtime) changes the colour only a little and slowly. | 3s: the continuous colour sensor stream with real lux; Bedtime is always warmer than adaptive. |
| The pen capsule shows with the pen in the dock. | Next build: the dock state must stay for 3 s. |
| After many UI restarts, OPPO swap files fill the storage. | 3r + pt18 rules: `pipa_port` removes the extra swap files. |
| Video thumbnails do not show in Gallery and file apps. | 3l: 64-bit mediaserver. |
| The pen is ready only up to 5 s after screen-on. | 3n: about 1 s. |
| Netflix plays only in SD (Widevine L3). | 3o: Netflix sees a Pixel 6 and gets Widevine L1 (HD). If Netflix was installed before, clear its app data one time. |
| Google Photos has no free original-quality backup. | 3o + 3p: Google Photos sees an original Pixel XL (free unlimited original quality). |

### Open

| Problem | Symptom | Workaround | Status |
|---|---|---|---|
| Wi-Fi start | Wi-Fi sometimes does not turn on. | Reboot the tablet. | Open. No recovery path in the driver configuration. |
| Navigation bar | Some apps draw a part of the screen behind the navigation bar. | None. | Open. Device dumps from an affected app are necessary. |
| Video apps | Some video apps show a black picture after you leave and open them again. | Restart the app. | Open. Not reproduced on the development build. Steps to reproduce are necessary. |
| Microphone | Some recordings have no audio ("sometimes"). | None. | Open. Not reproduced. Steps to reproduce are necessary. |
| Call sharing echo | In shared calls, the far end can hear an echo of itself. | Use headphones. | Parked: the pipa DSP echo canceller does not work in this path. |
| Pen page | Settings → Stylus (OPPO pen page) shows the Xiaomi pen as "disconnected". | None necessary: the pen works. | By design (OPPO pen protocol). |
| Keyboard case | The auto-off when you fold the keyboard behind the tablet is not tested. | Typing works. | Not tested. |
| Play Integrity | Only BASIC integrity (unlocked bootloader). Apps that need DEVICE integrity do not work. | None. | By design. |
| Material blur | With "Material blur" on, the launcher animations are less smooth. | Turn "Material blur" off: `adb shell settings put system system_material_blur_enable 0`. | By design (GPU load). |
| Dual boot with Linux | Linux cannot read the internal storage. | Use a shared drive or the network. | By design: see [DUALBOOT-LINUX.md](DUALBOOT-LINUX.md). |

## For maintainers

| Item | Status |
|---|---|
| Clean flash of the release package | Tested on 2026-10-25 (2u package). The fixes are in 2v (beta5). |
| `pipa_port` SELinux domain | Enforcing since 3g. Rules: `maintainer/sepolicy/pipa_port_rules.cil`. |
| Live SELinux rules with `ksud sepolicy patch` | Kernel walt-r8kpm hangs (watchdog reset). Compile on the tablet with `secilc` and test with a ROM build. |
| Step 3o and the boot image | `framework.jar` is patched: odrefresh compiles the framework boot image into `/data` on the first boot (about 1 min longer). |
| Step 3k (odm interconnect from C.06) | Optional (`PORT_ODM_C06=1`). Built, not tested. |
| OPPO performance service (`vendor-oplus-hardware-performance-V1-service`) | SELinux blocks its read of `/proc/version`, so it does not know the kernel paths. A live fix works but gave no measured gain. |
| `/proc/oplus_binder/ux_flag` | Not in the kernel. ColorOS cannot pass UX through binder calls. |
