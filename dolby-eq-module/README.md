# pipa Dolby speaker EQ module (v1.0)

KernelSU / SukiSU / APatch / Magisk module with the measured speaker EQ of step 6a (`maintainer/dolby-eq/`).
For the Xiaomi Pad 6 (pipa) on a ROM with the **stock HyperOS 2 Dolby tuning file**
(`/vendor/etc/dolby/dax-default.xml`, md5 `582003e70df30be8964df17610212ef3`): ColorOS 17 port beta7.1 / beta7.2,
stock HyperOS 2, and other ROMs with that vendor file. The port from beta8 has the EQ built in (the module refuses).

- `post-fs-data.sh` bind-mounts the EQ file (no KernelSU metamodule needed), only over the stock file.
- After install and after removal, Dolby rebuilds its database once: Dolby settings and the GEQ reset one time.
- Only the 4 speaker tunings change. Headphones, Bluetooth and USB keep the stock sound.
- Build: zip the contents of `src/` at the archive root (Python `zipfile`). The public repo has no `src/dax-default.xml`
  (vendor file): make it with `maintainer/dolby-eq/apply_speaker_eq.py` from the stock HyperOS 2 file.
- Tested 2026-11-07 on pt81 with the stock file bind-mounted (simulated beta7.2): install OK, bind mount OK
  (md5 `c6413875…`), refuse on pt81 OK. Not yet tested with a real reboot on beta7.x.
