# Moving runtime fixes from modules into the ROM (phase 2/3 design)

Goal: a pipa build that works without KernelSU modules. Every fix lives in the ROM, so it survives a
data wipe and doesn't depend on root. Modules keep only experiments and opt-in tweaks.

**Status 2026-10-23: phases 1c to 2e are done** (pipa_port, face HAL, charger shim, subsys daemons, pen, helper app are ROM services/apps since beta5-2e; the `pipa_port` domain is still permissive). Open: SELinux rules for that domain, colour/adaptive restore (B5/B6), AudioX disable. See `MAINTAINER-STATUS.md`. The text below is the original design and the 2026-10-22 progress notes.

Status 2026-10-22 19:20: **A2 now really in the ROM since beta5-2b** (vendor `pipa_port_pen.rc` + one vendor_init rule), **B1 drain fixed in the ROM since beta5-2b** (xiaomi-keyboard branch patch; module keyboard gate now optional). A1 in the ROM since beta5-1c. **A2 does not work via `ueventd.rc`**: the `fuda` power_supply fails its coldboot synthetic uevent (`driver failed to report pin_enabled`, `failed to send synthetic uevent`), so ueventd never applies the lines; the nodes were only right because pipa_core chowns them (1.11 logs `pen sysfs perms fixed` on 2a). Redo A2 as an init `on boot` chown/chmod in the next build; **A4, A9 in the ROM since beta5-2a** (verified on the tablet), `pipa_core` v1.11 skips them when the ROM has them. AVC denials: `maintainer/avc_trace.sh` (the kernel has no audit core, so the `logcat | grep avc` steps below need it). Earlier: design; phase 1 (`maintainer/build_beta5_baked.sh`, `MAINTAINER-STATUS.md` row 6)
and phase 1c A1/A2 (`maintainer/build_beta5_1c.sh`, row 13) are built offline, nothing is booted.
A9 has `maintainer/aod_overlay_test.sh`. Stability and performance
work is tracked in `STABILITY-PERF.md`.

## Why this is harder than phase 1

A module's `service.sh` runs as **root in KernelSU's su domain**. That domain is effectively
unconfined, which is why `pipa_core` can start the face HAL, `subsys_daemon` and `app_process`
daemons that the ROM's own init services cannot. In the ROM, every daemon runs in an SELinux domain
that needs explicit rules. The port boots permissive and `portenforce.rc` switches to enforcing at
`sys.boot_completed` (U3), so a missing rule shows up only **after** boot, as a silent feature
failure. Each item below must therefore be tested on an enforcing system and checked with
`logcat -b all | grep avc` (note: `pipa_core` enables susfs `avc-log-spoofing`, which hides AVCs.
Disable that line, or use a build without `pipa_core`, while testing).

Policy mechanics on this port: `odm/etc/selinux/precompiled_sepolicy` does not match its hashes
(U6), so init compiles the policy from the `.cil` files on every boot. New types and rules can
therefore go straight into `system_ext/etc/selinux/system_ext_sepolicy.cil` (plus `_debug.cil`),
under the existing `pipa port` block, with file labels in `system_ext_file_contexts`. Keep every
rule in one marked block so the next rebase can carry it with `append_from_marker`.

## Inventory: what runs at runtime today

| # | Piece | Module | What it does | ROM-native target | Needs | Risk | Phase |
|---|---|---|---|---|---|---|---|
| A1 | GNSS retry kill | pipa_core | `ctl.stop` + kill `loc_sys_service` (no GNSS hw; ~2.4 log lines/s) | comment the `start loc_sys_service` line in `on early-boot` (`disabled` alone does not stop an explicit start) | rc edit only | low | 1c |
| A2 | Pen sysfs perms | pipa_core | chown/chmod 4 nodes under `/sys/class/power_supply/{fuda,wireless}` so system_server can drive the pen charger | `ueventd.rc` sysfs lines (`/sys/class/power_supply/fuda reverse_chg_mode 0664 system system`, …) | vendor `ueventd.rc` append | low | 1c |
| A3 | `tablet_type` resetprop | pipa_core | boot animation orientation | **already in beta5** (`my_product/build.prop ro.build.tablet_type=pad`) | nothing; the module line becomes a no-op | none | done |
| A4 | Legacy face client | power-tune | disables `com.pipa.faceunlock` while `/data/system/facehal_socket` is absent | drop `system/app/FaceUnlock` from the ROM (R4) | confirm on device that the socket never exists with facehal-rs | low | 1c |
| A5 | `/metadata` cleanup | pipa_core | `rm -rf /metadata/bootcap /metadata/portdiag` (58 MB /metadata fills, aconfig StorageFull) | find and stop the bootcap writer, or an init `exec` cleanup | identify writer first (`ls -la /metadata/bootcap` on device) | low-med | 2 |
| A6 | Blur default off | pipa_core | `settings put system animationBlurrySwitch 0` if unset (drops frames on SD870) | framework default: overlay or `SettingsProvider` default | find where ColorOS reads the default | low | 2 |
| A7 | Subsys HALs | pipa_core | runs `/odm/bin/hw/subsys_daemon` slot 0/1 as root, because `hal_radio_default` is denied `/dev/diag` (`vendor_diag_device`) | re-enable the odm `subsys_daemon` service + `(allow hal_radio_default vendor_diag_device (chr_file (open read write ioctl)))` | policy + device test (sharing/tethering, `service list`) | med | 2 |
| A8 | Face HAL | pipa_core + power-tune watchdog | starts facehal-rs from `/data/adb/modules/pipa_core/facehal` as root with `LD_LIBRARY_PATH`; the watchdog restarts it after crashes | init service with `interface aidl …IFace/default`, own domain with camera + GPU (KGSL, OpenCL) access, libs on `/system_ext` so the system namespace resolves `libcamera2ndk_vendor.so` deps (U4) | new domain, file labels, VINTF entry, linker config; biggest item | high | 3 |
| A9 | AOD backlight (**decision 2026-10-22: AOD stays off, LCD; drop the daemon, see Proposed order**) | pipa_core (+ power-tune freeze) | `AodBacklightDaemon` (`app_process`) lifts the backlight while dozing, because ColorOS classic AOD sets no doze brightness (NaN → 1/4095 → black) | **first try a framework overlay**: `config_screenBrightnessDoze` (and doze brightness array) in a pipa RRO. If AOD then shows, the daemon and the freeze guard both go away | RRO only; test first with `maintainer/aod_overlay_test.sh` (fabricated overlay, no APK). ColorOS's `DozeBrightnessStrategyExtImpl.updateBrightness(f)` is just `f * maxBrightness`, so the AOSP doze config is what reaches the panel | low-med | 2 |
| A10 | Charger shim | pipa_core | `app_process` registers a fake `vendor.oplus.hardware.charger.ICharger` fed from qcom `power_supply` (otherwise "abnormal charger" warnings) | init service running `app_process` with the jar in `system_ext/framework`, own domain allowed to add that service | domain + `service_contexts` + VINTF; med-high | med-high | 3 |
| A11 | Pen enable on wake | pipa_core | loop: after each screen-on, `xiaomi_touch_ioctl pen on` (novatek needs `Touch_Pen_ENABLE` re-armed) + `pen_keys.sh` (getevent → key mapping) | small native daemon (or the existing `xiaomi-pen` vendor service, `persist.vendor.parts.pen`) triggered by display state; check first whether `xiaomi-pen` already does this on HyperOS | investigation | med | 3 |
| A12 | susfs hiding | pipa_core | hides `/data/adb`, mounts, AVC logs (root hiding) | **not a ROM feature.** Stays with whoever uses root | n/a | n/a | stays module |
| B1 | Keyboard gating | power-tune | starts `xiaomi-keyboard` only while a Xiaomi keyboard input device exists; the daemon otherwise polls the accelerometer ~6.7×/s (R1) | **source fix:** restore HyperOS's event-driven `vendor.xiaomi.hardware.keyboardnanoapp@1.0-service` (D5) and drop `xiaomi-keyboard`. Fallback: an init service gated by a property that a tiny input watcher sets | blobs + rc + policy from HyperOS stock vendor | med | 2 |
| B2 | `event12` link | power-tune | symlinks `/dev/input/event12` to the keyboard node (fold detection) | goes away with B1's source fix | — | — | 2 |
| B3 | AOD freeze | power-tune | SIGSTOP/SIGCONT `AodBacklightDaemon` while AOD is off | goes away with A9 | — | — | 2 |
| B4 | Face watchdog | power-tune | restarts the face HAL after a crash | goes away with A8 (init restarts services) | — | — | 3 |
| B5 | Colour mode restore | power-tune | rewrites `display_color_mode` after ColorOS resets it at boot | find the resetter (likely the display settings app on first boot); overlay default `display_color_mode` | investigation | low | 2 |
| B6 | Adaptive/Bedtime restore | power-tune | rewrites the two settings that the eyeprotect app resets every boot (it checks OPPO's CCT sensor type directly) | patch the eyeprotect app's sensor check, or keep in the module | apk patch + re-sign (needs Java/apksigner on host) | med | 3 / module |

## Proposed order

Maintainer decision 2026-10-22: the goal is a ROM that needs no fix module. Everything that can move into the ROM moves; the power-tune module keeps only experiments and opt-out tweaks. Later: user toggles for those (a Settings page or a small app writing `persist.` props that the ROM's init scripts read at boot). Prerequisite for phase 2/3 policy work: visible kernel AVC denials (`MAINTAINER-STATUS.md` row 12; they currently reach no log).

**Phase 1c** (quick ROM fixes, low risk; `maintainer/build_beta5_1c.sh`, built on the phase 1 image, flash after it boots):
A1, A2; A4 only with `DROP_FACEUNLOCK=1` after confirming the socket never exists (not in the built 1c image). Each removes a `pipa_core` task. The module still runs, and its now-redundant action
is harmless: stopping a disabled service, or a chown that is already right.

**Phase 2** (one item per test build, each verified enforcing with an AVC check):
1. **A9 AOD: drop it.** Maintainer decision 2026-10-22: AOD stays off for good (the panel is LCD, so AOD only lights the whole backlight). Remove `AodBacklightDaemon` from `pipa_core`'s `run_aod` and hide or disable the AOD setting instead of building the doze-brightness overlay; the module's AOD freeze guard (B3) then goes away too. The overlay experiment (`aod_overlay_test.sh`) is no longer needed.
2. **A7 subsys policy.** It removes the root-started daemons and the U5 dependency on `pipa_core`.
3. **B1 keyboard HAL from HyperOS.** This is the source fix for R1's drain.
4. A5, A6, B5 (investigations first).

**B1 finding (2026-10-22, offline + device):** the HyperOS `vendor.xiaomi.hardware.keyboardnanoapp@1.0-service` is a passive pipe (opens `/dev/nanodev0`, forwards reads to a registered `INanoappCallback`, writes what the client sends). All keyboard logic lives in HyperOS `system_ext/framework/miui-services.jar`, its only client, so dropping the HAL into ColorOS would do nothing. Keep `xiaomi-keyboard`. ROM-native drain fix candidate: patch `vendor/bin/xiaomi-keyboard` at vaddr `0x2504` (`tbnz w8,#0,0x24e0` → `b 0x24e0`, `0x17fffff7`) so a missing `/dev/input/event12` always means the 3 s sleep instead of the 150 ms accelerometer read. Untested question: does the keyboard still get enabled when attached without the module's event12 link (the daemon then never writes `32 ff 1`)? Needs the real keyboard. Kernel presence flag for later: `/sys/class/nanodev/nanodev0/_version176x` reads `Connected=[0] Power=[0]` (poll only, no uevent).

**Phase 3** (needs real policy work): A8 face HAL, A10 charger shim, A11 pen daemon. After phase 3,
`pipa_core` is no longer required. Until then, keep it installed.

## Domain template (draft, untested)

For an init service `pipa_foo` running `/system_ext/bin/pipa_foo`, in the `pipa port` block of
`system_ext_sepolicy.cil` (+ `_debug.cil`):

```lisp
;; pipa port: pipa_foo daemon
(type pipa_foo)
(roletype object_r pipa_foo)
(typeattributeset domain (pipa_foo))
(type pipa_foo_exec)
(roletype object_r pipa_foo_exec)
(typeattributeset exec_type (pipa_foo_exec))
(typeattributeset file_type (pipa_foo_exec))
(typeattributeset system_file_type (pipa_foo_exec))
(typetransition init pipa_foo_exec process pipa_foo)
(allow init pipa_foo_exec (file (read getattr map execute open)))
(allow init pipa_foo (process (transition)))
(allow pipa_foo pipa_foo_exec (file (read getattr map execute open entrypoint)))
;; + the specific rules the daemon needs, collected from AVCs on a test build
```

`system_ext_file_contexts`:

```
/system_ext/bin/pipa_foo    u:object_r:pipa_foo_exec:s0
```

and the rc service gets `seclabel u:r:pipa_foo:s0` if the transition is not picked up. Build the
rule list from real AVCs (`audit2allow`-style), never with broad `allow pipa_foo self:capability *`
or by putting the domain in `permissive`. A permissive domain would hide exactly the failures we
want to see.

## Test protocol per item

1. Build with only that item changed (one variable per flash).
2. `device_check.sh <item>`: the existing checks must not regress.
3. The item's own check (e.g. AOD visible at night, `service list | grep ISubsys`, keyboard attach
   and fold with `getprop init.svc.<kbd service>`).
4. `logcat -b all -d | grep 'avc: denied'` after boot_completed, with susfs AVC spoofing off.
5. 30 min screen-off drain against the 42 mAh/h baseline.
6. Record in `MAINTAINER-STATUS.md`, then remove the matching module/pipa_core action.
