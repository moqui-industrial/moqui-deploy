#!/bin/bash
# Restore a specific pgBackRest backup set label.
# Usage: restore_set.sh "<backup-set-label>"
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
LOG_FILE="$LOG_DIR/${BACKUP_INSTANCE}-restore-set-${DATE_STR}.log"

{
  echo "DANGER: backup-set restore requested for ${BACKUP_INSTANCE} on $(hostname)"
  echo "Backup set: $BACKUP_SET"
  echo "This script stops containers and restores PGDATA from the selected pgBackRest backup set."
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
  docker_compose run --rm "$POSTGRES_SERVICE" pgbackrest --stanza="$PGBACKREST_STANZA" --set="$BACKUP_SET" restore
  docker_compose start "$POSTGRES_SERVICE"

  sleep 10
  docker_compose exec -T "$POSTGRES_SERVICE" pg_isready || true

  if [ -n "${APP_SERVICE:-}" ]; then
    docker_compose start "$APP_SERVICE" || true
  fi

  notify "RESTORE SET COMPLETED" "Backup-set restore completed for ${BACKUP_INSTANCE} on $(hostname). Set: ${BACKUP_SET}. Log: ${LOG_FILE}" || true
} > >(tee -a "$LOG_FILE") 2> >(tee -a "$LOG_FILE" >&2)
