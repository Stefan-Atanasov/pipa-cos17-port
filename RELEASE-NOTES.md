# ColorOS 17 for Xiaomi Pad 6 (pipa) — beta6 (2026-10-30)

Maintainer build by Stefan-Atanasov, based on 梦归zzz's beta4 port. **Beta:** tested on one device (8 GB). Back up first.

Build: ROM `port.sh` up to step 3w (+ SukiSU manager v4.3.0), kernel `walt-r8kpm`. Donor: OPPO OPD2515
`17.0.0.103(CN01)` (C.06); pipa vendor/odm/firmware from beta4.

## Highlights

- **Display colours (new):** HDR video no longer has a green tint, and HDR photos are no longer dark (the OPPO
  HDR brightness boost is off: it did not work on this LCD). The "Standard" colour mode shows correct colours with a
  slightly warmer white (it was oversaturated). Adaptive tone now follows the room light like on OPPO phones.
- **Game Filter (new):** the filters match their names (Vivid, FPS vision, Fantasy vision, ...); colour enhancement
  is visible.
- **Pen dock:** the capsule shows about 1 s after you dock or undock the pen (was 3-4 s), also with the pen the
  other way round (the second dock sensor was not read before).
- **Face unlock works again** (since the security hardening in an earlier test build the face camera was blocked:
  black preview, "Add now" did nothing, unlock failed). Enrollment preview works in landscape and portrait.
- **Pen back button** is now the standard Android second pen button (apps decide what it does), like the front
  button. It no longer takes a screenshot.
- **Faster start:** the port service (pen buttons, pen capsule, keyboard guard, case lid) starts about 2 s after
  the boot (was about 20 s).
- **Fix:** the pen capsule no longer shows up with the pen in the dock. After many UI restarts, OPPO swap files no
  longer fill the storage.
- **Cleaner logs:** the battery service no longer writes an error line every few seconds while charging (it was
  not a real error; charging data is the same).
- **Netflix in HD (new):** Netflix now gets Widevine **L1** (checked with a probe; HD playback not confirmed yet). The tablet has real L1 hardware, but Netflix gives L1
  only to models on its list. The port shows Netflix (and only Netflix) a Pixel 6. If Netflix was installed before,
  clear its app data one time (Settings → Apps → Netflix → Storage → Clear data), then log in again.
- **Google Photos (new):** free, unlimited backup in **original quality** (Google Photos sees an original Pixel XL).
  Check: Photos settings → Backup → Backup quality. All other apps see the real device.
- **Standby battery:** the sensor hub sleeps again with the screen off (the ColorOS fold sensor was the Xiaomi knuckle
  sensor and kept it awake). Night test: 0.21 %/h (13 h, screen off, Wi-Fi and Bluetooth on).
- **Game Filter and colour enhancement work** (no screen freeze any more).
- **60 Hz when idle:** the panel drops to 60 Hz on a static screen.
- **Privacy password and app lock work** (software replacement for the missing OPPO TEE service).
- **Phone connection (interconnect):** network, call and SMS sharing with a phone.
- **HDR video:** HDR display mode, wide colour, YouTube HDR plays.
- **Video thumbnails** show again (64-bit media server).
- **Pen ready about 1 s after screen-on** (was up to 5 s).
- **Face enrollment** no longer crashes near the edge of the frame. Bedtime / Eye Protect settings stay after a reboot.
- **Kernel `walt-r8kpm`:** SukiSU-Ultra v4.3.0 (manager 41100), susfs, KPM. No more "Xiaomi Keyboard configured"
  notification and no phantom game controller without a keyboard; Wi-Fi connects about 17 s sooner after a boot. KPM is experimental.
- **SukiSU manager v4.3.0** is installed (or updated from 4.2.1) on the first boot. The update from 4.2.1 is not
  tested yet.
- **Dual boot friendly:** an update with "keep data" writes the boot image only to slot B. A Linux or UEFI image in
  `boot_a` and `dtbo_a` stays (not tested on a device yet). Read `DUALBOOT-LINUX.md` in the GitHub repo before you try a dual boot.

## Notes

- **The first boot takes about 1 minute longer** than usual: Android compiles the framework again. Do not reboot it.
- Update from beta5: flash with Enter ("keep data"). From another ROM: "y" (clean flash).
- Known issues: https://github.com/Stefan-Atanasov/pipa-cos17-port/blob/main/KNOWN-ISSUES.md

## Tests (one device)

Open items are not tested yet. Report results in the group. "maintainer" = a check by hand on the maintainer's tablet,
"automated" = `device_check.sh`, "probe" = a software check only. `ptNN` = a test build before beta6.

- [ ] Dirty flash from beta5 (manager 4.2.1 → 4.3.0, root works)
- [ ] Clean flash (root on first boot, setup wizard)
- [ ] Netflix HD playback after a data clear (probe: Widevine L1 with the Pixel 6 identity, pt11, 2026-10-29)
- [ ] Update with "keep data": `boot_a` and `dtbo_a` stay unchanged
- [x] Google Photos backup quality: Original, free (maintainer, pt13, 2026-10-29)
- [x] Night standby (pt18, 2026-10-29 20:40 → 10-30 09:58, 13 h 18 min screen off): 74 % → 71 %, 240 mAh = 18 mA,
  0.21 %/h (3j night: 22.5 mA, 0.26 %/h). Wake-ups: Bluetooth UART 343, RTC alarm 156. The colour sensor stream
  (adaptive tone) stops at screen-off; only the ambient light sensor stays on (stock)
- [x] Pen dock: capsule about 1 s after dock/undock, both pen orientations, no random capsule (3u, maintainer, 2026-10-30)
- [ ] Keyboard case (no tester)
- [x] Game Filter (maintainer): matrices follow the app descriptions (Vivid = saturation 1.25, maintainer choice); colour enhancement
  visible (fixed for pt14, 2026-10-29)
- [x] HDR (maintainer): no green tint (3q), HDR photos at normal brightness and no brightness jumps (EDR off, 3q) (pt14)
- [x] Standard colour mode (maintainer): Natural colours, slightly warmer white (3r, maintainer values) (pt14)
- [x] Adaptive tone (maintainer): follows the room like on OPPO phones (3s: continuous colour sensor, real lux); Bedtime always warmer, warm in a dark room (pt18, 2026-10-29)
- [x] Automated check: pt18 device_check 58 pass, 0 fail (2026-10-29 20:29); beta6 image (dirty flash on pt18) 58 pass, 0 fail, 0 warn (2026-10-30 13:15, final image d79419f9; face enroll/unlock and pen tested, 0 pipa_port denials)
- [x] Calls/SMS/network sharing via phone (maintainer): work (pt13, 2026-10-29); network sharing with Wi-Fi off (2026-10-30)
- [~] KPM: probably works, not checked in detail (pt13, 2026-10-29)
- Note: Game Assistant shows ~200 ms network latency. It measures to a server in China (ping baidu.com 208 ms,
  8.8.8.8 4 ms from the tablet); the network is not slow
