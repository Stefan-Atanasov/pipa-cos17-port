# Known issues

This document lists the open problems of the current build. Each entry gives the symptom, a workaround if
there is one, and the status.

## For users

| Problem | Symptom | Workaround | Status |
|---|---|---|---|
| Network sharing (interconnect) | Call and SMS sharing with a phone does not work. | None. | Open. Logs from the phone are necessary. |
| Privacy password and app lock | The privacy password and the ColorOS app lock do not work. | None. | Open. The OPPO `ICryptoeng` HAL is not available. |
| Wi-Fi start | Wi-Fi sometimes does not turn on. | Reboot the tablet. | Open. No recovery path in the driver configuration. |
| Navigation bar | Some apps draw a part of the screen behind the navigation bar. | None. | Open. |
| Idle refresh rate | The refresh rate stays at 120 Hz on a static screen. | None. | Open. A display panel HAL shim is necessary. |
| Face enrollment | Enrollment can stop near the edge of the camera frame. | Try again with the face in the centre. | Open. |
| Keyboard notification | A "Xiaomi Keyboard configured" notification shows without a keyboard. | Turn off the "Physical keyboard" notifications. | Open. The keyboard driver makes its input devices at start. |
| Pen page | Settings → Stylus (OPPO pen page) shows the Xiaomi pen as "disconnected". | None necessary: the pen works (drawing, buttons, 120 Hz, battery in the live alert). | By design. The page shows the state of the OPPO pen link. |
| Pen capsule at boot | The pen battery capsule can show 2-3 times after a boot. | None. | Open. |
| Keyboard case | The auto-off when you fold the keyboard behind the tablet is not tested. | Typing works. | Not tested. |
| Play Integrity | Only BASIC integrity (unlocked bootloader). Apps that need DEVICE integrity do not work. | None. | By design. |
| Adaptive colour | Adaptive colour uses only the colour temperature sensor. | None. | Open. The ambient light value is not connected. |
| Material blur | With "Material blur" on, the launcher animations are less smooth. | Turn "Material blur" off: `adb shell settings put system system_material_blur_enable 0`. | Hardware limit. |

## For maintainers

| Item | Status |
|---|---|
| Clean flash of the release package | Not tested. Only dirty upgrades from beta4 are tested. |
| `pipa_port` SELinux domain | Permissive. The rules are not collected. |
| Colour and adaptive restore | A script in `pipa_port`. The app that resets the values is not patched. |
| OPPO performance service (`vendor-oplus-hardware-performance-V1-service`) | SELinux blocks its read of `/proc/version`, so it does not know the kernel paths. A live fix works but gave no measured gain. Not in the ROM. |
| `/proc/oplus_binder/ux_flag` | Not in the kernel. ColorOS cannot pass UX through binder calls. |
