#!/bin/bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/lib_backup.sh"

if [ -f "$DISABLE_FILE" ]; then
  echo "Removing disable file: $DISABLE_FILE"
  rm -f "$DISABLE_FILE"
  notify "BACKUPS RE-ENABLED" "Backups have been re-enabled for ${BACKUP_INSTANCE} on host $(hostname)." || true
else
  echo "Backups were not disabled. No disable file found: $DISABLE_FILE"
fi
