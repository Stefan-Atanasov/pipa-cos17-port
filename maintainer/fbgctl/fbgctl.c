/*
 * fbgctl: the OPPO frame boost call of the stock gameopt HAL (GameoptIoctl, notes/cloud/GAMEOPT-SHIM.md 4.3)
 * on /proc/oplus_frame_boost/sys_ctrl (kernel/tuning/frame_ioctl.c):
 *   fbgctl cluster <tid> <cluster>     bindMainThread: preferred cluster (0 = cpu0-3, 1 = cpu4-6, 2 = cpu7; -1 = none)
 * Exit 0 = ioctl done, 1 = bad arguments, 2 = open/ioctl error.
 */
#include <errno.h>
#include <fcntl.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/ioctl.h>
#include <sys/types.h>
#include <unistd.h>

struct ofb_ctrl_cluster { pid_t tid; int cluster_id; char reserved[32]; };
#define CMD_CLUSTER _IOWR(0xDF, 1, struct ofb_ctrl_cluster)

static int num(const char *s, long lo, long hi, long *v) {
    char *e;
    errno = 0;
    *v = strtol(s, &e, 10);
    return !errno && e != s && !*e && *v >= lo && *v <= hi;
}

int main(int argc, char **argv) {
    long a, b;
    int fd, r;
    if (argc == 4 && !strcmp(argv[1], "cluster") && num(argv[2], 1, 4194304, &a) && num(argv[3], -1, 2, &b)) {
        struct ofb_ctrl_cluster c;
        memset(&c, 0, sizeof(c));
        c.tid = (pid_t)a;
        c.cluster_id = (int)b;
        if ((fd = open("/proc/oplus_frame_boost/sys_ctrl", O_RDWR | O_CLOEXEC)) < 0) { perror("open"); return 2; }
        r = ioctl(fd, CMD_CLUSTER, &c);
    } else {
        fprintf(stderr, "usage: fbgctl cluster <tid> <-1..2>\n");
        return 1;
    }
    if (r < 0) { perror("ioctl"); close(fd); return 2; }
    close(fd);
    return 0;
}
