# Kernel

The port uses an own kernel, `walt-r5` (Linux 4.19.325). The source is in
https://github.com/Stefan-Atanasov/kernel_xiaomi_pipa_cos17.

## 1. Parts

| Part | Source |
|---|---|
| Core kernel (WALT scheduler, BPF, f2fs, memory, network, binder) | LineageOS `android_kernel_xiaomi_sm8250`, branch `lineage-24.0` |
| pipa device drivers | liyafe1997 `kernel_xiaomi_sm8250_mod` |
| Display and touch | E404R kernel |
| Root | SukiSU-Ultra (built in) and susfs 2.3.0 |
| OPPO UI First scheduler (`sched_assist`, frame boost) | OPPO open-source sm8250 kernel |

## 2. Branches

| Branch | Contents |
|---|---|
| `oppo` | The kernel that the port uses (with OPPO UI First). |
| `own` | The same kernel without the OPPO UI First code. |

## 3. Settings

| Setting | Default | Function |
|---|---|---|
| `kernel.ux_prefer_big` | 1 | UX UI threads start on the big CPU cores. 0 gives the OPPO behaviour (only during scrolling). |
| `kernel.frame_rate` | 120 | Frame rate for the UX frequency calculation. |
| `kernel.sched_assist_scene` | set by `pipa_port` | UI First scene. Bit 8 keeps SurfaceFlinger off the little cores. |

To change a setting until the next reboot, use root: `echo 0 > /proc/sys/kernel/ux_prefer_big`.

## 4. Requirements

- ROM beta5-2i or newer. Older ROMs do not have the SELinux rules for the UI First nodes.
- SukiSU-Ultra manager 4.2.1-r1.

## 5. Build

- Use the build script in the kernel repository. Refer to its `README.md`.
- To use the scripts in this repository, refer to [BUILD.md](BUILD.md), section 4.

WARNING: Pack the kernel only with `pack-boot.sh` (kernel repository) or `maintainer/kernel/mkboot.sh`. A
`magiskboot repack` alone changes the patch level, and the tablet does not boot.
