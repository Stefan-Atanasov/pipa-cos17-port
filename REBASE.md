# Move the port to a new donor build

This document gives the procedure to build the port on a new OPPO Pad Mini (OPD2515) ColorOS build. The build tool is
`maintainer/port/port.sh`.

## 1. What changes

| Part | Contents | On a new donor |
|---|---|---|
| Firmware | Bootloader, modem, DSP, `vendor_boot`, `dtbo`, `vbmeta*` | Keep. |
| Device side | `vendor`, `odm` | Keep the pinned beta4 images. The steps edit them again on each build. |
| System side | `system` (with the donor `my_*` folders), `system_ext`, `product` | Use the new donor and the port edits. |
| Runtime | `pipa_port`, helper app (in the ROM) | Check. |

- The donor `my_*` partitions are folders at the root of `system`.
- `product` is the donor image with the step edits (`product/etc/build.prop`, `product/etc/sysconfig/pipa-photos.xml`).
- `vbmeta` has verification off. The images need no signature.
- `fstab.qcom` says `ext4` for the erofs partitions. Do not change it.

## 2. Procedure

1. Get the new full OTA (CN, with `payload.bin`).
2. Extract `payload.bin` from the OTA zip. Then extract the images. The output folder must exist:

```sh
D=$PIPA_ROOT/donor/OPD2515_<version>
mkdir -p $D/img
python3 -I maintainer/payload_extract.py payload.bin $D/img system system_ext product my_product my_manifest my_stock my_region my_heytap my_bigball my_carrier my_engineering
```

3. Compare the new donor with the old donor. Always give the output folder (the default is a path on the
   maintainer's PC). `--image-only` (before the paths) is a fast check without extraction:

```sh
sudo bash maintainer/donor_check.sh <old-donor-img-dir> <new-donor-img-dir> <out-dir>
```

   WARNING: A new `waitForService` import stops system_server at boot. The watchdog then restarts the tablet.

   Read `report.md` in the output folder. It lists:
   - the changed files that the steps touch,
   - the md5 gates that will stop a step,
   - new `waitForService` imports (a boot hang),
   - the SurfaceFlinger `waitForService` sites,
   - changes in sepolicy, VINTF, init files and `build.prop`.

   For a second scan of the `waitForService` imports in extracted trees (from `port.sh --keep-tree` or
   `fsck.erofs --extract`), use `sudo bash maintainer/wfs_scan.sh <old tree> <new tree>`.
4. Fix what the report lists. Make the patched files again from the new donor files with the tools in `module/tools/`.
   Change the md5 gates in the steps. Update the edit list `maintainer/c06-vs-beta4/PORT-EDITS.tsv` with
   `maintainer/port_diff.py`. If the helper app changed, build it: `sh helper/build.sh`.
   - `oplus-services.jar`: `module/tools/patch_framework.sh <new jar> module/framework/<md5>.jar` (your own copy: the
     patched jars are not in this repository, refer to [BLOBS.md](BLOBS.md))
   - Brightness table: `module/tools/gen_brightness_table.py`
5. Do the preflight check, then build with a new tag. The run stops at each step that finds an unknown file. Fix the
   step and start the run again from the beginning. There is no resume.

```sh
sh maintainer/port/port.sh --check <newtag> <new-donor-img-dir>
sudo sh maintainer/port/port.sh <newtag> <new-donor-img-dir>
```

   The default run applies all steps up to 3w. The optional steps 2u, 3k and 3x do nothing unless you set
   `PORT_WITH_2U=1`, `PORT_ODM_C06=1` or `PORT_NOENCRYPT=1`. Step 3k has md5 gates for the C.06 `odm` and `vendor`
   images: on a new donor it needs new values.

6. Compare the file manifests (`report/<partition>.tsv`) with the old build. Do not compare the image md5.
7. Compile the SELinux policy on the tablet with `/system/bin/secilc` and the eight policy inputs: the platform CIL,
   the mapping and compat CIL, the `system_ext` CIL and mapping, `product`, the vendor `plat_pub_versioned.cil` and
   `vendor_sepolicy.cil`, and `odm`. A non-zero exit means an error.
8. Flash `super` without a wipe: `sh maintainer/flash_super.sh -y <name>`. For an image that is not in the list, give
   the path and the md5. Keep the previous image for a rollback.
9. Do the regression check: `ADB="adb -s <serial>" sh maintainer/device_check.sh <tag>`. Do the checks that `port.sh`
   shows at the end.

NOTE: The older command `maintainer/build_port.sh` runs the old layer chain. Use it only to test.

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
- [ ] Feature files: WCG 2.0 off, HDR10 and HDR10+ off, `lcd_aod_mode` on (base step). Steps 3h and 3i then set
      `has_HDR_display` and `has_wide_color_display` in `product/etc/build.prop`.
- [ ] `system_ext_sepolicy.cil` and `system_ext_sepolicy_debug.cil`: the "pipa port" block. The rule
      `tee oppo_block_device` is necessary for boot.
- [ ] No `system/system/etc/init/zz_portdebug.rc`.
- [ ] `com.oplus.ota`, `com.oplus.sau` and `com.oplus.sauhelper` removed (`/system_ext/app/OTA`,
      `SystemAppUpdateService`, `SAUHelper`).

## 5. Image parameters

- erofs images: `mkfs.erofs -zlz4hc -C65536 -T0 <image> <tree>`.
- Extract trees as root with `fsck.erofs --extract=<dir> --xattrs --preserve <image>`. This keeps the SELinux
  labels.
- `super`: 9126805504 bytes, metadata 65536 bytes, 2 slots, `--virtual-ab`, groups `qti_dynamic_partitions_a` and
  `qti_dynamic_partitions_b`. `port.sh` runs `lpmake` with these values.

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
