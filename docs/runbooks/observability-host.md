# Runbook — Observability Host (Staging)

**Host:** `ixora-observability-staging` (DigitalOcean Droplet)  
**Deploy path:** `/opt/ixora-observability/collector`  
**Runtime:** `docker compose` via `ixora-observability.service`

---

## SSH access

```bash
ssh root@<observability-public-ipv4>
# Or use output: tofu output -raw observability_ssh_command
```

SSH is restricted to CIDRs in `observability_ssh_allowed_cidrs`. Password auth is disabled.

---

## Service status

```bash
systemctl status docker
systemctl status caddy
systemctl status ixora-observability
cd /opt/ixora-observability/collector && docker compose ps
```

Expected containers:

| Container | Service |
| --- | --- |
| `ixora-otel-collector` | OpenTelemetry Collector |
| `ixora-prometheus` | Prometheus |
| `ixora-loki` | Loki |
| `ixora-tempo` | Tempo |
| `ixora-grafana` | Grafana |

---

## Health checks (from host)

```bash
curl -sf http://127.0.0.1:13133/health          # Collector
curl -sf http://127.0.0.1:9090/-/healthy        # Prometheus
curl -sf http://127.0.0.1:9090/-/ready
curl -sf http://127.0.0.1:3100/ready              # Loki
curl -sf http://127.0.0.1:3200/ready              # Tempo
curl -sf http://127.0.0.1:3000/api/health         # Grafana
```

External (after DNS + TLS):

```bash
curl -sf https://grafana-staging.ixora-app.app/api/health
curl -sf -o /dev/null -w '%{http_code}\n' https://otel-staging.ixora-app.app/v1/traces
# Expect 401/405 without auth — confirms Caddy routing, not 502
```

---

## Logs

```bash
cd /opt/ixora-observability/collector

docker compose logs --tail=200 collector
docker compose logs --tail=200 prometheus
docker compose logs --tail=200 loki
docker compose logs --tail=200 tempo
docker compose logs --tail=200 grafana

journalctl -u ixora-observability -n 200 --no-pager
journalctl -u caddy -n 100 --no-pager
```

---

## Safe redeployment

Use **immutable release tags** — not `git pull develop`. See [deployment-strategy.md](../specs/observability-foundation/mvp/deployment-strategy.md).

```bash
cd /opt/ixora-observability
git fetch --tags origin
git checkout release-2026.07.20
IXORA_GIT_REF=release-2026.07.20 ./scripts/deploy-observability.sh
```

**Never run:** `docker compose down -v`

---

## Restart procedures

```bash
# Full stack (systemd)
systemctl restart ixora-observability

# Single service
cd /opt/ixora-observability/collector
docker compose restart prometheus

# Caddy (TLS / reverse proxy)
systemctl reload caddy
```

---

## Image upgrades

1. Update image tags in `collector/.env` (or use defaults from `.env.example`)
2. `./scripts/deploy-observability.sh` (runs `docker compose pull` + `up -d`)
3. Verify health checks

---

## Disk usage

```bash
df -h
docker system df
docker volume ls
du -sh /var/lib/docker/volumes/collector_*
```

Watch Prometheus 30d retention and Loki 14d on Strategy A (160 GB root disk).

---

## Volume inspection

```bash
docker volume ls | grep -E 'prometheus|loki|tempo|grafana'
docker volume inspect collector_prometheus_data
```

Volumes survive container recreation and `docker compose up -d`. They are **destroyed** by `docker compose down -v` or Droplet destroy (Strategy A).

---

## TLS renewal

Caddy handles automatic Let's Encrypt renewal. If certificates fail:

1. Verify DNS A records point to Droplet IP
2. Verify port 443 open in Cloud Firewall
3. `journalctl -u caddy -n 50`
4. `caddy validate --config /etc/caddy/Caddyfile`
5. `systemctl restart caddy`

---

## Failed deployment recovery

```bash
cd /opt/ixora-observability/collector
docker compose config          # validate syntax
docker compose ps -a
docker compose logs --tail=100 <service>
./scripts/deploy-observability.sh
```

If `.env` has placeholders, re-run `bootstrap-collector-env.sh` with real secrets.

---

## Full host reboot

```bash
reboot
# After boot (~2 min):
systemctl status docker ixora-observability caddy
cd /opt/ixora-observability/collector && docker compose ps
# Run health checks above
```

---

## Emergency shutdown

```bash
cd /opt/ixora-observability/collector
docker compose stop
# To restart: docker compose up -d  OR  systemctl start ixora-observability
```

---

## Accidental container deletion

```bash
cd /opt/ixora-observability/collector
docker compose up -d
# Volumes remain unless -v was used
```

---

## Accidental host replacement

1. `tofu apply` creates new Droplet (Strategy A = **data loss** unless backups restored)
2. Re-create DNS if IP changed — **skip if Reserved IP enabled** (`observability_use_reserved_ip = true`)
3. Clone repo at last known-good release tag, bootstrap `.env`, deploy
4. App Platform OTEL endpoint unchanged when DNS/Reserved IP preserved

See [backup-strategy.md](../specs/observability-foundation/mvp/backup-strategy.md) and [storage-strategy.md](../specs/observability-foundation/mvp/storage-strategy.md) §5.

---

## How to avoid deleting volumes

| Safe | Unsafe |
| --- | --- |
| `docker compose up -d` | `docker compose down -v` |
| `docker compose restart` | `docker volume rm` |
| `docker compose stop` | Droplet destroy without backup |

---

## Security verification

From an external machine (not the host):

```bash
# Should timeout or refuse:
nc -zv <public-ip> 9090
nc -zv <public-ip> 3100
nc -zv <public-ip> 3200
nc -zv <public-ip> 3000

# Should succeed:
nc -zv <public-ip> 443
```
