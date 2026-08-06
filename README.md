# Moqui Deploy

These are opinionated configurations of different ways to deploy Moqui along with infrastructure it depends on. 

## Layout

To keep deployments organized, configuration files are grouped into subdirectories based on their deployment profile:

*   **`industrial/`**: Configurations for industrial IoT applications (includes Docker Swarm configurations, ActiveMQ, MQTT Device Gateway, Grafana dashboards, OpenSearch, Postgres/YugabyteDB clustered data stores, backups, automated staging deployment scripts using Multipass, and GPU-oriented OpenVLA inference services callable from Moqui `remote-rest` services).
*   **`ai/`**: AI-oriented local deployment profile for components such as LibreChat and OpenSearch used with `moqui-mcp`.
*   *Other profiles* (e.g., `ecommerce/`, `erp/`, etc.) can be added to customize deploy environments for specific application areas.

The `industrial/` profile also includes two Grafana usage modes:
- integrated inside `moqui-postgres-compose.yml` for the full local stack
- `grafana-compose.yml` for a single Grafana instance used with native Moqui

Both modes share the same dashboard set and the same `grafana/datasource/datasource-compose.yml`
definition so there is only one local Grafana datasource configuration to maintain.

The pinned Grafana container version for this profile is currently `13.1.0`.
No AI-specific Grafana plugins are preinstalled by default in this deployment
profile so the stack remains fully self-hosted and free of optional commercial
assistant dependencies.

## Industrial OpenVLA

The `industrial/openvla/` subtree provides a standalone deployment unit for
serving OpenVLA-style inference behind simple REST endpoints that Moqui can call
through `service type="remote-rest"`.

Key files:

- `industrial/openvla-compose.yml` — local Docker Compose deployment
- `industrial/openvla-stack.yml` — Docker Swarm deployment
- `industrial/openvla/server.py` — FastAPI server exposing `/act`, `/ground`, `/healthz`, `/readyz`
- `industrial/openvla/openvla.env` — default runtime parameters
- `industrial/openvla/fetch_openvla_sample_media.py` — helper that downloads
  official OpenVLA demo media and extracts local sample frames for grounding tests

Production expectation:

- a GPU is available for the main OpenVLA action model
- Hugging Face model cache is persisted on a shared or host-backed volume
- API tokens are injected via Docker secrets or environment variables depending on the profile

Operational note:

- `/act` is the full VLA path intended for GPU-backed action inference
- `/ground` is the lighter visual-grounding path; it was also verified in a CPU-only
  developer setup with an OWLViT model, but production should still prefer GPU-backed execution
  and the stronger default grounding models

The generated `sample-media/` assets used during local testing are intentionally
not committed; regenerate them locally with:

```bash
python industrial/openvla/fetch_openvla_sample_media.py
```

## Usage
1. Fork it
2. Remove what you don't want
3. Change what you want different
4. Use it
