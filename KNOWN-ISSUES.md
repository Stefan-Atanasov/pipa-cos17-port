# Known issues

This document lists the known problems of the public release **beta7.2** (2026-11-06, ROM `port.sh` up to step 5x +
kernel walt-r17, donor C.07) and what beta7.2, beta7.1, beta7 and beta6 fixed. Each entry gives the symptom, a workaround if
there is one, and the status. Updated 2026-11-06.

**Found a new bug?** Add it to the bug report document: https://docs.google.com/document/d/1nCv448YX7-I_X9f0O-01NkF6mV-mJFdkRph2O8JJM7c/edit?usp=sharing
Write the build, clean or dirty flash, the steps to reproduce, what you expected and what happened. Most of this work was done with an AI assistant (Claude) and tested on one tablet.

## For users

### Fixed in beta7.2

| Problem in beta7.1 | Fix |
|---|---|
| Echo in voice chat and call sharing: the far end heard the tablet speaker. The pipa DSP echo canceller removes nothing in the VoIP path. | 5w: a wrapper audio HAL (`audio.primary.pipaaec.so`, chosen by `ro.hardware.audio.primary`) runs the AOSP WebRTC AEC3 and AGC2 (+24 dB) on voice-communication input. The real HAL is unchanged. |
| Log spam (tester report): OStats CPU errors, UAH urcc errors, QoS scene warnings, "Access denied finding property", audioserver denials. | 5x: pipa power profile (`cpu.*` from stock HyperOS), UAH native calls return at once, 3 QoS warnings removed, 11 empty vendor props readable, audioserver rule. 1-minute test: 53 177 -> 8 797 log lines. |
| Debug and verbose log lines from every app. | 5x: `persist.log.tag=I` by default. Helper 1.2 Quick Settings tile "Logs": Quiet / Verbose. |
| Per-app battery use was computed with the donor's CPU layout (6+2 cores). | 5x: the power profile has the pipa layout (4+3+1 cores, 56 speed steps). |

### Fixed in beta7.1

| Problem in beta7 | Fix |
|---|---|
| Grey screen after a clean flash. The setup wizard `com.coloros.bootreg` crashed in a loop. A dirty flash was not affected. | 5f keeps Find My Device. The wizard needs its provider `com.coloros.findmyphone.provider.SharedProvider`. Find My Device still cannot be switched on. |
| No SukiSU manager after a clean flash. | 5u: SELinux rule set for the `pipa_port` service (`pm install <file>` failed without it). 5t: the service retries the install every 60 s. |
| Blur was off after a clean flash, and ColorOS hid the switches with the "Fast" animations. | 5t: Visual blur and Contour glow are on at the first boot. Personalization > More > "Textured visual effects" shows with "Fast". |
| The ROM had only an old Play Store stub; no Gboard, no Google app. | 5u: Play Store, Gboard and the Google app install at the first boot. Gboard becomes the keyboard only over Sogou or no keyboard. Circle to Search works after the Google app is installed. |
| Animations tile: "ColorOS" (tier 1). | Helper 1.1: "Fast" (tier 3, default) and "Slow" (tier 2). |
| Password fields use the secure keyboard. | Secure keyboard is off one time (Settings > Additional settings > Keyboard & input method > Secure keyboard). |

### Fixed in beta7

| Problem in beta6 | Fix |
|---|---|
| The OPPO App Market could replace the port's patched OPPO Share with its own update (file sharing with the phone then needs the phone link). | 5r: the patched OPPO Share has a higher version number (17999036); the App Market sees no newer version. |
| Settings and the launcher are slow after a clean flash. | 4y + 4z: SystemUI, Settings and the launcher are compiled after each flash, and Android builds a matching framework boot image on the first boot. Launcher janky frames 35 % -> 16 % (measured). |
| A second floating window closes the first. | 5c: several floating windows also with the fast animations. |
| No blur on the home screen and in Quick Settings with the fast animations. | 5g: blur at the "Fast" animation tier (no measurable cost at normal use). The Animations tile has two states: Fast and ColorOS. |
| USB-C monitor: no output, drops, 60 Hz only, everything too big; PC Screen Extend / Mirror black. | 4j, kernel walt-r14/r15 (8-bit colour, best refresh for the link), 5a (120 Hz), 5b (extended desktop), 5e (native size, 200 dpi), 5d (PC Screen Extend / Mirror). |
| Games always use Xiaomi's daily thermal profile (CPU slows from 38 °C skin). | 5l: Xiaomi's game profile while a game is in front (full clocks up to 46 °C skin). `GAME_THERMAL_SCENE` in `/data/misc/pipa_port/config.prop`. |
| Bedtime mode turns on again after you turn it off. | 5i: each Bedtime switch is restored on its own. |
| SELinux denials and error spam in the logs. | 5f, 5h-5k: no denials from the ROM in a full and an advanced test session. OPPO's UI First boost hints now reach SurfaceFlinger, system_server, camera and media. |
| Circle to Search does not open. | 4e + 4v: install the Google app and reboot once; hold the gesture bar for about 0.6 s. |
| Keep the screen on while you look at it has no effect. | 4i. |
| File sharing tablet -> OPPO phone needs the phone link. | 4k (Google Quick Share also: 4l). |
| Games offer only 60 fps. | 3o: listed games (PUBG, Racing Master) see a gaming device. |
| No ColorOS banner in About device. | 4u. |
| Charging: no bypass, the charging limit is not exact. | 4m, 4p, 4w. |
| Touch is less exact while charging. | Kernel walt-r9 (charger state for the touch firmware). |

### Fixed in beta6

| Problem in beta5 | Fix |
|---|---|
| Battery drain in standby: the sensor hub never sleeps. | 2w (OPPO fold sensor type = Xiaomi knuckle sensor). Night test: 0.21 %/h (13 h, screen off). |
| No root after a clean flash (SukiSU manager). | 2w: the manager installs into `/data/app` on the first boot. The install was tested on a running system; a clean flash with 2w is not tested yet. |
| Game Filter and colour enhancement freeze the screen. | 2x (no freeze) and 3f (the filters work as a colour matrix). |
| The refresh rate stays at 120 Hz on a static screen. | 2z and 3b: the panel drops to 60 Hz when idle. |
| The privacy password and the ColorOS app lock do not work. | 3a: `ICryptoeng` shim. |
| Network, call and SMS sharing with a phone (interconnect) do not work. | 3c, 3d and kernel walt-r7ov. Call echo fixed in beta7.2 (5w). |
| Face enrollment can crash near the edge of the camera frame. | 3f: eye guard in the face HAL. |
| Bedtime / Eye Protect settings reset at each boot. | 3f: Eye Protect patch. |
| A "Xiaomi Keyboard configured" notification shows without a keyboard. Games show a controller. | Kernel walt-r7ov. |
| Wi-Fi is slow to connect after a reboot. | Kernel walt-r6-nvmac and later. |
| HDR video plays as SDR; YouTube HDR glitches. | 3h (HDR display), 3i (wide colour), 3j (composer patch). An occasional glitch can stay. |
| HDR whites look green; HDR photos are dark; the brightness jumps at the start and end of HDR. | 3q: HDR uses the Natural calibration with a P3 matrix; the OPPO HDR brightness boost (EDR) is off (it does not work on this LCD). |
| The "Standard" colour mode is oversaturated. | 3r: correct sRGB colours with a slightly warmer white. |
| Game Filter colours do not match their names ("Vivid" is pale); colour enhancement is not visible. | New filter matrices from the app descriptions. |
| Adaptive tone (and Bedtime) changes the colour only a little and slowly. | 3s: the continuous colour sensor stream with real lux; Bedtime is always warmer than adaptive. |
| The pen capsule shows with the pen in the dock, or 3-4 s late; the pen the other way round is not seen. | 3u: both dock sensors are read; the capsule shows about 1 s after dock or undock. |
| Pen, keyboard and case features start about 20 s after the boot. | 3v: the service starts about 2 s after the boot. |
| The battery service writes an error line every few seconds while charging. | 3t (log only; charging was correct). |
| After many UI restarts, OPPO swap files fill the storage. | 3r + pt18 rules: `pipa_port` removes the extra swap files. |
| Video thumbnails do not show in Gallery and file apps. | 3l: 64-bit mediaserver. |
| The pen is ready only up to 5 s after screen-on. | 3n: about 1 s. |
| Netflix plays only in SD (Widevine L3). | 3o: Netflix sees a Pixel 6 and gets Widevine L1 (probe). HD playback is not confirmed yet. If Netflix was installed before, clear its app data one time. |
| Google Photos has no free original-quality backup. | 3o + 3p: Google Photos sees an original Pixel XL (free unlimited original quality). |

### Open

| Problem | Symptom | Workaround | Status |
|---|---|---|---|
| Screen lock after a clean flash | You cannot set a PIN, pattern or password: "Screen lock was already changed. Try again with the new screen lock." Face unlock then also does not work. Probably when the tablet came from another ROM with a screen lock. | `adb reboot bootloader`, `fastboot erase frp`, `fastboot reboot`. Your data stays. | Cause: `frp` keeps the screen lock of the old ROM. Fixed: the beta6 package from 2026-10-30, 17:00 erases `frp` in a clean flash. The first beta6 download does not: use the `beta6-frpfix` zip or the workaround. The workaround worked on beta4 (maintainer); a beta6 user report (2026-10-30) waits for a result. |
| Wi-Fi start | Wi-Fi sometimes does not turn on. | Reboot the tablet. | Open. No recovery path in the driver configuration. |
| Navigation bar | Some apps draw a part of the screen behind the navigation bar. | None. | Open. Device dumps from an affected app are necessary. |
| Video apps | Some video apps show a black picture after you leave and open them again. | Restart the app. | Open. Not reproduced on the development build. Steps to reproduce are necessary. |
| Microphone | Some recordings have no audio ("sometimes"). | None. | Open. Not reproduced. Steps to reproduce are necessary. |
| Call sharing echo | Fixed in beta7.2 (5w). In the first seconds of a call some echo can remain. | - | Fixed. |
| Cast to TV (Miracast) | A tester sees coloured noise on the TV (Settings > Device connection > TV). Screen recording works. | - | Open: a log of a cast is needed. |
| Keyboard case as touchpad | A tester reports that the keyboard case shows as a touchpad. | - | Open: `dumpsys input` with the keyboard attached is needed. |
| Pen page | Settings → Stylus (OPPO pen page) shows the Xiaomi pen as "disconnected". | None necessary: the pen works. | By design (OPPO pen protocol). |
| Keyboard case | Attach, detach and the auto-off when you fold the keyboard behind the tablet are not tested on beta6. | None. | Not tested (no tester). |
| Play Integrity | Only BASIC integrity (unlocked bootloader). Apps that need DEVICE integrity do not work. | None. DEVICE needs a keybox that Google accepts; public keyboxes were rejected in a test on 2026-10-30. | By design. |
| Dual boot with Linux | Linux cannot read the internal storage (it is encrypted). | Use a shared drive or the network, or the experimental `beta7.1-noenc` package. | See [DUALBOOT-LINUX.md](DUALBOOT-LINUX.md). `beta7.1-noenc`: clean flash only (it erases all data); not tested by a user yet. Do not update between `beta7.1` and `beta7.1-noenc` with "keep data". Data on the tablet has no encryption. |
| Pen back button | It no longer takes a screenshot. | None necessary: it is the standard second stylus button now (apps decide what it does). | Changed on purpose in beta6. |
| Network sharing with a phone | The tablet does not use the phone's network while Wi-Fi is connected. | Turn Wi-Fi off. After a reboot, if the phone's SIM does not show, turn the sharing off and on in the phone link once. | Normal Android behaviour (mobile data only without Wi-Fi). Works: tested 2026-10-30. |
| Game Assistant latency | Game Assistant shows about 200 ms network latency. | None necessary. | It measures to a server in China; the network is not slow. |
| HeyTap account | A ColorOS CN tablet and a global OPPO/OnePlus phone show as two different accounts. | None. | By design: CN and global HeyTap are separate servers. |
| OPPO earbuds | No pop-up when you open the earbuds case. | Install the OPPO wireless earbuds app from the OPPO store and keep it. | Workaround from a user (2026-11-02). |
| Sounds while charging | At a low battery level (1-20 %), while gaming and charging, some sounds play. | None. | Open, cause not confirmed. Step 4w removes one candidate (bypass cap/charge switching at 14/15 %). Also seen: a wall charger connects two times in 0.6 s at plug-in. Please send the time, the battery level, a screen recording with sound and a bug report. |

| Refresh rate | The panel stayed at 120 Hz on a static screen once. | Reboot. | Open, cause unknown (seen once). |
| Smart charging | The 80 % hold does not start. | Use the fixed charging limit. | ColorOS needs several nights without a reboot to train its sleep prediction (DeepThinker). |
| Screen share | A striped picture during screen sharing (seen twice). | Stop and start the share. | Open, not reproduced. |
| USB-C monitor colours | The monitor looks a bit warm. | None. | By design: the tablet's colour correction applies to all screens. |
| Monitor sound | No sound on a monitor without speakers. | Use the tablet speakers or headphones. | Android sends the sound to the USB-C monitor. |
| Find My Device, cloud password sync | Not available. | None. | They need OPPO secure storage (RPMB/TEE) that the Xiaomi hardware does not have. Find My Device stays in the ROM because the setup wizard needs it, but it cannot be switched on. |
| KernelSU modules | A module that replaces system files does nothing. | Script modules and `system.prop` work. | SukiSU 4.3 needs a metamodule for file overlays; none is included. `sepolicy.rule` modules are not tested. |
| Flash script stops: "Failed to set slot B" | The bootloader sometimes reports no slots. | `fastboot reboot bootloader`, then start the script again. Nothing was written. | Seen two times on the maintainer's tablet. |

## For maintainers

| Item | Status |
|---|---|
| Release paths of the beta7.1 package | Tested with the image pt61 (not as a package): clean flash (setup, installs, device_check 57 pass / 0 fail / 1 warn) and a dirty flash over beta7-based data (pt60, nearly the same code). Not tested: the package scripts, an update from beta6, "keep data" leaves `boot_a`/`dtbo_a` unchanged, night standby on beta7.1. Reports welcome. |
| Clean flash of a release package | Image pt61 tested with a clean flash on 2026-11-05 (wipe like the flash script, beta7 firmware and kernel). On the same day, the steps of the package flash script (same script as beta7.1) ran by hand with the beta7 package: beta7.1 changes only `super.img`. |
| Step 3x (unencrypted `/data`, `PORT_NOENCRYPT=1`) | Built as `beta6-noenc`, `beta7-noenc` (withdrawn) and `beta7.1-noenc` (pt63-noenc), not tested by a user. Clean flash only. |
| Face unlock and `pipa_port` enforcing | Since 3g the face camera worker had no rules (black enroll preview, no unlock) in the test builds; 3w adds them. Code that the service starts needs rules in `pipa_port_rules.cil`. |
| `pipa_port` SELinux domain | Enforcing since 3f (3g and 3w added rules). Rules: `maintainer/sepolicy/pipa_port_rules.cil`. |
| Live SELinux rules with `ksud sepolicy patch` | Kernel walt-r8kpm hangs (watchdog reset). Compile on the tablet with `secilc` (`maintainer/sepolicy/secil_test.sh`) and test with a ROM build. |
| SELinux state | 0 denials from ROM domains, apps and root in a full capture (audit rate 2000) and an advanced capture on pt48-pt50. The neverallow check reports the same 76 violations as the donor base policy. |
| Step 4h and the boot image | `oplus-framework.jar` (boot jar) is patched too: the same odrefresh compile on the first boot. Debug logs again: `setprop persist.sys.assert.panic true`. |
| Step 3o and the boot image | `framework.jar` is patched: odrefresh compiles the framework boot image into `/data` on the first boot (about 1 min longer). |
| Step 3k (odm interconnect from C.06) | Optional (`PORT_ODM_C06=1`). Built, not tested. |
| OPPO performance service | Since 5h it may mark system_server, cameraserver and mediaserver threads as UX and read `/proc/version`. Its UI First scene writes (`sched_assist_scene`) are silenced, not allowed: `pipa_port` owns that node (A/B test open, BUGS 70). |
| `/proc/oplus_binder/ux_flag` | A no-op node since kernel walt-r10 (ColorOS can open it). |
| `/proc/shell-temp` | Since kernel walt-r16: OPPO `horae` writes its shell temperature; only storage maintenance reads it. The Xiaomi/Qualcomm thermal stack is unchanged. |
