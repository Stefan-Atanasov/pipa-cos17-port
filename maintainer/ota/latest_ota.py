#!/usr/bin/env python3
"""Write the "ota" block of docs/latest.json (Pipa Helper 3.6, step 9h, BUGS 193).

  python3 -I maintainer/ota/latest_ota.py [--into docs/latest.json] \
      --payload pt166 URL [URL ...] --payload pt166-from-pt165 URL [URL ...]

Each --payload is a folder port-work/ota/<name>/ from make_payload.sh (ota-<name>.txt: offset, size, headers) and its
mirror URLs (https, any order: the helper sorts them by a speed probe). "<tag>-from-<old>" = delta from build <old>.
Every URL is checked first: a range request at the payload offset must give 206 and the payload magic "CrAU", and
the file must end where the payload ends (zip size check on the last bytes). A failed check stops the script: no
latest.json with a dead mirror. Without --into, the block goes to stdout.
"""
import argparse, json, os, re, sys, urllib.request

HERE = os.path.dirname(os.path.abspath(__file__))
OTA = os.path.normpath(os.path.join(HERE, "../../../port-work/ota"))


def ranged(url, a, b):
    r = urllib.request.Request(url, headers={"User-Agent": "PipaHelper", "Range": "bytes=%d-%d" % (a, b)})
    with urllib.request.urlopen(r, timeout=30) as f:
        return f.status, f.read(b - a + 1)


def payload(name, urls):
    t = os.path.join(OTA, name, "ota-%s.txt" % name)
    kv = dict(l.split("=", 1) for l in open(t).read().splitlines() if "=" in l)
    off, size = int(kv["offset"]), int(kv["size"])
    headers = kv["headers"].replace("\\n", "\n")
    if not re.search(r"^FILE_HASH=", headers, re.M) or "FILE_SIZE=%d" % size not in headers:
        sys.exit("%s: headers do not match the size" % name)
    for u in urls:
        if not u.startswith("https://") or re.search(r"[|^ ]", u):
            sys.exit("%s: bad url %s" % (name, u))
        st, d = ranged(u, off, off + 3)
        if st != 206 or d != b"CrAU":
            sys.exit("%s: %s gives %s %r, not 206 CrAU" % (name, u, st, d))
        st, d = ranged(u, off + size - 4, off + size - 1)
        if st != 206 or len(d) != 4:
            sys.exit("%s: %s: payload end not readable (%s)" % (name, u, st))
        print("ok  %-22s %s" % (name, u.split("/")[2]), file=sys.stderr)
    p = {"offset": off, "size": size, "headers": headers, "urls": urls}
    m = re.fullmatch(r"(.+)-from-(.+)", name)
    if m:
        p = {"from": m.group(2), **p}
    return p


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--into")
    ap.add_argument("--payload", nargs="+", action="append", required=True, metavar="NAME URL")
    a = ap.parse_args()
    ps = []
    for g in a.payload:
        if len(g) < 2:
            sys.exit("--payload needs a name and at least one url")
        ps.append(payload(g[0], g[1:]))
    if not any("from" not in p for p in ps):
        sys.exit("no full payload: a tablet on another build would get no update")
    ota = {"payloads": sorted(ps, key=lambda p: "from" not in p)}
    if a.into:
        j = json.load(open(a.into))
        j["ota"] = ota
        with open(a.into, "w") as f:
            json.dump(j, f, indent=2)
            f.write("\n")
        print("wrote %s: %d payload(s)" % (a.into, len(ps)), file=sys.stderr)
    else:
        print(json.dumps({"ota": ota}, indent=2))


main()
