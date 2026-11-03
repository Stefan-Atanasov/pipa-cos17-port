# Persistent and boot-started system apps on pipa: RAM review (static, donor C.07)

Status: draft. Static analysis only. No device was used.
Tags: [seen] = read in a manifest, sysconfig, repo file or dump. [inferred] = my conclusion from names or strings. [unknown] = needs a device check.

## 1. Scope and method

- [seen] Donor C.07 `system/system/{app,priv-app}` and `system_ext/{app,priv-app}`: 163 APKs. I parsed all manifests with androguard.
- [seen] The `my_*` and `product` partitions are not available. Apps that live there are not in this note. Likely examples: the NetworkAssistSys host app, NFC engineer test, Wallet, eSIM manager, Phone Manager. Their persistent state is [unknown].
- [seen] The port already removes these donor apps (PORT-EDITS.tsv, action `remove`): `OTA`, `SystemAppUpdateService`, `SAUHelper`. It also removes debloat apps from `my_stock/del-app` and `my_product/del-app` (Melody is re-added by step 4c). I do not repeat them.
- [seen] The port adds `android.hardware.telephony.gsm` so that the ColorOS telephony stack runs on the Wi-Fi pad. Steps 3c and 3d add a **virtual modem** (AIDL radio V3, ims V7) for call sharing with the phone. Thus the telephony stack is **not** dead on pipa. The IMS app (`org.codeaurora.ims`) must stay (step 3d header: without it a call never rings on the pad).
- [seen] The `.dataservices`, `com.qti.phone`, `com.android.phone` and `com.oplus.subsys` processes each host several packages. Removing one package of a shared process saves little RAM. The process leaves only when all its packages leave.
- RAM figures are estimates (typical PSS of a persistent app: 15-60 MB). [unknown] until a `dumpsys meminfo` run.

## 2. Persistent apps (android:persistent="true"), 19 packages

APK size is in KB. Process = `android:process`, "own" = package name.

| package | path (under donor fs) | persistent | needs | verdict | evidence | risk |
|---|---|---|---|---|---|---|
| com.android.nfc | system/system/priv-app/NfcNci (9.7 MB) | yes, uid android.uid.nfc, own process, dba, BOOT_COMPLETED | NFC chip and NFC HAL | NONE-ON-PIPA | [seen] pipa has no NFC. HAL-INVENTORY.draft.md line 89 lists nfc, nfcExtns, felica, eid, secure_element as "NONE on a Wi-Fi tablet". [seen] `NfcNci.xml` permissions file, `nfcvendorlib.xml`. [unknown] whether NfcService exits early when `android.hardware.nfc` is absent. | LOW-MED. Name appears in the Athena protect list (`Athena/p0/c.txt`) and in BluetoothManagerService (`dis/services`), `DefaultPermissionGrantPolicy`, StartingWindowConstants. [inferred] These are string lists, not binds. Bluetooth.apk declares `NFC_HANDOVER_STATUS` use; it is a framework permission. The `Tag` app and the NFC settings toggles lose their target (both are hidden without the feature). |
| com.android.se | system/system/app/SecureElement (348) | yes, uid android.uid.se, own process, dba | Secure element HAL (eSE/UICC) | NONE-ON-PIPA | [seen] JAVA-WAITS lists SecureElement.apk with `waitForDeclaredService` for `secure_element`. [seen] HAL-INVENTORY: `ISecureElement` is absent on a Wi-Fi tablet. | LOW. Its only service is `SecureElementService`. Only NFC card emulation and Wallet apps bind it. [inferred] `com.android.se` appears in many strings, but most are `com.android.server` prefix matches. I did not find a hard dependency. |
| com.qti.qcc | system_ext/app/QCC (1.2 MB) | yes, own process, dba, BOOT_COMPLETED + LOCKED_BOOT_COMPLETED | Data network, a carrier or Qualcomm server | NONE-ON-PIPA (telemetry) | [seen] Actions `com.qualcomm.qti.qdma.PERIODIC_CI_REGISTRATION` and `..._WAITING_FOR_NETWORK`. [seen] Classes in `com.qualcomm.qti.qdma` (job manager, transfer, session). Services: FileDeliveryService, MgmTreeService, IsvService. [inferred] QDMA = Qualcomm device management and client-insights upload. | LOW. [seen] `Battery/k6/a.txt` lists the package name next to `org.codeaurora.ims` (a package list, probably a battery-whitelist). No bind found. |
| vendor.qti.data.ntnsatapp | system_ext/app/NtnSatApp (92) | yes, uid phone, process `.dataservices` | Non-terrestrial (satellite) data | NONE-ON-PIPA | [seen] Name "Ntn" + `NtnDataServiceImpl`. `android.telephony.satellite.xml` is present. Task says: no satellite. | LOW alone. It shares the process with two other packages (see below), so RAM gain alone is about 0-2 MB. |
| vendor.qti.imsdatachannel | system_ext/app/ImsDataChannelService (136) | yes, uid phone, process `.dataservices` | IMS data channel HAL (`IDataChannelService`) | UNSURE | [seen] JAVA-WAITS item H: unguarded wait for `vendor.qti.ims.datachannelservice...`. [seen] The ims app is needed for call sharing. [unknown] whether IMS data channel is used by the virtual modem. | MED. Same process as dpm. |
| com.qti.dpmserviceapp | system_ext/priv-app/dpmserviceapp (80) | yes, uid phone, process `.dataservices`, BOOT_COMPLETED | Qualcomm DPM (data port mapper) over a modem | UNSURE | [seen] JAVA-WAITS item H: `DpmAidlVndrInterface.connect` waits for a vendor service. [seen] `Athena/p0/c.txt` lists the package (protect list). | MED. Remove `.dataservices` only after a check that no call or Wi-Fi calling path uses it. The whole process (3 packages) may use 15-30 MB (estimate). |
| org.codeaurora.ims | system_ext/priv-app/ims (997) | yes, uid qtiphone, process `com.qti.phone` | IMS stack, for virtual-modem calls | **KEEP** | [seen] Step 3d header: the IMS app must find `IImsRadio/imsradio0`, else call sharing does not ring. | Removing it breaks call sharing. |
| com.qualcomm.qcrilmsgtunnel | system_ext/priv-app/qcrilmsgtunnel (92) | yes, uid qtiphone, process `com.qti.phone`, LOCKED_BOOT | QCRIL OEM hook | UNSURE | [seen] It shares the `com.qti.phone` process with ims, so no RAM gain alone. [seen] allow-in-power-save in sysconfig. | LOW gain. Keep. |
| com.android.phone | system_ext/priv-app/TeleService (29 MB) | yes, uid phone | Telephony core | **KEEP** | [seen] Task rule: core. It hosts TelephonyProvider, MmsService, BeidouMsgService, ONS. | n/a |
| com.android.ons | system/system/priv-app/ONS (104) | yes, uid phone, process `com.android.phone`, LOCKED_BOOT | Opportunistic network (CBRS) switching | NONE-ON-PIPA (code only) | [seen] Service `OpportunisticNetworkService`. [inferred] Needs a real multi-SIM modem. | Gain ~1-3 MB (estimate), it shares `com.android.phone`. Not worth the risk. |
| com.android.cellbroadcastservice | system_ext/priv-app/CellBroadcastService (1.2 MB) | yes, process `com.android.networkstack.process` | Cell broadcast (alerts) | NONE-ON-PIPA but KEEP | [seen] It shares the NetworkStack process (core). | Gain ~0. Do not touch. |
| com.android.networkstack | system/system/priv-app/NetworkStack | yes | Network core | **KEEP** | [seen] Core. | n/a |
| com.android.systemui | system_ext/priv-app/SystemUI | yes | UI | **KEEP** | [seen] Core. | n/a |
| com.oplus.athena | system_ext/app/Athena (2.9 MB) | yes, uid system | Memory and process manager, app freezer (Hans) | **KEEP** | [seen] Services: AthenaService, AppFrozenService, OplusPinnerService. BUGS.md item 2 uses its freezing. Hosts Battery (`com.oplus.battery`) in its process. | Removing it raises RAM use. |
| com.oplus.healthservice | system_ext/app/HealthService (561) | yes, process `com.oplus.exsystemservice` | Keep-alive, stylus services | **KEEP** | [seen] Services `StylusTouchInterceptService`, `StylusPressReceiver`, `KeepAliveService`, plus `StepBRPluginService`. The pen pill and pen features need the stylus parts. | Shares the exsystemservice process, so no gain. |
| com.oplus.exsystemservice | system_ext/priv-app/OplusExSystemService (19 MB) | yes, uid system, LOCKED_BOOT | App manager, cast manager, headset dialog, compatibility | **KEEP** | [seen] `CastManagerWrapper` in oplus-services references it. 19 services, 19 providers. | n/a |
| com.oplus.atlas | system_ext/app/OplusAtlasService (718) | yes, process `com.oplus.persist.multimedia`, BOOT + LOCKED_BOOT | Thumbnails, file observer | KEEP | [seen] Services `OplusThumbnailService`, `OplusFileObserveService`. Named in OplusPackageHideManager and AudioServiceExtImpl (`dis/oplus-services`). | Gallery thumbnails depend on it [inferred]. |
| com.oplus.subsys | system_ext/app/SubsystemApp (1.5 MB) | yes, uid system, process `com.oplus.subsys` | Subsystem framework (modem ACI, NAS API, link boost). Hosts `com.oplus.nearcomm` and `com.oplus.voice.crs` | KEEP | [seen] `subsys` AIDL is present on pipa (JAVA-WAITS line 60). Interconnect (steps 3c/3d) uses subsys. `OplusPackageHideManager` names it. Manifest permission mentions eSIM dialog, but the host is shared. | Do not touch. |
| com.oplus.olc | system_ext/app/Olc (5.1 MB) | yes, uid system, own process | OPPO log core: log pack, upload daemon, screen-record log, modem log receiver | UNSURE (telemetry) | [seen] 16 services (`UploadDaemonService`, `LogCoreService`, `RetryUploadJobService`, `OlcPushMessageService`). [seen] notes/cloud/TRANS-URCC-STATS.md: Olc waits on `transmessage` (one blocked thread). Writes `/data/persist_log`. | MED. Removal changes crash and ANR log paths. Many OPPO apps send data to Olc by broadcast (they just fail without it) [inferred]. Process estimate 30-60 MB. |

Not persistent but note: `com.oplus.battery` runs in the Athena process (no own RAM). `com.oplus.qualityprotect` runs in `com.oplus.midas`.

## 3. Boot-started, not persistent

These start at boot and may stay in RAM, but Android can kill them. Gain is small or [unknown].

| package | path | start | needs | verdict | evidence | risk |
|---|---|---|---|---|---|---|
| com.oplus.logtrial | system_ext/app/LogTrialCommercial (35 MB) | BOOT_COMPLETED | Logging, mic and camera features (all `required=false`) | UNSURE (telemetry) | [seen] name "LogTrial Commercial". | LOW. |
| com.android.cellbroadcastreceiver.module | system_ext/priv-app/CellBroadcastReceiver (17 MB) | BOOT_COMPLETED, dba | Cell broadcast from modem | NONE-ON-PIPA | [seen] MODIFY_PHONE_STATE. [seen] Duplicate legacy app `CellBroadcastLegacyApp` (849 KB, dba). | LOW. Android needs a cell broadcast receiver package in config; check overlay first [unknown]. |
| com.oplus.subsys plugins | system_ext/app/NetworkAssistSys_plugin_Cellular* (8 APKs), SubsysPlugins_plugin_CellMap/CellularQoe, NetworkHealthService | none | Cellular network quality | NONE-ON-PIPA | [seen] Names. They are plugin APKs: the host loads them into its own process. The host (NetworkAssistSys) may be in `my_*` [unknown]. | LOW gain. |
| com.oplus.engineermode etc. | OplusCommercialEngineerMode, OplusEngineerNetwork, OplusCommercialEngineerCamera | none | `android.hardware.nfc` / telephony features | NONE-ON-PIPA (factory) | [seen] uses-feature nfc, telephony. Not started at boot. | Zero RAM. Skip. |
| satellite auth | RsmcSatelliteAuth (32 KB), TTSatelliteAuth (32 KB), BeidouMsgService (4.5 MB, in `com.android.phone`) | none | Satellite | NONE-ON-PIPA | [seen] Names. [seen] oplus-evolution-satellite.jar clients use `waitForService` (JAVA-WAITS item I). | Zero RAM. Skip. |
| others: Traceur (BOOT), PowerSaveMode (LOCKED), workloadclassifier (BOOT+LOCKED, QTI), PowerMonitor (BOOT, uid system), OplusEyeProtect (BOOT+LOCKED), OplusLocationService (BOOT), SafeCenter, SecurityPermission, NotificationCenter, Settings, StorageManager, DocumentsUI, ManagedProvisioning, DynamicSystemInstallationService, MtpService, CalendarProvider, DownloadProvider, OppoPackageInstaller | various | BOOT | | KEEP | [seen] AOSP core or user features. EyeProtect is used by step 3f. PowerMonitor has a repo analysis (`dis/PowerMonitor`). Traceur is a dev tool (not needed, tiny). | n/a |

## 4. Telephony notes

- [seen] pipa has no modem, but the port installs a virtual modem so that call sharing works. `com.android.phone`, Telecom, TelephonyProvider, MmsService and the ims app (`com.qti.phone`) are therefore needed.
- [inferred] Removable telephony add-ons, by lower risk first: `NtnSatApp`, `QCC`, the `Cellular*` NetworkAssist plugins, the satellite auth apps, `CellBroadcastReceiver` and `CellBroadcastLegacyApp`, `ONS`.
- [unknown] Whether `dpmserviceapp` and `ImsDataChannelService` have a role with the virtual modem. Check first (section 7).
- The `.dataservices` process holds three packages (NtnSat, ImsDataChannel, dpm). It can only leave if all three go.
- Fingerprint and biometrics: `FidoAsm`, `SoterService` are not persistent, so no RAM is saved. Skip.

## 5. Ranked removal candidates (largest RAM first)

RAM numbers are estimates.

1. **NfcNci** (`com.android.nfc`): about 15-30 MB. Clear case. Own persistent process. Remove the directory `system/priv-app/NfcNci` in a new step. Also drop `Tag` (not RAM, but dead). Keep `NfcNci.xml`/`nfcvendorlib.xml` (harmless).
2. **QCC** (`com.qti.qcc`): about 15-25 MB. Telemetry. Own persistent process. Clear case.
3. **SecureElement** (`com.android.se`): about 8-15 MB. Own persistent process. Pair it with NfcNci.
4. **Olc** (`com.oplus.olc`): about 30-60 MB. UNSURE. Large gain, but risk of log-path side effects. Test only on a device, with `dumpsys meminfo`.
5. **`.dataservices` process** (NtnSatApp + ImsDataChannelService + dpmserviceapp): about 15-30 MB together. Remove NtnSatApp alone first: it gives about 0. All three: only after the checks in section 7.
6. **CellBroadcastReceiver, CellBroadcastLegacyApp, LogTrialCommercial**: disk gain, small RAM (not persistent).
7. **ONS, qcrilmsgtunnel**: 1-3 MB each, in shared processes. Do not remove.

Do **not** remove: ims, TeleService, Telecom, TelephonyProvider, MmsService, Athena, HealthService, ExSystemService, Atlas, SubsystemApp, NetworkStack, SystemUI.

How to remove: add one step in `maintainer/port/steps/` that deletes the app directory in the tree (not `pm disable`: a clean flash loses it). If the step touches a system APK or jar, call `set_layer`, as AGENTS.md says. Check that the sysconfig `<allow-in-power-save>` lines for removed packages do no harm (a missing package in sysconfig is ignored [inferred]).

## 6. Open questions

1. [unknown] Is `NfcService` already idle on pipa? If the app exits at once when the feature is absent, the gain is small. Measure first.
2. [unknown] Which persistent apps are in `my_*` / `product` (for example `NetworkAssistSys`, `OplusNfc`, eSIM, Wallet)? Needs the device or the beta4 images.
3. [unknown] Does `dpmserviceapp` or `ImsDataChannelService` take part in call sharing?
4. [unknown] Does any Oplus app crash or hang when Olc is absent? Callers use broadcast or `waitForService` [inferred].
5. [unknown] Who binds `QCC` on this ROM? Only name lists were found.
6. [unknown] PSS values. All RAM numbers here are estimates.
7. [unknown] The `CellBroadcastReceiver` config overlay: does framework need the package name to exist?

## 7. Device checks (read-only)

Run as root (`adb shell "su -c '<cmd>'"`). Do not use `pgrep -f` in `su -c`.

```
# which processes run, with PSS, sorted
dumpsys meminfo -s
dumpsys meminfo com.android.nfc
dumpsys meminfo com.qti.qcc
dumpsys meminfo com.android.se
dumpsys meminfo com.oplus.olc
dumpsys meminfo .dataservices
dumpsys meminfo com.qti.phone

# persistent processes in the AMS list
dumpsys activity processes | grep -i persistent
dumpsys activity processes | grep -E "nfc|qcc|\.se|olc|dataservices|qti.phone"

# package paths and flags
pm list packages -f | grep -E "nfc|qcc|android.se|olc|ntnsat|imsdatachannel|dpmservice|qcrilmsg|\.ons"
dumpsys package com.android.nfc | grep -iE "flags|codePath|sharedUser"
dumpsys package com.qti.qcc | grep -iE "flags|codePath"
dumpsys package com.oplus.olc | grep -iE "flags|codePath"

# features the tablet declares
pm list features | grep -iE "nfc|telephony|fingerprint|se\.|ims"

# who binds a service
dumpsys activity services com.qti.qcc
dumpsys activity services com.oplus.olc
dumpsys activity services com.qti.dpmserviceapp
dumpsys activity services vendor.qti.imsdatachannel

# NFC state
dumpsys nfc | head -20
service list | grep -iE "nfc|secure_element|radio|ims"
```

For before/after: run `dumpsys meminfo -s` 60 s after unlock, and again 10 min later, on a build with the step and one without. Compare "Total PSS by process" and "Free RAM".

## Review (2026-11-03)

- Checked: `com.android.nfc` (system/priv-app/NfcNci), `com.android.se` (system/app/SecureElement) and `com.qti.qcc`
  (system_ext/app/QCC) are `android:persistent="true"` in the donor manifests. Step 4s
  (`maintainer/port/steps/72-4s-persistent-no-hw.sh`) removes these three app folders.
- Not removed (need a device check or a decision): Olc (`com.oplus.olc`, log/telemetry; log paths change), the
  `.dataservices` group (only worth it if all three go). The telephony stack stays (virtual modem 3c/3d).
