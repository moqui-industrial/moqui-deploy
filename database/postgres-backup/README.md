# Moqui PostgreSQL Backup Operator Guide

This package is designed to live inside `moqui-framework/docker` and provides:

- `postgres-compose.yml` for the Moqui production PostgreSQL database
- `postgres-log-compose.yml` for the telemetry TimescaleDB database
- `pgBackRest` backup automation
- optional NAS mirroring after each successful local backup

This guide is written for operators. It focuses on repeatable, step-by-step procedures.

## Scope

Production database:

- database name: `moqui`
- compose file: `postgres-compose.yml`
- local port: `5433`
- backup stanza: `moqui-prod`

Telemetry database:

- database name: `moqui_log`
- compose file: `postgres-log-compose.yml`
- local port: `5434`
- backup stanza: `moqui-log`

This README starts with the production database because that is the most common operator workflow.

## Directory layout

Run all commands from `moqui-framework/docker`.

Top-level package files:

```text
.env.example
.env
README.md
postgres-compose.yml
postgres-log-compose.yml
postgres-moqui/
postgres-moqui-log/
db/
postgres-backup/
```

Namespaced support files:

```text
postgres-backup/
  README.md
  config/
  cron/
  docs/
  pgbackrest/
  scripts/
  var/
    log/
    state/
```

The package uses bind mounts relative to the `docker/` directory:

```text
./db/moqui-prod/postgresql        -> /var/lib/postgresql
./db/moqui-prod/config            -> PostgreSQL and pgBackRest config
./db/moqui-prod/pgbackrest/repo   -> local pgBackRest repository

./db/moqui-log/postgresql         -> /var/lib/postgresql
./db/moqui-log/config             -> PostgreSQL and pgBackRest config
./db/moqui-log/pgbackrest/repo    -> local pgBackRest repository
```

For PostgreSQL 18 images, the effective data directory inside the container is:

```text
/var/lib/postgresql/18/docker
```

## Prerequisites

Required host tools:

```bash
docker --version
docker compose version
java -version
psql --version
rsync --version
```

If mail notifications are used, the host also needs a working `mail` command.

## Logging and retention policy

This package uses native tooling where possible:

- PostgreSQL logs stay on container stderr/stdout
- Docker rotates container logs with the `json-file` logging driver
- pgBackRest writes to console only
- shell script logs are written to `./postgres-backup/var/log/*.log` and should be rotated with `logrotate`

### Docker container log rotation

Both database services use Docker native log rotation:

```text
driver: json-file
max-size: 50m
max-file: 5
```

These values are configurable through a `.env` file in `moqui-framework/docker`.

Example:

```bash
cp .env.example .env
nano .env
```

Available variables:

```text
DOCKER_LOG_MAX_SIZE=50m
DOCKER_LOG_MAX_FILE=5
```

### Script log rotation

The backup and restore scripts write logs under:

```text
./postgres-backup/var/log/
```

Use the provided template:

```text
postgres-backup/config/logrotate.postgres-backup.template
```

Copy it into your system logrotate configuration and replace the absolute path placeholder.

### pgBackRest logging

pgBackRest file logging is disabled intentionally:

- `log-level-console=info`
- `log-level-file=off`

This keeps pgBackRest aligned with container logging and avoids unmanaged file logs inside the container.

### Backup retention

Backup retention is configured in pgBackRest to keep:

- the latest `2` full backup chains
- only `1` differential layer per active chain

This means:

- the newest two full backup chains are retained
- differential and incremental backups older than the active chains are removed automatically by `expire`
- when a full backup expires, its dependent diff/incr backups expire with it

## Files to review before first use

Production database:

- `postgres-backup/config/backup.moqui-prod.env`
- `db/moqui-prod/config/postgresql.conf`
- `db/moqui-prod/config/pgbackrest.conf`

Telemetry database:

- `postgres-backup/config/backup.moqui-log.env`
- `db/moqui-log/config/postgresql.conf`
- `db/moqui-log/config/pgbackrest.conf`

## Production Database: First-Time Setup

This procedure creates a clean production database test environment from scratch.

### 1. Go to the docker directory

```bash
cd /absolute/path/to/moqui-framework/docker
```

### 2. Stop any existing production database container

```bash
docker compose -f postgres-compose.yml -p moqui down
```

### 3. Reset the local production database test directory if needed

Use this only for a clean rebuild or test reset.

```bash
rm -rf db/moqui-prod postgres-backup/var/log/* postgres-backup/var/state/*
mkdir -p postgres-backup/var/state/lock
```

### 4. Start the production database

Use the Moqui-style wrapper:

```bash
./build-compose-up.sh postgres-compose.yml
```

What this does:

- prepares the local directory structure
- copies default PostgreSQL and pgBackRest config
- fixes container-side ownership for bind mounts
- builds the PostgreSQL image
- starts the container

### 5. Confirm that the database container is healthy

```bash
docker compose -f postgres-compose.yml -p moqui ps
docker compose -f postgres-compose.yml -p moqui logs --tail=50 moqui-database
```

Expected result:

- container status is `Up`
- health status is `healthy`

At this stage you may still see archive warnings. That is normal until the pgBackRest stanza is created.

### 6. Confirm that PostgreSQL accepts connections

```bash
docker compose -f postgres-compose.yml -p moqui exec -T moqui-database pg_isready -U moqui -d moqui
docker compose -f postgres-compose.yml -p moqui exec -T moqui-database psql -U moqui -d moqui -c "select current_database(), current_user();"
```

Expected result:

- `accepting connections`
- database `moqui`
- user `moqui`

### 7. Initialize the pgBackRest stanza

```bash
CONFIG_FILE=./postgres-backup/config/backup.moqui-prod.env ./postgres-backup/scripts/init_pgbackrest_stanza.sh
```

### 8. Verify the stanza

```bash
docker compose -f postgres-compose.yml -p moqui exec -T moqui-database pgbackrest --stanza=moqui-prod info
```

Expected result on a new system:

- stanza status is `ok`
- no valid backups yet

This is correct before the first backup.

## Moqui Database Bootstrap

The production PostgreSQL container is now ready. Next, create the Moqui schema and data.

### 9. Go to the Moqui framework root

From `moqui-framework/docker`:

```bash
cd ../
```

### 10. Download the PostgreSQL JDBC driver

```bash
./gradlew getPostgresJdbc
```

### 11. Load Moqui into PostgreSQL

```bash
./gradlew load
```

If you need more details:

```bash
./gradlew load --info
```

### 12. Verify that Moqui created tables

```bash
psql -h 127.0.0.1 -p 5433 -U moqui -d moqui -c "\dt"
psql -h 127.0.0.1 -p 5433 -U moqui -d moqui -c "select schemaname, tablename from pg_tables where schemaname not in ('pg_catalog','information_schema') order by schemaname, tablename limit 20;"
```

Then return to the docker directory:

```bash
cd docker
```

## Production Database: Backup Test Procedure

This section validates:

- full backup
- differential backup
- incremental backup

### 13. Optional local test mode without real NAS

If you are validating backup logic on a workstation or temporary test VM, disable production fail-stop behavior before backup testing.

Edit:

```bash
nano postgres-backup/config/backup.moqui-prod.env
```

Recommended local test values:

```text
ENABLE_NAS_SYNC="false"
DISABLE_BACKUP_ON_NAS_FAILURE="false"
NOTIFY_METHOD="none"
```

If you are not testing a real NAS mount yet:

- set `ENABLE_NAS_SYNC="false"`
- set `DISABLE_BACKUP_ON_NAS_FAILURE="false"`
- set `NOTIFY_METHOD="none"`

This prevents local backup validation from being interrupted by NAS checks.

If a previous NAS failure created a disable file, re-enable backups:

```bash
CONFIG_FILE=./postgres-backup/config/backup.moqui-prod.env ./postgres-backup/scripts/enable_backups.sh
```

### 14. Run the first full backup

```bash
CONFIG_FILE=./postgres-backup/config/backup.moqui-prod.env ./postgres-backup/scripts/backup_pgbackrest.sh full
```

### 15. Verify the full backup

```bash
docker compose -f postgres-compose.yml -p moqui exec -T moqui-database pgbackrest --stanza=moqui-prod info
```

Expected result:

- one `full backup`
- stanza status `ok`

### 16. Create test data for the differential backup

```bash
docker compose -f postgres-compose.yml -p moqui exec -T moqui-database psql -U moqui -d moqui -c "create table if not exists backup_test(id bigint primary key, note text, created_at timestamptz default now());"
docker compose -f postgres-compose.yml -p moqui exec -T moqui-database psql -U moqui -d moqui -c "insert into backup_test(id, note) values (1, 'before diff') on conflict (id) do update set note = excluded.note;"
```

### 17. Run the differential backup

```bash
CONFIG_FILE=./postgres-backup/config/backup.moqui-prod.env ./postgres-backup/scripts/backup_pgbackrest.sh diff
```

### 18. Verify the differential backup

```bash
docker compose -f postgres-compose.yml -p moqui exec -T moqui-database pgbackrest --stanza=moqui-prod info
```

Expected result:

- one `full backup`
- one `diff backup`

### 19. Create more test data for the incremental backup

```bash
docker compose -f postgres-compose.yml -p moqui exec -T moqui-database psql -U moqui -d moqui -c "insert into backup_test(id, note) values (2, 'before incr') on conflict (id) do update set note = excluded.note;"
docker compose -f postgres-compose.yml -p moqui exec -T moqui-database psql -U moqui -d moqui -c "update backup_test set note = 'updated before incr' where id = 1;"
```

### 20. Run the incremental backup

```bash
CONFIG_FILE=./postgres-backup/config/backup.moqui-prod.env ./postgres-backup/scripts/backup_pgbackrest.sh incr
```

### 21. Final verification

```bash
CONFIG_FILE=./postgres-backup/config/backup.moqui-prod.env ./postgres-backup/scripts/check_backup_status.sh
docker compose -f postgres-compose.yml -p moqui exec -T moqui-database pgbackrest --stanza=moqui-prod info
docker compose -f postgres-compose.yml -p moqui exec -T moqui-database psql -U moqui -d moqui -c "select * from backup_test order by id;"
```

Expected result:

- one `full backup`
- at least one `diff backup`
- at least one `incr backup`
- test rows visible in `backup_test`

## Production Database: Normal Daily Operations

Useful commands:

Check container:

```bash
docker compose -f postgres-compose.yml -p moqui ps
```

Check database readiness:

```bash
docker compose -f postgres-compose.yml -p moqui exec -T moqui-database pg_isready -U moqui -d moqui
```

Check pgBackRest inventory:

```bash
docker compose -f postgres-compose.yml -p moqui exec -T moqui-database pgbackrest --stanza=moqui-prod info
```

Check recent logs:

```bash
docker compose -f postgres-compose.yml -p moqui logs --tail=100 moqui-database
```

## Telemetry Database: First-Time Setup

Use the telemetry compose only on the telemetry VM or telemetry environment.

### 1. Start the telemetry database

```bash
./build-compose-up.sh postgres-log-compose.yml
```

### 2. Confirm health

```bash
docker compose -f postgres-log-compose.yml -p moqui-log ps
docker compose -f postgres-log-compose.yml -p moqui-log logs --tail=50 moqui-log-database
```

### 3. Initialize the telemetry stanza

```bash
CONFIG_FILE=./postgres-backup/config/backup.moqui-log.env ./postgres-backup/scripts/init_pgbackrest_stanza.sh
```

### 4. Verify telemetry backup inventory

```bash
docker compose -f postgres-log-compose.yml -p moqui-log exec -T moqui-log-database pgbackrest --stanza=moqui-log info
```

## NAS Mirroring

The design is:

```text
pgBackRest local repository -> rsync mirror to NAS
```

NAS synchronization happens after each successful local backup.

To disable NAS mirroring explicitly for local backup testing:

```text
ENABLE_NAS_SYNC="false"
```

If NAS mirroring fails and `DISABLE_BACKUP_ON_NAS_FAILURE="true"`, the scripts create:

```text
./postgres-backup/var/state/BACKUP_DISABLED
```

When this file exists:

- future backup jobs abort immediately
- the operator must fix the NAS issue
- the operator must re-enable backups manually

Re-enable:

```bash
CONFIG_FILE=./postgres-backup/config/backup.moqui-prod.env ./postgres-backup/scripts/enable_backups.sh
```

## Cron Installation

Production database:

```bash
sed "s|/absolute/path/to/moqui-framework/docker|$(pwd)|g" postgres-backup/cron/moqui-prod.cron | crontab -
```

Telemetry database:

```bash
sed "s|/absolute/path/to/moqui-framework/docker|$(pwd)|g" postgres-backup/cron/moqui-log.cron | crontab -
```

Schedules:

Production:

```text
full: daily at 02:00
diff: hourly at minute 05
incr: every 10 minutes
check: daily at 08:30
```

Telemetry:

```text
full: daily at 03:00
incr: every 12 hours
check: daily at 08:45
```

## Restore Procedures

Restore latest backup:

```bash
CONFIG_FILE=./postgres-backup/config/backup.moqui-prod.env ./postgres-backup/scripts/restore_latest.sh
```

How this works:

- `pgBackRest` does not restore a differential or incremental backup in isolation
- when you restore the latest backup, `pgBackRest` automatically uses the correct chain
- if the latest valid backup is incremental, the restore uses:
  - the required full backup
  - the required differential backup, if any
  - the selected incremental backup

In other words, a "full restore from a diff or incr backup" is automatic. The operator does not need to manually apply full, then diff, then incr.

The restore scripts also do this automatically before restore:

- stop the PostgreSQL container
- empty the current `PGDATA`
- recreate the directory ownership expected by PostgreSQL
- run the restore
- start PostgreSQL again

### Restore the latest valid backup set

Use this when you want to recover the database to the most recent backup available in the local pgBackRest repository.

Steps:

1. Confirm the available backup chain:

```bash
docker compose -f postgres-compose.yml -p moqui exec -T moqui-database pgbackrest --stanza=moqui-prod info
```

2. Run the latest restore script:

```bash
CONFIG_FILE=./postgres-backup/config/backup.moqui-prod.env ./postgres-backup/scripts/restore_latest.sh
```

3. Type `RESTORE` when prompted.

4. Verify that PostgreSQL started correctly:

```bash
docker compose -f postgres-compose.yml -p moqui ps
docker compose -f postgres-compose.yml -p moqui exec -T moqui-database pg_isready -U moqui -d moqui
```

### Restore a specific backup set label

Use this when you want to restore a specific differential or incremental backup set shown by `pgbackrest info`.

Example labels:

```text
20260512-161700F
20260512-161700F_20260512-162648D
20260512-161700F_20260512-162758I
```

Important:

- if you restore a `D` label, pgBackRest automatically includes the required full backup
- if you restore an `I` label, pgBackRest automatically includes the required full and diff chain

Procedure:

1. Inspect the available labels:

```bash
docker compose -f postgres-compose.yml -p moqui exec -T moqui-database pgbackrest --stanza=moqui-prod info
```

2. Run the restore for the selected label:

```bash
CONFIG_FILE=./postgres-backup/config/backup.moqui-prod.env ./postgres-backup/scripts/restore_set.sh "20260512-161700F_20260512-162758I"
```

3. Verify that PostgreSQL started correctly:

```bash
docker compose -f postgres-compose.yml -p moqui ps
docker compose -f postgres-compose.yml -p moqui exec -T moqui-database pg_isready -U moqui -d moqui
```

### Restore a backup set exactly and promote the database

Use this when you must overwrite the current database and return it to the
exact state of a selected pgBackRest backup set.

This differs from `restore_set.sh`: a normal restore may replay later archived
WAL records after the selected backup set. The immediate restore script uses
`--type=immediate`, so later WAL records are intentionally not replayed. Because
that leaves PostgreSQL in recovery, the script also promotes the database to
primary with `pg_promote(...)`.

Procedure:

1. Inspect available labels:

```bash
docker compose -f postgres-log-compose.yml -p moqui-log exec -T moqui-log-database pgbackrest --stanza=moqui-log info
```

2. Run the exact overwrite restore:

```bash
CONFIG_FILE=./postgres-backup/config/backup.moqui-log.env ./postgres-backup/scripts/restore_set_immediate_promote.sh "20260514-161854F"
```

3. Type `RESTORE` when prompted.

For controlled automation or repeatable validation:

```bash
printf 'RESTORE\n' | CONFIG_FILE=./postgres-backup/config/backup.moqui-log.env ./postgres-backup/scripts/restore_set_immediate_promote.sh "20260514-161854F"
```

The script performs:

- stop the configured application service, if any
- stop the PostgreSQL service
- empty and re-own `PGDATA`
- run `pgbackrest restore --set=<label> --type=immediate`
- start PostgreSQL
- check `pg_is_in_recovery()`
- promote with `pg_promote(wait => true, wait_seconds => 30)` when needed
- verify that PostgreSQL is primary and ready

Post-restore verification:

```bash
docker compose -f postgres-log-compose.yml -p moqui-log exec -T moqui-log-database psql -U moqui -d moqui_log -c "select pg_is_in_recovery();"
CONFIG_FILE=./postgres-backup/config/backup.moqui-log.env ./postgres-backup/scripts/check_backup_status.sh
```

Expected result:

```text
pg_is_in_recovery = false
Backup status OK
```

### Verified restore example

The following incremental backup label was restored successfully during validation:

```text
20260512-161700F_20260512-162758I
```

Command used:

```bash
CONFIG_FILE=./postgres-backup/config/backup.moqui-prod.env ./postgres-backup/scripts/restore_set.sh "20260512-161700F_20260512-162758I"
```

Post-restore verification:

```bash
docker compose -f postgres-compose.yml -p moqui ps
docker compose -f postgres-compose.yml -p moqui exec -T moqui-database pg_isready -U moqui -d moqui
docker compose -f postgres-compose.yml -p moqui exec -T moqui-database psql -U moqui -d moqui -c "select * from backup_test order by id;"
```

Expected restored rows:

```text
 id |        note
----+---------------------
  1 | updated before incr
  2 | before incr
```

### Recommended restore verification

After any restore, verify:

```bash
docker compose -f postgres-compose.yml -p moqui exec -T moqui-database psql -U moqui -d moqui -c "select current_database(), current_user();"
docker compose -f postgres-compose.yml -p moqui exec -T moqui-database psql -U moqui -d moqui -c "select * from backup_test order by id;"
```

Point-in-time recovery:

```bash
CONFIG_FILE=./postgres-backup/config/backup.moqui-prod.env ./postgres-backup/scripts/restore_pitr.sh "2026-05-08 14:30:00"
```

Use PITR when you want to recover to a timestamp between backups. pgBackRest uses the full backup plus the archived WAL needed to reach the requested time.

Restore repository from NAS before restore, if needed:

```bash
CONFIG_FILE=./postgres-backup/config/backup.moqui-prod.env ./postgres-backup/scripts/pull_repo_from_nas.sh
```

## Troubleshooting

### PostgreSQL container is restarting

Check:

```bash
docker compose -f postgres-compose.yml -p moqui logs --tail=100 moqui-database
```

Common causes:

- bind mount permissions
- invalid PostgreSQL config
- invalid pgBackRest config

### `archive.info` missing

This means the stanza was not created yet.

Fix:

```bash
CONFIG_FILE=./postgres-backup/config/backup.moqui-prod.env ./postgres-backup/scripts/init_pgbackrest_stanza.sh
```

### `ClassNotFoundException: org.postgresql.xa.PGXADataSource`

The PostgreSQL JDBC driver is missing from Moqui runtime.

Fix from `moqui-framework`:

```bash
./gradlew getPostgresJdbc
./gradlew load
```

### Backups abort because they are disabled

Check:

```bash
ls -l state
cat postgres-backup/var/state/BACKUP_DISABLED
```

Fix the root cause, then run:

```bash
CONFIG_FILE=./postgres-backup/config/backup.moqui-prod.env ./postgres-backup/scripts/enable_backups.sh
```

### Local backup works but NAS mirroring fails

Check:

- `NAS_MOUNT_POINT`
- `NAS_BACKUP_ROOT`
- host mount state
- permissions for the NAS mount path

For workstation testing, disable fail-stop behavior temporarily:

```text
ENABLE_NAS_SYNC="false"
DISABLE_BACKUP_ON_NAS_FAILURE="false"
NOTIFY_METHOD="none"
```

## Recommended Production Values

Use the following baseline values unless the customer has a specific operational requirement.

### Docker container logs

In `.env`:

```text
DOCKER_LOG_MAX_SIZE=50m
DOCKER_LOG_MAX_FILE=5
```

This gives bounded Docker log growth while keeping recent PostgreSQL and pgBackRest console output available through `docker logs`.

### Script log rotation

In `postgres-backup/config/logrotate.postgres-backup.template`:

```text
size 50M
rotate 10
```

Adjust only if the host has strict storage limits or unusually heavy operator activity.

### Backup retention

Current pgBackRest production defaults:

```text
repo1-retention-full=2
repo1-retention-diff=1
```

This means:

- keep the latest 2 full backup chains
- keep the latest differential layer inside each active chain
- retain incremental backups only as part of valid active chains

### Production backup environment

Recommended production values in `postgres-backup/config/backup.moqui-prod.env`:

```text
ENABLE_NAS_SYNC="true"
DISABLE_BACKUP_ON_NAS_FAILURE="true"
NOTIFY_METHOD="mail"
NAS_MOUNT_POINT="/mnt/backup_nas"
NAS_BACKUP_ROOT="/mnt/backup_nas/moqui-postgres-backup"
```

### Local test environment

Recommended local validation values:

```text
ENABLE_NAS_SYNC="false"
DISABLE_BACKUP_ON_NAS_FAILURE="false"
NOTIFY_METHOD="none"
```

## Acceptance Checklist

Before production handover, confirm all of the following:

```text
[ ] Production database container starts and remains healthy
[ ] pgBackRest stanza-create succeeds
[ ] Moqui connects to PostgreSQL successfully
[ ] Moqui schema/data load completes successfully
[ ] Full backup succeeds
[ ] Differential backup succeeds
[ ] Incremental backup succeeds
[ ] WAL archiving succeeds
[ ] NAS mirror succeeds on the real target environment
[ ] Backup disable/re-enable workflow is understood by operators
[ ] Latest restore has been tested
[ ] PITR has been tested
[ ] Cron jobs are installed
```
