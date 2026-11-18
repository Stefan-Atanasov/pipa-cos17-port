#!/bin/sh
# Phase 7s: helper 2.0 assistant + corner swipe (BUGS 98/49, user 2026-11-18: "swipe side to open Gemini").
#
# * pipa helper 2.0 (step 2d/4g copy helper/out/PipaHelper.apk) is a VoiceInteractionService: the session routes by
#   invocation_type, gesture-bar long press (OplusLauncher 1000) -> Circle to Search (contextual_search service, no
#   invisible activity any more), corner swipe (1) -> Gemini app (else Google voice, else Circle to Search). No hotword,
#   no microphone; the recognition service is a stub (voice_recognition_service stays as it was: unset).
# * service.sh cts_assistant: the assistant role is set again once (cts_assistant_v2) so the system binds the service;
#   a user's own assistant choice is kept.
# * SystemUI NavBarUtils.isAssistantAvailable: the CN (!isExpRegion) and Circle-to-Search gotos become nops
#   (maintainer/cts/patch_systemui_corner_assist.py), so the launcher gets the corner region.
# * Step 6n (Settings: corner-swipe switch hidden) is off (moved to port/drafts): the switch is back.
#NEEDS: "$HERE/cts/patch_systemui_corner_assist.py" "$HERE/jar-edits/venv/bin/python" "$HERE/../helper/out/PipaHelper.apk"
set -eu
. "$PORT/lib.sh"
STEP=7s
python3 -I - "$HERE/../helper/out/PipaHelper.apk" <<'PY'
import sys, zipfile
z = zipfile.ZipFile(sys.argv[1]); d = z.read('classes.dex')
assert b'AssistSession' in d and b'invocation_type' in d, 'PipaHelper.apk is not 2.0 (no AssistSession)'
assert 'res/xml/assist_service.xml' in z.namelist(), 'no assist_service.xml'
PY
need_grep 'cts_assistant_v2' "$T/system_ext/pipa_port/service.sh"
A=$T/system_ext/priv-app/SystemUI/SystemUI.apk
[ -f "$A" ] || die "no $A"
"$HERE/jar-edits/venv/bin/python" -I "$HERE/cts/patch_systemui_corner_assist.py" "$A" "$R/SystemUI.7s.apk" > "$R/7s.log" 2>&1 \
    || { grep -v DEBUG "$R/7s.log"; die "SystemUI corner assist patch failed"; }
grep -v DEBUG "$R/7s.log"; rm -f "$R/7s.log"
cat "$R/SystemUI.7s.apk" > "$A"; rm -f "$R/SystemUI.7s.apk"
rm -rf "$T/system_ext/priv-app/SystemUI/oat"
set_layer "$STEP"
