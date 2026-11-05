# ColorOS 17 for Xiaomi Pad 6 (pipa) — beta7 (2026-11-05)

Maintainer build by Stefan-Atanasov, based on 梦归zzz's beta4 port. Tested on one device (8 GB). Back up first.

Build: ROM **pt56 = beta7** (`port.sh` up to step 5r), kernel **walt-r17**. Donor: OPPO OPD2515 `17.0.0.104(CN01)`
(C.07, security patch 2026-09-01); pipa vendor/odm/firmware from beta4. Root: SukiSU-Ultra **v4.3.0-r1** (builtin).

## Highlights (changes since beta6)

- **New donor C.07** (OPPO 17.0.0.104, security patch 2026-09-01).
- **Faster UI after a flash:** the port compiles SystemUI, Settings and the launcher again after each flash, and
  Android builds a matching framework boot image at the first boot. Before, a clean flash ran these apps without
  compiled code (slow Settings, laggy launcher) until the nightly compile. Measured: launcher janky frames 35 % -> 16 %.
- **Animations tile with two states:** "Fast" (default, smoothest) and "ColorOS" (OPPO's own, slower). Blur stays
  on in both: the home screen dock and folders and the Quick Settings panel now have blur also with "Fast". Measured
  cost: none at normal speed, about 1 point of launcher jank when you open and close apps very fast.
- **Several floating windows at a time** also with the "Fast" animations (before: a second window closed the first).
- **USB-C monitor:** 120 Hz modes, extended desktop, the monitor's own resolution at 200 dpi (like 125 % on Windows),
  and OPPO PC Screen Extend / Mirror work (black screen before). Kernel: no more drops on monitors that disconnected
  at 10-bit colour. Sound over USB-C goes to the monitor only if the monitor has speakers.
- **Game thermal profile:** while a game is in front, Xiaomi's thermal service uses its game profile (full CPU clocks
  up to 46 °C skin temperature instead of 38 °C). Off again when you leave the game or turn the screen off. Set
  `GAME_THERMAL_SCENE` in `/data/misc/pipa_port/config.prop` (13 = hotter, 0 = off).
- **Clean logs:** no SELinux denials from the ROM in a full test (boot, apps, camera, recording, split screen,
  floating windows, Wi-Fi/Bluetooth/airplane toggles, idle). OPPO's UI First boost hints now reach SurfaceFlinger,
  system_server, camera, media and more apps. Find My Device is removed (it needs OPPO secure storage).
- **Bedtime mode** no longer turns itself on again after you turn it off.
- **App updates:** you can update apps from the Play Store and the App Market. The App Market can no longer
  replace the port's patched OPPO Share (file sharing with the phone without the phone link).
- **Face unlock in a dark room:** the face camera helper no longer crashes when the camera sees only black frames
  (before: a crash report each time). Face unlock still needs some light.
- **Charging:** bypass charging (hold the level while plugged in), charging limit and the smart charging cap.
- **Games:** Racing Master and PUBG report a gaming phone model (higher FPS options). Games that target Android 14 now
  reach OPPO's game optimizer too (blocked before). Game Eye Care works. Game touch
  controls map to the Xiaomi touch firmware.
- **Kernel walt-r17:** SukiSU-Ultra v4.3.0-r1 kernel part, OPPO thermal shell-temperature node, DP fixes.
- **SukiSU manager v4.3.0-r1** is in `extras/`. The ROM installs or updates it on the first boot. After an update
  from beta6, open the SukiSU manager once: if it asks to update ksud, let it (the kernel is SukiSU v4.3.0-r1 now).
- Also new: touch while charging, Circle to Search (hold the gesture bar), OPPO file sharing with the phone link
  off, screen attention, Dolby restore, OPPO earbuds pop-up, O-Live wallpapers, About page "ColorOS 17".
- Google services are on right after a clean flash. Google Quick Share works next to OPPO Share. OPPO QoS
  scheduling is on. Fewer background log writes (touch log spam, storage maintenance parts pipa cannot use).

## Notes

- **The first boot takes about 1 minute longer** than usual: Android compiles the framework. Do not reboot it.
- Update from beta6: flash with Enter ("keep data"). From another ROM: "y" (clean flash). A clean flash
  erases data. Do not change between this package and the `beta7-noenc` package with "keep data".
- **If the flash stops with "Failed to set slot B":** the bootloader sometimes reports no slots. Run
  `fastboot reboot bootloader`, then start the flash script again. Nothing was written at that point.
- **Technical:** ROM md5 `46b49fb8d81a7c75e719afad447103e7`, boot image md5 `70e4816be872995be0da7549348cdccd`. Source and step list:
  https://github.com/Stefan-Atanasov/pipa-cos17-port
- **KernelSU modules:** script modules (`service.sh`, `post-fs-data.sh`) and `system.prop` work. Modules that
  replace system files (a `system/` folder) need a KernelSU metamodule; none is included. Modules with their own
  SELinux rules (`sepolicy.rule`) are not tested. Zygisk modules need a Zygisk implementation.

## Known issues

- **Refresh rate:** the panel stayed at 120 Hz on a static screen once; the cause is unknown. A reboot clears it.
- **Wi-Fi:** it sometimes does not turn on. Reboot the tablet.
- **Smart charging:** the 80 % hold needs ColorOS's sleep prediction, which trains only after several nights without a
  reboot. The fixed charging limit works.
- **Shared calls:** the other person can hear an echo. Use headphones.
- **Screen share:** a striped picture was seen twice during screen sharing; not reproduced.
- **Navigation bar:** some apps draw content behind it.
- **HeyTap:** this CN ROM and global OPPO/OnePlus phones use separate account servers.
- **Play Integrity:** only BASIC integrity. No keybox is included.
- **Find My Device** and **cloud password sync** are not available (they need OPPO secure storage).
- **USB-C monitor:** colours on the monitor are a bit warm (the tablet's colour correction applies to all screens).
- Open reports that could not be reproduced: silent microphone recordings, recorder stutter, random screen flicker.
- Public list: https://github.com/Stefan-Atanasov/pipa-cos17-port/blob/main/KNOWN-ISSUES.md

## Tests (maintainer device, 2026-11-04/05)

"automated" = `device_check.sh`; "capture" = all SELinux denials logged (audit rate 2000) during a scripted session.

- [x] Dirty flash of each test build, boot in 25-45 s, automated check 58 pass, 0 fail, 0 warn (ROM + walt-r17)
- [x] SELinux capture: 0 denials from ROM domains, apps and root (normal + advanced session)
- [x] Smoothness: launcher 1.6-2.0 %, SystemUI 3.1-3.8 %, apps 3.7-3.9 % janky frames (heavy test, "Fast" + blur)
- [x] Home and Quick Settings blur with "Fast" after a cold boot
- [x] Game profile switches when Racing Master opens and back when it closes
- [x] Bedtime stays off after you turn it off
- [x] Stress test on the final build (35 Settings pages, screen off/on x20, rotation x12, Wi-Fi/Bluetooth/airplane
      toggles, camera x5, floating windows and split screen, 16 apps at once, forced doze): no crash, no ANR, no
      crash report
- [x] Face unlock: 21 unlock attempts in a dark room without a crash; the dark-room retry ends without a crash
- [x] USB-C monitor 120 Hz, extended desktop, 200 dpi, PC Screen Extend / Mirror (GO27Q24)
- [x] Root (SukiSU v4.3.0-r1), susfs initialised, manager and ksud on the same version
- [x] Framework boot image built on /data and signed; SystemUI, Settings, launcher compiled
- [ ] Clean flash of the release package
- [ ] Night standby on this build (beta6: 0.21 %/h)
- [ ] Keyboard case (no tester)
