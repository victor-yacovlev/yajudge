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
mount -t tmpfs tmpfs "$YAJUDGE_OVERLAY_MERGEDIR/tmp"
if [ ! $? ]
then
  echo "cant mount $YAJUDGE_OVERLAY_MERGEDIR/tmp"
  exit 1
fi

if [ ! -d "$YAJUDGE_CGROUP_PATH" ]
then
  mkdir -p "$YAJUDGE_CGROUP_PATH"
    if [ ! $? ]
    then
      echo "cant create $YAJUDGE_CGROUP_PATH"
      exit 1
    fi
fi


# create new clean cgroup and dedicated subgroup for solution itself
if [ ! -d "$YAJUDGE_CGROUP_PATH/$YAJUDGE_CGROUP_SUBDIR" ]
then
  echo "+memory +pids" > "$YAJUDGE_CGROUP_PATH/cgroup.subtree_control"
  if [ ! $? ]
  then
    echo "cant add +memory +pids to $YAJUDGE_CGROUP_PATH/cgroup.subtree_control"
    exit 1
  fi
  mkdir -p "$YAJUDGE_CGROUP_PATH/$YAJUDGE_CGROUP_SUBDIR"
  if [ ! $? ]
  then
    echo "cant create $YAJUDGE_CGROUP_PATH/$YAJUDGE_CGROUP_SUBDIR"
    exit 1
  fi
fi

# setup cgroup-configurable limits
if [ -n "$YAJUDGE_PROC_COUNT_LIMIT" ]
then
  echo "$YAJUDGE_PROC_COUNT_LIMIT" > "$YAJUDGE_CGROUP_PATH/$YAJUDGE_CGROUP_SUBDIR/pids.max"
  if [ ! $? ]
  then
    echo "cant write procs limit to $YAJUDGE_CGROUP_PATH/$YAJUDGE_CGROUP_SUBDIR/pids.max"
    exit 1
  fi
fi
if [ -n "$YAJUDGE_PROC_MEMORY_LIMIT" ]
then
  echo "$YAJUDGE_PROC_MEMORY_LIMIT" > "$YAJUDGE_CGROUP_PATH/$YAJUDGE_CGROUP_SUBDIR/memory.max"
  if [ ! $? ]
  then
    echo "cant write memory limit to $YAJUDGE_CGROUP_PATH/$YAJUDGE_CGROUP_SUBDIR/memory.max"
    exit 1
  fi
fi

# unshare IPC namespace due it will be in use by timeout command on next stage
if [ -n "$YAJUDGE_DEBUG" ]; then echo $YAJUDGE_SCRIPT_STAGE; fi
unshare -i bash "$YAJUDGE_SCRIPT_DIR/run_wrapper_stage03.sh" $@
EXIT_STATUS=$?

umount -l "$YAJUDGE_OVERLAY_MERGEDIR/tmp" > /dev/null 2>&1
umount -l "$YAJUDGE_OVERLAY_MERGEDIR" > /dev/null 2>&1
#rmdir "$YAJUDGE_CGROUP_PATH/$YAJUDGE_CGROUP_SUBDIR"
exit $EXIT_STATUS
