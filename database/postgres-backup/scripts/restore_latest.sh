#!/bin/bash
# Restore latest local pgBackRest backup.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/lib_backup.sh"

DATE_STR="$(date +'%Y%m%d-%H%M%S')"
LOG_FILE="$LOG_DIR/${BACKUP_INSTANCE}-restore-latest-${DATE_STR}.log"

{
  echo "DANGER: latest restore requested for ${BACKUP_INSTANCE} on $(hostname)"
  echo "This script stops containers and restores PGDATA from pgBackRest."
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
  docker_compose run --rm "$POSTGRES_SERVICE" pgbackrest --stanza="$PGBACKREST_STANZA" restore
  docker_compose start "$POSTGRES_SERVICE"

  sleep 10
  docker_compose exec -T "$POSTGRES_SERVICE" pg_isready || true

  if [ -n "${APP_SERVICE:-}" ]; then
    docker_compose start "$APP_SERVICE" || true
  fi

  notify "RESTORE COMPLETED" "Latest restore completed for ${BACKUP_INSTANCE} on $(hostname). Log: ${LOG_FILE}" || true
} > >(tee -a "$LOG_FILE") 2> >(tee -a "$LOG_FILE" >&2)
