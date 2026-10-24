# Kernel research and own build (2026-10-23)

Goal: a kernel we can build ourselves, that is actively developed, smooth, light on battery, and works on this
ColorOS 17 port. Build trees: `port-work/kernel/` (NVMe). **Flashed: own WALT kernel walt-r1 (boot_b, 2026-10-23 21:40;
rollback E404 r2b); walt-r2 (= walt13 release: UI First + WALT fix) flashed; smoothness work: "2026-10-23 midnight", then "2026-10-23 late night" and "2026-10-23 night" below and the recipe `WALT-KERNEL.md`.**

## Status and next steps (start here)

| Item | State (2026-10-23 15:00) |
|---|---|
| Base | E404R `staging-bpf` 9b8e5a79 + SukiSU builtin 7f1c299a (uapi 6) + susfs 2.3.0 + `CONFIG_AUDIT` + pstore port. **One command rebuilds the tree**: `maintainer/kernel/prepare_tree.sh <dir> [E404_REF] [SUKISU_REF]` (patches `e404-pipa.patch`, `sukisu-pipa.patch`), then `build_kernel.sh`, `mkboot.sh`, `flash_kernel.sh test` |
| Performance | **better**: bench.sh launch 766/706/563 → 590/477/429 ms, janky 0.08–0.12 → 0.04–0.08 %, p99 10–12 → 9–10 ms (v1) |
| Display, touch, Wi-Fi, BT, audio, charging, susfs | work |
| **Root** | ✅ **works** (v2 code): second_stage → rules → SIDs → init.rc injection → zygote → allowlist; manager `com.sukisu.ultra` recognised. Only remaining step: install manager v4.2.1-r1 after flashing so ksud matches (uapi 6; ksud 4.2.0 logs "UAPI version mismatch … skip" and `pipa_susfs` does not run until then) |
| `adb shell su` | the joeyzhu kernel allows it because its SukiSU is a **DEBUG build** ("shell is allowed at init"). Our release build does not: grant "Shell" once in the SukiSU manager (user's choice, 2026-10-23). `KCONFIG_EXTRA="-e KSU_DEBUG"` gives the joeyzhu behaviour for tests |
| **gpuservice** | ✅ fixed in ROM **beta5-2h** (`maintainer/patch_gpuserviceext.py`): E404 has no ftrace/tracepoints, so GpuMem's BPF attach to `gpu_mem/gpu_mem_total` fails and retries 30 s; OPPO's ext forwards binder calls to a not-yet-created PreCacheService. Null guards make them return 0. Enabling tracing in E404 instead breaks the build (sched trace events need WALT fields E404 removed) |
| pstore | ✅ E404 had **none** on pipa (the DT has no ramoops node; Lineage/joeyzhu read `ramoops_memreserve=4M` from the cmdline). Ported into `fs/pstore/ram.c`. Our kernel's log after a forced panic is not readable by the joeyzhu kernel (format detail, open); our kernel reads its own |
| Battery | not measured on E404 yet (joeyzhu: 71 mAh/h screen-off with USB attached + charging paused) |

**The "v2 does not boot" mystery (solved 2026-10-23):** `magiskboot unpack -h` + `repack` rewrites the boot header's
`os_version`/`os_patch_level` (backup: 16.0.0 / 2099-12 → 17.126.9 / 2099-00, a different value on every repack). The
bootloader then stops before the kernel prints a byte (black screen, no USB, no pstore, TWRP after ~2 min). v1 was
packed without `-h`. Every image since v2 had the bad header, so the SukiSU hooks were never the problem.
`mkboot.sh` now copies the original 4 bytes back and checks them. Proof: v1 and a clean rebuild of v1's source
differ in 46 bytes, 4 of them that header field.

**Smoothness and battery findings (2026-10-23 evening) → decision: move to a WALT base**
- `maintainer/stress_switch.sh` (rapid icon taps from home with Spotify playing / Dynamic Island; gfxinfo of launcher
  and SystemUI; `ICONS=Spotify OPEN=0.3 GAP=0.2` = the user's "spam Spotify" case). Janky %, median frame ms:

  | kernel | launcher taps | SystemUI taps | launcher Spotify spam | SystemUI Spotify spam |
  |---|---|---|---|---|
  | old joeyzhu (WALT) | 21.6 %, 10 | 27.3 %, 8 | 26.9 %, 12 | **14.2 %, 9** |
  | E404 r2 | 31.3 %, 13 | 35.4 %, 14 | – | – |
  | E404 r3 (deep idle) | 28.1 %, 14 | 35.8 %, 12 | 29.6 %, 13 | 30.6 %, 18 |

  Not fixed by: CPUs/GPU locked at max clock, blur off, top-app `uclamp.min` 10/30. Cause: scheduler. The port's
  power HAL (`lineage-libperfmgr`, `/vendor/etc/powerhint.json`) is written for WALT (`sched_min_task_util_for_boost`,
  `_for_colocation`, … = "all top-app tasks to big cores" on touch); E404 and N0 use CASS, those writes fail.
- Battery: E404's `lpm-levels.c` idles **WFI only** (select returns 0, enter = `wfi()`); deep power collapse only in
  suspend. `drain_usb.sh`: E404 r2 **98.7 mAh/h** vs old 71 (USB attached, charging paused). r3 = Lineage's
  `lpm-levels.{c,h}` + `lpm-levels-of.c` (cpu_isolated stubbed, IPI prediction off) restores C1 (tree
  `port-work/kernel/e404-lpm`, image `boot-e404-r3-lpm.img`); not drain-tested.
- liyafe (`android15-lineage22-mod`, WALT, pipa DT) test boot: black screen, no USB. **Solved 2026-10-23 17:20**
  (log via pstore, see "liyafe black screen" below): not the dtb and not the size; the kernel boots fine, but
  A17's `netbpfload` exits ("Android 25Q2 requires kernel 5.4", uname 4.19.325), init reboots, and the shutdown
  hangs unmounting `/mnt/vendor/spunvm` → black screen. A WALT kernel for this ROM needs E404/N0's bpfloader uname
  spoof + BPF backports. The bootloader refuses `fastboot boot`
  of the raw `boot_b` backup ("Press any key to shutdown"); repacking its kernel with `mkboot.sh` works
  (`bootimg/boot-joeyzhu-repack.img`).

**2026-10-24 14:25: kernel walt-r5 (heavy UX threads on big cores, frame_rate 120)**
- `kernel.ux_prefer_big` (new, default 1): OPPO's slide-scene-only placement of heavy UX tasks (start on the mid/big
  cluster when util >= boost_task_threshold, `find_ux_task_cpu` on misfit) applies at all times. A/B in one boot (2
  traced runs each, taskbar on + blur off, ROM 2n): launcher gfxinfo 5.8-6.7 % vs 7.4-7.9 %, App Deadline 182-236 vs
  266-300, SystemUI 11.7-12.1 vs 12.7-13.3 %, SF on time ~94 % both; power 6.74/6.79 W vs 6.99 W.
- `kernel.frame_rate` defaults to 120 (was 60; OPPO's perf daemon would write it, nothing does on pipa).
- Earlier slide-scene test (r3) in launcher terms: late frames per launcher frame 5.4-6.1 % -> 4.4 %: the placement
  gain was there, hidden by looking only at SF numbers.

**2026-10-24 late afternoon: taskbar + blur, unmapped ColorOS hints (start here)**
- ROM 2n heavy run: SF on time 94.6 %, dropped 0.9 %, long DRM commits 312 (was 700-1000); QS -> Settings launch
  175-196 ms (morning 276-332).
- **Taskbar cost** (parallel trace + APK study): ColorOS "transient" taskbar redraws on every frame of every app
  open/close (~79 frames/transition, ~3.1 ms main thread each, blurred `TransientTaskbarBlurBackgroundView`, own
  SurfaceView); not GPU-composed. Settings: `system enable_launcher_taskbar`, `enable_launcher_tools_transient_entry`
  (1 = transient), `system_material_blur_enable` (system-wide material blur: taskbar, folders, workspace).
  A/B (2 traced runs each, walt-r4 + 2n): pinned taskbar (transient 0) **worse** (launcher App Deadline 744-924,
  gfxinfo 15-18 %); **taskbar on + material blur off: launcher gfxinfo 7.2-7.6 %, p50 9 ms, SF on time 94-96 %, dropped
  0.9-1.1 %, App Deadline 260-301** (taskbar off + blur: 11 %, 182-208). User's choice: taskbar on, material blur off.
- **Unmapped/blocked ColorOS hints** (logcat scan of failed /proc,/sys opens):
  - OPPO's vendor perf daemon `vendor-oplus-hardware-performance-V1-service` (`/vendor/bin/hw`, service
    `oplus.performance.hal.service-1-0`, domain `vendor_hal_perf_default`) is OPPO's scene engine (writes
    sched_assist_scene, slide_boost_enabled, frame_rate, sched_impt_task, ux_task, im_flag). It reads `/proc/version`
    (`Linux version %d.%d.%d`; >= 5.10 -> /proc/oplus_scheduler/... + /proc/sys/walt/..., else /proc/sys/kernel/...),
    but SELinux denied the read (proc_version) -> "Linux version 0.0.0", "not support", 312 opens of "(null)" per
    run. Live fix (`ksud sepolicy patch`): allow vendor_hal_perf_default proc_version read, proc +
    oplus_sched_assist_scene_proc + oplus_scheduler_sched_assist_proc write, restart the service -> "Linux version
    4.19.325", no (null) errors, scene SA_LAUNCH (1) set during app launches. Measured neutral (heavy SF on time 91 %,
    QS -> Settings 169-183 ms): not in the ROM yet; a proper policy would label frame_rate/slide_boost_enabled/
    input_boost_enabled (now generic `proc`) instead of allowing proc writes.
  - `/proc/sys/kernel/frame_rate` stays 60 at 120 Hz (OPPO UX freq-load uses it: maxtime 5 vs 4); nothing sets it.
  - Missing nodes: `/proc/oplus_binder/ux_flag` (SchedAssist, binder UX hint; port not done), `/proc/oplus_afs_config/
    afs_config`, `/proc/oplus_healthinfo/cpu_loading`, `/proc/jank_info/...`; `/sys/block/zram0/hybridswap_*` denied.
  - `sched_impt_task` (PerformanceService) denied: same domain; covered by the policy above.
- OPPO device tiers: `persist.sys.oplus.platformlevel` = c:3,g:3 (HIGH) on SD870; budget tablets run lower gaussian/
  animation levels and the launcher has a "LowEndLargeScreen" path; the launcher also degrades animations on Osense
  events (cpuLoad >= 95, temperature >= 45 C). Re-test of mid tier (`ro.oplus.animationlevel=2`, `gaussianlevel=2`,
  resetprop + restart launcher/SystemUI) on 2n + taskbar on/blur off: launcher gfxinfo 8.3-10.2 % (7.2-7.6), SF on time
  93-94 % (94-96), dropped 1.0-1.1 %: no gain, reverted. Material blur off is the useful part of "low end".
- Is blur CPU- or GPU-bound? GPU locked at max: no change (earlier). Blur on, 2n baseline: launcher gfxinfo 11.9-14.2 %,
  App Deadline 591-640, SF on time 90-91 %. Blur on + launcher main/RenderThread pinned to cpus 4-7 (taskset f0):
  10.2-10.7 %, 504-526, 90-91 %: placement recovers ~1/4 of the blur cost; the rest is per-frame work (extra
  blurred layers/SurfaceViews updated every transition frame). A kernel rule "top-app launcher main/RenderThread
  prefer big cores" is a possible small gain (~-15 % launcher App Deadline); not built. Blur off kept (user choice).

**2026-10-24 afternoon: Settings glitch, QS -> Settings lag (ROM 2m, 2n)**
- **Screen glitching in Settings search** = SF layer caching (2j `debug.sf.enable_layer_caching=1`): `service call
  SurfaceFlinger 1040 i32 0` ("Planner is disabled") fixed it live; **ROM 2m** drops the line (md5 989d94be...). Side
  note: the composer logs `lib_scale_get_pipe_settings failed` ~130x/s (LOG_FLOWCTRL drops 800 lines/s); no layer is
  actually scaled, cause unknown, not the glitch.
- **QS gear -> Settings** (automated: `kgest` swipe from top-right, tap (2748,108), 4 rounds under perfetto): each tap
  launches Settings + `com.oplus.wirelesssettings` (tablet two-pane). Settings main thread waits on system_server
  binder 1.8 s / 4 launches, there mostly WindowManager lock contention owned by **android.anim** (466 ms) and
  InputDispatcher, plus 131 ms on `osense.kill` (AMS lock). system_server android.anim/display/ui have no UX
  (ColorOS only sets app UX); android.display runnable > running. SystemUI's real hitches: a few 45-53 ms frames when
  QS opens/collapses. All apps were speed-profile.
- Fix: system_server android.anim/display/ui as animator UX (`ux_task` "p <tid> 132") + full `speed` compile of
  SystemUI / Settings / wirelesssettings / launcher: Settings 276-332 -> 226-261 ms, Wi-Fi page 221-354 -> 194-251 ms,
  SystemUI frames on time 52 -> 65 %, longest SystemUI frame ~45 ms. **ROM 2n** (md5 ece2e9e1...): pipa_port
  `SYSTEM_UX`, `SPEED_COMPILE` (once per build, 3 min after boot, state `/data/misc/pipa_port/speed_compiled`) and
  product `dalvik.vm.systemuicompilerfilter=speed`.
- Gotcha: restarting SystemUI (kill) locks the tablet; writing `p <tid> 0` to `ux_task` clears a thread's UX.

**2026-10-24 midday: dropped frames = SurfaceFlinger on the little cores -> ROM beta5-2l (start here)**
- The ~390 SF "Dropped Frame"s per run are display frames without a prediction token, right after a late GPU-composed
  frame (GPU Deadline Missed -> Stuffing -> Dropped catch-up frame). Not refresh-rate switches (6 mode changes per run,
  0 drops near them), not `debug.sf.latch_unsignaled` (E: =0, same numbers), not GPU clock (min_pwrlevel 0, same).
- Frames still bad with D sit in Vsync-Early mode with GPU composition. SF main thread in bad frames: Running on
  little cores 41 %, big 9 %, prime 3 %; RenderEngine mostly little too. SF is SCHED_FIFO; WALT's RT placement
  (`rt_energy_aware_wake_cpu`) picks the smallest CPU that fits. OPPO UI First moves SF/RE off the little cores
  (`drop_ux_task_cpus()`: `sf_boost_scene() && is_sf(p)`; cpupri `sf_task_misfit()` -> `kick_min_cpu_from_mask`),
  but only while a sched_assist scene is set (SA_SLIDE/ANIM/INPUT/GPU_COMPOSITION). `/proc/sys/kernel/
  sched_assist_scene` stayed 0 even during flings: ColorOS 17's framework does not write it (no path in
  oplus-framework/oplus-services), OPPO's vendor perf daemon does, pipa has Xiaomi's vendor. Writing the scene needs
  SA_SCENE_OPT_SET (1<<7): `echo 384` sets SA_GPU_COMPOSITION (256); a write without bit 7 clears those bits.
  Users of the scene: only the SF/RE placement (+ `slide_rt_boost()`, which nothing calls).
- **Scene on (traced, D active):** SF on time 75 -> 86 %, Dropped 384 -> 163, GPU deadline 238 -> 115, Scheduling
  165 -> 75, launcher FrameTimeline janky 66 -> 45 %, launcher frames 13.5k -> 16.2k; gfxinfo launcher 10.5-11.4 %,
  SystemUI 12.3-14.2 %. Power same thermal state: scene off 7.09-7.40 W (avg 7.22), on 7.32-7.39 W (+2 %). The
  morning's 6.5 W baseline was a cooler tablet (battery 24 vs 35 C): compare power only back to back.
- **ROM beta5-2l** = 2k + pipa_port `SF_BIG_CORES` (echo 384 at boot) + product build.prop: early/earlyGl SF offset
  -6.5 ms, early app offsets -1.5 ms, predict_hwc 1 (product loads after vendor). Confirmation trace `rom-2l`: SF on
  time 88 %, Stuffing 5.6 %, Dropped 2.2 %, GPU deadline 1.4 % of SF frames (2k morning: 59 / 24 / 6.5 / 4.5 %);
  launcher FrameTimeline janky 46 % (87 %).
- Tools: `maintainer/perfetto/traced_heavy.sh <label>` (traced heavy run + `frame_summary.py`), settle 60 s after
  unlock before measuring (the user's rule; an unsettled run looked worse).
- After 2l (trace `rom-2l`): SF main on big/prime 99 % (sampled), but **RenderEngine still on little 38 %**: `is_sf()`
  matches only the SF main thread (pid == tgid), RenderEngine only via `re_pid` + the util threshold in cpupri. A root
  shell cannot rename another process's thread to re-trigger the comm hook (EINVAL). Kernel fix on branch `oppo`:
  `is_sf()` also matches the SF process's "RenderEngine" thread -> **walt-r4** (flashed 12:10). Sampled placement:
  RenderEngine on little 38 -> 1 %. Traced (2 runs vs 3 on r3): SF on time 92-93 % (80-88), Stuffing 2.2-3.4 % (5.5-11.6),
  Dropped 1.7-2.0 % (2.2-3.3), GPU deadline 0.6-0.8 % (1.3-2.1), launcher FrameTimeline janky 41-42 % (45-51); gfxinfo
  launcher 10.9-11.7 %, SystemUI 12.0-13.4 %; power 7.35-7.45 W (r3 + scene 7.32-7.39). `fastboot boot` needed one
  `fastboot reboot-bootloader` first ("unknown command" / getvar "Variable Not found" state).
- No gain: `slide_boost_enabled=1` for a whole run (SF on time 87.8 vs 88.1 %); SystemUI main + RenderThread as heavy UX
  via `/proc/oplus_scheduler/sched_assist/ux_task` ("p <tid> 130") is reset by ColorOS (non-top app) within the run.
  SystemUI late frames: main thread runnable 29 % (no UX flag; no SystemUI im_flag type exists in OPPO's enum).
- **On walt-r4 + 2l, what is left** (trace r4-2l-r2): launcher App Deadline ~4-5 % of its frames; SystemUI main thread
  runnable 44 % in its late frames. CPU holders while they wait: the other UI threads (launcher RenderThread/main, SF,
  SystemUI RenderThread, composer HwBinder) and kswapd0 (~1 s per run; pgscan_kswapd 4 M pages since boot = cold app
  starts churn the file cache). kswapd pinned to cpus 0-3: no gain (SF on time 87.6/91.3 %), reverted.
- Launcher late frames: main `traversal` 9.3 s, `postAndWait` 6.9 s, **`draw-VRI[Taskbar]` 4.3 s**, `draw-VRI[Launcher]`
  3.7 s; RenderThread `queueBuffer` 3.5 s, `waitForBufferRelease` 1.4 s. **Taskbar off** (`settings put system
  enable_launcher_taskbar 0`): launcher App Deadline 617-671 -> 182-189 per run, launcher FrameTimeline janky 41-42 ->
  25-27 %, SF on time 93-94 %, dropped 1.4-1.5 %; SystemUI gfxinfo 15-20 % (it now draws the gesture bar in apps). A
  user choice (no taskbar inside apps): the user chose **off** (2026-10-24 12:50, live setting, not a ROM default).
- Keep the screen on for test series: `svc power stayon usb` (the 5-min timeout locked the tablet between runs;
  `traced_heavy.sh` now refuses to run when locked). Set back with `svc power stayon false`.
- Run-to-run noise of a single traced run is a few % (SF on time 84-88 % on identical settings): judge A/Bs on >= 2 runs.

**2026-10-24 morning: root cause of the remaining stutter = SurfaceFlinger timing vs the video-mode commit (ROM 2k, walt-r3)**
- Test fix first: `heavy_mix.sh` bursts no longer tap a bottom-centre icon (Play Store in the dock sits where Recents
  puts "clear all"; a burst home swipe that lands in Recents then killed every app -> INVALID with 0 frames). With
  GAP=0.2 Opera/Play Store taps are still sometimes eaten by the YouTube close animation (INVALID on browser/vending
  only); launcher/SystemUI numbers stay comparable. Baseline 2k (OPEN=0.4 FL=0.2 GAP=0.2): launcher 12.4-13.1 %,
  SystemUI 14.5-17.0 % gfxinfo janky, 6.5-6.6 W (walt-r2 era: 20-25 % / 20-22 %).
- FrameTimeline (`port-work/traces/walt-r3-2k-heavy.pftrace`): launcher frames 87 % janky, of which Buffer Stuffing
  6608, App Deadline only 856; SF frames: Stuffing 1481, Dropped 392, GPU deadline 274, Scheduling 199, Display HAL 120.
  SF main `present` (whole composite) avg 4.5 ms, 370 > 8.3 ms; composer `PresentDisplay` avg 1.4 ms but 374 DRM atomic
  commits > 4 ms (avg 6 ms) = the composer sleeping until `crtc_commit:138` finishes the previous commit. Kernel stack
  samples of `crtc_commit:138` during the test: 62 % `sde_encoder_phys_vid_wait_for_vblank` (commit done = next vblank,
  video-mode panel), 6 % `sde_plane_wait_input_fence` (GPU-composed buffer), 28 % idle. Chain: GPU-composed frames
  (shade blur radius 400, ColorOS rounded/blurred animation layers -> CLIENT composition) need ~4.5 ms SF CPU + ~2.4 ms
  GPU, but the HyperOS SF offsets give SF 4 ms before vsync (`high_fps_*_phase_offset_ns = -4 ms`) -> kickoff misses
  the vblank -> the CRTC stays busy until the next one -> next commit blocks (`start_atomic`) -> SF Stuffing/drops ->
  apps' buffers back up.
- Tried, no gain or worse: SF blur algorithm (already KawaseDualFilterV2), `persist.sys.sf.disable_blurs=1` (ColorOS
  adds a Dim + scrim layer, everything CLIENT; gfxinfo same), predict_hwc only (A, same), duration model with the port's
  commented values (B: app 6.83 ms -> launcher 26-27 %, SystemUI 30-31 %; needs every `*phase_offset_ns` prop deleted
  or SF aborts "expecting duration"), duration SF 6.17 / app 11.67 ms (C: gfxinfo same, FrameTimeline worse: SF
  Stuffing 4218, long commits 772).
- **D (works):** early + earlyGl SF offset -6.5 ms, early app offsets -1.5 ms (apps keep their draw time), late
  unchanged, predict_hwc 1 (`/data/adb/post-fs-data.d/pipa-sf-ab.sh` until the ROM has it). FrameTimeline: SF on time
  59 -> 75 %, SF Stuffing 1481 -> 515, launcher Buffer Stuffing 6608 -> 3805, launcher janky 87 -> 66 %, SF dropped
  392 -> 384. gfxinfo unchanged (12.1/13.2 %, SystemUI 16.0/15.1 %). Power 7.2-7.5 W vs 6.5-6.6 W: re-check.
- Also found: pipa's vendor build.prop sets `debug.sf.predict_hwc_composition_strategy=0` and loads after system_ext,
  so 2j's `=1` is overridden (the A/B had it from the KSU script). SF props belong in `product` (loads last).
- Next: user feel test of D, power re-check, then ROM 2l (product build.prop); then why dropped frames stay ~390
  (Display HAL 93-120, GPU deadline 238), and fewer CLIENT layers (shade blur forces everything above it to GPU).

**2026-10-23 midnight: smoothness investigation on walt-r2 (heavy mixed test, traces; start here)**
- **New test `maintainer/heavy_mix.sh`** (the user's "smooth everywhere, fast" case): closes every app in recents first
  (force-stop; keeps launcher, SystemUI, microG `app.revanced.android.gms` which YouTube Morphe needs), Spotify playing
  (live alert pill up), then app after app (Settings, Photos, YouTube, Opera, Play Store; icon positions re-read every
  round because the dock's recent-apps section shifts the dock icons): open, 3 flings down + 1 up, HOME; per round the
  shade, Quick Settings, pill hold (= opens Spotify) and pill tap (= expands the live alert card `SeedlingCard`), app
  drawer (swipe up from home, flings); ends with on-device open/close bursts, the last two with the next app opening
  during the previous close animation. All taps and swipes go through the touchscreen's kernel input device with
  **`maintainer/kgest`** (static arm64 C tool, `kgest tap X Y` / `kgest swipe X1 Y1 X2 Y2 MS`, 4 ms moves, HOME = swipe up
  from the bottom edge), like a finger. Knobs `OPEN FL GAP BURST`, results in `port-work/perf-ab/heavy.csv`.
  `maintainer/shade_scroll.sh` (shade/QS/Settings only, `input swipe`) is the first, lighter version.
- **Baseline walt-r2** (OPEN=0.4 FL=0.2 GAP=0.2, 10-20 cycles, clean start): launcher **19-25 %** janky (p50 12-13, p90
  26, p99 40 ms at 144 Hz), SystemUI **21-24 %** (p90 24-26, p99 44-57), apps 20-30 %. Run-to-run spread about ±3 %.
- **Ruled out (A/B, two runs each, no change beyond the spread):** CPU+GPU locked at max clock (22.4/22.3 %), 120 Hz
  cap via `peak_refresh_rate` (20.7/24.5 %), SystemUI main+RenderThread forced UX (`ux_state` 0x06000282 every 0.3 s:
  21.5 %), GNSS loop stopped (21.2/23.2 %). So the frames are not late for lack of compute or because of the vsync budget.
- **UI First facts:** launcher main/RenderThread are UX (`ux_state=0x06000002`) all the time; SystemUI only gets UX
  while the shade is open (0 otherwise). The scheduler hooks are live in our kernel (`fair.c`
  `place_entity_adjust_ux_task`, `should_ux_task_skip_cpu`, `cpupri.c` `drop_ux_task_cpus`). Launcher sits in
  `cpu:/foreground` when an app is on top; the donor vendor also sets `cpu.uclamp.colocate` only for top-app (by design).
- **Scheduling (raw tracefs trace, `maintainer/perfetto/ktrace.sh`, reliable):** launcher threads wake fast (p99 ~1.5 ms,
  max < 10 ms); SystemUI main waits more (p99 7.2 ms, max 61 ms, 422 waits > 2 ms = 2.5 s in 35 s, behind RenderThreads,
  surfaceflinger and nice-0 app threads: vending, DefaultDispatch, Opera, YouTube); surfaceflinger, the composer
  (HwBinder:1241_2) and crtc_commit wake within 0.2 ms p99. The 0.7-1.1 s "runnable" waits seen in the first atrace
  were atrace artefacts (heavy overhead); do not trust atrace runnable totals.
- **Display path:** kernel side is fast (SDE markers: composer `atomic_commit` ioctl 1.5 ms avg, max 3.1; crtc_commit
  waits one vsync for frame done, normal). HWC `HWDeviceDRM::Commit` 4.7 ms avg on the composer thread. SurfaceFlinger
  `composite` 5.8 ms + `commit` 2.2 ms per frame, about 65 % of frames with GPU composition (RenderEngine
  `drawLayers` 3.5 ms avg; ColorOS blur). Launcher RenderThread time is dominated by `queueBuffer` (9 s),
  `dequeueBuffer` (4.5 s) and `waitForBufferRelease` (4.3 s): it waits for buffers more than it draws.
- **Blocking calls:** launcher main -> servicemanager once 327 ms; SystemUI RenderThread -> surfaceflinger 178 ms;
  system_server lock contention 10-20 ms (owners InputDispatcher, AccessibilityWindowManager).
- **Port bugs found (fix in ROM beta5-2j, see `BUGS-TODO.md`):** (1) `loc_sys_service` polls the absent
  `vendor.qti.gnss.ILocAidlGnss` once a second (beta5-1c only commented out its `start`; `class main` still starts it):
  add `disabled`. (2) **perfetto `traced` never starts**: the donor's `/product/etc/build.prop` sets
  `traced.relay_producer_port=vsock://-1:2010` and our kernel has no AF_VSOCK, so `traced` exits ("Failed to create
  vsock://-1:2010 (errno 97)"); remove the line. Live: `resetprop -d traced.relay_producer_port` then
  `setprop persist.traced.enable 1`. With traced, SurfaceFlinger's **FrameTimeline** works (`maintainer/perfetto/jank.cfg`).
- **First FrameTimeline result (3 shade pulls):** surfaceflinger on time 515/520 frames; SystemUI 394 frames "Buffer
  Stuffing" (queued ahead = extra latency, the "laggy" feel without drops), only 8 "App Deadline Missed".
- **FrameTimeline of the heavy test (traced working):** surfaceflinger missed its own deadline on 50 % of its frames;
  GPU-composed SF frames 85 % janky (1664/1947) vs 34 % for device-composed; launcher/SystemUI janky frames are mostly
  attributed to SurfaceFlinger (7813 / 1689) rather than the app (1721 / 612). **GPU composition comes from the
  rounded corners of animating windows** (ColorOS launch/close animation radius 300-455 px, starting surface,
  "Caption of Task"): SDE cannot round corners, so those layers and everything above (status bar, screen decor,
  taskbar, iconViewSurface) go CLIENT on 82 % of frames during app opens. Static shade/drawer are fully DEVICE.
  `config_supportsRoundedCornersOnWindows=false` (fabricated overlay) does not remove them: ColorOS sets its own radius.
- **Why SF's GPU work is late (kgsl tracepoints `adreno_cmdbatch_*`, script in this section's session):** GPU 56-93 %
  busy at 670 MHz during animations, no thermal cap (39-41 C, LM throttling in 7/2121 samples). Per context:
  launcher RenderThread prio **4** (36 % of GPU time), SurfaceFlinger RenderEngine prio **4** (27 %, 2.6 ms per job,
  wait before start p90 4.2 / max 14 ms), SystemUI prio **8** (wait avg 7.7, p90 19, max 44 ms), apps prio 8.
  kgsl ringbuffer = priority / 4 and preemption is only between ringbuffers, so SF shared ringbuffer 1 with the
  launcher and could never preempt its animation work. **Fix (kernel commit 920120643a03, branch own, merged into oppo
  = walt-r3):** `_set_pipa_priority()` in `adreno_drawctxt.c`: surfaceflinger contexts priority 1 (ringbuffer 0),
  SystemUI (`ndroid.systemui`) at least 4.
- **A/B tests 2026-10-24 (heavy_mix, POWER=1, 2 runs each, launcher / SystemUI janky %, W):** original SF GL
  24.4/20.4 26.4/22.2 7.22/6.53; SF RenderEngine Vulkan (`skiavkthreaded`) 25.3/22.1 25.5/25.4 6.85/7.24 (dropped);
  HWUI apps on GL (`skiagl`) launcher same, SystemUI 27.8/26.3 (dropped); **SF layer caching + HWC strategy prediction**
  (`debug.sf.enable_layer_caching=1`, `debug.sf.predict_hwc_composition_strategy=1`) 20.9/19.6 24.4/20.8 6.83/7.00
  (kept, KSU script `/data/adb/post-fs-data.d/pipa-sf-test.sh`; ROM build.prop in beta5-2j); OPPO mid tier
  (`ro.oplus.animationlevel=2`, `ro.oplus.gaussianlevel=2`; `OplusPlatformLevelUtils` derives both from
  `persist.sys.oplus.platformlevel` = c:3,g:3 HIGH for SM8250; read by SystemUI and OplusLauncher) 23.3/20.9
  25.9/23.9 7.27/7.23 (dropped); DDR/LLCC/gpubw pinned to max 23.3/23.5 23.5/23.2 7.29/7.32 (dropped); 120 Hz
  (user's choice, `peak_refresh_rate=120`) 23.7 / 22.9, 6.88 W. The original dev's `pipa_core` had no perf tweaks
  (blur default off, `loc_sys_service` stop, traced off).
- **walt-r3 = walt-r2 + the kgsl priority fix, flashed to boot_b 2026-10-24 01:00** (`bootimg/boot-walt-r3.img`, md5
  `9a167e41…`; rollback `boot-walt-r2.img`). kgsl after the fix: RenderEngine prio 1, wait before GPU start avg 0.42 /
  p90 1.44 / max 4.8 ms (walt-r2 1.32 / 4.2 / 14.2). FrameTimeline (traced heavy run; not fully comparable: r2 trace at
  144 Hz without layer caching, r3 at 120 Hz, buffer wrapped): launcher late 58.1 -> 41.8 %, of which SF-caused 51.2 ->
  36.9 %; SystemUI 41.1 -> 37.7 %; SF GPU-composed frames late 85.5 -> 72.5 %. gfxinfo unchanged (launcher 23-24 %,
  SystemUI 25-26 %), SystemUI p90 27 -> 21-22 ms. Power 7.2-7.6 W (r2 6.9, within noise).
- **Traced runs and OPPO's memory killer:** with a perfetto buffer (128-384 MB) running, `athena_killer` / `osense.kill`
  kill the test apps and Spotify as soon as they go to the background (trace slices `kill/<pkg>/…`), so gfxinfo of the
  apps is lost and `heavy_mix.sh` reports INVALID; launcher/SystemUI/SF FrameTimeline stays usable. `heavy_mix.sh`
  now prints INVALID when an app renders < 50 frames or the music stopped (also when a floating window, e.g. Messages
  in freeform, or the battery dialog blocks the taps; run >= 5 cycles so every app is reached).
- Next levers (same kind, "wrong order" rather than missing power): the launcher's GPU load (42 % of GPU time, a
  separate ColorOS "Blur" GPU context), launcher Buffer Stuffing (frames queued ahead = latency), display commit on
  SF's main thread (~2.2 ms).
- App drawer trace: launcher misses its own deadline rarely (~300 frames); SF GPU composition on 693/1593 frames, 72 %
  of them late; 2086 launcher frames Buffer Stuffing.
- Tools: `maintainer/perfetto/` (`jank.cfg`, `analyse.py`, `ktrace.sh`), trace processor
  `port-work/tp/trace_processor_shell` (`-D --http-port 9001 <trace>`, then `TP_ADDR=127.0.0.1:9001`), Python venv
  `port-work/perfetto-venv`, traces in `port-work/traces/`.

**2026-10-23 late night: UI First works + WALT frequency fix (walt13 -> walt-r2, start here)**
- **Root cause of walt-r1's jank (found by the smoothness audit + code reading):** `pipa-cos17.config` enables
  `UCLAMP_TASK`, and `SCHED_TUNE` depends on `!UCLAMP_TASK`, so schedtune dropped out silently (walt4+). Without it
  (1) schedutil's `stune_util()` was a macro for `cpu_util_cfs()` = **PELT**, not WALT; `walt_load` (nl/pl/rtgb) stayed
  0, so hispeed/predictive/colocation boosts never ran; (2) `schedtune_task_colocated()` was always false: top-app never
  joined WALT's colocation group; (3) boosted placement ignored uclamp. Also walt-r1 runs 144 Hz (E404 display), walt2
  had 120 Hz, so walt2's numbers were not comparable. Fix (branch `own`, 825c52f8): `stune_util()` = `cpu_util_freq()`
  clamped by rq uclamp; cpu cgroup `cpu.uclamp.colocate` (the msm uclamp knob the donor's vendor init writes: top-app
  1), default on for top-app; `uclamp_boosted()` counts as boosted. `uclamp_boost.c` (E404 touch boost) ported but off:
  A/B on WALT showed no gain (15.8/17.2 % vs 13.8/15.3 %).
- **ColorOS 17 UI First interface** (from `libSchedAssistExtImpl.so` disassembly + decompiled `com.oplus.uifirst`):
  fds on ux_task, ux_task_app, im_flag, oplus_frame_boost/{ctrl,sys_ctrl}, oplus_binder/ux_flag,
  oplus_frame_boost_async/async_perf_ctrl, ddl_task; `/dev/sched_boost` mmap page (lock boost). ux ioctls 0x2700/0x2701
  ({pid,tid}/{pid,tid,value}, 5.10 bit layout: SET 0x80, RESET 0x100, SET_PRIORITY 0x200, prio top byte); frame boost
  0xde01-0xde0b (48-byte ofb_ctrl_data, 68-byte ofb_stune_data); ddl 0xdd00-02; binder 0x407a6900. Not in any published
  OPPO source (sm8450/sm8750 16.0): /dev/sched_boost, async_perf_ctrl, the binder ioctl -> left out (the lib skips fds
  it cannot open). ddl_task = a deadline scheduler inside sched_assist (sm8750 `sa_ddl.c`) -> left out.
- **Implemented on `oppo`:** `kernel/sched_assist/sa_ux_task.c` (ux_task/ux_task_app, 5.10 -> 4.19 ux_state rules of
  write_task_ux(), uid checks as 5.10), frame_ioctl built + initialised (68-byte stune struct, STUNE_DEF, GPU/non-GPU SF),
  `/proc/sys/fbg/*`. **SELinux** for these nodes is in OPPO's *vendor* policy (we ship pipa's vendor): ROM **beta5-2i**
  adds the donor's types/genfscon/rules to system_ext (`maintainer/uifirst-policy/`, generator + donor rules; donor
  vendor extracted from payload.bin with `maintainer/payload_extract.py` to `port-work/donor-c06-vendor/`).
- **Result (walt13 test boot on 2i):** launcher main/RenderThread/hwuiTask/anim, SystemUI, Spotify audio threads get
  UX with priorities. KTAP Spotify spam 30 cycles at 144 Hz: launcher **13.8 / 15.3 %** janky (walt-r1 24.9-27.8),
  p99 26-27 ms (32-34); SystemUI 17.0 / 18.6 % (22.0-23.5). 0 CFI failures. Hot (84 C max zone) during repeats.
- Next levers: 120 Hz cap option, frame boost stune values, systrace of late frames, ddl/game_opt later.

**2026-10-23 night: own WALT kernel ("walt") built and booting (start here)**
- Repo `port-work/kernel/walt-own`, branch **`own`** = merge of `liyafe/android15-lineage22-mod` + `lineage/lineage-24.0`
  (38 conflicts). Rule used: core (fs incl. f2fs, kernel, mm, include, block, net, lib, crypto, binder) = **Lineage**
  (4.19.325-cip136, CIP f2fs fixes to 2026-09; supports every /data f2fs feature incl. casefold); from liyafe only
  device drivers/techpack/dts/defconfig fragments + device headers + lz4kd/lzo-rle. Dropped: liyafe's f2fs fork, all
  MIUI-only core hooks (XIAOMI_MIUI, MIGT, PERF_HUMANTASK, MILLET, RTMM, MI_RECLAIM; off on pipa anyway), old KSU/susfs.
  Kept liyafe's pipa `aw8697.c` (from pipa-t-oss) + Lineage's cast fix; liyafe's `scripts/dtc/Makefile` (dtc 1.5).
- Commits on top: uname spoof (`kernel/sys.c`: root bpfloader/netbpfload/uprobestats/netd see 5.15.325, uid >= 1000 and
  zygote 5.10.325, like E404), pstore layout (E404/joeyzhu), `CONFIG_PIPA_BOOTDBG` (kernel/pipa_bootdbg.c, test builds),
  build fixes (aw882xx/tfa98xx `-I$(srctree)/$(src)/inc`, bq2597x casts), config fragment
  `arch/arm64/configs/vendor/xiaomi/pipa-cos17.config` (AUDIT, CFI permissive), then (branch `ksu`, fast-forwarded into
  `own`) vendored `KernelSU/` = SukiSU builtin 7f1c299a + `sukisu-pipa.patch`, and the SukiSU/susfs 2.3.0 hooks
  taken from our E404 r2b tree with `oppo_extract.sh` (unifdef CONFIG_KSU*) + 3-way merge; susfs' mount hook moved to
  `vfs_create_mount()` (Lineage 24 has the fs_context mount API).
- **Config = Lineage's fragment chain** (`vendor/kona-perf_defconfig` + `xiaomi/sm8250-common.config` + `xiaomi/pipa.config`
  + `xiaomi/pipa-cos17.config` [+ `xiaomi/pipa-oplus.config`]), as Lineage builds elish/enuma. liyafe's
  `pipa_defconfig` is an old snapshot: it lacks ANDROID_VENDOR_HOOKS (link fails), USERFAULTFD, BPF_LSM, XDP,
  MEMFD_ASHMEM_SHIM, TRACE_GPU_MEM, CFI/SCS. Build: `maintainer/kernel/build_walt.sh` (ThinLTO + CFI, ~15 min clean).
  Image 58 MB, arm64 `image_size` 66.4 MiB: the bootloader accepts it.
- **walt1 test boot (19:18, `bootimg/boot-walt1-dbg-trim.img`, no root):** boot_completed at 40 s; Wi-Fi + internet,
  120 Hz, touch/pen nodes, 4 aw882xx amps, WALT sysctls (`sched_boost`, colocation, ...) present, cpuidle C0+C1 (deep
  idle). No CFI failure, no oops in dmesg (from `adb bugreport`, `port-work/kernel/checks/walt1/`). BpfLoader runs;
  only `timeInState.bpf` fails (no kernel BTF; `CONFIG_DEBUG_INFO_BTF` needs pahole). Spotify spam with plain `input
  tap` (no kernel boost): launcher 16-21 %, SystemUI 15-18 % janky (joeyzhu WALT 26.9/14.2; E404 r2b with KTAP 13-16).
- **walt2 test boot (19:31, `bootimg/boot-walt2-dbg-trim.img` = walt1 + SukiSU/susfs):** root works (uid 0 `u:r:ksu:s0`,
  ksud 4.2.1-r1 uapi 6 matches the installed manager), susfs 2.3.0 + `pipa_susfs` applied, audit core works (SELinux
  events in dmesg), pipa_port/face HAL/BT/audio fine, no CFI failure. Spotify spam **KTAP**: launcher 15.7/16.6/17.3 %,
  SystemUI 15.2/15.8/17.5 % (E404 r2b + uclamp boost 13.0-15.4 / 14.9-16.2). `sukisu-pipa.patch` now also marks
  rules.c's 5.10-only pointers `__maybe_unused` (Lineage builds with -Werror).
- **walt2/walt4 drain + touch (20:18-20:45):** `drain_usb.sh` walt2 **62.5 mAh/h** (E404 r2 98.7, joeyzhu 71): deep
  idle works. walt4 (= walt2 + uclamp) boots; uclamp files appear in /dev/cpuctl. **Touch dead with fingers** (KTAP and
  `input` still work): liyafe's `dsi_panel_lockdowninfo_param_read()` uses the wrong command index for the pipa m82
  panel (`failed to read cmds, rc=0`), `lockdowninfo_read_done` stays 0, `dsi_panel_lockdown_info_read()` makes the
  NT36532 firmware load wait 500 s, and after the first screen off/on `nvt_ts_resume: fw has not been loaded`. Fixed
  with E404's version (panel_id 0x4D38324100420200: two commands, read in cmds[2]). Also switched to E404's
  `nt36532` + `xiaomi_touch` drivers (pen buttons KEY_PAGEUP/PAGEDOWN for `pen_keys.sh`, tp_common double tap, the
  modes `xiaomi_touch_ioctl` uses) and dropped liyafe's Himax driver (pipa = NT36532 on both panels).
- **walt3 (OPPO) black screen (20:19):** no adb, no self-reboot (panic timeout is -1, so it hung, not panicked). Missing
  hook found: OPPO initialises `init_task.ux_entry` in `init/init_task.c`, which the extraction list did not cover
  (also checked all 61 OPPO files with wanted symbols: block/, mm/ = UX IO/memory, not enabled; kgsl's UX workqueue
  does not apply to our kthread-worker kgsl). DBG builds now also enable softlockup/hung-task panics + panic on oops,
  because a 10 s power press is a hard reset that loses pstore.
- **walt5 = OPPO + all fixes (20:43): boots** (init_task fix was the hang), touch firmware loads (`Update firmware
  success`, fw 0x12). `/proc/oplus_scheduler/sched_assist/{debug_enabled,sched_impt_task,im_flag,im_flag_app,audio}`,
  `/proc/oplus_locking`, ux_state, sysctls work; `sched_impt_task` errors gone, binder threads get IM flags. **But
  ColorOS 17 marks almost nothing UX** (36 threads, all kernel name-matches; no app UI thread even with Settings
  open): its `libSchedAssistExtImpl.so` uses OPPO's **newer** interface: ioctls on
  `/proc/oplus_scheduler/sched_assist/{ux_task,ux_task_app,ddl_task}`, `/proc/oplus_frame_boost/{ctrl,sys_ctrl}`
  (`ofb*` ioctls), `/proc/oplus_frame_boost_async/async_perf_ctrl`, `/proc/oplus_binder/ux_flag` (binder ux ioctl),
  `/dev/sched_boost`, `/proc/sys/fbg/`; each process logs 6x ENOENT + 1x EACCES "open sharedFd failed". OPPO's 4.19
  (ColorOS 14) modules predate it (frame_ioctl.c exists but OPPO did not build it on 4.19). **Next:** port the newer
  interface from OPPO's ColorOS 16 sources, best `oppo-source/android_kernel_modules_and_devicetree_oppo_sm8450`
  branch `oppo/sm8450_b_16.0_find_x5_pro` (kernel 5.10 = closest to 4.19; also `sm8650_b_16.0.0_pad_3_pro`,
  `sm8750_b_16.0.0_pad_4_pro`). Also check the EACCES (SELinux labels for the new proc nodes come from the ROM policy).
- **E404 display/touch on the Lineage core (21:00-21:23):** walt6 crashed at 10 s (pstore text in `unused-ramoops-0`):
  CFI `dsi_display_clk_ctrl` (enum vs u32 prototype) and an oops in `dma_fence_signal_locked` (E404's sde_fence writes
  `fence->timestamp`, which is a union with `cb_list` in Lineage's dma_fence). walt7: refcount underflow in
  `drm_dev_put` (E404's preallocated `msm_atomic_state_alloc` skipped the `drm_dev_get()` that Lineage's
  `drm_atomic_state_init()` takes). Also ported: `connectors_preallocated`, E404's `drm_sysfs.c` (PCC/kdev),
  `generic_handle_irq_safe`, Xiaomi DRM master allow list (displayfeature, disp_pcc). **walt8 (21:22) boots clean:** 0
  CFI failures, no PANEL_DEAD, lockdown read at 11 s (0x53,0x42), touch firmware loaded at 11 s, root/susfs/audio/
  charging/Wi-Fi/services OK. Image `bootimg/boot-walt8-dbg-trim.img`.
- **OPPO sched_assist (branch `oppo`, worktree `port-work/kernel/walt-oppo`):** `oppo_extract.sh` (rewritten: OPPO
  symbol = OPLUS_*/VENDOR_EDIT or a CONFIG_ that no Kconfig of our tree defines; IS_ENABLED() rewritten for unifdef;
  KEEP=<dir> saves both versions) on `oppo-ref/k-sm8250_u_14.0.0_oslo` → 32 files, ~1 800 lines; applied as a **3-way
  merge** (`git merge-file ours oppo-ab/a/f oppo-ab/b/f`; `patch -F2+` misplaces fair.c hunks by 10 000 lines). 56
  conflicts, all resolved and reviewed (fair, core, rt, cpupri, walt, schedutil, binder, mutex, rwsem, workqueue, fork,
  exec, proc). Fixes: sched.h include guard, `skip_big_cluster` (OPPO declares it unguarded), HANS block in signal.c
  dropped, futex hook (commented out by OPPO) dropped, `uxchain_v2` fixed on (OPPO: random per boot, A/B test).
  Modules copied to `kernel/sched_assist`, `kernel/tuning` (frame_boost), `kernel/special_opt`, `drivers/soc/oplus/im`
  (+ include/linux symlinks); Kconfig menu in init/Kconfig, `-DOPLUS_FEATURE_SCHED_ASSIST/IM` from Kconfig in the top
  Makefile; options in `xiaomi/pipa-oplus.config` (= OPPO's defconfig minus stats/IO/memory). **Not compiled yet.**

**2026-10-23 evening: E404 r2b flashed, then the decision for the full WALT + OPPO kernel (start here)**
- **Why E404 stuttered:** ColorOS sends its boosts (app launch 2 s, scroll, first launch) to the **QTI perf HAL**
  (`vendor.qti.hardware.perf@2.2`, `/vendor/etc/perf/perfboostsconfig.xml`) as WALT controls: `sched_boost=1`
  (0x40C00000 = all tasks to big cores), migration thresholds, colocation, WALT window per refresh rate. On E404 (CASS)
  `sched_boost` is a dummy variable. The Lineage power HAL (`powerhint.json`) gets **no hints at all** (INTERACTION 0,
  LAUNCH 0 in `dumpsys android.hardware.power.IPower/default`), so editing `powerhint.json` is useless here.
  Little-core capacity is 313/1024 (30.6 %): the earlier uclamp test at 30 % was just below the line.
- **Fix on E404 = r2b (flashed 18:16):** `kernel/sched/uclamp_boost.c` (input handler like `devfreq_boost`):
  top-app + foreground `uclamp.min` 40 % from the first touch until 1.5 s after the last
  (`/sys/module/uclamp_boost/parameters/{pct,ms}`), in `maintainer/kernel/e404-pipa.patch`. Spotify spam with real
  kernel touches (`KTAP=1 maintainer/stress_switch.sh`; `input tap` bypasses kernel input handlers!): boost off
  21→25→32 % launcher / 20→25→33 % SystemUI janky (gets worse once the boot boost `sched_boost 1` from
  `init.target.rc` fades), boost on **13–15 % / 15–16 %**, stable; old joeyzhu WALT 26.9 % / 14.2 %.
  E404's `UCLAMP_ASSIST` caps `foreground` (SystemUI's group) at uclamp.max 80 %: tested, no measurable effect.
- **r3b** = r3 (Lineage lpm-levels, deep idle) + uclamp_boost, built in `port-work/kernel/e404-lpm` (Image 18:2x),
  **not packed or tested yet**; battery test (`drain_usb.sh`, 40 min) postponed by the user.
- **ColorOS "UI First" has no kernel here:** `oplus-framework.jar` `com.oplus.uifirst.OplusUIFirstManager`,
  `system_ext/lib64/libSchedAssistExtImpl.so`, libgui, the OPLUS PerformanceService and every app write OPPO's
  sched_assist / frame_boost interface: `/proc/<pid>/task/<tid>/ux_state`,
  `/proc/oplus_scheduler/sched_assist/{ux_task,ux_task_app,im_flag,im_flag_app,sched_impt_task,ddl_task,lb_enable,
  debug_enabled,audio/status}`, `/proc/oplus_binder/ux_flag`, `/proc/oplus_frame_boost/{ctrl,sys_ctrl}`,
  `/proc/oplus_frame_boost_async/async_perf_ctrl`, `/proc/sys/fbg/`, `/proc/game_opt/gpu_ctrl/*`. All fail with ENOENT
  ("Linux version 0.0.0" in logcat `PerformanceService`/`SchedAssist`), so ColorOS cannot tell any of our kernels
  which threads matter.
- **OPPO's source for exactly this:** `github.com/oppo-source/android_kernel_oppo_sm8250` and
  `.../android_kernel_modules_and_devicetree_oppo_sm8250`, branch **`oppo/sm8250_u_14.0.0_oslo`** (OPD2101 = OPPO Pad,
  SD870 like pipa, ColorOS 14, 2025-12-24, Qualcomm LA.UM.9.12 4.19 **WALT**). Local blobless/sparse clones:
  `port-work/kernel/oppo-ref/k-sm8250_u_14.0.0_oslo` (kernel: hooks) and `oppo-ref/m-oslo`
  (`vendor/oplus/kernel/oplus_performance/{sched_assist,frame_boost,im,input_boost}`; `kernel/sched_assist` and
  `include/linux/sched_assist` in the kernel repo are symlinks into it). sched_assist = ~7 000 lines; hooks in ~50
  files (fair.c 70, binder.c 49, page_alloc 23, core.c 21, rwsem 36, sysctl 19, workqueue 17, schedutil 14, block/ 30,
  proc/base 11, futex 10, mutex 9, fork 8, cpupri 8, walt.c 7, ...). It needs WALT (18 direct refs), so it belongs on
  a WALT base, not on E404/N0 (CASS).
- **Lineage `lineage-24.0` already has the full BPF backport** (kernel/bpf 44 files incl. ringbuf, bpf_iter, BTF,
  bpf_lsm, trampoline; uapi bpf.h 5268 lines, like N0/E404) on 4.19.325 with **WALT + core_ctl + CPU isolation intact**,
  and supports the Xiaomi sm8250 pads elish/enuma/dagu, but **not pipa**. Lineage patches its own userspace
  netbpfload; our ROM's prebuilt one needs a **uname spoof ≥ 5.10** for root `bpfloader/netbpfload/uprobestats/netd`
  (liyafe test: "Android 25Q4 requires kernel 5.10"; with 5.10.239 and liyafe's old BPF it fails in BTF/ENOSYS).
- liyafe (`android15-lineage22-mod`) forked Lineage at `e05f3d14` (2025-04-28) and adds 858 commits: 535 f2fs
  backports, pipa port (drm/msm and xiaomi_touch from Xiaomi `pipa-t-oss`, NT36532 touch+pen, pipa charger/fuel gauge,
  nuvolta pen charger, aw882xx amps from UtsavBalar1231 trees, defconfig `pipa_defconfig`), SukiSU. Lineage 24 has
  9 353 commits on top of the same base. Combined repo with both histories (blobless):
  **`port-work/kernel/walt-own`** (remotes `lineage`, `liyafe`; refs `lineage/lineage-24.0` 6b34d247,
  `liyafe/android15-lineage22-mod` 3ebb6338).
- liyafe on the device (test boots with `kernel/pipa_bootdbg.c`, pstore layout patch, spoof; trees
  `port-work/kernel/liyafe/out-lto`): kernel and all pipa drivers come up, init reaches second stage, display works;
  failures are only BPF. Its touch driver hangs a reboot that happens before the display is first turned on
  (`nvt_ts_shutdown` → `cancel_work_sync(get_lockdown_info)`, which waits for `dsi_panel_lockdown_info_read`): needs a
  timeout in the WALT kernel.

**Plan (user's decision 2026-10-23 evening: "do 2", the full WALT + OPPO kernel)**
1. **Base:** in `walt-own`: branch from `liyafe/android15-lineage22-mod`, `git merge lineage/lineage-24.0`, resolve
   conflicts (expect f2fs: liyafe's 535 backports vs Lineage's updates; prefer Lineage 24 where both changed upstream
   code, keep liyafe's pipa drivers/dts/defconfig). Alternative if f2fs is a mess: lineage-24.0 + cherry-pick only
   liyafe's non-f2fs commits (`git log --no-merges e05f3d14..liyafe/android15-lineage22-mod`).
   Add the uname spoof (`kernel/sys.c`, as in E404: 5.10/5.15 for root BPF loaders; check what A17 netbpfload needs
   with Lineage's BPF, start with 5.10.239 like N0). Build with `pipa_defconfig` + ThinLTO (liyafe's Image is 57 MiB in
   memory without LTO; the ABL limit is `image_size` ≤ DT load − kernel load, checked: fine), `pipa_bootdbg.c` +
   E404's pstore layout for the first tests. Test-boot (trimmed image!) until Android boots; then `stress_switch.sh`
   (KTAP=1) against joeyzhu/r2b.
2. **Our fixes:** SukiSU builtin + susfs 2.3.0 hooks (liyafe already carries an older SukiSU + susfs: compare with
   `maintainer/kernel/sukisu-pipa.patch`/`e404-pipa.patch`, keep the hook `extern` types right), `CONFIG_AUDIT`,
   ramoops layout = joeyzhu/E404, NT36532 shutdown timeout, `pipa_bootdbg` off in release. Write a
   `prepare_tree_walt.sh` like `prepare_tree.sh`.
3. **OPPO sched_assist:** `maintainer/kernel/oppo_extract.sh <oppo-kernel-tree> <out.patch>` (written, not yet run:
   uses unifdef, compile it from `liyafe/scripts/unifdef.c` with `gcc -std=gnu11`) strips all other OPLUS features and
   emits only the sched_assist/binder/locking/IM/frame_boost hooks in OPPO's context; apply with `patch -p1 -F3`, fix
   rejects; copy the module dirs from `m-oslo` (as `kernel/sched_assist`, `kernel/frame_boost`, ... with OPPO's
   Kconfig/Makefile wiring; `OPLUS_FEATURE_SCHED_ASSIST` is a `-D` define, see OPPO's Makefiles). block/ and mm/ parts
   (UX IO first, uxmem) optional, later. Then frame_boost. Verify on the device that ColorOS writes `ux_state` etc.
   (`/proc/oplus_scheduler/sched_assist/debug_enabled`, `/proc/oplus_binder/all_tasks_ux_sts`), A/B with stress_switch.
4. Bench + drain (deep idle comes with Lineage's lpm-levels) + stress, then flash (ask); E404 r2b stays the fallback.

**liyafe black screen, how it was found (2026-10-23 evening)**
- Size theory ruled out: the ABL (`firmware/abl.img`, LinuxLoader) refuses a kernel only if the arm64 header
  `image_size` > DT load addr − kernel load addr ("DTB header can get corrupted due to runtime kernel size", an error
  that lands in `/dev/logfs/UefiLog*.txt`). Load window = UEFI vars `KernelBaseAddr`/`KernelSize`; dtb goes below the
  ramdisks (boot + vendor) minus 2 MB. All logged liyafe boots reached "Start EBS" (kernel started).
- E404 r2 had **no pstore**: our ram.c port needs `ramoops_memreserve=4M` on the cmdline, which joeyzhu/liyafe have
  built in (`CONFIG_CMDLINE`) and E404 does not. Fixed by flashing **`boot-e404-r2p.img`** (same r2 kernel, boot header
  cmdline `ramoops_memreserve=4M`, md5 3d2f2a5f…; boot_b since 17:12). liyafe's own layout (2 MB console at 0xB0000000,
  no dump zone) also differs from E404's (1 MB dump, 2 MB console, 1 MB pmsg); the test build uses E404's layout.
- Test build: `liyafe/out-lto` (ThinLTO, + `kernel/pipa_bootdbg.c` from e404-dbg, pstore layout patch), image
  `bootimg/boot-liyafe-dbg-trim.img`, cmdline `pipa_bootdbg=120 pipa_bootdbg_force=1` → forced panic, warm reboot,
  log in `/sys/fs/pstore` of the next boot.
- `fastboot boot` of the full 196 MB image hung the bootloader twice in a row; the trimmed image (header + kernel +
  ramdisk, 76 MB) went through at once. Use trimmed images for tests (the old v2-trim failure was the header bug).

**Debug kit (port-work/kernel/e404-dbg, not for release):** `kernel/pipa_bootdbg.c` = watchdog that dumps tasks and panics if
no system_server after `pipa_bootdbg=` s (`pipa_bootdbg_force=1` panics anyway to keep a log), `pipa_hooks=` bitmask
switches the exec/stat/faccessat hooks. Cmdline goes into the boot header: `mkboot.sh <Image> <out> "pipa_hooks=0"`.

## What the running kernel is
- `4.19.325-cip136-st20-N0-kernel++` by joeyzhu (clang 20.1.8), no source. Name = N0 config lineage, version =
  LineageOS sm8250 `v4.19.325-cip136` base. LineageOS itself has **no pipa** support, so someone merged pipa + N0
  config onto a cip136 tree. joeyzhu could not be identified.
- Strings in `boot_b` Image: SukiSU (syscall-table hooks) + susfs (NON-GKI variant), Xiaomi `nanodev`, **no OPLUS
  drivers, no audit core**. So the ROM does not need any OPLUS kernel driver; any sound pipa kernel can boot it.
- Kernel is monolithic (`lsmod` empty). Vendor `.ko` (rmnet_perf/shs, gspca) are not loaded today either.
- Boot layout: `boot_b` = header v3, raw `Image` + 82 MB ramdisk; dtb in `vendor_boot_b`; `dtbo_b` separate.
  Backups: `kernel/backup-partitions-20261023/`.

## Candidates (all three built here with AOSP clang r547379 = clang 20, `LLVM=1 LLVM_IAS=1`, ~4–6 min)

| Kernel | Base | Activity | Perf/battery features | Root | Built here |
|---|---|---|---|---|---|
| **E404R** kvsnr113/xiaomi_sm8250_kernel_e404 `staging-bpf` (= our `RE404-…-261010` zip) | 4.19.246 (EmanuelCN line; "404R" is branding) | most active (pushes 2026-10-18, R15 release, Telegram Projkt113), pipa since 2026-05, `a17` branch | CASS scheduler, SimpleLMK, uclamp, LTO, NTsync, BBR, LZ4 zram, bypass charging, battery cut-off, BPF for A16+ | backslashxx KernelSU submodule (not SukiSU) | yes, 254 s, `4.19.404R` |
| **N0** CuriousNom/n0_kernel_pipa (`15`, `lineage-24.0-bpf`) | 4.19.246 (EmanuelCN fork) | active (2026-10-21), ready GitHub Actions builder (CuriousNom/kernel-builder) | CASS, SimpleLMK, uclamp, BBR, OC/UV, Qsync, pen-button (NT36532) fixes; BPF + uname spoof 5.10.239 | KernelSU v0.9.5 (lineage-24), KSU-Next 3.0.1 + susfs 2.0.0 (`rksu-susfs`) | yes, 295 s, `4.19.246-N0-kernel+` |
| liyafe1997/kernel_xiaomi_sm8250_mod | 4.19.325 (Lineage 22 + pipa/MIUI bits) | slower (last 2026-07) | stock Qualcomm WALT, 1 % battery-bug fix | old SukiSU (3.x manager only) + susfs | yes, 338 s, `4.19.325-perf+` |

None enables `CONFIG_AUDIT` (that is why SELinux denials never reach the log); in our own build we turn it on.
E404 `staging-bpf` dropped the old OPLUS-port mode (`drivers/oplus`, `rom_port`); its installer only aborts on
Dandaa's marker files `/vendor/OemPorts10T.prop|.rc`, which **this ROM does not have** (earlier note was wrong).
Its kernel reads `e404_args=rom_oem|rom_aosp,dtbo_…` from the cmdline (MIUI vs AOSP display/panel size): our ROM
runs the pipa MIUI vendor, so `rom_oem` + `dtbo_oem_pipa` is the likely right pick (untested).

## Root (SukiSU) facts
- Running: kernel part SukiSU 4.2.0, ksud 4.2.0 (**uapi 2**), manager v4.2.0 (40900).
- SukiSU 4.2.1 / 4.2.1-r1 moved to **uapi 6**; ksud skips post-fs-data/services/boot-completed on a mismatch
  (`pipa_susfs` would stop running). **Do not update the manager on the current kernel.** Update kernel + manager together.
- Non-GKI 4.19: SukiSU `builtin` branch (manual/inline hooks), susfs v2.3.0 via JackA1ltman/NonGKI_Kernel_Build_2nd
  `susfs_patch_to_4.19.patch` + `susfs_inline_hook_patches.sh` (known `namespace.c` `vfs_kern_mount` fix-up on CAF sm8250).
  Fallback: BakaSU (ex-ReSukiSU). tiann KernelSU and KSU-Next `dev` do not support 4.19. `ksu_susfs` userspace must match.

## Play Integrity / "toolbox"
The HyperOS port (iqraOS 1.0) bakes **Kaorios Toolbox** (`com.kousei.kaorios`): a priv-app + framework.jar hooks
(`Instrumentation.newApplication`, `hasSystemFeature`, `KeyStore2.getKeyEntry`, `AndroidKeyStoreSpi.engineGetCertificateChain`),
fed by a downloaded fingerprint + **leaked keybox**. All hook points exist in our A17 framework.jar. The project is
archived (2026-09-10), so its feed goes stale. Props/fingerprint spoofing alone gives nothing beyond BASIC on an unlocked
device; DEVICE/STRONG need a leaked keybox (revoked over time, against Google's terms). susfs is unrelated to Play
Integrity: it only hides root from apps that look for it. Details: agent report in session 2026-10-23.

## Recommendation
Base our own kernel on **E404R `staging-bpf`** (best tuning, most active, builds here), keep SukiSU by integrating
SukiSU `builtin` + susfs 2.3.0 (so the manager family stays), enable `CONFIG_AUDIT`, and use `rom_oem`/`dtbo_oem_pipa`.
Fallback base: N0 (same base, simpler, has a CI builder). Flash plan: repack `boot_b` with magiskboot (keep our
ramdisk), dtb into `vendor_boot_b`, `dtbo_b`; roll back with the backups. Take the perf baseline on the current
kernel **first** (a new kernel changes it).

## Own build, first tests (2026-10-23)
- Tree `port-work/kernel/e404-own` = E404R `staging-bpf` (9b8e5a79) + SukiSU `builtin` **7f1c299a** (newest commit with
  uapi 6 that still builds on 4.19; later commits pull in `static_call.h`, `vdso_clock_mode`, 3-arg `access_ok`) +
  JackA1ltman `susfs_patch_to_4.19.patch` (v2.3.0; 2 hunks hand-applied: `fs/proc/task_mmu.c` pagemap SUS_MAP,
  `kernel/sys.c` newuname spoof next to E404's bpfloader spoof) + `susfs_inline_hook_patches.sh` + `CONFIG_AUDIT`.
  SukiSU fixes for 4.19: guard `selinux_hide` (5.10+ only) in `ksu.c`, `policy/feature.c`, `runtime/ksud.c`; guard the
  unused `static_call.h` include; version pinned in `KernelSU/kernel/Makefile` (41010, `v4.2.1-7f1c299a@builtin`,
  else 13000 without git/API and the manager rejects it).
- Build: `bash maintainer/kernel/build_kernel.sh` (clean, ~4.5 min). A stale `out/` made ThinLTO's lld segfault once.
- Boot image: `magiskboot unpack` of `backup-partitions-20261023/boot_b.img`, swap `kernel`, `repack` →
  `port-work/kernel/bootimg/boot-e404-own-v1.img` (md5 ddfdc306…). No `e404_args` needed: on pipa the panel size then
  comes from our dtbo (308.9 dpi, same as now).
- **Test boot (`fastboot boot`, nothing written) works:** boot completes in 26 s; display 144 Hz/308.9 dpi, Wi-Fi, BT,
  audio, charging OK; susfs 2.3.0 works with `pipa_susfs` (hide mounts, sus_path /data/adb). `uname -r` = 5.10.404R
  (E404 spoof for the A17 bpfloader).
- **bench.sh A/B** (3 rounds, `port-work/perf-ab/results.csv`): current kernel launch 766/706/563 ms, janky
  0.08/0.12/0.08 %, p99 12/11/10 ms → E404 own 590/477/429 ms, 0.08/0.04/0.04 %, p99 10/9/10 ms.
- Screen-off drain with USB attached and charging paused (`input_suspend`): current kernel **71 mAh/h** (USB keeps it
  out of deep sleep; only comparable to the same method). E404 not measured yet.
- **Open: root on E404.** ksud must match (uapi 6) → `/data/adb/ksud` is now the ELF switch
  `archive/kernel-old/ksud_switch.c` (→ `/data/adb/ksud-4.2.1` on 4.19.404R, else `/data/adb/ksud-4.2.0`); a shell-script
  wrapper breaks `su` (KernelSU execs /data/adb/ksud in place of /system/bin/su). With it the boot stages run on both
  kernels. But on E404 the manager (v4.2.1-r1, cert 947ae944… = expected) was **not recognised** and `su` was not
  available: cause unknown, needs the E404 kernel log (try `/sys/fs/pstore` after rebooting back, or a root shell).
- Manager on the device: back to v4.2.0 (backup APK), working with the current kernel. `/data/adb` also holds
  `ksud-4.2.0`, `ksud-4.2.1`, `ksud-v420/`, `ksud-v421/` (test leftovers). Manager v4.2.1-r1 + ksud are in
  `kernel/sukisu-v4.2.1-r1/`.
- `fastboot boot` of the 196 MB image hung once (bootloader stopped answering; needed a power-button restart).

### v2 (2026-10-23 11:33): hook/type mismatch fixed
- JackA1ltman's `susfs_inline_hook_patches.sh` declares `extern struct static_key_true ksu_su_compat_enabled` and
  tests it with `static_branch_likely()` in `fs/exec.c`, `fs/open.c`, `fs/stat.c`, but in SukiSU builtin 7f1c299a it is
  a plain `bool __read_mostly`. The linker does not notice; at boot the jump-label code writes `key->entries` 8 bytes
  past the bool, i.e. over `cached_zygote_sid`/`cached_init_sid` (System.map neighbours). That explains v1: no `su`,
  manager not recognised. Fix: `extern bool` + `likely()`. Also `ksu_handle_sys_read` takes `(fd, &buf, &count)` here
  (hook passed only `fd`; harmless since SukiSU ignores them, fixed anyway).
- **Check this again whenever SukiSU or the hook script is updated** (compare every `extern` the script adds with
  the SukiSU definition).
- Patches to rebuild from scratch: `archive/kernel-old/e404-susfs-hooks.patch` (superseded by `maintainer/kernel/e404-pipa.patch`) (on E404 `staging-bpf` 9b8e5a79:
  susfs 2.3.0 + inline hooks + fixes) and `archive/kernel-old/sukisu-7f1c299a-4.19.patch` (superseded by `sukisu-pipa.patch`) (on SukiSU builtin 7f1c299a,
  placed as `KernelSU/`, `drivers/kernelsu -> ../KernelSU/kernel`).
- Images: `port-work/kernel/bootimg/boot-e404-own-v2.img` (md5 fedc4167…, full partition size, for flashing) and
  `boot-e404-own-v2-trim.img` (62ff820e…, 61 MB, header+kernel+ramdisk only, for `fastboot boot`). Not yet tested.

### 2026-10-23 afternoon: boot hangs and recovery (read this before the next kernel test)
- **(Wrong conclusion, see "Status": the cause was the boot header written by `magiskboot -h`, not v2.)** v2 does not boot (black screen, no USB, full or trimmed image). v1 boots. v2 only "fixed" the
  `ksu_su_compat_enabled` type, which turns on SukiSU's exec/stat/faccessat sucompat path for the first time; something
  in that path stalls early boot (before USB/`/data`). Not found yet: needs a kernel log (pstore was empty; try
  `CONFIG_PSTORE_CONSOLE` + ramoops check, or UART-less: boot with `initcall_debug`/`printk.devkmsg` and keep the
  hook off except `su`). rescue/rescue2 builds (KSUD_PATH changed / no rc injection) hang the same way → not ksud.
- **The current (joeyzhu) kernel hung on the Mi logo** after `/data/adb/ksud` was replaced by the ELF switch
  (`archive/kernel-old/ksud_switch.c`) — v1 boots fine with the switch, the old kernel did not. **Never replace
  `/data/adb/ksud`** for A/B tests again; test E404 root with a matching ksud only after flashing, or via the manager.
- **Rescue path that worked:** the boot ramdisk contains **TWRP 3.7.1** (it came up by itself after the failed boots;
  manually: Power + Volume up). TWRP adb is root (`u:r:su:s0`) and mounts/decrypts `/data` → `/data/adb/ksud` was
  restored there (`cp ksud-4.2.0 ksud; chcon u:object_r:ksu_file:s0 ksud`). TWRP's clock shows CDT (UTC-5).
- **E404 + this ROM: `gpuservice` crashes** (SIGSEGV null deref, several times per boot, tombstone_26/27). Likely BPF
  related (E404 BPF backport / uname spoof). Must be fixed before E404 can be flashed.
- `fastboot boot` of a 196 MB image hung the bootloader once; trimmed images work for transfer (`flash_kernel.sh test`).
