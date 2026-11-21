#include <dlfcn.h>
#include <fcntl.h>
#include <pthread.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <dispatch/dispatch.h>
#include <mach/mach.h>
#include <os/proc.h>
#include "anvil_native.h"

// ---------- Слежение за памятью: iOS молча убивает процесс, когда он превышает лимит ----------

static unsigned long long footprint_mb(void) {
    task_vm_info_data_t info;
    mach_msg_type_number_t count = TASK_VM_INFO_COUNT;
    if (task_info(mach_task_self(), TASK_VM_INFO, (task_info_t)&info, &count) != KERN_SUCCESS) return 0;
    return info.phys_footprint >> 20;
}

static void log_memory(const char *reason) {
    // os_proc_available_memory — сколько ещё можно занять до принудительного завершения.
    fprintf(stderr, "[Anvil] Память (%s): занято %llu МБ, до лимита iOS %llu МБ\n",
            reason, footprint_mb(), (unsigned long long)(os_proc_available_memory() >> 20));
}

static void start_memory_monitor(void) {
    static dispatch_source_t timer, pressure;
    dispatch_queue_t queue = dispatch_get_global_queue(QOS_CLASS_UTILITY, 0);
    timer = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, queue);
    dispatch_source_set_timer(timer, dispatch_time(DISPATCH_TIME_NOW, 0), 10 * NSEC_PER_SEC, NSEC_PER_SEC);
    dispatch_source_set_event_handler(timer, ^{ log_memory("каждые 10 с"); });
    dispatch_resume(timer);

    pressure = dispatch_source_create(DISPATCH_SOURCE_TYPE_MEMORYPRESSURE, 0,
                                      DISPATCH_MEMORYPRESSURE_WARN | DISPATCH_MEMORYPRESSURE_CRITICAL, queue);
    dispatch_source_set_event_handler(pressure, ^{
        unsigned long flags = dispatch_source_get_data(pressure);
        log_memory(flags & DISPATCH_MEMORYPRESSURE_CRITICAL ? "КРИТИЧЕСКАЯ нехватка" : "предупреждение iOS");
    });
    dispatch_resume(pressure);
}

typedef int JLI_Launch_t(int argc, char **argv, int jargc, const char **jargv,
                         int appclassc, const char **appclassv,
                         const char *fullversion, const char *dotversion,
                         const char *pname, const char *lname,
                         unsigned char javaargs, unsigned char cpwildcard,
                         unsigned char javaw, int ergo);

static int g_argc;
static char **g_argv;
static JLI_Launch_t *g_launch;

static int call_jli(int argc, char **argv) {
    return g_launch(argc, argv, 0, NULL, 0, NULL, "1.8.0-internal", "1.8",
                    "java", "openjdk", 0, 1, 0, 1);
}

__attribute__((visibility("default")))
int anvil_jli_reentry(int argc, char **argv) {
    // libjli на Apple-платформах находит main() приложения через dlsym и вызывает её
    // повторно в новом потоке. Возвращаем управление в JLI вместо второго запуска UI.
    return g_launch ? call_jli(argc, argv) : -1;
}

static void *jvm_thread(void *unused) {
    const char *home = getenv("JAVA_HOME");
    char path[1024];
    void *jli = NULL;
    const char *candidates[] = { "lib/libjli.dylib", "lib/jli/libjli.dylib", "jre/lib/jli/libjli.dylib" };
    for (int i = 0; i < 3 && !jli; i++) {
        snprintf(path, sizeof(path), "%s/%s", home, candidates[i]);
        jli = dlopen(path, RTLD_GLOBAL);
    }
    if (!jli) {
        fprintf(stderr, "[Anvil] libjli не найден: %s\n", dlerror());
        exit(1);
    }
    JLI_Launch_t *launch = (JLI_Launch_t *)dlsym(jli, "JLI_Launch");
    g_launch = launch;
    if (!launch) {
        fprintf(stderr, "[Anvil] JLI_Launch отсутствует\n");
        exit(1);
    }
    fprintf(stderr, "[Anvil] Запуск JVM, аргументов: %d\n", g_argc);
    // JVM сама вызовет exit() при закрытии игры.
    exit(call_jli(g_argc, g_argv));
}

int anvil_launch_jvm(int argc, const char *const *argv, const char *logPath) {
    g_argc = argc;
    g_argv = calloc((size_t)argc + 1, sizeof(char *));
    for (int i = 0; i < argc; i++) g_argv[i] = strdup(argv[i]);

    if (logPath) {
        int fd = open(logPath, O_WRONLY | O_CREAT | O_TRUNC, 0644);
        if (fd >= 0) {
            dup2(fd, STDOUT_FILENO);
            dup2(fd, STDERR_FILENO);
            close(fd);
            setvbuf(stdout, NULL, _IOLBF, 0);
            setvbuf(stderr, NULL, _IONBF, 0);
        }
    }

    pthread_attr_t attr;
    pthread_attr_init(&attr);
    pthread_attr_setstacksize(&attr, 8 << 20);
    pthread_t thread;
    start_memory_monitor();
    int rc = pthread_create(&thread, &attr, jvm_thread, NULL);
    pthread_attr_destroy(&attr);
    if (rc == 0) pthread_detach(thread);
    return rc;
}
