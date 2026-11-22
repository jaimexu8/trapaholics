# trapaholics backups

Automatic full-network backups (ARCHITECTURE.md §11). Scripts live under
`scripts/backup/`; systemd units under `systemd/`.

| Script | Timer (UTC) | What it does |
|---|---|---|
| `backup.sh` | every 4 h (`00/4:00`) | Consistent archive → `backups/trapaholics-YYYY-MM-DD_HHMM.tar.zst` + `.sha256` |
| `offload.sh` | hourly at `:30` | Upload archives older than 24 h to encrypted Drive, verify, then delete local |
| `prune-drive.sh` | daily at `03:30` | Permanently delete Drive archives ≥ 30 days after upload |

Enable the **timers** only (`systemctl enable --now …timer`); the `.service` units have no `[Install]` section.

Local archives are **not** encrypted (`chmod 700` on `backups/`, `600` on files).
Everything that leaves the server goes through the rclone **crypt** remote (B6).

## .env variables required

Do **not** commit these. Put them in the repo-root `.env` (mode 600):

| Variable | Used by | Purpose |
|---|---|---|
| `DISCORD_WEBHOOK_URL` | all three scripts | Admin-only Discord channel for failure / low-space / prune alerts. If unset, scripts log a warning and continue. |
| `MARIADB_ROOT_PASSWORD` | `backup.sh` | Password for `mariadb-dump` of the `luckperms` database. |

Tunables (non-secret) live in `scripts/backup/backup.conf`.

## Install on the host (`jt@` Debian, repo at `/home/jt/mc`)

### 1. Prerequisites

```bash
sudo apt-get update
sudo apt-get install -y rclone zstd curl
# flock comes from util-linux (already on Debian)
# jt must be in the docker group (already done on this host)
groups jt   # should include docker
```

### 2. Install rclone remotes (one-time)

You need **two** remotes: `gdrive` (OAuth to Drive) and `gdrive-crypt` (crypt on top of `gdrive:mc-backups`).

#### 2a. Headless Google OAuth for `gdrive`

On the server:

```bash
rclone config
# n) New remote
# name: gdrive
# storage: drive  (Google Drive)
# scope: drive
# Leave client_id / client_secret blank to use rclone's
# When asked about auto config: N  (headless)
```

rclone prints a command to run on a machine with a browser:

```bash
# On your laptop (rclone installed):
rclone authorize "drive"
# Paste the token back into the server prompt.
```

Confirm you can see Drive:

```bash
rclone lsd gdrive:
rclone mkdir gdrive:mc-backups
```

#### 2b. Crypt remote `gdrive-crypt`

```bash
rclone config
# n) New remote
# name: gdrive-crypt
# storage: crypt
# remote: gdrive:mc-backups
# filename_encryption: off          # dates stay readable; contents encrypted
# directory_name_encryption: false
# Password / salt: generate strong values (rclone can generate them)
```

**Store the crypt password and salt OFF the server** (password manager). rclone only
*obscures* them in `rclone.conf`; it does not encrypt them. If both the server and
that off-site copy are lost, **every Drive backup is permanently unrecoverable**.

```bash
chmod 600 ~/.config/rclone/rclone.conf
# Never commit rclone.conf. Never put it inside backups/ or the git repo.
```

Optional: lock the config with `RCLONE_CONFIG_PASS` and feed it from a root-only
file into the systemd units later.

Smoke-test:

```bash
echo test > /tmp/rclone-crypt-test.txt
rclone copy /tmp/rclone-crypt-test.txt gdrive-crypt:
rclone cryptcheck /tmp/rclone-crypt-test.txt gdrive-crypt:
rclone deletefile gdrive-crypt:rclone-crypt-test.txt --drive-use-trash=false
rm /tmp/rclone-crypt-test.txt
```

### 3. Enable systemd timers

From the repo root after deploy:

```bash
cd /home/jt/mc
sudo cp systemd/trapaholics-*.service systemd/trapaholics-*.timer /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl enable --now trapaholics-backup.timer
sudo systemctl enable --now trapaholics-offload.timer
sudo systemctl enable --now trapaholics-prune-drive.timer
systemctl list-timers 'trapaholics-*'
```

Manual one-shot runs:

```bash
sudo systemctl start trapaholics-backup.service
sudo systemctl start trapaholics-offload.service
sudo systemctl start trapaholics-prune-drive.service
journalctl -u trapaholics-backup.service -u trapaholics-offload.service -u trapaholics-prune-drive.service -n 100 --no-pager
```

Units run as user `jt` with `WorkingDirectory=/home/jt/mc`.

### 4. Permissions

```bash
mkdir -p /home/jt/mc/backups
chmod 700 /home/jt/mc/backups
chmod 755 /home/jt/mc/scripts/backup
chmod 644 /home/jt/mc/scripts/backup/backup.conf /home/jt/mc/scripts/backup/lib.sh
chmod 755 /home/jt/mc/scripts/backup/*.sh
```

## What each backup contains

- `velocity/`, `survival/`, `creative/` (worlds, plugins, configs)
- `config/`, `scripts/`, `docker-compose.yml`, `.env`, `frpc.toml`, `relay/` (if present)
- MariaDB logical dump at `.backup-staging/luckperms.sql` (via
  `docker exec mariadb mariadb-dump --single-transaction`)
- **Not** included: live `mariadb/` datadir and legacy top-level `data/` (not on
  the include list). Optional excludes in `backup.conf` are **anchored** paths
  such as `survival/libraries` (never bare `data`, which would strip world/plugin
  data directories).

While archiving, `backup.sh` runs `save-off` + `save-all flush` on running Paper
containers (`survival`, `creative`) over `rcon-cli`, and always restores `save-on`
via an EXIT trap.

## Low-disk behaviour (B4 / B5)

Before creating a new archive, `backup.sh` estimates need ≈ newest archive × 1.25
(or live data size if none) + `SAFETY_MARGIN_BYTES` (default 5 GiB). While free
space is short it offloads the **oldest** local archive (ignoring the 24 h rule)
through the same upload→cryptcheck→delete path. If Drive is unreachable or
nothing remains to move, it **aborts without deleting anything** and Discord-alerts.

## Offload details (B2 / B3 / B5 / B6)

```bash
rclone copy <file> gdrive-crypt: --bwlimit=8M   # tunable in backup.conf
rclone cryptcheck <file> gdrive-crypt:
# only then:
#   append "<filename> <UTC ISO>" to backups/.uploaded.log
#   delete local archive + .sha256
```

`offload.sh --oldest-one` offloads a single oldest file ignoring age (same path
`backup.sh` uses for space).

Repeated upload/verify failures trip a Discord alert after
`OFFLOAD_FAIL_ALERT_THRESHOLD` (default 3) consecutive failures.

## Prune (B7)

`prune-drive.sh` deletes every Drive object whose upload time in
`backups/.uploaded.log` is ≥ `PRUNE_AGE_DAYS` (30), with
`--drive-use-trash=false`, then drops the log line. Safety net:

```bash
rclone delete gdrive-crypt: --min-age 31d --drive-use-trash=false \
  --include 'trapaholics-*.tar.zst' --include 'trapaholics-*.tar.zst.sha256'
```

## Restore procedure

Practise this from a Drive copy before launch, and periodically after.

1. **Recreate rclone remotes** on the restore machine with the saved crypt
   password and salt (see §2). Without them, Drive backups cannot be decrypted.
2. **Download and decrypt** one archive (and its `.sha256` if present):

   ```bash
   mkdir -p /tmp/restore && cd /tmp/restore
   rclone copy gdrive-crypt:trapaholics-YYYY-MM-DD_HHMM.tar.zst .
   rclone copy gdrive-crypt:trapaholics-YYYY-MM-DD_HHMM.tar.zst.sha256 .
   ```

   A local archive under 24 h old can be used directly from `backups/` instead.
3. **Verify checksum:**

   ```bash
   sha256sum -c trapaholics-YYYY-MM-DD_HHMM.tar.zst.sha256
   zstd -t trapaholics-YYYY-MM-DD_HHMM.tar.zst
   ```
4. **Stop the stack** (on the host that will receive the restore):

   ```bash
   cd /home/jt/mc
   docker compose down
   ```
5. **Extract** over the repo root (or into a fresh directory you then promote):

   ```bash
   # Destructive — know what you are overwriting.
   zstd -dc /tmp/restore/trapaholics-YYYY-MM-DD_HHMM.tar.zst | tar -x -C /home/jt/mc
   ```
6. **Start MariaDB only**, load the dump, then bring the rest up:

   ```bash
   cd /home/jt/mc
   set -a
   # shellcheck disable=SC1091
   source .env
   set +a
   docker compose up -d mariadb
   # wait until healthy, then:
   MYSQL_PWD="$MARIADB_ROOT_PASSWORD" docker exec -e MYSQL_PWD -i mariadb \
     mariadb -uroot < /home/jt/mc/.backup-staging/luckperms.sql
   docker compose up -d
   ```
7. Confirm players can join; check LuckPerms groups; remove `.backup-staging/` when done.

## Testing without production

### Automated harness (laptop)

From the worktree / repo:

```bash
bash scripts/backup/test/run-tests.sh
```

Uses temp dirs and stub `docker` / `rclone` / `df` (real `flock` from
util-linux when available). Covers save-off/on, flush-failure trap via
`backup.sh`, dump failure + alert, world/plugin `data/` retention, low-space
abort + alert, cryptcheck gate, prune 29d23h/30d boundaries, malformed names,
invalid `RCLONE_REMOTE`, same-minute rerun, and `.partial` skip.

### Manual checks on the server

**Low-space path**

```bash
# Temporarily set a huge SAFETY_MARGIN_BYTES in backup.conf (e.g. several TB),
# put at least one archive in backups/, then:
/home/jt/mc/scripts/backup/backup.sh
# Expect: offload of oldest → either enough space and a new archive, or abort + Discord.
# Restore SAFETY_MARGIN_BYTES afterwards.
```

**Pruning**

```bash
# Append a fake old line (upload time 31+ days ago), with a disposable remote file:
echo "trapaholics-2000-01-01_0000.tar.zst 2000-01-01T00:00:00Z" >> backups/.uploaded.log
# Upload a tiny matching file first if you want a real delete, then:
/home/jt/mc/scripts/backup/prune-drive.sh
# Confirm the line is gone (or kept if deletefile failed) and journal looks clean.
```

**Timers**

```bash
systemctl list-timers 'trapaholics-*'
systemd-analyze verify /etc/systemd/system/trapaholics-*.service /etc/systemd/system/trapaholics-*.timer
```
