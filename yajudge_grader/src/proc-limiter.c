#include <inttypes.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include <semaphore.h>
#include <sys/types.h>
#include <sys/mman.h>
#include <unistd.h>


static const char ProcLimitEnv[] = "YAJUDGE_PROC_COUNT_LIMIT";
static const char ProcStartDelayEnv[] = "YAJUDGE_PROC_START_DELAY";



typedef struct wrapper_context {
    sem_t guard;

    uint64_t max_procs;
    uint64_t start_delay;

} wrapper_context_t;

static wrapper_context_t *Context;

pid_t __real_fork();

pid_t __wrap_fork()
{
    sem_wait(&Context->guard);
    if (Context->max_procs <= 1) {
        sem_post(&Context->guard);
        return -1;
    }
    else {
        Context->max_procs --;
        sem_post(&Context->guard);
        if (Context->start_delay > 0) {
            usleep(1000 * Context->start_delay);
        }
        return __real_fork();
    }
}

static uint64_t read_limit_env(const char* name, uint64_t default_value)
{
    char* value = getenv(name);
    size_t token_len = 0;
    if (value) {
        token_len = strlen(value);
    }
    if (0 == token_len) {
        return default_value;
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
    Context = mmap(NULL, 4096, PROT_READ | PROT_WRITE, MAP_SHARED | MAP_ANONYMOUS, -1, 0);
    if (MAP_FAILED == Context) {
        perror("Cant create shared wrapper_context context");
        abort();
    }
    if (-1 == sem_init(&Context->guard, 1, 1)) {
        perror("Cant initialize guard in shared wrapper_context context");
        abort();
    }

    Context->max_procs = read_limit_env(ProcLimitEnv, 2000);
    Context->start_delay = read_limit_env(ProcStartDelayEnv, 0);
}

__attribute__((destructor)) static void finalize_limits()
{
    sem_destroy(&Context->guard);
    munmap(Context, 4096);
}
