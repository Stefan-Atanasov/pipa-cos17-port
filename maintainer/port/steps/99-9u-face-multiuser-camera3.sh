#!/bin/sh
# Step 9u: face unlock with more than one user, quiet face log, no camera provider crash in a dark room.
# * BUGS 215 (user report 2026-11-27, "tablet warm since v9"; reproduced on pt178 with `pm create-user` +
#   `am switch-user`): the face HAL (domain pipa_port) had no dir create on face_vendor_data_file, and service.sh made
#   the face folder for user 0 only. Any second user (another user, guest, private space): createSession fails with
#   "create_dir_all(/data/vendor_de/<u>/facedata/facehal) failed: Permission denied", system_server retries
#   FaceStartUserClient without end (~21000 errors and 7 MB of facehal.log in 25 s; it goes on after the user is
#   removed, until a reboot). Fix: rules_9u (dir create), service.sh face_start makes the folder for each user and cuts
#   a face log over 8 MB once (pt180: user 0 only; listing /data/vendor_de was denied, the HAL makes the other folders).
# * persist.sys.facehal.verbose: step 01 set false in system/build.prop, but vendor/build.prop (loaded later) has true:
#   the HAL logged every frame decision (~280 KB/h with face unlock, GBs in the retry loop). Set false in vendor too.
# * BUGS 214: in a dark room the face worker also opens camera "3" (logical front camera); the QTI CHI override maps
#   it to UsecaseVTCam -> camera.provider SIGSEGV in CamX::Session::Initialize. libpipa_camguard refuses camera "3"
#   (ACameraManager_openCamera, src/camguard.c). Live test 2026-11-27: 12 dark wakes, 8 refusals, 0 VTCam, 0 crashes
#   (before: 1 crash in 3-4 wakes).
#NEEDS: "$ROM/pipa_port/facehal/lib64/libpipa_camguard.so" "$ROM/pipa_port/facehal/VERSION" "$ROM/pipa_port/service.sh" "$HERE/sepolicy/rules_9u_system_ext.cil"
set -eu
. "$PORT/lib.sh"
STEP=9u
echo "== 9u face: folder for each user, verbose log off, camera 3 guard"

SE=$T/system_ext
F=$SE/pipa_port/facehal
[ -f "$F/lib64/libpipa_camguard.so" ] || die "no $F/lib64/libpipa_camguard.so (step 5n missing?)"
need_grep 'camera 3 refused' "$ROM/pipa_port/facehal/lib64/libpipa_camguard.so"
cat "$ROM/pipa_port/facehal/lib64/libpipa_camguard.so" > "$F/lib64/libpipa_camguard.so"   # in place: label kept
cat "$ROM/pipa_port/facehal/VERSION" > "$F/VERSION"
need_grep "$(md5sum "$F/lib64/libpipa_camguard.so" | cut -d' ' -f1)  ./lib64/libpipa_camguard.so" "$F/VERSION"
cat "$ROM/pipa_port/service.sh" > "$SE/pipa_port/service.sh"
need_grep '9u (BUGS 215)' "$SE/pipa_port/service.sh"
echo "facehal: libpipa_camguard.so (camera 3 guard), VERSION, service.sh"

VP=$T/vendor/build.prop
need_grep '^persist.sys.facehal.verbose=true$' "$VP"
sed 's/^persist.sys.facehal.verbose=true$/persist.sys.facehal.verbose=false/' "$VP" > "$R/vendor.build.prop.9u"
cat "$R/vendor.build.prop.9u" > "$VP"; rm -f "$R/vendor.build.prop.9u"
need_grep '^persist.sys.facehal.verbose=false$' "$VP"
forbid_grep 'persist.sys.facehal.verbose=true' "$VP"
echo "edited  vendor/build.prop (persist.sys.facehal.verbose=false)"

for f in system_ext_sepolicy.cil system_ext_sepolicy_debug.cil; do
    [ -f "$SE/etc/selinux/$f" ] || continue
    forbid_grep "pipa port 9u" "$SE/etc/selinux/$f"
    { cat "$SE/etc/selinux/$f"; cat "$HERE/sepolicy/rules_9u_system_ext.cil"; } > "$R/$f.new"
    cat "$R/$f.new" > "$SE/etc/selinux/$f"; rm -f "$R/$f.new"
    need_grep "pipa port 9u" "$SE/etc/selinux/$f"
done
echo "edited  system_ext sepolicy (+ face_vendor_data_file dir create)"
