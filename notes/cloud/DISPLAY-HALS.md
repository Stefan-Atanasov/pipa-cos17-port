# OPPO display colour HALs on pipa: interfaces, callers, what is lost, shim plan

Static notes (cloud session, 2026-11-03). Reviewed against the donor files. Nothing here is tested on a device.

- **Donor build:** OPPO Pad Mini OPD2515, OTA `OPD2515_11.C.07_1070_202610201803`. The port documents C.06. C.07 is the
  newest build on the OTA server (a bug-fix release). The C.07 `surfaceflinger` has the same md5 as the C.06 file
  (`STOCK_MD5` in `module/tools/patch_sf_waits.py`). Check the feature ids again on C.06 before you build.
- **Scope:** `displaypanelfeature`, `display.MixLut3D`, `displaycolorfeature`, `mmdisplayfeature`, `cwb`, pixelworks
  `IIris` / `IIrisFeature`. Background: ARCHITECTURE.md steps 2x, 2z, 3f, 3q-3s; BUGS.md rows 13 and B11. (The prompt
  names BUGS.md item 22. BUGS.md has no row 22 now.)
- **Method:** string scan of all partitions, androguard disassembly of the Java callers, ELF imports, call sites and
  `.gnu_debugdata` symbols of `surfaceflinger` and the donor services, decode of the two jump tables (set, get) in the
  donor `displaypanelfeature` service. No decompiled code is in this file.
- Evidence labels: **[seen]** = read in the donor. **[inferred]** = a reading of the evidence. **[unknown]** = not found.

## Summary

1. **No caller hangs on pipa today** (with step 2x). [seen]
   - `surfaceflinger`, `libsensorserviceextimpl`, `lib_inputflingerEx` and `horae` use `AServiceManager_checkService`
     for `displaypanelfeature`. They log `displayPanelFeature is NULL` and return.
   - The Java helper `HidlDisplayPanelFeature` (services.jar) tries AIDL `ServiceManager.getService`, then the HIDL
     `IDisplayPanelFeature.getService()`, on every call, with no null cache. pipa does not declare the HIDL instance,
     so hwservicemanager answers at once: the known log `Cannot find entry ... IDisplayPanelFeature/default` and
     `getHidlDisplayPanelFeatureService error`. This costs one lookup per call. It is not a hang.
   - MixLut3D, displaycolorfeature, cwb and Iris: SF and the Java callers use `checkService` or `isDeclared` first.
     After 2x every site handles null.
2. **MixLut3D and displaycolorfeature are not separate HALs on the donor.** OPPO snapdragoncolor plugins
   (`odm/lib64/libPanelChaplin.so`, `odm/lib64/libstc_color_feature.so`, listed in
   `vendor/etc/snapdragon_color_libs_config.xml`) register them inside the Qualcomm composer process. They link the
   donor SDM colour ABI. pipa keeps its own vendor and odm, so it cannot load them. [seen]
3. **displaypanelfeature** has 3 methods (AIDL codes: get 1, set 2, info 3). All work is in about 100 feature ids
   (section A.2). Most ids drive OPPO panel hardware that pipa does not have (HBM, DC dimming, FOD press, demura, ADFR,
   pulse, AOD). [seen]
4. **User features lost on pipa** that are not worked around yet:
   - Read Mode panel part (id 35, `OplusFeatureReadMode`). [seen caller; effect to verify]
   - Game Eye Care / game dark eye protect (id 228, `OplusFeatureGameEyeCare`). [seen caller]
   - Reduce White Point (id 249, `OplusFeatureWhitePoint`). [seen caller; effect to verify]
   - Sharpness switch (Settings -> SF transaction 24000 -> `Sharpness::handleSharpness` -> displaycolorfeature). [seen]
   - Panel 3D LUT in screenshots (`IMixLut3D.getDisplayLut`, SF `fetchPanelLuts`). Low value. [seen]
   - Worked around already: colour modes and seed (id 4) by QDCM (3q, 3r) and SF 23114; Game Filter by a colour
     matrix (3f); idle refresh drop by 2z; adaptive tone by 3s.
5. **Eye Protect CCT:** no `displaypanelfeature` id carries CCT or RGB gains in the C.07 callers, and the donor
   service has no CCT handler. The claim in `module/README.md` section 11 (the tint goes to `IDisplayPanelFeature`)
   needs a check on the device (open question 1). [inferred from absence]

## Section 4: shim plan (plan only, no code)

### 4.1 Recommendation

| Item | Do | Why |
|---|---|---|
| MixLut3D, displaycolorfeature, mmdisplayfeature, cwb, Iris | **Nothing.** Keep them absent and undeclared. | Every caller handles null (2x). A registered stub would start SF code paths (Iris setup, cwb sampling, call_once LUT fetch) on SF threads with no timeout. |
| displaypanelfeature, "answer only" stub | **Optional, low priority.** | It removes the log noise and one failed lookup per call in system_server and SF. It adds no user feature. |
| Read Mode (35), Game Eye Care (228), Reduce White Point (249) | **Patch the Java callers in `oplus-services.jar`** (the 3f method), not a HAL. | All three callers run in system_server. There they can use `DisplayTransformManager` levels, which compose with Night Light, Game Filter and Eye Protect. A HAL process can only send SF transaction 1015 directly, which replaces the whole matrix and fights with `DisplayTransformManager`. |
| Sharpness | Leave it. Optional later: hide the switch. | pipa's SDM stack has no OPPO sharpness block. |

### 4.2 If the displaypanelfeature stub is built (model: `maintainer/touchshim`)

- **Service name:** `vendor.oplus.hardware.displaypanelfeature.IDisplayPanelFeature/default`, AIDL V1 only. Never
  declare the HIDL `@1.0` instance: a declared HIDL instance with no server makes `getService()` wait.
- **Process:** a Java host plus a registrar started by `pipa_port`, the same as `touchshim.jar` (4o) and the charger
  shim. Own jar `port-rom/pipa_port/panelshim.jar`, own code from the AIDL wire protocol (descriptor, codes 1-3,
  `getInterfaceVersion`/`getInterfaceHash` from the stub jar). No donor classes.
- **Stability and VINTF:** register a system-stability binder and add **no** VINTF entry, as the touch shim does.
  All callers are system processes (system_server, SF, sensorservice in system_server, inputflinger), so a system
  binder is accepted. Without a manifest entry `isDeclared` stays false, so `libcwb_client` skips it (no 5 s wait),
  and `checkService` / `getService` still find it. A VINTF-stability binder would need a manifest entry, and then a
  late start makes `libcwb_client` wait 5 s. The touch shim README lists VINTF stability as an open runtime risk:
  test it the same way.
- **SELinux:** label the name `oplus_absent_service` in `system_ext_service_contexts` (as 4o). The system_ext policy
  already lets `pipa_port` add that type. Check that SF, system_server and inputflinger may `find` it; compile with
  `secilc` and all 8 inputs (AGENTS.md). If a rule is missing, add it to `maintainer/sepolicy/pipa_port_rules.cil`.
- **Answers** (details in A.5):
  - `get` (code 1): fill the requested array length; status 0 and zeros for the probe ids (5, 6, 13, 14, 20, 34, 69,
    179, 183, 211, 212, 233, 247, 264). Id 211 must say "no FP type". Ids 8 and 29 may read
    `/sys/class/backlight/panel0-backlight/{max_brightness,brightness}` (needs a read rule).
  - `set` (code 2): status 0 for the accept-and-ignore ids (A.5.2); keep the last value for `get`. Status -1 for
    unknown ids and the unsupported list, like the donor (`default, no choice!`).
  - `info` (code 3): status 0 and a list with one string (empty is fine). A null list can crash a caller.
  - Ids >= 0x1000 (sub panel): status -1.
  - Never block, never call back into SF or system_server from a binder thread.
- **Must answer first:** the SF set/get ids (4, 184, 194, 201, 260), `libsensorserviceextimpl` ids 6, 13, 14, 22, 29,
  34 and info 9, id 211, `lib_inputflingerEx` id 20.
- **Death:** SF and the sensor lib link to death and look up again. If the host dies, `pipa_port` must start it again.
- **Step:** `maintainer/port/steps/NN-<step>-panel-shim.sh`, the same pattern as `68-4o-touch-hal-shim.sh` (install the
  jar with the label of the jar next to it, `forbid_grep` the name in `system_ext_service_contexts`, append the
  label line, `set_layer`). Add the name and md5 to `maintainer/flash_super.sh`.

### 4.3 Java patch for ids 35, 228, 249 (plan)

1. In `oplus-services.jar`, find the three senders (`OplusFeatureReadMode.setReadModeStatus`,
   `OplusFeatureGameEyeCare.updateGameEyeCareStatus`, `OplusFeatureWhitePoint` observer). Each one calls
   `setDisplayPanelFeatureValue(<id>, ...)` on the panel helper.
2. Replace that call with a `DisplayTransformManager.setColorMatrix(<level>, <matrix>)` call, as 3f does for Game
   Filter. Use a free level between the Night Light and the accessibility levels; check the levels that 3f uses.
3. Matrices (to tune on the tablet): Read Mode = a warm paper tint with lower saturation; Game Eye Care = a small dim
   and warm shift; Reduce White Point = a uniform scale (for example 0.8). First check that AOSP Reduce Bright Colors
   (`ColorDisplayService`) does not already cover 249 on pipa.
4. Test each with `dumpsys color_display` and a camera photo against the switch off. Remove the matrix when the
   switch goes off and at screen off/on.

### 4.4 Device checks before any work

1. Eye Protect CCT (open question 1): `setprop log.tag.HidlDisplayPanelFeature V`, turn Eye Protect on, read the
   `setDisplayPanelFeatureValue +++, ID:` lines. This shows which ids the UI sends.
2. Read Mode and Reduce White Point: turn them on and compare a photo. If nothing changes, they are on the list in 4.3.
3. Count `displayPanelFeature is NULL` lines in SF per minute. If they are rare, the answer-only stub has no value.


# Part A: displaypanelfeature

## A.1 Interface

### A.1.1 AIDL V1 [seen]

- Descriptor: `vendor.oplus.hardware.displaypanelfeature.IDisplayPanelFeature`. Instance: `.../default`. Interface version 1. Hash `39afca22ac77253421ad681eeb2bae0c6ff62c13`.
- Stability: VINTF (the Java stub calls `markVintfStability`). A stub service must register with VINTF stability.
- Java stub in `services.jar` (also in SystemUI, OplusGames, PostmanService; same layout):

| code | method | parcel in | parcel out |
|---|---|---|---|
| 1 | `int getDisplayPanelFeatureValue(int featureId, inout int[] values)` | int featureId, int length, (no payload) | exception header, int status, int[] values (length = request length) |
| 2 | `int setDisplayPanelFeatureValue(int featureId, in int[] values)` | int featureId, int[] values | exception header, int status |
| 3 | `int getDisplayPanelInfo(int featureId, out List<String> info)` | int featureId | exception header, int status, String[] info |
| 16777214 | `getInterfaceHash` | - | String |
| 16777215 | `getInterfaceVersion` | - | int |

- The caller chooses the length of the get array. The stub of the callee gets a zero-filled array of that length. Max length is 1,000,000 (Binder check). The services.jar helper asks for length 1, and for 5 when featureId is 5 (panel id). SystemUI asks 10 (id 179) and 32 or 1 (id 211). [seen]
- Status convention: 0 = success. The Java helper treats `status >= 0` as success for get and builds the list from the array; a negative status gives a null list. [seen]
- NDK client vtable (libs): in `lib_inputflingerEx.so` `get_sau_mode_aidl` calls slot +0x30 with id 20, so slot +0x30 is the get method [seen]. In the NDK lib, the service side writes status then the int array for this slot.
- The Java wrapper for the AIDL get waits at most 10 ms on a `PendingResult`, but it sets the result before it waits, so there is no real timeout [seen].

### A.1.2 HIDL 1.0 [seen]

- Descriptor `vendor.oplus.hardware.displaypanelfeature@1.0::IDisplayPanelFeature`, instance `default`. Chain: IDisplayPanelFeature, IBase.
- Methods (HIDL codes 1..3; 2 and 3 seen in the Java proxy, 1 by elimination):

| code | method | args | return |
|---|---|---|---|
| 1 | `getDisplayPanelFeatureValue(int32 featureId) generates (int32 status, vec<int32> values)` | int32 | callback `onValues(int, ArrayList<Integer>)` |
| 2 | `setDisplayPanelFeatureValue(int32 featureId, vec<int32> values) generates (int32 status)` | int32, vec<int32> | int32 |
| 3 | `getDisplayPanelInfo(int32 featureId) generates (int32 status, vec<string> info)` | int32 | callback `onValues(int, ArrayList<String>)` |

### A.1.3 AIDL against HIDL

| item | AIDL V1 | HIDL 1.0 |
|---|---|---|
| get length | The caller sets the length (inout array). The service fills it. | The service chooses the length (`vec`). |
| get return | status + array | status + vec in a callback |
| set | `int[]` | `vec<int32>` |
| lookup (Java) | `ServiceManager.getService("...IDisplayPanelFeature/default")` | `getService()` of the generated class (name `default`, 2-arg `HwBinder.getService`) |
| lookup (native) | `AServiceManager_checkService` / `getService` / `waitForService` | `...::V1_0::IDisplayPanelFeature::getService(name, getStub)` |
| absent | null binder, no exception | `NoSuchElementException` in Java; null in C++ |
| manifest | `odm/etc/vintf/manifest/manifest_oplus_displaypanelfeature_aidl.xml` (V1, `IDisplayPanelFeature/default`) | The donor odm has no HIDL manifest entry; the service binary is AIDL only [seen]. `vendor_hwservice_contexts` still lists the HIDL name. |
| framework matrix | `system/system/etc/vintf/compatibility_matrix.device.xml` lines ~741-756 list both | same |

The donor service is AIDL only: `odm/bin/hw/vendor.oplus.hardware.displaypanelfeature-service` calls `AServiceManager_addService`. The HIDL path in the callers is a legacy fallback. On the donor, those fallback calls fail too, unless a HIDL service exists [inferred]. Callers that use only HIDL (section 3) are dead code on the donor.

### A.1.4 Donor service (for reference) [seen]

- rc: `odm/etc/init/vendor.oplus.hardware.displaypanelfeature-service.rc`. Class hal animation, user system. The early-boot trigger sets owners of `/sys/kernel/oplus_display/*` nodes.
- Internal clients: `display.qservice` (Qualcomm IQService, OPPO-specific commands), `vendor.oplus.hardware.cwb.ICwbService/default`, `vendor.qti.hardware.display.postproc`. It waits for them (`waitForService`/`checkService`).
- Ids above 0xFFF: the low 12 bits (`id & 0xFFF`) pick the feature, the upper bits pick the display (`0x1000` = second/sub panel, "_Ext" handlers). Examples: 4107 = serial number of the sub panel, 4165 = 4096 + 69, 0x101d = 4096 + 29. [seen]
- Test tool `odm/bin/displaypanelfeatureTest` and a "for test" set/get switch exist in the service (shell: `get|set OMMDP...`, ids 1..15 in the help text).

## A.2 Feature id table

Reading help:

- "Callers": J = Java helper `OplusDisplayPanelFeatureHelper` (services.jar). The helper sends a single int as `int[]{v}` for `setDisplayPanelFeatureValue(int,int)`, or an array for `...Array`. S = oplus-services.jar class. UI = SystemUI. N = native.
- "pipa today": every call fails (no instance). "no-op" means the caller ignores the failure or has a fallback.
- "Stub can do": **A** = answer only (return a constant). **M** = pipa can implement it (matrix, saturation, backlight node). **U** = unsupported: return status -1 and an untouched array (this is what the donor service does for an unknown id). Details in section 5.
- The meaning column comes from the handler name in the donor service (log string) and from the Java constant name. Where only one of them exists, the cell says so.

### A.2.1 Basic panel nodes (ids 1-34) [seen]

| id | name / meaning | set/get | value format | callers | pipa today | stub can do |
|---|---|---|---|---|---|---|
| 1,2,3 | VDDI / VDDR / VGATE panel power rails (`SetDisplayPanelPower`) | s+g | int | Java constants only; no production caller found | n/a | U |
| 4 | **SEED**: colour mode index in the panel (`SetDisplayPanelSeed`; also sends `seed_mode` to qservice) | s+g | s: `{mode}`. Values: 0 vivid, 1 soft/adaptive/cinema, 3 colour4 (default values in `ColorModeConstants`); 100-103 = MTK variants; 102 for one branch | S `OplusFeatureColorMode.writeSeedValue`; N SurfaceFlinger (set, call site near the colour mode path); Game Filter / colour enhancement path | Dropped. Colour modes work through QDCM (3q, 3r) and SF transaction 23114 instead | A (return 0, keep the last value for get) or M (map the mode to the QDCM mode; not needed, 3q/3r already do it) |
| 5 | Panel id (5 ints, `GetDisplayPanelId`) | g | out `int[5]` | J `OPlusOnlineConfigManager`, `OPlusExternalRefreshRateManager` (only if `DEFECT_PANEL_MODE_ENABLE`) | list null; the defect-panel branch is off or reads null [unknown which] | A (zeros) |
| 6 | FFL (flash-free light?) `SetDisplayPanelFfl` | s+g | int | N `libsensorserviceextimpl` (get, `getFFLSetFromDisplayPanel`) | native get fails; ALS code takes its failure path | A (0) |
| 7 | AOD mode / doze light (`SetDisplayPanelAod`) | s+g | int; doze nit for get | S `OplusPowerManagerHelper.setDozeDisplayBrightness`, `OplusFeatureLongTakeBrightness`; UI `OplusOSAodManager.setAODLightMode` | doze nit read = -1; AOD light write dropped | U (A for get: 0) |
| 8 | Max brightness (`SetDisplayPanelMaxBrightness`; get also id 30) | s+g | int (nit/raw) | S `OplusCabcHelper.getAllProperties` (get) | get = -1 | M (read `max_brightness` of `panel0-backlight`) or A |
| 9 | Panel info string (`GetDisplayPanelInfo_Str`, from `/proc/devinfo/lcd`) | info | `List<String>` | J `DevicePropertyHelper.getDeviceManufacture` (info 9); N `libsensorserviceextimpl` (info 9, 0x1009) | manufacture string null | M/A (return one string such as the Xiaomi panel name) |
| 10 | CCD check | g | int | none seen | n/a | U |
| 11 | Panel serial number (info; `_Ext` for sub panel 4107) | info | String | S `OplusDisplayManagerServiceEnhance.getScreenProductionTime` | "production time" unknown in Settings | A (empty/"FAILEDSN") |
| 12 | HBM (`SetDisplayPanelHBM`) | s+g | int | none seen in C.07 Java except Fod paths | n/a | U |
| 13 | Dim alpha (`SetDisplayPanelDimAlpha`) | s+g | int | N `libsensorserviceextimpl` get (`getDimAlphaFromDisplayPanel`) | native get fails | A (0) |
| 14 | DC dim alpha (`SetDisplayPanelDimDCAlpha`) | s+g | int | N `libsensorserviceextimpl` get | native get fails | A (0) |
| 15 | Audio ready node | s | int | constant only | n/a | U |
| 16 | Dump info (`GetDisplayPanelDumpInfo`, `[id min cur max]` x5) | g | int[5] | constant only | n/a | U |
| 17 | Panel DSC | g | int | none | n/a | U |
| 18 | Panel power status | s+g | int | S `OplusPowerManagerServiceFeature$WorkerHandler.handleMessage` (set) | set dropped | A (accept) |
| 19 | Regulator control (`SetDisplayPanelRC`) | s | int | constant only | n/a | U |
| 20 | SAU close-backlight flag (silent reboot flag) | s+g | int | S `OplusSilentRebootManager.read/writeSilenceFlagValue`; N `lib_inputflingerEx.get_sau_mode_aidl` (get) | Java get = -1 | A (get 0) |
| 21 | Panel register read/write | s+g | `{reg, ...}` | none | n/a | U |
| 22 | Dim-layer HBM (`SetDisplayPanelDimlayHBM`) | s+g | `{0/1}` | S `OplusFakeImageLayerExtImpl.setScreenFeatureForFakeImage` (set, HIDL only); UI `OnScreenHighLightControl.hbmControl` (set, HIDL); N `libsensorserviceextimpl` (get `getDimLayerHBM`) | set throws, caught, log "iDisplayPanelFeature err : " | A (accept) |
| 23 | Dim-layer backlight enable (DC dimming) | s+g | `{0/1}` | S `OplusFeatureDCBacklight.updateDCBacklight` | DC dimming write dropped; the panel never dims by DC | U (pipa panel has no OPPO node) |
| 24 | Panel blank notify | s | int | constant only | n/a | U |
| 25 | SPR | s+g | int | none | n/a | U |
| 26 | Round corner | s+g | int | none | n/a | U |
| 27 | DOC | s+g | int | none | n/a | U |
| 28 | FP press (`SetDisplayPanelFPPress`; notify under-display fingerprint) | s | `{0/1}` | J `setDisplayPanelFeatureValue` special case for FOD types (also SF transaction 20004 for MTK); S `UdfpsHelperExtImpl.writeLcdHighLightPath`; N SF (set) | dropped. pipa has no UDFPS | A |
| 29 | OBrightness (`GetDisplayPanelOBrightness`; 0x101d sub) | s+g | int | N `libsensorserviceextimpl` (`getBrightnessFromDisplayPanel`) | native get fails | M (read `brightness` of `panel0-backlight`) or A |
| 32 | Round corner (`SetDisplayPanelrRoundCorner`) | s+g | int | none | n/a | U |
| 33 | LCD max brightness | g | int | none | n/a | U |
| 34 | Panel stage (`GetDisplayPanelStage`; 0x1022 sub) | g | int | N `libsensorserviceextimpl` (`getMainDisplayPanelStage`, `getSubDisplayPanelStage`) | native get fails | A (0) |

### A.2.2 PQ, colour and eye care ids [seen]

| id | name / meaning | set/get | value format | callers | pipa today | stub can do |
|---|---|---|---|---|---|---|
| 35 | PQ mode status (`SetPQModeStatus` -> qservice 3D-LUT mode) | s | `{mode, status}` (the Java read-mode path sends `{1,...}`) | S `OplusFeatureReadMode.setReadModeStatus` (twice); N SF (set) | **Read Mode: panel part dropped** (check the visible effect) | M: apply a paper-like matrix through `DisplayTransformManager` (SF 1015) [inferred] |
| 68 | PQ trigger flag (`SetDisplayPqTrigger`) | s+g | `{flag}` (0/1) | S `OplusFeatureMEMCGame` (set 0/1) | dropped | A |
| 69 | Bits per pixel / multi-bit dimming support (`GetDisplayPanelBpp`; 4165 sub) | g | int | S `OplusDisplayManagerServiceEnhance.getScreenMultiBitsSupport` | = -1, treated as "not supported" | A (return 0 or 8) |
| 179 | Soft iris colour (`GetDisplayPanelSoftIrisColor`) | g | `int[10]` | UI `OnScreenHighLightControl` (`isDisplayColorModeCalibrateSupport`) | = unsupported | A (zeros) |
| 182 | CWB post process status | s+g | int | N (cwb clients) | n/a | U |
| 183 | `GetDPDisplaySupport` | g | int | none seen | n/a | A (0) |
| 184 | CABC status (`SetDisplayPanelCabcStatus`) | s+g | int | S `CabcService.get/setCabcValue`, N SF (set and get) | CABC setting has no effect; get = -1 | A (keep value in memory) |
| 185 | DRE status | s+g | int | N SF (set) | dropped | A |
| 186 | CWB enable (`SetCwbEnbale` -> ICwbService) | s | `{0/1}` | J `WifiDisplayAdapter.setCwbEnabled` | dropped; also "CWB AIDL is not present" on the donor side | A |
| 210 | Shutdown flag (`SetDisplayShutdownFlag`) | s | `{1}` | J `ShutdownThread` | dropped | A |
| 211 | **FP type** (`GetDisplayFpType`) | g | `int[1..32]` bit mask (bit 2 = dim layer; `0x4`) | UI `KeyguardFeatureOption.getUdfpsType`, `OnScreenHighLightControl`; S `OplusFeaturePanoramicBrightness.isOpticalFpWithNonLocalHBM`; N SF `[FOD] getDisplayPanelFeatureValue fpType=0x%x` | read fails; FOD treated as absent. This is the right answer for pipa | A (return 0 = no FP type) |
| 212 | CWB display id | g | int | N SF (get) | n/a | A |
| 213 | Fake AOD | s+g | int | UI `OplusOSAodManager.setFakeAodState` | dropped | A |
| 215 | qservice command (SF set) | s | int | N SF | dropped | U |
| 217 | Longrui AOD | s+g | `{0/1}` | UI `SmoothTransitionController` (get and set) | AOD transitions use the failure path | A |
| 192 | AOD area list | s | int list | UI `OplusOSAodManager.setAodArea` | dropped | A |
| 193 | Panel video mode | s+g | int | none seen | n/a | U |
| 194 | Dynamic TE (`SetDisplayDynamicTE`) | s+g | int | N SF (set, get) | dropped | A |
| 195 | Ultra-low-power AOD (LTPO AOD) | s+g | `{0/1}` | UI `OplusAODRefreshRateController.enableLTPOAod` | dropped | A |
| 197 | DC real brightness | s | int | none seen | n/a | U |
| 199 | PWM turbo (`SetDisplayPanelPWMTurbo`) | s+g | int | S `OplusFeaturePWMBacklight.handlePWMBacklightChanged` | dropped | A |
| 201 | PWM pulse (single-pulse dimming; also tells the composer) | s+g | int | S `OplusFeatureSinglePulseDimming` (get and set); N SF (set and get, two sites) | get = -1; the feature stays off | A |
| 220 | DC compensation (`DCCompensate...` via qservice; "DCC month") | s | int array (main switch, first comp, ...) | S `OplusFeatureCompensationConfig.applyDCCompensateLogStatus` (`{4}`) | dropped | U |
| 225 | FOSS param (`setFossParam`: enable, ratio, type) | s | `{enable, ratioBits, type}`; ratio = float bits (96.0 in the C.07 call) | S `OplusFeatureFoss.updateFossConfig` | dropped | U |
| 226 | UIR (under-display ... `SetUirEnable`) | s | `{enable, nitThd, tempThd, maxRatio, force}` | S `OplusFeatureUIR.switchUIR` | dropped | U |
| 227 | UIR mode (`SetUirMode`, needs `vendor.display.uir_support`) | s | int | none seen | n/a | U |
| 228 | **Game dark eye protect** (`SetGameDarkEyeProtect`, via qservice) | s | `{0/1}` | S `OplusFeatureGameEyeCare.updateGameEyeCareStatus` | dropped; Game Eye Care has no panel effect | M: apply a dim/warm matrix (SF 1015) [inferred] |
| 232 | ADFR min-fps param | s | int array | S `OplusHwDisplayRusAdfr` | dropped | U |
| 233 | ADFR state (get: support flag) | g | int | S `OplusHwDisplayRusAdfr.isSupportAdfr` | = -1 -> "not supported" | A (0) |
| 234 | RUS update (ADFR / pulse XML to the panel) | s | `{type, ...}` (225, 54 seen) | S `OplusHwDisplayRusAdfr`, `OplusHwDisplayRusPulse` | dropped | A |
| 235 | Panel scale-up state (DDIC scale up) | s | int | S `OplusFeatureMEMCGame.setPanelScaleUpState` | dropped | A |
| 236 | Demura RUS DBV gain | s | int array | S `OplusFeatureDMR.setDemuraGain` | dropped | U |
| 241 | Demura state / DMR enable (`SetDisplayDemuraState`) | s+g | int | S `OplusFeatureDMR` (set) | dropped | U |
| 244 | DMR info (get, manufacture info; `GetDisplayDemuraManufactureInfo`) | info | String (date/SN from `/mnt/vendor/persist/display/demura_product_info.json`) | S `OplusFeatureDMR.handleUpdateDMRValue` | null | A (empty) |
| 245 | Auto brightness status (`setAutoBrightnessStatus` via qservice) | s | `{0/1}` | S `OplusDisplayPowerControllerExtImpl.handleBrightnessModeChange` | dropped | A |
| 246 | Panel log config / AEEV fatal underrun | s+g | int | S `OplusFeaturePanelLogConfig.updateIsuLogStatus` | dropped | A |
| 247 | Normal max brightness | g | int | constant only | n/a | A |
| 249 | **Reduce white point** (`SetReduceWhitePointStatus`) | s | `{0/1}` or level | S `OplusFeatureWhitePoint` observer (twice) | **Reduce White Point has no effect** (verify) | M: apply a dim matrix or lower the backlight scale [inferred] |
| 251 | Brightness time (info; backlight on time string) | info | String | S `OplusScreenTimeEvent.getBacklightOnTime` | null | A |
| 255 | DSR mode (`Set DSR mode`, qservice) | s | `{mode}` / -1 | S `OplusFeatureMEMCDSR.enableSR/disableSR` | dropped; DSR (super-resolution) is off | U |
| 256 | Counting enable (deburn-in) | s | int | S `OplusFeatureDeburnin` | dropped | U |
| 257 | DBI enable | s | int | S `OplusFeatureDeburnin` | dropped | U |
| 258 | Counting frequency | s | int | S `OplusFeatureDeburnin.updateCaptureInterval` | dropped | U |
| 259 | Secondary sensor rect (get; `ro.vendor.oplus.sec.sensor.rect.*`) | g | int[4] | none seen | n/a | U |
| 260 | Dynamic float TE | s+g | int | N SF (set and get) | dropped | A |
| 262 | PCD error flag | g | int | none | n/a | U |
| 263 | Low-PWM AOD | s+g | int | none | n/a | U |
| 264 | Pulse state (support flag) | g | int | S `OplusHwDisplayRusPulse.isSupportPulse`; UI `SmoothTransitionController.initPwmPulseSupport` | = -1 -> "not supported" | A (0) |
| 265 | Pulse param | s | `{...}` (7 seen) | UI `SmoothTransitionController` | dropped | A |
| 266 | LGD value (get) | g | int | none seen | n/a | U |
| 267 | LGD value set (dark mode path) | s | `{0}` | S `OplusDarkModeServiceManager` | dropped | A |

Other handlers in the donor service with no caller seen in the dumps (ids 65, 66, 67, 80, 81, 177, 182, 198, 214, 216, 218, 219, 221-223, 239, 240, 242, 243, 250, 252-254, 261): kernel log level and switch (65, 67), `qservice` calls (66, 215), SVI/LTM switches (80, 81), apollo backlight (177), IRIS loopback (198), HBM max (216), MIPI/ESD/CRC checks (218, 221-223), demura get/config (239-243), ignore mode (250), DMR enable and SN (252, 254). SF calls ids 65, 66 and 215 through its set wrapper [seen]. Their use on pipa is [unknown].

SF set ids [seen, from the call sites of the set wrapper]: 4, 28, 35, 65, 66, 184, 185, 194, 201, 215, 260, plus two sites with a register variable. SF get ids [seen]: 184, 194, 201, 211, 212, 260.

The donor set function has an early check for ids 236, 241 and 257 (extra handling before the switch) [seen]; its purpose is [unknown].

## A.3 Service lookup per caller

Legend: "cache" = whether the caller keeps a null result.

| caller | how it looks up | blocks? | cache of null | when absent |
|---|---|---|---|---|
| `AidlDisplayPanelFeature` (services.jar) | `ServiceManager.getService("...IDisplayPanelFeature/default")` | No (Java `getService` does not wait) [inferred] | No: every call looks up again | `isAvailable()` false |
| `HidlDisplayPanelFeature` (services.jar) | `IDisplayPanelFeature.getService()` (name "default", no retry flag) | No: not declared in VINTF, so libhidl returns at once ("getTransport: Cannot find entry" in hwservicemanager) [seen in module/README] | No: every call looks up again | Exception caught, log `HidlDisplayPanelFeature: getHidlDisplayPanelFeatureService error`; `isAvailable()` false |
| `OplusDisplayPanelFeatureHelper` (services.jar) | AIDL first, then HIDL, on **each** call | No | No | Set: silent no-op. Get: null / -1 / "" / null array. Log `AidlDisplayPanelFeature` has no error line for a null binder; the HIDL error line shows on every call. |
| `OplusFeatureMEMCDSR` | `ServiceManager.getService(AIDL name)`, own copy; retry when null | No | No | logs `sDisplayPanelFeature is null`, `DisplayPanelFeature is null`; skips DSR |
| `OplusFakeImageLayerExtImpl` | HIDL `getService()` only | No | No | exception caught; log `iDisplayPanelFeature err : ` / ` iDisplayPanelFeature == null`. It also sends SF transaction 20005 first (this part works) |
| SystemUI `SmoothTransitionController` | HIDL `getService()` in three helper functions; one log says `setDisplayPanelFeature aidl` | No | No | logs `getDisplayFeature error: `, `getDisplayPanelFeatureHidl error: `, `displayPanelFeature is null or empty!` |
| SystemUI `KeyguardFeatureOption` | AIDL by `ServiceManager.getService` first, HIDL `getService()` as fallback | No | No | logs `getDisplayFeature error: `, `Read FP IDisplayPanelFeature exception : ` |
| SystemUI `OnScreenHighLightControl` | HIDL `getService()` only | No | No | logs `getDisplayFeature error: `, `achieve displayPanelFeature failed` |
| SystemUI `OplusOSAodManager`, `OplusAODRefreshRateController` | HIDL `getService()`; `OplusOSAodManager` also AIDL via `ServiceManager.getService` | No | No | exception caught |
| PostmanService | `com.oplus.wrapper...ServiceManager.getService(AIDL name)` | No | No | `getDisplayPanelFeatureValue` logs; factory tool only |
| OplusCommercialEngineerMode | AIDL by `ServiceManager.getService`, HIDL fallback | No | No | logs `achieve displayPanelFeature failed`; engineer tool only |
| `WatchdogExtImpl` | lists the AIDL name prefix as an "interface of interest" for the watchdog | No | n/a | nothing (list entry only) |
| SurfaceFlinger (`/system/bin/surfaceflinger`) | AIDL `AServiceManager_checkService` + `fromBinder`; death recipient; then HIDL `getService(name, getStub=false)`. Wrapper functions for set, get and info ids | No: `checkService` does not wait; the HIDL call is not retried because the HIDL name is not declared [inferred] | Possibly not: the lookup function runs at the start of each wrapper [inferred] | Logs `Failed to get AIDL/IDisplayPanelFeature Service.` and `Failed to get HIDL/IDisplayPanelFeature Service.` (debug level), then `%s displayPanelFeature is NULL` (warning) and the call returns -38 (ENOSYS) |
| `libsensorserviceextimpl.so` (class `AidlDisplayPanelFeature` / `HidlDisplayPanelFeature`) | `AServiceManager_checkService`; HIDL `getService(name, false)`; death recipient | No | n/a | `%s displayPanelFeature is NULL`, `%s getDisplayPanelFeatureValue failed, returnValue = %d` |
| `lib_inputflingerEx.so` | `get_sau_mode_aidl` uses `checkService`; `get_sau_mode_hidl` uses HIDL `getService`; `getStatbilityHalService` is another HAL | No | n/a | `%s getDisplayPanelFeatureValue failed, returnValue = %d` |
| `horae` (system_ext daemon, `horae.rc`) | `AServiceManager_isDeclared` + `checkService`; HIDL `getService(name, false)` | No | n/a | `displayComp %s displayPanelFeature is NULL`, `displayComp %s getDisplayPanelFeatureValue failed` |
| `libcwb_client.so` | Imports the HIDL `getService` of this interface (use in `CwbClient::getCwbService`, purpose unclear). The AIDL part (`getCwbService_aidl`) is for ICwbService: `isDeclared` then `AServiceManager_getService` | `AServiceManager_getService` **waits up to 5 s** when the name is declared but not registered [inferred from libbinder] | n/a | CWB client unusable |
| Donor vendor libs `libsdmcore.so`, `libdtlm.so`, `libdisplayaidlapis.so` | AIDL `fromBinder` on a fetched service | n/a: pipa uses its own vendor | n/a | Not relevant. They do not exist on pipa's vendor. |

Log lines that show on pipa today: `HidlDisplayPanelFeature: getHidlDisplayPanelFeatureService error` (every Java call), `hwservicemanager: getTransport: Cannot find entry vendor.oplus.hardware.displaypanelfeature@1.0::IDisplayPanelFeature/default ...`, SF `Failed to get AIDL/IDisplayPanelFeature Service.`, `... HIDL ...`, `displayPanelFeature is NULL`; `OplusFakeImageLayerExtImpl: iDisplayPanelFeature err : ...`; SystemUI `getDisplayFeature error: ...`.

## A.4 Features lost or limited on pipa because the HAL is missing

Status "port" = what the port already does (AGENTS.md, ARCHITECTURE.md).

| user feature | id / path | effect on pipa | port work-around |
|---|---|---|---|
| Game Filter and colour enhancement back end | 4 (seed) + SF 23114 (colour mode); SF 22031 | The panel part does nothing. | 3f: `PipaGameFilter` sets a colour matrix through `DisplayTransformManager`. 2x makes SF not wait for the OPPO display HALs. |
| Colour mode (Vivid / Natural / Standard) | 4, SF 23114 | Seed write is dropped. | 3q, 3r: QDCM XML (`standard_hdr`, `hal_native`) |
| Eye Protect / Bedtime tint and CCT | not a displaypanelfeature id [inferred] | Works through the framework colour path. The older README (module section 11) blamed this HAL; that needs a log check (Open question 1) | 3f patch of the Eye Protect app; 3s adaptive tone from `front_cct_strm` |
| Reduce White Point | 249 | Panel part dropped | none seen |
| Read Mode | 35 | Panel part dropped | none seen |
| Game Eye Care (dark eye protect) | 228 | Panel part dropped | none seen |
| DC dimming / low-brightness flicker setting | 23, 199, 201, 220 | Settings may show the options; the writes are dropped | none (pipa has its own backlight path) |
| HBM, FP press, UDFPS dim layer | 12, 22, 28, 211 | Not needed on pipa (no under-display sensor). 211 failing is the correct "no FOD" answer | none |
| Touch-idle refresh drop (OTI-HW) | no id; blocked by a nit threshold | Fixed without the HAL | 2z: `oplus_vrr_config.json` (nit limits -1) |
| Dynamic TE, ADFR, pulse, LTPO AOD | 194, 232-234, 260, 264, 265, 195 | Features off ("not supported") | none needed |
| Fake image layer (edge decoration) | 22 (HIDL) + SF 20005 | The SF part works; the id-22 write fails with a caught exception | none |
| CABC setting | 184 | Setting has no effect | none |
| Panel info in Settings / About | 9, 11, 251 | Manufacture string and production time are empty or null | none |
| Demura, deburn-in, FOSS, UIR, DSR | 225, 226, 236, 241, 244, 255-258 | Off | none needed |
| ALS compensation for the dim layer (sensor service ext) | 6, 13, 14, 22, 29, 34 | Native get fails; code takes its failure path | none |
| AOD / doze on the panel | 7, 192, 195, 213, 217, 265 | AOD hardware paths dropped | pipa has its own AOD/doze handling (not checked) |
| Silent reboot flag | 20 | read = -1 | none |

## A.5 Stub plan: what pipa can implement and what a stub must answer

### A.5.1 What pipa has [seen in repo notes]

- `DisplayTransformManager` colour matrix (SF transaction 1015) and SF saturation (1022). The port uses both (3f Game Filter, accessibility test).
- QDCM / PCC / GC through the composer and `vendor.display.color@1.0` (3q, 3r).
- `/sys/class/backlight/panel0-backlight/{brightness,max_brightness}` (linear 4095 scale, `module/README.md`).
- Xiaomi `vendor.xiaomi.hardware.displayfeature@1.0` (parked, test layer 2y showed no visible change).
- It does **not** have the OPPO nodes `/sys/kernel/oplus_display/*`, `/dev/oplus_display`, or the OPPO-specific qservice commands (60, 64, DYNAMIC_DEBUG variants) [inferred: the nodes belong to the OPPO kernel and OPPO libsdm].

### A.5.2 Per id class

| class | ids | answer |
|---|---|---|
| Implementable | 8, 29 (read backlight), 9 and 11 (panel strings), 35 (read mode matrix), 228 and 249 (dim/warm matrix) | M. Needs a small service that talks to SF/`DisplayTransformManager`. Keep the last value for get. |
| Constant answer, safe | 5, 6, 13, 14, 20, 34, 69, 179, 183, 211, 212, 233, 247, 264 | status 0 and zeros. Zero is "not supported" for the support probes (211, 233, 264, 69). |
| Accept and ignore (store) | 4, 7, 18, 22, 28, 68, 184, 185, 186, 192, 194, 195, 199, 201, 210, 213, 217, 234, 235, 245, 246, 260, 265, 267 | status 0; keep the value in memory, return it on get. |
| Unsupported | 1-3, 10, 12, 15-17, 19, 21, 23-27, 32, 33, 66, 215, 220, 225-227, 232, 236, 239-243, 255-259, 262, 263, 266 and every unknown id | status -1, array untouched. The donor service does the same for ids that have no case (log "default, no choice!"). |

Ids 23 (DC backlight) and 220/225/226 are `U` because pipa has no equivalent. If a later change gives DC dimming through the backlight path, move 23 to `M`.

### A.5.3 Rules the stub must follow

Note: section 4.2 replaces rules 1 and 2. Use a system-stability binder with no VINTF entry, as the touch shim (4o) does.

1. **Register AIDL only**, name `vendor.oplus.hardware.displaypanelfeature.IDisplayPanelFeature/default`, with VINTF stability. The Java helper tries AIDL first, so HIDL callers keep failing as today (no worse). Do not add a HIDL manifest entry. If HIDL is declared and no HIDL service runs, libhidl `getService` waits for the registration [inferred from libhidl] and a thread can hang in the callers that call it from a main path (SystemUI, system_server). [inferred]
2. **Declare in the VINTF manifest only if the service always runs before system_server.** `libcwb_client` calls `AServiceManager_isDeclared` then `AServiceManager_getService`. For a declared but missing name, `getService` waits up to 5 s. Other native users call `checkService` and do not wait. The Java users do not wait.
   - Alternative: register a name without a manifest entry. Then `isDeclared` is false and `checkService` still finds the service. This is a design choice to test ([unknown] whether servicemanager accepts a vendor-stability name without a manifest entry on pipa).
3. **Get must fill the array.** Return the requested length (the AIDL server gets it zero-filled). Return status 0 with zeros for "probe" ids so that callers see "not supported" without an error log. Return -1 for unknown ids.
4. **Set must return an int.** Return 0. Java callers ignore it. SF logs a failure if it is negative.
5. **getDisplayPanelInfo must fill the list.** Return status 0 and a list with one string (empty is fine). A null list gives null in `getDisplayPanelInfoAsString`; some callers do not check for null [unknown which].
6. **Must answer these** because they run in loops or on hot paths: SF ids 4, 184, 194, 201, 260 (set and get); `libsensorserviceextimpl` ids 6, 13, 14, 22, 29, 34 and info 9 (ALS code path); id 211 (FOD probe; must say "no FP type"); `lib_inputflingerEx` id 20.
7. **Ids with the high bits** (`0x1000` and up): mask with `0xFFF` first. Answer the sub panel as "not present" (status -1) because pipa has one panel.
8. Death recipients: SF and the sensor ext lib link to death and look up again. A stub that restarts must register the same name again. Keep the process alive (`class hal`, restart policy default).
9. SELinux: a new service name needs a `service_contexts` entry (the donor label is `oplus_hal_displaypanel_service`; HIDL label `oplus_hal_displaypanel_hwservice`) and an `add`/`find` rule for system_server, SF, SystemUI. This is the port policy in `maintainer/sepolicy/` [inferred]; compile it with `secilc` as AGENTS.md demands.
10. Cost/benefit: a pure "answer" stub removes log noise and per-call lookups in SF and system_server; it does not add a user feature. A user-visible gain needs the `M` ids (35, 228, 249).

## A. Open questions (displaypanelfeature)

1. **Eye Protect CCT.** No displaypanelfeature id carries CCT or RGB gains in the C.07 callers. Which id raised the `getHidlDisplayPanelFeatureService error` line in the log of 2026-10-21 (module README section 11)? Candidates: 4 (seed), 249, 35, 228. Capture the stack with `setprop log.tag.HidlDisplayPanelFeature V` and the call order, or search for `setDisplayPanelFeatureValue +++, ID:` (debug log of the helper). The helper prints the id for each set.
2. **Which ids does SF call per frame?** The set wrapper has 14 sites. Check the rate on a running device (`logcat -s SurfaceFlinger | grep displayPanelFeature`).
3. **`horae`** gets one id from a register. The value is not decoded. Constants 32, 98 and 255 are near the code. [unknown]
4. **`libcwb_client`** imports the HIDL getService of this interface. Why? [unknown]
5. **Id 83** (`ColorModeConfig.getDevInfo`, info) and ids 4107/4165 have no case in the info/get switches; they reach the "_Ext" default handler. What does it return? [unknown]
6. **Panel id use (id 5)** in `OPlusOnlineConfigManager` and `OPlusExternalRefreshRateManager`: is `DEFECT_PANEL_MODE_ENABLE` true on pipa? If true, a null list may disable a VRR path. [unknown]
7. **Settings app**: there is no Settings dump hit. Settings reads panel data through `OplusDisplayManagerServiceEnhance` (`getScreenMultiBitsSupport`, `getScreenProductionTime`) [seen]. Does Settings show an item that is hidden because these calls fail? [unknown]
8. **Declared-but-missing behaviour** (rule 2 above) rests on libbinder and libhidl source knowledge, not on a test on pipa. [inferred]
9. **C.06 against C.07.** Compare the id set with the C.06 service before you ship. A new id could appear in a new donor; run the id extraction again on each donor change.
10. **Vtable slot map** of the NDK interface: only slot +0x30 = get is confirmed. The other slots are [inferred].


# Part B: MixLut3D, displaycolorfeature, mmdisplayfeature, cwb, Iris

## B.0 Key finding: who provides these services on the donor

- There is no standalone service binary for MixLut3D or displaycolorfeature. [seen]
- Both are AIDL services that live inside the Qualcomm composer process, as plugins of the "snapdragoncolor" stack. [seen]
- `vendor/etc/snapdragon_color_libs_config.xml` lists the plugins in order: 1 `libsnapdragoncolor-qdcm.so`, 2 `libPanelChaplin.so`, 3 `libstc_color_feature.so`. [seen]
- `libsnapdragoncolor-manager.so` and `libsdmcore.so` (composer side) load them. The exact `dlopen` site was not traced. [inferred]
- Two files are named `libPanelChaplin.so`:
  - `vendor/lib64/libPanelChaplin.so` (35 KB): a thin `StcOemImpl` shim. It exports `GetScPostBlendInterface` and needs `libPanelChaplin.so`. [seen]
  - `odm/lib64/libPanelChaplin.so` (316 KB): the real code. It has `PanelChaplin::initAidlService`, class `PanelChaplin::MixLut3DAidl`, and imports `AServiceManager_addService`. It reads `odm/etc/PanelChaplin/*` (3D LUT text files, `Dark_Eye_Protect_*.txt`, `Game_*_Fliter.txt`) and `/data/vendor/display/*`, `/mnt/vendor/persist/display/*.odf`. [seen]
- `odm/lib64/libstc_color_feature.so` (118 KB) has `BnDisplayColorFeature` plus `AServiceManager_addService`. It implements `OplusColorUnify::set/getDisplayColorFeatureValue`, `OplusStc` and `LocalEyecare::setStcFeatureValue`. It reads `odm/etc/displaycolorfeaturecfg.xml` (file not present in the donor tree). [seen]
- Consequence for pipa: pipa keeps the beta4 `vendor` and `odm` (ARCHITECTURE.md lines 14, 23). Those have no snapdragoncolor plugin list entry for these libs. So the services cannot exist on pipa unless the port adds a new process. [inferred]
- The donor plugin libs link the donor SDM colour ABI (`libsdm-color.so`, `libqservice.so`, `libdisplaydebug.so`). They are not usable with the pipa SDM stack. [inferred]
- SELinux/service names for the donor (`odm/etc/selinux/precompiled_service_contexts`, `vendor/etc/selinux/vendor_service_contexts`): [seen]

| Instance | SELinux type |
|---|---|
| `vendor.oplus.hardware.display.MixLut3D.IMixLut3D/default` | `hal_oplus_display_mixlut3d_service` |
| `vendor.oplus.hardware.displaycolorfeature.IDisplayColorFeature/default` | `oplus_hal_displaycolor_service` |
| `vendor.oplus.hardware.cwb.ICwbService/default` | `hal_cwb_service` |
| `vendor.pixelworks.hardware.display.IIris/default` | `hal_display_iris_service` |
| `vendor.pixelworks.hardware.feature.IIrisFeature/default` | `hal_feature_irisfeature_service` |
| HIDL `vendor.oplus.hardware.mmdisplayfeature::IMMDisplayFeature` | `hal_omdisplay_hwservice` |
| HIDL `vendor.oplus.hardware.cwb::ICwbService` | `hal_cwb_hwservice` |
| HIDL `vendor.pixelworks.hardware.display::IIris`, `feature::IIrisFeature` | `hal_display_iris_hwservice` |

- Other composer init facts: `vendor.qti.hardware.display.composer` runs `/vendor/bin/hw/vendor.qti.hardware.display.composer-service` with `onrestart restart surfaceflinger`. [seen] The `vendor.qti.hardware.display.color-service` (IDisplayColor, IDisplayPostproc) is a separate process and does not load the OPPO plugins. [seen]
- A pipa stub for any of these must therefore be a new process (for example under `pipa_port`) that registers the name, plus a VINTF fragment and an SELinux type. [inferred]

## B.1 display.MixLut3D (IMixLut3D)

### Interface
- AIDL, stable. V1 (`set`, `sencept`) and V2 (adds `getDisplayLut`). The manifest declares V2: `vintf_manifext_aidl_panelchaplin.xml`. [seen]
- Descriptor: `vendor.oplus.hardware.display.MixLut3D.IMixLut3D`. Parcelables in V2: `Luts`, `LutProperties` (field names not recovered). [seen]
- Transaction codes (from `mov w1,#N` before `AIBinder_transact` in the `Bp` methods): [seen]

| Code | Method | Parcel (in -> out) |
|---|---|---|
| 1 | `int set(int, int)` | two int32 -> int32 result (the NDK signature has `int*` as return) |
| 2 | `int sencept(int cmd, int n, int[] data, out int[] res)` | int32, int32, int32[] , int32 length of out array -> int32 result, int32[] |
| 3 | `getDisplayLut(int display, out Luts)` (V2 only) | int32 -> Luts parcelable |

- Java stub (`vendor.oplus.hardware.display.MixLut3D-V1-java.jar`, also inside `oplus-services.jar`) has the V1 methods only. [seen]
- Test binary `MixLut3DTest` builds against V1, uses `waitForService`, prints `CMD[%d] = %d`. [seen]
- Meaning of `sencept` data in the Java caller: `[ambientColorEnable, x*10000, y*10000, screenCCT, duration]` with `cmd=screen id`, `n=1`. [seen]
- Aging update (RUS) calls `sencept(110, 110, {0})`. [seen]

### Provider on donor
- `libPanelChaplin.so` inside the composer (section 0). [seen]

### Callers and null handling

| Caller | How it gets the service | On null | Feature |
|---|---|---|---|
| `surfaceflinger`: `OplusSurfaceFlinger::fetchPanelLuts(int)` lambda (call_once, `__call_once_proxy`) | `AServiceManager_waitForService` (blocks) then `IMixLut3D::fromBinder`; call site `0x3d0344` | logs a warning and returns; no crash [seen] | panel LUT data for display id |
| path to it | `SurfaceFlinger::setScreenshotDisplayState` (call `0x259d98`) -> `OplusSurfaceFlinger::getPanelLuts(int)` -> `fetchPanelLuts` | | screenshot / colour-managed capture path [inferred] |
| `oplus-services.jar` `OplusLutController.getMixLut3DInterface` | `ServiceManager.checkService` | logs "Failed to get MixLut3D interface." and returns | ambient colour temperature LUT, only if feature `oplus.software.display.intelligent_color_temperature_lut_support` is set |
| `oplus-services.jar` `OplusDisplayAgingUpdateHelper$DisplayAgingUpdateInfo.sendCmd2MixL` | `ServiceManager.checkService` | returns -1 | panel ageing compensation from RUS |

- `OplusLutController` is created by `DisplayColorController`; `mSupportLutColor` comes from `OplusDisplayFeatureConfig.isSupportLut()`. That flag is not set in any donor feature file I searched (`my_product/etc`, `my_stock/etc`, `my_manifest/etc`, `odm/etc`). So the Java LUT path is probably off. [inferred]
- The 2x patch changes the SF `waitForService` here to `checkService`. [seen in repo doc]

### Features lost on pipa
- Panel 3D LUT readout for screenshot/colour paths. [inferred]
- Ambient colour LUT (not enabled anyway). [inferred]
- Ageing compensation. Pipa panel is not the OPPO panel; no loss. [inferred]
- The "Game Filter" freeze (BUGS row 22 / 3j) was this service: the SF main thread blocked in `fetchPanelLuts`. Fixed by 2x. [seen in repo doc]

### Stub feasibility
| Method | Possible on pipa? |
|---|---|
| `getDisplayLut` | Not useful. Pipa has no OPPO panel LUT files. Returning empty `Luts` is unverified for SF. Safest: leave the service absent (the null path is tested live). [inferred] |
| `sencept` (ambient colour) | Could map to the `DisplayTransformManager` matrix, but the caller is off (flag). The adaptive tone work (3s, `front_cct_strm`) already does this. Return an error code. [inferred] |
| `set` | No known caller on the system side. Return 0. [inferred] |

## B.2 displaycolorfeature (IDisplayColorFeature)

### Interface
- AIDL V1 only. Descriptor `vendor.oplus.hardware.displaycolorfeature.IDisplayColorFeature`. [seen]
- Codes: [seen]

| Code | Method | Parcel |
|---|---|---|
| 1 | `int getDisplayColorFeatureValue(DisplayColorFeatureType type, out int[] values)` | enum int32 -> int32[], int32 result |
| 2 | `int setDisplayColorFeatureValue(DisplayColorFeatureType type, in int[] values)` | enum int32, int32[] -> int32 result |

- Enum `DisplayColorFeatureType` values recovered from `displaycolorfeature_test` strings: PostBlendPCC=1, PostBlendPa=2, PostBlendDither=3, PostBlendPaDither=4, PostBlendDE=5, PostBlendGC=6, PostBlendGamut=7, PostBlendIGC=8, kStcDebugEnable=19, ClstcDetailEnhancer=20, ClstcIgcFeature=21, ClstcCscFeature=22, ClstcGcFeature=23, ClstcdLutFeature=24, kClstcDebugEnable=30. Value 0 = FeatureDisable, 1 = FeatureEnable. The list may be incomplete. [seen, partial]
- The test tool text says it can disable the PCC block ("displaycolorfeature_test 1 0"). So the interface toggles SDM post-blend blocks. [seen]

### Provider on donor
- `libstc_color_feature.so` inside the composer (section 0). [seen]

### Callers and null handling
| Caller | Get method | On null | Feature |
|---|---|---|---|
| `surfaceflinger` `Sharpness::handleSharpness(uint)` (call `0x3fd2b8`), run by `Sharpness::SharpnessMessageHandler::handleMessage` | `waitForService` | log "can not get IDisplayColorFeature!", skip [seen] | display sharpness (scene/app hit: `onDispSceneHit`, `onDispSceneExit`, `postSetSharpness`). Switch from Settings key `customize_resolution_display_sharpness_switch` via SF transaction 24000 (`OplusFeatureSharpness` in `oplus-services.jar`). [seen] |
| `surfaceflinger` `OplusSurfaceFlinger::updateColorSpaceValue(int, vector<int>)` (call `0x3c5234`) | `waitForService` | log "Can not get IDisplayColorFeature !", return [seen] | colour space value update, called from `OplusSurfaceFlinger::onTransact` with type 2, 6 or 7 plus an int and an int vector. The transaction code was not resolved. [seen, code unknown] |

- No Java caller found in `oplus-services`, `fw`, `Settings`, `SystemUI`, `OplusGames` dumps. [seen: grep]
- Both SF waits are patched to `checkService` by 2x. [seen in repo doc]
- The `waitForService` is not under the SF main thread in the first case (Sharpness looper thread). The second runs on a binder thread of SF. [inferred]

### Features lost on pipa
- Hardware sharpness enhancement (`Sharpness` scene feature). Pipa has no equivalent in the SF path. The Settings switch has no effect. [inferred]
- OPPO "colour space value" update from `onTransact`. [inferred]

### Stub feasibility
| Method | Possible on pipa? |
|---|---|
| `setDisplayColorFeatureValue` | Types 1-8 are SDM post-blend block toggles. QDCM/`display-color-hal-1-0` may allow PCC/GC/dither switches. The semantic (which value means what for sharpness) is unknown. Return "unsupported" status. [inferred / unknown] |
| `getDisplayColorFeatureValue` | Return an error or an empty vector. [inferred] |

## B.3 mmdisplayfeature (IMMDisplayFeature)

### Interface
- HIDL `vendor.oplus.hardware.mmdisplayfeature@1.0::IMMDisplayFeature`, instance `default`. Lib: `system_ext/lib64/vendor.oplus.hardware.mmdisplayfeature@1.0.so`. [seen]
- Methods seen in the proxy: `setFeatureValue`, `getFeatureOn`. Argument types not recovered. [seen, partial] HIDL codes follow declaration order starting at 1 (assumption, not verified). [unknown]
- Declared in the donor system compatibility matrix (`system/etc/vintf/compatibility_matrix.device.xml`) only as a requirement. No vendor/odm manifest of the donor declares it, and no service binary exists. [seen]
- SELinux: `hal_omdisplay_hwservice` in `vendor_hwservice_contexts`. [seen]

### Provider on donor
- [unknown]. No binary found. Likely a MediaTek-origin interface that this SM8250/Qualcomm donor does not use. The "MM" naming is an assumption. [unknown]

### Callers and null handling
| Caller | Get method | On null |
|---|---|---|
| `surfaceflinger` `OplusDEE::bootFinish()` (call `0x40fcec`), run from `OplusSurfaceFlinger::bootFinish` <- `SurfaceFlinger::bootFinished` | HIDL `getService(name, false)` | log "Failed to get HIDL/IMMDisplayFeature Service."; no crash [seen] |
| `surfaceflinger` `HidlDisplayPanelFeature::getService(int)` (call `0x440ed4`) | same | -> panelfeature |
| Native libs with the string only: `libphoenix_native.so`, `liboplusextstability.so`, bootstrap `linker` | namespace/library lists | not calls [inferred] |

- The HIDL `getService(name, bool)` call passes `false` for the second argument (register `w1` = 0 before the call). Whether it blocks depends on the manifest. A HIDL service that is not declared in any manifest returns null at once, but a declared and absent service waits. This is what I expect from libhidl, not verified here. [inferred]
- pipa boots with no change to this call (inventory row), so pipa's manifests do not declare it. [inferred]

### Features lost / stub
- "DEE" feature in `OplusDEE` (name not expanded; likely a dynamic enhancement function). Lost on pipa. [unknown]
- Stub: not needed. Do not declare it in the pipa manifest. [inferred]

## B.4 cwb (ICwbService)

### Interface
- AIDL V2 (manifest `manifest_oplus_cwb_aidl.xml`), V1 also present. Plus HIDL `vendor.oplus.hardware.cwb@1.0::ICwbService`. [seen]
- AIDL V2 codes (declaration order, checked with `Bp` bodies: `getRGBValue`=1, `getCwbPostProcessStatus`=4, `enable`=8, `initializeSharedMemory`=13, `releaseSharedMemory`=16): [seen]

| Code | Method |
|---|---|
| 1 | `getRGBValue(Rect, out Rgb, out Error)` |
| 2 | `getLumasValue(Rect, out float[], out Error)` |
| 3 | `getHistogramValue(Rect, out Histogram, out Error)` |
| 4 | `getCwbPostProcessStatus(out bool)` |
| 5 | `setCwbPostProcessStatus(bool, out Error)` |
| 6 | `registerCallback(ICwbCallback, out Error)` |
| 7 | `unregisterCallback(ICwbCallback, out Error)` |
| 8 | `enable(out bool)` |
| 9 | `disable(out bool)` |
| 10 | `setDebug(int[], out Error)` |
| 11 | `getCwbValue(int, Rect, out int[], out Error)` |
| 12 | `setCwbValue(int, Rect, in/out int[], out Error)` |
| 13 | `initializeSharedMemory(int, int, ScopedFileDescriptor, out Error)` |
| 14 | `getSharedData(int, Rect, ScopedFileDescriptor, int, out int[], out Error)` |
| 15 | `getScreenResolution(int, out int[], out Error)` |
| 16 | `releaseSharedMemory(int, int, out Error)` |

- Codes 2, 3, 5-7, 9-12, 14, 15 follow the declaration order of the `Bp` symbols and were not each checked by disassembly. [inferred]
- Callback `ICwbCallback.onAvailableStatusChanged(bool)`. The V1 lib lacks methods 13-16. [seen]
- HIDL V1_0 methods (Java dump): enable, disable, getCwbBuffer, getRGBValue(s), getHistogramValue, getLumasValue, registerCallback, setCwbPostProcessStatus (from the step-1 inventory row). [seen]
- "CWB" = concurrent write-back of the composed frame (the SDM write-back path). The provider code has `prepareCwbBuffer`, `calcPixelsRGB`, `updateAvailableConfigs`. [seen]

### Provider on donor
- `vendor/lib64/libcwb_qcom_aidl.so` implements `aidl::...::cwb::implementation::CwbService` and imports `addService`. It needs `libqservice.so`, `libdisplayconfig.qti.so`, composer3. `libsdmclient.so` references the cwb AIDL; it is the likely loader in the composer. [seen / inferred]
- `odm/bin/hw/vendor.oplus.hardware.displaypanelfeature-service` also imports `addService` and holds the cwb instance string. It may register the cwb service itself or only call it. -> panelfeature, [unknown]
- Test binary: `odm/bin/cwb_utils_aidl`. [seen]
- Init: no separate rc for cwb. [seen]

### Callers and null handling
| Caller | Get method | On null |
|---|---|---|
| `surfaceflinger` `OplusRegionSamplingThread::getCwbService_aidl()` (calls `AServiceManager_isDeclared` `0x3a6ecc`, then `AServiceManager_getService` `0x3a6edc`) | declared check, non-blocking `getService` | falls back to HIDL [seen] |
| `surfaceflinger` `OplusRegionSamplingThread` constructor (HIDL `getService(name,false)` `0x3a733c`) and `captureSampleCwb()` (`0x3a7bb8`) | HIDL | no sample, caller keeps old path [inferred] |
| `services.jar` `WifiDisplayAdapter.setCwbEnabled(Z)` | HIDL `ICwbService.getService()` | logs "No Cwb service fetched." [seen] |
| `theia_screen_monitor` (`system_ext/bin`), `libtheiahelper.so`, `libcwb_client.so` | `waitForService` | blocks that daemon only [seen in repo inventory] |
| `midasd`, `ostats_pullerd`, `libsensorserviceextimpl.so` | link the lib | [unknown] |

- The SF AIDL path uses `isDeclared` first, so it never blocks. [seen]

### Features lost on pipa
- CWB-based region sampling for the SF colour/luma decisions. [inferred]
- Wi-Fi display (Miracast) write-back enable. The Java code logs and continues. [inferred]
- Screen monitor (blank/black screen detection, `theia_screen_monitor`). Not user visible. [inferred]

### Stub feasibility
| Method | Possible on pipa? |
|---|---|
| `enable`/`disable`/`get*PostProcessStatus` | Yes: return false/OK. [inferred] |
| `getRGBValue`/`getLumasValue`/`getHistogramValue` | Real data needs frame write-back on the Qualcomm composer: not available through the pipa vendor HAL. Return an `Error` value for "unsupported". The exact `Error` enum values were not recovered. [unknown] |
| `registerCallback` | Store or ignore. [inferred] |
| `initializeSharedMemory`/`getSharedData`/`getScreenResolution` | Unsupported. [inferred] |
- Priority: LOW. Nothing a user sees depends on it. Do not declare it in the pipa manifest. Then SF's `isDeclared` check fails and the daemons that wait stay blocked or off. [inferred]

## B.5 Pixelworks IIris / IIrisFeature

### Interface
- AIDL `vendor.pixelworks.hardware.display.IIris` (lib V3, large: about 45 methods) and `vendor.pixelworks.hardware.feature.IIrisFeature` (lib V2: `getFeature(out int)`, `getFeatures(out int[])`). Callbacks `IIrisCallback`, `ISoftIrisClient`. Plus HIDL `display@1.0-1.2`, `feature@1.0-1.2`. [seen]
- `IIris` examples: `initialize`, `irisConfigureSet/Get/Batch/Buffer`, `setColorTransform(float[])`, `setColorModeWithRenderIntent`, `presentDisplay`, `panelReadWrite`, `updateDisplayBrightness`, `registerCallback`. It mirrors a full composer. [seen]

### Provider on donor
- A vendor-side HAL for an external Pixelworks Iris chip (`vendor/lib64/libpwirishal.so`, `libpwirisfeature.so`, `libpwirishardware_ext.so`). No `iris` service binary in `vendor/bin/hw`; no rc entry; no VINTF entry in the donor vendor manifest (my grep found no `pixelworks` in `vendor/etc/vintf`). So even the donor device may not run it. [seen]

### Callers and null handling
| Caller | Get method | On null |
|---|---|---|
| `surfaceflinger` `pxlw::IrisHal::createHalImpl(bool)` (`AServiceManager_isDeclared` `0x42a9c4`), `IrisHalAidlImpl` ctor (`isDeclared` `0x42ae08`) then `IrisHalAidlImpl::initialize` (`waitForService` `0x42ae88`) | declared check first | "IIris AIDL is not declared" [seen] |
| `pxlw::IrisFeatureHal::createHalImpl`, `IrisFeatureHalAidlImpl` ctor (`isDeclared` then `waitForService` `0x42be64`) | declared check first | "IIrisFeature AIDL is not declared" [seen] |
| HIDL fallbacks `IrisHalHidlImpl` (`0x42b554`), `IrisFeatureHalHidlImpl` (`0x42c210`) | `getService(name,false)` | [inferred] null |
| `checkIrisVersion()`, `SurfaceFlinger::dumpPwIrisInfo` | call `createHalImpl` | dump only |
| Java `com.pixelworks.hardware.IrisHalAidlImpl` (in `services.jar`) | `isDeclared()` then `waitForDeclaredService` | "IIris service is not declared." [seen] |
| `Iris5Util` (Settings, SystemUI), `OplusMemc*` (`oplus-services`), `OplusGames` frame insert, `COSA` frame insert | gated by `oplus.software.display.pixelworks_x7_enable`, `..._x7p_enable`, `memc_enable`, `memc_frc_support`, `game.memc_enable` | flags not found in donor feature files [seen: grep, no match] |

- 2x patches the SF `IIris` `waitForService` to `checkService`, and keeps the `IComposer` and `IIrisFeature` waits. The `IIrisFeature` wait is reached only after `isDeclared` is true. [seen in repo doc]

### Features lost / stub
- Video super resolution ("Iris5") and MEMC frame interpolation by the Pixelworks chip. Pipa has no chip. [inferred]
- Stub: none. Never declare either name on pipa, or SF would wait/call into it. [inferred]

## B.6 Other display-related OPPO HALs seen on the system side

| HAL | Where | Note |
|---|---|---|
| `IDisplayPanelFeature` (AIDL V1 + HIDL) | SF, `services.jar`, `oplus-services.jar`, SystemUI, OplusGames, inputflinger ext, horae | -> panelfeature. Game Filter and colour enhancement run via SF transaction 22031 -> feature 35 (from `PipaGameFilter.java` header). |
| `IGameOptHalService` | SF `OplusGameOpt::checkService()` (`checkService`) | not display colour. Null-safe by name. |
| `IPerformance` | SF `OplusSurfaceFlinger::getPerformanceInterface()` (`checkService`) | not display colour. |
| `IOplusLights` (`vendor.oplus.hardware.opluslights`) | `oplus-services.jar` | LED/lights path; relation to the backlight is [unknown]. |
| QTI `IDisplayConfig`, `IQtiComposer3Client` | SF | Qualcomm side, present on pipa. |
| `oplusSensor` `ISensorFeature` | `OplusCommercialEngineerMode`, sensors | not display. |

- SF also has SF transaction 23114: it reads one int and stores it in an `OplusSurfaceFlinger` field at offset `0x31c`. [seen] I could not link it to a HAL call from the disassembly. The Game Filter seed role from the task text is not confirmed here. [unknown]

## B.7 Must-answer calls for a stub

Today (with 2x) the answer is: none. SF handles a null binder at every site listed above, and the Java callers use `checkService` or `isDeclared`. [seen / inferred]

If a future change registers any of these names, then SF threads call it with no timeout. The stub must answer all of these at once, with no blocking and no binder call back into SF:
- IMixLut3D `getDisplayLut` (code 3): SF screenshot path via `fetchPanelLuts`, call_once. A bad answer sticks for the SF lifetime. [inferred]
- IDisplayColorFeature `setDisplayColorFeatureValue` (code 2): `Sharpness` looper thread and the binder thread in `updateColorSpaceValue`. [seen]
- ICwbService `enable`, `disable`, `registerCallback` (codes 8, 9, 6): SF `OplusRegionSamplingThread`. [inferred]
- IIris/IIrisFeature: never register. SF would run `initialize` and a full Iris setup on top of it. [inferred]
- IMMDisplayFeature (HIDL): never declare.

## B.8 Open questions

1. Which SF transaction code reaches `updateColorSpaceValue` (type 2, 6, 7)? Needs the switch/jump table in `OplusSurfaceFlinger::onTransact` at `0x289488`. [unknown]
2. Layout and field names of `Luts`/`LutProperties` and the `cwb::Error` enum values. They need a `toString` or the AIDL hash source. [unknown]
3. Does a HIDL `getService(name,false)` block for a service that is declared in the manifest but absent? Check against the pipa vendor manifest (read-only repo has no copy). Same for Java `ICwbService.getService()` in `WifiDisplayAdapter`. [unknown]
4. Does `vendor.oplus.hardware.displaypanelfeature-service` also register the cwb AIDL service? Part A did not find a cwb registration in that service. [unknown]
5. What does the `OplusDEE` feature do, and does anything in the UI depend on `IMMDisplayFeature`? [unknown]
6. Is `oplus.software.display.intelligent_color_temperature_lut_support` ever set on a ColorOS 17 donor device? The donor feature XML search found nothing. [unknown]
7. Which pipa display controls could back the post-blend toggles (types 1-8)? QDCM/`display-color-hal-1-0` calls have not been mapped. [unknown]
8. `IOplusLights`: does any display colour or brightness feature depend on it? [unknown]
