/*
 * Minimal EGL diagnostic interposer for the P1404 cockpit window self-test.
 *
 * This library is loaded only into the experimental renderer.  It forwards
 * every intercepted call to the vehicle's real libEGL and prints the result
 * plus EGL error state to stdout, which the worker redirects to the SD log.
 */

typedef void *EGLDisplay;
typedef void *EGLConfig;
typedef void *EGLSurface;
typedef void *EGLContext;
typedef void *EGLNativeDisplayType;
typedef void *EGLNativeWindowType;
typedef int EGLBoolean;
typedef int EGLint;

extern void *dlopen(const char *, int);
extern void *dlsym(void *, const char *);
extern int printf(const char *, ...);
extern int fflush(void *);

#define RTLD_LAZY 1
#define EGL_FALSE 0

static void *g_egl;
static void *g_gles;
static EGLint (*real_eglGetError)(void);
static unsigned int g_swap_count;
static unsigned int g_draw_count;
static unsigned int g_tex_image_count;
static unsigned int g_tex_sub_image_count;

static void load_real(void) {
    if (g_egl) return;
    g_egl = dlopen("libEGL.so.1", RTLD_LAZY);
    if (g_egl) real_eglGetError = (EGLint (*)(void))dlsym(g_egl, "eglGetError");
    printf("[egl-diag] real_lib=%p get_error=%p\n", g_egl, (void *)real_eglGetError);
    fflush((void *)0);
}

static void load_gles(void) {
    if (g_gles) return;
    g_gles = dlopen("libGLESv2.so.1", RTLD_LAZY);
    printf("[egl-diag] gles_lib=%p\n", g_gles);
    fflush((void *)0);
}

static EGLint take_error(void) {
    return real_eglGetError ? real_eglGetError() : -1;
}

EGLDisplay eglGetDisplay(EGLNativeDisplayType native_display) {
    EGLDisplay (*fn)(EGLNativeDisplayType);
    EGLDisplay out;
    load_real();
    fn = (EGLDisplay (*)(EGLNativeDisplayType))dlsym(g_egl, "eglGetDisplay");
    out = fn ? fn(native_display) : (EGLDisplay)0;
    printf("[egl-diag] eglGetDisplay native=%p out=%p err=0x%x\n",
           native_display, out, (unsigned int)take_error());
    fflush((void *)0);
    return out;
}

EGLBoolean eglInitialize(EGLDisplay display, EGLint *major, EGLint *minor) {
    EGLBoolean (*fn)(EGLDisplay, EGLint *, EGLint *);
    EGLBoolean out;
    load_real();
    fn = (EGLBoolean (*)(EGLDisplay, EGLint *, EGLint *))dlsym(g_egl, "eglInitialize");
    out = fn ? fn(display, major, minor) : EGL_FALSE;
    printf("[egl-diag] eglInitialize display=%p out=%d version=%d.%d err=0x%x\n",
           display, out, major ? *major : -1, minor ? *minor : -1,
           (unsigned int)take_error());
    fflush((void *)0);
    return out;
}

EGLBoolean eglChooseConfig(EGLDisplay display, const EGLint *attributes,
                           EGLConfig *configs, EGLint config_size,
                           EGLint *num_configs) {
    EGLBoolean (*fn)(EGLDisplay, const EGLint *, EGLConfig *, EGLint, EGLint *);
    EGLBoolean out;
    load_real();
    fn = (EGLBoolean (*)(EGLDisplay, const EGLint *, EGLConfig *, EGLint, EGLint *))
        dlsym(g_egl, "eglChooseConfig");
    out = fn ? fn(display, attributes, configs, config_size, num_configs) : EGL_FALSE;
    printf("[egl-diag] eglChooseConfig out=%d count=%d first=%p err=0x%x\n",
           out, num_configs ? *num_configs : -1,
           (configs && config_size > 0) ? configs[0] : (EGLConfig)0,
           (unsigned int)take_error());
    fflush((void *)0);
    return out;
}

EGLSurface eglCreateWindowSurface(EGLDisplay display, EGLConfig config,
                                  EGLNativeWindowType window,
                                  const EGLint *attributes) {
    EGLSurface (*fn)(EGLDisplay, EGLConfig, EGLNativeWindowType, const EGLint *);
    EGLSurface out;
    load_real();
    fn = (EGLSurface (*)(EGLDisplay, EGLConfig, EGLNativeWindowType, const EGLint *))
        dlsym(g_egl, "eglCreateWindowSurface");
    out = fn ? fn(display, config, window, attributes) : (EGLSurface)0;
    printf("[egl-diag] eglCreateWindowSurface window=%p out=%p ok=%d err=0x%x\n",
           window, out, out != (EGLSurface)0, (unsigned int)take_error());
    fflush((void *)0);
    return out;
}

EGLBoolean eglBindAPI(EGLint api) {
    EGLBoolean (*fn)(EGLint);
    EGLBoolean out;
    load_real();
    fn = (EGLBoolean (*)(EGLint))dlsym(g_egl, "eglBindAPI");
    out = fn ? fn(api) : EGL_FALSE;
    printf("[egl-diag] eglBindAPI api=0x%x out=%d err=0x%x\n",
           (unsigned int)api, out, (unsigned int)take_error());
    fflush((void *)0);
    return out;
}

EGLContext eglCreateContext(EGLDisplay display, EGLConfig config,
                            EGLContext share, const EGLint *attributes) {
    EGLContext (*fn)(EGLDisplay, EGLConfig, EGLContext, const EGLint *);
    EGLContext out;
    load_real();
    fn = (EGLContext (*)(EGLDisplay, EGLConfig, EGLContext, const EGLint *))
        dlsym(g_egl, "eglCreateContext");
    out = fn ? fn(display, config, share, attributes) : (EGLContext)0;
    printf("[egl-diag] eglCreateContext out=%p ok=%d err=0x%x\n",
           out, out != (EGLContext)0, (unsigned int)take_error());
    fflush((void *)0);
    return out;
}

EGLBoolean eglMakeCurrent(EGLDisplay display, EGLSurface draw,
                          EGLSurface read, EGLContext context) {
    EGLBoolean (*fn)(EGLDisplay, EGLSurface, EGLSurface, EGLContext);
    EGLBoolean out;
    load_real();
    fn = (EGLBoolean (*)(EGLDisplay, EGLSurface, EGLSurface, EGLContext))
        dlsym(g_egl, "eglMakeCurrent");
    out = fn ? fn(display, draw, read, context) : EGL_FALSE;
    printf("[egl-diag] eglMakeCurrent draw=%p read=%p context=%p out=%d err=0x%x\n",
           draw, read, context, out, (unsigned int)take_error());
    fflush((void *)0);
    return out;
}

EGLBoolean eglSwapBuffers(EGLDisplay display, EGLSurface surface) {
    EGLBoolean (*fn)(EGLDisplay, EGLSurface);
    EGLBoolean out;
    EGLint err;
    load_real();
    fn = (EGLBoolean (*)(EGLDisplay, EGLSurface))dlsym(g_egl, "eglSwapBuffers");
    out = fn ? fn(display, surface) : EGL_FALSE;
    err = take_error();
    g_swap_count++;
    if (g_swap_count <= 3 || !out || (g_swap_count % 300U) == 0U) {
        printf("[egl-diag] eglSwapBuffers count=%u surface=%p out=%d err=0x%x\n",
               g_swap_count, surface, out, (unsigned int)err);
        fflush((void *)0);
    }
    return out;
}

EGLint eglGetError(void) {
    load_real();
    return take_error();
}

void glDrawArrays(unsigned int mode, int first, int count) {
    void (*fn)(unsigned int, int, int);
    load_gles();
    fn = (void (*)(unsigned int, int, int))dlsym(g_gles, "glDrawArrays");
    g_draw_count++;
    if (g_draw_count <= 3U || (g_draw_count % 300U) == 0U) {
        printf("[egl-diag] glDrawArrays count=%u mode=0x%x first=%d vertices=%d\n",
               g_draw_count, mode, first, count);
        fflush((void *)0);
    }
    if (fn) fn(mode, first, count);
}

void glTexImage2D(unsigned int target, int level, int internal_format,
                  int width, int height, int border, unsigned int format,
                  unsigned int type, const void *pixels) {
    void (*fn)(unsigned int, int, int, int, int, int,
               unsigned int, unsigned int, const void *);
    load_gles();
    fn = (void (*)(unsigned int, int, int, int, int, int,
                   unsigned int, unsigned int, const void *))
        dlsym(g_gles, "glTexImage2D");
    g_tex_image_count++;
    printf("[egl-diag] glTexImage2D count=%u size=%dx%d pixels=%p format=0x%x type=0x%x\n",
           g_tex_image_count, width, height, pixels, format, type);
    fflush((void *)0);
    if (fn) fn(target, level, internal_format, width, height, border,
               format, type, pixels);
}

void glTexSubImage2D(unsigned int target, int level, int xoffset, int yoffset,
                     int width, int height, unsigned int format,
                     unsigned int type, const void *pixels) {
    void (*fn)(unsigned int, int, int, int, int, int,
               unsigned int, unsigned int, const void *);
    load_gles();
    fn = (void (*)(unsigned int, int, int, int, int, int,
                   unsigned int, unsigned int, const void *))
        dlsym(g_gles, "glTexSubImage2D");
    g_tex_sub_image_count++;
    if (g_tex_sub_image_count <= 3U || (g_tex_sub_image_count % 60U) == 0U) {
        printf("[egl-diag] glTexSubImage2D count=%u offset=%d,%d size=%dx%d pixels=%p\n",
               g_tex_sub_image_count, xoffset, yoffset, width, height, pixels);
        fflush((void *)0);
    }
    if (fn) fn(target, level, xoffset, yoffset, width, height,
               format, type, pixels);
}
