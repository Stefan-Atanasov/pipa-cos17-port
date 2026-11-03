#!/usr/bin/env python3
"""BUGS-TODO 50 (step 3z): the charger shim records the charge-control calls of ColorOS.

The original shim (binary only) answers every ICharger setter with 0 and does nothing, so "Custom charging limit" and
"Smart charging" never hold the battery level. With this patch these setters write their arguments to
/data/misc/pipa_port/chg_<name> (pipa_port holds the level with battery_charging_enabled, service.sh chg_hold):
  setChgConfig(14, "2++<on>+<level>")   -> chg_cfg14   (charging limit; Smart charging uses the same call)
  setPsyMmiChgEn("0"/"1")                -> chg_mmi
  setCustomSelectChgMode(mode, on)       -> chg_sel<mode> ("0"/"1"; 3 = smart rapid charging, 4 = single speed)
  setSmartChgMode(s)                     -> chg_smart
Each record is written to chg_<name>.tmp and renamed (the 30 s poller never sees a half-written file); the setter returns
0 (setChgConfig 12: 1, the EngineerMode caller tests == 1) when it worked, -1 (the framework's failure value) when not.
When the shim starts, a chg_cfg5 or chg_cfg25 older than this boot (mtime < now - elapsedRealtime) is deleted: a hold
or bypass from before the reboot must not stop charging before the Battery app sends a fresh command (a restart of the
shim keeps a fresh one).
Bypass charging (step 4p, notes/cloud/CHARGER-HAL.md section E): setChgConfig(25, "1+switch=<0|1>") is recorded as
chg_cfg25 like every type and returns 1 (the Battery app arms its 180 s re-send watchdog only for a non-zero return).
getChgConfig(24) answers "1" when the last chg_cfg25 is "1+switch=1", else "0" (system_server parses it with
Integer.parseInt; never "5", which makes the Battery app send the request again). getChgConfig(31, "24"|"25") (support
probe) answers "1". Every other getChgConfig call goes to the original method (renamed getChgConfigOrig).
The telemetry getters read /sys/class/power_supply/battery (charge_full*: bms as fallback):
  getPsyBatteryLevel %, getPsyBatteryTemp 0.1 degC, getPsyBatteryRm / Fcc mAh, getPsyBatteryCurrentNow mA,
  getBatteryVoltageNow mV, getUIsohValue = health % = charge_full / charge_full_design (100 without data, the app's default).
Disassembles with baksmali, edits the smali text, assembles with smali (-j 1: same dex on each run).
usage: patch_record.py <in.jar> <out.jar> <baksmali.jar> <smali.jar>
"""
import os, subprocess, sys, tempfile, zipfile

src, dst, baksmali, smali = sys.argv[1:5]
tmp = tempfile.mkdtemp()
with zipfile.ZipFile(src) as z:
    open(f"{tmp}/classes.dex", "wb").write(z.read("classes.dex"))
subprocess.run(["java", "-jar", baksmali, "d", "-j", "1", f"{tmp}/classes.dex", "-o", f"{tmp}/s"], check=True)

helper = f"{tmp}/s/shim/Helper.smali"
s = open(helper).read()
if "record(Ljava/lang/String;Ljava/lang/String;)V" in s:
    sys.exit("already patched")
s += """
.method public static record(Ljava/lang/String;Ljava/lang/String;)Z
    .registers 7
    :try_start_0
    new-instance v1, Ljava/lang/StringBuilder;
    invoke-direct {v1}, Ljava/lang/StringBuilder;-><init>()V
    const-string v2, "/data/misc/pipa_port/chg_"
    invoke-virtual {v1, v2}, Ljava/lang/StringBuilder;->append(Ljava/lang/String;)Ljava/lang/StringBuilder;
    invoke-virtual {v1, p0}, Ljava/lang/StringBuilder;->append(Ljava/lang/String;)Ljava/lang/StringBuilder;
    invoke-virtual {v1}, Ljava/lang/StringBuilder;->toString()Ljava/lang/String;
    move-result-object v1
    new-instance v2, Ljava/lang/StringBuilder;
    invoke-direct {v2}, Ljava/lang/StringBuilder;-><init>()V
    invoke-virtual {v2, v1}, Ljava/lang/StringBuilder;->append(Ljava/lang/String;)Ljava/lang/StringBuilder;
    const-string v3, ".tmp"
    invoke-virtual {v2, v3}, Ljava/lang/StringBuilder;->append(Ljava/lang/String;)Ljava/lang/StringBuilder;
    invoke-virtual {v2}, Ljava/lang/StringBuilder;->toString()Ljava/lang/String;
    move-result-object v2
    new-instance v0, Ljava/io/FileOutputStream;
    invoke-direct {v0, v2}, Ljava/io/FileOutputStream;-><init>(Ljava/lang/String;)V
    invoke-static {p1}, Ljava/lang/String;->valueOf(Ljava/lang/Object;)Ljava/lang/String;
    move-result-object v3
    invoke-virtual {v3}, Ljava/lang/String;->getBytes()[B
    move-result-object v3
    invoke-virtual {v0, v3}, Ljava/io/FileOutputStream;->write([B)V
    invoke-virtual {v0}, Ljava/io/FileOutputStream;->close()V
    new-instance v0, Ljava/io/File;
    invoke-direct {v0, v2}, Ljava/io/File;-><init>(Ljava/lang/String;)V
    new-instance v3, Ljava/io/File;
    invoke-direct {v3, v1}, Ljava/io/File;-><init>(Ljava/lang/String;)V
    invoke-virtual {v0, v3}, Ljava/io/File;->renameTo(Ljava/io/File;)Z
    move-result v0
    :try_end_0
    .catch Ljava/lang/Exception; {:try_start_0 .. :try_end_0} :catch_0
    return v0
    :catch_0
    const/4 v0, 0x0
    return v0
.end method

.method public static dropOld(Ljava/lang/String;)V
    .registers 8
    :try_start_0
    new-instance v0, Ljava/io/File;
    invoke-direct {v0, p0}, Ljava/io/File;-><init>(Ljava/lang/String;)V
    invoke-virtual {v0}, Ljava/io/File;->lastModified()J
    move-result-wide v1
    invoke-static {}, Ljava/lang/System;->currentTimeMillis()J
    move-result-wide v3
    invoke-static {}, Landroid/os/SystemClock;->elapsedRealtime()J
    move-result-wide v5
    sub-long/2addr v3, v5
    cmp-long v1, v1, v3
    if-gez v1, :done
    invoke-virtual {v0}, Ljava/io/File;->delete()Z
    :try_end_0
    .catch Ljava/lang/Exception; {:try_start_0 .. :try_end_0} :catch_0
    :catch_0
    :done
    return-void
.end method

.method public static bootCheck()V
    .registers 1
    const-string v0, "/data/misc/pipa_port/chg_cfg5"
    invoke-static {v0}, Lshim/Helper;->dropOld(Ljava/lang/String;)V
    const-string v0, "/data/misc/pipa_port/chg_cfg25"
    invoke-static {v0}, Lshim/Helper;->dropOld(Ljava/lang/String;)V
    return-void
.end method

.method public static bypassStatus()Ljava/lang/String;
    .registers 4
    :try_start_0
    new-instance v0, Ljava/io/BufferedReader;
    new-instance v1, Ljava/io/FileReader;
    const-string v2, "/data/misc/pipa_port/chg_cfg25"
    invoke-direct {v1, v2}, Ljava/io/FileReader;-><init>(Ljava/lang/String;)V
    invoke-direct {v0, v1}, Ljava/io/BufferedReader;-><init>(Ljava/io/Reader;)V
    invoke-virtual {v0}, Ljava/io/BufferedReader;->readLine()Ljava/lang/String;
    move-result-object v1
    invoke-virtual {v0}, Ljava/io/BufferedReader;->close()V
    :try_end_0
    .catch Ljava/lang/Exception; {:try_start_0 .. :try_end_0} :catch_0
    if-eqz v1, :off
    const-string v2, "1+switch=1"
    invoke-virtual {v1, v2}, Ljava/lang/String;->startsWith(Ljava/lang/String;)Z
    move-result v3
    if-eqz v3, :off
    const-string v0, "1"
    return-object v0
    :catch_0
    :off
    const-string v0, "0"
    return-object v0
.end method

.method public static cap(Ljava/lang/String;)I
    .registers 4
    new-instance v0, Ljava/lang/StringBuilder;
    invoke-direct {v0}, Ljava/lang/StringBuilder;-><init>()V
    const-string v1, "/sys/class/power_supply/battery/"
    invoke-virtual {v0, v1}, Ljava/lang/StringBuilder;->append(Ljava/lang/String;)Ljava/lang/StringBuilder;
    invoke-virtual {v0, p0}, Ljava/lang/StringBuilder;->append(Ljava/lang/String;)Ljava/lang/StringBuilder;
    invoke-virtual {v0}, Ljava/lang/StringBuilder;->toString()Ljava/lang/String;
    move-result-object v0
    const/4 v2, 0x0
    invoke-static {v0, v2}, Lshim/Helper;->readInt(Ljava/lang/String;I)I
    move-result v0
    if-gtz v0, :cap_ok
    new-instance v0, Ljava/lang/StringBuilder;
    invoke-direct {v0}, Ljava/lang/StringBuilder;-><init>()V
    const-string v1, "/sys/class/power_supply/bms/"
    invoke-virtual {v0, v1}, Ljava/lang/StringBuilder;->append(Ljava/lang/String;)Ljava/lang/StringBuilder;
    invoke-virtual {v0, p0}, Ljava/lang/StringBuilder;->append(Ljava/lang/String;)Ljava/lang/StringBuilder;
    invoke-virtual {v0}, Ljava/lang/StringBuilder;->toString()Ljava/lang/String;
    move-result-object v0
    invoke-static {v0, v2}, Lshim/Helper;->readInt(Ljava/lang/String;I)I
    move-result v0
    :cap_ok
    return v0
.end method

.method public static batteryHealth()I
    .registers 3
    const-string v0, "charge_full"
    invoke-static {v0}, Lshim/Helper;->cap(Ljava/lang/String;)I
    move-result v0
    const-string v1, "charge_full_design"
    invoke-static {v1}, Lshim/Helper;->cap(Ljava/lang/String;)I
    move-result v1
    const/16 v2, 0x64
    if-lez v0, :h_def
    if-lez v1, :h_def
    mul-int/lit8 v0, v0, 0x64
    div-int/2addr v0, v1
    if-gt v0, v2, :h_def
    return v0
    :h_def
    return v2
.end method
"""
# batteryFcc: charge_full with the bms fallback
old = ('    const-string v0, "/sys/class/power_supply/battery/charge_full"\n\n    const/4 v1, 0x0\n\n'
       '    invoke-static {v0, v1}, Lshim/Helper;->readInt(Ljava/lang/String;I)I\n\n    move-result v0\n\n    div-int/lit16')
assert old in s
s = s.replace(old, '    const-string v0, "charge_full"\n\n    invoke-static {v0}, Lshim/Helper;->cap(Ljava/lang/String;)I\n\n    move-result v0\n\n    div-int/lit16')
open(helper, "w").write(s)

impl = f"{tmp}/s/shim/ChargerImpl.smali"
s = open(impl).read()
REC = "invoke-static {%s}, Lshim/Helper;->record(Ljava/lang/String;Ljava/lang/String;)V"
OK = "    move-result v0\n    if-eqz v0, :rec_f\n    const/4 v0, 0x0\n    return v0\n    :rec_f\n    const/4 v0, -0x1\n    return v0\n"
def body(sig, regs, code, tail=OK):
    global s
    a = s.index(f".method public {sig}\n")
    b = s.index(".end method", a)
    m = s[a:b]
    assert "const/4 v0, 0x0\n\n    return v0" in m, sig
    head = m[:m.index("    .annotation")]
    head = head.replace(head.split("\n")[1], f"    .registers {regs}")
    ann = m[m.index("    .annotation"):m.index(".end annotation") + len(".end annotation")]
    s = s[:a] + head + "    " + ann + "\n" + code + "\n" + tail + s[b:]
def getter(sig, reader):   # return the sysfs value instead of the constant 0
    global s
    a = s.index(f".method public {sig}\n")
    b = s.index(".end method", a)
    m = s[a:b]
    old = "    const/4 v0, 0x0\n\n    return v0"
    assert m.count(old) == 1, sig
    s = s[:a] + m.replace(old, f"    invoke-static {{}}, Lshim/Helper;->{reader}()I\n\n    move-result v0\n\n    return v0") + s[b:]

SB = ("    new-instance v0, Ljava/lang/StringBuilder;\n    invoke-direct {v0}, Ljava/lang/StringBuilder;-><init>()V\n"
      "    const-string v1, \"%s\"\n    invoke-virtual {v0, v1}, Ljava/lang/StringBuilder;->append(Ljava/lang/String;)Ljava/lang/StringBuilder;\n"
      "    invoke-virtual {v0, p1}, Ljava/lang/StringBuilder;->append(I)Ljava/lang/StringBuilder;\n"
      "    invoke-virtual {v0}, Ljava/lang/StringBuilder;->toString()Ljava/lang/String;\n    move-result-object v0\n")
REC1 = "invoke-static {%s}, Lshim/Helper;->record(Ljava/lang/String;Ljava/lang/String;)Z"
# setChgConfig: 0 = ok, but 1 for type 12 (EngineerMode clearBattEcoData tests == 1) and type 25 (bypass: the Battery
# app arms its re-send watchdog only for a non-zero return); -1 = failed
CFG = ("    move-result v1\n    if-eqz v1, :rec_f\n    const/4 v0, 0x0\n    const/16 v1, 0xc\n    if-eq p1, v1, :rec_one\n"
       "    const/16 v1, 0x19\n    if-ne p1, v1, :rec_r\n    :rec_one\n"
       "    const/4 v0, 0x1\n    :rec_r\n    return v0\n    :rec_f\n    const/4 v0, -0x1\n    return v0\n")
body("setChgConfig(ILjava/lang/String;I)I", 6, SB % "cfg" + "    " + REC1 % "v0, p2", CFG)
body("setPsyMmiChgEn(Ljava/lang/String;)I", 3, "    const-string v0, \"mmi\"\n    " + REC1 % "v0, p1")
body("setSmartChgMode(Ljava/lang/String;)I", 3, "    const-string v0, \"smart\"\n    " + REC1 % "v0, p1")
body("setCustomSelectChgMode(IZ)I", 5, SB % "sel" +
     "    const-string v1, \"0\"\n    if-eqz p2, :rec_z\n    const-string v1, \"1\"\n    :rec_z\n    " + REC1 % "v0, v1")

for sig, reader in (("getPsyBatteryLevel()I", "batteryLevel"), ("getPsyBatteryTemp()I", "batteryTemp"),
                    ("getPsyBatteryRm()I", "batteryRm"), ("getPsyBatteryFcc()I", "batteryFcc"),
                    ("getPsyBatteryCurrentNow()I", "batteryCurrent"), ("getBatteryVoltageNow()I", "batteryVoltage"),
                    ("getUIsohValue()I", "batteryHealth")):
    getter(sig, reader)
# getChgConfig: own answers for 24 (bypass status) and 31 "24"/"25" (support probe); the original method stays as
# getChgConfigOrig for every other type
GSIG = ".method public getChgConfig(ILjava/lang/String;I)Ljava/lang/String;\n"
assert s.count(GSIG) == 1, "getChgConfig not found once"
cls = s[s.index(".class "):s.index("\n", s.index(".class "))].split()[-1]
assert cls.startswith("L") and cls.endswith(";"), cls
s = s.replace(GSIG, GSIG.replace("getChgConfig(", "getChgConfigOrig("))
s += f"""
.method public getChgConfig(ILjava/lang/String;I)Ljava/lang/String;
    .registers 7
    const/16 v0, 0x18
    if-ne p1, v0, :not24
    invoke-static {{}}, Lshim/Helper;->bypassStatus()Ljava/lang/String;
    move-result-object v0
    return-object v0
    :not24
    const/16 v0, 0x1f
    if-ne p1, v0, :orig
    const-string v0, "24"
    invoke-virtual {{v0, p2}}, Ljava/lang/String;->equals(Ljava/lang/Object;)Z
    move-result v1
    if-nez v1, :sup
    const-string v0, "25"
    invoke-virtual {{v0, p2}}, Ljava/lang/String;->equals(Ljava/lang/Object;)Z
    move-result v1
    if-eqz v1, :orig
    :sup
    const-string v0, "1"
    return-object v0
    :orig
    invoke-virtual {{p0, p1, p2, p3}}, {cls}->getChgConfigOrig(ILjava/lang/String;I)Ljava/lang/String;
    move-result-object v0
    return-object v0
.end method
"""
# shim start: a hold recorded before this boot is dropped
old = "    invoke-direct {p0}, Lvendor/oplus/hardware/charger/ICharger$Stub;-><init>()V\n"
assert s.count(old) == 1
s = s.replace(old, old + "\n    invoke-static {}, Lshim/Helper;->bootCheck()V\n")
open(impl, "w").write(s)

subprocess.run(["java", "-jar", smali, "a", "-j", "1", "--api", "30", f"{tmp}/s", "-o", f"{tmp}/new.dex"], check=True)
with zipfile.ZipFile(src) as zi, zipfile.ZipFile(dst + ".tmp", "w", zipfile.ZIP_DEFLATED) as zo:
    for i in zi.infolist():
        zo.writestr(i, open(f"{tmp}/new.dex", "rb").read() if i.filename == "classes.dex" else zi.read(i))
os.replace(dst + ".tmp", dst)
print("patched", dst)
