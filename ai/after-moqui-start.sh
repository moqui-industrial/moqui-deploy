#!/bin/bash
# Waits until Moqui answers and then restarts LibreChat, so that its MCP client (and its circuit breaker, which does not heal by
# itself) starts against a Moqui that is up. Called by the user service moqui-main.service after Moqui starts.
for i in $(seq 1 120); do
  curl -s -o /dev/null http://127.0.0.1:8080/Login && break
  sleep 5
done
curl -s -o /dev/null http://127.0.0.1:8080/Login || { echo "Moqui does not answer" >&2; exit 1; }
docker restart moqui-librechat
