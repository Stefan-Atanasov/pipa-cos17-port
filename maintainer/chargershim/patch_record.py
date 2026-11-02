#!/usr/bin/env python3
"""BUGS-TODO 50 (step 3z): the charger shim records the charge-control calls of ColorOS.

The original shim (binary only) answers every ICharger setter with 0 and does nothing, so "Custom charging limit" and
"Smart charging" never hold the battery level. With this patch these setters write their arguments to
/data/misc/pipa_port/chg_<name> (pipa_port holds the level with battery_charging_enabled, service.sh chg_hold):
  setChgConfig(14, "2++<on>+<level>")   -> chg_cfg14   (charging limit; Smart charging uses the same call)
  setPsyMmiChgEn("0"/"1")                -> chg_mmi
  setCustomSelectChgMode(mode, on)       -> chg_sel<mode> ("0"/"1"; 3 = smart rapid charging, 4 = single speed)
  setSmartChgMode(s)                     -> chg_smart
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
.method public static record(Ljava/lang/String;Ljava/lang/String;)V
    .registers 5
    :try_start_0
    new-instance v1, Ljava/lang/StringBuilder;
    invoke-direct {v1}, Ljava/lang/StringBuilder;-><init>()V
    const-string v2, "/data/misc/pipa_port/chg_"
    invoke-virtual {v1, v2}, Ljava/lang/StringBuilder;->append(Ljava/lang/String;)Ljava/lang/StringBuilder;
    invoke-virtual {v1, p0}, Ljava/lang/StringBuilder;->append(Ljava/lang/String;)Ljava/lang/StringBuilder;
    invoke-virtual {v1}, Ljava/lang/StringBuilder;->toString()Ljava/lang/String;
    move-result-object v1
    new-instance v0, Ljava/io/FileOutputStream;
    invoke-direct {v0, v1}, Ljava/io/FileOutputStream;-><init>(Ljava/lang/String;)V
    invoke-static {p1}, Ljava/lang/String;->valueOf(Ljava/lang/Object;)Ljava/lang/String;
    move-result-object v2
    invoke-virtual {v2}, Ljava/lang/String;->getBytes()[B
    move-result-object v2
    invoke-virtual {v0, v2}, Ljava/io/FileOutputStream;->write([B)V
    invoke-virtual {v0}, Ljava/io/FileOutputStream;->close()V
    :try_end_0
    .catch Ljava/lang/Exception; {:try_start_0 .. :try_end_0} :catch_0
    :catch_0
    return-void
.end method
"""
open(helper, "w").write(s)

impl = f"{tmp}/s/shim/ChargerImpl.smali"
s = open(impl).read()
REC = "invoke-static {%s}, Lshim/Helper;->record(Ljava/lang/String;Ljava/lang/String;)V"
def body(sig, regs, code):
    global s
    a = s.index(f".method public {sig}\n")
    b = s.index(".end method", a)
    m = s[a:b]
    assert "const/4 v0, 0x0\n\n    return v0" in m, sig
    head = m[:m.index("    .annotation")]
    head = head.replace(head.split("\n")[1], f"    .registers {regs}")
    ann = m[m.index("    .annotation"):m.index(".end annotation") + len(".end annotation")]
    s = s[:a] + head + "    " + ann + "\n" + code + "\n    const/4 v0, 0x0\n    return v0\n" + s[b:]

SB = ("    new-instance v0, Ljava/lang/StringBuilder;\n    invoke-direct {v0}, Ljava/lang/StringBuilder;-><init>()V\n"
      "    const-string v1, \"%s\"\n    invoke-virtual {v0, v1}, Ljava/lang/StringBuilder;->append(Ljava/lang/String;)Ljava/lang/StringBuilder;\n"
      "    invoke-virtual {v0, p1}, Ljava/lang/StringBuilder;->append(I)Ljava/lang/StringBuilder;\n"
      "    invoke-virtual {v0}, Ljava/lang/StringBuilder;->toString()Ljava/lang/String;\n    move-result-object v0\n")
body("setChgConfig(ILjava/lang/String;I)I", 6, SB % "cfg" + "    " + REC % "v0, p2")
body("setPsyMmiChgEn(Ljava/lang/String;)I", 3, "    const-string v0, \"mmi\"\n    " + REC % "v0, p1")
body("setSmartChgMode(Ljava/lang/String;)I", 3, "    const-string v0, \"smart\"\n    " + REC % "v0, p1")
body("setCustomSelectChgMode(IZ)I", 5, SB % "sel" +
     "    const-string v1, \"0\"\n    if-eqz p2, :rec_z\n    const-string v1, \"1\"\n    :rec_z\n    " + REC % "v0, v1")
open(impl, "w").write(s)

subprocess.run(["java", "-jar", smali, "a", "-j", "1", "--api", "30", f"{tmp}/s", "-o", f"{tmp}/new.dex"], check=True)
with zipfile.ZipFile(src) as zi, zipfile.ZipFile(dst + ".tmp", "w", zipfile.ZIP_DEFLATED) as zo:
    for i in zi.infolist():
        zo.writestr(i, open(f"{tmp}/new.dex", "rb").read() if i.filename == "classes.dex" else zi.read(i))
os.replace(dst + ".tmp", dst)
print("patched", dst)
