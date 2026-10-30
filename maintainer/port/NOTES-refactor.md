# NOTES-refactor: what is not 1:1

> **Historical record (2026-10-29).** Written before the first `port.sh` run. Since then `port.sh` built all test
> builds and beta6 (52 step files, `00-base` to `51-3x`). For the current state, read `README.md` in this folder.
> References to `BUILD-GUIDE.md`, `MAINTAINER-STATUS.md` and `notes/` point to private maintainer notes.

Written 2026-10-29 with the first version of `port.sh` and the 36 step files. Nothing in `port/` has run on the real
tree yet. I tested only:

- `bash --posix -n` on all files (syntax),
- `port.sh --check` (preflight) on the real inputs: all checks passed,
- the runner logic (dirty detection, timing, `lpmake` size check, failed step, `--keep-tree`) with stub tools and
  fake steps in a scratch folder,
- `lib.sh` functions and steps 2a, 2i and 2o on a small synthetic tree (the step 2c anchor does not exist in the raw
  donor CIL, so 2c stopped as designed).

Treat every real step as untested until the first run.

## Result you should expect

The files of the five partitions must match the 3h images (`beta5-3h`). The image bytes cannot match: every
`mkfs.erofs` run writes a random filesystem UUID (all layers did that). To compare, extract the 3h images with
`tree_manifest.py` or compare with the `report/<partition>.tsv` files of this run.

Facts that I checked read-only against the existing chain output:

- Every file of `port-rom/pipa_port/` and `port-rom/pipa_port.rc` is byte-equal to the file in `beta5-3g/tree/system_ext`.
- `helper/out/PipaHelper.apk` equals the APK in the 3c and 3f trees. `bootanim/*.zip` equal the 3c files.
- `cryptoeng.jar` and the SukiSU APK (in `pipa_port/`) equal the 3f files. `aidl-modem/network_manifest.xml` equals the
  3d odm file, and `odm_service_contexts.add` is the end of the 3d `odm_service_contexts`.
- `uifirst-policy/sa_block.cil` and `sepolicy/pipa_port_rules.cil` are both inside the 3g `system_ext_sepolicy.cil`;
  `(typepermissive pipa_port)` is absent.
- `work/parts/vendor_b.img` and `odm_b.img` have the pinned md5.
- All `mkfs.erofs` calls of all layers use `-zlz4hc -C65536 -T0`. All `lpmake` calls have the same arguments.
  `mkfs.erofs` is 1.9.4.

## Lineage of the old chain (what "the same result" means)

I followed the `cp -a` lines of each layer script, not the order of `STEPS`.

- 2u is a dead end. 2v takes system_ext from 2t. 2w takes system from 2s and system_ext from 2v. The 3c tree has no
  `my_stock/del-app/SukiSU`. In one tree, step 2u would add it to the final image. Step 2u does nothing unless
  `PORT_WITH_2U=1`. With that variable the result differs from 3h (the preload stays).
- 2y, 3i and 3j are not in the chain. They have no step file. 2z is built on 2x as in the old chain.
- 2c takes system from 2a and system_ext from 1c. 2b changed only vendor, so a single tree gives the same.
- 2q, 2r, 2t, 2v built only system_ext. The other partitions came from the image of the layer before (2t/img for 2u
  and later). No layer between changed product, vendor or odm except: 2j, 2l, 2n (product), baked, 1c, 2b, 3e
  (vendor), baked, 3d (odm), 3h (product). I checked this with the `cp` and `fsck.erofs` lines of every script.
- 3f takes system from 3c and system_ext from 3e. 3d and 3e do not change system (3d: odm and system_ext, 3e: vendor
  and system_ext).
- 3g restores the 3e CIL files and runs `pipa_port_enforce.py` again. 3f had run it already on the same input.
- `ro.pipa.port.layer` is `3g` in the end. 3h does not set it (as before).

## Differences in behaviour

### Whole-image checks and checks of earlier outputs

| Old check | New |
|---|---|
| 3f: `cmp 3c/img/system.img 3e/img/system.img` | Converted. 3c writes `$ORIG/system.fp-after-3c`, 3f compares. The fingerprint (`lib.sh: fingerprint`) hashes path, type, size, **mtime**, owner, mode and link target of every entry. It reads no content. A content change that keeps size and mtime is not detected. A write changes the mtime, so this is a weaker check than the image `cmp`, but it catches any normal edit. |
| 2k: `cmp ROM/chargershim.jar tree-jar && exit 1` ("already patched") | Weakened. 2e now copies the current `port-rom` (patched jar), so "equal" is normal. The step prints a note and writes the jar. It still writes the current jar. |
| 2f: `cmp -s ... && continue` ("unchanged") | Kept. The branch is now always the "unchanged" one for both files. |
| 3g: `cmp ROM/service.sh tree service.sh` | Kept, with `cmp -s ... || die`. |
| every layer: `[ -f $IMGSRC/super.img ]`, `[ -d $P/<tag>-<prev>/tree ]` | Dropped. They only checked that the chain was run. |
| md5 of stock files (jar 2175..., 7afe... before baked, six bake files, mm-sys, xiaomi-keyboard, IPeManager, SystemUI before and after the patch, cryptoeng.jar) | Kept. Same values. 3a checks `CE_MD5` inside the step (the old script did it before it made the work dir). |
| new | Preflight checks the md5 of `vendor_b.img` and `odm_b.img`. The old chain did not check them. |

### `set -e` and `! grep`

- 2s had two `! grep -q` lines. They checked nothing.
  - `! grep -q "settings get " service.sh`: I did not convert it. A real check fails on the current `service.sh`
    (2t went back to `settings get` into a file). I left a comment.
  - `! grep -q 'settings put global $k 0.8' service.sh`: converted to `forbid_grep`. The current `service.sh` passes.
- Bare `grep -q pattern file` lines (they stop the step by `set -e`) are now `need_grep pattern file`. The stop is
  the same, but with a message. `grep -c ...` lines in 2f, 3d and 3e became `need_grep` or a count test.
  In 3d the count must be 2 (the old line only printed it and failed at 0).
- The test lines `[ "$(md5sum ...)" = "$KSU_MD5" ]` (2u, 2w) now have `|| die`.

### Edits that are different in form

- `set_layer` (in `lib.sh`) replaces the 16 copies of the "ro.pipa.port.layer" block. Some old layers used `sed` only
  (2s, 2u, 2w, 2x, 2z, 3a-3g) and some had an "append when absent" branch (2q, 2r, 2t, 2v). The new function does both.
  The result is the same, because the line exists after 2q. 2q appends it.
- `replace_once` and `replace_all` are in `lib.sh` and accept a tree-relative or an absolute path. The Python code is
  the old code.
- 1c: the `DROP_FACEUNLOCK=1` switch is removed. The chain never set it and 2a does the same work (a second removal
  would fail with "FaceUnlock not found").
- 2d and 2e used `T=$(mktemp -d)`. `T` is now the tree, so the temp dir is `TMPD`.
- 3d: the C.06 donor path variable `DONOR` is now `C06_VENDOR` (`DONOR_IMG` is the main donor).
- 3d: the `df` check (12 GB) is gone from the step. The runner checks 20 GB before `mkfs.erofs` and `lpmake`.
- 2e: I added a test that `system_ext/pipa_port` does not exist. `cp -a` would copy into it without a message.
- 2u: I added `exit 0` unless `PORT_WITH_2U=1`, and a test that `del-app/SukiSU` does not exist.
- Temp files of the old layers in `$W/report/` are in `$R` (same place), plus `$W/eng.jar`, `$W/libgpuserviceextimpl.so`,
  `$W/donor/`.
- The `Input:` and `Output:` lines of the step headers are gone (they named the old layer folders). The `Old layer
  script:` line replaces them. All other header text stayed. In some headers a sentence about "run as root" is gone.

### Runner

- The old `build_port.sh` did a label check, `mkfs.erofs` and `lpmake` for each layer. Now: one label check
  (`tree_manifest.py`) for each partition that gets a new image, one `mkfs.erofs` each, one `lpmake`.
- Partition image rules. The old layers copied the input image of a partition that they did not touch: raw donor
  `product.img` in the base layer, raw `vendor_b.img` and `odm_b.img` until `baked`. `port.sh` does the same when no
  step changed a partition. It decides with `fingerprint` (path, size, mtime, ...). `system` and `system_ext` always
  get a new image. With all steps, every partition is new. This matters only for `--until` before 2j or before baked.
- `lpmake`: old layers up to 3c used `| grep -v ... || true`, which hides errors. New code:
  1. writes the output to `report/lpmake.log`,
  2. stops when the exit status is not 0,
  3. prints lines that are not "will resize" or "Invalid sparse" and stops when one has `error`, `fail` or `no space`,
  4. stops when `super.img` is smaller than the sum of the five images, or more than 1 MiB larger.
  The 1 MiB limit comes from the 3h and 3d numbers (68 156 bytes). If another `lpmake` version adds more, the
  runner stops and you must raise the limit.
- The runner keeps `$W/img` and `$W/report`; it removes `tree`, `orig`, `state` after a good run unless `--keep-tree`.
  The old chain kept every tree.
- `report/<partition>.tsv` now exists for all new partitions, not only for the partitions of the last layer.
- Per-step output goes to the terminal and to `report/steps/*.log`. A step runs with `</dev/null`.
- There is no resume. A failed step may leave half of its edits. Start again from the beginning. (Extraction of the
  donor is part of each run.)

### Round trips

The old chain extracted `product` from an image at 2j, 2l, 2n and 3h, `vendor` at 3e and `odm` at 3d. Each time the
tree went through `mkfs.erofs` and `fsck.erofs --extract` first. The single tree has no round trip for these
partitions. If a round trip changed something (hard links, an xattr, a mode), the 3h files can differ from the new
files in `product`, `vendor` or `odm`. I did not look for this. The trees of `system` and `system_ext` were copied with
`cp -a --reflink`; no round trip there.

## Assumptions

1. The current files in `port-rom/`, `helper/out/`, `module/tools/`, `maintainer/*` are what the 3h layers used. The
   old layers read these files at build time (2e copied `port-rom/pipa_port` as it was at the 2e build). I verified the
   byte equality for the files listed above. I did not verify the output of the patch tools (`patch_*.py`, `.sh`)
   against the 3h files. They have md5 checks in some places (3b, 3a).
2. The tree after `apply_port_edits.py` does not depend on the extra directories `product`, `vendor`, `odm` in `$T`.
   The script maps `/system_ext/...` to `system_ext/` and everything else to `system/`. `PORT-EDITS.tsv` has no
   `/product`, `/vendor` or `/odm` rows.
3. `ls "$V"/etc/init/*.rc | head -n 1` in 2b gives the same template file as before. Vendor `etc/init` has no new rc
   files from baked or 1c, so it does.
4. `fsck.erofs --extract` of an image needs a target folder that does not exist. `port.sh` extracts into
   `$T/system`, ... (new folders).
5. The tree fits: 40 GB preflight is a guess from "13-23 GB for each layer" plus 7 GB of images. The
   tree of one run is as large as the tree of the old 3g layer.
6. `sh` can be bash or dash. I avoided bashisms and checked with `bash --posix -n`. Dash was not available here.
   `patch_gamefilter.sh` is run with `bash` as before.

## Not converted

- `build_beta5_2y.sh`, `build_beta5_3i.sh`, `build_beta5_3j.sh` (tests, not in `STEPS`).
- `build_port.sh` is unchanged. Its `LAST` default is `2h` and its text is old. It still builds the chain.
- `flash_super.sh` has no case for a `port.sh` result. I did not edit it.
- `BUILD-GUIDE.md`, `MAINTAINER-STATUS.md`, `CLAUDE.md` do not mention `port/` yet.

## Open questions

1. Delete the tree after a good run (current default) or keep it? The 3d layer needs `port-work/donor-c06-vendor`
   (HDD) in each run.
2. Pin the filesystem UUID (`mkfs.erofs -U`) to get reproducible image md5? I kept the flags of the layers.
3. Should `--until` also accept `--from` with a kept tree? Not possible safely today (see "no resume").
4. Should the tree check labels beyond "has a `security.selinux` xattr" (for example `u:object_r:unlabeled:s0`)? The old
   layers did not.
5. After a switch of `PORT_OVERLAY_SRC` to a frozen overlay folder: it needs the same `system/` and `system_ext/`
   layout, with the files that `PORT-EDITS.tsv` carries.
6. Step 2u: delete the file when you are sure that the preload is gone for good?
7. `c06-vs-beta4/port-overlay.md5` (new on 2026-10-29, not from me) looks like a checksum list of the overlay files. The
   preflight could check `PORT_OVERLAY_SRC` against it. I did not do that, because I do not know its scope.

## Risky spots to check first

1. Steps 3f and 3g (`$ORIG` handling, fingerprint, CIL restore): the only steps with state between steps.
2. Step 2e `cp -a` of the current `port-rom` and then the later steps that rewrite the same files: modes and labels of
   `pipa_port/*` in the new tree against 3h (`tsv` columns mode, uid, gid, xattrs).
3. Step 2u skip (`SukiSU` must not be in `system/my_stock/del-app`).
4. The partitions `product`, `vendor`, `odm` (round trip, see above).
5. The `lpmake` size window and the error scan in `port.sh`.
