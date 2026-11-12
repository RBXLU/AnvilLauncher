#include <unistd.h>
#include <sys/mman.h>
#include "anvil_native.h"

#define CS_OPS_STATUS 0
#define CS_DEBUGGED 0x10000000
int csops(pid_t pid, unsigned int ops, void *useraddr, size_t usersize);

AnvilJITStatus anvil_jit_status(void) {
    AnvilJITStatus s = {0};
    uint32_t flags = 0;
    csops(getpid(), CS_OPS_STATUS, &flags, sizeof(flags));
    s.debugged = (flags & CS_DEBUGGED) != 0;
    // Пока процесс под отладчиком, его родитель — debugserver, а не launchd.
    s.debuggerAttached = getppid() != 1;
    if (s.debugged) {
        size_t page = (size_t)getpagesize();
        void *p = mmap(NULL, page, PROT_READ | PROT_WRITE, MAP_ANON | MAP_PRIVATE, -1, 0);
        if (p != MAP_FAILED) {
            s.canMapRX = mprotect(p, page, PROT_READ | PROT_EXEC) == 0;
            munmap(p, page);
        }
    }
    return s;
}

// ---------- iOS 26+: TXM и протокол скрипта Universal JIT в StikDebug ----------

#include <CoreFoundation/CoreFoundation.h>
#include <dirent.h>
#include <limits.h>
#include <dlfcn.h>
#include <stdio.h>
#include <string.h>

static bool detect_txm(void) {
    DIR *dir = opendir("/private/preboot");
    if (dir) {
        // Прошивка монитора лежит в /private/preboot/<96 символов хеша>/usr/standalone/firmware/FUD/.
        char path[PATH_MAX] = "";
        struct dirent *entry;
        while ((entry = readdir(dir))) {
            if (strlen(entry->d_name) == 96) {
                snprintf(path, sizeof(path),
                         "/private/preboot/%s/usr/standalone/firmware/FUD/Ap,TrustedExecutionMonitor.img4", entry->d_name);
                break;
            }
        }
        closedir(dir);
        return path[0] && access(path, F_OK) == 0;
    }
    // Новые iOS закрыли preboot: решаем по чипу.
    int64_t (*answer)(CFStringRef) = dlsym(RTLD_DEFAULT, "MGGetSInt64Answer");
    int64_t chip = answer ? answer(CFSTR("ChipID")) : 0;
    switch (chip) {
        case 0x8020: case 0x8027: return false;                  // A12, A12X/Z
        case 0x8030: case 0x8101: case 0x8103:                   // A13, A14, M1
            if (__builtin_available(iOS 27.0, *)) return true;
            return false;
        default:
            if (__builtin_available(iOS 19.0, *)) return true;
            return false;
    }
}

// Рантайм Java сам ищет эту функцию через dlsym, чтобы выбрать способ выделения JIT-памяти.
__attribute__((visibility("default")))
bool DeviceHasTXM(void) {
    static int cached = -1;
    if (cached < 0) cached = detect_txm();
    return cached;
}

#if defined(__arm64__)
// Вызовы скрипта: brk останавливает процесс, StikDebug выполняет команду и продолжает его.
__attribute__((noinline, optnone, naked)) static uint64_t jit26_legacy_brk(size_t len) {
    __asm__("brk #0x69\n ret");
}
__attribute__((noinline, optnone, naked)) static void jit26_send_script(const char *script, size_t len) {
    __asm__("mov x16, #2\n brk #0xf00d\n ret");
}
__attribute__((noinline, optnone, naked)) static void jit26_detach_after_first_br(bool value) {
    __asm__("mov x16, #3\n brk #0xf00d\n ret");
}
#endif

int anvil_jit26_handshake(const char *extensionScript) {
#if defined(__arm64__)
    // Universal-скрипт отвечает на старую команду 0x69 кодом E0000069 (в регистре 0x690000E0).
    uint64_t reply = jit26_legacy_brk((size_t)getpagesize());
    if ((uint32_t)reply != 0x690000E0) return -1;
    jit26_send_script(extensionScript, strlen(extensionScript));
    jit26_detach_after_first_br(true);
    return 0;
#else
    return -1;
#endif
}
