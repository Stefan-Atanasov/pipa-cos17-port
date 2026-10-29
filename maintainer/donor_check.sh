#!/bin/bash
# Check a new OPPO donor before you build the port. Keep the inputs read-only.
# Usage: sudo bash donor_check.sh OLD_IMG_DIR NEW_IMG_DIR [OUT_DIR]
# Use --image-only before the paths to check images without extraction.
# This mode checks touched files, md5 gates, text files and SurfaceFlinger.
# It cannot scan all native libraries or all changed dex files.
# The full run needs 30 GiB free before each partition extraction.
# Read report.md first. Then read the TSV files that it names.
set -euo pipefail
export LC_ALL=C

usage() {
    echo "Usage: bash $0 [--image-only] <old-donor-img-dir> <new-donor-img-dir> [out-dir]"
}
mode=full
if [[ ${1:-} == --help || ${1:-} == -h ]]; then usage; exit 0; fi
if [[ ${1:-} == --image-only ]]; then mode=image-only; shift; fi
if (( $# < 2 || $# > 3 )); then usage >&2; exit 2; fi
here=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
out=${3:-/home/stefan/Documents/pipa/port-work/donor-check/$(basename -- "$2")}
command -v python3 >/dev/null || { echo 'ERROR: Install python3.' >&2; exit 1; }
# -B prevents import of port_diff.py from writing into the source folder.
python3 -B - "$here" "$1" "$2" "$out" "$mode" <<'PY'
import collections
import csv
import difflib
import fnmatch
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import re
import shlex
import shutil
import subprocess
import sys

HERE, OLD, NEW, OUT = (Path(p).resolve() for p in sys.argv[1:5])
MODE = sys.argv[5]
sys.dont_write_bytecode = True
warnings = []


def say(s):
    print(s, flush=True)


def fail(s):
    raise RuntimeError(s)


def inside(p, root):
    return p == root or root in p.parents


def write_tsv(name, header, rows):
    with (OUT / name).open('w', newline='') as f:
        w = csv.writer(f, delimiter='\t', lineterminator='\n')
        w.writerow(header)
        w.writerows(rows)


def free_space():
    r = subprocess.run(['df', '-Pk', str(OUT)], check=True, capture_output=True, text=True)
    free = int(r.stdout.splitlines()[-1].split()[3]) * 1024
    say(f'Free space at {OUT}: {free / 2**30:.2f} GiB')
    return free


def image_set(root):
    return {p.stem: p for p in sorted(root.glob('*.img'))
            if p.stem in ('system', 'system_ext', 'product') or p.stem.startswith('my_')}


def fingerprint(p):
    st = p.stat()
    return [str(p.resolve()), st.st_size, st.st_mtime_ns, st.st_ino]


def extract(images, label):
    root = OUT / label
    root.mkdir(exist_ok=True)
    for part, image in images.items():
        dest = root / part
        marker = root / ('.' + part + '.complete.json')
        signature = fingerprint(image)
        if marker.exists() and dest.is_dir():
            if json.loads(marker.read_text()) != signature:
                fail(f'{dest}: Image changed. Use a new output directory.')
            say(f'Reuse extracted partition: {label}/{part}')
            continue
        if dest.exists():
            fail(f'{dest}: No completion marker. Use a new output directory or remove this incomplete tree.')
        if free_space() < 30 * 2**30:
            fail('Less than 30 GiB free. Stop before extraction.')
        say(f'Extract {label}/{part}')
        with (OUT / f'extract-{label}-{part}.log').open('wb') as log:
            subprocess.run(['fsck.erofs', '--extract=' + str(dest), str(image)],
                           stdout=log, stderr=subprocess.STDOUT, check=True)
        marker.write_text(json.dumps(signature) + '\n')
    return root


def load_port_diff():
    spec = importlib.util.spec_from_file_location('port_diff', HERE / 'port_diff.py')
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def partition(path):
    top = path.strip('/').split('/')[0]
    # Ramdisk root symlinks such as /product still belong to system.img.
    return top if top in parts and '/' in path.strip('/') else 'system'


def normalize(path):
    path = path.strip('"\'').rstrip('/')
    if '/tree/' in path:
        path = path.split('/tree/', 1)[1]
    path = path.lstrip('/')
    if path == 'system/system':
        path = 'system'
    elif path.startswith('system/system/'):
        path = path[len('system/'):]
    elif path.startswith('system/my_'):
        path = path[len('system/'):]
    return '/' + path


# Do not source build scripts. Expand literal shell assignments and finite loops only.
# Keep source lines and unresolved expressions so a new script cannot silently lose a gate.
VAR = re.compile(r'\$\{([A-Za-z_]\w*)\}|\$([A-Za-z_]\w*)')
PATH = re.compile(r'(?<![\w.-])(?:[^\s"\'<>|;(){}=,]*?/tree/)?'
                  r'(?:system_ext|system|product|my_[\w]+|vendor|odm)/'
                  r'[A-Za-z0-9_./@+*?${}\[\]-]+')
HEX = re.compile(r'(?<![0-9a-fA-F])[0-9a-fA-F]{32}(?![0-9a-fA-F])')


def expand(text, env):
    values = [text]
    for _ in range(12):
        new = []
        for value in values:
            m = next((m for m in VAR.finditer(value) if (m[1] or m[2]) in env), None)
            if m:
                for sub in env[m[1] or m[2]]:
                    new.append(value[:m.start()] + sub + value[m.end():])
            else:
                new.append(value)
        new = list(dict.fromkeys(new))
        if len(new) > 4096:
            fail('Static shell expansion exceeds 4096 variants. Review the new layer script.')
        if new == values:
            return new
        values = new
    return values


def words(text):
    try:
        return shlex.split(text, comments=True)
    except ValueError:
        return text.split()


def found_paths(text):
    # Shell words may join quoted and unquoted pieces: "$S/framework/oat"/*/x.*.
    text = text.replace('"', '').replace("'", '')
    return list(dict.fromkeys(normalize(m[0]) for m in PATH.finditer(text)))


def discover():
    touched = collections.defaultdict(set)
    port_actions = {}
    gates, sources, calls = [], [], collections.defaultdict(set)
    edits = HERE / 'c06-vs-beta4/PORT-EDITS.tsv'
    with edits.open() as f:
        for row in csv.DictReader(f, delimiter='\t'):
            touched[row['path']].add('PORT-EDITS.tsv')
            port_actions[row['path']] = row['action']
    scripts = sorted(HERE.glob('build_beta5*.sh'))
    if not scripts:
        fail('No build_beta5*.sh layer scripts found.')
    for script in scripts:
        env = {'W': ['@WORK@'], 'HERE': [str(HERE)]}
        last_md5 = ''
        last_input = ''
        # Join shell continuations, but retain the first physical line number.
        lines = []
        buf, start = '', 1
        for n, raw in enumerate(script.read_text().splitlines(), 1):
            if not buf:
                start = n
            buf += raw.rstrip('\\') if raw.endswith('\\') else raw
            if raw.endswith('\\'):
                buf += ' '
                continue
            lines.append((start, buf))
            buf = ''
        functions, body_lines = {}, set()
        current = None
        for n, line in lines:
            definition = re.match(r'^(\w+)\(\)\s*\{', line)
            if definition:
                current = definition[1]
                functions[current] = []
                body_lines.add(n)
            elif current:
                body_lines.add(n)
                if line == '}':
                    current = None
                else:
                    functions[current].append(line)
        for n, line in lines:
            if line.lstrip().startswith('#') or n in body_lines:
                continue
            src = f'{script.name}:{n}'
            loop = re.search(r'\bfor\s+(\w+)\s+in\s+(.*?);?\s*do\b', line)
            if loop:
                vals = [w for v in expand(loop[2].rstrip('; '), env) for w in words(v)]
                if vals:
                    env[loop[1]] = vals
            assignment = re.match(r'\s*([A-Za-z_]\w*)=("[^"]*"|\x27[^\x27]*\x27|[^\s;]+)', line)
            if assignment and assignment[1] not in ('W', 'HERE'):
                value = assignment[2].strip('"\'')
                if not value.startswith('$('):
                    env[assignment[1]] = expand(value, env)
            variants = expand(line, env)
            for value in variants:
                tokens = words(value)
                function_paths = []
                if tokens and tokens[0] in functions:
                    body = '\n'.join(functions[tokens[0]])
                    body = re.sub(r'\$\{?(\d+)\}?',
                                  lambda m: tokens[int(m[1])] if int(m[1]) < len(tokens) else m[0], body)
                    function_paths = [p for v in expand(body, env) for p in found_paths(v)]
                paths = found_paths(value) + function_paths
                for path in paths:
                    if path.count('/') >= 2 and path.split('/')[1] not in ('vendor', 'odm'):
                        touched[path].add(src)
                sources.append((src, value))
                # Link a tool's md5 constant to its input at the layer call site.
                for i, token in enumerate(tokens):
                    if token.endswith(('.py', '.sh')) and i + 1 < len(tokens):
                        arg = tokens[i + 1]
                        if not arg.startswith('-'):
                            calls[Path(token).name].add(arg)
                if line.lstrip().startswith('bake '):
                    tok = words(value)
                    if len(tok) >= 5 and HEX.fullmatch(tok[3]):
                        gates.append((src, normalize(tok[1]), tok[3].lower(), 'input'))
                        gates.append((src, tok[2], tok[4].lower(), 'generated-copy'))
                    continue
                md = re.search(r'md5sum\s+(?:<\s*)?("[^"]+"|\x27[^\x27]+\x27|[^\s|)]+)', value)
                if md:
                    last_md5 = md[1].strip('"\'')
                if 'python3' in value and "<<" in value:
                    # Inline Python receives the path on its command line.
                    before = value.split('<<', 1)[0]
                    candidates = found_paths(before)
                    if candidates:
                        last_input = candidates[-1]
                expected = HEX.findall(value)
                if expected and ('=' in value) and ('md5sum' in value or
                        re.search(r'\[\s*["\x27]?\$?(?:md5|have)\b', line)):
                    for digest in expected:
                        gates.append((src, last_md5 or 'UNRESOLVED', digest.lower(),
                                      'output' if 'patched' in value or 'unexpected jar' in value else 'input'))
                elif expected and 'hashlib.md5' in value and ('==' in value or '!=' in value):
                    gates.append((src, last_input or 'UNRESOLVED', expected[0].lower(), 'input'))
                # Computed (nonliteral) gates must also appear in the inventory.
                if re.search(r'\[.*md5sum.*\s=\s', line) and not expected:
                    gates.append((src, last_md5 or 'UNRESOLVED', 'DYNAMIC', 'local-copy'))
    for tool in sorted((HERE.parent / 'module/tools').glob('*')):
        if tool.suffix not in ('.py', '.sh'):
            continue
        text = tool.read_text()
        for n, line in enumerate(text.splitlines(), 1):
            m = re.match(r'\s*(?:STOCK_MD5|MD5_IN|[A-Z_]*MD5)\s*=\s*["\x27]([0-9a-fA-F]{32})', line)
            if m:
                # A tool may be used outside the layer chain. Its usage text can name its input.
                documented = {p for p in found_paths(text) if p.startswith(('/vendor/', '/odm/'))
                              and p.endswith(('.so', '.xml'))}
                for target in sorted(calls.get(tool.name) or documented or {'UNRESOLVED'}):
                    gates.append((f'module/tools/{tool.name}:{n}', target, m[1].lower(), 'input'))
            elif HEX.search(line) and 'hashlib.md5' in line and re.search(r'==|!=', line):
                for target in sorted(calls.get(tool.name) or {'UNRESOLVED'}):
                    gates.append((f'module/tools/{tool.name}:{n}', target, HEX.search(line)[0].lower(), 'input'))
    for src, target, digest, stage in gates:
        if '/tree/' in target or target.startswith(('/system/', '/system_ext/', '/product/', '/my_')):
            touched[normalize(target)].add(src)
    write_tsv('source-paths.tsv', ['source', 'expanded_line'], sources)
    return touched, list(dict.fromkeys(gates)), port_actions


class Images:
    """Read selected EROFS files. Do not extract a partition or follow donor symlinks."""
    def __init__(self, images):
        self.images = images
        self.lists = {}
        self.records = {}

    def location(self, path):
        top, _, tail = path.lstrip('/').partition('/')
        if top in self.images and top != 'system':
            return top, '/' + tail
        if top in ('vendor', 'odm'):
            return top, '/' + tail
        return 'system', path

    def listing(self, part, path):
        key = (part, path)
        if key in self.lists:
            return self.lists[key]
        if part not in self.images:
            return {}
        r = subprocess.run(['dump.erofs', '--ls', '--path=' + path, str(self.images[part])],
                           capture_output=True, text=True)
        if r.returncode:
            fail(f'Cannot list {part}:{path}: {r.stderr.strip()}')
        entries = {}
        for line in r.stdout.splitlines():
            m = re.match(r'\s*\d+\s+(\d+)\s+(.*)$', line)
            if m and m[2] not in ('.', '..'):
                entries[m[2]] = int(m[1])
        self.lists[key] = entries
        return entries

    def kind(self, path):
        part, internal = self.location(path)
        if part not in self.images:
            return None
        parent, _, name = internal.rpartition('/')
        current = '/'
        for element in parent.strip('/').split('/'):
            if not element:
                continue
            if self.listing(part, current).get(element) != 2:
                return None
            current = current.rstrip('/') + '/' + element
        return self.listing(part, parent or '/').get(name)

    def data(self, path):
        if self.kind(path) != 1:
            return None
        part, internal = self.location(path)
        r = subprocess.run(['dump.erofs', '--cat', '--path=' + internal, str(self.images[part])],
                           capture_output=True, check=True)
        return r.stdout

    def record(self, path):
        if path not in self.records:
            kind = self.kind(path)
            if kind == 1:
                self.records[path] = ('file', hashlib.md5(self.data(path)).hexdigest(), path)
            elif kind == 7:
                part, internal = self.location(path)
                r = subprocess.run(['dump.erofs', '--cat', '--path=' + internal, str(self.images[part])],
                                   check=True, capture_output=True)
                self.records[path] = ('link', r.stdout.decode(errors='replace'), path)
            else:
                self.records[path] = None
        return self.records[path]

    def tree(self, path):
        if self.kind(path) == 2:
            part, internal = self.location(path)
            for name in self.listing(part, internal):
                yield from self.tree(path.rstrip('/') + '/' + name)
        elif self.kind(path) in (1, 7):
            yield path


class Tree:
    def __init__(self, root, module):
        say(f'Hash files with port_diff.py: {root}')
        if not (root / 'system/system').is_dir():
            fail(f'{root}/system: Expected a system-as-root image with a system/ directory.')
        self.records = module.walk(str(root))
        # port_diff.walk indexes the OS trees. Also include ramdisk symlinks and files
        # in other ramdisk directories. Do not hash the OS trees a second time.
        for p in (root / 'system').iterdir():
            if p.is_symlink():
                self.records['/' + p.name] = ('link', os.readlink(p), str(p))
            elif p.is_dir() and p.name != 'system' and not p.name.startswith('my_'):
                for directory, dirs, files in os.walk(p):
                    for name in files + [n for n in dirs if (Path(directory) / n).is_symlink()]:
                        hp = Path(directory) / name
                        dp = '/' + str(hp.relative_to(root / 'system'))
                        if hp.is_symlink():
                            self.records[dp] = ('link', os.readlink(hp), str(hp))
                        elif hp.is_file():
                            digest = hashlib.md5()
                            with hp.open('rb') as f:
                                for chunk in iter(lambda: f.read(1 << 20), b''):
                                    digest.update(chunk)
                            self.records[dp] = ('file', digest.hexdigest(), str(hp))

    def record(self, path):
        return self.records.get(path)

    def data(self, path):
        rec = self.record(path)
        return Path(rec[2]).read_bytes() if rec and rec[0] == 'file' else None


def change(path):
    a, b = old.record(path), new.record(path)
    status = portdiff.status({path: a} if a else {}, {path: b} if b else {}, path)
    return {'same': 'unchanged', 'modified': 'changed', '-': 'absent-both'}.get(status, status)


def critical(path):
    if path.startswith(('/system/etc/selinux/', '/system_ext/etc/selinux/')):
        return 'sepolicy'
    if '/etc/vintf/' in path or re.search(r'/(?:manifest|compatibility_matrix)[^/]*\.xml$', path):
        return 'vintf'
    if path.endswith('.rc'):
        return 'init'
    return None


def critical_image_paths(reader):
    for part in reader.images:
        prefix = '/' + part
        for directory in ('/etc/selinux', '/etc/vintf', '/etc/init', '/etc/init/hw'):
            if 'selinux' in directory and part not in ('system', 'system_ext'):
                continue
            yield from reader.tree(prefix + directory)
        # Include init rc files outside etc/init (including the ramdisk root).
        imgpart, internal = reader.location(prefix + '/dummy')
        internal = internal.rsplit('/', 1)[0] or '/'
        for name, kind in reader.listing(imgpart, internal).items():
            if name.endswith('.rc') and kind == 1:
                yield prefix + '/' + name
    for name, kind in reader.listing('system', '/').items():
        if name.endswith('.rc') and kind == 1:
            yield '/' + name


def properties(data):
    result = {}
    for raw in (data or b'').decode('utf-8', errors='replace').splitlines():
        if '=' in raw and not raw.lstrip().startswith('#'):
            k, v = raw.split('=', 1)
            result[k.strip()] = v.strip()  # Android uses the last assignment in a file.
    return result


def dex_counts(reader, path, label):
    data = reader.data(path)
    if data is None:
        return (0, 0, 'absent')
    tmp = OUT / 'tmp' / (label + '-dex.zip')
    tmp.write_bytes(data)
    # Use the same unzip | strings view as a manual inspection. Match multidex names.
    with (OUT / 'dex-errors.log').open('ab') as errors:
        r = subprocess.run(['unzip', '-Z1', str(tmp)], capture_output=True)
        if r.returncode:
            warnings.append(f'Cannot list dex in {path} ({label}).')
            return ('?', '?', 'error')
        names = [n for n in r.stdout.decode().splitlines() if re.fullmatch(r'classes\d*\.dex', n)]
        if not names:
            return (0, 0, 'no-dex')
        proc = subprocess.Popen(['unzip', '-p', str(tmp)] + names, stdout=subprocess.PIPE, stderr=errors)
        strings = subprocess.run(['strings'], stdin=proc.stdout, capture_output=True)
        proc.stdout.close()
        status = proc.wait()
        if status or strings.returncode:
            warnings.append(f'Cannot read dex in {path} ({label}).')
            return ('?', '?', 'error')
    return (strings.stdout.count(b'waitForService'), strings.stdout.count(b'waitForDeclaredService'), 'ok')


def sf_count(reader, label):
    data = reader.data('/system/bin/surfaceflinger')
    if data is None:
        warnings.append(f'SurfaceFlinger is missing in {label}.')
        return ('?', 'missing')
    binary = OUT / 'tmp' / (label + '-surfaceflinger')
    binary.write_bytes(data)
    objdump = shutil.which('llvm-objdump')
    if objdump:
        # Keep only call sites, not the large full disassembly.
        with (OUT / f'surfaceflinger-{label}.errors.log').open('wb') as errors:
            proc = subprocess.Popen([objdump, '-d', str(binary)], stdout=subprocess.PIPE,
                                    stderr=errors, text=True)
            sites = [line.rstrip() for line in proc.stdout
                     if re.search(r'\bbl\s+.*<AServiceManager_waitForService@plt>', line)]
            proc.stdout.close()
            rc = proc.wait()
        if rc == 0:
            (OUT / f'surfaceflinger-{label}-sites.txt').write_text('\n'.join(sites) + '\n')
            return (len(sites), 'llvm-objdump call sites')
        warnings.append(f'llvm-objdump failed for {label}; SurfaceFlinger uses a strings estimate.')
    r = subprocess.run(['strings', str(binary)], check=True, capture_output=True)
    return (r.stdout.count(b'AServiceManager_waitForService'), 'strings occurrences (not call sites)')


def main():
    global old, new, parts, portdiff
    for root in (OLD, NEW):
        if not root.is_dir():
            fail(f'Image directory does not exist: {root}')
        if inside(OUT, root) or inside(root, OUT):
            fail('Output and input directories must be separate. Neither may contain the other.')
    if inside(HERE, OUT) or OUT == HERE:
        fail('Use a separate output directory.')
    for tool in ('df', 'strings', 'unzip', 'dump.erofs', 'cmp', 'find', 'grep', 'bash') + (() if MODE == 'image-only' else ('fsck.erofs',)):
        if not shutil.which(tool):
            fail(f'Missing command: {tool}')
    for helper in ('port_diff.py', 'wfs_scan.sh', 'c06-vs-beta4/PORT-EDITS.tsv'):
        if not (HERE / helper).is_file():
            fail(f'Missing helper: {HERE / helper}')
    OUT.mkdir(parents=True, exist_ok=True)
    # Reject existing symlinks in output so writes cannot escape it.
    for directory, dirs, files in os.walk(OUT):
        if Path(directory).parts[len(OUT.parts):len(OUT.parts)+1] in (('old',), ('new',)):
            dirs[:] = []
            continue
        for name in dirs + files:
            if (Path(directory) / name).is_symlink():
                fail(f'Output contains a symlink: {Path(directory) / name}')
    (OUT / 'tmp').mkdir(exist_ok=True)
    os.environ['TMPDIR'] = str(OUT / 'tmp')
    free = free_space()
    if MODE == 'full' and free < 30 * 2**30:
        fail('Less than 30 GiB free. Stop before extraction.')
    oi, ni = image_set(OLD), image_set(NEW)
    for label, images in (('old', oi), ('new', ni)):
        for part in ('system', 'system_ext', 'product'):
            if part not in images:
                fail(f'Missing required image in {label}: {part}.img')
    parts = sorted(set(oi) | set(ni))
    # An output directory belongs to one image pair. Stat signatures detect replaced images.
    signature = {label: {p: fingerprint(img) for p, img in images.items()}
                 for label, images in (('old', oi), ('new', ni))}
    pair = OUT / 'inputs.json'
    if pair.exists() and json.loads(pair.read_text()) != signature:
        fail('Output belongs to other images. Use a new output directory.')
    pair.write_text(json.dumps(signature, indent=2) + '\n')
    touched_patterns, gates, port_actions = discover()
    portdiff = load_port_diff()
    if MODE == 'full':
        oldroot, newroot = extract(oi, 'old'), extract(ni, 'new')
        old, new = Tree(oldroot, portdiff), Tree(newroot, portdiff)
        allpaths = set(old.records) | set(new.records)
    else:
        say('Image-only check: No partition extraction. The native scan is skipped.')
        old, new = Images(oi), Images(ni)
        allpaths = set()
    touch_sources = collections.defaultdict(set)
    unresolved = []
    say('Resolve touched paths from PORT-EDITS.tsv and layer scripts.')
    for pattern, refs in sorted(touched_patterns.items()):
        if '$' in pattern or '{' in pattern:
            unresolved.append((pattern, '; '.join(sorted(refs)), 'dynamic path; resolve before build'))
            continue
        if MODE == 'full':
            matched = {p for p in allpaths if fnmatch.fnmatchcase(p, pattern) or p.startswith(pattern + '/')}
        elif any(c in pattern for c in '*?['):
            # Enumerate only the directory before the first wildcard.
            stem = re.split(r'[*?\[]', pattern, maxsplit=1)[0].rsplit('/', 1)[0]
            matched = {p for r in (old, new) for p in r.tree(stem) if fnmatch.fnmatchcase(p, pattern)}
        else:
            matched = {p for r in (old, new) for p in r.tree(pattern)}
        for path in matched or {pattern}:
            touch_sources[path].update(refs)
    write_tsv('unresolved-paths.tsv', ['expression', 'sources', 'action'], unresolved)
    if unresolved:
        warnings.append(f'{len(unresolved)} dynamic path expressions need review in unresolved-paths.tsv.')
    if MODE == 'image-only':
        allpaths.update(touch_sources)
        allpaths.update(critical_image_paths(old))
        allpaths.update(critical_image_paths(new))
    changed = [(p, change(p)) for p in sorted(allpaths) if change(p) not in ('unchanged', 'absent-both')]
    write_tsv('files.tsv', ['partition', 'path', 'status', 'old_kind', 'new_kind'],
              [(partition(p), p, s, (old.record(p) or ('-',))[0], (new.record(p) or ('-',))[0])
               for p, s in changed])
    counts = collections.defaultdict(collections.Counter)
    for p, status in changed:
        counts[partition(p)][status] += 1
    partition_rows = []
    for part in parts:
        scope = 'all files (content and symlink targets)'
        if MODE == 'image-only':
            identical = part in oi and part in ni and (oi[part].samefile(ni[part]) or
                subprocess.run(['cmp', '-s', str(oi[part]), str(ni[part])]).returncode == 0)
            scope = 'identical images; all files unchanged' if identical else 'selected files only; full diff not run'
            if not identical:
                warnings.append(f'{part}: Full partition diff was not run in image-only mode.')
        c = counts[part]
        partition_rows.append((part, c['added'], c['removed'], c['changed'], scope))
    write_tsv('partitions.tsv', ['partition', 'added', 'removed', 'changed', 'scope'], partition_rows)
    touched = [(p, change(p), '; '.join(sorted(refs))) for p, refs in sorted(touch_sources.items())]
    write_tsv('touched.tsv', ['path', 'status', 'sources'], touched)
    work = [row for row in touched if row[1] in ('changed', 'removed', 'added')]
    write_tsv('touched-work.tsv', ['path', 'status', 'sources'], work)

    say('Check md5 gates. No patch tool will run.')
    gate_rows = []
    produced = {digest for _, _, digest, stage in gates if stage in ('output', 'generated-copy')}
    for src, target, expected, stage in gates:
        path = normalize(target) if '/tree/' in target else target
        isdevice = path.startswith(('/system/', '/system_ext/', '/product/', '/my_', '/vendor/', '/odm/'))
        a = old.record(path) if isdevice else None
        b = new.record(path) if isdevice else None
        before = a[1] if a and a[0] == 'file' else '-'
        after = b[1] if b and b[0] == 'file' else '-'
        if expected == 'DYNAMIC':
            status = 'LOCAL-COPY-CHECK'
            note = 'Computed copy checksum. Check the local build artifact.'
        elif stage in ('output', 'generated-copy'):
            status = 'BUILD-OUTPUT'
            note = 'Gate checks generated bytes. Run the preceding patch to validate it.'
        elif expected in produced and before != expected:
            status = 'LAYER-INPUT'
            note = 'Expected md5 is an earlier patch output. Validate after that patch; raw donor cannot pass this gate.'
        elif not isdevice or path.startswith(('/vendor/', '/odm/')):
            status = 'OUTSIDE-DONOR' if target != 'UNRESOLVED' else 'UNRESOLVED'
            note = 'Local artifact or pipa vendor/odm. This donor image set cannot validate it.'
        elif before == expected:
            status = 'PASS' if after == expected else ('REMOVED-STOP' if after == '-' else 'FAIL-STOP')
            note = 'Stock input gate passes.' if status == 'PASS' else 'Step stops. Regenerate the patch for this donor.'
        elif after == expected:
            status, note = 'PASS', 'New donor matches the expected input.'
        elif port_actions.get(path) in ('carry', 're-apply', 're-apply?') and before != expected:
            status = 'PORT-EDIT-INPUT'
            note = 'PORT-EDITS.tsv replaces or edits this file first. Validate that result; raw donor md5 differs.'
        elif a is None and b is None:
            status, note = 'MISSING-STOP', 'File missing from both donors. Review this gate.'
        else:
            # Do not claim a patch-result checksum can pass on raw donor bytes.
            status = 'BASELINE-MISMATCH'
            note = 'Both raw donors fail. Step stops unless a prior layer changes the bytes. Check layer order or regenerate.'
        gate_rows.append((src, path, expected, before, after, status, note))
    write_tsv('md5-gates.tsv', ['source', 'path', 'expected_md5', 'old_md5', 'new_md5', 'status', 'action'], gate_rows)

    native_lines = []
    if MODE == 'full':
        say('Run wfs_scan.sh on the extracted trees.')
        r = subprocess.run(['bash', str(HERE / 'wfs_scan.sh'), str(oldroot), str(newroot)],
                           capture_output=True, text=True)
        (OUT / 'wfs-scan.txt').write_text(r.stdout)
        (OUT / 'wfs-scan-errors.log').write_text(r.stderr)
        if r.returncode:
            warnings.append(f'wfs_scan.sh failed with exit {r.returncode}. Read wfs-scan-errors.log.')
        native_lines = [s for s in r.stdout.splitlines() if re.search(r'\(old \d+ -> new \d+\)', s)]
    else:
        (OUT / 'wfs-scan.txt').write_text('SKIPPED: image-only mode. Run the full check before building.\n')
    # The helper scans existing changed .so files in three partitions. Cover additions and my_* too.
    native_extra = []
    if MODE == 'full':
        for path, status in changed:
            if not path.endswith('.so') or status == 'removed':
                continue
            if status != 'added' and partition(path) in ('system', 'system_ext', 'product'):
                continue
            nums = []
            for reader in (old, new):
                rec = reader.record(path)
                if not rec or rec[0] != 'file':
                    nums.append(0)
                    continue
                r = subprocess.run(['strings', '-n', '8', rec[2]], check=True, capture_output=True)
                nums.append(sum(bool(re.search(rb'waitFor(?:Declared)?Service', line)) for line in r.stdout.splitlines()))
            if nums[1] > nums[0]:
                native_extra.append((path, nums[0], nums[1]))
    write_tsv('native-waits-extra.tsv', ['path', 'old_strings', 'new_strings'], native_extra)
    say('Count wait strings in changed jar/apk dex files.')
    dex_rows, dex_risks = [], 0
    for path, status in changed:
        if path.endswith(('.jar', '.apk')):
            a, b = dex_counts(old, path, 'old'), dex_counts(new, path, 'new')
            if all(isinstance(x, int) for x in a[:2] + b[:2]) and (b[0] > a[0] or b[1] > a[1]):
                dex_risks += 1
            dex_rows.append((path, status, *a[:2], *b[:2], a[2], b[2]))
    write_tsv('dex-waits.tsv', ['path', 'status', 'old_waitForService', 'old_waitForDeclaredService',
                              'new_waitForService', 'new_waitForDeclaredService', 'old_scan', 'new_scan'], dex_rows)
    say('Count SurfaceFlinger waitForService call sites.')
    sf_old, sf_new = sf_count(old, 'old'), sf_count(new, 'new')
    write_tsv('surfaceflinger.tsv', ['old_count', 'new_count', 'old_method', 'new_method'],
              [(sf_old[0], sf_new[0], sf_old[1], sf_new[1])])

    text_rows = []
    for path, status in changed:
        category = critical(path)
        if category:
            a, b = old.data(path), new.data(path)
            al, bl = (a or b'').decode(errors='replace').splitlines(), (b or b'').decode(errors='replace').splitlines()
            opcodes = difflib.SequenceMatcher(None, al, bl).get_opcodes()
            plus = sum(j2-j1 for tag, i1, i2, j1, j2 in opcodes if tag in ('insert', 'replace'))
            minus = sum(i2-i1 for tag, i1, i2, j1, j2 in opcodes if tag in ('delete', 'replace'))
            text_rows.append((category, path, status, len(al), len(bl), len(bl)-len(al), plus, minus))
    write_tsv('text-changes.tsv', ['category', 'path', 'status', 'old_lines', 'new_lines', 'line_delta',
                                 'added_lines', 'removed_lines'], text_rows)
    prop_rows = []
    prop_files = []
    for part in ('system', 'system_ext', 'product', 'my_product', 'my_manifest'):
        candidates = {'/' + part + '/build.prop', '/' + part + '/etc/build.prop'}
        if MODE == 'full':
            candidates.update(p for p in allpaths if partition(p) == part and p.endswith('/build.prop'))
        for path in sorted(candidates):
            a, b = old.data(path), new.data(path)
            if a is None and b is None:
                continue
            prop_files.append((part, path, 'present' if a is not None else 'absent', 'present' if b is not None else 'absent'))
            av, bv = properties(a), properties(b)
            for key in sorted(set(av) | set(bv)):
                if av.get(key) == bv.get(key) and key in av and key in bv:
                    continue
                status = 'added' if key not in av else ('removed' if key not in bv else 'changed')
                prop_rows.append((part, path, key, status, av.get(key, ''), bv.get(key, '')))
    write_tsv('build-prop-files.tsv', ['partition', 'path', 'old', 'new'], prop_files)
    write_tsv('build-props.tsv', ['partition', 'path', 'key', 'status', 'old_value', 'new_value'], prop_rows)
    write_tsv('warnings.tsv', ['warning'], [(w,) for w in warnings])

    tc = collections.Counter(row[1] for row in touched)
    gc = collections.Counter(row[5] for row in gate_rows)
    must = []
    if MODE == 'image-only':
        must.append('Run the full check before building. Native and complete file/dex scans are not included here.')
    stops = sum(gc[x] for x in ('FAIL-STOP', 'REMOVED-STOP', 'MISSING-STOP', 'BASELINE-MISMATCH'))
    if stops:
        must.append(f'Regenerate {stops} failed or missing md5 input gates. See md5-gates.tsv. These steps stop.')
    if gc['BASELINE-MISMATCH'] or gc['UNRESOLVED'] or gc['LAYER-INPUT'] or gc['PORT-EDIT-INPUT']:
        must.append(f'Review {gc["BASELINE-MISMATCH"]} baseline mismatches and {gc["UNRESOLVED"]} unresolved gates. '
                    f'Validate {gc["LAYER-INPUT"] + gc["PORT-EDIT-INPUT"]} input gates after their preceding patch or port edit. See md5-gates.tsv.')
    if native_lines or native_extra or dex_risks:
        must.append(f'Check blocking HAL waits: {len(native_lines)+len(native_extra)} native increases; '
                    f'{dex_risks} dex increases. See wfs-scan.txt, native-waits-extra.tsv and dex-waits.tsv. '
                    'A wait for an absent HAL can stop boot.')
    sf_changed = change('/system/bin/surfaceflinger') != 'unchanged'
    if sf_changed or sf_old != sf_new:
        must.append('Review SurfaceFlinger wait sites and regenerate patch_sf_waits.py. See surfaceflinger.tsv and site lists.')
    if work:
        must.append(f'Review {len(work)} touched file changes or removals/additions. See touched-work.tsv. '
                    'Recheck IEngineer, CCT sensor 33171001 -> 33171088 and fold sensor 33171038 patches.')
    if text_rows:
        must.append(f'Review {len(text_rows)} policy, VINTF or init changes. Check mapping compatibility. See text-changes.tsv.')
    if prop_rows:
        must.append(f'Review {len(prop_rows)} build.prop key changes. See build-props.tsv. '
                    'Check display flags and SurfaceFlinger timing properties.')
    if warnings:
        must.append(f'Resolve {len(warnings)} scan warnings. See warnings.tsv.')
    if not must:
        must.append('No donor delta needs action. Keep the port patches and validate their output during the build.')
    scope_label = 'File delta' if MODE == 'full' else 'File delta (image-only selection)'
    report = ['# Donor check', '',
              f'{scope_label}: **{sum(c["added"] for c in counts.values())} added, '
              f'{sum(c["removed"] for c in counts.values())} removed, '
              f'{sum(c["changed"] for c in counts.values())} changed**.',
              f'Touched files: **{tc["changed"]} changed**, {tc["removed"]} removed, {tc["added"]} added, '
              f'{tc["unchanged"]} unchanged, {tc["absent-both"]} absent from both donors.',
              f'Md5 gates: **{gc["PASS"]} pass**, {stops} stop; '
              f'{gc["BASELINE-MISMATCH"]} baseline mismatches; '
              f'{gc["LAYER-INPUT"] + gc["PORT-EDIT-INPUT"]} layer/port-edit input checks; '
              f'{gc["BUILD-OUTPUT"]} generated-output checks; '
              f'{gc["OUTSIDE-DONOR"] + gc["LOCAL-COPY-CHECK"]} local/vendor checks.',
              f'SurfaceFlinger waits: **{sf_old[0]} -> {sf_new[0]}** ({sf_new[1]}).', '',
              '## Must check before build', '']
    report += [f'{i}. {item}' for i, item in enumerate(must, 1)]
    report += ['', '## Partition counts', '', '| Partition | Added | Removed | Changed | Scope |',
               '| --- | ---: | ---: | ---: | --- |']
    report += [f'| {p} | {a} | {r} | {c} | {s} |' for p, a, r, c, s in partition_rows]
    report += ['', '## Scope and files', '', f'- Old images: `{OLD}`', f'- New images: `{NEW}`',
               f'- Mode: `{MODE}`. Initial free space: {free / 2**30:.2f} GiB.',
               '- files.tsv lists file content, type and symlink-target changes. It does not compare ownership, modes or xattrs.',
               '- touched.tsv includes port additions that are absent from both stock donors. touched-work.tsv is the main work list.',
               '- source-paths.tsv records static path expansion. unresolved-paths.tsv lists expressions that need manual review.',
               '- Md5 PASS applies to the checked input bytes only. It does not prove that every earlier layer still works.',
               '- BASELINE-MISMATCH also needs review on identical donors. It can be an intermediate patch input or an older baseline.',
               '- Wait string counts are risk indicators. Equal counts can hide changed targets or control flow. Inspect changed touched dex.',
               '- wfs_scan.sh covers changed existing libraries in system, system_ext and product. native-waits-extra.tsv covers added libraries and my_*.',
               '- text-changes.tsv gives line totals and inserted/deleted lines for policy, VINTF and init files.',
               '- build-props.tsv compares keys per file. Duplicate keys use the last value. build-prop-files.tsv lists the input files.',
               '- Extracted trees are reused only with matching completion markers and input image stat signatures.', '']
    (OUT / 'report.md').write_text('\n'.join(report))
    say(f'{sum(c["changed"] for c in counts.values())} changed; {len(work)} touched work items; {stops} md5 stops.')
    say(f'Report: {OUT / "report.md"}')


try:
    main()
except (OSError, ValueError, RuntimeError, subprocess.SubprocessError) as exc:
    print(f'ERROR: {exc}', file=sys.stderr)
    sys.exit(1)
PY
