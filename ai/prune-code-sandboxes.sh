#!/bin/bash
# Removes stopped sandbox runtimes and enforces a conservative maximum lifetime.
set -euo pipefail

MAX_AGE_SECONDS="${CODE_SANDBOX_MAX_AGE_SECONDS:-14400}"
now="$(date +%s)"

docker ps -aq --filter 'label=com.librechat.code.runtime=true' | while read -r container_id; do
    [ -n "$container_id" ] || continue
    state="$(docker inspect --format '{{.State.Status}}' "$container_id")"
    created="$(docker inspect --format '{{.Created}}' "$container_id")"
    created_epoch="$(date -d "$created" +%s)"
    age="$((now - created_epoch))"
    if [ "$state" != running ] || [ "$age" -ge "$MAX_AGE_SECONDS" ]; then
        docker rm --force "$container_id"
    fi
done
