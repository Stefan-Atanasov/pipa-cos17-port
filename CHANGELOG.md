# Changelog: beta7.1 → v10.1 (Xiaomi Pad 6, ColorOS 17 port)

## v10.1 (2026-11-27: over-the-air update, ROM pt183 + kernel walt-hi17)
- **Full OPPO tablet multi-window:** up to 4 floating windows at the default Display size, 5 with a smaller Display size (Settings > Display; OPPO allows 5 only from 800 dp screen width) and the four-finger gestures (pinch out: floating windows to split view, one floating window to full screen; pinch in: back to floating). v10 had turned off OPPO's panorama mode to get 4 windows, which also turned off the gestures; v10.1 keeps the mode and lets the 8 GB Pad 6 use OPPO's full tablet version (BUGS 216).
- **Recents with floating windows:** each floating window is a card next to its app; no windows on top of Recents, no frame drops on app switches (the first v10.1 build pt181 had both; BUGS 217).
- **Settings > About device:** the ColorOS card opens the update check in Pipa Helper (BUGS 219).
- Pipa Helper 3.8: fits a floating window (BUGS 218).
- Update in Pipa Helper > System > Updates (about 100 MB from v10 or from pt181). No new PC package: clean installs flash v10, then update.

## v10 (2026-11-27: ROM pt180 + kernel walt-hi17)
- **Updates without a PC:** Pipa Helper > System > Updates installs new versions into the second system slot (about 100 MB deltas, one restart, automatic fallback to the old system). Optional daily check with a notification (BUGS 191, 193). v10 is the base: every v10 install (this package or the OTA) gets the next versions this way. From v9.3 or older: flash v10 with the PC once.
- **Smoother unlock:** the lock screen follows the refresh rate setting (Auto and High: 120 Hz; FPS Max 144 Hz: 144 Hz). Before, it ran at 144 Hz and switched to 120 Hz in each unlock animation (BUGS 210, 212).
- **No stutter after wake:** kernel walt-hi17 sends the panel's dimming command in one transfer (one 25 ms frame on every wake before; BUGS 213).
- **Games:** the main game thread runs on the fastest core (steadier BGMI / PUBG frame rate, BUGS 175); BGMI uses the PUBG refresh rule.
- **Pen buttons in Notein and StarNote** work as on HyperOS ("Apps made for the Xiaomi pen", kernel walt-hi16+, BUGS 170).
- **Hotspot:** 5 GHz and Wi-Fi 6 (BUGS 171). **Dual Wi-Fi** (BUGS 173). Hotspot and Dolby Atmos tiles (BUGS 172).
- **Battery health** page with "Maximum capacity" (BUGS 176). **Extra dim** works (BUGS 190). **Double tap to wake** can be turned off (BUGS 174).
- **Google switch** in Settings > Google settings; no repeated prompts with Google off (BUGS 200).
- **Charging limit** holds with the screen off (BUGS 204).
- **Up to 4 floating windows** (was 2): OPPO's panorama multi-window mode is off; it allows only 2 windows on 8 GB tablets (BUGS 201).
- **Collect logs** includes the log of a spontaneous restart and a persistent error log (BUGS 183, 198).
- **Warm tablet with a second user / guest / private space fixed:** the face service retried without end (1.5 cores busy, the face log filled the storage); face log quiet; an oversized log is cut once (BUGS 215).
- **Face unlock in a dark room** no longer crashes the camera service (BUGS 214).
- **Note:** after a clean install the tablet starts on China time (UTC+8); set your time zone once in Settings > Date & time.
- **Note:** do not use the KernelSU module "Thermal & Battery Fix" with v10: v10 has the face fix built in.
- Pipa Helper 3.7.

## v9.3 (2026-11-21: ROM pt151 + kernel walt-hi15)
- **Pen buttons work in StarNotes and other drawing apps again** (stopped in v9.2): with the pen near the screen the button reaches apps over Bluetooth as well as through the screen, as in v9.1 (kernel hi14/hi15, BUGS 166).
- **Press first, then bring the pen down** now counts as a near press (eraser / stylus button); before, the pen wrote ink and Quick Note opened. A press right after a lift (0.8 s) also counts as near (kernel hi15, BUGS 169).
- **Long press 500 ms by default** (was 380 ms); Pipa Helper > Pen > Pen buttons.
- **Pen buttons no longer stop after a reboot** with the Pen buttons test screen open (BUGS 167).
- **32-bit-only apps start again** (they closed at once since beta4): 32-bit graphics driver from stock HyperOS (BUGS 168).
- Pipa Helper 2.9.

## v9.2 (2026-11-21: ROM pt150 + kernel walt-hi13)
- **Smoother app open/close, swipes and scrolling:** the refresh rate switches 300 ms after an open/close animation, apps run at 120 Hz in Auto again (video apps 60 Hz, document apps 90 Hz), and the screen drops to 60 Hz 3.5 s after the last touch (BUGS 163).
- **White flash fixed (kernel hi10):** the display clock is raised for every refresh rate change (BUGS 48).
- **OPPO / HeyTap account sign-in works** ("Device environment not secure" is gone; MSP 2.3.0, BUGS 160).
- **Built-in OPPO apps get updates again** (SAU, BUGS 161).
- **Gemini Live screen share works.** Cast to a Windows PC reconnects.
- **Pen buttons** work also a few cm away from the screen; Notes pen/eraser switch and the shortcut wheel work. Pens without Bluetooth: Pipa Helper > Pen > always on.
- **Keyboard cover:** Caps Lock LED turns off at screen off (kernel hi11); the Super key alone can run an action you choose.
- **Charging while powered off** shows the charging screen again (BUGS 152).
- **Settings:** a back swipe with the keyboard open closes only the keyboard (BUGS 157).
- **Video recording with sound in third-party camera apps** (for example GCam, BUGS 159).
- **Pipa Helper 2.8:** System > Collect logs (logs without personal data in Download); Effects page (animation style, speed, blur, contour glow, Apply without reboot); animation style waits for Apply or Reboot; "Light" removed; Live blur tile removed (switch stays in Effects); Games: device identity per game, own games list; System > Optimise apps.
- Less background work (face unlock service restart only when it stops). Flash scripts in English.
- Update from v9 or v9.1: flash with "keep data".

## v9.1 (2026-11-19, audio hotfix on top of v9: ROM pt132 + kernel walt-hi9)
- **No short sound dropout on volume changes** (around 2/3 of the bar) and **no stutter when the sound settings open**: helper 2.3 no longer resets the MiSound sound processor (BUGS 144).
- **No blip 3 s after the MiSound app starts**: the beta4 porter code that turned on the effects in MiSound is off; the helper does this job the stock way (BUGS 145).
- **A tap on an effect in Sound effects always works**: a quick tap after opening the page or after the equalizer
  page was undone before, and the page showed the wrong effect (BUGS 146).
- **Face unlock setup preview upright from the first frame**, also after turning the tablet; not squashed (BUGS 147).
- **Display driver clamps transparency values** instead of refusing them after a screen rotation (likely cause of a
  short white flash; BUGS 48).
- Update from v9: flash with "keep data".

## v9 (2026-11-18)

v9 = ROM pt128 + kernel walt-hi9 (2026-11-18). v9 is the first stable release. It includes beta7.2 (2026-11-06) and the beta 8 test build
(never a public release). Update from beta7.1 or newer: flash with "keep data". From another ROM: clean flash ("y").

## Display, touch and pen
- **Touch no longer dies after the screen turns on** (some tablets needed a reboot). The driver also retries the
  touch firmware and restarts the panel power by itself if the touch chip does not answer.
- **Game touch:** Game Assistant > Performance > Pro Gamer + "Ultra touch" turns on the Xiaomi touch game mode (less
  touch delay in PUBG/BGMI). Ultra touch and the touch sliders stay on after screen off/on.
- **Pen only while it is connected over Bluetooth** (like HyperOS): no pen scan without a pen, saves power.
- **Refresh rate as on stock OPPO:** OPPO's refresh rules and the 144 Hz column (High > FPS Max 144, per-app
  "Supported apps" switches).
- **Display size has Large again** (Small / Standard / Large).
- **Home screen:** full width in portrait, landscape grid fixed (page dots, camera area).
- **Device name "Xiaomi Pad 6"**, screen size 11.0 inch in About.

## Sound
- **Dolby Atmos like on HyperOS:** the stock HyperOS 2 Dolby library with the stock tuning per output and volume.
- **Better speaker sound:** a speaker EQ measured with a microphone (deeper bass, smoother treble).
- **Dolby stays on** after the screen was off and after "clear recent apps"; set per device ("Original" for
  Bluetooth, Dolby for the speakers). Sound effect settings show only what works.
- **No more echo in voice chat and calls** (PUBG/BGMI voice, VoIP, phone link): software echo canceller + mic gain.
- **Bluetooth audio sharing** (two headphones at once) is visible. Passive USB-C earphones (no DAC) should work now
  (please test).

## Google, assistant and apps
- **Circle to Search:** long press on the gesture bar opens it directly.
- **Gemini:** a swipe from a bottom corner opens the Gemini app (bundled; installed after the first boot).
- **Cast to TV / Screencast:** Miracast and Windows "Wireless Display" show the picture (was coloured noise).
- **O+ Connect / PC Extend:** no more corrupted lines when the refresh rate drops.
- **Live Clock themes** can be applied. The lock screen clock flies to the home screen clock on unlock.
- **Face unlock works again after a PIN lockout.**
- **Sideloaded apps install** even when OPPO's cloud scan marks them "High-risk".
- **Game Space 10.44.6** preinstalled. **App Market updates cannot replace** the apps the port changes.
- **GCam HDR+ works** (tested: AGC 9.6.19 V7.0, rear HDR+, front, Night Sight; default settings).
- **Location:** the network location provider is OPPO's, as on stock.
- Hidden switches that work now: "Digital assistant from Google" (corner swipe), OTG connection; "Never" is back in
  Auto screen off.

## Performance and battery
- **Memory as on stock OPPO, with working RAM expansion** (zram + extra swap file); swappiness tuned for 8 GB
  (fewer stalls, faster app reopen). The 6 GB model keeps OPPO's value.
- OPPO's performance service can pause background swap while an app opens. Swap work stops with the screen off.
- **Animations:** full ColorOS animations (tier 3) and blur from the first boot.
- **"Live blur" Quick Settings tile** (off by default): live blur behind the shade; costs GPU while it is open.
- **Floating window from the dock:** drag to the middle and hold still.
- **Battery:** the face camera closes right after a cancelled face unlock (it could stay open with the screen off).
  Standby about 0.15 %/h. Battery usage per app uses pipa's real CPU layout.
- **83 % less log spam** (causes fixed). Logs tile: "Quiet" (default) / "Verbose" for bug reports.
- fstrim after idle, background dexopt, two-finger split screen with the touchpad, 5 GHz hotspot by default.

## Root and flashing
- **Root: SukiSU Nova 3.0.0** (new name of SukiSU-Ultra), manager bundled; the old manager is removed on update.
  Modules and su grants stay.
- **Keyboard cover:** no lockup when typing with the screen off; a cover folded behind the tablet does not type;
  Super key opens All apps. (Still under test.)
- **macOS:** `FlashMac.sh` (not tested on a real Mac yet).
- A dirty flash keeps a Linux/UEFI image in slot A (boot and dtbo go to slot B only).

## Known issues (short)
- Miracast with a TV: please test and report. Excel/document viewer scrolls jittery. 144 Hz + media in the
  background can judder: use 120 Hz or Auto. Wi-Fi sometimes does not turn on (reboot). Play Integrity BASIC only.
  Find My Device and SOTA system updates do not work. 6 GB model not tested.
- Full list: RELEASE-NOTES.md in the package.
