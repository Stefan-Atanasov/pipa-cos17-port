> Public copy of the maintainer bug list (`BUGS-TODO.md`). Links to `MAINTAINER-STATUS.md`, `HISTORY.md`, `notes/` and `kernel/*.md` point to private maintainer notes that are not in this repository.

# Bugs and to-do (user reports)

Reported bugs and wishes, collected for later work. Each entry has the report, what the images
show (offline analysis), what to capture on a device, and where a fix would live.
Status: **open** (not investigated), **analysed** (offline cause candidates), **fix planned**,
**fixed in <build>**.

Updated 2026-10-24 17:00 (ROM beta5-2p, kernel walt-r5). Related: `MAINTAINER-STATUS.md` (builds and plan),
`notes/STABILITY-PERF.md` (old stability and performance plan, captures D1-D17), `notes/PHASE2-ROM-INTEGRATION.md`
(how the runtime fixes went into the ROM).

## Open items (2026-10-24, beta5-2p + walt-r5; the large table below has the full history of each item)

| Prio | Item | Why it is open | Next step |
|---|---|---|---|
| 1 | **Clean-flash test of the release package** | Only dirty upgrades are tested | The user runs `FlashLinux.sh` with wipe from `ColorOS17-Port-pipa-beta5-2o-20261024` |
| 2 | Night drain on 2j+ | The keyboard guard (2j) is not measured for a full night | batterystats after a night (reset 2026-10-24 09:21) |
| 3 | Stutter under real use | Manual trace: SF on time 86 %, drops = SF GPU deadline misses (74 % of frames GPU-composed: blur, rounded window corners); memory reclaim ruled out (HISTORY 16:20, 17:15) | Blur decision (row below), loop fix (3a) |
| 3 | Window blur → GPU composition | Blur forces client composition of all layers below (clientType=BLUR); A/B blur off: -25 % drops, -35 % GPU misses | User decides: `disable_window_blurs=1` as a ROM default in 2q? |
| 3a | pipa_port loop CPU | 14.7 % of a core while the screen is on (short processes every second) | **2.3 % live** (HISTORY 17:15); user test of pen dock/buttons, then ROM 2q |
| 3b | **14** Package cache keeps old manifest data | Layers build with `mkfs.erofs -T0` and keep the fingerprint: a changed system APK keeps its cached manifest (helper shows 0.4 on 2p; its 0.5 code runs) | Clear `/data/system/package_cache` when the layer changes (early boot), or build with a newer fixed `-T` per layer |
| 3c | **15** Pen capsule 2-3 times at boot | pipa_port sends present=1 at boot +10 s +40 s (old workaround for "stylus connected"); with 2p each one shows the capsule | Send the boot resends without the capsule (flag) or drop them if Settings stays correct |
| 4 | Unmapped ColorOS hints | SELinux blocks OPPO's perf daemon (a live fix works, measured neutral); `/proc/oplus_binder/ux_flag` is missing | Optional ROM 2p policy + kernel binder ux_flag (KERNEL-RESEARCH "2026-10-24 late afternoon") |
| 5 | **11** "Xiaomi Keyboard configured" notification without a keyboard | The nanosic driver registers virtual input devices at probe | Kernel: register them on attach (a keyboard is necessary for the test) |
| 6 | **B9** network sharing | The virtual modem answers `RADIO_NOT_AVAILABLE` | Logs from the **phone** during a share |
| 7 | **B8** privacy password and app lock | Needs the OPPO `ICryptoeng` HAL (absent) | A small `ICryptoeng` shim, or hide the entry |
| 8 | Face enrollment crash | `crop_eyes` ROI out of range near the frame edge | A guard in a wrapper; a second try works |
| 9 | **B1** Wi-Fi sometimes does not turn on | No recovery path | `gEnableForceTargetAssert=1`, correct the `wifi_cool_reset` domain |
| 10 | **B2** UI behind the navigation bar | Insets are the probable cause | Device dumps from an app with the problem |
| 11 | **B11** refresh rate does not drop when idle | Needs an `IDisplayPanelFeature` shim | Parked |
| 12 | `pipa_port` domain is permissive | The rules are not collected | `avc_trace.sh` boot trace, then remove `typepermissive` |
| 13 | Colour and adaptive restore is still a script | The apps that reset them are not patched | Find the app that resets them |
| — | Play Integrity | BASIC only (unlocked bootloader) | None |

Fixed on 2026-10-24: pen battery in the OPPO live alert (**12**, 2p, verified on the flashed ROM 16:56). Before: idle drain from `xiaomi-keyboard` (2j), GNSS retry loop (2j), perfetto/traced (2j), "battery not
genuine" dialog (2k), stutter / dropped frames (2l + walt-r4/r5: SurfaceFlinger, RenderEngine and UI threads on big
cores, SF timing), Settings search glitch (2m, layer caching off), slow QS -> Settings (2n), refresh-rate switches mid-animation (Spotify -> pill; 2o: apps at 120 Hz, video 60). B4/B5 (lag): heavy-test
SF frames on time 59 -> 94-96 %, launcher 5.8-7.6 % janky with material blur off. Own kernel: done (walt-r5).

Verified fixed: B3, B6, B7, B10, B12, B13, B14 (details in the table).

| # | Report (source) | Status | Summary |
|---|---|---|---|
| B1 | Wi-Fi sometimes does not turn on (other users, 2026-10-22) | analysed | no recovery path when the QCA6390 driver/firmware fails to come up: SSR off in the ini, ColorOS cold-reset service can't run (`su` domain) |
| B2 | UI drawn behind the navigation bar (other users, 2026-10-22) | analysed | no port navbar overrides; density values disagree (370/360, stock 400); taskbar insets and edge-to-edge suspected; needs device dumps |
| B3 | Pen not shown while charging, no pen battery percentage (other users, 2026-10-22) | **fixed in beta5-2d/2f** (pen pill on dock/undock, low-battery notification at ≤15 %; verified 2026-10-22 22:18; "stylus connected" in Settings needed the pen message repeated, fixed in 2f, verified 2026-10-23) | hardware fine (pen charges, `reverse_pen_soc`); ColorOS UI only for OPPO pens. Plan: module watcher sends the pen-present intent + own battery notification |
| B4 | Lag in animations with blur enabled (other users, 2026-10-22) | analysed (offline) | `maintainer/bugs/B3-B4-pen-blur.md`: `anim_level=1` (donor flagship grade), `system_material_blur_enable`, skiavk renderer, 144 Hz; ranked fixes to A/B with the perf module |
| B5 | Make it smoother and lighter (other users, 2026-10-22) | analysed (offline) | `notes/STABILITY-PERF.md` §2–3 and `maintainer/bugs/B3-B4-pen-blur.md` B4/B5; beta4 perf baseline in `port-work/perf-ab/results.csv` (`bench.sh`, fixed 2026-10-22) |
| B7 | Face enrollment preview is rotated (correct only in portrait) and slightly stretched (maintainer, 2026-10-22) | **fixed in beta5-2e/2f (verified 2026-10-23)** | **Rotation:** facehal-rs adds `persist.vendor.facehal.rotation` (0/90/180/270, read per preview frame) to the camera orientation but ignores the display rotation; on pipa the extra turn is **90 × display rotation** (tested: 270 at rotation 1 = upside down, 90 = correct). pipa_port sets it while a camera worker (second facehal process) runs, from `dumpsys display` `mCurrentOrientation`. **Stretch:** ColorOS Settings shows the preview in a square SurfaceView (740×740) but the HAL fills it with the full 3:4 frame (480×640 / 640×480, `dumpsys SurfaceFlinger` geomBufferSize), so it was squashed one way per orientation. `port-module/src/facecrop.c` → `facehal/lib64/libpipa_facecrop.so` (NDK 30), LD_PRELOADed into facehal-rs, wraps `ANativeWindow_setBuffersGeometry` and sets a centred square `NATIVE_WINDOW_SET_CROP` (log tag `pipa_facecrop`). Maintainer: "works now perfect". **Separate open bug:** the face engine's `crop_eyes` (libjni_stfaceunlock_api, OpenCV ROI out of range → `cv::error` → unwinder SIGSEGV) can kill the HAL during enrollment when the face is near the frame edge (tombstone_08, 22:51) |
| B8 | Privacy password (Settings): linking it to the account or enabling it does not work (maintainer, 2026-10-22) | **cause found 2026-10-22 (beta5-2d)**; decision pending (shim or hide) | Flow runs (ChooseGenericPrivacy → ChooseNumberPrivacy → LinkAccountActivity → SecurityQuestionActivity), but every step fails silently: Settings `com.oplus.settings.privacy.sdk.PrivacyPasswordController` stores the password through `RpmbChannel.processCmdV2` → `com.oplus.hardware.cryptoeng.CryptoEngManager.cryptoEngCommand` → vendor HAL **`vendor.oplus.hardware.cryptoeng.ICryptoeng/default`** (OPPO TEE/RPMB), absent on pipa (`CryptoEngManager: getService fail`, `RpmbResultParser: buffer is empty`, `isMethodExecuteSuccess resultSummary is null`). Not portable (OPPO secure-world TA). No OPPO account is signed in either (`dumpsys account`), but that is not the blocker. Options: (1) software `ICryptoeng` shim storing in `/data` (protocol from Settings' MethodBuffer/RpmbResultParser; also unblocks app lock / hidden apps if they use it), (2) hide the entry. |
| B9 | Interconnect: most features work, but network sharing, call sharing, SMS sharing and app relay do not (user report, 2026-10-22) | **partly fixed in beta5-2c** (bluetooth→ISubsysRadio denial gone); network sharing still broken | Lead (live, beta5-2b): `bluetooth` is denied `find` on `ISubsysRadio` (`tcontext=ISubsysService`, enforcing); call/SMS sharing go through the virtual modem (`subsys_daemon`, started by pipa_core for 通信共享/网络共享; `ISubsys/default`, `ISubsysRadio/slot1`+`slot2` are registered). Candidate fix: `(allow bluetooth ISubsysService (service_manager (find)))` in the system_ext pipa port block, then retest with `avc_trace.sh` while trying each feature. Also check app relay separately (likely a feature flag / account-bound service). `ro.carrier=wifi-only` is set on purpose (hides cellular UI); confirm it does not also disable call relay. Same report: USB-DAC volume fix works with AKG earphones **2026-10-22 21:25 (beta5-2c), network sharing:** no SELinux denial; the phone pairs (PadConnect sees the OPPO Find … Pro Max as a Synergy device). Network sharing uses the phone's mobile data through the virtual modem, and that data path fails: `RilRequest DATA_REGISTRATION_STATE/VOICE_REGISTRATION_STATE error RADIO_NOT_AVAILABLE`, `SET_DATA_PROFILE REQUEST_NOT_SUPPORTED`, `RILJ … not supported on service NETWORK < 2.2`, netd `TetherController: property_get sys.radio.data.modem_share_flag return 0`. Suspect: `ro.carrier=wifi-only` (set by the port to hide cellular UI) may also disable the virtual-SIM data link; test with the prop changed at post-fs-data. Also compare with what the virtual modem (pipa_core subsys_daemon, `libqti-radio-service.so`) actually serves.  **Call sharing test 2026-10-22 21:28 (beta5-2c): nothing happened on the tablet.** The virtual comm link does come up: `com.oplus.subsys` `DistributedCommDev` exchanges `VcCapabilityMsg{mCallShared=true, mSmsShared=true}` with the phone over `VirtualCommChannel` (21:27:45); virtual RIL is up (`virtual-ril-daemon-0/1`, `IRadio/vircommslot1/2`, `gsm.version.baseband=Virtual RILD Modem`). At the call the only event was `bt_btif_sock_rfcomm: bta_co_rfc_data_incoming: RFCOMM slot_id 14 not found` (21:28:46): the phone sent RFCOMM data to a socket the tablet's BT stack does not have, likely the call signalling. Network sharing: the request never reached com.oplus.subsys; `com.heytap.accessory` logs `usb host ip is None` / `get_virtual_gateway_ip`. **Next:** a dedicated session with logs from both devices (phone `logcat` too) during a call and a network-share attempt; focus on the BT RFCOMM sockets the OPPO apps open (`dumpsys bluetooth_manager`, `btsnoop` HCI log) vs this port's BT stack; check whether the tablet's donor identity (OPD2515) matters to the phone |
| B10 | Dolby Atmos not active after a reboot until toggled off/on in Settings (maintainer, 2026-10-22, beta5-2b) | **cause found 2026-10-22 (beta5-2c); **fixed in beta5-2d** (pipa helper, verified 2026-10-22 22:17)** | **Cause:** nothing creates the Dolby effect at boot. pipa's vendor has only Xiaomi's `dap` effect (`9d4921da-…`, `DAP_offload`). Settings → Sound effects (`portcolor_misound_entry`) opens **MiSound** `HeadsetSettingsActivity`, which creates a `DolbyAudioEffect` on the global output mix (session 0) when it starts (`setDsOnSafely`); the effect lives only as long as MiSound's process (it is the only client in `dumpsys media.audio_flinger`), and ActivityManager kills MiSound as a cached app (seen 21:19, `Cached(nirvana)`). On HyperOS the global effect is held in system_server by `miui-services.jar` `com.android.server.audio.dolbyeffect` (DolbyEffectController: creates it at boot, restores the state, retunes on rotation/volume/device), which the port does not carry. The DAX db `/data/vendor/dolby/dax_sqlite3.db` keeps `State=true`, `Profile=0`. **Second problem:** ColorOS's `com.oplus.audio.effectcenter` `AudioxService` (`ro.oplus.audio.effect.type=audiox_merge`) tries to create OPPO's AudioX effect `41f6c0f4-5d8f-11ec-bf63-0242ac130002`, which pipa's vendor lacks, and retries **every 3 s forever** (`Failed to recreate AudioxEffect … Error: -3`): wasted wakeups. **Fix plan:** a persistent holder of the global `DolbyAudioEffect` that applies the saved state at boot (best in the planned helper app, as a persistent priv-app in the ROM; later also the rotation/volume tuning); stop the AudioX loop: **done live 2026-10-22 21:45** (`pm disable …/.service.AudioxService`, README device table; ROM: same via a default disabled-component or by dropping `audiox_merge`), sound pages still to check. Capture: `port-work/device-captures/b10-dolby-2c-20261022/` (toggle log, DAX db). **Helper test 2026-10-22 21:54** (`COS17/helper/`, `DolbyKeeper`, priority −1 on session 0): next to MiSound it waits without control; after `am force-stop com.miui.misound` it gets control and DAP stays enabled; with both stopped (no DAP left) a fresh start creates DAP, reads DS state 1 and enables it (`applied saved state: on`). **ROM (2d):** `system/app/PipaHelper/PipaHelper.apk` (persistent system app) + `system/etc/sysconfig/pipa-helper-hiddenapi-package-whitelist.xml` (`<hidden-api-whitelisted-app package="com.port.pipa.helper"/>`), then drop the global exemption |
| B13 | Boot animation turns to portrait and the logo is drawn wrong (maintainer, 2026-10-22, beta5-2b) | **fixed in beta5-2e (verified 2026-10-23)** | **Cause:** ColorOS `services.jar` `DisplayRotation.<init>` sets the first rotation `mRotation = mUserRotation = ro.panel.pad_orientation / 90`. OPPO pads have native landscape panels, so the donor's `0` is landscape there; pipa's panel is native portrait (1800×2880, `installOrientation ROTATION_0`), so WM started at portrait right after the bootanimation (which forces `ROTATION_90` for tablets, `ro.bootanim.set_orientation_*`) and the screen flipped. **Fix:** `ro.panel.pad_orientation=90` (`my_product/build.prop`, two lines): SurfaceFlinger now only sets `ROTATION_90` through the boot (logcat `OplusSurfaceFlinger: setProjection`), maintainer confirmed. Also makes landscape the default with auto-rotate off. Live test: `/data/adb/post-fs-data.d/99-pipa-padorient-test.sh` (`resetprop`), remove after 2e. `libquickboot.so` reads the prop too. **Logo position (fixed live 23:14, maintainer: centred):** ColorOS bootanimation centres the `g` strip and adds `offsety`; OPPO rescales it from a device height pipa lacks (`device height is not available for animation`), so the raw +844 put the 1680×128 logo at the bottom edge ((1800−128)/2+844=1680). `my_product/media/bootanimation/{,r}bootanimation.zip` desc.txt `g 1680 128 0 844 60` → `g 1680 128 0 0 60` (stored zips in `maintainer/bootanim/`, md5 `6aa83f59…`/`0f1dab08…`); live test bind `/data/adb/post-fs-data.d/98-pipa-bootlogo-test.sh` + `/data/adb/pipa-bootlogo/`, remove after 2e |
| B14 | Closing the magnetic case does not turn the screen off (maintainer, 2026-10-22) | **fixed in beta5-2e (helper LidKeeper, instant)** (verified 2026-10-23) | Hall = `gpio_keys/hall_key` SW_LID on GPIO 110 (`/dev/input/event2`, fires: `/proc/interrupts`), Android sees it (`mLidState`). `PhoneWindowManager` sleeps on lid close only if `global lid_behavior`=1; it is 0 because SettingsProvider seeds it at first boot from its own `config_lidControlsSleep`=false (HyperOS: true). **Fix:** static RRO `PipaSettingsProviderOverlay` (target `com.android.providers.settings`, `config_lidControlsSleep=true`) in `my_product/overlay` + for existing data `settings put global lid_behavior 1`. Test the keyboard case folded behind does not trigger it. **Wiring (v1.2):** ColorOS's own switch `global device_case_enabled` (OplusDeviceCaseManagerService in exsystemservice) waits for an OPPO hall *sensor* (`Hall Sensor Not Found`) and does nothing on pipa; pipa_port sets `lid_behavior` = 1 while it is on, 0 while off (checked every 15 s, written on change), so the overlay is not needed. **Verified 2026-10-22 23:13** both ways (switch on → screen off on close, off → stays on); up to 15 s lag after flipping the switch (felt random). **v1.3 (live 23:18, maintainer: works):** sync triggered by the mtime of `/data/system/users/0/settings_global.xml` (stat per second while the screen is on, `settings get` only after a change): ~2 s lag. Helper 0.4 `LidKeeper` (built) cannot be installed as an update (`Persistent apps are not updateable`), ships in 2e. **2e:** helper `LidKeeper` with a ContentObserver on `device_case_enabled` (instant), helper moves to `priv-app` with `WRITE_SECURE_SETTINGS` in a privapp-permissions xml; the module poll goes. Details: `maintainer/bugs/B14-smart-cover.md` |
| B12 | Pen buttons do nothing in drawing apps (Xodo, OPPO Notes) (maintainer, 2026-10-22) | **fixed in beta5-2f (verified 2026-10-23)** | Android already classifies `Xiaomi Smart Pen Keyboard` as `EXTERNAL_STYLUS` and the panel as `BUTTON_FUSION` (vendor keylayout: 109 → `STYLUS_BUTTON_PRIMARY`, 104 → `SECONDARY`), but `secure stylus_buttons_enabled` was unset; with it set to 1 the buttons are merged into the pen's MotionEvents (`External Stylus Buttons Applied: 0x20/0x40`). Xodo: front (primary) = eraser while held; secondary is unused by Xodo; the button must be pressed before the tip touches (standard BT-stylus fusion). Also pipa_core's global actions fired over the app: device `keys.conf` now `pageup=120` (back button = screenshot), `pagedown=none`; maintainer copy `pipa_core/keys.conf` changed the same way (for v1.13). ROM: add `stylus_buttons_enabled=1` as a default. OPPO Notes still ignores them (OPPO BLE protocol, helper app). **beta5-2e regression (2026-10-23 23:50):** the back button stopped taking screenshots in the ROM service: `input keyevent 120` from `pen_keys.sh` failed with `cmd: Failure calling service input: Failed transaction (2147483646)` (FAILED_TRANSACTION, nothing in the AVC trace: OPPO's policy dontaudits it). `cmd` passes the caller's stdin/stdout/stderr to system_server over binder; inside the `getevent | while read` pipeline stdin is a pipe labelled `pipa_port`, which system_server may not use (the old ksu domain was allowed everything). **Fix:** `run_action … </dev/null >/dev/null 2>&1` (port-module/pen_keys.sh and port-rom/pipa_port/pen_keys.sh); verified live 23:49 (`rc=0`, screenshot saved) via a bind-mounted copy. **Fixed in beta5-2f (flashed 2026-10-23 00:00, maintainer: back button works).** Front button (STYLUS_BUTTON_PRIMARY) was fine: it is merged into the pen events by Android, no injection |
| B11 | Refresh rate never drops when idle, in 144 and 120 mode (maintainer, 2026-10-22) | **cause found, parked 2026-10-22** (revisit when the donor is final; a new donor may differ) | **Cause:** ColorOS's general idle drop is touch-idle OTI-HW: SurfaceFlinger asks OPPO's panel HAL `vendor.oplus.hardware.displaypanelfeature@1.0::IDisplayPanelFeature/default` (logs: `Cannot find entry … IDisplayPanelFeature/default in … VINTF manifest`, `Failed to get HIDL/IMMDisplayFeature Service`), which pipa lacks. Ruled out: OTI-SW is only a per-app request path for whitelisted video apps (`sw_whitelist_3rd`, `OtiAppRefreshRateRequest`); the AOSP SF idle timer runs (4000 ms) but ColorOS's SF `RefreshRateDirector` decides (with `refreshrate_director: false` the range opens to [0,144] but still no drop); `hw_enable: false` reaches SF (`TouchIdleBean mHwEnable=false`) without effect. Config: `my_product/etc/oplus_vrr_config.json` (`touch_idle` entry: timeout 2500 ms, lowest 60). Test bind used `/data/adb/post-fs-data.d/99-pipa-vrr-test.sh` (removed). No public port has a fix. **Options:** A) own `IDisplayPanelFeature` shim (proper, step-4 type work); B) interaction-based switching in the pen helper app (approach of https://github.com/mahmutaunal/Adaptive-Hz, MIT; it has no ColorOS support), using `secure oplus_customize_screen_refresh_rate` / `peak_refresh_rate` |
| — | Apps run at ≤120 Hz in the 144 Hz mode (maintainer, 2026-10-22) | **by design, keep (maintainer decision 2026-10-22: better for battery and performance)** | `my_product/etc/refresh_rate_config.xml` has per-app `rateId` rules for ~2 200 apps in the donor's 4 modes (auto-90-60-120); only 3 entries (e.g. `com.android.launcher rateId="3-2-2-3-4"`) have the 5th (144) field, so in 144 mode the home screen runs 144 and listed apps their OPPO rate (e.g. Spotify `2-2-2-1`). Generating a 144 column was considered and rejected |
| B6 | Refresh rate with the pen attached vs detached should behave like HyperOS (maintainer, 2026-10-22) | **fixed: beta5-2c (`ipePencilRateId="3"`) + power-tune v0.14 (sets `settings_enable_oppo_pencil` by dock state), verified 2026-10-22 21:20 incl. lockscreen**; v0.13's settings method lost on the lockscreen. Earlier: out of the dock → fixed 120 within ~1 s, docked → user setting, pen writes everywhere incl. the lockscreen. Findings: pen works only at **60 or 120 Hz** (not 144/90/30); dock = `fuda/reverse_chg_hall4` (0 = docked; kernel logs `hall4_irq_handler: pen attach/detach`; hall3 stays 1); ColorOS's own choice `secure oplus_customize_screen_refresh_rate` (8 = 144, 3 = 120) outranks `peak_refresh_rate`, so v0.13 sets it to 3 and restores it; only while the pen is connected over BT. | Earlier notes: **The panel senses the pen only at 120 Hz**: `dsi_panel_match_fps_pen_setting` logs every switch, and a 90 s `getevent` capture showed zero pen events in every 144 Hz period (incl. the ColorOS lockscreen, which runs at 144 = "pen dead on the lockscreen") and events within 1 s of each switch to 120. With `peak_refresh_rate` capped at 120 the lockscreen runs at 120. HyperOS (maintainer): pen docked = 30/60–144 Hz, pen out of the dock = 60–120 Hz. v0.11 `PEN_REFRESH_CAP`: dock = `fuda/reverse_chg_hall3`, connected = the pen's BT input device; out of the dock → peak 120/min 60, user values saved and restored. Also `PEN_PRESENT` sends the IPeManager present intent (MAC from `bt_config.conf`). Battery notification: `cmd notification` from root is silently dropped by ColorOS (`com.android.shell` channel disabled), so it needs a small helper app. Buttons: IPeManager raises `STYLUS_BUTTON_STATE_CHANGED` only from its OPPO BLE code (`btadsorb/ble/k0`); the Xiaomi keys arrive as HID `STYLUS_BUTTON_PRIMARY/SECONDARY` (vendor keylayout) that ColorOS ignores, so `pen_keys.sh` stays until a helper can inject ColorOS's own button path | later. The pen-present intent from B3 reaches `OplusSurfaceFlinger processPadFloorFPS` (`mIpePresent=1`). Lead: ColorOS ties pen VRR to `ipe_pencil_present` (`OplusFloorRefreshRateController`, `ro.oplus.vrr.pencil.support=1`), which never changes on pipa (B3); compare with what HyperOS does on pen attach/detach |

Details per item follow below as they are analysed.

## 12 Pen charging and pen battery in the OPPO live alert (wish, user, 2026-10-24)

**Wish:** the pen charging state and the pen battery level must show in the ColorOS live alert ("fluid cloud",
the pill at the top of the screen), not in the helper's own floating window.

**Now:** the pipa helper (`helper/`, B3) shows its own pill when the pen goes on or off the dock, and a notification at
15 % or less. The ColorOS pen UI (IPeManager) works only for OPPO pens.

**Offline analysis (2026-10-24, 2o images):**
- IPeManager (`my_product/priv-app/IPeManager`) has its own fluid-cloud pen card: `com.oplus.ipemanager.fluid.SeedlingCardProvider`
  on OPPO's Pantanal Seedling API (`com.oplus.pantanal.seedling`).
- `btadsorb/ble/k0.B0(level)`: if fluid cloud is supported (`btadsorb/util/w.d0`), it writes `sp_key_unic_battery_level`
  and `sp_key_pencil_seeding_card_type` to its preferences and calls `x3/c.g` (`UPK_IPeSeedlingCardManager`, "showBarCapsule")
  to push the card. It needs a pen MAC (`k0.u` → `l0.a`); else it logs `showFluidCloudBatteryCapsule mCurrentMacAddr null`.
  Without fluid support it uses the old window capsule (`IUIServiceControl.showBatteryCapsule`, `capsule_id_pencil_battery`).
- Callers of `B0`: `k0.h0(present, mac)` from `CoreService.d` ("pencilNodeChange", the pen-present path that the B3 intent
  reaches), `k0.W` (charging state from the OPPO BLE characteristic), a click handler, and a service connection.
- SystemUI does not show Android 16 live-update (promoted) notifications in the fluid cloud. Its
  `FluidReplaceNotificationManager` (`fluid_seeding_notification`, feature `oplus.software.fluid_replace_ntf`) only hides
  the notification of an app that already has a Seedling card. A card of our own would need the Pantanal Seedling SDK
  and a registration with Pantanal UMS (more work).

**Live test (2026-10-24 16:05, 2o):** present intent sent by hand, debug logs on (`persist.sys.assert.panic true`,
then set back to false; `ipe_pencil_battery_level` written for the test, then deleted).
- IPeManager reads the pen battery only from global `ipe_pencil_battery_level` (absent on pipa → -1). With 100 it logs
  `setWirelessPenSoc batteryLevel = 100, ConnectState 2`, but no card.
- `isPencilDeviceNameMatched deviceName = Xiaomi Smart Pen → matched = false`: only OPPO/OnePlus pen names are known
  (OPPO Pencil, Pencil 2/2R/2 Pro/3/3 Pro, OnePlus Pencil 2/Stylo …).
- `nodeChangeSamePencil` then tries the OPPO BLE GATT link: `doServicesDiscovered return invalid device address`. The
  card (`B0`) comes only after this OPPO BLE link works. **Result: IPeManager does not show the card for the Xiaomi pen
  without a code change.**
- Options: (A) patch IPeManager (smali: accept the Xiaomi pen and call `B0(level)` on present, with the level from the
  helper; the app must be re-signed, so its data is cleared once); (B) a Seedling card in the helper (Pantanal SDK not
  public; the protocol must be reimplemented); (C) keep the helper pill.

**Fix (2p, 2026-10-24):** `maintainer/ipe-fluid/patch_ipemanager.py` patches `k0.h0` in place (classes2.dex, same
size, OPPO platform signature block kept; Android does not verify system-partition APKs at boot, and re-signing would
lose the platform-signature permissions): the "new pen" branch reads `ipe_pencil_battery_level` and calls `B0(level)`;
P1 removes the "same present → return" check (else only the first present=1 after a present=0 shows the card); P2
sends the `B0(k0.L)` branch (OPPO BLE level) to the new code. pipa_port `PEN_FLUID` writes the level and sends
present=1 on each dock and undock; helper 0.5 skips its pill while `pipa_pen_fluid`=1. The capsule hides by itself
after a few seconds; IPeManager does not show it while its own pen page is in the foreground.
Not changed: the OPPO pen page (Settings → Stylus) shows "disconnected". It shows the state of OPPO's own BLE link
(`e0.getConnectState` → `l0.f`), which the Xiaomi pen never has (also before 2p).

**Old next steps (done):**
1. On the tablet: `logcat | grep -iE 'IPeManager|Seedling|FluidCloud'`, dock and undock the pen (the helper sends the
   pen-present intent). Look for `showFluidCloudBatteryCapsule` or `mCurrentMacAddr null`.
2. If the MAC is the block: give the pen MAC in the intent or in `ipe_pencil_mac_addr`, and the level in
   `ipe_pencil_battery_level`, then send the present intent again.
3. If the card shows: remove the helper's floating pill (keep the low-battery notification).
4. If IPeManager refuses a non-OPPO pen: plan B is a Seedling card from the helper (Pantanal SDK).

## B1 Wi-Fi sometimes does not turn on

Full analysis: `maintainer/bugs/B1-B2-wifi-navbar.md`. Nothing confirmed on a device yet.

**Setup:** QCA6390 on PCIe (`cnss2`). The vendor Wi-Fi stack (configs, supplicant, hostapd,
cnss-daemon) is the PixelOS/Lineage one, byte-identical; the HAL versions match the COS17 framework
matrix, and no OPPO Wi-Fi HAL is required. The wlan driver is in the kernel, loaded on demand.

**Cause candidates (ranked):**
1. **No recovery when the chip/firmware fails to start.** Verified in the images:
   - `vendor/etc/wifi/WCNSS_qcom_cfg.ini` has no `gEnableForceTargetAssert=1`. HyperOS stock
     (`vendor/etc/wifi/qca6390/WCNSS_qcom_cfg.ini`) has it, which lets the firmware crash be
     recovered by subsystem restart instead of leaving Wi-Fi dead until reboot.
   - ColorOS's own recovery, `sys.oplus.wifi.coldreset=1` → service `wifi_cool_reset`
     (`echo 2 > /sys/module/cnss2/parameters/pci_reset`), is declared with
     `seclabel u:r:su:s0`. The `su` domain only exists in debug builds, so on this user build init
     most likely cannot start it at all.
2. SELinux denials once `portenforce.rc` switches to enforcing; the port's policy has no Wi-Fi rules.
3. Users on other kernels: the ini/firmware layout follows Lineage (`qca_cld/`), not stock (`qca6390/`).
4. Lower: the donor Wi-Fi capability overlay (6 GHz, 11ax softap) may not match the chip.

**Capture on a failing device** (right after Wi-Fi refuses to turn on, before rebooting):
`logcat -b all -d | grep -i -E "wifi|wlan|cnss|supplicant|WifiHal|vendor.wifi"`,
`dmesg | grep -i -E "cnss|wlan|qca6390|pci"`, `ls /sys/class/net`,
`getprop | grep -i wifi`, `getprop init.svc.wifi_cool_reset`, AVCs (`device_capture.sh`).

**Fix ideas:** add `gEnableForceTargetAssert=1` to the vendor ini (vendor, low risk); give
`wifi_cool_reset` a real domain or replace it with a pipa init service (phase 2 policy work);
optionally a watchdog that triggers the cold reset if `wlan0` doesn't appear. Record the supported
kernel in the release notes.

## B2 UI drawn behind the navigation bar

Full analysis: `maintainer/bugs/B1-B2-wifi-navbar.md`. Needs device data before any fix.

**Findings:** the port overrides no navbar/taskbar/inset resources. Gestural navigation comes from
the Oplus overlay (`config_navBarInteractionMode=2`); a Lineage leftover
`ro.boot.vendor.overlay.theme` is still in `vendor/build.prop`. **Density disagrees** (verified):
`ro.sf.lcd_density=370` in system and my_product, `360` (+ `vendor.display.lcd_density=360`) in
vendor; HyperOS stock uses 400 on the same panel.

**Cause candidates:** Android 15/16 edge-to-edge enforcement with donor per-app policy; the launcher
taskbar not reporting correct insets on the 1800×2880 panel; default navigation mode / leftover prop;
navbar dimensions tuned for the donor's density.

**Capture:** which apps and which navigation mode (gesture or buttons, taskbar shown?), a screenshot,
then `wm size; wm density; settings get secure navigation_mode;
cmd overlay lookup android android:dimen/navigation_bar_height;
cmd overlay lookup android android:dimen/taskbar_frame_height;
dumpsys window | grep -A3 -i "InsetsSource"`.

**Fix ideas:** make the densities consistent (370 everywhere, or test 400 like stock); drop the
Lineage overlay-theme prop and set the navigation mode explicitly; if the inset values are wrong, test
a navbar-dimension overlay with `cmd overlay fabricate` (as in `aod_overlay_test.sh`) before baking an RRO.

## B3 Pen not shown while charging / no pen battery (live test 2026-10-22, beta5-baked)

Full offline analysis: `maintainer/bugs/B3-B4-pen-blur.md`.

**Hardware works.** With the pen attached: `fuda/reverse_chg_hall3=1`, reverse charging on
(`reverse_vout` 5580 mV, `reverse_iout` 139 mA), `wireless/reverse_pen_soc=100`,
`reverse_pen_chg_state=4`, `wireless/pen_mac=fb39144a40dc` (= the bonded "Xiaomi Smart Pen").

**Test.** As root:
`am startservice --user 0 -a com.oplus.ipemanager.action.PENCIL_STATUS_CHANGE -p com.oplus.ipemanager --es present 1 --es macAddr fb39144a40dc --es pencilId 1`
(this is what `OplusExSystemService` sends on the OPPO `oplus_wireless/pencil` uevent; all extras are
strings, `macAddr` must be the **raw kernel format without colons**: `FB:39:…` arrives as empty and
logs `pencilNodeChange invalid macAddr`).

**Result.** IPeManager sets `ipe_pencil_present=1`, `ipe_pencil_charging_state=1`,
`ipe_pencil_mac_addr`, `ipe_pencil_bt_device_name=Xiaomi Smart Pen`; Settings shows the stylus as
connected; `OplusSurfaceFlinger processPadFloorFPS` sees `mIpePresent=1` (B6 lead). No GATT
connection attempt was logged. Writing `settings put global ipe_pencil_battery_level 100` by hand shows
**no battery anywhere**: the capsule/card need IPeManager's own BLE GATT read (OPPO protocol).
Reverted with `--es present 0` and `settings delete global ipe_pencil_battery_level`.

**Fix plan.** A module watcher (screen-on poll or uevent on `power_supply/wireless`): on attach/detach
send the intent above with `present 1/0` (stylus status, likely the B6 refresh behaviour) and post an
own notification "Xiaomi Smart Pen · N % · charging" from `reverse_pen_soc` / `reverse_pen_chg_state`.
A shell `cmd notification post` works as a first version; a tiny app gives a proper icon and no root.

