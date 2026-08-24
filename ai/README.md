# AI Profile

This profile contains local Docker deployment assets for the Moqui AI stack.

Current scope:

- LibreChat as the chat client
- Anthropic/Claude as the LLM provider for LibreChat
- MongoDB for LibreChat state
- OpenSearch and OpenSearch Dashboards for Moqui retrieval and evaluation

The profile is intended for development and staging-style local validation, especially for `moqui-mcp`.

## Files

- `librechat-compose.yml`: LibreChat + MongoDB
- `librechat/librechat.yaml`: LibreChat MCP configuration for Moqui and Anthropic
- `opensearch-compose.yml`: OpenSearch + Dashboards
- `opensearch/`: custom Dockerfiles and plugin install scripts

## Usage

Start LibreChat:

```bash
docker compose -f ai/librechat-compose.yml -p moqui-ai up -d
```

LibreChat expects an Anthropic API key in `ai/.env`:

```bash
LIBRECHAT_ANTHROPIC_API_KEY=your_claude_key
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
- Ollama is not part of the active local validation profile anymore; Claude is the supported path for current `moqui-mcp` prompt testing
