# Rebuilding beta4 vendor + odm from stock sources (offline research, 2026-11-19)

Folder: <root>/port-work/fromstock/vendor. Nothing outside it was changed. No root, no adb.

## 1. Method
- Extracted beta4 vendor_b.img / odm_b.img (`fsck.erofs --extract --no-preserve`) and C.06 vendor/odm; md5 of every file in
  beta4, PixelOS, hyperos1-stock, iqraos3.1, iqraos_v1.0, C.06 donor, COS17/pipa_core, COS17/port-rom (`idx/*.tsv`, scripts/index.py).
- beta4 manifest check: cos17.vendor.md5 (1870 files) equals the beta4 vendor_b.img file list and md5s exactly (0 diffs). The
  tree has 291 more symlinks (bin/[ , bin/awk ... toybox links, `odm`), all identical to PixelOS.
- Per path vs PixelOS: same / modified / added / removed; each modified/added file looked up by md5 in all other trees
  (scripts/delta.py -> vendor-delta.tsv, odm-delta.tsv). UNIQUE = no byte-identical source anywhere (scripts/unique.py ->
  unique-v.tsv, unique-o.tsv, patches/). C.07 has NO vendor/odm image in donor/OPD2515_11.C.07/img (only system/my_*; the payload.bin
  was not unpacked), so C.07 contributed nothing.
- Assembly scripts: make_vendor_from_stock.sh, make_odm_from_stock.sh (wrappers of make_from_stock.sh), extract_trees.sh.

## 2. PixelOS vendor tree (task 1)
vendor/build.prop: ro.vendor.build.version.release=17, sdk=37 (sdk_full 37.0), build.id CP2A.260605.016, date Wed Aug 5 20:07:13
CEST 2026 (utc 1785953233), type userdebug, security_patch 2025-04-01. Fingerprint string is the Xiaomi stock one
(Xiaomi/pipa_global/pipa:13/RKQ1.211001.001/V816.0.7.0.UMZMIXM) but it is an Android 17 / SDK 37 vendor. beta4: date Sat Aug 22
08:57:08 UTC 2026 (1787389028), type user, fingerprint OPPO/OPD2515/OP6548L1:17/CP2A.260605.016/B.3b6223c-156ee02-15799c7. Same
build id as PixelOS: the same AOSP release branch, built 17 days later, with spoofed identity.

## 3. vendor delta beta4 vs PixelOS (2161 entries = 1870 files + 291 links; PixelOS 2052)
| status | n | source found | UNIQUE |
|---|---|---|---|
| same (1390 files + 291 links) | 1681 | PixelOS same path | - |
| removed | 36 | - (16 Lineage/Aperture overlay APKs, 14 codec2/bufferpool libs, libsqlite, media_codecs_c2_dolby_audio.xml) | - |
| added | 145 | 96 hyperos1-stock, 6 pipa_core/facehal, 3 iqraos3.1, 2 PixelOS (other path: media_profiles.xml, media_profiles_kona.xml = media_profiles_V1_0.xml), 1 C.06 vendor (oplus_avb.pubkey), 1 C.06 odm (manifest_performance_aidl.xml) | 36 |
| modified | 335 | 3 pipa_core/facehal (libOpenCL, libc++_shared, libllvm-qcom), 1 hyperos (libqti-perfd-client) | 331 |
So 113 of 481 non-identical files are reproducible byte for byte; 367 are UNIQUE (36 added + 331 modified).
pipa_core/facehal holds the face HAL support libs: libjni_stfaceunlock_api (29.7 MB), libfacehal_jni, libtensorflowlite(+gpu),
libadreno_compiler_cl, libOpenCL_adreno, libOpenCL, libllvm-qcom, libc++_shared - all byte-identical to beta4.

## 4. UNIQUE vendor files (unique-v.tsv: path, status, size, kind, counterpart, detail)
(a) 36 text files (patches/vendor/*.diff = `diff -u` on raw bytes, apply with `patch --binary -p1`; *.new = whole new file):
- build.prop (+127 -36): port block (AOSPA-aligned graphics/HWUI, ccodec, latch_unsignaled, idle timer, density, Dolby/MiSound, face props,
  OPPO fingerprint/ab_ota_partitions, build date/uuid/type=user).
- odm_dlkm/etc/build.prop, vendor_dlkm/etc/build.prop: same OPPO identity/date/uuid. etc/build_flags.json: aconfig release flags (newer build).
- etc/init/portenforce.rc (new): write selinux enforce 1 at boot_completed. etc/init/oplus_hal_odm.rc (new): OPPO perf/stability HAL
  services. etc/init/android.hardware.biometrics.face-service.facehal.rc (new): face HAL (disabled, pipa_core starts it).
- etc/init/hw/init.device.rc (+3): chown root system /sys/touchpanel/double_tap. init.target.rc (-7): /dev/stune lines dropped.
  android.hardware.light-service.lineage.rc (+44): extra light/backlight perms (rebuilt Lineage tree).
- etc/vintf/manifest: power-service.lineage IPower 6 -> 7 (needs the beta4 power HAL, see risks); new face-service.xml,
  manifest_oplus_stability.xml, vendor.qti.hardware.perf@2.2.xml.
- etc/permissions: freeform_window_management, picture_in_picture (new); device_id_attestation emptied.
- etc/audio_effects.xml (misoundfx/hwdap/gamedap/vqe + Dolby), audio_policy_configuration.xml (BT A2DP ports, 44.1k),
  usbv2_audio_policy_configuration.xml, etc/powerhint.json (+31), etc/camera/camxoverridesettings.txt (multiCamera, logs, OIS flags).
- usr/idc/Xiaomi_Keyboard.idc (orientationAware dropped), NVTCapacitivePen.idc + Xiaomi_Consumer.idc (new), usr/keylayout/Xiaomi_Smart_Pen_Keyboard.kl
  (keys 109/104 -> STYLUS_BUTTON_*), Khronos/OpenCL/vendors/adreno.icd (new).
- SELinux (9 files, see section 6): vendor_sepolicy.cil, plat_pub_versioned.cil, vendor_file_contexts, vendor_hwservice_contexts,
  vendor_service_contexts, vendor_property_contexts, vendor_seapp_contexts, vndservice_contexts, vendor_mac_permissions.xml.
(b) 306 binaries with a PixelOS counterpart at the same path (the newer source build) + 10 with another counterpart:
- 228 differ in size (real rebuild), 39 differ in <=2000 bytes, 21 in <=64 bytes (16-byte = only build-id/timestamp: libui,
  libgralloc.qti, libgralloctypes, libcap, libjson, libminijail, libril, libflatbuffers, ipacm, toolbox ...), 18 > 2000 bytes.
- By group (lib/lib64): 118 android.* AIDL/HIDL interface libs (android.hardware.*, android.hidl, android.system, android.frameworks),
  27 display/gralloc/composer (libgralloc, libui, mapper@4.0-impl-qti-display, composer deps), 21 platform support (libc++, libcutils,
  libbinder, libhidlbase, libbase, libprotobuf...), 19 GPU (Adreno 2025 driver: vulkan.adreno 5.1 MB vs 1.9 MB, libGLESv2_adreno,
  libEGL_adreno, eglSubDriver, q3dtools, a650_sqe.fw/zap.elf), 7 vendor.* interface libs, 6 audio/bt, 4 radio/diag, 3 kernel modules
  (gspca_main, rmnet_perf, rmnet_shs: tiny diffs), 2 camera, 1 wifi, 47 other.
- bin/hw HALs rebuilt: boot-service.qti, health-service.qti, light-service.lineage, power-service.lineage-libperfmgr (64 KB differ),
  thermal-service.qti, wifi-service; bin: awk, sh, toybox_vendor, toolbox, ipacm, vndservicemanager. audio.primary.kona (64-bit, 8 bytes)
  and android.hardware.audio@6.0-impl: 8-byte diffs.
- 32 etc/thermal-*.conf (Xiaomi-encrypted, same length, ~1500 bytes differ: edited, key unknown); 4 apps (CACertService, CneApp, IWlanService,
  TimeService) same size, ~3610 bytes differ = different signature block (re-signed with the build's platform key).
- Other-base counterparts: face-service.facehal (pipa_core copy is 517424 B vs 513920 B: older/other build), soundfx/libhwdap.so
  (hyperos stock, 3-4 bytes differ: patched), libcamera2ndk_vendor/libadreno_app_profiles (hyperos, other size), libkcl/libllvm-qgl/
  libkernelmanager/libcamera_metadata/libVkLayer_ADRENO_qprofiler (C.06 vendor, other size).
(c) 15 binaries with no counterpart anywhere (all in the donor/community category):
  vendor-oplus-hardware-performance-V1-service, vendor.oplus.hardware.stability.oplus_project-V1-service (+ libs performance-V5-ndk,
  stability-V3-ndk; origin: community C17 power-key package, from the rc comment), lib/ + lib64/ gralloc.qcom.so (new QTI gralloc),
  vulkan.turnip.so (19 MB Mesa), android.frameworks.cameraservice.{common,device,service 2.0/2.1}@2.0, android.hidl.manager@1.0 and
  android.hidl.memory.block@1.0 (32+64 bit; Android 17 dropped them from the platform, the build re-added them). Origin "unknown"
  beyond that; strings would say "Mesa" for turnip only.

## 5. odm (95 files; PixelOS odm 55, hyperos odm 21)
Counts (odm-delta.tsv): same 10, removed 38, added 78, modified 7. Byte-identical sources: 7 from C.06 odm (init.subsys.sh, commcenterd.rc,
gps_modem.cfg, modem_data_pb.cfg, libvasapi.so, vintf communication_center_aidl + subsys). UNIQUE 78: 14 text, 64 binary.
- The whole virtual-modem stack (commcenterd, subsys_daemon, 8 modem cfg, ~55 libs: android.hardware.radio@1.0-1.6, libdmtp*, libcommcenter*,
  libmindroid-*, lib-virtual-modem-*, libqti-radio-service, libprotobuf 21.7, vendor.oplus.hardware.* ) is the donor **C.05** build. Only C.06
  exists here and the files differ (e.g. libqti-radio-service 1.65 MB vs 3.8 MB in C.06; 5 radio@1.2-1.6 HIDL libs and subsys_radio-V8 and
  libradio-service/libsubsys-service/libqti-subsys-service/protobuf 21.7 do not exist in C.06 at all). Not reproducible: C.05 is not on disk.
  C.06 is a functional replacement = what step 3k (PORT_ODM_C06=1) already does with an odm_closure check.
- Text patches (patches/odm): etc/build.prop (OPPO/OPD2515/pipa identity, 2026-08-22 date/uuid, user), etc/init.oplus.mm-sys.sh (author script: zram
  8192 MB, swappiness 100, nandswap loop swapfile; diff vs C.06's original ~+216 -163), etc/init/subsys_daemon.rc (qti-modem-daemon triggers commented,
  2026-10-10), virtual_daemon.rc, permissions/android.hardware.telephony.ims.xml, vintf network/telephony_manifest_{dsds,ssss}.xml and
  manifest/network_manifest.xml (subsys_radio V9 slot1 / V8 slot2, radio 1.5 HIDL), selinux/odm_service_contexts (19 hal_radio_service names),
  3 precompiled_sepolicy sha256 files. The 7 bases for these diffs are C.06 odm files (scripts copy base, then patch).
- precompiled_sepolicy (1.63 MB) + etc/NOTICE.xml.gz: binary, PixelOS counterpart differs; the policy is a compile of beta4's plat/system_ext/
  product/vendor: unreproducible without that exact system. The stand-in script drops it so init compiles at boot (sha256 files then irrelevant).

## 6. SELinux (task 5)
- vendor_file_contexts and the rest of etc/selinux are PixelOS + patch: vs PixelOS only 201 (file_contexts), 18, 17, 89, 28, 31 changed lines
  (CR-normalised) vs 1358 vs hyperos. The changes: PixelOS test/debug binaries removed (iw, ndc, iperf, sns*, qseecom_*test, ...; userdebug
  -> user), Xiaomi labels added back (campostproc, libcvp*/libSNPE/libalCFR... same_process_hal_file). plat_pub_versioned.cil 57 lines.
- vendor_sepolicy.cil (1.43 MB, 21061 lines) is a user-build recompile, not a simple patch: of 12391 distinct lines before the port block, 11841
  are equal to PixelOS, 550 beta4-only (renumbered typeattr_NNN, different _202604 mappings), 2597 PixelOS-only (vendor-qti-testscripts, userdebug
  rules). The "pipa port" block starts at line 20969 (enforcing bring-up, face HAL socket, bootanim -> oplusoiface). CRLF warning: beta4's
  vendor_sepolicy.cil is CRLF in 21007 of 21061 lines and vendor_property_contexts has 460 CRLF lines; PixelOS has none. patches/vendor keep
  those bytes (diff is binary-exact; the cil patch is therefore 840 KB). Practical recipe: copy beta4's cil as one unit; it is UNIQUE.
- vendor_mac_permissions.xml: different platform signer certificate than PixelOS (beta4 build signed with another key; same for the 4 apps).
- Labels: erofs images carry labels as security.selinux xattrs of every inode (beta4: 1 xattr per inode). The local mkfs.erofs has no --file-contexts, so
  labels come from the tree: extract PixelOS vendor.img as root with `fsck.erofs --extract=DIR --xattrs --preserve` (not possible as user: setxattr
  security.* fails; I could not read labels offline). Copied/added files (113 byte-identical + 36 added + 331 stand-ins) carry the xattrs of their
  source image only if copied with `cp -a` from an xattr-preserving extraction; otherwise unlabeled -> must be relabelled by path against the NEW
  etc/selinux/vendor_file_contexts (patch result) with a setfattr loop (match `/vendor/...` regex top-to-bottom, last match wins) before mkfs.erofs.
  Check after build: root extract + `getfattr -d -m security.selinux` on bin/hw/*, lib64/hw/*, etc/init/*.rc vs vendor_file_contexts.
  Unlabeled or `vendor_file`-labelled HAL binaries = silent start failures (same failure class as the face HAL rc in U4).

## 7. Result of the assembly (make_*_from_stock.sh, run as user into x/, trees deleted afterwards)
- vendor, with B4 tree given (UNIQUE binaries copied, each printed): 2161 / 2161 entries identical to beta4. (Trivially true for text: patches are
  derived from beta4; the point is that the recipe covers everything: 113 files from stock, 36 text from patches, 331+0 from beta4.)
- vendor, STANDIN mode (no beta4): 1827 / 2161 identical (84.5%). 316 binaries replaced by PixelOS/hyperos/C.06/pipa_core stand-ins, 15 missing
  (list in run-vendor-standin.log), 2 orphan oplus entries dropped, IPower vintf patch skipped. Differences: vendor-standin-diffpaths.txt (334).
- odm, with B4: 95 / 95. odm STANDIN: 28 / 95 (C.06 libs/bins as stand-ins, 21 files missing: radio@1.2-1.6, protobuf 21.7, libradio-service...,
  precompiled_sepolicy dropped). odm-standin-diffpaths.txt.
- Modes/owners are not compared (extraction used --no-preserve); fs_config in odm is the HyperOS skeleton (identical to PixelOS).

## 8. Real unknowns (UNIQUE to beta4, cannot come from public/stock sources)
1. The A17 source build of ~306 PixelOS-counterpart binaries (118 AIDL/HIDL interface libs, platform support libs, display/gralloc, HAL
   services). Needs the dev's tree or the beta4 image.
2. Adreno 2025 stack (vulkan.adreno 40-byte cMetaOffset-patched, GLESv2/EGL, libllvm-qgl, libkcl, a650 fw), vulkan.turnip, gralloc.qcom.
3. OPPO perf/stability HAL binaries (community power-key package), face-service.facehal exact build, 3 camera/hidl compat libs.
4. 32 encrypted thermal-*.conf edits, vendor_sepolicy.cil recompile, mac_permissions signer, 4 re-signed apps, odm precompiled_sepolicy.
5. odm virtual-modem stack from C.05 (only C.06 present). Check C.07 payload.bin (9.2 GB) for vendor/odm: not unpacked here.

## 9. Boot-test risks of a stand-in (PixelOS libs) vendor
- Same AOSP branch (CP2A.260605.016), so core ABI should match, but 250 libs differ: any HAL service that links a changed AIDL/HIDL
  interface lib from another build is fine only if both sides come from the same set - never mix single libs from beta4 and PixelOS.
- IPower v7 (beta4 manifest) vs v6 PixelOS binary: keep v6 (script does). Health HAL: beta4 reads current_now/voltage_now (behaviour change).
- Display: composer-service, mapper@4.0-impl-qti-display, gralloc (beta4 adds gralloc.qcom.so) and the Adreno 2025 userspace belong together; the vulkan
  patch is a rendering fix (green lines). Using PixelOS Adreno = known-good for pipa but the beta4 SurfaceFlinger/HDR patches may assume newer drivers.
- Wi-Fi (wifi-service rebuilt, new log strings), thermal (thermal-service.qti + 32 conf edits: stock/PixelOS confs may throttle differently),
  boot/health/light HALs: low risk. audio.primary.kona 8-byte patch (rotation) is port-relevant; PixelOS copy lacks it.
- SELinux: vendor policy from PixelOS (userdebug rules) + port block needs a consistent set (do NOT mix beta4 cil with PixelOS file_contexts).
  First boot permissive via portenforce.rc, as today. Check labels (section 6) before blaming HALs.
- Missing OPPO HAL binaries: rc/vintf dropped by the script; ColorOS may log missing IPerformance/stability services (they are "absent_*" labelled already).
- odm without precompiled_sepolicy compiles at boot (+seconds); with C.06 stack the AIDL radio manifest from step 3d/3k is needed (network_manifest patch is C.05 HIDL style).
