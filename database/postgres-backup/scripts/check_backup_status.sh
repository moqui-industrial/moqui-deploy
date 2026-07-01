#!/bin/bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/lib_backup.sh"

assert_not_disabled

if [ "${ENABLE_NAS_SYNC:-true}" = "true" ]; then
  if ! check_nas_mount; then
    fail_and_notify "NAS MOUNT FAILED" "NAS mount point is not available: ${NAS_MOUNT_POINT}"
  fi
else
  echo "NAS synchronization check skipped because ENABLE_NAS_SYNC=false"
fi

compose_exec_postgres pgbackrest --stanza="$PGBACKREST_STANZA" check
compose_exec_postgres pgbackrest --stanza="$PGBACKREST_STANZA" info

echo "Backup status OK for ${BACKUP_INSTANCE}"
