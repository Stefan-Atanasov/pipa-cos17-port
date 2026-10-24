# Maintainer status (current state)

Short and kept up to date. The full work log (every step, md5s, evidence) is `HISTORY.md`.
Last updated: 2026-10-24 14:30 (kernel **walt-r5** + ROM **beta5-2n**; release prep). Before: 2026-10-24 12:15 (**kernel walt-r4** + ROM **beta5-2l**: stutter fixes, SF frames on time 59 -> 92 %; see kernel/KERNEL-RESEARCH.md "2026-10-24 midday"). Before: 2026-10-24 09:25 (**ROM beta5-2j** flashed: keyboard guard = overnight idle fix, loc_sys_service disabled, SF layer caching/HWC prediction in the ROM, Perfetto works; KSU scripts retired). Before: 2026-10-24 01:10 (kernel walt-r3 = SurfaceFlinger GPU priority fix, pushed; smoothness session, see "To do" 0/1). Before: 2026-10-23 22:50 (walt-r2 + ROM 2i, UI First works, kernel source on GitHub). Before that: 2026-10-23 21:45 (**own WALT kernel flashed** on boot_b: Lineage 24 core + liyafe pipa drivers + E404 display/touch + SukiSU/susfs + uclamp; battery 62.5 mAh/h vs E404 98.7; recipe `kernel/WALT-KERNEL.md`; next: ColorOS 17 UI First interface on branch `oppo`).

## What runs on the tablet

- **ROM beta5-2n** (2026-10-24 13:07, super md5 `ece2e9e11c2506b86efde8e6fb28d8df`). Layers on top of the C.06 rebase
  (one line each; evidence in `HISTORY.md` and `kernel/KERNEL-RESEARCH.md`):

  | Step | md5 (super) | Adds |
  |---|---|---|
  | 2g | `79add8ff…` | AudioX retry loop disabled (sysconfig) |
  | 2h | `82c48b04…` | null guards in OPPO's gpuservice extension (needed with our kernel) |
  | 2i | `d9c5bb8a…` | SELinux labels/rules for the UI First proc nodes |
  | 2j | `f5c63fab…` | keyboard guard (idle drain), `loc_sys_service` disabled, Perfetto works (no vsock relay) |
  | 2k | `c4d33757…` | charger shim reports the battery genuine |
  | 2l | `b517e27b…` | SurfaceFlinger off the little cores (pipa_port `SF_BIG_CORES`), SF early offsets + predict_hwc in product |
  | 2m | `989d94be…` | SF layer caching off (Settings search glitch) |
  | 2n | `ece2e9e1…` | system_server animation threads as UX, UI apps speed-compiled, `dalvik.vm.systemuicompilerfilter=speed` |

  Rollback: `sh maintainer/flash_super.sh -y beta5-2m` (any name in `flash_super.sh`).
- **Kernel walt-r5** on boot_b (2026-10-24 14:25, `port-work/kernel/bootimg/boot-walt-r5.img`, md5
  `bbc576523eb15649520b3ccd97200c15`, branch `oppo` 07c07a536bc1, public `oppo` 14710e930108): Lineage `lineage-24.0` core
  (WALT) + liyafe's pipa drivers + E404 display/touch + SukiSU builtin/susfs 2.3.0 + OPPO UI First + our fixes (kgsl
  SF priority r3, RenderEngine placement r4, `kernel.ux_prefer_big` + `frame_rate` 120 r5). Rollbacks
  `boot-walt-r4.img` (`e1dc8fec…`), `boot-walt-r3.img`, `boot-walt-r2.img`, E404 `boot-e404-r2b.img`; original joeyzhu
  kernel: `flash_kernel.sh restore`. Recipe: `kernel/WALT-KERNEL.md`.
- **Root:** SukiSU-Ultra manager/ksud **4.2.1-r1** (uapi 6, matches our kernel; backups `kernel/sukisu-backup/`), Shell
  granted. Module `pipa_susfs` (root hiding, `pipa-susfs-v1.0.zip`) only; it can only be judged from a real app process.
- **No KernelSU module is needed.** Everything the port needs is in the ROM:
  - `/system_ext/pipa_port/` + `/system_ext/etc/init/pipa_port.rc`: services `pipa_port` (`service.sh`: face HAL + crop
    + rotation, charger shim, pen wake/buttons/watcher, keyboard guard, SF scene, system_server UX, one-time speed
    compile, colour/adaptive/bedtime restore, defaults) and `pipa_subsys0/1` (virtual modem HALs). Switches:
    `config.prop`, user overrides `/data/misc/pipa_port/config.prop`. Domain `pipa_port` is **permissive**.
  - **pipa helper app** (`com.port.pipa.helper`, persistent priv-app): Dolby keeper (B10), pen pill and low-battery
    notification (B3), "lock with cover" → `lid_behavior` (B14).
  - Image fixes: boot rotation + logo (B13), native pen 120 Hz lock, OTA updater removed, Dolby/audio/QDCM/brightness
    files baked (`PATCH-INVENTORY.md`).
- **User settings on this tablet (live, not ROM defaults):** launcher taskbar on + `system_material_blur_enable 0`
  (smoothest); `svc power stayon usb` during test series (turn off with `svc power stayon false`). Full list: `README.md`
  "What was changed on the device".

## Build chain (each step is a script on top of the previous image)

`build_beta5.sh` (plain C.06 rebase) → `build_beta5_baked.sh` → `_1c` → `_2a` … `_2n` in `maintainer/`, each `sudo sh …`,
output in `$PIPA_ROOT/port-work/<step>/`. Recipe, adding a layer, flashing, rollback: **`BUILD-GUIDE.md`**. Sources the
steps copy in: `helper/`, `port-rom/`, `maintainer/bootanim/`, `maintainer/uifirst-policy/`, `port-module/src/facecrop.c`;
port edit list `maintainer/c06-vs-beta4/PORT-EDITS.tsv`. Every text edit needs its anchor exactly once.

**One command for all steps / a new base:** `sudo sh maintainer/build_port.sh <tag> <donor-img-dir> [first] [last]`
(`--check` = preflight only; passes for every step 2026-10-24). On a new donor the first two steps stop at their
stock-md5 checks on purpose: regenerate from the new files, update the md5, resume with the first-step argument.
Scripts take `PIPA_ROOT` (default `/home/stefan/Documents/pipa`) and `PIPA_OWNER` (default `stefan:stefan`).

## Bugs (details and evidence: `BUGS-TODO.md`)

| Status | Items |
|---|---|
| Fixed in the ROM (verified on the tablet) | B3 pen pill/battery and "stylus connected" (2f), B6 pen 120 Hz, B7 face preview, B10 Dolby at boot, B12 pen buttons (2f), B13 boot rotation + logo, B14 magnetic case, interconnect HAL rule (B9 part); 2026-10-24: idle drain from `xiaomi-keyboard` (2j), GNSS loop (2j), Perfetto (2j), battery "not genuine" dialog (2k), stutter/dropped frames (2l + walt-r4/r5), Settings search glitch (2m), QS -> Settings launch (2n) |
| Open | clean-flash test of the release, night drain on 2j+, **B9** network sharing, **B8** privacy password / app lock, B1 Wi-Fi recovery, B2 UI behind navbar, B11 idle refresh rate (parked), face enrollment `crop_eyes` crash, phantom keyboard notification (11), OPPO perf daemon SELinux (optional) |

## Start of a session (2 minutes)

1. `adb devices` (USB serial `83836a90`); `mountpoint /mnt/reference` (builds need the HDD); `df -h ~/Documents/pipa/port-work` (each ROM layer ~7 GB).
2. `adb -s 83836a90 shell getprop ro.build.display.id`; `cat /proc/version` (ours: `4.19.325-cip136-st20-perf-g<commit>`, walt-r5 = `g07c07a536bc1`); `ls ~/Documents/pipa/port-work/` (newest `beta5-2n`).
3. Read this page, `BUILD-GUIDE.md`, then `BUGS-TODO.md` (table at the top). Passwords and the lock PIN are asked again every session and never stored.
4. SukiSU manager/ksud 4.2.1-r1 (uapi 6) match the kernel. If the tablet does not boot: TWRP (Power + Volume up) has root adb and decrypted `/data`; `maintainer/kernel/flash_kernel.sh restore` writes the partition backups.

## Sharing / publishing (2026-10-24)

- Kernel source (GPL): https://github.com/Stefan-Atanasov/kernel_xiaomi_pipa_cos17, branch `oppo` (README, `build-pipa-cos17.sh`, `pack-boot.sh`). Publish new kernel commits by cherry-picking onto `pub/oppo` in `port-work/kernel/walt-own` and `git push origin pub/oppo:oppo`; save the bundle (`prepare_tree_walt.sh --save`).
- Port scripts/sources/docs (public, no blobs, no signing key): https://github.com/Stefan-Atanasov/pipa-cos17-port, updated with `sh maintainer/sync_port_repo.sh "message"` (repo tree `port-work/port-repo`; excluded blobs listed in its `BLOBS.md`).
- Full private kit for a co-maintainer (with blobs, without the helper signing key): `sh maintainer/make_port_kit.sh` -> `port-work/release/pipa-cos17-port-kit-<date>.tar.gz`.
- User release: `bash maintainer/build_release.sh beta5-2n --boot <boot-walt-r5.img> --name "..." --7z` -> `port-work/release/ColorOS17-Port-pipa-beta5-2n-<date>/` (+ `.7z`), notes = `RELEASE-NOTES-beta5.md`.
- The helper keystore password lives in `helper/keys/keystore.pass` (private, next to `pipa-helper.jks`); `helper/build.sh` reads it.

## To do (prioritised; bug details in `BUGS-TODO.md`)

**Next session (in this order)**
1. **Clean-flash test** of the release package (the user runs `FlashLinux.sh` with wipe), then publish it (Telegram).
2. **Night drain on 2j+** (batterystats reset 2026-10-24 09:21 at 75 %; previous night 2i: 78 -> 75 % in 8 h with SLPI
   asleep only 27 %): check `/sys/power/system_sleep/stats` and `/sys/power/rpmh_stats/master_stats`.
3. **Optional ROM 2o:** SELinux for OPPO's perf daemon (`proc_version` read + labelled scene nodes), binder ux_flag in
   the kernel (KERNEL-RESEARCH "2026-10-24 late afternoon"); measured neutral so far.
4. **Leftover bugs:** phantom keyboard notification (11), B9, B8, B1, B2, face `crop_eyes`, B11.
5. **Companion app v0.5** (`helper/COMPANION-APP-PROPOSAL.md`).

**Later**
4. B9 network sharing (needs logs from the phone while a share is attempted), B8 privacy password/app lock (`ICryptoeng` shim; same problem blocks ColorOS app lock), B1 Wi-Fi recovery (`gEnableForceTargetAssert`), B2 UI behind the navigation bar, face enrollment `crop_eyes` crash, B11 idle refresh (needs an `IDisplayPanelFeature` shim).
5. Enforcing SELinux for `pipa_port`: boot trace with `avc_trace.sh` (the tracer starts only after boot; arm it as early as possible, restart the services to re-trigger), write the rules, drop `typepermissive` in `build_beta5_2e.sh`'s policy block.
6. Colour/adaptive/bedtime restore into the ROM (find and patch the resetters), OPPO Notes pen bridge, the first untested rebase on a real new donor with `build_port.sh`.
7. Root extras: Play Integrity stays BASIC (see above); nothing to do.

### Kernel
Own WALT kernel since 2026-10-23 (now walt-r5): recipe and updating `kernel/WALT-KERNEL.md`, all evidence and A/B
results `kernel/KERNEL-RESEARCH.md`. The 2026-10-23 research on the original joeyzhu kernel and E404R is kept there.

### Companion app (research, idea)
**Research done 2026-10-23: `helper/COMPANION-APP-PROPOSAL.md`** (closest model PipaControls; v0.5 = separate non-persistent priv-app with Pen / Display / Status pages, Settings.Global `pipa_*` keys whitelisted in `service.sh`; check `settings get` in the `pipa_port` domain first).
Today the pipa helper app has no UI. A settings app for the port would let users switch things without root: pen button actions (now `keys.conf`), pen 120 Hz lock and the pen pill (+ low-battery threshold), lock-with-cover (ColorOS's own switch already drives it), keyboard-case behaviour, refresh-rate modes (B11 option B, interaction-based like Adaptive-Hz), performance/battery profiles (the `perf-test-module` flags), colour/adaptive restore, Dolby default, and a status page (pen battery, face HAL, services). Architecture question for the research: the helper is an ordinary-uid priv-app with `WRITE_SECURE_SETTINGS`, so the channel to the root service `pipa_port/service.sh` is `Settings.Global` keys (`pipa_*`) that the script reads (it already reads `pipa_pen_state` the other way); `/data/misc/pipa_port` is root-only. Also check what community apps exist (`~/Documents/pipa/pipa_pen_fix_v1.3.zip` is one).

## Rebuild everything from scratch (new machine or lost work trees)

1. **Inputs:** this COS17 folder (scripts, ROM sources `port-rom/`, `helper/`, patches, `kernel/walt-own.bundle`,
   `kernel/backup-partitions-20261023/`), the beta4 release 7z (firmware) and the donor OPD2515 C.06 images
   (`../donor/OPD2515_11.C.06/`; HDD `/mnt/reference` holds a second copy).
2. **ROM:** `sudo sh maintainer/build_port.sh <tag> <donor-img-dir>` runs every layer (base → baked → 1c → 2a … 2n) and
   prints the checklist; `maintainer/flash_super.sh -y <tag>` flashes super to slot B. Details: `PORT-MAINTAINER.md`.
3. **Kernel (own WALT):** `bash maintainer/kernel/prepare_tree_walt.sh` (clones Lineage + liyafe, restores our branches
   from the bundle), `build_walt.sh`, `mkboot.sh`, `flash_kernel.sh` (all in `kernel/WALT-KERNEL.md`). The E404 r2b
   fallback: `maintainer/kernel/prepare_tree.sh` + `build_kernel.sh` (E404 + `e404-pipa.patch` + `sukisu-pipa.patch`).
4. **Root extras:** SukiSU manager v4.2.1-r1 (`kernel/sukisu-backup/`), `pipa-susfs-v1.0.zip`.
5. Save the kernel bundle after every kernel commit session: `bash maintainer/kernel/prepare_tree_walt.sh --save`.

## Disk and artifacts

- `port-work/<tag>-<step>/` per layer (tree + images, ~7 GB each by `du`, btrfs reflinks share most); the newest is the
  base of the next layer. 23 GB free on 2026-10-24: delete old steps' `tree/` and `img/` except `img/super.img` of
  the rollback targets you want to keep (check `flash_super.sh`).
- `port-work/release/`: user packages, the port kit. `port-work/port-repo/`: the public repo tree. `port-work/traces/`:
  perfetto traces (~400 MB each; delete old ones). `port-work/kernel/bootimg/`: kernel images (walt-r1 … r5, E404).
- Tablet `/data/local/tmp`: live service logs, test helpers (`kgest`, `recpu.sh`, `ss_ux.sh`, `thr.sh`), retired KSU
  scripts in `ksu-retired/`.

## Device state and rules

- ADB over USB `83836a90` (TCP `192.168.0.37:5555` after enabling). Root via KernelSU. See `CLAUDE.md`.
- Ask before flashing, wiping or other persistent changes; tell the user before rebooting. Sudo password and
  PIN: ask each session, never store them.
- `README.md` ("What was changed on the device") lists every live change and its persistence.
- Downloads, archives and scratch: HDD `/mnt/reference` (symlinks); builds in `~/Documents/pipa/port-work/`.
  Check `mountpoint /mnt/reference` before builds.

## Doc map

| Doc | Purpose |
|---|---|
| `BUILD-GUIDE.md` | build, test, flash and roll back the ROM and the kernel (start here for any build) |
| `MAINTAINER-STATUS.md` | this page |
| `NEXT-SESSION-PROMPT.md` | ready-to-paste first message for the next session (plan, rules, what to read) |
| `kernel/WALT-KERNEL.md` | recipe for our own WALT kernel: sources, rebuild from scratch, checks, updating |
| `kernel/KERNEL-RESEARCH.md` | kernel research, test results and evidence (E404, liyafe, WALT, OPPO) |
| `HISTORY.md` | full log from 2026-10-22 on: every build/flash with md5s, findings, session notes |
| `BUGS-TODO.md` | bug list with causes, tests and fixes; `maintainer/bugs/*.md` offline analyses |
| `CLAUDE.md` / `AGENTS.md` | guidance for AI agents (keep the two consistent) |
| `PORT-MAINTAINER.md` | how to rebase on a new donor build (layer model, erofs/super parameters, checks) |
| `PATCH-INVENTORY.md` | what the port changed vs the donor (S/U/R/M IDs) |
| `PHASE2-ROM-INTEGRATION.md` | design notes for moving runtime fixes into the ROM (done through 2e) |
| `STABILITY-PERF.md` | stability/performance plan, captures D1–D17 |
| `RELEASE-NOTES-beta5.md` | user release notes (copied into the release package) |
| `maintainer/port-repo/` | README + BLOBS of the public port repo (`sync_port_repo.sh`); `maintainer/make_port_kit.sh` = private kit |
| `README.md` | the original device audit (kept as record) with the device-changes table |
| `module/README.md` | developer write-up of every fix (display, audio, adaptive colour, pen); the main technical document |
| `HANDOFF*.md`, `perf-test-module/README.md`, `maintainer/jar-edits/REPORT.md` | reference |
| `archive/` | superseded files and old module zips (power-tune, pipa_core 1.11, pipa_port 1.0–1.2) |
