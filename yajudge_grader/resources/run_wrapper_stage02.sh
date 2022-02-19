#!/usr/bin/env bash
# shellcheck disable=SC2068

YAJUDGE_SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &> /dev/null && pwd)
export YAJUDGE_SCRIPT_STAGE=02

# Stage 2: mount overlay file system then run next stage and umount after done

# mount new root filesystem
if [ ! -d "$YAJUDGE_OVERLAY_WORKDIR" ]
then
  mkdir -p "$YAJUDGE_OVERLAY_WORKDIR"
fi
if [ ! -d "$YAJUDGE_OVERLAY_MERGEDIR" ]
then
  mkdir -p "$YAJUDGE_OVERLAY_MERGEDIR"
fi
mount -t overlay overlay \
  -o lowerdir="$YAJUDGE_OVERLAY_LOWERDIR",upperdir="$YAJUDGE_OVERLAY_UPPERDIR",workdir="$YAJUDGE_OVERLAY_WORKDIR"\
  "$YAJUDGE_OVERLAY_MERGEDIR"
if [ ! $? ]
then
  echo "cant mount $YAJUDGE_OVERLAY_MERGEDIR"
  exit 1
fi

# create new clean cgroup and dedicated subgroup for solution itself
echo "+memory +pids" > "$YAJUDGE_CGROUP_PATH/cgroup.subtree_control"
mkdir -p "$YAJUDGE_CGROUP_PATH/$YAJUDGE_CGROUP_SUBDIR"

# setup cgroup-configurable limits
if [ -n "$YAJUDGE_PROC_COUNT_LIMIT" ]
then
  echo "$YAJUDGE_PROC_COUNT_LIMIT" > "$YAJUDGE_CGROUP_PATH/$YAJUDGE_CGROUP_SUBDIR/pids.max"
fi
if [ -n "$YAJUDGE_PROC_MEMORY_LIMIT" ]; then echo "$YAJUDGE_PROC_MEMORY_LIMIT" > "$YAJUDGE_CGROUP_PATH/$YAJUDGE_CGROUP_SUBDIR/memory.max"; fi

# unshare IPC namespace due it will be in use by timeout command on next stage
if [ -n "$YAJUDGE_DEBUG" ]; then echo $YAJUDGE_SCRIPT_STAGE; fi
unshare -i bash "$YAJUDGE_SCRIPT_DIR/run_wrapper_stage03.sh" $@
EXIT_STATUS=$?

umount -l "$YAJUDGE_OVERLAY_MERGEDIR"
#rmdir "$YAJUDGE_CGROUP_PATH/$YAJUDGE_CGROUP_SUBDIR"
exit $EXIT_STATUS
