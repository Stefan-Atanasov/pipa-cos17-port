# ColorOS 17 for Xiaomi Pad 6 (pipa) — beta7.2 (2026-11-06)

Maintainer build by Stefan-Atanasov, based on 梦归zzz's beta4 port. Tested on one device (8 GB). Back up first.

Build: ROM **pt68 = beta7.2** (`port.sh` up to step 5x), kernel **walt-r17** (same as beta7.1). Donor: OPPO OPD2515
`17.0.0.104(CN01)` (C.07, security patch 2026-09-01); pipa vendor/odm/firmware from beta4. Root: SukiSU-Ultra
**v4.3.0-r1** (builtin).

## What's new in beta7.2

- **No more echo in voice chat and call sharing:** the tablet's own echo canceller removed nothing, so the other side
  heard the tablet speaker (games like PUBG/BGMI voice chat, VoIP apps, calls through the phone link). A software
  echo canceller now cleans the microphone, with automatic gain (the voice-chat microphone was quiet). Tested with a
  real call: echo gone after the first seconds.
- **Much less log spam:** in the same 1-minute test (apps, recents, music) the system wrote 83 % fewer log lines
  (53 000 -> 8 800). Causes fixed, not hidden: a wrong CPU table, lookups of an OPPO service pipa does not have,
  unreadable OPPO properties, an audio permission. Errors, warnings and crash reports stay.
- **Logs tile (Quick Settings):** "Quiet" (default) drops debug messages; "Verbose" gives the full Android logs. Switch
  to Verbose before you capture logs for a bug report.
- **Battery usage per app is more correct:** Android used the donor phone's CPU layout (6+2 cores); now pipa's
  (4+3+1 cores, Snapdragon 870 speeds).
- Tip: if a game runs at 60 Hz, open Game Space and set a higher frame rate for that game (the game asks for 60 FPS
  itself; this is not a port bug).
- Update from beta7.1: flash with "keep data" (Enter on Linux, `N` on Windows). **Tested as an update from beta7.1.
  A clean install of 7.2 was not tested** (beta7.1's clean install was; 7.2 removes nothing that the setup needs).
- Known issues: casting to a TV (Settings > Device connection > TV) can show coloured noise (log wanted); the
  keyboard case may show up as a touchpad (log wanted).

## beta7.1 (fixes for beta7)

- **Clean flash fixed:** beta7 showed a grey screen after a clean flash (the setup wizard crashed: it needs Find My
  Device, which beta7 removed). Find My Device is back (it still cannot be switched on). A dirty flash from beta6 was
  not affected.
- **SukiSU manager on a clean flash:** beta7 could not install it on the first boot (an SELinux check blocked every
  install from the port service). Fixed; the manager is there right after the setup.
- **Play Store, Gboard and the Google app are installed on the first boot** (stable versions; Play Store updates
  them). Before, the ROM had only an old Play Store stub, and you had to install the real one from the App Market.
  Gboard becomes the keyboard (only over the CN keyboard Sogou: a dirty flash keeps your keyboard). Circle to Search
  works right after the Google app is installed (hold the gesture bar).
- **Blur on by default:** "Fast" animations, Visual blur and Contour glow are switched on once after the flash (clean
  flash and update with "keep data"; no measured cost). The switches are in Personalization -> More -> Textured visual
  effects (ColorOS hid them with "Fast"). You can change them again after that.
- **Animations tile:** "Fast" (default) and "Slow" (ColorOS's full animation set, tier 2; was "ColorOS" = tier 1).
- **No "Set charging limit to 80%" pop-up after each boot** (the battery app read a wrong charger value at boot). Your
  own charging limit in Settings > Battery still works.
- **Secure keyboard off:** password fields use your normal keyboard (Settings > Additional settings > Keyboard & input
  method > Secure keyboard turns it on again).

## Notes

- **The first boot takes about 1 minute longer** than usual: Android compiles the framework. Do not reboot it.
- Update from beta6, beta7 or beta7.1: flash with "keep data" (Enter on Linux, `N` on Windows). From another ROM: "y" (clean flash). A clean flash
  erases data. There is no `noenc` package for beta7.2 yet: `beta7.1-noenc` users stay on 7.1 for now. Do not change between encrypted and noenc packages with "keep data".
- **The first minutes after a clean flash:** the port installs Play Store, Gboard, the Google app and the SukiSU
  manager in the background (about 1 minute). Let it finish.
- **If the flash stops with "Failed to set slot B":** the bootloader sometimes reports no slots. Run
  `fastboot reboot bootloader`, then start the flash script again. Nothing was written at that point.
- **Technical:** ROM md5 `acd73e2e27e955b779d56e2db1af5d01`, boot image md5 `70e4816be872995be0da7549348cdccd`. Source and step list:
  https://github.com/Stefan-Atanasov/pipa-cos17-port
- **KernelSU modules:** script modules (`service.sh`, `post-fs-data.sh`) and `system.prop` work. Modules that
  replace system files (a `system/` folder) need a KernelSU metamodule; none is included. Modules with their own
  SELinux rules (`sepolicy.rule`) are not tested. Zygisk modules need a Zygisk implementation.

## Known issues

- **Refresh rate:** the panel stayed at 120 Hz on a static screen once; the cause is unknown. A reboot clears it.
- **Wi-Fi:** it sometimes does not turn on. Reboot the tablet.
- **Smart charging:** the 80 % hold needs ColorOS's sleep prediction, which trains only after several nights without a
  reboot. The fixed charging limit works.
- **Shared calls:** fixed in beta7.2 (software echo canceller). In the first seconds of a call some echo can remain.
- **Screen share:** a striped picture was seen twice during screen sharing; not reproduced.
- **Cast to TV (Miracast):** a tester sees coloured noise on the TV. Screen recording works. A log of a cast is needed.
- **Keyboard case:** a tester reports that it shows as a touchpad. A log with the keyboard attached is needed.
- **Navigation bar:** some apps draw content behind it.
- **HeyTap:** this CN ROM and global OPPO/OnePlus phones use separate account servers.
- **Play Integrity:** only BASIC integrity. No keybox is included.
- **Find My Device** (it cannot be switched on) and **cloud password sync** are not available (they need OPPO secure
  storage).
- **USB-C monitor:** colours on the monitor are a bit warm (the tablet's colour correction applies to all screens).
- Open reports that could not be reproduced: silent microphone recordings, recorder stutter, random screen flicker.
- Public list: https://github.com/Stefan-Atanasov/pipa-cos17-port/blob/main/KNOWN-ISSUES.md

## Tests beta7.2 (maintainer device, 2026-11-06)

- [x] Dirty flash pt63 (beta7.1) -> pt66 -> pt68: boot OK, automated check 57 pass, 0 fail (1 warning: nandswap right
      after boot); no crash, no ANR
- [x] Real call with call sharing on the speaker: echo gone after the first seconds, loudness OK (user)
- [x] Log test, 1 minute (Settings, recents, Spotify): 53 177 -> 8 797 lines; 0 SELinux denials from the ROM
- [x] Logs tile: Quiet <-> Verbose applied in about 1 s
- [x] Framework boot image built and compiled after the jar changes (no verify error)
- [ ] Clean install of 7.2 (beta7.1 clean install tested)
- [ ] Night standby on this build

## Tests beta7.1 (maintainer device, 2026-11-05)

- [x] Clean flash (wipe like the flash script, beta7 firmware and kernel): setup wizard OK, SukiSU manager, Play Store,
      Google app and Gboard installed in the first minute (each on the first try), Gboard default, Circle to Search
      assistant set, Visual blur + Contour glow on, blur switches visible with "Fast"
- [x] Automated check 57 pass, 0 fail (1 warning: a ColorOS log size value); no crash, no ANR, no denial from the port
- [x] Dirty flash over beta7-based data: installed apps and the keyboard kept, no second install
- [x] Dirty flash over a simulated beta6 user (tier 3, Visual blur and Contour glow off, stock Wallpapers): after the
      boot Fast + blur + glow on, SystemUI and launcher restarted once, the blur switches visible; automated check 56
      pass, 0 fail
- [x] Charging pop-up: no pop-up after a boot on USB power (pt63, dirty flash), battery app runs, no crash
- [ ] Night standby on this build (beta6: 0.21 %/h)

## Tests beta7 (maintainer device, 2026-11-04/05)

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
- [ ] Night standby on this build (beta6: 0.21 %/h)
- [ ] Keyboard case (no tester)
