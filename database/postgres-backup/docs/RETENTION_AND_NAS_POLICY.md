# Retention, Incremental Backups, and NAS Policy

## pgBackRest retention behavior

pgBackRest does not overwrite old backups in place.

It creates backup sets organized in chains:

```text
FULL
  ├── DIFF
  │     ├── INCR
  │     └── INCR
  └── DIFF
        └── INCR
```

When a full backup expires, all dependent differential and incremental backups expire with it. When a differential backup expires, dependent incremental backups expire with it.

Therefore incremental and differential backups do not remain forever. They are retained only while their backup chain is retained.

## Production database policy

For `moqui-prod`:

- Full backup: daily.
- Differential backup: hourly.
- Incremental backup: every 10 minutes.
- pgBackRest retention: 2 full backup chains.

Configuration:

```ini
repo1-retention-full=2
repo1-retention-diff=1
```

With one full backup per day, this gives approximately 2 active full chains.

## Telemetry database policy

For `moqui-log`:

- Full backup: daily.
- Incremental backup: every 12 hours.
- pgBackRest retention: 2 full backup chains.

Configuration:

```ini
repo1-retention-full=2
repo1-retention-diff=1
```

With one full backup per day, this gives approximately 2 active full chains.

## NAS mirror policy

The local pgBackRest repository is the retention authority.

NAS synchronization uses:

```bash
rsync -aH --numeric-ids --delete
```

This means the NAS copy is a mirror of the local pgBackRest repository. When pgBackRest expires old backup chains locally, the next successful NAS synchronization removes the same expired files from the NAS.

## Fail-stop policy

If NAS copy fails after the configured number of retries, the scripts create:

```text
./postgres-backup/var/state/BACKUP_DISABLED
```

After that, all future backup jobs abort immediately and send a notification.

This is intentional. It prevents the system from silently accumulating backups only on the VM without external NAS protection.
