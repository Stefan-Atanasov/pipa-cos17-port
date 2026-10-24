/*
 * mitouch: get/set a xiaomi-touch mode (drivers/input/touchscreen/xiaomi/xiaomi_touch.c).
 *
 *   mitouch <mode> [value]     no value = GET_CUR_VALUE, value = SET_CUR_VALUE
 *
 * The driver dispatches on _IOC_NR(cmd) only and copies an int[256] from/to user space:
 * buf[0] = mode, buf[1] = value. Modes (xiaomi_touch.h): 0 Touch_Game_Mode, 9 Touch_Report_Rate,
 * 8 Touch_Panel_Orientation, 20 Touch_Pen_ENABLE, ...
 *
 * Freestanding (no libc): build with
 *   clang --target=aarch64-linux-gnu -O2 -static -nostdlib -ffreestanding -fno-stack-protector \
 *         -fuse-ld=lld -o mitouch mitouch.c
 */
typedef unsigned long u64;

static long sys(long n, long a, long b, long c, long d) {
    register long x8 __asm__("x8") = n;
    register long x0 __asm__("x0") = a;
    register long x1 __asm__("x1") = b;
    register long x2 __asm__("x2") = c;
    register long x3 __asm__("x3") = d;
    __asm__ volatile("svc #0" : "+r"(x0) : "r"(x8), "r"(x1), "r"(x2), "r"(x3) : "memory");
    return x0;
}
#define SYS_openat 56
#define SYS_ioctl 29
#define SYS_write 64
#define SYS_exit 93
#define AT_FDCWD -100
#define O_RDWR 2
#define IOC(nr) ((3UL << 30) | (1024UL << 16) | ('t' << 8) | (nr))

static int buf[256];

static void out(const char *s) { int n = 0; while (s[n]) n++; sys(SYS_write, 1, (long)s, n, 0); }
static void outnum(long v) {
    char t[24]; int i = 23; int neg = v < 0; t[i] = 0;
    if (neg) v = -v;
    do { t[--i] = '0' + v % 10; v /= 10; } while (v);
    if (neg) t[--i] = '-';
    out(t + i);
}
static long num(const char *s) {
    long v = 0; int neg = 0;
    if (*s == '-') { neg = 1; s++; }
    while (*s >= '0' && *s <= '9') v = v * 10 + (*s++ - '0');
    return neg ? -v : v;
}

void main_c(long argc, char **argv) {
    if (argc < 2) { out("usage: mitouch <mode> [value]\n"); sys(SYS_exit, 2, 0, 0, 0); }
    long fd = sys(SYS_openat, AT_FDCWD, (long)"/dev/xiaomi-touch", O_RDWR, 0);
    if (fd < 0) { out("open /dev/xiaomi-touch failed: "); outnum(fd); out("\n"); sys(SYS_exit, 1, 0, 0, 0); }
    buf[0] = (int)num(argv[1]);
    long nr = 1; /* GET_CUR_VALUE */
    if (argc > 2) { buf[1] = (int)num(argv[2]); nr = 0; /* SET_CUR_VALUE */ }
    long r = sys(SYS_ioctl, fd, IOC(nr), (long)buf, 0);
    out(nr ? "get " : "set "); outnum(num(argv[1]));
    out(" -> ret "); outnum(r); out(" buf0 "); outnum(buf[0]); out("\n");
    sys(SYS_exit, r < 0, 0, 0, 0);
}

__asm__(".globl _start\n_start:\n ldr x0, [sp]\n add x1, sp, #8\n bl main_c\n");
