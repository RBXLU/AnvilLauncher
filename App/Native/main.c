// Точка входа на C, а не SwiftUI @main: libjli вызывает main() повторно (см. jvm.c).
#include "anvil_native.h"

int anvil_swift_main(void);

__attribute__((visibility("default")))
int main(int argc, char *argv[]) {
    int rc = anvil_jli_reentry(argc, argv);
    return rc == -1 ? anvil_swift_main() : rc;
}
