# AI Profile

This profile contains local Docker deployment assets for the Moqui AI stack.

Current scope:

- LibreChat as the chat client
- Keycloak as the shared OIDC provider for Moqui and LibreChat
- OpenAI and Anthropic/Claude as the primary LLM providers for LibreChat
- Google/Gemini as an optional additional provider for LibreChat
- DeepSeek as an optional direct OpenAI-compatible provider
- Kimi as an optional direct OpenAI-compatible provider
- MongoDB for LibreChat state
- OpenSearch and OpenSearch Dashboards for Moqui retrieval and evaluation

The profile is intended for development and staging-style local validation, especially for `moqui-mcp`.

## Files

- `librechat-compose.yml`: LibreChat + MongoDB
- `keycloak-compose.yml`: Keycloak + PostgreSQL and the importable `moqui` realm
- `keycloak/realm/moqui-realm.json`: OIDC client definitions without committed secrets
- `librechat/librechat.yaml`: LibreChat MCP configuration for Moqui, OpenAI, Anthropic, Google, DeepSeek, and Kimi
- `opensearch-compose.yml`: OpenSearch + Dashboards
- `opensearch/`: custom Dockerfiles and plugin install scripts

## Usage

Start LibreChat:

```bash
docker compose -f ai/librechat-compose.yml -p ai up -d
```

LibreChat reads provider keys from `ai/.env`:

```bash
LIBRECHAT_OPENAI_API_KEY=your_openai_key
LIBRECHAT_ANTHROPIC_API_KEY=your_claude_key
LIBRECHAT_GOOGLE_KEY=your_gemini_key
LIBRECHAT_GOOGLE_MODELS=gemini-3.6-flash
LIBRECHAT_DEEPSEEK_API_KEY=your_deepseek_key
LIBRECHAT_MOONSHOT_API_KEY=your_kimi_key
```

Start OpenSearch:

```bash
docker compose -f ai/opensearch-compose.yml -p moqui-ai up -d --build
```

Start Keycloak before configuring Moqui SSO and LibreChat OIDC:

```bash
KEYCLOAK_DB_PASSWORD=replace-me
KEYCLOAK_ADMIN_PASSWORD=replace-me
KEYCLOAK_MOQUI_CLIENT_SECRET=replace-me
KEYCLOAK_LIBRECHAT_CLIENT_SECRET=replace-me
docker compose -f ai/keycloak-compose.yml -p ai up -d
```

The Keycloak compose file joins the externally managed `moqui_default` network, so
start Moqui before Keycloak and LibreChat. Keycloak is available at
`https://localhost:8444`; its development certificate is intentionally local and
is mounted into LibreChat as a trusted CA. The shared issuer is
`https://host.docker.internal:8444/realms/moqui` for the LibreChat container. Use
the matching browser-reachable issuer and redirect URL for the `moqui-web` client
configured through `moqui-sso`.

LibreChat is served directly at `http://localhost:3081`. Its `moqui` MCP server is
preconfigured to call the authenticated Moqui endpoint at
`http://host.docker.internal:8080/mcp`. This is a local integration profile: replace
the development service account configuration with per-user authentication before
deployment outside a trusted environment.

Stop services:

```bash
docker compose -f ai/librechat-compose.yml -p ai down
docker compose -f ai/opensearch-compose.yml -p moqui-ai down
```

## Notes

- runtime data directories such as `librechat/db`, `librechat/logs`, and `opensearch/data` are intentionally ignored
- Keycloak PostgreSQL data and all Keycloak credentials are intentionally ignored
- Keycloak TLS certificates and private keys are generated locally and are intentionally ignored
- the MCP authorization header in `librechat/librechat.yaml` is a development placeholder and should be replaced for production use
- this profile complements `moqui-mcp`; it does not replace runtime configuration inside Moqui
- Ollama is not part of the active local validation profile anymore
- the current validation profile keeps OpenAI and Claude as the main providers, with Gemini, DeepSeek, and Kimi available when their API keys are configured
