# Handoff: Adaptive colour / Bedtime mode on the COS17 pipa port

Companion module: `pipa-cos17-power-tune-v0.9.zip` (md5 `4d479de1…`). This
write-up was written for v0.5 (beta4 jar); v0.9 ships one patched jar per ROM
build (`module/framework/<base-md5>.jar`), see `module/README.md` §12.

Device: Xiaomi Pad 6 (`pipa`), ColorOS 17 beta4 `OPD2515_17.0.0.102(CN01)`,
KernelSU 4.2.0, alongside `pipa_core` v1.10.

## Symptom

Eye Comfort and Reader mode work. **Adaptive colour** and **Bedtime mode** did
nothing: the settings could be switched on but the panel stayed at the default
7900 K.

## Root cause

ColorOS's ambience stack (`com.android.server.display.color.*`, inside
`/system/framework/oplus-services.jar`) registers the ambient colour sensor with
a hard-coded **OPPO sensor type 33171001**:

```java
OplusColorAmbientAdapter.registerSensor():
    registerSensorIfAvailable(sensorManager, 33171001, ...);
```

pipa's tcs3701 exposes its CCT channel only as Xiaomi vendor types:

| Sensor | Type |
|---|---|
| `xiaomi.sensor.cct` | 33171058 |
| `xiaomi.sensor.front_cct` | **33171088** |
| `xiaomi.sensor.front_cct_strm` | 33171089 |

`getDefaultSensor(33171001)` returns null, so
`OplusColorContext.sensorDataValid` stays false and both post-processing
features skip every frame:

- `OplusFeatureAmbientColor` (Adaptive colour)
- `OplusFeatureAmbientEyeprotect` (Bedtime)

Second, independent issue: the Eye Protect app (`com.oplus.eyeprotect`) has a
hard-coded capability flag `a1()` that returns **false**, and its startup path
calls `E1(resolver, false)` / `checkColorTemperature()`, which write the
settings back to 0. This is why the switches did not stay on.

## What the module changes

### 1. Framework jar: `oplus-services.jar`

The module ships `/system/framework/oplus-services.jar` with three binary edits
in `classes.dex` (port-shipped jar md5 `3316594f…`, dex md5 `23c054c6…`; the port author had
already repacked this jar, it is not donor stock):

1. **Switch payload reorder** (`handleSensorChange`, offset `0x8bb170`).
   The sparse-switch case for type 33171001 is retargeted to 33171088. DEX
   requires sparse-switch keys to be **sorted**, so the key/target pairs are
   reordered together:

   ```
   keys    [8, 27, 33171001, 33171052]  ->  [8, 27, 33171052, 33171088]
   targets [16, 12, 8, 4]               ->  [16, 12, 4, 8]
   ```

   Without the reorder ART rejects the class:
   `VerifyError: invalid sparse switch payload … unordered keys`.

2. **Sensor type literal** `33171001 -> 33171088` in the remaining two places:
   - `OplusColorAmbientAdapter.registerSensor()` (`const`, offset `0x8bb54c`)
   - `EyeProtectConstant.SENSOR_COLOR_TEMPERATURE` (static int in the
     encoded-array item at `0x4b130e`)

3. **Lux source** in `onSingleSensorChanged()` (offset `0x8bb36a`).
   OPPO's sensor contract is `values[0] = CCT`, `values[9] = lux`. The Xiaomi
   `front_cct` event is 16 floats but has **no lux**: live data is
   `[CCT, x, y, 0, 0, …]`, so `values[9]` is always 0. With `sensorLux = 0` the
   framework stays in low-light lock and pins the CCT to 5300 K even under a
   6000 lx lamp.

   The patch replaces `aget v1, v2, v1` (read `values[9]`) with
   `const/high16 v1, #0x42c80000` = **100.0 f**, i.e. a fixed 100 lx. Adaptive
   colour then follows the CCT sensor; brightness-based adaptation is lost.

4. Dex `SHA-1` (bytes 12–32) and `Adler32` checksum (bytes 8–12) are
   recomputed, then the jar is rebuilt with the other entries unchanged.
   Patched jar md5: `06c5c30317965509952881d9e712027f`.

### 2. Mounting

KernelSU 4.2 on this port has no module mount provider (`"mount": "false"`), so
`post-fs-data.sh` bind-mounts the jar itself:

```sh
chcon u:object_r:system_file:s0 "$JAR"      # system_server cannot read shell_data_file
mount --bind "$JAR" /system/framework/oplus-services.jar
```

(Historical, v0.5: the script searched `$MODDIR` for the jar. Since v0.9 it binds
`$MODDIR/framework/<md5 of /system/framework/oplus-services.jar>.jar` if it exists,
and skips the bind if a prebuilt `oplus-services.odex` exists unless
`FRAMEWORK_ALLOW_ODEX=1`.) `FRAMEWORK_SENSOR_REROUTE=0` in `config.prop` disables
it. The jar is in `systemserverclasspath.pb`, not `BOOTCLASSPATH`. The beta4 jar
has no `.odex`, so no stale prebuilt image is involved there; C.06 stock ships one
and beta5 removes it.

### 3. Settings and the boot reset

Two different settings exist for Adaptive colour:

| Key | Reader | Meaning |
|---|---|---|
| `setting_enable_color_temperature_regulation` | system_server | **actual runtime state**; applies the tint |
| `oplus_customize_comfort_color_temperature_enable` | Eye Protect app | visible switch state only |

Bedtime also has two keys:

| Key | Meaning |
|---|---|
| `oplus_customize_rhythm_health_enable` | `rhythmEnabled`: **standalone** Bedtime; warms with Adaptive and Eye Comfort off |
| `oplus_customize_comfortable_rhythm_enable` | `comfortableRhythmEnabled`: Eye Comfort–dependent variant |

The Eye Protect app resets the app-side keys at startup. `service.sh` remembers
the user's last state in `$MODDIR/adaptive_state` / `$MODDIR/bedtime_state` and
writes it back once, after boot and after the CCT sensor has data
(`ADAPTIVE_RESTORE=1`). Turning a switch off is remembered as well.

## Behaviour

Verified on the device (2026-10-21):

- `tcs3701 front CCT Non-wakeup` registers under type 33171088.
- `sensorCCT ≈ 5400–6100 K`, `sensorLux = 100` (fixed), `sensorDataValid = true`,
  `lowLightLocked = false`.
- Adaptive colour only: target ≈ **6100–6300 K**, follows the ambient CCT.
- Bedtime only (`rhythm_health_enable=1`, Eye Comfort and Adaptive off):
  target ≈ **5263 K** — this is the standalone warm shift.
- Both on, daytime: Adaptive wins (`OplusFeatureAmbientColor` ≈ 6338 K);
  Bedtime computes its point (5263 K) but defers. At night the Bedtime point
  applies. This matches the donor's behaviour.
- Off → on again after 5 s: sensor re-registers, `sensorDataValid=true` within
  ~2 s, target returns. Re-enabling after hours works the same way.

Battery: the sensor is the **non-wakeup** variant; `dumpsys power` shows no
wake locks from it. Overhead is a few events per second while the display is on
(plus `system_server` post-processing), not a screen-off waker. It has not yet
been measured against the 53.4 mAh/h deep-idle baseline.

## Known limitations / proper fixes

1. **Fixed 100 lx.** Adaptive colour tracks ambient *colour temperature* but not
   ambient brightness. The proper fix is a HAL that puts real ALS lux into the
   OPPO `values[9]` slot, or framework code that reads the light sensor.
2. **App switch reset.** The module restores the framework state after boot, but
   the Eye Protect UI can still show its switch off. Proper fix: patch
   `Lg8/h;->a1()Z` to return true and remove the `E1(false)` /
   `checkColorTemperature()` resets in `com.oplus.eyeprotect`, or ship a fixed
   app.
3. **Offsets are for the beta4 jar only.** `module/tools/patch_framework.sh`
   finds the sites by pattern and also works on C.06 (payload `0x4365c0`, lux
   `+0x1fa`); for another build run it on that build's own jar.
4. **Proper ROM fix:** in `oplus-services.jar`, map the OPPO CCT type to the
   Xiaomi one (or make it configurable); add an OPPO-compatible CCT+lux sensor
   to the vendor HAL (type 33171001, 10+ floats, CCT at 0, lux at 9); fix the
   Eye Protect app's hard-coded capability flag.

## Verify

```sh
dumpsys sensorservice | grep -A2 'front CCT  Non-wakeup'
dumpsys color_display | grep -E 'sensorCCT|sensorLux|sensorDataValid|currentCCT|rhythmEnabled'
settings get system setting_enable_color_temperature_regulation
settings get system oplus_customize_rhythm_health_enable
grep -E 'oplus-services|restored' /data/local/tmp/pipa_power_tune.log
md5sum /system/framework/oplus-services.jar   # 06c5c303… (beta4 + module), 8c211ca5… (C.06 + module, or beta5-baked)
```

## Files

```
pipa-cos17-power-tune-v0.9.zip                      install in KernelSU/Magisk
module/README.md §12                                developer write-up
module/tools/patch_framework.sh                     regenerate the patched jar from a ROM jar
module/post-fs-data.sh                              binds the jar
module/service.sh                                   ADAPTIVE_RESTORE / state files
module/framework/<base-md5>.jar                     patched jars (beta4 3316594f…, C.06 2175feb9…)
```
