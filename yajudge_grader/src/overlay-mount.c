/*
 * Helper program to allow mount/umount overlayfs from single setcapped binary
 * not requiring sudo/su.
 */

#include <errno.h>
#include <limits.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

#include <sys/capability.h>
#include <sys/mount.h>

static const char LowerDirEnv[] = "YAJUDGE_OVERLAY_LOWERDIR";
static const char UpperDirEnv[] = "YAJUDGE_OVERLAY_UPPERDIR";
static const char WorkDirEnv[] = "YAJUDGE_OVERLAY_WORKDIR";
static const char MergeDirEnv[] = "YAJUDGE_OVERLAY_MERGEDIR";

static char *getenv_or_fail(const char *env) {
    char *value = getenv(env);
    if (NULL == value) {
        fprintf(stderr, "Value %s not set\n", env);
        exit(1);
    }
    return value;
}

static void ensure_cap_sys_admin() {
    cap_t cap = cap_get_proc();
    static const cap_value_t cap_list[] = {CAP_SYS_ADMIN};
    cap_set_flag(cap, CAP_EFFECTIVE, 1, cap_list, CAP_SET);
    if (-1 == cap_set_proc(cap)) {
        fprintf(stderr,
                "Can't set CAP_SYS_ADMIN\n"
                "Ensure you have executed 'sudo setcap cap_sys_admin+p' on this binary\n");
        exit(1);
    }
    cap_free(cap);
}

static void process_mount() {
    const char *lower = getenv_or_fail(LowerDirEnv);
    const char *upper = getenv_or_fail(UpperDirEnv);
    const char *work = getenv_or_fail(WorkDirEnv);
    const char *merge = getenv_or_fail(MergeDirEnv);

    char merged_tmp[PATH_MAX];
    char merged_proc[PATH_MAX];
    char merged_devshm[PATH_MAX];

    strncpy(merged_tmp, merge, PATH_MAX);
    strncpy(merged_devshm, merge, PATH_MAX);
    strncpy(merged_proc, merge, PATH_MAX);
    strcat(merged_tmp, "/tmp");
    strcat(merged_devshm, "/dev/shm");
    strcat(merged_proc, "/proc");

    char options[65536] = {};
    snprintf(options, sizeof(options),
             "lowerdir=%s,upperdir=%s,workdir=%s",
             lower, upper, work);
    int status = mount("overlay",merge,"overlay",0,options);
    if (0 != status) {
        perror("Mount overlay failed");
        exit(1);
    }

    // mount special filesystems in new root: /tmp, /dev/shm and /proc
    status = mount("tmpfs", merged_tmp, "tmpfs", 0, "");
    if (0 != status) {
        perror("Mount /tmp in overlay failed");
        exit(1);
    }
    status = mount("tmpfs", merged_devshm, "tmpfs", 0, "");
    if (0 != status) {
        perror("Mount /dev/shm in overlay failed");
        exit(1);
    }
    status = mount("procfs", merged_proc, "proc", 0, "");
    if (0 != status) {
        perror("Mount /proc in overlay failed");
        exit(1);
    }
}

static void process_unmount() {
    const char *merge = getenv_or_fail(MergeDirEnv);

    char merged_tmp[PATH_MAX];
    char merged_proc[PATH_MAX];
    char merged_devshm[PATH_MAX];

    strncpy(merged_tmp, merge, PATH_MAX);
    strncpy(merged_devshm, merge, PATH_MAX);
    strncpy(merged_proc, merge, PATH_MAX);
    strcat(merged_tmp, "/tmp");
    strcat(merged_devshm, "/dev/shm");
    strcat(merged_proc, "/proc");

    int status = 0;
    status = umount2(merged_tmp, MNT_FORCE);
    if (0 != status) {
        perror("Umount /tmp in overlay failed");
    }
    status = umount2(merged_devshm, MNT_FORCE);
    if (0 != status) {
        perror("Umount /dev/shm in overlay failed");
    }
    status = umount2(merged_proc, MNT_FORCE);
    if (0 != status) {
        perror("Umount /proc in overlay failed");
    }
    status = umount2(merge, MNT_FORCE);
    if (0 != status) {
        perror("Umount overlay failed");
        exit(1);
    }
}

int main(int argc, char* argv[]) {
    ensure_cap_sys_admin();
    if (argc > 1 && 0==strncmp(argv[1], "-u", 2)) {
        process_unmount();
    } else {
        process_mount();
    }
    return 0;
}
