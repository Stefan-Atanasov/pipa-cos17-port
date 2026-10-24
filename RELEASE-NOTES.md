# ColorOS 17 for Xiaomi Pad 6 (pipa) — beta5 (2026-10-24)

Maintainer build by Stefan-Atanasov, based on 梦归zzz's beta4 port. **Beta:** tested on one device (8 GB), dirty-upgraded from beta4
through every beta5 build; a clean flash of this package is still to be tested. Back up first.

ROM `beta5-2p` + kernel `walt-r5`. Donor: OPPO OPD2515 `17.0.0.103(CN01)` (C.06); pipa vendor/odm/firmware from beta4.

## Highlights

- **Smoothness:** SurfaceFlinger, its GPU composition thread and the UI threads of the app you use now run on the big
  CPU cores; SurfaceFlinger gets enough time per frame at 120 Hz; system animation threads are prioritised; SystemUI,
  Settings and the launcher are fully compiled. In a heavy stress test (fast app switching, flings, shade, drawer)
  frames shown on time went from 59 % to 94-96 %, dropped frames from 6.5 % to about 1 %, and opening Settings from
  quick settings from ~300 ms to ~180 ms.
- **120 Hz in all apps** in the Auto refresh mode (ColorOS capped music and many other apps at 60/90 Hz, and the
  switch between rates in the middle of animations caused stutter). Fullscreen video still drops to 60 Hz.
- **Pen battery in the ColorOS live alert:** when you dock or take out the Xiaomi pen, ColorOS's own capsule at the
  top shows the pen and its battery level (OPPO's pen app, patched to accept the Xiaomi pen).
- **Battery:** the keyboard-cover daemon no longer polls the accelerometer all night when no keyboard is attached
  (it kept the sensor hub and SoC awake); the GNSS service no longer retries a missing HAL every second.
- **Own kernel** (`walt-r5`, Linux 4.19.325): LineageOS base with WALT, pipa drivers, E404 display/touch, OPPO's
  "UI First" scheduler (what ColorOS 17 expects), SukiSU-Ultra root + susfs built in. Source:
  https://github.com/Stefan-Atanasov/kernel_xiaomi_pipa_cos17 (branch `oppo`).
- **No modules needed any more:** everything `pipa_core` and the power-tune module did is in the ROM (face unlock,
  pen, AOD, Dolby, charger shim, colour/adaptive restore, helper app with the pen battery pill).

## Fixes vs beta4

- Face unlock: preview rotation and crop, HAL watchdog; pen: battery pill and low-battery notice, "stylus connected"
  in Settings, 120 Hz while the pen is out, back button = screenshot, buttons merged into drawing apps; Dolby works
  from boot; correct boot rotation and logo; magnetic case (lid) works.
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
4. Root: update to the **SukiSU-Ultra manager 4.2.1-r1** APK (the kernel has a newer SukiSU than beta4's).
5. Accept the ADB authorisation prompt on the tablet if you use ADB.

## Tips

- Smoothest setup measured: turn ColorOS **"Material blur" off** (search "blur" in Settings, or
  `adb shell settings put system system_material_blur_enable 0`). It removes the frosted background of folders and
  the taskbar and cuts launcher jank by about 40 %. The taskbar can stay on.

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
