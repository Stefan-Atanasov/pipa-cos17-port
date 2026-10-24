/* kgest: finger-like taps and swipes through the touchscreen's kernel input device, so the kernel's input handlers
 * and InputReader see a real touch (unlike `input swipe`, which is injected above the kernel).
 *   kgest tap X Y                    (display pixels, landscape rotation 90, like ktap.sh)
 *   kgest swipe X1 Y1 X2 Y2 MS       (moves every 4 ms ~ 240 Hz touch report rate, ease-out like a fling)
 * Device: $KTAP_DEV (default /dev/input/event8, NVTCapacitiveTouchScreen, panel 1800x2880 px, 10 units/px).
 * Build: maintainer/kgest/build.sh (NDK). Needs root. */
#include <fcntl.h>
#include <linux/input.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>
#include <unistd.h>

static int fd;
static void ev(int type, int code, int val)
{
	struct input_event e;
	memset(&e, 0, sizeof(e));
	e.type = type; e.code = code; e.value = val;
	if (write(fd, &e, sizeof(e)) != sizeof(e)) { perror("write"); exit(1); }
}
static void pos(int x, int y)	/* ROTATION_90: panel_x = W - y, panel_y = x */
{
	ev(EV_ABS, ABS_MT_POSITION_X, (1800 - y) * 10);
	ev(EV_ABS, ABS_MT_POSITION_Y, x * 10);
}
static void down(int x, int y)
{
	ev(EV_ABS, ABS_MT_SLOT, 0);
	ev(EV_ABS, ABS_MT_TRACKING_ID, getpid() % 60000 + 1);
	pos(x, y);
	ev(EV_ABS, ABS_MT_TOUCH_MAJOR, 6);
	ev(EV_ABS, ABS_MT_PRESSURE, 60);
	ev(EV_KEY, BTN_TOUCH, 1);
	ev(EV_SYN, SYN_REPORT, 0);
}
static void up(void)
{
	ev(EV_ABS, ABS_MT_TRACKING_ID, -1);
	ev(EV_KEY, BTN_TOUCH, 0);
	ev(EV_SYN, SYN_REPORT, 0);
}
static void sleep_us(long us)
{
	struct timespec t = { us / 1000000, (us % 1000000) * 1000 };
	nanosleep(&t, NULL);
}

int main(int argc, char **argv)
{
	const char *dev = getenv("KTAP_DEV");
	fd = open(dev ? dev : "/dev/input/event8", O_WRONLY);
	if (fd < 0) { perror("open"); return 1; }
	if (argc == 4 && !strcmp(argv[1], "tap")) {
		down(atoi(argv[2]), atoi(argv[3]));
		sleep_us(40000);
		up();
		return 0;
	}
	if (argc == 7 && !strcmp(argv[1], "swipe")) {
		int x1 = atoi(argv[2]), y1 = atoi(argv[3]), x2 = atoi(argv[4]), y2 = atoi(argv[5]);
		int ms = atoi(argv[6]), n = ms / 4 > 1 ? ms / 4 : 1;
		down(x1, y1);
		for (int i = 1; i <= n; i++) {
			double t = (double)i / n, f = 1 - (1 - t) * (1 - t);	/* ease-out */
			sleep_us(4000);
			pos(x1 + (int)((x2 - x1) * f), y1 + (int)((y2 - y1) * f));
			ev(EV_SYN, SYN_REPORT, 0);
		}
		up();
		return 0;
	}
	fprintf(stderr, "usage: kgest tap X Y | kgest swipe X1 Y1 X2 Y2 MS\n");
	return 2;
}
