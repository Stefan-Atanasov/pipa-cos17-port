# ColorOS 17 for pipa — beta5 (maintainer build)

**STATUS: not yet released — tested on one device (the maintainer's, 2026-10-22).** beta5 and
beta5-baked boot and pass the regression check (24/24) on a dirty flash over beta4. More testers
wanted before the public release.

beta5 is the first build by the new maintainer (stefan). The original developer 梦归zzz has stopped
working on the port.

Variants: `beta5` (this), `beta5-baked` (module file fixes baked in; recommended), `beta5-1c`
(+ GNSS, pen perms; not yet tested on a device).

## Base

- OPPO Pad Mini **OPD2515 17.0.0.103(CN01) / C.06** (beta4 was C.05 / 17.0.0.102)
- Firmware, kernel, vendor and odm are **unchanged from beta4**
- Flash target: slot B, as before

## Changes vs beta4

- OS side (system, system_ext, product) rebased onto the C.06 donor build
- Port additions and debloat applied as in beta4 (same app removals, same added files)
- **SELinux:** stock C.06 policy plus only the pipa port allow rules. beta4 had deleted all
  `dontaudit` rules (a debugging leftover); that is not carried, so less log noise
- **ADB security restored:** `ro.secure`, `ro.adb.secure`, `ro.debuggable` are set again (beta4 had
  them deleted). Your PC will ask for ADB authorisation once after flashing
- `system/build.prop` file mode is now 644 (was 600)
- The prebuilt `oplus-services` odex files that C.06 ships are removed, same as beta4 (needed for
  the module's patched framework jar)
- **OPPO's updater is removed** (`com.oplus.ota`, `com.oplus.sau`, `com.oplus.sauhelper`). The "Software
  update" entry disappears. It only ever offered OPPO Pad Mini app bundles, never a real system update,
  and installing them could override port apps. Port updates come as new builds like this one
- **Fixed three C.06 boot hangs** that made the plain C.06 rebase bootloop on pipa: C.06 waits
  forever for hardware services pipa doesn't have (OPPO's engineering HAL, and Qualcomm's QSPM
  performance HAL in `libupdateprof.qti.so` / `libtrigger-handler.so`). The two libraries are
  carried from beta4 (C.05), and a 2-byte fix in `oplus-services.jar` restores beta4's
  non-blocking path for the engineering HAL
- `oplus-services.jar` is otherwise C.06 stock. A diff against beta4 found no port-author edit that
  needed re-applying
- Build fingerprints/dates in `my_manifest` stay as in beta4 so they keep matching the unchanged vendor

## Required modules

1. **pipa_core v1.10** (by 梦归zzz) — still required: face unlock, stylus, AOD, subsys HALs.
   It lives outside the ROM image; reinstall it after any data wipe.
2. **Pipa COS17 Power & Polish Tune** — optional, but if you use it you need **v0.10**.
   - **v0.7 or older must NOT be used with beta5**: it binds the beta4 framework jar over the C.06
     framework, which likely bootloops.
   - v0.8 is safe on beta5 (md5 guard) but skips the reroute, so adaptive colour stays off.
   - v0.9 works on these images but lacks the C.06 boot fixes; use v0.10.
   - v0.10 carries one patched jar per base (beta4 and C.06) and binds only the matching one; on an
     unknown build it skips the bind. It also skips it if a prebuilt `oplus-services.odex` is present.
   - v0.10 re-enables adaptive colour / bedtime colour on plain beta5 (beta5-baked has it built in).

## Install

1. Back up `/data` first. C.05 → C.06 is a minor ColorOS update, so a dirty flash from beta4 is
   expected to work, but it is untested.
2. **Install/upgrade the module to v0.10 before flashing** and reboot once on beta4 (check the module
   log for `bind /system/framework/oplus-services.jar <- module`).
3. Flash with `FlashLinux.sh` / `FlashWindows.bat` as usual (slot B). Firmware is untouched.
4. **If it bootloops:** reflash the beta4 `super.img` (boot to fastboot, flash, no wipe needed).
5. After boot, accept the one-time ADB authorisation prompt on the tablet.

## Known issues / limitations

- Tested on one device only so far (8 GB, dirty flash over beta4 with pipa_core v1.10).
- First boot after flashing shows "Optimizing apps" and is laggy for a few minutes while apps
  are recompiled; this settles by itself.
- Possible difference: the default slow brightness ramp rate in the C.06 framework differs from
  beta4 (40 vs 320; probably overridden at runtime). Tell us if brightness ramping feels different
- Adaptive colour (module) uses a fixed 100 lx in place of the missing lux value, so it follows the
  colour-temperature sensor only; brightness-based ambient adaptation is not bridged
- ColorOS sound effects (Audiox) cannot work on this hardware (carried over from beta4)
- Face unlock depends on the pipa_core HAL start (carried over from beta4): if the HAL crashes,
  face unlock stays dead until reboot
- Two display overlays are carried over from beta4 unchanged
- Some UNSURE removals (boot-monitor/phoenix services) were applied for parity with beta4; the
  donor C.05 build would be needed to confirm they were port edits

## Please report

After flashing, tell us: boots or bootloops, face unlock, stylus, AOD, audio (incl. rotation),
adaptive colour, brightness ramp, battery idle drain. Include the module version.

## Download

- super.img: <download link>
- md5: <md5>
- Module v0.10: <download link> (md5 `ec6e3425…`)
- pipa_core v1.10: <download link>

## Credits

- **梦归zzz** — original ColorOS 17 port for pipa and the pipa_core module
- stefan — maintainer, beta5 rebase and Power & Polish Tune module

## Known limitations (to include in the final notes)

- Play Integrity: only `MEETS_BASIC_INTEGRITY` (unlocked bootloader). Apps that require DEVICE integrity (some banking/payment apps, some games) will not work.
- Network sharing (interconnect) and the privacy password / app lock do not work yet.
