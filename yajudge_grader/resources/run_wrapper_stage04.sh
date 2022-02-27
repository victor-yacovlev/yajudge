#!/usr/bin/env bash
# shellcheck disable=SC2068

YAJUDGE_SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &> /dev/null && pwd)
export YAJUDGE_SCRIPT_STAGE=04

# Stage 4: if network unshared, setup new localhost interface

if [ -z "$YAJUDGE_ALLOW_NETWORK" ]
then
  ip link set dev lo up
fi

if [ -n "$YAJUDGE_DEBUG" ]; then echo $YAJUDGE_SCRIPT_STAGE; fi
exec unshare -pf bash "$YAJUDGE_SCRIPT_DIR/run_wrapper_stage05.sh" $@
