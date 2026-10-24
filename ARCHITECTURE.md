# Architecture

This document tells how the port is put together.

## 1. Partitions

| Part | Contents | Source |
|---|---|---|
| Firmware | Bootloader, modem, DSP, `vendor_boot`, `dtbo`, `vbmeta*` | beta4 release, not changed |
| Kernel (`boot`) | Own kernel `walt-r5` | [KERNEL.md](KERNEL.md) |
| `vendor`, `odm` | pipa device side with port edits | beta4 release, not changed by a rebase |
| `system` (with the donor `my_*` folders), `system_ext`, `product` | ColorOS 17 | donor OPD2515 C.06 and the ROM layers below |

All content is in slot B. The `_a` partitions are empty. `vbmeta` has verification off, so the images need no
signature.

## 2. ROM layers

Each build step is a script in `maintainer/`. Each step reads the tree and the images of the previous step and
writes `port-work/<tag>-<step>/`. `maintainer/build_port.sh` runs all steps in sequence.

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
| 2u | `build_beta5_2u.sh` | SukiSU-Ultra manager 4.2.1-r1 as a removable preload (`my_stock/del-app/SukiSU`). |

NOTE: SurfaceFlinger properties must be in `product/etc/build.prop`. The pipa `vendor/build.prop` loads after
`system` and `system_ext` and sets other values.

## 3. The `pipa_port` service

The ROM includes the port runtime. No KernelSU module is necessary.

| Path in the ROM | Source in this repository |
|---|---|
| `/system_ext/pipa_port/` (`service.sh`, `early.sh`, `pen_keys.sh`, `config.prop`, face HAL, charger shim) | `port-rom/pipa_port/` |
| `/system_ext/etc/init/pipa_port.rc` | `port-rom/pipa_port.rc` |

The init file starts the services `pipa_port`, `pipa_subsys0` and `pipa_subsys1` in the SELinux domain
`pipa_port`. The domain is permissive.

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
