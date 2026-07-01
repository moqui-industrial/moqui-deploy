# Moqui Deploy

These are opinionated configurations of different ways to deploy Moqui along with infrastructure it depends on. 

## Layout

To keep deployments organized, configuration files are grouped into subdirectories based on their deployment profile:

*   **`industrial/`**: Configurations for industrial IoT applications (includes Docker Swarm configurations, ActiveMQ, MQTT Device Gateway, Grafana dashboards, OpenSearch, Postgres/YugabyteDB clustered data stores, backups, and automated staging deployment scripts using Multipass).
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

## Usage
1. Fork it
2. Remove what you don't want
3. Change what you want different
4. Use it
