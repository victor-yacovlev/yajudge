/*
 * Helper program to run arbitary command in a process
 * that preliminary added to cgroup if provided
 */

#include <inttypes.h>
#include <limits.h>
#include <stdio.h>
#include <stdint.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

#include <sys/resource.h>
#include <sys/time.h>

static const char CgroupPathEnv[] = "YAJUDGE_CGROUP_PATH";
static const char StackSizeEnv[] = "YAJUDGE_STACK_SIZE_LIMIT_MB";
static const char CpuTimeEnv[] = "YAJUDGE_CPU_TIME_LIMIT_SEC";
static const char FdLimitsEnv[] = "YAJUDGE_FD_COUNT_LIMIT";

uint64_t get_env_value(const char *name) {
    char *s_value = getenv(name);
    if (!s_value) {
        return 0;
    }
    uint64_t result = strtoull(s_value, NULL, 10);
    return result;
}

void setup_limits() {
    struct rlimit lim = {};
    uint64_t stack_size = get_env_value(StackSizeEnv) * 1024 * 1024;
    uint64_t cpu_max = get_env_value(CpuTimeEnv);
    uint64_t files_max = get_env_value(FdLimitsEnv);

    // process count does not use rlimit,
    // but set it to some not very big value
    // to prevent fork bombs
    getrlimit(RLIMIT_NPROC, &lim);
    lim.rlim_cur = 2000;
    setrlimit(RLIMIT_NPROC, &lim);

    if (stack_size > 0) {
        getrlimit(RLIMIT_STACK, &lim);
        lim.rlim_cur = stack_size;
        lim.rlim_max = stack_size;
        if (-1 == setrlimit(RLIMIT_STACK, &lim)) {
            fprintf(stderr, "Cant set stack size to %"PRIu64"\n", stack_size);
            perror("setrlimit");
            exit(1);
        }
    }
    if (cpu_max > 0) {
        getrlimit(RLIMIT_CPU, &lim);
        lim.rlim_cur = cpu_max;
        lim.rlim_max = cpu_max;
        if (-1 == setrlimit(RLIMIT_CPU, &lim)) {
            fprintf(stderr, "Cant set cpu limit to %"PRIu64"\n", cpu_max);
            perror("setrlimit");
            exit(1);
        }
    }
    if (files_max > 0) {
        getrlimit(RLIMIT_NOFILE, &lim);
        lim.rlim_cur = files_max;
        lim.rlim_max = files_max;
        if (-1 == setrlimit(RLIMIT_NOFILE, &lim)) {
            fprintf(stderr, "Cant set fd count limit to %"PRIu64"\n", files_max);
            perror("setrlimit");
            exit(1);
        }
    }
}

void put_pid_into_cgroup(const char *cgroup_path) {
    char file_path[PATH_MAX];
    const char file_name[] = "/cgroup.procs";
    strncpy(file_path, cgroup_path, sizeof(file_path));
    size_t prefix_len = strnlen(cgroup_path, PATH_MAX);
    strncat(file_path, file_name, sizeof(file_path)-prefix_len);
    FILE* procs_file = fopen(file_path, "a");
    if (!procs_file) {
        fprintf(stderr, "Can't open %s to append pid\n", file_path);
        abort();
    }
    int pid = getpid();
    fprintf(procs_file, "%d\n", pid);
    fclose(procs_file);
}

int main(int argc, char *argv[]) {
    char *cgroupPath = getenv(CgroupPathEnv);
    if (cgroupPath) {
        put_pid_into_cgroup(cgroupPath);
    }
    if (argc < 2) {
        fprintf(stderr, "No command specified\n");
        abort();
    }
    setup_limits();
    char *new_argv[256] = {};
    memcpy(new_argv, argv+1, (argc-1) * sizeof(char*));
    execvp(new_argv[0], new_argv);
    fprintf(stderr, "Can't launch %s\n", new_argv[0]);
    abort();
}