#include <inttypes.h>
#include <stdbool.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include <semaphore.h>
#include <sys/types.h>
#include <sys/mman.h>

static const char ProcLimitEnv[] = "YAJUDGE_PROC_COUNT_LIMIT";

typedef struct limits {
    sem_t guard;

    uint64_t max_procs;

} limits_t;

static limits_t *Limits;


pid_t __real_fork();
pid_t __wrap_fork()
{
    sem_wait(&Limits->guard);
    if (Limits->max_procs <= 1) {
        sem_post(&Limits->guard);
        return -1;
    }
    else {
        Limits->max_procs --;
        sem_post(&Limits->guard);
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
    Limits = mmap(NULL, 4096, PROT_READ|PROT_WRITE, MAP_SHARED|MAP_ANONYMOUS, -1, 0);
    if (MAP_FAILED == Limits) {
        perror("Cant create shared limits context");
        abort();
    }
    if (-1 == sem_init(&Limits->guard, 1, 1)) {
        perror("Cant initialize guard in shared limits context");
        abort();
    }

    Limits->max_procs = read_limit_env(ProcLimitEnv);;
}

__attribute__((destructor)) static void finalize_limits()
{
    sem_destroy(&Limits->guard);
    munmap(Limits, 4096);
}
