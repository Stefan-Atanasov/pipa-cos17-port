#!/bin/sh
# Pack the port's build kit for another maintainer (e.g. the original developer): every build/flash/test script, the
# ROM-side sources (port-rom, helper source, module/ for the baked step, UI First policy, boot animation, port edit
# list) and the docs. No images, no donor files, no signing key:
#   * helper/keys/ (pipa-helper.jks + keystore.pass) stays private: with it anyone can sign helper updates the ROM
#     accepts. A kit user gets a fresh key on the first helper build.
#   * venvs, build outputs, caches, the original release 7z and work/ (images) are left out.
#
#   sh maintainer/make_port_kit.sh            -> ~/Documents/pipa/port-work/release/pipa-cos17-port-kit-<date>.tar.gz
#   KIT_INPUTS=1 sh maintainer/make_port_kit.sh  also packs the private build inputs (about 2.2 GB): COS17/port-overlay
#     (frozen beta4 files), port-inputs/apps-5u (Google APKs of step 5u), port-inputs/dolby-5z (stock libhwdap of step 5z), tools/ (smali, apktool),
#     kernel/sukisu-*/ (SukiSU manager APKs of steps 2u, 2w, 5m, 7u), pipa-susfs-v1.0.zip, and the beta4 DEVICE SIDE:
#     work/parts/{vendor_b,odm_b}.img (pinned base) + the beta4 release tree without its super (firmware, bin, flash
#     scripts; build_release.sh and the kernel base boot.img) + kernel/backup-partitions-20261023 (links to the same
#     beta4 firmware files). With it no beta4 download is needed. Only for a trusted co-maintainer; never publish such a kit.
set -eu
HERE=$(cd "$(dirname "$0")" && pwd)
COS=$(cd "$HERE/.." && pwd)
OUTDIR=${OUTDIR:-${PIPA_ROOT:-$HOME/Documents/pipa}/port-work/release}
NAME=pipa-cos17-port-kit$([ "${KIT_INPUTS:-0}" = 1 ] && echo -inputs)-$(date +%Y%m%d)   # -inputs: private inputs inside
mkdir -p "$OUTDIR"
STAGE=$(mktemp -d "$OUTDIR/.kit-stage.XXXXXX"); trap 'rm -rf "$STAGE"' EXIT   # on disk: the inputs kit is >2 GB (/tmp is RAM)
K=$STAGE/$NAME
mkdir -p "$K"

cd "$COS"
DOCS="BUILD-GUIDE.md MAINTAINER-STATUS.md DEVICE-STATE.md BUGS-TODO.md RELEASE-NOTES-v9.md CHANGELOG-beta7.1-to-v9.md HISTORY.md CLAUDE.md AGENTS.md NEXT-SESSION-PROMPT.md"
for f in $DOCS; do [ -f "$f" ] && cp "$f" "$K/"; done
cp -r docs notes "$K/"
mkdir -p "$K/kernel"; cp kernel/WALT-KERNEL.md kernel/KERNEL-RESEARCH.md "$K/kernel/"
[ -f kernel/walt-own.bundle ] && cp kernel/walt-own.bundle "$K/kernel/"

tar -C "$COS" -cf - \
    --exclude='maintainer/jar-edits/venv' --exclude='__pycache__' --exclude='*.pyc' \
    --exclude='helper/keys' --exclude='helper/out' --exclude='maintainer/*/out' --exclude='maintainer/cts/overlay/keys' \
    --exclude='*.7z' --exclude='*.img' \
    --exclude='dolby-eq-module/*.png' \
    maintainer port-rom helper module port-module/src dolby-eq-module global-region-module susfs-module | tar -C "$K" -xf -

if [ "${KIT_INPUTS:-0}" = 1 ]; then
    P=$(cd "$COS/.." && pwd)
    # port-overlay needs its owners and SELinux labels (the steps copy them into the ROM): an inner tar with xattrs,
    # made as root (some files are root-only). Unpack: sudo tar --xattrs --xattrs-include='*' --numeric-owner -xpzf ...
    sudo tar -C "$COS" --xattrs --xattrs-include='security.*' --numeric-owner -cpzf "$K/port-overlay.tar.gz" port-overlay
    mkdir -p "$K/port-inputs"; cp -r "$P/port-inputs/apps-5u" "$P/port-inputs/dolby-5z" "$K/port-inputs/"
    mkdir -p "$K/tools"; cp -r "$P/tools/smali" "$P/tools/apktool" "$K/tools/"
    # SukiSU manager APKs preinstalled by steps 2u, 2w and 5m (#NEEDS lines in maintainer/port/steps)
    for d in sukisu-v4.2.1-r1 sukisu-v4.3.0 sukisu-v4.3.0-r1 sukisu-nova-3.0.0; do cp -r "$COS/kernel/$d" "$K/kernel/"; done
    cp "$COS/pipa-susfs-v1.0.zip" "$K/"
    # blobs that steps take from <root>/port-work/blobs: OPPO Games 10.44.6 (7c, from OPPO's App Market update) and
    # the PixelOS libgrallocutils (7h, = PixelOS vendor lib and lib64)
    mkdir -p "$K/port-work"; cp -r "$P/port-work/blobs" "$K/port-work/"
    # beta4 device side: the pinned vendor/odm and the release tree without its 6.4 GB super
    B4N="ColorOS17 Port for pipa-beta4-20261017"
    mkdir -p "$K/work/parts" "$K/$B4N"
    cp "$COS/work/parts/vendor_b.img" "$COS/work/parts/odm_b.img" "$K/work/parts/"
    (cd "$K/work/parts" && printf '%s  vendor_b.img\n%s  odm_b.img\n' b601a907363d01e78697cd5d4f60edf6 8e25ab23745ad3d9abb7a3312abe3e23 | md5sum -c --quiet) ||
        { echo "pinned vendor/odm md5 mismatch" >&2; exit 1; }
    (cd "$COS/$B4N" && tar -cf - --exclude=./super .) | tar -C "$K/$B4N" -xf -
    mkdir -p "$K/kernel/backup-partitions-20261023"
    for f in boot dtbo vendor_boot; do ln -s "../../$B4N/firmware/$f.img" "$K/kernel/backup-partitions-20261023/${f}_b.img"; done
    (cd "$K/port-inputs/apps-5u" && sha256sum -c --quiet SHA256SUMS) || { echo "apps-5u sha256 mismatch" >&2; exit 1; }
    (cd "$K/port-inputs/dolby-5z" && sha256sum -c --quiet SHA256SUMS) || { echo "dolby-5z sha256 mismatch" >&2; exit 1; }
fi

# fail closed: no key material may slip in
if find "$K" \( -name '*.jks' -o -name '*.keystore' -o -name 'keystore.pass' -o -name '*.pk8' \) | grep -q .; then
    echo "signing key material found in the kit, aborting" >&2; exit 1
fi
if grep -rIl 'KSPASS=[^$]' "$K/helper" >/dev/null 2>&1; then echo "helper password in the kit, aborting" >&2; exit 1; fi

cat > "$K/KIT-README.md" <<'EOF'
# ColorOS 17 port for Xiaomi Pad 6 (pipa): build kit

Everything needed to rebuild the port's ROM layers and the kernel, without images or donor files.

* Start with **`BUILD-GUIDE.md`** (ROM + kernel: build, test, flash, roll back), then `docs/REBASE.md` (rebase
  onto a new OPPO donor) and `MAINTAINER-STATUS.md` (current state, what each step does). Bugs: `BUGS-TODO.md`.
  Why each fix exists: `kernel/KERNEL-RESEARCH.md`, `HISTORY.md`, `module/README.md`.
* Kernel source: https://github.com/Stefan-Atanasov/kernel_xiaomi_pipa_cos17 (branch `oppo`, README + build script);
  `kernel/walt-own.bundle` holds the same commits for `maintainer/kernel/prepare_tree_walt.sh`.
* Paths: `port.sh` and the main scripts use the folder that holds `COS17/` (also `port-work/`, `donor/`, `tools/`)
  and give build outputs to the owner of `COS17/`. The old layer scripts default to `/home/stefan/Documents/pipa`:
  for them set **`PIPA_ROOT`** and **`PIPA_OWNER`** through sudo: `sudo env PIPA_ROOT=$PWD PIPA_OWNER=$USER:$USER sh ...`.
* Step-by-step runbook for a new PC (also for a local AI model): **`docs/HANDOFF-FROM-ZERO.md`** (Part A: rebuild;
  Part B: where every beta4 part comes from and how to make it from stock).
* Current release: **v9** = ROM pt128 (`port.sh` default build, last step 7x, donor OPD2515 `17.0.0.104(CN01)`
  = C.07) + kernel walt-hi9. Release notes: `RELEASE-NOTES-v9.md`. Next work: `NEXT-SESSION-PROMPT.md`.
* Folder layout (next to `COS17/`): `donor/OPD2515_11.C.07/img/` (images from the C.07 OTA zip, docs/REBASE.md),
  `port-inputs/apps-5u/` (step 5u), `port-inputs/dolby-5z/` (step 5z), `tools/` (smali, apktool), `port-work/` (build output, about 40 GB free needed).
* Input never in the kit: the donor C.07 OTA zip (`OPD2515_11.C.07_1070_202610201803.zip`, 9.2 GB; docs/BUILD.md 1.3).
* A kit made with `KIT_INPUTS=1` has all other inputs. Unpack the labelled overlay in `COS17/` as root:
  `sudo tar --xattrs --xattrs-include='*' --numeric-owner -xpzf port-overlay.tar.gz` (then check it:
  `cd port-overlay && sudo md5sum -c --quiet ../maintainer/c06-vs-beta4/port-overlay.md5`). Keep these in `COS17/`:
  `work/parts/`
  (pinned beta4 vendor/odm), the folder `ColorOS17 Port for pipa-beta4-20261017/` (beta4 firmware, bin, flash scripts;
  its super is not needed), `kernel/` (SukiSU APKs, `backup-partitions-20261023` = links to the beta4 boot, dtbo and
  vendor_boot) and `pipa-susfs-v1.0.zip`. Move `port-inputs/`, `tools/` and `port-work/` (it holds `blobs/`) next to `COS17/`. Then no beta4 download
  is needed. A kit without `KIT_INPUTS=1` needs the beta4 release and docs/BUILD.md section 1.3.
* Build the repository parts first: `sh maintainer/build_parts.sh` (androguard venv, helper, cryptoeng, overlays).
* The pipa helper app is signed with your own key: `helper/build.sh` creates `helper/keys/` on first run. Keep it;
  ROM builds and helper updates must share it. (Builds signed with another key cannot update each other's helper.)
* Tools: erofs-utils, lpmake/lpunpack, fastboot/adb, python3, JDK 21 + Android SDK build-tools 37 (helper), NDK 30
  (face crop add-on), AOSP clang r547379 (kernel). Androguard venv for jar work: `python3 -m venv
  maintainer/jar-edits/venv && maintainer/jar-edits/venv/bin/pip install androguard`.
EOF

tar -C "$STAGE" -czf "$OUTDIR/$NAME.tar.gz" "$NAME"
ls -la "$OUTDIR/$NAME.tar.gz"
md5sum "$OUTDIR/$NAME.tar.gz"
