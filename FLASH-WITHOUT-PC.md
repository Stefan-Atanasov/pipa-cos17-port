# Flash without a PC (Bugjaeger on a second Android phone)

Status: **not tested by the maintainer** (2026-11-14). One tester flashed a beta (before v9) with Bugjaeger and it booted. Bugjaeger has a
fastboot shell for typed commands; its author says basic commands work but are not fully tested. Use the PC script
`FlashLinux.sh` if you can. Report your result in the tester group.

## What you need

- A second Android phone with the app **Bugjaeger** and a USB-C to USB-C OTG cable (or an OTG adapter).
- The release package, unpacked on the phone (folders `firmware/` and `super/`). About 8 GB free space.
- The tablet in fastboot mode: power off, then hold **Volume down + Power**.

## Important

- Do not reboot the tablet before the last step is done.
- `super.img` is a sparse image of about 7 GB. If Bugjaeger stops with a size or "sparse" error, stop and use a PC.
- The PC script writes `<name>_ab` (both slots). Bugjaeger sends commands to the bootloader, so this list writes
  slot `_a` and slot `_b` one after the other. Both are needed.
- Step 4 erases all your data (photos, apps, accounts). Do it when you come from another ROM, or when the release
  notes tell you to do a clean flash. Make a backup first.

## Steps (fastboot commands, in this order)

1. Set slot B active:
   `fastboot set_active b`
2. Flash the firmware (file = `firmware/<name>.img`), each partition on slot a and slot b:
   `fastboot flash abl_a firmware/abl.img`
   `fastboot flash abl_b firmware/abl.img`
   `fastboot flash aop_a firmware/aop.img`
   `fastboot flash aop_b firmware/aop.img`
   `fastboot flash bluetooth_a firmware/bluetooth.img`
   `fastboot flash bluetooth_b firmware/bluetooth.img`
   `fastboot flash boot_a firmware/boot.img`
   `fastboot flash boot_b firmware/boot.img`
   `fastboot flash cmnlib_a firmware/cmnlib.img`
   `fastboot flash cmnlib_b firmware/cmnlib.img`
   `fastboot flash cmnlib64_a firmware/cmnlib64.img`
   `fastboot flash cmnlib64_b firmware/cmnlib64.img`
   `fastboot flash devcfg_a firmware/devcfg.img`
   `fastboot flash devcfg_b firmware/devcfg.img`
   `fastboot flash dsp_a firmware/dsp.img`
   `fastboot flash dsp_b firmware/dsp.img`
   `fastboot flash dtbo_a firmware/dtbo.img`
   `fastboot flash dtbo_b firmware/dtbo.img`
   `fastboot flash featenabler_a firmware/featenabler.img`
   `fastboot flash featenabler_b firmware/featenabler.img`
   `fastboot flash hyp_a firmware/hyp.img`
   `fastboot flash hyp_b firmware/hyp.img`
   `fastboot flash imagefv_a firmware/imagefv.img`
   `fastboot flash imagefv_b firmware/imagefv.img`
   `fastboot flash keymaster_a firmware/keymaster.img`
   `fastboot flash keymaster_b firmware/keymaster.img`
   `fastboot flash modem_a firmware/modem.img`
   `fastboot flash modem_b firmware/modem.img`
   `fastboot flash qupfw_a firmware/qupfw.img`
   `fastboot flash qupfw_b firmware/qupfw.img`
   `fastboot flash tz_a firmware/tz.img`
   `fastboot flash tz_b firmware/tz.img`
   `fastboot flash uefisecapp_a firmware/uefisecapp.img`
   `fastboot flash uefisecapp_b firmware/uefisecapp.img`
   `fastboot flash vbmeta_a firmware/vbmeta.img`
   `fastboot flash vbmeta_b firmware/vbmeta.img`
   `fastboot flash vbmeta_system_a firmware/vbmeta_system.img`
   `fastboot flash vbmeta_system_b firmware/vbmeta_system.img`
   `fastboot flash vendor_boot_a firmware/vendor_boot.img`
   `fastboot flash vendor_boot_b firmware/vendor_boot.img`
   `fastboot flash xbl_a firmware/xbl.img`
   `fastboot flash xbl_b firmware/xbl.img`
   `fastboot flash xbl_config_a firmware/xbl_config.img`
   `fastboot flash xbl_config_b firmware/xbl_config.img`
3. Flash the system (one partition, no slot suffix; this takes several minutes):
   `fastboot flash super super/super.img`
   Then set slot B again and check it: `fastboot set_active b`, `fastboot getvar current-slot` (must say `b`).
4. Only for a clean flash (erases all data):
   `fastboot erase metadata`
   `fastboot erase userdata`
5. Set slot B a last time, then reboot:
   `fastboot set_active b`
   `fastboot reboot`

The first boot can take a few minutes. If the tablet does not boot, flash again from a PC with `FlashLinux.sh`.
