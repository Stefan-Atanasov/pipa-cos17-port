#!/bin/sh
# Phase 3k (OPTIONAL, runs only with PORT_ODM_C06=1): the whole OPPO interconnect stack in /odm from C.06 ("Tier 1").
#
# The odm is pinned from beta4 (OPPO donor C.05). Step 3d added the C.06 AIDL virtual modem on top of it
# ("Tier 2"): ten C.06 libs whose sonames collide with the C.05 ones went into the private dir /odm/lib64/aidl, and
# virtual_daemon.rc sets LD_LIBRARY_PATH=/odm/lib64/aidl for the two virtual RIL daemons. commcenterd,
# subsys_daemon in the pipa_subsys slots and the libs that they load stay C.05. This step moves them to C.06:
# * Replaces 26 C.05 files by the C.06 file of the same path (bin, lib64, lib; table below). The write goes into
#   the same inode (label, owner, mode stay). Old and new md5 are pinned: a different base or donor stops the step.
# * Adds 4 files that only C.06 has and that the C.06 libqti-radio-service needs: libipcapis, libipc-framework,
#   subsys_radio-V1-ndk (odm/lib64) and the 32-bit libprotobuf-cpp-lite-21.12 (from the C.06 vendor image). They
#   get label, mode and owner of a sibling file.
# * Removes the private dir /odm/lib64/aidl and the two setenv lines in virtual_daemon.rc, but only after
#   maintainer/port/odm_closure.py found that every ELF in /odm resolves without them. A failed check stops the
#   build (the tree stays).
# * Leaves alone: libs that C.06 does not have (libradio-service, libsubsys-service, libqti-subsys-service,
#   protobuf 21.7, the HIDL virtual modem libs; nothing loads them any more), subsys_daemon.rc (the port copy keeps
#   the qti-modem-daemon triggers off; pipa_port.rc starts pipa_subsys0/1), and the system_ext sepolicy rule
#   `allow init hal_radio_default (process (noatsecure))` of 3d (harmless without LD_LIBRARY_PATH).
# Details, risks, test plan and rollback: maintainer/port/NOTES-3k-odm-c06.md.
#
# Old layer script: none (new in port.sh)
#NEEDS: "$P/donor-c06-vendor/odm.img" "$P/donor-c06-vendor/vendor.img" "$PORT/odm_closure.py"
set -eu
. "$PORT/lib.sh"
STEP=3k

if [ "${PORT_ODM_C06:-0}" != 1 ]; then
    echo "skipped (PORT_ODM_C06 is not 1): the odm keeps the C.05 interconnect stack + the 3d private dir"
    exit 0
fi

C06_VENDOR=$P/donor-c06-vendor
O=$T/odm
[ -f "$C06_VENDOR/odm.img" ] && [ -f "$C06_VENDOR/vendor.img" ] || die "C.06 vendor/odm images missing: $C06_VENDOR"
[ -d "$O/lib64/aidl" ] || die "odm/lib64/aidl is missing: step 3d did not run"
[ "$(grep -c 'setenv LD_LIBRARY_PATH /odm/lib64/aidl' "$O/etc/init/virtual_daemon.rc")" = 2 ] \
    || die "virtual_daemon.rc: expected the 2 LD_LIBRARY_PATH lines of step 3d"

S3K=$W/scratch/3k
rm -rf "$S3K"; mkdir -p "$S3K"

# R = replace (path, md5 of the C.05 file, md5 of the C.06 file); N = new file; V = must already be the C.06 file.
# Fields: kind, source image (odm|vendor), path in the source and in the odm, old md5, new md5.
cat > "$S3K/table.tsv" <<'EOF'
R	odm	bin/commcenterd	025daba21160742f0474cfb929ff74aa	b8ff10e4445ac9e7577ec100af98e4b2
R	odm	bin/hw/subsys_daemon	ccd4b9ffc02a811996b574444e8b9c17	9ef3104638be7184ea0629dbc413406a
R	odm	lib64/libcommcenterfw.so	146c6f67e907f5850c9d8bfd7a3f0837	04913b71bae91e04da2fe7b0372883c3
R	odm	lib64/libcommcenterutils.so	61c066ab025261a872ec8a98484da35b	977bd7c47d2a4a025f2b716ba4169471
R	odm	lib64/libdmtp.so	392988227818b0678f79e9459d045097	c697f387ba55a4303147a3dc1b1c3440
R	odm	lib64/libdmtp-protos-lite.so	f7661e4c309b5f1dd77b3edff830fed6	1c70c222ee7e041ed3b6ecc9a3a4d944
R	odm	lib64/libdmtpclient.so	05c4d316d9f914e17be59c971db79bfe	c549063dbd208f85162eda57677ec055
R	odm	lib64/libmindroid-app.so	7c295fdff81d92660b0e3d1866737dc4	b2df55c3135e333c5e615052fcdbb303
R	odm	lib64/libmindroid-framework.so	80f32ff8f68ea3866c1336a20918b441	8f3c4c13b0ce5fe74997119fe5611d77
R	odm	lib64/libqti-radio-service.so	04d8e5b073aa591b35e4e95ea71752f0	48c88bff02b98424ea3cb4a18ed0593e
R	odm	lib64/libradioapis.so	6b40be48e74a227895be47d23295dd89	5ea91118fe06e93385c2af4952ca2981
R	odm	lib64/libsubsys-utils.so	e264448920c7eabbe433afb3b9706fe4	ab7bdea8fb1a4e262bd0c93e85571c0a
R	odm	lib64/lib-virtual-modem-api.so	bda24e2a2a5f77c38c0d5da0c7f8e270	8963a15cc342bf408515bfcbda0d6f78
R	odm	lib64/lib-virtual-modem-protos.so	412b8a649cc2b4ce258688074253ab66	340a26306b5d4552deb6f148c739cee0
R	odm	lib64/vendor.oplus.hardware.communicationcenter-V1-ndk.so	9d70aaf48d045d597c5c334c239584f0	c38ef56b9551bfaa3c52e3e67177102b
R	odm	lib64/vendor.oplus.hardware.communicationcenter-V2-ndk.so	82a76d9743956ca62fe69acbba859f6a	edc653e0fa177c896eb10a3c0bde54cf
R	odm	lib64/vendor.oplus.hardware.subsys-V5-ndk.so	e4d51cfd2a0ca0fb3d1247a8a388211c	7742cb2fc174e3061997f228bbe44caf
R	odm	lib/libcommcenterfw.so	2baec6dad3a57d8855fe6b44b000d3eb	97627e3a20e6624d310896ee37f1bfd4
R	odm	lib/libcommcenterutils.so	3274235249ea172b1c8162613a942b37	691ccfd3cfbe0a31cd33c0d75afa6c63
R	odm	lib/libdmtp.so	a6abeecfa9d201e6596d47fc924a87b0	3bc227c2e6979372a91ea55e875d47d8
R	odm	lib/libdmtp-protos-lite.so	99be07bee856aece90f6bbecccd6dcf3	c97482971454c82ee6b4af666e971f91
R	odm	lib/libdmtpclient.so	8ef6f0d6d351b93568e89e3a17a7f931	06260884a5294662f635e46e85fec9cd
R	odm	lib/lib-virtual-modem-protos.so	2364e28f4f52cf745328a0aa7cdebe95	2689ab5a5b9f1f73a69ba12d34d3c04e
R	odm	lib/vendor.oplus.hardware.communicationcenter-V1-ndk.so	6dcbdcae306c3c16a4703f02a4ec4f8e	585f12eb804fb72a8e43b0eada7f7132
R	odm	lib/vendor.oplus.hardware.communicationcenter-V2-ndk.so	a491e0bcbffdc8595efe4cf8b67dee29	9eae0eb69799db4bb5495770bfd29f55
R	odm	lib/vendor.oplus.hardware.subsys-V5-ndk.so	3e96fccb92204fe39684aa7b4efcc385	d9d1862464fb83200250c43d05ddee85
N	odm	lib64/libipcapis.so	-	fc20effbaf697f32612bb7a4ba72fbe1
N	odm	lib64/libipc-framework.so	-	c5c3ea630ece561390a3b4102bf33c04
N	odm	lib64/vendor.oplus.hardware.subsys_radio-V1-ndk.so	-	d1e867440deb3981e324351a28290f1b
N	vendor	lib/libprotobuf-cpp-lite-21.12.so	-	64d742281559a5be0565bceba3dffad8
V	vendor	lib64/libprotobuf-cpp-lite-21.12.so	544b9bd6426536908c8d7c240e25766e	544b9bd6426536908c8d7c240e25766e
EOF

cp "$S3K/table.tsv" "$R/3k-table.tsv"
echo "== C.06 interconnect files -> odm (same inode; table: $R/3k-table.tsv)"
python3 -I - "$O" "$C06_VENDOR" "$S3K/table.tsv" <<'PY'
import hashlib, os, subprocess, sys

O, CV, TABLE = sys.argv[1:4]
IMG = {'odm': CV + '/odm.img', 'vendor': CV + '/vendor.img'}
SIBLING = {'lib64': 'lib64/libsubsys-utils.so', 'lib': 'lib/libcommcenterfw.so'}   # label, owner, mode of a new file


def md5(b):
    return hashlib.md5(b).hexdigest()


def fail(msg):
    sys.exit('FAIL: ' + msg)


def c06(src, path):
    # dump.erofs exits 0 for a missing path: accept only an ELF file of the pinned md5
    r = subprocess.run(['dump.erofs', '--cat', '--path=/' + path, IMG[src]], capture_output=True)
    if r.returncode != 0 or r.stdout[:4] != b'\x7fELF':
        fail(f'cannot read {path} from the C.06 {src} image')
    return r.stdout


rows = [l.rstrip('\n').split('\t') for l in open(TABLE) if l.strip()]
print(f'{"path":62s} {"old md5":32s} -> {"new md5":32s}  size')
for kind, src, path, old, new in rows:
    dst = os.path.join(O, path)
    data = c06(src, path)
    if md5(data) != new:
        fail(f'C.06 {src}:{path} has md5 {md5(data)}, expected {new}: a different C.06 donor? Regenerate the table.')
    if kind == 'R':
        if not os.path.isfile(dst):
            fail(f'odm/{path} is missing')
        have = md5(open(dst, 'rb').read())
        if have == new:
            print(f'{path:62s} already the C.06 file')
            continue
        if have != old:
            fail(f'odm/{path}: md5 {have} is neither the pinned C.05 file ({old}) nor the C.06 file')
        with open(dst, 'r+b') as f:                        # same inode: label, owner and mode stay
            f.write(data)
            f.truncate()
    elif kind == 'N':
        if os.path.lexists(dst):
            fail(f'odm/{path} exists already')
        sib = os.path.join(O, SIBLING[path.split('/')[0]])
        st = os.stat(sib)
        fd = os.open(dst, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
        with os.fdopen(fd, 'wb') as f:
            f.write(data)
        os.chown(dst, st.st_uid, st.st_gid)
        os.chmod(dst, st.st_mode & 0o7777)
        try:
            os.setxattr(dst, 'security.selinux', os.getxattr(sib, 'security.selinux'))
        except OSError as e:
            fail(f'label of {sib} cannot be copied ({e}): was the tree extracted with --xattrs?')
    elif kind == 'V':
        have = md5(open(dst, 'rb').read()) if os.path.isfile(dst) else None
        if have != new:
            fail(f'odm/{path} is not the C.06 file (md5 {have})')
        print(f'{path:62s} already the C.06 file (checked)')
        continue
    else:
        fail('bad table row ' + repr(kind))
    got = md5(open(dst, 'rb').read())
    if got != new:
        fail(f'odm/{path}: md5 {got} after the write, expected {new}')
    print(f'{path:62s} {old:32s} -> {new:32s}  {len(data)}')
PY

echo "== the private dir /odm/lib64/aidl must now hold only copies of files that are in /odm/lib64"
n=0
for f in "$O"/lib64/aidl/*; do
    b=${f##*/}
    [ -f "$O/lib64/$b" ] || die "odm/lib64/aidl/$b has no file of the same name in odm/lib64"
    cmp -s "$f" "$O/lib64/$b" || die "odm/lib64/aidl/$b differs from odm/lib64/$b"
    n=$((n + 1))
done
echo "$n files in odm/lib64/aidl are identical to odm/lib64"
[ "$n" = 10 ] || die "expected 10 files in odm/lib64/aidl (step 3d), found $n"

echo "== closure check WITHOUT the private dir (odm_closure.py --assume-no-private)"
APEX=$W/scratch/apex
python3 -I "$PORT/odm_closure.py" --tree "$T" --assume-no-private --apex-cache "$APEX" > "$R/odm-closure-3k-before-removal.txt" 2>&1 || {
    tail -60 "$R/odm-closure-3k-before-removal.txt"
    die "closure check failed without odm/lib64/aidl: full report in $R/odm-closure-3k-before-removal.txt. Nothing was removed."
}
tail -3 "$R/odm-closure-3k-before-removal.txt"

echo "== remove odm/lib64/aidl and the LD_LIBRARY_PATH lines of virtual_daemon.rc"
rm -rf "$O/lib64/aidl"
NL='
'
replace_all odm/etc/init/virtual_daemon.rc "    setenv LD_LIBRARY_PATH /odm/lib64/aidl$NL" '' 2   # replace_all does not decode \n
forbid_grep 'lib64/aidl' "$O/etc/init/virtual_daemon.rc"
forbid_grep 'LD_LIBRARY_PATH' "$O/etc/init/virtual_daemon.rc"
if grep -rl 'odm/lib64/aidl' "$O/etc" >/dev/null 2>&1; then die "a file in odm/etc still names odm/lib64/aidl"; fi
[ ! -e "$O/lib64/aidl" ] || die "odm/lib64/aidl is still there"

echo "== closure check of the final odm (rc LD_LIBRARY_PATH honoured: there is none)"
python3 -I "$PORT/odm_closure.py" --tree "$T" --apex-cache "$APEX" > "$R/odm-closure-3k.txt" 2>&1 || {
    tail -60 "$R/odm-closure-3k.txt"
    die "closure check failed on the final odm: $R/odm-closure-3k.txt"
}
tail -3 "$R/odm-closure-3k.txt"
echo "closure report: $R/odm-closure-3k.txt"
rm -rf "$S3K/apex" "$APEX"
