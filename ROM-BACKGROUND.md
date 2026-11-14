# Background: why the ROM code does what it does (moved verbatim from CLAUDE.md, 2026-11-14)

These facts come from the module period. The ROM code still uses them. Full detail: `module/README.md`,
`notes/HANDOFF.md`, `notes/HANDOFF-adaptive-bedtime.md`, `notes/PATCH-INVENTORY.md`.

- **`xiaomi-keyboard`** (from disassembly; stock HyperOS does not have it):
  - All I/O goes through `/dev/nanodev0`. The daemon only checks `/dev/input/event12` with `access()` as a "keyboard
    present" flag.
  - Each loop: if `event12` is absent **and** the keyboard state is 1, it sleeps 3 s. Else it enables the
    accelerometer, waits 150 ms, reads and disables it. With no keyboard, the state stays 0, which gives a loop of
    about 6.7 Hz.
  - The tilt angle sets on or off (40° to 230° gives 1; 45° to 185° since step 6l). It writes changes to
    `nanodev0` as `32 ff <state>`. Up to walt-r19 the kernel dropped that write, so folding did nothing (BUGS 95).
    walt-r20 acts on it (debounced 1 s, never with the screen off; `fold_remove=1` removes the input devices).
    Since step 6k the daemon checks `/proc/nanokbd` (exists while the keypad is attached) instead of `event12`.
  - Never remove the daemon. Start and stop it with `setprop ctl.start|stop`. Pen devices and
    `xiaomi keyboard WakeUp` are not a keyboard.
- **`AodBacklightDaemon`:** freeze it with SIGSTOP/SIGCONT. Do not kill it: `pipa_core`'s loop started it again 5 s
  after it stopped.
- **Face HAL log:** facehal-rs writes its own log to `/data/vendor_de/0/facedata/facehal.log` (root); logcat has
  almost nothing from it. Three LD_PRELOAD guards (`port-module/src/`): `facecrop` (square preview), `eyeguard` (eye ROI),
  `camguard` (5n: no ANativeWindow to the vendor camera NDK in the dark-room retry).
- **Face HAL watchdog:** start the HAL only when no other copy runs. Use the same binary path, `LD_LIBRARY_PATH` and
  OpenCL loader as the HAL service.
- **Colour:** the QDCM modes have PCC and gamut disabled. The fix enables PCC in `standard` (Natural) and `hal_srgb`
  with HyperOS `miLut_2` (`module/tools/patch_qdcm.py`). Since 3q/3r: `standard_hdr` (HDR) = Natural with a P3 PCC
  (stock HDR LUT was green), `hal_native` (ColorOS "Standard") = Natural x warm gains (user values). Per-unit factory
  colour data is in `/mnt/vendor/persist/display/` (HyperOS uses it through displayfeature; the port does not).
  **Live test of a calibration:** bind the XML over `/vendor/etc/qdcm_calib_data_*42*.xml` in init's namespace,
  `setprop ctl.restart display-color-hal-1-0` and `vendor.qti.hardware.display.composer` (the UI restarts). `umount`
  the old bind first: stacked binds keep the old inode. Preview a matrix without a build: `su -c 'service call
  SurfaceFlinger 1015 i32 1 <16 floats>'` (`i32 0` resets; shell gets "Operation not permitted"); the PCC acts
  stronger than such a preview.
- **Brightness:** `module/tools/gen_brightness_table.py` makes the ColorOS `<level>P,B,N,K</level>` table. Levels at or
  below AOD_BRIGHTNESS go raw (level 1 = black). Keep the minimum at 20 or more. To measure, use
  `settings put system screen_brightness <level>` (manual mode), not swipes on the QS slider (they close Quick
  Settings). Set auto mode again after.
- **Adaptive colour and Bedtime (since 3s):** ColorOS now reads the continuous Xiaomi stream `front_cct_strm`
  (33171089, `[lux, CCT, R, G, B, C, ...]`) mapped to OPPO's layout, with real lux, a stronger curve and bedtime
  curves that are never cooler than adaptive (`maintainer/ambientlux/`). The on-change `front_cct` (33171088) never
  filled the ColorOS filter. Check: `dumpsys color_display` (`sensorDataValid`, `targetCCT`). Older notes below:
  the framework asks for OPPO CCT sensor type 33171001; pipa has Xiaomi type
  **33171088**. The ROM's `oplus-services.jar` has four dex edits (three for the reroute, one for the IEngineer boot
  hang) from `module/tools/patch_framework.sh` (it finds the sites by pattern; tested on beta4 and C.06; for a new
  donor, run it on that donor's jar). A diff against C.06 found no code edit by the port author
  (`maintainer/jar-edits/REPORT.md`). The Eye Protect app resets the settings at boot; `pipa_port` saves and restores
  them. (Up to pt14 a constant 100 lx replaced the missing lux; since 3s the stream gives real lux.)
- **USB audio and speakers:** the ROM has USB_HEADSET and A2DP volume curves (`module/tools/patch_audio_volumes.py`),
  so USB DACs do not play at full scale, and a patched 32-bit audio HAL (`module/tools/patch_audio_hal.py`) that
  corrects the swapped speaker L/R.
- **The old module** (`module/`, `pipa_cos17_power_tune` v0.15): edit `module/`, increase `version`/`versionCode` in
  `module.prop`, and zip the contents at the archive root with Python `zipfile` (the host has no `zip`). Install with
  `ksud module install`. This KernelSU has no module mount provider, so `post-fs-data.sh` did the bind mounts itself.
  It is only for rollbacks to beta5-2d or older.
