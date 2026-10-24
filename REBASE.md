# Move the port to a new donor build

This document gives the procedure to build the port on a new OPPO Pad Mini (OPD2515) ColorOS build.

## 1. What changes

| Part | Contents | On a new donor |
|---|---|---|
| Firmware | Bootloader, modem, DSP, `vendor_boot`, `dtbo`, `vbmeta*` | Keep. |
| Device side | `vendor`, `odm` | Keep. |
| System side | `system` (with the donor `my_*` folders), `system_ext`, `product` | Use the new donor and the port edits. |
| Runtime | `pipa_port`, helper app (in the ROM) | Check. |

- The donor `my_*` partitions are folders at the root of `system`.
- `product` is the donor image without changes.
- `vbmeta` has verification off. The images need no signature.
- `fstab.qcom` says `ext4` for the erofs partitions. Do not change it.

## 2. Procedure

1. Get the new full OTA (CN, with `payload.bin`).
2. Extract the images:

```sh
D=$PIPA_ROOT/donor/OPD2515_<version>
python3 -I COS17/maintainer/payload_extract.py <ota>.zip -o $D/img -p system,system_ext,product,my_product,my_manifest,my_stock,my_region,my_heytap,my_bigball,my_carrier,my_engineering
```

3. Find new waits for services that pipa does not have:

```sh
sh maintainer/wfs_scan.sh <old tree> <new tree>
```

   WARNING: A new `waitForService` import stops system_server at boot. The watchdog then restarts the tablet.

4. Compare the new donor with the old donor. Update the edit list `maintainer/c06-vs-beta4/PORT-EDITS.tsv` with
   `maintainer/port_diff.py`.
5. If the helper app changed, build it: `sh helper/build.sh`.
6. Build all steps with a new tag:

```sh
sudo sh maintainer/build_port.sh <newtag> <donor-img-dir>
```

7. If the first two steps stop at an md5 check, make the fix again from the new donor file:
   - `oplus-services.jar`: `module/tools/patch_framework.sh <new jar> module/framework/<md5>.jar`
   - Brightness table: `module/tools/gen_brightness_table.py`
8. Write the new md5 into the step script.
9. Continue the build from that step:

```sh
sudo sh maintainer/build_port.sh <newtag> <donor-img-dir> <step>
```

10. Compile the SELinux policy on the tablet with `/system/bin/secilc` and the eight policy inputs.
11. Flash `super` without a wipe: `sh maintainer/flash_super.sh -y <path-to-super.img> <md5>`.
12. Do the regression check: `sh maintainer/device_check.sh <tag>`. Do the checks that `build_port.sh` shows at
    the end.

## 3. Binary conflicts

| File | Action |
|---|---|
| `/system/framework/oplus-services.jar` | Use the new donor jar. Delete its `oat/arm64/oplus-services.*`. Make the patched jar with `module/tools/patch_framework.sh`. |
| Port apps (`FaceUnlock`, `OppoCamera`, `MiSound`, `com.port.pipa.overlay.*`) | Keep. They conflict only if the donor has a file at the same path. |
| Re-signed donor overlays (`*.display.product.25928*.apk`) | Blank the `rc_*` corner drawables again and sign the apk again. |

## 4. System side checklist

Make sure that the new tree has:

- [ ] `system/build.prop`: heap lines.
- [ ] `system/system/build.prop`: board overrides and `ro.hardware.telephony=qcom`.
- [ ] `system/build.prop`: the donor values `ro.secure=1`, `ro.adb.secure=1`, `ro.debuggable=0`, `ro.force.debuggable=0`.
- [ ] `my_product/build.prop`: `ro.build.tablet_type=pad`.
- [ ] `my_manifest/build.prop`: the identity block (device `pipa`, display id) and your version text.
- [ ] Feature files: WCG 2.0 off, HDR10 and HDR10+ off, `lcd_aod_mode` on.
- [ ] `system_ext_sepolicy.cil` and `system_ext_sepolicy_debug.cil`: the "pipa port" block. The rule
      `tee oppo_block_device` is necessary for boot.
- [ ] No `system/system/etc/init/zz_portdebug.rc`.
- [ ] `com.oplus.ota`, `com.oplus.sau` and `com.oplus.sauhelper` removed.

## 5. Image parameters

- erofs images: `mkfs.erofs -zlz4hc -C65536 -T0 <image> <tree>`.
- Extract trees as root with `fsck.erofs --extract=<dir> --xattrs --preserve <image>`. This keeps the SELinux
  labels.
- `super`: 9126805504 bytes, metadata 65536 bytes, 2 slots, `--virtual-ab`, groups `qti_dynamic_partitions_a` and
  `qti_dynamic_partitions_b`. The build steps run `lpmake` with these values.

NOTE: `lpmake` shows `Invalid sparse file format at header magic` one time for each raw input image. This is
correct.

## 6. Regression checklist

| Check | Expected result |
|---|---|
| SELinux | `getenforce` shows `Enforcing`. |
| Subsystem HALs | `service list | grep -i subsys` shows `ISubsys/default` and `ISubsysRadio/slot1`. |
| Face HAL | `service list | grep IFace` shows the HAL. |
| Keyboard daemon | `pgrep xiaomi-keyboard` is empty without the keyboard case. |
| Colours and brightness | Natural and Vivid are different. Minimum brightness is about 1 nit. Auto-brightness changes. |
| Audio | Left and right are correct in rotation 270. USB DAC volume has steps. |
| Swap | `cat /proc/swaps` shows zram0. |

Then do a screen-off battery check. Refer to [TESTING.md](TESTING.md), section 6.
