# port: single-tree build of the ColorOS 17 port

`port.sh` builds the port ROM (`super.img`) in one tree. It replaces the layer chain of `build_port.sh`.

The old chain ran 36 scripts. Each script extracted the images of the previous script, made its edits, and ran
`mkfs.erofs` and `lpmake`. That used 13-23 GB of disk for each layer. The new build does this one time:

1. Extract the donor and the pinned beta4 `vendor` and `odm` into one tree.
2. Run the steps in order. Each step edits the tree.
3. Check the SELinux labels, run `mkfs.erofs` for each partition, and run `lpmake`.

The result must have the same files as the 3h images of the old chain. The image bytes differ: `mkfs.erofs` puts a
random UUID in each image. Compare the files, not the image md5. Read `NOTES-refactor.md` for all differences.

## Files

| File | Use |
|---|---|
| `port.sh` | The runner. |
| `lib.sh` | Helper functions for the steps (`replace_once`, `need_grep`, `set_layer`, `fingerprint`, ...). |
| `steps/NN-<step>-<name>.sh` | One file for each step (00-base to 46-3s). 47 files. Steps 00-37 match the old layer scripts; 39-3l and later are new steps. Step 38-3k is optional (`PORT_ODM_C06=1`). `odm_closure.py` checks the odm libraries (see `NOTES-3k-odm-c06.md`). |
| `NOTES-refactor.md` | What is not 1:1, every difference, every assumption. |

The old scripts (`build_port.sh`, `build_beta5*.sh`) stay unchanged.

## How to run

```sh
sh maintainer/port/port.sh --check <tag> <donor-img-dir>                 # preflight only, builds nothing
sudo sh maintainer/port/port.sh <tag> <donor-img-dir> [--until <step>] [--keep-tree]
```

Example:

```sh
sudo sh maintainer/port/port.sh single ~/Documents/pipa/donor/OPD2515_11.C.06/img
```

- `<tag>` is the name of the run. Use a new tag. The run deletes `port-work/<tag>/`. The runner refuses a tag that
  the old chain used (`port-work/<tag>-baked` exists) unless you set `PORT_FORCE=1`.
- `--until <step>` stops after this step. Step names: `base baked 1c 2a ... 2x 2z 3a ... 3j 3k 3l 3m 3n 3o 3p`. The default is the last step (3p). Step 3k does nothing without `PORT_ODM_C06=1`. `--until 3h` gives the old chain's 3h.
- `--keep-tree` keeps `port-work/<tag>/tree`. Without it, the runner deletes the tree after a good run. After a
  failed run, the tree always stays.
- `--check` does the preflight and stops.

Set variables with `sudo env NAME=value sh ...` (plain `sudo` can remove them).

| Variable | Default | Use |
|---|---|---|
| `PORT_OVERLAY_SRC` | `COS17/port-overlay` | The frozen beta4 files for `PORT-EDITS.tsv` (md5 list `maintainer/c06-vs-beta4/port-overlay.md5`). It needs `system/` and `system_ext/`. The full beta4 tree `port-work/roundtrip/src` also works. |
| `PORT_WITH_2U` | `0` | Set to `1` to apply step 2u. The old chain does not have 2u in 3h. |
| `PORT_ODM_C06` | `0` | Set to `1` to apply the optional step 3k: the OPPO interconnect stack in the odm from C.06 ("Tier 1"). Read `NOTES-3k-odm-c06.md` first. |
| `PORT_FORCE` | `0` | Set to `1` to overwrite a work dir that `port.sh` did not make. |
| `PIPA_ROOT`, `PIPA_OWNER` | as in the old scripts | Base folder and owner of the result files. |

### Preflight

The preflight stops the run when one of these is true:

- `/mnt/reference` is not mounted.
- A donor image, a tool (`fsck.erofs`, `mkfs.erofs`, `lpmake`, ...) or an input of a step is missing.
- The md5 of `work/parts/vendor_b.img` is not `b601a907363d01e78697cd5d4f60edf6`, or the md5 of `odm_b.img` is not
  `8e25ab23745ad3d9abb7a3312abe3e23`.
- Less than 40 GB is free in `port-work`.

Each step lists its own inputs in `#NEEDS:` lines at the top. The preflight checks them.

### Safety checks during the run

- The runner checks for 20 GB free space before `mkfs.erofs` and before `lpmake`.
- The runner stops when `lpmake` exits with an error or prints an error line.
- The runner stops when the size of `super.img` is not the sum of the images plus less than 1 MiB.
  (In 3h, the difference was 68 156 bytes.) A full disk makes a short `super.img` without an error. Do not flash a
  file that fails this check.
- The runner makes a new image only for a partition that a step changed. It copies the input image of the other
  partitions. With all steps, every partition changes.

### Result

All files are in `port-work/<tag>/`:

| Path | Content |
|---|---|
| `img/super.img` | The sparse super image, and the five partition images. |
| `report/PORT-REPORT.txt` | Time of each step, image sizes, the final md5. |
| `report/steps/NN-<step>-<name>.log` | The output of each step. |
| `report/<partition>.tsv` | `tree_manifest.py` output (path, mode, owner, md5, xattrs) for each new partition. |
| `report/port.log`, `report/mkfs_*.log`, `report/lpmake.log` | Logs of the runner. |

To flash: add a name to the `case` list of `flash_super.sh`, then run `sh flash_super.sh -y <super.img> <md5>`.

## Steps

The runner starts each step as its own `sh` process, in the order of the number `NN`. The step name is the second
part of the file name (`23-2u-sukisu-preload.sh` has the name `2u`).

A step gets these variables: `T` (tree root with `system system_ext product vendor odm`), `W` (work dir),
`R` (report dir), `ORIG` (`$W/orig`), `HERE` (`COS17/maintainer`), `PORT`, `ROM` (`COS17/port-rom`), `MOD`, `TOOLS`,
`PARTS`, `DONOR_IMG`, `TAG`, `OWNER`, `P` (`port-work`), `PORT_OVERLAY_SRC`.

A step does not extract, label-check, run `mkfs.erofs`, or run `lpmake`. The runner does that.

### Order and lineage

The old chain is not a straight line. These facts matter:

- Step 2u is skipped by default. In the old chain, 2v is built on 2t and 2w is built on 2s. Thus the 3h images do not
  have the SukiSU preload of 2u.
- Step 2y (test layer) is not part of the chain. It has no step file. 3i and 3j are steps 36 and 37 (added
  2026-10-29; the tablet runs them since 3j).
- Step 3g needs the system_ext SELinux files as the 3e tree had them. Step 3f saves them in `$ORIG`. Step 3g
  restores them and applies the rules again.
- Step 3f checks that the system tree did not change since 3c. Step 3c records a fingerprint in `$ORIG`.

### Table: step, old layer script, partitions touched

"Touched" means that the step changes files in this partition. The old layers sometimes built more partitions than
they changed (for example 3a to 3c built `system` again without a change).

| NN | Step | Old layer script | Partitions touched |
|---|---|---|---|
| 00 | base | `build_beta5.sh` | system, system_ext |
| 01 | baked | `build_beta5_baked.sh` | system, system_ext, vendor, odm |
| 02 | 1c | `build_beta5_1c.sh` | system_ext, vendor |
| 03 | 2a | `build_beta5_2a.sh` | system |
| 04 | 2b | `build_beta5_2b.sh` | vendor |
| 05 | 2c | `build_beta5_2c.sh` | system, system_ext |
| 06 | 2d | `build_beta5_2d.sh` | system |
| 07 | 2e | `build_beta5_2e.sh` | system, system_ext |
| 08 | 2f | `build_beta5_2f.sh` | system_ext |
| 09 | 2g | `build_beta5_2g.sh` | system_ext |
| 10 | 2h | `build_beta5_2h.sh` | system_ext |
| 11 | 2i | `build_beta5_2i.sh` | system_ext |
| 12 | 2j | `build_beta5_2j.sh` | system_ext, product |
| 13 | 2k | `build_beta5_2k.sh` | system_ext |
| 14 | 2l | `build_beta5_2l.sh` | system_ext, product |
| 15 | 2m | `build_beta5_2m.sh` | system_ext |
| 16 | 2n | `build_beta5_2n.sh` | system_ext, product |
| 17 | 2o | `build_beta5_2o.sh` | system |
| 18 | 2p | `build_beta5_2p.sh` | system, system_ext |
| 19 | 2q | `build_beta5_2q.sh` | system_ext |
| 20 | 2r | `build_beta5_2r.sh` | system_ext |
| 21 | 2s | `build_beta5_2s.sh` | system, system_ext |
| 22 | 2t | `build_beta5_2t.sh` | system_ext |
| 23 | 2u | `build_beta5_2u.sh` | none by default (system, system_ext with `PORT_WITH_2U=1`) |
| 24 | 2v | `build_beta5_2v.sh` | system_ext |
| 25 | 2w | `build_beta5_2w.sh` | system, system_ext |
| 26 | 2x | `build_beta5_2x.sh` | system, system_ext |
| 27 | 2z | `build_beta5_2z.sh` | system, system_ext |
| 28 | 3a | `build_beta5_3a.sh` | system_ext |
| 29 | 3b | `build_beta5_3b.sh` | system_ext |
| 30 | 3c | `build_beta5_3c.sh` | system_ext |
| 31 | 3d | `build_beta5_3d.sh` | system_ext, odm |
| 32 | 3e | `build_beta5_3e.sh` | system_ext, vendor |
| 33 | 3f | `build_beta5_3f.sh` | system, system_ext |
| 34 | 3g | `build_beta5_3g.sh` | system_ext |
| 35 | 3h | `build_beta5_3h.sh` | product |
| 36 | 3i | `build_beta5_3i.sh` | product |
| 37 | 3j | `build_beta5_3j.sh` | vendor |
| 38 | 3k | none (new) | odm, only with `PORT_ODM_C06=1` |

The order of `build_port.sh` is the order of the numbers.

## How to add a step

1. Choose the next number and a short name. Example: `39-3l-short-name.sh`. The step name (`3l`) must be unique.
   Do not use `2y`: the old test layer has this name.
2. Copy a small step (for example `15-2m-layer-caching-off.sh`) and change it.
3. Start with the header comment: what the step does and why. Keep it as short as the old layer headers.
4. Add `#NEEDS: "<path>" ...` lines for every input file outside the tree (patch tools, APKs, ROM files).
5. Source `lib.sh` and set `STEP=<name>`. Edit the tree only through `$T`.
6. Check every input before you change it: the md5 of a stock file, or an anchor that must occur once
   (`replace_once`). A different donor must stop the step with a clear message.
7. Write to existing files with `cat new > old`. Never use `sed -i` or `mv` on a file in the tree. The same inode
   keeps the label, owner and mode. A new file needs `chown`, `chmod` and `setfattr -n security.selinux`.
8. Do not use `! grep -q x file`. `set -e` ignores it. Use `forbid_grep`, or `if grep -q ...; then ...; exit 1; fi`.
9. If the step changes a system or system_ext file that Android caches, call `set_layer "$STEP"`. `early.sh` clears
   the package cache when `ro.pipa.port.layer` changes.
10. If the step needs the old state of a file that a later step changes, save a copy in `$ORIG`. Say it in a comment.
11. Test with `sudo sh port.sh <tag> <donor> --until <step> --keep-tree`. Look at `report/steps/<NN-...>.log`.
12. Add the step to the table above, to `BUILD-GUIDE.md`, and to `MAINTAINER-STATUS.md`.

## What to do on a new donor

The first steps stop on a new donor. This is expected. It is the safety net.

1. Run `sh port.sh --check ...` first.
2. Start the build. `port.sh` extracts the new donor before step `base`. When a step stops, the tree stays in
   `port-work/<tag>/tree`.
3. Read the message of the step. These steps check the donor files:

   | Step | Check |
   |---|---|
   | base | md5 of the stock `oplus-services.jar`, rows of `PORT-EDITS.tsv`, md5 of the engineer-patched jar |
   | baked | stock and baked md5 of the six baked files, md5 of the odm `init.oplus.mm-sys.sh`, anchors for `replace_once` |
   | 2a, 2c, 3c, 3d | text anchors in feature lists, CIL files and `virtual_daemon.rc` (`replace_once` needs exactly one match) |
   | 2b | md5 and instruction word of `xiaomi-keyboard` |
   | 2p | `IPE_STOCK_MD5` of `IPeManager.apk` |
   | 3b | `SUI_MD5` and `SUI_NEW` of `SystemUI.apk` |
   | 2h, 2w, 2x, 2z, 3e, 3f | the patch tools in `module/tools/` and `maintainer/` stop on an unknown binary or text |

4. Make the fix again from the new file (`module/tools/*`, `patch_framework.sh`, `ipe-fluid/`, `gamefilter/`).
   Change the md5 in the step. Start the build again from the start. There is no resume: a step that stopped can
   leave half of its edits in the tree.
5. Before you flash a rebase, scan the changed libraries for new `waitForService` imports. They hang `system_server`:
   `sudo bash maintainer/wfs_scan.sh <old tree> <new tree>` (for example `../reference/cos17` and
   `port-work/<tag>/tree`).
6. Update `c06-vs-beta4/PORT-EDITS.tsv` with `maintainer/port_diff.py`:
   `port_diff.py changes OLD_DONOR PORT -o OUT`, then `port_diff.py rebase OLD_DONOR PORT NEW_DONOR -o OUT`.
   Read `OUT/apply.sh` and `OUT/conflicts/` before you use them. Details: `notes/PORT-MAINTAINER.md`.
7. After the build: add a name to `flash_super.sh`, flash, run `maintainer/device_check.sh <tag>`.
   The list "re-verify on a new base" at the end of `build_port.sh` still applies.
