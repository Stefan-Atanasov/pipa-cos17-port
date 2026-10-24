> **2026-10-23:** the current build chain is driven by `maintainer/build_port.sh` (see `MAINTAINER-STATUS.md`); the steps below describe the rebase it automates and the checks it cannot.

## Rebase recipe for a new donor build (short version)

1. Get the new OTA, extract its images (`maintainer/payload_extract.py`) into `~/Documents/pipa/donor/<build>/img/`.
2. Scan for HALs pipa lacks: `maintainer/wfs_scan.sh <old tree> <new tree>` (new `waitForService` imports hang system_server until the watchdog panics the device).
3. Diff the new donor against the old one and update the curated edit list: `maintainer/port_diff.py` → `maintainer/c06-vs-beta4/PORT-EDITS.tsv`.
4. `cd ~/Documents/pipa/COS17 && sh helper/build.sh` if the helper changed (needs JDK 21 + `~/Android/Sdk`).
5. `sudo sh maintainer/build_port.sh <newtag> <donor-img-dir>`. The first two steps stop at their stock-md5 checks (patched `oplus-services.jar`, brightness xml, odm script): regenerate those fixes from the new files (`module/tools/patch_framework.sh`, `gen_brightness_table.py`, ...), update the md5 in the step script, resume with `sudo sh maintainer/build_port.sh <newtag> <donor-img-dir> <step>`.
6. Test-compile the SELinux policy on the tablet (`/system/bin/secilc`, see `CLAUDE.md`), then dirty-flash with `maintainer/flash_super.sh -y <img> <md5>` and run `maintainer/device_check.sh <tag>` plus the checklist printed at the end of `build_port.sh`.

# Maintaining the COS17 port: rebase onto a new OPPO Pad Mini build

The original developer (梦归zzz) has stopped updating the port. This file is the procedure for
taking a new **OPPO Pad Mini (OPD2515)** ColorOS build and turning it into a new pipa build.
`PATCH-INVENTORY.md` lists what the port changed; this file covers what to do with that list.

Status of each step: **verified** means tested on this host against beta4. **Untested** means
written from the image evidence but not yet run end to end.

---

## 1. What a port build is made of

The port has four layers. Only one of them comes from the donor.

| Layer | Contents | Source | On a donor update |
|---|---|---|---|
| Firmware | `firmware/*.img`: Xiaomi pipa bootloader/modem/DSP, the port kernel (`boot`, `vendor_boot`, `dtbo`), `vbmeta*` | pipa + port kernel | **keep unchanged** |
| Device side | `vendor`, `odm` | Lineage-family pipa vendor + port edits (`PATCH-INVENTORY.md` §4.1–4.2) | **keep unchanged** |
| OS side | `system` (with donor `my_*` folded in), `system_ext`, `product` | **donor OPD2515** + port edits (§4.3) | **rebase** |
| Runtime | `pipa_core` (port author's KSU module), `pipa_cos17_power_tune` (ours) | modules | re-check, then reinstall |

So a donor update only replaces the OS side. Vendor, odm and firmware carry over byte for byte,
and so do all of the vendor/odm fixes.

Facts from the beta4 images (verified):

- **The donor base is** OPD2515 `17.0.0.102(CN01)`, OTA `OPD2515_11.C.05_1050_202609191848`, built
  2026-09-19 (`system/my_manifest/build.prop`).
- **`product` is the donor's own image, untouched.** Its erofs build time (2026-09-18 17:37:10 UTC)
  equals `ro.product.build.date`, and its UUID differs from the repacked images. Use the new donor
  `product.img` as-is.
- **The donor's `my_*` partitions** (`my_product`, `my_manifest`, `my_stock`, `my_region`,
  `my_heytap`, `my_bigball`, `my_carrier`, `my_engineering`, plus the empty `my_company`,
  `my_preload` and `my_reserve`) **are directories at the root of `system`**. `vendor/etc/fstab.qcom`
  mounts no `my_*` partitions. Labels come from `system_ext_file_contexts` (`/my_*` →
  `system_file`, `/my_*/overlay` → `vendor_overlay_file`).
- `vbmeta.img` flags = 3 (verity and verification disabled), so rebuilt images need no signing.
- `fstab.qcom` declares `system`, `system_ext` and `product` as `ext4` although they are erofs.
  It boots like this. Don't touch it.

## 2. What you need

1. **The baseline donor package: OPD2515 `11.C.05` / `17.0.0.102(CN01)`.** The C.05 package is only
   needed to settle the UNSURE rows of `maintainer/c06-vs-beta4/PORT-EDITS.tsv`; the working list
   already exists (`MAINTAINER-STATUS.md` roadmap row 3). With C.05, `port_diff.py changes` gives the
   **exact** list of everything the port author changed on the OS side. Without it, every rebase
   also carries all donor-version churn.
2. **The new donor package** you want to move to: a CN full OTA zip with `payload.bin`.
3. On the host: `erofs-utils` 1.9 (`fsck.erofs`, `mkfs.erofs`, `dump.erofs`),
   `lpmake`/`lpdump`/`lpunpack`, `diff3`, `getfattr`/`setfattr` and Python 3 are installed.
   For `payload.bin`, use `maintainer/payload_extract.py`: stdlib only, it reads straight from the
   OTA zip and checks every operation's SHA-256. It was verified on C.06.
4. Finding packages: OPPO's CN OTA server, queried with
   [OPlus-Tracker](https://github.com/Deuteriunt/OPlus-Tracker) `tomboy_pro.py OPD2515_11.C cn`. It
   returns the latest full OTA with a signed link valid for about 10 minutes; `curl -C -` resumes. **MIO-Kitchen is not needed**; its parameters are in §5 and §6.

## 3. Extracting a donor package

```sh
D=~/Documents/pipa/donor/OPD2515_<version>
python3 -I COS17/maintainer/payload_extract.py <ota>.zip -o $D/img -p system,system_ext,product,my_product,my_manifest,my_stock,my_region,my_heytap,my_bigball,my_carrier,my_engineering
# Extract as root with xattrs (SELinux labels, capabilities) and ownership; a rebuild needs them.
for p in system system_ext product my_product my_manifest my_stock my_region my_heytap my_bigball my_carrier my_engineering; do
  sudo fsck.erofs --extract=$D/$p --xattrs --preserve $D/img/$p.img
done
```

Some `my_*` images are empty or ext4 in some builds. Check each with `file` first. The diff
tool accepts `my_*` either next to `system/` (donor layout) or inside `system/` (port layout).

Extract the current port the same way for rebuilding (the read-only copy in
`../reference/cos17/` is fine for diffing only, since it has no xattrs):

```sh
P=~/Documents/pipa/port-work/beta4
for p in system system_ext; do sudo fsck.erofs --extract=$P/$p --xattrs --preserve COS17/work/parts/${p}_b.img; done
```

## 4. Rebase procedure

### 4.0 What we actually ran for beta5

For beta5 (C.06 base) the build path was `maintainer/build_beta5.sh` -> `maintainer/apply_port_edits.py`
with the curated list `maintainer/c06-vs-beta4/PORT-EDITS.tsv` (C.06 used as the donor, since C.05 was
not obtained), then `maintainer/build_beta5_baked.sh` (module file fixes baked in) and
`maintainer/build_beta5_1c.sh`. Decisions and checks: `MAINTAINER-STATUS.md` "beta5 build". The
sections below describe the general procedure.

### 4.1 Get the exact change list (once, needs the C.05 baseline)

```sh
python3 COS17/maintainer/port_diff.py changes $D_C05 ../reference/cos17 -o COS17/maintainer/beta4-changes
```

(`$D_C05` does not exist, C.05 was not obtained; in practice `$D_C06` was used with
`-o COS17/maintainer/c06-vs-beta4`, and the real output is `maintainer/c06-vs-beta4/port-changes.tsv`.)

The output, `beta4-changes/port-changes.tsv` (example output dir), lists every OS-side path the port added, modified or
removed. Expect three kinds of rows:

- **The patches in `PATCH-INVENTORY.md` §4.3 (S17–S25).** The table is the ground truth for those.
- **Removals.** This is the port's debloat list, which we have never seen directly.
- **Anything else**, which is new information. Add it to `PATCH-INVENTORY.md`.

### 4.2 Rebase onto the new donor

```sh
python3 COS17/maintainer/port_diff.py rebase $D_C05 ../reference/cos17 $D_NEW -o COS17/maintainer/rebase-<new>
```

`rebase.tsv` gives one action per changed path:

| Action | Meaning | What happens |
|---|---|---|
| `carry` | port changed it, donor didn't | `apply.sh` copies the port file |
| `remove` | port removed it (debloat) | `apply.sh` deletes it |
| `MERGED-text` | both changed, `diff3` merged cleanly | `apply.sh` copies the merge, but review it |
| `CONFLICT-text` | both changed the same lines | fix `conflicts/<file>.diff3` by hand, then copy |
| `CONFLICT` | both changed a binary (jar/apk/so) | redo the port's edit on the new file (§4.3) |

Then build the work tree and apply:

```sh
W=~/Documents/pipa/port-work/<new>
sudo cp -a --preserve=all $D_NEW/system $D_NEW/system_ext $W/   # product: reuse the donor image
for m in $D_NEW/my_*; do sudo cp -a --preserve=all $m $W/system/; done
less COS17/maintainer/rebase-<new>/apply.sh                    # review first
sudo sh COS17/maintainer/rebase-<new>/apply.sh $W
```

The tool is **verified** on synthetic trees (carry, remove, clean merge, text conflict, binary
conflict, folded `my_*`, paths with spaces), but it has not yet run on a real donor.

**Labels on carried files.** Files copied from the read-only `reference/cos17` tree have no
SELinux xattr. Either point `rebase` at the root-extracted port tree from §3 (preferred), or fix
the labels afterwards with `setfattr -n security.selinux -v u:object_r:system_file:s0 <file>`. Use
the label of the file it replaced; check it with `getfattr -d -m - <file>`.

### 4.3 Binary conflicts you will certainly get

- **`/system/framework/oplus-services.jar`.** The port repacked it (S17) but made no code edit that
  must be re-applied (`maintainer/jar-edits/REPORT.md`). Use the new donor jar as is, delete its
  `oat/arm64/oplus-services.*`, then generate the reroute jar with
  `module/tools/patch_framework.sh <new jar> module/framework/<md5>.jar` (pattern-based, no manual
  offsets).
- **Port apps** (`FaceUnlock`, `OppoCamera`, `MiSound`, the `com.port.pipa.overlay.*` RROs). They
  are port-only, so they show up as `carry`. They only conflict if the donor ships a file at the
  same path.
- **Re-signed donor overlays** (`*.display.product.25928*.apk`). Re-do the blanked `rc_*` corner
  drawables on the new apk and re-sign it.

### 4.4 OS-side checklist (from `PATCH-INVENTORY.md` §4.3)

Even with the tool, confirm each of these is present in the work tree:

- [ ] `system/build.prop`: heap lines; `system/system/build.prop`: board overrides (lines 315–340),
      `ro.hardware.telephony=qcom`. Set `persist.sys.facehal.verbose=false`.
- [ ] `system/build.prop`: keep the donor's `ro.secure=1`, `ro.adb.secure=1`, `ro.debuggable=0`,
      `ro.force.debuggable=0` (U17; beta4 deleted them).
- [ ] `my_product/build.prop`: `ro.build.tablet_type=pad` (R12).
- [ ] `my_product/build.prop` dated edits (game low-latency off, punch-hole props off, 144 Hz).
- [ ] `my_manifest/build.prop` identity block (device=pipa, display id). Bump your own version
      string here.
- [ ] Feature XMLs: WCG 2.0 off, HDR10/10+ off, `lcd_aod_mode` on.
- [ ] `system_ext_sepolicy.cil` **and** `system_ext_sepolicy_debug.cil` "pipa port" block (the
      `tee oppo_block_device` rule is required to boot).
- [ ] `system_ext/etc/display_brightness_config_default.xml`, or bake in the module's table (M7).
- [ ] **Do not carry** `system/system/etc/init/zz_portdebug.rc` (U1).
- [ ] Remove `com.oplus.ota`, `com.oplus.sau` and `com.oplus.sauhelper` (D9; rows in `PORT-EDITS.tsv`, tested safe 2026-10-22; keep RomUpdate), so nobody installs a
      donor SOTA bundle.

Vendor-side items to bake in at the same time, if you rebuild vendor/odm too (optional): the
module's qdcm, volume and audio-HAL files; the facehal rc `interface` line (U4); and the
`init.oplus.mm-sys.sh` 6 GB branch (U11).

## 5. Rebuilding the images

Parameters read from the beta4 images (`dump.erofs -s`): erofs, block 4096, **lz4** (not lz4hc),
features `sb_csum mtime xattr_filter` / `lz4_0padding compr_cfgs big_pcluster`. system has
build time 2026-10-07; system_ext/vendor/odm use `-T0` and a shared UUID
`4aa96973-51ff-4aec-29cd-baabf2fbe346`. Neither the UUID nor the timestamp matters for booting.

Use `-C65536`: beta4's largest physical cluster is 64 KiB, and it is what gives the original's
`compr_cfgs big_pcluster` features. `lz4hc` writes the same lz4 on-disk format the kernel already reads.

```sh
cd $W
sudo mkfs.erofs -zlz4hc -C65536 -T0 system.img     system
sudo mkfs.erofs -zlz4hc -C65536 -T0 system_ext.img system_ext
cp $D_NEW/img/product.img product.img
cp ~/Documents/pipa/COS17/work/parts/vendor_b.img vendor.img   # or your patched vendor
cp ~/Documents/pipa/COS17/work/parts/odm_b.img    odm.img
```

`mkfs.erofs` stores the xattrs already on the source files, so root extraction with `--xattrs`
(§3) is what keeps the SELinux labels. This host's erofs-utils has no `--file-contexts` or
`--fs-config-file`. Spot-check after building:
`sudo fsck.erofs --extract=/tmp/chk --xattrs --path=/system/bin/app_process64 system.img` and
`getfattr -d -m - /tmp/chk`. Expect `security.selinux` and, on a few binaries,
`security.capability`.

**Verified offline (2026-10-22)** with `maintainer/roundtrip_test.sh` (run as root):
beta4 system and system_ext were extracted, rebuilt with the flags above, re-extracted and
compared with `maintainer/tree_manifest.py`. **Identical**: 11 335 / 4 078 entries; path, type,
mode, uid/gid, content and symlink targets all match, and every entry carries its
`security.selinux` label (beta4 has no file capabilities). The superblock features are the same
as the original. The images come out smaller: system 5.09 GB vs 5.65 GB, system_ext 1.01 GB vs
1.06 GB.
**Still open:** booting the rebuilt image. The round-trip super is
`~/Documents/pipa/port-work/roundtrip/img/super.img` (md5 `090e5a32…`).

## 6. Repacking super

Layout read from beta4 (`lpdump`): super 9 126 805 504 bytes, metadata 65536 bytes with 2 slots,
the `virtual_ab_device` flag, and groups `qti_dynamic_partitions_a`/`_b` of 9 126 805 504 bytes
each. All content is in slot **b**; the `_a` partitions are empty. beta4 uses 7.49 GB, leaving
about **1.6 GB** of headroom.

```sh
bash -c '
args=()
for p in system system_ext product vendor odm; do args+=(--partition ${p}_a:readonly:0:qti_dynamic_partitions_a); done
for p in system system_ext product vendor odm; do args+=(--partition ${p}_b:readonly:$(stat -c %s $p.img):qti_dynamic_partitions_b --image ${p}_b=$p.img); done
lpmake --metadata-size 65536 --super-name super --metadata-slots 2 --virtual-ab \
  --device super:9126805504 \
  --group qti_dynamic_partitions_a:9126805504 --group qti_dynamic_partitions_b:9126805504 \
  "${args[@]}" --sparse --output super.img'
lpdump super.img     # compare with: lpdump COS17/work/super_raw.img
```

**Verified:** with the beta4 part sizes this reproduces the beta4 partition table. The only
difference is that odm starts 9 MiB earlier, because beta4 left a gap (both are 1 MiB-aligned).
With the round-trip images it builds a 6.83 GB sparse super. `simg2img` + `lpunpack` give back
partitions byte-identical to their inputs, and every `_a` partition is empty.
`lpmake` prints `Invalid sparse file format at header magic` once per raw input image. That is
expected. `lpdump` needs the unsparsed image (`simg2img super.img raw.img`).

## 7. Packaging and flashing

Copy the release folder and replace only `super/super.img`. Keep `firmware/` from beta4. The user
runs `FlashLinux.sh`, which flashes slot B. Without a data wipe, a ColorOS version jump may boot-loop
or break apps. Take a full backup first; if it fails, the fallback is to wipe, or to reflash beta4.

**Rollback** is always available: the beta4 `.7z` is the source of truth, and its `firmware/` plus
`super.img` restore the current state.

## 8. Regression checklist after a rebase

From the audit (README / module README):

| Check | Command / expectation |
|---|---|
| boots enforcing after boot | `getenforce` → Enforcing (`portenforce.rc`) |
| subsys HALs (needs `pipa_core`) | `service list \| grep -i subsys` shows `ISubsys/default` and `ISubsysRadio/slot1` |
| face HAL | `service list \| grep IFace`; no 1 Hz `ctl.interface_start` spam (R2) |
| keyboard daemon gated | `pgrep xiaomi-keyboard` is empty without the case (R1, M1) |
| colours / brightness | Natural ≠ Vivid; minimum ≈ 1 nit; auto-brightness moves (M6, M7) |
| adaptive colour | `OplusColorAmbientAdapter` registers 33171088 (M12; the module binds `framework/<md5>.jar` only when the ROM jar md5 matches) |
| audio | rotation 270 L/R correct (M14); USB DAC volume steps (M13) |
| zram / nandswap | `cat /proc/swaps`: zram0 8 G + `/data/nandswap/swapfile` |
| OTA | `/data/ota_package/OTA` exists or `com.oplus.ota` disabled (R11) |
| module binds | md5 of every file the module bind-mounts matches the module copy |

Then do a 30-minute screen-off drain check against the 42 mAh/h baseline (README Open item 1).
