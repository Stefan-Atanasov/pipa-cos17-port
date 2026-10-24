#!/usr/bin/env python3
"""Apply the curated port edits (PORT-EDITS.tsv) to a root-extracted donor work tree.

  sudo python3 -I apply_port_edits.py EDITS.tsv BETA4_SRC WORK_TREE

BETA4_SRC and WORK_TREE both have system/ (system-as-root, my_* folded in) and system_ext/, as
produced by `fsck.erofs --extract --xattrs --preserve`. Run as root so SELinux xattrs and
ownership are copied. Content written over an existing file keeps that file's inode, label and
owner. New files and directories are copied from beta4 with cp -a, which keeps beta4's labels.
"""
import os, re, shutil, subprocess, sys

edits, B, W = sys.argv[1:4]


def host(root, p):
    top = p.split("/")[1]
    return os.path.join(root, p.lstrip("/")) if top == "system_ext" else os.path.join(root, "system", p.lstrip("/"))


def log(*a):
    print(*a, flush=True)


def carry(p):
    """Copy p from beta4, bringing its highest missing ancestor directory along (labels included)."""
    src, dst = host(B, p), host(W, p)
    cur_src, cur_dst = src, dst
    while not os.path.exists(os.path.dirname(cur_dst)):
        cur_src, cur_dst = os.path.dirname(cur_src), os.path.dirname(cur_dst)
    if os.path.exists(cur_dst) and cur_dst != dst:
        cur_src, cur_dst = src, dst
    if os.path.isdir(cur_src):
        subprocess.run(["cp", "-a", cur_src, os.path.dirname(cur_dst) + "/"], check=True)
    else:
        if os.path.exists(cur_dst):
            os.remove(cur_dst)
        subprocess.run(["cp", "-a", cur_src, cur_dst], check=True)
    log("carry   ", p, "" if cur_dst == dst else f"(with dir {cur_dst[len(W):]})")


def overwrite(p, data, mode=None):
    with open(host(W, p), "w", encoding="utf-8") as f:  # same inode: label/owner kept
        f.write(data)
    if mode is not None:
        os.chmod(host(W, p), mode)


def read(root, p):
    return open(host(root, p), encoding="utf-8", errors="surrogateescape").read()


def prop_merge(p, churn, mode=None):
    """beta4 file as the base; churn keys take the donor's value; donor keys beta4 lacks
    (and did not comment out) are appended."""
    donor, port = read(W, p), read(B, p)
    dv = {}
    for l in donor.splitlines():
        m = re.match(r"^([^#=\s][^=]*)=(.*)$", l)
        if m:
            dv[m[1]] = m[2]
    out, seen = [], set()
    for l in port.splitlines():
        m = re.match(r"^([^#=\s][^=]*)=(.*)$", l)
        if m:
            seen.add(m[1])
            if re.search(churn, m[1]) and m[1] in dv and dv[m[1]] != m[2]:
                l = f"{m[1]}={dv[m[1]]}"
        else:
            m2 = re.match(r"^#\s*([^#=\s][^=]*)=", l)
            if m2:
                seen.add(m2[1])
        out.append(l)
    extra = [f"{k}={v}" for k, v in dv.items() if k not in seen]
    if extra:
        out += ["", "# ---- from the donor build, not present in beta4 ----"] + extra
    overwrite(p, "\n".join(out) + "\n", mode)
    log("props   ", p, f"({len(extra)} donor keys appended)")


def append_from_marker(p, marker):
    port = read(B, p).splitlines()
    i = next(k for k, l in enumerate(port) if marker in l)
    donor = read(W, p).rstrip("\n").splitlines()
    overwrite(p, "\n".join(donor + [""] + port[i:]) + "\n")
    log("append  ", p, f"({len(port) - i} lines from beta4)")


rows = [(l.split("\t") + ["", "", ""])[:4] for l in open(edits, encoding="utf-8").read().splitlines()[1:] if l.strip()]
for p, action, cls, note in rows:
    if action == "carry":
        carry(p)
    elif action in ("remove", "remove?"):
        t = host(W, p)
        if os.path.isdir(t) and not os.path.islink(t):
            shutil.rmtree(t)
        elif os.path.lexists(t):
            os.remove(t)
        else:
            log("absent  ", p)
            continue
        log("remove  ", p)
    elif action == "DROP":
        log("skip    ", p, "(DROP)")
    elif action == "re-derive":
        if p.endswith("oplus-services.jar"):
            log("keep    ", p, "(donor jar; port edits not re-derived yet)")
        else:
            shutil.copyfile(host(B, p), host(W, p))
            log("beta4   ", p, "(port-modified overlay, copied as-is)")
    elif p == "/system/build.prop":
        prop_merge(p, r"(\.date(\.utc)?|\.uuid|\.incremental|\.host|\.description|\.fingerprint|image\.system\.version)$", 0o644)
    elif p == "/my_product/build.prop":
        prop_merge(p, r"(image\.my_product\.(date(\.utc)?|version)|^ro\.build\.version\.ota)$")
    elif p == "/my_manifest/build.prop":
        # keep beta4 fingerprints/incrementals/dates: they must match the (unchanged) vendor
        prop_merge(p, r"^(ro\.oplus\.version\.|ro\.build\.display\.id|ro\.build\.version\.ota|ro\.build\.display\.ota)")
    elif p.endswith("_sepolicy.cil") or p.endswith("_sepolicy_debug.cil"):
        append_from_marker(p, "pipa port: SELinux enforcing bring-up")
    elif p == "/my_stock/applist/applist.txt":
        keep = set(read(B, p).splitlines())
        lines = read(W, p).splitlines()
        overwrite(p, "\n".join(l for l in lines if l in keep or not l.strip()) + "\n")
        log("filter  ", p, f"({sum(1 for l in lines if l not in keep)} debloated entries dropped)")
    elif action in ("re-apply", "re-apply?"):
        # the remaining text edits: beta4 == donor + port edit (checked in text-diffs.txt)
        shutil.copyfile(host(B, p), host(W, p))
        log("beta4   ", p)
    else:
        sys.exit(f"unhandled row: {p} {action}")
