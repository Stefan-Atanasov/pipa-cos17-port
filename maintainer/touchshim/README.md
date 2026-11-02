# Touch HAL draft (BUGS-TODO 51)

Build with `sh maintainer/touchshim/build.sh`. Output: `port-rom/pipa_port/touchshim.jar`.
The build uses JDK 21, javac, d8 and the API 37 jar. It does not use donor classes.
The jar contains original wire-protocol code. It has no signing key.

`TouchService.java` implements transactions 1–9 and metadata. `TouchHost.java` runs the host
and the registrar in separate processes. `start.sh` starts both. Step `68-4o-touch-hal-shim.sh`
ships these files and inserts the startup block in the build tree. It does not change the source
runtime or the charger jar. Step 4m keeps its current jar and host.
The binary-only charger host cannot host this service without a separate patch. This draft
uses its process model, with a new intermediate name (`pipa.touch.shim`).

## Evidence

The requested donor path under `system/system/framework` does not exist here.
The interface jar is `../reference/cos17/system_ext/framework/vendor.oplus.hardware.touch-V2-java.jar`.
Its Stub confirms the descriptor, codes 1–9, argument order, nullable typed parcelable in code 7,
and the one-way code 6. OplusTouchInfo has a size prefix, then time (long), deviceId, nodeFlag,
data (ints), and info (String). The draft validates and skips this parcelable because code 7 is unsupported.
Metadata is version 2 and hash `ef41c5fab372bb5ad6a417f606845c87cf0e9b17`.
Callbacks arrive as strong binders. The draft stores at most 32. It never calls them.
Dead callbacks stay until unregister or process exit. Duplicate registrations are idempotent.

`ColorTouchNodeManagerService.isTouchNodeSupport` in
`../reference/cos17/system/system/framework/oplus-services.jar` returns true only when the
HAL result is greater than zero (`if-lez`). The scratchpad's nonnegative rule is incorrect
for this donor. Mapped nodes return 1. Other nodes and device IDs return -1.
Writes return 0 on queue acceptance and -1 on unsupported input or a full queue.
The service's write handler tests negative results for failure. Reads return the last accepted
write or an empty string. They do not read hardware. Values reset when the host exits.

Kernel paths below are relative to `../port-work/kernel/walt-oppo/`.
The enum is in `drivers/input/touchscreen/xiaomi/xiaomi_touch.h:67`.
Let N mean `drivers/input/touchscreen/nt36532/nt36xxx.c`.

| OPPO node | Xiaomi mode | Draft input mapping | Kernel evidence |
|---|---|---|---|
| 5 direction | 8, Touch_Panel_Orientation | 0..3 unchanged | N:2284–2288 range; N:2373–2376 direction; N:2411–2430 commands |
| 25 sensitivity | 3, Touch_Tolerance | 0..100 -> round(value * 4 / 100) | N:2257–2261 range; N:2383–2408 firmware worker |
| 243 click sensitivity | 2, Touch_UP_THRESHOLD | 0..100 -> round(value * 4 / 100) | N:2250–2254 range; N:2383–2408 firmware worker |
| 245 extreme touch | 0, Touch_Game_Mode | 0/1 unchanged | N:2236–2240 range; N:2404–2406 state and pen switch |
| 251 edge | 7, Touch_Edge_Filter | 0..3 | N:2291–2295 range; N:2383–2408 firmware worker |
| 252 corner | 7, Touch_Edge_Filter | 0..3 | Same shared filter |
| 8 grip | 7, Touch_Edge_Filter | Exact `mod para_V2 set_ime_showing:0` or `:1` sets an IME floor of 0 or 1 | Same shared filter; IME policy is a draft approximation |

The shared filter is max(edge, corner, IME floor). Initial bridge requests are zero.
The kernel default filter is 2, but its initial current/set fields are zero.
The draft cannot give edge and corner separate regions.
The slider mapping is linear and uses the same direction. The OPPO 0..100 input range is an
explicit draft assumption, not a verified COSA contract. Reject values outside each range.
Calibrate the range and direction before release. Rotation 1 is anticlockwise 90 degrees in the
kernel. Confirm the OPPO convention on all four rotations.

Node 192 is unsupported. The NT36532 set handler and firmware worker have no glove command.
All other nodes are unsupported. This includes report rate, Active_MODE timing, rain, underwater,
gestures, diagnostics and joystick geometry. An enum alone does not prove a firmware operation.
Unknown node-8 commands are ignored and return -1. Bluetooth writes (5) and notifications (7)
return -1. Initialize returns 0. One-way writes use the normal write mapping but have no reply.

The tool has no source in this workspace. Its embedded usage is `set <mode> <value>`,
`get <mode>`, and `pen on|off [id]`. Existing `service.sh:544` uses `pen on`.
The draft runs its absolute path with fixed arguments and no shell. One worker preserves order.
The queue holds at most 64 requests. Each child has a two-second wait limit.
Failures go to `touchshim.log`. A kernel ioctl in uninterruptible sleep can outlive a kill.
There is no hardware-success acknowledgement or retry. Kernel writes also queue firmware work.

## SELinux and registration

The charger name is already labelled `oplus_absent_service` in donor
`vendor/etc/selinux/vendor_service_contexts:51`. No charger context edit exists in the step files.
The draft adds both touch names to `system_ext_service_contexts` with the same existing type.
It adds these rules to the normal and optional debug CIL:

```cil
(allow pipa_port oplus_absent_service (service_manager (add find)))
(allow system_server oplus_absent_service (service_manager (find)))
```

The existing runtime rules permit peer Binder calls, fd use, and
`pipa_port -> xiaomi_touch_device` ioctl/open/read/write. These are reused.
The shared type also permits access to other names with that type. A dedicated type could
reduce this scope later. Check all service_contexts inputs for conflicting touch labels.
Compile the combined policy before a ROM build. The draft step does not compile policy.
No policy, service registration, or device test has run here.
A separate registrar passes the host's BinderProxy to servicemanager, as the charger does.
The manual Binder is not marked VINTF-stable. This follows the charger proxy workaround;
VINTF stability checks remain an open runtime risk. Do not add a duplicate VINTF entry blindly.

## Live test commands (not executed)

First validate and boot the policy/context changes through the normal maintainer process.
A jar bind mount cannot install service labels or reload servicemanager's policy cache.
Do not use live `ksud sepolicy patch`. If 4o policy is absent, stop before registration.
The commands below assume the 4o names and policy are active, and no real touch HAL runs.
The directory bind also works when the old ROM has no `touchshim.jar` mount target.
Ask the user to coordinate if `pgrep -af opencode` shows an active agent.

```sh
pgrep -af opencode
ADB='adb -s 83836a90'
$ADB push port-rom/pipa_port/touchshim.jar /data/local/tmp/touchshim.jar
$ADB push maintainer/touchshim/start.sh /data/local/tmp/touchshim-start.sh
# Stop an existing touch host only by its recorded PID. Do not stop the charger.
$ADB shell "su -c 'if [ -f /data/local/tmp/touchshim-host.pid ]; then kill \$(cat /data/local/tmp/touchshim-host.pid); fi'"
$ADB shell "su -c 'mkdir -p /data/local/tmp/touchshim-runtime; cp -a /system_ext/pipa_port/. /data/local/tmp/touchshim-runtime/; cp /data/local/tmp/touchshim.jar /data/local/tmp/touchshim-runtime/touchshim.jar; cp /data/local/tmp/touchshim-start.sh /data/local/tmp/touchshim-runtime/touchshim-start.sh; chcon -R u:object_r:system_file:s0 /data/local/tmp/touchshim-runtime; chmod 755 /data/local/tmp/touchshim-runtime/touchshim-start.sh; nsenter -t 1 -m -- mount --bind /data/local/tmp/touchshim-runtime /system_ext/pipa_port'"
$ADB shell "su -c 'nsenter -t 1 -m -- runcon u:r:pipa_port:s0 /system/bin/sh /system_ext/pipa_port/touchshim-start.sh </dev/null >/data/local/tmp/touchshim-start.log 2>&1 &'"
$ADB shell 'service check vendor.oplus.hardware.touch.IOplusTouch/default'
$ADB shell 'service call vendor.oplus.hardware.touch.IOplusTouch/default 16777215'
$ADB shell 'service call vendor.oplus.hardware.touch.IOplusTouch/default 2 i32 0 i32 5'
$ADB shell 'service call vendor.oplus.hardware.touch.IOplusTouch/default 2 i32 1 i32 5'
$ADB shell 'service call vendor.oplus.hardware.touch.IOplusTouch/default 2 i32 0 i32 192'
$ADB shell 'service call vendor.oplus.hardware.touch.IOplusTouch/default 4 i32 0 i32 243 s16 50'
$ADB shell 'service call vendor.oplus.hardware.touch.IOplusTouch/default 3 i32 0 i32 243'
$ADB shell "su -c '/system_ext/pipa_port/xiaomi_touch_ioctl get 2; cat /data/local/tmp/touchshim.log; logcat -d -s auditd'"
# Stop and remove the bind. A reboot also removes the bind and resets driver state.
$ADB shell "su -c 'kill \$(cat /data/local/tmp/touchshim-host.pid); nsenter -t 1 -m -- umount /system_ext/pipa_port'"
```

Use the ColorOS UI for an end-to-end test. A shell transaction can be denied by caller policy.
Check orientation, each sensitivity endpoint, shared-filter arbitration and unsupported device 1.
Check queue failures and restart behavior. Keep the pen away during game-mode tests:
N:1231 explicitly disables pen input while game mode is on. Set node 245 back to 0 after a test.
Stopping the host does not restore driver modes. Save ioctl values first and restore them, or reboot.
Record any future device changes in DEVICE-STATE.md. This draft made none.
