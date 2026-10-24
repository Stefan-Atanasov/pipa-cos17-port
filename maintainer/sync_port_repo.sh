#!/bin/sh
# Sync the public port repo (scripts, our sources, the public docs in docs/; no proprietary blobs, no signing key) and push it.
#   sh maintainer/sync_port_repo.sh ["commit message"]        repo: $PIPA_ROOT/port-work/port-repo
# Left out on purpose (listed in BLOBS.md of the repo): OPPO/Qualcomm/Xiaomi/SenseTime binaries (*.so, *.jar, face
# HAL, vendor calibration and brightness files, boot animations), helper/keys (signing key + password), venvs,
# build outputs. The full private kit for a co-maintainer is maintainer/make_port_kit.sh.
set -eu
HERE=$(cd "$(dirname "$0")" && pwd)
COS=$(cd "$HERE/.." && pwd)
R=${REPO:-${PIPA_ROOT:-$HOME/Documents/pipa}/port-work/port-repo}
MSG=${1:-"sync from COS17 $(date +%F)"}
mkdir -p "$R"
cd "$COS"
rsync -a --delete --delete-excluded \
    --filter='P .git/' --exclude='.git/' \
    --exclude='maintainer/jar-edits/venv/' --exclude='__pycache__/' --exclude='*.pyc' \
    --exclude='helper/keys/' --exclude='helper/out/' \
    --exclude='*.so' --exclude='*.jar' --exclude='*.apk' --exclude='*.7z' --exclude='*.img' --exclude='*.zip' \
    --exclude='port-rom/pipa_port/facehal/' --exclude='port-rom/pipa_port/xiaomi_touch_ioctl' \
    --exclude='maintainer/kgest/kgest' --exclude='maintainer/jars/' \
    --exclude='module/system/vendor/etc/qdcm_calib_data_*' --exclude='module/system/system_ext/etc/display_brightness_config_*' \
    --exclude='module/framework/' --exclude='maintainer/port-repo/' --exclude='maintainer/bugs/' \
    --include='/maintainer/***' --include='/port-rom/***' --include='/helper/***' --include='/module/***' \
    --exclude='*' \
    ./ "$R/"
# fail closed
if find "$R" -path "$R/.git" -prune -o \( -name '*.jks' -o -name 'keystore.pass' -o -name '*.pk8' -o -name '*.so' -o -name '*.jar' \) -print | grep -q .; then
    echo "key or blob in the repo tree, aborting" >&2; exit 1
fi
grep -rIl 'KSPASS=[^$]' "$R/helper" >/dev/null 2>&1 && { echo "helper password in the repo, aborting" >&2; exit 1; }
# public docs (STE100, no session history) at the repo root; the internal root notes (CLAUDE.md, AGENTS.md,
# MAINTAINER-STATUS.md, HISTORY.md, BUGS-TODO.md, kernel/*.md ...) stay local
cp "$COS"/docs/*.md "$HERE/port-repo/BLOBS.md" "$R/"
cp "$COS/RELEASE-NOTES-beta5.md" "$R/RELEASE-NOTES.md"
cd "$R"
[ -d .git ] || { git init -q -b main
    git config user.name Stefan-Atanasov; git config user.email 243114191+Stefan-Atanasov@users.noreply.github.com; }
git add -A
git diff --cached --quiet && { echo "nothing to commit"; exit 0; }
git commit -q -m "$MSG"
git log --oneline -1
if git remote get-url origin >/dev/null 2>&1; then git push -q origin main && echo pushed; else echo "no remote yet"; fi
