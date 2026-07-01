#!/bin/bash
# Initialize/check pgBackRest stanza after the database container is running.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/lib_backup.sh"

compose_exec_postgres pgbackrest --stanza="$PGBACKREST_STANZA" stanza-create
compose_exec_postgres pgbackrest --stanza="$PGBACKREST_STANZA" check
compose_exec_postgres pgbackrest --stanza="$PGBACKREST_STANZA" info
