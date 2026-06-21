Put custom OpenSearch configuration files in this directory.

By default, `opensearch-compose.yml` uses the official image defaults (recommended for security plugin bootstrap).
If you want to override the config, uncomment the related volume mapping in `opensearch-compose.yml`:

- ./opensearch/config/opensearch.yml:/usr/share/opensearch/config/opensearch.yml:ro

After changing config files, rebuild and restart containers.
