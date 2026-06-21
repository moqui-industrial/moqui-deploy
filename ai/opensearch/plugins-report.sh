#!/usr/bin/env bash
set -euo pipefail

container_name="${1:-moqui-search}"

echo "== CLI plugin list (${container_name}) =="
docker exec "${container_name}" /usr/share/opensearch/bin/opensearch-plugin list | sort

echo
echo "== _cat/plugins =="
curl -sS -k -u "${OPENSEARCH_USER:-admin}:${OPENSEARCH_PASSWORD:-MoquiElasticChangeMe@2026}" \
  "${OPENSEARCH_URL:-https://127.0.0.1:9200}/_cat/plugins?v"

echo
echo "== _nodes/plugins =="
curl -sS -k -u "${OPENSEARCH_USER:-admin}:${OPENSEARCH_PASSWORD:-MoquiElasticChangeMe@2026}" \
  "${OPENSEARCH_URL:-https://127.0.0.1:9200}/_nodes/plugins?pretty"
