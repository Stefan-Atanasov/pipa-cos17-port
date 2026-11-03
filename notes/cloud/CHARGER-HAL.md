# Charger HAL and ColorOS charge-control: static analysis of the donor

- Donor: OPPO Pad Mini OPD2515, OTA C.07_1070_202610201803 (build of 2026-10-20). The port doc uses donor C.06. The HAL file dates (2026-10-20 09:38) are from C.07. Check C.06 again before you rely on a detail.
- Date of analysis: 2026-11-03.
- Method: static only (no device). Callers: smali-like dumps of `oplus-services.jar`, `services.jar`, `oplus_bluetooth_common_ext.jar`, Battery, OplusGames (Game Assistant), COSA, Athena, Settings, SystemUI, OBrain, PowerMonitor, OTrace. HAL: `odm/bin/hw/vendor.oplus.hardware.charger-V12-service`. The HAL has a `.gnu_debugdata` section, so it has function names. I read the `chgFuncMapInit` table (type ID to handler) and the strings inside each handler. No code is pasted here.
- Evidence labels: **[seen]** = read in the donor. **[inferred]** = my reading of the evidence. **[unknown]** = not found.
- Working files (disassembly, HAL symbols) stayed in the cloud work folder. They are not in git.

## Short answer for the bypass plan

1. ColorOS sends the bypass request as `setChgConfig(25, "1+switch=1", callname)` (on) and `"1+switch=0"` (off). The HAL writes the string unchanged, plus `|callname=<n>`, to `/sys/class/oplus_chg/common/plc`. **[seen]**
2. Bypass status is `getChgConfig(24, "", callname)`. The HAL returns the content of the same `plc` node. Java code parses it with `Integer.parseInt`. **[seen]**
3. There are two UI paths. (a) All-scene bypass (the donor sets `com.oplus.fullscene_plc_charge.support=true`): the Games app writes `Settings.System bypass_charge_state`, and the Battery app (`BypassChargeController`) turns it into the HAL call. (b) Classic bypass (`com.oplus.plc_charge.support`): the Games app calls the Battery app service and the HAL directly. **[seen]**
4. The shim needs three things: accept type 25 and keep the string, answer type 24 with a decimal string, and answer type 31 (`CHECK_FLAG_SUPPORT`) for the flags the apps ask about. The shim must also do the real work on pipa (stop or reduce charge input). Details in the last section.

## A. ICharger interface

- AIDL name: `vendor.oplus.hardware.charger.ICharger/default` (declared in `odm/etc/vintf/manifest/manifest_oplus_charger_aidl.xml`, version 12). Service: `oplus_charger_hal_service` (`odm/etc/init/vendor.oplus.hardware.charger-V12-service.rc`, user `system`, class `hal`). The HAL also starts the helper daemons `wlschgd`, `gauged`, `ufcsd`.
- V12 has 134 methods plus `getInterfaceVersion` (16777215) and `getInterfaceHash` (16777214). Hash `fe84d18c...`.
- The transaction code equals the constant in `ICharger$Stub` (`FIRST_CALL_TRANSACTION + n`, already folded). The code order is not alphabetical: the 11 methods that V12 added after V1 have the high codes (113 to 134).
- V1 AIDL (`vendor.oplus.hardware.charger-V1-java.jar`, hash `049782b2...`): 123 methods. V12 adds these 11: `getBattGaugeInfo`, `getChgConfig`, `getDeepSleepClustersSleepWake`, `getPowerbankInfo`, `getPsyBatterySN`, `getUsbCurrentEyeDiagram`, `queryRgcpHboostInfo`, `setCV`, `setChgConfig`, `setChgRusConfig`, `setUsbEyeDiagram`. So a V1 stub has **no** `setChgConfig` or `getChgConfig`. The framework that sends types 5/14/24/25 needs the V12 stub (`system_ext/framework/vendor.oplus.hardware.charger-V12-java.jar`).
- V1.0 HIDL (`vendor.oplus.hardware.charger-V1.0-java.jar`, `charger@1.0`): 134 entries with the same old method names (no ChgConfig). `midasd` still links `charger@1.0` and V1-ndk.
- Services that use V1/V12 stubs: system_server (`OplusBatteryServiceFeature`), `OplusGuardElfFeature`, `OplusUsbDeviceFeature`, `ChargeHelper` (display), oplus-wifi-service, bluetooth ext, PowerMonitor, OTrace, OBrain, Settings, SystemUI, RegService, NetworkHealthService, Postman, EngineerMode and others (scan.json).

### Full method list (V12)

Codes are the AIDL transaction codes. A `getInterface*` entry is added by the AIDL tool.

| txn | method | args | returns |
|---|---|---|---|
| 1 | VolDividerIcWorkModeSet | String | int |
| 2 | chgExchangeMesgInit |  | int |
| 3 | chgExchangeSohMesgInit |  | int |
| 4 | getAcType |  | int |
| 5 | getBattAuthenticate |  | int |
| 6 | getBattPPSChgIng |  | int |
| 7 | getBattPPSChgPower |  | int |
| 8 | getBattParamNoplug |  | String |
| 9 | getBattShortIcOtpStatus |  | int |
| 10 | getBattSubCurrent |  | int |
| 11 | getBattVoocChgIng |  | int |
| 12 | getBatteryVoltageNow |  | int |
| 13 | getBccCsvData |  | String |
| 14 | getBccExpStatus |  | int |
| 15 | getBmsHeatingRunningStatus |  | String |
| 16 | getBmsHeatingStatus |  | int |
| 17 | getChargerControl |  | String |
| 18 | getChargerCoolDown |  | int |
| 19 | getChargerCriticalLog |  | int |
| 20 | getChargerIdVolt |  | int |
| 21 | getChargerLog |  | int |
| 22 | getCustomSelectChgMode |  | int |
| 23 | getDevinfoFastchg |  | String |
| 24 | getFastCharge |  | int |
| 25 | getParallelChgMosTestResult |  | int |
| 26 | getPsyAcOnline |  | int |
| 27 | getPsyBatteryCC |  | int |
| 28 | getPsyBatteryCurrentNow |  | int |
| 29 | getPsyBatteryFcc |  | int |
| 30 | getPsyBatteryHmac |  | int |
| 31 | getPsyBatteryLevel |  | int |
| 32 | getPsyBatteryNotify |  | int |
| 33 | getPsyBatteryPchg |  | int |
| 34 | getPsyBatteryPchgResetCount |  | int |
| 35 | getPsyBatteryRm |  | int |
| 36 | getPsyBatteryShortFeature |  | int |
| 37 | getPsyBatteryShortStatus |  | int |
| 38 | getPsyBatteryStatus |  | String |
| 39 | getPsyBatteryTemp |  | int |
| 40 | getPsyChargeTech |  | int |
| 41 | getPsyFastChgType |  | int |
| 42 | getPsyInputCurrent |  | int |
| 43 | getPsyOtgOnline |  | int |
| 44 | getPsyOtgSwitch |  | int |
| 45 | getPsyPcPortOnline |  | int |
| 46 | getPsyQGVbatDeviation |  | int |
| 47 | getPsyTypeOrientation |  | int |
| 48 | getPsyUsbOnline |  | int |
| 49 | getPsyUsbStatus |  | int |
| 50 | getPsyWirelessRX |  | String |
| 51 | getPsyWirelessRxVersion |  | String |
| 52 | getPsyWirelessTX |  | String |
| 53 | getPsyWirelessTxVersion |  | String |
| 54 | getQgVbatDeviation |  | int |
| 55 | getQuickModeGain |  | String |
| 56 | getReserveSocDebug |  | String |
| 57 | getSmartChgMode |  | int |
| 58 | getUIsohValue |  | int |
| 59 | getUisohDebugParameterInfo |  | String |
| 60 | getUsbInputCurrentNow |  | int |
| 61 | getUsbPrimalType |  | int |
| 62 | getWiredOtgOnline |  | int |
| 63 | getWirelessAdapterPower |  | int |
| 64 | getWirelessCapacity |  | int |
| 65 | getWirelessChargePumpEn |  | int |
| 66 | getWirelessCurrentNow |  | int |
| 67 | getWirelessDeviated |  | String |
| 68 | getWirelessOnline |  | int |
| 69 | getWirelessPenPresent |  | int |
| 70 | getWirelessPtmcId |  | int |
| 71 | getWirelessRXEnable |  | int |
| 72 | getWirelessRealType |  | int |
| 73 | getWirelessTXEnable |  | String |
| 74 | getWirelessUserSleepMode |  | int |
| 75 | getWirelessVoltageNow |  | int |
| 76 | healthd_update_ui_soc_decimal |  | String |
| 77 | nightstandby | int | int |
| 78 | notifyScreenStatus | int | int |
| 79 | queryChargeInfo |  | String |
| 80 | setChargeEMMode | String | int |
| 81 | setChargerControl | String | int |
| 82 | setChargerCoolDown | String | int |
| 83 | setChargerCriticalLog | String | int |
| 84 | setChargerCycle | String | int |
| 85 | setChargerFactoryModeTest | String | int |
| 86 | setChargerLog | String | int |
| 87 | setChgStatusToBcc | int | int |
| 88 | setCustomSelectChgMode | int, boolean | int |
| 89 | setFastchgFwUpdate | String | int |
| 90 | setPsyMmiChgEn | String | int |
| 91 | setPsyOtgSwitch | String | int |
| 92 | setReserveSocDebug | String | int |
| 93 | setShipMode | String | int |
| 94 | setSmartChgMode | String | int |
| 95 | setSmartCoolDown | int, int, String | int |
| 96 | setTbattPwrOff | String | int |
| 97 | setUisohDebugInfo | String | int |
| 98 | setUsbPrimalType | String | int |
| 99 | setWirelessChargePumpEn | String | int |
| 100 | setWirelessFtmMode | String | int |
| 101 | setWirelessIconDelay | String | int |
| 102 | setWirelessIdtAdcTest | String | int |
| 103 | setWirelessPenSoc | String | int |
| 104 | setWirelessRXEnable | String | int |
| 105 | setWirelessTXEnable | String | int |
| 106 | setWirelessUserSleepMode | String | int |
| 107 | setWlsThirdPartitionInfo | String | int |
| 108 | testKitFeatureTest | int | testKitFeatureTestResult |
| 109 | testKitGetFeatureList |  | String |
| 110 | testKitGetFeatureName | int | String |
| 111 | testKitGetFeatureNum |  | int |
| 112 | updateUiSohToPartion |  | int |
| 113 | queryWlsPencilInfo |  | String |
| 114 | getChgOlcConfig |  | String |
| 115 | setChgOlcConfig | String | int |
| 116 | setSuperEnduranceStatus | String | int |
| 117 | setSuperEnduranceCount | String | int |
| 118 | setBobStatus | String | int |
| 119 | setPsySlowChgEn | String | int |
| 120 | getCpVbatDeviation |  | int |
| 121 | setBatteryLogPush | String | int |
| 122 | getChargingModeInGsmCall |  | int |
| 123 | setChargingModeInGsmCall | String | int |
| 124 | setChgRusConfig | String | int |
| 125 | getPsyBatterySN |  | String |
| 126 | getBattGaugeInfo |  | String |
| 127 | setChgConfig | int, String, int | int |
| 128 | getChgConfig | int, String, int | String |
| 129 | setUsbEyeDiagram | int, String, boolean | int |
| 130 | getUsbCurrentEyeDiagram | int | String |
| 131 | queryRgcpHboostInfo |  | String |
| 132 | setCV | int, int | String |
| 133 | getDeepSleepClustersSleepWake |  | String |
| 134 | getPowerbankInfo | String, int | String |
| 16777214 | getInterfaceHash |  | String |
| 16777215 | getInterfaceVersion |  | int |

Sysfs/proc nodes behind the old typed setters (from the HAL, **[seen]**):

| ICharger method | node |
|---|---|
| setChargerCoolDown | `/sys/class/power_supply/battery/cool_down`, else `/sys/class/oplus_chg/battery/cool_down` |
| setSmartCoolDown(cool, normal, pkg) | `.../battery/cool_down`, `/sys/class/oplus_chg/battery/normal_cool_down`, `/sys/class/oplus_chg/battery/pkg_name` |
| setPsySlowChgEn | `/sys/class/oplus_chg/battery/slow_chg_en` |
| setPsyMmiChgEn | `.../battery/mmi_charging_enable` (power_supply first, then oplus_chg) |
| setChargerControl | `/dev/oplus_chg` |
| setSmartChgMode | HAL internal state (mutex) and `/sys/class/power_supply/battery/current_now`; format `%d` |
| setCustomSelectChgMode(mode, on) | HAL internal state only (log "smart chg mode selected %d and enable %d by user") |
| setWirelessPenSoc | `/sys/class/oplus_wireless/pencil/rx_soc`, else `/sys/class/oplus_chg/wireless/wlspen_soc` (value is `atoi`) |
| setWirelessTXEnable / RXEnable | `/proc/wireless/enable_tx`, `/proc/wireless/enable_rx` |
| queryWlsPencilInfo | builds a string with keys `ble_pencil_addr` (`.../pencil/ble_mac_addr`), `ping_time`, `tx_status`, `tx_current`, `tx_voltage`, `fm_version` (`fw_version`), `wireless_ic_id` |
| getWirelessPenPresent | `/sys/class/oplus_wireless/pencil/present` |

## B. setChgConfig / getChgConfig

### B.1 Common rules

- Signature: `int setChgConfig(int type, String value, int callname)` and `String getChgConfig(int type, String value, int callname)`. The HAL keeps two maps (`chgFuncMapInit`): type to set handler, type to get handler. An unknown type returns `-1` (set) or `"-1"` (get). **[seen]**
- The third int is a **caller ID** (the HAL calls it `callname`). It is not a mode. The HAL logs it and appends it as `|callname=<n>` to the text it writes to the node (the plc, chg_path, rx_disable, wlspen_info, wlspen_dischg_soc, tx_charge_disable and bs_blind_cfg handlers). In `chg_up_limit` it is the fifth number. Values seen at the callers: 0 (Settings, display ChargeHelper), 1 (system_server polling), 2 (Battery app through `OplusBatteryManager`; also what the Games call becomes), 3 (Games app to the Battery remote service), 7 (Bluetooth), 11 (USB VDM poll). **[seen]**
- Value format: `"<n>++<v1>+<v2>..."` for the charge-limit family (types 5, 13, 14) and `"1+<key>=<val>"` for key=value commands (types 25, 27, 34). The leading number is not the count of fields in every case (`3++1+95` has two fields). It is a group ID. **[inferred]**
- `getChgConfig(31, "<type>", n)` = `CHECK_FLAG_SUPPORT`. The HAL does `sscanf("%d")` on the value and answers `"-1"` if the type has no handler. system_server asks `(31, "30")` once at start to learn if the "Update" JSON interface exists. **[seen]**
- Return value: the limit handlers (5, 14) return 0. Type 25 returns `max(0, bytes written)` (positive on success, 0 on a failed write) [seen]; 32, 27, 38, 39, 41 have the same code shape [inferred]. The framework wrapper (`OplusBatteryServiceFeature`) returns `-1` on a binder failure. **[seen]** The Battery app checks this value for type 25 (see C.3).

### B.2 Table of all types

Callers: **sys** = system_server `OplusBatteryService` / `OplusBatteryServiceFeature` (oplus-services.jar); **Bat** = Battery app `com.oplus.battery` (class names are obfuscated; `t6.g` is its ChargeUtil, which calls `android.os.OplusBatteryManager` by reflection with callname 2); **Games** = OplusGames `business.module.bypasscharge.*`.

| ID | Name | S/G | Value format | Third arg | Caller (class.method) | ColorOS feature | Donor HAL action |
|---|---|---|---|---|---|---|---|
| 0 | GET_UI_CHG_ICON_TYPE | G | `""`, int string | 1 | sys `OplusBatteryService.getDataFromHalByOldInterface` | charge icon type in the battery intent | IntfInfo `uiIconType` |
| 1 | GET_UI_POWER_VALUE | G | `""`, int | 1 | sys same | shown charge wattage | `/sys/class/oplus_chg/common/ui_power` |
| 2 | GET_DEVICE_POWER_VALUE | G | `""`, int | 0 (Settings), 2 (Bat `t6.g.u`) | Settings `OplusDeviceInfoUtils.isWiredChargVisible`, `DeviceChargeInfoItemPreference`, About phone | "rated charge power" in About | `/sys/class/oplus_chg/common/device_power` |
| 3 | GET_ADAPTER_POWER_VALUE | G | `""` | - | none found | - | `.../common/adapter_power` |
| 4 | GET_CPA_POWER_VALUE | G | `""`, int | 1 | sys same; `PulseLight$Policy.isMatchWattage` | charge light, wattage UI | `.../common/cpa_power` |
| 5 | SET_CHG_UP_LIMIT_VALUE | S | `4++<stop>+<L1>+<mode>+<L2>` (see C.1) | 2 | Bat `t6.n.T2` (called by the `x8.k` SmartChargeProtectionController) | custom charge limit, smart charge | parse, keep in HAL state, write `<a>,<b>,<c>,<d>,<callname>` to `/sys/class/oplus_chg/common/chg_up_limit` (also stored in the smart-charge partition) |
| 6 | IS_SUPPORT_SINGLE_HYPER_SPEED | G | `""`, int | 1 | sys same | "super-fast single speed" gate | IntfInfo `isSupportSpeedCharge` |
| 7 | GET_BATT_EXPANSION_STATE | G | - | - | none found | - | no handler in the get map |
| 8 | IS_SUPPORT_ECO_DESIGN | G | `""` | 2 | Bat `t6.g.G` | battery eco design UI | `BatteryEcoDesign` (HAL logic) |
| 9 | GET_BATT_MANU_DATE | G | `""`, date text | 2 | Bat `t6.g.d` | battery info | `.../battery/battery_manu_date` |
| 10 | GET_BATT_FIRST_USAGE_DATE | G | `""` | 2 | Bat `t6.g.c` | battery health page | `.../battery/battery_first_usage_date` |
| 11 | SET_BATT_FIRST_USAGE_DATE | S | date text | 2 | Bat `t6.g.H` | battery health page | write first-use date (compares with manu date) |
| 12 | CLEAR_BATT_ECO_DATA | S | - | - | EngineerMode (per the shim's comment; not scanned here) | factory reset of eco data | HAL `clearBattDataAfter911` |
| 13 | SET_RECHG_SOC_EN | S | `3++1+95` (on) or `3++0+100` (off) | 2 | Bat `t6.g.P(int)` | "recharge threshold" (battery-health protection) | `setRechgSocEnableThreshold`: writes the level to `/sys/class/oplus_chg/battery/rechg_soc` |
| 14 | SET_CHG_UP_LIMIT_STATE | S | `2++<on>+<level>` | 2 | Bat `t6.n.M3`, `x8.k$k.handleMessage`, `x8.k.c0/g0` | charge limit switch ("regular charge protection") | like type 5; also reads `.../battery/chip_soc` or `capacity`; same `chg_up_limit` node |
| 15 | GET_BATTERY_STATUS_PM_VPH | G | `""` | - | none found | factory | reads the PMIC VPH in device tree/proc |
| 16 | GET_BATTERY_STATUS_PM_VBAT | G | `""` | - | none found | factory | PMIC VBAT |
| 17 | GET_DEEP_DISCHG_COUNTS_VALUE | G | `""` | - | none found | battery health | `.../common/deep_dischg_counts` |
| 18 / 19 | GET / SET_ANTI_EXPANSION_INFO | G/S | HAL text | - | none found | swelling protection | HAL thread; it can itself call set-limit with `4++1+80+1+80` |
| 20 | GET_BATT_UI_CYCLE_COUNT | G | `""` | 2 | Bat `t6.g.b` | cycle count UI | `.../battery/battery_ui_cc` |
| 21 | GET_BATTERY_TYPE | G | `""`; text `graphite` / `silicon` | 0 | Settings `DeviceInfoUtils.getBatteryType`; display `ChargeHelper.isSiliconBattery` | battery type | `.../battery/battery_type` |
| 22 | WIRELESS_PENCIL_QCALI | S+G | calibration text | - | none found | pen charge Q calibration | `/sys/class/oplus_wireless/pencil/q_cali` |
| 23 | GET_BATTERY_GAUGE_TYPE | G | `""` | - | none found | - | `.../battery/gauge_type` |
| 24 | GET_CHG_BYPASS_STATUS | G | `""`; returns a decimal string | 1 (sys), 3 (Games) | sys `getDataFromHalByOldInterface`; Games `business.module.bypasscharge.b.g` | bypass support and status (C.3) | IntfInfo `bypassChgStatus` = `/sys/class/oplus_chg/common/plc` |
| 25 | SET_CHG_BYPASS | S | `1+switch=1` / `1+switch=0` | 2 (Bat), 3 (Games remote) | Bat `a9.a.C` (BypassChargeController), `EapConfigReceiver.onReceive`; Games `b.l` -> `b.m` | bypass charging | write the string plus `|callname=<n>` to `/sys/class/oplus_chg/common/plc` |
| 26 | GET_RX_DISABLE_STATUS | G | `""` | - | none found | wireless RX | `/sys/class/oplus_chg/wireless/rx_disable` |
| 27 | SET_RX_DISABLE | S | `1+disable=<0|1>` | 2 | Bat `rb.t.i` ("Thermal.WirelessChargeControl", setting `oplus_thermal_wireless_charge_hightemp`) | stop wireless charge at high temperature | `/sys/class/oplus_chg/wireless/rx_disable` |
| 28 | GET_BATTERY_SEC_IC_TEST_STATUS | G | `""` | - | none found | factory | `.../battery/sec_ic_test` |
| 29 | GET_CHARGER_INFO | G | `""` | - | none found | - | JSON of all IntfInfo |
| 30 | GET_CHARGER_INFO_UPDATE | G | `"Update"`; returns JSON | 1 | sys `getDataFromHalByUpdate` / `handleUpdataInfo` | battery-changed extras | JSON with changed keys, see C.3 |
| 31 | CHECK_FLAG_SUPPORT | G | `"<type>"` | 0 | sys `OplusBatteryService.<init>` (`"30"`) | capability probe | `-1` if the type has no handler |
| 32 | SET_CHG_PATH | S | text | - | none found in scanned apps | charge path select (factory / wireless) | `/sys/class/oplus_chg/battery/chg_path` (+`|callname`) |
| 33 | GET_BATTERY_GAUGE_CAR_C | G | `""` | - | none found | gauge | `.../battery/gauge_car_c` |
| 34 | SET_BT_INFO | S | `1+btconnect=<n>`, `btincar=`, `carlink=`, `bttype=`, `btname=<name>` (key=value list; separator not extracted) | 7 | `oplus_bluetooth_common_ext.jar` `OplusBluetoothScenarioMonitor.setChgConfig` | car/BT scene hint for charging | `/sys/class/oplus_chg/wireless/bt_info` |
| 35 | GET_BDD_LEAK_CURR | G | `""` | - | none found | factory | `.../battery/bdd_voltdiff_trend` family |
| 36 / 37 | SET / GET_REVERSE_CHG_INFO | S/G | text | - | none found | reverse charging | `/sys/class/oplus_chg/common/reverse_chg_info` |
| 38 | SET_WLSPEN_INFO | S | text | - | none found (caller is outside the scanned set) | pen charge info | `/sys/class/oplus_chg/wireless/wlspen_info` |
| 39 | SET_WLSPEN_DISCHG_SOC | S | text / int | - | none found | pen discharge SOC | `/sys/class/oplus_chg/wireless/wlspen_dischg_soc` |
| 40 | GET_VDM_INFO | G | `""` | 11 | display/usb `OplusUsbDeviceFeature$OplusUsbHandler.onVdmPollStep` | USB PD VDM poll | `/sys/class/oplus_chg/usb/vdm_info` |
| 41 | SET_PENCIL_TX_CHARGE_DISABLE | S | text (a number) | - | none found | stop pen charging | `/sys/class/oplus_wireless/pencil/tx_charge_disable` |
| 42 | SET_BS_BLIND_CFG | S | text | 2 | Bat `l9.a.a` | battery-state blind config | `/sys/class/oplus_chg/battery/bs_blind_cfg` |
| 43 | GET_BS_BLIND_CFG | G | `""`; JSON with `support` | 2 | Bat `powermanager.powerauto.d.F` | power-auto feature | reads `bs_blind_cfg`, JSON |
| 44 | GET_POWERBANK_STATUS | G | `""` | - | none found | powerbank | IntfInfo `powerbankStatus` |
| 45 | GET_WLS_POWERBANK_INFO | G | `""` | 2 | Bat `t6.g.A` | wireless powerbank UI (flag `oplus.software.chg.wls_powerbank_info_support`) | IntfInfo, `getWlsPowerbankInfo` |
| 46 | GET_WLS_POWERBANK_STATUS | G | `""` | - | none found | - | IntfInfo `wlsPowerbankStatus` |
| 47 | GET_POWERBANK_INFO | G | `""` | 2 | Bat `t6.g.s` | wired powerbank UI (flag `oplus.software.chg.wired_powerbank_info_support`) | `getPowerbankInfoCFG` |

Notes on the table:
- "none found" means no caller in the scanned code. Some callers sit in apps I did not dump (EngineerMode, factory tools, the pen stack). Pen types 22, 38, 39, 41 and 32 are the open ones.
- `ICharger.CHG_FUNC_FLAG_MAX = 35` in the V12 stub is stale. The HAL handles IDs up to 47.
- The Battery app is the only normal sender of types 5, 13, 14, 25. It bridges for other apps: `RemoteClientService` / `RemoteUiClientService` in the Battery app implement `IRemoteClientInterface` (`setChgConfig(int,String,int)`, `getChgConfig`). The remote service ignores the third int and calls `t6.g.K` (callname 2).

## C. Features

### C.1 Charge limit and smart charging (types 5 and 14, 13)

- Who: Battery app. Settings keys `regular_charge_protection_switch_state` (switch) and `regular_charge_protection_open_power_level` (the chosen level, default read as `-1` then fixed by `t6.n.F0`). Class `x8.k` is the `SmartChargeProtectionController`; it handles "stop charging", "release" and the alarm for smart charging.
- Type 14, confirmed: `"2++" + <state> + "+" + <level>` from `t6.n.M3(context, state)`. State is the switch value (0/1); level is the setting above. **[seen]**
- Type 5, confirmed: `"4++" + <stop> + "+" + <L> + "+" + <mode> + "+" + <L>`, from `t6.n.T2(mode, stop, context)`, where `L = (mode == 1) ? user level : 80`. The first number after `4++` is the **stop** flag (`handleStopCharging(isStopCharging)`), the third number is the mode. This matches BUGS row 50 (4m). **[seen]**
- The HAL parses the four numbers and writes `a,b,c,d,callname` to `/sys/class/oplus_chg/common/chg_up_limit`. The kernel (oplus_chg) does the real limit. The HAL also keeps the values in a partition (`/dev/block/by-name/oplusreserve1`) for the next boot, and the anti-expansion thread can set `4++1+80+1+80` by itself. **[seen]**
- Type 13: `3++1+95` (on) and `3++0+100` (off) come from `t6.g.P(int)`. The HAL `setRechgSocEnableThreshold` writes the recharge SOC to `.../battery/rechg_soc`. This is the "recharge at 95%" rule. **[seen]**
- Smart charging (`SmartChargeController`, `customize_charge_*` settings): it uses setChgConfig 5/14 as above. It also calls `setSmartChgMode("0"/"1")` through `t6.g.W` ("life mode charge") and `setCustomSelectChgMode(mode, on)` through `aa.a` (`aa.a$f.handleMessage`: mode 3 = smart rapid charge, 4 = single speed). **[seen]**
- Slow charge in smart charging: `x8.k.h0` calls `t6.g.O(ctx, status, E, F)` -> `OplusBatteryManager.setPsySlowChgEnable(a,b,c)` -> in the framework: string `"a,b,c"` -> `setPsySlowChgEn` -> `/sys/class/oplus_chg/battery/slow_chg_en`. Defaults in `t6.g`: `E` = 4 (default of the first static), `F` = 33. Meaning of the three numbers: **[unknown]**.

### C.2 Smart charging flags

See D. The Battery app asks `com.oplus.battery.smart.charge.mode`, `com.oplus.battery.speed_charge_mode`, `com.oplus.battery.customize_charge_mode`, `com.oplus.battery.single_charge_boost`, `com.oplus.battery.remove.rm_smartcharge_80w`, `com.oplus.battery.unsupport_smartcharge_80w` and `os.charge.settings.longchargeprotection.ai`.

### C.3 Bypass charging (types 24, 25, 32)

**Who sends type 25**
1. Battery app `a9.a.C(value, reason)` (class `BypassChargeController`, tag "BypassChargeController"). It calls `t6.g.K(25, value)` with the string `"1+switch=1"` or `"1+switch=0"`.
2. Battery app `EapConfigReceiver`: on `oplus.intent.action.BOOT_COMPLETED`, `OPLUS_OTA_UPDATE_SUCCESSED` and `OPLUS_RECOVER_UPDATE_SUCCESSED` it sends `"1+switch=0"` (log "SET_BYPASS_OFF"). So bypass is always off after a boot.
3. Games app, classic path: `business.module.bypasscharge.b.l(boolean)` -> `b.m(25, "1+switch=1"/"1+switch=0")` -> `IRemoteClientInterface.setChgConfig(25, value, 3)`. The Games app binds `com.oplus.battery` with action `com.oplus.battery.RemoteClientService`.

**Conditions: Battery app BypassChargeController (all-scene path)**
- Created in the Battery app `OplusBatteryService` only if `com.oplus.fullscene_plc_charge.support` is true (read in `m6.a` from `AppFeatureProviderUtils`) and the user is the main user (user 0). **[seen]**
- State is in `Settings.System`: `bypass_charge_state` (0/1, the switch; the Games app writes it too) and `bypass_charge_value` (battery level threshold, default 20). It registers content observers on both keys and receivers for screen on/off, shutdown, user switch, `BATTERY_CHANGED`, `ACTION_ADDITIONAL_BATTERY_CHANGED` and `oplus.intent.action.bypass_charge_close` (the "close" button in the notification). **[seen]**
- It sends `"1+switch=1"` only when ALL hold: switch = 1, plugged (plug type 1 AC or 2 USB), battery level >= `bypass_charge_value`, main user. Reasons in the log: "user change", "batterylevel big", "screen on", "timeout". **[seen]**
- It sends `"1+switch=0"` when the level drops below the threshold ("batterylevel small"), on unplug ("plug out"), on shutdown, on notification close, and on boot or OTA (item 2 above). When the screen goes off it sends `"1+switch=0"` (reason "screen off", when the Battery app knows bypass is on) and `"1+switch=1"` again at screen on (reason "screen on") if the other conditions hold. **[seen]**
- Watchdog: after `setChgConfig(25, ...)` returns a **non-zero** value, switch=1 arms a delayed message (180000 ms = 3 minutes) that repeats the evaluation, and switch=0 removes it. If the call returns 0 the Battery app arms nothing. (The HAL returns the number of bytes written, so non-zero means success.) **[seen]** A HAL status of `5` in the `bypass_charge_status` extra also triggers a re-evaluation and a repeat of switch=1 or 0 (reason "timeout"). So the kernel `plc` mode seems to time out and needs a refresh. **[inferred]**
- On enable it shows a notification (`bypass_charge_open_channel_id`, close action `oplus.intent.action.bypass_charge_close`, deep link to Settings > Battery `bypass_charge_switch_preference`). **[seen]**

**Conditions: Games app**
- All-scene (`AllSceneBypassChargeFeature`, active when the app feature `com.oplus.fullscene_plc_charge.support` is true and the Games control library version is in range): in a game, when USB power is connected and the user turned on "auto open" or the switch, it writes `Settings.System bypass_charge_state=1`. It force-closes (writes 0) if no power is connected at game start, restores the pre-game state at game stop, and has a "gun pad" (cooling back-clip) case. It does **not** call `getChgConfig(24)` for the support check. **[seen]**
- Classic (`BypassChargeFeature`, active only if all-scene is not): enabled when app feature `com.oplus.plc_charge.support` is true (or the brand is realme) and `getChgConfig(24, "", 3)` is an integer `>= 0`; value `0` -> not supported, `> 0` -> supported. Level choices in the UI picker: 20, 40, 60, 80 (`bypass_charge_value`). It enables bypass at game start if battery >= level and power is connected, disables at game stop. **[seen]**
- Temperature: I found no temperature condition in the apps. Any thermal protection is in the kernel `plc` driver. **[unknown]**

**Type 24 (status)**
- system_server asks `getChgConfig(24, "", 1)` at init and receives the key `bypassChgStatus` in the type-30 "Update" JSON. It does `Integer.parseInt` and puts the result in the intent `ACTION_ADDITIONAL_BATTERY_CHANGED` as int extra `bypass_charge_status`. A non-numeric answer breaks the parse. **[seen]**
- Meaning of values: `5` has a special effect in the Battery app (see watchdog). `0` = no bypass hardware in the Games classic check. Other values: **[unknown]**.

**Type 32 SET_CHG_PATH**: handled by the HAL (`/sys/class/oplus_chg/battery/chg_path`). No app in the scanned set sends it. **[unknown]** who uses it (likely factory or the wireless path logic).

**HAL**: `setChgBypass` and `getChgBypassStatus` only pass text to and from the kernel node `plc`. The `plc_charge` kernel device exists in the donor sepolicy as `/sys/devices/platform/soc/soc:oplus,plc_charge/oplus_mms/plc/...`. The HAL also has `setPlcBuckEnable` (same node), called by `setChgBypass`.

### C.4 Slow charging

- `setPsySlowChgEn(String)` -> `/sys/class/oplus_chg/battery/slow_chg_en`. The string is `"<a>,<b>,<c>"` built by `OplusBatteryServiceFeature.setPsySlowChgEnable(int,int,int)`. Sender: Battery `x8.k.h0` ("handleSlowCharge", tag SmartChargeProtectionController) with `status`, `t6.g.E`, `t6.g.F`. Feature: smart charging "slow charge" stage. **[seen]** Meaning of the numbers: **[unknown]**.

### C.5 Charger cool-down

- `setSmartCoolDown(int cool, int normal, String pkg)`: sender is the Battery app thermal engine `ThermalControlUtils.U1(cool, normal, pkg)` through `OplusBatteryManager`. HAL writes the node `.../battery/cool_down`, `.../battery/normal_cool_down` and `.../battery/pkg_name` (the foreground package that caused the cool-down). **[seen]**
- `setChargerCoolDown(String)`: system_server `OplusGuardElfFeature` (guard elf thermal control) with a level string. Node `.../battery/cool_down`. `getChargerCoolDown()` reads it back. **[seen]**
- Feature gates: `com.oplus.cosa.support.game_custom_temp_control`, `com.oplus.battery.thermal_*` (D).

### C.6 Pen / stylus charging

- All pen nodes are under `/sys/class/oplus_wireless/pencil/` (`present`, `rx_soc`, `tx_charge_disable`, `q_cali`, `tx_status`, `tx_current`, `tx_voltage`, `fw_version`, `ping_time`, `ble_mac_addr`, `wireless_ic_id`) and `/sys/class/oplus_chg/wireless/` (`wlspen_info`, `wlspen_soc`, `wlspen_dischg_soc`). The HAL runs `wlschgd` for the pen wireless IC (`/dev/wls_dev`). **[seen]**
- Type 41 `SET_PENCIL_TX_CHARGE_DISABLE`: the HAL writes the value plus `|callname=<n>` to `tx_charge_disable` (log "setPencilTxChargeDisable formattedData [%s]"). Types 38 and 39 write `wlspen_info` and `wlspen_dischg_soc` the same way. `setWirelessPenSoc(String)` writes `rx_soc` (an integer). `queryWlsPencilInfo()` returns a text with the keys listed in A.
- The senders are **not** in the code I scanned (no Battery, system_server, Settings or SystemUI caller). Rules such as "stop pen charge at X %" or "pen discharge SOC" are therefore **[unknown]**. The pen model feature list is `my_stock/etc/pencil_feature_config.xml` (UI features, not charge rules).
- On pipa the pen is the Xiaomi pen with its own driver, so these OPPO nodes have no kernel counterpart.

## D. Flags that show or hide the toggles

How the apps read them: `AppFeatureProviderUtils` (content provider of "app features", file `my_product/etc/extension/com.oplus.app-features.xml`) and `OplusFeatureConfigManager.hasFeature` (file `com.oplus.oplus-feature.xml`, same folder). They are XML feature files, not props.

| Flag | Where it is read | Effect | Donor value / source | Pipa action |
|---|---|---|---|---|
| `com.oplus.fullscene_plc_charge.support` (app feature, `boolean:true`) | Battery `m6.a` (creates BypassChargeController); Games `OplusFeatureHelper.A()` | All-scene bypass UI in Game Assistant and the Battery controller | **true** in `my_product/etc/extension/com.oplus.app-features.xml` | already true in the donor file; check that the pipa `my_product` has the line |
| `com.oplus.plc_charge.support` (app feature) | Games `OplusFeatureHelper.K()` | classic bypass path | not in the donor files (false) | not needed if all-scene is used |
| `com.android.settings.device_rm` | Battery `m6.b`, Games brand checks | realme build marker | not set | leave unset |
| `os.charge.settings.longchargeprotection.ai` (app feature) | Settings / Battery | AI long-charge protection entry | set in `feature_com.android.battery.xml` (my_product/etc/extension) | keep if you want smart-charging text |
| `oplus.hardware.wired_reverse_charging` (oplus-feature) | Battery, Settings | wired reverse charge entry | set in `com.oplus.oplus-feature.xml` | remove or leave: pipa has no reverse charge |
| `oplus.power.onwirelesscharger.support`, `oplus.power.wirelesschgwhenwired.support`, `com.oplus.battery.wireless.charging.notificate`, `com.oplus.battery.wireless_charge_otg_conflict` | Battery | wireless charging pages and notification | not in donor files (false) | none |
| `oplus.software.chg.wired_powerbank_info_support`, `oplus.software.chg.wls_powerbank_info_support` | Battery | powerbank info rows (types 44 to 47) | not set | none |
| `com.oplus.battery.smart.charge.mode`, `com.oplus.battery.speed_charge_mode`, `com.oplus.battery.customize_charge_mode`, `com.oplus.battery.single_charge_boost`, `com.oplus.battery.remove.rm_smartcharge_80w`, `com.oplus.battery.unsupport_smartcharge_80w` | Battery `m6.a` | smart charge, speed charge and custom charge pages | **not defined in the donor XML**. The defaults and the way the Battery app gets them (its own assets or a missing file) were not found | check on the device with the port: BUGS row 50 says the charge-limit UI already works, so the needed page flag is already on **[inferred]** |
| `com.oplus.battery.thermal_diff`, `thermal_tolerance`, `thermal_distinguish_env_temp`, `thermal_temp_src_motherboard`, `special_hightemp`, `special_aging`, `cabc_level_dynamic_enable` | Battery thermal control | thermal engine variants | not in donor files | none |
| `com.oplus.cosa.support.game_custom_temp_control` | Battery, COSA | game temperature control | not set | none |
| `oplus.hardware.type.tablet` | Battery | tablet layout | set (oplus-feature) | already needed by the port |
| `ro.vendor.config.oplus.disable_long_battery_ui` (prop) | Battery | hide the long battery UI | read as a prop | none |
| `persist.sys.ic_status` (prop) | system_server `OplusBatteryService` | battery IC status string | read as a prop | none |
| `vendor.oplus.hardware.charger` (+ `-V1`) in `system_ext/etc/permissions/vendor-oplus-hardware-charger.xml` | framework class loading | makes `vendor.oplus.hardware.charger-V1-java.jar` visible | present | the V12 stub must also be on the boot or system_server class path |
| `Settings.System bypass_charge_state` (0/1), `bypass_charge_value` (default 20) | Battery controller, Games, Battery `BypassChargeTile` | switch and level threshold | not a flag: user state | none |
| `Settings.System regular_charge_protection_switch_state`, `regular_charge_protection_open_power_level` | Battery | charge limit state and level | user state | none |

Summary for pipa: the only flag that gates bypass in the donor build is `com.oplus.fullscene_plc_charge.support` (app-feature XML). No prop is involved.

## Open questions

1. Value meaning of `plc` (type 24): 0, 1, 2, 5 and others. The kernel driver is not in the donor tree. Look at the oplus_chg kernel source or the `oplus_mms/plc` driver names if available.
2. Is there an access check on the binder path `OplusBatteryManager` -> system_server (`BatteryServiceExtImpl$GuardElfThermalControl`)? I did not read the caller permission code.
3. Who sends the pen types 22, 32, 38, 39, 41? The caller is outside the scanned set. Candidates: the pen service in another APK, `wlschgd`, factory tools.
4. How the Battery app decides the smart-charge page flags (D). They are not in the XML of the donor.
5. The three numbers of the slow-charge string and the exact mapping of `mode` in type 5 (values 0/1/2).
6. Whether the C.06 donor behaves the same. I read C.07 files.
7. What happens at the HAL when `plc` is missing (the answer for type 24: `"-1"` or empty). Not decoded.

## Facts for bypass plan (Step 4)

**Requests (set)**
- Type 25: value exactly `1+switch=1` (on) or `1+switch=0` (off). No other keys found. Third arg: 2 from the Battery app, 3 from a Games call (the remote service rewrites it to 2). **Return: a positive int (the HAL returns the bytes written) for success.** The Battery app arms its 3-minute watchdog only for a non-zero return. The Games classic path only logs it ("setBypassChargingSwitch is ..."). Note: the current pipa shim returns 0 for success on setChgConfig; for type 25 return a positive number (for example the length of the string).
- The HAL writes `<value>|callname=<n>` to `/sys/class/oplus_chg/common/plc`. A shim must accept the string up to the first `|` and parse `switch=<0|1>`.
- The Battery app sends `1+switch=0` after every boot, OTA and recovery (`EapConfigReceiver`) and on unplug.
- Bypass is re-sent (switch=1) when the HAL reports status 5, and the controller re-evaluates every 3 minutes (180000 ms) while the switch is on.

**Status (get)**
- Type 24, value `""`, third arg 1 (system_server) or 3 (Games classic). The answer must be a plain decimal integer in a string, for example `"0"`. Anything else gives a `NumberFormatException` in system_server (`Integer.parseInt`) and a null in the Games app (it then treats the result as "not supported", `-1`).
- Games classic support check: answer `>= 1` = supported, `0` = not supported. All-scene mode does not call it.
- system_server also reads key `bypassChgStatus` from the type-30 "Update" JSON (`getChgConfig(30, "Update", 1)`). Without a type-30 answer system_server uses the old interface (types 0, 1, 4, 6, 24 with value `""`, third arg 1). To reply to the probe `getChgConfig(31, "30", 0)`, return a non-negative string if the shim supports type 30, or `"-1"` if not.
- Value 5 in `bypass_charge_status` = "re-assert bypass" for the Battery app. Do not return 5 unless a re-assert is wanted.

**Conditions the apps check before they send 25**
- Plugged (plug type 1 or 2), battery level >= `Settings.System bypass_charge_value` (default 20), main user, switch `bypass_charge_state` = 1. In games: game foreground or game mode on. Screen off cancels (a delayed message).
- No temperature check in the apps.

**Sysfs nodes the donor HAL touches for bypass**
- `/sys/class/oplus_chg/common/plc` (set and get, only node). `/sys/class/oplus_chg/battery/chg_path` for type 32 (no known sender). Kernel side in the donor sepolicy: `/sys/devices/platform/soc/soc:oplus,plc_charge/oplus_mms/plc/`.
- On pipa the shim must map `switch=1` to a real action. The shim idea of the port is `battery_charging_enabled` (stop charge) or an input-current limit. I did not check what pipa's smb5 supports.

**Callbacks the app waits for**
- No direct callback. The Battery app reads the effect from `ACTION_ADDITIONAL_BATTERY_CHANGED` (extra `bypass_charge_status`) which system_server builds from type 24 / type 30. The Games app watches `Settings.System bypass_charge_state` and `ACTION_POWER_CONNECTED/DISCONNECTED`. The UI does not wait for an ack.

**Gate to set (pipa)**
- App feature `com.oplus.fullscene_plc_charge.support` = true (already in the donor file). The Battery app creates `BypassChargeController` only with this flag and for user 0.

## E. Bypass charging on pipa: plan for step 4p (plan only, no code)

### E.1 What the HAL must do

Bypass charging means: the charger powers the system, and the battery does not charge. The battery level stays the
same while the user plays. Less heat comes from the battery. The donor HAL only passes `1+switch=<0|1>` to the
kernel node `plc`. The OPPO kernel driver (`oplus,plc_charge`) does the real work. pipa has no such driver, so the
port must do it in user space.

The Battery app controls bypass, not the Games app (all-scene path, flag `com.oplus.fullscene_plc_charge.support`):

- The Games app only writes `Settings.System bypass_charge_state` (1 in a game with power, the old state at game stop).
- The Battery app `BypassChargeController` sends `setChgConfig(25, "1+switch=1", 2)` when all of these are true:
  the switch is 1, the tablet is plugged in (AC or USB), the battery level >= `bypass_charge_value` (default 20),
  the user is 0, and the **screen is on**.
- It sends `"1+switch=0"` at screen off, at unplug, when the level falls below the threshold, at shutdown, when the
  user closes the notification, and after each boot or OTA.
- Watchdog (checked in the Battery app, method `C`): only when `setChgConfig(25, ...)` returns **non-zero**, `switch=1`
  arms a 180 s message. The message runs `onByPassWatchDog` and sends `switch=1` again. So while bypass is on, a
  fresh `switch=1` comes every 3 minutes. `switch=0` removes the message.
- The apps have no temperature condition. The donor kernel driver probably has one.

### E.2 Map to the pipa charger (Qualcomm smb5)

| Node (`/sys/class/power_supply/battery/`) | Effect | Use for bypass |
|---|---|---|
| `battery_charging_enabled` = 0 | Stops the battery charge current. The input path stays on, so the charger powers the system. | **Yes.** This is bypass. Step 3z/4m charge hold already uses it, and it is tested on the tablet. |
| `input_suspend` = 1 | Cuts the input. The battery powers the system and discharges. | **No.** This is the opposite of bypass. |

Note: when the load is higher than the input current limit, the battery still gives the difference. That is normal
and also true on OPPO devices.

### E.3 What 4p adds

1. **Charger shim** (`maintainer/chargershim/patch_record.py`):
   - The shim already records every `setChgConfig` type as `chg_cfg<type>`. Thus `chg_cfg25` = `1+switch=<0|1>` is
     already written. No new record is necessary.
   - Type 25 must return a positive value on success (for example 1, or the length of the string, as the donor HAL
     does). Now the shim returns 0, so the Battery app never arms its watchdog. Keep -1 for a failed write.
   - `getChgConfig(24, "", n)` must return a plain decimal string. Proposal: `"1"` when the last `chg_cfg25` is
     `switch=1`, else `"0"`. Never return `"5"` (it makes the Battery app send the request again). system_server runs
     `Integer.parseInt` on it, so an empty or text answer gives an exception.
   - `getChgConfig(31, "<type>", n)` (capability probe): return `"1"` for 24 and 25.
   - First check what the current shim returns for types 24 and 31. The shim is binary only (BLOBS.md).
   - `bootCheck`: also delete a `chg_cfg25` older than this boot, the same as `chg_cfg5`.
2. **`port-rom/pipa_port/service.sh`**, function `chg_hold`:
   - Read `$STATE/chg_cfg25`. Bypass is active if the value starts with `1+switch=1` **and** the file is newer than
     about 10 minutes (the watchdog refreshes it every 3 minutes). An old file is a dead app: ignore it. This is the
     timeout that the OPPO kernel has.
   - Stop charging (`want=0`) when bypass is active. Keep the hold logic of 3z/4m for the limits. Log the reason
     (`bypass` or `limit`).
   - Safety floor: when the level is below 15 %, charge, also in bypass.
   - When no input is online (`/sys/class/power_supply/usb/online` = 0), write 1 to `battery_charging_enabled`, so the
     next plug-in charges. Check the node name on the tablet.
   - Run `chg_hold` every 5 s while the input is online. Now it runs every 30 s, which is slow for screen on and off.
     Keep 30 s without input.
3. **New step** `maintainer/port/steps/69-4p-bypass-charge.sh`: copies the new `service.sh` and `chargershim.jar`,
   `need_grep` an anchor in each, `set_layer 4p`. Add the name and md5 to `maintainer/flash_super.sh`. Update BUGS.md
   row 50, ARCHITECTURE.md (step table) and KNOWN-ISSUES.md.
4. **Feature flag:** `com.oplus.fullscene_plc_charge.support` (and `com.oplus.plc_charge.support`) are true in the
   C.07 `my_product/etc/extension/com.oplus.app-features.xml`. Check the C.06 image of the build:
   `dump.erofs --cat --path=/etc/extension/com.oplus.app-features.xml <my_product.img> | grep plc_charge`.
   If the flag is there, 4p needs no flag change. The switch shows in the Games app and in Settings > Battery
   (`bypass_charge_switch_preference`).

### E.4 Device test (after a build with 4p)

1. Plug in the charger. Battery level > 20 %. Turn on the bypass switch in the Games app and start a game.
2. `logcat -s BypassChargeController` shows `setBypassToAidl:value=1+switch=1`. `/data/misc/pipa_port/chg_cfg25`
   shows `1+switch=1`. The pipa_port log shows the bypass stop.
3. `battery_charging_enabled` = 0. `current_now` of the battery is near 0. The level stays the same for 10 minutes.
4. Screen off: `switch=0` comes, and charging starts again within 5 s. Screen on: bypass comes back.
5. Unplug, then plug in again: the battery charges. Reboot: no hold from the last boot.
6. Wait more than 3 minutes in a game: a new `switch=1` comes (watchdog). This shows that the non-zero return works.
