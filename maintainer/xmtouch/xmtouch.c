/* xmtouch: get/set Xiaomi touch IC modes through /dev/xiaomi-touch (the kernel xiaomi_touch interface that HyperOS's
 * touchfeature HAL uses; the port ships no such HAL). Test tool for BUGS 117 (game mode, panel orientation).
 *   xmtouch get <mode>            current value (GET_CUR_VALUE)
 *   xmtouch info <mode>           cur/def/min/max
 *   xmtouch set <mode> <value>    SET_CUR_VALUE (nt36532 applies it in a workqueue, 40 ms per changed mode)
 * Modes (pipa, NEW_GAME_MODE): 0 Game_Mode, 2 UP_THRESHOLD, 3 Tolerance, 4 Aim_Sensitivity, 5 Tap_Stability,
 * 6 Expert_Mode, 7 Edge_Filter, 8 Panel_Orientation (0 = 0 deg, 1 = 90, 2 = 180, 3 = 270), 12 Resist_RF.
 * The kernel reads only _IOC_NR(cmd): 0 SET_CUR, 1 GET_CUR, 2 GET_DEF, 3 GET_MIN, 4 GET_MAX. Build: build.sh. Root. */
#include <fcntl.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/ioctl.h>
#include <unistd.h>

static int fd;
static int call(int nr, int mode, int value)
{
	int buf[256];
	memset(buf, 0, sizeof(buf));
	buf[0] = mode; buf[1] = value;
	if (ioctl(fd, _IOWR('T', nr, int[256]), buf) < 0) { perror("ioctl"); exit(1); }
	return buf[0];
}

int main(int argc, char **argv)
{
	if (argc < 3) { fprintf(stderr, "usage: xmtouch get|info <mode> | set <mode> <value>\n"); return 2; }
	fd = open("/dev/xiaomi-touch", O_RDWR);
	if (fd < 0) { perror("/dev/xiaomi-touch"); return 1; }
	int mode = atoi(argv[2]);
	if (!strcmp(argv[1], "get")) printf("%d\n", call(1, mode, 0));
	else if (!strcmp(argv[1], "info")) printf("cur %d def %d min %d max %d\n", call(1, mode, 0), call(2, mode, 0), call(3, mode, 0), call(4, mode, 0));
	else if (!strcmp(argv[1], "set") && argc == 4) printf("set %d -> ret %d\n", atoi(argv[3]), call(0, mode, atoi(argv[3])));
	else { fprintf(stderr, "bad arguments\n"); return 2; }
	return 0;
}
