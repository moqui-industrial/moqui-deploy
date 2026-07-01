#! /bin/bash

if [[ ! $1 ]]; then
  echo "Usage: ./build-compose-up.sh <docker compose file>"
  exit 1
fi

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
"$SCRIPT_DIR/compose-up.sh" "$1"
