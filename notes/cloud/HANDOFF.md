# Hand-off: cloud session of 2026-11-03 to a local session

Everything below is static analysis or a cloud build. **Nothing is tested on the tablet.** Do not merge a cloud
branch without a review and a device test (CLOUD-PROMPTS rule). Donor of the analysis: C.07 (the OTA server offers no
C.06 now); the port builds from C.06, so each patch stops on a mismatch instead of guessing.

## Branches (stacked, merge in this order)

| # | Branch | Content |
|---|---|---|
| 1 | `cloud/hal-inventory` | Notes: HAL inventory, charger HAL table, gameopt interface |
| 2 | `cloud/bypass-4p` | Step 4p bypass charging (patch_record.py, service.sh chg_hold) |
| 3 | `cloud/vintf-4q` | Step 4q (no VINTF entry for oplusSensor/urcc/hummingbird); notes: init services, Java waits, oplusSensor; DEVICE-CHECKS.md |
| 4 | `cloud/halshims` | Step 4r: HAL shims in one host (gameopt, displaypanelfeature, misc, touch); notes: gameopt shim, misc/sensor, transmessage/urcc/stats, defrag |
| 5 | `cloud/opt-service` | service.sh process savings (kb_guard, system_ux); step 4s (no NfcNci, SecureElement, QCC); notes: APPS-RAM |

Independent: `cloud/display-hals` (display colour HALs; Java colour-matrix plan), `cloud/bug36` (stuck 120 Hz capture
checklist), kernel repo `cloud/dp-test` (DP test switches, `out/Image-dptest.gz`, `notes/DP-TEST.md`).

## First steps (local, in this order)

1. Read `notes/cloud/DEVICE-CHECKS.md`. Run the read-only checks (sections 1, 2, 7.1). They decide what to build.
2. Build the jars: `sh maintainer/halshims/build.sh` (Android SDK platform 37, build-tools 37) and
   `maintainer/chargershim/patch_record.py` on the shim jar (4p).
3. Compile the policy on the tablet with `/system/bin/secilc`, all 8 inputs, plus `maintainer/halshims/halshims.cil`
   (DEVICE-CHECKS section 6 step 0). The cloud could not run a secilc for Android 17 CIL.
4. Build with `port.sh --until 4s --keep-tree`, compare the `report/*.tsv` manifests, add the image name and md5 to
   `maintainer/flash_super.sh`, ask before the flash.
5. Tests: CHARGER-HAL.md E.4 (4p), DEVICE-CHECKS sections 6 (4r) and 7 (4s), DP-TEST.md (kernel, `fastboot boot`).

## Open decisions and next work

- Display Java patch (Read Mode, Reduce White Point, Game Eye Care): only after DEVICE-CHECKS section 2.
- gameopt: keep the shim if oiface shows a blocked thread without it (section 1.2) and the game thread UX shows up.
- oplus_defrag: DEFRAG.md section 7, then a step that turns off dedup and Turbo Pocket only.
- urcc: measure first (TRANS-URCC-STATS.md); no own shim without a measured gap.
- horae: decision 2026-11-03, mi_thermald stays the only thermal controller.
- RAM: the cryptoeng shim stays a separate process (privacy records); the charger shim has no source to merge.
- Rebase to C.07: run `maintainer/donor_check.sh` with the C.06 and C.07 images; all jar patches need a re-check.
