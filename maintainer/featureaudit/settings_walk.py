#!/usr/bin/env python3
"""Feature audit, live part (b): walk ColorOS Settings with uiautomator, find every switch, toggle it and back.

WRITTEN OFFLINE 2026-11-13, NOT YET RUN ON THE TABLET. Start with `list` mode and watch the screen.

Usage:
  python3 -I settings_walk.py list  [--serial S] [--depth 2] [--out DIR]   # read only: screens + switches, no taps on switches
  python3 -I settings_walk.py walk  [--serial S] [--depth 2] [--out DIR] [--persist] [--only TEXT]
      walk: for each allowed switch: tap, wait, check the state flipped, check crashes, (--persist: leave the screen and
      come back, check the state stayed), tap again, check it is back. A dialog after a tap is answered with BACK
      (never OK) and recorded.
  --start PKG/ACT  start activity (default com.android.settings/.Settings); use it for single OPPO apps too.
Rules (CLAUDE.md): Wi-Fi-only tablet over USB adb (serial 83836a90). Unlock the tablet first. Stop if a pgrep -af
opencode shows another agent. Results: <out>/walk.tsv, <out>/crashes/, <out>/screens/*.xml.
"""
import argparse, os, re, subprocess, sys, time, xml.etree.ElementTree as ET

DENY = [  # substrings (lower case) of row or switch titles that are never tapped
    'reset', 'erase', 'factory', 'wipe', 'format', 'delete', 'clear', 'uninstall', 'restore', 'backup', 'update',
    'developer', 'usb debugging', 'wireless debugging', 'oem unlock', 'reboot', 'restart', 'shut down', 'power off',
    'account', 'heytap', 'oppo id', 'google', 'sign in', 'log in', 'payment', 'wallet', 'pay', 'nfc',
    'screen lock', 'lock screen password', 'password', 'pin', 'pattern', 'privacy password', 'app lock', 'fingerprint',
    'face', 'find my', 'find device', 'sim', 'airplane', 'wlan', 'wi-fi', 'wifi', 'hotspot', 'usb',
    'talkback', 'select to speak', 'switch access', 'magnification', 'accessibility shortcut', 'voice access',
    'navigation', 'gesture', 'simple mode', 'kid', 'children', 'elderly', 'super power saving', 'power saving mode',
    'emergency', 'sos', 'storage', 'dual apps', 'clone', 'users', 'multiple users', 'guest', 'language', 'date & time',
    'time zone', 'auto time', 'encryption', 'credential', 'certificate', 'device admin', 'trust agent', 'vpn',
    'private dns', 'mobile network', 'satellite', 'log', 'feedback', 'diagnos', 'system update', 'software update',
]
NAV_DENY = DENY + ['about device', 'about tablet', 'legal', 'licen', 'privacy policy', 'user agreement', 'help',
                   'search', 'tips']

def sh(args, serial, timeout=30, check=False):
    r = subprocess.run(['adb', '-s', serial] + args, capture_output=True, text=True, timeout=timeout)
    if check and r.returncode:
        raise RuntimeError(f'adb {args}: {r.stderr.strip()}')
    return r.stdout

def dump(serial):
    # --windows: all windows, so both panes of the tablet Settings (the page is a separate embedded activity)
    sh(['shell', 'uiautomator', 'dump', '--windows', '/data/local/tmp/fa_ui.xml'], serial, timeout=40)
    xml = sh(['exec-out', 'cat', '/data/local/tmp/fa_ui.xml'], serial)
    try:
        return ET.fromstring(xml), xml
    except ET.ParseError:
        return None, xml

def bounds(n):
    m = re.match(r'\[(\d+),(\d+)\]\[(\d+),(\d+)\]', n.get('bounds', ''))
    return tuple(map(int, m.groups())) if m else (0, 0, 0, 0)

def center(n):
    x1, y1, x2, y2 = bounds(n)
    return (x1 + x2) // 2, (y1 + y2) // 2

def texts(n):
    return [t for t in (c.get('text', '').strip() for c in n.iter()) if t]

def focus(serial):
    out = sh(['shell', 'dumpsys', 'window', 'displays'], serial)
    m = re.search(r'mCurrentFocus=Window\{\S+ \S+ ([^}\s]+)\}', out) or re.search(r'mFocusedApp=.*? (\S+/\S+)', out)
    return m.group(1) if m else '?'

PANE = None   # (x_min, x_max): only nodes whose centre is inside (two-pane Settings on the tablet)

def in_pane(n, pane=None):
    pane = pane or PANE
    if pane is None:
        return True
    x1, y1, x2, y2 = bounds(n)
    return pane[0] <= (x1 + x2) // 2 < pane[1]

def scrollables(root, pane=None):
    return [n for n in root.iter('node') if n.get('scrollable') == 'true' and in_pane(n, pane)]

def parents(root):
    return {c: p for p in root.iter() for c in p}

def rows(root, pane=None):
    """Switch rows and navigation rows on the current screen (inside the pane)."""
    par = parents(root)
    sw, nav = [], []
    for n in root.iter('node'):
        if not in_pane(n, pane):
            continue
        cls = n.get('class', '')
        if n.get('checkable') == 'true' and ('Switch' in cls or 'CheckBox' in cls or 'Toggle' in cls):
            row = n
            while row in par and row.get('clickable') != 'true':
                row = par[row]
            r2 = par.get(row, row)
            t = [x for x in texts(row if texts(row) else r2) if x not in ('ON', 'OFF')]
            sw.append({'node': n, 'title': t[0] if t else '?', 'sub': ' | '.join(t[1:3]), 'checked': n.get('checked'),
                       'enabled': n.get('enabled')})
    seen = set()
    for n in root.iter('node'):
        if not in_pane(n, pane):
            continue
        if n.get('clickable') != 'true' or n.get('checkable') == 'true':
            continue
        if any(c.get('checkable') == 'true' for c in n.iter()):
            continue
        t = texts(n)
        if not t or t[0] in seen or len(t[0]) > 60:
            continue
        x1, y1, x2, y2 = bounds(n)
        if (x2 - x1) < 200 or (y2 - y1) < 60:   # icons, toolbar buttons
            continue
        seen.add(t[0])
        nav.append({'node': n, 'title': t[0]})
    return sw, nav

def denied(title, lst):
    low = title.lower()
    return any(d in low for d in lst)

def scroll(serial, root, pane=None):
    sc = scrollables(root, pane)
    if not sc:
        return False
    x1, y1, x2, y2 = bounds(max(sc, key=lambda n: (bounds(n)[3] - bounds(n)[1])))
    x = (x1 + x2) // 2
    sh(['shell', 'input', 'swipe', str(x), str(y1 + (y2 - y1) * 3 // 4), str(x), str(y1 + (y2 - y1) // 4), '400'], serial)
    time.sleep(0.4)
    return True

def crash_mark(serial):
    return sh(['shell', 'date', '+%m-%d %H:%M:%S.000'], serial).strip()

def crashes_since(serial, mark):
    out = sh(['shell', 'logcat', '-b', 'crash', '-d', '-T', mark], serial, timeout=40)
    return [l for l in out.splitlines() if 'FATAL' in l or 'Process:' in l or 'ANR' in l]

def find_switch(root, title):
    sw, _ = rows(root)
    for s in sw:
        if s['title'] == title:
            return s
    return None

def screen_sig(root):
    return tuple(texts(root)[:8]) if root is not None else ()

def walk_screen(a, path, depth, log, visited):
    serial = a.serial
    seen_sw, seen_nav, last = set(), [], None
    for page in range(8):
        root, xml = dump(serial)
        if root is None:
            break
        sig = screen_sig(root)
        with open(os.path.join(a.out, 'screens', f'{len(visited):03d}-{page}.xml'), 'w') as f:
            f.write(xml)
        sw, nav = rows(root)
        for s in sw:
            if s['title'] in seen_sw:
                continue
            seen_sw.add(s['title'])
            title = s['title']
            rec = {'path': ' > '.join(path), 'switch': title, 'sub': s['sub'], 'before': s['checked'],
                   'after': '', 'kept': '', 'restored': '', 'crash': '', 'dialog': '', 'note': ''}
            if a.mode == 'list' or s['enabled'] != 'true' or denied(title, DENY) or (a.only and a.only.lower() not in title.lower()):
                rec['note'] = 'listed' if a.mode == 'list' else ('denied' if denied(title, DENY) else 'skipped')
                log(rec)
                continue
            mark = crash_mark(serial)
            x, y = center(s['node'])
            sh(['shell', 'input', 'tap', str(x), str(y)], serial)
            time.sleep(0.4)
            r2, _ = dump(serial)
            s2 = find_switch(r2, title) if r2 is not None else None
            if s2 is None:
                rec['dialog'] = 'yes (screen changed)'
                sh(['shell', 'input', 'keyevent', '4'], serial)
                time.sleep(0.5)
                r2, _ = dump(serial)
                s2 = find_switch(r2, title) if r2 is not None else None
            rec['after'] = s2['checked'] if s2 else '?'
            if s2 and a.persist and rec['after'] != rec['before']:
                sh(['shell', 'input', 'keyevent', '4'], serial); time.sleep(0.6)
                sh(['shell', 'input', 'keyevent', '4'], serial); time.sleep(0.3)  # second BACK only if the first closed a dialog
                rec['note'] = 'persist check: reopen by hand path ' + rec['path']
            if s2 and rec['after'] != rec['before']:
                x, y = center(s2['node'])
                sh(['shell', 'input', 'tap', str(x), str(y)], serial)
                time.sleep(0.4)
                r3, _ = dump(serial)
                s3 = find_switch(r3, title) if r3 is not None else None
                if s3 is None:
                    sh(['shell', 'input', 'keyevent', '4'], serial); time.sleep(0.5)
                    r3, _ = dump(serial)
                    s3 = find_switch(r3, title) if r3 is not None else None
                rec['restored'] = 'yes' if s3 and s3['checked'] == rec['before'] else 'NO'
            elif s2:
                rec['note'] = (rec['note'] + ' no effect (state did not change)').strip()
            cr = crashes_since(serial, mark)
            if cr:
                rec['crash'] = cr[0][:160]
                with open(os.path.join(a.out, 'crashes', f'{len(visited):03d}-{re.sub(r"[^A-Za-z0-9]+", "_", title)[:40]}.txt'), 'w') as f:
                    f.write(sh(['shell', 'logcat', '-b', 'crash', '-d', '-T', mark], serial, timeout=40))
            log(rec)
        for n in nav:
            if n['title'] not in [x['title'] for x in seen_nav]:
                seen_nav.append(n)
        if sig == last or not scroll(serial, root):
            break
        last = sig
    if depth <= 0:
        return
    if len(seen_nav) > 25:   # a list of apps or items (per-app notifications, app management): no recursion
        print(f"skip children of {' > '.join(path)}: {len(seen_nav)} rows (list page)")
        return
    # go back to the top of this screen, then open each navigation row
    for _ in range(6):
        root, _ = dump(serial)
        sc = scrollables(root) if root is not None else []
        if not sc:
            break
        x1, y1, x2, y2 = bounds(sc[0])
        sh(['shell', 'input', 'swipe', str((x1 + x2) // 2), str(y1 + (y2 - y1) // 4), str((x1 + x2) // 2), str(y2 - 10), '300'], serial)
    for n in seen_nav:
        t = n['title']
        key = tuple(path + [t])
        if key in visited or denied(t, NAV_DENY):
            continue
        visited.add(key)
        # find the row again (positions change after scrolling)
        target = None
        for _ in range(12):
            root, _ = dump(serial)
            if root is None:
                break
            _, nav2 = rows(root)
            target = next((x for x in nav2 if x['title'] == t), None)
            if target or not scroll(serial, root):
                break
        if not target:
            continue
        before = focus(serial), screen_sig(root)
        x, y = center(target['node'])
        sh(['shell', 'input', 'tap', str(x), str(y)], serial)
        time.sleep(0.9)
        r2, _ = dump(serial)
        if (focus(serial), screen_sig(r2)) == before:
            continue  # did not open a new screen (expanding row or dialog-less action)
        walk_screen(a, path + [t], depth - 1, log, visited)
        sh(['shell', 'input', 'keyevent', '4'], serial)
        time.sleep(0.6)

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('mode', choices=['list', 'walk'])
    ap.add_argument('--serial', default='83836a90')
    ap.add_argument('--depth', type=int, default=2)
    ap.add_argument('--out', default='fa-walk-' + time.strftime('%Y%m%d-%H%M'))
    ap.add_argument('--persist', action='store_true')
    ap.add_argument('--only')
    ap.add_argument('--start', default='com.android.settings/.Settings')
    ap.add_argument('--from-top', dest='from_top', help='two-pane mode: begin at this menu entry')
    a = ap.parse_args()
    if subprocess.run(['pgrep', '-af', 'opencode'], capture_output=True, text=True).stdout.strip():
        sys.exit('opencode runs: agree on the tablet use with the user first (CLAUDE.md)')
    for d in ('screens', 'crashes'):
        os.makedirs(os.path.join(a.out, d), exist_ok=True)
    tsv = open(os.path.join(a.out, 'walk.tsv'), 'w')
    cols = ['path', 'switch', 'sub', 'before', 'after', 'kept', 'restored', 'crash', 'dialog', 'note']
    tsv.write('\t'.join(cols) + '\n')
    def log(rec):
        tsv.write('\t'.join(str(rec.get(c, '')) for c in cols) + '\n'); tsv.flush()
        print(f"{rec['path'][:50]:50} | {rec['switch'][:40]:40} | {rec['before']}->{rec['after']} restored={rec['restored']} {rec['crash'][:40]} {rec['note']}")
    global PANE
    sh(['shell', 'am', 'start', '-W', '-n', a.start], a.serial, check=True)
    time.sleep(2)
    root, _ = dump(a.serial)
    width = max(bounds(n)[2] for n in root.iter('node')) if root is not None else 0
    left = [n for n in scrollables(root, (0, width // 2))
            if bounds(n)[2] < width * 0.45] if root is not None else []
    if not left:
        walk_screen(a, [a.start.split('/')[0]], a.depth, log, set())
    else:
        split = max(bounds(n)[2] for n in left)
        print(f'two-pane Settings: menu x<{split}, pages x>={split}')
        menu = (0, split)
        # top level: rows of the left menu; each one opens its page in the right pane
        for _ in range(8):   # menu to the top
            r, _ = dump(a.serial)
            if r is None or not scrollables(r, menu):
                break
            x1, y1, x2, y2 = bounds(scrollables(r, menu)[0])
            sh(['shell', 'input', 'swipe', str((x1 + x2) // 2), str(y1 + (y2 - y1) // 4), str((x1 + x2) // 2), str(y2 - 10), '300'], a.serial)
        tops, last = [], None
        for _ in range(15):
            r, _ = dump(a.serial)
            sw, nav = rows(r, menu)
            for n in nav:
                if n['title'] not in tops:
                    tops.append(n['title'])
            sig = screen_sig(r)
            if sig == last or not scroll(a.serial, r, menu):
                break
            last = sig
        print('menu:', ' | '.join(tops))
        visited = set()
        if a.from_top and a.from_top in tops:
            tops = tops[tops.index(a.from_top):]
        for t in tops:
            if denied(t, NAV_DENY) or (t.lower() in ('search', 'sign in')):
                continue
            # fresh Settings for each entry: a page can leave the two-pane view or open another app
            sh(['shell', 'am', 'force-stop', a.start.split('/')[0]], a.serial)
            sh(['shell', 'am', 'start', '-W', '-n', a.start], a.serial)
            time.sleep(1.0)
            target = None
            for _ in range(8):   # menu opens at the top: scroll down to the row
                r, _ = dump(a.serial)
                if r is None:
                    break
                target = next((x for x in rows(r, menu)[1] if x['title'] == t), None)
                if target or not scroll(a.serial, r, menu):
                    break
            if not target:
                print('menu row not found:', t)
                continue
            x, y = center(target['node'])
            sh(['shell', 'input', 'tap', str(x), str(y)], a.serial)
            time.sleep(0.9)
            PANE = (split, width + 1)
            walk_screen(a, [t], a.depth - 1, log, visited)
            PANE = None
    print('done:', os.path.join(a.out, 'walk.tsv'))

if __name__ == '__main__':
    main()
