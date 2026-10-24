# Documentation audit, 2026-10-22 (read-only; no doc was edited)

Ground truth used: the task brief (stefan is maintainer; module v0.9 md5 `4d479de1…`; jar-per-base layout; no port-author jar edits to re-apply; beta5 / baked / 1c / round-trip not flashed; U17 restored and U1 absent in beta5). Facts confirmed against `module/` (module.prop = v0.9; `module/framework/{3316594f…,2175feb9…}.jar` exist, md5 of patched jars `06c5c303…` / `8c211ca5…`; `module/system/system/` is gone), `module/post-fs-data.sh`, `module/tools/patch_framework.sh`, the v0.7/v0.8/v0.9 zips, and `maintainer/*.sh`. md5 of `pipa-cos17-power-tune-v0.9.zip` = `4d479de19d0d…`, `pipa_core-v1.10.zip` = `bbae9309…`, `pipa-perf-test-v0.1.zip` = `4f721ac3…` (all match the docs).

Line numbers refer to the files as they are now.

## 1. Contradictions with ground truth, or with each other

| # | File:line | Problem | Proposed replacement |
|---|---|---|---|
| 1.1 | AGENTS.md:36-37 | Lists `system/system/framework/oplus-services.jar` in module layout. File no longer exists. | `- framework/<base-md5>.jar` - adaptive/bedtime sensor reroute, one patched jar per ROM build (beta4 `3316594f…`, C.06 `2175feb9…`; see below) |
| 1.2 | AGENTS.md:40-41 | "built module" is `v0.7` | `pipa-cos17-power-tune-v0.9.zip` (md5 `4d479de1…`) - built module (archive root, no top-level folder). `pipa-perf-test-v0.1.zip` is the separate A/B test module. Older zips are predecessors (archive them, see section 6). |
| 1.3 | AGENTS.md:110-113 | "`system/framework` stays under `system/system/...`. The script searches for the framework jar, so both layouts work." Script no longer searches; it uses `$MODDIR/framework/<md5>.jar`. | "The framework jar lives in `framework/<md5 of the ROM jar>.jar` at the module root; `post-fs-data.sh` binds only the one matching the running ROM jar." |
| 1.4 | AGENTS.md:125-127 | Flag list omits `FRAMEWORK_ALLOW_ODEX` (exists in `config.prop`). | Add `FRAMEWORK_ALLOW_ODEX` after `FRAMEWORK_SENSOR_REROUTE`. |
| 1.5 | AGENTS.md:158-160 | "`patch_framework.sh` ... refuses to run on a different stock jar; re-derive offsets for a new port build." Script locates the sites by pattern and is verified on beta4 AND C.06 (header lines 19-20). | "`module/tools/patch_framework.sh` finds the edit sites by pattern (verified on beta4 `3316594f…` and C.06 `2175feb9…`) and aborts if a count differs. For a new ROM build run it on that build's own jar and save the output as `framework/<md5 of input>.jar`." |
| 1.6 | AGENTS.md:162-166 | "has no `.odex`, so no stale ART image is involved." True for beta4/beta5 only; C.06 stock ships `oat/arm64/oplus-services.{odex,vdex,art}`. | Add: "C.06 stock ships an odex; beta5 removes it, and `post-fs-data.sh` skips the bind if one exists unless `FRAMEWORK_ALLOW_ODEX=1`." |
| 1.7 | AGENTS.md:79 | androguard venv `/tmp/opencode/venv` | "androguard venv: `maintainer/jar-edits/venv` (184 MB, regenerable); no Java on the host." |
| 1.8 | AGENTS.md:228-237 | "Current state (2026-10-21, v0.6 installed)" - also omits v0.7 speaker fix, v0.9, beta5 work. "Open: ... debloat" etc. | Replace section with a pointer: "Current state: see `MAINTAINER-STATUS.md` (roadmap and session plan). Installed module version on the tablet: check `ksud module list`." Keep only the one-line list of open product issues (charger info, `crop_eyes`, thermal mapping, keyboard case test). |
| 1.9 | CLAUDE.md:100-105 and AGENTS.md:147-160 | Describe the jar as "holds the ROM's jar, which for beta4 is not donor stock (port author repacked it...)". OK historically but the later sentence "re-derive" (AGENTS) conflicts with `jar-edits/REPORT.md`. | Add after the S17 sentence: "A diff against C.06 found no port-author code edit (`maintainer/jar-edits/REPORT.md`); the repack itself is the only difference." |
| 1.10 | CLAUDE.md:16 | "regenerates ... the patched framework jar from the beta4 originals" | "... the patched framework jar from a ROM's own `oplus-services.jar`" |
| 1.11 | CLAUDE.md:72 | Flag list lacks `ADAPTIVE_RESTORE`, `FRAMEWORK_SENSOR_REROUTE`, `FRAMEWORK_ALLOW_ODEX`. | Append them (or link to `module/config.prop`). |
| 1.12 | HANDOFF.md:1, 6, 144, 167 | Title says "module v0.7"; `pipa-cos17-power-tune-v0.7.zip` three times. | `(module v0.9)`; `pipa-cos17-power-tune-v0.9.zip`. |
| 1.13 | HANDOFF.md:4 | Only beta4 is named. | "ROM: ColorOS 17 port beta4 `OPD2515_17.0.0.102(CN01)` (2026-10-17); beta5 (C.06 base) is built but not flashed, see `MAINTAINER-STATUS.md`." |
| 1.14 | HANDOFF.md:153 | `md5sum /system/framework/oplus-services.jar  # 06c5c303…` - only true on beta4 with the module. On beta5 + module it is `8c211ca5…`; on `beta5-baked` the ROM jar is already `8c211ca5…`. | `# 06c5c303… (beta4 + module), 8c211ca5… (C.06 + module, or beta5-baked)` |
| 1.15 | HANDOFF.md:166-179 | "Files" block: lists `README.md ... (this file)` (this file is HANDOFF.md), `patch_*.py` as if at the root, "The four line items above" (there are 8). | Replace with real paths (`module/tools/patch_framework.sh`, ...) and drop the "four line items" sentence, or delete the block and link `module/README.md` "Files". |
| 1.16 | HANDOFF-adaptive-bedtime.md:3-4 | Header says companion module v0.5 + md5. | "Companion module: `pipa-cos17-power-tune-v0.9.zip` (md5 `4d479de1…`). This write-up was written for v0.5 (beta4 jar); v0.9 ships one patched jar per ROM build." |
| 1.17 | HANDOFF-adaptive-bedtime.md:97-100 | "searches `$MODDIR` for the jar"; "has no `.odex`". | "binds `$MODDIR/framework/<md5 of /system/framework/oplus-services.jar>.jar` if it exists; skipped if a prebuilt `oplus-services.odex` exists (`FRAMEWORK_ALLOW_ODEX`)". |
| 1.18 | HANDOFF-adaptive-bedtime.md:154-156 | "Jar tied to beta4. The offsets and md5 checks are build-specific." | "Offsets in this note are for the beta4 jar only. `patch_framework.sh` finds the sites by pattern and also works on C.06 (payload `0x4365c0`, lux `+0x1fa`)." |
| 1.19 | HANDOFF-adaptive-bedtime.md:170, 176-181 | md5 `06c5c303…` as the only answer; Files lists `pipa-cos17-power-tune-v0.5.zip` and `module/system/system/framework/oplus-services.jar`. | Use `module/framework/<base-md5>.jar` and v0.9 as in 1.14. |
| 1.20 | MAINTAINER-STATUS.md:11 | "No beta5 is coming" - reads as if our own beta5 is cancelled. | "The original developer will not release a further build; there is no access to his MIO-Kitchen project or change list." |
| 1.21 | MAINTAINER-STATUS.md:79 | "Install v0.9 (or v0.8) before flashing beta5". v0.8 ships a single beta4 jar at the old path with an md5 guard; on C.06 it is safe but silently skips the reroute (no adaptive colour). RELEASE-NOTES-beta5.md:35 says v0.9 is required. | "Install v0.9 before flashing beta5. v0.8 is safe on C.06 (md5 guard, reroute skipped, adaptive colour off); v0.7 and older would put the beta4 jar over the C.06 framework (likely bootloop)." |
| 1.22 | MAINTAINER-STATUS.md:6 | "Last updated: ... (module v0.9, beta5 odex fix)"; rows 11-14, perf-test module and 1c were added later. | `Last updated: 2026-10-22 (module v0.9; beta5, beta5-baked, beta5-1c built offline; none flashed)` |
| 1.23 | MAINTAINER-STATUS.md:28 vs 29 | Row 4 says "Fixed 2026-10-22: 6 `remove` rows appended"; row 29 phrase "FRAMEWORK_ALLOW_ODEX=0" fine. Row 4 states "(`super.img` md5 `aeb211a5…`) replaced" - fine. No contradiction, but row 4 notes are 12 lines of history; move history into a changelog (section 3). | n/a |
| 1.24 | MAINTAINER-STATUS.md:30 vs STABILITY-PERF.md:60 | STATUS row 6 bakes `persist.sys.facehal.verbose=false` (beta5-baked); STABILITY ST15 and line 33 say "beta5 still has `…verbose=true`" with no baked qualifier. | STABILITY:60 `... still in plain beta5; fixed in beta5-baked (R12)`; line 33 same. |
| 1.25 | STABILITY-PERF.md:189 | Row 20 effort "S (script ready)", prerequisite "plain beta5 boots". The baked image is built and verified offline. | `S (built offline 2026-10-22: beta5-baked, MAINTAINER-STATUS row 6)` |
| 1.26 | STABILITY-PERF.md:171 | "Flash order from MAINTAINER-STATUS" - that doc has "Session plan". Also "verify U1/U17 fixed" is correct (restored in beta5). | `Session plan from MAINTAINER-STATUS (steps 3-6: 2b round trip, module v0.9, beta5)` |
| 1.27 | STABILITY-PERF.md:170 | "section 4: D1-D14", but section 4 has D1-D17. | `D1-D17` |
| 1.28 | STABILITY-PERF.md:25-26 | "`D15` is not a failing service" - collides with capture ID D15 (build identity) in section 4 and row 2. | "PATCH-INVENTORY item D15 (`init.fg.protect.rc-qcom`) is not a failing service" |
| 1.29 | STABILITY-PERF.md:3-9 | Mentions no `perf-test-module` / `bench.sh`; roadmap rows 3, 5, 11 (watermark, heap, perf-hal) are exactly what `pipa-perf-test-v0.1.zip` tests. | Add to rows 3, 5, 11: "Test first with `perf-test-module/` (flags WSF, HEAP_TUNE, PERF_HAL_VER)." |
| 1.30 | PHASE2-ROM-INTEGRATION.md:6-8 | "design only, nothing built or tested." Phase 1c (A1, A2) is built (`build_beta5_1c.sh`, STATUS row 13) and A9 test script exists. | "Status 2026-10-22: design; phase 1 (`build_beta5_baked.sh`) and phase 1c A1/A2 (`build_beta5_1c.sh`) are built offline, nothing is booted. A9 has `aod_overlay_test.sh`." |
| 1.31 | PHASE2-ROM-INTEGRATION.md:52-53 | "Phase 1c ... add to `build_beta5_baked.sh`". It is a separate script, A4 is opt-in (`DROP_FACEUNLOCK=1`). | "Phase 1c is `maintainer/build_beta5_1c.sh` (A1, A2; A4 with `DROP_FACEUNLOCK=1` after confirming the socket never exists)." |
| 1.32 | PHASE2-ROM-INTEGRATION.md:31, 32, 34 | Phase column `1c` but A1 row says "add `disabled` to loc_sys_service.rc"; the script comments the `start` line instead (STATUS row 13: "`disabled` alone would not stop an explicit start"). | A1 target: "comment the `start loc_sys_service` line in `on early-boot` (`disabled` alone does not stop an explicit start)". |
| 1.33 | PORT-MAINTAINER.md:130-138 | "Re-diff C.05 jar vs beta4 jar ... recovers the port's own edits ... Re-apply ... re-run the CCT reroute (M12) ... offsets have to be found again". Stale on all three counts. | "`oplus-services.jar`: the port repacked it (S17) but made no code edit that must be re-applied (`maintainer/jar-edits/REPORT.md`). Use the new donor jar as is, delete its `oat/arm64/oplus-services.*`, then generate the reroute jar with `module/tools/patch_framework.sh <new jar> module/framework/<md5>.jar` (pattern-based, no manual offsets)." |
| 1.34 | PORT-MAINTAINER.md:249 | "needs the re-derived jar patch" | "`OplusColorAmbientAdapter` registers 33171088 (M12; the module binds `framework/<md5>.jar` only when the ROM jar md5 matches)" |
| 1.35 | PORT-MAINTAINER.md:149-151 | Checklist says `system/build.prop`... "Add `ro.build.tablet_type=pad` (R12)"; the edit is in `my_product/build.prop` (PATCH-INVENTORY.md:345). No item for U17. | Add: "`system/build.prop`: keep the donor's `ro.secure=1`, `ro.adb.secure=1`, `ro.debuggable=0`, `ro.force.debuggable=0` (U17; beta4 deleted them)." Change tablet_type to "`my_product/build.prop` `ro.build.tablet_type=pad`". |
| 1.36 | PORT-MAINTAINER.md:44-47 | Calls C.05 "the most important download"; since C.06 + `PORT-EDITS.tsv` this is "nice to have, settles UNSURE rows". | "The C.05 package is only needed to settle the UNSURE rows of `maintainer/c06-vs-beta4/PORT-EDITS.tsv`; the working list already exists (STATUS row 3)." |
| 1.37 | PORT-MAINTAINER.md (whole) | Never mentions the build path actually used: `build_beta5.sh`, `apply_port_edits.py`, `PORT-EDITS.tsv`, `build_beta5_baked.sh`. | Add a short "§4.0 What we actually ran for beta5" paragraph linking `MAINTAINER-STATUS.md` "beta5 build" and those scripts. |
| 1.38 | PATCH-INVENTORY.md:162-166 vs 366-369 | S17 says the jar "carries an `OplusRemoteDisplay.uau` rule" as port edit; §9 says that is donor-native and "S17's mention ... is wrong". Self-contradiction. | S17 line 164: "It carries port strings ... (`OplusRemoteDisplay.uau` is donor-native, see §9)". Keep only the repack evidence as the port change. |
| 1.39 | PATCH-INVENTORY.md:216, 224 | Header "(`pipa_cos17_power_tune` v0.7)"; table row `system/framework/oplus-services.jar` / `3316594f…`. | Header `v0.9`; row: `framework/<base-md5>.jar` / `3316594f…` (beta4), `2175feb9…` (C.06) / "port-repacked (S17) on beta4; C.06 is donor stock". |
| 1.40 | PATCH-INVENTORY.md:41, 43, 256, 271 | U1, U17 shown as open; no marker that beta5 fixes them. | Append to U1: "Fixed in beta5 (absent)." Append to U17: "Fixed in beta5 (donor values restored); `device_check.sh` reports them." |
| 1.41 | PATCH-INVENTORY.md:296-297 | "Re-diff `oplus-services.jar` ... to re-derive the port's own dex edits, then run `tools/patch_framework.sh`" | "No port dex edits exist (`jar-edits/REPORT.md`). Run `tools/patch_framework.sh` on the new jar for the CCT reroute (M12)." |
| 1.42 | PATCH-INVENTORY.md:3-4 | Says "We have no Oppo Pad Mini donor stock" and baselines against HyperOS only; §9 later has C.06. | "Baseline: HyperOS1 factory for vendor/odm; OS side vs donor C.06 (§9)." |
| 1.43 | README.md:46 | `pipa-cos17-power-tune-v0.1.zip` "companion module" | `pipa-cos17-power-tune-v0.9.zip` (current), older zips are archived; `pipa-perf-test-v0.1.zip` is the A/B test module |
| 1.44 | README.md:319-321 | Section "Companion module ... v0.1", path v0.1.zip, md5 `1c8f066c…`. Whole section duplicates `module/README.md`. | Replace the section with 3 lines: current version v0.9, link to `module/README.md`, list of flags in `config.prop`. |
| 1.45 | README.md:491-504 | "Handoff (2026-10-21, after module v0.2)": item 1 says Eye comfort/bedtime/adaptive colour don't work; fixed since v0.3/v0.5. Item 2/3 stale. | Delete the subsection (superseded by `MAINTAINER-STATUS.md` and `HANDOFF.md` "Not fixed / open"). |
| 1.46 | README.md:308-313 | Changed-on-device table is in non-chronological order (v0.2, ..., v0.6 after the v0.7-era row) and has no row for current module (v0.9), OTA freeze (open), nor `device_capture --unhide-avc`. | Reorder by date; add "installed module version: check `ksud module list`; v0.9 not yet installed" until it is. |
| 1.47 | module/README.md:1-4 | Header only about beta4. | "...for the COS17 port, beta4 `17.0.0.102` and beta5 (C.06 `17.0.0.103`); v0.9 supports both (see 12)." |
| 1.48 | module/README.md:360-363 | "Base jar ... Re-derive those edits before reusing the patch on a new base (PATCH-INVENTORY S17)". Stale (no edits to re-derive). | "**Base jars.** beta4: the port-shipped repacked jar (`3316594f…`). C.06: donor stock (`2175feb9…`). A diff found no port code edit (`maintainer/jar-edits/REPORT.md`), so the same `patch_framework.sh` output applies to both." |
| 1.49 | module/README.md:418-422 | "Caveat. This is a stock 30 MB framework jar with a 4-byte dex edit ... (both KernelSU and Magisk layouts are searched)". Three edits, not stock on beta4, layout not searched. | "This is the ROM's own 30 MB jar with three dex edits, bind-mounted from `framework/<md5>.jar` ..." |
| 1.50 | module/README.md:334 | Heading "(v0.3)" while content is v0.9. | `## 12. Adaptive colour and Bedtime mode (v0.3; per-ROM jars and odex guard since v0.9)` |
| 1.51 | module/README.md:289 | Heading "11. ... (open, diagnosis only)" - problem solved by section 12. | `## 11. Eye comfort / bedtime tint (warm tint open; adaptive colour solved in 12)` |
| 1.52 | module/README.md:20-31 | Overview table lists rows 1-7 and 12, omitting 13 (USB DAC volume) and 14 (speaker rotation), though both are shipped files. | Add rows `13 | USB DAC / headset volume stuck at max | USB_HEADSET/A2DP curves | file: system/vendor/etc/audio_policy_volumes.xml` and `14 | speakers L/R swapped (rotation 270) | 32-bit audio HAL 270 -> spin_270 | file: system/vendor/lib/hw/audio.primary.kona.so`. |
| 1.53 | RELEASE-NOTES-beta5.md:3-5 | Only plain beta5 described; baked and 1c images not mentioned. | Add "Variants: `beta5` (this), `beta5-baked` (module file fixes baked in), `beta5-1c` (+ GNSS, pen perms); offered only after plain beta5 boots." |
| 1.54 | RELEASE-NOTES-beta5.md:25-26 | OK but "needed for the module's patched framework jar" fine; line 33 says "pipa_core ... required" OK. | none |
| 1.55 | perf-test-module/README.md:1-5 | OK; module is "v0.1" and has no pointer to `bench.sh` output format. | none (cosmetic) |
| 1.56 | maintainer/jar-edits/REPORT.md:1, 34 | Fine. Line 34 "(already handled in beta5 build)" fine. Line 6 is the authority; but contradicts AGENTS 1.5/PORT-MAINTAINER 1.33 only in those docs. | none |
| 1.57 | CLAUDE.md:5-6 and AGENTS.md:8-9 | Say "keep the two in sync". They differ now (AGENTS has "Current state", CLAUDE has keyboard internals). | Keep the sync rule but cut the duplicated blocks (section 3). |

## 2. Stale references (versions, paths, wording)

| File:line | Stale item | Replacement |
|---|---|---|
| AGENTS.md:30, 94 | fine (v0.9) | none |
| AGENTS.md:40, 228 | v0.7 zip, v0.6 state | see 1.2, 1.8 |
| HANDOFF.md:1,6,144,167 | v0.7 | v0.9 |
| HANDOFF.md:113 | "measured with v0.5" fine historically | add "(not re-measured with v0.9)" |
| HANDOFF-adaptive-bedtime.md:3, 176 | v0.5 zip | v0.9 |
| README.md:46, 308, 313, 319-321, 491-493 | v0.1 / v0.2 / v0.6 | see 1.43-1.46 |
| CLAUDE.md:16 | "Built zips sit next to it ... v0.1 is the zip-only predecessor" | "Built zips are `pipa-cos17-power-tune-v<ver>.zip`; v0.9 is current. Older zips are archived under `archive/`." |
| MESSAGE.md:4 | `pipa-cos17-power-tune-v0.7.zip` | v0.9 if kept, else archive MESSAGE.md (it is a note to the departed developer) |
| MESSAGE.md:26 | "`patch_*.py` / `patch_framework.sh` ... baked straight into `super`" | accurate now; add "(done in `beta5-baked`)" |
| MESSAGE.md:31-39 | Questions to the original developer ("if you move to the HyperOS 4 port ... I'd like to maybe keep maintaining") - answered/obsolete since he stopped. | Archive. |
| STABILITY-PERF.md:171 | "Flash order" | "Session plan" (1.26) |
| STABILITY-PERF.md:189, 20-row refs "MAINTAINER-STATUS step 1 / step 6" | STATUS has rows (roadmap) and "Session plan" steps; "step 1" in STABILITY:89 means roadmap row 1 and "step 6" row 6, but the Session plan also has steps 1-8. | Use "roadmap row N" everywhere (STABILITY:89, 189; PHASE2:7 already says "row 6"). |
| PORT-MAINTAINER.md:136-138 | "will refuse a new jar, so the offsets have to be found again" | see 1.33 |
| PATCH-INVENTORY.md:216 | v0.7 | v0.9 |
| module/README.md:183 | "An earlier v0.2 build" - fine | none |
| module/README.md:516 | Files block lists `service.sh (color_mode: runtime state)` | fine; add `perf-test-module` pointer? not needed |
| module/README.md:197 | `oplus-services.jar` "(beta4)" in brightness text | fine |
| PHASE2-ROM-INTEGRATION.md:7 | "row 6" | fine |
| MAINTAINER-STATUS.md:79-80 | "(or v0.8)" | see 1.21 |
| MAINTAINER-STATUS.md:42 | "blocked by the auto-mode classifier" - tooling anecdote, not maintainer info | "The user must run the third-party OPlus-Tracker script themselves (`tomboy_pro.py OPD2515_11.C cn`, Python deps in a venv)." |
| CLAUDE.md:25, 159 | Refer to README "What was changed on the device" - correct section name. | none |
| `.task-diff-inventory.md` (COS17 root, hidden) | leftover task prompt for the inventory run | Delete or move to `maintainer/archive/`. |

## 3. Duplicated content that should become a link

| Same facts maintained in | Suggested owner | Action |
|---|---|---|
| "Maintainership (from 2026-10-22)" block: CLAUDE.md:49-58 = AGENTS.md:83-92 (identical, including long script list) | `MAINTAINER-STATUS.md` (index of scripts), plus a doc map | Replace both blocks with 3 lines: "stefan maintains the port since 2026-10-22. Start at `MAINTAINER-STATUS.md`; doc map in `README-DOCS.md`/`MAINTAINER-STATUS.md`." |
| Adaptive colour / Bedtime: CLAUDE.md:96-114, AGENTS.md:145-189, HANDOFF.md:89-100 and fix-matrix row 7, HANDOFF-adaptive-bedtime.md, module/README.md section 12, MESSAGE.md:21 | `module/README.md` section 12 (current), `HANDOFF-adaptive-bedtime.md` for dex offsets only | Keep one short paragraph + link in CLAUDE/AGENTS/HANDOFF. Version-guard and odex text only in module/README section 12. |
| USB audio + speaker rotation: CLAUDE.md:116-133 = AGENTS.md:191-208 (verbatim) = HANDOFF.md:120-138 = MESSAGE.md:12-17 | `module/README.md` sections 13-14 | Replace with 2-3 line summary + link. |
| Module build/install, no mount provider, design constraints: CLAUDE.md:60-80 = AGENTS.md:94-143 = module/README.md:9-17 | `AGENTS.md` (agent instructions) | CLAUDE.md should say "see AGENTS.md" for these, keeping only Claude-specific lines (plan limits, memory). One file, not two copies. |
| Display facts: CLAUDE.md:90-94 = AGENTS.md:172-189 = HANDOFF.md:66-87 = module/README.md sections 6-7 | `module/README.md` | Link. |
| Module v0.9 jar md5s (`3316594f…`->`06c5c303…`, `2175feb9…`->`8c211ca5…`): CLAUDE.md:100-105, AGENTS.md:147-159, STATUS row 5 and line 78, module/README.md:365-368, RELEASE-NOTES-beta5.md:38, HANDOFF.md:153 | `module/README.md` section 12 | Other docs: name the guard once, link; keep md5 in one table. |
| beta5 build facts (odex removal, U17, build.prop, jar): MAINTAINER-STATUS row 4, "beta5 build" section (lines 55-82), RELEASE-NOTES-beta5.md:16-29, STABILITY-PERF.md:31-34 | `MAINTAINER-STATUS.md` "beta5 build: decisions" | STABILITY item 5 -> link; RELEASE-NOTES keeps user-facing wording only. Move the 12-line row-4 history to a "Build log" section. |
| beta5-baked file list: STATUS row 6 (long), `build_beta5_baked.sh` header, PHASE2 section "Phase 1c" | `maintainer/build_beta5_baked.sh` header | STATUS row 6: one sentence + md5 + link to script header. |
| Regression checklist: PORT-MAINTAINER.md §8, `device_check.sh` header, PHASE2 "Test protocol", STATUS row 7 | `maintainer/device_check.sh` (executable truth) + PORT-MAINTAINER §8 (human list) | Others link. |
| Idle numbers 53.4 -> 42 mAh/h: README TL;DR/Open item 1, HANDOFF.md:44-53,113, MESSAGE.md:11, STABILITY:148, PHASE2:105, PORT-MAINTAINER:255 | `README.md` Open item 1 | Link elsewhere. |
| Fix matrix (14 rows): HANDOFF.md:25-40, module/README.md:20-29, README.md TL;DR, MESSAGE.md fixes list | `module/README.md` table | HANDOFF fix matrix may stay as the 1-page index but must include "Module workaround" only by link. |
| OTA false storage dialog + do-not-install: CLAUDE.md:139-157, AGENTS.md:216-226, README.md finding 11, HANDOFF.md row 10, RELEASE-NOTES:55-57, STABILITY | `README.md` finding 11 | Keep 2 lines + link. |
| `pipa_core` v1.10 copy facts: STATUS line 95 vs RELEASE-NOTES:33 vs CLAUDE (none) | `MAINTAINER-STATUS.md` artifacts table | CLAUDE.md: add one line pointing to `COS17/pipa_core-v1.10.zip`. |
| Donor info (C.05 base, C.06 obtained): STATUS lines 14-17, 46-53; PORT-MAINTAINER.md:28; PATCH-INVENTORY.md:332-336; RELEASE-NOTES:12 | `MAINTAINER-STATUS.md` "Donor firmware" | Link. |
| Session plan vs STABILITY roadmap rows 1, 2, 20 vs PHASE2 "Test protocol" | `MAINTAINER-STATUS.md` Session plan | STABILITY rows 1-2: reference it, do not restate. |

## 4. Broken or doubtful internal references

| File:line | Reference | Problem / fix |
|---|---|---|
| AGENTS.md:36 | `system/system/framework/oplus-services.jar` | Removed. See 1.1. |
| HANDOFF-adaptive-bedtime.md:181 | `module/system/system/framework/oplus-services.jar` | Removed. Use `module/framework/<md5>.jar`. |
| PATCH-INVENTORY.md:162, 224 | `system/system/framework/oplus-services.jar`, `system/framework/oplus-services.jar` | Fine for the ROM path (162); 224 is the module-side path, now `framework/<md5>.jar`. |
| HANDOFF.md:11-13 | Item "0" before "1", numbered list starts at 0 and `AGENTS.md` last; read order puts maintainer docs first but README "1." is "audit". | Renumber 1-5 and mention `PORT-MAINTAINER.md` and `PATCH-INVENTORY.md` explicitly (it only says "then"). |
| HANDOFF.md:168-175 | `README.md  full audit (this file)`, `patch_framework.sh`, `patch_audio_volumes.py`, `patch_audio_hal.py` listed as if next to the zip | They are in `module/tools/`. |
| HANDOFF.md.bak:11-16, 165-166 | Refers to `audit.md`, `module-README.md` (names from the flat handoff zip) | The live HANDOFF.md already uses `README.md` / `module/README.md`. The .bak is the pre-rename copy; archive or delete. The old handoff zips v0.5-v0.7 presumably contain these flat names. |
| CLAUDE.md:152 | "README finding #11" | OK (exists). |
| CLAUDE.md:82 | "README, open item 2" | OK. |
| PORT-MAINTAINER.md:87 | `beta4-changes/port-changes.tsv` | Not present; actual output is `maintainer/c06-vs-beta4/port-changes.tsv`. Replace by the real path or note "(example output dir)". |
| PORT-MAINTAINER.md:84 | `port_diff.py changes $D_C05 ... -o COS17/maintainer/beta4-changes` | `$D_C05` does not exist (C.05 not obtained); in practice `$D_C06` was used with `-o maintainer/c06-vs-beta4`. State that. |
| PATCH-INVENTORY.md:15-19 | `diff_manifests.py`, `vendor-findings.md`, `odm-product-findings.md`, `system-findings.md` | Live in `../reference/analysis/inventory/`; fine but add the path to each (they are not in COS17). |
| STABILITY-PERF.md:80 | "add `remove` row to `PORT-EDITS.tsv`" | Full path `maintainer/c06-vs-beta4/PORT-EDITS.tsv`. |
| STABILITY-PERF.md:31 | "(PORT-EDITS row 32)" | Row 32 of the file is line 32; use the path and "line 32 DROP `zz_portdebug.rc`". |
| STABILITY-PERF.md:89, 189 | "MAINTAINER-STATUS step 1 / step 6" | Roadmap uses "#"/rows; "Session plan" uses numbered steps. Say "roadmap row 1/6". |
| perf-test-module/README.md:4 | `MAINTAINER-STATUS.md` row 11 | OK. |
| module/README.md:31 | "(8), (9), (10)" | Sections exist; fine. |
| module/README.md:197-200 | "(`oplus-services.jar`, beta4)" | fine |
| MAINTAINER-STATUS.md:57 | `build_beta5.sh` is listed as "root" but is not executable (mode 644) unlike the other `*.sh` | `chmod +x` or document `sudo sh`. (Not a doc defect; note only.) |
| MAINTAINER-STATUS.md:99 | "`maintainer/` ... `jars/`" | `maintainer/jars/oplus-services.C06-2175feb9.patched.jar` equals `module/framework/2175feb9….jar` (same md5 `8c211ca5…`). Document "copy used by build_beta5_baked.sh" or remove (baked script reads `$MOD/framework/…`). |
| CLAUDE.md:56, STATUS:99 | `maintainer/__pycache__/`, `roundtrip_run.log`, `jar-edits/venv`, `onlyb4.txt` vs `only_b4.txt` | Duplicate-named files in `jar-edits/` (`only_b4.txt`/`onlyb4.txt`, `only_c06.txt`/`onlyc06.txt`). Not referenced by any doc; delete one of each pair. |

## 5. Malformed markdown tables

| File:line | Problem | Fix |
|---|---|---|
| MAINTAINER-STATUS.md:38 (roadmap row 14) | Code span `` `sh maintainer/aod_overlay_test.sh lookup|apply N|freeze-daemon|resume-daemon|revert` `` contains unescaped pipes: GFM splits the row into 8 cells (header has 4). | Write `lookup\|apply N\|freeze-daemon\|resume-daemon\|revert`, or list the subcommands with commas: `lookup, apply N, freeze-daemon, resume-daemon, revert`. |
| STABILITY-PERF.md:200-207, 209-215 (section 4, D1-D17) | Shell commands in the 3-column table (`| ID | Answers | Command |`) contain many unescaped `|` (pipes to `grep`/`sort`/`head`/`awk`). Rows render with 4 to 18 cells; commands are cut. Lines affected: 200, 201, 202, 203, 204, 205, 206, 207, 209, 210, 211, 212, 213, 214, 215. | Move the commands out of the table: keep `| ID | Answers |` and put each command in a fenced block under the table, or escape every `|` as `\|`. Safest: one fenced block per D-ID, and `device_capture.sh` as the single source (STATUS row 12). |
| MAINTAINER-STATUS.md:28-30, 37 | Rows are syntactically 4 cells, but cells hold 800-1500 characters and a nested "second table cell" appearance (row 6 and 13 read like 5 columns: the Notes cell starts with a path and md5 and a `sudo sh ...` command). | Split rows 4, 6, 13 into a short table row (status + md5) plus a "Build details" subsection per build; move the sudo commands to a "Commands" list. |
| README.md:300-313 | Cells with `\|` none; OK. | none |
| PORT-MAINTAINER.md:245 | Uses `\|` correctly (renders; keep). | none |

Checked all other tables in the 15 docs with a pipe counter: no other mismatch.

## 6. Suggested doc map

Audience: M = maintainer (stefan), A = AI agent working in the folder, R = release readers (Telegram), D = original developer / outside.

| Doc | Purpose | Audience | Verdict |
|---|---|---|---|
| `MAINTAINER-STATUS.md` | Roadmap, build decisions, artifacts on disk, session plan. Single status source. | M, A | **Keep; split the heavy rows** (see section 5), add changelog section. |
| `PORT-MAINTAINER.md` | Procedure to rebase onto a new donor; layer model; erofs/super parameters; regression table. | M, A | **Keep**; fix 1.33-1.37; add real beta5 workflow. |
| `PATCH-INVENTORY.md` | Classified list of what the port changed (S/U/R/M IDs). | M | **Keep**; fix 1.38-1.42; split §9 into its own file if it grows. |
| `PHASE2-ROM-INTEGRATION.md` | Design to move runtime fixes into the ROM. | M | **Keep**; fix status line (1.30-1.32). |
| `STABILITY-PERF.md` | Stability/performance plan and capture IDs. | M | **Keep**; fix D-table (section 5) and refs; move D-commands to `device_capture.sh`. |
| `RELEASE-NOTES-beta5.md` | Draft release notes for readers. | R | **Keep as draft**; add variants; publish only after boot. |
| `README.md` | Original device audit (findings, evidence, change table, reproduce). | M, A | **Keep as the audit record**; delete v0.1 module section and "Handoff after v0.2"; keep "What was changed on the device". |
| `module/README.md` | Per-fix developer write-up for the module (main technical doc). | M, A | **Keep**; fix 1.47-1.52. |
| `perf-test-module/README.md` | Perf A/B module instructions. | M | **Keep**. |
| `maintainer/jar-edits/REPORT.md` | Evidence that the jar has no port edits. | M | **Keep** (cite from other docs instead of restating). |
| `CLAUDE.md` | Claude Code guidance. | A | **Keep, slim down**: remove blocks duplicated in AGENTS.md and module/README; keep device access, flashing rule, gotchas, pointers. |
| `AGENTS.md` | Agent-agnostic guidance (same content). | A | **Keep as the owner**; make CLAUDE.md a thin file pointing here. Or merge both: `AGENTS.md` canonical, `CLAUDE.md` = "@AGENTS.md" plus Claude-only lines. |
| `HANDOFF.md` | One-page index of fixes for the *original developer* (module v0.7 era). | D | **Merge into module/README (fix matrix) and archive**; or refresh (v0.9, beta5) and keep only as a short external handoff. As it stands it duplicates module/README and README. |
| `HANDOFF-adaptive-bedtime.md` | Exact dex offsets and behaviour of the CCT reroute (beta4 jar). | M | **Keep as module/README appendix** (rename `module/ADAPTIVE-COLOUR-DEX.md`) after fixing 1.16-1.19; it is the only place with beta4 offsets. |
| `MESSAGE.md` | Cover note and 6 questions to the original developer (v0.7). | D | **Archive** (obsolete: he stopped, questions answered by the C.06 work). |
| `HANDOFF.md.bak` | Pre-rename copy (`audit.md`, `module-README.md`) of HANDOFF.md. | none | **Delete** (or move to `archive/`); differs only in file names. |
| `MESSAGE.md.bak` | Same, pre-rename (`audit.md`). | none | **Delete/archive** with MESSAGE.md. |
| `maintainer/c06-vs-beta4/PORT-EDITS.tsv.bak` | Backup before 6 `remove` rows were added (69 vs 75 lines). | none | **Delete after beta5 boots** (or move to `archive/`); rows are all in PORT-EDITS.tsv. |
| `pipa-cos17-power-tune-v0.1`..`v0.7.zip` (and v0.8) | Old module builds. | none | **Archive** to `archive/modules/`; keep v0.8 only if its md5-guard behaviour is needed for rollback (v0.9 supersedes). v0.7/older are dangerous on beta5 (bind beta4 jar); do not keep them next to the current zip. |
| `pipa-cos17-dev-handoff-v0.5/0.6/0.7.zip` | Old handoff bundles (flat file names). | none | **Archive** (14.9-15.3 MB each) or delete after confirming `HANDOFF.md` + `module/` are enough; keep only the newest if a bundle is still wanted, regenerate for v0.9. |
| `pipa-cos17-power-tune-v0.9.zip`, `pipa-perf-test-v0.1.zip`, `pipa_core-v1.10.zip` | Current artifacts. | M, R | **Keep**. |
| `.task-diff-inventory.md` | Leftover task prompt. | none | **Delete/archive.** |
| `maintainer/roundtrip_run.log`, `maintainer/__pycache__`, `jar-edits/onlyb4.txt`, `jar-edits/onlyc06.txt` (duplicates of `only_b4.txt`, `only_c06.txt`) | Scratch. | none | Delete. |

Proposed: add a short `DOCS.md` (or make the top of `MAINTAINER-STATUS.md` this table) and cut the "Maintainership" and "USB audio" blocks from both CLAUDE.md and AGENTS.md.

## Counts

| Category | Count |
|---|---|
| 1 Contradictions / stale facts | 57 rows (about 44 real defects; the rest are "none"/notes) |
| 2 Stale references | 20 |
| 3 Duplication to link | 14 clusters |
| 4 Broken / doubtful references | 20 |
| 5 Malformed tables | 2 real (STATUS:38; STABILITY-PERF section 4, 15 rows) + 1 readability warning |
| 6 Doc map entries | 25 |

## Ten most important fixes

1. MAINTAINER-STATUS.md:79 and RELEASE-NOTES-beta5.md:35: say "v0.9 required; v0.8 is safe on C.06 but disables adaptive colour; v0.7 and older bootloop" (v0.8 and v0.7 zips ship a single beta4 jar at the removed path).
2. AGENTS.md:36-41, 110-113, 125-127, 158-166 (and HANDOFF-adaptive-bedtime.md:97-100, 154-156, 176-181): remove the deleted `system/system/framework/oplus-services.jar` path, v0.7 zip, "searched layouts", "re-derive offsets", "no .odex" - replace with the `framework/<md5>.jar` + odex-guard description.
3. PORT-MAINTAINER.md:130-138 and 249, PATCH-INVENTORY.md:296-297, module/README.md:360-363 and 418-422: delete the "re-derive the port's jar edits" instructions (REPORT.md found none); say `patch_framework.sh` is pattern-based and verified on beta4 and C.06.
4. PATCH-INVENTORY.md:164 vs 366-369: S17 still says `OplusRemoteDisplay.uau` is a port edit; §9 says the opposite. Fix S17.
5. HANDOFF.md:1, 6, 144, 153, 166-179 and AGENTS.md:228-237: version v0.7/v0.6 and "current state" are stale, `06c5c303…` is not the md5 on C.06 or baked images, "Files" block lists non-existent root files. Update or archive HANDOFF.md.
6. MAINTAINER-STATUS.md:38 and STABILITY-PERF.md:200-215: fix the broken tables (unescaped `|` inside code spans); the D1-D17 table is unreadable as rendered.
7. PHASE2-ROM-INTEGRATION.md:6-8, 52-53: "nothing built" and "add to build_beta5_baked.sh" contradict STATUS row 13 and `build_beta5_1c.sh` (A1 is a commented `start`, A4 is opt-in).
8. STABILITY-PERF.md:60, 33, 170-171, 189: facehal.verbose is fixed in beta5-baked; "Flash order" -> "Session plan"; "D1-D14" -> "D1-D17"; row 20 script is built; "D15" naming collision at lines 25-26.
9. README.md:46, 319-321, 491-504, 308-313: delete the v0.1 module section and the "after v0.2" handoff (claims adaptive colour does not work), refresh artifact list; keep one authoritative module description in `module/README.md`.
10. Remove duplicate blocks (Maintainership, USB audio, adaptive colour, module build/design constraints) from CLAUDE.md/AGENTS.md in favour of links; archive MESSAGE.md(.bak), HANDOFF.md.bak, `PORT-EDITS.tsv.bak` (after beta5 boots), v0.1-v0.7 module zips and v0.5-v0.7 handoff zips; add a doc map to `MAINTAINER-STATUS.md`.

## Applied (2026-10-22)

Edited only `.md` files under COS17; the snapshot, scripts and zips were not touched. All tables in the edited docs were re-checked: every row has the same cell count as its header (the only mismatches left are the audit's own illustrative rows in this file).

Applied:
- 1.1-1.7, 1.9-1.11, 1.57 (AGENTS.md, CLAUDE.md): module layout `framework/<base-md5>.jar`, v0.9 zip, no "searched layouts", `FRAMEWORK_ALLOW_ODEX` and the other flags, pattern-based `patch_framework.sh`, odex statement (C.06 ships one, beta5 removes it, bind skipped unless `FRAMEWORK_ALLOW_ODEX=1`), venv path, "Current state" replaced by a pointer to MAINTAINER-STATUS.md, jar-diff sentence. Duplicated blocks (Maintainership, adaptive colour internals, display, USB audio / speaker rotation) shortened to summaries with links to module/README.md and HANDOFF-adaptive-bedtime.md. All device-access, ask-before-flash/wipe/persistent-change, reboot, module design constraint, don't-kill-system_server, OTA warning and "another agent may be attached" text was kept. CLAUDE.md and AGENTS.md updated in parallel. The CLAUDE.md-only keyboard-daemon internals block was left (device-specific, not duplicated elsewhere).
- 1.8: AGENTS.md "Current state" replaced as proposed.
- 1.12-1.15, 4 (HANDOFF.md): refreshed rather than archived: v0.9 title and zip, beta5 note, md5 comment for both jar states, renumbered read order including PORT-MAINTAINER/PATCH-INVENTORY, real paths in the Files block, "not re-measured with v0.9" note, short intro stating it is an index.
- 1.16-1.19 (HANDOFF-adaptive-bedtime.md): header, binding/odex paragraph (v0.5 behaviour kept as historical), limitation 3, verify md5, Files list.
- 1.20-1.22, 2 (MAINTAINER-STATUS.md): "Last updated" line, rephrased "No beta5 is coming", v0.9-required sentence, A4 opt-in note in row 8, `\|` escapes in row 14 (table fixed), tooling-anecdote sentence removed from "Donor firmware", `jars/` note, Doc map section added after Context (also lists zips, .bak/.tsv.bak and scratch files with recommendations, none moved).
- 1.24-1.29, 4, 5 (STABILITY-PERF.md): facehal.verbose qualifier (plain beta5 vs baked), D15 naming, "Session plan", D1-D17, row 20 effort, roadmap-row wording, PORT-EDITS.tsv full path and line, perf-test-module pointers on rows 3, 5, 11, and the D1-D17 table: every `|` in the command cells escaped as `\|`.
- 1.30-1.32 (PHASE2-ROM-INTEGRATION.md): status line, A1 target, phase 1c script and A4 opt-in.
- 1.33-1.37 (PORT-MAINTAINER.md): jar procedure, row 249 wording, checklist (U17 keep, tablet_type in my_product), C.05 wording, real paths/`$D_C05` note, new section 4.0 describing the beta5 build path.
- 1.38-1.42 (PATCH-INVENTORY.md): S17 `uau` contradiction, v0.9 header and module-file row, U1/U17 "fixed in beta5", jar re-derive step, baseline wording.
- 1.43-1.46 (README.md): file-list row now v0.9. Per rule 2 the v0.1 module section and "Handoff after v0.2" were NOT deleted; each got a "(historical ...; superseded by v0.9)" note. Changed-on-device table left intact; a short module-state/OTA-freeze/--unhide-avc note was added below it instead of reordering rows.
- 1.47-1.52 (module/README.md): header, "Base jars", caveat paragraph, headings of sections 11 and 12, overview rows 13 and 14.
- 1.53 (RELEASE-NOTES-beta5.md): variants line, plus a v0.8 sentence.
- Rule 4: MESSAGE.md, MESSAGE.md.bak, HANDOFF.md.bak moved to `archive/` (no remaining references except the doc map and the HANDOFF.md Files block).

Not applied, and why:
- 1.23 / section 5 "split rows 4, 6, 13 of MAINTAINER-STATUS.md into short rows plus build-detail subsections" and moving the row-4 history to a changelog: the tables are syntactically valid, and restructuring them is a larger rewrite; left as is.
- Section 3 consolidation beyond CLAUDE.md/AGENTS.md (STATUS row 6 shortened, STABILITY item 5 and RELEASE-NOTES de-duplication, Idle-numbers/fix-matrix links): left, to avoid dropping facts.
- Section 6 verdicts needing file operations: `HANDOFF-adaptive-bedtime.md` rename to `module/ADAPTIVE-COLOUR-DEX.md`, a separate `DOCS.md`, making CLAUDE.md a thin "@AGENTS.md" file; zips, `PORT-EDITS.tsv.bak`, `.task-diff-inventory.md`, scratch files and `onlyb4.txt`/`onlyc06.txt` were not moved or deleted (listed in the Doc map with recommendations).
- 1.45 and 1.44 deletions (rule 2: historical content kept with notes). 1.46 row reordering (rule 2: table kept intact).
- PATCH-INVENTORY.md lines 15-19 tool-path additions (section 4), 1.54-1.56 (no change needed), `build_beta5.sh` mode 644 (script, not a doc).
- STABILITY-PERF.md `device_capture.sh` as single source for D-commands (commands kept in the doc, only escaped).
- Decision for the user: whether to archive the old zips and handoff bundles and delete `PORT-EDITS.tsv.bak` after beta5 boots.
