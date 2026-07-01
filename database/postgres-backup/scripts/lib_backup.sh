#!/bin/bash
# Shared library for Moqui PostgreSQL production backup scripts.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SUPPORT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
DOCKER_ROOT="$(cd "$SUPPORT_ROOT/.." && pwd)"
CONFIG_FILE="${CONFIG_FILE:-$SUPPORT_ROOT/config/backup.moqui-prod.env}"

if [ ! -f "$CONFIG_FILE" ]; then
  echo "ERROR: missing config file: $CONFIG_FILE" >&2
  exit 2
fi

# shellcheck disable=SC1090
source "$CONFIG_FILE"

require_command() {
  local cmd="$1"
  if ! command -v "$cmd" >/dev/null 2>&1; then
    echo "ERROR: required command not found: $cmd" >&2
    exit 127
  fi
}

resolve_config_relative_path() {
  local path_value="$1"
  if [[ "$path_value" = /* ]]; then
    printf '%s\n' "$path_value"
  else
    local config_dir
    config_dir="$(cd "$(dirname "$CONFIG_FILE")" && pwd)"
    (cd "$config_dir" && realpath -m "$path_value")
  fi
}

COMPOSE_FILE="$(resolve_config_relative_path "$COMPOSE_FILE")"
LOCAL_REPO_PATH="$(resolve_config_relative_path "$LOCAL_REPO_PATH")"
LOG_DIR="$(resolve_config_relative_path "$LOG_DIR")"
STATE_DIR="$(resolve_config_relative_path "$STATE_DIR")"
LOCK_DIR="$(resolve_config_relative_path "$LOCK_DIR")"
POSTGRES_CONTAINER_UID="${POSTGRES_CONTAINER_UID:-999}"
POSTGRES_CONTAINER_GID="${POSTGRES_CONTAINER_GID:-999}"
CONTAINER_PGDATA_PATH="${CONTAINER_PGDATA_PATH:-/var/lib/postgresql/18/docker}"

mkdir -p "$LOG_DIR" "$STATE_DIR" "$LOCK_DIR"

DISABLE_FILE="$STATE_DIR/BACKUP_DISABLED"

require_command realpath
require_command "$DOCKER_COMPOSE_BIN"

if ! "$DOCKER_COMPOSE_BIN" info >/dev/null 2>&1; then
  echo "ERROR: docker is not accessible for the current user" >&2
  echo "Run the script from a shell that can access the Docker daemon socket." >&2
  exit 126
fi

if [ "${ENABLE_NAS_SYNC:-true}" = "true" ]; then
  require_command "$RSYNC_BIN"
fi

log_message() {
  echo "$(date '+%Y-%m-%d %H:%M:%S') - $*"
}

docker_compose() {
  "$DOCKER_COMPOSE_BIN" compose -f "$COMPOSE_FILE" -p "$COMPOSE_PROJECT" "$@"
}

compose_exec_postgres() {
  docker_compose exec -T "$POSTGRES_SERVICE" "$@"
}

normalize_local_repo_permissions() {
  if [ ! -d "$LOCAL_REPO_PATH" ]; then
    return 0
  fi

  "$DOCKER_COMPOSE_BIN" run --rm -u root \
    -v "$LOCAL_REPO_PATH:/repo" \
    alpine:3.22 \
    sh -lc '
      find /repo -type d -exec chmod 755 {} \; &&
      find /repo -type f -exec chmod 644 {} \;
    '
}

prepare_empty_pgdata_for_restore() {
  log_message "Preparing empty PGDATA for restore: ${CONTAINER_PGDATA_PATH}"
  docker_compose run --rm -u root "$POSTGRES_SERVICE" sh -lc "
    mkdir -p '$CONTAINER_PGDATA_PATH' &&
    find '$CONTAINER_PGDATA_PATH' -mindepth 1 -maxdepth 1 -exec rm -rf {} + &&
    chown -R '$POSTGRES_CONTAINER_UID:$POSTGRES_CONTAINER_GID' '$CONTAINER_PGDATA_PATH' &&
    chmod 700 '$CONTAINER_PGDATA_PATH'
  "
}

notify() {
  local subject="$1"
  local body="$2"

  case "${NOTIFY_METHOD:-mail}" in
    mail)
      if [ -z "${NOTIFY_TO:-}" ]; then
        log_message "ERROR: NOTIFY_TO is empty; cannot send mail notification"
        return 1
      fi
      if [ -x "${MAIL_BIN:-/usr/bin/mail}" ]; then
        printf '%s\n' "$body" | "${MAIL_BIN:-/usr/bin/mail}" -s "${NOTIFY_SUBJECT_PREFIX:-[Moqui Backup]} ${subject}" "$NOTIFY_TO"
        return $?
      fi
      if command -v mail >/dev/null 2>&1; then
        printf '%s\n' "$body" | mail -s "${NOTIFY_SUBJECT_PREFIX:-[Moqui Backup]} ${subject}" "$NOTIFY_TO"
        return $?
      fi
      log_message "ERROR: mail command not found. Install mailutils or configure MAIL_BIN."
      return 1
      ;;
    webhook)
      if [ -z "${NOTIFY_WEBHOOK_URL:-}" ]; then
        log_message "ERROR: NOTIFY_WEBHOOK_URL is empty"
        return 1
      fi
      python3 - <<PY | curl -fsS -X POST "$NOTIFY_WEBHOOK_URL" -H 'Content-Type: application/json' -d @-
import json, socket, datetime
print(json.dumps({
  "subject": "${NOTIFY_SUBJECT_PREFIX:-[Moqui Backup]} ${subject}",
  "body": ${body@Q},
  "host": socket.gethostname(),
  "timestamp": datetime.datetime.now(datetime.timezone.utc).isoformat()
}))
PY
      ;;
    none|"")
      log_message "Notification disabled: $subject - $body"
      ;;
    *)
      log_message "ERROR: unknown NOTIFY_METHOD=${NOTIFY_METHOD}"
      return 1
      ;;
  esac
}

fail_and_notify() {
  local subject="$1"
  local body="$2"
  log_message "ERROR: $subject"
  log_message "$body"
  notify "$subject" "$body" || log_message "ERROR: notification delivery failed"
  exit 1
}

assert_not_disabled() {
  if [ -f "$DISABLE_FILE" ]; then
    local body
    body="Backups are disabled for ${BACKUP_INSTANCE} on host $(hostname).

Disable file:
${DISABLE_FILE}

Reason:
$(cat "$DISABLE_FILE" 2>/dev/null || true)

Manual intervention is required. After fixing the root cause, run:
  ${SCRIPT_DIR}/enable_backups.sh"
    notify "BACKUP ABORTED - DISABLED" "$body" || true
    echo "$body" >&2
    exit 3
  fi
}

create_disable_file() {
  local reason="$1"
  mkdir -p "$STATE_DIR"
  {
    echo "timestamp=$(date --iso-8601=seconds)"
    echo "host=$(hostname)"
    echo "instance=${BACKUP_INSTANCE}"
    echo "reason=${reason}"
  } > "$DISABLE_FILE"
}

check_nas_mount() {
  log_message "Checking NAS mount point: $NAS_MOUNT_POINT"
  # Trigger systemd automount if configured.
  ls "$NAS_MOUNT_POINT" >/dev/null 2>&1 || true
  sleep 2

  if ! mountpoint -q "$NAS_MOUNT_POINT"; then
    return 1
  fi

  mkdir -p "$NAS_BACKUP_ROOT/$NAS_INSTANCE_DIR"
  return 0
}
