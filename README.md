# Moqui Deploy

These are opinionated configurations of different ways to deploy Moqui along with infrastructure it depends on. 

## Layout

To keep deployments organized, configuration files are grouped into subdirectories based on their deployment profile:

*   **`industrial/`**: Configurations for industrial IoT applications (includes Docker Swarm configurations, ActiveMQ Artemis and a redundant RMQTT MQTT broker (see `industrial/rmqtt/README.md`), MQTT Device Gateway, Grafana dashboards, OpenSearch, Postgres/YugabyteDB clustered data stores, backups, automated staging deployment scripts using Multipass, and GPU-oriented OpenVLA inference services callable from Moqui `remote-rest` services).
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

## Rust device gateway

`industrial/device-gateway-compose.yml` describes the Java/Quarkus gateway.
Use `industrial/device-gateway-rust-compose.yml` for the Rust `mr-moqui` branch:

```bash
export DEVICE_GATEWAY_CONTEXT=/absolute/path/to/moqui-device-gateway
export GATEWAY_DEVICE_ID=GW_EDGE_01
export GATEWAY_API_AUTH_TOKEN='replace-with-a-real-secret'
docker compose -f industrial/device-gateway-rust-compose.yml -p moqui up -d --build
```

The checkout must be on `mr-moqui`. Start the industrial database/broker first,
load the model through MR-Moqui master, and select the existing model and broker
networks with `GATEWAY_MODEL_NETWORK` (default `moqui_default`) and
`GATEWAY_BROKER_NETWORK` (default `moqui-broker_brokernet`, as created by the
Artemis Compose project `moqui-broker`). Set `GATEWAY_DATABASE_URL`, `GATEWAY_LOG_DATABASE_URL` and
broker credentials and `MQTT_BROKER_URL` for your environment. The default shared DB is for local tests;
log storage may use a separate PostgreSQL/TimescaleDB database in production.
The gateway reads the shared Moqui schema; it does not run the Java Moqui image.

Rust gateway instructions are maintained in its branch-specific README:
https://github.com/moqui/moqui-device-gateway/blob/mr-moqui/README.md
Use a single gateway implementation on port 8081 and one active process for each
logical `GATEWAY_DEVICE_ID`.
