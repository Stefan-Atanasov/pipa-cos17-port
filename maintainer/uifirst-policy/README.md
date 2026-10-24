# SELinux for OPPO's UI First proc nodes (ROM layer beta5-2i)

ColorOS 17 talks to the kernel's UI First interface through /proc/oplus_scheduler/sched_assist/* (ux_task,
ux_task_app, im_flag, im_flag_app), /proc/oplus_frame_boost/sys_ctrl and /proc/sys/fbg/*. The labels and rules
for these nodes live in OPPO's **vendor** policy, and we ship pipa's Xiaomi vendor, so without this block the
nodes are plain `proc` and system_server/apps get EACCES.

- `sa_rules.cil`: every line of the donor's (OPD2515 C.06) vendor_sepolicy.cil that mentions these types
  (vendor image taken from the donor payload.bin with `maintainer/payload_extract.py`).
- `gen_sa_policy.py sa_rules.cil <our cils>`: declares the types, keeps the genfscon lines of nodes our kernel
  has and the rules whose domain exists in our ROM + pipa vendor (`_202504` suffix dropped) -> `sa_block.cil`.
- `build_beta5_2i.sh` appends `sa_block.cil` to system_ext_sepolicy.cil (+ _debug).
Regenerate for a new donor: extract its vendor, grep the same types into sa_rules.cil, rerun the generator with
the new plat/system_ext cils and pipa's vendor cils.
