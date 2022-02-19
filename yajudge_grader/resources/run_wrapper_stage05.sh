#!/usr/bin/env bash
# shellcheck disable=SC2068

export YAJUDGE_SCRIPT_STAGE=05

# Stage 5 : setup limits, than chroot and run program itself

# setup setrlimit-configurable limits
if [ -n "$YAJUDGE_CPU_TIME_LIMIT" ]; then ulimit -t "$YAJUDGE_CPU_TIME_LIMIT"; fi
if [ -n "$YAJUDGE_CPU_STACK_SIZE_LIMIT" ]; then ulimit -s "$YAJUDGE_CPU_STACK_SIZE_LIMIT"; fi
if [ -n "$YAJUDGE_CPU_FD_COUNT_LIMIT" ]; then ulimit -n "$YAJUDGE_CPU_FD_COUNT_LIMIT"; fi

# make limited processes count to prevent fork bombs in case if cgroup will fail
ulimit -u 5000

# move this process to control group
echo "$$" > "$YAJUDGE_CGROUP_PATH/$YAJUDGE_CGROUP_SUBDIR/cgroup.procs"

LOCAL_YAJUDGE_ROOT_DIR="$YAJUDGE_ROOT_DIR"
LOCAL_YAJUDGE_WORK_DIR="$YAJUDGE_WORK_DIR"

# unset all environment variables
for e in $(env)
do
  env_name=$(echo "$e" | cut -d '=' -f 1)
  if [[ ! "$env_name" =~ ^(PATH|TERM|UID)$ ]]; then
    unset "$env_name"
  fi
done

export PATH="/bin:/usr/bin:/usr/local/bin"
export HOME="/build"

exec unshare --mount-proc \
  --root="$LOCAL_YAJUDGE_ROOT_DIR" \
  --wd="$LOCAL_YAJUDGE_WORK_DIR" \
  $@
