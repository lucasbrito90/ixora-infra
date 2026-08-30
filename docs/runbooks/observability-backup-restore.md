# Runbook — Observability Volume Backup & Restore (Staging)

**Host:** `ixora-observability-staging` (DigitalOcean Droplet)  
**Deploy path:** `/opt/ixora-observability`  
**Backup path:** `/opt/ixora-observability/backups/`  
**Scripts:** `scripts/backup-observability-volumes.sh`, `scripts/restore-observability-volume.sh`

---

## What is backed up

| Compose service | Docker volume key | Host volume name (typical) |
| --- | --- | --- |
| `prometheus` | `prometheus_data` | `collector_prometheus_data` |
| `loki` | `loki_data` | `collector_loki_data` |
| `tempo` | `tempo_data` | `collector_tempo_data` |
| `grafana` | `grafana_data` | `collector_grafana_data` |

Grafana **provisioning** (dashboards, datasources, alerting rules) lives in Git (`collector/grafana/provisioning/`) and does not need volume backup for dashboard recovery. The `grafana_data` tarball covers SQLite state, plugins, and user preferences only.

Secrets (`collector/.env`) are **not** backed up by these scripts — store them in the team password manager (see [backup-strategy.md](../specs/observability-foundation/mvp/backup-strategy.md) §3.6).

---

## Backup policy (staging)

| Setting | Value | Rationale |
| --- | --- | --- |
| Method | Per-volume `.tar.gz` tarball | Matches backup-strategy.md §3.5 staging recommendation |
| Frequency | Weekly (cron) + before release deploy (manual) | §5 |
| Retention | **4 tarballs per volume** | ~4 weekly generations; enough to recover from a bad deploy without unbounded disk use on the Droplet |
| Storage | Local only (`/opt/ixora-observability/backups/`) | No Spaces/S3 — staging scope only |
| Downtime | One service at a time (~seconds each) | Sequential stop → tar → start; other backends stay up |

Tarball naming: `{volume_key}-{YYYYMMDD-HHMMSS}.tar.gz`  
Example: `prometheus_data-20260829-030000.tar.gz`

---

## Manual backup

Run from the observability host as root (or a user in the `docker` group):

```bash
cd /opt/ixora-observability
./scripts/backup-observability-volumes.sh
```

Expected output ends with:

```
All 4 volume backups succeeded.
```

Verify tarballs were created:

```bash
ls -lh /opt/ixora-observability/backups/
```

Run before every release deploy to staging observability (in addition to the weekly cron).

---

## Weekly cron (operator installs — not automated by this repo)

Install on the **observability host** as root. The scripts do not install cron themselves.

```bash
# Edit root crontab on the observability host:
crontab -e
```

Add this line (Sundays at 03:00 UTC — low-traffic window):

```cron
0 3 * * 0 cd /opt/ixora-observability && ./scripts/backup-observability-volumes.sh >> /var/log/ixora-backup.log 2>&1
```

Optional: create the log file with restricted permissions before the first run:

```bash
touch /var/log/ixora-backup.log
chmod 600 /var/log/ixora-backup.log
```

Verify cron entry after saving:

```bash
crontab -l | grep ixora-backup
```

---

## Restore a single volume

**Warning:** restore replaces the entire volume contents. Run only when you need to recover from data loss or corruption.

List available backups for a service:

```bash
ls -1t /opt/ixora-observability/backups/prometheus_data-*.tar.gz
```

Restore the **latest** backup (default):

```bash
cd /opt/ixora-observability
./scripts/restore-observability-volume.sh prometheus
```

Restore a **specific** tarball:

```bash
cd /opt/ixora-observability
./scripts/restore-observability-volume.sh loki \
  /opt/ixora-observability/backups/loki_data-20260829-030000.tar.gz
```

Valid service names: `prometheus`, `loki`, `tempo`, `grafana`.

The script performs (backup-strategy.md §4.1):

1. `docker compose stop <service>`
2. Extract tarball into the Docker volume
3. `docker compose start <service>`
4. Poll the service health endpoint until ready

---

## Post-restore verification

After any restore, confirm health and data continuity:

### Health checks (from host)

```bash
curl -sf http://127.0.0.1:9090/-/ready          # Prometheus
curl -sf http://127.0.0.1:3100/ready              # Loki
curl -sf http://127.0.0.1:3200/ready              # Tempo
curl -sf http://127.0.0.1:3000/api/health         # Grafana
```

### Data continuity (Grafana)

1. Open Grafana staging UI.
2. For **Prometheus**: open a dashboard with recent metrics — confirm time series exist for the expected window.
3. For **Loki**: run a LogQL query for a known recent log line.
4. For **Tempo**: search for a recent trace ID.
5. For **Grafana volume**: confirm user preferences / alert notification state if applicable.

If provisioning-only recovery is sufficient (dashboards/datasources), prefer re-deploying from Git instead of restoring `grafana_data`:

```bash
cd /opt/ixora-observability
./scripts/deploy-observability.sh
./collector/grafana/validate.sh
```

---

## Troubleshooting

### Backup failed for one service

The backup script continues with the remaining services. Check the log for the failing service:

```bash
tail -50 /var/log/ixora-backup.log   # if using cron
```

Common causes:

- **Stop failed:** container name mismatch — run `docker compose ps` in `collector/`
- **Disk full:** check `df -h /opt/ixora-observability/backups/` — old tarballs are only pruned after a **successful** new backup
- **Volume not found:** run `docker volume ls | grep collector_`

### Restore health check timeout

```bash
cd /opt/ixora-observability/collector
docker compose logs --tail=50 <service>
docker compose ps
```

The restore script always attempts to restart the service even if extraction fails. If the service is down, start manually:

```bash
docker compose start <service>
```

### Service left stopped after interrupted run

If a backup/restore was interrupted (Ctrl-C, SSH drop), check and restart:

```bash
cd /opt/ixora-observability/collector
docker compose ps
docker compose start prometheus loki tempo grafana
```

---

## Related documents

| Document | Role |
| --- | --- |
| [backup-strategy.md](../specs/observability-foundation/mvp/backup-strategy.md) | Architecture, retention design, disaster recovery |
| [observability-host.md](observability-host.md) | Host access, service status, health checks |
| [deployment-strategy.md](../specs/observability-foundation/mvp/deployment-strategy.md) | Pre-deploy backup hook (future) |
