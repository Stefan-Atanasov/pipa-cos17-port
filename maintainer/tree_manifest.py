#!/usr/bin/env python3
"""Print one line per entry of a tree: path, type, mode, uid, gid, md5 or link target, xattrs.
Ignores timestamps. Run as root so security.* xattrs and every file are readable."""
import hashlib, os, stat, sys

root = os.path.abspath(sys.argv[1])


def xattrs(p):
    try:
        names = sorted(os.listxattr(p, follow_symlinks=False))
    except OSError:
        return "-"
    return ";".join(f"{n}={os.getxattr(p, n, follow_symlinks=False).hex()}" for n in names) or "-"


def line(p):
    st = os.lstat(p)
    if stat.S_ISLNK(st.st_mode):
        kind, data = "l", os.readlink(p)
    elif stat.S_ISREG(st.st_mode):
        h = hashlib.md5()
        with open(p, "rb") as f:
            for chunk in iter(lambda: f.read(1 << 20), b""):
                h.update(chunk)
        kind, data = "f", h.hexdigest()
    elif stat.S_ISDIR(st.st_mode):
        kind, data = "d", "-"
    else:
        kind, data = "o", str(st.st_rdev)
    rel = "/" + os.path.relpath(p, root) if p != root else "/"
    return f"{rel}\t{kind}\t{stat.S_IMODE(st.st_mode):o}\t{st.st_uid}\t{st.st_gid}\t{data}\t{xattrs(p)}"


print(line(root))
for d, dirs, files in os.walk(root):  # os.walk does not follow directory symlinks
    dirs.sort()
    for name in sorted(dirs + files):
        print(line(os.path.join(d, name)))
