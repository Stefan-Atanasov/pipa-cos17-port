# oplusSensor HAL: does the wait block pipa, and is a stub worth it?

Donor: C.07 (only `system/system` and `system_ext` unpacked). Date: 2026-11-03.
Method: static only. `readelf` (dynsym and `.gnu_debugdata` symbols), `llvm-objdump` plus grep, `strings`, androguard disassembly of the interface jar. No device.
Work files stayed in the cloud work folder (not in git).
Marks: [seen] read in the files. [inferred] follows from the code. [unknown] needs the device.

## Summary

- The wait is behind `AServiceManager_isDeclared` at all 3 sites. [seen]
- The donor system manifest (`/system/etc/vintf/manifest.xml`) declares `ISensorFeature/default`. [seen] On pipa the declare check is probably true, so the wait has no timeout. [inferred]
- The wait runs inline in sensorservice code. It runs on the thread that registers sensors (once, behind a gate) and on the threads that activate the fusion light sensor. [inferred]
- The port boots with a lib of the same family. So the boot-time path is not taken today. The gate is probably false (`isOSTypeLightBase()` or the sensor types). [inferred]
- Verdict: no stub is needed for boot. A one-line manifest edit is the cheapest guard. A stub is optional (section 6).

## 1. Interface

| Item | Value | Mark |
|---|---|---|
| AIDL descriptor | `vendor.oplus.hardware.oplusSensor.ISensorFeature` | [seen] (`descriptor` symbol, string in NDK lib, Java stub) |
| AIDL instance | `vendor.oplus.hardware.oplusSensor.ISensorFeature/default` | [seen] (odm `precompiled_service_contexts`, odm rc, lib strings) |
| AIDL version | 1 (stable AIDL V1) | [seen] (`VERSION = 1` in Java stub) |
| Interface hash | `11597a0080b32caa5e6b8494d84965bb46d77eb6` | [seen] (same string in NDK lib and Java stub) |
| HIDL twin | `vendor.oplus.hardware.oplusSensor@1.0::ISensorFeature`, instance `default` | [seen] (matrix entry, `V1_0` jar and `@1.0.so`) |
| Donor service | `odm/bin/hw/vendor-oplus-hardware-oplusSensor-V1-service` (odm, not in the unpacked donor) | [seen] (scan.json) |
| NDK lib | `system_ext/lib(64)/vendor.oplus.hardware.oplusSensor-V1-ndk.so` | [seen] |
| Java lib | `system_ext/framework/vendor.oplus.hardware.oplusSensor-V1-java.jar` (+ `V1.0-java.jar`), `<library>` in `system_ext/etc/permissions/vendor-oplus-hardware-oplusSensor.xml` | [seen] |

AIDL methods. Transaction codes come from the `mov w1, #n` before `AIBinder_transact` in each `Bp` method. Codes 1 to 9 follow the declaration order. [seen]
The parcel layout comes from the `AParcel_write*` and `AParcel_read*` calls in each `Bp` method. A status header comes first in every reply. [seen]

| Code | Method | In (parcel order) | Out (after status) |
|---|---|---|---|
| 1 | `calibrateSensor(int, int)` | int32, int32 | bool |
| 2 | `getSensorCalibrationData(int)` | int32 | String |
| 3 | `getSensorConfig()` | none | String |
| 4 | `getSensorRawData(int)` | int32 | float |
| 5 | `saveCalibrationData(int, int, byte[])` | int32, int32, byte[] | int32 |
| 6 | `sensorRawDataEnableDisable(int, int)` | int32, int32 | bool |
| 7 | `sensorReadNodeFile(String, int)` | String, int32 | String |
| 8 | `sensorWriteNodeFile(String, String)` | String, String | int32 |
| 9 | `setPhoneMode(byte, byte)` | byte, byte | int32 |
| 0xffffff | `getInterfaceVersion()` | none | int32 (1) |
| 0xfffffe | `getInterfaceHash()` | none | String |

Callbacks: none. [seen] No callback type in the NDK lib.
The meaning of the int arguments (sensor ids, node ids, mode values) is [unknown]. The NDK lib has no names for them.

## 2. libsensorserviceextimpl.so

File: `system_ext/lib64/libsensorserviceextimpl.so` (and `lib/`). It has `.gnu_debugdata` symbols. [seen]

### The 3 waitForService sites

| Site | Enclosing function | Guard before the wait | Mark |
|---|---|---|---|
| `0xaf020` | `android::AidlSensorFeature::getService()` | `AServiceManager_isDeclared` at `0xaf004`. If false, it jumps over the wait. | [seen] |
| `0xb3fe8` | `android::LazySensorFeature::getTransientService()` | Flag byte at object `+0x44`. The `LazySensorFeature` constructor sets it from `isDeclared` (call at `0xb3d70`). Log: `ISensorFeature isDeclared=%d`. | [seen] |
| `0xb40f0` | `android::LazySensorFeature::ensureCachedServiceLocked()` | Same flag. The caller holds the object mutex. | [seen] |

All 3 wait on the same instance name. The call has no timeout. [seen]
There is also one non-blocking `AServiceManager_checkService` at `0xad388`. It belongs to `AidlDisplayPanelFeature::getService()`, not to this HAL. [seen]
The HIDL twin (`HidlSensorFeature::getService`, call at `0xb3114`) passes `retry = false`. It does not block. [seen]

Strings in the lib: `ISensorFeature is not declared.`, `%s: mIsDeclared is false`, `%s: wait for sensor feature service failed`, `waitForService returned null binder for ISensorFeature.`, `%s both ISensorFeature server can't access`. [seen]
So a "not declared" result gives a null service and a log line. A declared but absent service blocks inside `waitForService`. [inferred]

### Who declares it on pipa

- The donor `system/system/etc/vintf/manifest.xml` has an AIDL `<hal>` for `vendor.oplus.hardware.oplusSensor` with `ISensorFeature/default`. [seen]
- The donor `compatibility_matrix.device.xml` has the HIDL 1.0 and the AIDL entry (no `optional` attribute). [seen]
- `servicemanager` `isDeclared` looks at the device manifest and at the framework manifest. [inferred, AOSP behaviour, not checked in this donor]
- pipa has no odm manifest for it. The port steps do not edit `system/etc/vintf/manifest.xml` (grep of `maintainer/port/steps`: only the modem manifest). [seen]
- So `isDeclared` is probably true on pipa and the wait has no end. [inferred] The log line `ISensorFeature isDeclared=%d` shows it on the device (section 6).

### When each site runs

| Entry | Called from | Thread | Mark |
|---|---|---|---|
| `LazySensorFeature::triggerSensorFeatureOnBoot()` -> `getTransientService()` (site 2) | A `call_once` lambda in `SensorServiceExtImpl::onSensorFound(sensor_t const*, unsigned long)` | The thread that registers sensors. No thread is created. In AOSP this is the sensorservice start (`StartSensorService` init thread in system_server) and later dynamic sensor hot-plug. | [inferred] |
| Gate of that lambda | `OplusSensorServiceUtils::isOSTypeLightBase()` must be true, and the sensor type must be 6, 33171059 or 33171052 (read at `sensor_t +0x18`) | same | [seen] |
| `LazySensorFeature::beginSession()` -> `ensureCachedServiceLocked()` (site 3) | `OplusFusionLightNextGen::activateInternal()` (fusion light sensor activate). `endSession()` at the last deactivate releases the service. | The thread that enables the sensor (binder thread of the client). | [inferred] |
| `getSensorCalibrationData(int)` (Lazy, then Aidl, then Hidl) | `fastCaliArgsInit()`, `fastCaliArgsInitSidePanel()` (from `OplusFusionLightArgs::initArgs`, `OplusSidePanelFusionLightArgs::initArgs`), `OplusFusionLightConfig::loadLeakFromHal(bool,int)` | Fusion light sensor setup | [seen] callers, [inferred] timing |
| `sensorWriteNodeFile(String, String)` | `OplusFusionLightNextGen::onSampleCollected(...)`, `appendCWBScreenShotResultRecord(...)`, and fusion light config paths | The sensor event thread (sample path) | [seen] callers, [inferred] thread |
| `AidlSensorFeature::getService()` (site 1) | `isAvailable()`, `getSensorCalibrationData`, `sensorWriteNodeFile` of `AidlSensorFeature` | Same callers as the two rows above | [inferred] |

Fusion light means the OPPO ambient-light fusion (screen colour and brightness correction from lux and display data). [inferred from the names `OplusFusionLight*`, `Rgb_valus`, `AILightPerceptionConfig`, `fusionlight_profile`]
`isOSTypeLightBase()` is a once-computed flag. It likely reads `ro.oplus.os_type` (string present in the lib). Its value on pipa is [unknown]. The donor `build.prop` files that remain have no `ro.oplus.os_type`.

### Is the sensorservice main thread blocked?

- Possible at sensorservice start, only if the gate is true and the service is declared but absent. Then `onSensorFound` never returns. Sensor registration stops for all apps, and system_server waits for the sensor service start. [inferred]
- On pipa this does not happen today. The port boots with a lib of the same family (inventory note, C.06). So the gate is false in practice. [inferred]
- The activation path (site 3) can block a binder thread of the sensor service for ever. It does so only if the fusion light sensor is created on pipa. It holds the `LazySensorFeature` mutex, so the next activate or deactivate of that sensor also blocks. [inferred]
- Collision risk: the gate and the fusion code compare sensor types 33171028, 33171042, 33171052, 33171059 and 33171070 (OPPO fusion sensors). [seen] If a Xiaomi sensor on pipa has one of these types, the fusion code can wake up. Which Xiaomi sensors have these numbers is [unknown]. 33171052 is already touched by the port: `patch_framework.sh` reorders a switch with this key.

### Effect when the service never appears

- Not declared: calls return null. The lib logs and goes on. Calibration data stays empty and node writes are dropped. [inferred]
- Declared and absent: the call blocks (see above).

## 3. Other callers

| Caller | Lookup | Blocks? | Mark |
|---|---|---|---|
| `libsensorserviceextimpl.so` (3 sites above) | `AServiceManager_waitForService`, after `isDeclared` | Yes, no timeout | [seen] |
| `libsensorserviceextimpl.so` HIDL path | `V1_0::ISensorFeature::getService("default", retry=false)` | No | [seen] |
| `OplusCommercialEngineerMode.apk` (system_ext app) | Strings `checkService`, `not support oplusSensor aidl`, `not support oplusSensor hidl: ` | No (`checkService`) | [seen] strings, [inferred] use |
| `SystemUI` | Text `oplusSensor` appears in `OplusStatusBarDependencyEx*` and the dagger component dumps. Probably a dependency name, not a lookup. | [unknown] | [unknown] |
| Other system code | No other `vendor.oplus.hardware.oplusSensor` string in `scan.json` outside the interface libs, the permission files and the items above | n/a | [seen] |

## 4. Features lost on pipa

Without the HAL, the lib cannot use these. Names come from the interface and the callers. [inferred]

- Factory sensor calibration data (`getSensorCalibrationData`, `saveCalibrationData`, `calibrateSensor`). The fusion light code reads it at setup. Without it, the light fusion uses default values. Effect: less exact lux and colour correction from the OPPO fusion path.
- Sensor node reads and writes (`sensorReadNodeFile`, `sensorWriteNodeFile`). The fusion light code writes display and CWB data to nodes. Effect: the OPPO fusion path gives no data to the sensor hub.
- Raw data and config (`getSensorRawData`, `sensorRawDataEnableDisable`, `getSensorConfig`). Used by the engineering mode app (factory test). Effect: no raw sensor test screen.
- `setPhoneMode` (ear mode for the proximity sensor on phones). pipa is a tablet. No visible loss.

On pipa the user-visible parts are already replaced by the port: adaptive tone uses Xiaomi `front_cct_strm` (3s) and the OPPO CCT type is rerouted (2w). [seen in AGENTS.md]
No user-visible tablet feature needs this HAL. [inferred]

## 5. Stub plan

Model: the touch shim (`maintainer/touchshim/README.md`): Java binder service, own wire code, host and registrar from `pipa_port`, system-stability binder, SELinux label `oplus_absent_service`, no VINTF entry.

Instance: `vendor.oplus.hardware.oplusSensor.ISensorFeature/default`.
The framework manifest already declares it, so no new VINTF entry is needed. A registered stub makes `waitForService` return at once. The stub must also answer `getInterfaceVersion` (1) and `getInterfaceHash`, or the NDK client can reject the binder. [inferred]

| Code | Method | Stub answer | Must answer? | Note |
|---|---|---|---|---|
| 1 | `calibrateSensor` | `false` | Yes | Never start a calibration. |
| 2 | `getSensorCalibrationData` | empty String | Yes (fusion setup) | How the callers treat an empty String is [unknown]. |
| 3 | `getSensorConfig` | empty String | Yes | |
| 4 | `getSensorRawData` | `0.0f` | No (engineering app only) | |
| 5 | `saveCalibrationData` | `-1` | No | Do not store data. |
| 6 | `sensorRawDataEnableDisable` | `false` | Yes | Must never enable a sensor. Raw data on a colliding Xiaomi id can cost power. |
| 7 | `sensorReadNodeFile` | empty String | Yes | Never read a real node. |
| 8 | `sensorWriteNodeFile` | `-1` or `0`; the value the callers like is [unknown] | Yes | Never write a real node. A path from ColorOS can be a pipa node with another meaning. |
| 9 | `setPhoneMode` | `0` | No | |
| 0xffffff | `getInterfaceVersion` | `1` | Yes | |
| 0xfffffe | `getInterfaceHash` | the hash string | Yes | |

Risks:
- A stub removes the block but turns the fusion light code into a working path with empty data. [inferred]
- Extra wakeups: the fusion code writes a node at each sample (`onSampleCollected`). A stub adds a binder call at the sample rate. The cost is small, but measure it. [inferred]
- The stub must answer constants only. It must not call a sensor HAL or enable a sensor. This keeps Xiaomi sensors (for example `knuckle`) off.
- The Java stub jar `vendor.oplus.hardware.oplusSensor-V1-java.jar` exists in the donor. A Java service can reuse it, but the shim style uses its own wire code. Pick one.

## 6. Verdict and device checks

Verdict:
1. Boot: no stub needed. The port boots. [seen]
2. Residual risk: a hang when the fusion light path starts on pipa. Probability: low, because the gate seems false. [inferred]
3. Cheapest guard: remove the `oplusSensor` `<hal>` block from `/system/etc/vintf/manifest.xml` in a new port step (text edit, exactly one anchor). Then `isDeclared` is false at all 3 sites and the lib logs `ISensorFeature is not declared.` Check first that the VINTF compatibility check does not need the entry: the matrix lists it without `optional`.
4. Build the stub only if the device checks show a real wait. It costs a service, a SELinux label and a test pass, and it brings no feature that pipa needs.

Device checks (read-only):
- `getprop ro.oplus.os_type` and `getprop ro.vendor.oplus.sensor.black_frame_3v1`: gate input.
- `logcat -d | grep -E "ISensorFeature|LazySensorFeature|AidlSensorFeature"`: look for `ISensorFeature isDeclared=` (the value), `is not declared`, `wait for sensor feature service failed`, `triggerSensorFeatureOnBoot`.
- `su -c 'debuggerd -b $(pidof system_server)' | grep -A20 -i -E "oplussensor|LazySensorFeature|ensureCachedService|waitForService"`: a blocked thread shows its stack. Run it again after the light sensor is used (auto brightness, a colour feature).
- `dumpsys sensorservice`: list sensors with `type` 6, 33171028, 33171042, 33171052, 33171059, 33171070 and note their Xiaomi names.
- `service list | grep -i sensorfeature`: confirm the service is absent.
- In the built ROM: `dump.erofs --cat --path=/system/etc/vintf/manifest.xml` shows the entry.

## Open questions

1. Value of `ro.oplus.os_type` on pipa, and the exact test inside `isOSTypeLightBase()`. [unknown]
2. Which Xiaomi sensors on pipa use 33171028, 33171042, 33171052, 33171059, 33171070? Does the `knuckle` problem repeat? [unknown]
3. Does the donor `servicemanager` `isDeclared` read the framework manifest? (AOSP does; not verified here.) [unknown]
4. Which id values do the callers pass to `getSensorCalibrationData`, `sensorWriteNodeFile` and `sensorRawDataEnableDisable`? [unknown]
5. How do the callers treat an empty calibration String and a `-1` write result? [unknown]
6. Does `OplusFusionLightNextGen` ever start on pipa, and on which thread does `activateInternal` run? [unknown]

## Review note (2026-11-03): declared but not served

The donor `/system/etc/vintf/manifest.xml` declares three OPPO vendor HALs that no system process serves:
`oplusSensor` (`ISensorFeature/default`), `urcc` (`IUrcc/default`) and `hummingbird` (`IOplusHmbirdService/default`).
On the donor the odm side serves them. On pipa nothing does, so `AServiceManager_isDeclared` is true and a following
`waitForService` blocks with no timeout (`libsensorserviceextimpl.so`, `liboplus-uah-client.so`). Java callers use
`ServiceManager.getService` and do not wait. Step 4q (`maintainer/port/steps/70-4q-vintf-absent-hals.sh`) removes the
three entries. `compatibility_matrix.device.xml` states what the vendor side must give, so the framework manifest change
does not change a VINTF check. Check on the device after 4q: `logcat | grep -i "not declared"` shows the clients take
the null path; `service list | grep -i -E "SensorFeature|Urcc|Hmbird"` is empty, as before.
