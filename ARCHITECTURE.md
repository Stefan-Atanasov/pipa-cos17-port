# Architecture

This document tells how the port is put together.

## 1. Partitions

| Part | Contents | Source |
|---|---|---|
| Firmware | Bootloader, modem, DSP, `vendor_boot`, `dtbo`, `vbmeta*` | beta4 release, not changed |
| Kernel (`boot`) | Own kernel `walt-r6` | [KERNEL.md](KERNEL.md) |
| `vendor`, `odm` | pipa device side with port edits | beta4 release, not changed by a rebase |
| `system` (with the donor `my_*` folders), `system_ext`, `product` | ColorOS 17 | donor OPD2515 C.06 and the build steps below |

All content is in slot B. The `_a` partitions are empty. `vbmeta` has verification off, so the images need no
signature.

## 2. ROM build steps

The steps live in `maintainer/port/steps/` as `NN-<step>-<name>.sh`. The step names are the same as the names of the old
layer scripts. `maintainer/port/port.sh` runs them in order of `NN` in one tree:

1. It extracts the donor and the pinned beta4 `vendor` and `odm` one time.
2. It runs all steps. Each step edits the tree.
3. It checks the SELinux labels, makes one image for each partition (`mkfs.erofs`) and makes `super.img` (`lpmake`).

The default last step is 3p. `--until <step>` stops after a step (`--until 3h` gives the 3h content).
Step 2u is off by default (`PORT_WITH_2U=1` turns it on).

Before `port.sh`, each layer was a script `maintainer/build_beta5_<step>.sh`. It read the images of the previous layer
and wrote `port-work/<tag>-<step>/`. `maintainer/build_port.sh` ran them in sequence. These scripts stay in the
repository as history and as a way to test one fix on top of the newest image. The column "Script" gives the old
layer script of each step.

| Step | Script | Contents |
|---|---|---|
| base | `build_beta5.sh` | Donor `system`, `system_ext`, `product` and the port edits in `maintainer/c06-vs-beta4/PORT-EDITS.tsv`. |
| baked | `build_beta5_baked.sh` | Files of the older module: panel colour (QDCM), audio curves, brightness table, patched `oplus-services.jar`. |
| 1c | `build_beta5_1c.sh` | GNSS service off, pen sysfs permissions. |
| 2a | `build_beta5_2a.sh` | Old FaceUnlock app and AOD removed. |
| 2b | `build_beta5_2b.sh` | Keyboard drain patch, pen sysfs init file. |
| 2c | `build_beta5_2c.sh` | Interconnect SELinux rule, native pen 120 Hz lock. |
| 2d | `build_beta5_2d.sh` | pipa helper app (first form). |
| 2e | `build_beta5_2e.sh` | `pipa_port` service in the ROM, boot rotation and logo, helper app. |
| 2f | `build_beta5_2f.sh` | Pen button and pen message fixes. |
| 2g | `build_beta5_2g.sh` | AudioX retry loop off (sysconfig). |
| 2h | `build_beta5_2h.sh` | Null guards in the OPPO gpuservice extension (needed with the own kernel). |
| 2i | `build_beta5_2i.sh` | SELinux labels and rules for the UI First kernel nodes. |
| 2j | `build_beta5_2j.sh` | Keyboard guard (idle drain), `loc_sys_service` off, Perfetto works (no vsock relay). |
| 2k | `build_beta5_2k.sh` | Charger shim reports the battery as genuine. |
| 2l | `build_beta5_2l.sh` | SurfaceFlinger off the little CPU cores, SurfaceFlinger timing in `product/etc/build.prop`. |
| 2m | `build_beta5_2m.sh` | SurfaceFlinger layer caching off (screen glitches). |
| 2n | `build_beta5_2n.sh` | system_server animation threads as UX, UI apps fully compiled. |
| 2o | `build_beta5_2o.sh` | All app-wide `refresh_rate_config` rules at 120 Hz in Auto and 120 Hz modes. Video players keep their lower rate. |
| 2p | `build_beta5_2p.sh` | Pen battery in the ColorOS live alert: OPPO IPeManager patched in place (`maintainer/ipe-fluid/patch_ipemanager.py`), `pipa_port` `PEN_FLUID`, helper without its own pill. |
| 2q | `build_beta5_2q.sh` | `pipa_port` loop with shell builtins (idle CPU 14.7 → 2.3 % of a core), smoothness defaults once per install (window blur off, material blur off, animation 0.8), package-cache reset per layer, OIFace cpusets, nandswap duplicate guard. |
| 2r | `build_beta5_2r.sh` | `pipa_port` `KSWAPD_NO_PRIME` (kswapd on CPUs 0-6), pen "connected" once at boot. |
| 2s | `build_beta5_2s.sh` | `pipa_port` `ANIM_TIER` (launcher animation tier, default 3) + helper Quick Settings tile "Animations", `sget` for settings reads, no animation 0.8 default. |
| 2t | `build_beta5_2t.sh` | `sget` reads settings with `settings get` into a file (cheap); a failed read keeps the animation tier. |
| 2u | `build_beta5_2u.sh` | SukiSU-Ultra manager 4.2.1-r1 as a removable preload (`my_stock/del-app/SukiSU`). Not released: KernelSU finds its manager only under `/data/app`. |
| 2v | `build_beta5_2v.sh` | 2t + first-boot defaults (animation blur off, on-screen keyboard on), face preview rotation from `cmd display get-displays`. Public beta5. |
| 2w | `build_beta5_2w.sh` | `oplus-services.jar` without the knuckle sensor (idle drain), SukiSU manager installed once on the first boot. |
| 2x | `build_beta5_2x.sh` | `surfaceflinger` does not wait for OPPO display HALs (Game Filter froze the screen). |
| 2z | `build_beta5_2z.sh` | Panel goes to 60 Hz when idle (`oplus_vrr_config.json`). |
| 3a | `build_beta5_3a.sh` | `CryptoEngShim`: privacy password and app lock work. |
| 3b | `build_beta5_3b.sh` | SystemUI keeps the idle 60 Hz after a screen-off (OTI pause with auto-resume). |
| 3c | `build_beta5_3c.sh` | Interconnect to the phone: SELinux rule, two virtual SIM slots. |
| 3d | `build_beta5_3d.sh` | AIDL virtual modem in `odm` (calls on the pad). |
| 3e | `build_beta5_3e.sh` | Echo reference in the non-voip mixer paths. |
| 3f | `build_beta5_3f.sh` | Game Filter and colour enhancement as a colour matrix, face eye guard, Eye Protect Bedtime patch, `pipa_port` enforcing. |
| 3g | `build_beta5_3g.sh` | `pipa_port` property-set and one-time-path rules. |
| 3h | `build_beta5_3h.sh` | `ro.surface_flinger.has_HDR_display=true` in `product/etc/build.prop` (HDR profiles and HDR output). |
| 3i | `build_beta5_3i.sh` | Wide colour. |
| 3j | `build_beta5_3j.sh` | Composer HAL skips `SET_LAYER_GENERIC_METADATA` (YouTube HDR plays). |
| 3k | step only (optional, `PORT_ODM_C06=1`) | The odm interconnect stack from C.06 instead of C.05. Not tested. |
| 3l | step only | `ro.mediaserver.64b.enable=true`: 64-bit mediaserver (video thumbnails work). |
| 3m | step only | `media.settings.xml` points to `media_profiles_kona.xml` (the first zygote64 no longer aborts at boot). |
| 3n | step only | The `pipa_port` loop sleeps 1 s with the screen off: the pen is ready about 1 s after screen-on. |
| 3o | step only | `framework.jar`: per-app device identity. Netflix sees a Pixel 6 (Widevine L1, HD), Google Photos sees a Pixel XL. Other apps see the real device. |
| 3p | step only | `product/etc/sysconfig/pipa-photos.xml`: the feature `com.google.android.apps.photos.NEXUS_PRELOAD`. Google Photos detects an original Pixel by this feature (free original-quality backup). |

NOTE: SurfaceFlinger properties must be in `product/etc/build.prop`. The pipa `vendor/build.prop` loads after
`system` and `system_ext` and sets other values.

## 3. The `pipa_port` service

The ROM includes the port runtime. No KernelSU module is necessary.

| Path in the ROM | Source in this repository |
|---|---|
| `/system_ext/pipa_port/` (`service.sh`, `early.sh`, `pen_keys.sh`, `config.prop`, face HAL, charger shim) | `port-rom/pipa_port/` |
| `/system_ext/etc/init/pipa_port.rc` | `port-rom/pipa_port.rc` |

The init file starts the services `pipa_port`, `pipa_subsys0` and `pipa_subsys1` in the SELinux domain
`pipa_port`. The domain is enforcing since step 3g.

- State: `/data/misc/pipa_port/`
- Log: `/data/local/tmp/pipa_port.log`
- User settings: `/data/misc/pipa_port/config.prop` (root). Reboot after a change.

### 3.1 Switches in `config.prop`

Each switch is 1 (on) or 0 (off).

| Switch | Default | Function |
|---|---|---|
| `FACE_HAL` | 1 | Start the face unlock HAL as root and start it again if it stops. |
| `CHARGER_SHIM` | 1 | Give ColorOS an OPPO charger HAL that reads the Qualcomm power supply nodes. |
| `PEN_WAKE` | 1 | Enable the pen in the touch driver after each screen-on. |
| `PEN_KEYS` | 1 | Map the pen buttons to actions (`keys.conf`). |
| `PEN_WATCH` | 1 | Tell ColorOS that a pen is connected. Lock 120 Hz while the pen is out of the dock. Publish the pen battery. |
| `COLOR_MODE_RESTORE` | 1 | Set the colour mode again after ColorOS resets it at boot. |
| `ADAPTIVE_RESTORE` | 1 | Set adaptive colour and Bedtime mode again after boot. |
| `BLUR_DEFAULT` | 1 | Set animation blur off if the user did not set it. |
| `STYLUS_BUTTONS_DEFAULT` | 1 | Merge the pen buttons into drawing apps if the user did not set it. |
| `HELPER_GRANTS` | 1 | Give the helper app its notification and overlay permissions. |
| `KB_EVENT_LINK` | 1 | Link `/dev/input/event12` to the keyboard case while it is attached. |
| `KEYBOARD_GUARD` | 1 | Run `xiaomi-keyboard` only while the keyboard case is connected. |
| `SF_BIG_CORES` | 1 | Set the UI First scene that keeps SurfaceFlinger and RenderEngine off the little cores. |
| `SYSTEM_UX` | 1 | Mark the system_server threads `android.anim`, `android.display` and `android.ui` as UX. |
| `SPEED_COMPILE` | 1 | Compile Settings, the Wi-Fi page and the launcher fully, one time for each ROM build. |
| `LID_SYNC` | 0 | Magnetic case sync. The helper app does this. |
| `KSWAPD_NO_PRIME` | 1 | Keep kswapd (memory reclaim) off the prime core. |
| `ANIM_TIER` | 1 | Set the launcher animation tier (`persist.sys.oplus.anim_level`) from global `pipa_anim_level`, else `ANIM_LEVEL` (3). A change restarts the launcher. |

## 4. The pipa helper app

`com.port.pipa.helper` is a persistent system app (`helper/`).

- It keeps Dolby on from boot.
- It shows the pen battery pill and a low-battery notification.
- It sets the "lock with cover" switch (`lid_behavior`).
- Quick Settings tile "Animations": writes global `pipa_anim_level` (3 → 2 → 1 → 4); `pipa_port` applies it.

## 5. SELinux

- The ROM is enforcing.
- `maintainer/uifirst-policy/sa_block.cil` labels the UI First kernel nodes and gives access to them. Step 2i adds
  it to `system_ext_sepolicy.cil`.
- The `pipa_port` domain is enforcing (steps 3f and 3g). Its rules are in `maintainer/sepolicy/pipa_port_rules.cil`.
- Before you build a policy change, compile it on the tablet with `/system/bin/secilc` and the eight policy
  inputs. A non-zero exit means an error.
- SELinux denials do not show in the logs. Use `maintainer/avc_trace.sh`.

## 6. Kernel parts that the ROM uses

| Kernel feature | Used by |
|---|---|
| OPPO UI First (`/proc/oplus_scheduler/sched_assist/`, `/proc/sys/kernel/sched_assist_scene`) | ColorOS, `pipa_port` (`SF_BIG_CORES`, `SYSTEM_UX`) |
| `kernel.ux_prefer_big`, `kernel.frame_rate` | Placement of UI threads |
| SukiSU-Ultra and susfs | Root, root hiding |
| nanosic keyboard driver (`/sys/devices/virtual/nanodev/nanodev0/`) | `KEYBOARD_GUARD` |

Refer to [KERNEL.md](KERNEL.md).
