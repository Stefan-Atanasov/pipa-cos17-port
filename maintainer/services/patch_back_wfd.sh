#!/bin/bash
# services.jar patches (2026-11-20):
# * BUGS 157: WindowManagerService.moveFocusToAdjacentEmbeddedWindow(WindowState) returns false while the keyboard is
#   showing for the focused window. AOSP PhoneWindowManager calls it on back key-down; it moved focus to the other
#   pane of an activity-embedding split (two-pane Settings), so a back meant to close the keyboard closed the pane
#   and with it all of Settings. With the check, the window that owns the keyboard keeps the back key and the
#   keyboard closes (as in a single-pane app). Without the keyboard, back works as AOSP.
# * BUGS 158: WifiDisplayController.updateConnection sets WifiP2pConfig.netId = -1 (temporary group) after OPPO's
#   generateConfigByGoIntent and before WifiP2pManager.connect. Miracast then pairs fresh each time (WPS PBC) and
#   saves no persistent group: Windows makes a new key each session, so a saved group failed (PSK failure) and its
#   leftover in p2p_supplicant.conf blocked the next fresh pairing. Persistent flag in the wifi service: netId == -2.
#   patch_back_wfd.sh <services.jar in> <services.jar out>
# Needs JDK 21, ~/Android/Sdk build-tools 37, tools/smali (2.5.2). Stops on any surprise. smali/baksmali with -j 1.
set -euo pipefail
IN=$(realpath "$1"); OUT=$(realpath -m "$2")
HERE=$(cd "$(dirname "$0")" && pwd)
SMALI=$HERE/../../../tools/smali
SDK=${ANDROID_HOME:-$HOME/Android/Sdk}; BT=$SDK/build-tools/37.0.0
W=$(mktemp -d); trap 'rm -rf "$W"' EXIT
WMS=com/android/server/wm/WindowManagerService.smali
WDC=com/android/server/display/WifiDisplayController.smali

unzip -q "$IN" 'classes*.dex' -d "$W"
DEX_WMS=; DEX_WDC=
for d in "$W"/classes*.dex; do
    n=$(basename "$d" .dex)
    java -jar "$SMALI/baksmali-2.5.2.jar" d -j 1 -a 36 "$d" -o "$W/sm_$n"
    [ -f "$W/sm_$n/$WMS" ] && DEX_WMS=$n
    [ -f "$W/sm_$n/$WDC" ] && DEX_WDC=$n
done
[ -n "$DEX_WMS" ] && [ -n "$DEX_WDC" ] || { echo "WindowManagerService or WifiDisplayController not found"; exit 1; }

python3 -I - "$W/sm_$DEX_WMS/$WMS" "$W/sm_$DEX_WDC/$WDC" <<'PY'
import sys
wms, wdc = sys.argv[1:]

# --- BUGS 157
s = open(wms).read()
head = '.method moveFocusToAdjacentEmbeddedWindow(Lcom/android/server/wm/WindowState;)Z\n    .registers 5\n'
assert s.count(head) == 1, 'moveFocusToAdjacentEmbeddedWindow (.registers 5) not found once'
if 'pipa_ime_keeps_focus' not in s:
    a = s.index(head) + len(head)
    p = s.index('    .param p1', a); assert p < s.index('.end method', a), '.param p1 not in the method'
    a = s.index('\n', p) + 1   # after the .param line
    ins = '''
    # pipa (BUGS 157): the window that owns the shown keyboard keeps the back key
    invoke-virtual {p1}, Lcom/android/server/wm/WindowState;->getDisplayContent()Lcom/android/server/wm/DisplayContent;
    move-result-object v0
    if-eqz v0, :pipa_ime_keeps_focus
    invoke-virtual {v0}, Lcom/android/server/wm/DisplayContent;->getImeInputTarget()Lcom/android/server/wm/InputTarget;
    move-result-object v1
    if-eqz v1, :pipa_ime_keeps_focus
    invoke-interface {v1}, Lcom/android/server/wm/InputTarget;->getWindowState()Lcom/android/server/wm/WindowState;
    move-result-object v1
    if-ne v1, p1, :pipa_ime_keeps_focus
    invoke-virtual {v0}, Lcom/android/server/wm/DisplayContent;->getInsetsStateController()Lcom/android/server/wm/InsetsStateController;
    move-result-object v0
    invoke-virtual {v0}, Lcom/android/server/wm/InsetsStateController;->getImeSourceProvider()Lcom/android/server/wm/ImeInsetsSourceProvider;
    move-result-object v0
    invoke-virtual {v0}, Lcom/android/server/wm/ImeInsetsSourceProvider;->isImeShowing()Z
    move-result v0
    if-eqz v0, :pipa_ime_keeps_focus
    const/4 v0, 0x0
    return v0

    :pipa_ime_keeps_focus
'''
    s = s[:a] + ins + s[a:]
    open(wms, 'w').write(s)
print('patched: moveFocusToAdjacentEmbeddedWindow keeps focus while the keyboard shows (BUGS 157)')

# --- BUGS 158
s = open(wdc).read()
call = ('    invoke-interface {v2, v0, v7}, Lcom/android/server/display/IWifiDisplayControllerExt;->generateConfigByGoIntent'
        '(Landroid/net/wifi/p2p/WifiP2pConfig;Landroid/net/wifi/p2p/WifiP2pDevice;)Landroid/net/wifi/p2p/WifiP2pConfig;\n')
assert s.count(call) == 1, 'generateConfigByGoIntent call not found once'
a = s.index(call) + len(call)
mr = '\n    move-result-object v0\n'
assert s[a:a + len(mr)] == mr, 'move-result-object v0 does not follow'
a += len(mr)
nxt = s[a:a + 400]
assert 'iget-object v2, p0, Lcom/android/server/display/WifiDisplayController;->mConnectingDevice' in nxt, 'v2 not reloaded after the call'
if 'pipa (BUGS 158)' not in s:
    ins = ('\n    # pipa (BUGS 158): temporary group, no saved Miracast group (Windows new key each session)\n'
           '    const/4 v2, -0x1\n'
           '    iput v2, v0, Landroid/net/wifi/p2p/WifiP2pConfig;->netId:I\n')
    s = s[:a] + ins + s[a:]
    open(wdc, 'w').write(s)
print('patched: WifiDisplayController connects with netId -1 (BUGS 158)')

# --- BUGS 158 part 2: Windows keeps its own GO group and the supplicant saves it as persistent when the tablet joins
# it (P2P-GROUP-STARTED ... [PERSISTENT]); the next connect re-invokes it with the old key (PSK failure). The group
# id from the connection's group info is kept (netId + 1, 0 = none) and that group is deleted before the next
# connect and after a normal disconnect (as "delete" in Wi-Fi Direct settings).
s = open(wdc).read()
if 'pipaDeleteWfdGroup' not in s:
    C = 'Lcom/android/server/display/WifiDisplayController;'
    f = '.field private mConnectedDeviceGroupInfo:Landroid/net/wifi/p2p/WifiP2pGroup;\n'
    assert s.count(f) == 1, 'mConnectedDeviceGroupInfo field not found once'
    s = s.replace(f, f + '\n.field private pipaWfdNetId:I\n')
    setter = ('.method static bridge synthetic -$$Nest$fputmConnectedDeviceGroupInfo(' + C + 'Landroid/net/wifi/p2p/WifiP2pGroup;)V\n'
              '    .registers 2\n\n'
              '    iput-object p1, p0, ' + C + '->mConnectedDeviceGroupInfo:Landroid/net/wifi/p2p/WifiP2pGroup;\n\n'
              '    return-void\n.end method\n')
    assert s.count(setter) == 1, 'group info setter not found once'
    s = s.replace(setter, '.method static bridge synthetic -$$Nest$fputmConnectedDeviceGroupInfo(' + C + 'Landroid/net/wifi/p2p/WifiP2pGroup;)V\n'
        '    .registers 3\n\n'
        '    iput-object p1, p0, ' + C + '->mConnectedDeviceGroupInfo:Landroid/net/wifi/p2p/WifiP2pGroup;\n'
        '    # pipa (BUGS 158): remember the saved group of this connection\n'
        '    if-eqz p1, :pipa_ret\n'
        '    invoke-virtual {p1}, Landroid/net/wifi/p2p/WifiP2pGroup;->getNetworkId()I\n'
        '    move-result v0\n'
        '    if-ltz v0, :pipa_ret\n'
        '    add-int/lit8 v0, v0, 0x1\n'
        '    iput v0, p0, ' + C + '->pipaWfdNetId:I\n'
        '    :pipa_ret\n'
        '    return-void\n.end method\n\n'
        '.method private pipaDeleteWfdGroup()V\n'
        '    .registers 5\n'
        '    iget v0, p0, ' + C + '->pipaWfdNetId:I\n'
        '    if-lez v0, :pipa_none\n'
        '    add-int/lit8 v0, v0, -0x1\n'
        '    const/4 v1, 0x0\n'
        '    iput v1, p0, ' + C + '->pipaWfdNetId:I\n'
        '    iget-object v2, p0, ' + C + '->mWifiP2pManager:Landroid/net/wifi/p2p/WifiP2pManager;\n'
        '    iget-object v3, p0, ' + C + '->mWifiP2pChannel:Landroid/net/wifi/p2p/WifiP2pManager$Channel;\n'
        '    if-eqz v2, :pipa_none\n'
        '    if-eqz v3, :pipa_none\n'
        '    invoke-virtual {v2, v3, v0, v1}, Landroid/net/wifi/p2p/WifiP2pManager;->deletePersistentGroup(Landroid/net/wifi/p2p/WifiP2pManager$Channel;ILandroid/net/wifi/p2p/WifiP2pManager$ActionListener;)V\n'
        '    const-string v1, "WifiDisplayController"\n'
        '    const-string v2, "pipa: deleted the saved Miracast group (BUGS 158)"\n'
        '    invoke-static {v1, v2}, Landroid/util/Slog;->i(Ljava/lang/String;Ljava/lang/String;)I\n'
        '    :pipa_none\n'
        '    return-void\n.end method\n')
    # before each new connection
    nc = '    new-instance v0, Landroid/net/wifi/p2p/WifiP2pConfig;\n'
    assert s.count(nc) == 1, 'WifiP2pConfig creation not found once'
    s = s.replace(nc, '    invoke-direct {p0}, ' + C + '->pipaDeleteWfdGroup()V\n\n' + nc)
    # after a normal disconnect (removeGroup of the connected device)
    rg = ('    invoke-virtual {v1, v2, v3}, Landroid/net/wifi/p2p/WifiP2pManager;->removeGroup(Landroid/net/wifi/p2p/WifiP2pManager$Channel;'
          'Landroid/net/wifi/p2p/WifiP2pManager$ActionListener;)V\n')
    n = s.count(rg)
    assert n >= 1, 'removeGroup call not found'
    a = s.index('const-string v2, "Disconnecting from Wifi display: "')
    b = s.index(rg, a)
    s = s[:b + len(rg)] + '\n    invoke-direct {p0}, ' + C + '->pipaDeleteWfdGroup()V\n' + s[b + len(rg):]
    open(wdc, 'w').write(s)
print('patched: WifiDisplayController deletes the saved Miracast group before a connect and after a disconnect (BUGS 158)')
PY

for n in $(printf '%s\n' "$DEX_WMS" "$DEX_WDC" | sort -u); do
    java -jar "$SMALI/smali-2.5.2.jar" a -j 1 -a 36 "$W/sm_$n" -o "$W/$n.dex.new"
done
python3 -I - "$IN" "$OUT" "$W" "$DEX_WMS" "$DEX_WDC" <<'PY'
import sys, zipfile, os
src, dst, w, *names = sys.argv[1:]
new = {n + '.dex': os.path.join(w, n + '.dex.new') for n in set(names)}
with zipfile.ZipFile(src) as zi, zipfile.ZipFile(dst + '.tmp', 'w') as zo:
    for e in zi.infolist():
        data = open(new[e.filename], 'rb').read() if e.filename in new else zi.read(e)
        n = zipfile.ZipInfo(e.filename, e.date_time); n.compress_type = e.compress_type; n.external_attr = e.external_attr
        zo.writestr(n, data)
PY
"$BT/zipalign" -f -p 4 "$OUT.tmp" "$OUT"; rm -f "$OUT.tmp"
"$BT/zipalign" -c -p 4 "$OUT" >/dev/null && echo "ok: $OUT $(md5sum < "$OUT" | cut -c1-32)"
