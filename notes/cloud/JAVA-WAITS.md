# Java blocking waits in the ColorOS 17 donor (C.07) and their effect on pipa

- Donor: OPD2515 C.07 (`system/system/` and `system_ext/` only).
- Date: 2026-11-03.
- Status: static analysis. No device. Nothing is tested.
- Tags: [seen] = read in the dex. [inferred] = follows from [seen] facts and AOSP behavior. [unknown] = needs the device.

## 1. Method

1. I listed every jar and apk in `system/system` and `system_ext` (434 files).
2. I searched the raw dex bytes for `waitForService` and `waitForDeclaredService`. 38 files matched. Candidate list: (cloud work folder).
3. I parsed the dex with androguard (a patched androguard is needed (`HiddenApiClassDataItem` enum) for `framework.jar`, `oplus-framework.jar`, `telephony-common.jar`, `subsystem-framework.jar`). Script: (cloud work folder). Output: (cloud work folder). It lists each `invoke` of the two methods with the class, the method, the nearby string constants and a `guard` flag. The flag is true when the same method also calls `isDeclared` or `checkService`.
4. For HIDL and retry loops I scanned 258 files with (cloud work folder) (output (cloud work folder)). It finds HIDL `getService` calls and methods that call `ServiceManager.getService`/`checkService` together with `Thread.sleep`/`SystemClock.sleep`.
5. For each OPPO site I traced the callers ((cloud work folder)) and the thread (new `Thread`, executor, handler, binder).
6. Limits:
   - Native libraries are out of scope (`maintainer/wfs_scan.sh` covers them).
   - The caller search sees only direct calls. Reflection and Handler dispatch are not followed.
   - Service names that the code builds at run time (string concatenation, constants from other classes) show as empty in the table.
   - `oplus-framework.jar` has no direct `waitForService` call. It has only the `com.oplus.wrapper.os.ServiceManager.waitForService` wrapper. The same wrapper is in `Bluetooth.apk`. I found no caller of the wrapper in 29 jars/apks that reference it [seen, with the direct-call limit above].

## 2. Facts that decide the impact

- [seen] `android.os.ServiceManager.waitForDeclaredService` in the C.07 `framework.jar` calls `isDeclared` first. It calls `waitForService` only when the name is declared. If the name is not declared, it returns null at once.
- [inferred] `isDeclared` reads the merged VINTF manifests (vendor, odm, system, system_ext, product). A name that pipa's vendor and odm manifests do not declare gives null at once. A name that they declare, but that no process registers, blocks with no timeout.
- [seen] In the donor, only `system/etc/vintf/manifest.xml` declares OPPO names on the system side. These are `commondcs`, `hummingbird`, `oplusSensor`, `osense.client` and `urcc`. Step 4q already removes `hummingbird`, `oplusSensor` and `urcc`. The system_ext manifests declare no OPPO name.
- [unknown] The VINTF files of pipa's `vendor` and `odm` are not here. The port copies some C.06 odm files (step 3k). Check them on the device (section 6).
- [seen] HIDL `getService()` (no argument) calls `getService("default")`. That calls `HwBinder.getService(iface, name)`, which passes retry = false. Only `getService(true)` and `getService(name, true)` wait. I checked the generated class `vendor.oplus.hardware.biometrics.fingerprint@2.1` and `android.os.HwBinder` in the C.07 `framework.jar`. The task text says that `getService()` retries. In this donor it does not.
- [inferred] HIDL `getService(true)` waits only for an instance that the device manifest declares. For an undeclared instance, `hwservicemanager` answers with null at once.
- [seen] Plain `ServiceManager.waitForService` has no `isDeclared` guard in most sites. The sites with a guard are `OplusLocationAidlClient.bindOplusLocationService` (lbs), `IContextHubWrapper` (AOSP) and `ServiceManager.waitForDeclaredService` itself.
- [inferred] A service with an `interface aidl <name>` line in an init `.rc` file is started by init on the first lookup (lazy start). This applies to `DefragService`, `cotaservice`, `aiseal_host` and `vendor.qti.ImsVtService.IImsVtRequest/ImsVtService`. All four binaries are in the donor `system_ext` or `system`. They therefore exist on pipa. Whether they start and register is [unknown].

## 3. Table

Reading help: "pipa has it" refers to the HAL inventory (`cloud/hal-inventory:notes/cloud/HAL-INVENTORY.md`). "Port patch" is what the repository does today.

### 3.1 OPPO and vendor sites (relevant)

| file | class.method | service | process/thread | trigger | pipa has it | port patch | impact | fix |
|---|---|---|---|---|---|---|---|---|
| oplus-services.jar (classes.dex) | `OplusEngineerFwService.getEngineerService` | `vendor.oplus.hardware.engineer.IEngineer/default` | system_server; caller thread (binder methods such as `getImpedance`, `getVibratorCalibrateResult`) | factory-mode binder calls; at boot when `isRootVersion()` is true | no (missing) | yes: `patch_framework.sh` edit 4 (00-base) | none after patch; hang at boot without it [seen in the port notes] | re-apply on the C.07 jar. Structure is the same as C.06 [seen] |
| oplus-services.jar (classes2) | `OplusStorageManagerFeature.connectDefrag` | `DefragService` | system_server; caller of `runIdleMaintForground` | idle maintenance | binary `system_ext/bin/oplus_defrag` is in the ROM; `rc` has `interface aidl DefragService`, `disabled` | no | blocks the idle-maintenance thread if the service never registers [inferred] | section 5, item D |
| services.jar (classes) | `StorageManagerService.connectDefrag` (called from `runIdleMaint`) | `DefragService` | system_server; thread that calls `runIdleMaint` (idle job) | idle maintenance, property `persist.sys.oplus.disableDefragFiles` | as above | no | same as above | section 5, item D |
| services.jar (classes) | `StorageManagerService.lambda$replayTurboPocketBootAsync$4` | `DefragService` | system_server; new `Thread` named `replayTurboPocketBoot` | boot (unless `persist.sys.oplus.disableTurboPocket` is set) | as above | no | one leaked thread [seen: own thread, null is logged] | section 5, item D |
| oplus-services.jar (classes2) | `DeviceStorageMonitorServiceExtImpl$StorageCompressDedupProvider.startAppCompressAndFileDedup` | name built at run time [unknown]; probably `CompressScanService` (same rc as Defrag) [inferred] | system_server; caller thread of the dedup scan | storage monitor, low-space or idle | `defrag.rc` also lists `CompressScanService` [seen] | no | blocks the storage monitor caller [inferred]; logs "binder is null" when null [seen] | section 5, item D |
| oplus-services.jar (classes) | `OplusOperatorManagerService.waitForCotaService` (used by 13 methods: `mountCotaImage`, `getCotaModuleInfos`, `saveCotaVersionInfo`, ...) and `OplusCustomizeRollback.waitForCotaService` (from `preRollback`) | `cotaservice` | system_server; binder threads or the thread that runs the operator manager | operator config, SIM switch, rollback | `system_ext/bin/cotad`, `interface aidl cotaservice`, `disabled` | no | blocks a binder thread if `cotad` does not register [unknown] | section 5, item E |
| oplus-services.jar (classes2) | `NfcExtnsService.getNfcExtnsService` | `NfcExtnsService/default` (`vendor.oplus.hardware.nfcExtns.INfcExtns`) | system_server binder thread | only the engineering calls `oplusPnscr*` | no (missing; tablet has no NFC) | no | one blocked binder thread per call; low | section 5, item G |
| oplus-services.jar (classes2) | `TransmessgeManager.obtainTransmessgeAidlService` | `vendor.oplus.hardware.transmessage.ITransmessge/default` (`waitForDeclaredService`) | system_server; caller thread of the `native*File` methods | usage-service file calls | no (missing) | no | none if not declared; blocks the caller if declared [inferred] | no patch. Check the manifest |
| Olc.apk (classes2) | `b2.o.c` (called from `b2.o.i` and `b2.o.k` through `b2.o.b`) | `vendor.oplus.hardware.transmessage.ITransmessge/default` | `com.oplus.olc`, persistent, system uid; thread [unknown] | log core start | no (missing) | no | a blocked thread in a persistent app. ANR only if it is the main thread [unknown] | section 5, item F |
| oplus-lbs-services.jar | `OplusLocationAidlClient.bindOplusLocationService` | `vendor.oplus.hardware.location.IOplusLocation/default` | system_server; location handler (`LocalHandler` on an `OplusLocationThreadRenter` queue) | geofence feature (`config_geofenceMtkSubFunction`) | no | no | none: the method calls `isDeclared` first and logs "Hal location is not exist!" [seen] | none. This corrects the inventory ("lazy wait") |
| subsystem-framework.jar | `ClientMessengerHelper$1.run` | name from `listenServiceUp(name)` (subsys AIDL service names) | each client process; new `Thread` named `ClientMessenger` per name | first use of the subsys client | subsys, subsys_radio: present | no | one thread per name. Leak only if a name is absent [inferred] | none |
| framework.jar (classes) | `AiSealManager.connectToHostService` (via `connectService` lambda) | `aiseal_host` | any app process that uses `AiSealManager`; lambda (executor thread) [inferred] | feature use | `system/bin/aisealhostservice`, `interface aidl aiseal_host`, started when `service.aiseal.enable=1` | no | one blocked executor thread in the app | none; check with `service list` |
| services.jar (classes4), SystemUI.apk, Settings.apk, OplusCommercialEngineerMode.apk | `IrisHalAidlImpl.initialize`, `IrisFeatureHalAidlImpl.<init>` (`waitForDeclaredService`); HIDL `IrisHalHidlImpl.initialize` and `IrisFeatureHalHidlImpl.<init>` use `getService(true)` | `vendor.pixelworks.hardware.display.IIris`, `...feature.IIrisFeature` | system_server: display thread (`LocalDisplayDeviceExtImpl.initIrisHal`); SystemUI main thread (`IrisHal.<init>`) | display device add (boot); SystemUI start | no | partly: SF native waits removed in 2x. Java side not patched | none if undeclared: both paths test `isDeclared` first [seen]. If declared: display thread and SystemUI main thread block (boot hang) | no patch. Check the manifest. Fix: section 5, item B |
| oplus-services.jar (classes) | `OplusEyeProtectLcdInfoHelper.getOplusMiscService` (HIDL `getService(true)`) | `vendor.oplus.hardware.misc@1.0::IOplusMisc` | system_server; display color config. Chain: `OplusFeatureColorMode.<clinit>` / `OplusColorConfig.<init>` -> `ColorModeConfig.buildDeviceIdentifier` -> `getDevInfo` -> `readNodeFile` [seen as caller chain; run time order is inferred] | boot (color mode config) | no (missing) | no | none if `misc@1.0` is not declared. If declared: system_server blocks at boot [inferred] | section 5, item A |
| oplus-services.jar (classes) | `AlertSliderHw.getOplusMiscService` (HIDL `getService(true)`) | `vendor.oplus.hardware.misc@1.0::IOplusMisc` | system_server; `getHwKeyState` path | alert slider key (the tablet has no slider) | no | no | same condition as above, but probably not reached | section 5, item A |
| ims.apk | `ImsVtRequestAidl.initImsVtService` (from `ImsMedia.init`) | `vendor.qti.ImsVtService.IImsVtRequest/ImsVtService` | `org.codeaurora.ims`, process `com.qti.phone`, persistent; thread [unknown] | IMS start | `imsvtdaemon` is in the ROM (lazy start), but it needs a modem | no | a blocked thread in a persistent phone process [unknown] | section 5, item H |
| dpmserviceapp.apk | `DpmAidlVndrInterface.connect`, `MwqemVndrAidlInterface.connect` | name ends with `/default` (prefix not seen), and `.../MwqemAdapter` | `com.qti.dpmserviceapp`, process `.dataservices`, persistent; thread [unknown] | app start (`DpmVndrService.connect`, `MwqemVndrApp.connect`) | `dpmd` is in the ROM (`disabled`); vendor side [unknown] | no | blocked thread in a persistent process [unknown] | section 5, item H |
| ImsDataChannelService.apk | `ImsDataChannelServiceMgr.queryForAidlService` | `vendor.qti.ims.datachannelservice.IDataChannelService/default` | process `.dataservices`, persistent; executor thread (`startQueryForAidlService` -> `Executor.execute`) | app start | no (vendor side, [unknown]) | no | one blocked executor thread [seen: executor] | section 5, item H |
| PostmanService.apk, BTtestmode.apk, OplusCommercialEngineerMode.apk, oplus-evolution-satellite.jar | `SatelliteZbClient.<init>`, `SatelliteRsmcClient.<init>`, `RsmcSatelliteService$18.run`, `TTSatelliteProxy.getSatelliteHal` | `vendor.oplus.radio.ttsatellite` (+ `zb`), satellite rsmc `.../default` | the host app; constructor thread (probably main) [inferred] | satellite feature or engineering app start | no | no | app ANR if the constructor runs on the main thread. Satellite service should not start on a tablet [inferred] | section 5, item I |
| OplusCommercialEngineerMode.apk, OplusCommercialEngineerCamera.apk | `EngineerHalHelperByAidl.getEngineerService` / `initHalService` / `c` (3 classes) | `vendor.oplus.hardware.engineer.IEngineer/default` | `com.oplus.engineermode`, `com.oplus.engineercamera`; app thread | user opens the factory app | no | no | app ANR in a factory app only | none; low |
| oplus-telephony-common.jar, oplus-telephony-common-ext.jar, oplus-subsys-tool.jar, oplus-wifi-service.jar, oplus-lbs-services.jar (OplusMtkGnss), qcrilmsgtunnel.apk, xrcbservice.apk, SecureElement.apk, EidService.apk, SoterService.apk | `waitForDeclaredService` only (esim, radio, subsys, wifi supplicant, mtk gnss, qcril oemhook, qxr, secure_element, eID, soter, IFactory) | many | various | various | mostly no | no | none unless the name is declared in pipa's VINTF. subsys and subsys_radio are present on pipa | check the manifest list (section 6) |

### 3.2 Retry loops (getService plus sleep) [seen]

| file | class.method | service | thread / trigger | pipa has it | impact |
|---|---|---|---|---|---|
| oplus-services.jar (classes2) | `OplusRemovableAppManager.waitInstalldReady` | `installd` (`getService` + `Thread.sleep`) | system_server; boot | yes (AOSP `installd`) | none |
| oplus-services.jar (classes2) | `OplusShutdownFeature.delayForPlayAnimation`, `shutdownService` | `checkService` + sleep (bounded by the shutdown animation) | shutdown | n/a | none |
| services.jar, framework.jar, svc.jar | `NetworkStackClient.getRemoteConnector`, `IdmapDaemon.getIdmapServiceLocked`, `ArtModuleServiceManager$ServiceRegisterer.waitForService`, `PowerCommand.run` | AOSP services (`network_stack`, `idmap`, `artd`, `power`) | AOSP code | yes | none |

### 3.3 HIDL with retry = true, OPPO and vendor interfaces [seen]

| file | class.method | interface | impact on pipa |
|---|---|---|---|
| oplus-services.jar | `OplusEyeProtectLcdInfoHelper.getOplusMiscService`, `AlertSliderHw.getOplusMiscService` | `vendor.oplus.hardware.misc@1.0::IOplusMisc` | see table 3.1 and item A |
| services.jar (classes4) | `IrisHalHidlImpl.initialize` (`IIris@1.1`), `IrisFeatureHalHidlImpl.<init>` | `vendor.pixelworks.hardware.display`, `.feature` | guarded by `isDeclared`; item B |
| OplusCommercialEngineerMode.apk | `OplusMiscHelper.*` (5 methods), `OplusTouchHelper.*` (3), `IrisHalHidlImpl.initialize` | `misc@1.0`, `touch@1.0`, `IIris` | factory app only; low. `touch` is shimmed |
| services.jar (classes4) | `ActivityTaskSupervisorSocExtImpl.getServicetrackerInstance` | `vendor.qti.hardware.servicetracker@1.2` | the argument is not a clear constant in my scan [unknown]; check `lshal` |

The many other HIDL `getService()` calls (face, fingerprint, nfc, displaypanelfeature, cwb, lmvibrator, esim, wifi, handlefactory, performance, charger) use retry = false. They return null at once. They need no patch for waits.

### 3.4 AOSP and stock Qualcomm sites (not OPPO code)

These sites exist in the same form in beta4. I did not analyze them one by one. They are [inferred] safe, because beta4 boots with the same AOSP code. They are:
`services.jar` (`ConsumerIrService`, `LightsService`, `ThermalManagerService`, `HintManagerService`, `PowerStatsHALWrapper`, `VibratorManager`, `UsbPortAidl`, `UsbGadgetAidl`, `SoundTrigger*`, `LockSettings`, `SyntheticPasswordManager`, `VendorLockAidl`, `RecoverySystemService`, `HealthServiceWrapperAidl`, `IContextHubWrapper`, `FaceProvider/FingerprintProvider.getVhal`, `VirtualCameraController`, `SerialManagerService`, `UsbAuthManager`, `BinaryTransparencyService`, `ApexManager`, `DynamicSystemService`, `HotwordDetectionConnection`, audio `ServiceHolder`), `framework.jar` (`FaceSensorConfigurations`, `FingerprintSensorConfigurations`, `MediaCas`, `MediaServiceManager`, `ArtModuleServiceManager`), `telephony-common.jar` (`RIL`, `RadioConfig`), `Bluetooth.apk` (`SapRilReceiver`), `NetworkStack.apk` and `service-art.jar`.
One point needs a check: `FaceSensorConfigurations.getIFace` and `FingerprintSensorConfigurations.getIFingerprint` call plain `waitForService` for the virtual HAL names. The port has its own face HAL in the `pipa_port` domain. [unknown] whether the call is reached.

## 4. Ranked list (high first)

No unpatched site is a confirmed boot hang on pipa. The one known boot hang (IEngineer) is patched. Three sites become a boot hang if pipa's VINTF declares their name. Rank reflects the worst case and the likelihood.

1. **HIGH if declared, otherwise none: IOplusMisc (HIDL `getService(true)`) in `OplusEyeProtectLcdInfoHelper`.** [inferred] It runs inside system_server in the display color config. It blocks system_server startup if `vendor.oplus.hardware.misc@1.0::IOplusMisc/default` is declared and no process serves it. The HAL inventory says pipa does not declare it. Verify with `lshal`.
2. **MED, conditional: Pixelworks IIris on the display thread.** [seen] `LocalDisplayDeviceExtImpl.initIrisHal` runs in system_server when a display device is added. `IrisHal.createHalImpl` checks `isDeclared` first. A declared but unserved IIris blocks the display thread. That is the same failure class as the QSPM hang of C.06. SystemUI (persistent) does the same on its main thread.
3. **MED: `DefragService` waits (4 sites in system_server).** [seen] No `isDeclared` guard, no patch. `oplus_defrag` is `disabled` and lazy-started. If it does not start or does not register, `runIdleMaint` blocks the idle-maintenance thread, and the dedup scan blocks its caller. The boot-time `replayTurboPocketBoot` call uses its own thread (one leaked thread).
4. **LOW-MED: `cotaservice` waits (14 methods in system_server).** [seen] `cotad` is lazy-started and lives in `system_ext`. A failed start blocks a binder thread per call. [unknown] whether anything calls them on pipa at boot.
5. **LOW-MED: persistent phone processes (`ims.apk`, `dpmserviceapp.apk`, `ImsDataChannelService.apk`).** [seen] Unguarded waits for Qualcomm vendor services. A blocked thread in `com.qti.phone` or `.dataservices`. These processes also host other work. The thread is unknown for two of them.
6. **LOW: `com.oplus.olc` waits for transmessage.** [seen] Persistent, system uid, unguarded. One blocked thread. The same wait is in `TransmessgeManager` but behind `isDeclared`.
7. **LOW: `NfcExtnsService`, `AiSealManager`, satellite clients, engineer apps, `ClientMessengerHelper`.** One thread or one app call each. No boot effect.
8. **NONE: lbs `bindOplusLocationService`.** It has an `isDeclared` guard.

## 5. Fix plan

Common method (patch kind P1): change the call from `waitForService` to `checkService`. Both are `static (String)IBinder` in `android.os.ServiceManager`, so the instruction size stays equal.
- In smali: replace the method name in the `invoke-static` line. Use `-j 1` for smali and baksmali (AGENTS.md).
- In place (as for APKs, AGENTS.md "Patching a system app"): in the dex, change the 16-bit method index of the `invoke-static` to the index of `ServiceManager.checkService(String)`. That method id must exist in the same dex. If it does not, use the smali route. Then fix the dex checksum and signature.
- Each patch must find its anchor exactly one time. Anchor = the class, the method, and the `const-string` with the service name directly before the call. If the anchor is not found, stop.
- Check the null path first. The callers below log and return on null [seen] for Defrag and the dedup scan. For `cotaservice` the code passes the result to `Binder.allowBlocking` and `asInterface`, which accept null [seen]. The callers of those methods must then handle a null interface [unknown].

| item | site | patch | anchor | test |
|---|---|---|---|---|
| A | `OplusEyeProtectLcdInfoHelper.getOplusMiscService` and `AlertSliderHw.getOplusMiscService` | Change `IOplusMisc.getService(Z)` to be called with false. Smali: change the `const/4 vX, 1` before the call to 0. Or change the call to `getService()` (no argument) | the method and the `Failed to get service, error is : ` string | `logcat -s OplusEyeProtectLcdInfoHelper`. `kill -3 system_server` (or `debuggerd -b <pid>` for native frames) must show no thread in `HwBinder.getService` |
| B | Iris sites in services.jar classes4, SystemUI classes9 | Only if `lshal` shows IIris declared: P1 for `IrisHalAidlImpl.initialize`, and retry false for the HIDL path | `IrisHalAidlImpl.initialize` with the `"IrisHal"` / `"Use IIris AIDL"` strings | `logcat -s IrisHal` must show "No found IIris service". display thread must not wait |
| C | engineer: keep the existing patch | re-run `patch_framework.sh` on the C.07 `oplus-services.jar`. Edit 4 anchor is unchanged in C.07 [seen]: `isRootVersion()` result tested by `if-eqz`, then `initHalService`, then `waitForService` with `vendor.oplus.hardware.engineer.IEngineer/default` | as in the script | `logcat -s OplusEngineerFwService` |
| D | 4 Defrag sites | P1 on all four (2 in `oplus-services.jar` classes2, 2 in `services.jar` classes). Optional: a smaller change that keeps the lazy start is to call `checkService` once and ignore null | const-string `DefragService` before the call; the log strings `defrag not found; trying again`, `replayTurboPocketBoot: DefragService not found`, `scanner: wait for ` | `service list \| grep -E 'DefragService|CompressScanService'`; `logcat -s StorageManagerService OplusStorageManagerFeature`; `sm idle-maint run` (root) and check that the call returns |
| E | `cotaservice` | P1 in `OplusOperatorManagerService.waitForCotaService` and `OplusCustomizeRollback.waitForCotaService` (2 methods, not 14 call sites) | const-string `cotaservice` | `service list \| grep cota`; `logcat \| grep -i cota` |
| F | Olc transmessage | P1 in `b2.o.c` (obfuscated name; the name can change per build). Anchor: the string `vendor.oplus.hardware.transmessage.ITransmessge/default` plus the `createService HIDL: ` string. Patch the dex in place | as left | `logcat \| grep TransmessgeHelper`. `kill -3 $(pidof com.oplus.olc)` shows no waiting thread |
| G | `NfcExtnsService` | P1 or leave. Not needed | const-string `NfcExtnsService` then `/default` | none |
| H | ims, dpm, imsdatachannel | Prefer to not start the packages on pipa (disable them in the ROM) if the tablet has no cellular data. Otherwise P1 in the connect methods. They live in `system_ext`, so a smali patch needs the APK platform signature kept: use the in-place dex patch | `ImsVtRequestAidl.initImsVtService`, `DpmAidlVndrInterface.connect`, `ImsDataChannelServiceMgr.queryForAidlService` | `kill -3 $(pidof com.qti.phone)` and the `.dataservices` pid; look for `ServiceManager.waitForService` frames |
| I | satellite clients | none; do not start the satellite service. Optional P1 | constructor of `SatelliteZbClient` | none |

Test commands (all need root through `su -c`, and the pid file rule of AGENTS.md):
- Find the blocked thread of a native or Java process: `debuggerd -b <pid>`.
- Java frames: `kill -3 <pid>`, then read `/data/anr/anr_*`. A hang in system_server also writes `/data/anr/traces_SystemServer_WDT*`.
- Search logcat for the strings in the anchor column. A skipped wait prints the app's own "not found" line.
- Live test of a jar or APK: bind mount over the original in init's namespace and restart the app or zygote (AGENTS.md "Live test of a framework jar"). Do not kill `system_server`.

## 6. Open questions

1. [unknown] What do pipa's `/vendor/etc/vintf` and `/odm/etc/vintf` declare? Read the files, and run `lshal --init-vintf` (HIDL and AIDL) or `service list` plus `cmd -l` on the device. List these names: `misc@1.0`, `pixelworks IIris` (AIDL and HIDL), `IIrisFeature`, `transmessage`, `location`, `esim`, `oplus wifi`, `qti ImsVtService`, `qti datachannelservice`, `dpmservice`, `servicetracker@1.2`. The result sets the rank of items A and B.
2. [unknown] Do `oplus_defrag`, `cotad` and `aisealhostservice` start and register on pipa (`service list`, `getprop init.svc.oplus_defrag`)? Do their SELinux domains work with the pipa policy?
3. [unknown] Which thread starts the Olc, ims, dpm and satellite waits? I did not trace past the first caller.
4. [unknown] Does the port boot with C.07 jars? The `waitForDeclaredService` guard makes most sites safe. The C.07 jars have new md5 values. Re-apply every jar patch.
5. [unknown] Do `FaceSensorConfigurations` and `FingerprintSensorConfigurations` (framework.jar) reach their plain `waitForService` on pipa (virtual HAL names)?
6. [unknown] `OplusEyeProtectLcdInfoHelper`: what runs it at boot (`OplusFeatureColorMode.<clinit>`)? Confirm the order with a boot trace. The caller chain is [seen]. The time is [inferred].
7. Native libraries and `oplus-framework.jar` internals use `AServiceManager_waitForService`. `maintainer/wfs_scan.sh` covers them. The next step is a C.07 vs C.06 diff of those imports. This is outside this draft.
8. The inventory says `OplusLocationAidlClient` waits with no guard. The C.07 code has an `isDeclared` guard [seen]. Update `HAL-INVENTORY.md`. The inventory also lists `NfcExtnsService`, `Satellite*` and `Olc` correctly.

## Review note (2026-11-03)

- `DefragService` (MED): the server is OPPO's own `oplus_defrag` (system_ext, lazy `interface aidl DefragService`).
  The real fix is to make it start and register on pipa, so that OPPO's f2fs defrag and file dedup work as on
  ColorOS. Device check first: `getprop init.svc.oplus_defrag`, `service check DefragService`, logcat for its tag
  during idle maintenance (`cmd jobscheduler run -f android 808` runs it; see `dumpsys jobscheduler` for the id).
  If it fails (missing kernel or f2fs feature), find the cause before any `checkService` patch.
- `IOplusMisc` / Iris: wait only when pipa's VINTF declares them. `lshal` / `service list` on the tablet decides.
