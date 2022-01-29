/*
 * For development use only! Tune up your systemd in production use.
 * The program must have SUID flag.
 * Moves PID to specific cgroup.
 */

#include <limits.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

int main(int argc, char *argv[]) {
    if (argc < 3) {
        fprintf(stderr, "No enought arguments\n");
        exit(1);
    }
    const char *cgroup_root = argv[1];
    const char *pid = argv[2];
    char file_name[PATH_MAX];
    strncpy(file_name, cgroup_root, sizeof(file_name));
    size_t path_len = strnlen(cgroup_root, PATH_MAX);
    strncat(file_name, "/cgroup.procs", PATH_MAX-path_len);
    FILE *procs_file = fopen(file_name, "a");
    if (!procs_file) {
        fprintf(stderr, "Cant open %s\n", file_name);
        exit(1);
    }
    fprintf(procs_file, "%s\n", pid);
    fclose(procs_file);
}