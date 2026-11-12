package org.lwjgl.glfw;

/** Окна Cocoa на iOS нет: Minecraft получает 0 и пропускает macOS-специфичные правки окна. */
public class GLFWNativeCocoa {
    protected GLFWNativeCocoa() {}

    public static int glfwGetCocoaMonitor(long monitor) { return 0; }
    public static long glfwGetCocoaWindow(long window) { return 0L; }
    public static long glfwGetCocoaView(long window) { return 0L; }
}
