#!/bin/bash
# Execute one pgBackRest backup, expire old backup chains, then mirror repository to NAS.
# Usage: backup_pgbackrest.sh full|diff|incr

set -euo pipefail

BACKUP_TYPE="${1:-}"
if [[ ! "$BACKUP_TYPE" =~ ^(full|diff|incr)$ ]]; then
  echo "Usage: $0 full|diff|incr" >&2
  exit 2
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/lib_backup.sh"

assert_not_disabled

DATE_STR="$(date +'%Y%m%d-%H%M%S')"
LOG_FILE="$LOG_DIR/${BACKUP_INSTANCE}-${BACKUP_TYPE}-${DATE_STR}.log"
LOCK_FILE="$LOCK_DIR/postgres-backup-${BACKUP_INSTANCE}.lock"

{
  flock -n 9 || fail_and_notify "BACKUP SKIPPED - LOCKED" "Another backup is already running for ${BACKUP_INSTANCE}. Lock file: ${LOCK_FILE}"

  log_message "Starting pgBackRest backup"
  log_message "instance=${BACKUP_INSTANCE} stanza=${PGBACKREST_STANZA} type=${BACKUP_TYPE}"

  compose_exec_postgres pgbackrest --stanza="$PGBACKREST_STANZA" --type="$BACKUP_TYPE" backup
  compose_exec_postgres pgbackrest --stanza="$PGBACKREST_STANZA" expire
  compose_exec_postgres pgbackrest --stanza="$PGBACKREST_STANZA" info
  normalize_local_repo_permissions

  log_message "Local pgBackRest backup and expiration completed"

  "$SCRIPT_DIR/sync_backup_to_nas.sh"

  log_message "Backup and NAS synchronization completed"

} 9>"$LOCK_FILE" > >(tee -a "$LOG_FILE") 2> >(tee -a "$LOG_FILE" >&2) || {
  rc=$?
  body="Backup failed.

Instance: ${BACKUP_INSTANCE}
Stanza: ${PGBACKREST_STANZA}
Type: ${BACKUP_TYPE}
Host: $(hostname)
Date: $(date --iso-8601=seconds)
Log: ${LOG_FILE}
Exit code: ${rc}"
  notify "BACKUP FAILED" "$body" || true
  exit "$rc"
}
