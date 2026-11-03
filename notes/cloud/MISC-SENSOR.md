# SPEC-MISC-SENSOR: shims for `vendor.oplus.hardware.misc` and `vendor.oplus.hardware.oplusSensor`

Static analysis only. No device, no network. Donor tree `/home/user/donor/fs` (C.07 per the older notes; the port docs say C.06 [unknown: diff]).
Marks: [seen] read in files. [inferred] follows from code or names. [unknown] needs the device.
Model for the shims: `maintainer/touchshim/TouchService.java` and its README. Same method: Java binder service, own wire code, donor interface hash, system-stability binder, SELinux label `oplus_absent_service`.
Rule for both shims: the shim never calls a sensor HAL, never enables a sensor, and never writes a node that is not on a whitelist. The whitelist is EMPTY in phase 1.

## 0. Summary

- misc: 5 methods, codes 1..5, descriptor `vendor.oplus.hardware.misc.IOplusMisc`, version 1, hash `a899a863d8a7e0b5ed35ced2275f2ba68aaad329`. Instance `vendor.oplus.hardware.misc.IOplusMisc/default`.
- The donor misc service has a table of 128 nodes (flag -> /proc, /sys or /dev path). Callers pass `(deviceId=0, nodeFlag)`. Only one flag has a pipa use: 83 (`/proc/devinfo/lcd`, panel make and version, read by ColorModeConfig).
- `isMiscNodeSupport` is true for the caller only when the result is `> 0` (`if-lez` in `ColorMiscNodeManagerService`). Donor answer: `1` if the path exists (`access(F_OK)`), else `-1`. The shim must answer `1` only for flags it can serve.
- oplusSensor: 9 methods, codes 1..9, descriptor `vendor.oplus.hardware.oplusSensor.ISensorFeature`, version 1, hash `11597a0080b32caa5e6b8494d84965bb46d77eb6`. Instance `.../ISensorFeature/default`.
- DANGER (sensor code 9): the donor `setPhoneMode` writes `c` to `/proc/sysrq-trigger` (kernel crash) and a line to `/dev/kmsg` when both arguments are 1. The shim must answer `0` and do nothing. [seen strings, inferred trigger condition]
- DANGER (misc code 3/4 with flags 290, 291, 288, 289, 282..287): FPGA and reserve-partition (`/dev/block/by-name/oplusreserve1`) paths. The shim must not touch them.
- Phase 1 for both shims: read-only, constant answers, plus one real read (misc flag 83 and sensor node `lcd`). All writes return "unsupported".
- Native clients use non-blocking lookups for misc (`AServiceManager_getService`, `checkService`). Java clients use `ServiceManager.getService` or `checkService`. A missing misc service does not hang the system. [seen]
- The oplusSensor wait is a different case (blocking `waitForService`). Step 4q already removes the VINTF entry. See the older note `notes/cloud/OPLUSSENSOR.md` on branch `cloud/vintf-4q`.

---

# A. `vendor.oplus.hardware.misc.IOplusMisc`

## A.1 Donor files

| Item | Value |
|---|---|
| Binary | `odm/bin/hw/vendor-oplus-hardware-misc-V1-service` (120 KB, arm64, symbols in `.gnu_debugdata`) |
| rc | `odm/etc/init/vendor-oplus-hardware-misc-V1-service.rc`: `service vendor.misc-aidl-1`, class hal, user system, group system readproc, capabilities SYS_PTRACE, `interface aidl vendor.oplus.hardware.misc.IOplusMisc/default`. Also a long `on boot` list of `chown system system`/`chmod` for the nodes in A.4 (pogopin, fan, ex_gpio, haptics, aw22xxx/aw210xx leds), and `chmod 0666 /mnt/vendor/persist/data/ec2_aging_data.txt` |
| NEEDED | `vendor.oplus.hardware.misc-V1-ndk.so`, libbase, libcutils, liblog, libbinder_ndk, libutils, libhardware, libhidlbase, `android.frameworks.stats-V1-ndk.so`, libc++, libc, libm, libdl |
| Interface libs | `odm/lib(64)/vendor.oplus.hardware.misc-V1-ndk.so`, `system_ext/lib(64)/vendor.oplus.hardware.misc-V1-ndk.so`; Java: `system_ext/framework/vendor.oplus.hardware.misc-V1-java.jar` |
| Log tag | `vendor.oplus.hardware.OplusMisc-V1-service` (service cpp: `vendor/oplus/hardware/misc/aidl/service.cpp`) |
| Side work in the binary | FPGA log saver and report thread (`OplusFpga`), exgpio stats reporter (`OplusExgpio`), fan init (`OplusFan`), report to `android.frameworks.stats`. The shim does none of this. |
| HIDL twin | `vendor.oplus.hardware.misc@1.0::IOplusMisc/default`, enum `OplusMiscStatus`. services.jar has a fallback to it (`V1_0.IOplusMisc`). NOT implemented. The Java callers try AIDL first and use HIDL only when AIDL is null. A null AIDL on pipa gives a HIDL lookup that returns null at once. [inferred] |

## A.2 Wire protocol

Descriptor `vendor.oplus.hardware.misc.IOplusMisc`. Stable AIDL, version 1. Parcel starts with the interface token. Reply starts with the status header (binder exception code 0 = OK), then the return value.
Codes come from the Java stub `IOplusMisc$Stub$Proxy` (`transact(n)`) [seen]. Declaration order = code order.

| Code | Method (Java stub) | Args in parcel order | Reply after status |
|---|---|---|---|
| 1 | `initialize()` | none | int32 (`OplusMiscStatus`: OK = 0, FAILED = 1) |
| 2 | `isMiscNodeSupport(int deviceId, int nodeFlag)` | int32, int32 | int32 |
| 3 | `miscReadNodeFile(int deviceId, int nodeFlag)` | int32, int32 | String |
| 4 | `miscWriteNodeFile(int deviceId, int nodeFlag, String data)` | int32, int32, String | int32 |
| 5 | `saveCalibrationData(int type, byte[] data, int length)` | int32, byte[] (`writeByteArray`), int32 | boolean (int32 0/1) |
| 0xffffff | `getInterfaceVersion()` | none | int32 = 1 |
| 0xfffffe | `getInterfaceHash()` | none | String |

Native signatures in the service (from `.gnu_debugdata`) [seen]:
`initialize(OplusMiscStatus*)`, `isMiscNodeSupport(int,int,int*)`, `miscReadNodeFile(int,int,std::string*)`, `miscWriteNodeFile(int,int,const std::string&,int*)`, `saveCalibrationData(int,const vector<uint8_t>&,int,bool*)`.
No callbacks. No parcelable. `OplusMiscStatus` is an AIDL enum: `OK = 0`, `FAILED = 1` [seen in the Java stub].
The reply String for code 3 is never null in the donor (empty string on any failure). The shim does the same.

## A.3 Donor behaviour per method

| Method | Donor does | Evidence |
|---|---|---|
| `initialize` | Logs "oplus misc initialize enter" and returns OK. No work. | handler `0xe3cc`, 68 bytes [seen] |
| `isMiscNodeSupport` | Logs `in_deviceId, in_nodeFlag`. Looks up `nodeFlag` in the 128-row table. Not found: log "nodeFlag is not support", result `-1`. Found: build path. If `deviceId == 0` path = table path. If `deviceId != 0` path = `sprintf("%s%d", table path, deviceId)`. Result `1` if `access(path, F_OK) == 0`, else `-1` (logs "access %s failed"). Status always OK. | `0xf178` [seen] |
| `miscReadNodeFile` | Same lookup and path build. Flag 288 (0x120): special FPGA read (`readFpgaOpInfo`). Other flags: `open(O_RDONLY)`, `lseek(0)`, `read(size)` where size = table column 2 (A.4), result string = bytes read. Any error or unknown flag: empty string. No newline strip is visible [unknown]. | `0xed74`, `readInterface 0xd928` [seen] |
| `miscWriteNodeFile` | Same lookup. Flag 289 (0x121): special FPGA write (`writeFpgaOpInfo`, partition `oplusreserve1`). Other flags: `writeInterface(path, data)`: for the leaf names `repeat` and `hw_pattern` it retries `open` for a while (retry loop; constants 1000, 80, 15 seen, exact meaning [unknown]; log "open ok, elapsed %ld ms since retry start"); then `open(O_WRONLY)`, `write(data)`. Returns bytes written, or `-1`. Unknown flag: `-1`. | `0xeb38`, `writeInterface 0xda30` [seen] |
| `saveCalibrationData(type, data, length)` | `length` must equal `data.size()` and be `<= 4096`, else log "data size error" / "invalid calibrationData" and false. Switch on `type` (3 values): see A.5. All other types: log "do nothing", false. | `0xe410` [seen] |

The `deviceId` argument is 0 in every caller found (A.6). The "path + deviceId" rule matters only for a second device. The shim answers `-1` for `deviceId != 0`. [inferred safe]

## A.4 Node table (flag -> path), extracted from `.data` of the service

Table at file offset `0x18018`, 128 rows of 136 bytes: int32 read-buffer size, int32 nodeFlag, char path[128]. Order in file is by group, here sorted by flag. Columns: flag, read size, path. [seen]

```
40   1      /proc/colorctrl/color_ctrl
41   256    /proc/colorctrl/temperature
42   256    /proc/colorctrl/voltage
43   256    /proc/colorctrl/cover_color
44   256    /proc/colorctrl/ave_aging_vol
80   256    /proc/devinfo/audio_mainboard
81   256    /proc/devinfo/distribution
82   256    /proc/devinfo
83   256    /proc/devinfo/lcd
84   256    /proc/devinfo/mainboard
85   256    /proc/devinfo/tp
86   256    /proc/devinfo/oplus_board_type
120  256    /proc/tristatekey/hall_data
121  256    /proc/tristatekey/hall_data_calib
122  256    /proc/tristatekey/tri_state
123  256    /mnt/vendor/persist/engineermode/tri_state_hall_calib_flag
124  256    /proc/cs_press/left_press_gear
125  256    /proc/cs_press/right_press_gear
126  256    /proc/cs_press/press_game_switch
127  256    /proc/cs_press/MechanicalKeyParams
128  256    /proc/cs_press/press_charge_state
129  256    /proc/tristatekey/tri_hall
130  256    /proc/tristatekey/dump_register
131  4096   /proc/tristatekey/hall_debug_info
132  256    /proc/pogopin/health_monitor
133  256    /proc/tristatekey/communicate_test
140  256    /proc/cs_press/camera_key_mode
141  256    /proc/cs_press/camera_key_config
142  256    /proc/cs_press/fw_update_file
143  256    /proc/cs_press/fw_info
144  256    /proc/cs_press/gpio_control
145  256    /proc/cs_press/local_fw_info
146  256    /proc/cs_press/health_info
147  20480  /proc/cs_press/quick_on_close
148  256    /proc/cs_press/game_key_mode
150  256    /sys/class/qcom-haptics/lra_frequency_hz
151  256    /sys/class/qcom-haptics/check_trig_status
152  256    /sys/class/leds/vibrator/check_trig_status
180  256    /sys/class/leds/red/support
185  256    /sys/class/leds/red/brightness
186  256    /sys/class/leds/red/trigger
187  256    /sys/class/leds/red/br
188  256    /sys/class/leds/red/color
189  256    /sys/class/leds/red/led_num
190  256    /sys/class/leds/red/l_type
191  256    /sys/class/leds/red/effectdata
192  256    /sys/class/leds/red/repeat
193  256    /sys/class/leds/red/hw_pattern
205  256    /sys/class/leds/green/brightness
206  256    /sys/class/leds/green/trigger
207  256    /sys/class/leds/green/br
208  256    /sys/class/leds/green/color
209  256    /sys/class/leds/green/led_num
210  256    /sys/class/leds/green/repeat
211  256    /sys/class/leds/green/hw_pattern
225  256    /sys/class/leds/blue/brightness
226  256    /sys/class/leds/blue/trigger
227  256    /sys/class/leds/blue/br
228  256    /sys/class/leds/blue/color
229  256    /sys/class/leds/blue/led_num
230  256    /sys/class/leds/blue/repeat
231  256    /sys/class/leds/blue/hw_pattern
240  256    /proc/oplus_misc/misc_feedback
245  256    /sys/class/leds/white/brightness
246  256    /sys/class/leds/white/trigger
247  256    /sys/class/leds/white/detect
248  256    /sys/class/leds/white/support
260  256    /sys/class/leds/aw22xxx_led/rgb
261  256    /sys/class/leds/aw22xxx_led/effect
262  256    /sys/class/leds/aw22xxx_led/cfg
263  256    /sys/class/leds/aw22xxx_led/group_rgb
264  256    /sys/class/leds/aw22xxx_led/group_effect
265  256    /sys/class/leds/aw22xxx_led/group_cfg
266  256    /sys/class/leds/aw22xxx_led/abnormal_reset_count
267  256    /sys/class/leds/aw22xxx_led/funcpme_irq_count
268  256    /sys/class/leds/aw22xxx_led/wtd_irq_count
269  256    /sys/class/leds/aw22xxx_led/check_period
270  256    /sys/class/leds/aw210xx_led/group_rgb
271  256    /sys/class/leds/aw210xx_led/group_effect
272  256    /sys/class/leds/aw210xx_led/group_brightness
273  256    /sys/class/leds/aw210xx_led/group_cfg
274  256    /sys/class/leds/aw210xx_led/led_gpio_detect
275  256    /sys/class/leds/aw210xx_led/abnormal_reset_count
280  256    /proc/fpga/status
281  256    /proc/fpga/info
282  4096   /proc/fpga/debug_level
283  256    /proc/fpga/health_info
284  4096   /proc/fpga/hw_control
285  256    /proc/fpga/work_state
286  256    /proc/fpga/update_flag
287  4096   /proc/fpga/dump_info
288  256    /dev/block/by-name/oplusreserve1
289  120    /dev/block/by-name/oplusreserve1
290  32     /proc/fpga/heartbeat_switch
291  256    /proc/fpga/monitor_time
320  256    /proc/pogopin/kbd_battery_power_level
321  256    /proc/pogopin/kbd_battery_charge_current
323  256    /proc/pogopin/kbd_debug
324  256    /proc/pogopin/kbd_brightness
325  256    /proc/pogopin/kbd_touch_press
326  256    /proc/pogopin/kbd_cover_status
360  256    /proc/magnetic_cover/magcvr_data_handle
361  256    /proc/magnetic_cover/magcvr_farmax_th
362  256    /proc/magnetic_cover/magcvr_healthinfo
363  256    /proc/magnetic_cover/magcvr_cali_support
364  256    /proc/magnetic_cover_pen/magcvr_data_handle
400  256    /sys/class/leds/fan/speed
401  256    /sys/class/leds/fan/state
402  256    /sys/class/leds/fan/rpm
403  256    /sys/class/leds/fan/level
404  256    /sys/class/leds/fan/device_id
405  256    /sys/class/leds/fan/check_period
406  256    /sys/class/leds/fan/fan_install_type
407  256    /sys/class/leds/fan/present
440  256    /sys/class/ex_gpio/chipid
441  256    /sys/class/ex_gpio/reg
442  256    /sys/class/ex_gpio/get_gpio_status
443  256    /sys/class/ex_gpio/monitor_info
444  256    /sys/class/ex_gpio/r_reg
480  256    /sys/class/leds/rgb/support
481  256    /sys/class/leds/rgb/brightness
482  256    /sys/class/leds/rgb/trigger
483  256    /sys/class/leds/rgb/multi_intensity
484  256    /sys/class/leds/rgb/delay_on
485  256    /sys/class/leds/rgb/delay_off
486  256    /sys/class/leds/rgb/hw_pattern
487  256    /sys/class/leds/rgb/repeat
488  256    /sys/class/leds/rgb/multi_index
```

Reading guide (names are from the path; use is [inferred] unless a caller is named in A.6):
- 40..44 `colorctrl`: electrochromic back cover (OPPO phones).
- 80..86 `devinfo`: `80` audio mainboard, `81` distribution, `82` whole devinfo, `83` LCD, `84` mainboard, `85` touch IC, `86` board type.
- 120..133 `tristatekey`, 129..133: three-key and hall switch (alert slider). `122` = `tri_state`: AlertSliderHw reads it.
- 124..128, 140..148 `cs_press`: shoulder / pressure keys (OPPO gaming phones). `127`, `128`, `140`, `148` have system callers.
- 150..152 haptics; 180..275, 480..488 leds (red/green/blue/white/rgb/aw22xxx/aw210xx breathing light).
- 240 `oplus_misc/misc_feedback`; 280..291 FPGA (`288` and `289` special, reserve partition; `290` heartbeat_switch, `291` monitor_time).
- 320..326 `pogopin`: pogo keyboard (324 brightness, 325 touch press have system callers).
- 360..364 `magnetic_cover`: magnetic cover hall.
- 400..407 `leds/fan`: cooling fan. 440..444 `ex_gpio`.

## A.5 `saveCalibrationData` types

| type | Meaning [inferred from log strings] | Length | Storage |
|---|---|---|---|
| 1000030 (0xF425E) | hall / motor calibration | must be 24 | text `%d,%d,%d,%d,%d,%d` to `/sys/class/motor/hall_calibration`; also `/dev/block/by-name/oplusreserve1` when the reserve flag is set |
| 1000104 (0xF42A8) | tri-state key hall calibration (`saveTriCalibrationData`) | any <= 4096 | `/mnt/vendor/persist/engineermode/tri_state_hall_data`, flag file `.../tri_state_hall_calib_flag`, node `/proc/tristatekey/hall_data_calib`. File mode 0664 after create |
| 1000200 (0xF4308) | magnetic cover calibration | any <= 4096 | `/mnt/vendor/persist/engineermode/magneticCoverCalibrationData`, flag `.../magneticCoverCalibrationFlag`, node `/proc/magnetic_cover/magcvr_data_handle` |

Shim: return `false` for all types, write nothing.

## A.6 Callers (system side) and node ids they use

All use `deviceId = 0` unless noted. Lookup is non-blocking in all Java and NDK clients found [seen].

| Caller | Method | Flag(s) | Feature |
|---|---|---|---|
| `ColorModeConfig.getDevInfo` (oplus-services, display colour) -> `OplusEyeProtectLcdInfoHelper.readNodeFile` -> `miscReadNodeFile` | read | 83 (only when `mFeatureID == 9`, main screen) | Panel identity for colour-mode config file name (A.7) |
| `OplusEyeProtectLcdInfoHelper` | read | (generic helper; only caller found is the one above) | Eye Protect LCD info |
| `AlertSliderHw.getHwKeyState` | read | 122 | Alert slider position. Expects the strings "1", "2", "3". pipa has no slider. |
| `ColorMiscNodeManagerService` (system service `IOplusMiscNodeManager`: `isMiscNodeSupport`, `readMiscNodeFile[ByDevice]`, `writeMiscNodeFile[ByDevice]`) | 2, 3, 4 | pass-through from the callers below | generic proxy; looks up with `checkService`; `isMiscNodeSupport` true only if `> 0` |
| `OplusShoulderPressureManagerService`, `StrategyVolumeKeyLaunchCamera`, `StrategyLingXiKey`, `OplusShoulderKeyManagerService`, `ShoulderSingleKeyPolicy`, OplusGames shoulder-key code, Settings `SpecialFeaturesAutoCategoryKeyUtils` | 2, 3, 4 | 140 (support probe), 148, 127, 128 | Shoulder / "Spruce" pressure keys. Probe 140 false -> feature off. |
| `OplusFpgaRusHelper.sendFpgaConfig` | 4 | 290, 291 | FPGA RUS config |
| `KeyboardMiscManager` (+ `KeyboardBacklightDevice`, `KeyboardPressureDevice`) | 1(getInterfaceVersion), 2, 3, 4 via `IOplusMisc` direct | 324 (backlight), 325 (touch press); probes with `isNodeSupported(flag)` (int) | Pogo keyboard |
| `PowerMonitor` `MiscManager` | 3 | 240 | breath-light time |
| `PostmanService` / `OplusCommercialEngineerMode` `OplusMiscHelper` | 2, 3, 4 | 401, 402, 400, 255 (fan), 360..363 (magnetic hall), 120..123, 129 (hall key), 122 (three key), 140/148 (pressure key), 142/143 (pressure fw), 320/321 (pogo battery), 80, 86, 85 (devinfo), 40..44 (electrochromic), 180, 245..248, 260..262 (breath light) | Factory / engineer mode screens only |
| `touchLogkit` (system_ext/bin), `libgaia_logcore_bundle.so` | NDK `fromBinder` (`AServiceManager_getService`/`checkService`) | `touchAidlReadNode(deviceId, flag)` (touch log kit) | log collection; null -> log "oplusMiscHalAidl is null", no hang |
| `OplusQualityProtect`, `OplusAtlasService`, `OplusExSystemService` | (hold the interface string) | [unknown] | not decompiled here |

Expected effect of the shim on these: every probe returns `<= 0`, so the OPPO features that need these nodes stay off, exactly as today with no service. [inferred]

## A.7 Feature detail: colour mode device identifier (flag 83)

`ColorModeConfig.buildDeviceIdentifier` (cached after first call):
1. For `mFeatureID == 9` it calls `getDevInfo()` = `miscReadNodeFile(0, 83)` via `OplusEyeProtectLcdInfoHelper`. Other feature ids use `OplusDisplayPanelFeatureHelper.getDisplayPanelInfoAsString` (the DisplayPanelFeature shim, `maintainer/halshims/.../PanelFeatureService.java`, info id 9).
2. Parse (for feature 9) per line: a line containing `Device version:` sets version = text after the first `:`, trimmed, runs of spaces -> `_`, `-` -> `_`. A line containing `Device manufacture:` sets manufacture the same way.
3. Identifier = `<manufacture>_<version>`. If one is missing: "buildDeviceIdentifier: manufacture or version is null", result null.
4. The config XML name = identifier + suffix (`_srgb`, `_adapt`, `_colorful`, `_cm2_standard`, `_cm2_vivid_standard`, `_cm2_vivid_enhance`, `_cinema`) + `.xml`. If the file is missing the code logs "... .xml, try find default" and uses a default.

Shim reply for flag 83: two lines, `Device version:<V>` and `Device manufacture:<M>` (each ended by `\n`), built from the first non-empty readable pipa panel node. Same node list as `PanelFeatureService.PANEL_NAME`: `/sys/class/drm/card0-DSI-1/panel_info`, `/sys/class/mi_display/disp-DSI-0/panel_info`, `/proc/devinfo/lcd`. The format of the Xiaomi `panel_info` line and the split into version and manufacture are [unknown] (device check D1). If no node gives a value: answer empty String and `isMiscNodeSupport(83) = -1` (current behaviour).
Risk of a wrong value: the identifier matches no XML and the default config is used, same as today. [inferred] Check D2 lists the XML files that exist.

## A.8 pipa mapping per node id

Only rows with a pipa use are listed. Every flag not listed: unsupported (support `-1`, read `""`, write `-1`).

| Flag | Donor node | pipa equivalent | Mark | Phase 1 |
|---|---|---|---|---|
| 83 | `/proc/devinfo/lcd` | Xiaomi panel name from `/sys/class/mi_display/disp-DSI-0/panel_info` or `/sys/class/drm/card0-DSI-1/panel_info` | [inferred], device check D1 | READ: support 1 if a value exists, read returns the two-line text of A.7 |
| 82, 84, 85, 86, 80, 81 | `/proc/devinfo/*` | touch IC name (the touch shim README names NT36532), board type: no OPPO format known | [unknown] | unsupported |
| 324, 325 | `/proc/pogopin/kbd_brightness`, `kbd_touch_press` | pipa pogo keyboard node names unknown | [unknown], D4 | unsupported. A phase 2 whitelist candidate only after D4. |
| 360..364 | `/proc/magnetic_cover/*` | pipa smart-cover hall exists (see `maintainer/bugs/B14-smart-cover.md`) but not through this ABI | [inferred] | unsupported |
| 122, 120..133 | tristatekey | none (tablet has no slider) | [inferred] | unsupported |
| 400..407 | fan | none | [inferred] | unsupported |
| all others | leds, haptics, FPGA, cs_press, colorctrl, ex_gpio | none | [inferred] | unsupported |

## A.9 Shim behaviour table (misc)

| code | method | donor does | shim does on pipa | reply on unsupported | risk |
|---|---|---|---|---|---|
| 1 | `initialize` | log, OK | return 0 (OK) | n/a | none |
| 2 | `isMiscNodeSupport(dev, flag)` | `1` if `access(path)` ok, else `-1` | `dev == 0 && flag == 83 && panel text available` -> `1`; else `-1` | `-1` | A wrong `1` turns on an OPPO feature that writes nodes. Whitelist of supported flags is the only source of `1`. Callers need `> 0`. |
| 3 | `miscReadNodeFile(dev, flag)` | read file, up to table size | `dev == 0 && flag == 83` -> panel text (A.7), max 256 bytes; else `""` | `""` (never null) | Never read other paths (FPGA reserve block, procfs with side effects). Do not use the donor table paths. |
| 4 | `miscWriteNodeFile(dev, flag, data)` | write file; flags 289 FPGA | return `-1`, write nothing | `-1` | OPPO flag numbers collide with pipa kernel nodes of other meaning, so no passthrough. Whitelist empty. |
| 5 | `saveCalibrationData(type, data, len)` | persist files, sysfs | `false`, write nothing | `false` | `/mnt/vendor/persist` writes could damage pipa factory data. Never. |
| 0xffffff | version | 1 | 1 | n/a | The NDK client rejects a binder without version 1 [inferred]. |
| 0xfffffe | hash | hash | `a899a863d8a7e0b5ed35ced2275f2ba68aaad329` | n/a | must match the client lib |

The service must reply with status OK for all codes (the donor never sets a binder error for these methods). An unknown code: return `UNKNOWN_TRANSACTION` as TouchService does.
Registration: `vendor.oplus.hardware.misc.IOplusMisc/default`. The odm service context exists in `odm/etc/selinux/precompiled_service_contexts` (donor) and `vendor/etc/selinux/vendor_service_contexts` (pipa vendor lists it too, label unknown [D5]). Use the label scheme of the touch shim (`oplus_absent_service`). The VINTF side: `odm/etc/vintf/manifest/manifest_misc_aidl.xml` is odm-only and not on pipa; `compatibility_matrix.device.xml` lists misc. No manifest edit is needed for a Java-side `checkService`. A native `isDeclared` check is not used by the clients found. [inferred]

---

# B. `vendor.oplus.hardware.oplusSensor.ISensorFeature`

Prior client-side analysis: `git show cloud/vintf-4q:notes/cloud/OPLUSSENSOR.md` (wire, wait sites, stub plan). Facts below confirmed or added.

## B.1 Donor files

| Item | Value |
|---|---|
| Binary | `odm/bin/hw/vendor-oplus-hardware-oplusSensor-V1-service` (357 KB; symbols in `.gnu_debugdata`) |
| rc | `odm/etc/init/vendor-oplus-hardware-oplusSensor-V1-service.rc`: `service vendor.oplusSensor-aidl-1`, class hal, user system, group system, `disabled`, `oneshot`, `interface aidl vendor.oplus.hardware.oplusSensor.ISensorFeature/default`. Started by `on property:ro.vendor.oplus.sensor.lowmem=` (empty) and `=false`. |
| NEEDED | `vendor.oplus.hardware.oplusSensor-V1-ndk.so`, libbase, libcutils, `libdumpstateutil.so`, liblog, libbinder_ndk, libutils, libhardware, libc++, libc, libm, libdl. Also `dlopen("/odm/lib64/libams.so")` and `/odm/lib64/lib%s.so` (sensor vendor libs, by name). |
| Config | `/odm/etc/sensor/sensor_config.json` (key "25928", project id; lists accelerometer icm456xx, proximity tcs3720, rgb 33171001/33171995/33171028, gyro, hall_effect 33171002, screen_sn 33171996 ...) and `/odm/etc/sensor/config/*.json`. Hardware is OPPO specific. |
| Interface libs | `odm/lib(64)/` and `system_ext/lib(64)/vendor.oplus.hardware.oplusSensor-V1-ndk.so`; Java `system_ext/framework/vendor.oplus.hardware.oplusSensor-V1-java.jar` |
| HIDL twin | `vendor.oplus.hardware.oplusSensor@1.0::ISensorFeature/default`. NOT implemented. `HidlSensorFeature::getService` in `libsensorserviceextimpl.so` uses `retry = false` and does not block. |
| Service log | "eng_aidl service oplus sensor feature started!", "eng_aidl service start in lazy mode" |

## B.2 Wire protocol

Descriptor `vendor.oplus.hardware.oplusSensor.ISensorFeature`. Stable AIDL, version 1, hash `11597a0080b32caa5e6b8494d84965bb46d77eb6`. Codes from the NDK `Bp` methods and the Java stub agree [seen].

| Code | Method | Args in parcel order | Reply after status |
|---|---|---|---|
| 1 | `calibrateSensor(int sensorType, int arg)` | int32, int32 | bool |
| 2 | `getSensorCalibrationData(int sensorType)` | int32 | String |
| 3 | `getSensorConfig()` | none | String |
| 4 | `getSensorRawData(int sensorType)` | int32 | float |
| 5 | `saveCalibrationData(int sensorType, int arg, byte[] data)` | int32, int32, byte[] | int32 |
| 6 | `sensorRawDataEnableDisable(int sensorType, int enable)` | int32, int32 | bool |
| 7 | `sensorReadNodeFile(String name, int maxLen)` | String, int32 | String |
| 8 | `sensorWriteNodeFile(String name, String data)` | String, String | int32 |
| 9 | `setPhoneMode(byte type, byte on)` | byte (`writeByte`), byte | int32 |
| 0xffffff | `getInterfaceVersion()` | none | int32 = 1 |
| 0xfffffe | `getInterfaceHash()` | none | String |

Native service signatures [seen]: `calibrateSensor(int,int,bool*)`, `getSensorCalibrationData(int,std::string*)`, `getSensorConfig(std::string*)`, `getSensorRawData(int,float*)`, `saveCalibrationData(int,int,const vector<uint8_t>&,int*)`, `sensorRawDataEnableDisable(int,int,bool*)`, `sensorReadNodeFile(const string&,int,string*)`, `sensorWriteNodeFile(const string&,const string&,int*)`, `setPhoneMode(int8_t,int8_t,int*)`. No callbacks, no parcelable.

## B.3 Donor behaviour per method

| Method | Donor does | Evidence |
|---|---|---|
| `calibrateSensor` | Switch on sensor type. Handled: Android types 1, 2, 4, 5, 6, 8, 18, 19; OPPO types 65608 (0x10048), 65626..65627, 65634, 65637..65642 (0x1005A..0x1006A); 33171001, 33171002, 33171051, 33171052, 33171055, 33171059, 33171069, 33171070, 33171103, 33171999; calls vendor libs (`libams.so` etc.) and writes calibration files. Other type: false. | `0x3b8a4` [seen switch]; actions [inferred] |
| `getSensorCalibrationData` | Switch on sensor type, per-sensor reader (names in strings: Gyroscope, GyroscopeSub, Gsensor, Proximity, StructureProximity, FakeProximity, HingeDetect, AngleHall, HallEffect, Pressure, RGB, RGBBlackFrame, Spectral, ScreenLight, PadLight, VicePadLight, BackLight). Returns JSON-like String (max 4096). Includes types 1, 2, 4, 5, 6, 8, 65626..65641, 268369921, 268369924, and 33171001, 33171002, 33171005..07, 33171027, 33171028, 33171038, 33171042, 33171043, 33171055, 33171059, 33171062, 33171063, 33171070, 33171093..95, 33171101..03, 33171990..94. | `0x3bc2c` [seen switch] |
| `getSensorConfig` | Reads `/odm/etc/sensor/sensor_config.json`, returns the section of the platform key (via `ro.soc.model` / project). | `0x3c6bc`, strings [inferred] |
| `getSensorRawData` | Constant: writes `0.0f`, status OK. | `0x3c68c` [seen] |
| `saveCalibrationData` | Switch on type (33171006/07/27/28/42/58/59/70/92/93/101..03/991/992/996, 65627, 999996..999998): writes JSON/binary into `/mnt/vendor/persist/engineermode/sensor/spectrum/...`, `/mnt/vendor/persist/camera/...`, `/mnt/vendor/persist/sensors/registry/registry`, reserve partition `/dev/block/by-name/oplusreserve1`. | `0x3cb78` [seen switch], paths [seen strings] |
| `sensorRawDataEnableDisable` | Constant: logs and writes `false`. No sensor is enabled. | `0x3c630` [seen] |
| `sensorReadNodeFile(name, len)` | Name looked up in a 23-row table (B.4). Path = `dir/name`. `open`, read up to the table size, String. Unknown name: "sensorReadNodeFile not support this node", empty. | `0x3b3d4` [seen] |
| `sensorWriteNodeFile(name, data)` | If `data.size() > 4096`: "not support more than 4k file", return -1/-3. Same 23-row table. Writes `data` to `dir/name`, returns bytes written, else -1. | `0x3aed8` [seen] |
| `setPhoneMode(type, on)` | Logs `type=%d, on=%d`. If both arguments equal 1: opens `/proc/sysrq-trigger` and `/dev/kmsg`, writes "oplus_sensor triggered dump by setPhoneMode aidl." to kmsg, writes `c` (0x63) to sysrq-trigger, and writes a "qcom adsp dump node". Open failure: "open dump node or dmesg node failed". Returns int. | `0x3ad64` [seen strings, constants; trigger condition inferred from two `cmp #1`] |

## B.4 Node table for `sensorReadNodeFile` / `sensorWriteNodeFile`

Table at file offset `0x5401c`, 23 rows of 260 bytes: char name[128], char dir[128], int32 size. [seen]

| name | path | read size |
|---|---|---|
| `red_max_lux` | `/proc/sensor/als_cali/red_max_lux` | 16 |
| `green_max_lux` | `/proc/sensor/als_cali/green_max_lux` | 16 |
| `blue_max_lux` | `/proc/sensor/als_cali/blue_max_lux` | 16 |
| `white_max_lux` | `/proc/sensor/als_cali/white_max_lux` | 16 |
| `row_coe` | `/proc/sensor/als_cali/row_coe` | 16 |
| `cali_coe` | `/proc/sensor/als_cali/cali_coe` | 16 |
| `offset` | `/proc/sensor/pressure_cali/offset` | 16 |
| `prjName` | `/proc/oplusVersion/prjName` | 16 |
| `ps` | `/sys/bus/platform/drivers/als_ps/ps` | 16 |
| `ps_raw` | `/sys/bus/platform/drivers/als_ps/ps_raw` | 16 |
| `ps_state` | `/sys/bus/platform/drivers/als_ps/ps_state` | 16 |
| `cali` | `/sys/bus/platform/drivers/als_ps/cali` | 16 |
| `gain_als` | `/sys/bus/platform/drivers/als_ps/gain_als` | 16 |
| `als` | `/sys/bus/platform/drivers/als_ps/als` | 16 |
| `test_id` | `/sys/bus/platform/drivers/msensor/test_id` | 16 |
| `magnet_close` | `/sys/bus/platform/drivers/msensor/magnet_close` | 16 |
| `magnet_leave` | `/sys/bus/platform/drivers/msensor/magnet_leave` | 16 |
| `get_ic_modle` | `/sys/bus/platform/drivers/msensor/get_ic_modle` | 16 |
| `factory_step_debounce` | `/sys/bus/platform/drivers/gsensor/factory_step_debounce` | 16 |
| `hw_region_id` | `/proc/devinfo/hw_region_id` | 16 |
| `lcd` | `/proc/devinfo/lcd` | 100 |
| `lcd_s` | `/proc/devinfo/lcd_s` | 100 |
| `ssc_screenshot_info` | `/dev/ssc_screenshot_info` | 128 |

## B.5 Callers and ids

| Caller | Method | Ids / names | Feature |
|---|---|---|---|
| `libsensorserviceextimpl.so` `fastCaliArgsInit()`, `fastCaliArgsInitSidePanel()` (via `OplusFusionLightArgs::initArgs`, `OplusSidePanelFusionLightArgs::initArgs`) | 2 (Lazy, then Aidl, then Hidl) | sensorType 33171103 (0x1FA269F) | Fusion light calibration args. [seen immediate] |
| `OplusFusionLightConfig::loadLeakFromHal(bool,int)` | 2 | int argument from caller [unknown] | Leak ratio of the screen light |
| `OplusFusionLightNextGen` (`onSampleCollected`, CWB screenshot record) | 8 | name `ssc_screenshot_info` (string present in the lib) | Colour-white-balance screenshot result to the sensor hub. A failed write logs "sensorWriteNodeFile[...] failed, description = ..." from the binder status text. |
| `OplusCommercialEngineerMode` `OplusSensorFeatureHelper` (`getSensorCalibrationData`, `getSensorConfig`, `getSensorRawData`, `saveCalibrationData`, `sensorRawDataEnableDisable`, `sensorReadNodeFile`, `sensorWriteNodeFile`, `doSensorCalibrate`) | 1..8 | node names: `red_max_lux`, `green_max_lux`, `blue_max_lux`, `white_max_lux`, `cali_coe` (size 16), `als`, `gain_als`, `ps`, `ps_raw`, `ps_state`, `cali` (16), `lcd` (100); setters `setAls*MaxLux`, `setAlsCaliPara`; spectrum / RGB calibration screens | Factory sensor calibration UI; SKU node `getSkuNode` |
| `setPhoneMode` | 9 | no caller found in the engineer-mode app or in `scan.json` | none |
| `libsensorserviceextimpl.so` lookups (`waitForService` at 3 sites) | n/a | n/a | See the older note; step 4q removes the VINTF declaration |

## B.6 pipa mapping and sensor-type collision

The 3317xxxx type range collides with Xiaomi's sensors on pipa (AGENTS.md "OPPO sensor type numbers collide"). The shim never receives a sensor enable request, but it does receive types that came from OPPO code. It must not forward any of them to the sensor HAL. In particular: 33171038 (OPPO fold angle = Xiaomi `knuckle`), 33171037 (`screen_down`), 33171001 (CCT, rerouted to 33171088 by `patch_framework.sh`). Which Xiaomi sensor owns 33171028, 33171042, 33171052, 33171059, 33171070, 33171103 is [unknown] (device check S1).

| Item | pipa equivalent | Mark | Phase 1 |
|---|---|---|---|
| node `lcd`, `lcd_s` (read, size 100) | panel text as in A.7 | [inferred], D1 | READ real (same function as misc flag 83); `lcd_s` empty |
| nodes `als`, `gain_als`, `ps*`, `cali`, `*_max_lux`, `cali_coe`, `row_coe`, `offset`, `prjName`, `test_id`, `magnet_*`, `get_ic_modle`, `factory_step_debounce`, `hw_region_id` | none under these paths on pipa; Xiaomi sensors use the SSC / `/sys/class/sensors` HAL | [unknown], S2 | `""` |
| node `ssc_screenshot_info` (write) | `/dev/ssc_screenshot_info` is OPPO kernel specific | [inferred], S3 | return -1, drop data |
| calibration data (types listed in B.3) | none (pipa factory data is in `/mnt/vendor/persist/sensors/registry`, Xiaomi format) | [inferred] | `""` / -1 / false |
| raw data, enable/disable | n/a | | 0.0f / false |
| `setPhoneMode` | n/a (tablet) | | 0, no action |

## B.7 Shim behaviour table (oplusSensor)

| code | method | donor does | shim does on pipa | reply on unsupported | risk |
|---|---|---|---|---|---|
| 1 | `calibrateSensor` | runs calibration, writes persist files | nothing | `false` | A start of calibration on a colliding Xiaomi type could change factory data. Never forward. |
| 2 | `getSensorCalibrationData(type)` | JSON text from persist | nothing | `""` | The fusion light code may treat an empty String as "no data" and use defaults; its exact reaction is [unknown] (S4). |
| 3 | `getSensorConfig` | JSON section | nothing | `""` | engineer mode only |
| 4 | `getSensorRawData` | `0.0f` | `0.0f` | `0.0f` | none |
| 5 | `saveCalibrationData` | persist / reserve partition writes | nothing | `-1` | persist damage if written. Never write. |
| 6 | `sensorRawDataEnableDisable` | `false`, no action | `false`, no action | `false` | A real enable on a colliding Xiaomi id costs power (see `knuckle`). Never enable. |
| 7 | `sensorReadNodeFile(name, len)` | table lookup, read | `lcd` -> panel text, truncated to `len` and 100 bytes; everything else `""` | `""` | Never read a path built from `name`. Match `name` against a fixed set only. |
| 8 | `sensorWriteNodeFile(name, data)` | table lookup, write; max 4096 | nothing | `-1` | The fusion code calls it at the sample rate (`ssc_screenshot_info`): keep the handler cheap (no logging per call, or rate-limit). |
| 9 | `setPhoneMode(type, on)` | with (1,1): writes `c` to `/proc/sysrq-trigger` | nothing | `0` | MUST NOT implement. A passthrough crashes the device. |
| 0xffffff | version | 1 | 1 | n/a | clients check it |
| 0xfffffe | hash | hash | `11597a0080b32caa5e6b8494d84965bb46d77eb6` | n/a | |

Registration and gating: the lookup in `libsensorserviceextimpl.so` is `isDeclared` then `waitForService` (blocking). Step 4q (`maintainer/port/steps/70-4q-vintf-absent-hals.sh`) removes the `oplusSensor` entry, so the clients take the null path today. A shim registered under `ISensorFeature/default` is only reached if the entry is declared again, or by clients that use `checkService`. Decision for the owner: with 4q in place the shim has no user-visible gain; it is useful as a guard if 4q is dropped. [inferred]

---

# C. Device checks (read-only, ADB root)

Use `adb -s <serial> shell "su -c '<cmd>'"`. None of these writes.

Misc / panel:
- D1 `for f in /sys/class/drm/card0-DSI-1/panel_info /sys/class/mi_display/disp-DSI-0/panel_info /proc/devinfo/lcd; do echo "== $f"; cat $f 2>&1 | head -5; done` gives the panel name and the format to split into version and manufacture.
- D2 `find /my_product /my_engineering /odm /vendor /system /system_ext -name '*_srgb.xml' -o -name '*_cm2_standard.xml' 2>/dev/null | head` lists colour-mode config XMLs; compare with `<manufacture>_<version>` from D1.
- D3 `logcat -d | grep -E 'ColorModeConfig|OplusEyeProtectLcdInfoHelper|buildDeviceIdentifier|try find default'` shows today's behaviour with no service.
- D4 `ls /proc/pogopin /sys/class/leds /sys/class/ex_gpio /proc/tristatekey /proc/magnetic_cover /proc/cs_press /proc/fpga /proc/devinfo /proc/colorctrl 2>&1 | head -80` confirms that the OPPO nodes are absent on pipa; and `ls /sys/class/input/input*/name; cat /sys/class/input/input*/name` and `getprop | grep -i -E 'keyboard|pogo'` locate the Xiaomi keyboard nodes.
- D5 `service list | grep -i -E 'IOplusMisc|ISensorFeature'` and `ls -Z /sys/class/mi_display/disp-DSI-0/panel_info` (SELinux read access for the shim domain; add a rule in `maintainer/sepolicy/pipa_port_rules.cil` if the shim runs in `pipa_port`).
- D6 `logcat -d | grep -E 'AlertSliderHw|KeyboardMiscManager|ColorMiscNodeManagerService|StrategyVolumeKeyLaunchCamera|isMiscNodeSupport'` shows which callers run and whether the missing service is logged.
- D7 `su -c 'cat /proc/oplusVersion /proc/sensor/als_cali/cali_coe /proc/sensor/pressure_cali/offset' 2>&1` confirms the sensor-HAL proc nodes do not exist.

Sensor:
- S1 `dumpsys sensorservice | grep -E 'type|Sensor' | head -80` and note names for types 33171028, 33171037, 33171038, 33171042, 33171052, 33171059, 33171070, 33171088, 33171103.
- S2 `ls /sys/bus/platform/drivers | grep -E 'als_ps|msensor|gsensor'; ls /proc/sensor 2>&1` (expected: absent).
- S3 `ls -l /dev/ssc_screenshot_info 2>&1` (expected: absent).
- S4 `logcat -d | grep -E 'ISensorFeature|LazySensorFeature|AidlSensorFeature|OplusFusionLight|fastCali|sensorWriteNodeFile|leakLoaded'` after the first auto-brightness use: shows whether the fusion light starts and how it reacts to an empty calibration String.
- S5 `getprop ro.oplus.os_type; getprop ro.vendor.oplus.sensor.black_frame_3v1; getprop ro.vendor.oplus.sensor.lowmem` for the fusion-light gate.
- S6 `service list | grep -i SensorFeature` (empty after 4q) and `dumpsys sensorservice | grep -i -E 'fusion|oplus'`.

# D. Open points

1. [unknown] Whether the donor read strips the trailing newline. Return the file text as read; Java callers (`AlertSliderHw`, `ColorModeConfig`) trim or split on lines.
2. [unknown] The exact meaning of the second int in sensor `calibrateSensor`/`saveCalibrationData` and the argument semantics of `setPhoneMode`; irrelevant because the shim does nothing.
3. [unknown] C.06 versus C.07 differences in the tables (only C.07 was read). Re-extract the two tables with the offsets above on C.06: misc `.data` at `0x18018`, 128 x 136 bytes; sensor `.data` at `0x5401c`, 23 x 260 bytes.
4. [unknown] `OplusQualityProtect`, `OplusAtlasService`, `OplusExSystemService` flags (not decompiled here).
5. [inferred] `deviceId != 0` is unused by all callers found; the shim answers `-1`.

## Review decisions (2026-11-03)

- misc: `maintainer/halshims/src/pipa/hal/MiscService.java`. Supported flag only 83, and only when pipa has
  `/proc/devinfo/lcd`; no writes; no calibration saves. Enable it after the `lshal` check (HIDL misc declared on
  pipa = the shim removes a possible endless wait).
- oplusSensor: no shim for now. Step 4q removes the declaration, so the clients take the null path at once. No
  sensor data is lost that pipa can give: the fusion-light calibration (type 33171103) and the OPPO node table have no
  pipa source, and many calibration types collide with Xiaomi sensor types. **Never** forward `setPhoneMode`: the
  donor writes `c` to `/proc/sysrq-trigger` (a kernel crash on purpose) for one argument pair (string
  `/proc/sysrq-trigger` confirmed in the C.07 binary).
