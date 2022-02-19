#!/usr/bin/env bash
# shellcheck disable=SC2068

YAJUDGE_SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &> /dev/null && pwd)
export YAJUDGE_SCRIPT_STAGE=01

# Stage 1: unshare root and mount namespaces to allow mount overlay file system
if [ -n "$YAJUDGE_DEBUG" ]; then echo $YAJUDGE_SCRIPT_STAGE; fi
exec unshare -rm bash "$YAJUDGE_SCRIPT_DIR/run_wrapper_stage02.sh" $@
