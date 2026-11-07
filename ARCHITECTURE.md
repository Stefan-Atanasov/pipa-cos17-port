# Architecture

This document tells how the port is put together. It is a reference: each section gives the source files in this
repository. For the build procedure, refer to [BUILD.md](BUILD.md).

State: public release **beta6** (2026-10-30) = `port.sh` default run (last active step 3w) + kernel `walt-r8kpm`.

## 1. Partitions

| Part | Contents | Source |
|---|---|---|
| Firmware | Bootloader, modem, DSP, `vendor_boot`, `dtbo`, `vbmeta*` | beta4 release, not changed |
| Kernel (`boot`) | Own kernel `walt-r8kpm` (beta6). beta5 had `walt-r6`. | [KERNEL.md](KERNEL.md) |
| `vendor`, `odm` | pipa device side | beta4 `super` (slot B), pinned by md5, with the step edits in section 2.3 |
| `system` (with the donor `my_*` partitions as folders), `system_ext`, `product` | ColorOS 17 | Donor OPD2515 `17.0.0.103(CN01)` (C.06), with the step edits in section 2 |

- `super.img` has 5 partitions in each slot: `system`, `system_ext`, `product`, `vendor`, `odm` (`port.sh`,
  `lpmake --virtual-ab`, group `qti_dynamic_partitions_<slot>` = 9126805504 bytes).
- `port.sh` extracts each donor `my_*.img` into its mount point folder `system/my_*`. The folders are
  `my_product`, `my_manifest`, `my_stock`, `my_region`, `my_heytap`, `my_bigball`, `my_carrier` and `my_engineering`.
- All content is in slot B. The `_a` partitions of `super` are empty (size 0).
- The beta4 `vbmeta.img` has the flags 3 (verity off, verification off). Thus the images need no signature.
- `port.sh` checks the md5 of `vendor_b.img` (`b601a907…`) and `odm_b.img` (`8e25ab23…`) before it extracts them
  (`VENDOR_MD5`, `ODM_MD5` in `port.sh`).

## 2. ROM build

### 2.1 Pipeline

`maintainer/port/port.sh` makes `super.img` in one tree:

1. Preflight: tools, inputs, md5 of the pinned images, free space (`--check` does only this).
2. Extract the donor `system`, `system_ext`, `product`, the `my_*` images, and the pinned beta4 `vendor` and `odm`.
3. Run the steps `maintainer/port/steps/NN-<step>-<name>.sh` in the order of `NN`. Each step is a separate `sh`
   process with `set -eu`. A step that fails stops the run and keeps the tree.
4. Check the SELinux labels of all files (`maintainer/tree_manifest.py`).
5. Make one image for each partition (`mkfs.erofs -zlz4hc -C65536 -T0`) and `super.img` (`lpmake`).

The helper functions for the steps are in `maintainer/port/lib.sh` (`replace_once`, `need_grep`, `forbid_grep`,
`set_layer`). A step writes a file with `cat new > old`. This keeps the owner, the mode and the SELinux label.

Donor patches find their target by a pattern, not by an offset. A pattern that is not found stops the step. Refer
to [REBASE.md](REBASE.md).

### 2.2 Which steps run

- Without options, `port.sh` runs all step files.
- Three steps are optional. They do nothing unless you set their variable:

| Step | Variable | Function |
|---|---|---|
| 2u | `PORT_WITH_2U=1` | SukiSU manager as a preload. Not used: KernelSU finds its manager only in `/data/app`. 2w replaces it. |
| 3k | `PORT_ODM_C06=1` | The OPPO interconnect stack in `odm` from C.06. Built, not tested. Refer to `maintainer/port/NOTES-3k-odm-c06.md`. |
| 3x | `PORT_NOENCRYPT=1` | `/data` without encryption, for Linux dual boot (`beta6-noenc`). Experimental. |

- Thus the last step that changes the default build is 4x (beta6 ended at 3w). Since pt28 (2026-11-03) the donor is C.07 (17.0.0.104).
- `--until <step>` stops after that step. Example: `--until 3h` gives the 3h content.
- The property `ro.pipa.port.layer` (in `system_ext/etc/build.prop`) gives the last step that called `set_layer`.
  Steps 3u, 3v and 3w do not call it. Thus beta6 shows `3t`. When this value changes, `early.sh` clears the package
  cache.

### 2.3 Steps

Before `port.sh`, each layer was a script `maintainer/build_beta5_<step>.sh`. It read the images of the previous
layer and wrote `port-work/<tag>-<step>/`. `maintainer/build_port.sh` ran them in sequence. These scripts stay in the
repository as history and as a test path for one fix. New fixes are step files only (from 3k on). The column
"Script" gives the old layer script.

| Step | Script | Contents |
|---|---|---|
| base | `build_beta5.sh` | Donor `system`, `system_ext`, `product` and the port edits in `maintainer/c06-vs-beta4/PORT-EDITS.tsv` (face unlock, OppoCamera, MiSound, media profiles, power profile, the beta4 boot-hang libraries, CIL rules). |
| baked | `build_beta5_baked.sh` | Files of the older module: panel colour (QDCM), audio curves, brightness table, patched `oplus-services.jar`. |
| 1c | `build_beta5_1c.sh` | GNSS service off, pen sysfs permissions (`vendor` ueventd). |
| 2a | `build_beta5_2a.sh` | Old FaceUnlock app and AOD removed. |
| 2b | `build_beta5_2b.sh` | Keyboard drain patch (`vendor` `xiaomi-keyboard`), pen sysfs init file. |
| 2c | `build_beta5_2c.sh` | Interconnect SELinux rule, native pen 120 Hz lock. |
| 2d | `build_beta5_2d.sh` | pipa helper app (first form). |
| 2e | `build_beta5_2e.sh` | `pipa_port` service and SELinux domain in the ROM, boot rotation and logo, helper app. |
| 2f | `build_beta5_2f.sh` | Pen button and pen message fixes. |
| 2g | `build_beta5_2g.sh` | AudioX retry loop off (sysconfig). |
| 2h | `build_beta5_2h.sh` | Null guards in the OPPO gpuservice extension (necessary with the own kernel). |
| 2i | `build_beta5_2i.sh` | SELinux labels and rules for the UI First kernel nodes (`maintainer/uifirst-policy/`). |
| 2j | `build_beta5_2j.sh` | Keyboard guard (idle drain), `loc_sys_service` off, Perfetto works (no vsock relay). |
| 2k | `build_beta5_2k.sh` | Charger shim reports the battery as genuine. |
| 2l | `build_beta5_2l.sh` | SurfaceFlinger off the little CPU cores, SurfaceFlinger timing in `product/etc/build.prop`. |
| 2m | `build_beta5_2m.sh` | SurfaceFlinger layer caching off (screen glitches). |
| 2n | `build_beta5_2n.sh` | system_server animation threads as UX, UI apps fully compiled. |
| 2o | `build_beta5_2o.sh` | All app-wide `refresh_rate_config` rules at 120 Hz in Auto and 120 Hz modes. Video players keep their lower rate. |
| 2p | `build_beta5_2p.sh` | Pen battery in the ColorOS live alert: OPPO IPeManager patched in place (`maintainer/ipe-fluid/patch_ipemanager.py`), `pipa_port` `PEN_FLUID`, helper without its own pill. |
| 2q | `build_beta5_2q.sh` | `pipa_port` loop with shell builtins (idle CPU 14.7 → 2.3 % of a core), smoothness defaults once for each install, package-cache reset for each layer, OIFace cpusets, nandswap duplicate guard. |
| 2r | `build_beta5_2r.sh` | `pipa_port` `KSWAPD_NO_PRIME` (kswapd on CPUs 0-6), pen "connected" once at boot. |
| 2s | `build_beta5_2s.sh` | `pipa_port` `ANIM_TIER` (launcher animation tier, default 3) and the helper Quick Settings tile "Animations". |
| 2t | `build_beta5_2t.sh` | `sget` reads settings with `settings get` into a file; a failed read keeps the animation tier. |
| 2u | `build_beta5_2u.sh` | Optional (section 2.2). SukiSU manager 4.2.1-r1 as a removable preload. Not released. |
| 2v | `build_beta5_2v.sh` | First-boot defaults (animation blur off, on-screen keyboard on), face preview rotation from `cmd display get-displays`. Public beta5. |
| 2w | `build_beta5_2w.sh` | `oplus-services.jar` without the knuckle sensor (idle drain). The SukiSU manager installs once on the first boot (`KSU_MANAGER`). |
| 2x | `build_beta5_2x.sh` | `surfaceflinger` does not wait for OPPO display HALs (Game Filter froze the screen). |
| 2z | `build_beta5_2z.sh` | Panel goes to 60 Hz when idle (`oplus_vrr_config.json`). |
| 3a | `build_beta5_3a.sh` | `CryptoEngShim` (software `ICryptoeng`): privacy password and app lock work. |
| 3b | `build_beta5_3b.sh` | SystemUI keeps the idle 60 Hz after a screen-off (OTI pause with auto-resume). |
| 3c | `build_beta5_3c.sh` | Interconnect to the phone: SELinux rules, two virtual SIM slots. |
| 3d | `build_beta5_3d.sh` | AIDL virtual modem in `odm` (calls on the pad). |
| 3e | `build_beta5_3e.sh` | Echo reference in the non-VoIP mixer paths (`vendor`). No measured effect. |
| 3f | `build_beta5_3f.sh` | Game Filter and colour enhancement as a colour matrix (`maintainer/gamefilter/`), face eye guard (`LD_PRELOAD` of `libpipa_eyeguard.so`), Eye Protect Bedtime patch, `pipa_port` enforcing (`maintainer/sepolicy/pipa_port_enforce.py`). |
| 3g | `build_beta5_3g.sh` | `pipa_port` property-set and one-time-path rules. |
| 3h | `build_beta5_3h.sh` | `ro.surface_flinger.has_HDR_display=true` (HDR profiles and HDR output). |
| 3i | `build_beta5_3i.sh` | Wide colour. Use only with 3j: 3i alone gives composer glitches. |
| 3j | `build_beta5_3j.sh` | Composer HAL (`vendor`) skips `SET_LAYER_GENERIC_METADATA` (YouTube HDR plays). |
| 3k | step only | Optional (section 2.2). The `odm` interconnect stack from C.06 instead of C.05. |
| 3l | step only | `ro.mediaserver.64b.enable=true`: 64-bit mediaserver (video thumbnails work). |
| 3m | step only | `media.settings.xml` points to `media_profiles_kona.xml` (the first zygote64 no longer stops at boot). |
| 3n | step only | The `pipa_port` loop sleeps 1 s with the screen off: the pen is ready about 1 s after screen-on. |
| 3o | step only | `framework.jar` (`maintainer/propspoof/`): per-app device identity. Netflix sees a Pixel 6 (Widevine L1), Google Photos sees a Pixel XL. Games (since pt36) see a gaming device, so that they show their high frame rates: RedMagic Nova (NP03J) for Racing Master and PUBG (tested), the other games get the device of the crDroid `PixelPropsUtils` list (Apache-2.0). Only listed packages change; other apps see the real device. To add a game, add its package to `GAMES` in `PipaAppIdentity.java`. |
| 3p | step only | `product/etc/sysconfig/pipa-photos.xml`: the feature `com.google.android.apps.photos.NEXUS_PRELOAD`. Google Photos finds an original Pixel by this feature. |
| 3q | step only | QDCM `standard_hdr` = the Natural features with a P3 matrix (the stock HDR LUT made whites green). EDR (`oplus.software.display.enhance_brightness_with_uidimming`) off: apps got 4.9x HDR headroom without a backlight boost. |
| 3r | step only | QDCM `hal_native` (ColorOS "Standard") = the Natural matrix with a warmer white (R 1.0, G 0.99, B 0.962). |
| 3s | step only | `oplus-services.jar` (`maintainer/ambientlux/`): adaptive tone reads the continuous Xiaomi colour stream (`front_cct_strm`, lux and CCT), a stronger curve, Bedtime never cooler than adaptive, dark room locks 3600 K. |
| 3t | step only | `oplus-services.jar` (`maintainer/batterylog/`): no OplusBatteryService error line at each battery update. Log only. |
| 3u | step only | Pen dock: the service reads both dock hall sensors (`hall3`, `hall4`). Dock in at once, dock out after a second read 0.5 s later. |
| 3v | step only | The `pipa_port` main loop starts about 1 s after `sys.boot_completed` (was about 24 s). The colour restore runs in the background. |
| 3w | step only | 27 `pipa_port` SELinux rules for the face camera worker (enroll preview, face unlock). Pen back button = standard stylus second button (`keys.conf`). beta6. |
| 3x | step only | Optional (section 2.2). `vendor/etc/fstab.qcom`: `/data` without file and metadata encryption. Clean flash only. |
| 3y | step only | SELinux noise: rules and `dontaudit` for the denial loops of the bug doc (tcm socket, vendor props, OPPO scheduler nodes; Android 17 `priv_app_36`/`platform_app_36` domains). |
| 3z | step only | Charge limit and smart charging: the charger shim records the ColorOS settings, `pipa_port` stops and starts charging at the limit (`battery_charging_enabled`). |
| 4a | step only | `vendor/etc/media_codecs_c2.xml`: hardware HEVC decoder up to 4096x4096 (the O-Live wallpapers are 2500x2500). |
| 4b | step only | pipa helper 0.7: Dolby check on each audio device change and every 60 s with the screen on. |
| 4c | step only | Melody (OPPO earbuds app) from the donor `my_stock/del-app`. |
| 4d | step only | CN Google services on by default (first boot of a clean flash). |
| 4e | step only | Circle to Search: launcher and SystemUI patches (in place, signature kept), two feature files. |
| 4f | step only | Overlay `PipaContextualSearchOverlay`: the `contextual_search` service uses the Google app. |
| 4g | step only | pipa helper 0.8 = default assistant (once, when the Google app is installed); it starts Circle to Search. |
| 4h | step only | Touch log spam: `persist.sys.assert.panic=false`; no urcc HAL lookup (oplus-framework); Osense, WindowStateExtImpl and PMS log calls removed. oplus-framework is a boot jar: odrefresh compiles on the first boot. |
| 4i | step only | Screen attention (keep the screen on while you look): C.06 `odm/lib64/libaiboost.so`, `libaiboost.so` in `vendor/etc/public.libraries.txt`, AppFeature `com.aiunit.aon.is_cpu_support_only` (the NPU path crashes on SM8250). |
| 4j | step only | `persist.sys.display.enable_on_connect.external_force=true`: a USB-C monitor is enabled without the consent dialog that ColorOS does not show. |
| 4k | step only | OShare (`maintainer/oshare/patch_oshare.py`, in place, signature kept): `b0.y()` accepts the BLE peer when the TEE has no OPPO key, so tablet → OPPO phone works without the interconnect. |
| 4l | step only | No `cn.google.services` (GMS turns on Quick Share); pipa_port: Quick Share components on once (`QUICK_SHARE`), App Market updates of OShare removed at boot (`OSHARE_ROLLBACK`). |
| 4m | step only | Charge hold reads the type 5 stop field. Charger shim reads sysfs telemetry and health, writes records with `.tmp` + rename, reports failed writes, and removes a record older than the boot. |
| 4n | step only | `uifirst-policy/qos_block.cil`: QoS proc label, system_server access and ioctl allowlist. `ro.oplus.osense.uaf_qos_enable=true`. |
| 4o | step only | Own IOplusTouch V2 service maps game mode, tap, swipe, smoothness, edge, corner, IME grip and direction to Xiaomi touch modes. Rotation tested. Games-app slider test open. |
| 4p | step only | Bypass charging: the charger shim answers `setChgConfig(25)` with 1 and `getChgConfig(24)` from the record; `chg_hold` stops the battery charge (`battery_charging_enabled`=0, the charger powers the tablet) while a fresh `1+switch=1` exists, with a 15 % floor. The plug check reads `usb/present` (`usb/online` is 0 on a PC port). Hold tested; Battery-app switch test open. |
| 4q | step only | System VINTF manifest without `oplusSensor`, `urcc` and `hummingbird`: pipa has no server for them, and a declared name makes native `waitForService` clients wait for ever. Boot tested (pt30). |
| 4r | step only | Own-code HAL shims in one host (`maintainer/halshims`): `gameopt` (game key threads get sched_assist UX, always reset), `displaypanelfeature` and `misc` (donor answers, read-only), and the 4o touch shim. `gameopt` keeps the pipa vendor label `oplus_absent_service`: a second label for a name stops servicemanager at boot. Boot, registration and touch rotation tested (pt30); game test open. |
| 4t | step only | Game Eye Care (Games app): `oplus-services.jar` adds a warm, slightly darker DisplayTransformManager level (152) while the switch is on and a game is in full screen. OPPO does it in the panel (id 228), which pipa does not have. Tested live. |
| 4u | step only | Settings > About device shows the ColorOS banner card (`maintainer/aboutcard/patch_settings_otacard.py`, in place, signature kept): the card no longer needs `com.oplus.ota`, a tap on it starts nothing ("Version up to date"). `ro.build.version.oplusrom.display=17.0`. |
| 4v | step only | Circle to Search after a 600 ms hold on the gesture bar (was 800 ms): `maintainer/cts/patch_navhandle_longpress.py` changes the long-press constant of the NavigationGestureDetector copies in OplusLauncher and SystemUI. |
| 4w | step only | Bypass charging: after a charge below 15 %, the charge-current cap comes back only at 20 % (no cap/charge switching at 14/15 % under a game load). |
| 4x | step only | `persist.sys.oplus.disableCompressDedup=1`, `persist.sys.oplus.disableTurboPocket=1`: OPPO idle maintenance keeps the file defrag but skips the dedup scan and Turbo Pocket (they need OPPO-only f2fs ioctls and an OPPO UFS driver). |
| 5a | step only | `services.jar` (`maintainer/extdisplay/patch_ext_modes.sh`): external display modes without FLAG_SIZE_OVERRIDE, so a USB-C monitor can use its high refresh modes (e.g. 2560x1440@120). |
| 5b | step only | `persist.wm.debug.enforce_display_extended_mode=true` + pipa_port `EXT_DISPLAY` (`mirror_built_in_display=0` once): a USB-C monitor is an extended ColorOS screen with its own taskbar (the stock check wants 12 GB RAM). |
| 5c | step only | `oplus-services.jar` (`maintainer/flexwin/patch_float_limit.sh`): more than one floating window also with launcher animation tier 3/4. |
| 5d | step only | PC Screen Extend / Mirror (OPPO PC Connect): patched `odmf.jar` (`maintainer/odmf/patch_odmf_pcextend.sh`, no `color-format` 19 in surface decode mode) in `/system_ext/pipa_port/odmf/`; `pipa_port.rc` bind-mounts it over the signed odmf opex overlay folder. |
| 5e | step only | `oplus-services.jar` (`maintainer/extdisplay/patch_ext_density.sh`): a USB-C monitor keeps its native size; density = short side x 200 / 1440 (1440p: 200 dpi, like Windows 125 %). |
| 5f | step only | SELinux rules from a full capture (`maintainer/sepolicy/rules_5f_*.cil`): UI First hints for SurfaceFlinger, bootanim and apps, f2fs GC policy nodes for init and system_server, read-only props; dontaudit for probes. Find My Device first removed (needs OPPO RPMB/TEE); since pt57 it stays, because the ColorOS setup wizard `com.coloros.bootreg` needs its provider (without it: grey screen after a clean flash). |
| 5g | step only | Full blur at animation tier 3: app feature `com.oplus.blur.support_upgrade_anim_material_blur` (launcher dock and folders; ColorOS allows them only at tier 1-2 without it) and `debug.systemui.gaussblur_level=2` (Quick Settings blur; SystemUI has none at tier 3). Helper 0.9: two-state Animations tile (Fast = tier 3, ColorOS = tier 1). |
| 5h | step only | SELinux clean-up from the boot logs: the OPPO part of the perf HAL may mark system_server/cameraserver threads as UX (`ux_state`), frame boost for more app domains, read-only props; dontaudit for diag, probes and `noatsecure` (`maintainer/sepolicy/rules_5h_*.cil`). |
| 5i | step only | SELinux round 2 from a full capture (audit rate 2000): UI First / frame boost hints for SurfaceFlinger, bootanim, mediaserver, audioserver, cameraserver and more app domains, game service GPU reads; dontaudit for probes and third-party app probes. Bedtime: each Bedtime key is restored on its own (the old restore switched Bedtime on again). |
| 5j | step only | SELinux round 3: camera and media provider UX hints, dex2oat /data search; dontaudit for the perf HAL scene writes (pipa_port owns that node) and app emulator checks. |
| 5k | step only | Last SELinux items from an advanced capture (camera, recording, split screen, toggles). Result: 0 denials from ROM domains, apps and root. |
| 5l | step only | Xiaomi game thermal profile while a game is in the foreground: helper 1.0 (`GameKeeper`, UID importance listener, appCategory game) sets `pipa_game_fg`; pipa_port writes `mi_thermald` `sconfig` `GAME_THERMAL_SCENE` (default 20 = no CPU caps below 46 °C skin) and -1 otherwise. |
| 5m | step only | SukiSU-Ultra manager v4.3.0-r1 (41140) in `system_ext/pipa_port/SukiSU.apk` (the same level as kernel walt-r17); new layer. beta7. |
| 5n | step only | Face camera worker guard `libpipa_camguard.so` (LD_PRELOAD): no SIGABRT when the HAL retries with an ANativeWindow in a dark room; dontaudit for OPPO crash log collection. beta7. |
| 5o | step only | Last SELinux noise (dontaudit only): OPPO game service virtual device lookup, game anti-cheat /proc probes, a system app search of the Play services folder. beta7. |
| 5p | step only | OPPO game optimizer (oiface) and horae also for games that target SDK 34 (the donor policy stops at `untrusted_app_32`); Play services frame boost hint. beta7. |
| 5q | step only | OPPO game service may mark game threads as UI First (ux_task_app ioctl, the set of 5i). beta7. |
| 5r | step only | OShare versionCode 17999036 in place (`maintainer/oshare/bump_version.py`): the OPPO App Market cannot replace the patched OShare (4k). beta7. |
| 5s | optional (`PORT_MAINTAINER_ADB=1`) | Maintainer test builds only: this host's adb key in `product/etc/security/adb_keys` and USB debugging on at the first boot, for unattended clean-flash tests. `build_release.sh` refuses such an image. Never published. |
| 5t | step only | Blur entry and first-boot defaults. `maintainer/wallpapers/patch_blur_entry.py` patches Wallpapers.apk: Personalization > More > "Textured visual effects" shows at animation tier 3 (ColorOS hid it above tier 2). `service.sh` sets Visual blur (`system_material_blur_enable=1`) and Contour glow (`system_material_stroke_enable=1`) on at the first boot, and retries the SukiSU manager install every 60 s. Helper 1.1: Animations tile "Fast" = tier 3, "Slow" = tier 2. Secure keyboard off once (`SECURE_KEYBOARD_OFF`). beta7.1. |
| 5u | step only | Google apps: Play Store 84932800, Gboard 176071774, Google app 301827586 (base APK and splits from `port-inputs/apps-5u`) in `/system_ext/pipa_port/apps/<package>/`. `service.sh` installs each one time as a normal app when the installed version is older. Gboard becomes the keyboard only over Sogou or no keyboard. The Circle to Search assistant is set after the install and checked every 5 minutes until the Google app exists. SELinux: `rules_5u_system_ext.cil` (AOSP `selinux_check_access` set for `pipa_port`; `pm install <file>` failed without it, thus beta7 had no SukiSU manager after a clean flash) + dontaudit idmap2 getattr. beta7.1. |
| 5v | step only | Battery.apk (`maintainer/battery/patch_long_charge.py`, same-size dex edit, OPPO signature kept): no "Set charging limit to 80%" pop-up after each boot (the charger notify mask bits 28/29 become 0). |
| 5w | step only | Software echo canceller: `maintainer/aecshim` wrapper HAL `vendor/lib/hw/audio.primary.pipaaec.so`, chosen by `ro.hardware.audio.primary=pipaaec`; it loads the real `audio.primary.kona.so` (never renamed: the sound trigger HAL dlopens it by name) and runs WebRTC AEC3 + AGC2 on VOICE_COMMUNICATION input. Switches `persist.vendor.audio.pipa_aec`, `persist.vendor.audio.pipa_aec_gain`. |
| 5x | step only | Log causes and quiet logs: `my_product/etc/power_profile/power_profile.xml` with `cpu.*` from stock HyperOS (`maintainer/power_profile/`); `maintainer/logspam/patch_logspam.py` table 5x (UAHPerfManager native urcc calls return at once; 3 QoS scene warnings removed); `system_ext_property_contexts` for 11 empty vendor props; `rules_5x_system_ext.cil` (pipa_port sets `persist.log.tag`, audioserver reads `/proc/<system_server>`); `service.sh` `log_check` + helper 1.2 Logs tile (`persist.log.tag=I` unless global `pipa_verbose_logs=1`). |
| 5z | step only | Dolby 1:1 with HyperOS: the stock HyperOS 2 `vendor/lib{,64}/soundfx/libhwdap.so` replaces beta4's patched copy (it hid DMS errors). Inputs: `port-inputs/dolby-5z` (private). |
| 6a | step only | Measured speaker EQ (pink noise, USB mic) added to the audio optimizer of the 4 speaker tunings in `vendor/etc/dolby/dax-default.xml`; the user EQ in MiSound stays free on top. Values, graph and a standalone script for other ports: `maintainer/dolby-eq/`. `rules_6a_system_ext.cil`: priv_app reads the stock Dolby tuning-control props. |
| 6b | step only | Settings > Sound > Sound effect settings: overlay `maintainer/overlays/misound` (English) shows only the MiSound / Dolby entry. The ColorOS AudioX ("OReality") modes need OPPO effect libraries that the Xiaomi vendor does not have. |

### 2.4 Where properties go

- SurfaceFlinger and media properties must be in `product/etc/build.prop`. The pipa `vendor/build.prop` loads after
  `system` and `system_ext` and sets other values.
- Examples: 2l (SurfaceFlinger phase offsets), 3h `has_HDR_display`, 3i `has_wide_color_display`, 3l
  `ro.mediaserver.64b.enable`, 3m `media.settings.xml`.
- `ro.pipa.port.layer` is in `system_ext/etc/build.prop`.

### 2.5 Donor boot hangs

The C.06 donor waits for services that pipa does not have. Without the fixes below, the boot stops:

- `libupdateprof.qti.so` and `libtrigger-handler.so` come from beta4 (`PORT-EDITS.tsv`).
- The base step patches the IEngineer wait in `oplus-services.jar`.
- Step 2x changes the SurfaceFlinger waits for OPPO display HALs to `checkService` (`module/tools/patch_sf_waits.py`).

## 3. The `pipa_port` service

The ROM includes the port runtime. No KernelSU module is necessary.

| Path in the ROM | Source in this repository |
|---|---|
| `/system_ext/pipa_port/` | `port-rom/pipa_port/` (`service.sh`, `early.sh`, `pen_keys.sh`, `keys.conf`, `config.prop`) and proprietary files (`facehal/`, `chargershim.jar`, `xiaomi_touch_ioctl`, refer to [BLOBS.md](BLOBS.md)) |
| `/system_ext/pipa_port/cryptoeng.jar` | `maintainer/cryptoeng/` (step 3a) |
| `/system_ext/pipa_port/SukiSU.apk` | SukiSU-Ultra manager v4.3.0 (step 2w) |
| `/system_ext/etc/init/pipa_port.rc` | `port-rom/pipa_port.rc` |

### 3.1 Start sequence (`pipa_port.rc`)

1. `post-fs-data`: init makes `/data/misc/pipa_port`, runs `early.sh` and starts `pipa_subsys0` and `pipa_subsys1`
   (virtual modem HALs for the interconnect). It sets `persist.radio.multisim.config=dsds` and
   `persist.vendor.radio.virtualcomm=1`.
2. `early.sh` clears the package cache when `ro.pipa.port.layer` changes, makes the OIFace cpusets and removes
   extra nandswap files.
3. `sys.boot_completed=1`: init starts `pipa_port` (`service.sh`). The main loop runs once each second (screen on).

All three services run as root in the SELinux domain `pipa_port`.

### 3.2 Files on the tablet

| Path | Contents |
|---|---|
| `/data/misc/pipa_port/` | State (colour mode, adaptive and Bedtime state, one-time markers, the face HAL copy). |
| `/data/misc/pipa_port/config.prop` | User settings (root). Reboot after a change. A root shell reads this file: put only trusted content in it. |
| `/data/local/tmp/pipa_port.log` | Service log. Also `pipa_pen.log`, `chargershim.log`, `cryptoeng.log`, `facehal.log`. |

The face HAL runs from a copy in `/data/misc/pipa_port/facehal`, because of the linker namespaces.

### 3.3 Switches in `config.prop`

Each switch is 1 (on) or 0 (off). The defaults are in `port-rom/pipa_port/config.prop`.

| Switch | Default | Function |
|---|---|---|
| `FACE_HAL` | 1 | Start the face unlock HAL as root and start it again if it stops. |
| `CHARGER_SHIM` | 1 | Give ColorOS an OPPO charger HAL that reads the Qualcomm power supply nodes. |
| `CRYPTOENG` | 1 | Start the `ICryptoeng` shim (privacy password, app lock). |
| `PEN_WAKE` | 1 | Enable the pen in the touch driver after each screen-on. |
| `PEN_KEYS` | 1 | Map the pen buttons to actions (`keys.conf`). |
| `PEN_WATCH` | 1 | Tell ColorOS that a pen is connected. Lock 120 Hz while the pen is out of the dock. Read the dock sensors. |
| `PEN_FLUID` | 1 | Show the pen battery in the ColorOS live alert (patched IPeManager). |
| `COLOR_MODE_RESTORE` | 1 | Set the colour mode again after ColorOS resets it at boot. |
| `ADAPTIVE_RESTORE` | 1 | Set adaptive colour and Bedtime mode again after boot. |
| `BLUR_DEFAULT` | 1 | Set animation blur off if the user did not set it. |
| `STYLUS_BUTTONS_DEFAULT` | 1 | Merge the pen buttons into drawing apps if the user did not set it. |
| `SMOOTH_DEFAULT` | 1 | One time for each install: window blur, material blur and animation blur off; on-screen keyboard with a hardware keyboard on. |
| `HELPER_GRANTS` | 1 | Give the helper app its notification and overlay permissions. |
| `KSU_MANAGER` | 1 | Install the SukiSU manager one time as a normal app (KernelSU finds it only in `/data/app`). |
| `KB_EVENT_LINK` | 1 | Link `/dev/input/event12` to the keyboard case while it is attached. |
| `KEYBOARD_GUARD` | 1 | Run `xiaomi-keyboard` only while the keyboard case is connected. |
| `SF_BIG_CORES` | 1 | Set the UI First scene that keeps SurfaceFlinger and RenderEngine off the little cores. |
| `SYSTEM_UX` | 1 | Mark the system_server threads `android.anim`, `android.display` and `android.ui` as UX. |
| `KSWAPD_NO_PRIME` | 1 | Keep kswapd (memory reclaim) off the prime core. |
| `ANIM_TIER` | 1 | Set the launcher animation tier (`persist.sys.oplus.anim_level`) from global `pipa_anim_level`, else from `ANIM_LEVEL`. A change restarts the launcher. |
| `ANIM_LEVEL` | 3 | The default animation tier (a value, not a switch). |
| `SPEED_COMPILE` | 1 | Compile SystemUI, Settings, the Wi-Fi page and the launcher fully, one time for each ROM build (180 s after boot). `SPEED_APPS` changes the list. |
| `LID_SYNC` | 0 | Magnetic case sync. The helper app does this. |

### 3.4 Rules for scripts in the service

- Give `input`, `am`, `settings` and `pm` the input `/dev/null`. Do not use pipes with these tools: in the
  `pipa_port` domain, system_server cannot use the pipe and the call fails.
- To read a setting, use `sget` (`service.sh`). It writes the value to a file.
- Test each new command in the domain: `su -c 'runcon u:r:pipa_port:s0 <command>'`. Write the output to a file.
- Code that the service starts runs in the `pipa_port` domain. It needs rules in `pipa_port_rules.cil` (section 5).

## 4. The pipa helper app

`com.port.pipa.helper` (version 1.6) is a persistent privileged system app. The source is in `helper/`.

| Part | Function |
|---|---|
| `DolbyKeeper` | Keeps the Dolby and MiSound effects on the output mix (event driven, no polling). Selects the stock Dolby tuning per output and volume. Remembers the effect the user picks in MiSound per output (speaker, Bluetooth, wired, USB) and applies it when the output changes; automatic changes by MiSound are undone. |
| `PenKeeper`, `PenPill` | Low pen battery notification (15 %). The pen pill shows only when `pipa_pen_fluid` is 0. |
| `LidKeeper` | Sets the "lock with cover" switch (`lid_behavior`). |
| `AnimTile` | Quick Settings tile "Animations": writes global `pipa_anim_level` (3 → 2 → 1 → 4). `pipa_port` applies it. |
| `BootReceiver` | Starts the keepers after boot. |

- Path: `/system/priv-app/PipaHelper`, with `privapp-permissions-pipa-helper.xml` (`WRITE_SECURE_SETTINGS`).
- Build: `helper/build.sh` (aapt2, javac, d8, zipalign, apksigner; no Gradle). Output: `helper/out/PipaHelper.apk`.
  Step 2e needs this file.
- Signing: the helper has its own key (`helper/keys/`, not in this repository), not the platform key. An update must
  have the same key. You cannot update a persistent system app with `adb install`.

## 5. SELinux

- The ROM is enforcing.
- The domain `pipa_port` is declared in `system_ext_sepolicy.cil` (and `_debug.cil`) by step 2e. It is enforcing
  since step 3f. Steps 3g and 3w add rules.
- Rule sources:

| Rules | Source | Step |
|---|---|---|
| `pipa_port` domain | `maintainer/sepolicy/pipa_port_rules.cil` | 3f, 3g, 3w |
| UI First kernel nodes | `maintainer/uifirst-policy/sa_block.cil` | 2i |
| beta4 "pipa port" block (service finds, a TEE rule) | `PORT-EDITS.tsv` | base |
| Interconnect (`ISubsysRadio`, `system_app` and `hal_radio_default`) | step files | 2c, 3c, 3d |

- SELinux denials are in logcat (tag `auditd`) and `dmesg`: the kernel has `CONFIG_AUDIT=y`. The default audit rate
  drops most denials. For a capture, set `persist.logd.audit.rate` to 2000 and reboot.
- init checks property sets in user space. For a permissive domain, it logs nothing. Thus test property-set rules
  with a boot in enforcing mode.
- Before you build a policy change, compile it on the tablet with `/system/bin/secilc` and the eight policy inputs.
  A non-zero exit means an error.

WARNING: Do not use a live `ksud sepolicy patch` on kernel `walt-r8kpm`. It stopped the kernel (watchdog reset). Test
rules with `secilc` and a ROM build.

## 6. Kernel parts that the ROM uses

| Kernel feature | Used by |
|---|---|
| OPPO UI First (`/proc/oplus_scheduler/sched_assist/`, `/proc/sys/kernel/sched_assist_scene`) | ColorOS, `pipa_port` (`SF_BIG_CORES`, `SYSTEM_UX`) |
| `kernel.ux_prefer_big`, `kernel.frame_rate` | Placement of UI threads |
| OPPO frame boost (`/proc/oplus_frame_boost/`, `/proc/sys/fbg/`) | ColorOS (labels from step 2i) |
| OPPO Hans channel (netlink 29) | ColorOS app freezer (`hans`) |
| SukiSU-Ultra v4.3.0, susfs 2.3.0, KPM | Root, root hiding |
| nanosic keyboard driver (`/sys/devices/virtual/nanodev/nanodev0/`) | `KEYBOARD_GUARD` |
| `ovnet` network device | Network sharing with a phone (interconnect) |

The kernel has no vsock. Thus `traced` is off (step 2e). Refer to [KERNEL.md](KERNEL.md).
