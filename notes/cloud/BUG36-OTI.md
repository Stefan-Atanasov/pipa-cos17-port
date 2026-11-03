# Bug 36: panel stays at 120 Hz while OTI asks for 60 Hz

Static notes (cloud session, 2026-11-03). Two key strings (`mode is nullptr, so ignore it.`, `CurrentDirectorMapOti`) were checked again in the C.07 `surfaceflinger`. Nothing here is tested on a device. Use section 5 (capture checklist) at the next occurrence, before any restart.

- Donor analysed: ColorOS 17 C.07 (system + system_ext only). Port docs use donor C.06. Differences between C.06 and C.07 are not checked.
- Date: 2026-11-03.
- Method: static reading of the smali-like dumps (oplus-services.jar, services.jar) and of `surfaceflinger` (function names from `.gnu_debugdata`, strings, `llvm-objdump` of single functions). No device, no logs, no runtime test.
- Tags: [seen] = read in the donor code or strings. [inferred] = follows from code but not tested. [unknown] = cannot be known without the device.
- Not available: `my_product/etc/oplus_vrr_config.json` (partition is not in the donor tree). Native offsets below are for the C.07 `surfaceflinger`.
- Dump class names: `com.oplus.vrr.*` and `com.android.server.wm.Oplus*` are in oplus-services.jar. `LocalDisplayAdapter*` and `DisplayModeDirector` are in services.jar.

## 0. Short answer

1. Two Java writers and one native layer decide the panel mode. [seen]
   - Writer 1: window manager policy `OplusRefreshRatePolicyImpl` (WM). It calls `SurfaceControl.setDesiredDisplayModeSpecs` directly with the range [rate, rate]. So "physical [120,120]" is the normal result of a 120 Hz vote. [seen]
   - Writer 2: `DisplayModeDirector` through `LocalDisplayAdapter`. [seen]
   - Native: `OplusRefreshRateDirector` in SurfaceFlinger keeps both specs and the OTI requests, and sends the best mode to SF. OTI itself bypasses the SF policy (it requests a mode directly). [seen/inferred]
2. The symptom "oti-hw fps=60, mode id 0" fits best one SF-side case: the OTI request holds fps 60 but a null (or wrong) `DisplayMode` pointer. Then SF logs "mode is nullptr, so ignore it." and keeps 120 Hz. [inferred, strong fit]
3. A system_server restart cleared it, but SF stayed alive. So the stale part is probably in system_server (a Java cache) or in a SF input that system_server rewrites (the display specs). [inferred]
4. Java caches that are built once and can be stale after a boot race: `mSfDisplayModes` (WM), `OPlusRefreshRateConfigs` maps. [seen]

## 1. Mode selection path (OTI to panel)

### 1.1 Java side (config and gates) [seen unless marked]

1. `OPlusRefreshRateService` (service name `oplus_vrr_service`) loads `oplus_vrr_config.json` through `OPlusRusHelper`. It reads `/etc/oplus_vrr_config.json` and `data/system/oplus_vrr_config.json` and compares the version of both. The higher version wins. [seen] Risk: a RUS data file can replace the 2z-patched config (see path P7).
2. `OPlusExternalRefreshRateManager` parses the `touch_idle` entry into `TouchIdleBean` (`onTouchIdleConfigChange`) and sets `mTouchIdleHwSwitch`, `mBlockedRefreshRate`, panel id list.
3. It computes the gates: `mTouchIdleHwBacklightEnough`, `mTouchIdleHwBacklightRangeIn`, `mTouchIdleHwNitExitHbm` (in `handleBacklightChange`), `mLockRefreshRate`, `mDirectorBackLight`.
4. `handleTouchIdleState` decides the pause flag `mTouchIdleShouldPause`. It also reads `mTouchIdleShouldPauseForce` (set only by `notifyDisableOtiMode(Z)`). It sends the result with `OPlusSurfaceFlingerController.setTouchIdleShouldPause(Z)` and the config with `setTouchIdleConfig(TouchIdleBean)`.
5. Per-source disable flags live in `OPlusRefreshRateService.mVrrDisableState` (HashMap keyed by source, value = bits OTI=1, ADFR=2, PW=4). `mVrrStateSummary` is the OR of all values. Entry point: `notifyDisableAdfrOtiPwStatus(int)`. Callers: SystemUI `OplusAdfrRefreshRateController`, `SensorServiceExtImpl`, `DeviceStateListener`, and four sites inside the service. The summary goes to the handler message `ADFR_OTI_MODE_CHANGE`. [seen]
6. `OPlusSurfaceFlingerController` sends all of it to SF by binder transactions (`setDirectorState(I)`, `setDirectorMode60Config`, `setDirectorOtiHwConfig`, `setTouchIdleShouldPause`, `setTouchIdleConfig`, `setTouchIdleAppRequest`).

### 1.2 Native side (SurfaceFlinger C.07) [seen: names and strings; inferred: behaviour]

1. `OplusTouchIdle` (input and content idle timer) drives `OTIHWStrategy` and `OTISWStrategy`. [seen]
2. `OTIHWStrategy::applyChangedState` is the HW path. It calls `getRefreshRateRange`, then `requestRateViaDirector("oti-hw", fps, modePtr)`. If the target is above the current mode, it logs "keep rate." and sends nothing. If OTI is not ready, it logs "restore sys rate.". Log tag "VRR [OTI-HW]". [seen/inferred]
3. `getRefreshRateRange` builds a pair (low mode, high mode) from the pacesetter `RefreshRateSelector`:
   - high = `getMaxRefreshRateByPolicy` (depends on the SF policy);
   - low = the lowest mode with fps >= the floor rate (member of `OTIHWStrategy`, set by `storeSystemConfig` from the touch-idle config, 60 Hz in the 2z config), on the same physical display as the active mode, and only if a compatibility check on the OPLUS config mode type (`OPlusRefreshRateSelector::getConfigModeType`, types 0..3 = OA/OM/SA/SM) passes while `OPlusAdfrUtil` is enabled. [inferred]
4. `OplusRefreshRateDirector::requestRefreshRateByOti(key, OplusVrrRequest)` inserts or updates the request in the OTI map (member map, dump name `CurrentDirectorMapOti`). The request carries fps and a `shared_ptr<DisplayMode const>`. Logs: "requestRefreshRateByOti insert/update [ %s, %s ]". Tag "VRR [RefreshRateDirector]". [seen]
5. `selectBestFrameRate` picks the best entry from the XOD, generic, replace-60 and OTI maps ("selectBestFrameRate DirectorMapOti [%s, %s]"). If no request exists, it makes a "default" request. For XOD and for requests without a mode pointer it calls `getModePtrByFps(fps)`. [seen]
6. `getModePtrByFps(fps)` returns the first mode in the pacesetter selector mode list with rounded fps equal to the request and the same physical display id as the director's active mode. It skips modes of config type 2 and 3 when `OPlusAdfrUtil` is enabled. A second loop uses the XOD fps member. If nothing matches, it returns null. It does not use the mode group. [inferred from the instruction pattern]
7. `updateBestFrameRate` logs "updateBestFrameRate [%s, %s]". If the chosen request has a null mode, it logs "mode is nullptr, so ignore it." and changes nothing. Otherwise it builds a `DisplayModeRequest` and calls `OplusSurfaceFlinger::changeRefreshRate`. That function clears the OTI map when the director is active and calls `SurfaceFlinger::setDesiredMode`. [seen/inferred]
8. `getApScaleModePtr/getApScaleModeID` map mode ids through an int map (+0x210) only when a DDIC2AP-scale feature flag is on. [inferred; flag value on pipa unknown]
9. Specs input: `OplusRefreshRateDirector::requestRefreshRateBySpecs(token, specs)` stores the latest specs per display token in two maps (dump names `CurrentDirectorMapSpecs`, `LastDirectorMapSpecs`). If the new default mode is not in the same mode group (`isSameModeGroup`) as the stored one, it clears the generic map and the OTI map and sends the specs now. If the group is the same, it posts "select best" only when the generic map and the XOD request are empty. Else it waits. [inferred]

### 1.3 Java mode id mapping (where "fps to id" is cached) [seen]

1. `OPlusRefreshRateConfigs` (vrr) holds `mSupportedModes`, `mModeTypes`, `mModeTypeMap`, `mConfigMap`. `buildConfigMap(displayId)` reads `SurfaceControl.getDynamicDisplayInfo` and asks SF for the mode type of every mode id (transaction code 23005 on SurfaceFlinger). `getModeId(type, fps, w, h)` returns the first id of that type with equal fps (tolerance 1 Hz), width and height, else -1. `getModeIdByPolicy(type, modeId)` reuses the rate and size of an existing mode id.
2. `OPlusRefreshRatePolicy.findDisplayModeIdByPolicy(policy, displayIdFlag, modeId)` is called by `LocalDisplayAdapter.setDesiredDisplayModeSpecsLocked` for the main display. It maps the DMD base mode id to the id of the same rate and size but another type (OA/OM/SA/SM, by VRR policy 0..5). If nothing is found, it returns the input id. [seen]
3. WM `OplusRefreshRatePolicyImpl.findDisplayModeIdLocked(Display.Mode)` matches a framework mode with the cached array `mSfDisplayModes` and returns the SF mode id. It then calls `SurfaceControl.setDesiredDisplayModeSpecs(token, defaultMode=id, ranges [rate,rate])` from `setDisplayConfigSpecs` (on the `OPlusVRRThread` handler). [seen]

## 2. Cached state

| field | class | set by | reset by | stale risk |
|---|---|---|---|---|
| `mSfDisplayModes` (copy of SF mode array) | `wm.OplusRefreshRatePolicyImpl` | `initPhysicalDisplayToken` only when `mActiveDisplayToken` is null (first call) [seen] | nothing found; process restart only | High if the first read happens before SF has the final list, or after SF re-creates the display with other ids. Empty or wrong array gives no id or a wrong id. |
| `mActiveDisplayToken`, `mActivePhysicalDisplayId` | same | constructor, `initPhysicalDisplayToken`, `updateDisplayInfo` | `updateDisplayInfo` (partly) | Medium. Token stays after a display re-add. |
| `mDisplayInfo`, `mSupportMaxRefreshId`, `mLastDisplayInfoResolution` | same | `updateDisplayInfo(displayId)`; it returns early when resolution and max refresh id are unchanged [seen] | same method | Low-medium. Mode list changes with the same resolution and max id are ignored. |
| `mCore.mVotes` (per priority: 10 app request, 20 flexible window, 25 game, 30 pocket studio, 40 animation boost, 50 high brightness, 60 DC, 70 MEMC, 80 high temp, 85 launcher, 100 OSYNC, 110 low rate, 120 pad mirage, 121 AOD, 130 FOD, 150 near flash) | `wm.OplusRefreshRateCore` | `updateVoteLocked(priority, vote)`; null vote removes [seen] | the caller that set it (token exit, timer message, window change) | Medium. A vote lives until its owner removes it. |
| token death recipients `mActiveDeathRecipients` (one per type: PS mode, request, DC) | `OplusRefreshRatePolicyImpl$DeathRecipient` | `getOrCreateDeathRecipient`, `relink(newToken)` | `binderDied` calls the exit setter; `unlinkDeath` on exit | Medium. One recipient per type: a second client replaces the first token (relink). |
| timed boosts: `MSG_RESET_APP_SWITCH_BOOST`(9), `MSG_RESET_DELAY_ANIMATING`(8), `RESET_BOOST_MSG`(3), FOD/high brightness delay (4,5); fields `mDelayAfterAnimating`, `mStartTimeOfAppSwitchBoost`, `mChangeInAnimation` | `OplusRefreshRatePolicyImpl`, `InnerHandler` | start of boost | handler message; the 9-handler re-arms itself while a transition plays or a recents transition exists ("app switch boost timeout,transition isPlaying:") [seen] | Low-medium |
| `mPickRefreshRateData`, `mCurrentPickRate`, `mIsFirstWinReqRefreshrate`, `mTopInterestedWinMaxRate` | same | window rate pick | `requestUpadate` resets them [seen] | Low |
| `mOifaceRequestedRates`, `mAllFreezeTokens` | same | OIface and freeze requests | owner; death | Low |
| setting-driven: `oplus_customize_screen_refresh_rate`, `oplus_refreshrate_override`, `display_pwm_settings_switch`, `app_extreme_high_refresh_switch` | `OplusRefreshRatePolicyImpl$SettingsObserver` | content observer | on change: `requestUpadate`, `resetMinRefreshRate` | Low |
| `mSupportedModes`, `mModeTypes`, `mModeTypeMap`, `mConfigMap` | `vrr.OPlusRefreshRateConfigs` | `buildConfigMap` (called by `updateDisplayModes(J)`) | `buildConfigMap` clears the last three, NOT `mSupportedModes` [seen] | Medium. `buildConfigMap` returns early (token null, or dynamic info null) and leaves the old or empty maps. A failed mode type call (`getSFModeType` catch) gives type 0 for every mode. |
| `mPloliciesByRate`, `mOverridePlolicy`, `mFactoryMode`, `mPolicyChangedSequence` | `vrr.OPlusRefreshRatePolicy` | `setRefreshRatePolicy(policy, rate, on)` | the same call with `on=false` | Medium. No death link was found for the caller [unknown who calls it]. |
| `mDisplayModeSpecs`, `mDisplayModeSpecsInvalid` | `LocalDisplayAdapter$LocalDisplayDevice` (services.jar) | `setDesiredDisplayModeSpecsLocked`; invalid flag set by `updateDisplayModesLocked` | specs equal and valid means no resend [seen] | Medium. The cache does not know that WM wrote other specs to SF in between (two writers). |
| `ModeRequestManager` (`isAnyModeInProgress`, timeout 5000 ms) | services.jar | user-preferred-mode requests | `clearRequests`, timeout | Low. While a request is in progress, DMD specs are dropped silently. |
| `mTouchIdleShouldPause`, `mTouchIdleShouldPauseForce`, `mScreenState`, `mNits`, `mTouchIdleHw*`, `mLockRefreshRate`, `mBlockedRefreshRate`, `mAppRequest`, `mAppRequestStored`, `mCurrentModeId`, `mCurPkgName` | `vrr.OPlusExternalRefreshRateManager` | see 1.1 | `mTouchIdleShouldPauseForce`: only `notifyDisableOtiMode(Z)`. `mCurrentModeId`: only `setDynamicStatusFromModeChange`. `screenStateChange` sets `mScreenState` and the ambient callbacks, and no pause flag. [seen] | Medium for Force (the known 3b case). |
| `mVrrDisableState`, `mVrrStateSummary` | `vrr.OPlusRefreshRateService` | `notifyDisableAdfrOtiPwStatus` | by the same source sending 0 [seen]; no death link and no screen-off clear found | Medium |
| `mActivePhysicalDisplayId`, `mPrimaryPhysicalDisplayId`, `mModeId`, `mCurPolicy`, `mRenderPeriod` | `vrr.OPlusRefreshRateService` | `handleActivePhysicalDisplayIdChange`, `handleBaseModeChange`, `handleDisplayModeSpecsChange`, `handleConfigIdChange` | next event | Low |
| `mDirectorStateOff`, `mShutdownAdfrOtiStatus` | `vrr.OPlusRefreshRateService` | director state and settings events | next event | Low |
| `CurrentDirectorMap`, `CurrentDirectorMapSpecs`, `LastDirectorMapSpecs`, `CurrentDirectorMapReplace60`, `CurrentDirectorMapOti`, `BestRequest`, XOD request (fps + mode ptr) | native `OplusRefreshRateDirector` | `requestRefreshRateBy*`, `selectBestFrameRate` | `clearRefreshRateMapOti` (called from `changeRefreshRate`, `OTIHWStrategy::onFloorFrequencyChanged`, `OplusMVT::chooseFrameRateMode`, `OplusSurfaceFlinger::onTransactVRRMisc`); `clearAllDirectorMaps` (from `updateDirectorMode60Config` and a director state transaction); `removeDisplayToken` (display removed); group change in `requestRefreshRateBySpecs` [seen] | Medium. Requests keep a `DisplayMode` pointer taken at request time. |
| mode type table in SF (`OPlusRefreshRateSelector::getConfigModeType`) | native | at selector build | `forceReconstructRefreshRates` (called by `OplusTouchIdle::updateConfigLocked`) | Unknown |

## 3. Reset events

| event | what resets | what does NOT reset |
|---|---|---|
| Screen off / on | Java: `screenStateChange` on the OTI manager and the other managers (ambient callback register/unregister). Native: `setPhysicalDisplayPowerMode` on doze calls `OplusSurfaceFlinger::disableOTI` ("screen doze, disable OTI"), `applyDeferredModeChange`, `OplusTouchIdle::updateAdfrIdleMode`. WM: `setDisplayConfigSpecs` is skipped while `DisplayContent.isSleeping()` unless the top vote is FOD (130). Log "setDisplayConfigSpecs display is sleeping,do nothing". [seen] | Pause flags (`Force`), `mVrrDisableState`, `mSfDisplayModes`, the OTI map. A vote change during sleep is dropped, not queued. A re-evaluation on wake is [unknown]. |
| Doze / AOD | `PRIORITY_AOD` (121) vote; `handleAodStyleStateChange`; SF `updateAvtAodStatus`. | The same as above. |
| Display changed (`onDisplayChanged`) | WM `OplusDisplayModeService` display listener calls `updateDisplayInfo(id)` (re-init only if resolution or max refresh id changed). `LocalDisplayAdapter.updateDisplayModesLocked` calls `OPlusRefreshRateConfigs.buildConfigMap` and sets `mDisplayModeSpecsInvalid`. [seen] | `mSfDisplayModes`; `mSupportedModes`. |
| SF config/mode id event | `handleConfigIdChange`: updates SA/OA/game managers, `updateRenderPeriodChange`, and calls `notifyDisableOtiMode`. | `OPlusRefreshRateConfigs` maps. |
| Refresh-rate setting change (Auto / High / Standard) | WM `SettingsObserver` calls `requestUpadate` and `resetMinRefreshRate`. `requestUpadate` resets `mPickRefreshRateData` and window pick state, then asks `OplusDisplayModeService.requestUpadate`. Service: `handleRefreshRateSwitchChange` (`adfr_screen_refresh_rate`). | Core votes of other priorities, token votes. |
| App / process death | Token votes (types PS, request, DC) are removed by `binderDied` of the latest token. Service recipients exist for FRTC, game assistant, game battle, synthetic vsync, info monitor, abutment mode and frame rate. | `mVrrDisableState` sources (no recipient found). A window preference vote (priority 10) follows the focused window only. Voters that replaced a token with `relink` leave the first owner without a recipient. |
| User switch | Nothing found in the VRR/WM classes. AOSP DMD has `MSG_SWITCH_USER`. | [unknown] |
| system_server / zygote restart | All Java state is rebuilt. Specs are sent again. Native maps are overwritten by the new specs (same-group path may keep OTI entries). | SF native state (SF stays alive). |
| SF restart | All native state. | Java caches (system_server stays alive unless it also restarts). `LocalDisplayAdapter` would re-read modes only on a display change. |

## 4. Stale-vote paths, ranked by likelihood on pipa

### P1. SF-side OTI request with a null or wrong mode pointer (best fit for "fps=60, id 0")

- Trigger [inferred]: `getModePtrByFps(60)` or the low-mode selection in `getRefreshRateRange` finds no 60 Hz mode. Reasons: (a) the director's cached active mode belongs to another physical display or selector (display re-add, `forceReconstructRefreshRates`), so the physical id compare fails for every mode; (b) `OPlusAdfrUtil` is on and the 60 Hz mode has a config type that the compatibility check rejects, so the low mode stays at the policy maximum (120 Hz, id 0); (c) the floor rate member (`OTIHWStrategy`) is stale at 120 after a config push.
- Stale field: `CurrentDirectorMapOti` entry (fps + mode pointer), `BestRequest`.
- Why not reset: `updateBestFrameRate` ignores a null-mode request and leaves the OTI map as is. The map is cleared only by the events listed in section 2.
- Likelihood: high as the mechanism; the exact trigger is [unknown]. pipa has no OPLUS mode-type source, so the type table may be inconsistent. [unknown]
- Confirm on device (before any restart):
  1. `dumpsys SurfaceFlinger`: read `CurrentDirectorMapOti`, `BestRequest`, `CurrentDirectorMapSpecs`, `LastDirectorMapSpecs`, `HW Strategy Status` (`Enable`, `LowestRate`, `policy`, `cur`, `min`, `max`), `Rate:` lines. Look for a request with fps 60 and mode id 0 or no mode.
  2. `dumpsys SurfaceFlinger | grep -i -E 'displayManagerPolicy|active mode|activeMode'` and the mode list: note each id, fps, group, and config type if printed.
  3. `logcat -b all -d | grep -E 'VRR \[(OTI-HW|OTI|RefreshRateDirector)\]|mode is nullptr|keep rate|restore sys rate|requestRefreshRateByOti|updateBestFrameRate|selectBestFrameRate'`. The strings "mode is nullptr, so ignore it." and "keep rate." are the markers. Whether these logs are on in a user build is [unknown].
- Patch plan: native, not smali. Optional binary patch in `updateBestFrameRate`: when the mode pointer is null, call `getModePtrByFps(request fps)` once and use the result. It needs a ROM layer test (a system binary cannot be tested from /data). Java mitigation: none for the cause. Recovery nudge, if wanted later: `OPlusSurfaceFlingerController.setDirectorState(I)` leads to `updateDirectorState`, which clears director maps and triggers a fake tap. [inferred] Use it only after the capture proves the stale map.

### P2. WM `mSfDisplayModes` built once (stale or empty SF mode array)

- Trigger [inferred]: `initPhysicalDisplayToken` runs when the token is null, copies `SurfaceControl.getDynamicDisplayInfo().supportedDisplayModes` once, and never again. A first call at early boot (clean flash, slow composer), or a later SF/composer re-add with new ids, leaves a wrong copy.
- Stale field: `OplusRefreshRatePolicyImpl.mSfDisplayModes`.
- Why not reset: the copy happens only under `mActiveDisplayToken == null`. `updateDisplayInfo` does not re-copy and returns early when resolution and max refresh id are equal.
- Effect [inferred]: `findDisplayModeIdLocked` returns -1 or a wrong SF id. `setDisplayConfigSpecs` then logs "setDisplayConfigSpecs: sfModId=..." and does not push the new specs. SF keeps the previous specs ([120,120] from an older vote). OTI still works against its own stale mode data.
- Fit: seen after a clean flash, intermittent, cleared by a system_server restart, absent after a normal reboot. Likelihood: medium-high.
- Confirm: `logcat -b all -d | grep -E 'RefreshRate'` for "initPhysicalDisplayToken mActiveDisplayToken == null", "initPhysicalDisplayToken dynamicInfo == null", "setDisplayConfigSpecs: sfModId=", "setDisplayConfigSpecs complete: targetMode=", "do setDisplayConfigSpecs", "setDisplayConfigSpecs error:". `dumpsys oplusscreenmode` (WM policy dump: votes, current mode, display id). Compare SF mode ids in `dumpsys SurfaceFlinger` with the ids logged.
- Patch plan (smali, services: oplus-services.jar): class `com.android.server.wm.OplusRefreshRatePolicyImpl`, method `initPhysicalDisplayToken`. Remove the "token not null" early exit for the mode copy, so the array is re-read on every call. Also call it from `updateDisplayInfo` when the id list differs. Keep the log strings.

### P3. `OPlusRefreshRateConfigs` built once with a failed read

- Trigger [inferred]: `buildConfigMap` returns early if `getPhysicalDisplayToken` or `getDynamicDisplayInfo` is null at the time of `LocalDisplayAdapter.updateDisplayModesLocked`. `getSFModeType` returns 0 when the SF transaction 23005 throws ("Failed to get mode type"). `mSupportedModes` is never cleared.
- Stale field: `mModeTypeMap`, `mModeTypes`, `mConfigMap`, `mSupportedModes`.
- Why not reset: the next call happens only on the next display mode update.
- Effect: `getModeId` returns -1 for the wanted type, `findDisplayModeIdByPolicy` returns the input id unchanged (the DMD base mode), so the type-based remap does not happen. A wrong base id (for example id 0, 120 Hz) can stay. Likelihood: medium.
- Confirm: `dumpsys oplus_vrr_service` (the configs dump prints the mode type maps; look for all modes with the same type). `logcat -b all -d | grep -E 'OPRefreshRateConfigs|buildConfigMap|No valid dynamic info found|Failed to get mode type|modeType|72 only for osync'`. Debug logs depend on `OPlusLogUtil.DEBUG` (userdebug or `persist.sys.assert.panic`). [seen]
- Patch plan (smali): `com.oplus.vrr.OPlusRefreshRateConfigs.buildConfigMap`: clear `mSupportedModes` with the other maps; on a null token, null dynamic info, or a mode type read that throws, keep the old maps and re-post an update. A simpler variant: call `updateDisplayModes` again from `OPlusRefreshRateService.handleConfigIdChange`.

### P4. Two writers and the `LocalDisplayAdapter` dedupe cache

- Trigger [inferred]: WM writes [r,r] to SF directly. DMD writes its own specs through `LocalDisplayAdapter`. The adapter skips a write when the new DMD specs equal its own cache (and the cache is valid). If WM wrote in between, SF holds the WM value and the adapter does not replace it.
- Stale field: `LocalDisplayDevice.mDisplayModeSpecs` (adapter cache) versus real SF specs.
- Why not reset: `mDisplayModeSpecsInvalid` is set only on a display info update.
- Likelihood: medium. It only creates a mismatch between the two policies; the OTI path itself ignores the SF policy, so it explains a stale `displayManagerPolicy`, not the id 0 mapping.
- Confirm: compare `dumpsys display` (DisplayModeDirector votes and desired specs) with `dumpsys SurfaceFlinger | grep displayManagerPolicy` and `CurrentDirectorMapSpecs`. A difference between them is the proof. Log tag `LocalDisplayAdapter`.
- Patch plan (smali, services.jar): `LocalDisplayAdapter$LocalDisplayDevice.setDesiredDisplayModeSpecsLocked`: no change in the first step. Optional: in `OplusRefreshRatePolicyImpl$lambda setDisplayConfigSpecs$5` (after `SurfaceControl.setDesiredDisplayModeSpecs`) invalidate the adapter cache through the existing `mDisplayModeSpecsInvalid` path. Risky; do it only if the capture shows the mismatch.

### P5. WM skip while sleeping

- Trigger [seen/inferred]: a vote change while `DisplayContent.isSleeping()` is true (top priority not 130). `setDisplayConfigSpecs` returns with the log "setDisplayConfigSpecs display is sleeping,do nothing". No code was found that replays it on wake. The next vote change fixes it.
- Stale field: SF specs (the last non-sleep write).
- Why not reset: skip, not queue.
- Likelihood: medium-low (a wake normally changes the keyguard or app vote).
- Confirm: logcat `RefreshRate` for the sleep log, with the time of the stuck state. `dumpsys oplusscreenmode`: the vote table must show a rate different from `displayManagerPolicy`.
- Patch plan (smali): `OplusRefreshRatePolicyImpl.setDisplayConfigSpecs`: at the sleeping return, set a pending flag. In the wake path (`updateDisplayInfo` with display state ON, or `requestUpadate`), re-run the last call when the flag is set.

### P6. Stale disable source or Force pause (known family, step 3b)

- Trigger [seen]: a source sends a disable bit and never sends 0 (SystemUI keyguard source 5 after power_off was fixed in 3b). `Force` is set only by `notifyDisableOtiMode(Z)`. `mVrrDisableState` has no process-death link and no screen-off clear.
- Effect: OTI paused, so the panel stays at its last high mode. This differs from the observed case (OTI was active and asked for 60), so rank is low for bug 36.
- Confirm: `dumpsys oplus_vrr_service`: `VrrState` (`source: ..., state: ...`), `VrrStateSummary`, `TouchIdleShouldPause`, `TouchIdleShouldPauseForce`, `TouchIdleKeepHight`, `TouchIdleHwBacklightEnough`, `TouchIdleHwBacklightRangeIn`. Logs: "notifyDisableAdfrOtiPwStatus:", "notifyDisableOtiMode:", " [OTI] handleTouchIdlePauseState: Force".
- Patch plan (smali): `OPlusRefreshRateService.handleScreenStateChange` (state OFF): clear sources owned by SystemUI. Or give `notifyDisableAdfrOtiPwStatus` a timeout. Not needed unless the capture shows it.

### P7. RUS data config replaces the patched config

- Trigger [seen/unknown]: `data/system/oplus_vrr_config.json` has a higher version than `/etc/oplus_vrr_config.json`. `OPlusRusHelper.updateConfigSource` then loads the data file (original nit limits and histogram). A RUS push or a restored backup can create it.
- Effect: the HW gate (110+ nits) returns. OTI then lowers only the render rate. Looks like the original B11 symptom, not like id 0.
- Confirm: `ls -l /data/system/oplus_vrr_config.json`; `dumpsys oplus_vrr_service` (`DataSource = data/system/oplus_vrr_config.json` line); logcat tag `OPlusRusHelper` ("dataVersion=", ", systemVersion=").
- Patch plan: none in smali. If the file exists, it is a build or ROM issue: ship the 2z config with a higher version number or block the data file.

### P8. Other (low)

- `ModeRequestManager.isAnyModeInProgress` drops DMD specs for up to 5000 ms. Low.
- Stale `OPlusRefreshRatePolicy` per-rate policy sets (`setRefreshRatePolicy`). Caller unknown. Low.
- Timed boosts that re-arm during recents/transition (message 9). Low.
- Core votes of types with one shared recipient (`relink`). Low.

## 5. Capture checklist for the next occurrence (do it before any restart)

1. Note the time, the current refresh setting (Auto/High/Standard), the foreground app, and the last actions (screen off/on, pen, unlock, app switch, rotation).
2. `date; settings get system oplus_customize_screen_refresh_rate; settings get system peak_refresh_rate; settings get system min_refresh_rate`
3. `dumpsys SurfaceFlinger > /data/local/tmp/b36_sf.txt` then grep: `displayManagerPolicy`, `CurrentDirectorMapOti`, `CurrentDirectorMapSpecs`, `LastDirectorMapSpecs`, `CurrentDirectorMapReplace60`, `BestRequest`, `HW Strategy Status`, `LowestRate`, `Rate:`, `policy:`, `StateCollect`, `shouldPause`, `mMute`, `ContentIdleData`. Keep the mode list (ids, fps, group).
4. `dumpsys oplus_vrr_service > /data/local/tmp/b36_vrr.txt` (VrrState, VrrStateSummary, mCurPolicy, TouchIdle fields, mode type maps, DataSource line).
5. `dumpsys oplusscreenmode > /data/local/tmp/b36_wm.txt` (WM policy: votes, current mode, display id).
6. `dumpsys display > /data/local/tmp/b36_dm.txt` (DisplayModeDirector votes, desired specs, supported modes and ids).
7. `logcat -b all -d > /data/local/tmp/b36_log.txt`. Grep for: `RefreshRate`, `OPlusRefreshRateService`, `OPlusExternalRefreshRateManager`, `OPRefreshRateConfigs`, `OPlusRefreshRatePolicy`, `LocalDisplayAdapter`, `VRR [OTI-HW]`, `VRR [OTI]`, `VRR [RefreshRateDirector]`, `OPlusRusHelper`, and the strings: "mode is nullptr", "keep rate.", "restore sys rate.", "display is sleeping,do nothing", "initPhysicalDisplayToken", "sfModId", "Failed to get mode type", "No valid dynamic info found", "handleConfigIdChange", "notifyDisableOtiMode", "notifyDisableAdfrOtiPwStatus".
8. `ls -l /data/system/oplus_vrr_config.json /data/anr /sys/fs/pstore` and `getprop | grep -E 'oplus.display|vrr|ro.pipa.port.layer'`.
9. Probe without a restart: touch the screen, wait 5 s, run steps 3 and 4 again (does `CurrentDirectorMapOti` change? does `BestRequest` change?). Then change the refresh setting once and repeat step 3 (does the policy line follow?). Record the result.
10. Only then restart (zygote), and note what changed.
11. For a longer test: before the next boot, set `persist.sys.assert.panic` to true so that `OPlusLogUtil` debug logs appear (userdebug builds have them already), and keep `logcat -b all` in a ring buffer of 16 MB (`persist.logd.size`). Reset both after. `dumpsys oplus_vrr_service dynamic_debug true` turns on the service dynamic log without a reboot. [seen: command name]

## Open questions

1. Which `DisplayMode` does the stuck OTI request hold (null, id 0, or id 3)? Only the SF dump shows it. [unknown]
2. Does `OPlusAdfrUtil` (+0x30) run on pipa, and which config type does each pipa mode have in `OPlusRefreshRateSelector`? [unknown]
3. Is the director's active-mode member updated after a display re-add? [unknown]
4. Does a wake re-run `setDisplayConfigSpecs` (P5)? [unknown]
5. Who calls `OPlusRefreshRateService.setRefreshRatePolicy(policy, rate, on)`, and does it ever send `on=false` after a death? [unknown]
6. Are the SF `VRR [..]` logs active in the user-type build? [unknown]
7. Is the DDIC2AP feature flag on (id map +0x210)? [unknown]
8. Does C.07 differ from C.06 in these classes? Compare `OplusRefreshRatePolicyImpl`, `OPlusRefreshRateConfigs` and the SF symbols before porting any patch. [unknown]
9. The `touch_idle` entry of `my_product/etc/oplus_vrr_config.json` is not in this donor tree. Its `lowest` value feeds the floor rate. [unknown]
