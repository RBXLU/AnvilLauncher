// Нативная половина GLFW-шима: очередь событий ввода, EGL-контекст поверх ANGLE
// и JNI-методы для класса dev.anvil.Bridge (см. Java/src/dev/anvil/Bridge.java).
#import <UIKit/UIKit.h>
#include <dlfcn.h>
#include <pthread.h>
#include <unistd.h>
#include <jni.h>
#include "anvil_native.h"

#pragma mark - Очередь событий

enum { EV_KEY = 1, EV_CHAR, EV_BUTTON, EV_CURSOR, EV_SCROLL, EV_RESIZE };

typedef struct { int type, a, b, c, d; double x, y; } Event;

#define QUEUE_SIZE 1024
static Event g_queue[QUEUE_SIZE];
static int g_head, g_tail;
static pthread_mutex_t g_lock = PTHREAD_MUTEX_INITIALIZER;

static int g_width = 1280, g_height = 720;
static double g_cursorX, g_cursorY;
static bool g_grabbed;
static void (*g_grabCallback)(bool);
static void *g_layer;

static void push(Event e) {
    pthread_mutex_lock(&g_lock);
    int next = (g_tail + 1) % QUEUE_SIZE;
    if (next != g_head) { g_queue[g_tail] = e; g_tail = next; }
    pthread_mutex_unlock(&g_lock);
}

void anvil_set_surface(void *layer, int width, int height) {
    g_layer = layer;
    if (width == g_width && height == g_height) return;
    g_width = width; g_height = height;
    push((Event){ .type = EV_RESIZE, .a = width, .b = height });
}

void anvil_send_key(int key, int scancode, int action, int mods) {
    push((Event){ .type = EV_KEY, .a = key, .b = scancode, .c = action, .d = mods });
}
void anvil_send_char(uint32_t cp, int mods) {
    push((Event){ .type = EV_CHAR, .a = (int)cp, .b = mods });
}
void anvil_send_mouse_button(int button, int action, int mods) {
    push((Event){ .type = EV_BUTTON, .a = button, .b = action, .c = mods });
}
void anvil_send_cursor_pos(double x, double y) {
    g_cursorX = x; g_cursorY = y;
    push((Event){ .type = EV_CURSOR, .x = x, .y = y });
}
void anvil_send_cursor_delta(double dx, double dy) {
    double x = g_cursorX + dx, y = g_cursorY + dy;
    if (!g_grabbed) {
        x = MAX(0, MIN(x, g_width));
        y = MAX(0, MIN(y, g_height));
    }
    anvil_send_cursor_pos(x, y);
}
void anvil_send_scroll(double dx, double dy) {
    push((Event){ .type = EV_SCROLL, .x = dx, .y = dy });
}
bool anvil_is_grabbed(void) { return g_grabbed; }
void anvil_set_grab_callback(void (*cb)(bool)) { g_grabCallback = cb; }

#pragma mark - EGL (ANGLE, Metal)

typedef void *EGLDisplay, *EGLConfig, *EGLContext, *EGLSurface;
typedef int32_t EGLint;
typedef unsigned int EGLBoolean;
#define EGL_NONE 0x3038
#define EGL_RED_SIZE 0x3024
#define EGL_GREEN_SIZE 0x3023
#define EGL_BLUE_SIZE 0x3022
#define EGL_ALPHA_SIZE 0x3021
#define EGL_DEPTH_SIZE 0x3025
#define EGL_STENCIL_SIZE 0x3026
#define EGL_SURFACE_TYPE 0x3033
#define EGL_WINDOW_BIT 0x0004
#define EGL_RENDERABLE_TYPE 0x3040
#define EGL_OPENGL_ES3_BIT 0x0040
#define EGL_CONTEXT_CLIENT_VERSION 0x3098
#define EGL_OPENGL_ES_API 0x30A0

static struct {
    EGLDisplay (*GetDisplay)(void *);
    EGLBoolean (*Initialize)(EGLDisplay, EGLint *, EGLint *);
    EGLBoolean (*BindAPI)(unsigned int);
    EGLBoolean (*ChooseConfig)(EGLDisplay, const EGLint *, EGLConfig *, EGLint, EGLint *);
    EGLSurface (*CreateWindowSurface)(EGLDisplay, EGLConfig, void *, const EGLint *);
    EGLContext (*CreateContext)(EGLDisplay, EGLConfig, EGLContext, const EGLint *);
    EGLBoolean (*MakeCurrent)(EGLDisplay, EGLSurface, EGLSurface, EGLContext);
    EGLBoolean (*SwapBuffers)(EGLDisplay, EGLSurface);
    EGLBoolean (*SwapInterval)(EGLDisplay, EGLint);
    void *(*GetProcAddress)(const char *);
    EGLint (*GetError)(void);
    EGLSurface (*GetCurrentSurface)(EGLint);
} egl;
#define EGL_DRAW 0x3059
#define EGL_SUCCESS 0x3000

static EGLDisplay g_display;
static EGLConfig g_config;
static EGLSurface g_surface;
static EGLContext g_context;
static void *g_glLib;

/// Загрузка библиотеки рендерера. MobileGlues при загрузке делает текущим свой временный
/// pbuffer-контекст (на iOS он его не отвязывает), поэтому грузим его до создания нашего контекста.
static void load_renderer(void) {
    if (g_glLib) return;
    char path[512];
    snprintf(path, sizeof(path), "@rpath/%s", getenv("ANVIL_RENDERER") ?: "libmobileglues.dylib");
    g_glLib = dlopen(path, RTLD_GLOBAL);
    if (!g_glLib) fprintf(stderr, "[Anvil] %s: %s\n", path, dlerror());
}

static bool egl_init(void) {
    if (g_display) return true;
    load_renderer();
    void *lib = dlopen("@rpath/libEGL.framework/libEGL", RTLD_GLOBAL);
    if (!lib) { fprintf(stderr, "[Anvil] libEGL: %s\n", dlerror()); return false; }
#define LOAD(name) egl.name = dlsym(lib, "egl" #name)
    LOAD(GetDisplay); LOAD(Initialize); LOAD(BindAPI); LOAD(ChooseConfig);
    LOAD(CreateWindowSurface); LOAD(CreateContext); LOAD(MakeCurrent);
    LOAD(SwapBuffers); LOAD(SwapInterval); LOAD(GetProcAddress); LOAD(GetError); LOAD(GetCurrentSurface);
#undef LOAD
    g_display = egl.GetDisplay(NULL);
    if (!g_display || !egl.Initialize(g_display, NULL, NULL)) return false;
    egl.BindAPI(EGL_OPENGL_ES_API);
    const EGLint attrs[] = {
        EGL_RED_SIZE, 8, EGL_GREEN_SIZE, 8, EGL_BLUE_SIZE, 8, EGL_ALPHA_SIZE, 8,
        EGL_DEPTH_SIZE, 24, EGL_STENCIL_SIZE, 8,
        EGL_SURFACE_TYPE, EGL_WINDOW_BIT, EGL_RENDERABLE_TYPE, EGL_OPENGL_ES3_BIT, EGL_NONE
    };
    EGLint count = 0;
    return egl.ChooseConfig(g_display, attrs, &g_config, 1, &count) && count > 0;
}

#pragma mark - JNI: dev.anvil.Bridge

#define JNI_FN(name) Java_dev_anvil_Bridge_##name

JNIEXPORT jint JNICALL JNI_FN(nPollEvent)(JNIEnv *env, jclass cls, jdoubleArray out) {
    pthread_mutex_lock(&g_lock);
    if (g_head == g_tail) { pthread_mutex_unlock(&g_lock); return 0; }
    Event e = g_queue[g_head];
    g_head = (g_head + 1) % QUEUE_SIZE;
    pthread_mutex_unlock(&g_lock);
    jdouble values[6] = { e.a, e.b, e.c, e.d, e.x, e.y };
    (*env)->SetDoubleArrayRegion(env, out, 0, 6, values);
    return e.type;
}

JNIEXPORT jint JNICALL JNI_FN(nWidth)(JNIEnv *env, jclass cls) { return g_width; }
JNIEXPORT jint JNICALL JNI_FN(nHeight)(JNIEnv *env, jclass cls) { return g_height; }
JNIEXPORT jdouble JNICALL JNI_FN(nCursorX)(JNIEnv *env, jclass cls) { return g_cursorX; }
JNIEXPORT jdouble JNICALL JNI_FN(nCursorY)(JNIEnv *env, jclass cls) { return g_cursorY; }

JNIEXPORT void JNICALL JNI_FN(nSetCursorPos)(JNIEnv *env, jclass cls, jdouble x, jdouble y) {
    g_cursorX = x; g_cursorY = y;
}

JNIEXPORT void JNICALL JNI_FN(nSetGrab)(JNIEnv *env, jclass cls, jboolean grab) {
    if (g_grabbed == (bool)grab) return;
    g_grabbed = grab;
    if (!grab) { g_cursorX = g_width / 2.0; g_cursorY = g_height / 2.0; }
    if (g_grabCallback) g_grabCallback(grab);
}

/// Слой берём у интерфейса, если UIKit ещё не успел его передать: без слоя ANGLE рисует в никуда.
static void *current_layer(void) {
    if (g_layer) return g_layer;
    for (int i = 0; i < 50 && !g_layer; i++) usleep(100 * 1000);
    if (!g_layer) fprintf(stderr, "[Anvil] Слой для рендера так и не появился\n");
    return g_layer;
}

static void log_layer(const char *stage) {
    void *ptr = g_layer;
    dispatch_sync(dispatch_get_main_queue(), ^{
        CALayer *layer = (__bridge CALayer *)ptr;
        fprintf(stderr, "[Anvil] %s: layer=%p %s bounds=%.0fx%.0f scale=%.2f hidden=%d superlayer=%p\n",
                stage, ptr, layer ? NSStringFromClass(layer.class).UTF8String : "nil",
                layer.bounds.size.width, layer.bounds.size.height, layer.contentsScale,
                layer.hidden, (__bridge void *)layer.superlayer);
    });
}

JNIEXPORT jlong JNICALL JNI_FN(nCreateContext)(JNIEnv *env, jclass cls, jlong share) {
    if (!egl_init()) {
        fprintf(stderr, "[Anvil] EGL не инициализировался: 0x%x\n", egl.GetError ? egl.GetError() : 0);
        return 0;
    }
    if (!g_surface) {
        void *layer = current_layer();
        log_layer("eglCreateWindowSurface");
        g_surface = egl.CreateWindowSurface(g_display, g_config, layer, NULL);
        fprintf(stderr, "[Anvil] eglCreateWindowSurface -> %p (0x%x)\n", g_surface, egl.GetError());
        if (!g_surface) return 0; // без поверхности картинки не будет: пусть игра сообщит об ошибке
    }
    const EGLint attrs[] = { EGL_CONTEXT_CLIENT_VERSION, 3, EGL_NONE };
    EGLContext ctx = egl.CreateContext(g_display, g_config, (EGLContext)share, attrs);
    fprintf(stderr, "[Anvil] eglCreateContext -> %p (0x%x)\n", ctx, egl.GetError());
    return (jlong)ctx;
}

JNIEXPORT void JNICALL JNI_FN(nMakeCurrent)(JNIEnv *env, jclass cls, jlong ctx) {
    if (!g_display) return;
    EGLSurface s = ctx ? g_surface : NULL;
    g_context = (EGLContext)ctx;
    EGLBoolean ok = egl.MakeCurrent(g_display, s, s, (EGLContext)ctx);
    fprintf(stderr, "[Anvil] eglMakeCurrent(ctx=%p, surface=%p) -> %d (0x%x)\n", (void *)ctx, s, ok, egl.GetError());
}

JNIEXPORT void JNICALL JNI_FN(nSwapBuffers)(JNIEnv *env, jclass cls) {
    static int frames;
    if (!g_display || !g_surface) {
        if (frames++ < 3) fprintf(stderr, "[Anvil] SwapBuffers без поверхности\n");
        return;
    }
    // Подстраховка: если кто-то перепривязал поток к своему контексту, возвращаем наш.
    if (g_context && egl.GetCurrentSurface && egl.GetCurrentSurface(EGL_DRAW) != g_surface) {
        static int rebinds;
        if (rebinds++ < 5) fprintf(stderr, "[Anvil] Чужой текущий контекст, возвращаем свой\n");
        egl.MakeCurrent(g_display, g_surface, g_surface, g_context);
    }
    EGLBoolean ok = egl.SwapBuffers(g_display, g_surface);
    EGLint error = egl.GetError();
    // Первые кадры, каждый 600-й и первые ошибки пишем в лог, но не на каждом кадре.
    static int failures;
    if (frames < 3 || frames % 600 == 0 || (!ok && failures++ < 5)) {
        fprintf(stderr, "[Anvil] eglSwapBuffers #%d -> %d (0x%x)\n", frames, ok, error);
        if (frames == 0) log_layer("first swap");
    }
    frames++;
}

JNIEXPORT void JNICALL JNI_FN(nSwapInterval)(JNIEnv *env, jclass cls, jint interval) {
    if (g_display) egl.SwapInterval(g_display, interval);
}

JNIEXPORT jlong JNICALL JNI_FN(nGetProcAddress)(JNIEnv *env, jclass cls, jstring jname) {
    const char *name = (*env)->GetStringUTFChars(env, jname, NULL);
    load_renderer();
    void *fn = g_glLib ? dlsym(g_glLib, name) : NULL;
    if (!fn && egl.GetProcAddress) fn = egl.GetProcAddress(name);
    (*env)->ReleaseStringUTFChars(env, jname, name);
    return (jlong)fn;
}

JNIEXPORT jstring JNICALL JNI_FN(nGetClipboard)(JNIEnv *env, jclass cls) {
    __block NSString *text;
    dispatch_sync(dispatch_get_main_queue(), ^{ text = UIPasteboard.generalPasteboard.string; });
    return (*env)->NewStringUTF(env, (text ?: @"").UTF8String);
}

JNIEXPORT void JNICALL JNI_FN(nSetClipboard)(JNIEnv *env, jclass cls, jstring jtext) {
    const char *chars = (*env)->GetStringUTFChars(env, jtext, NULL);
    NSString *text = @(chars);
    (*env)->ReleaseStringUTFChars(env, jtext, chars);
    dispatch_async(dispatch_get_main_queue(), ^{ UIPasteboard.generalPasteboard.string = text; });
}
