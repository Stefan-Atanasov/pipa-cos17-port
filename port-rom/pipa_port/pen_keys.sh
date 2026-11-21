#!/system/bin/sh
# 监听小米笔的 HID 键盘设备（"Xiaomi Smart Pen Keyboard"），把两个笔身按键映射成动作。
#
# HyperOS 上是 MIUI 的手写笔服务做这件事；ColorOS 只认自家 OPPO Pencil
# （com.oplus.ipemanager），所以小米笔的按键发出来的 KEY_PAGEUP / KEY_PAGEDOWN
# 没人处理 —— 表现就是"按键没反应"。
#
# 两个物理键（实测）：
#   KEY_PAGEUP   = 截图键（副键，离笔尖远）
#   KEY_PAGEDOWN = 速记键（主键，靠笔尖）
#
# 映射在 keys.conf 里改，值支持四种写法：
#   120                     数字 = Android keycode（120=截屏SYSRQ, 4=返回, 3=Home, 187=最近任务）
#   none                    不动作
#   app:包名/Activity        启动一个 Activity
#   cmd:<shell 命令>         直接跑命令

MODDIR=${0%/*}
CONF="$MODDIR/keys.conf"
[ -f "$CONF" ] && . "$CONF"
PAGEUP_ACTION=${pageup:-120}
PAGEDOWN_ACTION=${pagedown:-4}
LOG=/data/local/tmp/pipa_pen.log
CUR=""
PIDF=/data/local/tmp/pipa_pen_keys.pid

# 单实例：如果已有同类实例在跑就直接退出，避免重复监听导致按键双触发。
# （pid 文件跨重启可能残留，所以要核对 /proc/<pid>/cmdline 确实是 pen_keys.sh）
if [ -f "$PIDF" ]; then
	old=$(cat "$PIDF" 2>/dev/null)
	if [ -n "$old" ] && [ "$old" != "$$" ] && kill -0 "$old" 2>/dev/null \
	   && [ -r "/proc/$old/cmdline" ] \
	   && tr '\0' ' ' < "/proc/$old/cmdline" | grep -q 'pen_keys.sh'; then
		echo "$(date) another pen_keys instance ($old) is alive, exiting" >> $LOG
		exit 0
	fi
fi
echo $$ > "$PIDF"

# The actions go through `cmd` (input, am), which hands the caller's stdin/stdout/stderr to the
# system server over binder. Here stdin is the getevent pipe, labelled with our own domain, and
# system_server may not use it: the call then fails with "Failed transaction (2147483646)" and
# nothing happens (beta5-2e, domain pipa_port; the old ksu domain was allowed everything).
# So give every action plain /dev/null streams.
run_action() {
	case "$1" in
		""|none) return ;;
		cmd:*) sh -c "${1#cmd:}" >/dev/null 2>&1 ;;
		app:*) am start -n "${1#app:}" >/dev/null 2>&1 ;;
		*[!0-9]*) sh -c "$1" >/dev/null 2>&1 ;;
		*) input keyevent "$1" ;;
	esac
}

find_pen_node() {
	awk -v name="${1:-Xiaomi Smart Pen Keyboard}" 'BEGIN{RS=""; FS="\n"} index($0, "Name=\"" name "\"") {
		for (i=1;i<=NF;i++) if ($i ~ /Handlers=/) {
			n = split($i, a, /[ =]/);
			for (j=1;j<=n;j++) if (a[j] ~ /^event[0-9]+$/) { print "/dev/input/" a[j]; exit }
		}
	}' /proc/bus/input/devices
}

# nap: wait without a sleep process (see service.sh)
NAP_FIFO=/data/misc/pipa_port/nap_keys.fifo
rm -f "$NAP_FIFO"
if mkfifo "$NAP_FIFO" 2>/dev/null && exec 8<>"$NAP_FIFO"; then
	nap() { read -t "$1" -u8 _ 2>/dev/null; }
else
	nap() { sleep "$1"; }
fi
# ---------------------------------------------------------------- BUGS 153 (kernel walt-hi12 and later)
# The kernel (pipa_pen_buttons.c) owns the Bluetooth keys of the pen and decides each press once: near the screen =
# stylus buttons in the pen events; away = a short press (page keys; far_mode 3: KEY_F21 front / KEY_F22 back), a
# double press (far_mode 3 with double_ms: KEY_F19 / KEY_F20) or a long press (KEY_F23 / KEY_F24, held for long_ms),
# on the virtual device "pipa_pen_buttons". Here: the actions, and the settings of the helper screen "Pen buttons"
# (global pipa_pen_buttons = "<far_mode> <long_ms> <front long> <back long> <front short> <back short>
# <front double> <back double>") into the kernel. While that screen is open (global pipa_pen_test = 1), a press goes
# to the helper as a broadcast instead of its action.
# Without the virtual device (older kernel) the old Bluetooth listener below runs (keys.conf).
PG_F=/data/local/tmp/pipa_pen.sget
sget2() {   # sget2 <namespace> <key>
	: > "$PG_F"
	settings get "$1" "$2" </dev/null >"$PG_F" 2>/dev/null || return 1
	v=; read -r v < "$PG_F"
	echo "${v:-null}"
}
pget() { sget2 global "$1"; }
PEN_CFG=-
PEN_DEFAULT="1 500 quicknote screenshot none none none none"   # v9.3: long press 500 ms (BUGS 169)
set -- $PEN_DEFAULT; LONG_FRONT=$3; LONG_BACK=$4; SHORT_FRONT=$5; SHORT_BACK=$6; DBL_FRONT=$7; DBL_BACK=$8
pen_cfg() {   # the actions (the service applies far_mode, long_ms and double_ms to the kernel)
	c=$(pget pipa_pen_buttons) || return
	[ "$c" = null ] && c=$PEN_DEFAULT
	[ "$c" = "$PEN_CFG" ] && return
	PEN_CFG=$c
	set -f; set -- $c; set +f
	LONG_FRONT=${3:-quicknote}; LONG_BACK=${4:-screenshot}; SHORT_FRONT=${5:-none}; SHORT_BACK=${6:-none}
	DBL_FRONT=${7:-none}; DBL_BACK=${8:-none}
}
pen_action() {
	case "$1" in
		screenshot) run_action 120 ;;
		quicknote) run_action "cmd:am start -a action.nearme.note.add.quicknote -p com.coloros.note" ;;
		quickpaint) run_action "cmd:am start -a com.oplus.note.quick_paint -p com.coloros.note" ;;
		circle) run_action "app:com.port.pipa.helper/.CircleSearchActivity" ;;
		playpause) run_action 85 ;;
		next) run_action 87 ;;
		previous) run_action 88 ;;
		volup) run_action 24 ;;
		voldown) run_action 25 ;;
		lock) run_action 223 ;;
		notifications) run_action "cmd:cmd statusbar expand-notifications" ;;
		quicksettings) run_action "cmd:cmd statusbar expand-settings" ;;
		camera) run_action "cmd:am start -a android.media.action.STILL_IMAGE_CAMERA" ;;
		assistant) run_action 231 ;;
		flashlight) run_action "cmd:am broadcast -n com.port.pipa.helper/.PenActionReceiver -a com.port.pipa.helper.TORCH" ;;
		dnd) if [ "$(pget zen_mode)" = 0 ]; then run_action "cmd:cmd notification set_dnd priority"
			else run_action "cmd:cmd notification set_dnd off"; fi ;;
		rotate) if [ "$(sget2 system accelerometer_rotation)" = 1 ]; then run_action "cmd:settings put system accelerometer_rotation 0"
			else run_action "cmd:settings put system accelerometer_rotation 1"; fi ;;
		back) run_action 4 ;;
		home) run_action 3 ;;
		recents) run_action 187 ;;
		none) ;;
		app:*)   # only package/activity names: the setting is writable by any app with WRITE_SECURE_SETTINGS
			c=${1#app:}
			case "$c" in
				*[!A-Za-z0-9_./\$]*|*/*/*|/*|*/) echo "$(date +%H:%M:%S) rejected action $1" >> $LOG ;;
				*/*) am start -n "$c" </dev/null >/dev/null 2>&1 ;;
				*) echo "$(date +%H:%M:%S) rejected action $1" >> $LOG ;;
			esac ;;
		*[!0-9]*|"") echo "$(date +%H:%M:%S) rejected action $1" >> $LOG ;;   # never cmd: or a shell string
		*) input keyevent "$1" </dev/null >/dev/null 2>&1 ;;
	esac
}
# BUGS 153: a short stylus-button press (kernel KEY_F13 front / KEY_F14 back) as an OPPO pencil click, the same
# broadcasts as IPeManager 17.4.0 sends for an OPPO pen (k0.e): front = double click (Notes: pen <-> eraser, mode
# ipe_pencil_double_click, default 1), back = single click (mode ipe_pencil_single_click, default 4 = global wheel in
# HealthService). Mode 0 = off. Only the OPPO apps that hold the DOUBLE_CLICK permission receive it.
ipe_click() {
	if [ "$1" = 0 ]; then k=ipe_pencil_double_click; m=1; a=PENCIL_DOUBLE_CLICK; else k=ipe_pencil_single_click; m=4; a=PENCIL_SINGLE_CLICK; fi
	v=$(pget $k) || return
	case "$v" in null) ;; [0-9]) m=$v ;; *) return ;; esac
	[ "$m" = 0 ] && return
	set -- -a "com.oplus.ipemanager.action.$a" -f 0x10000000 \
		--receiver-permission com.oplus.ipemanager.permission.receiver.DOUBLE_CLICK
	[ "$m" = 4 ] && set -- "$@" -p com.oplus.healthservice
	[ "$a" = PENCIL_SINGLE_CLICK ] && set -- "$@" --ei action "$m"
	am broadcast "$@" </dev/null >/dev/null 2>&1
}
# BUGS 155: the keyboard's Super key pressed alone (kernel: nanosic super_alone = 1, KEY_F18 on the virtual device).
# Global pipa_kb_super = an action of pen_action (Pipa Helper > Keyboard case > Super key); "default" = the service
# leaves super_alone at 0 and Android handles the key as stock.
kb_super() {
	a=$(pget pipa_kb_super) || return
	case "$a" in null|default) return ;; esac
	bl=0; read -r bl < /sys/class/backlight/panel0-backlight/brightness 2>/dev/null
	[ "${bl:-0}" -le 0 ] && return
	pen_action "$a" </dev/null >/dev/null 2>&1
	echo "$(date +%H:%M:%S) super -> $a" >> $LOG
}
pen_press() {   # $1: 0 = front, 1 = back; $2: short, double or long
	pen_cfg
	if [ "$(pget pipa_pen_test)" = 1 ]; then
		am broadcast -a com.port.pipa.helper.PEN_ACTION -p com.port.pipa.helper --ei button "$1" --es kind "$2" \
			</dev/null >/dev/null 2>&1
		echo "$(date +%H:%M:%S) $2 $1 -> helper test screen" >> $LOG
		return
	fi
	bl=0; read -r bl < /sys/class/backlight/panel0-backlight/brightness 2>/dev/null
	if [ "${bl:-0}" -le 0 ]; then echo "$(date +%H:%M:%S) $2 $1: screen off, skipped" >> $LOG; return; fi
	case "$1$2" in
		0long) a=$LONG_FRONT ;; 1long) a=$LONG_BACK ;; 0short) a=$SHORT_FRONT ;; 1short) a=$SHORT_BACK ;;
		0double) a=$DBL_FRONT ;; *) a=$DBL_BACK ;;
	esac
	pen_action "$a" </dev/null >/dev/null 2>&1
	echo "$(date +%H:%M:%S) $2 $1 -> $a" >> $LOG
}
vnode=$(find_pen_node pipa_pen_buttons)
if [ -n "$vnode" ]; then
	echo "$(date) kernel pen buttons on $vnode" >> $LOG
	while true; do
		# blocks until a key: no wakeups while idle (the virtual device never goes away)
		/system/bin/getevent -lt "$vnode" 2>/dev/null | while read -r line; do
			case "$line" in
				*KEY_F18*DOWN*) kb_super ;;
				*KEY_F13*DOWN*) ipe_click 0 ;;
				*KEY_F14*DOWN*) ipe_click 1 ;;
				*KEY_F19*DOWN*) pen_press 0 double ;;
				*KEY_F20*DOWN*) pen_press 1 double ;;
				*KEY_F21*DOWN*) pen_press 0 short ;;
				*KEY_F22*DOWN*) pen_press 1 short ;;
				*KEY_F23*DOWN*) pen_press 0 long ;;
				*KEY_F24*DOWN*) pen_press 1 long ;;
			esac
		done
		nap 1
	done
fi

DEVS_SEEN=-
while true; do
	# awk only when the input device list changed (builtin read of /proc/bus/input/devices)
	devs=$(< /proc/bus/input/devices)
	if [ "$devs" != "$DEVS_SEEN" ] || [ -z "$node" ]; then node=$(find_pen_node); DEVS_SEEN=$devs; fi
	if [ -n "$node" ] && [ -e "$node" ]; then
		if [ "$node" != "$CUR" ]; then
			echo "$(date) key listener on $node" >> $LOG
			CUR="$node"
		fi
		# 3 秒一轮：笔蓝牙重连会让 HID 设备重建（节点号可能变、旧 fd 变成死节点），
		# 卡死的 getevent 不会退出，所以这里用 timeout 定期重挂 —— 这正是
		# "重连之后按钮就挂了" 的原因。
		# 注意：设备被拔掉时 getevent 会抱着死 fd 空转烧 CPU，所以超时只能给 2 秒，
		# 而且下面必须补一个 sleep，避免节点异常时把循环打成高频重启。
		timeout 2 /system/bin/getevent -lt "$node" 2>/dev/null | while read -r line; do
			case "$line" in
				*KEY_PAGEUP*DOWN*)
					run_action "$PAGEUP_ACTION" </dev/null >/dev/null 2>&1
					echo "$(date +%H:%M:%S) pageup -> $PAGEUP_ACTION" >> $LOG
					;;
				*KEY_PAGEDOWN*DOWN*)
					run_action "$PAGEDOWN_ACTION" </dev/null >/dev/null 2>&1
					echo "$(date +%H:%M:%S) pagedown -> $PAGEDOWN_ACTION" >> $LOG
					;;
			esac
		done
		nap 0.3
	else
		CUR=""
		nap 3
	fi
done
