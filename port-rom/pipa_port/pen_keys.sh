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
	awk 'BEGIN{RS=""; FS="\n"} /Xiaomi Smart Pen Keyboard/ {
		for (i=1;i<=NF;i++) if ($i ~ /Handlers=/) {
			n = split($i, a, /[ =]/);
			for (j=1;j<=n;j++) if (a[j] ~ /^event[0-9]+$/) { print "/dev/input/" a[j]; exit }
		}
	}' /proc/bus/input/devices
}

while true; do
	node=$(find_pen_node)
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
		sleep 0.3
	else
		CUR=""
		sleep 3
	fi
done
