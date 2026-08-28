/*
 * P1404 compatibility replacement for the two libdisplayinit entry points
 * used by OneB1t's opengl-render-qnx.
 *
 * The stock P1404 libdisplayinit calls screen_create_window_type() with a
 * null Screen context. P1404's libscreen rejects that with EINVAL. This shim
 * creates a real application context, then reproduces the remaining property
 * sequence from the vehicle's own libdisplayinit.so.
 */

typedef void *screen_context_t;
typedef void *screen_window_t;

extern int printf(const char *, ...);
extern int fflush(void *);
extern void exit(int);
extern int screen_create_context(screen_context_t *, int);
extern int screen_create_window_type(screen_window_t *, screen_context_t, int);
extern int screen_set_window_property_iv(screen_window_t, int, const int *);
extern int screen_set_window_property_cv(screen_window_t, int, int, const char *);
extern int screen_get_window_property_iv(screen_window_t, int, int *);
extern int screen_manage_window(screen_window_t, const char *);
extern int screen_create_window_buffers(screen_window_t, int);

#define SCREEN_APPLICATION_CONTEXT 0
#define SCREEN_APPLICATION_WINDOW 0
#define SCREEN_PROPERTY_FORMAT 14
#define SCREEN_PROPERTY_ID_STRING 20
#define SCREEN_PROPERTY_POSITION 35
#define SCREEN_PROPERTY_SIZE 40
#define SCREEN_PROPERTY_USAGE 48
#define SCREEN_PROPERTY_VISIBLE 51
#define SCREEN_FORMAT_RGBA8888 8
#define SCREEN_USAGE_OPENGL_ES2 (1 << 5)

static screen_context_t g_context;
static screen_window_t g_window;

static void fatal_stage(const char *stage, int rc) {
    printf("[p1404-displayinit] FAILED stage=%s rc=%d\n", stage, rc);
    fflush((void *)0);
    exit(41);
}

int display_init(int unused_a, int unused_b) {
    (void)unused_a;
    (void)unused_b;
    printf("[p1404-displayinit] compatibility shim selected\n");
    fflush((void *)0);
    return 1;
}

int display_create_window(void *egl_display, void *egl_config, int width, int height,
                          int displayable, void **native_window, int *kd_window) {
    int rc;
    int visible = 1;
    int size[2];
    int position[2];
    int actual_position[2] = { -1, -1 };
    int format = SCREEN_FORMAT_RGBA8888;
    int usage = SCREEN_USAGE_OPENGL_ES2;
    char id[16];
    int id_len = 0;
    int requested_displayable = displayable;
    /* P1404 context 76 is the dedicated full-screen virtual-cockpit map
     * transport and contains only displayable 58
     * (DISPLAYABLE_GOOGLE_EARTH_KOMBI_MAP_VIEW).  Using that vacant slot
     * avoids racing the stock map window (33) and the route overlay (20). */
    int value = 58;

    (void)egl_display;
    (void)egl_config;
    size[0] = width;
    size[1] = height;
    /* Context 76 owns the complete 1440x542 virtual-cockpit canvas.  A
     * full-size window is anchored at the origin; the renderer centers the
     * 90-percent MMI texture inside it.  Keep a calculated fallback for the
     * small self-test window. */
    position[0] = width < 1440 ? (1440 - width) / 2 : 0;
    position[1] = height < 542 ? (542 - height) / 2 : 0;

    if (value == 0) id[id_len++] = '0';
    else {
        char reverse[16];
        int n = 0;
        if (value < 0) { id[id_len++] = '-'; value = -value; }
        while (value && n < (int)sizeof(reverse)) { reverse[n++] = (char)('0' + (value % 10)); value /= 10; }
        while (n) id[id_len++] = reverse[--n];
    }
    id[id_len] = 0;

    rc = screen_create_context(&g_context, SCREEN_APPLICATION_CONTEXT);
    if (rc != 0 || !g_context) fatal_stage("screen_create_context", rc);
    rc = screen_create_window_type(&g_window, g_context, SCREEN_APPLICATION_WINDOW);
    if (rc != 0 || !g_window) fatal_stage("screen_create_window_type", rc);
    rc = screen_set_window_property_iv(g_window, SCREEN_PROPERTY_VISIBLE, &visible);
    if (rc != 0) fatal_stage("set_visible", rc);
    rc = screen_set_window_property_iv(g_window, SCREEN_PROPERTY_SIZE, size);
    if (rc != 0) fatal_stage("set_size", rc);
    rc = screen_set_window_property_iv(g_window, SCREEN_PROPERTY_POSITION, position);
    if (rc != 0) fatal_stage("set_center_position", rc);
    rc = screen_set_window_property_iv(g_window, SCREEN_PROPERTY_FORMAT, &format);
    if (rc != 0) fatal_stage("set_format_rgba8888", rc);
    rc = screen_set_window_property_iv(g_window, SCREEN_PROPERTY_USAGE, &usage);
    if (rc != 0) fatal_stage("set_usage_gles2", rc);
    rc = screen_set_window_property_cv(g_window, SCREEN_PROPERTY_ID_STRING, id_len, id);
    if (rc != 0) fatal_stage("set_displayable_id", rc);
    rc = screen_manage_window(g_window, "How are you gentlemen?");
    if (rc != 0) fatal_stage("screen_manage_window", rc);
    /* The P1404 manager may apply the displayable layout during manage.
     * Reassert the exact native centering inside the 1440x542 cockpit. */
    rc = screen_set_window_property_iv(g_window, SCREEN_PROPERTY_POSITION, position);
    if (rc != 0) {
        printf("[p1404-displayinit] post-manage center rc=%d\n", rc);
    }
    rc = screen_create_window_buffers(g_window, 2);
    if (rc != 0) fatal_stage("create_two_buffers", rc);

    if (native_window) *native_window = g_window;
    if (kd_window) *kd_window = (int)g_window;
    rc = screen_get_window_property_iv(g_window, SCREEN_PROPERTY_POSITION, actual_position);
    printf("[p1404-displayinit] window ready size=%dx%d requested=%d effective=58 center=%d,%d getrc=%d\n",
           width, height, requested_displayable,
           actual_position[0], actual_position[1], rc);
    fflush((void *)0);
    return 1;
}
