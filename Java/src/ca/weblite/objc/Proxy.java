package ca.weblite.objc;

/** Объект-пустышка для заглушки {@link Client}: любые сообщения игнорируются. */
public class Proxy {
    public Object send(String selector, Object... args) { return null; }
    public Proxy sendProxy(String selector, Object... args) { return this; }
    public Object sendRaw(String selector, Object... args) { return null; }
    public int sendInt(String selector, Object... args) { return 0; }
    public boolean sendBoolean(String selector, Object... args) { return false; }
    public String sendString(String selector, Object... args) { return null; }
    public Proxy dealloc() { return this; }
    public Proxy release() { return this; }
    public Proxy retain() { return this; }
}
