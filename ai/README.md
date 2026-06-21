# AI Profile

This profile contains local Docker deployment assets for the Moqui AI stack.

Current scope:

- LibreChat as the chat client
- MongoDB for LibreChat state
- OpenSearch and OpenSearch Dashboards for Moqui retrieval and evaluation

The profile is intended for development and staging-style local validation, especially for `moqui-mcp`.

## Files

- `librechat-compose.yml`: LibreChat + MongoDB
- `librechat/librechat.yaml`: LibreChat MCP configuration for Moqui
- `opensearch-compose.yml`: OpenSearch + Dashboards
- `opensearch/`: custom Dockerfiles and plugin install scripts

## Usage

Start LibreChat:

```bash
docker compose -f ai/librechat-compose.yml -p moqui-ai up -d
```

Start OpenSearch:

```bash
docker compose -f ai/opensearch-compose.yml -p moqui-ai up -d --build
```

Stop services:

```bash
docker compose -f ai/librechat-compose.yml -p moqui-ai down
docker compose -f ai/opensearch-compose.yml -p moqui-ai down
```

## Notes

- runtime data directories such as `librechat/db`, `librechat/logs`, and `opensearch/data` are intentionally ignored
- the MCP authorization header in `librechat/librechat.yaml` is a development placeholder and should be replaced for production use
- this profile complements `moqui-mcp`; it does not replace runtime configuration inside Moqui
