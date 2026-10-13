#!/bin/bash
# Starts the AI side of the local stack in the order it needs: the skills of the deployment are copied, the client patch is built,
# Keycloak and LibreChat come up. Moqui itself runs on the host (see after-moqui-start.sh, which a service of the user runs once
# Moqui answers): LibreChat connects to its MCP endpoint when it starts, so it is restarted after Moqui is up.
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$HERE"
./sync-librechat-skills.sh
[ -f librechat-ui-patch.generated.yml ] || ./patch-librechat-ui.sh
docker compose -f keycloak-compose.yml -p ai up -d
mkdir -p librechat/skill-workspace
docker compose -f python-skills-compose.yml -p ai up -d --build
docker compose -f librechat-compose.yml -f librechat-ui-patch.generated.yml -p ai up -d
