# COS17 port: stability and performance plan (beta5 and later)

Date: 2026-10-22. Scope: ColorOS 17 donor C.06 + the port's vendor/odm/kernel (carried from beta4) on pipa
(SM8250, 8 GB, 144 Hz LCD). Goal from the maintainer: as stable as the HyperOS port or stock, then smoother.

Method: static diff of `reference/{cos17,hyperos1-stock,iqraos3.1,pixelos}` plus the existing audit docs
(`README.md`, `PATCH-INVENTORY.md`, `MAINTAINER-STATUS.md`, `PORT-MAINTAINER.md`) and
`reference/device/pipa_core/`. **No device was touched.** Everything marked *(guess)* is a hypothesis;
everything marked *(data)* needs a read-only device capture first (commands in section 4).

Legend: R = risk of the fix (L/M/H). "ROM" = vendor/odm/system image rebuild; "module" = `pipa_cos17_power_tune`.

---

## 0. What the diffs say in one page

1. **`vendor` is a Lineage/PixelOS vendor, not the HyperOS one.** `init.qcom.post_boot.sh` is byte-identical to
   PixelOS (`8c7ba1fb…`), not to HyperOS/iqraos (`79f8df95…`). All CPU governor, core_ctl, WALT, bw_hwmon and
   cpufreq parameters in the `kona` case are identical to stock; the differences are only in the **memory
   block** (section 2.1). Power HAL is Lineage libperfmgr (IPower v7) *and* the stock QTI perf HAL 2.2 runs too.
2. **SELinux has never been observed.** README/inventory contain zero `getenforce` / AVC captures. `pipa_core`
   turns on `susfs enable-avc-log-spoofing 1` at post-fs-data, so AVC denials are **hidden from the very logs
   you would use to find them** (`reference/device/pipa_core/post-fs-data.sh`). Every SELinux item below is
   therefore *(data)*. Roadmap row 1 below is to switch that off for one capture session.
3. **PATCH-INVENTORY item D15 (`init.fg.protect.rc-qcom`) is not a failing service.** `product/etc/init/init.fg.protect.rc-qcom` ends in `.rc-qcom`; init only
   reads `*.rc`, so the file is inert. (The `qvirt*` rcs are `disabled`, also inert.) Drop D15 from the risk list.
4. **U2 is partly explained.** `pipa_core/post-fs-data.sh` ends with: "GPU / charging tiers are now set by
   vendor `thermal-*.conf` (MONITOR-GPU, MONITOR-BAT trigger temperature raised by 10 C overall)". So the 32
   edited encrypted thermal files very probably contain **+10 C trip points on GPU and battery monitors**
   (strong inference from the author's own comment; contents not decrypted).
5. beta5 already fixes: `zz_portdebug.rc` dropped (`maintainer/c06-vs-beta4/PORT-EDITS.tsv` line 32, DROP `zz_portdebug.rc`), `ro.secure/ro.adb.secure/ro.debuggable`
   restored (verified in `port-work/beta5/tree/system/system/build.prop`), `dontaudit` rules not deleted,
   `ro.build.tablet_type=pad` baked in. plain beta5 still has `persist.sys.facehal.verbose=true` (fixed in beta5-baked, R12),
   `has_wide_color_display=false`, `has_HDR_display=false`.

---

## 1. Stability

### 1.1 Triage table (every known or likely source)

Status column: **K** known/observed on device, **L** likely (strong static evidence), **H** hypothesis.

| ID | Item | St | Evidence | Impact | HyperOS / stock / iqraos handling |
|---|---|---|---|---|---|
| ST1 | SELinux: permissive boot, flipped to enforcing by `portenforce.rc`; denials hidden by susfs (U3) | L | `vendor/etc/init/portenforce.rc` (`write /sys/fs/selinux/enforce 1` on `sys.boot_completed=1`); `pipa_core/post-fs-data.sh` `susfs enable-avc-log-spoofing 1`; `oplus_hal_odm.rc` header: "SELinux labels below are generic ... only works while SELinux is permissive" | After the flip, any domain relying on permissive silently loses access (perf HAL, stability HAL, face, subsys). Failures look like random feature breakage with no AVC in logcat. Also a security hole if the flip never happens | Stock boots enforcing from the kernel cmdline; HyperOS has proper `*_exec` labels for all HALs |
| ST2 | Enforcing-boot deadlock root cause unknown (U3) | H | Author: vold waits for IKeystoreService, keystore2 never registers, keymaster never comes up, no AVC. Later fix `allow tee oppo_block_device blk_file` (S22) was found after the note, so the deadlock may already be solved | The device boots permissive for the whole boot: keystore, vold, init services run unconfined until boot_completed | Stock: no deadlock; qseecomd reads `ssd` partition under a pipa label |
| ST3 | Precompiled sepolicy hashes mismatch (U6) | K | `odm/etc/selinux/precompiled_sepolicy.plat_..sha256 = 61a4556e…` vs `system/etc/selinux/plat_sepolicy_and_mapping.sha256 = ff615285…`; system_ext `69d1a826…` vs `bb3a2e0a…`; product `d080e3d0…` vs `3797d004…`. HyperOS/iqraos odm hash `f8fbdc3e…` | init compiles the full policy at every boot (secilc). Costs boot time and is the *only* reason the port's cil edits take effect. Not itself a crash. A beta5 rebuild keeps all three mismatching | Stock ships a matching precompiled policy |
| ST4 | `subsys_daemon` runs only because `pipa_core` starts it as root (U5) | K | `odm/etc/init/subsys_daemon.rc` comments out `qti-modem-daemon-*`; `pipa_core/post-fs-data.sh` lines 98-123 start both slots with nohup; avc spoofing hid the original denial | Clean flash or `pipa_core` removal: `ISubsys` / `ISubsysRadio` HALs missing, communication/network sharing dead, framework retries | Not applicable on HyperOS (no virtual modem). Original failure was `/dev/diag` EACCES in `hal_radio_default` *(per author, unverified)* |
| ST5 | `subsys_radio` VINTF: slot1 declared V9, slot2 V8, shipped lib V8; `override="true"` for `android.hardware.radio@1.5 vircommslot1/2` and `ims@1.7` with no process registering them (U7) | L | `odm/etc/vintf/manifest/network_manifest.xml` lines 29-52; `odm/lib64/vendor.oplus.hardware.subsys_radio-V8-ndk.so` | Possible `UNKNOWN_TRANSACTION` for V9-only calls (comm sharing), telephony waiting on `vircommslot*` HIDL services (log spam / delays, *guess*). Boot is not affected | n/a (donor-ODM artifact) |
| ST6 | Face HAL: rc has `disabled`, no `interface aidl` line, no exec label; runs from `/data` as root via `pipa_core` (U4/R2) | K | `vendor/etc/init/android.hardware.biometrics.face-service.facehal.rc`; `crop_eyes` SIGSEGV tombstone; 1 Hz `ctl.interface_start` spam (README #2) | Face unlock dead after any crash; 1 log line/s while down | Stock HyperOS has a signed face HAL under init. Module `FACE_WATCHDOG=1` is the stop-gap |
| ST7 | `com.pipa.faceunlock` retry loop (R4) | K | 350 stack traces / 3 s in README #4; app is in `system/app/FaceUnlock` | Log spam, CPU wake every 3 s while awake | n/a |
| ST8 | `xiaomi-keyboard` 6 Hz accelerometer loop (R1) | K | README #1 | Dominant idle drain; 100 log lines/s | HyperOS uses event-driven `keyboardnanoapp` HAL |
| ST9 | `AodBacklightDaemon` 300 ms poll (R3) | K | README #3 | Wakeups while screen off | n/a |
| ST10 | `traced` crash loop (no `CONFIG_VSOCKETS`) | K | `pipa_core/post-fs-data.sh` end: init restarted traced every 5 s, 88 times in 500 s. Mitigated by `resetprop persist.traced.enable 0` in the module | Wakeups + tombstones if `pipa_core` absent. **Check it still holds on C.06**, whose perfetto binaries changed | Stock kernel has vsock |
| ST11 | `AudioxService.t()` retry every 3 s (`ro.oplus.audio.effect.type=audiox_merge`, no Audiox lib) | K | README bug sweep | Log spam while awake; small CPU | HyperOS has no Audiox |
| ST12 | `OplusBatteryService getDataFromHalByOldInterface` ~every 11 s; charger shim in `pipa_core` | K | README #6; `chargershim.jar` | Wrong charger info + log spam. Shim is a root `app_process` restarted by a shell loop | Stock: native charger HAL |
| ST13 | `com.oplus.midas` boot crash `NumberFormatException: "show"` in `QualityProtectService.c` (R7) | K | README #7. No prop `=show` anywhere in `build.prop`s; my guess is a donor `/proc` or `/sys` node that the port kernel lacks (read returns text) | One-shot crash dialog-less; harmless but shows up in crash buffers and `dropbox` | n/a |
| ST14 | Kernel noise from missing OPLUS kernel features: `SchedAssist binderSetThreadUxFlagByIoctl` ~230/min, `hybridswap_swapd_pause` x2 /20 s, `HybridSwap pidMap empty` | K | README bug sweep | ~300 log lines/min, wakeups from `PerformanceService` / Athena. Also means OPPO's UX-thread boosting is absent (performance, section 2) | n/a |
| ST15 | `persist.sys.facehal.verbose=true` still in plain beta5 `system/system/build.prop`; fixed in beta5-baked (R12) | K | beta5 tree grep | Log volume only when HAL alive | n/a |
| ST16 | Health HAL declares `IHealth` v4, binary links `health-V5-ndk` (U12) | L | `vendor/etc/vintf/manifest/android.hardware.health-service.qti.xml` (`<version>4</version>`); inventory D1 | Boots fine on beta4. Risk is a framework that requires >=v4 features only with V5 *(guess: none seen)*. Keep | Stock: health@2.1 HIDL |
| ST17 | `/data` fstab lost `age_extent_cache,compress_mode=user,compress_cache` | K | `diff hyperos1-stock/vendor/etc/fstab.qcom cos17/...` | Less f2fs compression/extent cache; matches kernel feature set, neutral | Stock has them |
| ST18 | Dangling services: `nqnfcinfo, ptt_socket_app, ssgqmigd, qvop-daemon, qseeproxydaemon, esepmdaemon` (non-disabled, binary missing) and `rusWifiBootCheck` (script missing) | K | scan of every `*.rc` against the image (this audit) | One init error line each at boot; no function lost | Stock has the binaries |
| ST19 | `qvirt*` / `fg.protect` / `rf_ddr_aging` rcs from donor product | K | all `disabled` or `.rc-qcom` suffix | **None** (inert) | n/a |
| ST20 | `com.android.vending` restart loop, 176 OPPO-family packages | K | README #8 | Memory + wakeups. Beta5 PORT-EDITS debloat removes 15 apps only | Stock: 30 fewer system apps |
| ST21 | LLKD / hung_task | L | `system/etc/init/llkd.rc` is donor-native and gated on `ro.llk.enable`/`ro.khungtask.enable` (default off, `ro.debuggable=0`). beta4 additionally had `zz_portdebug.rc` (hung_task_panic=1 at 60 s, softlockup_panic=1, panic=20): any 60 s D-state (UFS stall, f2fs GC, swapfile on loop) rebooted the tablet | **beta4 spontaneous reboots under I/O stalls are plausibly this file.** Dropped in beta5 | n/a |
| ST22 | Stale `/data/ota_package/OTA` (R11) and OTA apps (`com.oplus.ota`, SAUHelper, RomUpdate) still present | K | README #11 | User can install a donor SOTA bundle and brick port apps | Disable in ROM |
| ST23 | Root-daemon sprawl in `pipa_core` (face HAL, subsys, charger shim, AOD jar, pen loop), each a shell `while true` respawn loop | K | `pipa_core/service.sh` | Everything is a single point of failure on `/data/adb/modules`; after a data wipe nothing starts until the module is reinstalled | n/a |

### 1.2 Per-item fix plan

| ID | Concrete fix (file / partition) | Needs data? | Risk |
|---|---|---|---|
| ST1/ST3 | Add proper domain/labels for `vendor-oplus-hardware-performance-V1-service` and `...oplus_project-V1-service` in `vendor/etc/selinux/vendor_file_contexts` (currently `oplus_project` is `vendor_hal_perf_default_exec`; the performance one has no entry) and matching `allow` in `vendor_sepolicy.cil`. Drive the rule list from a real AVC log, not from guesses | **Yes** (section 4, cmd D1-D3) | M |
| ST2 | After D1-D3 show a clean enforcing log, run one controlled test: boot beta5 with `androidboot.selinux=enforcing` (boot image cmdline) and capture `pstore`/`last_kmsg`. If it boots, delete `portenforce.rc`. Keep rollback to the permissive-boot image ready | Yes | H (bootloop) |
| ST3 | Optional: regenerate `odm/etc/selinux/precompiled_sepolicy` + the 3 `.sha256` files from the final cil set on the host (`secilc` from the AOSP build tools) so init skips the on-device compile. Do **not** copy HyperOS's precompiled policy (would drop all pipa-port rules). Gain: boot time only *(guess: 1-3 s)* | No | M (wrong hash = same as now; wrong policy = no boot) |
| ST4 | Add a `hal_radio_default` (or new) allow for `/dev/diag` (`chr_file`, `vendor_qti_diag_device`), label the daemon, re-enable the commented `qti-modem-daemon-0/1` triggers, drop the pipa_core start. Test only after AVC capture shows the exact denial | Yes | M |
| ST5 | In `odm/etc/vintf/manifest/network_manifest.xml` set slot1 to `<version>8</version>` to match the shipped library. Remove the `override="true"` HIDL radio/ims stanzas if telephony logs show waits for `vircommslot*` | Yes for the radio part (D6) | L |
| ST6 | Add `interface aidl android.hardware.biometrics.face.IFace/default`, exec label + camera/GPU rules in vendor sepolicy; ship the HAL in `/vendor`. Fix `crop_eyes` ROI clamping upstream. Until then keep `FACE_WATCHDOG` | Yes (AVC) | M |
| ST7 | Remove `system/system/app/FaceUnlock` from the beta5 tree (add `remove` row to `maintainer/c06-vs-beta4/PORT-EDITS.tsv`). Module already disables it | No | L |
| ST8 | Bake the keyboard gate in ROM: change `vendor/etc/init/hw/init.device.rc` line 18 `start xiaomi-keyboard` to a property trigger, started by a tiny uevent watcher or the module. Or restore `vendor.xiaomi.hardware.keyboardnanoapp@1.0` from HyperOS (needs its HAL, blobs and vintf) | Keyboard test | M |
| ST9 | Replace the `aod_bl.jar` polling loop with a sysfs write on doze enter (`dumpsys`-free); or accept the module's SIGSTOP gate | No | L |
| ST10 | Bake `persist.traced.enable=0` / `persist.device_config.global_settings.sys_traced=0` into `vendor/build.prop` instead of a module `resetprop`; check `init.svc.traced` on C.06 | D4 | L |
| ST11 | Set `ro.oplus.audio.effect.type=` (empty) in `system/my_product/build.prop` and delete `oplus.product.features_audiox.xml` entries. Untested, README says clearing at runtime did not stop the service | Yes (test boot) | L |
| ST12 | Implement the legacy `getDataFromHalByOldInterface` path in the shim, or add `vendor.oplus.hardware.charger` stub to the ROM | No | M |
| ST13 | `logcat -b crash` stack + `strings` on the caller to identify the node; stub it in the module or silence via the property it reads | D5 | L |
| ST15 | `persist.sys.facehal.verbose=false` in `system/system/build.prop` | No | L |
| ST18 | Delete the dead `service` blocks (or leave; cosmetic). Not worth a rebuild alone | No | L |
| ST20/22 | Extend the debloat list; `pm disable-user com.oplus.ota` for the OTA trio (MAINTAINER-STATUS roadmap row 1); pre-create `/data/ota_package/OTA` in an init rc | No | L |
| ST23 | Long term: move subsys/face/charger to proper init services (ST4/ST6/ST12) so the module becomes optional | Yes | M |

### 1.3 U-items not in the table above

| ID | Assessment |
|---|---|
| U1 | Fixed in beta5. Verify on device: `cat /proc/sys/kernel/hung_task_panic /proc/sys/kernel/softlockup_panic /proc/sys/kernel/panic` should print 0 / 0 / kernel default, and `ls /metadata/port` empty/absent (D7). |
| U2 | See ST-U2 below. |
| U8 | `ro.surface_flinger.has_wide_color_display=false` and `has_HDR_display=false` exist in both `vendor/build.prop` and `system/system/build.prop`; HyperOS sets neither (SF default), PixelOS sets both true. Author turned `wcg_2.0_support` off for "colour temperature wrong" (2026-10-13). Trade-off, not a bug. Leave until the colour module work (M6) is finished. |
| U9/U10/U12/U13/U14/U15/U16 | Cosmetic or feature-level; no stability link seen. |
| U17 | Fixed in beta5. Side effect: first ADB connection needs RSA approval; the TCP-5555 workflow in README needs one USB authorise first. |

**ST-U2 thermal (important, safety + perf).**
- Evidence: 32 of 43 `thermal-*.conf` differ from HyperOS (and from PixelOS which equals HyperOS); `thermal-engine.conf`, `-map*`, `-chg-only`, `-huanji` are identical. Same length, shared prefix of 320-1232 bytes, then different. `pipa_core` comment says the temperature of `MONITOR-GPU` and `MONITOR-BAT` was raised by 10 C.
- Test result already in README: `mi_thermald` never wrote a frequency cap; prime core sat at ~85 C regardless. So CPU throttling is by the SoC's own limiter, not these files.
- Impact: battery (charge-current tiers) and GPU tiers kick in 10 C later than Xiaomi designed. For a tablet with a big battery this is a **wear and safety margin issue under sustained charging+gaming**, not a boot issue.
- Fix: (a) decide whether to keep the +10 C; (b) to *see* the real values without decrypting: `dumpsys android.hardware.thermal.IThermal/default` (HAL thresholds) and `cat /sys/class/thermal/thermal_message/*`. The decrypt key lives in the Xiaomi thermal userspace (`mi_thermald` / thermal client lib) *(guess)*; decrypt on host and diff, then restore stock for the battery monitor at least. Revert path is trivial: copy the 32 files from `hyperos1-stock/vendor/etc/`.
- Also: `dumpsys thermalservice` showed CPU0..4 at 60-70 C while raw zones were 26-31 C (README #10). That is the thermal HAL (`android.hardware.thermal-service.qti`, thermal-legacy-um) reporting through a zone-name map; needs D8 to decide if the map is wrong or the numbers are thresholds.
- R: L to restore stock; M to keep +10 C. Needs data: D8.

---

## 2. Performance and smoothness

### 2.1 Comparison matrix (vendor/odm/system vs HyperOS stock vs iqraos3.1)

iqraos3.1 equals HyperOS for every item in the "stock" column below (md5-identical `init.qcom.post_boot.sh`, perf XMLs, vendor build.prop sections), so one column covers both.

| Area | HyperOS stock / iqraos | cos17 (port) | Evidence | Effect (smoothness / battery) | Suggested value |
|---|---|---|---|---|---|
| **vm.watermark_scale_factor** | **60** for pipa (`MIUI MOD` branch) | **1** | `init.qcom.post_boot.sh` last `configure_memory_parameters` lines; odm `init.oplus.mm-sys.sh` never sets it | wsf=1 leaves almost no gap between low and high watermark: kswapd wakes late and stops early, so allocations hit **direct reclaim** more often. With an 8 GB zram-backed system that is the classic cause of UI hitches when memory fills. Plausible top smoothness fix *(guess on magnitude; data D9)* | 60 (stock). Write it in `apply_vm_params()` of `odm/etc/init.oplus.mm-sys.sh` |
| **zram size** | `RAM/2` capped at **4096 MB**, default comp algo (lz4 for low_ram only), `use_dedup` | **8192 MB lz4**, plus 8 GiB loop swapfile prio 2020 when `persist.sys.oplus.nandswap=true` (it is set `true` in a build.prop) | `odm/etc/init.oplus.mm-sys.sh` `init_zram()` (`MEM_TOTAL <= 8388608` -> 8192); inventory U11 | zram is 100 % of RAM; compressed pages can eat >1 GB of RAM, shrinking page cache and background-app headroom. Doing `swapoff` + reset of an in-use zram at boot_completed can stall for seconds (guess). Swapfile adds flash writes | 4096 MB (stock) or 6144 MB; keep lz4. Make nandswap opt-in (default `persist.sys.oplus.nandswap=false`) unless the user wants it |
| **swappiness** | **180** in `configure_memory_parameters` (pipa branch; kernel allows >100) and 140 for `bg` memcg (`init.qcom.rc` line 78) | 100 (odm script re-applies 5x every 30 s) | stock `init.qcom.post_boot.sh` line 1085; `init.qcom.rc` | Not an outlier (stock is higher). The README line "swappiness=60" is the vendor script default which the odm script overrides. | Keep 100; consider 140-180 only after wsf and size are fixed and PSI is measured |
| `page-cluster` | 0 (3 first, then 0 in kona branch) | 0 | scripts | none | keep 0 (README mentions 3: check live, D9) |
| `watermark_boost_factor` | 0 for <=8 GB | 0 | script | none | keep |
| `min_free_kbytes` | not set by script | 23168 (odm script, THP off, `compaction_proactiveness=0`) | `init.oplus.mm-sys.sh` | fine; matches OPPO | keep |
| **ART heap tuning** | `heapgrowthlimit=256m, heapsize=512m`, product: `heaptargetutilization=0.5, heapminfree=2m` | `heapgrowthlimit=384m, heapsize=512m`; **no** `heapstartsize/minfree/maxfree/targetutilization` anywhere (ART defaults: 8m / 512k / 8m / 0.75) | grep over all build.props; root `/build.prop` comment: "OPPO normally overrides it from their vendor/odm" | ART defaults mean more frequent, smaller GCs on a tablet; 384m growth limit lets one app crowd the others and hurts LMK. PixelOS vendor uses `startsize 16m, minfree 8m, maxfree 32m, targetutil 0.5` | `dalvik.vm.heapstartsize=16m`, `heapgrowthlimit=256m` (or 320m if apps OOM), `heapminfree=2m`, `heapmaxfree=32m`, `heaptargetutilization=0.5` in `vendor/build.prop` or `system/build.prop` |
| LMKD props | `ro.lmk.use_minfree_levels=true`, `kill_heaviest_task`, `kill_timeout_ms=15` | none (lmkd defaults, PSI) | grep | OPPO's own memory framework (Athena/hybridswap) is partly dead on this kernel, so lmkd defaults rule. Needs live PSI data | measure first (D9) |
| **Power HAL** | Xiaomi `android.hardware.power-service` + QTI perf HAL 2.2 | Lineage `power-service.lineage-libperfmgr` (IPower v7) **and** the same QTI perf HAL 2.2 | `vendor/etc/init/*power*`, bin/hw list | Two boost paths. libperfmgr is a Pixel-style hint table with no Xiaomi tuning | see next rows |
| `powerhint.json` INTERACTION | n/a | little min 1612800 kHz, big min 1574400, GPU min idx 3, BW hysteresis 0, `sched_prefer_spread=2` | `vendor/etc/powerhint.json` | Every touch holds the little cluster at 1.6 GHz and the big at 1.57 GHz. Smooth but expensive: a battery drain whenever the user scrolls or taps; with `peak_refresh_rate=144` this runs ~always while reading | if battery matters: little min 1075200, big min 1286400 (both exist in the node `Values` lists) |
| `powerhint.json` LAUNCH | n/a | 5 s: all clusters min = max (`9999999`), `GPUForceClkOn/RailOn`, L3 min 1.6 GHz, DDR floors | same | App-open stutter is reduced, but 5 s pinned at max triggers the SoC limiter (85 C seen) and burns battery | duration 5000 -> 2000 ms |
| `powerhint.json` EXPENSIVE_RENDERING | n/a | **port-added** (differs from PixelOS): CPUBW/LLCC/L3 floors at max in addition to cluster mins at max | `diff cos17 pixelos powerhint.json` lines 829-858 | While SF flags expensive composition, DDR + L3 are pinned. Likely the single heaviest "hint" for battery | remove the 5 added actions (restore PixelOS) unless a jank case justifies them |
| `DOUBLE_TAP_TO_WAKE` default | n/a | `DefaultIndex` 1 (on) | diff line 351 | none | keep |
| **vendor `init.qcom.power.rc` (Lineage)** | not present | sets schedutil `up_rate_limit_us=500`, `down_rate_limit_us=20000` on all 3 policies at `vendor.post_boot.parsed=1`; cpuset top-app 0-7, foreground 0-6, background 0-1; DT writes `/dev/stune/*` | `vendor/etc/init/hw/init.qcom.power.rc` | Stock leaves 0/0. Down limit 20 ms = frequencies decay slowly (helps jank, costs battery). `stune` paths do not exist on A17 (inventory item 9) so ~20 writes fail every boot; `scheduler cfq` write to `sda` also likely fails | keep 500/20000 for smoothness; delete the stune and `cfq` lines (cosmetic). Measure `/sys/block/sda/queue/scheduler` (D10) |
| CPU governor / core_ctl / WALT / bw_hwmon | `kona` case | identical (same script text) | `diff` of the `kona` branch is empty | none | none |
| `ro.vendor.perf-hal.ver` | **2.2** | **3.0** | `hyperos1-stock/vendor/build.prop:616`, `cos17/vendor/build.prop:351`; HAL, lib and client are the stock 2.2 files (md5 equal) | client library may try a 3.0 API against a 2.2 HAL (boost calls silently dropped) *(guess; data D11)* | set `2.2` |
| perf XMLs (`etc/perf/*`, `perfboostsconfig`, `targetconfig`, ...) | stock | byte-identical to HyperOS | md5 compare | none | none |
| ORMS / oplus perf | n/a | donor `persist.sys.orms.name=ORMS`; OPPO `IPerformance` HAL (from the "power-key fix package") started in `oplus_hal_odm.rc`; kernel nodes absent (SchedAssist ioctl fails ~230/min, no hybridswap) | README bug sweep | OPPO's UX-thread priority boost and scene boosts cannot work without the OPPO kernel; the HAL just logs. The donor framework still spends CPU calling it | no ROM fix; only a kernel with OPLUS sched hooks would change it |
| **uclamp / cpuset** | task_profiles use `UClampMin/Max` on 4.19 stock kernel | same attribute set in ColorOS `task_profiles.json` | `etc/task_profiles.json` both | If the port kernel lacks `cpu.uclamp.*` (not verified), ADPF hint sessions and top-app boost do nothing | data D12; if missing, rely on `init.qcom.power.rc` cpuset + governor params |
| **Refresh rate** | 60/90/120 (`default_fps=60`, `idle_default_fps=50`, `mode_change_optimize`, `touch.idle.enable`, `smartpen_vrr_fps`) | vendor lacks all `ro.vendor.display.*` fps/idle props; SF: `set_idle_timer_ms=4000`, `set_touch_timer_ms=4000`, `set_display_power_timer_ms=1000`, `use_content_detection_for_refresh_rate=true`; ColorOS `refresh_rate_config.xml` (donor, per-app rateId mapping capped at 120, 144 only via "extreme" mode) and `oplus_vrr_config.json` (`adfr_enable:false`) | `vendor/build.prop`, `system/my_product/etc/*` | Auto mode picks 120 Hz, the 144 Hz setting is a user choice (`peak_refresh_rate=144`). At 144 Hz fixed with `sys_dynamic_frame_config` `targetFramerate=120` animations are driven at 120, so some animations still render at 120 | for battery: keep default Auto (120); for 144: accept per-app table; no ROM change needed. Validate the idle drop (D13) |
| `debug.sf.*` phase offsets | same -4 ms / +1 ms values (AOSPA) | same | build.prop | `latch_unsignaled=1`, `enable_gl_backpressure=1` same as stock | none |
| `vendor.display.use_smooth_motion` | 0 | 1 | build.prop | enables QTI smooth-motion path; no known issue; PixelOS has 0 | keep or set 0 for parity (L) |
| `vendor.display.enable_allow_idle_fallback`, `disable_idle_time_*`, `ro.surface_flinger.max_frame_buffer_acquired_buffers=3` | absent | present | build.prop | triple buffering with 144 Hz; fine | keep |
| `/vendor/etc/display/advanced_sf_offsets.xml` | present (48/40 % at 120/144 Hz) | **absent**; nothing in the port's libs reads it (grep) | find | none (feature not in port SF) | none |
| **HWUI / renderer** | default `skiagl`; `ro.hwui.use_vulkan` empty; HWUI caches texture 72 MB, layer 48, path 32 etc. | `debug.hwui.renderer=skiavk` and `ro.hwui.use_vulkan=true` in vendor; same cache sizes as stock in `system/system/build.prop` | vendor/build.prop, pipa_core comment ("HWUI Vulkan baked into vendor 2026-10-11") | Vulkan renderer on Adreno 650 with a **hand-patched `vulkan.adreno.so`** (40-byte cMetaOffset patch, inventory 4.1-8) is the highest-risk graphics setting: driver bugs show up as black frames/GPU resets, not as normal lag. Benefit over skiagl on A650 is small | if GPU hangs seen (D14): `debug.hwui.renderer=skiagl`, `ro.hwui.use_vulkan=false`. Otherwise leave |
| Adreno stack | stock `LA.VENDOR` older | 2025-08 driver + Turnip + A650 firmware | inventory D2 | newer driver generally smoother; kernel KGSL must match | none |
| **I/O** | `read_ahead_kb` 512 for dm/mmc; UFS `clkscale_enable 0` at early-init then 1 | same script; Lineage rc writes `nr_requests`, `cfq`, `iostats` | rc files | `dirty_expire_centisecs=3000`, `dirty_background_ratio=10` from power.rc; fine | check sda scheduler (D10). f2fs `discard` mount option is on in both |
| Camera memcg | 800 MB if RAM>8 GB else 500 MB | same | script | none | none |
| **Idle drain (already the biggest measured win)** | n/a | 53 -> 42 mAh/h after module; remaining floor is hardware | README open item 1 | keyboard/AOD/face are fixed by module; next wins are `traced`, Audiox, midas, hybridswap/SchedAssist noise, debloat | see roadmap |
| `DOUBLE_TAP`, `persist.sys.fuse.passthrough.enable=true` | stock also | same | n/a | none | none |

### 2.2 Ranked performance suggestions

1. **`watermark_scale_factor` 1 -> 60** (and re-apply in the odm script loop, because `init.qcom.post_boot.sh` runs after it). One-line change in `odm/etc/init.oplus.mm-sys.sh` `apply_vm_params()`; also writable live by the module for an A/B test (`echo 60 > /proc/sys/vm/watermark_scale_factor`). Needs D9 before/after. R: L.
2. **zram 8192 MB -> 4096 MB (stock) and nandswap default off.** Edit `init_zram()`/branch condition in the same script. R: L, but check that apps with big heaps do not get killed earlier on 8 GB (A/B with a normal day of use).
3. **ART heap props** (startsize 16m / minfree 2m / maxfree 32m / targetutil 0.5, growthlimit 256m-320m). `vendor/build.prop`. R: L-M (OOM risk on exotic apps; watch `dropbox`).
4. **Trim libperfmgr hints:** restore PixelOS `EXPENSIVE_RENDERING`, shorten `LAUNCH` to 2 s, lower INTERACTION mins. File `vendor/etc/powerhint.json`. R: M for smoothness (it can make animations rougher), L for stability. Do A/B with `dumpsys gfxinfo` jank% and a battery drain figure.
5. **`ro.vendor.perf-hal.ver=2.2`.** R: L. Needs D11 to confirm effect.
6. **Decide on Vulkan HWUI** after a GPU-hang scan (D14).
7. Confirm kernel has uclamp / WALT sysctls (D12). If not, much of the framework boost design (ADPF, task_profiles) is a no-op and the only effective levers are governor params (identical to stock) and `init.qcom.power.rc`.
8. Idle: Audiox, midas, `traced`, SchedAssist/hybridswap noise, extended debloat (section 1).

---

## 3. Roadmap

Effort: S < 1 h, M = half day, L = day+. "Where": ROM = image rebuild, module = `pipa_cos17_power_tune` (no rebuild, fastest to test), host = host-only change.

| # | Item | Cat | Impact | Effort | Risk | Where | Prerequisite |
|---|---|---|---|---|---|---|---|
| 1 | Capture baseline on beta4 *and* first beta5: enforcing state, AVC with spoofing off, init failures, crash buffer, PSI, vm params (section 4: D1-D17) | stab | Unblocks every SELinux and perf decision | S | L | none (read-only) | tablet, `adb` authorised (beta5 needs RSA prompt) |
| 2 | Session plan from MAINTAINER-STATUS (steps 3-6: 2b round trip, module v0.9, beta5) and verify U1/U17 fixed (D7, D15) | stab | Removes the panic-on-hang debug rc (likely spontaneous reboots) and the open ADB | S | M | ROM (done offline) | 2b boot test |
| 3 | `watermark_scale_factor=60` | perf | High (UI hitching under memory pressure, *guess*) | S | L | module first, then ROM odm script | D9 before/after. Test first with `perf-test-module/` (flag WSF) |
| 4 | zram 4 GB, nandswap opt-in | perf+stab | Med-high (more free RAM, fewer boot stalls, less flash wear) | S | L | ROM odm script (`init.oplus.mm-sys.sh`) | D9 |
| 5 | ART heap props | perf | Med (fewer GCs, less jank) | S | L-M | ROM `vendor/build.prop` | none; watch OOMs. Test first with `perf-test-module/` (flag HEAP_TUNE) |
| 6 | Disable AVC spoofing in `pipa_core` (or toggle for debug) so denials are visible | stab | Required for items 7-10 | S | L | module (`ksud susfs enable-avc-log-spoofing 0`) | D1 |
| 7 | Fix SELinux labels/rules for oplus perf+stability HALs, face HAL, subsys (ST1/ST4/ST6) from the real AVC list | stab | High (feature breakage that depends on permissive) and enables removing `pipa_core` as a dependency | M-L | M | ROM `vendor_sepolicy.cil`, `vendor_file_contexts`, odm cil | item 6 |
| 8 | Boot enforcing from cmdline, delete `portenforce.rc` (ST2) | stab (security) | High for security; none visible to user | M | **H** (bootloop) | ROM boot image + vendor | item 7 clean; fastboot rollback ready |
| 9 | Thermal: read HAL thresholds, decide on +10 C, restore stock battery monitor (ST-U2) | stab/safety | Med (battery temp margin) | M | L restore / M keep | ROM `vendor/etc/thermal-*.conf` | D8 |
| 10 | libperfmgr trim (EXPENSIVE_RENDERING, LAUNCH, INTERACTION) | perf | Med battery, neutral-to-slight smoothness change | S | M | ROM `powerhint.json` (module can bind-mount for testing) | A/B jank + battery |
| 11 | `ro.vendor.perf-hal.ver=2.2` | perf | Low-Med (*guess*) | S | L | ROM vendor build.prop / module resetprop | D11. Test first with `perf-test-module/` (flag PERF_HAL_VER) |
| 12 | Silence log/wakeup spam: `persist.sys.facehal.verbose=false`, Audiox off, `traced` off in ROM, midas stub, remove `FaceUnlock` app | stab/perf | Low-Med idle drain, cleaner logs | S-M | L | ROM `build.prop`, tree removals | none |
| 13 | Vulkan HWUI decision (skiavk vs skiagl) | stab/perf | Med if hangs exist, else nil | S | L | ROM `vendor/build.prop`, module resetprop to test | D14 |
| 14 | Confirm uclamp/WALT/cpuset presence; adapt hint tables if absent | perf | Unknown until measured | S | L | none | D12 |
| 15 | Regenerate `precompiled_sepolicy` + hashes (ST3) | stab (boot time) | Low | M | M | ROM odm | item 7 final cil |
| 16 | Face HAL as proper init service + `crop_eyes` fix (ST6) | stab | Med (feature reliability) | L | M | ROM vendor + upstream HAL fix | item 7 AVC |
| 17 | VINTF cleanup: subsys_radio V8, drop dead override stanzas (ST5) | stab | Low | S | L | ROM odm vintf | D6 |
| 18 | Move the five `pipa_core` daemons to init services (ST23); keep the module for user-only tools | stab | Med (clean-flash robustness) | L | M | ROM | items 7, 16 |
| 19 | Debloat: extend list past the 15 apps, disable OTA trio | perf/stab | Med memory, Low drain | M | L | ROM tree or module (`pm disable-user`) | usage review |
| 20 | Bake module file fixes into ROM (MAINTAINER-STATUS roadmap row 6 script) | stab | Fewer moving parts | S (built offline 2026-10-22: beta5-baked, MAINTAINER-STATUS row 6) | L | ROM | plain beta5 boots |

---

## 4. Read-only data collection (no sudo on host; on-device `su` where noted)

Use `ADB="adb -s 83836a90"`. Commands that need root are marked (su). Nothing here changes state, except D1 which toggles the AVC spoofing flag (reversible; run `ksud susfs enable-avc-log-spoofing 1` to restore).

| ID | Answers | Command |
|---|---|---|
| D1 | Is SELinux enforcing? Are denials hidden? | `$ADB shell getenforce; $ADB shell "su -c '/data/adb/ksud susfs enable-avc-log-spoofing 0'"` (then reproduce the issue, then reboot or re-enable) |
| D2 | AVC denials since boot | `$ADB shell "su -c 'dmesg \| grep -E \"avc: +denied\" \| sed -E \"s/.*avc: +denied +//\" \| sort \| uniq -c \| sort -rn \| head -80'"` and `$ADB logcat -b events -d \| grep auditd \| head` |
| D3 | Domain of the oplus HALs after the flip | `$ADB shell "su -c 'ps -AZ \| grep -E \"oplus\|performance\|facehal\|subsys\|qseecomd\|keystore\|vold\"'"` |
| D4 | Failed/looping services, init errors | `$ADB shell "su -c 'dmesg \| grep -E \"init: .*(Could not\|failed\|exited\|restarting)\" \| head -80'"`; `$ADB shell getprop \| grep -E "init.svc\..*(restarting\|stopped)" ` |
| D5 | midas crash, all crashes | `$ADB logcat -b crash -d \| head -120`; `$ADB shell "su -c 'ls -lt /data/tombstones \| head'"` |
| D6 | Telephony/VINTF waits | `$ADB logcat -d \| grep -i -E "vircomm\|imsradio\|subsys_radio\|waiting for service" \| sort \| uniq -c \| sort -rn \| head -20`; `$ADB shell "service list \| grep -i -E 'subsys\|IFace\|charger'"` |
| D7 | U1 really gone | `$ADB shell "cat /proc/sys/kernel/hung_task_panic /proc/sys/kernel/softlockup_panic /proc/sys/kernel/panic; ls /metadata/port 2>&1 \| head -3; pgrep -af 'logcat.*metadata'"` |
| D8 | Thermal HAL view and zones | `$ADB shell dumpsys android.hardware.thermal.IThermal/default \| head -80`; `$ADB shell dumpsys thermalservice \| head -60`; `$ADB shell "for z in /sys/class/thermal/thermal_zone*; do echo \$(cat \$z/type) \$(cat \$z/temp); done"`; `$ADB shell cat /sys/class/thermal/thermal_message/sconfig` |
| D9 | Memory state and tuning | `$ADB shell "cat /proc/sys/vm/{swappiness,watermark_scale_factor,watermark_boost_factor,min_free_kbytes,page-cluster}; cat /proc/swaps; cat /sys/block/zram0/{disksize,comp_algorithm,mm_stat}; cat /proc/pressure/memory /proc/pressure/io /proc/pressure/cpu; grep -E 'pgscan_direct\|allocstall\|pgsteal_kswapd\|workingset_refault' /proc/vmstat"` (sample twice, 60 s apart; direct scans rising means item 3 applies) |
| D10 | Block/IO | `$ADB shell "cat /sys/block/sda/queue/scheduler /sys/block/sda/queue/nr_requests /sys/block/sda/queue/read_ahead_kb; cat /sys/block/dm-*/queue/read_ahead_kb"` |
| D11 | Perf HAL props and logs | `$ADB shell "getprop \| grep -i -E 'perf-hal\|perf\.\|powerhal'; logcat -d \| grep -i -E 'perf-hal\|PerfService\|libqti-perfd\|libperfmgr\|PowerHAL' \| tail -30"`; `$ADB shell dumpsys android.hardware.power.IPower/default \| head -60` |
| D12 | uclamp / WALT / cpuset / governor | `$ADB shell "ls /dev/cpuctl/top-app/ \| head; cat /dev/cpuctl/top-app/cpu.uclamp.min 2>&1; ls /dev/stune 2>&1 \| head -3; for p in 0 4 7; do echo policy\$p \$(cat /sys/devices/system/cpu/cpufreq/policy\$p/scaling_governor) up=\$(cat /sys/devices/system/cpu/cpufreq/policy\$p/schedutil/up_rate_limit_us) down=\$(cat /sys/devices/system/cpu/cpufreq/policy\$p/schedutil/down_rate_limit_us); done; ls /proc/sys/kernel \| grep -E 'sched_(boost\|upmigrate\|prefer_spread\|walt)'; cat /dev/cpuset/{top-app,foreground,background,system-background}/cpus"`; `$ADB shell "zcat /proc/config.gz \| grep -E 'UCLAMP\|SCHED_WALT\|SCHEDTUNE\|CGROUP_SCHED'"` (su if not readable) |
| D13 | Refresh-rate behaviour | `$ADB shell "dumpsys display \| grep -E 'mActiveModeId\|DisplayModeRecord\|renderFrameRate\|mPeakRefreshRate\|minimalPostProcessing' \| head -20; settings get system peak_refresh_rate; dumpsys SurfaceFlinger --latency-clear >/dev/null"`; scroll a list, then `dumpsys SurfaceFlinger \| grep -i -E 'refresh\|vsync\|active mode' \| head -20` |
| D14 | GPU / Vulkan problems | `$ADB logcat -d \| grep -i -E 'kgsl\|adreno\|vulkan\|gpu hang\|fault\|GPU_FAULT\|skia' \| sort \| uniq -c \| sort -rn \| head -30`; `$ADB shell "su -c 'dmesg \| grep -i -E \"kgsl\|a6xx\|gpu\" \| tail -30'"`; `$ADB shell getprop debug.hwui.renderer; dumpsys gfxinfo <pkg> framestats` for jank % |
| D15 | Build identity, props | `$ADB shell getprop ro.secure ro.adb.secure ro.debuggable ro.build.tablet_type persist.sys.facehal.verbose ro.vendor.perf-hal.ver`; `$ADB shell getprop \| grep -E "dalvik.vm.heap"` |
| D16 | Idle/wakeup spam | `$ADB logcat -d \| awk '{print $6}' \| sort \| uniq -c \| sort -rn \| head -25` (top log tags); `$ADB shell dumpsys batterystats --charged \| grep -E "Wake lock\|Kernel Wake\|Estimated power" \| head -30` |
| D17 | Boot time effect of policy compile | `$ADB shell "dmesg \| grep -i -E 'selinux\|SELinux: (policy\|Loading)\|secilc' \| head"`; `$ADB logcat -b all -d \| grep -E "init: .*(Loading SELinux\|selinux_)" \| head`; boot-to-boot-completed time via `getprop ro.boottime.init.selinux` `getprop ro.boottime.zygote` `getprop sys.boot_completed` timestamps |

---

## 5. Caveats and open questions

- **Estimated magnitudes are guesses.** No jank or battery measurements exist for beta4 beyond the idle numbers in README. Items 3-5 of the roadmap should each be A/B tested with D9, `gfxinfo` jank % and an overnight idle figure.
- Whether the port kernel has uclamp, WALT sysctls and `cpu.uclamp.*` is unverified (D12); it decides whether the Lineage hint table and ColorOS `task_profiles` do anything.
- The thermal files cannot be read without Xiaomi's key; the "+10 C" statement rests on the author's own comment in `pipa_core/post-fs-data.sh`.
- The stock HyperOS pipa branch of `configure_memory_parameters` sets swappiness 180; the port's 100 is therefore not the cause of any swap-related lag by itself.
- `ro.vendor.perf-hal.ver` and zram `swapoff` stall claims are inferences from code/props, not observations.
- U13/U14 (audio engine configs, QDCM daemon) were not re-examined; they are feature items, not stability.
