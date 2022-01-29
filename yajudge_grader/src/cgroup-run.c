/*
 * Helper program to run arbitary command in a process
 * that preliminary added to cgroup if provided
 */

#include <limits.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

static const char CgroupPathEnv[] = "YAJUDGE_CGROUP_PATH";

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
    char *new_argv[256] = {};
    memcpy(new_argv, argv+1, (argc-1) * sizeof(char*));
    execvp(new_argv[0], new_argv);
    fprintf(stderr, "Can't launch %s\n", new_argv[0]);
    abort();
}