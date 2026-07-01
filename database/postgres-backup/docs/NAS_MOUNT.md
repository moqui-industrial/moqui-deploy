# NAS Mount Setup

Create the mount point:

```bash
mkdir -p /mnt/backup_nas
```

Create credentials:

```bash
install -m 600 -o root -g root /dev/null /etc/nas-credentials
nano /etc/nas-credentials
```

Example content:

```text
username=NAS_USER
password=NAS_PASSWORD
domain=OPTIONAL_DOMAIN
```

Add an `/etc/fstab` line based on:

```text
postgres-backup/config/fstab.cifs.template
```

Example:

```text
//NAS_IP_OR_DNS/backup_share /mnt/backup_nas cifs credentials=/etc/nas-credentials,uid=1000,gid=1000,iocharset=utf8,vers=3.0,x-systemd.automount,x-systemd.idle-timeout=60,x-systemd.mount-timeout=30,_netdev,nofail 0 0
```

Reload and test:

```bash
systemctl daemon-reload
mount -a
mountpoint -q /mnt/backup_nas && echo OK
```

The backup scripts also access the mount point before copying in order to trigger systemd automount.
