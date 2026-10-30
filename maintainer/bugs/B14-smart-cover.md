# B14: closing the magnetic case does not turn the screen off

> **Historical analysis (2026-10-22).** Current status: **fixed in beta5-2e** (helper `LidKeeper`), verified
> 2026-10-23. The current list is `BUGS.md` (B14).

Status: cause found (2026-10-22), fix proposed, not built. Investigation was read-only on the tablet.

## Event path on pipa (works)

- DT `soc/gpio_keys/hall_key`: `linux,input-type=5` (EV_SW), `linux,code=0` (SW_LID), wakeup GPIO 110.
  `hall_key1`: SW_TABLET_MODE (code 1), GPIO 121.
- Input device `gpio-keys` = `/dev/input/event2`: `SW_LID SW_TABLET_MODE` (`getevent -lp`).
  The virtual `xiaomi keyboard WakeUp` (event7) also declares SW_LID/SW_TABLET_MODE.
- `/proc/interrupts`: `hall_key` 12 edges, `hall_key1` 8, after 9 min uptime, so the sensor fires.
- Android receives it: `dumpsys window` shows `mLidState=LID_OPEN`; `dumpsys input` lists the
  devices as SWITCH. No Xiaomi hall sensor or service is involved (`dumpsys sensorservice` has none).

## Why ColorOS ignores it

Android 16/17 decides what a closed lid does from `Settings.Global.lid_behavior`
(0 none, 1 sleep, 2 lock), not from the framework config directly:

- `services.jar` `PhoneWindowManager.getLidBehavior()` = `Settings.Global.getInt("lid_behavior", 0)`.
  `applyLidSwitchState()` calls `goToSleep(now, 3 /*LID_SWITCH*/, 1 /*NO_DOZE*/)` only for 1.
  `notifyLidSwitchChanged()` wakes on open without any condition (`WindowWakeUpPolicy.wakeUpFromLid`).
- The value is seeded once, at first boot, by SettingsProvider
  `DatabaseHelper.loadGlobalSettings`: `config_lidControlsSleep` → 1, else `config_lidControlsScreenLock` → 2, else 0.
  In this ROM the lookup reads **SettingsProvider's own** resources
  (`system_ext/priv-app/SettingsProvider/SettingsProvider.apk`: `bool/config_lidControlsSleep=false`,
  `config_lidControlsScreenLock=false`), not framework-res (which is also `false`, `0x01110215`, unused).
- Device: `settings get global lid_behavior` = **0**, `dumpsys window`: `getLidBehavior=LID_BEHAVIOR_NONE`.
- HyperOS (same kernel path, Android 14): its SettingsProvider seeds `lid_behavior` from framework-res
  `config_lidControlsSleep` = **true** (`0x0111019c`), so `lid_behavior=1`. The PhoneWindowManager code is the same.
- ColorOS `oplus_devicecase` (`OplusDeviceCaseManagerService`) is OPPO's window-case feature built on a hall
  *sensor*; it reports "Hall Sensor Not Found" here and is not the lid path.

## Fix (ROM)

1. New static RRO `PipaSettingsProviderOverlay.apk` in `system/my_product/overlay/`, next to the other
   port RROs (`PipaCornersOverlay` etc.; add a `carry add port RRO` row in `PORT-EDITS.tsv`):
   package `com.port.pipa.overlay.settingsprovider`, `targetPackage="com.android.providers.settings"`,
   `isStatic=true`, priority 9001, `res/values/bools.xml`: `<bool name="config_lidControlsSleep">true</bool>`.
   Build with `aapt2` + `apksigner` from build-tools 37 (same as the helper). Optional: the same value
   for `android` in `PipaCornersOverlay`, for consistency only.
2. This seeds only a **fresh** `/data` (`DatabaseHelper.onCreate`). Dirty flashes keep the stored 0, so the
   release notes need the one-time command `adb shell settings put global lid_behavior 1` (shell has
   WRITE_SECURE_SETTINGS, no root needed). An in-ROM migration would need the helper as a priv-app with
   WRITE_SECURE_SETTINGS, which is more work.
   Untested alternative: `<settings_item name="lid_behavior" value="1" category="global"/>` in
   `system/my_stock/etc/extension/config_com.android.providers.settings.xml` (ColorOS `ConfigManager`, INSERT OR
   REPLACE after the AOSP defaults, also first boot only). Doubt: `security_window` on the device is 0 even though
   that file sets 1.

## Test for the user

1. Check the hall works: `adb shell su -c 'getevent -lt /dev/input/event2'`, close the case, then open it.
   You should see `EV_SW SW_LID 00000001`, then `00000000`.
2. Apply the setting at runtime: `adb shell settings put global lid_behavior 1`. Close the case: the screen goes off
   (no AOD). Open it: the screen wakes to the lock screen. Undo with `... lid_behavior 0`.
3. Keyboard case: fold it behind the tablet and type. The screen must stay on, and SW_LID must not change
   (that position should only toggle SW_TABLET_MODE).

## Risks

- If the keyboard case folded behind the tablet also closes `hall_key`, the screen would turn off while
  someone is using it. This matches stock (`lid_behavior=1`), but test it (step 3).
- `NO_DOZE`: closing the case skips AOD. That is fine, since AOD is off on this LCD.
- Upgraded installs keep 0 until the command is run.
