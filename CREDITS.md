# Credits

Where each part of the port comes from. Details: [HANDOFF-FROM-ZERO.md](HANDOFF-FROM-ZERO.md) (section B0),
[KERNEL.md](KERNEL.md), [BLOBS.md](BLOBS.md).

**People**

- 梦归zzz ([t.me/joeyzhu1](https://t.me/joeyzhu1)): the original ColorOS 17 port for pipa (beta4) and the `pipa_core` module (do not use `pipa_core` with v9).
- Stefan-Atanasov: maintenance since beta5 (beta5 to v9.3), ROM fixes, kernel, pipa helper.

**ROM**

| Part | From |
|---|---|
| System (`system`, `system_ext`, `product`, `my_*`) | OPPO ColorOS 17: OPPO Pad Mini OPD2515 `17.0.0.104(CN01)` (C.07) |
| Vendor, `odm`, recovery ramdisk, dtb, dtbo | beta4 (梦归zzz): a LineageOS-family Android 17 build of `device/xiaomi/pipa` + `sm8250-common`, with Xiaomi files and OPPO HALs |
| Firmware (17 of 18 images) | Xiaomi HyperOS 2 CN (byte-identical to the iqraOS 3.1 `firmware-update`); `abl` from beta4 |
| `boot` ramdisk (TWRP 3.7.1) | beta4 (梦归zzz, own build) |
| Face unlock (`facehal-rs`, SenseTime/Megvii libraries), pen-wake helper, charger shim | `pipa_core` / beta4 (梦归zzz) |
| Dolby library (`libhwdap.so`) | stock Xiaomi HyperOS 2 |
| MiSound | Xiaomi HyperOS (carried and changed by beta4) |
| 32-bit Adreno graphics driver | stock Xiaomi HyperOS |
| CPU power profile, panel colour data | stock Xiaomi HyperOS / pipa `vendor` |
| `libgrallocutils.so` (GCam HDR+ fix) | suga ([t.me/Megalodonzs](https://t.me/Megalodonzs)): a private PixelOS 17 test build for pipa (not public; only these 2 files, with suga's permission) |
| Game Space 10.44.6 | OPPO App Market |
| Play Store, Gboard, Google app, Gemini | Google (from Google Play) |
| Camera app (OppoCamera), pen library (`libxiaomipen.so`) | beta4 (camera based on Fossify Camera) |
| Port steps, `pipa_port` service, pipa helper, face crop / eye guard add-ons, overlays, SELinux | own work (this repository) |

**Tweaks and where the idea comes from**

Rule of the port: a fix should copy what stock OPPO or stock HyperOS does, not invent new behaviour.

| Tweak | Idea / model |
|---|---|
| Refresh rate rules, 144 Hz column, dark-mode idle guard | stock OPPO (donor `refresh_rate_config.xml`, `oplus_vrr_config.json`) |
| Refresh switch 300 ms after an animation | stock HyperOS |
| Memory: zram, nandswap, hybridswap RAM expansion | stock OPPO tablets; swappiness 100 tuned between OPPO (200) and HyperOS (180) by A/B tests |
| Pen only while connected over Bluetooth | stock HyperOS |
| Game Space "Ultra touch" and touch modes | OPPO touch API mapped to the Xiaomi touch game mode (HyperOS) |
| Dolby per output (Bluetooth "Original", speakers Dolby) | stock HyperOS |
| Speaker EQ | own measurement (pink noise, USB microphone) |
| Echo canceller for calls and voice chat | AOSP WebRTC AEC3 + AGC2 (`libaudiopreprocessing`) in an own wrapper HAL |
| Network location provider | stock OPPO (`com.oplus.location`) |
| Animations tier 3, blur | stock ColorOS features, unlocked for pipa; "Live blur" tile is an own option |
| Circle to Search on gesture bar long press, Gemini corner swipe | stock Pixel / Google behaviour |
| Per-app device identity (Netflix Widevine L1, Google Photos Pixel, games high FPS) | common community spoof methods; game FPS spoof requested by a tester |
| USB-C monitor density | Windows 125 % scaling (200 dpi at 1440p) |
| Display size Large (410) | same UI size as OnePlus Pad 3 / Pad 2 Pro |
| Graphics/HWUI build props | beta4 (aligned to AOSPA); HWUI split as on stock OPPO |
| OPPO perf and stability HALs | stock OPPO binaries (built from OPPO source for ColorOS 16 / Android 16; source phone unknown), from a community "C17 power-key fix" package (via beta4) |

**Kernel** (Linux 4.19, [kernel_xiaomi_pipa_cos17](https://github.com/Stefan-Atanasov/kernel_xiaomi_pipa_cos17))

| Part | From |
|---|---|
| Core kernel | LineageOS `android_kernel_xiaomi_sm8250` (`lineage-24.0`) |
| pipa device drivers | liyafe1997 `kernel_xiaomi_sm8250_mod` |
| Display and touch | kvsnr113 (E404R kernel) |
| UI First scheduler, Hans app freezer, hybridswap memory | OPPO open-source sm8250 kernel |
| Root | SukiSU Nova (SukiSU-Ultra team), susfs (simonpunk); KernelPatch (old KPM builds) |

**Tools**

- android-tools (`lpmake`, `lpunpack`, `simg2img`, `fastboot`, `adb`), smali/baksmali, apktool, `magiskboot` (Magisk), `avbtool`, Android NDK.
- offici5l `termux-adb-fastboot` (community method in [FLASH-WITHOUT-PC.md](FLASH-WITHOUT-PC.md)).

All trademarks and proprietary files belong to their owners.
