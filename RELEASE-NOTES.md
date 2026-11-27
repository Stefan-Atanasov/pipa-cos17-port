# ColorOS 17 for Xiaomi Pad 6 (pipa) — v10

Maintainer build by Stefan-Atanasov, based on 梦归zzz's beta4 port. Tested on one device (8 GB). Back up first.

Build: ROM **pt180** (`port.sh` up to step 9u), kernel **walt-hi17**. Donor: OPPO OPD2515 `17.0.0.104(CN01)` (C.07);
pipa vendor/odm/firmware from beta4. Root: **SukiSU Nova 3.0.0** (builtin; manager `com.sukisu.nova`).
Package date 2026-11-27.

## What's new in v10 (since v9.3)

Update from v9, v9.1, v9.2 or v9.3 with "1) Update" in the flash script (keeps your apps and data).

**Updates without a PC (Pipa Helper 3.7)**
- **Pipa Helper > System > Updates:** "Check for updates" shows a new version. "Install update" downloads it and
  installs it into the second system slot while you use the tablet. One restart at the end. Your apps and data stay.
- Updates are small: a delta of about 100 MB instead of the full ROM.
- If the new system does not start, the tablet goes back to the old one by itself.
- "Check automatically" (optional): once a day, a notification only. It downloads nothing.
- This works from v10 on. To get v10 from v9.3 or older, use the flash script (PC) one more time.

**Smoother screen**
- **Lock screen and unlock:** the lock screen now follows your refresh rate setting. Before, it always ran at 144 Hz
  and switched to 120 Hz in the middle of each unlock animation, which made the animation stutter.
  - Auto and High: 120 Hz on the lock screen, the home screen and in apps (as on the OPPO Pad Mini).
  - High > Refresh rate > **FPS Max 144 Hz**: 144 Hz everywhere. Games in OPPO's list can use up to 144 Hz.
- **Wake up:** one short stutter about half a second after each wake is gone (kernel walt-hi17: the panel's
  dimming command is sent in one transfer).
- **Games:** the main game thread runs on the fastest CPU core (BGMI, PUBG MOBILE and other heavy games: steadier
  frame rate). BGMI uses the same refresh rule as PUBG MOBILE.

**Pen (kernel walt-hi16+, Pipa Helper 3.0)**
- **Pen buttons in Notein and StarNote:** Pipa Helper > Pen > Pen buttons > "Apps made for the Xiaomi pen". In these
  apps a press near the screen works as on HyperOS (for example the Notein back button).

**Connectivity**
- **Hotspot:** 5 GHz band and Wi-Fi 6.
- **Dual Wi-Fi:** two Wi-Fi networks at the same time (as on HyperOS).
- **Quick Settings:** hotspot and Dolby Atmos tiles (Pipa Helper 3.1).

**Fixes for a warm tablet and a camera crash**
- **Face unlock with a second user, a guest or a private space:** the face service could not make its folder for
  that user and Android retried without end. The tablet stayed warm (about 1.5 CPU cores busy) and a face log
  filled the storage (up to 100+ GB). Fixed; the face log is also quiet now. The update cuts an oversized face log
  once.
- **Face unlock in a dark room** no longer crashes the camera service.
- Do not use the KernelSU module "pipa ColorOS 17 Thermal & Battery Fix" with v10: v10 has the face fix built in.
  Remove the module after the update. Its power settings are not needed: in our unplugged test its lower CPU floor saved
  about 1.5 % of screen-on idle power (259 vs 263 mA); the warm tablet came from the face loop.

**Settings and system**
- **Floating windows:** up to 4 at the same time (before: 2; OPPO's "panorama" multi-window mode allows only 2 on
  tablets with 8 GB RAM, the port turns it off). Recents: tap the app icon above a card for Floating window or
  Split View.
- **Battery > Battery health:** "Maximum capacity" is shown.
- **Extra dim** (Settings > Accessibility) works.
- **Google switch** (Settings > System & update > Google settings): Off turns off Google Play services (and with it
  Quick Share). On turns them on again. The system no longer asks you to turn Google on again and again.
- **Double tap to wake** can be turned off.
- **Charging limit:** the limit also holds while the screen is off. Before, the tablet could charge past it while it
  slept.
- **Collect logs** (Pipa Helper > System): includes the log of a spontaneous restart, and errors of the last hours in a
  file that stays after a restart (below 10 MB).

## Notes

- **The first boot takes about 1 minute longer** than usual: Android compiles the framework. Do not reboot it.
- Update from v9, v9.1, v9.2 or v9.3: flash with "keep data" (answer `1`). From another ROM: clean install (answer
  `2`, then type `ERASE`). A clean flash erases data.
- **The first minutes after a clean flash:** the port installs Play Store, Gboard, the Google app and the SukiSU Nova
  manager in the background (about 1 minute). Let it finish.
- **Time zone after a clean install:** the tablet starts on China time (UTC+8). The automatic time zone needs a
  SIM card, so set it once: Settings > search "Date & time" > turn off the automatic time zone > choose your region.
- **If the flash stops with "Failed to set slot B":** the bootloader sometimes reports no slots. Run
  `fastboot reboot bootloader`, then start the flash script again. Nothing was written at that point.
- **Technical:** ROM super.img md5 `7b78038cfd5741ecb2424e16761118b5` (pt180), boot image md5
  `239d02f4c95087086d7f8f9320e7b078` (walt-hi17).
  Source and step list: https://github.com/Stefan-Atanasov/pipa-cos17-port
- **KernelSU modules:** script modules (`service.sh`, `post-fs-data.sh`) and `system.prop` work. Modules that
  replace system files (a `system/` folder) need a KernelSU metamodule; none is included. Modules with their own
  SELinux rules (`sepolicy.rule`) are not tested. Zygisk modules need a Zygisk implementation.

## Known issues

- **Animation style Rich** (Pipa Helper > Effects) drops about 4 times more frames than Smooth (the default) in fast
  app open/close: the GPU of the Snapdragon 870 is at its limit. Use Smooth for the smoothest result.
- **Apps with a root check** (for example some banking or streaming apps) can refuse to start: KernelSU is built
  into the kernel. A kernel without root is planned for a later release.
- **Excel and document viewer:** scrolling in the default document viewer (Excel files) feels jittery. The app is
  slow at 120 Hz; Settings and other apps are smooth.
- **RAM in heavy games:** in BGMI and Racing Master with less than 1 GB free, frames drop and sound can cut. Tested on
  8 GB only. **The 6 GB Pad 6 is not tested** (OPPO's rule gives it a 3072 MB lz4 zram).
- **Keyboard cover:** with the cover attached Android lists a touchpad and a mouse the cover does not have
  (cosmetic; a game may show a controller icon).
- **Bypass charging** in games: it starts only when Game Assistant > Bypass charging has "auto open" on (or you turn
  it on in the Game Assistant panel), and it turns off with the screen off. This is the same on stock ColorOS.
- **Smart charging:** the 80 % hold needs ColorOS's sleep prediction, which trains only after several nights without
  a reboot. The fixed charging limit works.
- **Navigation bar:** some apps draw content behind it.
- **HeyTap:** this CN ROM and global OPPO/OnePlus phones use separate account servers.
- **Play Integrity:** only BASIC integrity. No keybox is included.
- **Find My Device** (it cannot be switched on) and **cloud password sync** are not available.
- **USB-C monitor:** colours on the monitor are a bit warm.
- Public list: https://github.com/Stefan-Atanasov/pipa-cos17-port/blob/main/KNOWN-ISSUES.md

## Tests v10

- [x] device_check pt180 + walt-hi17: 58 pass, 0 fail, 1 warn (natural tone display off on a fresh setup)
- [x] Refresh: Auto and High 120 = 120 Hz on home, Settings, scroll, screen off and lock screen; FPS Max 144 = 144 Hz
      everywhere (OPPO's own peak, no correction by the port service)
- [x] Unlock trace: no refresh switch in the unlock animation; 0 frames over 25 ms
- [x] Wake trace (3 wakes): worst display commit 5.3-5.8 ms (walt-hi16: 20-27 ms), no DSI errors
- [x] Fast app open/close trace: Smooth 0.6 % dropped frames; Rich about 3 %
- [x] OTA: pt175 -> pt176 -> pt177 by Pipa Helper on the maintainer tablet; a tester on pt172; pt177 -> pt178 (the first v10
      upload) with update_engine on the maintainer tablet
- [x] Floating windows: 4 at the same time; split view, Recents and Pipa Helper in a floating window work
- [x] Back gesture: left edge, right edge, portrait and landscape
- [x] Clean flash with the v10 package of pt178 (= this build without step 9u): setup wizard, first-boot installs,
      root; then pt178 -> pt179 -> pt180 as OTA deltas on the same tablet
- [x] Second user (pm create-user + switch): 0 face errors, folder made, nothing after the user is removed
      (before: ~21000 errors and 7 MB of face log in 25 s)
- [x] 20 wakes in the dark with face unlock: 0 camera service crashes (before: 1 in 3-4 wakes)
