# Step 3k: the odm interconnect stack from C.06 (optional, "Tier 1")

Status: built and checked statically, **not flashed, not tested on the tablet**. Image: `port-work/pt4/img/super.img`,
md5 `b75a944c851144b14073f4085f35cb5e`, 6 832 163 388 bytes. It is not in `flash_super.sh`.

## Why

The odm is pinned from beta4. Its OPPO interconnect stack comes from donor C.05, which we do not have. Step 3d added the
C.06 AIDL virtual modem on top of it ("Tier 2"): ten C.06 libs with the same soname as the C.05 libs went into the
private dir `/odm/lib64/aidl`, and `virtual_daemon.rc` sets `LD_LIBRARY_PATH=/odm/lib64/aidl` for the two virtual RIL
daemons. `commcenterd`, the two `pipa_subsys` slots (`libqti-radio-service.so`) and all other users of the stack stay C.05.
So the tablet runs two builds of the same libs at the same time, and the C.06 system side (`com.oplus.subsys`,
`oplus-subsystem-service.jar`, the C.06 IMS app) talks to a C.05 server.

The two builds differ much. Export changes, C.05 -> C.06 (`odm_closure.py --abi-diff`):

| Library | Exports removed / added |
|---|---|
| `libmindroid-framework.so` | -526 / +24 |
| `libqti-radio-service.so` | -435 / +2281 |
| `libdmtp.so` | -98 / +5 |
| `libdmtpclient.so` | -64 / +7 |
| `lib-virtual-modem-api.so` | -52 / +9 |
| `libcommcenterfw.so` | -42 / +8 |
| `vendor.oplus.hardware.subsys_radio` | C.05 `V8`, C.06 `V1`: 39 new types, 1 type removed (`CyberSenseHALCollectionPolicy`) |

A mix of the two builds fails: the C.06 `libqti-radio-service.so` with the C.05 `libmindroid-framework.so` has two
undefined symbols (`mindroid::Ticket::Ticket(int)`, `mindroid::VoteBox::VoteBox(...)`). Step 3k moves the whole stack
to one build.

## What the step does

Run: `sudo env PORT_ODM_C06=1 sh maintainer/port/port.sh <tag> <donor-img-dir> --keep-tree`. Without
`PORT_ODM_C06=1` the step prints `skipped` and exits 0 (the default build does not change).

1. **Replace** 26 C.05 files by the C.06 file of the same path. The write goes into the same inode (label, owner and mode
   stay). The step pins the old and the new md5 of each file. A different base or donor stops the step.
2. **Add** 4 files that only C.06 has: `libipcapis.so`, `libipc-framework.so`, `vendor.oplus.hardware.subsys_radio-V1-ndk.so`
   (they are `NEEDED` by the C.06 `libqti-radio-service.so`), and the 32-bit `libprotobuf-cpp-lite-21.12.so` (from the
   C.06 vendor image; the 32-bit C.06 libs need it). They get label, owner and mode of a sibling file (`vendor_file`, 0644).
3. **Check** that the ten files in `/odm/lib64/aidl` are identical to the files now in `/odm/lib64`.
4. **Run `odm_closure.py --assume-no-private`** on the tree (the private dir is ignored). On a failure, the step stops,
   removes nothing and keeps the tree.
5. **Remove** `/odm/lib64/aidl` and the two `setenv LD_LIBRARY_PATH /odm/lib64/aidl` lines in
   `odm/etc/init/virtual_daemon.rc`. No other file names the dir (checked).
6. **Run `odm_closure.py`** on the final tree. Report: `report/odm-closure-3k.txt`. Table: `report/3k-table.tsv`.

Not changed on purpose:

- `etc/init/subsys_daemon.rc` (port version): the `qti-modem-daemon-*` triggers stay off (they need `/dev/diag`, which the
  `hal_radio_default` domain cannot open). `pipa_port.rc` starts `pipa_subsys0/1`.
- The system_ext sepolicy rule `allow init hal_radio_default (process (noatsecure))` from 3d. It is harmless without
  `LD_LIBRARY_PATH`. A change needs a new policy compile.
- C.05-only files that C.06 does not have: `libradio-service.so`, `libsubsys-service.so`, `libqti-subsys-service.so`,
  `libprotobuf-cpp-{lite,full}-21.7.so`, `vendor.oplus.hardware.subsys_radio-V8-ndk.so`, the HIDL virtual modem
  (`lib-virtual-modem-radio.so`, `lib-virtual-modem-qti-ims.so`), `android.hardware.radio@1.x`, and the HIDL
  `vendor.oplus.hardware.{appradio,ims,radio}@1.0.so`. Nothing loads them after 3k (30 files, 18 in `lib64` and 12 in `lib`, about 32 MB; the report lists them under
  "not in the closure of an rc service"). They are dead weight and can go in a later clean-up.
- `ro.pipa.port.layer`: the step changes only the odm, so there is no package-cache change.

Only the odm differs from port-pt3 (manifest compare of `report/odm.tsv`: 130 -> 123 entries; only the md5 of the
replaced files changes; mode, owner and label of every other entry are equal; the 4 new files have the label of their
sibling; the 11 `lib64/aidl` entries are gone).

### Files (md5, first 12 hex digits; full values in `report/3k-table.tsv` and in the step)

| odm path | C.05 (old) | C.06 (new) |
|---|---|---|
| `bin/commcenterd` | `025daba21160` | `b8ff10e4445a` |
| `bin/hw/subsys_daemon` | `ccd4b9ffc02a` | `9ef3104638be` |
| `lib64/libcommcenterfw.so` | `146c6f67e907` | `04913b71bae9` |
| `lib64/libcommcenterutils.so` | `61c066ab0252` | `977bd7c47d2a` |
| `lib64/libdmtp.so` | `392988227818` | `c697f387ba55` |
| `lib64/libdmtp-protos-lite.so` | `f7661e4c309b` | `1c70c222ee7e` |
| `lib64/libdmtpclient.so` | `05c4d316d9f9` | `c549063dbd20` |
| `lib64/libmindroid-app.so` | `7c295fdff81d` | `b2df55c3135e` |
| `lib64/libmindroid-framework.so` | `80f32ff8f68e` | `8f3c4c13b0ce` |
| `lib64/libqti-radio-service.so` | `04d8e5b073aa` | `48c88bff02b9` |
| `lib64/libradioapis.so` | `6b40be48e74a` | `5ea91118fe06` |
| `lib64/libsubsys-utils.so` | `e264448920c7` | `ab7bdea8fb1a` |
| `lib64/lib-virtual-modem-api.so` | `bda24e2a2a5f` | `8963a15cc342` |
| `lib64/lib-virtual-modem-protos.so` | `412b8a649cc2` | `340a26306b5d` |
| `lib64/vendor.oplus.hardware.communicationcenter-V1-ndk.so` | `9d70aaf48d04` | `c38ef56b9551` |
| `lib64/vendor.oplus.hardware.communicationcenter-V2-ndk.so` | `82a76d974395` | `edc653e0fa17` |
| `lib64/vendor.oplus.hardware.subsys-V5-ndk.so` | `e4d51cfd2a0c` | `7742cb2fc174` |
| `lib/libcommcenterfw.so` | `2baec6dad3a5` | `97627e3a20e6` |
| `lib/libcommcenterutils.so` | `3274235249ea` | `691ccfd3cfbe` |
| `lib/libdmtp.so` | `a6abeecfa9d2` | `3bc227c2e697` |
| `lib/libdmtp-protos-lite.so` | `99be07bee856` | `c97482971454` |
| `lib/libdmtpclient.so` | `8ef6f0d6d351` | `06260884a529` |
| `lib/lib-virtual-modem-protos.so` | `2364e28f4f52` | `2689ab5a5b9f` |
| `lib/vendor.oplus.hardware.communicationcenter-V1-ndk.so` | `6dcbdcae306c` | `585f12eb804f` |
| `lib/vendor.oplus.hardware.communicationcenter-V2-ndk.so` | `a491e0bcbffd` | `9eae0eb69799` |
| `lib/vendor.oplus.hardware.subsys-V5-ndk.so` | `3e96fccb9220` | `d9d1862464fb` |
| `lib64/libipcapis.so` (new, from C.06 odm) | - | `fc20effbaf69` |
| `lib64/libipc-framework.so` (new, from C.06 odm) | - | `c5c3ea630ece` |
| `lib64/vendor.oplus.hardware.subsys_radio-V1-ndk.so` (new, from C.06 odm) | - | `d1e867440deb` |
| `lib/libprotobuf-cpp-lite-21.12.so` (new, from C.06 vendor) | - | `64d742281559` |
| `lib64/libprotobuf-cpp-lite-21.12.so` (already C.06, checked) | `544b9bd64265` | `544b9bd64265` |

The old md5 of every row is equal in `odm_b.img` (beta4) and in the port-pt3 odm. The 10 files in `lib64/aidl` were equal to
the new `lib64` files.

## Decisions

- **Slots `pipa_subsys0/1` (HIDL-style `libqti-radio-service.so`).** The C.06 odm runs this slot itself:
  `etc/init/subsys_daemon.rc` has `qti-modem-daemon-0/1` with `-l /odm/lib64/libqti-radio-service.so` for
  `ro.boot.hardware=qcom`. The C.06 lib resolves in the pad tree (36 files in the closure, no unresolved name, no missing
  symbol). So the step uses the C.06 lib. `pipa_port.rc` does not change. The C.06 lib registers the services itself
  (it imports `AServiceManager_addService`; the C.05 one did that through `libsubsys-service.so`).
- **Private dir.** Removed, because the closure check passes without it and the dir held only copies of the files that now are in
  `/odm/lib64`. Note: a static check cannot prove that a mix is safe (see risks), but after 3k there is no mix.
- **32-bit libs (`/odm/lib`).** Replaced too, so that no C.05 copy stays. No process on the tablet loads `/odm/lib`
  (the tablet map list `notes/aidl-virtual-modem/tablet_libs.txt` has `lib64` only), so this is inert.
- **No ELF outside the odm links an odm interconnect lib** (grep of vendor, system_ext, product, system `lib`, `lib64`,
  `bin`, `etc`, `framework`): only service contexts, the compatibility matrix, `pipa_port.rc` and the two
  `oplus-subsystem-service*.jar` name them. The compatibility matrix needs `communicationcenter` 1-2 and
  `subsys_interface.subsys` 1-5. The odm manifests (unchanged) give 2 and 5. `ISubsysRadio` has no version in the matrix.

## Closure check: `maintainer/port/odm_closure.py`

Python 3 stdlib only (own ELF parser; it does not need `readelf`; `DT_NEEDED`, undefined and exported symbols are equal to
`readelf` output on 70 odm files; on the bionic `libc.so` 17 IFUNC exports differ in that compare, the rest is equal). It reads a tree (`--tree`, optional `--odm` for another odm folder such as an extracted `odm.img`):

- Roots: every service in the rc files of odm, vendor, system_ext, system and product that starts from `/odm` or has a
  `-l /odm/...so` argument (13 services, including `pipa_subsys0/1`). The private dirs are the `setenv LD_LIBRARY_PATH` of
  the service. A `dlopen("/odm/...so")` string in a lib adds an edge. Every other ELF in `/odm` is a root of its own.
- Resolution order: private dirs, `/odm/lib64|lib`, `/vendor/...`, `/system/...`, `/system_ext/...`, `/product/...`
  (system, system_ext and product count only for the names in `llndk.libraries.txt` / `public.libraries.txt`; else
  `NOT-VISIBLE`), then the APEX libs. `com.android.runtime` and `com.android.i18n` are unpacked from the `.apex` files
  (zip + `fsck.erofs`), so `libc.so`, `libm.so`, `libdl.so` are real files and their symbols are checked.
- Symbols: each strong undefined dynamic symbol of every `/odm` ELF must be defined by a lib of the same closure.
- `--abi-diff OLD_ODM`: export changes of each changed lib.
- Exit status 1 for an unresolved `DT_NEEDED`, a missing symbol or an unreadable ELF in a service closure. Files that no
  service reaches give `WARN` (with `--strict` also a failure). A start target that is not in the odm (disabled
  services, `libmtk-radio-service.so`, `oplus_sensor_ssr`) gives `INFO`.

The reports are in `port-work/pt4/report/odm-closure-*.txt` (baseline, before removal, final with `--abi-diff`, one negative control).

Results (all with the system, system_ext, vendor and product of the pt4 tree; the baseline odm is the extracted
`port-work/pt3/img/odm.img`, so no `pt3b` build was needed; only the odm differs):

| Case | ELF in odm | Unresolved `DT_NEEDED` | Strong undefined symbols checked / missing |
|---|---|---|---|
| Default build (port-pt3 odm, `LD_LIBRARY_PATH` of 3d honoured) | 80 | 0 | 28 463 / 0 |
| pt4 before the removal, private dir ignored (`--assume-no-private`; the 10 aidl copies are also in the 84) | 84 | 0 | 0 missing |
| pt4 final (`report/odm-closure-3k.txt`) | 74 | 0 | 28 245 / 0 |

Negative controls (the check does fail when it should):

- pt4 odm with the C.05 `libmindroid-framework.so` put back: `FAIL`, `mindroid::Ticket::Ticket(int)` and
  `mindroid::VoteBox::VoteBox(...)` for `qti-modem-daemon-0/1` and `pipa_subsys0/1`.
- pt4 odm plus the C.06 `libcryptoapis.so`: `FAIL`, `android.hardware.security.keymint-V4-ndk.so` not found and
  `vendor.oplus.hardware.cryptoeng-V1-ndk.so` only in `/system_ext` (not visible to a vendor process). So this lib would not
  load on the pad; the step does not add it.
- Limit: the default odm without `lib64/aidl` also passes (the C.06 virtual-modem libs only import symbol names that the C.05
  libs also export). A symbol check cannot see changed struct layouts, vtable layouts or behaviour. It proves
  completeness of the names, not compatibility. For 3k this is acceptable because every interconnect file is now
  byte-equal to C.06; the open part is C.06 against the beta4 vendor and the C.06 system, and those names all resolve.

`dlopen` strings that name files that are not in the tree (INFO lines): the C.06 `libqti-radio-service.so` names
`/odm/lib64/{libcryptoapis,libnvbackupapis,librsautils}.so` (new against C.05), plus `libimsortcapis`, `libnvram`,
`libttsatellite-rpc801`, `vendor.oplus.hardware.displaypanelfeature*` (C.05 named these too), and
`lib-virtual-modem-radio-aidl.so` names `lib-virtual-modem-mtk-ims-aidl.so` (also in 3d).

## Risks

1. **Behaviour is not proven.** Only link completeness is. The C.06 daemon and libs run for the first time on the pad as
   a set. If `commcenterd` or `subsys_daemon` crash, the sharing features stop (the 3d virtual modem also: it uses the same
   `subsys_daemon`, `libmindroid-*`, `lib-virtual-modem-api`).
2. **SELinux.** The `pipa_subsys` slots run in the enforcing domain `pipa_port`. The C.06 `libqti-radio-service.so` has
   new paths: `/data/vendor/olog/enable_olog`, `/proc/devinfo/lcd`, `/dev/ttyHS3`, `/dev/esim-*`, `/dev/702_satellite`,
   `/mnt/vendor/persist/satellitecomm`, `/sdcard/.dcs_olog`, `/odm/etc/plugin_config.xml`. A denial on these should only
   hurt satellite, eSIM and log features. If it registers a service name that `odm_service_contexts` does not label (the
   labels are `ISubsys/default`, `ISubsysRadio/slot1`, `slot2`), `servicemanager` refuses the add, and the slot does not
   register. This is the first thing to look at in logcat.
3. **Missing plugins.** `plugin_config.xml` lists plugin libs that the pad does not have (`librfapis`, `libnvramapisv*`,
   `libqms_client`, display and satellite libs). The C.06 code checks "file exist" before it loads the crypto plugin; for
   the others it is not known. The C.05 lib had the same kind of missing files, so this is not new, but the set grew.
4. **Orphans stay.** C.05-only libs stay on the partition (30 files, about 32 MB). Nothing loads them.
5. **Servers move to V1 for `ISubsysRadio`.** The C.06 clients were built against the C.06 interface, so this should
   help, but the pt3 behaviour (which works for network sharing, calls and SMS) is the baseline. Any change from it is a
   regression of 3k until proven otherwise.
6. **Donor lock-in.** The md5 table is for this C.06 donor. A new donor stops the step (this is the intent). Regenerate
   the table from the new `odm.img` after you read the diff.
7. The check model of the linker namespaces is approximate (LLNDK/public lists, no `ld.config.txt` parse, no `dlopen` by
   computed names).

## Open questions

- Does the C.06 `libqti-radio-service.so` run in `pipa_subsys0/1` without a crash, and which service names does it
  register? (Test step 3 below.)
- Do the missing plugin libs (`libcryptoapis`, `libnvbackupapis`, `librsautils`) matter on the pad? If a log shows a
  failed `dlopen`, decide then: `libcryptoapis.so` needs `keymint-V4` and `cryptoeng`, which the pad cannot give to an odm process.
- Delete the 30 dead C.05 files (includes the dead HIDL virtual modem libs) in a later step?
- Remove the `noatsecure` rule of 3d from the system_ext sepolicy later (not needed any more; it needs a policy compile).

## Test plan (user)

Before: note on port-pt3 what works now (network sharing, call ring and audio, SMS), so that you can compare.

1. Flash (super only, slot B, no wipe; the md5 is checked):
   `sh maintainer/flash_super.sh -y ~/Documents/pipa/port-work/pt4/img/super.img b75a944c851144b14073f4085f35cb5e`
   The first boot is as long as for any dirty flash. Unlock the tablet once.
2. Identity and processes (ADB, root):
   - `md5sum /odm/bin/commcenterd` must be `b8ff10e4445ac9e7577ec100af98e4b2`. `ls /odm/lib64/aidl` must fail.
   - `ps -A | grep -E 'commcenterd|subsys_daemon'`: `commcenterd` and four `subsys_daemon` (`virtual-ril-daemon-0/1`,
     `pipa_subsys0/1`), and the same pids after 5 minutes (no restart loop).
   - `for p in $(pidof commcenterd subsys_daemon); do grep -c 'lib64/aidl' /proc/$p/maps; done` must print 0.
     `grep libprotobuf-cpp /proc/$(pidof commcenterd)/maps` must show only `21.12`.
   - `service list | grep -iE 'subsys|Dmtp|vircomm'`: `ISubsys/default`, `ISubsysRadio/slot1`, `ISubsysRadio/slot2`,
     `IDmtpService/default`, the `IRadio*/vircomm1|2` and `vircommslot1|2` names. Compare with port-pt3.
   - `ls /data/tombstones` (new `subsys_daemon` or `commcenterd` files = fail) and
     `logcat -b all -d | grep -iE 'CANNOT LINK|dlopen failed|Fatal signal|avc: +denied.*(pipa_port|hal_radio)|addService|Permission denied'`.
   - `sh maintainer/device_check.sh pt4`.
3. Network sharing: pair with the OPPO phone as before and turn on network sharing on the phone. The tablet must
   get internet through the phone (open a web page; `ip link show ovnet0` must exist while sharing is on).
4. Call: call the phone from another number. Check that it rings on the tablet, that you hear the caller after you answer
   on the tablet, and that the caller hears you (both directions). Then make a call from the tablet, and hang up from each
   side one time. The known echo for the far end (BUGS-TODO 27) is not a 3k regression.
5. SMS: send an SMS to the phone number and read it on the tablet. Send one from the tablet.
6. After a reboot of the tablet (no re-pairing): repeat step 2 and the quick checks 3, 4 and 5. Also check
   `getprop init.svc.virtual-ril-daemon-0` is `running`.
7. Pass: every feature that worked on port-pt3 works, no tombstone, no new `avc: denied` for the interconnect processes.
   Save `logcat -b all -d` and `dmesg` if anything fails.

## Rollback

Flash the default build: `sh maintainer/flash_super.sh -y port-pt3` (md5 `cd30ab3df125f3849e435de4b09a9e44`). No wipe is needed
(the step changes only the odm; it writes nothing to `/data`). If the pairing is gone after the rollback, pair again.
If the tablet does not boot, use TWRP or fastboot with the same command (CLAUDE.md "If the tablet does not boot").
To build the default image again: `sudo sh maintainer/port/port.sh <tag> <donor> --keep-tree` (without `PORT_ODM_C06`).
