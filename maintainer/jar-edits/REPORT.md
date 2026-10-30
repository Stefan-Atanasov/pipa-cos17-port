# oplus-services.jar: what did the port author change? (beta4 = C.05 repack vs C.06 stock)

> **Historical analysis (2026-10-22).** It answers one question: did the beta4 author change `oplus-services.jar`?
> The current build patches this jar in several steps (base, baked, 2w, 3f, 3s, 3t). Refer to
> `docs/ARCHITECTURE.md`, section 2.3.

Method: androguard 9.x in venv (scripts in this dir: strs.py, mdiff.py, cmp.py, show.py). All 3 dex files per jar, 124 167 (beta4) vs 124 201 (C.06) methods compared by full disassembly text.

## Result in one line
No port edit was found. All 17 beta4-only strings are explained by OPPO C.05 -> C.06 source changes. The "vibrator fallback" string differs only in a log label; the code path is the same. Nothing needs re-applying to C.06 (confidence: medium-high; cannot be proven without C.05).

## Findings table (the 17 beta4-only strings)
| beta4-only string(s) | Where | Explanation |
|---|---|---|
| 2x "playWithLinearVibrator: ringtone haptic unsupported, fallback to EFFECT_NOTIFICATION_REMIND[, path=]" | OplusSoundVibrateManager.playWithLinearVibrator | C.06 only renamed the log text to "...fallback to VIBRATE_WITH_RINGTONE". Same logic, same waveform id (399). OPPO churn |
| "Both color temperature regulation and comfortable rhythm disabled, sensors unregistered" | DisplayColorController.updateSensorRegistration | C.06 rewrote the method (new "Sensors unregistered: screenOn=" / "Sensor registration: colorTempReg=" logging, hasEyeProtectEffective). OPPO refactor |
| "Logtrial isExternalInstallApk is true, show icon" | DebugLogService.shouldShowLogtrialIcon | C.06 removed that method (LogTrial swap). OPPO |
| "checkExecutingComponent failed, force unfreeze uid=", ignoreExecutingComponent, isExecuting | OplusHansManager | C.06 restructured to handle/resolve/shouldIgnoreExecutingComponent (+ ...WhenHookDisable). OPPO refactor |
| invalidateSensorDataState | DisplayColorController | renamed invalidateSensorDataSnapshot in C.06 |
| 7x lambda$...$N, $r8$lambda$..., val$drawBounds | PackageManagerServiceExtImpl, eye-protect, etc. | lambda renumbering because C.06 added "special safe mode" code, boot monitor, etc. (~137 new strings, ~46 new methods in C.06) |

## Vibrator detail (the suspected edit)
Class `Lcom/android/server/notification/OplusSoundVibrateManager;` method `playWithLinearVibrator(ZLandroid/net/Uri;IZLjava/lang/String;)Z`.
Both versions, same structure:
```
invoke-virtual v1, OplusSoundVibrateManager->isSupportRingtoneHaptic()Z ; if-nez -> ringtone path
iget-boolean v0, v1, ...->mHasHapticFeature Z                           ; if-eqz -> alt
beta4: const-string/jumbo v0, "playWithLinearVibrator: ringtone haptic unsupported, fallback to EFFECT_NOTIFICATION_REMIND"
C.06 : const-string/jumbo v0, "playWithLinearVibrator: ringtone haptic unsupported, fallback to VIBRATE_WITH_RINGTONE"
both : Log.d(...); invoke-virtual LinearmotorVibrator->createWaveformEffect(I I I)  with const 399, -1, -1
```
The remaining diff in this method is register renumbering (v18->v17, v9/v8 swaps) and branch offsets, plus one extra `move/from16` in C.06: compiler output of a slightly different OPPO source, not a semantic change. The fallback is the OPPO linear-motor (`com.oplus.os.LinearmotorVibrator`) path, gated by mHasHapticFeature; it is dead on pipa unless the OPPO linear motor feature flag is set. Wrong in the earlier theory: this is not a "fallback to Xiaomi HAL" edit.

## Other observation: possible but unproven value difference
`OplusDisplayBrightnessModel.<init>`: `mBrightnessRampRateSlow` default is `const/16 v2, 320` in beta4 vs `40` in C.06 (hardcoded default). Could be an OPPO fix between C.05 and C.06 or a port tweak; cannot tell. `initRate()` (unchanged between the two) also writes the field, so the constructor default is likely overridden. Low impact; if the beta4 display feels different in slow brightness ramps, this is the one number to check.

## Repack artifacts (not behavioral)
beta4 jar has no META-INF/MANIFEST.MF and no D8 marker; dex has "const-string/jumbo" vs "const-string" differences from reassembly (smali/baksmali style), zip dates 2026-09-26, and an `OplusRemoteDisplay.uau` entry that is also in C.06 (donor native). The oat/odex was dropped with the repack (already handled in beta5 build).

## Recommendation
Do not re-apply anything to C.06: not needed. No ringtone-vibration, crash or log-spam risk from missing it. No device test required for this item. Optional: if display ramp behaviour regresses on beta5, compare the 320 vs 40 default above.

## Not determinable
- Without the real C.05 jar, edits that add no new strings and also look like OPPO churn (e.g. one constant flipped, like the 320 vs 40) cannot be separated. Of 109 changed methods, all large diffs are explained by OPPO features; ~50 small ones are string-constant encoding or register/offset shifts.
- Port edits that were already present in C.06 or only removed code cannot be seen.
