# Observability Infrastructure Provisioning — Phase 8.8.5

**Status:** Complete (IaC + deployment path — host not yet applied)  
**Hardening:** [observability-hardening.md](observability-hardening.md) (Phase 8.8.6)  
**Repo:** `ixora-infra`  
**OpenTofu:** `opentofu/staging/`  
**Runtime:** `collector/docker-compose.yml` (source of truth)  
**ADRs:** [ADR-028](../../../decisions/ADR-028-observability-platform.md) · [ADR-030](../../../decisions/ADR-030-observability-security-and-privacy.md) · [ADR-031](../../../decisions/ADR-031-retention-storage-and-cost-control.md)

> **Rule:** OpenTofu provisions the **host**. Docker Compose runs the **stack**. Never duplicate observability service definitions in OpenTofu.

---

## 1. Architecture

```
DigitalOcean Droplet (ixora-observability-staging)
├── Ubuntu 24.04 LTS
├── Docker Engine + Compose v2
├── Caddy (HTTPS reverse proxy)
│   ├── grafana-staging.ixora-app.app → 127.0.0.1:3000
│   └── otel-staging.ixora-app.app    → 127.0.0.1:4318
├── /opt/ixora-observability/         ← git clone of ixora-infra
│   └── collector/
│       ├── docker-compose.yml        ← runtime source of truth
│       ├── .env                      ← secrets (chmod 600, not in git)
│       ├── config.yaml
│       ├── prometheus/
│       ├── loki/
│       ├── tempo/
│       └── grafana/provisioning/
└── systemd: ixora-observability.service (post-first-deploy)
```

### App Platform integration path

| Client | Endpoint | Auth |
| --- | --- | --- |
| `back_vibes-api` (App Platform) | `https://otel-staging.ixora-app.app` | `Authorization=Bearer <OTEL_INGEST_API_KEY_BACKEND>` |
| `back_vibes-worker` / scheduler | Same | Same |
| `front_vibes` (mobile) | Same (HTTP/protobuf) | `Authorization=Bearer <OTEL_INGEST_API_KEY_MOBILE>` |
| Engineers | `https://grafana-staging.ixora-app.app` | Grafana admin credentials |

App Platform attaches to the staging VPC for Postgres but **egresses to the public internet** for external HTTPS. OTLP uses the **public HTTPS hostname** (Caddy → Collector), not private VPC IP, unless a future phase validates private routing.

**OTEL env vars for App Platform** (set manually via DO console or `api_secrets_extra` — not auto-wired in this phase to avoid env churn):

| Variable | Example value |
| --- | --- |
| `OTEL_EXPORTER_OTLP_ENDPOINT` | `https://otel-staging.ixora-app.app` |
| `OTEL_EXPORTER_OTLP_PROTOCOL` | `http/protobuf` |
| `OTEL_EXPORTER_OTLP_HEADERS` | `Authorization=Bearer <backend-key>` (SECRET) |
| `OTEL_TRACES_EXPORTER` | `otlp` |
| `OTEL_METRICS_EXPORTER` | `otlp` |
| `OTEL_LOGS_EXPORTER` | `otlp` |

---

## 2. OpenTofu resource inventory

| Resource | OpenTofu name | Condition |
| --- | --- | --- |
| Droplet | `digitalocean_droplet.observability[0]` | `observability_enabled = true` |
| Firewall | `digitalocean_firewall.observability[0]` | `observability_enabled = true` |
| Block volume | `digitalocean_volume.observability[0]` | `observability_use_block_volume = true` |
| Volume attachment | `digitalocean_volume_attachment.observability[0]` | optional |

**Files:**

| File | Purpose |
| --- | --- |
| `observability.tf` | Droplet, firewall, optional volume |
| `templates/observability-cloud-init.yaml.tftpl` | Host bootstrap (no secrets) |
| `variables.tf` | Observability variables (§ observability_*) |
| `outputs.tf` | Non-sensitive host outputs |

---

## 3. Capacity decision

| Parameter | Default | Rationale |
| --- | --- | --- |
| **Size slug** | `s-4vcpu-8gb` | 4 vCPU, 8 GB RAM, **160 GB SSD** — matches infrastructure-review.md §10 |
| **Compose limits** | ~3 GB RAM, 3.5 CPU | Guardrails; headroom for OS + Caddy + spikes |
| **Documented recommendation** | 128 GB disk | Droplet includes 160 GB on this SKU |
| **Monthly cost** | ~$48/mo (DO list price — verify current pricing) | Staging-appropriate |
| **Resize strategy** | Change `observability_droplet_size`, apply (may require power-off) | Document in runbook |
| **Production** | Consider `s-8vcpu-16gb` + block volume + backups | Future phase |

---

## 4. Storage decision — Strategy A (default)

**Selected:** Droplet root disk with Docker named volumes (`prometheus_data`, `loki_data`, `tempo_data`, `grafana_data`).

| Aspect | Strategy A (default) | Strategy B (optional) |
| --- | --- | --- |
| Implementation | `observability_use_block_volume = false` | `observability_use_block_volume = true` |
| Data location | Droplet root SSD | Attached block volume |
| Survives container restart | ✅ | ✅ |
| Survives host reboot | ✅ | ✅ |
| Survives Droplet destroy | ❌ | ❌ (volume survives but must reattach) |
| Complexity | Low | Medium (mount + fstab) |
| Staging cost | Included in Droplet | + volume cost |

**Retention unchanged:** Prometheus 30d, Loki 14d, Tempo 7d (ADR-031).

---

## 5. Network and firewall

### Public inbound (Cloud Firewall)

| Port | Protocol | Source | Purpose |
| --- | --- | --- | --- |
| 22 | TCP | `observability_ssh_allowed_cidrs` | SSH (operators only) |
| 443 | TCP | `observability_https_allowed_cidrs` (default 0.0.0.0/0) | Caddy — Grafana + OTLP HTTP |

### Not publicly exposed

| Port | Service |
| --- | --- |
| 3000 | Grafana (127.0.0.1 only in compose) |
| 9090 | Prometheus |
| 3100 | Loki |
| 3200 | Tempo |
| 4317/4318/4319 | Collector (direct — use Caddy 443 instead) |
| 8888, 13133, 1777, 55679 | Collector ops ports |

---

## 6. DNS prerequisites (manual)

Before TLS succeeds, create **A records** pointing to `observability_public_ipv4` output:

| Hostname | Record |
| --- | --- |
| `grafana-staging.ixora-app.app` | A → Droplet public IPv4 |
| `otel-staging.ixora-app.app` | A → Droplet public IPv4 |

DNS is **not** managed by OpenTofu in this repository (see commented `domains.tf` pattern).

---

## 7. Secret delivery (separate from OpenTofu)

Secrets are **never** in cloud-init, OpenTofu outputs, or git.

### Workflow

1. `tofu apply` creates Droplet (infrastructure only)
2. SSH to host
3. Clone `ixora-infra` to `/opt/ixora-observability`
4. Export secrets in shell session
5. Run `scripts/bootstrap-collector-env.sh`
6. Run `scripts/deploy-observability.sh`
7. Configure App Platform OTEL headers separately (DO encrypted env)

### Required secret env vars for bootstrap

```bash
export OTEL_INGEST_API_KEY_BACKEND="$(openssl rand -hex 32)"
export OTEL_INGEST_API_KEY_MOBILE="$(openssl rand -hex 32)"
export GF_ADMIN_PASSWORD="$(openssl rand -base64 24)"
export GF_SERVER_ROOT_URL="https://grafana-staging.ixora-app.app"
./scripts/bootstrap-collector-env.sh
```

Result: `collector/.env` with `chmod 600`.

---

## 8. Repository delivery

**Preferred:** Git clone with read-only deploy key (registered outside OpenTofu).

```bash
ssh root@<observability-ip>
git clone git@github.com:lucasbrito90/ixora-infra.git /opt/ixora-observability
cd /opt/ixora-observability && git checkout release-2026.07.20
```

> **Deployment model (Phase 8.8.6):** Use **immutable release tags**, not rolling `develop`. See [deployment-strategy.md](deployment-strategy.md).

**Alternatives:** CI rsync/scp from pipeline; manual first deploy + release checkout for updates.

---

## 9. First deployment procedure

```bash
# 1. OpenTofu (operator workstation)
cd opentofu/staging
tofu init
tofu plan   # expect: + droplet, + firewall
tofu apply  # manual — not automated by this phase

# 2. DNS — point A records to observability_public_ipv4

# 3. Host bootstrap completes via cloud-init (Docker, Caddy, directories)

# 4. SSH + clone repo
ssh root@<ip>
git clone ... /opt/ixora-observability

# 5. Secrets + deploy
cd /opt/ixora-observability
# export secrets...
./scripts/bootstrap-collector-env.sh
./scripts/deploy-observability.sh

# 6. Verify
curl -sf http://127.0.0.1:13133/health
curl -sf https://grafana-staging.ixora-app.app/api/health
```

---

## 10. Repeat deployment / upgrades

```bash
cd /opt/ixora-observability
git fetch --tags origin
git checkout release-2026.07.20
IXORA_GIT_REF=release-2026.07.20 ./scripts/deploy-observability.sh
```

See [deployment-strategy.md](deployment-strategy.md) for release naming and rollback.

**Never run:** `docker compose down -v` (destroys named volumes).

---

## 11. Rollback

| Scenario | Action |
| --- | --- |
| Bad compose config | `git checkout <previous-commit>` + `./scripts/deploy-observability.sh` |
| Bad image version | Pin version in `.env`, redeploy |
| Caddy misconfig | Fix `/etc/caddy/Caddyfile`, `systemctl reload caddy` |
| Full stack failure | `docker compose stop` → fix → `docker compose up -d` |

---

## 12. Disaster recovery limitations

| Event | Data survives? | Recovery |
| --- | --- | --- |
| Container restart | ✅ | Automatic |
| `docker compose up -d` | ✅ | Volumes preserved |
| Host reboot | ✅ | systemd + Docker restart |
| Droplet destroy (Strategy A) | ❌ | Re-provision + restore from backup ([backup-strategy.md](backup-strategy.md) — not implemented) |
| Grafana config | ✅ in git | Re-clone + provisioning reload |
| `collector/.env` | ❌ in git | Recreate via bootstrap script |
| Prometheus/Loki/Tempo TSDB | ❌ on Droplet destroy | No backup in MVP — accept gap or add snapshots (future) |

**Backup architecture designed in Phase 8.8.6 — implementation deferred.** See [backup-strategy.md](backup-strategy.md).

---

## 13. Known limitations

| ID | Limitation |
| --- | --- |
| KL-INFRA-1 | DNS manual — TLS fails until A records propagate |
| KL-INFRA-2 | App Platform OTEL env not wired in OpenTofu — see [app-platform-otel-integration.md](app-platform-otel-integration.md) |
| KL-INFRA-3 | Strategy A — data lost on Droplet destroy — see [storage-strategy.md](storage-strategy.md) |
| KL-INFRA-4 | cloud-init changes do not re-run — see [cloud-init-review.md](cloud-init-review.md) |
| KL-INFRA-5 | Block volume mount not automated (Strategy B) |
| KL-INFRA-6 | Node Exporter deferred |
| KL-INFRA-7 | Recording rules files exist but `rule_files` still commented in prometheus.yml |
| KL-INFRA-8 | Reserved IP optional (`observability_use_reserved_ip`, default false) |
| KL-INFRA-9 | Backups designed but not implemented |

---

## 14. Related documents

| Document | Relationship |
| --- | --- |
| [infrastructure-review.md](infrastructure-review.md) | Original topology review (Phase 2) |
| [collector-deployment.md](collector-deployment.md) | Collector config reference |
| [grafana-foundation.md](grafana-foundation.md) | Grafana provisioning |
| [runbooks/observability-host.md](../../../runbooks/observability-host.md) | Operational runbook |
| [observability-hardening.md](observability-hardening.md) | Phase 8.8.6 hardening index |
| [deployment-strategy.md](deployment-strategy.md) | Release-oriented deployments |
| [backup-strategy.md](backup-strategy.md) | Backup architecture (design only) |
| [storage-strategy.md](storage-strategy.md) | Strategy A/B + Reserved IP |
| [collector/README.md](../../../../collector/README.md) | Runtime quick start |
