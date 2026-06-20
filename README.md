# Moqui Deploy

These are opinionated configurations of different ways to deploy Moqui along with infrastructure it depends on. 

## Layout

To keep deployments organized, configuration files are grouped into subdirectories based on their deployment profile:

*   **`industrial/`**: Configurations for industrial IoT applications (includes Docker Swarm configurations, ActiveMQ, MQTT Device Gateway, Grafana dashboards, OpenSearch, Postgres/YugabyteDB clustered data stores, backups, and automated staging deployment scripts using Multipass).
*   *Other profiles* (e.g., `ecommerce/`, `erp/`, etc.) can be added to customize deploy environments for specific application areas.

## Usage
1. Fork it
2. Remove what you don't want
3. Change what you want different
4. Use it
