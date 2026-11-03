# SPEC: transmessage, urcc, handlefactory, cwb on pipa (static analysis, C.07 donor)

Scope: wire protocol, donor behaviour, clients, value on pipa, shim tables where value is HIGH/MED, device checks.
Method: static only (no device). Tags: [seen] = read in donor files; [inferred] = from names or structure; [unknown] = not resolved.
No donor code is quoted. Sources: `donor {odm,vendor,system,system_ext}`, dumps in (cloud work folder), pipa kernel `/home/user/kernel_xiaomi_pipa_cos17` (branch oppo).

## 0. Verdicts

| HAL | Version / hash | What it is | Value on pipa | Ship a shim? |
|---|---|---|---|---|
| `vendor.oplus.hardware.transmessage.ITransmessge/default` | AIDL V1, hash `686973cba241b3a803bc9efb831d7143383f385e` | A **file proxy**: system_server / Olc / gaia read and write OPPO-labelled vendor files through it (usage records, log core, custom flags, UAH config) | **LOW** (removes two blocked threads; no user-visible feature) | No functional shim. Optional deny-all stub (section 1.5). Keep gaia blocked. |
| `vendor.oplus.hardware.urcc.IUrcc/default` | AIDL V1, hash `cae43655eaf0af39cbb6d273c5e2206eebe33a10` | OPPO "UAH" resource arbiter: apps and Osense ask for CPU/GPU/DDR floors and caps, scene boosts | **LOW now, MED only if measured** (game performance mode, scroll/launch boosts). Policy table is AES-encrypted: a Java shim cannot reproduce the donor policy | No policy shim now. Measurement plan in section 2.6. Stub only if a blocked caller shows. |
| `vendor.oplus.hardware.handlefactory.IHandleFactory/default` | AIDL V1, hash `5d3d9c5a4b59928ff8c1cc7ab4e36839ccf91929` (HIDL @1.0 legacy) | Whitelisted node read/ioctl proxy inside the donor power-stats HAL. Feeds statsd pullers (OPPO telemetry) and OBrain's QPT energy meter (SM8850 only) | **NONE** | No. Telemetry. Do not ship upload paths. |
| `vendor.oplus.hardware.cwb.ICwbService/default` | AIDL V2 (V1 in odm lib), hash V2 `4fb4cb02257f0df716d661457e6c7f315e5eea4a`, V1 `f523d90366e7ffc66a67923f9329d4cbcfcb21d1`; HIDL @1.0 legacy | "Concurrent write-back" frame read-back (RGB / luma / histogram of the composed frame). Server lives in the donor Qualcomm composer (`libcwb_qcom_aidl.so`), not in odm | **NONE** (OLED power estimate, black-screen telemetry, RGB histogram log; one small auto-brightness refinement that falls back cleanly) | No. |

Bottom line: none of the four gives a user-visible feature that a shim can deliver on pipa. The only candidate for a real gain is urcc (MED, unproven). Stats (`ostatsd`, `ostats_pullerd`, `midasd`) are OPPO telemetry: keep them off (`persist.sys.ostatsd.enable=0`, `persist.sys.ostats_pullerd.enable=0`), as `INIT-SERVICES.md` already advises.

## 0.1 Facts that apply to all four

- **Service-manager wait rule** [inferred from libbinder behaviour, test on device, section 5]: native `AServiceManager_waitForService` blocks only if the name is *declared* in a VINTF manifest and not registered. If undeclared and absent it returns null at once. Step 4q removes the system-manifest `urcc` declaration for this reason. A registered service is found by `waitForService` even if undeclared.
- `waitForDeclaredService` / `isDeclared` clients (for example `TransmessgeManager`) need the name declared. If a shim is registered but undeclared, they treat the HAL as absent.
- Donor odm ships manifests `manifest_transmessage_aidl.xml`, `vendor.oplus.hardware.urcc-service.xml`, `manifest_oplus_cwb_aidl.xml`, `android.hardware.power.stats-service.oplus.xml` (handlefactory). Check whether the port copies any of them (section 5, check 1).
- Registration model for any shim: `maintainer/touchshim` (Binder subclass in own host process, name labelled `oplus_absent_service`, rule `(allow pipa_port oplus_absent_service (service_manager (add find)))`). Not repeated here.
- SM8250 kernel (branch oppo) has: `/proc/oplus_scheduler` (sched_assist), `/proc/oplus_qos_sched`, `/proc/oplus_binder`, `oplus_locking`, `oplus_hans`, WALT sysctls (`sched_upmigrate`, `sched_downmigrate`, `sched_group_*migrate`, `sched_min_task_util_for_colocation`, `sched_boost`, `input_boost_enabled`, `sched_ravg_window_nr_ticks`), qcom memlat/bwmon devfreq names (`qcom,cpu0-cpu-l3-lat`, `qcom,cpu-cpu-llcc-bw`, and others), `msm_performance`. It has **no** `/proc/perfmgr`, `/proc/game_opt`, `/proc/ufsplus_ctrl`, `/proc/oplus_healthinfo`, `/proc/oplusVersion`, `/proc/oplus_power`, `/proc/jank_info`, `/sys/class/oplus_chg` (charger shim emulates part), no `qpt` powercap, no `oplusreserve` partition.

---

## 1. transmessage (`ITransmessge`)

### 1.1 Wire protocol [seen]

- Descriptor `vendor.oplus.hardware.transmessage.ITransmessge`; instance `default`; AIDL V1; hash above. Java stub in `system_ext/framework/vendor.oplus.hardware.transmessage-V1-java.jar`; NDK in `odm/lib64/vendor.oplus.hardware.transmessage-V1-ndk.so`. HIDL `@1.0::ITransmessge` also exists in clients (services.jar, oplus_gaia) but the donor service is AIDL only; HIDL lookups return null at once (retry false).
- Codes (stub constants; 16777215 = getInterfaceVersion, 16777214 = getInterfaceHash):

| code | method | args (order) | reply (after the no-exception header) |
|---|---|---|---|
| 1 | `achieveFileListName` | String dir | byte[] (names list; separator not resolved [unknown]) |
| 2 | `deleteFile` | String path | boolean |
| 3 | `getFileSize` | String path | int (size; negative / 0 on error [inferred]) |
| 4 | `makeDir` | String path | boolean |
| 5 | `readOplusFile` | String path, int offset, int length | byte[] |
| 6 | `saveOplusFile` | int file_max, String path, int offset, boolean append, int length, byte[] data | int (bytes saved) |

No callbacks, no parcelables. No one-way methods.

### 1.2 Donor service behaviour [seen strings, inferred flow]

- `/odm/bin/hw/vendor-oplus-hardware-transmessage-V1-service`; rc: `class hal`, `user system`, `group system wifi mediadrm radio`, `oneshot`, `disabled`, `interface aidl ...ITransmessge/default`. Registered as a **lazy service** (`AServiceManager_registerLazyService`; log "Service transmessge exited (lazy)").
- Plain POSIX file I/O (`open`, `lseek`, `read`/`write`, `opendir`/`readdir`, `mkdir`, `remove`). No sockets, no other services, no netlink. **No path whitelist found** in the strings (no `/mnt`, `/data` prefixes): it is an open file proxy running as `system`, group `wifi radio mediadrm`. A shim must add its own path whitelist.
- Caller check: `AIBinder_getCallingUid` then `multiuser_get_app_id`; the app id minus 1000 must be <= 31 and in a bitmask `0x403` = app ids **1000 (system), 1001 (radio), 1010 (wifi)** [seen in disassembly, offset 0x4548 in `getFileSize`]. Others log "reject caller uid=%u". Root (app id 0) is not in that mask [unknown if handled elsewhere]; `oplus_gaia` runs as root.
- `saveOplusFile`: creates parent dirs (`makeDir`), seeks to `offset` (or end if `append`), caps with `file_max`, validates `length` against `data.size`, log "save size / request size". `readOplusFile`: clamps `offset+length` to file size ("just read to the end"). `achieveFileListName`: lists a directory into one byte[] (`getFileListVector`). `convertToNoSensitiveIfNeeded` masks sensitive text in logs.

### 1.3 Clients and what they do [seen]

| Client | Paths used through it | Feature |
|---|---|---|
| `oplus-services.jar` `TransmessgeManager` (guarded by `isDeclared`) | `/mnt/vendor/oplusreserve/media/log/usage/`; whole-file helpers (`nativeSaveEntireOplusFile`, `nativeReadEntireOplusFile`) | `OplusUsageService` usage records (cache/persist dirs, `UsageDataRecorder`, `PublicDataRecorder`, EMMC health collector). Telemetry spooling. |
| `CustomizeStateHelper` (oplus-services) | `/mnt/vendor/oplusreserve/system/flag/{flashback.cfg,b_flag.cfg,devicelock.cfg,custom_forbidden_recovery.prop}` | OPPO enterprise / device-lock / recovery-forbidden flags. Not used on a consumer tablet. |
| `OplusOperatorFileUtils` | delete / size of operator config files | Carrier config files. Wi-Fi tablet: unused. |
| `OplusUAwareRUSHelper$UpdateNotifyRunnable` | writes `/data/vendor/uah/uahconfig.pb` | Cloud (RUS) update of the UAH policy. Only meaningful with a real urcc. |
| `CameraSnHelper` | reads `/mnt/vendor/persist/camera/*_SN.bin` (direct, not necessarily through the HAL) | Camera serial numbers (factory data). |
| `com.oplus.olc` (Olc.apk, `b2.o.c`, **waitForService**) | `/data/persist_log/...` (DCS, olc exception_log, gaia config) | OPPO log core: exception log packing, "logkit" feedback logs, DCS (data collection) upload. Diagnostics / telemetry. |
| `/system_ext/bin/oplus_gaia` (`TransmessageHalService::checkService`, **waitForService**) | `GAIA::VendorFileUtil::readEntireOplusFileByTransmessage` | GAIA / Postman log daemon (socket `postmand`), log collection. Diagnostics / telemetry. |

User-visible feature: **none**. It is "telemetry only (log and usage spooling toward OPPO's DCS)", plus enterprise flags.

### 1.4 Value: **LOW**

- Gains: Olc non-main thread stops waiting; gaia leaves its wait. `JAVA-WAITS.md` rates the Olc wait as one blocked thread, no ANR.
- **Unblocking gaia is a net negative**: it starts log collection into `/data/persist_log/*` (the rc creates `olc`, `gaia`, `postman`, `ap_log` dirs), packs logs, and prepares DCS uploads. We do not ship upload paths. Keep gaia blocked or off. Prefer disabling gaia by property/rc (gate `persist.sys.dft_process.status`, see `INIT-SERVICES.md`) over feeding it.
- The paths under `/mnt/vendor/oplusreserve` do not exist on pipa (no partition). A "real" shim would need an emulated directory under `/data` and a whitelist. No feature justifies that.

### 1.5 Optional stub (only if Olc wait must go without a dex patch)

Deny-all stub in the touchshim style. No data flows, so no upload path is created and gaia does not start useful work.

| code | method | donor does | stub does | reply | risk |
|---|---|---|---|---|---|
| 1 | achieveFileListName | lists dir | nothing | empty byte[] | Caller treats as "no files": log "achieve file name failed". |
| 2 | deleteFile | `remove()` | nothing | false | Callers retry or log. |
| 3 | getFileSize | `lseek` end | nothing | -1 | `CustomizeStateHelper` reads -1 as "no flag file": correct default. |
| 4 | makeDir | `mkdir -p` | nothing | false | Olc logs failure. |
| 5 | readOplusFile | read | nothing | empty byte[] | OK. |
| 6 | saveOplusFile | write | nothing | -1 | Usage service drops the record: desired. |
| 16777215 / 16777214 | version / hash | n/a | return 1 / the hash string | | Must match the declared V1. |

Reject callers outside app ids {1000, 1001, 1010}, as the donor does. If a real file proxy is ever needed, use a whitelist of `/data/vendor/uah/`, `/data/persist_log/olc/` and reject `..`.

Declare in a VINTF fragment only if `TransmessgeManager` should use it (otherwise `isDeclared` is false and it stays off, which is also fine).

---

## 2. urcc (`IUrcc`) and UAH

### 2.1 Wire protocol [seen]

- Descriptor `vendor.oplus.hardware.urcc.IUrcc`; instance `default`; AIDL V1; hash above. Callback `vendor.oplus.hardware.urcc.IUrccCallback`. Java stubs: `oplus-framework.jar` (`vendor/oplus/hardware/urcc/*`, dump (cloud work folder)). NDK: `odm/lib64/vendor.oplus.hardware.urcc-V1-ndk.so`.

| code | method | args | return |
|---|---|---|---|
| 1 | `urccInit` | none | void |
| 2 | `urccResCtlRequest` | UrccRequestParcel | int (handle) |
| 3 | `urccResCtlRelease` | int handle | int |
| 4 | `urccResStateRequest` | UrccRequestParcel | UrccRequestData[] |
| 5 | `urccResListeningRegister` | UrccRequestParcel, IUrccCallback | int |
| 6 | `urccResListeningUnRegister` | int | int |
| 7 | `urccPropertyGet` | String key | String (default "-1" in the stub) |
| 8 | `urccPropertySet` | String key, String value | int |
| 9 | `urccThermalListeningRegister` | int[] ids, IUrccCallback | int |
| 10 | `urccThermalListeningUnRegister` | int | int |
| 11 | `uahNotifyExt` | int, int, int[] | int |
| 12 | `setRelatedSysInfo` | int, byte[] | int |
| 13 | `urccRuleCtl` | int, int, UrccRequestData[] | int |
| 14 | `uahResCtlRequestBypass` | UrccRequestParcel | void (oneway use [inferred]; the donor service logs it) |
| 16777214 / 16777215 | hash / version | | |

`IUrccCallback`: code 1 `onCallback(UrccRequestData[])` (oneway [inferred]).

Parcelables (all with the AIDL size prefix first, then fields in this order; from `writeToParcel`):

- `UrccRequestParcel`: `int type`, `UrccRequestData[] mUrccRequestData`, `boolean screenoff_support`, `int prio`, `int callingPID`, `int callingUID`, `long duration`, `String[] mParams`, `int handle`, `IUrccCallback urccCallback` (strong binder, nullable), `String pkgName`, `String identity`, `byte[] otherData`.
- `UrccRequestData`: `int res_Id`, `int event_Id`, `String res_Value`, `String res_Path`, `String desc` [seen: two ints, then three strings].

### 2.2 Donor service behaviour [seen]

- `/odm/bin/hw/vendor.oplus.hardware.urcc-service` (rc service `vendor.urcc-hal-aidl`, `class hal`, `user root`). It is thin: `dlopen("liburcccore.so")` and `dlsym`s `urccModuleInit/Exit`, `urccPropertyGet/Set`, `urccResCtlRequest/Release`, `urccResStateRequest`, `urccResListeningRegister/Unregister`, `urccRuleCtrl`, `urccSendNotification`, `urccThermalListeningRegister/UnRegister`, `uahResCtlRequestBypass`. Thread `UrccMainThread`, `mlockall`, real-time scheduler.
- `liburcccore.so` (650 KB) holds the arbiter: `UrccCtlServer`, `UrccResMap`, `UrccResOptManager` (per-resource priority and apply functions), `UrccThermalMap`, `UrccRequestQueue` + `ThreadPool`, timers (`UrccRequest::timerCallback`), `UrccGpu`, `UrccNpu`, protobuf (`UahConfig`, `SavedData`, `ClusterInfo`), XML (libxml2), stats atoms (`android.frameworks.stats`). It also loads `libuahcore.so`.
- **Policy source**: `/odm/etc/uah/uahconfig.pb` (88541 bytes). Entropy 7.998 bits/byte: **AES-encrypted** (`decode_aes` in libuahcore). A saved copy lives in `/data/vendor/uah/uahconfig.pb` and `SavedData.pb`. We cannot read the event-to-resource table, and we will not extract the key. A Java shim cannot reproduce the donor policy.
- Nodes it writes (strings in core, rc `chmod`s): `cpufreq/policy{0,6,7}/scaling_{min,max}_freq`, `cpu*/core_ctl/{min,max}_cpus`, `devfreq/...cpu-llcc-lat|llcc-ddr-lat|l3-lat|ddr-latfloor|llcc-bw/{min,max}_freq`, `bw_hwmon/*`, `bus_dcvs/*` (not in 5.4), `kgsl-3d0/{devfreq/min_freq,max_freq,min_pwrlevel,max_pwrlevel,force_*_on,idle_timer}`, `/proc/sys/walt/*`, `/proc/perfmgr/*` (absent), `/proc/oplus_scheduler/sched_assist/sched_assist_enabled`, `/proc/game_opt/disable_cpufreq_limit` (absent), `/dev/cpuctl/*/cpu.uclamp.min`, `/dev/cpuset/{display,sf}/cpus`, `/proc/ufsplus_ctrl/*` (absent), `/sys/class/devfreq/1d84000.ufshc/{min_freq,governor}`. Mixed platform (cluster numbering is SM8650-style: policy0/6/7; pipa SM8250 has policy0/4/7). Data dirs `/data/vendor/urcc`, `/data/vendor/uah` (rc), logs `urcclog.csv`, `history_record.txt`. Also dlopens `libpowerhal.so` and `liboplus_gpu_utils.so` [seen strings].

### 2.3 Clients [seen]

Native: `liboplus-uah-client.so` (system_ext, odm, vendor copies): `UahEventAcquire`, `UahEventAcquireOneWay`, `UahResAcquire`, `UahRelease`, `UahResStateRequest`, `UahMutiResStateRequest`, `UahNotify`, `UahGetFeatureStatus`, `UahGetHistory`, `UahGetPMStatus`, `UahGetPowerConsis`, `Uah_fetch_dataset`; calls `urccHalclient::urccResCtlRequest` and waits for `IUrcc/default` (**waitForService**). Java side: `oplus-framework.jar` `com.oplus.uah.{UAHPerfManager (JNI "UahPerf_Jni"), UAHResClient, UAHAdaptHelper, info.*, input.ScrollFlingBoost}`.

Consumers:
- Osense scene engine: `UAHAdaptHelper.adaptSetSceneAction` maps scene actions (launch, cold launch, activity start/resume, window rotation, swipe V/H, decode, camera modes, hyperboost L1-L3, touch boost, screen-on boost, unlock boost, animation, game modes) to `UAH_EVENT_*` ids. `setControlData` pushes cpu/gpu freq lists, migration lists, game adaptation (core/freq boost and limit).
- `ScrollFlingBoost` (fling boost; feature key `oplus_uah_featrue_osi_fling`).
- SystemUI: QS scroll boost, one-hand animation (`OsenseHelperImpl`, `SchedUtil`).
- OplusGames / GameSpace (`utils/m0`): game performance mode resources.
- Battery app `ThermalControlUtils`: OPPO thermal control applies resource caps with `UAHResClient.acquireResource`.
- COSA `ORMScontrol`: game rule control (`ctrlRule`).
- `OplusHyperModeGamePolicy`, `FlexibleWindowUtils`, `BaseHint` (oplus-services).
- `Bluetooth.apk` only bundles the classes.

Event ids (selected, from `UAHPerfConstants`): LAUNCH 0, COLD_LAUNCH 1, WINDOW_ROTATION 5, SWIPE_V 6, SWIPE_H 7, TOUCH_BOOST 37, SCREEN_ON_BOOST 38, INPUT_METHOD_BOOST 39, UNLOCK_BOOST 41, ANIMATION 42, LAUNCHER_GPU_BOOST 71, SWIPE_RECENT 80, LAUNCHER_OPEN_APP_ANIMATION 85, LAUNCHER_CLOSE_APP_ANIMATION 86, ROTATION_LATENCY_BOOST 110, HORIZONTAL_SCROLL_BOOST 113, SIDEBAR_SLIDEOUT_BOOST 117, ROUND_CORNER_ANIMATION 156, ASSISTANT_SCROLL_BOOST 194, HYPERBOOST_GPU 32 / CPU L1-L3 33-35 / DDR 36 (209 constants in total; camera events dominate the rest).
Resource ids (`UAHResourceConstants`, base 0x010nnnnn): `CPU_FREQ_SCALING_MIN_{SILVER,GOLD,PRIME}` 0x1010010/20/30; `..._MAX_...` 0x10100A0/B0/C0; `CORE_CTL_MIN_CPUS_*` 0x1010B10/20/30; `CORE_CTL_MAX_CPUS_*` 0x1010B90/A0/B0; `CPU_FREQ_TARGET_LOAD_*` 0x10108A0/B0/C0; `CPU_SCHED_UPMIGRATE` 0x1010F80, `DOWNMIGRATE` 0x1010F90, `GROUP_UPMIGRATE` 0x1010FB0, `GROUP_DOWNMIGRATE` 0x1010FC0, `MIN_TASK_UTIL_FOR_COLOCATION` 0x1011040, `WINDOW_TICKS_UPDATE` 0x1011070, `TOUCH_BOOST` 0x10112F0, `CPUSET_FOREGROUND_CPUS` 0x10115B0, `FPSGO_FORCE_ONOFF` 0x1011910 (MTK, ignore), `FREQ_BOUNCING_ENABLE` 0x10103A0; `GPU_MIN/MAX_CLOCK_MHZ`, `GPU_MIN/MAX_CORE` 0x1020070/80/B0/C0.

### 2.4 Current port state

Step 4h makes `UAHAdaptHelper.getAidlService` return false at once (stops a service lookup and a log line per touch). Step 4q removes the system-manifest declaration so native `waitForService` returns at once. Result: all UAH boosts are silently off. Step 4n (qos_sched, kernel r12/r13) and the sched_assist / frame_boost kernel parts are active, and the stock Power HAL boosts (AOSP launch and interaction hints) are untouched. `BUGS.md` 39 concluded "porting the OPPO urcc / touch HALs: not useful".

### 2.5 Value: **LOW today; MED only if a measured gap exists**

Reasons it is not HIGH:
1. The donor policy cannot be read or reproduced (encrypted). An own policy is new design work, not a port.
2. Most scenarios (launch, scroll, touch, rotation) already receive boosts from AOSP to the Xiaomi Power HAL and from the OPPO kernel parts present on pipa. A second writer on the same nodes adds thermal and battery cost and a write race.
3. Many target nodes do not exist on SM8250 (`perfmgr`, `bus_dcvs`, `game_opt`, `ufsplus_ctrl`, `policy6`).
4. Thermal control: pipa's Xiaomi thermal-engine already throttles. The OPPO layer on top is redundant.

Where a gain is plausible: game performance mode and game "freq floor" requests (OplusGames, COSA `ORMScontrol`, `OplusHyperModeGamePolicy`). This needs a measured gap versus HyperOS on a real game, not an assumption.

### 2.6 Experiment first, shim second

1. Baseline: `maintainer/perfetto/traced_heavy.sh <label>` FrameTimeline, 2 or more runs, 60 s after unlock, on: launcher open/close app, recents swipe, Settings scroll, rotation, one game.
2. Variant A (stub): revert 4h (`getAidlService` true) + register the shim below with **all handlers returning success and doing nothing**. Confirms only that callers stop retrying. Expect no change.
3. Variant B (boost map): the shim below with the "boost action" column active. Compare FrameTimeline jank and `dumpsys battery` / SoC temperature after 10 minutes. Ship only on a measured gain with no thermal cost.
4. Do **not** run the donor `urcc-service` natively: its tuned frequency table is for another SoC, it runs as root and writes cpufreq / devfreq / kgsl limits.

### 2.7 Shim behaviour table (MED path; stub is the same table with the "boost action" column replaced by "nothing")

Host: own process like touchshim; uid and SELinux domain as `pipa_port` (needs write rules for the nodes below: a CIL rule per node class, compile with `secilc` before a build). Handle allocator: monotonically increasing int > 0, map handle -> (nodes, previous values, expiry). Single worker thread, queue cap 64, `duration` in ms from `UrccRequestParcel.duration` (0 = until release; cap at 10 s to avoid stuck floors). Restore previous values on release, expiry, caller death (`linkToDeath` on `urccCallback` binder is not available for non-callback callers: use `callingPID` liveness check), and shim exit.

| code | method | donor does | shim does on pipa | reply | risk |
|---|---|---|---|---|---|
| 1 | urccInit | `urccModuleInit` (load config, build resource map) | no-op | void | none |
| 2 | urccResCtlRequest | queue request, resolve `res_Id`/`res_Path`, arbitrate by `prio`, apply with timer | Event path (`event_Id` set): look up own event table (below) and start a boost for `duration`. Resource path (`res_Id` set): accept only ids in the supported set, clamp values to the SM8250 `scaling_available_frequencies`; write the node; remember old value. Unknown id -> skip it | handle (>0) if at least one item applied, else 0 | Write race with Xiaomi perf HAL and `thermal-engine`: never lower a cap a thermal node set; only raise `scaling_min_freq` within limits and never touch `scaling_max_freq` except to restore a value the shim itself changed |
| 3 | urccResCtlRelease | restore values for handle | restore saved values, drop handle | 0 / -1 if unknown handle | Restore after a mode change may overwrite a newer writer: restore only if the node still holds the shim's value |
| 4 | urccResStateRequest | read current resource values | for each requested `res_Path`/`res_Id`: read the node (cpufreq `scaling_{min,max}_freq`, `cpu*/core_ctl/*`, `kgsl-3d0/devfreq/{min,max}_freq`, WALT sysctls) and fill `res_Value` | `UrccRequestData[]` same length; `res_Value` "" if unsupported | GameSpace may display values: return real values only |
| 5 | urccResListeningRegister | register change listener (callback on resource change) | store callback (max 32, dedupe by binder); never fire | 1 (id) | Dead callbacks: remove on `DeadObjectException` |
| 6 | urccResListeningUnRegister | remove listener | remove | 0 | none |
| 7 | urccPropertyGet | read internal property | return `"-1"` (the stock default) unless the key is `vendor.urcc.*`/`persist.vendor.oplus.uah.debugenable` (then `SystemProperties`) | String | none |
| 8 | urccPropertySet | set internal property | ignore | 0 | none |
| 9 | urccThermalListeningRegister | register for thermal-level callbacks | store callback; **fire once** `onCallback([])` never; no thermal events (pipa's thermal-engine owns throttling) | 1 | OPPO thermal control sees no thermal events: default state |
| 10 | urccThermalListeningUnRegister | remove | remove | 0 | none |
| 11 | uahNotifyExt | feature notifications (game mode, GPA, nr_ticks, cpubouncing, power-save source) | accept; for `UAH_NOTIFY_SRC_*` ids log only | 0 | none |
| 12 | setRelatedSysInfo | store info blob | ignore | 0 | none |
| 13 | urccRuleCtl | enable/disable rule groups (used by COSA ORMS) | return 0, no state | 0 | Game rules silently inert |
| 14 | uahResCtlRequestBypass | same as code 2 without reply (one-way) | same as code 2, no reply | void | same as code 2 |
| 16777215 | getInterfaceVersion | | return 1 | int | must equal the declared version |
| 16777214 | getInterfaceHash | | return `cae43655eaf0af39cbb6d273c5e2206eebe33a10` | String | |

Own event table (MED path, tunable; all `duration` from the request, default 300 ms, cap 1500 ms; actions are on the **big and prime** policies only, `policy4` and `policy7`):

| event id(s) | meaning | boost action (own design, to be tuned by measurement) |
|---|---|---|
| 0, 1, 85, 86, 71 | launch, cold launch, launcher open/close animation, launcher GPU | `scaling_min_freq` of policy4 and policy7 to 60 % of max for duration; GPU `min_freq` one OPP up |
| 6, 7, 80, 113, 117, 194 | swipe V/H, recents swipe, horizontal scroll, sidebar, assistant scroll | policy4 floor to 40 % of max |
| 5, 110 | rotation | policy4 and policy7 floor to 60 % for 500 ms |
| 37, 38, 41, 42, 39 | touch, screen on, unlock, animation, input method | WALT `input_boost`-class: no write (kernel has it); log only |
| 32-36 | hyperboost GPU / CPU L1-L3 / DDR (game) | L1 40 %, L2 60 %, L3 80 % floor on policy4/7; DDR: raise `soc:qcom,cpu-llcc-ddr-bw` `min_freq` one step; stop on release |
| camera ids (the rest) | camera scenes | ignore (pipa camera stack is Xiaomi) |

Floors are fractions of `cpuinfo_max_freq` rounded up to a value in `scaling_available_frequencies`. The shim must not run on `battery < 5 %` or when `thermal` zones report "throttled" (read `/sys/class/thermal/thermal_zone*/temp`; choose the CPU zone by `type` at start).

Required companion change if the MED path is built: revert step 4h's `getAidlService` patch (otherwise nobody calls the shim from `UAHAdaptHelper`; `ScrollFlingBoost`, SystemUI, GameSpace, Battery and COSA use the JNI client and would work). Keep the system-manifest `urcc` entry removed (step 4q): the registered shim is found by `waitForService` without a declaration.

---

## 3. handlefactory and cwb (statistics)

### 3.1 handlefactory wire protocol [seen]

- Descriptor `vendor.oplus.hardware.handlefactory.IHandleFactory`; instance `default`; AIDL (manifest has no version; lib V1); hash `5d3d9c5a4b59928ff8c1cc7ab4e36839ccf91929`. Java stub in OBrain.apk (dump (cloud work folder)).

| code | method | args | return |
|---|---|---|---|
| 1 | `getHandle` | String name, int | ParcelFileDescriptor |
| 2 | `ioctrl` | String name, int, int, int | HandleFactoryRet |
| 3 | `read` | String name, int | HandleFactoryRet |
| 4 | `write` | String name, int, String data | int |

`HandleFactoryRet` (size prefix, then): `int result`, `int param`, `String data`.

### 3.2 Donor provider [seen]

`odm/bin/hw/android.hardware.power.stats-impl.oplus` (rc service `vendor.power.stats`, `class hal`, `user system`, groups `system root`). One binary serves three AIDL interfaces: `android.hardware.power.stats` V2 (state residency from `/sys/power/soc_sleep/stats`, `rpmh_sleep_stats`, `/sys/module/oplus_rpmh_statics/...`; energy meter from `/sys/class/powercap/qpt:0:N/energy_uj`), `vendor.oplus.hardware.rpmh` V1, and `IHandleFactory`. The handle factory maps a **node key** to a path from a built-in config ("data providers config", "node path"), audits each call (`HandleFactoryAudit denied method=... reason=default_deny_non_read / unknown_node`), and allows reads of a whitelist and a few writes (QPT enable; `/proc/sysrq-trigger` dump trigger). Node keys seen: `qpt_gpu_energy_uj`, `qpt_nsp_energy_uj`, `qpt_cpu_L_energy_uj`, `qpt_cpu_M_energy_uj`, `remaining_battery_power`, `battery_typical_capacity`, `cpu_leakage_type`, `charger_passedchg`, `ufs_health_info`, `panel0_brightness_level_qcom`, `power_supply_{health,cycle_count,usb_online,ac_online}`, `gpu_freq_time_qual`, `gpu_stack_working_opp_table`, `/sys/class/oplus_chg/battery/{battery_soh,battery_rm,gauge_car_c}`, `/proc/task_overload/abnormal_task`, `/proc/charger/passedchg_reset_count`.

### 3.3 Clients [seen]

| Client | Use | Feature |
|---|---|---|
| `ostats_pullerd` (root, system_ext) | `read(nodeKey)` inside statsd pull-atom callbacks (`AStatsManager_setPullAtomCallback`); also cwb@1.0 for "RGB histogram log" (`dumpsys ostats_pullerd --rgbLog`) | Registers atoms with statsd; consumed by `ostatsd` |
| `ostatsd` | subscribes to statsd, builds DCS rows (`writeToDcs`, `uploadRatio`, RUS config `OStatsConfig.pb`) | **Upload to OPPO DCS. Telemetry only.** |
| `OBrain.apk` `E1/f` "QptControlComponent" | `read` model data, `write "1"/"0"` to enable the QPT energy meter by uid (ref-counted, binder death aware); only if `ro.soc.model` = SM8850 | Per-component energy accounting for OBrain; SM8850 hardware. pipa has no `qpt` powercap: **hardware pipa lacks** |
| `midasd` | `HandleFactory` + `cwb v3` | Power / thermal analytics (`calcEnergyCwbV3`, `/proc/oplus_healthinfo`, `/proc/oplus_power`): telemetry |
| `framework.jar`, `oplus-framework.jar` HIDL `@1.0` classes | bundled stubs; no live caller found | none |
| `libstatsd_export.so` | link only | none |

Settings > Battery usage, screen-on time, and charge data do **not** come from handlefactory: they come from AOSP `BatteryStats` / `IPowerStats` and the shimmed charger HAL. `PowerMonitor`'s sleep/wake data uses the separate `rpmh` HAL (not in scope).

### 3.4 cwb (`ICwbService`) wire protocol [seen]

- Descriptor `vendor.oplus.hardware.cwb.ICwbService`; callback `vendor.oplus.hardware.cwb.ICwbCallback`; V2. Parcelables `Rect` (4 ints: left, top, right, bottom [inferred order]), `Rgb` (4 ints [fields not resolved]), `Histogram` (int + parcelable array + int), `Buffer` (3 ints). `Error` is an out parcelable/enum.
- Codes (read from the V2 proxy; AIDL code = 1 + method index):

| code | method | args |
|---|---|---|
| 1 | getRGBValue | Rect -> Rgb, Error |
| 2 | getLumasValue | Rect -> float[], Error |
| 3 | getHistogramValue | Rect -> Histogram, Error |
| 4 | getCwbPostProcessStatus | -> boolean |
| 5 | setCwbPostProcessStatus | boolean -> Error |
| 6 | registerCallback | ICwbCallback -> Error |
| 7 | unregisterCallback | ICwbCallback -> Error |
| 8 | enable | -> boolean |
| 9 | disable | -> boolean |
| 10 | setDebug | int[] -> Error |
| 11 | getCwbValue | int, Rect -> int[], Error |
| 12 | setCwbValue | int, Rect -> int[], Error |
| 13 | initializeSharedMemory | int, int, ParcelFileDescriptor -> Error |
| 14 | getSharedData | int, Rect, ParcelFileDescriptor, int -> int[], Error |
| 15 | getScreenResolution | int -> int[], Error |
| 16 | releaseSharedMemory | int, int -> Error |

`ICwbCallback.onAvailableStatusChanged(boolean)`. V1 lacks 13-16. HIDL `@1.0` has: enable, disable, getCwbBuffer, getRGBValue(s), getHistogramValue, getLumasValue, registerCallback, setCwbPostProcessStatus (services.jar `oplus_cwb_buffer`, `CwbRect`).

### 3.5 cwb provider and clients [seen / inferred]

- Server: not in odm. The V2 AIDL client libs in `vendor/lib64` (`libcwb_qcom_aidl.so`, `libsdmclient.so`, `libcwb_client_vendor.so`, `sensors.qsh.so`) show that the Qualcomm display composer / SDM serves it from the composer's write-back path. `displaypanelfeature-service` and `cwb_utils_aidl` are only clients. pipa's PixelOS-based composer has no such path.
- Clients and features:

| Client | Use | Feature |
|---|---|---|
| `surfaceflinger` (props `persist.oplus.display.cwb.status`, `...regionsampling.cwb`) | luma sampling of regions (`captureSample`) | OPPO region sampling for adaptive UI contrast. Falls back to AOSP sampling when absent. |
| `theia_screen_monitor` + `libtheiahelper` (waitForService today) | `getRGBValue` at screen areas (`checkBlackArea`, "detected black") | Black / blank screen detection for OPPO diagnostics. Telemetry. |
| `midasd` | `calcEnergyCwbV3` from frame colour x panel current tables | OLED power estimate (pipa is LCD). Telemetry. |
| `ostats_pullerd` | RGB histogram log | Telemetry. |
| `libsensorserviceextimpl.so` | `activateScreenShot using CWB`, `getScreenRGB`, `FusionLight_compute` (RGB sensor compensation by on-screen colour; falls back to the raw sensor when "CWB is not available") | Ambient-light / colour-temperature refinement for devices whose RGB sensor sits under the panel. pipa's sensor is on the bezel; step 3s uses `front_cct_strm` and works without CWB. |
| `services.jar` display adapter `setCwbEnabled` | HIDL enable/disable | none visible |

### 3.6 Value: handlefactory **NONE**, cwb **NONE**

- handlefactory: telemetry plus an SM8850 energy meter. Nothing user-visible. A shim returning empty `HandleFactoryRet` would only make `ostats_pullerd` register empty atoms. Cheaper and safer: keep `ostats_pullerd` and `ostatsd` disabled by property. No shim. If a blocked `midasd`/`ostats_pullerd` is observed on the device, the existing advice (`persist.sys.midasd.enable=0`) already covers it.
- cwb: real data needs a frame write-back that pipa's composer does not provide. A Java emulation (screen capture per sample) would be expensive and serves only telemetry or a refinement that already falls back. The only blocking caller is `theia_screen_monitor` (a diagnostic daemon): disable it (init service property gate) instead.
- We will **not** ship any path that uploads data (DCS rows, `writeToDcs`, `uploadRatio`).

---

## 4. Decision list

1. transmessage: no functional shim. Optional deny-all stub (1.5) only if the Olc wait must be removed without the dex patch (JAVA-WAITS item F). Keep `oplus_gaia` off or blocked.
2. urcc: no policy shim now. Run the experiment in 2.6. Build the 2.7 table only if variant B shows a gain. Never run the donor service.
3. handlefactory, cwb: no shim. Disable `ostatsd`, `ostats_pullerd`, `midasd` (or keep disabled), `theia_screen_monitor`.
4. Record in `BUGS.md` (not done here; read-only task): "transmessage/urcc/handlefactory/cwb analysed, LOW/LOW-MED/NONE/NONE, see SPEC-TRANS-URCC-STATS.md".

## 5. Device checks (exact commands; `ADB="adb -s <serial>"`)

1. Declarations and registration on the running ROM:
   `$ADB shell "su -c 'service list | grep -iE \"transmessage|urcc|handlefactory|cwb\"; grep -rlE \"transmessage|urcc|handlefactory|cwb\" /odm/etc/vintf /vendor/etc/vintf /system/etc/vintf /system_ext/etc/vintf 2>/dev/null'"`
   Expect no service. Names found in a manifest are the ones that can block a native waiter.
2. Who is blocked (gaia, Olc, theia):
   `$ADB shell "su -c 'getprop init.svc.oplus_gaia; getprop init.svc.theia_screen_monitor; getprop init.svc.ostatsd; getprop init.svc.ostats_pullerd; getprop init.svc.midasd'"`
   `$ADB shell "su -c 'debuggerd -b \$(pidof oplus_gaia)' | head -40"` (look for `waitForService`)
   `$ADB shell "su -c 'kill -3 \$(pidof com.oplus.olc); sleep 1; grep -n -B2 -A12 \"transmess\" /data/anr/anr_* 2>/dev/null | head -40'"` (use the traces file name the device prints).
3. Restart loops (cost of telemetry daemons):
   `$ADB shell "su -c 'for s in oplus_gaia ostatsd ostats_pullerd midasd theia_screen_monitor; do echo \$s \$(getprop init.svc.\$s) \$(getprop init.svc_debug_pid.\$s); done; dmesg | grep -E \"init: Service .* (exited|received signal)\" | tail -20'"`
4. Do the UAH clients block now (urcc undeclared)? Trigger a QS scroll and a launcher swipe, then: `$ADB shell "su -c 'logcat -d -s UAH_CLIENT UAH-UahAdaptHelper | tail -30'"`. No hang and no repeated lookup lines means the 4h/4q state is clean.
5. Which UAH events ColorOS sends (for the 2.6 plan): temporarily revert 4h on a test build, register the stub, and log each `urccResCtlRequest` event id and duration to the shim log; count per minute during normal use.
6. Kernel nodes the MED path would use (exist on pipa?):
   `$ADB shell "su -c 'for p in /sys/devices/system/cpu/cpufreq/policy*/scaling_min_freq /sys/devices/system/cpu/cpu*/core_ctl/min_cpus /sys/class/kgsl/kgsl-3d0/devfreq/min_freq /proc/sys/walt/sched_upmigrate /proc/sys/walt/input_boost_enabled /proc/oplus_scheduler/sched_assist/sched_assist_enabled /proc/perfmgr /proc/game_opt /proc/ufsplus_ctrl /sys/class/devfreq/soc:qcom,cpu-llcc-ddr-bw/min_freq; do [ -e \$p ] && echo OK \$p || echo MISSING \$p; done; ls /sys/class/devfreq'"`
   SELinux label of each writable node: `ls -Z` on the same list; compile CIL changes with `/system/bin/secilc` before a build (see AGENTS.md).
7. Baseline for 2.6: `ADB=... sh maintainer/perfetto/traced_heavy.sh baseline-nouah` (2 runs minimum, 60 s after unlock), then the variants.
8. Thermal sanity during variant B: `$ADB shell "su -c 'cat /sys/class/thermal/thermal_zone*/type | paste -sd\" \"; cat /sys/class/thermal/thermal_zone*/temp | paste -sd\" \"'"` before and after 10 minutes of load; `dumpsys battery | grep -E \"temperature|level\"`.
9. Confirm the wait rule (section 0.1): on a test build, declare nothing and check `$ADB shell "su -c 'cmd -l | grep -i urcc'"`; then register any dummy Binder under `vendor.oplus.hardware.urcc.IUrcc/default` and confirm `liboplus-uah-client` callers return (logcat tag `UAH_CLIENT`).
10. Telemetry stays off: `$ADB shell "su -c 'getprop persist.sys.ostatsd.enable; getprop persist.sys.ostats_pullerd.enable; getprop persist.sys.midasd.enable; ls /data/persist_log 2>/dev/null | head; du -sh /data/persist_log 2>/dev/null'"`.

## 6. Open items [unknown]

- Exact AIDL layout of `Rgb` (4 ints, field names) and `Error`.
- `UrccRequestParcel.type` values and which `res_Id` / `event_Id` combination `UahEventAcquire` sends [inferred: `event_Id` set, `res_Id` 0].
- Whether the donor transmessage service also accepts root (app id 0) callers; `oplus_gaia` is root.
- `achieveFileListName` output separator.
- Whether the port's odm copies the four donor manifests (check 1).
- Whether `ro.oplus.osense.*` gates make `adaptSetSceneAction` call the native client on pipa at all.

## Review decisions (2026-11-03)

- No shim for transmessage, handlefactory and cwb: telemetry or OPPO-only hardware paths; no user-visible feature
  on pipa. The urcc policy `odm/etc/uah/uahconfig.pb` is encrypted (entropy 7.998 bits per byte, checked), so a shim
  cannot reproduce OPPO's resource policy.
- urcc: measure first (spec section on the MED path). Build an own event-to-floor shim only if a measured gap exists
  against the Power HAL boosts and the port kernel parts (qos_sched, sched_assist).
- ostats*, midasd, theia_screen_monitor: they feed OPPO telemetry. Turning them off is correct here (no feature is
  lost); confirm with the device checks first.
