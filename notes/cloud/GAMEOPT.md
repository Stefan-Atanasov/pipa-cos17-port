# gameopt HAL (`vendor.oplus.hardware.gameopt`): stub analysis

- Donor: C.07 (only `system/system/` and `system_ext/` unpacked).
- Date: 2026-11-03.
- Method: static only. Java interface jars V1 and V2 disassembled with androguard. `oplus-framework.jar` classes.dex disassembled with a patched androguard script (androguard fails on the hidden-api section). Reviewed: `persist.sys.oiface.enable=2` in the donor `system_ext/etc/build.prop` and the `AServiceManager_waitForService` import of `oiface` checked again. `oiface` read with `.gnu_debugdata` symbols, `llvm-objdump` call-site search and `strings`. Java callers from the COSA app and oplus-services.jar disassembly. No device, no run.
- Tags: [seen] read in a file. [inferred] derived from names or structure. [unknown] not provable offline.

## Summary

- The interface is small: 14 methods plus 2 meta methods in V2 (8 in V1). Callback interface has 8 oneway methods.
- Only 3 methods are synchronous (`notifyTGPAfps`, `setCallback`, `unsetCallback`). All others are oneway.
- Java callers and SurfaceFlinger use a non-blocking lookup. Only `oiface` can block, and only on 6 call sites, never at start.
- A stub is cheap (about the size of the touch shim). Its value is low to medium and uncertain. See section 7.

## 1. Interface

### 1.1 `IGameOptHalService`

- Descriptor: `vendor.oplus.hardware.gameopt.IGameOptHalService` [seen]. The Java Stub builds it from `vendor$oplus$hardware$gameopt$IGameOptHalService` with `$` replaced by `.`.
- Stability: AIDL vendor stability (NDK libs `-V1-ndk`, `-V2-ndk`). The Java jar has no parcelable. All arguments are primitives and Strings. [seen]
- Meta transactions (both versions): `getInterfaceVersion` = 16777215, `getInterfaceHash` = 16777214 [seen].
- V1: version 1, hash `48394e9cdbb0aee7539e513a52c9a972cf2f3fc7` [seen].
- V2: version 2, hash `79187eecf42abc41850736c8590e8c5e0bea0660` [seen]. `IGameCallback` V2 has the same hash and version.
- V2 keeps codes 1-6 of V1 unchanged [seen] and adds 7-14.

Parcel layout for a call: interface token, then arguments in order. A oneway call has transact flag 1 and no reply parcel. A synchronous call has reply = exception header (int 0 for OK), then the result.

| Code | Method | Since | Arguments (in order) | Return | Flag [seen] |
|---|---|---|---|---|---|
| 1 | `notifyGameInfo` | V1 | int type, String info | void | oneway |
| 2 | `notifySFBufferProduced` | V1 | int, long | void | oneway |
| 3 | `notifyTGPAfps` | V1 | int fps | int | sync |
| 4 | `setCallback` | V1 | IGameCallback (strong binder) | int | sync |
| 5 | `setKeyThread` | V1 | String | void | oneway |
| 6 | `unsetCallback` | V1 | IGameCallback (strong binder) | int | sync |
| 7 | `registerCallback` | V2 | String key, IGameCallback | void | oneway |
| 8 | `unregisterCallback` | V2 | String key | void | oneway |
| 9 | `notifyCommonIntValue` | V2 | int type, long value | void | oneway |
| 10 | `notifyCommonStringValue` | V2 | int type, String value | void | oneway |
| 11 | `notifyCommonIntPair` | V2 | int type, int a, long b | void | oneway |
| 12 | `notifyCommonStringPair` | V2 | int type, String a, String b | void | oneway |
| 13 | `notifySchedFrameTime` | V2 | int, long, long, long | void | oneway |
| 14 | `notifyRptStatus` | V2 | int, int, long | void | oneway |
| 16777214 | `getInterfaceHash` | all | none | String | sync |
| 16777215 | `getInterfaceVersion` | all | none | int | sync |

- No parcelable, no list, no nullable type. The only binder argument is `IGameCallback`.
- The Java wrapper marks codes 7-14 as "needs version 2" (`checkVersionAtLeast(2)`) [seen]. A stub that reports version 1 would turn all V2 methods into no-ops on the Java side.

### 1.2 `IGameCallback` (calls HAL to client; client implements it)

All methods are oneway, one String argument unless noted [seen].

| Code | Method | Argument |
|---|---|---|
| 1 | `onNotify` | String |
| 2 | `onReadTop` | String |
| 3 | `onFrameLimit` | String |
| 4 | `onBigDataReport` | String |
| 5 | `onNotifyTemp` | String |
| 6 | `onFrameProduce` | String |
| 7 | `onInputCollect` | String |
| 8 | `onCommonCall` | String, int |

- Meta codes 16777214/16777215 as above. Same hash as the service interface.
- Payload strings look like JSON from the strings in `oiface` ("gpa_info", "targetFps", "COLLECT_DATA") [inferred].

## 2. Service name

- AIDL instance: `vendor.oplus.hardware.gameopt.IGameOptHalService/default` [seen]. The Java manager builds `DESCRIPTOR + "/default"` (`OplusGameOptManager.sServiceName`). `oiface` holds the descriptor from `IGameOptHalService::descriptor` and the string `/default`.
- Donor odm side [seen in scan.json]: `odm/bin/hw/vendor.oplus.hardware.gameopt-service`, rc `vendor.oplus.hardware.gameopt-service.rc`, `manifest_oplus_gameopt.xml`, libs `-V1-ndk`, `-V2-ndk` in odm. The service links `-V2-ndk` and `vendor.oplus.hardware.gameopt.aidl.service.cpp`. Its rc line shows the service-contexts form `...IGameOptHalService.default` [seen; dots are probably the scan's form of `/default`, [inferred]].
- `system/system/etc/vintf/compatibility_matrix.device.xml` [seen]:
  - `hal format="hidl"`, name `vendor.oplus.hardware.gameopt`, version 1.0, `IGameOptHalService/default`.
  - `hal format="aidl"`, name `vendor.oplus.hardware.gameopt`, version `1-2`, `IGameOptHalService/default`.
- The donor service is also a client of the hummingbird (hmbird) scheduler service (HAL-INVENTORY row `hummingbird`). pipa has no hmbird kernel part. [seen in the inventory]
- Clients in the donor [seen]:
  - `oiface` (NDK V2).
  - `surfaceflinger` (NDK V1; strings: "OplusGameOpt notifySFBufferProduced check service failed", "OplusGameOpt notifyGameInfo failed: %s", "VsyncAppSignal::toGameOpt").
  - `oplus-framework.jar` (`com.oplus.hardware.gameopt.OplusGameOptManager`, Java V2). `Bluetooth.apk` embeds the interface classes but no caller was found [unknown].
  - `oplus-services.jar` (`GameManagerServiceExtImpl`).
  - COSA (see section 4).

## 3. `oiface`

### 3.1 Does it run on pipa?

- `oiface.rc`: `class hal`, `user root`, `group system readproc root`, `capabilities SYS_NICE`, `disabled` [seen].
- Start conditions [seen]: `on property:sys.boot_completed=1 && property:persist.sys.oiface.enable=1` or `=2` starts it. `=0` stops it.
- `system_ext/etc/build.prop` line 90: `persist.sys.oiface.enable=2`; line 91 `persist.sys.hardcoder.name=oiface`; line 92 `persist.sys.oiface.feature=oiface:1f,oifaceim:ffffffff` [seen]. So the donor ROM starts `oiface` after boot on pipa, unless the port or a later prop file overrides it [inferred]. Needs a check on the device.
- `on init` block changes owner and mode of `/dev/stune/top-app/schedtune.boost`, `/dev/cpuctl/top-app/cpu.uclamp.min`, and the schedutil `target_loads`, `up_rate_limit_us`, `down_rate_limit_us` of policy0, 4, 6, 7 [seen]. SM8250 has policies 0, 4, 7 only. Policy6 does not exist on pipa [inferred].
- Other props read by the binary: `ro.oplus.oiface.gcp.extmode`, `persist.sys.oiface.control`, `persist.sys.oiface.loglevel`, `debug.oiface.trace.switch`, `debug.oiface.trace.pkg_name`, `sys.oplus.oiface.debuggable`, `ro.sys.engineering.pre`, `persist.sys.assert.enable`, `persist.sys.assert.panic`, `ro.oplus.image.system_ext.area|brand`, `ro.oplusupgrade.alpha.version` [seen].
- `oiface.config` (8.5 KB): GPU nodes `/sys/class/kgsl/kgsl-3d0/freq_table_mhz` and `gpu_clock_stats`, thermal zone names (MTK names such as `mtktscpu`, [seen]), per-game entries (sgame etc.) [seen].
- The port already creates `/dev/cpuset/oiface_fg`, `oiface_fg+`, `oiface_bg` in `early.sh` (step `2q`). That shows `oiface` was seen running on pipa before [inferred from repo notes; not verified].
- SELinux: the port has `oiface` rules in `maintainer/uifirst-policy/sa_block.cil` (sched_assist, frame_boost ioctl `0xdf01`) [seen]. The domain exists on pipa.
- Other HALs of `oiface`: `IPerformance`, `ICharger`, `IOplusProject` use non-blocking `checkService` [seen: all other lookups call `AServiceManager_checkService`].

### 3.2 How it gets the service

- Class `GameOptService` (singleton). Constructor only inits a mutex. It does no lookup [seen].
- Two lookups [seen]:
  - `GameOptService::checkService()` calls `AServiceManager_checkService`, then `IGameOptHalService::fromBinder`. Non-blocking.
  - `GameOptService::waitForService()` calls `AServiceManager_waitForService` (blocks until the service exists, no timeout). Then `fromBinder`, then `initServiceData()` (death recipient, `setCallBack`, restore saved values).
- Nothing calls the wait at process start. `oiface_main` starts the thread pool, adds `oplusoiface` to servicemanager, and joins the pool. `setThreadPoolMaxThreadCount(4)` [seen]. So `oiface` starts and registers without the HAL. Log: "add oplusoiface service success".
- Wait call sites (6) [seen]:
  - `OplusOIfaceService::oifaceControlSwitch` (binder thread) before `registerCallback` and `unregisterCallback`.
  - `OplusOIfaceService::packageSwitch` (binder thread) via `GameOptService::packageSwitch`.
  - `DecisionDriver::oifaceDecisionSetKeyThread` via `GameOptService::setKeyThread`.
  - One worker thread (named, started from the `setCallBack` / death logic) that waits again after a death [inferred].
- Check call sites (non-blocking) [seen]: `notifyGameInfo`, `setTfps`, `notifyCommonStringValue`, `notifyCommonIntPair`, `notifyCommonStringPair`, `readTopApp`-related paths, plus many `DecisionDriver::oifaceDecision*` functions (`GameMode`, `FoldingChange`, `GameQuality`, `GTMode`, `GPAFreqControl`, `GpaMargin`, `AcceleratorMode`, `SR`, `EDR`, `PlayerCount`, `GPAEvent`, `CpuCtrlPanel*`, `InputInfo`, `BindProcess`, `FrameInsert`, `FrameInnerInsert`, `SuperHighResolution`) all call `GameOptService::notifyGameInfo`. Also `GpaBpfHandler` and `GpaCallbackImpl::onCommonCall`.
- If the HAL never comes: the thread in the wait blocks forever, no retry, no log after the first message ("unable to get GameOpt service", "GameOptService check service failed") [seen strings]. Each blocked binder call uses one of 4 binder threads. After 4 blocked calls `oiface` cannot serve binder calls any more [inferred]. The caller of a synchronous call (COSA, system_server) waits too. A blocked decision call blocks the thread that runs the decision [inferred, caller thread not identified].
- The check paths just log and drop the notification.
- If the service dies: `DeathMonitor` -> `handleServiceDied`. After more than 10 deaths it prints "...abnormally exited %d times, more than 10 times, skip restore" and stops restoring. It does not restore when the game is not in the foreground [seen strings].

### 3.3 What `oiface` does with each method

| Method | `oiface` use | Feature [from strings] |
|---|---|---|
| `notifyGameInfo(type, str)` | Called by many `oifaceDecision*` handlers and saved for restore | Game mode, GPA, frame insert, SR, EDR, folding change, bind process ("notify gameopt bind process") |
| `setKeyThread(str)` | `oifaceDecisionSetKeyThread` ("add keyThread: %d", "remove keyThread", "set game tid %d as key thread") | Key thread protection for the game |
| `setTfps` -> `notifyTGPAfps(fps)` | From `generalOIfaceSignal` ("GameOptService tfps %d notify", "set_TargetFps") | Target FPS for TGPA |
| `packageSwitch` -> `notifyCommonStringPair` | "gpa pkg switch data", "gpa pkg config" saved and restored | GPA per-package switch |
| `notifyCommonIntValue/IntPair/StringValue/StringPair` | Saved with `save*Sdk2GameOpt` and restored after HAL restart | Misc. values from the SDK |
| `registerCallback`/`setCallback` | `GameOptService::registerCallback` picks V2 `registerCallback(key, cb)` if version is 2 or more, else `setCallback` [inferred from the version compare] | Receive HAL events |
| callbacks | 8 lambdas in `setCallBack`; results go to `OifaceCallbackManager` (`reportFB`, `reportTGPAInfo`, `reportThermalStatus`, `reportGameStatus`, `setInputCollection`, `setThermalFps`, `setFrameTraceFps` ...) | Frame boost status, temperature fps limit, input collection, big data |
| `notifySFBufferProduced`, `notifySchedFrameTime`, `notifyRptStatus` | No call site in `oiface` found | SF and frame scheduling data [unknown consumer] |

- Real work of `oiface` on pipa (own sysfs writes): `/dev/stune/top-app/schedtune.boost`, `/dev/cpuset/oiface_*`, schedutil nodes, `/proc/oplus_scheduler/sched_assist/ux_task`, `/proc/.../frame_boost` ioctl, `/sys/class/kgsl/kgsl-3d0/*`, `/sys/devices/system/cpu/cpufreq/policy%d/*`. It also tries MTK nodes (`/sys/kernel/fpsgo/...`, `/sys/module/fbt_cpu/...`, `/sys/module/mtk_fpsgo/...`). These are absent on SM8250 [seen strings, absence inferred].
- Input: the HAL is the sink for what `oiface` sends. It is not needed for `oiface` to run its own boosts.

## 4. Java callers

Lookup kind: `ServiceManager.checkService(DESCRIPTOR + "/default")` in `OplusGameOptManager.getService()` (synchronized, cached, `linkToDeath`). Non-blocking. Null result: log "getService fail." and return [seen].

Null handling [seen]:
- `notify*` return void: null service means silent drop. `notifyTGPAfps` returns -1 on failure.
- `registerGameCallback` / `unregisterGameCallback` return -1 on failure; the wrapper keeps its callback list.
- Each `notifyGameInfo`, `notifyCommon*`, `notifyTGPAfps` first forwards the value to `oplusoiface` (`com.oplus.oiface.IOIfaceService`, `saveXToOiface`) before the HAL call. So `oiface` keeps its copy even without the HAL.
- `checkOifaceService` uses `ServiceManager.checkService("oplusoiface")` [seen].

Callers [seen in the COSA app and oplus-services.jar]:

| Caller | Methods | Feature |
|---|---|---|
| `com.oplus.cosa.service.COSAService` | `notifyGameInfo`, `notifyTGPAfps`, `notifyCommon{IntValue,IntPair,StringValue,StringPair}` | Game info / GPA data from the COSA service |
| `com.oplus.feature.gameopt.GameOptFeature` | `notifyGameInfo` x7 (types 135, 139, 153 with prefix "setfpsgo:", strings "ether_vip", "ether_shortPerf", "ether_longStable") | Performance modes |
| `...gameopt.actionfeatures.PerformanceSetting$f` | `notifyGameInfo` | Performance setting |
| `com.oplus.feature.gpa4.Gpa4Feature` | `registerCallback("cosa", cb)` | GPA4 receives HAL events; key "gpa_re_enable" nearby |
| `com.oplus.feature.gpa4.JoystickSettingNotifier` | `notifyCommonStringValue` | Joystick data |
| `CosaAmtManager`, `CosaAMTService`, `CosaAmtManager$resumeAmtFeature$1`, `ORMScontrol` | `notifyGameInfo` | AMT / ORMS control |
| Obfuscated COSA classes `h6/b`, `q6/a`, `p5/a`, `w0/i`, `ea/m`, `h5/j`, `x7/a` | `notifyGameInfo`, `notifyCommon*`, `notifyTGPAfps` | Game data ("gameopt_info", "gameopt_tfps", "gameopt_bind_process" strings) |
| `com.android.server.app.GameManagerServiceExtImpl.notifyGameOptGameStart` | `notifyGameInfo(185, ...)` | Game start signal from system_server |
| `surfaceflinger` (NDK V1) | `notifyGameInfo`, `notifySFBufferProduced` via `checkService` | Frame hints for game layer |

- Return values of `notifyTGPAfps` are ignored by COSA [seen].

## 5. User-visible effect of the missing HAL

All items are [inferred] from names. No device test.

- Silent no-ops: SF frame hints, game start and game info on the HAL side, key-thread protection, GPA package switch, target-FPS handoff, GPA4 callbacks (frame-limit, temperature fps, input collection, frame produce).
- Not affected: values that Java sends to `oiface` first (it keeps them); `oiface` own boosts (cpuset, schedtune, uclamp, kgsl) if its nodes exist.
- Risk of a visible stall: `registerCallback` / `packageSwitch` / `setKeyThread` can block `oiface` binder threads. After 4 blocked calls `oiface` stops answering Game Space / COSA calls. Whether this happens depends on whether COSA calls `registerCallback` through `oiface` (the Java `Gpa4Feature` uses the HAL directly with the key "cosa", so the path through `oiface` `oifaceControlSwitch` is a second user [unknown]).
- Likely affected settings of the Games app / Game Assistant (performance mode, frame insertion, touch response, "X-mode", MTK fpsgo strings in `GameOptFeature`): the effect is small, because the HAL on the donor mostly drives the hmbird scheduler and OPPO kernel parts that pipa lacks [inferred, HAL-INVENTORY]. Which UI toggles exist in this donor Games app is not checked here [unknown].

## 6. Stub plan

Model: the touch shim (`TouchService.java`, host + registrar started by `pipa_port`). Name `vendor.oplus.hardware.gameopt.IGameOptHalService/default`. Label `oplus_absent_service`. No VINTF entry. Binder stability: system. NDK clients check the interface only by `fromBinder` on the descriptor; stability flags on the pipa `servicemanager` for VINTF-less names follow the touch shim result [inferred].

| Code | Method | Answer | Needed to avoid block/loop? | Real pipa control [inferred] |
|---|---|---|---|---|
| 16777215 | `getInterfaceVersion` | 2 | Yes (version gate in `oiface` and Java) | none |
| 16777214 | `getInterfaceHash` | `79187eecf42abc41850736c8590e8c5e0bea0660` | Yes (NDK client may ask) | none |
| 1 | `notifyGameInfo` | accept, drop (oneway) | No | type 185 game start could set a "game" flag only |
| 2 | `notifySFBufferProduced` | drop at once (per-frame) | No | none |
| 3 | `notifyTGPAfps` | reply int 0 | No (sync, so must reply) | none |
| 4 | `setCallback` | store binder, reply int 0 | Yes (sync; non-zero or error makes `oiface` log "setCallBack failed") | none |
| 5 | `setKeyThread` | drop | No | tid to `/dev/cpuset/oiface_fg+/tasks` or uclamp; risky |
| 6 | `unsetCallback` | remove binder, reply int 0 | Yes (sync) | none |
| 7 | `registerCallback` | store by key (max 32), no reply | No | none |
| 8 | `unregisterCallback` | remove key | No | none |
| 9-12 | `notifyCommon*` | drop | No | none |
| 13 | `notifySchedFrameTime` | drop | No | none |
| 14 | `notifyRptStatus` | drop | No | none |

- Must answer: the three meta/sync calls (3, 4, 6, plus 16777214/16777215). They stop a sync caller from waiting on an unknown code. An unknown code returns an error status and does not hang, but `oiface` treats it as a failed set.
- Presence alone ends the six `waitForService` blocks of `oiface`. This is the main gain.
- Callbacks: store only, never call. Calling `onNotify` etc. makes `oiface` and COSA start real GPA work with fake data. Dead callbacks: drop on `linkToDeath` to avoid a leak; the touch shim keeps them until unregister, which is also fine.
- Possible real mappings (all [inferred], not for the first version):
  - key thread -> `cpuset` `oiface_fg+` (made by the port) or `uclamp.min` in `/dev/cpuctl/top-app` (SM8250 has it per the donor rc).
  - GPU min freq -> `/sys/class/kgsl/kgsl-3d0/min_clock_mhz` or `devfreq/min_freq`.
  - CPU min freq -> `/sys/devices/system/cpu/cpufreq/policy{0,4,7}/scaling_min_freq`.
  - Touch boost -> Xiaomi touch node via the touch shim (not tied to this HAL).
- Risks:
  - A registered service makes `oiface` call `initServiceData`, set callbacks and replay saved values on each deathless restart. All of these are no-ops here.
  - `oiface` then runs its normal GPA path and may write MTK-only nodes or SM8250 nodes with OPPO targets (e.g. schedutil `target_loads`). That is already the case today for the non-HAL paths [inferred].
  - Binder traffic from `surfaceflinger`: it would send `notifySFBufferProduced` per frame for game layers once a service exists. A oneway call is cheap, but it adds a binder transaction per frame. Drop it in the first line of the handler. Measure with Perfetto (project rule in AGENTS.md).
  - SELinux: `oplus_absent_service` allows `find` for `system_server` and `pipa_port` only (touch shim rules). `oiface`, `surfaceflinger` and the COSA app domain also need `find` [inferred from the cil of the touch step]. Without it the lookups fail silently and the stub is not used. Compile rules with `secilc` before the build (AGENTS.md).
  - Host process death: `oiface` restore thread calls `waitForService` again and then replays. If the host is not restarted, it blocks the same way as today.
  - Version: report 2 only if all of codes 1-14 are implemented, even as drops.

## 7. Verdict

- Worth it: yes, as a small safety item. Not as a performance feature.
  - Pro: removes the only indefinite blocking path in `oiface` (6 wait sites, 4 binder threads). Java and SF paths are non-blocking and cost nothing today.
  - Con: no performance gain without OPPO kernel parts (hmbird, frame_boost, osense) that pipa lacks.
  - Open: whether `oiface` really blocks in practice on pipa. A device check comes first (see below). If no thread is ever blocked, skip the stub.
- Size: about 250 to 350 lines of Java (service with 16 codes, a parcel reader for the 14 layouts, a store for up to 32 callbacks, metadata) plus the host and registrar copied from the touch shim. One step file, a service-contexts line, and about 5 CIL lines. Same effort class as the touch shim without the node mapping.
- Device tests (adb root):
  - `pidof oiface` and `getprop persist.sys.oiface.enable` (is it running?).
  - `service list | grep -i -e oiface -e gameopt` (is `oplusoiface` there, is the HAL absent?).
  - `dumpsys -l | grep -i oiface`, `dumpsys oplusoiface` [name unverified].
  - Blocked threads: `debuggerd -b $(pidof oiface)` (look for `AServiceManager_waitForService` in a binder thread). `ls /proc/$(pidof oiface)/task | wc -l`.
  - Log tags: `OplusGameOptManager` (Java), `oiface` / `GameOptService` (native), `COSA`, `GameManagerServiceExt`, `GPA4Feature`. Look for "unable to get GameOpt service", "GameOptService check service failed", "getService fail.", "GameOpt Service setCallBack done", "gameopt service abnormally exited".
  - After the stub: `service call` is not needed; run a game, check "setCallBack done" and no stuck binder thread. Compare Perfetto FrameTimeline with and without the stub (`maintainer/perfetto/traced_heavy.sh`).
  - SELinux: `persist.logd.audit.rate 2000`, reboot, list `scontext=u:r:oiface` and `scontext=u:r:surfaceflinger` denials for `oplus_absent_service`.

## Open questions

1. Does `oiface` run on pipa now, and is `persist.sys.oiface.enable` still 2? [unknown]
2. Which binder or looper thread runs `oifaceDecisionSetKeyThread`? If it is the main decision looper, one missing HAL stalls all decisions. [unknown]
3. Does a user-facing path reach `registerCallback` / `packageSwitch` through `oiface` on pipa (COSA calls)? [unknown]
4. What do the `notifyGameInfo` type numbers mean (135, 139, 153, 185 and others)? Only 4 values were seen.
5. Does SF send `notifySFBufferProduced` only for game layers? Cost with a stub. [unknown]
6. Return value contract of `setCallback`/`unsetCallback`/`notifyTGPAfps`: 0 is assumed success. The donor HAL binary is not available. [unknown]
7. The Games app / Game Assistant toggles that need the HAL: not checked in `OplusGames` or `GameSpace` dumps.
8. The service-contexts line form (`.default` vs `/default`) of the donor odm: confirm in `precompiled_service_contexts`.
