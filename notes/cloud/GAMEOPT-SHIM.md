# SPEC-GAMEOPT: what the donor `gameopt` service does, and what a pipa shim can do

- Date: 2026-11-03. Method: static only (donor C.06 files, no device). Nothing was run.
- Scope: `vendor.oplus.hardware.gameopt.IGameOptHalService/default`, codes 1-14 and `IGameCallback` 1-8.
  The interface itself is in `git show cloud/hal-inventory:notes/cloud/GAMEOPT.md` and is not repeated here.
- Tags: [seen] read in a binary, string or kernel source. [inferred] derived from structure or names.
  [unknown] not provable offline.
- Donor binary: `donor odm/bin/hw/vendor.oplus.hardware.gameopt-service` (aarch64, 5.1 MB, stripped, but
  `.gnu_debugdata` has 7115 function names). Function addresses below are virtual addresses in that file.
- Kernel: `kernel_xiaomi_pipa_cos17/` (branch `oppo`), config `arch/arm64/configs/vendor/xiaomi/pipa-oplus.config`.
  Quoted kernel lines are GPL and come from that tree.

## 0. Result in six lines

1. The donor service is the whole OPPO "GPA" game engine (about 7000 functions: frame modelling, frequency governors,
   GPU/DDR control, thermal prediction, NPU, scene logic). The 14 AIDL methods are only a thin front end that
   puts messages on a handler thread.
2. Almost every kernel/sysfs node that engine writes belongs to OPPO modules that **do not exist on pipa**
   (`/proc/game_opt/*`, `/proc/hmbird_sched/*`, `/proc/sys/hmbird_II/*`, `/proc/sys/walt/*`, `/proc/uag`,
   `/proc/oplus_cpu`, kgsl `dcvs_tunables`, `bus_dcvs`, MTK `fpsgo`). Run unchanged, the donor would do close to nothing on pipa.
3. The donor's own key-thread discovery (render thread, heavy tasks, wake-up tracking) reads `/proc/game_opt/rt_info`,
   `render_thread_info` and `heavy_task_info`. They are absent. So the donor only acts on thread ids that a client sends.
4. What the pipa kernel can really do for a game thread is small and well known:
   (a) UX state of a thread (`/proc/oplus_scheduler/sched_assist/ux_task`, text, pure Java is enough),
   (b) preferred cluster of a thread and (c) membership of the "game frame group" (both ioctls on
   `/proc/oplus_frame_boost/sys_ctrl`, need native code; (c) has no scheduling effect in this kernel).
5. The donor sets thread UX through the stock performance HAL (`IPerformance::writeUxState(pid, tid, value)`), which
   writes `/proc/<pid>/task/<tid>/ux_state`. The values the donor uses (0x81 = SET|LIGHT, 0x82 = SET|HEAVY) have exactly
   the meaning that the pipa kernel gives them. So a key-thread shim is a faithful port, not an invention.
6. The shim must be better than the donor on cleanup: the donor leaves `ux_state` set when it dies. Section 8 gives the reset rules.

## 1. Donor service structure

### 1.1 Process

- rc `odm/etc/init/vendor.oplus.hardware.gameopt-service.rc`: service `gameopt_hal_service-1-0`, `class hal`, `user root`,
  `group system readproc root`, `capabilities SYS_NICE SYS_ADMIN`, `interface aidl ...IGameOptHalService/default`,
  `disabled`, `oneshot` [seen]. It is started on demand by the service manager (lazy HAL).
- The rc also has three property triggers [seen]: `vendor.oplus.gameopt.sde.enable` (MTK `/proc/mtkfb`, `sde` trace events),
  `vendor.oplus.gameopt.perfdog.timerslack` (writes `/proc/${vendor.oplus.gameopt.perfdog.tid}/timerslack_ns`).
  Neither is needed on pipa.
- NEEDED libs [seen]: `libqti-perfd-client`, `libbinder_ndk`, `libtinyxml2`, `liboplus-uah-client`,
  `libosensenativeproxy_client`, `vendor.oplus.hardware.gameopt-V2-ndk`, `vendor.oplus.hardware.performance-V1-ndk`,
  `vendor.oplus.hardware.hummingbird-V1-ndk`, `android.frameworks.stats-V1-ndk`. Plugin libs by `dlopen`:
  `/odm/lib64/libcdgo.so`, `/odm/lib64/AIMotion/libQnnHtp.so` (NPU).
- Binder side: `GameOptHalService` (implementation class). Its constructor starts a `MultipleThreadPool`, clears old
  controllers (`FreqControl::deleteController`, `MemFreqControl::releaseAllControl`, `SchedExtManager::clearConfig`)
  and logs "new GameOptHalService" [seen at 0xa5984]. Every method wraps its work in a `DeadlockGuard` (id in the range
  0x9f..) that a watchdog (`DeadlockGuardManager`) times; on timeout it only logs "Any Guardian timeout" [seen].

### 1.2 Threads, timers

| Thread / timer | Purpose | Evidence |
|---|---|---|
| `GameMsgServer::runLoop` (handler thread) | Receives the `GameMessage{what, str}` of every `notifyGameInfo`, `setKeyThread`, `notifyTGPAfps` call. Dispatches by `what` to a `std::function` table (about 120 entries, `initMessageHandlers` at 0xc6698). | [seen] |
| `SceneCenter` handler | Scene state machine (game mode, quality, folding, SR, EDR ...). Fed by `makeSceneChangeRequest(SCENETYPE,int)`. | [seen] |
| `TaskManager` handler `taskHandler` (`gameopt::Handler`) | Key task search and apply. Internal message ids 0xca-0xd3 (set game zone, find key task, start tracking, update wake-up tasks ...). Uses `sendMessageDelayed`. | [seen] |
| Poll threads | `GpuControl::gpuStatPollThreadEntry`, `FrameDataTracker`, `TimelineTracker`, `TempMonitor`, `ReadTopAppEvent`, `FrameRepeatedlyNotifier` (frame produce notifications), `RptRepeatedlyNotifier` | [seen] |
| Delayed work | `TaskManager` config keys `delay_time`, `recognize_interval`, `wake_up_times`, `task_count`; log "start tracking, delay time %lldms" | [seen] |
| Watchdogs | `DeadlockGuardManager`, `EpollCallWatchdog`, `FreqGovernorWatchdog`, `FreqControlWatchdog`, `GpaCoreWatchdog` | [seen] |

### 1.3 Other services it calls

| Service | Used for | Pipa |
|---|---|---|
| `vendor.oplus.hardware.performance` `IPerformance` (AIDL, V1 client, `checkService`) | `writeUxState(string pid, string tid, string value, int* ret)` = vtable slot 0x4e8 of `PerformanceProxy::setKeyTask(int,int,int)` at 0xfd538 [seen]. The stock performance HAL then writes `/proc/<pid>/task/<tid>/ux_state` (its strings: "writeUxState: write path %s with value %s, tid is %s", "Failed to write pid %s with ux_state %s (%d): %s", [seen] in `odm/bin/hw/vendor-oplus-hardware-performance-V1-service`). | Service is present on pipa (HAL-INVENTORY row `performance`). A shim can call it or write the node itself. |
| `vendor.oplus.hardware.hummingbird` `IOplusHmbirdService` (`HmbirdServiceProxy`) | Only message type 179 (`getHmbirdStatus`) and HmbirdControlV2 BPF ops. | Absent by design. Nothing to do. |
| `liboplus-uah-client` -> `urcc` HAL (`uahRuleCtl`, `UahGetPMStatus`) | `GpuLevelControl::setGpuValue(UahResourceCmd,...)` and other CPU/GPU level requests. | urcc is absent. Nothing to do. |
| `vendor.oplus.hardware.thermalmodel` classes (linked in) | Temperature prediction, `TempPredictCloudConfigManager::activateFpsByTgpaFps` | Internal. Produces callbacks 4 and 121-124 only. |
| `AIDL IOplusHmbirdService` death handler, "Thermal service died" | Logs only | - |
| oiface back-calls | None by the HAL. The HAL only calls the `IGameCallback` that oiface registered (section 5). | - |

### 1.4 Files it reads or writes (all strings of the binary, with the node's fate on pipa)

Config comes from the clients, not from files: `notifyGameInfo(104, <config json>)` carries the per-game config
("notify config %s"), and the package switch (type 100) carries the state. The only static file inputs are
`/odm/etc/game_thermal_profile/game_thermal_config.xml` and `heavy_game_list.xml` (thermal prediction, not needed).
Scratch/state: `/data/vendor/gameopt/` (`daemon_data.json`, `daemon_report.json`, `hmbird.log`, `apid_tuner/*`),
`/data/local/tmp/` (`Ips.conf`, `FrameOffline`, `FrameUtilPred`).

Nodes the donor touches that **exist** in the pipa kernel [seen both sides]:

| Node | Donor user | Pipa kernel |
|---|---|---|
| `/proc/<pid>/task/<tid>/ux_state` (via perf HAL) | `PerformanceProxy::setKeyTask`, `GameoptUx` | yes (`fs/proc/base.c:3989`, handler `proc_ux_state_write`) |
| `/proc/oplus_frame_boost/sys_ctrl` ioctls 0xdf01/0xdf02/0xdf03 | `GameoptIoctl::bindMainThread`/`unbindMainThread`, `addKeyThread`/`removeKeyThread`, `readFbgInfo` | yes, same numbers (section 4.3) |
| `/sys/class/kgsl/kgsl-3d0/{min_pwrlevel,max_pwrlevel}` | `android::AdrenoFreqController` (started by `android::PIService::Init`) | yes (stock kgsl) |
| `/sys/devices/system/cpu/cpufreq/policy*/scaling_governor` | `CpufreqControl::ensureCurrentPolicy` (read) | yes |
| `/sys/class/power_supply/battery/{current_now,voltage_now}` | power sampling | yes |

Nodes the donor touches that **do not exist** on pipa [grep of kernel tree, no match]:
`/proc/game_opt/**` (task_boost, early_detect, gpu_ctrl, frame_sync, frame_load_track, multi_task, es4g, tlt_ctrl, geas_*, rt_info,
render_thread_info, heavy_task_info, game_pid, ui_assist_thread, lock_stealing, sf_app_wakee_info, tt_user, yield_*, cpu_max_freq,
cpu_min_freq, dsu_freq ...), `/proc/hmbird_sched/**`, `/proc/sys/hmbird_II/**`, `/proc/oplus_hmbird`, `/proc/sys/oplus_sched_ext/**`,
`/proc/sys/walt/*` (pipa's WALT sysctls are under `/proc/sys/kernel/`), `/proc/uag/is_game_scene`, `/proc/oplus_cpu/disable_inefficient`,
`/proc/oplus_frame_boost/game_ed_info`, `/proc/oplus_scheduler/sched_assist/{sched_prop,pipeline_args,pipeline_pids_cpus,pipeline_prime_rearrange,lb_enable}`,
`/proc/game_frame_sync`, `/proc/slbc`, `/proc/cpuqosmgr`, `/proc/oplus_slc`, `/config/*mpam*`, kgsl `dcvs_boost`, `dcvs_tuning_*`, `bus_pi_*`,
`gmu/dcvs_tunables/*`, `devfreq/.../kgsl-busmon/*`, `/sys/devices/system/cpu/bus_dcvs/**`, `/sys/devices/system/cpu/qcom_cpuctl/prefetch_ctl`,
`/sys/kernel/fpsgo/**`, `/sys/kernel/ged`, `/sys/kernel/cm_mgr`, `/sys/kernel/sched_penalty`, `/sys/module/oplus_{binder,locking}_strategy`.
`CONFIG_UCLAMP_TASK` is off (`# CONFIG_UCLAMP_TASK is not set`), so the donor's uclamp paths (`setUclamp` in `TaskManager::handleKeyTasks`, cgroup `cpu.uclamp.*`) also fail.

## 2. Per method: what the donor does (codes 1-14)

All oneway except 3, 4, 6. A call becomes a `GameMessage{what, int arg, string}` and returns at once. Addresses are in the donor binary.

| Code | Method | Donor path | Result in donor |
|---|---|---|---|
| 1 | `notifyGameInfo(type, info)` 0xa6458 | Fast inline cases for types 109, 141, 142, 143, 151, 182, 183, 185 (see 3.1). All others: `GameMessage{type, info}`; type 900 (0x384) to `SceneMsgServer`, rest to `GameMsgServer::sendMsg`. Log: `"[<type>] <info>"` at debug level. | Dispatch table of section 3. |
| 2 | `notifySFBufferProduced(int, long)` 0xa61f0 | `GameoptIoctl::readFbgInfo()` (ioctl 0xc010df03 on `/proc/oplus_frame_boost/sys_ctrl`: frame_scale, frame_busy of the game frame group), then `GameMsgServer::frameBufferProduceNotification(int, long)` 0xc01c8. | Feeds `FrameDataTracker`, `TimelineTracker`, `FrameRepeatedlyNotifier`. They drive callback 6 and the GPA governors. The kernel read is real on pipa. Rest is internal. |
| 3 | `notifyTGPAfps(int fps, int* ret)` 0xa6f0c | Log "notifyTGPAfps targetFps:%d". `GameMessage{what=1, arg=fps}`. Handler (0xc9458) logs "handle TGPA tfps %d to %d", `TargetFpsDecider::updateTargetFps(type, fps, ...)`, `TempPredictCloudConfigManager::activateFpsByTgpaFps(fps)`, `TaskManager::resetUpdateInterval()`. `*ret = 0`. | `TargetFpsDecider` only stores the value and calls the callbacks registered by about 20 governors/boosts (`FrameDataTracker`, `GpuControl`, `FreqGovernor`, `EarlyDetect`, `GameScene` ...). No kernel write on its own. |
| 4 | `setCallback(cb, int*)` 0xa7124 | `cb != null`: `GameCallBackManager::registerCallBack(cb)`; `*ret = 0`. `cb == null`: `*ret = -1`. | Stores one legacy callback. For each callback type it adds a lambda that calls the matching `IGameCallback` method (section 5). |
| 5 | `setKeyThread(str)` 0xa5e0c | Log "setKeyThread: %s". `GameMessage{what=5, str}` -> handler -> `TaskManager::setGameZone(str)` (0xd7698), which posts an internal message to the `taskHandler`. | Key thread search and apply, see 2.1. |
| 6 | `unsetCallback(cb, int*)` 0xa725c | Logs "unsetCallback". `*ret = 0` (or -1 for null). It does **not** remove anything in the paths I could read. [inferred: callback is only dropped when the process dies or a new `setCallback` replaces it] | None. |
| 7 | `registerCallback(key, cb)` 0xa7354 | `gpa::GpaService::setCallback(key, IGpaCallback wrapper)` -> `GpaCallbackManager` map keyed by string. Null cb: log only. | Keyed callbacks. `GpaCallbackManager` methods: `reportBigData`, `gpaStatus`, `frameTrace`, `sceneStateChange`, `bigDataInfo`, `joystickInfo`, `testBinderCall`. |
| 8 | `unregisterCallback(key)` 0xa75fc | `gpa::GpaService::unsetCallback(key)` | Drops that key. |
| 9 | `notifyCommonIntValue(type, long)` 0xa7718 | Log, then `gpa::GpaService::notifyCommonInfo(type, int or long long)` | GPA engine input (SDK values from COSA). |
| 10 | `notifyCommonStringValue(type, str)` 0xa7808 | `gpa::GpaService::notifyCommonInfo(type, string)` | same |
| 11 | `notifyCommonIntPair(type, int a, long b)` 0xa78e8 | `notifyCommonInfo(type, int, int or long long)`. Log "type: %d, key: %d, value %ld". | same |
| 12 | `notifyCommonStringPair(type, a, b)` 0xa79e4 | `notifyCommonInfo(type, int key, string value)`. Log "type: %d, key: %s, value %s". | same. oiface uses 303 (string value), 304/306 (pairs), 4 (int pair). |
| 13 | `notifySchedFrameTime(int bufNum, long produce, long consume, long reserve)` 0xa7af4 | `TimelineTracker::updateTime(TimelineRecorder)`, then `frameBufferProduceNotification`. Log "notifySchedFrameTime bufferNum: %d, produce: %lld, consume: %lld, reserve: %lld". | Frame timeline model. Internal. |
| 14 | `notifyRptStatus(int total, int current, long time)` 0xa7c54 | Log only: "notifyRptStatus totalRp: %d, currentRp: %d, time: %lld". [seen] no further call | None. |
| 16777214/5 | meta | AIDL stub (version 2, hash in GAMEOPT.md) | - |

### 2.1 Key thread flow (code 5, and the thread-bearing `notifyGameInfo` types)

Clients and payloads [seen]:

- COSA `GameZone` (`com.oplus.feature.gameopt.actionfeatures.GameZone`) builds a JSON object with keys
  `type`="key_thread", `status` ("1" set, "0" clear), `pid` (string), `key_thread_ux` (string integer, cloud value),
  and a JSON array of thread names (cloud key `white_list`). Clear form: `{"type":"key_thread","status":"0","pid":"<pid>"}`.
  Other cloud keys in that class: `delay`, `real_proc_name`.
- COSA sends it to oiface (`m7.c.a(String)`), and `DecisionDriver::oifaceDecisionSetKeyThread` (oiface 0x35c60) parses
  these keys: `status`, `pid`, `key_thread_value`, `key_worker_value`, `key_worker`, `bind_core`, plus the names
  `InputReader`, `InputDispatcher`, `system_server`. It then calls `GameOptService::setKeyThread(String, int, int)` (0x9a0c4),
  which sends a JSON string to HAL code 5. The exact HAL-side JSON is not visible offline [unknown]; a lenient parser is required.
- HAL side keys seen near `setGameZone`/`handleMessage`: `game_pkg_name`, `is_cold_start`, log text "startSpeedUp, pid: %d
  (mGamePid: %d), pkgName: %s, isColdStart: %s", "startSpeedUp, json data parse failed! jsonData: %s" [seen].
- `TaskManager::parseConfig` (config from type 104) knows these keys: `key_thread_ux`, `key_worker_ux`, `white_list_ux`,
  `white_list`, `black_list`, `bind_core`, `bind_main`, `bind_list`, `steam_list`, `monitor_by_gl`, `fbg_restrict`,
  `search_white_list`, `skip_gs_sa`, `pipeline_rearrange`, `wakeup_decay`, `load_tracking`, `start_speed_up`, `uc_thread`,
  `SafeGuardUxThread`, `DynamicUxThread`, `sf_app_wakee_tid_diff`, `ui_assist`, `lsr_list`, `delay_time`, `recognize_interval`,
  `wake_up_times`, `task_count`, `safeguard`, `preempt` [seen].

What `TaskManager` does with a thread id (`handleKeyTasks` 0xde6c8, `setKeyTask` 0xedf8c):

1. Find the thread: by name in the white/bind/preempt lists (`searchTaskByName`, `GetPidByName`; special name `__render__` = render thread,
   [inferred] "RenderThread"), by GL thread id (message from type 109), by load or heavy-task nodes (absent on pipa).
2. Apply UX value: `PerformanceProxy::setKeyTask(pid, tid, value)` -> perf HAL `writeUxState` -> `ux_state` node. Value is the
   configured `key_thread_ux`/`white_list_ux` integer. The code compares priorities first and logs "thread has a small nice value" /
   "set priority to ux prio(%d) failed" / "set nice value repeatedly" [seen].
3. Optional extras, each with a node that is absent on pipa: `prefer-prio`/`prefer-cpu` (hmbird_II), pipeline list
   (`pipeline_pids_cpus`), `/proc/game_opt/{lock_stealing,tt_user,ui_assist_thread,sf_app_wakee_info,skip_gameself_setaffinity}`,
   `/proc/sys/oplus_sched_ext/pid_unitymain`, uclamp, MPAM tasks file.
4. Optional extras with a pipa node: `GameoptIoctl::bindMainThread` (preferred cluster, `bind_main`), `GameoptIoctl::addKeyThread`
   (game frame group, always done for the final key task list).
5. Reset: `stopGameZone` (0xdb274, 5.9 KB): `setKeyTask(..., 0 value)` for every recorded thread, `removeKeyThread()` (ioctl),
   clear `pipeline_pids_cpus`, write 0 to the game_opt nodes, `osenseBatchRemoveKeyThread`/`osenseReleaseSysResource`.
   Triggered from `parseConfig` (new config) and when tracking fails ("couldn't track key task, stop game zone!").

Other thread-bearing `notifyGameInfo` types [seen]:

- 109 `GameInfoCenter::setGLThread(str)`: format `"<pid>_<tid>"` (split on `_`, both all digits, `stoi`; log "setGLThread %ld, name %s, pid %d, glthread %d"). Name is read from `/proc` by `GPA::getTaskNameByTid`. Then `TaskManager::setGLThread()` and `GameBroadcastLive::notifyBroadcastLiveOff`. Sent by `OIfaceServer::handleMessage` (GL/Vulkan notification).
- 144 `GameInfoCenter::setCriticalThreadInfo(str)`: JSON object, member name -> value (`getMemberNames`, `getJsonValue`) [seen]; consumed by `handleKeyTasks` ("new key task, tid %d name: %s").
- 141 `setFrameInsertThread(str)` + `FrameInsert::notifyFrameInsertThread(str)`: thread of the frame-insert engine. 124/140/164: `FrameInsert`.
- 120: `bind process` (oiface `oifaceDecisionBindProcess`): not in the handler table I extracted. [unknown handler; falls in the default log path]

## 3. `notifyGameInfo` types

### 3.1 Inline cases before the handler table (0xa6458)

The function first tests the type against a short compare chain (109, 141, 142, 143, 151, 182, 183, 185). All other types go straight to the table. [seen]

| Type | Inline effect |
|---|---|
| 109 | If the `GpaCore` "ignore" flag (byte +0x78) is set, return OK at once. Otherwise continue to the table (GL thread, see 2.1). |
| 141 | Stores `info != ""` in a service flag (byte +0x51), then continues to the table (`setFrameInsertThread`). |
| 142 | Only when that flag is 1: splits `info` with `FpsgoStrategy::splitString`, registers a `DeadlockGuard` (id 126), then continues to the default message path. No table entry. |
| 143 | `GameMsgServer::scheduleFrameResult(info)` (after the same `GpaCore` flag test, and a `GameoptIoctl::readFbgInfo` when a mode flag is set). Returns OK. |
| 151 | `GameMsgServer::logicStartNotification(atoll(info))`. Returns OK. |
| 182 / 183 | `PinchBoost::refreshTickStart(atoll(info))` / `refreshTickEnd(atoll(info))`. Returns OK. |
| 185 | `TaskManager::gmsDirectToGameOpt(info)` (JSON, log "gmsDirectToGameOpt, jsonData: %s"). Returns OK. |

### 3.2 Handler table (type -> action). Pipa column says whether any effect is possible.

Handler table extracted from `GameMsgServer::initMessageHandlers` (0xc6698). "Engine" means: sets state in the GPA engine
(`SceneCenter::makeSceneChangeRequest`, `FpsgoStrategy` (MTK fpsgo), `GameSceneCenter`...). It needs absent nodes to have
a visible effect. Pipa: none unless noted.

| Type | Meaning / handler | Payload [seen unless noted] | Pipa |
|---|---|---|---|
| 1 | TGPA target fps (from code 3) | arg=fps | none (store) |
| 2 | `frameBufferProduceNotification` (from code 2) | - | none |
| 5 | key thread (from code 5) -> `TaskManager::setGameZone` | JSON | **ux_state**, see 7 |
| 9, 10, 123 | `TargetFpsDecider::updateTargetFps` (10 also `resetUpdateInterval`); 123 = refresh rate "notify refresh rate %s" (digits) | digits | none (store) |
| 13 | glog `startPollBuffer` | - | none |
| 100 | package switch -> `GameMsgServer::packageSwitch(str)` (0xbf30c). JSON keys seen: `pkgStatus` (int), `secondPackage`, `pid` (log "pid:", "current package is %s", "invalid msg data format"). The first package key is not visible [unknown]. `pkgStatus` is turned into an internal message [seen, compare chain at 0xbfa38-0xbfb68]: **11 and 12 -> 400 (foreground)**, **1 -> 401 (background)**, **3 -> 402 (new game to foreground)**, **4 -> 403**, **5 -> 404**. Also `FpsgoStrategy::updateStatus`, `CdgoProxy::setForegroundPackage`, `GameInfoCenter` current package. | JSON | **fg/bg state (the only source of fg/bg)** |
| 101 | `CdgoProxy::setLogLevel(int)` | digits | none |
| 102 | `GpaCore::notifyTopApp(str)`; log "notify top app %s"; "current package is not a top app, stop gpa and gamezone"; triggers callback 2 (`onReadTop`) via `ReadTopAppEvent` | JSON with `status` [seen key] | state only |
| 103 | game mode: `FpsgoStrategy`, scene change (SCENETYPE 12), `TempMonitor::setGameMode(int)` | digits | none |
| 104 | **per-game config** ("notify config %s") -> `GameInfoCenter`, `TaskManager::parseConfig`, `SceneCenter::parseConfig` | JSON (big) | state only |
| 105, 118, 187 | temperature updates (`GameThermalControl::notifyTemp`, `TempDistributionCenter::updateTemp`); from oiface `readTempLoop` | float text | none |
| 106, 108, 111, 121, 122, 129, 130, 132, 133, 135, 137, 139, 147, 148, 150, 156-159, 161, 163, 167-169, 172-177, 179-181, 2000 | engine scene switches (quality, GT mode, accelerator mode, SR, EDR, ether policy ...) via `makeSceneChangeRequest` | digits or small strings ("ether_vip", "ether_shortPerf", "ether_longStable", "setfpsgo:...", "longstable:1", "shortperf:1", "Fps:%d") | none |
| 107 | `SceneCenter::sendMessage` GPA margin | digits | none |
| 109 | GL thread, see 2.1 | `"<pid>_<tid>"` | **thread** |
| 110, 112, 145 | `GameSceneCenter::notifyGameScene(int,int,int)`; 110 string prefix `gamescene:` ("game scene switch, %s"); 112 player count | digits | none (internal; the donor never writes `sched_assist_scene`) |
| 113 | `FrameBudget::calibrateConsumeTime` | digits | none |
| 114 | `gpa::GpaService::setTargetFps`, `GpaCore::notityFtrcFpsChanged` ("game handling FrtcFps message:%d data:%s") | "fps,data" | none |
| 115 | `GameMsgServer::parseGPAEvent` (oiface GPAEvent) | JSON | none |
| 116, 119 | `GameScene` / `notifyDrawcall` (input info, drawcall) | - | none |
| 117 | `GpaCore::freqControlOn/Off` | digits | none |
| 124, 140, 164 | `FrameInsert::frameInsertChange` / `notifyFrameInsertState` | digits | none |
| 125, 126, 127 | `CpuControlPanel::setCpuCtrlPanelState/Freqs`, `setLimitHighTemp` (CPU control panel from oiface) | string / int | none (would write absent `game_opt` nodes) |
| 128 | `GameMsgServer::dataTrackerCmd` | cmd string | none |
| 131 | `FrameDropDetection::setFrameDropNum` | digits | none |
| 134 | `HighResolution::notifyStateChange` | digits | none |
| 136 | `GameInfoCenter` flag | - | none |
| 138 | `GameBroadcastLive::notifyBroadcastLiveOn(str)` | - | none |
| 144, 141 | critical thread JSON / frame-insert thread | see 2.1 | **thread** |
| 146 | `handleGCMsg` | - | none |
| 149 | `SchedExtManager::setDebugLevel` | digits | none |
| 152 | `SimpleClient::updateControl` ("gpu_control update 2147483647 0" / "gpu_control restore" from `ORMScontrol`) | string | none (GPU control via absent nodes) |
| 153 | `FpsgoStrategy::updateStatus`; COSA sends "closeinsert" + "mfrc"/"ofrc" | string | none (MTK) |
| 155 | `ComplexScene::notifyComplexSceneChange`, `GeasTunning::notifyGeasFloatWindow` | string | none |
| 160 | `BpfControl::setBpfAttachReturnValue` (oiface `GpaBpfHandler`) | digits | none |
| 162 | `RpBoost::refreshTick` | - | none |
| 165 | `FirstTouchBoost::doFirstTouchBoost(str)` ("do first touch boost") COSA `PerformanceSetting` | - | none (GPU/CPU boost through absent nodes) |
| 166 | empty handler | - | - |
| 178 | assigns a string only | - | - |
| 184 | `GpaCore::notifyFrameSmooth(bool)` | - | none |
| 186 | `TempPredictorEngine::setReportInterval` | digits | none |
| 400 (internal, from type 100 with `pkgStatus` 11/12) | game foreground "%s foreground" -> `GameMsgServer::gameForeGround(pkg, bool, str)` (0xc0ba4): init thread pool, `PerformanceMode::notifyGameState(true)`, `GameoptUx::setUxTask(<own gettid>, 0x81)` (UX for the HAL's own handler thread), `FrameBudget::reset`, `TargetFpsDecider::init`, `FrameDataTracker::init`, `TimelineTracker::start`, `GameThermalControl::init`, `CpuControlPanel::init`, `SimpleClient::init`, `FpsgoStrategy::init`, `PredictionGameManager::init`, scene message. If already foreground: "stop first" (calls background first) | package name text | **fg state** |
| 401 (internal, `pkgStatus` 1) | "%s background" -> `gameBackGround()` (0xc1270), reset of everything listed in section 8 | package name | **reset** |
| 402 (internal, `pkgStatus` 3) | "new game switch to foreground %s" (background then foreground) | package name | **reset + fg** |
| 403, 404 (internal, `pkgStatus` 4 and 5) | scene change (SCENETYPE 3), `TaskManager::resetUpdateInterval` | - | none |
| 900 / 901 | 900: to `SceneMsgServer`. 901: `PerformanceMode::notifyStreamingChange(bool)` | digits | none |
| 1900/1901/1902 | AMT: `GameInfoForAMT::notifyAMTPeriod/Start/End` (COSA `CosaAmtManager` sends 1902 with "") | string | none |
| 2000 | folding status scene | digits | none |
| 95, 120, 142 | sent by clients (95 from COSA `h5/j`, 120 from oiface bind process, 142 from oiface `OIfaceServer`) but not in the table | - | default path, nobody handles them: ignore |

Types not in the table (95, 120, 142): the call logs `"[<type>] <info>"` and sends a message nobody handles. Safe to ignore.

### 3.3 Types that the clients actually send (from the client code)

- Types 400-404 are **never sent by a client** (no call site in oiface or COSA). The HAL derives them from the `pkgStatus` of type 100. A shim must read type 100.
- oiface `OplusOIfaceService`/`DecisionDriver`: 100, 101, 102, 103, 104, 105, 106, 107, 108, 109, 111, 112, 115, 116, 117, 118,
  120, 121, 122, 123, 124, 125, 126, 127, 138, 140, 142, 147, 160, 2000 [seen, call-site scan]. `setKeyThread` from
  `oifaceDecisionSetKeyThread`. `setTfps` (code 3) from `generalOIfaceSignal` ("set_TargetFps"). `notifyCommon*` types 303, 304,
  306, 4. `packageSwitch` sends 104 (config) then 100 (package).
- COSA Java: 128, 132 (`q6/a`), 135, 139, 153 (`GameOptFeature`, `x7/a`), 152 (`ORMScontrol`), 165 (`PerformanceSetting`),
  1902 (`CosaAmtManager`), 95 (`h5/j`), plus `notifyTGPAfps`, `notifyCommon*` from `COSAService`.
- SurfaceFlinger (NDK V1): `notifySFBufferProduced` and `notifyGameInfo` ("VsyncAppSignal::toGameOpt").
- Java manager `OplusGameOptManager` saves each value to oiface first, then calls the HAL (non-blocking `checkService`). It has no `setKeyThread` method. Only oiface calls code 5.

## 4. What the pipa kernel offers (exact nodes and formats)

### 4.1 UX state of a thread

- Config: `CONFIG_OPLUS_FEATURE_SCHED_ASSIST=y`, `CONFIG_OPLUS_FEATURE_SCHED_UX_PRIORITY=y`, `CONFIG_OPLUS_UX_IM_FLAG=y`.
  `sched_assist_enabled` (`/proc/sys/kernel/sched_assist_enabled`, int) must be 1 [kernel/sysctl.c:1841].
- Bits (`kernel/sched_assist/sched_assist_common.h:26`): `SA_TYPE_LIGHT` 1, `SA_TYPE_HEAVY` 2, `SA_TYPE_ANIMATOR` 4,
  `SA_TYPE_LISTPICK` 8, `SA_OPT_SET` 0x80, `SA_TYPE_INHERIT` 0x100, `SA_TYPE_ONCE_UX` 0x200 (same bit as `SA_OPT_SET_PRIORITY`),
  priority in bits 24-31 (`UX_PRIORITY_TOP_APP 0x0A000000`).
- Exec limit of a UX task before demotion (`ux_task_exec_limit`): base 4 ms; LIGHT x2 = 8 ms; HEAVY x8 = 32 ms; ANIMATOR x8; LISTPICK x25.
- **Node A (root text interface, use this):** `/proc/oplus_scheduler/sched_assist/ux_task` (mode 0666, `sa_ux_task.c`).
  - Write `p <tid> <value>\n` (decimal). The kernel finds the process id itself. Needs uid 0 or 1000 (`uxt_verified`, from_sys). Returns -EINVAL if
    n != 3, tid <= 0 or value < 0; -ESRCH if the thread is gone.
  - Value rules (`uxt_new_state`, 5.10 bit layout): `0x81` (129) = set LIGHT; `0x82` (130) = set HEAVY; priority only with bit 9 set
    (not used). A value **without** bit 7 (SET) and without bit 8 (RESET) **clears the listed types** (`orig & ~in`); the value 0 clears all UX types except ANIMATOR. Bit 8 and bit 7 together give -EINVAL.
    A type that is held by inheritance (`SA_TYPE_INHERIT`) is not cleared.
  - Read: write `r <tid>\n`, then read the file: `comm=%s pid=%d tgid=%d ux_state=0x%08x (5.10: 0x%08x)`.
- **Node B (per thread):** `/proc/<pid>/task/<tid>/ux_state` (`proc_ux_state_write`, `sched_assist_common.c:2255`). Write a decimal int: with bit 7 it ORs
  the other bits in (`0x81` set LIGHT); without bit 7 it clears the given bits that are set; `0` clears all but ANIMATOR (plus the camera/allocator ids). Read format:
  `pid=%d ux_state=0x%08x inherit=%llx(...) grp_id=%d ux_im_flag=%d`. The donor writes the same value through the perf HAL. A raw `"2"` (HEAVY without SET) would **clear** HEAVY here, so the donor's value only works because it carries 0x80.
  The file label of a `/proc/<pid>` entry follows the target process domain, so SELinux for node B is the harder case (section 6).
- `ux_state` of the **same** thread is also written by system_server (UI-first through `ux_task_app`/`ux_task`), binder inheritance, locks, and audio code. The shim must only add and remove its own type bit (see section 8).

### 4.2 IM flag (not needed, listed because the task named it)

`/proc/oplus_scheduler/sched_assist/im_flag` (0666): write `p <tid> <flag>\n`; `r <tid>` selects a thread for read. Flag values `IM_FLAG_*` (`sched_assist_common.h`): 1 SURFACEFLINGER, 3 RENDERENGINE, 4 WEBVIEW, 5 CAMERA_HAL, 6 AUDIO, 7 HWBINDER, 8 LAUNCHER,
10 SS_LOCK_OWNER, 11 FORBID_SET_CPU_AFFINITY, 12 SYSTEMSERVER_PID, 16 TPD_SET_CPU_AFFINITY, 17 COMPRESS_THREAD, 18 RENDER_THREAD. `>= 64` clears (flag+64).
Only one flag per thread. The donor never writes it. The only effect of `IM_FLAG_RENDER_THREAD` in this kernel is inheritance by forked threads named `RenderThread`.
Do not use it for games.

### 4.3 Frame boost / frame group (`kernel/tuning`)

`/proc/oplus_frame_boost/` nodes: `ctrl` (0777), `sys_ctrl` (0770, owner system:system), `stune_boost`, `info` (read: lists the frame groups and their tasks).
`ioctl` only, so **native code is needed** (Java `android.system.Os` has no `ioctl`). `sys_ctrl` with magic 0xDF (`ofb_sys_ioctl` -> `handle_ofb_extra_cmd`):

| ioctl value | Struct | Kernel action | Donor user |
|---|---|---|---|
| `0xc028df01` (= `_IOWR(0xDF,1,40)`) | `struct ofb_ctrl_cluster {int tid; int cluster_id; char reserved[32];}` | `__fbg_set_task_preferred_cluster(tid, cluster_id)`: stores `preferred_cluster_id` in the task (valid 0..`fbg_num_sched_clusters`-1, otherwise -1 = none). Honoured at wake-up placement (`fbg_cluster_boost`) only for **one** process: the last tgid that called it (`user_interested_tgid`). No reset on exit. Needs `frame_boost_enabled=1`. | `GameoptIoctl::bindMainThread` uses cluster id = (number of clusters - 1) = the last (prime) cluster; `unbindMainThread` uses -1 [seen]. |
| `0xc058df02` (= `_IOWR(0xDF,2,88)`) | `struct ofb_key_thread_info {int tid[20]; unsigned thread_num; unsigned add;}` | `add_task_to_game_frame_group(tid, add)` for each tid; skips tasks whose comm contains "binder:" or "HwBinder:". Takes a task reference until removed. | `addKeyThread` (`add=1`), `removeKeyThread` (`add=0`) [seen] |
| `0xc010df03` (= `_IOWR(0xDF,3,16)`) | `struct ofb_frame_util_info {unsigned long frame_scale; unsigned frame_busy;}` | Starts a game frame window and returns the previous frame scale and busy of the game group | `GameoptIoctl::readFbgInfo` (code 2) |

- The game frame group (`GAME_FRAME_GROUP_ID` 3) only collects utilisation in this kernel. Its tasks are excluded from `set_frame_group_task_to_perfer_cpu` and `fbg_need_up_migration` (`frame_group.c:2127,2162`), and `game_group_update_cpufreq` does not exist
  (only the default and the composition group drive `cpufreq`). So joining the game group has **no scheduling effect**; it only feeds `frame_scale`/`frame_busy`. Skip it.
- `ctrl` (0777, any process): `CMD_ID_SET_FPS` (0xde01) changes the frame group window only for SurfaceFlinger (`im_flag == IM_FLAG_SURFACEFLINGER`) or the frame-group UI process itself. A root shim cannot set the game fps window. SurfaceFlinger already does it. So target fps has no kernel sink for the shim.
- Other `sys_ctrl` ioctls (magic 0xDE): `BOOST_STUNE` (0xde0a, `struct ofb_stune_data`, 68 bytes) sets global frame-boost tuning (`boost_freq`, `boost_migr`, `util_*`). **Do not use**: it is global, SurfaceFlinger/system_server own it, and the shim could not restore the exact values.

### 4.4 Scene and QoS (for completeness)

- `/proc/sys/kernel/sched_assist_scene` (int; write `0x80 | bit` to set, `bit` to clear a scene bit). Bits: 1 LAUNCH, 2 SLIDE, 4 CAMERA, 8 ANIM_START, 16 ANIM, 32 INPUT, 64 LAUNCHER_SI, 256 GPU_COMPOSITION, 512 AUDIO.
  There is **no game scene bit**. The donor does not write this node (no string in the binary). Do not write it.
- `/proc/oplus_qos_sched/*` (`qos_level`, `qos_task_latency`, `qos_task_prio`, `qos_task_uclamp`, `qos_lut`; owner system): ColorOS 17 thread QoS, used by system_server's `QosSchedulerManager`. The latency level ends in `write_task_ux()`. The donor does not use it. Not a gameopt lever.
- GPU: `/sys/class/kgsl/kgsl-3d0/{min_pwrlevel,max_pwrlevel}` exist. The donor writes them only inside `android::AdrenoFreqController` (PI service). No gameopt method calls that path in a way a client can trigger [inferred: it needs the GPA engine started]. High power cost if forced. Not in v1.
- CPU floor: `/sys/devices/system/cpu/cpufreq/policy{0,4,7}/scaling_min_freq`. The donor's `CpufreqControl` uses `/proc/game_opt/cpu_{min,max}_freq` and `soft_freq_{min,max}` (both absent), or the UAH/urcc path. Pipa's thermal daemon (`mi_thermald`) also writes limits. Not in v1.

## 5. `IGameCallback`: what the donor sends and when

Mapping of donor `CALLBACKTYPE` to AIDL code (from the lambda table of `GameCallBackManager::registerCallBack`, vtable slots 0x30..0x68) [seen/inferred]:

| Code | Method | Donor internal type | Producers [seen] | Payload |
|---|---|---|---|---|
| 1 | `onNotify(String)` | 0 | `GameSceneRecognition::startCollectDrawcall`, `GameScene::stop` | JSON/text [unknown] |
| 2 | `onReadTop(String)` | 1 | `ReadTopAppEvent::success` (after type 102 / top-app change) | top app JSON [unknown] |
| 3 | `onFrameLimit(String)` | 2 | `FrameControl::setFps` ("game %s descriptor %s set fps to %d at temp %f") | fps limit info [unknown] |
| 4 | `onBigDataReport(String)` | 3 | `Statistics::notifyStat` (periodic stats text) | text |
| 5 | `onNotifyTemp(String)` | 4 | `GameThermalControl::init/reset`, `GpaCore::startCoreService`, `PredictionGameManager::init` | thermal text "thermal;temp:...;time:..." parsed by oiface callback 7 [seen in oiface] |
| 6 | `onFrameProduce(String)` | 5 | `FrameRepeatedlyNotifier::success`, `FrameNotificationCenter::releaseFrameNotificaition`, `RptNotificationCenter` | "NotifyFrameProduce" and frame data |
| 7 | `onInputCollect(String)` | 6 | `GameScene::start` | input collection data |
| 8 | `onCommonCall(String, int type)` | `invoke(string,int)` | many | type = int; see below |

`onCommonCall` types and meaning (oiface consumer text is the evidence) [seen/inferred]: 102 GPA4 state change (`GpaCore::startCoreService`, `SceneCenter`); 103 refresh rate request (`ScreenModeControl::setRefreshRate`, oiface "set refresh rate to %d, game %s"); 105 frame-trace fps (`FrameTraceAssist::reportTraceFps`); 108 vsync tracking
(`GeneralControl::setVsyncTrack`); 109 render-pass tracking state (`RptRepeatedlyNotifier`); 111 big data GPA info; 112 joystick big data; 121-124 thermal-model events; 1001 tuanzhan (team-battle) scene change; 1002 BPF control action (`BpfControl::sendBpfAction`); 1003 `GeneralControl::startControl`
lambda (surface/touch event tracking); 1004 sf-app wakee tid downlink (payload 3 fields: `tid,enable,diff`, from `TaskManager`); 1005 joystick; 0 CPU high-temp state change (`CpuControlPanel`).

- On pipa none of these engines run, so **no callback is ever needed**. The shim stores the callbacks and sends nothing. Features in oiface/COSA that wait for them stay idle (they are idle today because the service is absent).
- Callback storage: legacy single list (`setCallback`/`unsetCallback`, codes 4 and 6), keyed map (`registerCallback(key,cb)`/`unregisterCallback(key)`, codes 7 and 8; COSA uses key `"cosa"`, oiface registers through V2 if version >= 2). Every callback call is oneway.

## 6. Permissions and SELinux for the shim (`pipa_port`, uid 0, `app_process`)

Rules already in `maintainer/sepolicy/pipa_port_rules.cil` [seen]:

- `(allow pipa_port oplus_scheduler_sched_assist_proc (dir (search)))`, `(file (open write))`, `(file (getattr read))` -> **Node A (`ux_task`, `im_flag`) works for write and read**. No `ioctl` perm on that type (not needed for the text interface).
- `(allow pipa_port oplus_sched_assist_scene_proc (file (open read write)))` -> `sched_assist_scene`.
- `(allow pipa_port proc_frame_boost_sys_ctrl (file (getattr open read write)))` and `proc_frame_boost_ctrl` -> open/write ok, but **no `ioctl` and no `allowx`**. Native ioctls on `sys_ctrl` need two new lines (sorted into the `.cil`, compile with `secilc` on the device before a build, per AGENTS.md):
  `(allow pipa_port proc_frame_boost_sys_ctrl (file (ioctl)))` and `(allowx pipa_port proc_frame_boost_sys_ctrl (ioctl file (0xdf01 0xdf02)))` (the same style as the existing `oiface` line in `maintainer/uifirst-policy/sa_block.cil:126`). Add 0xdf03 only if frame stats are wanted.
- `(allow pipa_port domain (dir (getattr open read search)))`, `(file (getattr open read))`, `(lnk_file (getattr read))`, `mlstrustedsubject`, capabilities `dac_override dac_read_search sys_ptrace sys_admin` ->
  reading `/proc/<pid>/task/*/comm`, `stat`, `ux_state` of any process is allowed. `sys_nice` is not listed; it is not needed for these nodes.
- **Writing `/proc/<pid>/task/<tid>/ux_state` (Node B) is not allowed**: the file is labelled with the game app's domain (`untrusted_app*`, `platform_app`...), and `pipa_port` has only read on `domain`. A broad `(allow pipa_port appdomain (file (write)))` would be needed. Do not add it. Use Node A. (The donor writes Node B through the perf HAL domain, which has its own rules.)
- DAC: `ux_task` mode 0666. `sys_ctrl` mode 0770 system:system: root passes with `dac_override`. UX writes need uid 0 or 1000 inside the kernel (`uxt_verified`). `app_process` as root: ok.
- Java cannot do the `ioctl`. The two ioctl features need a tiny native helper (static ELF in `port-rom/`, or JNI). Because the frame group is useless and the preferred cluster is a global single-process switch, **v1 should not need native code**.

Registering the AIDL service from the Java shim (`ServiceManager.addService("vendor.oplus.hardware.gameopt.IGameOptHalService/default", ...)`) is covered by the existing touch/face shims in the same domain; this spec does not repeat it.

## 7. Shim behaviour table

Defaults are conservative. `UX` means: write to `ux_task` as in 4.1 Node A. `lease` = the tracked state of section 8.

| code | method | donor does | shim does on pipa (exact node/value) | reply | notes / risk |
|---|---|---|---|---|---|
| 1 | `notifyGameInfo(type, info)` | Dispatches by type (section 3). Most types change GPA engine state only. | **Type 100** (JSON `pkgStatus`, `secondPackage`, `pid`; the only fg/bg source): `pkgStatus` 11 or 12 = foreground (start/renew the lease clock, remember the package text and `pid` if present); `1` = background: `reset_all()`; `3` = new game to foreground: `reset_all()` then foreground; `4`, `5`: ignore. Types 400-402 are accepted too, with the same meaning (400 fg, 401 bg, 402 switch), in case a client sends them. Verify the 100 payload on a device before trusting it (section 9, test 3). **Type 109** `"<pid>_<tid>"`: UX(LIGHT) on that tid (clear form below). **Type 144** JSON `{name:tid,...}`: UX(LIGHT) on each numeric value (max 8). **Type 141**: ignore. **All other types**: log at debug level, drop. Never block. | void (oneway) | Parsing must tolerate bad input: no exceptions out of the binder thread. Cap: total UX threads 16 for all calls. |
| 2 | `notifySFBufferProduced(int,long)` | Reads frame stats from kernel, feeds governors | Drop. Called every frame by SurfaceFlinger: no allocation, no log, return at once. | void | High rate (60-120 Hz). The cheapest possible no-op. |
| 3 | `notifyTGPAfps(int fps)` | Stores target fps; governors react | Store `fps` in a field; `setprop` not needed. No kernel node can take it (4.3). | `0` | none |
| 4 | `setCallback(cb)` | Register legacy callback | Store `cb`, `linkToDeath`. Replace the previous one. | `0`; `-1` if null | Never call back (section 5). |
| 5 | `setKeyThread(json)` | Key task search + UX via perf HAL | Parse leniently: `status` ("0" clears), `pid` (string or int), `key_thread_ux` (string/int), array of names under `white_list` (also accept `key_thread_value`, `key_worker`). Verify `/proc/<pid>` exists and its `/proc/<pid>/cmdline` matches the foreground game package if one is known. Scan `/proc/<pid>/task/*/comm` (read allowed); match comm exactly against the names (first 15 chars). Token `__render__` = comm `RenderThread`. For each match (max 8): read `ux_state` (Node B read), remember original UX type bits, then write `p <tid> <v>` with `v = 0x81` (LIGHT) or `0x82` (HEAVY) where `key_thread_ux & 3` selects (default LIGHT). Ignore values with other type bits (ANIMATOR/LISTPICK), priority bits, or RESET. `status=0` or new pid: reset that pid's lease. | void | UX raises placement priority on big cores; power cost small for <= 8 threads, but real if the game thread is always busy. Bounded by section 8. |
| 6 | `unsetCallback(cb)` | Logs only | Remove `cb` from the legacy slot if it is the same binder; unlink death. | `0` | Donor does not drop it; shim does, which is safer. |
| 7 | `registerCallback(key, cb)` | Keyed callback map | `map[key] = cb` with death recipient; replace existing. | void | max 8 keys |
| 8 | `unregisterCallback(key)` | Remove key | `map.remove(key)` | void | none |
| 9 | `notifyCommonIntValue(type, long)` | GPA input | Drop (debug log once per type). | void | - |
| 10 | `notifyCommonStringValue(type, str)` | GPA input | Drop. | void | Type 303 is oiface's `onCommonCall` echo. |
| 11 | `notifyCommonIntPair(type,int,long)` | GPA input | Drop. | void | - |
| 12 | `notifyCommonStringPair(type,a,b)` | GPA input (oiface 304) | Drop. | void | - |
| 13 | `notifySchedFrameTime(int,long,long,long)` | Frame timeline model | Drop (no allocation). | void | per frame |
| 14 | `notifyRptStatus(int,int,long)` | Log only | Drop. | void | - |
| meta | `getInterfaceVersion`/`getInterfaceHash` | stub | Version **2**, hash `79187eecf42abc41850736c8590e8c5e0bea0660` (V2); a V1 answer disables codes 7-14 in the Java wrapper (GAMEOPT.md). | - | - |

Optional features, **off by default** (separate system properties, for example `persist.pipa.gameopt.bindmain=1`):

| id | Trigger | Action | Cost |
|---|---|---|---|
| O1 prefer prime cluster | Type 5 with non-empty `bind_core`/`bind_main` [unknown HAL key], or the GL thread of type 109 | native ioctl `0xc028df01` on `/proc/oplus_frame_boost/sys_ctrl` with `{tid, cluster_id = 2}` (3 clusters on SM8250: 0 = cpu0-3, 1 = cpu4-6, 2 = cpu7). | Pins wake-up placement to a **single** core (cpu7). Often worse for efficiency; the kernel returns false when that core is busy. Only one process may use it at a time. Reset with `cluster_id = -1`. |
| O2 game frame group | Same tid set | ioctl `0xc058df02` `{tid[], n, add=1}` | No scheduling effect (4.3). Only useful for frame stats. Keeps task references until `add=0`. **Do not implement** unless frame stats are wanted. |

Not in the shim (reason): CPU/GPU floor writes, `sched_assist_scene`, `im_flag`, stune/ofb tuning, `kgsl` pwrlevel, hmbird, uclamp, UAH. Reasons: no donor trigger that maps to them on pipa, or the node is absent or global (sections 1.4, 4).

## 8. Reset rules (the shim never leaves a thread boosted)

### 8.1 What the donor resets, and when [seen]

| Trigger | Donor reset |
|---|---|
| Type 401 (from type 100 `pkgStatus` 1) `gameBackGround()` (0xc1270) | `GeasAssist::appBg`, `GameInfoCenter::setGameForeGroundStatus(false)`, `GpuControl::onGameBackground`, `PerformanceMode::notifyGameState(false)`, `TargetFpsDecider::reset`, `FrameDataTracker::reset`, `TimelineTracker::stop`, **`GameoptUx::resetUxTask()`** (the HAL's own thread), `GameThermalControl::reset`, `TempDistributionCenter::reset`, `PredictionGameManager::shutdown`, scene off message, `GameSceneCenter::reset`, `CpuControlPanel::reset`, `SimpleClient::reset`, `FpsgoStrategy::reset`, `EDControl::unregisterEDSignalHandler`, `GpuLevelControl::resetGpuControl`, `GameControl::reset`, `GameInfoForAMT::notifyAMTEnd`, `YieldOpt::reset`, `GameoptIoctl::resetPipelineSwap`, `NpuControl::reset`. It does **not** call `TaskManager::stopGameZone`, so key-thread UX can stay set until the next `parseConfig`. [seen: no call in the function]
| Type 400 while already foreground | background first ("stop first!") |
| New config (type 104 -> `TaskManager::parseConfig`) | `TaskManager::stopGameZone()` |
| `TaskManager` cannot track a key task | `stopGameZone()` |
| `stopGameZone()` | UX value reset for each recorded thread through `setKeyTask`, `GameoptIoctl::removeKeyThread()` (all), clears game_opt nodes |
| `setCallback` null / `unsetCallback` | Return -1 / 0; nothing else |
| Binder death of a callback client | none in the code read [unknown]; oiface has its own `DeathMonitor` ("abnormally exited %d times, more than 10 times, skip restore") |
| Service start | `FreqControl::deleteController`, `MemFreqControl::releaseAllControl`, `SchedExtManager::clearConfig` |
| Service death | nothing (the kernel keeps `ux_state` of live threads) |

### 8.2 What the shim does

State: `leases = map<pid, {pkg, startElapsed, lastRenew, threads: [{tid, startTime(field 22 of /proc/<pid>/task/<tid>/stat), comm, origTypeBits, ourTypeBit}]}>`. Keep at most 2 pids.

`reset(pid)` = for each recorded thread, if the thread still exists with the same start time: read `ux_state`; if we added bit B (B not in `origTypeBits`) and B is still set, write `p <tid> <B>` (clears exactly B, per 4.1). Skip threads that are gone. Then drop the lease. If O1 was used: ioctl `cluster_id = -1` for each tid.

Triggers:

1. `notifyGameInfo(100)` with `pkgStatus` 1 (also 401) and `status="0"` in `setKeyThread`: `reset(pid)` (all leases if the package is unknown).
2. `notifyGameInfo(100)` with `pkgStatus` 3 (also 402), a foreground with a package different from the current one, or `setKeyThread` with a new `pid`: `reset_all()` first, then apply the new set.
3. Process death: while at least one lease exists, check `/proc/<pid>` every 10 s on the shim's handler thread (no timer when no lease). Gone, or `cmdline` changed, or start time changed -> drop the lease (nothing to write).
4. Timeout: every lease lasts at most **30 minutes** after its last renewal. A renewal is any `setKeyThread`, foreground type 100 (or 400/402), 109 or 144 for that pid. When it expires: `reset(pid)`. The donor config is re-sent by COSA on each foreground, so a live game renews itself. [Value is a guess; keep it as a property `persist.pipa.gameopt.lease_min`.]
5. Screen off (`ACTION_SCREEN_OFF`) with the game in the foreground: `reset_all()` (idle game, no point holding big-core priority). Optional.
6. `unsetCallback` / `unregisterCallback` / callback binder death: **no thread reset** (matches the donor and these calls are not game-state signals). Only drop the callback.
7. Shim stop (`onDestroy`, SIGTERM, uncaught exception handler): `reset_all()`.
8. Shim start after a crash: the kernel keeps old `ux_state` bits, the process has no memory of them. To make this safe, write the lease table to a file on each change (`/data/local/tmp/pipa_gameopt_leases`, tid, start time, bit B, small) and call `reset` for every entry at start-up. Ignore entries whose start time no longer matches.
9. Ownership guard: never clear a type bit that was already set before the shim added it (`origTypeBits`). Never write to a tid whose tgid does not match the lease pid.

## 9. Open points and a test plan for the device (all read-only or reversible; ask before running)

1. Confirm the live nodes: `ls -l /proc/oplus_scheduler/sched_assist/ /proc/oplus_frame_boost/`, `cat /proc/sys/kernel/sched_assist_enabled`.
2. Confirm Node A: pick a harmless own thread (an `adb shell` sleep process): `echo 'p <tid> 129' > ux_task`, then `echo 'r <tid>' > ux_task; cat ux_task` -> `ux_state=0x...81`; `echo 'p <tid> 1' > ux_task` clears it. In the `pipa_port` domain check logcat tag `auditd` for denials.
3. Capture the real payloads once on a device with the real COSA/oiface: `setprop persist.logd.audit.rate` is not needed. Log every call in the shim for one game session (types and the first 200 characters of `info`). Needed to resolve: HAL-side JSON of `setKeyThread`, `pkgStatus` values (1, 3, 4, 5, 11, 12) of type 100, payload of 102, whether 400-402 arrive directly or only inside 100.
4. Check that `oiface` is running on the port (HAL-INVENTORY open item 4) and `persist.sys.oiface.enable`. Without oiface and COSA nothing calls code 5 and the shim is idle.
5. Measure power with a real game before enabling O1.
6. Unknowns that could not be settled offline: the exact HAL `setKeyThread` JSON; callback payload JSON for codes 1-7 (not needed in v1); the donor's `unsetCallback` effect (the read function shows no removal); the meaning of type 142 and the missing handlers 95/120; the name of the first package key in type 100 (the `pkgStatus` to 400-404 mapping is known); what `key_thread_ux` values the cloud sends (the donor passes the integer straight to `ux_state`; if it is not `0x81/0x82` the shim should map it as in code 5).

## 10. Evidence index (where to look again)

- Message table: `GameMsgServer::initMessageHandlers` 0xc6698 (lambdas are `__func<...::$_N>` in `initExternalMessageHandlers`, `initNotifyGameInfo1thMessageHandlers`, `...2th...`, `...PkgSwitch...`, `...SHM...`, `...FoldingStatus...`).
- AIDL entry points 0xa5984 (ctor), 0xa5e0c (setKeyThread), 0xa61f0, 0xa6458, 0xa6f0c, 0xa7124, 0xa725c, 0xa7354, 0xa75fc, 0xa7718-0xa7c54.
- UX apply: `PerformanceProxy::setKeyTask` 0xfd538, `GameoptUx` 0x10d468/0x10d834/0x10d968, `TaskManager::setKeyTask` 0xedf8c, `handleKeyTasks` 0xde6c8, `stopGameZone` 0xdb274, `parseConfig` 0xd7c5c, `handleMessage` 0xefe04.
- Ioctl: `GameoptIoctl::*` 0x2a9c74-0x2acb94.
- Callbacks: `GameCallBackManager` 0x10ed10-0x1101fc; `GpaCallbackManager` 0x37b214-0x37c614.
- Clients: oiface `DecisionDriver::oifaceDecisionSetKeyThread` 0x35c60, `GameOptService::*` 0x99850-0x9cf54; COSA `com/oplus/feature/gameopt/**`, `h6/b`, `q6/a`, `x7/a`, `ea/m`, `h5/j` under (cloud work folder).
- Kernel: `kernel/sched_assist/sa_ux_task.c`, `sched_assist_common.c:2255-2350,2638-2767`, `sched_assist_common.h:26-36,120-150,357-363`, `kernel/tuning/frame_ioctl.{c,h}`, `frame_group.c:627,2127,2162`, `cluster_boost.c`, `fs/proc/base.c:3989`, `kernel/sysctl.c:1841-1855`.
- Port policy: `maintainer/sepolicy/pipa_port_rules.cil` lines 51-55, 123, 142-143; `maintainer/uifirst-policy/sa_block.cil:123-127`.

## Review (2026-11-03): what the shim implements

`maintainer/halshims/src/pipa/hal/GameOptService.java` follows sections 7 and 8 with these choices:
- UX source: `setKeyThread` (names from `white_list`, `key_thread_value`, `key_worker`; `key_thread_ux` only as SET|LIGHT
  or SET|HEAVY), type 109 (GL thread, LIGHT), type 144 (critical threads, LIGHT). Foreground/background from type 100
  `pkgStatus` (11/12 renew, 1 reset, 3 reset and new lease).
- Limits: 8 threads per game, 2 games. A bit that was set before is never touched; the thread start time guards against
  a reused tid; `Tgid` must be the game pid.
- Reset: background, new game, process death (10 s check only while a lease exists), 30 min without renewal, shim stop
  (shutdown hook), lease file `/data/misc/pipa_port/gameopt_leases` replayed at start.
- Not implemented (no pipa sink or a cost): the prime-cluster ioctl (O1), the frame group (O2), screen-off reset.
- Kernel facts checked in `kernel/sched_assist/sa_ux_task.c` (`uxt_new_state`: SET adds, a bare bit clears only that
  bit) and `fs/proc/base.c` (`ux_state` is in `tid_base_stuff`, decimal read).
