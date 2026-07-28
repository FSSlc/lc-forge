#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include "sodium.h"

int main() {
    const char *pkg_version = getenv("PKG_VERSION");
    if (pkg_version == NULL) {
        fprintf(stderr, "$PKG_VERSION env not set\n");
        return 1;
    }

    printf("SODIUM_VERSION_STRING=%s, PKG_VERSION=%s\n", SODIUM_VERSION_STRING, pkg_version);

    if (strncmp(SODIUM_VERSION_STRING, pkg_version, 20) != 0) {
        fprintf(stderr, "version mismatch: SODIUM_VERSION_STRING=%s, PKG_VERSION=%s\n",
                SODIUM_VERSION_STRING, pkg_version);
        return 1;
    }

    return 0;
}
