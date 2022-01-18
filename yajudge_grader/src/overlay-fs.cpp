extern "C" {
#if defined(__APPLE__)
#define GM_VERSION_MIN_REQUIRED 030000
#include <macFUSE.h>
#elif defined(__linux__)
#define FUSE_USE_VERSION 30
#include <fuse.h>
#else
#error Unsupported operating system
#endif
}

int main() {
    return 0;
}