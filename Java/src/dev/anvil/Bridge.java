package dev.anvil;

/** JNI-методы, реализованные в исполняемом файле приложения (App/Native/glfw_bridge.m). */
public final class Bridge {
    public static final int EV_KEY = 1, EV_CHAR = 2, EV_BUTTON = 3, EV_CURSOR = 4, EV_SCROLL = 5, EV_RESIZE = 6;

    static {
        // dlopen главного бинарника отдаёт уже загруженный образ, JVM находит в нём Java_dev_anvil_* символы.
        System.load(System.getenv("ANVIL_EXECUTABLE"));
    }

    private Bridge() {}

    public static native int nPollEvent(double[] out);
    public static native int nWidth();
    public static native int nHeight();
    public static native double nCursorX();
    public static native double nCursorY();
    public static native void nSetCursorPos(double x, double y);
    public static native void nSetGrab(boolean grab);
    public static native long nCreateContext(long share);
    public static native void nMakeCurrent(long context);
    public static native void nSwapBuffers();
    public static native void nSwapInterval(int interval);
    public static native long nGetProcAddress(String name);
    public static native String nGetClipboard();
    public static native void nSetClipboard(String text);
}
