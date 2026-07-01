#!/bin/bash
# Restore a specific pgBackRest backup set exactly, then promote PostgreSQL.
#
# This is useful when a full overwrite must return the database to the exact
# selected backup-set state. Unlike a normal restore, --type=immediate prevents
# replaying later WAL records that may still be available in the archive.
#
# Usage:
#   restore_set_immediate_promote.sh "<backup-set-label>"
set -euo pipefail

BACKUP_SET="${1:-}"
if [ -z "$BACKUP_SET" ]; then
  echo "Usage: $0 '<backup-set-label>'" >&2
  exit 2
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/lib_backup.sh"

DATE_STR="$(date +'%Y%m%d-%H%M%S')"
LOG_FILE="$LOG_DIR/${BACKUP_INSTANCE}-restore-set-immediate-promote-${DATE_STR}.log"
RESTORE_PROMOTE_USER="${RESTORE_PROMOTE_USER:-moqui}"
RESTORE_PROMOTE_DB="${RESTORE_PROMOTE_DB:-postgres}"
RESTORE_PROMOTE_WAIT_SECONDS="${RESTORE_PROMOTE_WAIT_SECONDS:-30}"

query_recovery_state() {
  docker_compose exec -T "$POSTGRES_SERVICE" \
    psql -U "$RESTORE_PROMOTE_USER" -d "$RESTORE_PROMOTE_DB" -tAc "select pg_is_in_recovery()" 2>/dev/null \
    | tr -d '[:space:]'
}

{
  echo "DANGER: immediate backup-set restore requested for ${BACKUP_INSTANCE} on $(hostname)"
  echo "Backup set: $BACKUP_SET"
  echo "This script stops containers, empties PGDATA, restores the selected pgBackRest backup set with --type=immediate, then promotes PostgreSQL."
  echo "Later WAL records are intentionally not replayed."
  read -r -p "Type RESTORE to continue: " CONFIRM
  if [ "$CONFIRM" != "RESTORE" ]; then
    echo "Restore aborted"
    exit 1
  fi

  if [ -n "${APP_SERVICE:-}" ]; then
    docker_compose stop "$APP_SERVICE" || true
  fi

  docker_compose stop "$POSTGRES_SERVICE"
  prepare_empty_pgdata_for_restore
  docker_compose run --rm "$POSTGRES_SERVICE" \
    pgbackrest --stanza="$PGBACKREST_STANZA" --set="$BACKUP_SET" --type=immediate restore
  docker_compose start "$POSTGRES_SERVICE"

  sleep 10
  docker_compose exec -T "$POSTGRES_SERVICE" pg_isready || true

  RECOVERY_STATE="$(query_recovery_state || true)"
  if [ "$RECOVERY_STATE" = "t" ]; then
    echo "Database is in recovery after immediate restore; promoting to primary."
    docker_compose exec -T "$POSTGRES_SERVICE" \
      psql -U "$RESTORE_PROMOTE_USER" -d "$RESTORE_PROMOTE_DB" \
      -c "select pg_promote(wait => true, wait_seconds => ${RESTORE_PROMOTE_WAIT_SECONDS});"
  elif [ "$RECOVERY_STATE" = "f" ]; then
    echo "Database is already primary; promotion is not required."
  else
    echo "ERROR: unable to determine recovery state using user=${RESTORE_PROMOTE_USER} db=${RESTORE_PROMOTE_DB}" >&2
    exit 1
  fi

  FINAL_RECOVERY_STATE="$(query_recovery_state || true)"
  if [ "$FINAL_RECOVERY_STATE" != "f" ]; then
    echo "ERROR: database is still in recovery after promotion attempt: ${FINAL_RECOVERY_STATE:-unknown}" >&2
    exit 1
  fi

  echo "Database promoted and writable."
  docker_compose exec -T "$POSTGRES_SERVICE" pg_isready || true

  if [ -n "${APP_SERVICE:-}" ]; then
    docker_compose start "$APP_SERVICE" || true
  fi

  notify "RESTORE SET IMMEDIATE PROMOTE COMPLETED" "Immediate backup-set restore and promotion completed for ${BACKUP_INSTANCE} on $(hostname). Set: ${BACKUP_SET}. Log: ${LOG_FILE}" || true
} > >(tee -a "$LOG_FILE") 2> >(tee -a "$LOG_FILE" >&2)
