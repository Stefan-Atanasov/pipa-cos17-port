# Our own WALT kernel for pipa (ColorOS 17 port): how it is made, rebuilt and updated

Status, test results and the history of why each piece is there: `KERNEL-RESEARCH.md` ("2026-10-23 night").
This page is the recipe. Everything here works on a fresh machine with the COS17 folder and internet access.

## What it is

| Part | Source | Rule |
|---|---|---|
| Core kernel (fs incl. f2fs, sched/WALT, mm, net, BPF backports, binder, lib, crypto, drm core) | LineageOS `android_kernel_xiaomi_sm8250` branch `lineage-24.0` (4.19.325-cip136) | always Lineage; update by merging |
| pipa device drivers (charger/fuel gauge, pen charger, aw882xx amps, aw8697 haptic, camera techpack, dts, config fragments) | liyafe1997 `kernel_xiaomi_sm8250_mod` branch `android15-lineage22-mod` | ours = liyafe's |
| Display (`techpack/display`) + touch (`drivers/input/touchscreen/{nt36532,xiaomi}`) | our E404 tree (`port-work/kernel/e404-own`, kvsnr113 E404R `staging-bpf` 9b8e5a79) | E404's: proven on this panel + ROM (lockdown read, ESD, pen keys KEY_PAGEUP/DOWN, tp_common) |
| Root | SukiSU-Ultra branch `builtin` 7f1c299a (vendored in `KernelSU/`) + `maintainer/kernel/sukisu-pipa.patch`, susfs 2.3.0 hooks | from our E404 r2b tree |
| ColorOS "UI First" (branch `oppo` only) | oppo-source `android_kernel_oppo_sm8250` + `android_kernel_modules_and_devicetree_oppo_sm8250`, branch `oppo/sm8250_u_14.0.0_oslo` (OPPO Pad, SD870, ColorOS 14) | extracted with `maintainer/kernel/oppo_extract.sh`, 3-way merged |

Our commits on top (see `git log own`): uname spoof for the A17 BPF loaders (`kernel/sys.c`), pstore layout,
`CONFIG_PIPA_BOOTDBG` boot watchdog, aw882xx/tfa98xx include paths, bq2597x casts, config fragment
`arch/arm64/configs/vendor/xiaomi/pipa-cos17.config` (AUDIT, uclamp, CFI permissive, no Himax), lockdown read fix,
E404 display/touch + the three core bits it needs (`connectors_preallocated` in drm_atomic, `drm_sysfs.c` PCC/kdev,
`generic_handle_irq_safe`), SukiSU/susfs hooks (susfs mount hook in `vfs_create_mount()`).

## Repositories on disk

- `port-work/kernel/walt-own` (branch `own`), worktrees `walt-oppo` (branch `oppo` = own + OPPO) and `walt-ksu` (old).
  Remotes `lineage`, `liyafe` (blobless). Our commits are also saved in **`COS17/kernel/walt-own.bundle`** (only our
  objects; upstream comes from GitHub). Save after every commit session:
  `bash maintainer/kernel/prepare_tree_walt.sh --save`.
- Reference trees: `e404-own` (E404 r2b = flashed fallback), `oppo-ref/` (OPPO sources, sparse), `liyafe`, `lineage24`.
- Toolchain `port-work/kernel/clang-r547379` (AOSP clang 20); `port-work/kernel/tools/unifdef`
  (`gcc -std=gnu11 -O2 -o tools/unifdef walt-own/scripts/unifdef.c`).

## Rebuild from scratch (new machine or lost tree)

```sh
cd ~/Documents/pipa/COS17
bash maintainer/kernel/prepare_tree_walt.sh            # clones Lineage + liyafe (blobless), restores own/oppo from the bundle
DBG=1 bash maintainer/kernel/build_walt.sh             # base (own); ~15 min clean with ThinLTO + CFI
TREE=~/Documents/pipa/port-work/kernel/walt-oppo DBG=1 bash maintainer/kernel/build_walt.sh   # with OPPO UI First
TRIM=1 bash maintainer/kernel/mkboot.sh <tree>/out/arch/arm64/boot/Image port-work/kernel/bootimg/boot-X-trim.img "pipa_bootdbg=150"
bash maintainer/kernel/flash_kernel.sh test port-work/kernel/bootimg/boot-X-trim.img     # fastboot boot, nothing written
bash maintainer/kernel/mkboot.sh <Image> port-work/kernel/bootimg/boot-X.img ""          # full image for flashing
bash maintainer/kernel/flash_kernel.sh flash port-work/kernel/bootimg/boot-X.img
```
Release builds: drop `DBG=1` (no boot watchdog, no lockup panics). Never pack with `magiskboot -h` alone (boot header
patch level; see `KERNEL-RESEARCH.md`). Config = `kona-perf_defconfig` + `sm8250-common.config` + `pipa.config` +
`pipa-cos17.config` (+ `pipa-oplus.config` on oppo) via `merge_config.sh` inside `build_walt.sh`; liyafe's
`pipa_defconfig` is not used.

After a flash: the SukiSU manager v4.2.1-r1 (ksud 4.2.1-r1, uapi 6) matches this kernel, same as E404 r2b.

## Checks after a boot

- `ADB="adb -s 83836a90" sh maintainer/kernel/kernel_check.sh <label>` (root, susfs, audit, input, display, battery)
- `sh maintainer/kernel/oplus_check.sh` (OPPO procfs nodes, UX threads, ColorOS open errors)
- touch: `dmesg | grep NVT-ts` must show `Update firmware success`; no `fw has not been loaded`
- display: no `esd check failed report PANEL_DEAD` loop
- `ADB=... OPEN=0.4 FL=0.2 GAP=0.2 sh maintainer/heavy_mix.sh <label> 10` (main smoothness test since 2026-10-23:
  clean start, Spotify + live alert, apps with flings, shade/QS, pill, drawer, fast bursts, all through `kgest` real
  touch; run it twice, spread ±3 %); why frames are late: `maintainer/perfetto/` (needs `traced`, see
  `KERNEL-RESEARCH.md` "2026-10-23 midnight"),
- `KTAP=1 ADB=... ICONS=Spotify OPEN=0.3 GAP=0.2 sh maintainer/stress_switch.sh <label> 30` (older Spotify spam test),
  `sh maintainer/kernel/drain_usb.sh <label> 40` (battery, screen off, USB, charging paused)
- If it does not boot: wait 3 min (DBG builds panic and warm-reset to the flashed kernel, log in
  `/sys/fs/pstore`); a 10 s power press is a hard reset and loses pstore.

## Updating later

- **Lineage update:** in `walt-own`: `git fetch lineage && git merge lineage/lineage-24.0`. Conflict rule: core = Lineage,
  device drivers/techpack/dts = ours. Then `git -C ../walt-oppo merge own`, build, test, `prepare_tree_walt.sh --save`.
  (Lineage may move to a new branch name; check `git ls-remote --heads $LINEAGE`.)
- **SukiSU update:** replace `KernelSU/` with `git -C <sukisu clone> archive <ref> kernel LICENSE`, re-apply
  `sukisu-pipa.patch`, re-check every hook `extern` type against SukiSU's definitions (a mismatch links fine and
  corrupts memory), bump the version pin in the patch, and update the manager together with the kernel.
- **susfs update:** re-extract the hooks from a working tree with `oppo_extract.sh` (WANT = CONFIG_KSU* symbols) or
  apply the new susfs 4.19 patch and fix rejects.
- **OPPO update / newer UI First:** `oppo_extract.sh <oppo tree> <our tree> out.patch` with `KEEP=<dir>`, then per file
  `git merge-file -L ours -L base -L oppo <ours> <dir>/a/<f> <dir>/b/<f>`, `maintainer/kernel/merge_resolve_ws.py` for
  the whitespace-only conflicts, the rest by hand, then `maintainer/kernel/verify_merge.py` (every hunk landed); check files outside the list with `git grep -l <wanted symbols>` (init/init_task.c was
  missed once and hung the boot). ColorOS 17 needs the newer interface (`ux_task` ioctls, `oplus_frame_boost/ctrl`,
  `oplus_binder/ux_flag`): port it from `oppo-source/android_kernel_modules_and_devicetree_oppo_sm8450` branch
  `oppo/sm8450_b_16.0_find_x5_pro` (5.10).
  **Done 2026-10-23 (walt13/walt-r2):** `kernel/sched_assist/sa_ux_task.c` (ux_task ioctls) + frame_ioctl + `/proc/sys/fbg`;
  needs ROM beta5-2i (SELinux for the nodes, `maintainer/uifirst-policy/`). Not ported: ddl_task, /dev/sched_boost,
  binder ux ioctl, async_perf_ctrl.
- **uclamp vs schedtune:** our config uses uclamp, which turns schedtune off. WALT's frequency path, colocation and
  boosts are wired to uclamp in `own` (825c52f8: `stune_util()`, `cpu.uclamp.colocate`, `uclamp_boosted()`). After a
  Lineage merge check that `kernel/sched/tune.h` still does not define `stune_util` as `cpu_util_cfs` for WALT, and that
  `/dev/cpuctl/top-app/cpu.uclamp.colocate` reads 1.
