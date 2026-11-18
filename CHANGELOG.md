# Changelog: beta7.1 → v9 (Xiaomi Pad 6, ColorOS 17 port)

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
