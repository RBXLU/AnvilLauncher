// Мост между Swift-лаунчером и нативной частью (JVM, GLFW-шим, JIT).
#pragma once
#include <stdbool.h>
#include <stdint.h>

typedef struct {
    bool debugged;          // CS_DEBUGGED выставлен: JIT доступен
    bool debuggerAttached;  // отладчик (StikDebug) всё ещё подключён
    bool canMapRX;          // можно сделать RW->RX без зеркалирования (до TXM)
} AnvilJITStatus;

AnvilJITStatus anvil_jit_status(void);

// Есть ли на устройстве Trusted Execution Monitor (iOS 26+ на новых чипах).
bool DeviceHasTXM(void);

// Проверяет, что в StikDebug назначен Universal JIT-скрипт, и передаёт ему расширение Anvil.
// 0 — готово, -1 — назначен старый скрипт или его нет. Вызывать только с подключённым отладчиком.
int anvil_jit26_handshake(const char *extensionScript);

// Запуск JVM в отдельном потоке с большим стеком. argv[0] — путь к JAVA_HOME.
int anvil_launch_jvm(int argc, const char *const *argv, const char *logPath);

// Повторный вход libjli через main(): -1, если JVM ещё не запускалась.
int anvil_jli_reentry(int argc, char **argv);

// Поверхность рендера (CAMetalLayer) и её размер в пикселях.
void anvil_set_surface(void *layer, int width, int height);

// Ввод в семантике GLFW.
void anvil_send_key(int key, int scancode, int action, int mods);
void anvil_send_char(uint32_t codepoint, int mods);
void anvil_send_mouse_button(int button, int action, int mods);
void anvil_send_cursor_pos(double x, double y);
void anvil_send_cursor_delta(double dx, double dy);
void anvil_send_scroll(double dx, double dy);
bool anvil_is_grabbed(void);
void anvil_set_grab_callback(void (*cb)(bool grabbed));
