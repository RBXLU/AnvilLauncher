package org.lwjgl.glfw;

/** Заглушка: колбэки шима живут в Java-полях и нативной памяти не занимают. */
public final class Callbacks {
    private Callbacks() {}

    public static void glfwFreeCallbacks(long window) {
        GLFW.resetCallbacks();
    }
}
