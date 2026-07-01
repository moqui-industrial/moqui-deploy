# Bind Mount Policy

Use host bind mounts, not Docker named volumes.

Recommended VM 1 layout:

```text
./db/moqui-prod/postgresql              -> PostgreSQL cluster directory
./db/moqui-prod/config/postgresql.conf -> PostgreSQL config
./db/moqui-prod/config/pgbackrest.conf -> pgBackRest config
./db/moqui-prod/pgbackrest/repo        -> local pgBackRest repository
```

Recommended VM 2 layout:

```text
./db/moqui-log/postgresql              -> PostgreSQL/TimescaleDB cluster directory
./db/moqui-log/config/postgresql.conf -> PostgreSQL config
./db/moqui-log/config/pgbackrest.conf -> pgBackRest config
./db/moqui-log/pgbackrest/repo        -> local pgBackRest repository
```

Bind mounts are preferred because they are explicit, easy to inspect, easy to include in operational documentation, and easier to recover manually during emergency maintenance.
