# Kernel

The port uses an own kernel (Linux 4.19.325). The public release v9 (2026-11-19) has
`walt-hi9`: SukiSU Nova 3.0.0 (builtin, commit `4bec532d`, kernel version 30691; manager package `com.sukisu.nova`), susfs 2.3.0.
The branch `oppo` of https://github.com/Stefan-Atanasov/kernel_xiaomi_pipa_cos17 has the hi9 source.
Test build `walt-hi11` (2026-11-20, for testers, not released): branch `hi11-test` = hi9 + hi10 (MDP boost also after a
refresh-rate rise, BUGS 48) + hi11 (keyboard Caps Lock LED, BUGS 151).
beta7, beta7.1 and beta7.2 had `walt-r17` (SukiSU-Ultra v4.3.0-r1, KSU 41140).

Changes since beta6 (`walt-r8kpm`): touch charger mode (r9, touch lag while charging), the binder UX node of ColorOS
16+ (r10), DisplayPort fixes for USB-C monitors (r11-r15: 8 bpc, the highest refresh rate the link allows), OPPO's
`/proc/shell-temp` for the horae thermal service (r16), SukiSU-Ultra v4.3.0-r1 (r17). KPM is not patched since r14.
After an update from beta6 to a SukiSU-Ultra kernel (r8 to r26), open the SukiSU manager once and let it update `ksud`. With v9 the ROM installs the SukiSU Nova manager itself.

Changes since `walt-r26`: hi1 healthinfo-lite; hi3 `gpu_comp_static=1`; hi5 the NT36532 touch features are sent again after the resume firmware download; hi8 a boost of the MDP clock and bandwidth when the refresh rate drops (O+ Connect underruns); hi9 SukiSU Nova (SukiSU-Ultra was renamed SukiSU Nova). After an update from a SukiSU-Ultra kernel, the SukiSU Nova manager installs its own `ksud`.

## 1. Parts

| Part | Source |
|---|---|
| Core kernel (WALT scheduler, BPF, f2fs, memory, network, binder) | LineageOS `android_kernel_xiaomi_sm8250`, branch `lineage-24.0` |
| pipa device drivers | liyafe1997 `kernel_xiaomi_sm8250_mod` |
| Display and touch | E404R kernel |
| Root | SukiSU Nova 3.0.0 (built in; since walt-hi9), susfs 2.3.0; SukiSU-Ultra v4.3.0-r1 in walt-r17 to r26; KPM only in walt-r8kpm to r13 |
| OPPO UI First scheduler (`sched_assist`, frame boost) | OPPO open-source sm8250 kernel |
| OPPO Hans app freezer channel (netlink 29, binder/signal/network reports) | OPPO open-source sm8250 kernel (OPD2101, ColorOS 14) |

## 2. Branches

| Branch | Contents |
|---|---|
| `oppo` | The kernel that the port uses (with OPPO UI First). |
| `own` | An older base (walt-r7 level, SukiSU 4.2.1) without the OPPO code (UI First, Hans), without `ovnet` and without SukiSU 4.3.0 and KPM. Not for beta6. |

## 3. Settings

| Setting | Default | Function |
|---|---|---|
| `kernel.ux_prefer_big` | 1 | UX UI threads start on the big CPU cores. 0 gives the OPPO behaviour (only during scrolling). |
| `kernel.frame_rate` | 120 | Frame rate for the UX frequency calculation. |
| `kernel.sched_assist_scene` | set by `pipa_port` | UI First scene. Bit 8 keeps SurfaceFlinger off the little cores. |

To change a setting until the next reboot, use root: `echo 0 > /proc/sys/kernel/ux_prefer_big`.

Hans: ColorOS's `/system_ext/bin/hans` reads `uname()`. Below 5.10 it uses netlink protocol 29 (this kernel); from
5.10 on it uses the generic netlink family `oplus_hans`. The kernel reports 5.10 to apps (Android 17 BPF loaders),
but gives the `hans` process the real 4.19 release. Without this channel, Hans turns itself off and ColorOS also
blocks the Android freezer: no app is frozen. Check: `getprop sys.hans.enable` = `true`.

## 4. Requirements

- ROM beta5-2i or newer. Older ROMs do not have the SELinux rules for the UI First nodes.
- SukiSU-Ultra manager 4.2.1-r1 (walt-r6, walt-r7) or v4.3.0 (41100) (walt-r8 and later). walt-hi9 needs the SukiSU Nova manager `com.sukisu.nova` (the ROM v9 has it, step 7u).
- Do not run a live `ksud sepolicy patch` on walt-r8kpm: it hung the kernel (watchdog reset).

## 5. Build

- Compiler: AOSP clang r547379 (clang 20).
- Use the build script in the kernel repository (`build-pipa-cos17.sh`). Refer to its `README.md`.
- KPM: after the build, patch the `Image` with KernelPatch `kptools` (procedure in the kernel `README.md`). The build
  scripts do not do this step. Without it, you get `walt-r8` without KPM. KPM is off in `walt-hi9`.
- Pack the `Image` into a pipa `boot.img`. `pack-boot.sh` (kernel repository) takes your own `boot.img`.
  `maintainer/kernel/mkboot.sh` takes the maintainer's partition backup (`BK`, not in this repository) and
  `magiskboot` in `K`/`bootimg/`. Refer to [BUILD.md](BUILD.md), section 4.

WARNING: Pack the kernel only with `pack-boot.sh` (kernel repository) or `maintainer/kernel/mkboot.sh`. A
`magiskboot repack` alone changes the patch level, and the tablet does not boot.
