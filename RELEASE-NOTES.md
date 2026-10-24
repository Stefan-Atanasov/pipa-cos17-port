# ColorOS 17 for Xiaomi Pad 6 (pipa) — beta5 (2026-10-24)

Maintainer build by Stefan-Atanasov, based on 梦归zzz's beta4 port. **Beta:** tested on one device (8 GB): dirty updates from beta4
through every beta5 build, and a clean flash. Back up first.

Build: ROM layer `2v`, kernel `walt-r6`. Donor: OPPO OPD2515 `17.0.0.103(CN01)` (C.06); pipa vendor/odm/firmware from beta4.

## Highlights

- **App freezer works (new):** ColorOS freezes the apps that you do not use ("Hans"). In beta4 and earlier beta5
  builds, the kernel did not have OPPO's freezer channel. Thus no app was frozen, and background apps used the CPU.
  Test with many open apps: long stalls 262 → 2, long frames (> 120 ms) 42 → 9. Standby battery also gets better.
- **Smoother app opening (new):** the launcher animation tier is 3. Tier 3 removes the wallpaper zoom. Dropped frames
  during app open and close: 2.7 % → 0.3 %. To change the tier, use the Quick Settings tile **"Animations"**:
  3 Smooth (default) → 2 Parallel → 1 ColorOS → 4 Light, then reboot. Tier 2 keeps all ColorOS parallel animations
  (1.5 % dropped frames). A root shell can also set it: `settings put global pipa_anim_level 2`.
- **Memory reclaim off the fastest core (new):** with many open apps, memory compression (kswapd) used a third of the
  prime core. It now uses the other cores. Launcher hitches: 21 → 4.
- **Smoothness:** SurfaceFlinger, its GPU composition thread and the UI threads of the app you use now run on the big
  CPU cores; SurfaceFlinger gets enough time per frame at 120 Hz; system animation threads are prioritised; SystemUI,
  Settings and the launcher are fully compiled. In a heavy stress test (fast app switching, flings, shade, drawer)
  frames shown on time went from 59 % to 94-96 %, dropped frames from 6.5 % to about 1 %, and opening Settings from
  quick settings from ~300 ms to ~180 ms.
- **120 Hz in all apps** in the Auto refresh mode (ColorOS capped music and many other apps at 60/90 Hz, and the
  switch between rates in the middle of animations caused stutter). Fullscreen video still drops to 60 Hz.
- **Smoother by default:** window blur and material blur off (with the taskbar on, blur costs about 50 % more
  launcher jank), and the port's background service uses about 2 % of one CPU core instead of 15 %. For the smoothest app switching, turn the taskbar off (see Tips).
- **Pen battery in the ColorOS live alert:** when you dock or take out the Xiaomi pen, ColorOS's own capsule at the
  top shows the pen and its battery level (OPPO's pen app, patched to accept the Xiaomi pen).
- **Battery:** the keyboard-cover daemon no longer polls the accelerometer all night when no keyboard is attached
  (it kept the sensor hub and SoC awake); the GNSS service no longer retries a missing HAL every second.
- **Own kernel** (`walt-r6`, Linux 4.19.325): LineageOS base with WALT, pipa drivers, E404 display/touch, OPPO's
  "UI First" scheduler and "Hans" app freezer channel (what ColorOS 17 expects), SukiSU-Ultra root + susfs built in. Source:
  https://github.com/Stefan-Atanasov/kernel_xiaomi_pipa_cos17 (branch `oppo`).
- **No modules needed any more:** everything `pipa_core` and the power-tune module did is in the ROM (face unlock,
  pen, AOD, Dolby, charger shim, colour/adaptive restore, helper app with the pen battery pill).

## Fixes vs beta4

- Face unlock: preview rotation and crop, HAL watchdog; pen: battery pill and low-battery notice, "stylus connected"
  in Settings, 120 Hz while the pen is out, back button = screenshot, buttons merged into drawing apps; Dolby works
  from boot; correct boot rotation and logo; magnetic case (lid) works.
- Bedtime mode does not turn on at each boot any more. The colour mode is kept correctly. (Since beta5-2e, the port
  service could not read settings.)
- The pen "connected" capsule shows once at boot, not three times.
- The on-screen keyboard shows after a clean flash (the keyboard driver always reports a "Xiaomi Keyboard", so
  Android hid it). With the keyboard cover you can turn it off: Settings, on-screen keyboard.
- Face unlock setup: the camera preview is upright in landscape on a clean install.
- "Battery may not be genuine" dialog gone (the charger shim reports the battery as genuine).
- Screen glitches in Settings search fixed (SurfaceFlinger layer caching off).
- ColorOS sound effects (AudioX) no longer retry in a loop.
- OPPO's updater removed: it only offered OPPO Pad Mini app bundles, never system updates for pipa.
- Three C.06 boot hangs fixed (OPPO engineering HAL, Qualcomm QSPM wait).
- Security: ADB authorisation and `ro.secure` restored; SELinux enforcing.

## Install

1. **Back up.** Coming from beta4 or an earlier beta5: **remove the `pipa_core` and power-tune modules first** (the
   ROM does their job now; running both duplicates services). The optional `pipa_susfs` module (root hiding) is fine.
2. Run `FlashLinux.sh` / `FlashWindows.bat` from the package (slot B). **Enter = dirty flash** (keeps data): works from
   beta4; the maintainer's tablet came from beta4 this way without a wipe. **y = clean flash**: use it when coming
   from another ROM, or if anything misbehaves after a dirty flash.
3. First boot takes a few minutes ("Optimizing apps"); about 3 minutes after the first boot the ROM compiles
   SystemUI, Settings and the launcher once in the background, so the first minutes can feel slower.
4. Root: install **`extras/SukiSU_v4.2.1-r1_41049-release.apk`** (SukiSU-Ultra manager 4.2.1-r1; the kernel has a newer
   SukiSU than beta4's). Open it once.
   Optional root hiding: `extras/pipa-susfs-v1.0.zip` (install it as a module in the manager).
   **Do not update the manager to 4.2.1-r2 or newer yet.** The kernel has SukiSU 4.2.1-r1. A later kernel will update both.
5. Accept the ADB authorisation prompt on the tablet if you use ADB.

## Tips

- The ROM turns material blur, animation blur and window blur off once at the first boot. To get blur back: search "blur" in
  Settings, and Developer options → "Allow window-level blurs". Animation scales stay at 1.0.
- Add the **"Animations"** tile in Quick Settings (edit mode). Tap it to change the animation tier. The launcher
  changes at once; **reboot** so that Quick Settings and the rest of the system also use the new tier.
- Smoothest setup measured for fast app switching: **taskbar off** (`adb shell settings put system
  enable_launcher_taskbar 0`). The ColorOS taskbar redraws on every frame of each app open/close; with it off the
  long launcher hitches (> 120 ms) were gone in the test.

## Known issues

- Network sharing (interconnect) and the privacy password / app lock do not work.
- Wi-Fi may occasionally fail to turn on; a reboot fixes it.
- Some apps may draw slightly behind the navigation bar.
- The refresh rate does not drop when the screen is idle (120 Hz stays on).
- Face enrollment can crash near the frame edge; retry works.
- A "Xiaomi Keyboard configured" notification can appear without a keyboard (turn off "Physical keyboard"
  notifications).
- Settings → Stylus shows the Xiaomi pen as "disconnected" (that page only tracks OPPO pens); the pen works.
- The keyboard cover's fold-behind auto-disable is untested (no keyboard here); typing should work.
- Play Integrity: BASIC only (unlocked bootloader); apps that need DEVICE integrity will not work.
- Adaptive colour follows the colour-temperature sensor only (no lux bridge).

## Please report

Boots or not, clean or dirty flash, face unlock, pen, keyboard cover (if you have one), Wi-Fi, battery drain overnight,
any stutter (which app or gesture).

## Build it yourself

Scripts, sources and docs: https://github.com/Stefan-Atanasov/pipa-cos17-port (start at `BUILD-GUIDE.md`).

## Credits

- **梦归zzz**: the original ColorOS 17 port for pipa and the `pipa_core` module
- **Stefan-Atanasov**: maintainer, beta5 rebase, ROM fixes, kernel
- LineageOS, liyafe1997 (pipa kernel drivers), kvsnr113 (E404 kernel), SukiSU-Ultra, susfs, OPPO (open-source kernel)
