#!/bin/bash
# Mirror the local pgBackRest repository to NAS with retry and fail-stop behavior.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/lib_backup.sh"

assert_not_disabled

if [ "${ENABLE_NAS_SYNC:-true}" != "true" ]; then
  log_message "NAS synchronization disabled by configuration; skipping mirror step"
  exit 0
fi

DEST_DIR="$NAS_BACKUP_ROOT/$NAS_INSTANCE_DIR/pgbackrest"
PARTIAL_DIR="$NAS_BACKUP_ROOT/$NAS_INSTANCE_DIR/.rsync-partial"

if [ ! -d "$LOCAL_REPO_PATH" ]; then
  fail_and_notify "NAS COPY FAILED" "Local repository path does not exist or is not accessible: ${LOCAL_REPO_PATH}"
fi

if ! check_nas_mount; then
  reason="NAS mount is not available at ${NAS_MOUNT_POINT}. Copy aborted."
  if [ "${DISABLE_BACKUP_ON_NAS_FAILURE:-true}" = "true" ]; then
    create_disable_file "$reason"
  fi
  fail_and_notify "NAS COPY FAILED - BACKUPS DISABLED" "$reason"
fi

mkdir -p "$DEST_DIR" "$PARTIAL_DIR"

attempt=1
max_attempts="${NAS_COPY_RETRIES:-3}"
sleep_seconds="${NAS_COPY_RETRY_SLEEP_SECONDS:-60}"

while [ "$attempt" -le "$max_attempts" ]; do
  log_message "NAS copy attempt ${attempt}/${max_attempts}: ${LOCAL_REPO_PATH}/ -> ${DEST_DIR}/"

  if "$RSYNC_BIN" -aH --numeric-ids --delete --partial --partial-dir="$PARTIAL_DIR" \
      "$LOCAL_REPO_PATH"/ "$DEST_DIR"/; then
    log_message "NAS copy completed successfully"
    exit 0
  fi

  log_message "NAS copy attempt ${attempt} failed"
  attempt=$((attempt + 1))

  if [ "$attempt" -le "$max_attempts" ]; then
    sleep "$sleep_seconds"
  fi
done

reason="NAS copy failed after ${max_attempts} attempts. Local repository: ${LOCAL_REPO_PATH}. Destination: ${DEST_DIR}."
if [ "${DISABLE_BACKUP_ON_NAS_FAILURE:-true}" = "true" ]; then
  create_disable_file "$reason"
fi

fail_and_notify "NAS COPY FAILED - BACKUPS DISABLED" "$reason

Future backups will abort until the disable file is removed after manual verification:
  ${DISABLE_FILE}

Use:
  ${SCRIPT_DIR}/enable_backups.sh
only after the NAS/copy issue is fixed."
