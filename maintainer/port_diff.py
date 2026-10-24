#!/usr/bin/env python3
"""Find what the port changed on the system side and carry it to a new donor build.

Trees are extracted partitions. A donor root holds system/, system_ext/, product/ and either
my_*/ next to them (separate donor partitions) or system/my_*/ (folded in, as the port does).
Every file is keyed by its on-device path (/system/..., /system_ext/..., /my_product/..., ...).

  port_diff.py changes OLD_DONOR PORT -o OUT
      exact port change list: OUT/port-changes.tsv (added / modified / removed vs the donor
      build the port was made from, OPD2515 17.0.0.102 C.05).

  port_diff.py rebase OLD_DONOR PORT NEW_DONOR -o OUT
      3-way: OUT/rebase.tsv, OUT/apply.sh (copies port files that are safe to carry, removes
      what the port removed) and OUT/conflicts/ (diff3 for text files changed on both sides).
      apply.sh only touches the work tree passed to it; review it before running.

Read-only on all input trees.
"""
import argparse, hashlib, os, shlex, subprocess, sys

PARTS = ("system", "system_ext", "product")
TEXT_EXT = (".prop", ".xml", ".rc", ".conf", ".cfg", ".txt", ".json", ".sh", ".cil", ".kl", ".idc")


def walk(root):
    """{device_path: (kind, digest_or_target, host_path)}"""
    out = {}
    root = os.path.abspath(root)

    def add_tree(base, prefix):
        for d, dirs, files in os.walk(base):
            rel = os.path.relpath(d, base)
            for name in files + [x for x in dirs if os.path.islink(os.path.join(d, x))]:
                hp = os.path.join(d, name)
                dp = os.path.normpath(os.path.join(prefix, rel, name))
                if os.path.islink(hp):
                    out[dp] = ("link", os.readlink(hp), hp)
                elif os.path.isfile(hp):
                    h = hashlib.md5()
                    with open(hp, "rb") as f:
                        for chunk in iter(lambda: f.read(1 << 20), b""):
                            h.update(chunk)
                    out[dp] = ("file", h.hexdigest(), hp)

    sysroot = os.path.join(root, "system")
    for entry in sorted(os.listdir(sysroot)):
        hp = os.path.join(sysroot, entry)
        if entry == "system":
            add_tree(hp, "/system")
        elif entry.startswith("my_") and os.path.isdir(hp) and not os.path.islink(hp):
            add_tree(hp, "/" + entry)
        elif os.path.isfile(hp) and not os.path.islink(hp):
            out["/" + entry] = ("file", hashlib.md5(open(hp, "rb").read()).hexdigest(), hp)
    for p in PARTS[1:]:
        if os.path.isdir(os.path.join(root, p)):
            add_tree(os.path.join(root, p), "/" + p)
    for entry in sorted(os.listdir(root)):
        if entry.startswith("my_") and os.path.isdir(os.path.join(root, entry)):
            add_tree(os.path.join(root, entry), "/" + entry)
    return out


def status(a, b, p):
    if p in a and p in b:
        return "same" if a[p][:2] == b[p][:2] else "modified"
    if p in b:
        return "added"
    return "removed" if p in a else "-"


def area(p):
    return "/".join(p.split("/")[:3])


def cmd_changes(args):
    old, port = walk(args.old_donor), walk(args.port)
    os.makedirs(args.out, exist_ok=True)
    counts = {}
    with open(os.path.join(args.out, "port-changes.tsv"), "w") as o:
        o.write("path\tstatus\tkind\n")
        for p in sorted(set(old) | set(port)):
            s = status(old, port, p)
            if s == "same":
                continue
            counts[s] = counts.get(s, 0) + 1
            o.write(f"{p}\t{s}\t{(port.get(p) or old.get(p))[0]}\n")
    print(counts)


def cmd_rebase(args):
    old, port, new = walk(args.old_donor), walk(args.port), walk(args.new_donor)
    os.makedirs(os.path.join(args.out, "conflicts"), exist_ok=True)
    rows, sh, counts = [], ["#!/bin/sh", "# usage: apply.sh <work tree = extracted NEW donor, my_* folded into system/>",
                          "set -eu", 'W="$1"'], {}

    def dest(p):
        """Shell word for p inside the work tree; my_* and root files live under system/."""
        top = p.split("/")[1]
        d = ("$W" if top in PARTS[1:] else "$W/system") + p
        return '"' + d.replace('\\', '\\\\').replace('"', '\\"').replace('`', '\\`') + '"'

    for p in sorted(set(old) | set(port) | set(new)):
        sp, sn = status(old, port, p), status(old, new, p)
        if sp in ("same", "-"):
            continue  # port did not touch it: the new donor's version wins
        if sp == "removed":
            action = "remove" if p in new else "already-gone"
            if action == "remove":
                sh.append(f"rm -f {dest(p)}")
        elif sn in ("same", "-") or (p in new and new[p][:2] == port[p][:2]):
            action = "carry"
            d = dest(p)
            sh.append(f'mkdir -p "$(dirname {d})"')
            if port[p][0] == "link":
                sh.append(f"ln -sfn {shlex.quote(port[p][1])} {d}")
            else:
                sh.append(f"cp -p {shlex.quote(port[p][2])} {d}")
        else:
            action = "CONFLICT"
            if p.endswith(TEXT_EXT) and all(p in t and t[p][0] == "file" for t in (old, port, new)):
                r = subprocess.run(["diff3", "-m", port[p][2], old[p][2], new[p][2]], capture_output=True)
                fn = p.strip("/").replace("/", "__") + ".diff3"
                with open(os.path.join(args.out, "conflicts", fn), "wb") as f:
                    f.write(r.stdout)
                action = "CONFLICT-text" if r.returncode else "MERGED-text"
                if r.returncode == 0:
                    merged = os.path.join(args.out, "conflicts", fn)
                    sh.append(f"cp {shlex.quote(os.path.abspath(merged))} {dest(p)}")
        counts[action] = counts.get(action, 0) + 1
        rows.append(f"{p}\tport:{sp}\tdonor:{sn}\t{action}")
    with open(os.path.join(args.out, "rebase.tsv"), "w") as o:
        o.write("path\tport_vs_old\tnew_vs_old\taction\n" + "\n".join(rows) + "\n")
    with open(os.path.join(args.out, "apply.sh"), "w") as o:
        o.write("\n".join(sh) + "\n")
    os.chmod(os.path.join(args.out, "apply.sh"), 0o755)
    print(counts)


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = ap.add_subparsers(dest="cmd", required=True)
    c = sub.add_parser("changes"); c.add_argument("old_donor"); c.add_argument("port")
    c.add_argument("-o", "--out", required=True); c.set_defaults(f=cmd_changes)
    r = sub.add_parser("rebase"); r.add_argument("old_donor"); r.add_argument("port"); r.add_argument("new_donor")
    r.add_argument("-o", "--out", required=True); r.set_defaults(f=cmd_rebase)
    a = ap.parse_args()
    a.f(a)


if __name__ == "__main__":
    sys.exit(main())
