#! /bin/bash

if [[ ! $1 ]]; then
  echo "Usage: ./compose-up.sh <docker compose file>"
  exit 1
fi

set -euo pipefail

COMP_FILE="$1"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SUPPORT_DIR="$SCRIPT_DIR/postgres-backup"
COMP_BASENAME="$(basename "$COMP_FILE")"

if ! command -v docker >/dev/null 2>&1; then
  echo "ERROR: docker command not found in PATH" >&2
  exit 127
fi

if ! docker info >/dev/null 2>&1; then
  echo "ERROR: docker is not accessible for the current user" >&2
  echo "The operator must run this script in a shell with Docker daemon access." >&2
  exit 126
fi

case "$COMP_BASENAME" in
  postgres-compose.yml)
    ROLE="moqui-prod"
    PROJECT_NAME="moqui"
    PG_DIR="$SCRIPT_DIR/db/moqui-prod/postgresql"
    PGBACKREST_DIR="$SCRIPT_DIR/db/moqui-prod/pgbackrest"
    POSTGRES_UID="999"
    POSTGRES_GID="999"
    ;;
  postgres-log-compose.yml)
    ROLE="moqui-log"
    PROJECT_NAME="moqui-log"
    PG_DIR="$SCRIPT_DIR/db/moqui-log/postgresql"
    PGBACKREST_DIR="$SCRIPT_DIR/db/moqui-log/pgbackrest"
    POSTGRES_UID="70"
    POSTGRES_GID="70"
    ;;
  *)
    echo "Unsupported compose file: $COMP_FILE" >&2
    echo "Supported files: postgres-compose.yml, postgres-log-compose.yml" >&2
    exit 2
    ;;
esac

"$SUPPORT_DIR/scripts/install_prepare_directories.sh" "$ROLE"

# Match the ownership expected by the postgres user inside the official images.
docker run --rm -u root \
  -v "$PG_DIR:/target/postgresql" \
  -v "$PGBACKREST_DIR:/target/pgbackrest" \
  alpine:3.22 \
  sh -lc '
    chown -R '"$POSTGRES_UID:$POSTGRES_GID"' /target/postgresql /target/pgbackrest &&
    chmod 700 /target/postgresql &&
    find /target/pgbackrest -type d -exec chmod 755 {} \; &&
    find /target/pgbackrest -type f -exec chmod 644 {} \; || true
  '

docker compose -f "$COMP_FILE" -p "$PROJECT_NAME" up -d --build
