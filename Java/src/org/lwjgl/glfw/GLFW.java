package org.lwjgl.glfw;

import dev.anvil.Bridge;
import java.nio.ByteBuffer;
import java.nio.DoubleBuffer;
import java.nio.FloatBuffer;
import java.nio.IntBuffer;
import org.lwjgl.PointerBuffer;
import org.lwjgl.system.MemoryUtil;

/**
 * Замена GLFW для iOS. Ложится в classpath раньше lwjgl-glfw.jar и перекрывает оригинальный класс.
 * Окно одно, его роль играет CAMetalLayer лаунчера; ввод приходит из нативной очереди Bridge.
 */
public class GLFW {
    public static final int GLFW_VERSION_MAJOR = 3, GLFW_VERSION_MINOR = 4, GLFW_VERSION_REVISION = 0;
    public static final int GLFW_TRUE = 1, GLFW_FALSE = 0;
    public static final int GLFW_RELEASE = 0, GLFW_PRESS = 1, GLFW_REPEAT = 2;
    public static final int GLFW_DONT_CARE = -1;

    public static final int GLFW_MOD_SHIFT = 0x1, GLFW_MOD_CONTROL = 0x2, GLFW_MOD_ALT = 0x4,
            GLFW_MOD_SUPER = 0x8, GLFW_MOD_CAPS_LOCK = 0x10, GLFW_MOD_NUM_LOCK = 0x20;

    public static final int GLFW_KEY_UNKNOWN = -1, GLFW_KEY_SPACE = 32, GLFW_KEY_ESCAPE = 256,
            GLFW_KEY_ENTER = 257, GLFW_KEY_TAB = 258, GLFW_KEY_BACKSPACE = 259, GLFW_KEY_LAST = 348;

    public static final int GLFW_MOUSE_BUTTON_1 = 0, GLFW_MOUSE_BUTTON_2 = 1, GLFW_MOUSE_BUTTON_3 = 2,
            GLFW_MOUSE_BUTTON_LEFT = 0, GLFW_MOUSE_BUTTON_RIGHT = 1, GLFW_MOUSE_BUTTON_MIDDLE = 2,
            GLFW_MOUSE_BUTTON_LAST = 7;

    public static final int GLFW_FOCUSED = 0x20001, GLFW_ICONIFIED = 0x20002, GLFW_RESIZABLE = 0x20003,
            GLFW_VISIBLE = 0x20004, GLFW_DECORATED = 0x20005, GLFW_MAXIMIZED = 0x20008, GLFW_HOVERED = 0x2000B;
    public static final int GLFW_CLIENT_API = 0x22001, GLFW_CONTEXT_VERSION_MAJOR = 0x22002,
            GLFW_CONTEXT_VERSION_MINOR = 0x22003, GLFW_OPENGL_PROFILE = 0x22008,
            GLFW_OPENGL_API = 0x30001, GLFW_OPENGL_CORE_PROFILE = 0x32001;

    public static final int GLFW_CURSOR = 0x33001, GLFW_STICKY_KEYS = 0x33002,
            GLFW_STICKY_MOUSE_BUTTONS = 0x33003, GLFW_LOCK_KEY_MODS = 0x33004, GLFW_RAW_MOUSE_MOTION = 0x33005;
    public static final int GLFW_CURSOR_NORMAL = 0x34001, GLFW_CURSOR_HIDDEN = 0x34002, GLFW_CURSOR_DISABLED = 0x34003;

    public static final int GLFW_PLATFORM = 0x50003, GLFW_ANY_PLATFORM = 0x60000, GLFW_PLATFORM_COCOA = 0x60002;
    public static final int GLFW_NO_ERROR = 0;

    private static final long WINDOW = 1L, MONITOR = 1L;
    private static final long START = System.nanoTime();
    private static final byte[] KEYS = new byte[GLFW_KEY_LAST + 1];
    private static final byte[] BUTTONS = new byte[GLFW_MOUSE_BUTTON_LAST + 1];
    private static final double[] EVENT = new double[6];

    private static long context, currentContext;
    private static boolean shouldClose;
    private static int cursorMode = GLFW_CURSOR_NORMAL;
    private static double timeOffset;
    private static GLFWVidMode.Buffer vidModes;

    private static GLFWErrorCallbackI errorCallback;
    private static GLFWKeyCallbackI keyCallback;
    private static GLFWCharCallbackI charCallback;
    private static GLFWCharModsCallbackI charModsCallback;
    private static GLFWMouseButtonCallbackI mouseButtonCallback;
    private static GLFWCursorPosCallbackI cursorPosCallback;
    private static GLFWCursorEnterCallbackI cursorEnterCallback;
    private static GLFWScrollCallbackI scrollCallback;
    private static GLFWFramebufferSizeCallbackI framebufferSizeCallback;
    private static GLFWWindowSizeCallbackI windowSizeCallback;
    private static GLFWWindowPosCallbackI windowPosCallback;
    private static GLFWWindowFocusCallbackI windowFocusCallback;
    private static GLFWWindowCloseCallbackI windowCloseCallback;

    protected GLFW() {}

    static void resetCallbacks() {
        keyCallback = null; charCallback = null; charModsCallback = null; mouseButtonCallback = null;
        cursorPosCallback = null; cursorEnterCallback = null; scrollCallback = null;
        framebufferSizeCallback = null; windowSizeCallback = null; windowPosCallback = null;
        windowFocusCallback = null; windowCloseCallback = null;
    }

    // ---------- Инициализация ----------

    public static boolean glfwInit() { return true; }
    public static void glfwTerminate() {}
    public static void glfwInitHint(int hint, int value) {}
    public static int glfwGetPlatform() { return GLFW_PLATFORM_COCOA; }
    public static boolean glfwPlatformSupported(int platform) { return platform == GLFW_PLATFORM_COCOA; }
    public static String glfwGetVersionString() { return "3.4.0 Anvil iOS shim"; }

    public static void glfwGetVersion(IntBuffer major, IntBuffer minor, IntBuffer rev) {
        if (major != null) major.put(major.position(), GLFW_VERSION_MAJOR);
        if (minor != null) minor.put(minor.position(), GLFW_VERSION_MINOR);
        if (rev != null) rev.put(rev.position(), GLFW_VERSION_REVISION);
    }

    public static int glfwGetError(PointerBuffer description) {
        if (description != null) description.put(description.position(), 0L);
        return GLFW_NO_ERROR;
    }

    public static GLFWErrorCallback glfwSetErrorCallback(GLFWErrorCallbackI cb) {
        errorCallback = cb;
        return null;
    }

    // ---------- Окно ----------

    public static void glfwDefaultWindowHints() {}
    public static void glfwWindowHint(int hint, int value) {}
    public static void glfwWindowHintString(int hint, CharSequence value) {}
    public static void glfwWindowHintString(int hint, ByteBuffer value) {}

    public static long glfwCreateWindow(int width, int height, CharSequence title, long monitor, long share) {
        context = Bridge.nCreateContext(0L);
        return context == 0L ? 0L : WINDOW;
    }

    public static long glfwCreateWindow(int width, int height, ByteBuffer title, long monitor, long share) {
        return glfwCreateWindow(width, height, "", monitor, share);
    }

    public static void glfwDestroyWindow(long window) {
        Bridge.nMakeCurrent(0L);
        currentContext = 0L;
    }

    public static boolean glfwWindowShouldClose(long window) { return shouldClose; }
    public static void glfwSetWindowShouldClose(long window, boolean value) { shouldClose = value; }
    public static void glfwSetWindowTitle(long window, CharSequence title) {}
    public static void glfwSetWindowTitle(long window, ByteBuffer title) {}
    public static void glfwSetWindowIcon(long window, GLFWImage.Buffer images) {}
    public static void glfwSetWindowPos(long window, int x, int y) {}
    public static void glfwSetWindowSize(long window, int width, int height) {}
    public static void glfwSetWindowSizeLimits(long window, int minW, int minH, int maxW, int maxH) {}
    public static void glfwSetWindowAspectRatio(long window, int numer, int denom) {}
    public static void glfwSetWindowMonitor(long window, long monitor, int x, int y, int w, int h, int refresh) {}
    public static void glfwSetWindowAttrib(long window, int attrib, int value) {}
    public static void glfwShowWindow(long window) {}
    public static void glfwHideWindow(long window) {}
    public static void glfwFocusWindow(long window) {}
    public static void glfwIconifyWindow(long window) {}
    public static void glfwRestoreWindow(long window) {}
    public static void glfwMaximizeWindow(long window) {}
    public static void glfwRequestWindowAttention(long window) {}
    public static long glfwGetWindowMonitor(long window) { return MONITOR; }
    public static float glfwGetWindowOpacity(long window) { return 1f; }
    public static void glfwSetWindowOpacity(long window, float opacity) {}

    public static int glfwGetWindowAttrib(long window, int attrib) {
        switch (attrib) {
            case GLFW_FOCUSED: case GLFW_VISIBLE: case GLFW_HOVERED: case GLFW_MAXIMIZED: return GLFW_TRUE;
            case GLFW_CLIENT_API: return GLFW_OPENGL_API;
            case GLFW_OPENGL_PROFILE: return GLFW_OPENGL_CORE_PROFILE;
            case GLFW_CONTEXT_VERSION_MAJOR: return 3;
            case GLFW_CONTEXT_VERSION_MINOR: return 2;
            default: return GLFW_FALSE;
        }
    }

    public static void glfwGetWindowSize(long window, IntBuffer width, IntBuffer height) {
        if (width != null) width.put(width.position(), Bridge.nWidth());
        if (height != null) height.put(height.position(), Bridge.nHeight());
    }

    public static void glfwGetWindowSize(long window, int[] width, int[] height) {
        if (width != null) width[0] = Bridge.nWidth();
        if (height != null) height[0] = Bridge.nHeight();
    }

    public static void glfwGetFramebufferSize(long window, IntBuffer width, IntBuffer height) {
        glfwGetWindowSize(window, width, height);
    }

    public static void glfwGetFramebufferSize(long window, int[] width, int[] height) {
        glfwGetWindowSize(window, width, height);
    }

    public static void glfwGetWindowPos(long window, IntBuffer x, IntBuffer y) {
        if (x != null) x.put(x.position(), 0);
        if (y != null) y.put(y.position(), 0);
    }

    public static void glfwGetWindowPos(long window, int[] x, int[] y) {
        if (x != null) x[0] = 0;
        if (y != null) y[0] = 0;
    }

    public static void glfwGetWindowFrameSize(long window, IntBuffer l, IntBuffer t, IntBuffer r, IntBuffer b) {
        for (IntBuffer buf : new IntBuffer[]{l, t, r, b}) if (buf != null) buf.put(buf.position(), 0);
    }

    public static void glfwGetWindowContentScale(long window, FloatBuffer x, FloatBuffer y) {
        if (x != null) x.put(x.position(), 1f);
        if (y != null) y.put(y.position(), 1f);
    }

    public static void glfwGetWindowContentScale(long window, float[] x, float[] y) {
        if (x != null) x[0] = 1f;
        if (y != null) y[0] = 1f;
    }

    // ---------- Контекст ----------

    public static void glfwMakeContextCurrent(long window) {
        currentContext = window == 0L ? 0L : context;
        Bridge.nMakeCurrent(currentContext);
    }

    public static long glfwGetCurrentContext() { return currentContext == 0L ? 0L : WINDOW; }
    public static void glfwSwapBuffers(long window) { Bridge.nSwapBuffers(); }
    public static void glfwSwapInterval(int interval) { Bridge.nSwapInterval(interval); }
    public static long glfwGetProcAddress(CharSequence name) { return Bridge.nGetProcAddress(name.toString()); }
    public static long glfwGetProcAddress(ByteBuffer name) { return glfwGetProcAddress(MemoryUtil.memASCII(name)); }
    public static boolean glfwExtensionSupported(CharSequence ext) { return false; }

    // ---------- Мониторы ----------

    public static long glfwGetPrimaryMonitor() { return MONITOR; }

    public static PointerBuffer glfwGetMonitors() {
        PointerBuffer buf = PointerBuffer.allocateDirect(1);
        buf.put(0, MONITOR);
        return buf;
    }

    public static String glfwGetMonitorName(long monitor) { return "iOS Display"; }

    public static GLFWVidMode glfwGetVideoMode(long monitor) { return videoModes().get(0); }

    public static GLFWVidMode.Buffer glfwGetVideoModes(long monitor) { return videoModes(); }

    private static GLFWVidMode.Buffer videoModes() {
        if (vidModes == null) vidModes = GLFWVidMode.create(MemoryUtil.nmemCalloc(1, GLFWVidMode.SIZEOF), 1);
        long address = vidModes.address();
        MemoryUtil.memPutInt(address + GLFWVidMode.WIDTH, Bridge.nWidth());
        MemoryUtil.memPutInt(address + GLFWVidMode.HEIGHT, Bridge.nHeight());
        MemoryUtil.memPutInt(address + GLFWVidMode.REDBITS, 8);
        MemoryUtil.memPutInt(address + GLFWVidMode.GREENBITS, 8);
        MemoryUtil.memPutInt(address + GLFWVidMode.BLUEBITS, 8);
        MemoryUtil.memPutInt(address + GLFWVidMode.REFRESHRATE, Integer.getInteger("anvil.refreshRate", 60));
        return vidModes;
    }

    public static void glfwGetMonitorPos(long monitor, IntBuffer x, IntBuffer y) { glfwGetWindowPos(WINDOW, x, y); }
    public static void glfwGetMonitorPos(long monitor, int[] x, int[] y) { glfwGetWindowPos(WINDOW, x, y); }

    public static void glfwGetMonitorWorkarea(long monitor, IntBuffer x, IntBuffer y, IntBuffer w, IntBuffer h) {
        glfwGetWindowPos(WINDOW, x, y);
        glfwGetWindowSize(WINDOW, w, h);
    }

    public static void glfwGetMonitorContentScale(long monitor, FloatBuffer x, FloatBuffer y) {
        glfwGetWindowContentScale(WINDOW, x, y);
    }

    public static GLFWMonitorCallback glfwSetMonitorCallback(GLFWMonitorCallbackI cb) { return null; }

    // ---------- Ввод ----------

    public static void glfwPollEvents() {
        int type;
        while ((type = Bridge.nPollEvent(EVENT)) != 0) dispatch(type);
    }

    public static void glfwWaitEvents() { glfwPollEvents(); }
    public static void glfwWaitEventsTimeout(double timeout) { glfwPollEvents(); }
    public static void glfwPostEmptyEvent() {}

    private static void dispatch(int type) {
        int a = (int) EVENT[0], b = (int) EVENT[1], c = (int) EVENT[2], d = (int) EVENT[3];
        switch (type) {
            case Bridge.EV_KEY:
                if (a >= 0 && a < KEYS.length) KEYS[a] = (byte) (c == GLFW_RELEASE ? 0 : 1);
                if (keyCallback != null) keyCallback.invoke(WINDOW, a, b, c, d);
                break;
            case Bridge.EV_CHAR:
                if (charCallback != null) charCallback.invoke(WINDOW, a);
                if (charModsCallback != null) charModsCallback.invoke(WINDOW, a, b);
                break;
            case Bridge.EV_BUTTON:
                if (a >= 0 && a < BUTTONS.length) BUTTONS[a] = (byte) b;
                if (mouseButtonCallback != null) mouseButtonCallback.invoke(WINDOW, a, b, c);
                break;
            case Bridge.EV_CURSOR:
                if (cursorPosCallback != null) cursorPosCallback.invoke(WINDOW, EVENT[4], EVENT[5]);
                break;
            case Bridge.EV_SCROLL:
                if (scrollCallback != null) scrollCallback.invoke(WINDOW, EVENT[4], EVENT[5]);
                break;
            case Bridge.EV_RESIZE:
                if (framebufferSizeCallback != null) framebufferSizeCallback.invoke(WINDOW, a, b);
                if (windowSizeCallback != null) windowSizeCallback.invoke(WINDOW, a, b);
                break;
            default:
                break;
        }
    }

    public static int glfwGetKey(long window, int key) {
        return key >= 0 && key < KEYS.length ? KEYS[key] : GLFW_RELEASE;
    }

    public static int glfwGetMouseButton(long window, int button) {
        return button >= 0 && button < BUTTONS.length ? BUTTONS[button] : GLFW_RELEASE;
    }

    public static String glfwGetKeyName(int key, int scancode) {
        if (key >= 'A' && key <= 'Z') return String.valueOf((char) (key + 32));
        if (key >= '0' && key <= '9') return String.valueOf((char) key);
        return null;
    }

    public static int glfwGetKeyScancode(int key) { return key; }

    public static void glfwGetCursorPos(long window, DoubleBuffer x, DoubleBuffer y) {
        if (x != null) x.put(x.position(), Bridge.nCursorX());
        if (y != null) y.put(y.position(), Bridge.nCursorY());
    }

    public static void glfwGetCursorPos(long window, double[] x, double[] y) {
        if (x != null) x[0] = Bridge.nCursorX();
        if (y != null) y[0] = Bridge.nCursorY();
    }

    public static void glfwSetCursorPos(long window, double x, double y) { Bridge.nSetCursorPos(x, y); }

    public static int glfwGetInputMode(long window, int mode) {
        return mode == GLFW_CURSOR ? cursorMode : GLFW_FALSE;
    }

    public static void glfwSetInputMode(long window, int mode, int value) {
        if (mode != GLFW_CURSOR) return;
        cursorMode = value;
        Bridge.nSetGrab(value == GLFW_CURSOR_DISABLED);
    }

    public static boolean glfwRawMouseMotionSupported() { return true; }

    public static long glfwCreateStandardCursor(int shape) { return 1L; }
    public static long glfwCreateCursor(GLFWImage image, int xhot, int yhot) { return 1L; }
    public static void glfwDestroyCursor(long cursor) {}
    public static void glfwSetCursor(long window, long cursor) {}

    public static String glfwGetClipboardString(long window) { return Bridge.nGetClipboard(); }
    public static void glfwSetClipboardString(long window, CharSequence text) { Bridge.nSetClipboard(text.toString()); }
    public static void glfwSetClipboardString(long window, ByteBuffer text) { Bridge.nSetClipboard(MemoryUtil.memUTF8(text)); }

    // Геймпад читает сам лаунчер и превращает в клавиши/мышь, так что GLFW джойстиков не видит.
    public static boolean glfwJoystickPresent(int jid) { return false; }
    public static boolean glfwJoystickIsGamepad(int jid) { return false; }
    public static String glfwGetJoystickName(int jid) { return null; }
    public static String glfwGetGamepadName(int jid) { return null; }
    public static boolean glfwGetGamepadState(int jid, GLFWGamepadState state) { return false; }
    public static boolean glfwUpdateGamepadMappings(ByteBuffer mappings) { return true; }
    public static GLFWJoystickCallback glfwSetJoystickCallback(GLFWJoystickCallbackI cb) { return null; }

    // ---------- Время ----------

    public static double glfwGetTime() { return (System.nanoTime() - START) / 1e9 + timeOffset; }
    public static void glfwSetTime(double time) { timeOffset = time - (System.nanoTime() - START) / 1e9; }
    public static long glfwGetTimerValue() { return System.nanoTime(); }
    public static long glfwGetTimerFrequency() { return 1_000_000_000L; }

    // ---------- Колбэки ----------

    public static GLFWKeyCallback glfwSetKeyCallback(long w, GLFWKeyCallbackI cb) { keyCallback = cb; return null; }
    public static GLFWCharCallback glfwSetCharCallback(long w, GLFWCharCallbackI cb) { charCallback = cb; return null; }
    public static GLFWCharModsCallback glfwSetCharModsCallback(long w, GLFWCharModsCallbackI cb) { charModsCallback = cb; return null; }
    public static GLFWMouseButtonCallback glfwSetMouseButtonCallback(long w, GLFWMouseButtonCallbackI cb) { mouseButtonCallback = cb; return null; }
    public static GLFWCursorPosCallback glfwSetCursorPosCallback(long w, GLFWCursorPosCallbackI cb) { cursorPosCallback = cb; return null; }
    public static GLFWCursorEnterCallback glfwSetCursorEnterCallback(long w, GLFWCursorEnterCallbackI cb) { cursorEnterCallback = cb; return null; }
    public static GLFWScrollCallback glfwSetScrollCallback(long w, GLFWScrollCallbackI cb) { scrollCallback = cb; return null; }
    public static GLFWFramebufferSizeCallback glfwSetFramebufferSizeCallback(long w, GLFWFramebufferSizeCallbackI cb) { framebufferSizeCallback = cb; return null; }
    public static GLFWWindowSizeCallback glfwSetWindowSizeCallback(long w, GLFWWindowSizeCallbackI cb) { windowSizeCallback = cb; return null; }
    public static GLFWWindowPosCallback glfwSetWindowPosCallback(long w, GLFWWindowPosCallbackI cb) { windowPosCallback = cb; return null; }
    public static GLFWWindowFocusCallback glfwSetWindowFocusCallback(long w, GLFWWindowFocusCallbackI cb) { windowFocusCallback = cb; return null; }
    public static GLFWWindowCloseCallback glfwSetWindowCloseCallback(long w, GLFWWindowCloseCallbackI cb) { windowCloseCallback = cb; return null; }
    public static GLFWWindowIconifyCallback glfwSetWindowIconifyCallback(long w, GLFWWindowIconifyCallbackI cb) { return null; }
    public static GLFWWindowMaximizeCallback glfwSetWindowMaximizeCallback(long w, GLFWWindowMaximizeCallbackI cb) { return null; }
    public static GLFWWindowRefreshCallback glfwSetWindowRefreshCallback(long w, GLFWWindowRefreshCallbackI cb) { return null; }
    public static GLFWWindowContentScaleCallback glfwSetWindowContentScaleCallback(long w, GLFWWindowContentScaleCallbackI cb) { return null; }
    public static GLFWDropCallback glfwSetDropCallback(long w, GLFWDropCallbackI cb) { return null; }
}
