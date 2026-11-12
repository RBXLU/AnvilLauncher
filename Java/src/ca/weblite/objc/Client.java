package ca.weblite.objc;

/**
 * Заглушка моста Java → Objective-C. Minecraft считает iOS разновидностью macOS и через этот мост
 * ставит иконку окна и правит его стиль. Настоящий мост требует JNA, а её нативную часть на iOS
 * загрузить нельзя, поэтому все вызовы тихо ничего не делают.
 */
public class Client {
    private static final Client INSTANCE = new Client();

    public static Client getInstance() { return INSTANCE; }
    public static Client getRawClient() { return INSTANCE; }

    public Object send(String receiver, String selector, Object... args) { return null; }
    public Object send(Proxy receiver, String selector, Object... args) { return null; }
    public Proxy sendProxy(String receiver, String selector, Object... args) { return new Proxy(); }
    public Proxy sendProxy(Proxy receiver, String selector, Object... args) { return new Proxy(); }
    public Object sendRaw(String receiver, String selector, Object... args) { return null; }
    public int sendInt(String receiver, String selector, Object... args) { return 0; }
    public boolean sendBoolean(String receiver, String selector, Object... args) { return false; }
    public String sendString(String receiver, String selector, Object... args) { return null; }
}
