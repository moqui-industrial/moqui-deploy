# AI Profile

This profile contains local Docker deployment assets for the Moqui AI stack.

Current scope:

- LibreChat as the chat client
- OpenAI and Anthropic/Claude as the primary LLM providers for LibreChat
- Google/Gemini as an optional additional provider for LibreChat
- DeepSeek as an optional direct OpenAI-compatible provider
- Kimi as an optional direct OpenAI-compatible provider
- MongoDB for LibreChat state
- OpenSearch and OpenSearch Dashboards for Moqui retrieval and evaluation

The profile is intended for development and staging-style local validation, especially for `moqui-mcp`.

## Files

- `librechat-compose.yml`: LibreChat + MongoDB
- `librechat/librechat.yaml`: LibreChat MCP configuration for Moqui, OpenAI, Anthropic, Google, DeepSeek, and Kimi
- `opensearch-compose.yml`: OpenSearch + Dashboards
- `opensearch/`: custom Dockerfiles and plugin install scripts

## Usage

Start LibreChat:

```bash
docker compose -f ai/librechat-compose.yml -p moqui-ai up -d
```

LibreChat reads provider keys from `ai/.env`:

```bash
LIBRECHAT_OPENAI_API_KEY=your_openai_key
LIBRECHAT_ANTHROPIC_API_KEY=your_claude_key
LIBRECHAT_GOOGLE_KEY=your_gemini_key
LIBRECHAT_GOOGLE_MODELS=gemini-2.5-flash,gemini-2.5-pro
LIBRECHAT_DEEPSEEK_API_KEY=your_deepseek_key
LIBRECHAT_MOONSHOT_API_KEY=your_kimi_key
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
- Ollama is not part of the active local validation profile anymore
- the current validation profile keeps OpenAI and Claude as the main providers, with Gemini, DeepSeek, and Kimi available when their API keys are configured
