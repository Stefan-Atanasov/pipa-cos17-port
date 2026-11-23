# ColorOS 17 for Xiaomi Pad 6 (pipa) — v9.3

Maintainer build by Stefan-Atanasov, based on 梦归zzz's beta4 port. Tested on one device (8 GB). Back up first.

Build: ROM **pt151** (`port.sh` up to step 8u), kernel **walt-hi15**. Donor: OPPO OPD2515 `17.0.0.104(CN01)` (C.07);
pipa vendor/odm/firmware from beta4. Root: **SukiSU Nova 3.0.0** (builtin; manager `com.sukisu.nova`).
Package date 2026-11-21.

## What's new in v9.3 (since v9.2)

Update from v9, v9.1 or v9.2 with "1) Update" in the flash script (keeps your apps and data).

**Pen buttons (kernel walt-hi15, Pipa Helper 2.9)**
- **Pen buttons work in StarNotes and other drawing apps again** (they stopped in v9.2). With the pen near the screen,
  the button now reaches apps over Bluetooth as well as through the screen, as in v9.1. Apps that use "hold the
  button to erase" (StarNotes "Button (press and hold)", Xodo, ...) work again. One press is still one press.
- **Press first, then bring the pen down:** if you press a pen button with the pen a few cm above the screen and then
  move it down to write or erase, the press now counts as a near press (stylus button, e.g. eraser). Before, the pen
  wrote ink and Quick Note opened. A press right after you lift the pen (within 0.8 s) also counts as near.
- **Long press is 500 ms by default** (was 380 ms), so there is more time to bring the pen down. You can change it
  in Pipa Helper > Pen > Pen buttons.
- **Pen buttons no longer stop working after a reboot** with the Pen buttons test screen open.
- StarNotes: its pen button actions are off until you set them (StarNotes > Settings > Stylus settings).
  "Primary key" and "Button (press and hold)" both work.

**32-bit apps**
- **32-bit-only apps start again.** They closed at once on every build since beta4 (the 32-bit graphics driver did
  not start). The 32-bit driver now comes from stock HyperOS. 64-bit apps and games keep the newer driver.

## What's new in v9.2 (since v9.1)

Update from v9 or v9.1 with "1) Update" in the flash script (keeps your apps and data).

**Accounts and updates**
- **OPPO / HeyTap account sign-in works.** It said "Device environment not secure". The account app needs a newer
  HeyTap mobile services app (MSP 2.3.0, from a stock ColorOS 17 device, OPPO signature). Use the phone number of your
  existing account: it signs in.
- **Built-in OPPO apps get their updates again** (system app updates, "SAU"). The updater quit at once on this port.
  Apps that the port changes keep their port version. OPPO system patches and OTA updates stay off on purpose.

**Display, cast and Gemini**
- **Smoother app open/close, swipes and scrolling (refresh rate).** Our traces showed that most short stutters come
  from refresh rate switches (60/90/120 Hz) in the middle of an animation: 18 % of frames near a switch were late, 5 %
  elsewhere. Three changes, all with OPPO's own settings:
  - the refresh rate changes 300 ms after an open/close animation, not on its first frames (as HyperOS does);
  - apps run at 120 Hz in Auto again (as in beta 8); video apps (YouTube, Netflix, ...) keep 60 Hz, and document
    apps (Docs, Office, WPS, PDF) keep 90 Hz, where 120 Hz janks;
  - the screen drops to 60 Hz 3.5 s after your last touch (was 2.5 s), so short pauses between swipes no longer
    switch. Reading and idle still save power.
  Result: a third fewer switches, none right after animations, no 90 Hz switches. Battery in our test was the same
  (in use 3.8 W, static screen 1.3 W, YouTube 1.9 W). For 120 Hz in every app (more power with video):
  Settings > Display > Screen refresh rate > High, then turn off "Supported apps".
- **White flash fixed (kernel):** on some panels the display lost a frame right after a 60 -> 90 Hz switch. The
  kernel now raises the display clock for every refresh change.
- **Gemini Live screen share works** (it showed a black screen and was very slow). Miracast stays smooth.
- **Cast to a Windows PC reconnects** without deleting the old Wi-Fi Direct group, and the PC prompt shows at once.

**Pen, keyboard and charging**
- **Pen buttons** work also when the pen is a few cm away from the screen; Notes pen/eraser switch and the OPPO
  shortcut wheel work. **Active pens without Bluetooth** (non-Xiaomi): Pipa Helper > Pen > always on.
- **Keyboard cover:** Caps Lock LED turns off when the screen goes off; pressing the Super key alone can run an
  action you choose (Pipa Helper > Keyboard > Super key; Super shortcuts stay as they are).
- **Charging while powered off** shows the charging screen again (it showed only the Xiaomi logo).

**Apps**
- **Settings:** a back swipe while the keyboard is open closes only the keyboard (it closed Settings in two-pane view).
- **Video recording in third-party camera apps has sound again** (e.g. GCam): the system now picks the right audio
  encoder. GCam is not included; a tested version is linked in the known issues.

**Pipa Helper 2.8**
- **System > Collect logs:** one tap after a problem saves the logs in Download (about 30 s), with personal data
  removed (emails, account and device names, phone numbers, Wi-Fi names and passwords, MAC addresses, locations).
  A notification lets you share the file or open the GitHub issues. Please attach it to bug reports.
- If Wi-Fi does not start correctly, a notification "Wi-Fi problem logged" asks you to collect the logs.
- Effects: animation style, animation speed, blur and contour glow, Apply (no reboot), reboot after a style change.
  **Animation style now waits for you:** choose Smooth (stock) or Rich, then tap Apply (status bar + home screen) or
  Reboot (everywhere). Before, the home screen restarted at once and closed the helper. "Light" is gone (it dropped
  OPPO's continuity animations); if you used it, you get Smooth. Reset to defaults also waits for Apply or Reboot.
- The "Live blur" Quick Settings tile is removed. The switch is in Pipa Helper > Effects > Live blur.
- Games: performance profile, device identity per game (try "real device" if a game looks wrong), your own games list
  (a game you add while it is open gets its profile at once).
- System: **Optimise apps** compiles your apps now, as Android does at night while charging (useful after an update).

**Under the hood**
- Less background work: the face unlock service is restarted only when it stops (no check every 15 s).
- Flash scripts in English: 1 = update (keep data), 2 = clean install (type ERASE to confirm).

## What's new in v9.1 (since v9)

Audio hotfix and a face unlock fix. Update from v9 with "keep data" (dirty flash).

- **No more short sound dropout when you change the volume.** Around 2/3 of the volume bar the speaker tuning
  switches (quiet / loud). Each switch made the pipa helper reset the MiSound sound processor: a short glitch.
  Helper 2.3 sends the tuning through its own Dolby handle and writes the MiSound setting only when it changes.
- **No more stutter when you open the sound settings.** The Settings sound page reads the effect state; each read
  caused 1 to 5 resets with helper 2.2. Now none.
- **No more blip about 3 s after the MiSound app starts.** The beta4 MiSound app turned on Dolby and the MiSound
  effect itself 3 s after each start (porter code, not stock). The helper does this job the stock way; that code
  is now off.
- **A tap on Dolby Atmos or Xiaomi Sound in Sound effects always works.** Before, a quick tap (within 3 s of
  opening the page, or of coming back from the equalizer) was undone, and the page then showed the wrong effect.
- **Face unlock setup: the camera preview is upright from the start** (it was rotated the first time after a clean
  flash or after turning the tablet, then squashed). Also a little less background work: the port service no longer
  checks for the face camera every 3 s.
- (Withdrawn in v9.2) Display driver change for transparency values after a rotation: the refused values were
  rotation transforms (normal Android behaviour), not the white flash. The real cause of the flash is fixed in v9.2.
- Tested with music playing: 8 volume steps across 2/3 = 8 resets on v9, 0 on v9.1; sound settings open 5 -> 0;
  MiSound screen open 1 -> 0. Dolby Atmos and Xiaomi Sound switch as before.

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
- **macOS:** new flash script `FlashMac.sh` (with Google's macOS fastboot). A user flashed with it successfully on a Mac (2026-11-20).
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
- Update from v9, beta6, beta7, beta7.1, beta7.2 or beta 8: flash with "keep data" (answer `1`).
  From another ROM: clean install (answer `2`, then type `ERASE`). A clean flash erases data. A separate `v9.3-noenc` package (no /data encryption, Linux dual boot, clean flash only, experimental) exists. Do not change between encrypted and noenc packages with "keep data".
- **The first minutes after a clean flash:** the port installs Play Store, Gboard, the Google app and the SukiSU Nova
  manager in the background (about 1 minute). Let it finish.
- **Install kernel walt-hi15 with the ROM** (the package does this; the bundled Nova manager needs it). The beta8 test zip has r17, which still has the touch bug. RAM expansion needs r24 or newer.
- **If the flash stops with "Failed to set slot B":** the bootloader sometimes reports no slots. Run
  `fastboot reboot bootloader`, then start the flash script again. Nothing was written at that point.
- **Technical:** ROM super.img md5 `83d2a2c60e473c0e66a0411092613346` (pt151), boot image md5 `384b81f8290e8c899ec4f91ff5c909ef` (walt-hi15). Source and step list:
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

## Tests v9.3

- [x] walt-hi14 (hi15 base): all Pen buttons settings, Xodo eraser by screen / Bluetooth / both, StarNote both modes, OPPO Notes one switch per press, device_check 58 pass, 0 fail
- [x] 32-bit EGL test (app_process32): no context with the beta4 set, OpenGL ES 3.2 on Adreno 650 with the HyperOS set
- [ ] hi15: press with the pen away, then bring it down (real pen)
- [ ] pt151: 32-bit test app opens; device_check

## Tests v9.1

- [x] pt129 (7y + 7z) dirty flash over v9: boot OK, device_check 57 pass, 0 fail; Dolby on after reboot (helper has control)
- [x] Music playing: 8 volume steps across 2/3 = 0 resets (v9: 8); sound settings open 0 (v9: 5); MiSound screen open 0 (v9: 1)
- [x] MiSound: Dolby Atmos <-> Xiaomi Sound switches the effects; the page shows Dolby Atmos after a restart
- [x] User listening test (helper 2.3): volume changes clean
- [x] pt132 (v9.1) dirty flash: device_check 58 pass, 0 fail; 0 plane alpha errors after rotation (pt131: ~20/s)
- [x] pt131 dirty flash: device_check 57 pass, 0 fail; face HAL refreshed from the ROM; face unlock OK (user)
- [x] pt130 dirty flash: device_check 57 pass, 0 fail; Dolby on after reboot; quick taps stored
- [x] Face setup preview (8b, live on pt130 with the old value set wrong): landscape upright and not squashed from the start; portrait right
- [x] helper 2.4 live on pt129: quick taps after a cold open and after the equalizer page are stored; page shows the right effect

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
- [x] FlashMac.sh on a real Mac (user report 2026-11-20)
