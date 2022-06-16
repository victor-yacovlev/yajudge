#!/usr/bin/env bash
# shellcheck disable=SC2068

YAJUDGE_SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &> /dev/null && pwd)
export YAJUDGE_SCRIPT_STAGE=05

# Stage 5 : run co-process in the same unshare than setup limits, chroot and run program itself
if [ -n "$YAJUDGE_COPROCESS" ]
then
  if [ ! -d "$YAJUDGE_ROOT_DIR/$YAJUDGE_WORK_DIR" ]; then mkdir -p "$YAJUDGE_ROOT_DIR/$YAJUDGE_WORK_DIR"; fi
  # shellcheck disable=SC2086
  export YAJUDGE_MAIN_PROGRAM_PID="$$"
  bash "$YAJUDGE_SCRIPT_DIR/run_wrapper_stage05_coprocess.sh" \
    1>"$YAJUDGE_ROOT_DIR/$YAJUDGE_WORK_DIR/coprocess.log" \
    2>&1 \
    $YAJUDGE_COPROCESS \
    &
fi

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
IFS=$'\n'
for e in $(env)
do
  env_name=$(echo "$e" | cut -d '=' -f 1)
  if [[ ! "$env_name" =~ ^(PATH|TERM|UID|LANG)$ ]]; then
    unset "$env_name"
  fi
done

export PATH="/bin:/usr/bin:/usr/local/bin"
export HOME="/build"
exec unshare --mount-proc \
  --root="$LOCAL_YAJUDGE_ROOT_DIR" \
  --wd="$LOCAL_YAJUDGE_WORK_DIR" \
  $@
