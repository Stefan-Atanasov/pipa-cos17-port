#!/bin/sh
# Rebuild the sensor-rerouted oplus-services.jar from a ROM's own oplus-services.jar.
#
#   ./patch_framework.sh /path/to/stock/oplus-services.jar /path/to/output.jar
#   PATCH=engineer ./patch_framework.sh in.jar out.jar     (edit 4 only, for the plain ROM)
#
# The full patch is four edits in classes.dex:
#   1. the sparse-switch payload in handleSensorChange() is reordered, because
#      DEX requires sparse-switch keys to be sorted (otherwise VerifyError);
#   2. every 33171001 (OPPO CCT sensor type) becomes 33171088 (Xiaomi front_cct)
#      -- registerSensor() and EyeProtectConstant.SENSOR_COLOR_TEMPERATURE;
#   3. in onSingleSensorChanged() the `aget values[9]` (OPPO's lux slot, always
#      0 on pipa) becomes a float constant 100.0 lx (const/high16).
#   4. OplusEngineerFwService.getEngineerService(): `if-eqz isRootVersion()` becomes
#      two nops, so it always takes the non-blocking getService path. Otherwise, with
#      ro.adb.secure=1 (isRootVersion() = !ro.adb.secure), it calls waitForService on
#      vendor.oplus.hardware.engineer.IEngineer/default, which pipa does not have:
#      system_server hangs at boot phase 480 and the watchdog panics the device.
#      beta4 only survived because it had deleted ro.adb.secure. Already-patched input
#      is accepted (edit 4 is skipped), so an engineer-only jar can be fully patched.
# Then the dex signature/checksum are recomputed and the jar is rebuilt.
#
# The sites are located by pattern, not by offset: the switch payload must occur
# exactly once, the lux aget must be the only `iget-object v2,..; aget v1,v2,v1;
# invoke-direct` sequence within 4 KiB after it, and exactly 2 CCT literals must
# remain after the reorder. Any other count aborts.
# Verified on beta4 (jar 3316594f…, payload 0x8bb170, lux +0x1fa) and on donor
# C.06 17.0.0.103 (jar 2175feb9…, payload 0x4365c0, lux +0x1fa).

set -eu
STOCK=${1:?usage: patch_framework.sh stock.jar output.jar}
export PATCH=${PATCH:-all}
OUT=${2:?usage: patch_framework.sh stock.jar output.jar}

python3 -I - "$STOCK" "$OUT" <<'PY'
import hashlib, os, re, struct, sys, zipfile, zlib
src, out = sys.argv[1:]
zin = zipfile.ZipFile(src)
d = bytearray(zin.read('classes.dex'))

def all_offsets(pat):
    r, i = [], d.find(pat)
    while i != -1:
        r.append(i); i = d.find(pat, i + 1)
    return r

def engineer():
    # 4. invoke-static isRootVersion; move-result v0; if-eqz v0,+0x0f; invoke-direct {v3} initHalService;
    #    sget-object v0, mEngineerService  ->  the if-eqz becomes two nops.
    pat = rb'\x71\x00..\x00\x00\x0a\x00%s\x70\x10..\x03\x00\x62\x00'
    todo = [m.start() + 8 for m in re.finditer(pat % rb'\x38\x00\x0f\x00', d, re.S)]
    done = [m.start() + 8 for m in re.finditer(pat % rb'\x00\x00\x00\x00', d, re.S)]
    if len(todo) + len(done) != 1:
        sys.exit(f'engineer branch found {len(todo)} times, patched {len(done)} times (need exactly 1)')
    if todo:
        d[todo[0]:todo[0] + 4] = b'\x00\x00\x00\x00'
        return f'engineer {todo[0]:#x}'
    return f'engineer {done[0]:#x} (already patched)'

def cct():
    # 1. Reorder the sparse-switch payload first: keys must be ascending.
    want = (struct.pack('<4I', 8, 27, 33171001, 33171052) +
            struct.pack('<4I', 16, 12, 8, 4))
    hits = all_offsets(want)
    if len(hits) != 1:
        sys.exit(f'switch payload found {len(hits)} times (need exactly 1)')
    base = hits[0]
    d[base:base + 16] = struct.pack('<4I', 8, 27, 33171052, 33171088)
    d[base + 16:base + 32] = struct.pack('<4I', 16, 12, 4, 8)

    # 2. OPPO CCT type -> Xiaomi front CCT type (const + static field; the switch
    #    key was already replaced in step 1).
    old, new = bytes.fromhex('3926fa01'), bytes.fromhex('9026fa01')
    offs = all_offsets(old)
    if len(offs) != 2:
        sys.exit(f'expected 2 CCT literals after reorder, found {len(offs)}')
    for o in offs:
        d[o:o + 4] = new

    # 3. values[9] (no lux in the Xiaomi event) -> 100.0f.
    #    iget-object v2, p0, field@?? ; aget v1, v2, v1 ; invoke-direct {..}
    window = bytes(d[base:base + 0x1000])
    lux = [base + m.start() + 4 for m in re.finditer(rb'\x54\x62..\x44\x01\x02\x01\x70', window, re.S)]
    if len(lux) != 1:
        sys.exit(f'lux aget found {len(lux)} times after the payload (need exactly 1)')
    off = lux[0]
    d[off:off + 4] = bytes.fromhex('1501c842')   # const/high16 v1, #0x42c80000
    return f'payload {base:#x}, CCT literals {[hex(o) for o in offs]}, lux {off:#x} (+{off - base:#x})'

if os.environ['PATCH'] == 'engineer':
    msgs = [engineer()]
elif os.environ['PATCH'] == 'all':
    msgs = [cct(), engineer()]
else:
    sys.exit('PATCH must be all or engineer')

# dex signature + checksum
d[12:32] = hashlib.sha1(d[32:]).digest()
d[8:12] = struct.pack('<I', zlib.adler32(d[12:]) & 0xffffffff)
print('patched classes.dex: ' + '; '.join(msgs))

with zipfile.ZipFile(out, 'w') as zout:
    for info in zin.infolist():
        data = bytes(d) if info.filename == 'classes.dex' else zin.read(info.filename)
        zi = zipfile.ZipInfo(info.filename, date_time=info.date_time)
        zi.compress_type = info.compress_type
        zi.external_attr = info.external_attr
        zi.internal_attr = info.internal_attr
        zi.create_system = info.create_system
        zout.writestr(zi, data)
print('wrote', out)
PY
