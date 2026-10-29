#!/usr/bin/env python3
"""Smali edits for patch_ambient_lux.sh (see there). Stops when an anchor is not found exactly once.

Also DefaultConfig.YS (the DEFAULT ambient CCT curve, 31 points for room CCT 2500..10000 K): stock maps all warm
light 2500-3500 K to 5329 K and 4000 K to 5400 K (too weak next to an OPPO phone, user 2026-10-29). New curve:
target = 6500 - (6500 - room) * STRENGTH below 6500 K, 6500 + (room - 6500) * 0.5 above (max 7515 K, as stock).
Bedtime (comfortable rhythm, OplusFeatureAmbientEyeprotect.calculateTargetCCT): day = ModelConfig day curve
(DefaultConfig.YS_DAY_CURVE, stock 4960-6180 K), night = YS_NIGHT_CURVE (stock steps 4800/5100/5300/5600 K). Both were
cooler than the new adaptive curve in warm light, so switching bedtime on made the screen cooler (map 2026-10-29).
New: night = adaptive - BEDTIME_OFFSET (min BEDTIME_MIN), day = min(stock day, adaptive); the night dark lock
(ModelConfig / EyeProtectConfig mNightLockCct, below 30 lx) 5100 -> NIGHT_LOCK K (warmer than the night curve). pipa has no p_d_*_sensor_lock.xml,
so these defaults apply. The LUT lock values (used at night with adaptive on, stock 0 = white in the
dark) default to the night lock. (YS_FOR_COMFORTABLE_TEMPERATURE, eye comfort / LUT, stays stock.)

Usage: edit_adapter.py <OplusColorAmbientAdapter.smali> <OplusColorAmbientAdapter$1.smali> <DefaultConfig.smali>
       <ModelConfig.smali> <EyeProtectConfig.smali>
"""
import struct
import sys

STRENGTH = 0.7
BEDTIME_OFFSET = 600.0
BEDTIME_MIN = 3400.0
NIGHT_LOCK = 3600.0

A = 'Lcom/android/server/display/color/control/OplusColorAmbientAdapter;->'
REG = 'registerSensorIfAvailable(Landroid/hardware/SensorManager;II)V'

REGISTER_OLD = f"""    const v2, 0x1fa2690

    const/4 v3, 0x3

    invoke-direct {{p0, v0, v2, v3}}, {A}{REG}
"""
REGISTER_NEW = REGISTER_OLD.replace('0x1fa2690', '0x1fa2691')

SWITCH_OLD = """    :goto_1f
    return-void

    :sswitch_data_20
    .sparse-switch
        0x8 -> :sswitch_1b
        0x1b -> :sswitch_17
        0x1fa266c -> :sswitch_f
        0x1fa2690 -> :sswitch_13
    .end sparse-switch
"""
SWITCH_NEW = f"""    :goto_1f
    return-void

    :sswitch_pipa_stream
    invoke-direct {{p0, p1}}, {A}onPipaStream(Landroid/hardware/SensorEvent;)V

    return-void

    :sswitch_data_20
    .sparse-switch
        0x8 -> :sswitch_1b
        0x1b -> :sswitch_17
        0x1fa266c -> :sswitch_f
        0x1fa2690 -> :sswitch_13
        0x1fa2691 -> :sswitch_pipa_stream
    .end sparse-switch
"""

# the patch_framework.sh constant before feedFilter(): read values[9] again (v2 = values, v1 = 9)
FEED_OLD = f"""    iget-object v2, p1, Landroid/hardware/SensorEvent;->values:[F

    const/high16 v1, 0x42c80000    # 100.0f

    invoke-direct {{p0, v0, v1}}, {A}feedFilter(FF)V
"""
FEED_NEW = FEED_OLD.replace('    const/high16 v1, 0x42c80000    # 100.0f\n', '    aget v1, v2, v1\n')

# Xiaomi stream [lux, CCT, R, G, B, C, ...] -> OPPO layout [CCT, .., x 7, y 8, lux 9, confidence 10]
STREAM = f"""
.method private onPipaStream(Landroid/hardware/SensorEvent;)V
    .registers 8
    .param p1, "sensorEvent"    # Landroid/hardware/SensorEvent;

    iget-object v0, p1, Landroid/hardware/SensorEvent;->values:[F

    array-length v1, v0

    const/16 v2, 0xb

    if-lt v1, v2, :done

    const/4 v1, 0x0

    aget v2, v0, v1

    const/4 v3, 0x1

    aget v3, v0, v3

    const v4, 0x461c4000    # 10000.0f: in the dark the stream CCT is 100000+ K (no light to measure)

    cmpl-float v5, v3, v4

    if-lez v5, :cct_low

    move v3, v4

    :cct_low
    const v4, 0x447a0000    # 1000.0f: in a dim room the stream gives CCT 0; ColorOS then drops the data
                            # (sensorDataValid=false, no adjustment). 3000 K keeps it valid; lux < 30 locks anyway.

    cmpg-float v5, v3, v4

    if-gez v5, :cct_ok

    const v3, 0x453b8000    # 3000.0f

    :cct_ok
    aput v3, v0, v1

    const/16 v4, 0x9

    aput v2, v0, v4

    const/4 v4, 0x0    # 0.0f

    const/4 v5, 0x7

    aput v4, v0, v5

    const/16 v5, 0x8

    aput v4, v0, v5

    const/high16 v4, 0x3f800000    # 1.0f

    const/16 v5, 0xa

    aput v4, v0, v5

    invoke-direct {{p0, p1}}, {A}onSingleSensorChanged(Landroid/hardware/SensorEvent;)V

    :done
    return-void
.end method
"""

CLONE_OLD = """    iget-object v6, p1, Landroid/hardware/SensorEvent;->values:[F

    invoke-direct/range {v1 .. v6}, Landroid/hardware/SensorEvent;-><init>(Landroid/hardware/Sensor;IJ[F)V
"""
CLONE_NEW = CLONE_OLD.replace('[F\n\n    invoke-direct/range', '''[F

    invoke-virtual {v6}, [F->clone()Ljava/lang/Object;

    move-result-object v6

    check-cast v6, [F

    invoke-direct/range''', 1)


def once(s, old, new, what):
    n = s.count(old)
    if n != 1:
        sys.exit(f"{what}: anchor found {n} times")
    return s.replace(old, new)


def fl(y):
    return '0x%08x    # %.1ff' % (struct.unpack('<I', struct.pack('<f', y))[0], y)


def adaptive():
    xs = [2500 + 250 * i for i in range(31)]
    return [6500 - (6500 - x) * STRENGTH if x <= 6500 else min(7515.0, 6500 + (x - 6500) * 0.5) for x in xs]


def read_array(s, label):
    head = f'    :{label}\n    .array-data 4\n'
    a = s.index(head) + len(head)
    b = s.index('    .end array-data\n', a)
    return [struct.unpack('<f', struct.pack('<I', int(l.split()[0], 16)))[0] for l in s[a:b].strip().split('\n')]


def set_array(s, field, label, first, ys):
    refs = [f'    fill-array-data {r}, :{label}\n\n    sput-object {r}, Lcom/android/server/display/color/model/DefaultConfig;->{field}:[F\n'
            for r in ('v0', 'v1')]
    if sum(s.count(ref) for ref in refs) != 1:
        sys.exit(f"DefaultConfig.{field}: fill-array-data anchor not found once")
    head = f'    :{label}\n    .array-data 4\n'
    a = s.index(head) + len(head)
    b = s.index('    .end array-data\n', a)
    old = s[a:b]
    if old.count('\n') != 31 or fl(first) not in old.split('\n')[0]:
        sys.exit(f"DefaultConfig.{field}: not the stock 31-point curve")
    return s[:a] + ''.join(f'        {fl(y)}\n' for y in ys) + s[b:]


def edit_curve(path):
    s = open(path).read()
    ad = adaptive()
    day = read_array(s, 'array_22c')
    s = set_array(s, 'YS', 'array_d4', 5329.0, ad)
    s = set_array(s, 'YS_DAY_CURVE', 'array_22c', 4960.0, [min(d, y) for d, y in zip(day, ad)])
    s = set_array(s, 'YS_NIGHT_CURVE', 'array_26e', 4800.0, [max(BEDTIME_MIN, y - BEDTIME_OFFSET) for y in ad])
    open(path, 'w').write(s)


def edit_night_lock(path, cls, reg):
    s = open(path).read()
    old = f'    const v1, 0x459f6000    # 5100.0f\n\n    iput v1, p0, L{cls};->mNightLockCct:F\n'
    new = f'    const v1, {fl(NIGHT_LOCK)}\n\n    iput v1, p0, L{cls};->mNightLockCct:F\n'
    s = once(s, old, new, f'{cls} mNightLockCct')
    # At night with adaptive on, bedtime locks with the LUT values (getLockCct/getLockLux), stock 0 without a LUT
    # config: lock CCT 0 = no colour at all in a dark room (white). Default them to the night values.
    old = f'    iput {reg}, p0, L{cls};->mLutLockCct:F\n'
    new = old + f"""
    iget {reg}, p0, L{cls};->mNightLockLux:F

    iput {reg}, p0, L{cls};->mLutLockLux:F

    iget {reg}, p0, L{cls};->mNightLockCct:F

    iput {reg}, p0, L{cls};->mLutLockCct:F

    const/4 {reg}, 0x0
"""
    open(path, 'w').write(once(s, old, new, f'{cls} mLutLockCct'))


def main(adapter, listener, defconfig, modelconfig, eyeconfig):
    s = open(adapter).read()
    if 'onPipaStream' in s:
        sys.exit("already patched")
    s = once(s, REGISTER_OLD, REGISTER_NEW, 'registerSensor')
    s = once(s, SWITCH_OLD, SWITCH_NEW, 'handleSensorChange')
    s = once(s, FEED_OLD, FEED_NEW, 'onSingleSensorChanged feedFilter')
    s = s.rstrip('\n') + '\n' + STREAM
    open(adapter, 'w').write(s)
    t = open(listener).read()
    assert CLONE_NEW != CLONE_OLD
    t = once(t, CLONE_OLD, CLONE_NEW, '$1.onSensorChanged')
    open(listener, 'w').write(t)
    edit_curve(defconfig)
    edit_night_lock(modelconfig, 'com/android/server/display/color/model/ModelConfig', 'v0')
    edit_night_lock(eyeconfig, 'com/android/server/display/color/config/EyeProtectConfig', 'v1')
    print(f"OplusColorAmbientAdapter: stream sensor 33171089, OPPO layout, real lux; curve strength {STRENGTH}, "
          f"bedtime -{BEDTIME_OFFSET:.0f} K (min {BEDTIME_MIN:.0f}), night lock {NIGHT_LOCK:.0f} K")


if __name__ == '__main__':
    main(*sys.argv[1:])
