Drop Grafana dashboard JSON files in this directory.

They are auto-provisioned into the "Moqui" folder on startup and reloaded
within about 30 seconds after changes.

This directory is shared by:
- `moqui-postgres-compose.yml` for the all-in-one local industrial stack
- `grafana-compose.yml` for Grafana-only usage with native Moqui
