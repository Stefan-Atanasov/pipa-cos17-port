# Known gotchas (moved verbatim from CLAUDE.md, 2026-11-14)

Read the matching entry before you act. CLAUDE.md has a one-line index.


- **C.06 boot hangs** (fixed in the ROM). C.06 waits for HALs that pipa does not have:
  `OplusEngineerFwService.getEngineerService()` calls `waitForService(IEngineer)` when `ro.adb.secure` is set, and
  `system_ext/{lib,lib64}/libupdateprof.qti.so` and `libtrigger-handler.so` use `waitForService` (QSPM). Each one
  stops system_server until its watchdog panics the device. Fixes: `patch_framework.sh` edit 4, and the four beta4
  libs through `PORT-EDITS.tsv`. On a new donor, scan the changed libs for new `waitForService` imports before you
  flash. To find the cause of a bootloop, read `/data/anr/traces_SystemServer_WDT*` (root ADB works during the
  loop) and `/sys/fs/pstore/dmesg-ramoops-0`.
- **OTA updater.** The ROM removes `com.oplus.ota`, `com.oplus.sau` and `com.oplus.sauhelper` (Settings then hides
  the entry). The update that they offered was a 262.30 MB app bundle for the donor model OPD2515, not for pipa. Do
  not install it: it can overwrite system apps that the port changed. Keep `com.oplus.romupdate`: it gets OPPO
  feature configs, not updates. The false "storage space is less than 262.30 MB" dialog came from a missing
  `/data/ota_package/OTA` (a ROM init rc now makes it; `notes/DEVICE-AUDIT-beta4.md` finding 11).
- **SELinux denials are in logcat (tag `auditd`) and dmesg** (WALT has `CONFIG_AUDIT=y`; the old "no audit core" note
  was from E404, and `avc_trace.sh` needs kprobes, which WALT does not have). The default audit rate (5/s) drops most
  denials: for a capture, `setprop persist.logd.audit.rate 2000` + `persist.logd.size 16M`, reboot, then set both back
  to "". **init checks property sets in user space and logs nothing for a permissive domain**, and a live
  `ksud sepolicy` rule does not reach init's cache: test property rules with a boot.
- **Services in the `pipa_port` domain: tools that use `cmd` (`input`, `am`, `settings`, `pm`, `cmd`) must not get
  your pipe or file as stdin, stdout or stderr.** They send these file descriptors to system_server over binder. If
  system_server cannot use the label of a descriptor, the call fails with `Failed transaction (2147483646)` and no
  log (dontaudit). Redirect all three to `/dev/null`.
  - So `$(settings get ...)` **cannot work** in the service (the output pipe is the problem). It returned the error
    text from 2e to 2r (Bedtime turned on at each boot). Read settings with `sget` in `service.sh`: `settings get` into a file in
    `/data/local/tmp` works (0.03 s CPU; `content query` also works but costs 0.28 s).
  - `dumpsys` fails in the service even into a file (`FAILED_TRANSACTION`). For the display rotation use
    `cmd display get-displays` into a file (`face_rotation_sync`).
  - **Test each new service command in the domain:** `su -c 'runcon u:r:pipa_port:s0 sh -c "<cmd> </dev/null
    >/data/local/tmp/x.txt 2>&1"'`, then read the file (2026-11-05: three silent failures found this way).
    `pm install <file>` needs the selinux_check_access rules of 5u (the cmd client checks system_server's access to
    the file; the APK must be `system_file`, not `/data/local/tmp`); `ime` finds no service (use `settings put secure
    default_input_method`); `getprop sys.user.0.*` (exported3_system_prop) reads empty.
- **A dirty flash never runs the setup wizard.** Test each release with a clean flash (wipe): beta7 removed
  FindMyPhone in 5f, and the setup wizard `com.coloros.bootreg` crashed in a loop without its provider (grey screen);
  dirty-flash tests and testers saw nothing. Read crashes from TWRP: `/data/system/dropbox/system_app_crash@*`.
- **Do not run a live `ksud sepolicy patch` on kernel walt-r8kpm (SukiSU 4.3 builtin).** On 2026-10-29 two live
  rules (an `allow` and a `dontaudit`) hung the big cores; the watchdog reset the tablet 20 s later (pstore:
  `Watchdog bark`, cpu alive mask 0f). Compile a policy change on the tablet with `secilc` and test it with a ROM build.
  2026-11-16 on walt-hi1: 6 live rules did not hang, but afterwards `secilc` could not execute even as root (EACCES)
  until a reboot. Run secil_test.sh on a clean boot.
- **Never replace `/data/adb/ksud`** (no wrapper, no switch). On 2026-10-23 a switch binary there stopped the boot at
  the Mi logo. Update ksud only together with a kernel that agrees with it, through the SukiSU manager.
- **If the tablet does not boot:** the boot image has TWRP 3.7.1 (Power + Volume up, or it starts after failed
  boots). TWRP ADB has root and `/data` is decrypted. Partition backups: `maintainer/kernel/flash_kernel.sh restore`.
- **Kernel images: pack only with `mkboot.sh`.** `magiskboot unpack -h`/`repack` changes the header patch level, and
  the bootloader then refuses the kernel with no message (black screen). For `fastboot boot` tests, use only trimmed
  images (`TRIM=1`): a full 196 MB image stopped the bootloader two times.
- **Own WALT kernel** (since 2026-10-23; now **walt-hi17** = v10, release image `boot-walt-hi17-su.img`: SukiSU Nova 3.0.0
  builtin, KPM off, susfs 2.3.0; v9 and v9.1 had walt-hi9, v9.2 walt-hi13, v9.3 walt-hi15; beta6 had walt-r8kpm (SukiSU-Ultra v4.3.0 + KPM), beta7 to beta7.2 had walt-r17, beta5 had walt-r6). The list below is the r3-r8 history. Lineage 24 core +
  liyafe's pipa drivers + E404 display and touch + SukiSU/susfs + OPPO UI First. r3: SurfaceFlinger on the top GPU
  ringbuffer. r4: SurfaceFlinger RenderEngine not on the little cores (`is_sf()`). r5: sysctl
  `kernel.ux_prefer_big`=1 (heavy UX threads on the big cluster), `kernel.frame_rate` default 120. r6: OPPO Hans app
  freezer channel (netlink 29, binder/signal/network reports, from the OPD2101 kernel); the `hans` daemon is exempt from
  the 5.10 uname spoof. r7ov: keyboard fix + `ovnet` (network sharing). r8: SukiSU 4.3.0. Rollbacks (in
  `port-work/kernel/bootimg/`): `boot-walt-r8.img`, then `boot-walt-r7ov.img` (manager 4.2.1-r1 for r6/r7).
  - Branch `own` in `port-work/kernel/walt-own`; branch `oppo` (what we flash) in the worktree `walt-oppo`.
  - Recipe, rebuild from zero (`maintainer/kernel/prepare_tree_walt.sh`; our commits are in `kernel/walt-own.bundle`,
    save it with `--save`), checks and updates: **`kernel/WALT-KERNEL.md`**. Evidence and A/B results:
    `kernel/KERNEL-RESEARCH.md`.
  - Build with `maintainer/kernel/build_walt.sh` (`DBG=1` = boot watchdog and lockup panics).
  - Never do `pkill -f build_walt.sh` from a command that contains that text: it kills the command itself. Do not
    edit `build_walt.sh` while it runs.
  - A 10 s push on the power key is a hard reset (pstore is lost). DBG builds do a warm reset themselves.
  - Android 17 does not mount schedtune. ColorOS uses the cpu cgroup and uclamp.
  - ColorOS boosts through the QTI perf HAL (WALT `sched_boost`), not through the power HAL.
  - `input tap` goes around the kernel input handlers. To measure touch boosts, use real touch (`maintainer/kgest`).
- **Idle drain and the keyboard guard (2j).** The nanosic driver makes its virtual "Xiaomi Keyboard" input devices
  also when no keyboard is attached. Thus an input-name check always says "attached". `pipa_port` (`KEYBOARD_GUARD`)
  asks the MCU (`echo 1 > /sys/devices/virtual/nanodev/nanodev0/_version176x`, `Connected=[1]`) and runs
  `xiaomi-keyboard` only then. Without the guard, the daemon's accelerometer loop keeps the SLPI awake and the SoC
  does not power-collapse. Keep this poll also with walt-r7: the r7 driver creates and removes the keypad devices from
  the hall status packet (0xA2), and the driver gets that packet only when `_version176x` is written (it never asks
  itself). Without the poll, a detach is not seen. Idle checks: `dumpsys batterystats` (wakelocks, wakeup reasons),
  `/sys/power/system_sleep/stats` (aosd/cxsd counts), `/sys/power/rpmh_stats/master_stats` (per subsystem, 19.2 MHz
  ticks).
- **OPPO sensor type numbers collide with Xiaomi's (2w).** ColorOS asks for OPPO's private sensor types (3317xxxx)
  with `getDefaultSensor(type)`. pipa's sensor HAL uses the same range for Xiaomi sensors. 33171001 (OPPO CCT) is
  absent (rerouted to Xiaomi 33171088 by `patch_framework.sh`). 33171038 (OPPO fold angle) is Xiaomi `knuckle`.
  33171037 is Xiaomi `screen_down`. A wrong match can run an expensive algorithm on the sensor hub all the time:
  `knuckle` kept the SLPI asleep only 1-40 % with the screen off (~50 mA in deep doze), fixed by
  `module/tools/patch_foldtouch.py`. To find such a drain: SLPI sleep in `/sys/power/rpmh_stats/master_stats`
  (19.2 MHz ticks, root), active sensors and their clients in `dumpsys sensorservice`.
  `dumpsys sensorservice restrict <pkg>` turns off all sensors at the HAL (an all-or-nothing test only;
  `dumpsys sensorservice enable` restores).
- **Live test of a framework jar:** copy the patched jar to `/data/local/tmp`, `chcon u:object_r:system_file:s0`, bind-mount
  it in init's mount namespace, then `setprop ctl.restart zygote` (worked on 2026-10-28; a reboot removes the mount).
  Since SukiSU 4.3 `nsenter -t 1 -m` is denied: use `su -M -c` (global mount namespace) with a script file, e.g.
  `/system/bin/mount -o bind <copy> <target>`. To remove a busy bind: `umount -l`.
- **SurfaceFlinger waits for OPPO display HALs (fixed in 2x).** C.06 `surfaceflinger` calls `waitForService` for
  `IMixLut3D`, `IDisplayColorFeature` and pixelworks `IIris` when a feature needs them (Game Filter: the main thread
  hangs, the picture freezes, touch is dead). `module/tools/patch_sf_waits.py` changes them to `checkService`. On a
  new donor, list the `bl <AServiceManager_waitForService@plt>` sites again (`llvm-objdump -d`). A frozen screen
  with working ADB: `debuggerd -b $(pidof surfaceflinger)` shows the blocked call.
- **A system binary that init starts as a service cannot be tested from `/data` by bind mount.** `/data` is
  `nosuid`, so SELinux refuses the domain change (`nosuid_transition`, e.g. init -> surfaceflinger) and the service
  does not start. Test such a binary with a ROM layer. (Jars and APKs work by bind mount.)
- **SurfaceFlinger properties go into `product/etc/build.prop`.** pipa's vendor build.prop sets HyperOS values (`-4 ms`
  offsets, `predict_hwc_composition_strategy=0`) and loads after system and system_ext.
- **UI First and SurfaceFlinger.** The UI First kernel keeps SurfaceFlinger off the little cores only while a
  sched_assist scene is set. On pipa nothing sets it (OPPO's vendor daemon does that on OPPO devices). Thus
  `pipa_port` `SF_BIG_CORES` writes `echo 384 > /proc/sys/kernel/sched_assist_scene` (bit 7 = SA_SCENE_OPT_SET; a
  write without it clears bits).
- Duration-model SF timing (`use_phase_offsets_as_durations=1`) stops SurfaceFlinger while a `*phase_offset_ns`
  property exists (the boot hangs).
- **Refresh rate (2o).** `my_product/etc/refresh_rate_config.xml` has per-app rules. 2o sets all app-wide rules to
  120 Hz in the Auto and 120 Hz modes. Per-activity rules (video players, live streams) stay as OPPO set them.
- **heavy_mix needs a thaw before gfxinfo (2026-11-02).** Android's cached-apps freezer (cgroup v2
  `apps/uid_*/pid_*/cgroup.freeze`) and Hans (`/dev/freezer/frozen`) freeze background apps within a second; a frozen
  app answers `dumpsys gfxinfo` with "Failure while dumping the app" (0 frames, INVALID). heavy_mix thaws both first.
  `kgest` finds the touchscreen by name: the event number changes (event8 -> event4 since walt-r9).
- **Smoothness measurement.** Use `maintainer/perfetto/traced_heavy.sh <label>` (FrameTimeline: SF on time,
  dropped, stuffing), not only gfxinfo. Wait 60 s after unlock. Do 2 runs or more. During a test series, set
  `svc power stayon usb`, and set `svc power stayon false` at the end.
  - `maintainer/heavy_mix.sh`: clean start, real touch through `maintainer/kgest`, apps, flings, shade, drawer.
    It taps fixed screen positions of the maintainer's home layout (icons, dock, a 600 ms hold). After a clean flash
    or any layout change it hits other icons and drags them (2026-11-18: user's fresh home screen rearranged). Ask the
    user and check the layout (screenshot of home) before a run.
  - Perfetto: `setprop persist.traced.enable 1` before you trace, and set it to 0 after. (2i and older: the donor's
    `traced.relay_producer_port=vsock://...` made `traced` crash; our kernel has no vsock.)
  - atrace "runnable" totals are too high because of atrace overhead. For scheduler numbers, use
    `maintainer/perfetto/ktrace.sh` (raw tracefs).
- **Sharing.** Kernel source: GitHub `kernel_xiaomi_pipa_cos17`, branch `oppo` (cherry-pick onto `pub/oppo` in
  `port-work/kernel/walt-own`, then `git push origin pub/oppo:oppo`). Port scripts and docs: GitHub
  `pipa-cos17-port` through `sh maintainer/sync_port_repo.sh "msg"` (no proprietary blobs, no signing key; it stops if
  it finds one). The repo also gets `docs/AGENTS.md` (public agent instructions: when you change a rule or gotcha here,
  change it there too) and `BUGS-TODO.md` as `BUGS.md`. Private kit for a co-maintainer: `maintainer/make_port_kit.sh`. User package:
  `maintainer/build_release.sh`. The scripts use `PIPA_ROOT` and `PIPA_OWNER`.
- **Patching a system app (APK).** Many OPPO system apps (for example IPeManager) are signed with the platform key.
  Do not re-sign them: they lose their platform-signature permissions. Android does not verify APKs on system
  partitions at boot (it only reads the certificate), so patch the dex **in place with the same size** in the original
  APK (the dex must be stored, not deflated), update only the zip CRCs, and keep the signing block
  (`maintainer/ipe-fluid/patch_ipemanager.py` is the model: pattern-based, stops on a different version). Delete the
  prebuilt `oat/` next to the APK.
  **Package cache:** the layers build with `mkfs.erofs -T0` (all file times 0) and keep the build fingerprint, so on a
  dirty flash Android's parse cache (`/data/system/package_cache`) keeps the old manifest data of a changed system APK
  (seen on 2p: helper code 0.5 runs, but the package manager showed 0.4). Since 2q, `early.sh` clears the cache when
  `ro.pipa.port.layer` changes. To test live: bind-mount the patched APK over the original in init's mount namespace
  (`nsenter -t 1 -m -- mount --bind ...`) and `am force-stop` the app; a reboot removes it.
- **A zygote restart (`setprop ctl.restart zygote`) is not a clean test state.** (The swap-file part is OBSOLETE since 6t/6v, pt94-pt96: OPPO's `nandswap` setup does not run again after a zygote restart (`sys.oplus.nandswap.init` guard) and `nandswap_dedup` is removed. Old text kept for pt18-pt93.) It sets `sys.boot_completed` again:
  OPPO's `init.oplus.nandswap.sh` attaches one more 8 GB swap file (its old file is deleted but stays open: /data
  fills up; 72 GB on 2026-10-29). 2q's `nandswap_dedup` removes the copies, but only since pt18 (3r/pt18 rules:
  `sys_admin` for swapoff, loop ioctls for `losetup -d`; before, both were denied). By hand: `swapoff` +
  `losetup -d` of each `loop` that `losetup` shows on `/data/nandswap/swapfile` and `/proc/swaps` does not list.
  Also, SystemUI warms up for minutes, so heavy-test runs right after it are worse than normal. Prefer a reboot, or wait
  5 minutes before you measure.
- **Do not edit `maintainer/port/port.sh` while a build runs.** `sh` reads the script in pieces: two inserted comment
  lines broke a running build with `syntax error near unexpected token` (2026-11-05). Step files are safe to add (each
  runs as its own process), but not the step that is running.
- **`/tmp` is a 7.8 GB tmpfs, and the build tools (baksmali in 5a and other jar steps) write to it.** A full `/tmp`
  stops a step with `No space left on device` although the SSD is free (2026-11-05: old session scratch folders,
  7.4 GB). Before a build: `df -h /tmp port-work`.
- **Layer scripts run with `set -e`, and `sh` ignores a failing negated command:** `! grep -q x file` checks nothing
  (2s had two such no-op checks). Write `if grep -q x file; then echo ...; exit 1; fi`.
- **A full SSD truncates `super.img` without an error (2026-10-28, 3d).** The layer scripts pipe `lpmake` through
  `grep -v ... || true`, so `sparse_file_write failed` / `No space left on device` is hidden and the md5 of the
  broken file is printed (6.1 GB instead of 6.8 GB). A flash of it was stopped in time. Since 3d the script stops
  below 20 GB free and on an `lpmake` error; copy that into each new layer. Before a build: `df -h port-work`.
- **A new fix is a new step file** in `maintainer/port/steps/` (`maintainer/port/README.md`). When it changes a system
  APK or jar, it must set a new `ro.pipa.port.layer` with `set_layer` (lib.sh): `early.sh` clears the package parse
  cache when the value changes.
- **A service name may have only ONE label in all `service_contexts` files** (plat, system_ext, product, vendor, odm).
  Two different labels stop servicemanager at boot (`SELinux: Multiple different specifications`, then a sysrq
  crash; pt29 bootloop 2026-11-03: the pipa vendor labels gameopt `oplus_absent_service`). Before a flash of a build
  that adds a service context, check all five files of the built images for a name with two labels.
- **Charging off is not a bypass on pipa (smb5).** With `battery_charging_enabled=0` the tablet runs mostly from the
  battery even on a wall charger. To hold a level or bypass, keep charging on and cap the charge current:
  `/sys/class/qcom-battery/restrict_chg=1` + `restrict_cur=100000` (0 and 50000 cut the input too). Steps 4p/4r
  service.sh `chg_hold`. Measure with `battery/current_now` (+ = discharge) and `usb/input_current_now`.
- **`setprop persist.<x> ""` does not delete a persistent prop.** It stores an empty value in
  `/data/property/persistent_properties`, and that value hides a `persist.*` default from build.prop at the next boot
  (4x test, 2026-11-03). After a live test, set the prop to the ROM value, not to "".
- **Our boot jar edits (3o framework.jar, 4h oplus-framework.jar) invalidate the donor's prebuilt boot image.** ART
  rejects it at runtime (artd: `dex file checksum ... does not match ... framework.jar`), but `odrefresh --check` says
  ok, so nothing rebuilds it. 4z removes the whole prebuilt boot image (`system/framework/{,arm,arm64}/boot*`); odrefresh
  then compiles one on /data at the first boot (odsign signs it). Removing only a part makes dex2oat abort at boot.
  After a failed compile odrefresh waits (`/data/misc/odrefresh/compilation-log.txt`, status 81) before it tries again.
  Artifacts from a manual `odrefresh --force-compile` are not signed: odsign deletes them at the next boot.
- **Do not start apps with `monkey -p <pkg> 1` in tests.** monkey injects a rotation event (rotation locked to 0 =
  portrait on pipa for ~100 ms): a rotation animation and composer errors that real launches do not have. Use
  `am start -n <pkg>/<activity>` or a real tap (`maintainer/kgest`).
- **mksh has an alias `r`** (`fc -e -`): a shell function named `r` in a tablet script does nothing.
- Do not kill `system_server` to apply framework changes. It causes `sysrq_trigwarmd_crash`. Reboot.
- The audio policy loads again when you restart `audioserver` (safe).
- **OPPO "opex" packages (`system_ext/opex/*.opex`) are signed.** Each one is a signed zip with an ext4 `opex.img` and its sha256 in `description.cfg`. init (`handle_opex_package`) loop-mounts it at `/mnt/opex/<pkg>@<ver>` and puts an overlay on `/system_ext/{framework,lib64}/oplusex/<pkg>`; the opex file wins over a plain file in that folder. Do not change the opex: ship the patched file in `/system_ext/pipa_port/` and bind-mount its folder from `pipa_port.rc` on `oplus.opex.done=1` (init may mount on `system_file` dirs, not on files). Example: step 5d (odmf.jar).
- **Never rename a vendor HAL library (2026-11-06, pt65 boot loop).** The sound trigger HAL dlopens
  `audio.primary.<ro.board.platform>.so` by name and calls its internal functions. A HAL wrapper must use a new name
  and be chosen through `ro.hardware.<class>.<inst>` (libhardware checks it first), e.g. 5w `ro.hardware.audio.primary=pipaaec`.
  A live swap after boot does not show such boot-time users: test HAL changes with a ROM build and a reboot.
- **`dump.erofs --ls --path=<missing>` returns exit code 0.** Check its output for "read inode failed".
- **Package cache between two test builds with the same layer (2026-11-05).** A dirty flash from a build to another
  build with the same `ro.pipa.port.layer` keeps Android's parsed manifest of a changed system APK (pt49 -> pt50: the
  helper's new `QUERY_ALL_PACKAGES` was missing). Users who come from an older release get a new layer, so only test
  flashes are affected. Fix: `su -c 'rm -rf /data/system/package_cache/*'` and reboot, or give the step a new layer.
- **App logs are muted on this ROM:** `persist.sys.assert.panic=false` (4h, against log spam) hides `Log.i/d` of apps
  (the helper logs nothing). For a debug session: `setprop persist.sys.assert.panic true`, restart the app; set it back
  to `false` (not "") after.
- **The helper and other apps' info:** Android 11+ package visibility hides other apps' `ApplicationInfo` without
  `QUERY_ALL_PACKAGES` (the game check saw every app as "not a game").
- **Live APK test by bind mount:** make the bind read-only (`/data/adb/ksu/bin/busybox mount -o remount,bind,ro
  <target>`; toybox fails with EBUSY). Else artd thinks the APK is on writable /data and fails to write its oat next to
  it (`cmd package compile` = Failure). Recompile the original after the unbind.
- **Xiaomi thermal scene:** `mi_thermald` picks its profile from `/sys/devices/virtual/thermal/thermal_message/sconfig`
  (`/sys/class/thermal/...` is a `sysfs` symlink). The `thermal-*.conf` files and the map are encrypted; the active
  profile is in `/data/vendor/thermal/decrypt.txt`. Map measured 2026-11-04 (HISTORY 23:15): -1 daily, 20/50 game
  (46 °C), 9/13/16 game (48 °C), 10/40 no limits (51 °C). Step 5l switches it for games.
- **OPPO app features** (`com.oplus.*` app-feature flags, e.g. the launcher blur gate) come from the
  `com.oplus.app-features.xml` files, loaded by system_server's AppFeatureProvider into `config_feature.db` at boot. A
  live test: `content insert --uri content://com.oplus.customize.coreapp.configmanager.configprovider.AppFeatureProvider/app_feature --bind featurename:s:<name> --bind 'parameters:s:boolean\:true'` + app restart (a reboot removes it).
- **Bootloader "Device does not support slots":** every slot getvar answers "not found" (seen 2026-11-02 and
  2026-11-04). `fastboot reboot bootloader` fixes it; `flash_super.sh` does that by itself since 2026-11-04.
- **SukiSU update (kernel + manager):** kernel first (walt-hi9 and later = SukiSU Nova 3.0.0 builtin since v9; r17 was SukiSU-Ultra v4.3.0-r1 up to beta7.2, `kernel/WALT-KERNEL.md`),
  then the manager APK (check the release sha256 and the signing cert against the installed one) with `adb install -r`.
  The manager carries its `ksud` as an obfuscated lib (`lib/arm64/lib<random>.so`, about 6 MB); the update runs
  `<that lib> install --libadbroot <manager lib dir>/libadbroot.so`, as the manager does. Save the old
  `/data/adb/ksud` first (`kernel/sukisu-v4.3.0/ksud-4.3.0-tablet-backup`).
- **KernelSU modules on SukiSU 4.3:** scripts and `system.prop` work; `system/` file overlays need a metamodule (none
  installed); `sepolicy.rule` modules use the live patch path (untested since the r8kpm hang).
- **SELinux compile test:** `maintainer/sepolicy/secil_test.sh <system_ext rules> <vendor rules>` on the tablet
  (push both files to /data/local/tmp): init flags exit code, then the neverallow count (76 = the donor base).
- **Gotchas from the Dolby work (2026-11-07, tester zip beta8, never released; in v9):**
  - Live-test a persistent priv-app or a static overlay without a build: bind-mount the new APK over the ROM file
    (`nsenter -t 1 -m -- mount -o bind ...`, keep the file label), `rm -rf /data/system/package_cache/*`, then
    `setprop ctl.restart zygote`. `adb install -r` refuses persistent apps. The bind ends at the next reboot.
  - Same `ro.pipa.port.layer` between two test builds = stale package cache: after the flash
    `rm /data/misc/pipa_port/pkgcache_layer` and reboot.
  - priv_app (MiSound, the helper) can never set a system property (`neverallow priv_app_all property_socket`):
    MiSound's `persist.audio.effect.device_map` stays empty; the helper keeps the per-output effect in its prefs.
  - MiSound's classes3.dex (added by the porter) holds stock `android.media.audiofx.AudioEffectCenter` and the effect
    presenters; they pick a default effect at BOOT_COMPLETED and on device broadcasts. The helper stores an effect
    only when MiSound is in the foreground (helper 1.6).
  - COUI preference lists show the children of a hidden `PreferenceCategory`; to hide ColorOS controls, leave them
    out of the overlay XML, but keep keys that a controller needs (`key_mss_spatial_render`, else Settings crashes).
  - A changed `vendor/etc/dolby/dax-default.xml` makes DMS rebuild `/data/vendor/dolby/dax_sqlite3.db` once (Dolby
    settings and the GEQ go back to default; the DB `signature` row is the xml md5).
  - Dolby tuning measurements: use pink noise, not sweeps (profile Dynamic has a leveler and adaptive EQ).
- **Gotchas from 2026-11-13:**
  - `adb shell "su -c 'a; b'"` with the inner quotes lost runs only `a` as root; quote the whole su command.
  - `pkill -f <pattern>` / `kill $(pgrep -f ...)` also matches your own shell when the pattern is in its command line:
    kill by PID.
  - Tablet Settings is two-pane (embedded activities): `uiautomator dump --windows` sees both panes; a second dump at
    the same time breaks a running walk. Section titles with parentheses break mksh heredoc scripts (quote them).
  - `cmd overlay fabricate` needs root (`su -c`); fabricated overlays stay after a reboot until disabled/removed.
- **Run smali/baksmali with `-j 1`.** With threads, the dex layout changes on each run (same code, other md5).
- **Refresh tests need a full reboot (2026-11-14, BUGS 110/36).** After `setprop ctl.restart zygote` OPPO's touch idle
  drop (panel -> 60 Hz) stops, so a live config swap must be tested after a real reboot: bind-mount the test files from
  an early-boot script (`/data/adb/post-fs-data.d/*.sh`, KernelSU runs it), then reboot. Files bind-mounted over
  /my_product need `chcon u:object_r:system_file:s0`; edit the source with `su -c 'cat new > src'` (same inode).
  The two-pane Settings top page is package `com.oplus.wirelesssettings`, not com.android.settings. Measure the panel
  with `dumpsys SurfaceFlinger | grep activeMode` (physical rate). The VRR service tells SF the USB-debugging state
  (transaction 23017, dumpsys oplus_vrr_service "AdbDebugState").
- **Refresh mix generator:** `maintainer/refresh/mix_refresh.py <pre-2o xml> hyperos_pipa_fps.txt <out>` (OPPO rules +
  stock HyperOS pipa smart list; fixed modes = selected rate for all apps). Data from stock PowerKeeper/Joyose assets.
- **Memory values belong to OPPO's scripts (2026-11-14, 6t).** OPPO's `init.oplus.nandswap.sh` and Qualcomm's
  `init.qcom.post_boot.sh` raced: the last writer won swappiness, `watermark_scale_factor` and zram. The porter odm
  `mm-sys.sh` hid OPPO's `main()`. 6t removes `mm-sys.sh`, so OPPO's `main()` runs (zram 5632 MB zstd on 8 GB, 3072 MB
  lz4 on 6 GB). Post_boot no longer writes swappiness, wsf or zram. lmkd values are in the odm `build.prop`. Do not add a
  second writer for these values.
- **Live zram A/B tests with `swapoff` distort the result (2026-11-14).** `maintainer/mem_zram.sh` changes zram live. The
  `swapoff` is slow and leaves the memory in another state. Compare zram settings with reboots.
- **`flash_kernel.sh` and "GetVar Variable Not found" (2026-11-14).** The bootloader sometimes cannot answer a getvar. The
  script refuses and writes nothing. Reboot to Android and flash again from adb.
- **OPPO kernel code under `CONFIG_DRM_MSM` is dead on pipa (2026-11-15, r25/r26).** `CONFIG_DRM_MSM` is unset and
  `msm_drm_register_client` is a stub, so a screen-off notifier never fires (r25 gate compiled out). Use `mi_drm`
  (`drm_notifier_mi.h`, `CONFIG_DRM`). r26 does this for the hybridswapd screen-off gate.

- **OplusLauncher layout follows the boot density (2026-11-17, BUGS 125).** `wm density` changes apps, not the home grid. Test launcher spacing only after a flash or reboot with a changed `ro.sf.lcd_density`.

- **Port OTA (2026-11-26, BUGS 193, skill pipa-ota).** One channel: `latest.json` names only SourceForge releases; test builds go to testers by hand. update_engine trusts only `my_engineering/etc/security/otacerts.zip` (port key, step 9c); without that file it would skip the signature check. A delta applies only to the exact source build (error 20 otherwise): keep `img/` of published builds. The pipa_port loop skips checks while the screen is off: an install request starts at the next screen-on. After the Virtual A/B merge the old slot is unbootable (back = PC flash). Live service test: bind-mount a copy; to change it, `cat` as root into the same file (adb push fails on the root-owned copy); stop the service before `umount` (busy).
