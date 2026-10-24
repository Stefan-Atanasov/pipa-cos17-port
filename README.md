# ColorOS 17 port for Xiaomi Pad 6 (pipa): build scripts and sources

Maintained by Stefan-Atanasov since 2026-10-22; the port was created by 梦归zzz (beta4, 2026-10-17). This repo holds
everything needed to rebuild the ROM from the original beta4 release and an OPPO OPD2515 donor build: the layered
build scripts (`maintainer/build_beta5*.sh`, `build_port.sh`), the port's runtime (`port-rom/`: pipa_port service,
init rc), the pipa helper app source (`helper/`), the older module and its tools (`module/`, used by the baked step),
the UI First SELinux policy, test and analysis tools (`maintainer/heavy_mix.sh`, `maintainer/perfetto/`) and the docs.

* **Start here:** [`BUILD-GUIDE.md`](BUILD-GUIDE.md) (build, test, flash, roll back ROM and kernel), then
  [`MAINTAINER-STATUS.md`](MAINTAINER-STATUS.md), [`PORT-MAINTAINER.md`](PORT-MAINTAINER.md) (rebase on a new donor),
  [`BUGS-TODO.md`](BUGS-TODO.md), [`RELEASE-NOTES-beta5.md`](RELEASE-NOTES-beta5.md), the original audit [`AUDIT.md`](AUDIT.md). Why each fix exists:
  [`kernel/KERNEL-RESEARCH.md`](kernel/KERNEL-RESEARCH.md), [`HISTORY.md`](HISTORY.md), `module/README.md`.
* **Kernel:** https://github.com/Stefan-Atanasov/kernel_xiaomi_pipa_cos17 (branch `oppo`).
* **Not in this repo:** proprietary binaries (see [`BLOBS.md`](BLOBS.md)), images, donor files, the signing key of
  the pipa helper (`helper/build.sh` creates your own on first run).
* Paths default to `/home/stefan/Documents/pipa`; set `PIPA_ROOT` (folder holding `COS17/`, `port-work/`, `donor/`)
  and `PIPA_OWNER` (user:group), e.g. `sudo PIPA_ROOT=$PWD PIPA_OWNER=$USER:$USER sh COS17/maintainer/build_port.sh ...`.
  Clone this repo as `COS17/` inside `PIPA_ROOT`.

The ROM itself is distributed as a release package (fastboot flash scripts + firmware + super + boot), not here.
