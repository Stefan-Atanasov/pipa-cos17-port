# Prompt for a new session

Paste the block below as the first message of a fresh Claude Code session started in `~/Documents/pipa/COS17`
(or `~`). Keep this file current when the plan changes.

```
Continue COS17 pipa maintenance (ColorOS 17 port for the Xiaomi Pad 6). Tablet on USB (serial 83836a90): ROM
beta5-2n + kernel walt-r5 on boot_b (rollbacks: flash_super.sh -y beta5-2m, bootimg/boot-walt-r4.img). My settings:
taskbar on + system material blur off. I have the Xiaomi pen, no keyboard.

Read first: COS17/CLAUDE.md, COS17/MAINTAINER-STATUS.md, COS17/BUILD-GUIDE.md, COS17/BUGS-TODO.md (table at the top),
COS17/kernel/KERNEL-RESEARCH.md (newest sections at the top of the dated list = 2026-10-24), HISTORY.md (last entries).
Rules: ask me for sudo password / PIN, never store them. ROM/kernel test flashes and rollbacks: go ahead, one line
what + rollback, tell me before rebooting. Short answers. Keep tool output small. Measure smoothness with
maintainer/perfetto/traced_heavy.sh (wait 60 s after unlock, >= 2 runs, `svc power stayon usb` during a series).

Published 2026-10-24: kernel source github.com/Stefan-Atanasov/kernel_xiaomi_pipa_cos17 (oppo), port repo
github.com/Stefan-Atanasov/pipa-cos17-port (sync_port_repo.sh), private kit make_port_kit.sh, release package
port-work/release/ColorOS17-Port-pipa-beta5-2n-20261024 (+ .7z).

Plan:
1. Clean-flash test of the release package (I run FlashLinux.sh with wipe), then I post it on Telegram.
2. Night drain on 2j+ (batterystats reset 2026-10-24 09:21, 75 %): /sys/power/system_sleep/stats, rpmh master_stats.
3. Optional ROM 2o: SELinux for OPPO's perf daemon + kernel binder ux_flag (KERNEL-RESEARCH "2026-10-24 late
   afternoon"; measured neutral so far). Phantom keyboard notification (BUGS-TODO 11).
4. Leftover bugs: B9 network sharing, B8 app lock, B1 Wi-Fi, B2 navbar, face crop_eyes, B11 idle refresh.
```
