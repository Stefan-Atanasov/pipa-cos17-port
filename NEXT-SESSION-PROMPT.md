# Prompt for a new session

Paste the block below as the first message of a fresh Claude Code session started in `~/Documents/pipa/COS17`
(or `~`). Keep this file current when the plan changes.

```
Continue COS17 pipa maintenance (ColorOS 17 port for the Xiaomi Pad 6). Tablet on USB (serial 83836a90): ROM
beta5-2n (2026-10-24: 2j idle fix + Perfetto; 2k battery dialog; 2l stutter fix = SF off the little cores + SF
early offsets; 2m layer caching off (glitch); 2n system_server UX + speed-compiled UI apps). Taskbar on + system material blur off (my choice, smoothest). No KSU scripts, kernel walt-r5 on boot_b (2026-10-24: r4 SF RenderEngine off the little cores, r5 UX threads on big cores +
frame_rate 120; rollback bootimg/boot-walt-r4.img;
ROM rollback flash_super.sh -y beta5-2i). Goal: smooth everywhere (app open/close, shade/QS, app drawer, scrolling)
at 120 Hz, good idle drain, then release. I have the Xiaomi pen, no keyboard.

Read first: COS17/CLAUDE.md, COS17/MAINTAINER-STATUS.md, COS17/BUILD-GUIDE.md (ROM + kernel build/flash/rollback),
COS17/BUGS-TODO.md, COS17/kernel/KERNEL-RESEARCH.md ("2026-10-23 midnight" = smoothness work), HISTORY.md (last entry).
Rules: ask me for sudo password / PIN, never store them. Kernel/ROM test flashes and rollbacks: go ahead, one line
what + rollback, tell me before rebooting. Short answers. Keep tool output small.

Plan:
1. Night on 2j vs night on 2i (2i: 78->75 % in 8 h, 307 mAh screen off, SLPI asleep 27 %, AOSD 0x/CXSD 1x).
   batterystats reset 2026-10-24 09:21 at 75 %. Check dumpsys batterystats, /sys/power/system_sleep/stats,
   /sys/power/rpmh_stats/master_stats (SLPI). Next idle levers: com.heytap.accessory BLE scans, deviceidle_maint.
2. Optional ROM 2o: SELinux for OPPO's perf daemon (proc_version read + labelled scene nodes) and frame_rate =
   refresh rate (measured neutral so far, see KERNEL-RESEARCH "2026-10-24 late afternoon"); binder ux_flag port.
   Phantom "Xiaomi Keyboard configured" notification (BUGS-TODO 11).
3. Smoothness next levers (after 2l: launcher Buffer Stuffing / App Deadline, long DRM commits, CLIENT layers; measure with maintainer/perfetto/traced_heavy.sh after 60 s settle) (measure with maintainer/heavy_mix.sh, 2 runs, POWER=1; why with maintainer/perfetto/,
   FrameTimeline now possible): launcher GPU load + ColorOS "Blur" GPU context, launcher Buffer Stuffing,
   display commit on SF main thread. Ruled out: clocks, DDR/LLCC bandwidth, 120 vs 144 Hz, SF Vulkan, HWUI GL,
   OPPO mid-tier anim/blur levels, SystemUI UX, rounded-corner overlay.
4. Release package (BUILD-GUIDE.md section 3: build_release.sh <newest ROM step> + walt-r5 boot.img) + clean-flash test.
```
