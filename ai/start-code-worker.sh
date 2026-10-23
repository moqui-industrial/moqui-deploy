#!/bin/bash
# Starts the trusted bridge worker. It is the only process allowed to use Docker.
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SOURCE_DIR="$HERE/.code-interpreter"
ENV_FILE="$HERE/.code-interpreter.env"
WORKER_ID="moqui-sandbox-worker"
WORKER_IMAGE="moqui-code-worker:v1.0.0"
RUNTIME_IMAGE="moqui-code-runtime:v1.0.0"

test -f "$ENV_FILE" || "$HERE/bootstrap-code-interpreter.sh"
"$HERE/start-code-interpreter.sh"

if ! grep -q 'AS moqui-local-oci-runtime' "$SOURCE_DIR/api/Dockerfile"; then
    cat >> "$SOURCE_DIR/api/Dockerfile" <<'EOF'

FROM local-oci-runtime AS moqui-local-oci-runtime
COPY --from=package-builder /pkgs /pkgs
EOF
fi

docker build --target moqui-local-oci-runtime -t "$RUNTIME_IMAGE" -f "$SOURCE_DIR/api/Dockerfile" "$SOURCE_DIR"
docker build -t "$WORKER_IMAGE" -f "$HERE/code-interpreter-worker.Dockerfile" "$HERE"

bridge_token="$(sed -n 's/^CODEAPI_BRIDGE_TOKEN=//p' "$ENV_FILE")"
pairing_code="$(docker exec moqui-codeapi-api bun -e '
const response = await fetch("http://127.0.0.1:3112/v1/bridge/pairings", {
  method: "POST",
  headers: { Authorization: `Bearer ${process.env.CODEAPI_BRIDGE_TOKEN}`, "Content-Type": "application/json" },
  body: JSON.stringify({ workerId: "moqui-sandbox-worker" })
});
if (!response.ok) throw new Error(await response.text());
process.stdout.write((await response.json()).code);
' )"

docker volume create moqui-code-worker-state >/dev/null
docker rm -f moqui-code-worker >/dev/null 2>&1 || true
docker run --rm \
    --network moqui_default \
    --mount type=volume,source=moqui-code-worker-state,target=/root \
    "$WORKER_IMAGE" \
    pair http://moqui-codeapi-api:3112/v1 "$pairing_code" --worker-id "$WORKER_ID"

docker run -d --name moqui-code-worker --restart unless-stopped \
    --network moqui_default \
    --mount type=bind,source=/var/run/docker.sock,target=/var/run/docker.sock \
    --mount type=volume,source=moqui-code-worker-state,target=/root \
    -e LIBRECHAT_CODE_URL=http://moqui-codeapi-api:3112/v1 \
    -e LIBRECHAT_CODE_WORKER_ID="$WORKER_ID" \
    -e LIBRECHAT_CODE_RUNTIME_SUPERVISOR=docker \
    -e LIBRECHAT_CODE_RUNTIME_IMAGE="$RUNTIME_IMAGE" \
    -e LIBRECHAT_CODE_STATEFUL_WORKSPACE=true \
    -e LIBRECHAT_CODE_POLICY=default-deny \
    "$WORKER_IMAGE" run

echo "Paired stateful code worker started"
