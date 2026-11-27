#!/bin/sh
# Step 9k (BUGS-TODO 195, user 2026-11-26: clean fix before v10, battery friendly): the GPU memory bus gets a floor
# during the touch and app-launch boosts.
# Stock ColorOS boosts GPU + bus on launcher animations through OPPO's IUrcc HAL (UAH events 71/85/86). pipa has no
# IUrcc (4h/4q). The boosts that do run on pipa come from the vendor power HAL (lineage libperfmgr,
# vendor/etc/powerhint.json): INTERACTION (touch, CPU + GPU floor 490 MHz) and LAUNCH (5 s, CPU/GPU max). No hint
# touches soc:qcom,gpubw (the GPU -> DDR vote, governor bw_vbif), so the bus stays low while the GPU composes the
# Rich-effects blur (BUGS 195: "GPU deadline missed").
# * vendor/etc/powerhint.json: new node GPUBWMinFreq (/sys/class/devfreq/soc:qcom,gpubw/min_freq, default 0 = no
#   floor) and a 10437 MB/s floor in INTERACTION and LAUNCH only, for the same time as the other floors of the hint.
#   Event driven (no loop), released with the hint; idle, screen off and video playback are unchanged.
# Same SELinux label as the bus nodes the HAL already writes (vendor_sysfs_devfreq): no policy change.
set -eu
. "$PORT/lib.sh"
STEP=9k
echo "== 9k GPU bus floor in the touch and launch boosts"

J=$T/vendor/etc/powerhint.json
[ -f "$J" ] || die "no $J"
need_grep '"LLCCBWMinFreq"' "$J"
python3 -I - "$J" "$R/powerhint.9k.json" <<'PY'
import json, sys
src, out = sys.argv[1], sys.argv[2]
d = json.load(open(src))
names = [n["Name"] for n in d["Nodes"]]
assert "GPUBWMinFreq" not in names, "already patched"
i = names.index("LLCCBWMinFreq")
d["Nodes"].insert(i + 1, {"Name": "GPUBWMinFreq", "Path": "/sys/class/devfreq/soc:qcom,gpubw/min_freq",
                          "Values": ["10437", "0"], "ResetOnInit": True})
acts, added = [], 0
for a in d["Actions"]:
    acts.append(a)
    if a.get("Node") == "LLCCBWMinFreq" and a["PowerHint"] in ("INTERACTION", "LAUNCH"):
        acts.append({"PowerHint": a["PowerHint"], "Node": "GPUBWMinFreq", "Duration": a["Duration"], "Value": "10437"})
        added += 1
assert added == 2, "INTERACTION/LAUNCH LLCCBWMinFreq actions: %d" % added
d["Actions"] = acts
open(out, "w").write(json.dumps(d, indent=4) + "\n")
print("powerhint.json: GPUBWMinFreq node + %d actions" % added)
PY
need_grep '"GPUBWMinFreq"' "$R/powerhint.9k.json"
cat "$R/powerhint.9k.json" > "$J"   # in place: owner, mode and SELinux label stay
rm -f "$R/powerhint.9k.json"
set_layer "$STEP"
