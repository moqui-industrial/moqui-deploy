#!/bin/bash
# Prepare directories and copy configuration files for the selected VM type.
# Usage:
#   install_prepare_directories.sh moqui-prod
#   install_prepare_directories.sh moqui-log
set -euo pipefail
ROLE="${1:-}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SUPPORT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
DOCKER_ROOT="$(cd "$SUPPORT_ROOT/.." && pwd)"

if [ "$ROLE" = "moqui-prod" ]; then
  mkdir -p "$DOCKER_ROOT/db/moqui-prod/postgresql" "$DOCKER_ROOT/db/moqui-prod/config" "$DOCKER_ROOT/db/moqui-prod/pgbackrest/repo"
  cp "$DOCKER_ROOT/postgres-moqui/postgresql.conf" "$DOCKER_ROOT/db/moqui-prod/config/postgresql.conf"
  cp "$DOCKER_ROOT/postgres-backup/pgbackrest/pgbackrest-moqui-prod.conf" "$DOCKER_ROOT/db/moqui-prod/config/pgbackrest.conf"
  mkdir -p "$SUPPORT_ROOT/config"
  [ -f "$SUPPORT_ROOT/config/backup.moqui-prod.env" ] || cp "$SUPPORT_ROOT/config/backup.env.moqui-prod.example" "$SUPPORT_ROOT/config/backup.moqui-prod.env"
elif [ "$ROLE" = "moqui-log" ]; then
  mkdir -p "$DOCKER_ROOT/db/moqui-log/postgresql" "$DOCKER_ROOT/db/moqui-log/config" "$DOCKER_ROOT/db/moqui-log/pgbackrest/repo"
  cp "$DOCKER_ROOT/postgres-moqui-log/postgresql.conf" "$DOCKER_ROOT/db/moqui-log/config/postgresql.conf"
  cp "$DOCKER_ROOT/postgres-backup/pgbackrest/pgbackrest-moqui-log.conf" "$DOCKER_ROOT/db/moqui-log/config/pgbackrest.conf"
  mkdir -p "$SUPPORT_ROOT/config"
  [ -f "$SUPPORT_ROOT/config/backup.moqui-log.env" ] || cp "$SUPPORT_ROOT/config/backup.env.moqui-log.example" "$SUPPORT_ROOT/config/backup.moqui-log.env"
else
  echo "Usage: $0 moqui-prod|moqui-log" >&2
  exit 2
fi

mkdir -p "$SUPPORT_ROOT/var/log" "$SUPPORT_ROOT/var/state/lock"
chmod 755 "$SUPPORT_ROOT/var/log" "$SUPPORT_ROOT/var/state" "$SUPPORT_ROOT/var/state/lock" || true

# Keep host-side permissions predictable before containers touch the directories.
# Final ownership for the database process is handled in compose-up.sh.
if [ "$ROLE" = "moqui-prod" ]; then
  chmod 755 "$DOCKER_ROOT/db/moqui-prod" "$DOCKER_ROOT/db/moqui-prod/config" "$DOCKER_ROOT/db/moqui-prod/pgbackrest" "$DOCKER_ROOT/db/moqui-prod/pgbackrest/repo" || true
  chmod 700 "$DOCKER_ROOT/db/moqui-prod/postgresql" || true
elif [ "$ROLE" = "moqui-log" ]; then
  chmod 755 "$DOCKER_ROOT/db/moqui-log" "$DOCKER_ROOT/db/moqui-log/config" "$DOCKER_ROOT/db/moqui-log/pgbackrest" "$DOCKER_ROOT/db/moqui-log/pgbackrest/repo" || true
  chmod 700 "$DOCKER_ROOT/db/moqui-log/postgresql" || true
fi

echo "Directories prepared for $ROLE. Review the generated config file under $SUPPORT_ROOT/config before use."
