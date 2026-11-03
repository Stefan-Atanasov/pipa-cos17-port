# pipa HAL shims (step 4r)

Own Java code for OPPO HALs that pipa does not have. All shims run in **one** host process
(`pipa.hal.HalHost`): one ART runtime and one binder pool of at most 4 threads, so the RAM cost is that of one small
app_process. Build: `sh build.sh` (JDK 21, Android SDK platform `android-37.0`, build-tools `37.0.0`; set
`ANDROID_HOME`). Output: `port-rom/pipa_port/halshims.jar` (not in git, BLOBS.md).

| Key | Interface | What it does on pipa | Notes |
|---|---|---|---|
| `gameopt` | `vendor.oplus.hardware.gameopt.IGameOptHalService/default` V2 | Game key threads, GL thread and critical threads get sched_assist UX (`/proc/oplus_scheduler/sched_assist/ux_task`), as OPPO's HAL does. Bounded and always reset. | `notes/cloud/GAMEOPT.md`, `GAMEOPT-SHIM.md` |
| `panel` | `vendor.oplus.hardware.displaypanelfeature.IDisplayPanelFeature/default` V1 | Backlight values (ids 8, 29); probe ids "not supported"; accepted ids kept; -1 for the rest. | `notes/cloud/DISPLAY-HALS.md` part A |
| `misc` | `vendor.oplus.hardware.misc.IOplusMisc/default` V1 | Read-only; OPPO node flags only where pipa has the same node; no writes, no calibration saves. | `notes/cloud/MISC-SENSOR.md` part A |
| `touch` | `vendor.oplus.hardware.touch.IOplusTouch/default` V2 | The 4o touch shim (`maintainer/touchshim/TouchService.java`, built into this jar). Without `touch` in `HAL_SHIMS` the separate 4o host runs. | `maintainer/touchshim/README.md` |

Not merged on purpose: the cryptoeng shim (privacy password and app-lock records; a separate process keeps them
apart from the other shims). The charger shim has no source in this repository (BLOBS.md).

Not built, with the reason in the notes: `oplusSensor` (4q, no pipa data; never forward `setPhoneMode`), `transmessage`,
`handlefactory`, `cwb` (telemetry or OPPO-only hardware), `urcc` (encrypted OPPO policy; measure first).

Design rules:
- Wire protocol from the decoded stubs (codes, parcel order, version, hash). No donor classes or code.
- A call that pipa cannot serve gets the donor's own "unsupported" answer. Never a fake success that turns on an
  OPPO-only feature.
- Per-frame calls return at once without allocation. Logs are rate-limited (one line per key per minute).
- The registrar does not replace a name that already has a server.
- SELinux: `halshims.cil`, one service type for each name; the clients are the donor's client domains.

Start and stop: `pipa_port` `service.sh` (`HAL_SHIMS` in `config.prop`, for example `HAL_SHIMS=gameopt` or empty for
off). After 5 quick exits in a row the host is not started again (log `/data/local/tmp/halshims.log`).
