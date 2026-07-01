#!/bin/bash
# Restore/mirror the pgBackRest repository from NAS back to local storage.
# Use this when the VM/local repository has been rebuilt but the NAS mirror is available.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/lib_backup.sh"

SRC_DIR="$NAS_BACKUP_ROOT/$NAS_INSTANCE_DIR/pgbackrest"

if ! check_nas_mount; then
  fail_and_notify "NAS MOUNT FAILED" "NAS mount point is not available: ${NAS_MOUNT_POINT}"
fi

if [ ! -d "$SRC_DIR" ]; then
  fail_and_notify "NAS REPOSITORY MISSING" "NAS repository source does not exist: ${SRC_DIR}"
fi

mkdir -p "$LOCAL_REPO_PATH"
"$RSYNC_BIN" -aH --numeric-ids --delete "$SRC_DIR"/ "$LOCAL_REPO_PATH"/

echo "Repository copied from NAS to local path: $LOCAL_REPO_PATH"
