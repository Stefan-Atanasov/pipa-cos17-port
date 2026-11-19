# ColorOS 17 for Xiaomi Pad 6 (pipa) — v9

Maintainer build by Stefan-Atanasov, based on 梦归zzz's beta4 port. Tested on one device (8 GB). Back up first.

Build: ROM **pt128** (`port.sh` up to step 7x), kernel **walt-hi9**. Donor: OPPO OPD2515 `17.0.0.104(CN01)` (C.07);
pipa vendor/odm/firmware from beta4. Root: **SukiSU Nova 3.0.0** (builtin; manager `com.sukisu.nova`).
Package date 2026-11-18, released 2026-11-19.

## What's new in v9 (since beta 8 = pt81 + walt-r17)

Short changelog from beta7.1 to v9 (all areas): `CHANGELOG.md` in this package.

If you have the "beta 8" test zip (beta8-test-20261107), this is what changed for you.

- **Cast to TV and Screencast work:** Miracast and Windows "Wireless Display" show the picture (it was coloured
  noise). If a second connection to the same PC fails, forget the saved Wi-Fi Direct group on both sides.
- **O+ Connect / PC Extend:** no more corrupted lines across the screen when the refresh rate drops (kernel hi8).
- **Circle to Search and Gemini:** long press on the gesture bar opens Circle to Search directly. A swipe from a
  bottom corner opens the Gemini app (bundled, installed after the first boot). Settings > System navigation >
  "Digital assistant from Google" is back.
- **Root is SukiSU Nova 3.0.0** (the new name of SukiSU-Ultra). The new manager is bundled; the old SukiSU-Ultra
  manager is removed on update. Your modules and su grants stay.
- **Live Clock themes** (Settings > Home screen, Lock screen & style) can be applied now.
- **Lock screen clock flies to the home screen clock** on unlock, as on stock.
- **Face unlock works again after a PIN lockout** (before, it stayed off until face was enrolled again).
- **Battery:** the face camera now closes right after a cancelled face unlock. It could stay open with the screen off.
- **After a clean flash:** Gboard becomes the keyboard after the setup wizard (Sogou stayed before), and
  Settings > Sound effects shows Dolby Atmos (it showed Xiaomi Sound although Dolby was on).
- **"Live blur" tile (Quick Settings, off by default):** with it on, a playing video keeps moving behind Quick
  Settings and the notification shade (ColorOS normally blurs a still picture on this tablet class). It costs GPU
  while the panel is open: in our test the panel had 20 % janky frames instead of 4 %. Add the tile with the pencil
  (edit) button in Quick Settings, tap it, then reboot.
- **Animations** use tier 3 (full ColorOS animations) from the first boot.
- **Landscape home screen grid:** icons no longer run into the camera island area.

- **Touch no longer dies after the screen turns on.** Some tablets stopped reacting to touch until a reboot. The old
  kernel skipped one touch-chip step when the screen came on after "double tap to wake" had changed. This is fixed
  (kernel r19). Two safety nets were added: the driver retries the touch firmware load (r21), and if that fails
  three times it restarts the panel power by itself (r22). Gestures that failed while the tablet was charging
  may be fixed too: please report.
- **Keyboard cover:** fixed a driver bug that could lock up the system when you typed with the screen off (r21).
  A cover folded behind the tablet no longer types (needs r20 or newer). The Super key alone now opens All apps
  and not Breeno. The on-screen keyboard still shows when the cover is off. These items are still under test.
- **Dolby keeps its mode:** after "clear recent apps" and opening the Dolby equalizer, the tablet no longer
  switches to Xiaomi Sound by itself (helper 1.8). Dolby is also checked again 10 and 30 seconds after boot, so the
  rare "no Dolby after a reboot" case should be gone. Tested on the speaker; headphones are not tested yet.
- **Home screen uses the full width:** the wide empty margins left and right of the icon grid in portrait are gone.
  The tablet now uses OPPO's own tablet values (a leftover port overlay forced bigger margins).
- **Device name is "Xiaomi Pad 6"** (it said "OPPO Pad Mini"). The screen size in About shows 11.0 inch, and the
  English market name is set.
- **Hidden switches that never worked on this tablet:**
  - Settings > System navigation > "Digital assistant from Google" (corner swipe). It cannot work next to Circle
    to Search, which stays.
  - Settings > Accessibility & convenience > OTG connection. USB drives and mice work by themselves.
- **"Never" is back** in Display > Auto screen off.
- **More ColorOS features switched on** (values that only OPPO's own firmware set): fstrim after idle, background
  dexopt, two-finger split screen with the touchpad, 5 GHz hotspot by default.
- **Package cache fix:** the system now clears its package cache when the apps in the ROM change. Before, an update could
  keep using old cached app data (for example an old helper version).
- **Smoother refresh rate, as on stock OPPO.** The refresh rate rules and the 144 Hz column now follow OPPO's own
  files. The HWUI settings follow ColorOS too.
- **Memory works as on stock OPPO, with working RAM expansion.** OPPO's own memory setup runs now (zram, swappiness,
  low-memory limits). RAM expansion (Settings) works again. It needs kernel r24 or newer: install r26 with the ROM.
  With an older kernel the switch shows but does nothing. Three kswapd threads run. In our tests (PUBG with a RAM
  filler) there were no janky frames and no audio underruns. The kernel stops background swapping while the screen is off (r26).
- **Memory tuned between OPPO and HyperOS (8 GB):** swappiness 100 (OPPO uses 200, HyperOS 180). In our tests: fewer
  memory stalls, System UI janky frames 7.5 % instead of 10.5 %, and 12 apps reopened in 3.6 s instead of 6.0 s.
  The 6 GB tablet keeps OPPO's value (160).
- **App starts:** OPPO's performance service can now pause background swapping while an app opens (it was blocked
  by a missing SELinux rule). OPPO's RAM expansion script also got the rights it needs.
- **Game Space 10.44.6 is preinstalled** (the donor ROM had 10.40.22).
- **Pen input only while the pen is connected over Bluetooth.** Before, the panel looked for a pen all the time, also without a connection: any active pen could write, and the pen scan cost power.
- **Less touch delay in PUBG and other games:** open Game Assistant (swipe from the left edge in a game) >
  Performance > **Pro Gamer**, and set Touch sampling rate to **Ultra touch**. This turns on the Xiaomi touch game
  mode, as on stock. The pen does not write while the game mode is on.
- **Game touch settings stay on after the screen was off.** Ultra touch and the Game Assistant touch sliders (tap
  sensitivity, touch sensitivity, smoothness, edge) were lost at each screen off/on: the touch chip reloads its
  firmware. Kernel walt-hi5 sends them again. The pen also no longer stays off when game mode was turned off while
  the screen was off.
- **Display size has Large again:** Settings > Display > Display size shows Small, Standard and Large (Large = the
  bigger size from older builds). After an update the page shows the size you really use.
- **Sideloaded apps install:** APKs that OPPO's cloud scan marks "High-risk" (for example repacked games installed
  with SAI) no longer stop at "Unable to install". The installer shows its normal page.
- **Landscape home screen:** the page dots no longer touch the icon labels and the dock.
- **App Market updates cannot break the port:** the apps that the port changes have a higher version, so an
  update cannot replace them. OPPO SOTA system updates do not run on the port (they need verified boot).
- **GCam with HDR+ works.** The ROM has the gralloc fix for RAW10/RAW12 camera buffers (before, HDR+ shots failed).
  Tested: BigKaka **AGC 9.6.19 V7.0** (`com.agc.gcam96`, download from celsoazevedo.com), rear HDR+, front camera
  and Night Sight. Use the default settings. Keep "RAW16" and "Fix Raw16 merge" off. If HDR+ shots fail after you
  changed a config, clear the GCam app data and start again.
- **Location:** the network location provider is fixed to OPPO's, as on stock. Before, it could switch to Google's
  after an app update.
- **Floating window from the dock:** drag the app icon to the middle of the screen and hold it still for a moment:
  the "Floating window" area shows. If you keep moving, only the split-screen areas show (stock ColorOS).
- **Games:** if a game is stuck at 60 fps, check its frame rate setting. "Smart Adjust" and "Power Saving" in the
  game can cap it at 60 fps. OPPO's rule for PUBG allows 90 Hz (144 Hz in "FPS Max").
- **Should work, please test:**
  - Passive USB-C earphones (no DAC, for example Realme Buds 3 Type-C). The audio switch is set to analog mode.
  - Bluetooth audio sharing: play to two Bluetooth headphones at once (Settings > Bluetooth).
- Wi-Fi: the vendor ini now has the stock recovery flag. It may not fix the "Wi-Fi does not turn on" case.
- The touch shim no longer sets the edge filter when the keyboard shows (fewer missed edge swipes).
- There is no DSP "Hey Breeno" wake-up: the pipa sound trigger cannot run it, and the audio service crashed in a
  loop when it was on. The flags are off now.
- **macOS:** new flash script `FlashMac.sh` (with Google's macOS fastboot). Not tested on a real Mac yet.
- Kernel walt-hi1 adds two OPPO status files that ColorOS services read (`/proc/oplus_healthinfo`, `/proc/fg_info`).
  No visible change.
- Update from beta8-test: flash with "keep data". The first boot after the update can take longer.

## Since beta7.2 (if you skip beta 8)

- **Dolby Atmos like on HyperOS:** the stock HyperOS 2 Dolby library. Dolby picks the stock tuning for the output
  and the volume (speaker, headphones, Bluetooth, USB).
- **Better speaker sound:** a speaker EQ measured with a microphone: deeper bass, less boomy upper bass, smoother
  treble. Only the speakers change. The Dolby equalizer still works on top. No distortion at maximum volume.
- **Dolby stays on after the screen was off,** and the effect is set per device like on HyperOS ("Original" for
  Bluetooth, Dolby for the speakers). Dolby and Xiaomi Sound are never on at the same time.
- **Sound effect settings cleaned up:** only the working Dolby / MiSound entry, in English. The ColorOS "OReality"
  modes need OPPO audio hardware and did nothing.
- **Game Space "Ultra touch"** now uses the Xiaomi touch game mode (less touch delay in games like BGMI).
- **Breeno microphone:** vendor properties and the "no DSP wake-up" fix (see above); the mic can still fail
  sometimes.
- Your Dolby settings and Dolby equalizer reset once (new tuning file).
- Update from beta7.2: flash with "keep data".

## Notes

- **The first boot takes about 1 minute longer** than usual: Android compiles the framework. Do not reboot it.
- Update from beta6, beta7, beta7.1, beta7.2 or beta 8: flash with "keep data" (Enter on Linux, `N` on Windows).
  From another ROM: "y" (clean flash). A clean flash erases data. There is no `noenc` package for v9. Do not change between encrypted and noenc packages with "keep data".
- **The first minutes after a clean flash:** the port installs Play Store, Gboard, the Google app and the SukiSU Nova
  manager in the background (about 1 minute). Let it finish.
- **Install kernel walt-hi9 with the ROM** (the package does this; the bundled Nova manager needs it). The beta8 test zip has r17, which still has the touch bug. RAM expansion needs r24 or newer.
- **If the flash stops with "Failed to set slot B":** the bootloader sometimes reports no slots. Run
  `fastboot reboot bootloader`, then start the flash script again. Nothing was written at that point.
- **Technical:** ROM super.img md5 `6615f44c1f867097e1c12a7495f5750e` (pt128), boot image md5 `56033d4292908299d57850f3c49d36d5` (walt-hi9). Source and step list:
  https://github.com/Stefan-Atanasov/pipa-cos17-port
- **KernelSU modules:** script modules (`service.sh`, `post-fs-data.sh`) and `system.prop` work. Modules that
  replace system files (a `system/` folder) need a KernelSU metamodule; none is included. Modules with their own
  SELinux rules (`sepolicy.rule`) are not tested. Zygisk modules need a Zygisk implementation.

## Known issues

- **Excel and document viewer:** scrolling in the default document viewer (Excel files) feels jittery. The app is
  slow at 120 Hz; Settings and other apps are smooth.
- **Cast to TV (Miracast):** fixed on Windows; please test with a TV and report.
- **Location:** one tester reported that location did not work in any app on beta8. v9 fixes the provider choice
  (see above). If location still fails, send a log.
- **RAM in heavy games:** in BGMI and Racing Master with less than 1 GB free, frames drop and sound can cut. Tested on
  8 GB only. **The 6 GB Pad 6 is not tested** (OPPO's rule gives it a 3072 MB lz4 zram).
- **Keyboard cover:** fold, Super key and the typing fix are still under test. With the cover attached Android lists
  a touchpad and a mouse the cover does not have (cosmetic; a game may show a controller icon).
- **Breeno:** the microphone sometimes does not work (not reproduced).
- **Scrolling at 144 Hz with music or a video in the background** can judder a little (the media pill in the
  status bar animates). At 120 Hz or Auto it is smooth. Use 120 Hz or Auto for now.
- **Torch:** one tester saw the torch stay on and the tile turn grey. Not reproduced. The torch shares its LED
  with the rear camera: if it happens, note which app was open.
- **Refresh rate:** the panel stayed at 120 Hz on a static screen once; the cause is unknown. A reboot clears it.
- **Wi-Fi:** it sometimes does not turn on. Reboot the tablet.
- **Smart charging:** the 80 % hold needs ColorOS's sleep prediction, which trains only after several nights without
  a reboot. The fixed charging limit works.
- **Navigation bar:** some apps draw content behind it.
- **HeyTap:** this CN ROM and global OPPO/OnePlus phones use separate account servers.
- **Play Integrity:** only BASIC integrity. No keybox is included.
- **Find My Device** (it cannot be switched on) and **cloud password sync** are not available.
- **USB-C monitor:** colours on the monitor are a bit warm.
- Open reports that could not be reproduced: silent microphone recordings, recorder stutter, random screen flicker,
  striped picture in screen sharing.
- Public list: https://github.com/Stefan-Atanasov/pipa-cos17-port/blob/main/KNOWN-ISSUES.md

## Tests v9 (maintainer device, so far)

- [x] Dirty flash pt81 -> pt91, kernel r17 -> r22: boot OK, automated check 57 pass, 0 fail, 1 warning
- [x] pt96 + r26: automated check (device_check) 59 pass, 0 fail, 0 warnings
- [x] RAM: PUBG Training Ground (moving) + RAM filler (`mem_load.sh`, `game_move.sh`): no janky frames, no audio underruns. Direct-reclaim stalls at 120 fps (average): r23 1 kswapd 3324, r23 3 kswapd 1898, r24 hybridswap on 1231, off 1396
- [x] Screen-off gate (r26): memory load with the screen off, 0 swapd wakeups (r24/r25: 20)
- [x] Touch: 10 screen off/on cycles on r21, fake-failure test of the r22 panel restart passed
- [x] Name, screen size, fstrim job, hidden corner swipe switch, "Never" timeout (live)
- [x] Home screen margins (OPPO values 80/102)
- [x] Dolby after clear recents on the speaker (cold start, late write, force-stop + reopen)
- [x] pt103 + walt-hi1: device_check 58 pass, 0 fail, 1 warning
- [x] Dolby applied after 10 of 10 reboots (pt103)
- [x] Settings walk: 190 settings listed, 103 switches toggled, 0 crashes
- [x] Game Space 10.44.6 from the system image: Pro Gamer + Ultra touch in PUBG
- [x] Swappiness A/B 60 / 100 / 200 (same boot, traced_heavy + 12-app retention)
- [ ] Dolby after clear recents with headphones
- [ ] Two Bluetooth headphones at once (audio sharing)
- [ ] Passive USB-C earphones
- [ ] Keyboard cover with pt91 + r22 (tester)
- [ ] RAM and RAM expansion on a 6 GB tablet
- [x] Night standby pt114 + hi5: about 0.15 %/h, 99 % deep doze
- [x] Pen with the pen detached, Ultra touch + screen off/on in a game, O+ Connect, Screencast to Windows (pt124/pt125)
- [x] Clean flash pt125 + walt-hi9: setup OK, bundled apps, root; found Gboard default and Sound effects label (fixed in pt127)
- [x] pt127 dirty: Sound effects page shows Dolby Atmos, device_check 58 pass, 0 fail
- [x] pt127 log check: 0 denials, crashes, ANRs, tombstones (40 min, incl. SystemUI restarts)
- [x] Clean flash pt128 + walt-hi9: setup OK, Gboard default after setup, Sound effects = Dolby Atmos, tiles Logs + Live blur, root, 0 denials/crashes; device_check 57 pass, 0 fail, 2 warnings (`logd` capture props at default; `sensorCCT` 0 because adaptive colour is off after a clean flash)
- [x] Night standby v9: about 0.18 %/h (15.5 mAh/h, drops only), 99 % deep sleep
- [ ] FlashMac.sh on a real Mac
