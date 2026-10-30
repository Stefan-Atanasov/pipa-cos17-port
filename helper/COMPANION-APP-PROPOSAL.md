# Companion app: research and proposal (2026-10-23, read-only research; nothing built yet)

> **Status 2026-10-30:** not built. Since this proposal, the helper (v0.6) has the Quick Settings tile
> "Animations" (global `pipa_anim_level`), the pen battery is in the ColorOS live alert (`PEN_FLUID`, step 2p), and
> `sget` (a `settings get` into a file) answers the question about `settings get` in the enforcing domain.

## What exists
- `~/Documents/pipa/pipa_pen_fix_v1.3.zip`: KSU module for iqraOS (HyperOS), no UI; MIUI pen sysfs/refresh loops. Not useful here.
- **PipaControls** (nullpointer1101/android_device_xiaomi_pipa, branch `16.derp`, `pipacontrols/`, Apache-2.0): the
  closest model. Pages: stylus mode/refresh/QS tile, keyboard, lid, per-app refresh cap, saturation, CPU/GPU caps,
  touch boost, bypass charging. System-uid app (writes sysfs directly; root actions via `persist.vendor.parts.*` +
  init `on property:`). Mine it for sysfs paths and the performance pages.
- Hagb/xiaomi-stylus-buttons (keylayout swap): we already get the effect with `stylus_buttons_enabled` (B12).
- PadStudio (HyperOS, Key Mapper profiles, pen test canvas): UX ideas only.
- Adaptive-Hz (MIT): AccessibilityService idle detection + WRITE_SECURE_SETTINGS; no ColorOS strategy (we would write
  `oplus_customize_screen_refresh_rate`). Reuse the engine design for B11 option B.
- No public companion app for ColorOS/OPLUS pipa ports found.

## Toggles and where they live
| Toggle | Today | UI |
|---|---|---|
| Pen button actions | `pipa_port/keys.conf` (read-only ROM, sourced once; no user override yet) | v0.5 |
| Pen buttons in drawing apps | `secure stylus_buttons_enabled` | v0.5 |
| Pen 120 Hz lock | `PEN_WATCH` (shared with the pen-present intent) → split into a new `PEN_LOCK` | v0.5 |
| Pen pill / low-battery threshold | helper constants (`PenKeeper.LOW_SOC=15`, `PenPill.SHOW_MS`) | v0.5 |
| Lock with cover | ColorOS `device_case_enabled` (LidKeeper mirrors it) | link only |
| Colour/adaptive/bedtime restore | `COLOR_MODE_RESTORE`/`ADAPTIVE_RESTORE` | v0.5 (could move into the helper as an observer) |
| Refresh modes / idle drop | `oplus_customize_screen_refresh_rate` (8=144, 3=120), `peak_refresh_rate` | v0.6 |
| Performance profiles | perf-test-module props (reboot) | later, with measured numbers |
| Face HAL, charger shim, keyboard link | `config.prop` flags | status only |

## Architecture
- App writes Settings.Global `pipa_*` keys (WRITE_SECURE_SETTINGS, as LidKeeper does). Missing key = ROM default.
  Precedence: `/data/misc/pipa_port/config.prop` > Settings key > ROM `config.prop`.
- Helper-only settings: ContentObserver in the helper. Root-only actions (sysfs, ioctl, getevent, face HAL): `service.sh`
  reuses the `settings_global.xml` mtime gate, then one `settings list global | grep ^pipa_`, renders `$STATE/runtime.conf`;
  `pen_keys.sh` re-reads it per key press (no binder call in the getevent pipeline).
- **Check first:** `$(settings get …)` hands a `pipa_port`-labelled pipe to system_server (same class of problem as the
  `input` FAILED_TRANSACTION). Verify in the domain; possible rule `(allow system_server pipa_port (fifo_file (read write getattr append)))`.
- **Security:** other apps with WRITE_SECURE_SETTINGS (Tasker, Shizuku users) can write these keys. Never eval/source
  setting values; whitelist with `case` (numeric keycode, `none`, `app:pkg/cls` matching `^[A-Za-z0-9_.]+/[A-Za-z0-9_.$]+$`);
  `cmd:` actions only from the root-only file. Never publish root/KSU/susfs state in a readable key.
- Feedback: `pipa_cfg_rev` (UI→root), `pipa_ack` (root→UI), `pipa_status` (face/keys/charger/service alive).

## Minimal v0.5
- Separate, **non-persistent** priv-app (e.g. `com.port.pipa.settings`), so it can be updated with `adb install -r`
  and a UI crash cannot take down the Dolby/pen keepers. Same build (`helper/build.sh`), same key, one more privapp xml.
- Plain Views, `Theme.DeviceDefault.DayNight`, insets listener (edge-to-edge at target 37). No AndroidX.
- Screens: Pen (2 button actions, drawing-apps switch, 120 Hz lock, pill, low-battery %), Display (restore switch,
  current refresh mode), Status (pen %, ROM, kernel, service ack, face HAL, links to ColorOS settings). EN + zh-CN.
- Root side: settings-sync step + `PEN_LOCK` + ack/status in `service.sh`; `pen_keys.sh` reads `runtime.conf`.

## Open questions
`settings get` in the enforcing domain; other refresh key values; AccessibilityService cost for option B; keyboard-case
behaviours; per-package Settings write quotas (privileged apps probably exempt).
