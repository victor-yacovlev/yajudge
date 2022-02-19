#!/usr/bin/env bash
# shellcheck disable=SC2068

YAJUDGE_SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &> /dev/null && pwd)
export YAJUDGE_SCRIPT_STAGE=04

# Stage 4: while unshared everything but chroot, run supplementing services and than go next stage

# move this process to control group
#echo "$$" > "$YAJUDGE_CGROUP_PATH/cgroup.procs"

for service in $YAJUDGE_SERVICES
do
  unshare -U --kill-child=SIGTERM --mount-proc \
    --root="$YAJUDGE_ROOT_DIR" \
    --wd="$YAJUDGE_WORK_DIR" \
    "$service"
done

if [ -n "$YAJUDGE_DEBUG" ]; then echo $YAJUDGE_SCRIPT_STAGE; fi
exec unshare -pf bash "$YAJUDGE_SCRIPT_DIR/run_wrapper_stage05.sh" $@
