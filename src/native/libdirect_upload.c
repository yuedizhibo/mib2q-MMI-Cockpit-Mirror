/*
 * P1404 cockpit texture bridge.
 *
 * The stock renderer remains responsible for the known-good displayable-58
 * window and geometry. Standalone B3 reads the already-composed MMI physical
 * display. Integrated MMI-Cockpit-Carplay mode is deliberately different: when
 * FULL_CHAIN_MODE is present, this preload MUST source the texture from the
 * private CarPlay AltScreen111 provider and MUST NEVER fall back to MMI capture.
 */

typedef unsigned char u8;
typedef unsigned int u32;
typedef unsigned long long u64;
typedef unsigned long size_t;
typedef void *screen_context_t;
typedef void *screen_pixmap_t;
typedef void *screen_buffer_t;
typedef void *screen_display_t;

extern void *dlopen(const char *, int);
extern void *dlsym(void *, const char *);
extern void *malloc(size_t);
extern void free(void *);
extern int access(const char *, int);
extern void *fopen(const char *, const char *);
extern int fprintf(void *, const char *, ...);
extern int fflush(void *);
extern int fclose(void *);
extern int gettimeofday(void *, void *);
extern char *strstr(const char *, const char *);

struct timeval { long tv_sec; long tv_usec; };

#define RTLD_LAZY 1
#define CAP_W 1024
#define CAP_H 480
#define CAP_BYTES (CAP_W * CAP_H * 4)
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
#define SCREEN_DISPLAY_MANAGER_CONTEXT (1 << 3)
#define SCREEN_WINDOW_MANAGER_CONTEXT (1 << 0)

#define SOURCE_UNRESOLVED 0
#define SOURCE_MMI_CAPTURE 1
#define SOURCE_CARPLAY_ALT_111 2
#define CP_ALT111_PROVIDER_ABI_VERSION 1
#define CP_ALT111_FORMAT_BGRA8888 1

#define FULL_CHAIN_A "/net/mmx/fs/sda0/Log/MMI-Cockpit-Carplay/current/FULL_CHAIN_MODE"
#define FULL_CHAIN_B "/net/mmx/fs/sda1/Log/MMI-Cockpit-Carplay/current/FULL_CHAIN_MODE"
#define ALT_PROVIDER_A "/net/mmx/fs/sda0/Toolbox/carplay_alt_screen/libcarplay_alt111_provider.so"
#define ALT_PROVIDER_B "/net/mmx/fs/sda1/Toolbox/carplay_alt_screen/libcarplay_alt111_provider.so"

typedef int (*fn_create_context)(screen_context_t *, int);
typedef int (*fn_destroy_context)(screen_context_t);
typedef int (*fn_get_context_iv)(screen_context_t, int, int *);
typedef int (*fn_get_context_pv)(screen_context_t, int, void **);
typedef int (*fn_get_display_iv)(screen_display_t, int, int *);
typedef int (*fn_create_pixmap)(screen_pixmap_t *, screen_context_t);
typedef int (*fn_destroy_pixmap)(screen_pixmap_t);
typedef int (*fn_set_pixmap_iv)(screen_pixmap_t, int, const int *);
typedef int (*fn_create_pixmap_buffer)(screen_pixmap_t);
typedef int (*fn_get_pixmap_pv)(screen_pixmap_t, int, void **);
typedef int (*fn_get_buffer_pv)(screen_buffer_t, int, void **);
typedef int (*fn_get_buffer_iv)(screen_buffer_t, int, int *);
typedef int (*fn_read_display)(screen_display_t, screen_buffer_t, int, const int *, int);

typedef int (*fn_alt111_open)(int abi_version, int width, int height, int format);
typedef const void *(*fn_alt111_frame)(u32 *frame_seq, u64 *frame_time_us, int *stride_bytes);
typedef int (*fn_alt111_health)(u32 *last_frame_seq, u64 *last_frame_time_us);

static const char *LOG_A = "/net/mmx/fs/sda0/Log/CarPlayMirror/direct_upload.log";
static const char *LOG_B = "/net/mmx/fs/sda1/Log/CarPlayMirror/direct_upload.log";
static void *g_screen;
static void *g_gles;
static screen_context_t g_context;
static screen_pixmap_t g_pixmap;
static screen_buffer_t g_buffer;
static screen_display_t g_display;
static u8 *g_pixels;
static u8 *g_rgba;
static int g_stride;
static int g_state;
static u32 g_frames;
static u32 g_failures;
static u32 g_stats_start_us;
static u32 g_stats_frames;
static int g_gpu_bgra_swizzle;
static int g_texture_ready;
static int g_draw_pump_logged;
static u64 g_next_draw_capture_us;
static u64 g_draw_frame_period_us = 50000ULL;
static int g_draw_target_fps = 20;
static int g_draw_pacing_configured;

/* Integrated Alt111 provider state. Default B3 never touches these symbols. */
static int g_source_mode;
static void *g_alt_provider;
static fn_alt111_open g_alt_open;
static fn_alt111_frame g_alt_frame;
static fn_alt111_health g_alt_health;
static int g_alt_state;
static u32 g_alt_last_seq;
static u32 g_alt_frames_seen;
static u32 g_alt_failures;
static u64 g_alt_last_log_us;

#define GL_TEXTURE_2D 0x0DE1
#define GL_RGBA 0x1908
#define GL_UNSIGNED_BYTE 0x1401
#define GL_TRIANGLE_FAN 0x0006
#define FPS30_PATH_A "/net/mmx/fs/sda0/Toolbox/carplay_mirror_test/FPS30"
#define FPS30_PATH_B "/net/mmx/fs/sda1/Toolbox/carplay_mirror_test/FPS30"
#define STATS_LOG_INTERVAL_US 10000000U

static void configure_draw_pacing(void) {
    if (g_draw_pacing_configured) return;
    g_draw_pacing_configured = 1;
    if (access(FPS30_PATH_A, 0) == 0 || access(FPS30_PATH_B, 0) == 0) {
        g_draw_target_fps = 30;
        g_draw_frame_period_us = 33333ULL;
    }
}

static const char *g_bgra_fragment_shader =
    "precision mediump float;\n"
    "varying vec2 v_texCoord;\n"
    "uniform sampler2D texture;\n"
    "void main() {\n"
    "  vec4 c = texture2D(texture, v_texCoord);\n"
    "  gl_FragColor = vec4(c.b, c.g, c.r, 1.0);\n"
    "}\n";

static void log_line(const char *message, int a, int b, int c) {
    const char *path = access("/net/mmx/fs/sda0/Toolbox", 0) == 0 ? LOG_A : LOG_B;
    void *fp = fopen(path, "a");
    if (!fp) return;
    fprintf(fp, "%s %d %d %d\n", message, a, b, c);
    fflush(fp);
    fclose(fp);
}

static long now_us(void) {
    struct timeval value;
    if (gettimeofday(&value, 0) != 0) return 0;
    return value.tv_sec * 1000000L + value.tv_usec;
}

static u32 now_us32(void) {
    struct timeval value;
    if (gettimeofday(&value, 0) != 0) return 0;
    return (u32)value.tv_sec * 1000000U + (u32)value.tv_usec;
}

static u64 now_us64(void) {
    struct timeval value;
    if (gettimeofday(&value, 0) != 0) return 0;
    return (u64)(unsigned long)value.tv_sec * 1000000ULL +
           (u64)(unsigned long)value.tv_usec;
}

static int source_mode(void) {
    if (g_source_mode != SOURCE_UNRESOLVED) return g_source_mode;
    if (access(FULL_CHAIN_A, 0) == 0 || access(FULL_CHAIN_B, 0) == 0) {
        g_source_mode = SOURCE_CARPLAY_ALT_111;
        log_line("SOURCE_MODE CARPLAY_ALT_111 strict_no_mmi_fallback", CAP_W, CAP_H, 0);
    } else {
        g_source_mode = SOURCE_MMI_CAPTURE;
        log_line("SOURCE_MODE MMI_CAPTURE standalone_b3", CAP_W, CAP_H, 0);
    }
    return g_source_mode;
}

static int init_alt111_provider(void) {
    const char *path;
    int rc;
    if (g_alt_state == 2) return 0;
    if (g_alt_state == -1) return -1;
    path = access("/net/mmx/fs/sda0/Toolbox", 0) == 0 ? ALT_PROVIDER_A : ALT_PROVIDER_B;
    g_alt_provider = dlopen(path, RTLD_LAZY);
    if (!g_alt_provider) goto failed;
    g_alt_open = (fn_alt111_open)dlsym(g_alt_provider, "cp_alt111_provider_open");
    g_alt_frame = (fn_alt111_frame)dlsym(g_alt_provider, "cp_alt111_provider_frame");
    g_alt_health = (fn_alt111_health)dlsym(g_alt_provider, "cp_alt111_provider_health");
    if (!g_alt_open || !g_alt_frame) goto failed;
    rc = g_alt_open(CP_ALT111_PROVIDER_ABI_VERSION, CAP_W, CAP_H, CP_ALT111_FORMAT_BGRA8888);
    if (rc != 0) {
        log_line("ALT111_PROVIDER open rejected abi width height", rc, CAP_W, CAP_H);
        goto failed;
    }
    if (!g_rgba) g_rgba = (u8 *)malloc(CAP_BYTES);
    if (!g_rgba) goto failed;
    g_alt_state = 2;
    log_line("ALT111_PROVIDER_READY abi width height", CP_ALT111_PROVIDER_ABI_VERSION, CAP_W, CAP_H);
    return 0;
failed:
    g_alt_state = -1;
    log_line("ALT111_PROVIDER_FAILED strict_no_fallback", 0, 0, 0);
    return -1;
}

static const void *capture_alt111(void) {
    const u8 *frame;
    u32 seq = 0;
    u64 frame_time = 0;
    int stride = 0;
    int y;
    u64 current;
    if (init_alt111_provider() != 0) return (const void *)0;
    frame = (const u8 *)g_alt_frame(&seq, &frame_time, &stride);
    if (!frame) {
        if (g_alt_failures++ < 3)
            log_line("ALT111_PROVIDER no private frame", (int)seq, stride, 0);
        return (const void *)0;
    }
    if (stride != CAP_W * 4) {
        if (g_alt_failures++ < 3)
            log_line("ALT111_PROVIDER bad stride strict_drop", stride, CAP_W * 4, 0);
        return (const void *)0;
    }
    g_alt_failures = 0;
    if (seq != g_alt_last_seq) {
        g_alt_last_seq = seq;
        g_alt_frames_seen++;
        if (g_alt_frames_seen == 1)
            log_line("ALT111_PROVIDER first private frame", (int)seq, CAP_W, CAP_H);
    }
    current = now_us64();
    if (current && (g_alt_last_log_us == 0 || current - g_alt_last_log_us >= 10000000ULL)) {
        int healthy = 1;
        u32 health_seq = seq;
        u64 health_time = frame_time;
        if (g_alt_health) healthy = g_alt_health(&health_seq, &health_time);
        log_line("ALT111_PROVIDER heartbeat seq healthy frames", (int)health_seq, healthy, (int)g_alt_frames_seen);
        g_alt_last_log_us = current;
    }
    if (g_gpu_bgra_swizzle) return frame;
    /* Provider contract is packed BGRA8888. If the renderer's shader was not
     * replaced, convert into the same RGBA path standalone B3 already uses. */
    for (y = 0; y < CAP_H; ++y) {
        const u8 *source = frame + y * CAP_W * 4;
        u8 *dest = g_rgba + y * CAP_W * 4;
        int x;
        for (x = 0; x < CAP_W; ++x) {
            dest[x * 4 + 0] = source[x * 4 + 2];
            dest[x * 4 + 1] = source[x * 4 + 1];
            dest[x * 4 + 2] = source[x * 4 + 0];
            dest[x * 4 + 3] = 255;
        }
    }
    return g_rgba;
}

static int init_capture(void) {
    fn_create_context create_context;
    fn_get_context_iv get_context_iv;
    fn_get_context_pv get_context_pv;
    fn_get_display_iv get_display_iv;
    fn_create_pixmap create_pixmap;
    fn_set_pixmap_iv set_pixmap_iv;
    fn_create_pixmap_buffer create_pixmap_buffer;
    fn_get_pixmap_pv get_pixmap_pv;
    fn_get_buffer_pv get_buffer_pv;
    fn_get_buffer_iv get_buffer_iv;
    screen_display_t displays[8];
    int count = 0;
    int i;
    int usage = SCREEN_USAGE_READ | SCREEN_USAGE_NATIVE;
    int format = SCREEN_FORMAT_RGBA8888;
    int size[2] = { CAP_W, CAP_H };
    int display_size[2];
    if (g_state == 2) return 0;
    if (g_state == -1) return -1;
    g_screen = dlopen("libscreen.so.1", RTLD_LAZY);
    g_gles = dlopen("libGLESv2.so.1", RTLD_LAZY);
    if (!g_screen || !g_gles) goto failed;
    create_context = (fn_create_context)dlsym(g_screen, "screen_create_context");
    get_context_iv = (fn_get_context_iv)dlsym(g_screen, "screen_get_context_property_iv");
    get_context_pv = (fn_get_context_pv)dlsym(g_screen, "screen_get_context_property_pv");
    get_display_iv = (fn_get_display_iv)dlsym(g_screen, "screen_get_display_property_iv");
    create_pixmap = (fn_create_pixmap)dlsym(g_screen, "screen_create_pixmap");
    set_pixmap_iv = (fn_set_pixmap_iv)dlsym(g_screen, "screen_set_pixmap_property_iv");
    create_pixmap_buffer = (fn_create_pixmap_buffer)dlsym(g_screen, "screen_create_pixmap_buffer");
    get_pixmap_pv = (fn_get_pixmap_pv)dlsym(g_screen, "screen_get_pixmap_property_pv");
    get_buffer_pv = (fn_get_buffer_pv)dlsym(g_screen, "screen_get_buffer_property_pv");
    get_buffer_iv = (fn_get_buffer_iv)dlsym(g_screen, "screen_get_buffer_property_iv");
    if (!create_context || !get_context_iv || !get_context_pv || !get_display_iv ||
        !create_pixmap || !set_pixmap_iv || !create_pixmap_buffer ||
        !get_pixmap_pv || !get_buffer_pv || !get_buffer_iv) goto failed;
    if (create_context(&g_context, SCREEN_DISPLAY_MANAGER_CONTEXT) != 0 &&
        create_context(&g_context, SCREEN_WINDOW_MANAGER_CONTEXT) != 0) goto failed;
    if (get_context_iv(g_context, SCREEN_PROPERTY_DISPLAY_COUNT, &count) != 0 || count <= 0) goto failed;
    if (count > 8) count = 8;
    if (get_context_pv(g_context, SCREEN_PROPERTY_DISPLAYS, (void **)displays) != 0) goto failed;
    for (i = 0; i < count; ++i) {
        display_size[0] = display_size[1] = 0;
        if (get_display_iv(displays[i], SCREEN_PROPERTY_SIZE, display_size) == 0 &&
            display_size[0] == CAP_W && display_size[1] == CAP_H) {
            g_display = displays[i];
            break;
        }
    }
    if (!g_display) goto failed;
    if (create_pixmap(&g_pixmap, g_context) != 0) goto failed;
    if (set_pixmap_iv(g_pixmap, SCREEN_PROPERTY_USAGE, &usage) != 0 ||
        set_pixmap_iv(g_pixmap, SCREEN_PROPERTY_FORMAT, &format) != 0 ||
        set_pixmap_iv(g_pixmap, SCREEN_PROPERTY_BUFFER_SIZE, size) != 0 ||
        create_pixmap_buffer(g_pixmap) != 0 ||
        get_pixmap_pv(g_pixmap, SCREEN_PROPERTY_RENDER_BUFFERS, &g_buffer) != 0 ||
        get_buffer_pv(g_buffer, SCREEN_PROPERTY_POINTER, (void **)&g_pixels) != 0 ||
        get_buffer_iv(g_buffer, SCREEN_PROPERTY_STRIDE, &g_stride) != 0 ||
        g_stride < CAP_W * 4) goto failed;
    g_rgba = (u8 *)malloc(CAP_BYTES);
    if (!g_rgba) goto failed;
    g_state = 2;
    log_line("direct upload capture ready", count, g_stride, 0);
    return 0;
failed:
    g_state = -1;
    log_line("direct upload capture init failed", count, g_stride, 0);
    return -1;
}

static const void *capture_mmi_rgba(const void *fallback) {
    fn_read_display read_display;
    long started;
    long elapsed;
    int y;
    u32 stats_now;
    if (init_capture() != 0) return fallback;
    read_display = (fn_read_display)dlsym(g_screen, "screen_read_display");
    if (!read_display) return fallback;
    started = now_us();
    if (read_display(g_display, g_buffer, 0, (const int *)0, 0) != 0) {
        g_failures++;
        if (g_failures <= 3) log_line("direct upload read failed", g_failures, 0, 0);
        return fallback;
    }
    g_failures = 0;
    if (!g_gpu_bgra_swizzle) {
        for (y = 0; y < CAP_H; ++y) {
            const u8 *source = g_pixels + y * g_stride;
            u8 *dest = g_rgba + y * CAP_W * 4;
            int x;
            for (x = 0; x < CAP_W; ++x) {
                dest[x * 4 + 0] = source[x * 4 + 2];
                dest[x * 4 + 1] = source[x * 4 + 1];
                dest[x * 4 + 2] = source[x * 4 + 0];
                dest[x * 4 + 3] = 255;
            }
        }
    }
    elapsed = now_us() - started;
    stats_now = now_us32();
    g_frames++;
    if (g_frames == 1) {
        log_line("direct upload first MMI frame", (int)(elapsed / 1000L), CAP_W, CAP_H);
        g_stats_start_us = stats_now;
        g_stats_frames = 0;
    } else {
        u32 span_us;
        g_stats_frames++;
        span_us = stats_now - g_stats_start_us;
        if (span_us >= STATS_LOG_INTERVAL_US) {
            int span_ms = (int)(span_us / 1000U);
            int fps_x1000 = span_ms > 0 ?
                ((int)g_stats_frames * 1000000) / span_ms : 0;
            log_line("direct upload measured fps_x1000 capture_ms frames", fps_x1000,
                     (int)(elapsed / 1000L), (int)g_frames);
            g_stats_start_us = stats_now;
            g_stats_frames = 0;
        }
    }
    return g_gpu_bgra_swizzle ? g_pixels : g_rgba;
}

static const void *source_pixels(const void *mmi_fallback) {
    if (source_mode() == SOURCE_CARPLAY_ALT_111)
        return capture_alt111();
    return capture_mmi_rgba(mmi_fallback);
}

/* Replace only the renderer's textured-video fragment shader. Both standalone
 * MMI capture and the Alt111 provider contract expose BGRA8888 before swizzle. */
void glShaderSource(unsigned int shader, int count, const char *const *strings,
                    const int *lengths) {
    void (*fn)(unsigned int, int, const char *const *, const int *);
    const char *replacement;
    if (!g_gles) g_gles = dlopen("libGLESv2.so.1", RTLD_LAZY);
    fn = (void (*)(unsigned int, int, const char *const *, const int *))
        dlsym(g_gles, "glShaderSource");
    if (count == 1 && strings && strings[0] && strstr(strings[0], "texture2D")) {
        replacement = g_bgra_fragment_shader;
        g_gpu_bgra_swizzle = 1;
        log_line("direct upload GPU BGRA swizzle enabled", (int)shader, 0, 0);
        if (fn) fn(shader, 1, &replacement, (const int *)0);
        return;
    }
    if (fn) fn(shader, count, strings, lengths);
}

void glTexImage2D(unsigned int target, int level, int internal_format,
                  int width, int height, int border, unsigned int format,
                  unsigned int type, const void *pixels) {
    void (*fn)(unsigned int, int, int, int, int, int, unsigned int, unsigned int, const void *);
    const void *src = pixels;
    int mode;
    if (!g_gles) g_gles = dlopen("libGLESv2.so.1", RTLD_LAZY);
    fn = (void (*)(unsigned int, int, int, int, int, int, unsigned int, unsigned int, const void *))
        dlsym(g_gles, "glTexImage2D");
    mode = source_mode();
    if (width == CAP_W && height == CAP_H) {
        if (mode == SOURCE_CARPLAY_ALT_111) {
            /* NULL is valid for glTexImage2D allocation and prevents the network/MMI
             * pixels from appearing while the private provider has no frame. */
            src = source_pixels((const void *)0);
        } else {
            src = source_pixels(pixels);
        }
    }
    if (fn) fn(target, level, internal_format, width, height, border, format, type, src);
    if (width == CAP_W && height == CAP_H) {
        if ((mode == SOURCE_MMI_CAPTURE && g_state == 2) || mode == SOURCE_CARPLAY_ALT_111) {
            configure_draw_pacing();
            g_texture_ready = 1;
            g_next_draw_capture_us = now_us64() + g_draw_frame_period_us;
        }
    }
}

void glTexSubImage2D(unsigned int target, int level, int xoffset, int yoffset,
                     int width, int height, unsigned int format,
                     unsigned int type, const void *pixels) {
    void (*fn)(unsigned int, int, int, int, int, int, unsigned int, unsigned int, const void *);
    const void *src = pixels;
    int mode;
    if (!g_gles) g_gles = dlopen("libGLESv2.so.1", RTLD_LAZY);
    fn = (void (*)(unsigned int, int, int, int, int, int, unsigned int, unsigned int, const void *))
        dlsym(g_gles, "glTexSubImage2D");
    mode = source_mode();
    if (width == CAP_W && height == CAP_H && g_texture_ready) return;
    if (width == CAP_W && height == CAP_H) {
        if (mode == SOURCE_CARPLAY_ALT_111) {
            src = source_pixels((const void *)0);
            if (!src) {
                log_line("ALT111_PROVIDER dropped network fallback subimage", width, height, 0);
                return;
            }
        } else {
            src = source_pixels(pixels);
        }
    }
    if (fn) fn(target, level, xoffset, yoffset, width, height, format, type, src);
}

static void pump_direct_texture(void) {
    void (*tex_sub)(unsigned int, int, int, int, int, int,
                    unsigned int, unsigned int, const void *);
    const void *pixels;
    u64 current;
    int mode;
    if (!g_texture_ready) return;
    mode = source_mode();
    if (mode == SOURCE_MMI_CAPTURE && g_state != 2) return;
    current = now_us64();
    if (current == 0 || current < g_next_draw_capture_us) return;
    pixels = source_pixels((const void *)0);
    if (!pixels) {
        /* In integrated mode a missing provider frame means blank/unchanged texture,
         * never MMI fallback. Keep pumping so a later valid private frame can appear. */
        g_next_draw_capture_us = current + g_draw_frame_period_us;
        return;
    }
    tex_sub = (void (*)(unsigned int, int, int, int, int, int,
                        unsigned int, unsigned int, const void *))
        dlsym(g_gles, "glTexSubImage2D");
    if (!tex_sub) return;
    tex_sub(GL_TEXTURE_2D, 0, 0, 0, CAP_W, CAP_H,
            GL_RGBA, GL_UNSIGNED_BYTE, pixels);
    if (!g_draw_pump_logged) {
        g_draw_pump_logged = 1;
        if (mode == SOURCE_CARPLAY_ALT_111)
            log_line("ALT111 draw-clock texture pump started", g_draw_target_fps, CAP_W, CAP_H);
        else
            log_line("direct draw-clock texture pump started", g_draw_target_fps, CAP_W, CAP_H);
    }
    current = now_us64();
    if (current > g_next_draw_capture_us + g_draw_frame_period_us)
        g_next_draw_capture_us = current + g_draw_frame_period_us;
    else
        g_next_draw_capture_us += g_draw_frame_period_us;
}

void glDrawArrays(unsigned int mode, int first, int count) {
    void (*fn)(unsigned int, int, int);
    if (!g_gles) g_gles = dlopen("libGLESv2.so.1", RTLD_LAZY);
    fn = (void (*)(unsigned int, int, int))dlsym(g_gles, "glDrawArrays");
    if (mode == GL_TRIANGLE_FAN && first == 0 && count == 4)
        pump_direct_texture();
    if (fn) fn(mode, first, count);
}
