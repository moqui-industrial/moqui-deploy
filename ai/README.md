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
- `start-ai-stack.sh`: starts the AI side in order (skills sync, client patch, Keycloak, Python skills server, LibreChat)
- `sync-librechat-skills.sh`: copies the deployment skills of LibreChat into `librechat/skills`
- `patch-librechat-ui.sh`: builds the LibreChat client patch (sidebar, theme and sign-in messages of the Moqui panel)
- `python-skills-compose.yml`, `python-skills-mcp/`: MCP server that runs the Python scripts of the skills, without network access

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

## LibreChat skills

LibreChat loads the skills of the deployment from one directory, `librechat/skills`, mounted at `/app/skills`
(`DEPLOYMENT_SKILLS_DIR`). The model spec `Moqui` in `librechat/librechat.yaml` switches them on for every chat, and the
Skills entry of the sidebar is hidden, so users neither build nor upload skills.

`sync-librechat-skills.sh` builds that directory from the skill repositories listed in its `SOURCES` array:

- `.agents/skills` in `moqui-industrial/moqui-agent-skills`

What it does:

1. copies every folder with a `SKILL.md` flat into `librechat/skills`, because LibreChat reads only the skills at the root
   of the directory; a skill removed from its repository is removed from the directory too
2. stops on a symbolic link or on two skills with the same folder name, which LibreChat refuses
3. moves the `compatibility` front-matter key under `metadata`, a key LibreChat does not accept at the top level

LibreChat reads the skills when it starts, so after a change in a skill repository:

```bash
ai/sync-librechat-skills.sh
docker restart moqui-librechat
```

`start-ai-stack.sh` runs the sync on every start. To add or remove a repository, edit `SOURCES` at the top of the
script. These are the skills of LibreChat (integrations and data loading towards Moqui); the llm-client skills of
the Moqui assistant are not offered to LibreChat by `moqui-mcp`.

## BI charts

The `Moqui` model spec enables LibreChat Artifacts. The `moqui-bi-analysis` skill renders bounded DataDocument query
results as a Chart.js HTML artifact and an accessible table. Chart.js is loaded from its pinned public CDN version;
the optional Vega-Lite JSON is an export format, not a LibreChat renderer.

Start the whole AI side (after Moqui):

```bash
ai/start-ai-stack.sh
```

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
