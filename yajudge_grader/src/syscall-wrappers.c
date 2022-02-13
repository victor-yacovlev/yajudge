#include <inttypes.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include <sys/socket.h>
#include <sys/stat.h>
#include <sys/types.h>
#include <unistd.h>

static const char ProcLimitEnv[] = "YAJUDGE_PROC_COUNT_LIMIT";
static uint64_t MaxForksLimit = 100;

pid_t __real_fork();
pid_t __wrap_fork()
{
    if (0 == MaxForksLimit) {
        return -1;
    }
    else {
        MaxForksLimit --;
        return __real_fork();
    }
}

static uint64_t read_limit_env(const char* name)
{
    char* value = getenv(name);
    size_t token_len = 0;
    if (value) {
        token_len = strlen(value);
    }
    if (0 == token_len) {
        return UINT64_MAX;
    }
    uint64_t multiplier = 1;
    size_t last_idx = token_len - 1;
    char suffix = value[last_idx];
    if ('k' == suffix || 'K' == suffix)
        multiplier = 1024;
    else if ('m' == suffix || 'M' == suffix)
        multiplier = 1024 * 1024;
    else if ('g' == suffix || 'G' == suffix)
        multiplier = 1024 * 1024 * 1024;
    if (multiplier > 1)
        value[last_idx] = '\0';
    uint64_t base = strtoull(value, NULL, 10);
    uint64_t result = base * multiplier;
    return result;
}

__attribute__((constructor)) static void initialize_limits()
{
    uint64_t procsLimit = read_limit_env(ProcLimitEnv);
    if (UINT64_MAX != procsLimit) {
        MaxForksLimit = procsLimit;
    }
}
