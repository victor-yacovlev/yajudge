#!/usr/bin/env bash
# shellcheck disable=SC2068

YAJUDGE_SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &> /dev/null && pwd)
export YAJUDGE_SCRIPT_STAGE=03

# Stage 3: unshare network and hostname namespaces

if [ -n "$YAJUDGE_ALLOW_NETWORK" ]
then
  UNSHARE_FLAGS='-u'
else
  UNSHARE_FLAGS='-un'
fi

exec unshare "$UNSHARE_FLAGS" bash "$YAJUDGE_SCRIPT_DIR/run_wrapper_stage04.sh" $@
