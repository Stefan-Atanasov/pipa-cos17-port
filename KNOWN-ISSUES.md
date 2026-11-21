# Known issues

This document lists the known problems of the public release **v9.3** (2026-11-21; ROM `port.sh` up to
step 8u = pt151 + kernel walt-hi15, donor C.07; v9.2 = step 8s, pt150 + walt-hi13; v9.1 = step 8c, pt132 + walt-hi9; v9 = first stable, step 7x = pt128). The known issues of v9, v9.1 and v9.2 apply to v9.3 unless this list says they are fixed. What v9 fixed since beta7.1: [CHANGELOG.md](CHANGELOG.md); full notes:
[RELEASE-NOTES.md](RELEASE-NOTES.md). The sections after "Known issues in v9.3 / v9.2" are the older lists (beta6 to beta8), kept as a record.
Updated 2026-11-21.

**Found a new bug?** Right after it happens: Pipa Helper > System > **Collect logs** (v9.2 and later; the file in Download has no personal data). Then add the bug and the file to the bug report document: https://docs.google.com/document/d/1nCv448YX7-I_X9f0O-01NkF6mV-mJFdkRph2O8JJM7c/edit?usp=sharing
Write the build, clean or dirty flash, the steps to reproduce, what you expected and what happened. Most of this work was done with an AI assistant (Claude) and tested on one tablet.

## Known issues in v9.3 / v9.2

- **Fewer effects than full ColorOS (by design, since v9).** The port uses ColorOS's "fast" animation level 3 and
  turns off the window blur and the animation blur: about 0.3 % dropped frames instead of 2.7 % on the SD870. At
  level 3 ColorOS itself turns off the wallpaper zoom when apps open and close, and some glass effects. Visual blur
  and Contour glow stay on. Since v9.2 there is a switch: Pipa Helper > Effects (animation style, animation speed, blur, contour glow; Apply, no
  reboot). To get all effects by hand (root, for example in Termux; more stutter, a little more heat and battery use):

  ```sh
  su -c '
  echo ANIM_LEVEL=1 >> /data/misc/pipa_port/config.prop
  settings put global disable_window_blurs 0
  settings put system animationBlurrySwitch 1
  settings put global pipa_live_blur 1
  reboot'
  ```

  `ANIM_LEVEL=1` is the full ColorOS level (the "ColorOS" state of the old Animations tile in beta7.1).
  `pipa_live_blur 1` is the same as the "Live blur" tile. To go back to the defaults:

  ```sh
  su -c '
  sed -i "/^ANIM_LEVEL=/d" /data/misc/pipa_port/config.prop
  settings put global disable_window_blurs 1
  settings put system animationBlurrySwitch 0
  settings put global pipa_live_blur 0
  reboot'
  ```

- **Excel and document viewer:** scrolling in the default document viewer (Excel files) feels jittery. The app is
  slow at 120 Hz; Settings and other apps are smooth.
- **Cast to TV (Miracast):** fixed on Windows; please test with a TV and report.
- **Location:** one tester reported that location did not work in any app on beta8. v9 fixes the provider choice
  (see above). If location still fails, send a log.
- **RAM in heavy games:** in BGMI and Racing Master with less than 1 GB free, frames drop and sound can cut. Tested on
  8 GB only. **The 6 GB Pad 6 is not tested** (OPPO's rule gives it a 3072 MB lz4 zram).
- **Keyboard cover:** fold and the typing fix are still under test (the Caps Lock LED and the Super key action are new in v9.2). With the cover attached Android lists
  a touchpad and a mouse the cover does not have (cosmetic; a game may show a controller icon).
- **Breeno:** the microphone sometimes does not work (not reproduced).
- **Scrolling at 144 Hz with music or a video in the background** can judder a little (the media pill in the
  status bar animates). At 120 Hz or Auto it is smooth. Use 120 Hz or Auto for now.
- **Torch:** one tester saw the torch stay on and the tile turn grey. Not reproduced. The torch shares its LED
  with the rear camera: if it happens, note which app was open.
- **Refresh rate:** the panel stayed at 120 Hz on a static screen once; the cause is unknown. A reboot clears it.
- **Wi-Fi:** it sometimes does not turn on. Reboot the tablet. If the notification "Wi-Fi problem logged" shows, tap it and collect the logs (Pipa Helper > System > Collect logs).
- **Smart charging:** the 80 % hold needs ColorOS's sleep prediction, which trains only after several nights without
  a reboot. The fixed charging limit works.
- **Navigation bar:** some apps draw content behind it.
- **HeyTap:** this CN ROM and global OPPO/OnePlus phones use separate account servers.
- **Play Integrity:** only BASIC integrity. No keybox is included.
- **Find My Device** (it cannot be switched on) and **cloud password sync** are not available.
- **USB-C monitor:** colours on the monitor are a bit warm.
- Open reports that could not be reproduced: silent microphone recordings, recorder stutter, striped picture in screen sharing.
- Public list: https://github.com/Stefan-Atanasov/pipa-cos17-port/blob/main/KNOWN-ISSUES.md

- **Setup wizard (clean flash, landscape):** on the "Enhancement services" page the Next button bar is barely
  visible. Scroll to the end of the text or turn the tablet to portrait.
- **Pens without Bluetooth (for example Lenovo Precision Pen):** as on HyperOS, pen input is on only while a
  Bluetooth pen is connected (saves power). For other pens, turn on Pipa Helper > Pen > always on (v9.2), or install the KernelSU module
  `pipa-pen-always-on-module-v1.0.zip` (Drive folder `modules/`) and reboot. Do not use the old pipa_core
  module with v9 or later.
- **GCam (recommended: AGC 8.8.224 V12.0 by BigKaka):** download the standard APK `AGC8.8.224_V12.0.apk`
  (package `com.agc.gcam88`) from https://www.celsoazevedo.com/files/android/google-camera/dev-BigKaka/f/dl96/ .
  Tested on pipa (2026-11-20): photos, HDR+ and video with sound (1080p) work from the build with step 8k. The
  OPPO camera gives flat photos on pipa (it has no OPPO image processing on Xiaomi camera hardware); GCam does its
  processing in the app. Do not use AGC 9.6.19: V7.0 has no video (the app lacks a class), V6.0 has no video (it
  crashes on a missing camera key). On first start, allow "All files access" when GCam asks.
- **Floating window from the dock:** hold the icon still in the middle of the screen until "Floating window" shows.
- **"Tweak" modules (for example SmoothPad):** do not use them with v9 or later. SmoothPad v3.6 locks 120 Hz, keeps the GPU
  awake, holds CPU floors, re-applies scheduler values every 12-15 s (a loop that wakes the CPU), resizes zram,
  freezes 32 OPPO apps (among them `deepthinker`, `obrain`, `appsense` and `pantanal.ums`, which live alerts and the
  pen pill use), forces the `skiavk` renderer and silences kernel logs (`printk 0`). Result: much more standby and
  screen-on drain, broken OPPO features, and bug reports without kernel logs. Before you report a battery, pen pill,
  rendering or "feature gone" bug, remove such modules in the SukiSU Nova manager and reboot. If an app stays
  frozen, re-enable it: `pm enable <package>`.

- **Fixed in v9.3 (were open in v9.2):** pen buttons in StarNotes and other apps that use "hold the button" (BUGS 166,
  kernel hi14/hi15); press first, then bring the pen down wrote ink and opened Quick Note (BUGS 169); pen buttons dead
  after a reboot with the Pen buttons test screen open (BUGS 167); 32-bit-only apps closing at once (BUGS 168, 32-bit
  graphics driver from stock HyperOS). Watch: one 32-bit test app crashed once in OPPO's frame capture on its very
  first start after boot (not reproduced in 11 more starts); report 32-bit app crashes with Collect logs.
- **Fixed in v9.2 (were open in v9.1):** no charging screen when the tablet is off (BUGS 152); Caps Lock LED of the
  keyboard case (BUGS 151); random short white flash after a refresh rate rise (BUGS 48, kernel hi10 and later);
  less smooth than beta 8 (BUGS 163, step 8r); animation style restarting the home screen (BUGS 165); Settings closing
  on a back swipe with the keyboard open (BUGS 157); no sound in video recording of third-party camera apps
  (BUGS 159); "Device environment not secure" at HeyTap sign-in (BUGS 160); no app updates for built-in OPPO apps (BUGS 161).

## Older lists (beta6 to beta8)

## For users

### Fixed after beta7.2 (the beta8 tester zip had these; they are in v9)

| Problem in beta7.2 | Fix |
|---|---|
| Dolby: beta4's patched `libhwdap` hid DMS errors. | 5z: stock HyperOS 2 library. |
| Speaker sound: thin bass. | 6a: measured speaker EQ in the Dolby speaker tunings (deeper bass, flat mids, slightly softer 7-9 kHz). Graph: `maintainer/dolby-eq/`. |
| Dolby dropped after the screen was off and the output closed. | helper 1.3: the Dolby handle is re-created on playback, device change and screen on. |
| "Original" on Bluetooth headphones was not remembered per device; Dolby did not come back on the speakers. | helper 1.4-1.6: the MiSound choice is remembered per output, like HyperOS. |
| Sound effect settings: ColorOS "OReality" modes did nothing, Chinese text. | 6b: the page shows only the MiSound / Dolby entry, in English. |
| "Hey Breeno" voice wake-up crashed the audio HAL in a loop (sound drops, Breeno mic failed). | 6c: DSP voice wake-up is off (pipa has no OPPO wake-up engine). |
| Game Space "Ultra touch" did nothing. | Touch HAL shim: Ultra touch turns on the panel game mode. The pen does not work in that mode (panel driver). |

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
| Dual boot with Linux | Linux cannot read the internal storage (it is encrypted). | Use a shared drive or the network, or the experimental `v9.2-noenc` package. | See [DUALBOOT-LINUX.md](DUALBOOT-LINUX.md). `beta7.1-noenc`: clean flash only (it erases all data); not tested by a user yet. Do not update between `beta7.1` and `beta7.1-noenc` with "keep data". Data on the tablet has no encryption. |
| Pen back button | It no longer takes a screenshot. | None necessary: it is the standard second stylus button now (apps decide what it does). | Changed on purpose in beta6. |
| Network sharing with a phone | The tablet does not use the phone's network while Wi-Fi is connected. | Turn Wi-Fi off. After a reboot, if the phone's SIM does not show, turn the sharing off and on in the phone link once. | Normal Android behaviour (mobile data only without Wi-Fi). Works: tested 2026-10-30. |
| Game Assistant latency | Game Assistant shows about 200 ms network latency. | None necessary. | It measures to a server in China; the network is not slow. |
| HeyTap account login | Before v9.2: "Device environment not secure" at sign-in or sign-up. | Update to v9.2 or later (MSP 2.3.0 in the ROM). Use the phone number of your existing account: it logs in. | Fixed in v9.2 (BUGS 160). |
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
| Release paths of the v9 package | Verified: clean flash of the image pt128 + walt-hi9 (setup, device_check 57 pass / 0 fail / 2 warnings). `FlashMac.sh` on a real Mac: works (user report, 2026-11-20). |
| Release paths of the beta7.1 package (old record) | Tested with the image pt61 (not as a package): clean flash (setup, installs, device_check 57 pass / 0 fail / 1 warn) and a dirty flash over beta7-based data (pt60, nearly the same code). Not tested: the package scripts, an update from beta6, "keep data" leaves `boot_a`/`dtbo_a` unchanged, night standby on beta7.1. Reports welcome. |
| Vendor props not loaded (BUGS 83) | Closed 2026-11-11: not a bug. `getprop` shows 144 of 345 lines of `/vendor/build.prop` as empty, but boot logs show that `init` loads them (same as stock HyperOS 2). No fix is necessary. |
| Clean flash of a release package | Image pt61 tested with a clean flash on 2026-11-05 (wipe like the flash script, beta7 firmware and kernel). On the same day, the steps of the package flash script (same script as beta7.1) ran by hand with the beta7 package: beta7.1 changes only `super.img`. |
| Step 3x (unencrypted `/data`, `PORT_NOENCRYPT=1`) | Built as `beta6-noenc`, `beta7-noenc` (withdrawn), `beta7.1-noenc` (pt63-noenc) and `v9.2-noenc` (pt150-noenc), not tested by a user. Clean flash only. |
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
