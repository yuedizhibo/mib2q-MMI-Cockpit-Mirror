/*
 * Experimental, opt-in full-MMI display mirror for Audi MHI2Q / QNX 6.5.
 *
 * This library is loaded into dio_manager next to the existing RGI hook.  It
 * is inert unless the SD-card arm file exists.  When armed, it captures the
 * complete 1024x480 MMI display with the privileged QNX Screen API and exposes
 * the pixels on a loopback-only RFB 3.3 server.  screen_read_display returns
 * the compositor's final output, including stock HMI, media and CarPlay.
 *
 * No QNX headers are included on purpose: the build host does not contain the
 * proprietary QNX SDK.  The declarations and enum values below are from the
 * public QNX 6.5 Screen API documentation.  Runtime functions are resolved
 * from the target's own libraries.
 */

typedef unsigned char u8;
typedef unsigned short u16;
typedef unsigned int u32;
typedef unsigned long size_t;
typedef long ssize_t;
typedef void *screen_context_t;
typedef void *screen_pixmap_t;
typedef void *screen_buffer_t;
typedef void *screen_window_t;
typedef void *screen_display_t;
typedef unsigned long pthread_t;

struct in_addr { u32 s_addr; };
struct sockaddr { u8 sa_len; u8 sa_family; char sa_data[14]; };
struct sockaddr_in {
    u8 sin_len;
    u8 sin_family;
    u16 sin_port;
    struct in_addr sin_addr;
    char sin_zero[8];
};
struct timeval { long tv_sec; long tv_usec; };

typedef void *(*alloc_func)(void *, unsigned int, unsigned int);
typedef void (*free_func)(void *, void *);
typedef struct z_stream_s {
    u8 *next_in;
    unsigned int avail_in;
    unsigned long total_in;
    u8 *next_out;
    unsigned int avail_out;
    unsigned long total_out;
    char *msg;
    void *state;
    alloc_func zalloc;
    free_func zfree;
    void *opaque;
    int data_type;
    unsigned long adler;
    unsigned long reserved;
} z_stream;

extern void *dlopen(const char *, int);
extern void *dlsym(void *, const char *);
extern int access(const char *, int);
extern void *malloc(size_t);
extern void free(void *);
extern void *memset(void *, int, size_t);
extern void *memcpy(void *, const void *, size_t);
extern int socket(int, int, int);
extern int bind(int, const struct sockaddr *, int);
extern int listen(int, int);
extern int accept(int, struct sockaddr *, int *);
extern int setsockopt(int, int, int, const void *, int);
extern ssize_t recv(int, void *, size_t, int);
extern ssize_t send(int, const void *, size_t, int);
extern int close(int);
extern u16 htons(u16);
extern int usleep(unsigned int);
extern int pthread_create(pthread_t *, const void *, void *(*)(void *), void *);
extern void *fopen(const char *, const char *);
extern int fprintf(void *, const char *, ...);
extern int fflush(void *);
extern int fclose(void *);
extern int gettimeofday(struct timeval *, void *);
extern char *getenv(const char *);

#define RTLD_LAZY 1
#define AF_INET 2
#define SOCK_STREAM 1
#define SOL_SOCKET 0xffff
#define SO_REUSEADDR 0x0004
#define SO_RCVTIMEO 0x1006
#define SO_SNDTIMEO 0x1005

#define SCREEN_PROPERTY_BUFFER_SIZE 5
#define SCREEN_PROPERTY_FORMAT 14
#define SCREEN_PROPERTY_POINTER 34
#define SCREEN_PROPERTY_RENDER_BUFFERS 37
#define SCREEN_PROPERTY_STRIDE 44
#define SCREEN_PROPERTY_USAGE 48
#define SCREEN_PROPERTY_SIZE 40
#define SCREEN_PROPERTY_DISPLAY_COUNT 59
#define SCREEN_PROPERTY_DISPLAYS 60
#define SCREEN_FORMAT_RGBA8888 8
#define SCREEN_USAGE_READ (1 << 1)
#define SCREEN_USAGE_NATIVE (1 << 3)
#define SCREEN_WINDOW_MANAGER_CONTEXT (1 << 0)
#define SCREEN_DISPLAY_MANAGER_CONTEXT (1 << 3)

#define Z_NO_FLUSH 0
#define Z_SYNC_FLUSH 2
#define Z_OK 0

#define CAP_W 1024
#define CAP_H 480
#define CAP_BYTES (CAP_W * CAP_H * 4)
#define RFB_PORT 5900

static const char *ARM_PATH_A = "/net/mmx/fs/sda0/Toolbox/carplay_mirror_test/ARMED";
static const char *ARM_PATH_B = "/net/mmx/fs/sda1/Toolbox/carplay_mirror_test/ARMED";
static const char *LOG_PATH_A = "/net/mmx/fs/sda0/Log/CarPlayMirror/mirror_hook.log";
static const char *LOG_PATH_B = "/net/mmx/fs/sda1/Log/CarPlayMirror/mirror_hook.log";
static const char *FPS20_PATH_A = "/net/mmx/fs/sda0/Toolbox/carplay_mirror_test/FPS20";
static const char *FPS20_PATH_B = "/net/mmx/fs/sda1/Toolbox/carplay_mirror_test/FPS20";
static const char *FPS30_PATH_A = "/net/mmx/fs/sda0/Toolbox/carplay_mirror_test/FPS30";
static const char *FPS30_PATH_B = "/net/mmx/fs/sda1/Toolbox/carplay_mirror_test/FPS30";
static const char *FPS40_PATH_A = "/net/mmx/fs/sda0/Toolbox/carplay_mirror_test/FPS40";
static const char *FPS40_PATH_B = "/net/mmx/fs/sda1/Toolbox/carplay_mirror_test/FPS40";
static const char *FPS50_PATH_A = "/net/mmx/fs/sda0/Toolbox/carplay_mirror_test/FPS50";
static const char *FPS50_PATH_B = "/net/mmx/fs/sda1/Toolbox/carplay_mirror_test/FPS50";
static const char *FPS60_PATH_A = "/net/mmx/fs/sda0/Toolbox/carplay_mirror_test/FPS60";
static const char *FPS60_PATH_B = "/net/mmx/fs/sda1/Toolbox/carplay_mirror_test/FPS60";
static const char *DIRECT_UPLOAD_PATH_A = "/net/mmx/fs/sda0/Toolbox/carplay_mirror_test/DIRECT_UPLOAD_TEST";
static const char *DIRECT_UPLOAD_PATH_B = "/net/mmx/fs/sda1/Toolbox/carplay_mirror_test/DIRECT_UPLOAD_TEST";

typedef int (*fn_screen_post_window)(screen_window_t, screen_buffer_t, int, const int *, int);
typedef int (*fn_screen_destroy_window)(screen_window_t);
typedef int (*fn_screen_get_buffer_iv)(screen_buffer_t, int, int *);
typedef int (*fn_screen_create_context)(screen_context_t *, int);
typedef int (*fn_screen_destroy_context)(screen_context_t);
typedef int (*fn_screen_get_context_iv)(screen_context_t, int, int *);
typedef int (*fn_screen_get_context_pv)(screen_context_t, int, void **);
typedef int (*fn_screen_get_display_iv)(screen_display_t, int, int *);
typedef int (*fn_screen_create_pixmap)(screen_pixmap_t *, screen_context_t);
typedef int (*fn_screen_destroy_pixmap)(screen_pixmap_t);
typedef int (*fn_screen_set_pixmap_iv)(screen_pixmap_t, int, const int *);
typedef int (*fn_screen_create_pixmap_buffer)(screen_pixmap_t);
typedef int (*fn_screen_get_pixmap_pv)(screen_pixmap_t, int, void **);
typedef int (*fn_screen_get_buffer_pv)(screen_buffer_t, int, void **);
typedef int (*fn_screen_read_display)(screen_display_t, screen_buffer_t, int, const int *, int);
typedef const char *(*fn_zlib_version)(void);
typedef int (*fn_deflate_init)(z_stream *, int, const char *, int);
typedef int (*fn_deflate)(z_stream *, int);
typedef int (*fn_deflate_end)(z_stream *);

static void *g_screen_lib;
static void *g_z_lib;
static fn_screen_post_window real_post;
static fn_screen_destroy_window real_destroy_window;
static fn_screen_get_buffer_iv p_get_buffer_iv;
static fn_screen_create_context p_create_context;
static fn_screen_destroy_context p_destroy_context;
static fn_screen_get_context_iv p_get_context_iv;
static fn_screen_get_context_pv p_get_context_pv;
static fn_screen_get_display_iv p_get_display_iv;
static fn_screen_create_pixmap p_create_pixmap;
static fn_screen_destroy_pixmap p_destroy_pixmap;
static fn_screen_set_pixmap_iv p_set_pixmap_iv;
static fn_screen_create_pixmap_buffer p_create_pixmap_buffer;
static fn_screen_get_pixmap_pv p_get_pixmap_pv;
static fn_screen_get_buffer_pv p_get_buffer_pv;
static fn_screen_read_display p_read_display;
static fn_zlib_version p_zlib_version;
static fn_deflate_init p_deflate_init;
static fn_deflate p_deflate;
static fn_deflate_end p_deflate_end;

static volatile int g_resolve_state;
static volatile int g_worker_running;
static volatile int g_frames_sent;
static volatile int g_read_failures;
static volatile int g_selected_fps;
static long g_stats_started_us;
static int g_stats_frames;

static int armed(void) {
    /* DIRECT_UPLOAD_TEST deliberately starts before ARMED.  This lets the
     * SD-owned v41 clock bind loopback port 5900 before an older copy of this
     * hook, already loaded in smartphone_integrator, notices ARMED.  Java is
     * armed only after the renderer-local texture gate has passed. */
    int direct = access(DIRECT_UPLOAD_PATH_A, 0) == 0 ||
                 access(DIRECT_UPLOAD_PATH_B, 0) == 0;
    if (direct) {
        /* During B3 the same preload is present in two processes. Only the
         * explicitly launched SD clock host may own port 5900. The copy that
         * is already resident in smartphone_integrator must stay inert even
         * after Java's ARMED flag appears; otherwise its 250-ms monitor keeps
         * creating Screen contexts and retrying bind(), starving the renderer. */
        const char *clock_host = getenv("MIRROR_CLOCK_HOST");
        return clock_host && clock_host[0] == '1' && clock_host[1] == '\0';
    }
    return access(ARM_PATH_A, 0) == 0 || access(ARM_PATH_B, 0) == 0;
}

static int selected_fps(void) {
    if (access(FPS60_PATH_A, 0) == 0 || access(FPS60_PATH_B, 0) == 0) return 60;
    if (access(FPS50_PATH_A, 0) == 0 || access(FPS50_PATH_B, 0) == 0) return 50;
    if (access(FPS40_PATH_A, 0) == 0 || access(FPS40_PATH_B, 0) == 0) return 40;
    if (access(FPS30_PATH_A, 0) == 0 || access(FPS30_PATH_B, 0) == 0) return 30;
    if (access(FPS20_PATH_A, 0) == 0 || access(FPS20_PATH_B, 0) == 0) return 20;
    return 10;
}

static int direct_upload_test(void) {
    return access(DIRECT_UPLOAD_PATH_A, 0) == 0 || access(DIRECT_UPLOAD_PATH_B, 0) == 0;
}

static void log_line(const char *message, int a, int b, int c) {
    const char *path = access("/net/mmx/fs/sda0/Toolbox", 0) == 0 ? LOG_PATH_A : LOG_PATH_B;
    void *fp = fopen(path, "a");
    if (!fp) return;
    fprintf(fp, "%s %d %d %d\n", message, a, b, c);
    fflush(fp);
    fclose(fp);
}

static int resolve_api(void) {
    if (g_resolve_state == 2) return 0;
    if (__sync_bool_compare_and_swap(&g_resolve_state, 0, 1)) {
        g_screen_lib = dlopen("libscreen.so.1", RTLD_LAZY);
        g_z_lib = dlopen("libz.so.2", RTLD_LAZY);
        if (g_screen_lib) {
            real_post = (fn_screen_post_window)dlsym(g_screen_lib, "screen_post_window");
            real_destroy_window = (fn_screen_destroy_window)dlsym(g_screen_lib, "screen_destroy_window");
            p_get_buffer_iv = (fn_screen_get_buffer_iv)dlsym(g_screen_lib, "screen_get_buffer_property_iv");
            p_create_context = (fn_screen_create_context)dlsym(g_screen_lib, "screen_create_context");
            p_destroy_context = (fn_screen_destroy_context)dlsym(g_screen_lib, "screen_destroy_context");
            p_get_context_iv = (fn_screen_get_context_iv)dlsym(g_screen_lib, "screen_get_context_property_iv");
            p_get_context_pv = (fn_screen_get_context_pv)dlsym(g_screen_lib, "screen_get_context_property_pv");
            p_get_display_iv = (fn_screen_get_display_iv)dlsym(g_screen_lib, "screen_get_display_property_iv");
            p_create_pixmap = (fn_screen_create_pixmap)dlsym(g_screen_lib, "screen_create_pixmap");
            p_destroy_pixmap = (fn_screen_destroy_pixmap)dlsym(g_screen_lib, "screen_destroy_pixmap");
            p_set_pixmap_iv = (fn_screen_set_pixmap_iv)dlsym(g_screen_lib, "screen_set_pixmap_property_iv");
            p_create_pixmap_buffer = (fn_screen_create_pixmap_buffer)dlsym(g_screen_lib, "screen_create_pixmap_buffer");
            p_get_pixmap_pv = (fn_screen_get_pixmap_pv)dlsym(g_screen_lib, "screen_get_pixmap_property_pv");
            p_get_buffer_pv = (fn_screen_get_buffer_pv)dlsym(g_screen_lib, "screen_get_buffer_property_pv");
            p_read_display = (fn_screen_read_display)dlsym(g_screen_lib, "screen_read_display");
        }
        if (g_z_lib) {
            p_zlib_version = (fn_zlib_version)dlsym(g_z_lib, "zlibVersion");
            p_deflate_init = (fn_deflate_init)dlsym(g_z_lib, "deflateInit_");
            p_deflate = (fn_deflate)dlsym(g_z_lib, "deflate");
            p_deflate_end = (fn_deflate_end)dlsym(g_z_lib, "deflateEnd");
        }
        if (p_get_buffer_iv && p_create_context && p_destroy_context &&
            p_get_context_iv && p_get_context_pv && p_get_display_iv &&
            p_create_pixmap && p_destroy_pixmap &&
            p_set_pixmap_iv && p_create_pixmap_buffer && p_get_pixmap_pv && p_get_buffer_pv &&
            p_read_display &&
            p_zlib_version && p_deflate_init && p_deflate && p_deflate_end) {
            g_resolve_state = 2;
            log_line("mirror api ready", 0, 0, 0);
        } else {
            g_resolve_state = -1;
            log_line("mirror api missing", p_get_context_pv != 0, p_read_display != 0, p_deflate != 0);
        }
    } else {
        while (g_resolve_state == 1) usleep(1000);
    }
    return g_resolve_state == 2 ? 0 : -1;
}

static void put_be16(u8 *p, u16 v) { p[0] = (u8)(v >> 8); p[1] = (u8)v; }
static void put_be32(u8 *p, u32 v) {
    p[0] = (u8)(v >> 24); p[1] = (u8)(v >> 16); p[2] = (u8)(v >> 8); p[3] = (u8)v;
}

static int send_all(int fd, const void *data, size_t bytes) {
    const u8 *p = (const u8 *)data;
    while (bytes) {
        ssize_t n = send(fd, p, bytes, 0);
        if (n <= 0) return -1;
        p += n;
        bytes -= (size_t)n;
    }
    return 0;
}

static int recv_all(int fd, void *data, size_t bytes) {
    u8 *p = (u8 *)data;
    while (bytes) {
        ssize_t n = recv(fd, p, bytes, 0);
        if (n <= 0) return -1;
        p += n;
        bytes -= (size_t)n;
    }
    return 0;
}

static int discard_bytes(int fd, u32 bytes) {
    u8 tmp[128];
    while (bytes) {
        u32 part = bytes > sizeof(tmp) ? sizeof(tmp) : bytes;
        if (recv_all(fd, tmp, part) != 0) return -1;
        bytes -= part;
    }
    return 0;
}

static int rfb_handshake(int fd) {
    static const char version[] = "RFB 003.003\n";
    u8 client_version[12];
    u8 security[4] = {0, 0, 0, 1};
    u8 shared;
    u8 init[24];
    static const char name[] = "MHI2Q Full MMI Mirror";
    memset(init, 0, sizeof(init));
    put_be16(init + 0, CAP_W);
    put_be16(init + 2, CAP_H);
    init[4] = 32;
    init[5] = 24;
    init[6] = 0;
    init[7] = 1;
    put_be16(init + 8, 255);
    put_be16(init + 10, 255);
    put_be16(init + 12, 255);
    /* The wire buffer below is normalized to byte-order RGBA. */
    init[14] = 0;
    init[15] = 8;
    init[16] = 16;
    put_be32(init + 20, (u32)(sizeof(name) - 1));
    if (send_all(fd, version, 12) != 0) return -1;
    if (recv_all(fd, client_version, 12) != 0) return -1;
    if (send_all(fd, security, sizeof(security)) != 0) return -1;
    if (recv_all(fd, &shared, 1) != 0) return -1;
    if (send_all(fd, init, sizeof(init)) != 0) return -1;
    if (send_all(fd, name, sizeof(name) - 1) != 0) return -1;
    return 0;
}

static long now_us(void) {
    struct timeval value;
    if (gettimeofday(&value, 0) != 0) return 0;
    return value.tv_sec * 1000000L + value.tv_usec;
}

static int send_frame(int fd, screen_display_t source_display,
                      screen_buffer_t capture_buffer,
                      u8 *pixels, int stride, u8 *packed,
                      u8 *compressed, u32 compressed_cap, z_stream *zs) {
    u8 header[20];
    u32 y;
    u32 out_bytes;
    long current_us;
    long elapsed_us;
    static u8 trigger_pixel[4] = { 0, 0, 0, 255 };
    int direct_trigger = direct_upload_test();
    if (!source_display) {
        log_line("MMI display unavailable", 0, 0, 0);
        return -1;
    }
    if (!direct_trigger) {
        if (p_read_display(source_display, capture_buffer, 0, (const int *)0, 0) != 0) {
            if (__sync_add_and_fetch(&g_read_failures, 1) == 1) {
                log_line("screen_read_display failed", CAP_W, CAP_H, g_selected_fps);
            }
            return -1;
        }
        g_read_failures = 0;
        /* P1404 exposes SCREEN_FORMAT_RGBA8888 as little-endian BGRA bytes in the
         * mapped pixmap.  The legacy receiver does not send SetPixelFormat and
         * uploads the RFB bytes directly with GL_RGBA, so normalize B,G,R,A to
         * R,G,B,A here.  Force opaque alpha: the captured compositor alpha is not
         * meaningful once the final MMI image is mirrored into another window. */
        for (y = 0; y < CAP_H; ++y) {
            u8 *source = pixels + y * stride;
            u8 *dest = packed + y * CAP_W * 4;
            u32 x;
            for (x = 0; x < CAP_W; ++x) {
                dest[x * 4 + 0] = source[x * 4 + 2];
                dest[x * 4 + 1] = source[x * 4 + 1];
                dest[x * 4 + 2] = source[x * 4 + 0];
                dest[x * 4 + 3] = 255;
            }
        }
    }

    /* Keep encoding 6 because the legacy P1404 renderer crashes in its Raw
     * decoder. Level 0 produces a valid zlib stream without CPU-heavy frame
     * compression, retaining the proven renderer path with minimal queuing. */
    /* In DIRECT_UPLOAD_TEST the RFB stream is only a pacing signal.  The
     * renderer-side preload captures the compositor immediately before the
     * texture upload.  Keep the proven legacy decoder alive but feed it four
     * bytes rather than copying, transporting and inflating a 1.9 MiB frame. */
    zs->next_in = direct_trigger ? trigger_pixel : packed;
    zs->avail_in = direct_trigger ? sizeof(trigger_pixel) : CAP_BYTES;
    zs->next_out = compressed;
    zs->avail_out = compressed_cap;
    if (p_deflate(zs, Z_SYNC_FLUSH) != Z_OK || zs->avail_in != 0) return -1;
    out_bytes = compressed_cap - zs->avail_out;
    memset(header, 0, sizeof(header));
    header[3] = 1;
    put_be16(header + 8, CAP_W);
    put_be16(header + 10, CAP_H);
    put_be32(header + 12, 6);
    put_be32(header + 16, out_bytes);
    if (send_all(fd, header, sizeof(header)) != 0) return -1;
    if (send_all(fd, compressed, out_bytes) != 0) return -1;
    {
        int frame_count = __sync_add_and_fetch(&g_frames_sent, 1);
        if (frame_count == 1) {
            if (direct_trigger) {
                log_line("mirror first direct-upload trigger sent", (int)out_bytes, CAP_W, CAP_H);
            } else {
                log_line("mirror first zlib0 frame sent", (int)out_bytes, CAP_W, CAP_H);
            }
        }
    }
    current_us = now_us();
    if (g_stats_started_us == 0) g_stats_started_us = current_us;
    g_stats_frames++;
    elapsed_us = current_us - g_stats_started_us;
    if (elapsed_us >= 1000000L) {
        int actual_fps_x1000 = (int)(((long)g_stats_frames * 1000000L) /
                                    (elapsed_us / 1000L));
        log_line("mirror measured fps_x1000 elapsed_ms frames",
                 actual_fps_x1000, (int)(elapsed_us / 1000L), g_stats_frames);
        g_stats_started_us = current_us;
        g_stats_frames = 0;
    }
    return 0;
}

static int serve_client(int fd, screen_display_t source_display,
                        screen_buffer_t capture_buffer,
                        u8 *pixels, int stride, u8 *packed,
                        u8 *compressed, u32 compressed_cap,
                        unsigned int frame_period_us) {
    z_stream zs;
    u8 type;
    long next_frame_us = 0;
    memset(&zs, 0, sizeof(zs));
    if (rfb_handshake(fd) != 0) return -1;
    if (p_deflate_init(&zs, 0, p_zlib_version(), (int)sizeof(zs)) != Z_OK) return -1;
    while (armed()) {
        if (recv_all(fd, &type, 1) != 0) break;
        if (type == 0) {
            if (discard_bytes(fd, 19) != 0) break;
        } else if (type == 2) {
            u8 h[3];
            u16 count;
            if (recv_all(fd, h, 3) != 0) break;
            count = (u16)(((u16)h[1] << 8) | h[2]);
            if (discard_bytes(fd, (u32)count * 4) != 0) break;
        } else if (type == 3) {
            if (discard_bytes(fd, 9) != 0) break;
            if (next_frame_us != 0) {
                long current_us = now_us();
                if (current_us > 0 && next_frame_us > current_us) {
                    usleep((unsigned int)(next_frame_us - current_us));
                }
            }
            if (send_frame(fd, source_display, capture_buffer, pixels, stride,
                           packed, compressed, compressed_cap, &zs) != 0) break;
            {
                long current_us = now_us();
                if (next_frame_us == 0 || current_us > next_frame_us + (long)frame_period_us) {
                    next_frame_us = current_us + (long)frame_period_us;
                } else {
                    next_frame_us += (long)frame_period_us;
                }
            }
        } else if (type == 4) {
            if (discard_bytes(fd, 7) != 0) break;
        } else if (type == 5) {
            if (discard_bytes(fd, 5) != 0) break;
        } else if (type == 6) {
            u8 h[7];
            u32 len;
            if (recv_all(fd, h, 7) != 0) break;
            len = ((u32)h[3] << 24) | ((u32)h[4] << 16) | ((u32)h[5] << 8) | h[6];
            if (discard_bytes(fd, len) != 0) break;
        } else {
            break;
        }
    }
    p_deflate_end(&zs);
    return 0;
}

static void *server_worker(void *unused) {
    int listen_fd = -1;
    int client_fd = -1;
    int one = 1;
    int addr_len;
    int usage = SCREEN_USAGE_READ | SCREEN_USAGE_NATIVE;
    int format = SCREEN_FORMAT_RGBA8888;
    int size[2] = { CAP_W, CAP_H };
    int stride = 0;
    struct sockaddr_in addr;
    struct timeval timeout;
    screen_context_t context = 0;
    screen_display_t displays[8];
    screen_display_t source_display = 0;
    screen_pixmap_t pixmap = 0;
    screen_buffer_t capture_buffer = 0;
    u8 *pixels = 0;
    u8 *packed = 0;
    u8 *compressed = 0;
    const u32 compressed_cap = CAP_BYTES + (CAP_BYTES / 8) + 65536;
    int display_count = 0;
    int display_index = 0;
    int display_size[2] = { 0, 0 };
    int fps = selected_fps();
    unsigned int frame_delay_us = fps == 60 ? 16667U :
                                  (fps == 50 ? 20000U :
                                  (fps == 40 ? 25000U :
                                  (fps == 30 ? 33333U :
                                  (fps == 20 ? 50000U : 100000U))));
    (void)unused;
    memset(displays, 0, sizeof(displays));
    g_selected_fps = fps;

    if (resolve_api() != 0) goto cleanup;
    /* screen_read_display requires a display-manager context. dio_manager is
     * launched by the MHI2Q service manager with the privileges needed for
     * the stock projection pipeline. Try the narrow display-manager flag
     * first, then the window-manager flag used by older Screen builds. */
    if (p_create_context(&context, SCREEN_DISPLAY_MANAGER_CONTEXT) != 0) {
        log_line("display-manager context failed", SCREEN_DISPLAY_MANAGER_CONTEXT, 0, 0);
        if (p_create_context(&context, SCREEN_WINDOW_MANAGER_CONTEXT) != 0) {
            log_line("window-manager context failed", SCREEN_WINDOW_MANAGER_CONTEXT, 0, 0);
            goto cleanup;
        }
    }
    if (p_get_context_iv(context, SCREEN_PROPERTY_DISPLAY_COUNT, &display_count) != 0 ||
        display_count <= 0) {
        log_line("display enumeration failed", display_count, 0, fps);
        goto cleanup;
    }
    if (display_count > 8) display_count = 8;
    if (p_get_context_pv(context, SCREEN_PROPERTY_DISPLAYS, (void **)displays) != 0) {
        log_line("display handles failed", display_count, 0, fps);
        goto cleanup;
    }
    /* This vehicle exposes two physical outputs: the 1024x480 MMI and the
     * 1440x542 virtual cockpit. Never rely on enumeration order: capture only
     * the exact MMI output, and fail closed if the topology changes. */
    for (display_index = 0; display_index < display_count; ++display_index) {
        display_size[0] = 0;
        display_size[1] = 0;
        if (p_get_display_iv(displays[display_index], SCREEN_PROPERTY_SIZE,
                             display_size) == 0) {
            log_line("MMI display candidate", display_index,
                     display_size[0], display_size[1]);
            if (display_size[0] == CAP_W && display_size[1] == CAP_H) {
                source_display = displays[display_index];
                break;
            }
        }
    }
    if (!source_display) {
        log_line("1024x480 MMI display missing", display_count, 0, fps);
        goto cleanup;
    }
    log_line("MMI display capture selected", display_index, CAP_W, CAP_H);
    if (p_create_pixmap(&pixmap, context) != 0) goto cleanup;
    if (p_set_pixmap_iv(pixmap, SCREEN_PROPERTY_USAGE, &usage) != 0) goto cleanup;
    if (p_set_pixmap_iv(pixmap, SCREEN_PROPERTY_FORMAT, &format) != 0) goto cleanup;
    if (p_set_pixmap_iv(pixmap, SCREEN_PROPERTY_BUFFER_SIZE, size) != 0) goto cleanup;
    if (p_create_pixmap_buffer(pixmap) != 0) goto cleanup;
    if (p_get_pixmap_pv(pixmap, SCREEN_PROPERTY_RENDER_BUFFERS, &capture_buffer) != 0) goto cleanup;
    if (p_get_buffer_pv(capture_buffer, SCREEN_PROPERTY_POINTER, (void **)&pixels) != 0) goto cleanup;
    if (p_get_buffer_iv(capture_buffer, SCREEN_PROPERTY_STRIDE, &stride) != 0) goto cleanup;
    if (stride < CAP_W * 4) goto cleanup;
    packed = (u8 *)malloc(CAP_BYTES);
    compressed = (u8 *)malloc(compressed_cap);
    if (!packed || !compressed) goto cleanup;

    listen_fd = socket(AF_INET, SOCK_STREAM, 0);
    if (listen_fd < 0) goto cleanup;
    setsockopt(listen_fd, SOL_SOCKET, SO_REUSEADDR, &one, sizeof(one));
    memset(&addr, 0, sizeof(addr));
    addr.sin_len = (u8)sizeof(addr);
    addr.sin_family = AF_INET;
    addr.sin_port = htons(RFB_PORT);
    addr.sin_addr.s_addr = 0x0100007fU;
    if (bind(listen_fd, (const struct sockaddr *)&addr, sizeof(addr)) != 0) goto cleanup;
    if (listen(listen_fd, 1) != 0) goto cleanup;
    log_line("mirror server listening", RFB_PORT, CAP_W, fps);

    while (armed()) {
        struct sockaddr_in client_addr;
        addr_len = sizeof(client_addr);
        client_fd = accept(listen_fd, (struct sockaddr *)&client_addr, &addr_len);
        if (client_fd < 0) { usleep(100000); continue; }
        timeout.tv_sec = 2;
        timeout.tv_usec = 0;
        setsockopt(client_fd, SOL_SOCKET, SO_RCVTIMEO, &timeout, sizeof(timeout));
        setsockopt(client_fd, SOL_SOCKET, SO_SNDTIMEO, &timeout, sizeof(timeout));
        g_frames_sent = 0;
        g_stats_started_us = 0;
        g_stats_frames = 0;
        log_line("mirror client connected", 0, 0, 0);
        serve_client(client_fd, source_display, capture_buffer, pixels, stride, packed,
                     compressed, compressed_cap, frame_delay_us);
        close(client_fd);
        client_fd = -1;
        log_line("mirror client disconnected", g_frames_sent, fps, 0);
    }

cleanup:
    if (client_fd >= 0) close(client_fd);
    if (listen_fd >= 0) close(listen_fd);
    if (compressed) free(compressed);
    if (packed) free(packed);
    if (pixmap) p_destroy_pixmap(pixmap);
    if (context) p_destroy_context(context);
    log_line("mirror worker stopped", 0, 0, 0);
    g_worker_running = 0;
    return 0;
}

/* The previous implementation only started the worker from an intercepted
 * screen_post_window call. On P1404 that symbol is never called through the
 * dio_manager PLT, so the hook stayed completely silent. A tiny constructor
 * monitor makes arming independent of Cinemo's private rendering path. */
static void *arm_monitor_worker(void *unused) {
    (void)unused;
    for (;;) {
        if (armed() && __sync_bool_compare_and_swap(&g_worker_running, 0, 1)) {
            pthread_t thread;
            if (pthread_create(&thread, 0, server_worker, 0) != 0) {
                g_worker_running = 0;
                log_line("mirror worker create failed", 0, 0, 0);
            }
        }
        usleep(250000);
    }
    return 0;
}

static void mirror_library_init(void) __attribute__((constructor));
static void mirror_library_init(void) {
    pthread_t thread;
    if (pthread_create(&thread, 0, arm_monitor_worker, 0) != 0 && armed()) {
        log_line("mirror monitor create failed", 0, 0, 0);
    }
}

int screen_post_window(screen_window_t win, screen_buffer_t buf, int count,
                       const int *dirty_rects, int flags) {
    int rc;
    /* Capture support is optional. Never block the original display path
     * merely because a diagnostic API or zlib symbol is unavailable. */
    if (resolve_api() != 0) {
        if (real_post) return real_post(win, buf, count, dirty_rects, flags);
        return -1;
    }
    rc = real_post(win, buf, count, dirty_rects, flags);
    return rc;
}

int screen_destroy_window(screen_window_t win) {
    if (resolve_api() != 0) {
        if (real_destroy_window) return real_destroy_window(win);
        return -1;
    }
    return real_destroy_window(win);
}
