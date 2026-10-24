# Files left out of this repo

Proprietary binaries are not published here. Get them from the original beta4 release / a flashed ROM, or regenerate
them with the tools in `module/tools/` and `maintainer/` (the build steps check md5s and stop when one is missing).

| Path | What | Where from |
|---|---|---|
| `module/framework/*.jar`, `maintainer/jars/*.jar` | OPPO `oplus-services.jar` with the port's dex edits (CCT sensor reroute, IEngineer boot hang) | `module/tools/patch_framework.sh` on the donor's own jar |
| `module/system/vendor/etc/qdcm_calib_data_*.xml` | Xiaomi panel colour calibration with PCC enabled | `module/tools/patch_qdcm.py` on pipa's vendor files |
| `module/system/system_ext/etc/display_brightness_config_*.xml` | ColorOS brightness table for pipa | `module/tools/gen_brightness_table.py` |
| `module/system/vendor/lib/hw/audio.primary.kona.so` | Qualcomm audio HAL with swapped speaker channels fixed | `module/tools/patch_audio_hal.py` on pipa's vendor HAL |
| `module/system/system_ext/lib*/libupdateprof.qti.so`, `libtrigger-handler.so` | Qualcomm libs from beta4 (C.06 versions hang the boot) | beta4 release `system_ext` |
| `port-rom/pipa_port/facehal/` | face unlock HAL (facehal-rs) + SenseTime/Qualcomm libs | the original developer's `pipa_core` module / beta4 release |
| `port-rom/pipa_port/xiaomi_touch_ioctl`, `port-rom/pipa_port/chargershim.jar` | pen-wake helper, OPPO charger HAL shim (from `pipa_core`; the shim is patched by `maintainer/chargershim/patch_auth.py`) | `pipa_core` / beta4 release |
| `maintainer/bootanim/*.zip` | boot animation | `maintainer/bootanim/` scripts from the donor animation |
| `maintainer/kgest/kgest` | touch gesture injector (built binary) | build from `maintainer/kgest/` |
