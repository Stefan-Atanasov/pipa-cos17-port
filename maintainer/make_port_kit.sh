#!/bin/sh
# Pack the port's build kit for another maintainer (e.g. the original developer): every build/flash/test script, the
# ROM-side sources (port-rom, helper source, module/ for the baked step, UI First policy, boot animation, port edit
# list) and the docs. No images, no donor files, no signing key:
#   * helper/keys/ (pipa-helper.jks + keystore.pass) stays private: with it anyone can sign helper updates the ROM
#     accepts. A kit user gets a fresh key on the first helper build.
#   * venvs, build outputs, caches, the original release 7z and work/ (images) are left out.
#
#   sh maintainer/make_port_kit.sh            -> ~/Documents/pipa/port-work/release/pipa-cos17-port-kit-<date>.tar.gz
set -eu
HERE=$(cd "$(dirname "$0")" && pwd)
COS=$(cd "$HERE/.." && pwd)
OUTDIR=${OUTDIR:-${PIPA_ROOT:-$HOME/Documents/pipa}/port-work/release}
NAME=pipa-cos17-port-kit-$(date +%Y%m%d)
STAGE=$(mktemp -d); trap 'rm -rf "$STAGE"' EXIT
K=$STAGE/$NAME
mkdir -p "$K" "$OUTDIR"

cd "$COS"
DOCS="BUILD-GUIDE.md MAINTAINER-STATUS.md DEVICE-STATE.md BUGS-TODO.md RELEASE-NOTES-beta5.md HISTORY.md CLAUDE.md AGENTS.md"
for f in $DOCS; do [ -f "$f" ] && cp "$f" "$K/"; done
cp -r docs notes "$K/"
mkdir -p "$K/kernel"; cp kernel/WALT-KERNEL.md kernel/KERNEL-RESEARCH.md "$K/kernel/"
[ -f kernel/walt-own.bundle ] && cp kernel/walt-own.bundle "$K/kernel/"

tar -C "$COS" -cf - \
    --exclude='maintainer/jar-edits/venv' --exclude='__pycache__' --exclude='*.pyc' \
    --exclude='helper/keys' --exclude='helper/out' \
    --exclude='*.7z' --exclude='*.img' \
    maintainer port-rom helper module | tar -C "$K" -xf -

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
* Inputs not in the kit: the original beta4 release (`ColorOS17 Port for pipa-beta4-20261017.7z`, its super and
  firmware), the donor OPD2515 `17.0.0.103(CN01)` (C.06) images, and the `COS17/port-overlay/` folder (frozen beta4 files, see docs/BUILD.md section 1.3).
* The pipa helper app is signed with your own key: `helper/build.sh` creates `helper/keys/` on first run. Keep it;
  ROM builds and helper updates must share it. (Builds signed with another key cannot update each other's helper.)
* Tools: erofs-utils, lpmake/lpunpack, fastboot/adb, python3, JDK 21 + Android SDK build-tools 37 (helper), NDK 30
  (face crop add-on), AOSP clang r547379 (kernel). Androguard venv for jar work: `python3 -m venv
  maintainer/jar-edits/venv && maintainer/jar-edits/venv/bin/pip install androguard`.
EOF

tar -C "$STAGE" -czf "$OUTDIR/$NAME.tar.gz" "$NAME"
ls -la "$OUTDIR/$NAME.tar.gz"
md5sum "$OUTDIR/$NAME.tar.gz"
