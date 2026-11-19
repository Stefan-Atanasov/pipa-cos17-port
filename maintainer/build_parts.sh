#!/bin/sh
# Build every part that the port.sh steps take from this repository (docs/HANDOFF-FROM-ZERO.md A5), as the normal
# user, in this order:
#   1 the jar-edits venv (androguard; 10 steps run their patch scripts with it)
#   2 the helper app (helper/out/PipaHelper.apk; makes helper/keys/ the first time: keep it private)
#   3 cryptoeng.jar (step 3a)
#   4 the overlay APKs: cts/overlay first (it makes maintainer/cts/overlay/keys/overlay.jks the first time; the
#     framework, launcher and location overlays are signed with that key), then the others (misound uses the helper key)
#   sh maintainer/build_parts.sh
set -eu
C=$(cd "$(dirname "$0")/.." && pwd); cd "$C"
V=maintainer/jar-edits/venv
if [ ! -x "$V/bin/python" ]; then
	python3 -m venv "$V"
	"$V/bin/pip" install -q androguard==4.1.4
fi
"$V/bin/python" -c 'import androguard' || { echo "androguard missing in $V" >&2; exit 1; }
sh helper/build.sh
sh maintainer/cryptoeng/build.sh
sh maintainer/cts/overlay/build.sh
for o in framework launcher location misound; do sh "maintainer/overlays/$o/build.sh"; done
ls -l helper/out/PipaHelper.apk maintainer/cryptoeng/cryptoeng.jar maintainer/cts/overlay/out/PipaContextualSearchOverlay.apk \
	maintainer/overlays/framework/out/PipaFrameworkOverlay.apk maintainer/overlays/launcher/out/PipaLauncherGridOverlay.apk \
	maintainer/overlays/location/out/PipaLocationOverlay.apk maintainer/overlays/misound/out/PipaMiSoundOverlay.apk
echo "parts ok"
