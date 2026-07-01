#!/bin/bash
# Restore to a point in time using pgBackRest.
# Usage: restore_pitr.sh "2026-05-08 14:30:00"
set -euo pipefail
TARGET_TIME="${1:-}"
if [ -z "$TARGET_TIME" ]; then
  echo "Usage: $0 'YYYY-MM-DD HH:MM:SS'" >&2
  exit 2
fi
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/lib_backup.sh"

DATE_STR="$(date +'%Y%m%d-%H%M%S')"
LOG_FILE="$LOG_DIR/${BACKUP_INSTANCE}-restore-pitr-${DATE_STR}.log"

{
  echo "DANGER: PITR restore requested for ${BACKUP_INSTANCE} on $(hostname)"
  echo "Target time: $TARGET_TIME"
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
  docker_compose run --rm "$POSTGRES_SERVICE" pgbackrest --stanza="$PGBACKREST_STANZA" --type=time --target="$TARGET_TIME" restore
  docker_compose start "$POSTGRES_SERVICE"

  sleep 10
  docker_compose exec -T "$POSTGRES_SERVICE" pg_isready || true

  if [ -n "${APP_SERVICE:-}" ]; then
    docker_compose start "$APP_SERVICE" || true
  fi

  notify "PITR RESTORE COMPLETED" "PITR restore completed for ${BACKUP_INSTANCE} on $(hostname). Target: ${TARGET_TIME}. Log: ${LOG_FILE}" || true
} > >(tee -a "$LOG_FILE") 2> >(tee -a "$LOG_FILE" >&2)
