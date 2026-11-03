# Donor init services on pipa: what runs, what it needs, what it costs

- **Donor:** OPD2515 C.07 (`system/system/` and `system_ext/` only).
- **Date:** 2026-11-03.
- **Method:** static only. No device. Parsed all `service` blocks in `system/system/etc/init/*.rc` (71 files) and
  `system_ext/etc/init/*.rc` (81 files): 479 services. Followed every `start`/`restart`/`enable` in an `on` block to find
  triggers. Read donor props in `system/system/build.prop` and `system_ext/etc/build.prop`. Ran `readelf -d`, `readelf --dyn-syms`
  and `strings -n 6` on each daemon. Read the pipa side from `KERNEL.md`, `BUGS.md` (rows 19, 60), the port steps and the
  `cloud/hal-inventory` note. No code was disassembled.
- **Tags:** [seen] = read in a file. [inferred] = conclusion from strings or imports. [unknown] = needs a device or a file that the
  donor copy does not hold (`vendor`, `odm`, `my_*` props and rc).
- **Limit:** props in `vendor`, `odm`, `my_*` build.prop are not available. A gate that I could not find there is marked [unknown].

## 1. How the list was made

- 479 services. About 430 have `disabled`. A `disabled` service starts only when an `on` block starts it.
- 25 services start with their class (no `disabled`). 10 of them are AOSP (`servicemanager`, `vold`, `lmkd`, `keystore2`,
  `surfaceflinger`, `audioserver`, `cameraserver`, `installd`, `logd`, `storaged`, ...). They are out of scope.
- Triggers that fire on pipa [inferred]: `post-fs`, `post-fs-data`, `boot`, `early-boot`, `zygote-start`, `sys.boot_completed=1`,
  `bpf.progs_loaded=1`, and `persist.*` values that the donor `build.prop` sets (list below).
- Donor gate props found in the two build.prop files [seen]: `persist.sys.midasd.enable=1`, `persist.sys.oiface.enable=2`,
  `persist.sys.horae.enable=1`, `persist.sys.ostatsd.enable=1`, `persist.sys.ostats_pullerd.enable=1`, `persist.sys.ostats_tpd.enable=1`,
  `persist.traced.enable=1`, `sys.oplus.cvt.manager=1`, `persist.oplus.zygote_c.enable=true`, `persist.oplus.zygote_ocomp=false`,
  `persist.sys.hardcoder.name=oiface`, `persist.sys.debuglog.config=stability`.
- Port sets `persist.sys.assert.panic=false` (step 4h) [seen]. That fires the `=false` branch of the debug triggers
  (`inittpdebug`, `resetlogpath`, `qmilogoff`, `oplus_dump_selfcure`, `oplus_dump_netconfig`). All are `oneshot`. One run per boot.
- Not set in the two files, so the gate is [unknown]: `persist.sys.dft_process.status` (olc and gaia start), `sys.osense.mem_pressured.enable`
  (`mempressured`), `persist.sys.midas_ostats.restriction`, `persist.sys.midasd.start`, `persist.sys.ostatsd.start`,
  `persist.oplus.theia.enable_suspend_resume_monitor`, `persist.sf.vsync.*`, `persist.sys.boot_monitor.mode`.

## 2. Table

Cost scale: none, low, medium, high. "pipa has" follows `KERNEL.md` and `BUGS.md` row 60: only `/proc/oplus_scheduler`,
`/proc/oplus_frame_boost`, `/proc/oplus_binder`, `/proc/oplus_qos_sched`, `ux_flag`, and the Hans netlink 29 channel exist.
HAL state follows `HAL-INVENTORY.md`: `charger`, `cryptoeng`, `touch` are shimmed. `gameopt`, `transmessage`, `handlefactory`,
`cwb`, `misc`, `oplusSensor`, `urcc`, `olc2`, `displaypanelfeature` are missing.

### 2.1 Long-running OPPO daemons (can loop or hold a thread)

| service | binary | trigger/gate | restart | needs (missing on pipa) | predicted on pipa | cost | fix |
|---|---|---|---|---|---|---|---|
| horae | `/system_ext/bin/horae` | `sys.boot_completed=1` and `persist.sys.horae.enable=1` [seen]; class hal, user system | none set: restarts on exit (5 s) | `/proc/shell-temp` [seen missing, BUGS 19c], `/proc/oplusVersion/{prjName,pcbVersion,prjVersion}`, `/sys/class/oplus_chg/battery/battery_type`, `displaypanelfeature` HAL, `/odm/etc/horae/*.conf` [unknown on pipa odm]; has `ICharger` (shimmed), `IPerformance` (present) | degraded: logs "/proc/shell-temp missing" every 5 s [seen BUGS 19c] | medium (5 s wakeup, log spam, CPU wake) | set `persist.sys.horae.enable=0` (port step, system_ext build.prop); mi_thermald already does thermal control [seen BUGS 19c]. Check that no framework thermal path needs horae |
| midasd | `/system_ext/bin/midasd` | `sys.boot_completed=1` and `persist.sys.midasd.enable=1` [seen] (also `=2`, `persist.sys.midasd.start=1`, `persist.sys.midas_ostats.restriction=0`); class hal, user system, `SYS_NICE` | none set: restarts on exit | `/proc/oplusVersion/prjName`, `/proc/oplus_healthinfo/{dstate,sched_latency}`, `/proc/oplus_power/top_process`, `/sys/class/oplus_chg/battery/*` (cc, fcc, rm, soh, chip_soc), `/sys/devices/virtual/oplus_chg/{battery,usb}/*`; HALs `handlefactory`, `cwb`, `cammidasservice` (missing); `charger` (shimmed, `waitForService`), `performance` (present) | degraded or blocks: it waits for `ICharger` [seen import]; shim must be up. `com.oplus.midas` app crash seen (BUGS 19a). Loop unknown | medium | measure first. Then set `persist.sys.midasd.enable=0`. Check the `com.oplus.midas` app and battery stats still work |
| ostatsd | `/system_ext/bin/ostatsd` | `sys.boot_completed=1` and `persist.sys.ostatsd.enable=1` [seen]; user system | restarts on exit | `/proc/oplusVersion/prjName`; `libofm`, `liboplusdcs`, `ocenter-aidl` (donor libs, present); sensorservice client | degraded, loop [unknown] | low to medium | `persist.sys.ostatsd.enable=0` |
| ostats_pullerd | `/system_ext/bin/ostats_pullerd` | `sys.boot_completed=1` and `persist.sys.ostats_pullerd.enable=1` [seen]; user root | restarts on exit | HALs `handlefactory`, `cwb` (missing); `charger`, `touch` (shimmed); statsd pull API | degraded, loop [unknown] | medium (root, statsd pulls) | `persist.sys.ostats_pullerd.enable=0` |
| ostats_tpd | `/system_ext/bin/ostats_tpd` | `sys.boot_completed=1` and `persist.sys.ostats_tpd.enable=1` [seen]; user system | restarts on exit | `libofm`, `libcommon_dcs_service` only (present) | works, idle [inferred] | low | keep, or `persist.sys.ostats_tpd.enable=0` with the other two |
| oiface | `/system_ext/bin/oiface` | `sys.boot_completed=1` and `persist.sys.oiface.enable=2` [seen]; class hal, user root, `SYS_NICE`; `persist.sys.hardcoder.name=oiface` [seen] | restarts on exit | `gameopt` HAL (missing, `waitForService` [seen in HAL-INVENTORY]); nodes `/proc/oplus_frame_boost/sys_ctrl`, `/proc/oplus_scheduler/sched_assist/ux_task` (pipa HAS both); `/sys/class/oplus_chg/battery/aging_ffc_data` (missing); `charger` (shim), `performance` (present), `oplus_project` (present) | blocks: the daemon waits for `gameopt` and never serves. Zero CPU. OPPO "hardcoder" requests get no answer [inferred]. Port `early.sh` already sets `oiface_fg*` cgroups [seen] | low (idle) but the feature is dead | keep for now. Option: a `gameopt` no-op shim (14 methods) so that oiface starts and uses the frame_boost and sched_assist nodes that pipa has. Decide after a measured gain |
| oplus_gaia | `/system_ext/bin/oplus_gaia` | class main, user root; socket `postmand` 0666 [seen]. Also started by `persist.sys.dft_process.status=true` [unknown] | restarts on exit | `transmessage` HAL (missing, `waitForService`); `olc2` (missing); `/proc/shell-temp`, `/proc/oplus_secure_common/oemLogEncrypt`, `/proc/oplus_storage/io_metrics/ioLatencyStat` (all missing) | blocks at start [inferred]: socket `postmand` is open but nobody accepts. PostmanService clients may wait [unknown] | low CPU, risk of a blocked client | keep. A `transmessage` shim (6 methods) is cheap if a client hang shows. Device check below |
| oplus_theias | `/system_ext/bin/oplus_theia` | no class (default), starts at boot; socket `theia_socket` 666 [seen] | restarts on exit | `libocenter`, `libcommon_dcs_service`, `libolc` (donor libs). Writes `/data/persist_log/theia*`. No HAL name found | works or degraded [inferred] | low | keep. Check log size under `/data/persist_log/theia` |
| qsguard | `/system_ext/bin/qsguard` | class late_start, user system, cap `KILL` | restarts on exit | surfaceflinger/composer: watches `/vendor/bin/hw/vendor.qti.hardware.display.composer-service` [seen string]; `/sys/class/backlight/panel0-backlight/brightness`; props `persist.sf.vsync.*` [unknown values] | works, but it holds a vsync watchdog that can write `/proc/sysrq-trigger` or ask for a reboot by property [seen strings]. False trigger on a pipa display stall is possible [inferred] | low CPU, reboot risk | keep. Check `/data/misc/user/0/qsguard/qsguard_log` for "Detect Screen freeze" |
| criticallog | `/system_ext/bin/criticallog` | class main, user system | restarts on exit | `/sys/kernel/oplus_mm/osvelte/common/{enable_bad_proc,add_bad_proc}` (missing); `oplus_project` HAL (present) | degraded: write fails, logs [inferred] | low | keep |
| atlasservice | `/system_ext/bin/atlasservice` | class main, user root, `SYS_NICE` | restarts on exit | `libatlasservice` uses `/sys/class/kgsl/kgsl-3d0/snapshot/*` (SM8250 has kgsl) | works [inferred] | none | keep |
| mmlistservice | `/system_ext/bin/mmlistservice` | class main, user root | restarts on exit | only `libmmlistservice` | works [inferred] | none | keep |
| vendor.perfservice | `/system_ext/bin/perfservice` | class main, user system (Qualcomm QSPM; rc has `swapon_all` on `ro.vendor.qti.per_boot_created=1`) | restarts on exit | registers `vendor.perfservice`, `vendor.qspmsvc` in servicemanager; HIDL thermal 1.0/2.0 | works [inferred]; pipa HyperOS has the same Qualcomm daemon | none | keep. Sepolicy has `vendor_perfservice` (cil line 150) |
| boot_monitor_service | `/system_ext/bin/boot_monitor_service` | `post-fs-data`; user system; socket `boot_monitor_service`; reads `persist.sys.boot_monitor.mode`, `sys.oplus.phoenix.handle_error` | restarts on exit | no lib deps | works [inferred]. Phoenix rescue needs kernel `phoenix` (missing, BUGS row 60) so no rescue | none | keep |
| oplus_trace | `/system_ext/bin/oplus_trace` | `sys.boot_completed=1` and `persist.traced.enable=1` and `persist.sys.oplus_trace=""` or `1` [seen]; class late_start, disabled | restarts on exit | libbinder only | works, idle [inferred] | none | keep |

### 2.2 OPPO one-shots that start on pipa (one run per boot)

| service | binary | trigger/gate | restart | needs (missing on pipa) | predicted on pipa | cost | fix |
|---|---|---|---|---|---|---|---|
| oplus_kevents, bsp_kevent | `/system_ext/bin/oplus_kevent`, `bsp_kevent` | class late_start, no `disabled`; oneshot | oneshot | kernel generic-netlink family or `NETLINK` OPPO kevent channel (missing) [seen strings "get_family_id err, use netlink"] | degraded: exits after one failed socket [inferred] | none | keep, or `disabled` |
| oplus_mm_configure | `init.sys.oplus.mm.post_boot.sh` | `sys.boot_completed=1`; oneshot | oneshot | writes `/proc/sys/vm/watermark_scale_factor` (16 to 60) and `watermark_boost_factor` (0 or 15000) by RAM size [seen script] | works. Overrides port memory tuning | low, but behaviour change | check the values after boot; compare with BUGS row 46 |
| oplus_f2fs_ufs_tune | `oplus_f2fs_ufs_tune.sh apply` | `boot`; oneshot | oneshot | `/proc/devinfo/ufs` (missing: script uses its default branch) [seen]; writes f2fs `min_ssr_sections`, `min_fsync_blocks`, `ipu_policy` on userdata | works, applies OPPO defaults to pipa f2fs [inferred] | low, storage behaviour change | check `/sys/fs/f2fs/*/min_ssr_sections` |
| oplus_kswapd_profile | `oplus_kswapd_profile.sh` | `sys.boot_completed=1`; oneshot | oneshot | `/proc/oplus_mem/kswapd_load_stat` (missing) | no-op [inferred] | none | keep |
| opluscvtmanager | `/system_ext/bin/opluscvtmanager` | `sys.boot_completed=1` and `sys.oplus.cvt.manager=1` [seen in build.prop]; caps `SYS_ADMIN NET_ADMIN`; oneshot | oneshot | `/sys/fs/bpf/oplusbpf`, `/sys/kernel/btf/vmlinux` [seen strings]; BTF in port kernel [unknown] | degraded or works [unknown] | low | check SELinux denials and `init.svc.opluscvtmanager` |
| ofm-service | `/system_ext/bin/ofm-service` | `post-fs`; oneshot | oneshot | `oplus-feature` config only | works [inferred] | none | keep |
| hans | `/system_ext/bin/hans` | `sys.hans.enable=true` (set by framework); class core | restarts on exit | netlink 29 channel: pipa kernel HAS it [seen KERNEL.md] | works [seen BUGS item 16, KERNEL.md] | none | keep (`getprop sys.hans.enable` = true) |
| Other boot one-shots | `PmicHistoryClear`, `oplus_last_boot_reason`, `supersize` script, `logd-auditctl`, `do_replace_splash_logo.sh`, `onbootlog`, `readdump`, `autochmod.sh`, `cotad boot_mount` | `post-fs-data` or `sys.boot_completed=1`; oneshot | oneshot | `oplus_project` HAL (present) or none | work or fail once [inferred] | none | keep |
| loc_sys_service | `/system_ext/bin/loc_sys_service` | `early-boot` | oneshot | GNSS | disabled by the port (step 12, 2j) [seen] | none | done |

### 2.3 Services that look OPPO but do not start (checked)

`mempressured` (needs `sys.osense.mem_pressured.enable=true`, unset), `oplusHmbirdBpfManager` (needs `sys.oplus.hmbird.manager.enable=1`; the
rc also needs `ro.kernel.version` 6.12 or 6.18; KERNEL.md says apps see 5.10, so it probably does not start) [inferred], `dpmd`, `tcmd`, `aisealhostservice`,
`pmgd` (`pmgd` is `disabled`, enabled at boot_completed [seen]: AOSP-like, `user nobody`), `theia_screen_monitor` (needs `ICwbService`, blocks;
requires `persist.oplus.display.fold.support=""` and `cwb.display_id=0` [seen]; value on pipa [unknown]), `oplus_suspend_resume_monitors`, `oplus_net_bpfloader`
(starts on `bpf.progs_loaded=1`, oneshot, disabled: it does start when bpf loads [seen], needs `/sys/fs/bpf/oplusbpf` [unknown]).
`zygote_c` starts (`persist.oplus.zygote_c.enable=true` [seen]; it needs `persist.oplus.zygote_c` [unknown]). `zygote_ocomp` and `zygote_tango` do not.

## 3. Ranked list of costly services (highest first)

1. **horae** (medium). Wakes every 5 s and logs the missing `/proc/shell-temp` [seen, BUGS 19c]. Fix: prop off.
2. **midasd** (medium). OPPO battery and power daemon with six missing node trees and three missing HALs. Loop or log spam possible [unknown].
   Needs a device count before a decision. Fix: prop off after a check.
3. **ostats_pullerd + ostatsd** (medium). Statsd pullers that need `handlefactory` and `cwb`. One runs as root. Fix: props off. `ostats_tpd` can stay.
4. **oiface** (low cost, high lost value). It blocks on `gameopt`. No battery cost. Option: `gameopt` no-op shim, because pipa has the
   `frame_boost` and `sched_assist` nodes that oiface uses.
5. **oplus_gaia** (low). Blocks on `transmessage`. Risk: a client that waits on socket `postmand`. Option: `transmessage` shim.
6. **qsguard** (low CPU, high impact if wrong). A vsync watchdog that can reboot the tablet. Watch its log.
7. **criticallog, kevents, kswapd_profile** (low). Failed writes, one log line each.
8. **oplus_mm_configure, oplus_f2fs_ufs_tune** (low). They work, but they change vm and f2fs tunables on pipa. Check the values.

Props on pipa that may restart loops (non-oneshot service, exit when a node or HAL is missing): horae, midasd, ostatsd, ostats_pullerd,
criticallog, oplus_gaia. None is proved. A restart loop at 5 s would show as a high `init.svc_debug_restart_count`.

## 4. Fix plan and device check (costly services)

Common method: add a port step (`maintainer/port/steps/NN-<name>.sh`) that appends the prop to `system_ext/etc/build.prop`
(model: step 4h, `persist.sys.assert.panic=false`; use `forbid_grep` before and `need_grep` after). A `persist.*` line in build.prop is only a
default. A value stored in `/data/property` wins, so test on a clean flash. To stop one service only, a step may add `disabled`
to its rc (model: step 12 on `loc_sys_service.rc`). Note: `class_start` ignores a `disabled` service, but the `on property` trigger in
the same rc still starts it, so a prop change is cleaner than an rc edit for the triggered daemons.

| service | fix | device check |
|---|---|---|
| horae | `persist.sys.horae.enable=0` | `getprop init.svc.horae` (expect empty or stopped); `logcat -d -b all \| grep -i horae`; `getprop init.svc_debug_restart_count.horae`; `dmesg \| grep "init: Service 'horae'"` ; wakeups: `/sys/power/rpmh_stats/master_stats` before and after |
| midasd | measure first; then `persist.sys.midasd.enable=0` (keep `persist.sys.midas_ostats.restriction` unset) | `getprop init.svc.midasd`; restart count; `logcat -d \| grep -iE 'midasd\|MidasD'`; `dumpsys battery`; check the `com.oplus.midas` app |
| ostatsd / ostats_pullerd | `persist.sys.ostatsd.enable=0`, `persist.sys.ostats_pullerd.enable=0` | `getprop init.svc.ostatsd`, `init.svc.ostats_pullerd`; logcat tags `ostatsd`, `ostats_pullerd`; `dmesg \| grep "init: Service .* exited"` |
| oiface | keep; later `gameopt` shim | `getprop init.svc.oiface` (running, but `ls /dev/socket` has no oiface socket = blocked); `debuggerd -b $(pidof oiface)` shows the blocked call; `logcat -s oiface` |
| oplus_gaia | keep; later `transmessage` shim | `getprop init.svc.oplus_gaia`; `debuggerd -b $(pidof oplus_gaia)`; logcat tag `GAIA`; `PostmanService` ANR in `/data/anr` |
| qsguard | keep | `cat /data/misc/user/0/qsguard/qsguard_log`; `getprop init.svc.qsguard`; `dmesg \| grep -i sysrq` |
| all | one scan for loops | `for s in $(getprop \| grep -o 'init.svc_debug_restart_count\.[^]]*' \| sort -u); do echo $s; done`, or `dmesg \| grep "init: Service .* exited"` after 10 min; `logcat -b all -d \| awk '{print $6}' \| sort \| uniq -c \| sort -rn \| head` to find the top log tags |

Note: `init.svc_debug_restart_count.<name>` exists only in some init builds [unknown]. If it is absent, count the `exited` lines in dmesg.
Use `su -c` for dmesg and `/sys/power/rpmh_stats` (AGENTS.md).

## 5. Port already handles

- `loc_sys_service`: `disabled` added to its rc (steps 1c and 2j) [seen].
- Charger, cryptoeng, touch HALs shimmed (`midasd`, `oiface`, `ostats_pullerd`, `horae` import `ICharger`; `ostats_pullerd` imports `IOplusTouch`) [seen].
- Hans kernel channel (`hans` works) and the OPPO scheduler/frame_boost/binder/QoS nodes [seen KERNEL.md].
- `persist.sys.assert.panic=false` (step 4h): turns debug-log branches off.
- `oiface_fg*` cgroups in `pipa_port/early.sh`; QoS prop `ro.oplus.osense.uaf_qos_enable=true` (step 4n) [seen].
- `surfaceflinger` waits, `engineer` wait, sensor type reroute (steps 2x, 2w) [seen AGENTS.md].
- Not handled: `horae`, `midasd`, `ostats*`, `oiface` block, `oplus_gaia` block, `qsguard`, `criticallog`, `kevents`. No step or doc names them
  (grep of `maintainer/port/steps/*.sh`, `port-rom/`, `*.md`), except BUGS row 19(c) for horae.

## 6. Open questions

1. Do `vendor`, `odm`, `my_*` build.prop on pipa set or override the gate props above (`midasd`, `ostats*`, `oiface`, `dft_process`,
   `persist.sf.vsync.*`)? The donor copy does not hold them. [unknown]
2. Does the port kernel have `CONFIG_DEBUG_INFO_BTF` (`/sys/kernel/btf/vmlinux`) and `/sys/fs/bpf/oplusbpf`? `opluscvtmanager` and `oplus_net_bpfloader` need them.
3. Do the daemons exit (restart loop) or only log when a node is missing? Static scan cannot say. Needs the restart-count check on a device.
4. Does a framework thermal or fan path depend on `horae` (it has a fan-control module, `FanSmartControl` strings)? Pad 6 has no fan, but
   a `setprop` of 0 must not change `thermalserviceext` behaviour. [unknown]
5. What does the OPPO `hardcoder` client in the framework do when `oiface` never answers (retry, log spam, delay)? Needs logcat.
6. Does `PostmanService` (or another client) block on the `postmand` socket while `oplus_gaia` waits for `transmessage`?
7. `vendor.perfservice` and `vendor.qspmsvc`: does the pipa vendor also define an init service with the same name? Init would ignore the later definition. [unknown]
8. `qsguard` reboot policy: which property selects it, and what is its value on pipa?
9. Is `ro.kernel.version` on pipa 6.12 or 6.18? It gates `oplusHmbirdBpfManager`. KERNEL.md says apps see 5.10. [unknown]

## Review note (2026-11-03): fix the cause, do not switch daemons off

Direction of the maintainer: a daemon that does useful work on ColorOS gets the parts it needs on pipa (a shim or a
kernel node). Turning it off (`persist.sys.*.enable=0`) is only a last choice, for a daemon that cannot do anything
on this hardware. So the fix column above is a fallback. The plan:

| Daemon | What it does | Real fix |
|---|---|---|
| `horae` | OPPO skin temperature and thermal model. Reads `/proc/shell-temp`, `/proc/oplusVersion/*`, `/proc/chip/*`, GPU load (`kgsl`), battery current, backlight, `qpt` power. | Kernel: a small proc driver for `/proc/shell-temp` from the pipa skin thermal zones (and `/proc/oplusVersion/prjName`). Check the format that horae parses first. |
| `oiface` | Game booster (frame boost, key threads). | `gameopt` shim that maps to the port kernel `sched_assist` (`ux_state`, `im_flag`) and `frame_boost`. |
| `midasd`, `ostatsd`, `ostats_pullerd` | Power and health statistics (battery history, app power use in Settings). | Check which nodes and HALs give user-visible data (battery usage pages); provide those (shim or kernel node). |
| `oplus_gaia` | Waits for `transmessage`. | Check what it serves (`postmand` socket clients); a `transmessage` shim if a feature needs it. |
