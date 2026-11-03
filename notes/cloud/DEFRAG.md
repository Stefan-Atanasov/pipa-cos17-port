# DefragService / oplus_defrag on pipa (static analysis, draft)

Scope: donor C.07, pipa port kernel (branch `oppo`, 4.19.325), Java disassembly of services.jar and oplus-services.jar. No device was used.
Marks: [seen] read in a file, [inferred] concluded from facts, [unknown] needs a device or OPPO source.

## 1. Summary

- [inferred] `oplus_defrag` will start and register on pipa. The rc, the SELinux domain and the service labels are all in the donor `system_ext`.
- [inferred] Plain file defrag (`F2FS_IOC_DEFRAGMENT`) will work. It is a stock f2fs ioctl and the pipa kernel has it.
- [seen] Dedup needs OPPO-only f2fs ioctls (numbers 100..107). The pipa kernel has none of them.
- [seen] Turbo Pocket needs a UFS sysfs node `ufstp` and an OPPO `/proc/devinfo/ufs`. pipa has neither.
- [inferred] Result: plan (b) for defrag, plan (c) for dedup and Turbo Pocket. Do not patch the Java waits. Fix the policy of the service and turn off the two parts that cannot work with props.

## 2. What oplus_defrag does

One process (`system_ext/bin/oplus_defrag`, 342 KB, aarch64) serves two AIDL services through `LazyServiceRegistrar`.
- [seen] `DefragService`, interface `oplus.os.IDefrag`. Callback: `oplus.os.IDefragTaskListener` (`onStatus`, `onFinished`).
- [seen] `CompressScanService` (native side of app compress and file dedup).
- [seen] Both names are labelled `defrag_service` in `system_ext_service_contexts`.

### 2.1 IDefrag methods and codes [seen: `services/oplus/os/IDefrag$Stub.txt`]

| Code | Method | Called by (Java) |
|---|---|---|
| 1 | `defragFiles(int userId, listener)` | `StorageManagerService.runIdleMaint` |
| 2 | `abortDefragFiles(listener)` | `StorageManagerService` (abort path) |
| 3 | `startScan(listener)` | `runIdleMaint` (compress and dedup scan) |
| 4 | `abortScan(listener)` | abort path |
| 5 | `startTurboPocket(listener)` | `runIdleMaint` |
| 6 | `abortTurboPocket(listener)` | abort path |
| 7 | `replayTurboPocketBoot(listener)` | `replayTurboPocketBootAsync` (own thread, boot) |

[seen] The service checks the caller uid. It logs `DefragService: permission denied for uid=` for a wrong caller.

### 2.2 The three functions

1. File defrag [seen strings]. It uses `ioctl(F2FS_IOC_DEFRAGMENT)` and `FS_IOC_GETFLAGS`. It asks a helper, `/system_ext/bin/defrag_wrapper` (shell script, `app_process` with `defrag_wrapper.jar`), for the list of cold apps and the foreground user (`-U`, `-A`, `-AT`, `-W` options; it uses UsageStats and PackageManager over binder). It works on app files (`/data/app`, `/data/data/<pkg>`, `/data/media/<user>/Android/{data,media,obb}`) and some user folders (DCIM, Download, Tencent...). State is kept in `/data/oplus/bsp_storage/{defrag_info,scan.cfg,scan_info}` and an SQLite DB.
2. App compress and file dedup [seen strings]. It scans, keeps SQLite tables (`config`, `dedup` with path, size, mtime, md5), then calls f2fs ioctls (section 3). It reports through the callbacks `setAppCompressCallback`, `setFileDedupCallback`.
3. Turbo Pocket [seen strings]. It copies hot app files to a fast UFS area ("pocket"). It uses FIEMAP for LBAs, the Java service `storage_healthinfo` (`IStorageHealthInfoService.turboPocketCopyLbaRanges`), and a UFS sysfs directory `ufstp` (`tp_enable`, `max_inodes`, `available_tp_size`, add and del inode). At boot, `replayTurboPocketBoot` writes the inode list back to the kernel.

## 3. What it needs, and what pipa has

### 3.1 Kernel ioctls

The ioctl magic is `0xf5` (`F2FS_IOCTL_MAGIC`). I read the numbers from `mov` immediates before each `ioctl` call. The direction and size bits are from the `movk` that follows. Names for the OPPO numbers come from the log strings near each call site. The mapping of name to number for 100..107 is [inferred]; the numbers themselves are [seen].

| Number | Value / form | Name | pipa kernel |
|---|---|---|---|
| 8 | `_IOWR(0xf5,8,16 bytes)` = 0xc010f508 | `F2FS_IOC_DEFRAGMENT` | present [seen] `include/uapi/linux/f2fs.h:19`, `fs/f2fs/file.c:4359` |
| 17 | `_IOR(0xf5,17,u64)` | `F2FS_IOC_GET_COMPRESS_BLOCKS` | present [seen] |
| 19 | `_IOR(0xf5,19,u64)` | `F2FS_IOC_RESERVE_COMPRESS_BLOCKS` | present [seen] |
| 23 | `_IO(0xf5,23)` | `F2FS_IOC_DECOMPRESS_FILE` | present [seen] `file.c:4165` |
| 24 | `_IO(0xf5,24)` | `F2FS_IOC_COMPRESS_FILE` | present [seen] `file.c:4238` |
| 100 (0x64) | write, 4 bytes | `F2FS_IOC_DEDUP_CREATE` [inferred] | missing [seen] |
| 101 (0x65) | write, 8 bytes | `F2FS_IOC_CLONE_FILE` [inferred] | missing |
| 102 (0x66) | write, 4 or 8 bytes | `F2FS_IOC_DEDUP_FILE` [inferred] | missing |
| 103 (0x67) | read, 8 bytes | `F2FS_IOC_DEDUP_GET_FILE_INFO` / is-deduped query [inferred] | missing |
| 106 (0x6a) | read/write, 8 bytes | `F2FS_IOC_MODIFY_CHECK` [inferred] | missing |
| 107 (0x6b) | no argument | `F2FS_IOC_DEDUP_PERM_CHECK` [inferred] | missing |

- [seen] The binary also names `DEDUP_SET_MODIFY_CHECK` and `is_dedupped`. These share the numbers above. 104 and 105 do not appear in the binary [seen: no `mov` with those values].
- [seen] `fs/f2fs/file.c` has no case above 25 and no word `dedup` or `clone_file` anywhere in `fs/f2fs`. An unknown f2fs ioctl returns `-ENOTTY` [inferred, standard behaviour].
- [seen] The binary logs `F2FS_IOC_*` failures with errno and goes on or breaks per file. It does not abort the process [inferred from the "error and break" strings].

### 3.2 f2fs features, sysfs, proc

| Need | Source | pipa |
|---|---|---|
| `CONFIG_F2FS_FS_COMPRESSION` | kernel | `=y` in `pipa_defconfig:728` [seen] |
| `/sys/fs/f2fs/features/may_compress` (OPPO node, read by the binary) | `sysfs.c` | absent. `sysfs.c` has a `compression` node only [seen] |
| On-disk `compression` feature and a compress mount option on `/data` | Xiaomi fstab, mkfs | [unknown] (device check D3) |
| init command `update_f2fs_compr_ext` (rc line `on property:persist.oplus.compr.ext=*`) | init | the donor `init` has the command [seen]. It writes a sysfs/mount value; pipa f2fs has no matching OPPO node [inferred]. Effect: a log line at most |
| `/sys/devices/platform/soc/4804000.ufshc/ufstp/*` or `.../112b0000.ufshci/ufstp/*` | OPPO UFS driver | pipa UFS is `1d84000.ufshc` [seen `kona.dtsi:3069`], and the kernel has no `ufstp` [seen: grep over `drivers/scsi`] |
| `/proc/devinfo/ufs` (`is_turbo_pocket_target_ufs`) | OPPO kernel | no `devinfo` proc code in the pipa kernel [seen]. The SELinux label exists (`proc_devinfo_file`) [seen] |
| Java `storage_healthinfo` service + native lib `turboPocketCopyLbaRanges_native` | oplus-services | the Java class is in the jar [seen]. Whether the native part loads is [unknown] (device check D6) |
| `/data/oplus/bsp_storage` | donor `init.rc:1927` (mkdir 0775 system system, restorecon) | present if the port uses the donor init.rc [inferred] |
| Libs: `libsqlite`, `libssl`, `libxml2`, `liblogwrap`, `libbinder` | donor `system/lib64` | present [seen] |

### 3.3 Services, SELinux, props

- Services it calls: `storage_healthinfo` (TP only). `installd` has `service_manager find` on it [seen cil:10946].
- SELinux [seen]. `file_contexts`: `/system_ext/bin/oplus_defrag` is `installd_exec`. The platform cil has `typetransition init installd_exec process installd`. So the process runs in domain **`installd`**, not in its own domain. `system_ext_sepolicy.cil` gives `installd`: `service_manager add` on `defrag_service`; `sysfs_fs_f2fs` file and dir access; `oplus_storage_data_file` (the bsp_storage dir); `sysfs_devices_block`; `exported_system_prop` set; `ctl_start_prop` set; `system_file execute_no_trans`. `system_server` has `service_manager find` on `defrag_service` [seen cil:20501].
- [seen] No `allowxperm` rule names `installd`. So ioctl rights on files come from the plain `ioctl` permission [inferred].
- Property `oplus.defragservice.status` is `exported_system_prop` [seen]. Java writes it; the rc starts or stops the service on 1 or 0.

Props that gate the feature [seen unless noted]:

| Prop | Read by | Effect |
|---|---|---|
| `persist.sys.oplus.disableDefragFiles` (default "0") | `StorageManagerService.runIdleMaint`, `OplusStorageManagerFeature.runIdleMaintForground` | "1" turns off file defrag |
| `persist.sys.oplus.nandswap.devlife` (default "true" if unset) | same | must be "true" for defrag. Who sets it on pipa: [unknown] |
| `persist.sys.oplus.disableCompressDedup` (default "0") | `runIdleMaint` | "1" turns off `startScan` |
| `persist.sys.oplus.disableTurboPocket` | `runIdleMaint`, `replayTurboPocketBootAsync` | "1" turns off TP and the boot replay thread |
| `persist.oplus.compr.ext` | rc (`update_f2fs_compr_ext`) | f2fs compress extension list |
| `oplus.compressdedup`, `oplus.defragservice.status` | Java sets, rc reads (status only) | service start/stop |
| `persist.sys.oplus.DefragFiles{DbScore,RegScore,Runtime,WriteDbSum,WriteRegSum}`, `TurboPocketHotColdThresholdSec`, `TurboPocketScanMinIntervalSec` | binary | tuning and counters |

[seen] `connectDefrag()` is called only if at least one of defrag, scan or TP is enabled. If the three props above turn all three off, `StorageManagerService` never calls `waitForService("DefragService")` from `runIdleMaint`. The boot thread is off with `disableTurboPocket=1`. [seen] The `DeviceStorageMonitorServiceExtImpl` dedup path runs only when an app calls the `storagecompressdedup` service (mEnable and a caller are needed) [inferred]. It is not part of the boot or idle path.

## 4. Gaps: small or big?

- Defrag: no gap.
- Compress (ioctl 17/19/23/24): kernel side present. Gap may exist in the OPPO `may_compress` sysfs node (a one-line read-only feature file, small [inferred]) and in the fs on-disk feature (device check).
- Dedup (ioctl 100..107): [inferred] big. The names `DEDUP_CREATE`, `CLONE_FILE`, `DEDUP_FILE`, `MODIFY_CHECK` point to a layered, shared-extent file format inside f2fs. The log says "not deduped but layered, revoke". That is an on-disk change, with read, write, truncate, GC and fsck paths. A port to a 4.19 tree needs OPPO's kernel source (not available here [unknown]) and a patched `fsck.f2fs`. I do not call it portable.
- Turbo Pocket: [inferred] big and hardware bound. It needs the UFS driver extension `ufstp` and a UFS device that has the feature. pipa has UFS 3.1 [task statement]; the binary reads `/proc/devinfo/ufs` and logs "UFS not %s, skip turbo pocket". The exact UFS string it wants is [unknown].

## 5. Prediction for today

1. [inferred] Lookup of `DefragService` makes servicemanager ask init (`interface aidl`). init starts `oplus_defrag` as `installd`. Depends on lazy-AIDL support in the pipa servicemanager and init [unknown, device check D1]. Other lazy services (cotaservice, ImsVt) use the same path.
2. [inferred] The binary registers both services. The `installd` domain may lack rules the donor assumed for the full OPPO policy, for example `proc_devinfo_file` read, `app_process` binder calls for `defrag_wrapper` (usagestats, package), `ufs` sysfs. Missing rules give denials in logcat (tag `auditd`) but not a crash [inferred]. Use the audit capture in AGENTS.md.
3. [inferred] `defragFiles`: the helper `defrag_wrapper` runs, the ioctl works on f2fs files. Real benefit: lower file fragmentation of cold app files. Quality of the benefit on UFS 3.1 is [unknown].
4. [inferred] `startScan`: it hashes files (md5) into the dedup table. All dedup ioctls then fail with `ENOTTY`. This costs I/O and battery for no gain. Turn it off.
5. [inferred] `startTurboPocket` and `replayTurboPocketBoot`: they log "skip turbo pocket" or "ufstp not found" and return. No harm, but the boot replay thread and its lookups are useless. Turn them off.
6. [inferred] If step 1 fails (service never registers), `runIdleMaint` blocks on `waitForService` and `replayTurboPocketBoot` leaks one thread (this is the case in `JAVA-WAITS.md`).

## 6. Plan

### (a) Works as is
No. Dedup and TP cannot work.

### (b) Small fixes: defrag works
Do these, in order, after the device checks pass.
1. Props. Add to `product/etc/build.prop` (or the step that already owns the port props): `persist.sys.oplus.disableCompressDedup=1` and `persist.sys.oplus.disableTurboPocket=1`. Keep `disableDefragFiles` at "0". A `persist.*` default in build.prop is used only if the value is unset [inferred].
2. Check `persist.sys.oplus.nandswap.devlife`. If unset, the code default is "true" and defrag stays on [seen].
3. SELinux. Collect `scontext=u:r:installd` denials with the audit-rate procedure from AGENTS.md. Add only the missing rules to `maintainer/sepolicy/pipa_port_rules.cil` (or the port's policy file). Compile with `secilc` on the tablet first.
4. rc: no change. [seen] It already has `disabled` and `interface aidl`.
5. Kernel: no change for defrag.
6. Optional later: add the read-only sysfs feature `may_compress` to `fs/f2fs/sysfs.c` if the device shows that compress needs it (check D3).

### (c) Dedup and Turbo Pocket cannot work
1. Turn them off with the two props above. This removes the idle-maint scan and the boot replay thread [seen].
2. Wait fix, only if D1 shows that the service does not register: patch the four sites from `JAVA-WAITS.md` (`StorageManagerService.connectDefrag`, `lambda$replayTurboPocketBootAsync$4` in `services.jar`; `OplusStorageManagerFeature.connectDefrag`, `StorageCompressDedupProvider.startAppCompressAndFileDedup` in `oplus-services.jar`) from `waitForService` to `checkService`. All four already handle a null binder with a log and return [seen]. With the props in (c)1, the two `StorageManagerService` sites are already skipped, so patch only if the defrag path stays on and D1 fails.

## 7. Device checks (read-only, root)

Use `ADB="adb -s <serial> shell"`. Quote `su -c` as in AGENTS.md. Never use `pgrep -f`.

- D1 Start and register:
  `getprop init.svc.oplus_defrag; service check DefragService; service check CompressScanService; getprop oplus.defragservice.status`
  Then trigger the lazy start (read-only in effect): `service check DefragService` again after 2 s. `ls /system_ext/bin/oplus_defrag /system_ext/etc/init/defrag.rc`.
- D2 Domain and labels: `ps -AZ | grep oplus_defrag; ls -Z /system_ext/bin/oplus_defrag /data/oplus/bsp_storage; getprop | grep -E "oplus.(defrag|compress)|oplus.nandswap|disable(Defrag|Compress|Turbo)"`.
- D3 f2fs: `grep ' /data ' /proc/mounts; ls /sys/fs/f2fs; ls /sys/fs/f2fs/features; cat /sys/fs/f2fs/features/may_compress; cat /sys/fs/f2fs/*/features`. A `compression` flag on `/data` means `COMPRESS_FILE` can work.
- D4 Kernel ioctl support: Run `logcat -d | grep -E "oplus_defrag|Defrag|F2FS_IOC"` after one idle-maint run and look for `ENOTTY` (errno 25) on `F2FS_IOC_DEDUP_*`.
- D5 UFS nodes: `ls /proc/devinfo/ufs; ls /sys/devices/platform/soc/*ufshc*/; ls /sys/devices/platform/soc/1d84000.ufshc | grep -i ufstp`. Expect "No such file".
- D6 Health service: `service check storage_healthinfo; logcat -d -s StorageHealthInfoService`.
- D7 Denials: `logcat -d | grep "avc:" | grep -E "scontext=u:r:installd|defrag"` and `dmesg | grep -E "avc.*installd"` (set the audit rate first, see AGENTS.md).
- D8 Idle run (changes state; ask first): `sm idle-maint run`, then `logcat -s StorageManagerService OplusStorageManagerFeature`. Look for "defrag start defragFiles", "defrag not found; trying again", "replayTurboPocketBoot: DefragService not found".
- D9 Java side: Use `logcat -d | grep "enableDefrag:"` for the line `enableDefrag: enableScan: enableTurboPocket:`.
- D10 Nandswap flag: `getprop persist.sys.oplus.nandswap.devlife`.

## 8. Open points

- [unknown] The exact name-to-number map for ioctls 100..107. Confirm with a `strace -e ioctl -p $(cat <pidfile>)` on a test device, or from OPPO kernel source.
- [unknown] The UFS string that `is_turbo_pocket_target_ufs` accepts.
- [unknown] Whether pipa `/data` has f2fs compression on disk.
- [unknown] Lazy AIDL start on the pipa servicemanager and init.
- Side task (do not start without asking): size of an OPPO f2fs dedup port. Record in `BUGS.md` only if the person wants dedup.

## Review (2026-11-03)

- Checked: `F2FS_IOC_DEFRAGMENT` is in the port kernel (`include/uapi/linux/f2fs.h`, handled in `fs/f2fs/file.c`);
  `oplus_defrag` has the label `installd_exec` (donor `system_ext_file_contexts`).
- So OPPO's file defrag can work on pipa as it is. Dedup (OPPO-only f2fs ioctls) and Turbo Pocket (OPPO UFS driver)
  cannot: no kernel parts, and no OPPO source to port.
- Next, on the tablet: D1 (does `DefragService` start and register) and the `installd` denials (D9). Then a step with
  `persist.sys.oplus.disableCompressDedup=1` and `persist.sys.oplus.disableTurboPocket=1` (the jobs that cannot work
  on pipa) and only the missing `installd` rules. No `checkService` patch unless D1 fails.
