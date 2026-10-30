# Files that are not in this repository

This repository does not contain proprietary binaries, images or signing keys. A build needs the files below.
`port.sh --check` shows each missing file (`MISSING input of <step>`). The inputs from outside this repository (beta4
release, donor OTA, tools) are in [BUILD.md](BUILD.md), section 1.3.

## Files that a build needs

| Path | What | Where from |
|---|---|---|
| `port-rom/pipa_port/facehal/` | Face unlock HAL (facehal-rs) and the SenseTime/Qualcomm libraries. `facehal/VERSION` lists the md5 of each file. | The original developer's `pipa_core` module / beta4 release |
| `port-rom/pipa_port/facehal/lib64/libpipa_facecrop.so`, `libpipa_eyeguard.so` | Face enrollment crop and eye guard add-ons (steps 2e, 3f) | Own code: source in `port-module/src/`. Build: `sh port-module/src/build_facecrop.sh` and `build_eyeguard.sh` (Android NDK). |
| `port-rom/pipa_port/xiaomi_touch_ioctl` | Pen-wake helper | `pipa_core` / beta4 release |
| `port-rom/pipa_port/chargershim.jar` | OPPO charger HAL shim (step 2k) | `pipa_core` / beta4 release, patched by `maintainer/chargershim/patch_auth.py` (input `chargershim-orig.jar`, also not in this repository) |
| `maintainer/cryptoeng/cryptoeng.jar` | `ICryptoeng` shim (step 3a) | Build: `sh maintainer/cryptoeng/build.sh` (source in the same folder) |
| `helper/out/PipaHelper.apk` | pipa helper app (steps 2d, 2e, 2p) | Build: `sh helper/build.sh`. The signing key `helper/keys/` is private. |
| `module/system/vendor/etc/qdcm_calib_data_*.xml` | Xiaomi panel colour calibration with PCC on (baked step) | `module/tools/patch_qdcm.py` on the pipa `vendor` files |
| `module/system/system_ext/etc/display_brightness_config_*.xml` | ColorOS brightness table for pipa (baked step) | `module/tools/gen_brightness_table.py` |
| `module/system/vendor/lib/hw/audio.primary.kona.so` | Qualcomm audio HAL with the speaker channels in the correct order (baked step) | `module/tools/patch_audio_hal.py` on the pipa `vendor` HAL |
| `module/system/system_ext/lib*/libupdateprof.qti.so`, `libtrigger-handler.so` | Qualcomm libraries from beta4 (the C.06 versions stop the boot) | beta4 release `system_ext` |
| `maintainer/bootanim/bootanimation.zip`, `rbootanimation.zip` | Boot animation (step 2e) | The donor animation with the logo centred (`offsety 0`). No script in this repository. |
| `COS17/kernel/sukisu-v4.3.0/`, `COS17/kernel/sukisu-v4.2.1-r1/` | SukiSU-Ultra manager APKs (steps 2w, 2u) | SukiSU-Ultra releases ([BUILD.md](BUILD.md), section 1.3) |

## Files that the build does not need

| Path | What | Where from |
|---|---|---|
| `module/framework/*.jar`, `maintainer/jars/*.jar` | Old copies of `oplus-services.jar` with the port's dex edits. The base step patches the donor jar during the build. | `module/tools/patch_framework.sh` on the donor's own jar |
| `maintainer/kgest/kgest` | Touch gesture injector for the smoothness test | Build: `maintainer/kgest/build.sh` |
