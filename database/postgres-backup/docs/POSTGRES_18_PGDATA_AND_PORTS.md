# PostgreSQL 18.3 PGDATA layout, UTC timezone and ports

This package follows the PostgreSQL 18 Docker image layout. Do not force `PGDATA=/var/lib/postgresql/data`.

Use bind mounts on the parent directory from `moqui-framework/docker`:

```text
./db/moqui-prod/postgresql -> /var/lib/postgresql
./db/moqui-log/postgresql  -> /var/lib/postgresql
```

The effective PGDATA inside the container is:

```text
/var/lib/postgresql/18/docker
```

The host-side data directories are therefore:

```text
./db/moqui-prod/postgresql/18/docker
./db/moqui-log/postgresql/18/docker
```

Ports:

```text
moqui-prod: 127.0.0.1:5433 -> 5432
moqui-log:  127.0.0.1:5434 -> 5432
```

Timezone settings in both `postgresql.conf` files:

```conf
timezone = 'UTC'
log_timezone = 'UTC'
```

Images:

```text
moqui-prod: postgres:18.3
moqui-log:  timescale/timescaledb:2.26.2-pg18
```
