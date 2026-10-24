# COS17 port for `pipa`: patch inventory

Date: 2026-10-22. Port: ColorOS 17 beta4 (2026-10-17), `OPD2515_17.0.0.102(CN01)`.

**Baseline.** HyperOS1 factory for vendor/odm; the OS side is compared against donor C.06 (§9).
Originally (before C.06 was obtained) there was no Oppo Pad Mini (OPD2515) donor stock, so every diff
was taken against **HyperOS1 factory** (`hyperos1-stock`, `V816.0.15.0.UMZMIXM`). Two secondary baselines are used for
provenance: **PixelOS** (a LineageOS-family source build of the pipa vendor) and **iqraos3.1** (a
HyperOS2 CN port). Read-only analysis; nothing under `reference/` was changed.

Cross-references: `R1`…`R12` are the numbered findings in `README.md`. `M1`…`M14` are the sections of
`module/README.md`.

Raw material lives in `../reference/analysis/inventory/`:

- `<rom>.<partition>.md5`: full md5 manifests.
- `<partition>.diff.tsv`: per path, the status vs HyperOS, PixelOS and iqraos3.1, plus which baselines
  hold byte-identical content.
- `diff_manifests.py`: regenerates the tsv files.
- `vendor-findings.md`, `odm-product-findings.md`, `system-findings.md`: the per-partition notes
  behind this file.

---

## 1. Files compared

| Partition | cos17 files | HyperOS1 files | same | modified | added | removed | identical to PixelOS |
|---|---|---|---|---|---|---|---|
| vendor | 1870 | 2881 | 974 | 441 | 455 | 1466 | 1390 |
| odm | 95 | 21 | 4 | 6 | 85 | 11 | 10 |
| system | 8576 | 3023 | 544 | 1777 | 6255 | 702 | 899 |
| system_ext | 3632 | 2193 | 135 | 888 | 2609 | 1170 | 26 |
| product | 237 | 1238 | 15 | 60 | 162 | 1163 | 31 |
| **total** | **14410** | **9356** | 1672 | 3172 | 9566 | 4512 | |

## 2. Summary by category

File counts are approximate. One finding often covers a group of files.

| Category | Files (≈) | Findings | Notable examples |
|---|---|---|---|
| **CONFIRMED PATCH** | ~150 | ~45 | `vendor/build.prop` port block, `portenforce.rc`, face-HAL props, `odm/etc/init.oplus.mm-sys.sh`, `odm/etc/init/subsys_daemon.rc`, system_ext sepolicy `tee` fix, `oplus-services.jar` (already repacked by the port), `display_brightness_config_default.xml`, 4 `com.port.pipa.overlay.*` RROs, 96 re-imported Xiaomi vendor blobs (Dolby/misys/perf) |
| **DONOR ARTIFACT** | ~420 | ~20 | Lineage-family A17 vendor rebuild (~250 libs), Adreno 2025 + Turnip stack, OemPorts10T face HAL, OPPO perf/stability HALs, Oppo "virtual modem" ODM stack, OPD2515 OTA identity, `*.lvy` overlays, `xiaomi-keyboard` (PixelOS tree) |
| **UNEXPLAINED** | ~50 | 16 | 32 encrypted `thermal-*.conf` edited, `zz_portdebug.rc` panic knobs, boot-time SELinux deadlock, `precompiled_sepolicy`, `subsys_radio` V9/V8 mismatch, `has_wide_color_display=false`, donor under-screen light sensor props |
| **NOISE** | ~13 800 | – | OS-version churn: `my_product` themes/wallpapers (3008), framework oat (~1550 in system_ext, 993 in system), lib/lib64 rebuilds, fonts, locales; 1463 Xiaomi CIT/factory/diag blobs pruned from vendor; 1163 MIUI/GMS product apps removed |

---

## 3. Provenance (where vendor came from)

- **Vendor is a LineageOS-family source build of the pipa tree, rebuilt for Android 17.** It has
  `vendor.lineage.health`, `light-service.lineage` and `power-service.lineage-libperfmgr`. 1390 of its
  1870 files are byte-identical to PixelOS, including `mixer_paths`, the qdcm XMLs, sensors,
  `xiaomi-keyboard` and the aw882xx firmware. The build itself is newer and separate: a `user` build
  dated 2026-08-22, SDK 37, IPower v7 where PixelOS has v6, and ~250 libs that differ in md5 from
  PixelOS.
- **The EvolutionX claim is consistent with this but not proven.** No `evolution`/`evox` string
  exists anywhere in vendor. EvolutionX, PixelOS and AOSPA all build from the same Lineage device
  trees, so the evidence points to that family rather than to one ROM. The port author's own
  `vendor/build.prop` comments say the graphics and display props were "aligned to AOSPA"
  (2026-10-07).
- **GPU stack from a newer tree.** Adreno `LA.VENDOR.12.3.11` (2025-08), `vulkan.turnip.so`,
  `libOpenCL_adreno`, `gralloc.qcom.so`, and new `a650_sqe.fw`/`a650_zap.elf`. None of these is in any
  baseline.
- **Then hand-edited by 梦归zzz.** There are dated comments in `vendor/build.prop`, the init rc files
  and `vendor_sepolicy.cil` ("pipa port 2026-10-13"). 96 Xiaomi stock blobs were re-imported
  byte-identical from HyperOS.
- **ODM is a stripped HyperOS skeleton.** It carries Oppo's virtual-modem/subsys stack plus
  port-author scripts. **product** is the generic Oppo QSSI product (`ossi`), with zero pipa/xiaomi
  strings. **system/system_ext** are donor ColorOS with a small, well-commented set of port edits.

---

## 4. CONFIRMED PATCH list

Format: path: what changed; tie to bug; how to reproduce on a new base.

### 4.1 Vendor

1. **`vendor/build.prop` port block** (from line ~200; signed "酷安@梦归zzz").
   - What changed: graphics/HWUI aligned to AOSPA (`ro.hwui.use_vulkan`, renderer props handed back
     to defaults), `debug.stagefright.ccodec=4`, `debug.sf.latch_unsignaled=1`,
     `ro.surface_flinger.set_idle_timer_ms=4000`, `vendor.display.use_smooth_motion=1`,
     `lcd_density`, Dolby/MiSound props.
   - Fixes: cyan/blue swapped chroma in video, hidden HW decoders, Dolby.
   - Reproduce: copy the commented block verbatim; each entry carries its rationale.
2. **`vendor/etc/init/portenforce.rc`.**
   - What changed: `write /sys/fs/selinux/enforce 1` on `sys.boot_completed=1`.
   - Why: booting enforcing deadlocks vold → keystore2/keymaster, with no AVC logged, so the boot runs
     permissive and switches to enforcing afterwards.
   - Reproduce: keep it until the root cause is known (see U3).
3. **`vendor/etc/selinux/vendor_sepolicy.cil` "pipa port" sections** (line ~20969 on).
   - What changed: legacy `/dev/ion` labels and allows (the COS17 platform policy dropped ion), face
     HAL socket rules, `oplus_port_hal_service`, bootanim → `oplusoiface_service`.
   - Also: `vendor_service_contexts`/`vendor_hwservice_contexts` label absent OPPO HALs (`ICharger`,
     `urcc`, `gameopt`, `perf2`, `displaypanelfeature`, …) as `oplus_absent_*`.
   - Ties to R6/M8 (charger) and M11 (`IDisplayPanelFeature` missing).
   - Reproduce: append the `pipa port` blocks to the new base's cil and contexts.
4. **Face HAL adaptation** (on top of the OemPorts10T HAL, see D3).
   - What changed: props `persist.oemports10t.fh=true`, `persist.facehal2.sdk=36` (the binary was
     patched to read this persist prop instead of the SDK version) and `persist.sys.facehal.verbose=true`.
     The rc pre-creates `/data/vendor_de/0/facedata`.
   - Ties to R2 and M4. The rc is still `disabled` with **no `interface aidl …IFace/default`**, which
     confirms the cause of R2.
5. **`vendor/etc/audio_policy_configuration.xml`.**
   - What changed: BT A2DP Out/Headphones/Speaker ports and routes ("keep the modern BT HAL as
     fallback"), and 44.1 kHz on primary/deep_buffer/mmap.
   - Ties to M13 (A2DP side).
6. **`vendor/etc/audio_effects.xml` + re-imported Xiaomi Dolby/MiSound.**
   - What changed: PixelOS `libswdap_v3_6` was swapped for stock `misoundfx`, `libhwdap`,
     `libswgamedap` and `libswvqe`. Dolby DMS 2.0 HAL, `dax-default.xml` and `ro.vendor.audio.dolby.*`
     were added.
   - This pairs with system-side MiSound (S8). Ties to the README "Bug sweep" Dolby note.
7. **96 Xiaomi stock blobs re-imported**, byte-identical to HyperOS.
   - Which: misys@1-4, mlipay, mtd, mfidoca, qti perf HAL (`vendor.qti.hardware.perf@2.2`),
     `etc/perf/*`, `powerhint`, `media_profiles*`, `libwvkeybox`.
   - Reproduce: copy from HyperOS stock; the list is `content_in=hyperos1-stock` and
     `vs_pixelos=added` in `vendor.diff.tsv`.
8. **`vendor/lib64/hw/vulkan.adreno.so`.**
   - What changed: a 40-byte `cMetaOffset` patch, per the build.prop notes.
   - Fixes video/graphics corruption with the newer Adreno driver.
9. **Init tweaks.**
   - `init.device.rc`: `chown root system /sys/touchpanel/double_tap` (DT2W).
   - `init.target.rc`: the `/dev/stune` lines were dropped (no stune cgroup on A17).
10. **Input.**
    - `usr/idc/Xiaomi_Keyboard.idc`: `keyboard.orientationAware=0` dropped; `internal=0`/`builtIn=0`
      set.
    - `usr/keylayout/Xiaomi_Smart_Pen_Keyboard.kl`: keys 109/104 mapped to
      `STYLUS_BUTTON_PRIMARY/SECONDARY`.
11. **`vendor/etc/camera/camxoverridesettings.txt`.**
    - What changed: `multiCameraEnable`, logs off, OIS optimisation, MPM delayed-unmap off,
      beauty/bokeh flags.
12. **Other vendor changes.**
    - Removed: the Lineage/Aperture overlays (16) and the stock vendor overlays. ColorOS framework
      resources would clash with them.
    - Added: `etc/permissions` `freeform_window_management`, `picture_in_picture` and
      `device_id_attestation`.

### 4.2 ODM

13. **`odm/etc/init.oplus.mm-sys.sh`** (written by the port author).
    - What changed: ColorOS `init.oplus.nandswap.sh` dispatches to this script, which sets zram
      8192 MB lz4, `swappiness=100`, THP off and `min_free_kbytes=23168`. It re-applies these 5× every
      30 s because `init.qcom.post_boot.sh` overwrites them. It also creates the f2fs-pinned
      `/data/nandswap/swapfile` on a loop device (priority 2020).
    - Ties to the README "Memory / zram" section, which attributes this to "OPPO nandswap". It is
      actually this port script.
14. **`odm/etc/init/subsys_daemon.rc`** (comment dated 2026-10-10).
    - What changed: the `qti-modem-daemon-*` triggers are commented out. In `hal_radio_default` the
      daemon cannot open `/dev/diag`, so it segfaulted every ~5 s (25 tombstones/min, ~15 MB/min, UFS
      stalls, standby drain).
    - **Dependency:** `pipa_core/post-fs-data.sh` (lines 98–123) starts
      `/odm/bin/hw/subsys_daemon` as root instead (verified). Without `pipa_core`, the
      `ISubsys`/`ISubsysRadio` HALs are missing.
15. **`odm/etc/build.prop`.**
    - What changed: OPPO/OPD2515 identity with `device=pipa`, plus `ro.vendor.qti.va_odm.support=1`.
16. **`odm/etc/permissions/android.hardware.telephony.ims.xml`.**
    - What changed: declares IMS/telecom so ColorOS communication-sharing UIs start on a Wi-Fi-only
      tablet.

### 4.3 System / system_ext

17. **`system/system/framework/oplus-services.jar` is already port-modified.**
    - Evidence: 4 entries, all dated 2026-09-26 10:30; Stored dex; no `META-INF/MANIFEST.MF` (sibling
      jars have 2009 dates and a manifest). It carries port strings
      ("adjustRectBySplitRatio ignore for oplus wps in port"). (`OplusRemoteDisplay.uau` is donor-native, see §9.)
    - The "stock beta4" jar md5 `3316594f…` cited in M12 and CLAUDE.md is **this port jar**, not donor
      stock. The module's CCT reroute (M12) layers on top of it.
    - The `.prof`/`.fsv_meta` files are stale donor copies.
18. **`system/system/build.prop` board overrides** (lines 315–340).
    - What changed: brand/manufacturer OPPO, model OPD2515, device/name pipa,
      `ro.product.oplus.cpuinfo=SM8250_AC`, `lcd_density=370`, bootanim orientation 90,
      `ro.oemports10t.facehal=true`, `persist.sys.facehal.verbose=true`. Also `ro.hardware.telephony=qcom`
      (ColorOS needs CarrierConfigManager).
    - Heap: `dalvik.vm.heapsize=512m` and `heapgrowthlimit=384m`, in both `system/build.prop` and
      `system/system/build.prop`.
    - Ties to R12 (verbose flag, model identity) and R8 (heap).
19. **`system/my_product/build.prop` dated edits.**
    - 2026-10-12: game low-latency audio disabled ("games crackle").
    - 2026-10-07: donor punch-hole `screenhole.positon`/`screen.heteromorphism` commented out (the
      status-bar clock collapsed).
    - 144 Hz options: `rapid.refresh_rate.level=144`, `refreshrate.maxsettings=4`,
      `ogfr.exclusive=144`. Ties to R12 (peak refresh 144).
20. **`system/my_manifest/build.prop`.**
    - What changed: device/name=pipa, display id `OPD2515_17.0.0.102(CN01)`, and
      `oplusrom.display="17.0 | by梦归zzz"`.
21. **Feature XMLs** (`system/my_product/etc/permissions/`).
    - `oplus.product.display_system_features.xml`: `wcg_2.0_support` commented out (2026-10-13,
      "colour temperature wrong"). Ties to M6.
    - `oplus.product.feature_video_unique.xml`: hdr10/hdr10plus commented out (stutter).
    - `oplus.product.display_features.xml`: adds `lcd_aod_mode`.
22. **`system_ext/etc/selinux/system_ext_sepolicy.cil` (+ `_debug`) "pipa port" block.**
    - What changed: `find` on 5 Oplus services. Also `allow tee oppo_block_device blk_file`, because
      the pipa ssd on `sda2` is labelled `oppo_block_device` → qseecomd EACCES → keymaster never
      registers → boot stalls.
23. **`system_ext/etc/display_brightness_config_default.xml`** (version 20261006).
    - **Corrected 2026-10-22 against the C.06 donor:** this is the donor's own table. The port
      changed only `brightness_table max` from 8191 to 10239 (plus the version stamp). The 800 nit peak
      and flat low end are therefore the Pad Mini panel's values.
    - The module replaces it (M7; input md5 `4714aaab…` matches).
24. **Port apps and bridges.**
    - `system/system/app/FaceUnlock/FaceUnlock.apk` (`com.pipa.faceunlock`, Megvii libs, 21 MB
      `etc/face/model_file`, `default-permissions/pipa_faceunlock.xml`). This is the legacy socket
      client of R4/M5.
    - `system/system/app/OppoCamera/OppoCamera.apk` (`com.oppocamera`): a Fossify-derived substitute,
      not Oppo's camera.
    - `system/system/priv-app/MiSound` (+ privapp/hiddenapi XMLs).
    - miuicamera permission XMLs.
    - `system/system/bin/virtual_keyboard` (+rc).
    - `system/system/lib64/libxiaomipen.so` (pen mode → `/dev/xiaomi-touch`).
25. **Overlays** (`system/my_product/overlay/`).
    - Port-built: `PipaCornersOverlay`, `PipaLauncherOverlay`, `PipaMiSoundOverlay` and
      `PipaSettingsPadOverlay` (`com.port.pipa.overlay.*`).
    - Re-signed donor `*.display.product.25928*.apk` with blanked `rc_*` corner PNGs. Ties to R12
      (corners overlay healthy).

### 4.4 Companion module (`pipa_cos17_power_tune` v0.9): what it changes vs the port

| Module file | Port original | Origin of the original | Ref |
|---|---|---|---|
| `vendor/etc/qdcm_calib_data_xiaomi_m82_36_02_0a_*.xml` / `42_02_0b` | `c5794bfe…` / `151b5080…` | byte-identical to HyperOS, PixelOS and iqraos | M6 |
| `vendor/etc/audio_policy_volumes.xml` | `be96e8f8…` | = PixelOS; vs HyperOS only a trailing newline | M13 |
| `vendor/lib/hw/audio.primary.kona.so` (32-bit) | `8725bcea…` | = PixelOS; differs from stock `fbc2ac12…` | M14 |
| `system_ext/etc/display_brightness_config_default.xml` | `4714aaab…` | port-synthesised (S23) | M7 |
| `framework/<base-md5>.jar` | `3316594f…` (beta4), `2175feb9…` (C.06) | port-repacked (S17) on beta4; C.06 is donor stock | M12 |

Runtime-only fixes (M1–M5, M6b) have no file counterpart in the image.

---

## 5. DONOR ARTIFACT list (with provenance evidence)

| # | Path(s) | Provenance evidence |
|---|---|---|
| D1 | ~250 `vendor/lib*`, HAL binaries, `vintf` (IPower v7, `health-V5`) | Lineage HAL names; same sizes as PixelOS but newer A17 build; build date 2026-08-22, incremental = unix time |
| D2 | `vendor/lib64/hw/vulkan.adreno.so`, `egl/*adreno*`, `libgsl`, `libllvm-q*`, `libOpenCL_adreno`, `vulkan.turnip.so`, `gralloc.qcom.so`, `firmware/a650_{sqe.fw,zap.elf}` | driver string `LA.VENDOR.12.3.11` 2025-08; absent from all baselines |
| D3 | `vendor/bin/hw/android.hardware.biometrics.face-service.facehal` (Rust), `libjni_stfaceunlock_api.so` (30 MB SenseTime), `libfacehal_jni.so`, `libcamera2ndk_vendor.so`, face vintf | vintf header "OemPorts10T"; absent from all baselines. `crop_eyes` crash (R2, M9) is in this lib |
| D4 | `vendor/bin/hw/vendor-oplus-hardware-performance-V1-service`, `…stability.oplus_project-V1-service`, `etc/init/oplus_hal_odm.rc`, `oplus_avb.pubkey` | rc comment: "from the community C17 power-key fix package (originally under /odm)"; "only works while SELinux is permissive" |
| D5 | `vendor/bin/xiaomi-keyboard` + `start xiaomi-keyboard` in `init.device.rc` | byte-identical to PixelOS. HyperOS stock has **no** `xiaomi-keyboard`; it uses `vendor.xiaomi.hardware.keyboardnanoapp@1.0`, which the port removed. R1's drain therefore comes from the Lineage tree, not from Xiaomi |
| D6 | `vendor/lib/hw/audio.primary.kona.so` (32-bit) | = PixelOS md5, differs from stock. M14 found stock's rotation table identical (same instruction, same offset), so the 270→spin_90 mapping is Xiaomi's; the binary itself comes from the custom-ROM build |
| D7 | `odm/bin/commcenterd`, `odm/bin/hw/subsys_daemon`, `bin/init.subsys.sh`, `etc/init/virtual_daemon.rc`, 8 modem/GPS `.cfg`, all `odm/lib*` (libmindroid-*, radio/subsys), 7 vintf fragments, `odm_service_contexts` | Oppo Pad Mini ODM "virtual modem" stack; fake `IRadio vircommslot1/2` on a Wi-Fi-only tablet |
| D8 | `product/*` (237 files) | generic Oppo QSSI product: `device=ossi`, `qti/qssi/qssi:17` fingerprint, `*ResCommon_Sys` RROs, 146 MB gmssystem apex; zero pipa strings |
| D9 | `system/my_product/build.prop` `ro.build.version.ota=OPD2515_11.A.01…`, `my_manifest` `OPD2515_11.C.05…`; `system_ext/app/{OTA,SAUHelper,SystemAppUpdateService}`, `priv-app/UpgradeGuide`, `my_stock/priv-app/RomUpdate`, Cota | donor OTA identity intact, which explains the OPD2515 SOTA offer (R11) |
| D10 | `my_product/overlay/*.lvy.apk`, `wallpaper.livepicker.overlay.25928_old`, `my_product/etc/dolby_vision.cfg` ("OPPO OPD2515") | "lvy" is the Pad Mini codename |
| D11 | `system_ext/etc/build.prop` (oplus/ossi, 2 SIM slots), `system/system/build.prop` nitz/RIL/`default_network=26,26` | donor cellular config on a Wi-Fi-only device |
| D12 | `system_ext/etc/display_brightness_config_common.xml` (20240808), `oplus_screen_effect_features_config.xml`, `sys_display_compat_config.xml`, `sensor/oplus_sys_sensor_config.xml` | donor display/sensor configs, not tuned for pipa |
| D13 | `system_ext/etc/obrain/config/midas.conf` (`<kona>` sections) | native Oplus SM8250 profiles, so R7's crash is not config-driven |
| D14 | `system/system/etc/init/a2lrootfs.rc` | Oppo Linux-container service |
| D15 | `product/etc/init/*qvirt*`, `init.fg.protect.rc-qcom` | QTI trusted-VM services (no `trustedvm` on SM8250); `fg.protect` points at `init.fg.protect.sh`, but the shipped file is `…sh-qcom`, so the service fails |

---

## 6. UNEXPLAINED list (ranked by likely impact)

| Rank | Item | Impact | Why it matters / next step |
|---|---|---|---|
| U1 | `system/system/etc/init/zz_portdebug.rc` ("added by Codex"): `hung_task_panic=1` (60 s), `softlockup_panic=1`, `panic=20`, root `logcat -b all` → `/metadata/port` | **High** | Bring-up debug left in a release. Any 60 s hung task or soft lockup becomes a panic and reboot; the logcat to `/metadata` also costs wakeups and flash writes. Remove for release, or confirm it's intentional. Not in any README Fixed in beta5 (absent). |
| U2 | 32 of 43 `vendor/etc/thermal-*.conf` differ from stock (= PixelOS). Same length, identical prefix, then the rest differs; Xiaomi-encrypted | **High-med** | Same-length edits fit sensor-name or trip-point substitutions (R10). Decrypt with the Xiaomi thermal key and diff. `thermal-engine.conf`, `thermal-map*`, `-chg-only` and `-huanji` are unchanged |
| U3 | Boot deadlock when enforcing (worked around by `portenforce.rc`) | **High** (security) | The device runs permissive through boot. Look at the keystore2/vold ordering; the `tee oppo_block_device` fix (S22) may already be the real cause |
| U4 | Face HAL rc: `disabled`, no `interface` line, no exec label in `vendor_file_contexts`; started only by `pipa_core` | High (feature) | Cause of R2 confirmed in the image. Fix in the ROM: add the `interface aidl` line, label the binary, grant camera/GPU access |
| U5 | ROM depends on `pipa_core` to start `subsys_daemon` as root (S14) | Med-high | A clean flash without the module loses the subsys HALs. Proper fix: a `hal_radio` sepolicy rule for `/dev/diag`, or a labelled init service |
| U6 | `odm/etc/selinux/precompiled_sepolicy` + 3 sha256 files differ from all baselines | Med | Needs `sepolicy-analyze`/`seinfo`. A stale hash makes init recompile at boot |
| U7 | `odm` vintf: `subsys_radio` slot1 declared **V9**, shipped lib is `…subsys_radio-V8-ndk.so`; `radio@1.5` and `ims@1.7` use `override="true"` | Med | Possible VINTF/servicemanager mismatch for Oplus radio clients |
| U8 | `system/build.prop` `ro.surface_flinger.has_wide_color_display=false`, `has_HDR_display=false` (not in stock), plus `wcg_2.0` off | Med | SF treats the panel as sRGB-only and skips colour management. Relevant to M6 oversaturation |
| U9 | `my_product/build.prop` donor display props: `ro.display.underscreen.lightsensor.support=1` (region 830,231,888,287), `hightempaging_dbv=3084`, `force_tonemapping=1`, `lcd_photodimming_module=1`, `brightness.curve.name=expressiveness` | Med | Pad Mini under-screen ALS assumptions on a pipa without one; related to M11/M12 (sensor 33171001) and to auto-brightness |
| U10 | Brightness table peak 800 nit, levels 2–4 flat at raw 4 | Med | pipa's panel peaks lower; affects the nit-based auto-brightness spline (M7). The module's replacement table supersedes it |
| U11 | `odm/etc/init.oplus.mm-sys.sh` uses 8192 MB zram for any RAM ≤ 8 GB | Med | Oversized on 6 GB pipa units; `swappiness=100` plus the loop-backed swapfile adds flash writes |
| U12 | Health: vintf declares `IHealth` v4, binary links `health-V5-ndk`; no OPPO charger HAL (stubbed `oplus_absent_service`) | Low-med | Background for R6/M8 |
| U13 | Removed `odm/etc/audio_policy_engine_*_mi.xml` (4) and `media_profiles_V1_0.xml` | Low-med | Check that the engine config is resolved from vendor |
| U14 | `vendor/bin/qdcmss` + rc missing (also missing in PixelOS) | Low-med | No QDCM service daemon; colour modes still switch via HWC (M6) |
| U15 | 3 vendor `.ko` modified (`gspca_main`, `rmnet_perf`, `rmnet_shs`); `libhwdap.so`/`libswdap.so` modified vs stock | Low | Check provenance against the shipped kernel |
| U17 | **`system/system/build.prop`: the port deleted `ro.secure=1`, `ro.adb.secure=1`, `ro.debuggable=0` and `ro.force.debuggable=0`**; no other system-side partition sets them | **High** (security), unverified | If nothing else sets `ro.adb.secure`, adbd skips RSA authorisation, so any USB host gets ADB without a prompt. They may come from the boot ramdisk or be injected at runtime, so check on the tablet: `getprop ro.adb.secure ro.secure ro.debuggable`. Found in the C.06 diff (§9) Fixed in beta5 (donor values restored); `device_check.sh` reports them. |
| U16 | `odm/etc/init/commcenterd.rc` CRLF, no seclabel; `heteromorphism` feature kept while the prop is commented out; `.uau` rule in the jar | Low | Cosmetic or probably harmless |

---

## 7. How to apply this on a new base

1. **Diff first.** Extract the new port build next to the current one. Re-run the manifests
   (`md5sum` per partition into `../reference/analysis/inventory/<rom>.<part>.md5`) and
   `python3 diff_manifests.py <part>`. Anything whose md5 matches the hashes in §4.4 can take the
   module files as they are. For anything else, regenerate with `module/tools/*`; never copy the old
   outputs.
2. **Vendor tree.** Start from the newest Lineage-family pipa vendor (PixelOS/EvolutionX/AOSPA). Then:
   - re-import the 96 stock blobs in 4.1-7 (the `content_in=hyperos1-stock` rows);
   - port the `vendor/build.prop` comment block, `portenforce.rc` and the `pipa port` sepolicy
     sections;
   - re-apply the `audio_policy_configuration.xml` and `audio_effects.xml` edits, the idc/kl files,
     `camxoverridesettings.txt` and the `vulkan.adreno.so` patch (only if the same driver);
   - drop the vendor overlays;
   - keep `xiaomi-keyboard` but gate it (M1/M2), or restore HyperOS's `keyboardnanoapp` HAL.
3. **ODM.** Carry `init.oplus.mm-sys.sh` (fix the 6 GB branch), the `subsys_daemon.rc` comment-outs,
   `build.prop` identity and the IMS feature XML. Either keep `pipa_core` for `subsys_daemon` or
   write the sepolicy so init can run it.
4. **System side.**
   - Apply S18–S21 prop/XML edits and the S22 sepolicy block.
   - No port dex edits exist (`maintainer/jar-edits/REPORT.md`). Run `tools/patch_framework.sh` on the
     new jar for the CCT reroute (M12).
   - Ship the port apps and overlays (S24, S25).
   - **Remove `zz_portdebug.rc`.**
   - Bake `ro.build.tablet_type=pad` and `persist.sys.facehal.verbose=false` (R12).
   - Pre-create `/data/ota_package/OTA` or disable `com.oplus.ota` (R11).
5. **Face.** Add `interface aidl android.hardware.biometrics.face.IFace/default` and an exec label to
   the facehal rc. Fix `crop_eyes` (M9). Remove `com.pipa.faceunlock` (R4).
6. **Verify.** On device: the md5 of each bind-mounted file, `getenforce` after boot,
   `dumpsys thermalservice` against the raw zones, and `service list | grep -i subsys`.

---

## 8. Contradictions with the existing READMEs

1. **M10: "34 of 43 `thermal-*.conf` differ from stock (raised trip points)".** 32 of 43 differ. The
   files are encrypted, so "raised trip points" cannot be read from them. The README's own "Thermals
   under load" section already says they are encrypted.
2. **R1 / Open item 2 call `xiaomi-keyboard` "the stock daemon".** It is the Lineage/PixelOS
   daemon. HyperOS stock uses the `keyboardnanoapp` HAL and has no `xiaomi-keyboard`.
3. **M12 / CLAUDE.md "stock beta4 jar md5 `3316594f…`".** That jar is the port's shipped jar, which
   the port author already repacked on 2026-09-26. It is not donor stock.
4. **README "Memory / zram" credits nandswap to "OPPO nandswap".** The configuration (8 GiB lz4 zram,
   swapfile, priority 2020) comes from the port-author script `odm/etc/init.oplus.mm-sys.sh`, run
   through ColorOS's hook.
5. **README "Bug sweep" cites `OplusBatteryService getDataFromHalByOldInterface` as "finding #8".**
   It is R6 (and M8).
6. **M6 says the qdcm files are "identical to stock HyperOS".** Confirmed. M14 calls the 32-bit
   audio HAL the "stock port HAL". It is the PixelOS build (`8725bcea…`), not Xiaomi's (`fbc2ac12…`);
   M14's finding that both share the same rotation table still stands.

Items 1–5 were corrected in README.md, module/README.md, CLAUDE.md, AGENTS.md and
HANDOFF-adaptive-bedtime.md on 2026-10-22.

## 9. Exact OS-side change list vs a real donor build (2026-10-22)

The newer donor build, OPD2515 `17.0.0.103(CN01)` / `11.C.06_1060_202610061842`, was downloaded from
OPPO's CN OTA server (see `MAINTAINER-STATUS.md`). It is one minor step after beta4's base C.05.
`maintainer/port_diff.py changes` against beta4 gives 1 678 differences: 40 added, 1 480 modified,
158 removed. Compare roughly 11 000 against HyperOS.

Most "modified" files are C.05→C.06 churn: 972 framework/oat files, app/lib rebuilds, version stamps,
`my_manifest/etc/*.map`, horae configs. They must **not** be carried onto C.06.

**`maintainer/c06-vs-beta4/PORT-EDITS.tsv`** is the curated list (75 rows): port additions
(`carry`), text edits to re-apply, binaries to re-derive, the debloat list (`remove`), and two `DROP`
rows. Supporting files in the same folder: `port-changes.tsv` (raw), `text-diffs.txt` (every
modified text file, diffed) and `modified-nonbinary.txt`.

What the diff added to this inventory:

- **The debloat list:** `del-app` Health, HeytapReader, HotGamesFolder, WpsLauncher, BrowserVideo,
  Gamecenter, KeKeThemeSpace, KeKeUserCenterMember, Melody, Music, OPPOStore, PhoneManagerLite,
  StudyCenter and Tips. Also `OplusCamera` (replaced by `OppoCamera`). The 5 Vodafone-ES `SimSwitchFirstTime` XMLs and
  `properties/es-vodafone` that are "missing" in beta4 are new in C.06, not port removals.
- **New port additions:** `system_ext/apex/com.android.vndk.v30–v33.apex` (VNDK compat for the
  re-imported Xiaomi blobs), `android.hardware.telephony.gsm.xml`, `system/etc/media_profiles.xml`,
  a second Megvii model `etc/face/panorama_mgb`, and the root `/build.prop` (heap).
- **New port edits:**
  - `refresh_rate_config.xml` (144 Hz rate id and max settings 4);
  - `power_profile.xml` `battery.capacity` 8000 → 8840;
  - `my_product/build.prop` `ro.build.tablet_type` mini → **pad** (so R12's "not in build.prop" only
    holds for `system/build.prop`), `persist.sys.block.fingerprint` true → false, density 420 → 370;
  - `system/build.prop` `persist.logd.size=4M` and the removal of the `ro.secure`/`ro.adb.secure`
    lines (U17).
- **Port-repacked archives:** only the three already known (`oplus-services.jar` and the two
  `*.display.product.25928*` overlays), found by zip entry dates. `Browser.apk` and `GlobalSearch.apk`
  carry 2026 dates in the donor too.
- **SELinux debugging leftovers in beta4:** all `dontaudit` rules were deleted from
  `plat_sepolicy.cil` (552) and `system_ext_sepolicy.cil` (172). That means more AVC log noise; don't
  carry it. `OplusRemoteDisplay.uau` in `oplus-services.jar` is **donor-native** (S17's mention of it
  as a port edit is wrong). The 17 differing strings are all C.05→C.06 churn, not port edits
  (`maintainer/jar-edits/REPORT.md`, 2026-10-22): the vibrator "fallback" string is only a renamed log
  label with identical logic. Nothing to re-apply to the C.06 jar; the repack itself (no manifest, no
  D8 marker) is the only visible port change.
- **Unsure without C.05:** whether the port removed Oppo's boot monitor / phoenix
  (`boot_monitor_service`, `bms_cli`, `phoenix_fault_recorder`) or C.06 introduced them. Same
  question for the `LogTrialNew` → `LogTrialCommercial` swap (probably churn).
- **Modified system binaries** (`surfaceflinger`, `gpuservice`, `perfetto`, …) and 24 `system/lib64`
  libs are treated as churn. No port marker was found, but only C.05 can prove that.
- **Churn that breaks pipa (found on the device, 2026-10-22):** C.06 changed
  `system_ext/{lib,lib64}/libupdateprof.qti.so` and `libtrigger-handler.so` only by switching the import
  `AServiceManager_checkService` -> `AServiceManager_waitForService` (QSPM / Snapdragon perf HAL, absent on
  pipa). The C.06 copies hang system_server (watchdog bootloop), so they are now `carry` rows (beta4
  copies). Separately, the restored `ro.adb.secure=1` (U17) sends `OplusEngineerFwService` into a
  `waitForService` on the missing IEngineer HAL; `patch_framework.sh` edit 4 fixes that in the jar.
  Details: `module/README.md` §15. Lesson for the next rebase: diff the imports of changed libraries,
  not just their existence; a new `waitForService` on a vendor HAL pipa lacks is a bootloop.
