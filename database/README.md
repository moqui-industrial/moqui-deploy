# Moqui PostgreSQL Backup Package

This directory is structured to match the style of `moqui-framework/docker`.

Compose files and service build directories stay at the top level:

```text
postgres-compose.yml
postgres-log-compose.yml
postgres-moqui/
postgres-moqui-log/
db/
postgres-backup/
```

All package-specific operator assets are namespaced under:

```text
postgres-backup/
```

That directory contains:

```text
postgres-backup/
  README.md
  config/
  cron/
  docs/
  pgbackrest/
  scripts/
  var/
```

Use the detailed operator guide here:

```text
postgres-backup/README.md
```

Quick start:

```bash
./build-compose-up.sh postgres-compose.yml
CONFIG_FILE=./postgres-backup/config/backup.moqui-prod.env ./postgres-backup/scripts/init_pgbackrest_stanza.sh
```

Exact overwrite restore:

Use this when you must restore a database to the exact state of a selected
pgBackRest backup set and intentionally avoid replaying later WAL records.
The script restores with `--type=immediate`, restarts PostgreSQL, promotes the
database to primary, and verifies that it is writable.

```bash
CONFIG_FILE=./postgres-backup/config/backup.moqui-log.env \
  ./postgres-backup/scripts/restore_set_immediate_promote.sh "20260514-161854F"
```

For an interactive safety prompt, type `RESTORE` when requested. In automation
or controlled validation sessions:

```bash
printf 'RESTORE\n' | CONFIG_FILE=./postgres-backup/config/backup.moqui-log.env \
  ./postgres-backup/scripts/restore_set_immediate_promote.sh "20260514-161854F"
```

Use the backup label shown by:

```bash
docker compose -f postgres-log-compose.yml -p moqui-log exec -T moqui-log-database pgbackrest --stanza=moqui-log info
```

Operational note:

- `moqui-database-backup/` is not part of the active package layout
- it is an old root-owned leftover created during earlier tests
- the active production-ready package is the current root directory plus `postgres-backup/`
