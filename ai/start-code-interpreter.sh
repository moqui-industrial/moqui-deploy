#!/bin/bash
# Starts only the Code API control-plane services for the Moqui sandbox bridge.
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SOURCE_DIR="$HERE/.code-interpreter"
ENV_FILE="$HERE/.code-interpreter.env"

test -f "$ENV_FILE" || "$HERE/bootstrap-code-interpreter.sh"
test -d "$SOURCE_DIR/.git" || "$HERE/bootstrap-code-interpreter.sh"
docker network inspect moqui_default >/dev/null

docker compose --env-file "$ENV_FILE" \
    -f "$SOURCE_DIR/docker-compose.yaml" \
    -f "$HERE/code-interpreter.override.yml" \
    -p moqui-codeapi \
    up -d --build api service-worker egress_gateway tool_call_server file_server redis minio

until docker exec moqui-codeapi-api bun -e "const response = await fetch('http://127.0.0.1:3112/v1/health'); process.exit(response.ok ? 0 : 1)"; do
    sleep 2
done

echo "Code API control plane is healthy on the private Docker network"
echo "Start the paired per-conversation worker with ./start-code-worker.sh"
