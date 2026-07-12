# Ixora Observability — Collector + Prometheus

**Phase:** 4 — Prometheus Metrics Backend  
**Stack:** OpenTelemetry Collector (contrib) + Prometheus via Docker Compose  
**VM:** DigitalOcean Droplet `observability-staging` (tor1) — [infrastructure-review.md](../docs/specs/observability-foundation/mvp/infrastructure-review.md)

> This directory contains the **complete Collector + Prometheus deployment** for the Ixora Observability Platform.  
> Loki (Phase 5), Tempo (Phase 6), and Grafana (Phase 9) are stubbed and will be enabled in their respective phases.

---

## Directory structure

```
collector/
├── config.yaml                  ← OpenTelemetry Collector configuration
├── docker-compose.yml           ← Compose file (Collector + Prometheus active)
├── .env.example                 ← Environment variable template (NEVER commit .env)
├── prometheus/
│   └── prometheus.yml           ← Prometheus configuration (Phase 4)
└── README.md                    ← This file
```

---

## Prerequisites

| Requirement | Version | Notes |
| --- | --- | --- |
| Docker | 24+ | `docker --version` |
| Docker Compose v2 | 2.20+ | `docker compose version` |
| VM disk | 128 GB recommended | [infrastructure-review.md §10](../docs/specs/observability-foundation/mvp/infrastructure-review.md) |
| Valid `.env` file | — | Copy from `.env.example` |

---

## Quick start

```bash
# 1. Clone / pull ixora-infra on the observability VM
cd /opt/ixora-observability

# 2. Create .env from template
cp collector/.env.example collector/.env
# Edit .env — fill OTEL_INGEST_API_KEY_BACKEND and OTEL_INGEST_API_KEY_MOBILE
# with strong random keys (openssl rand -hex 32)
chmod 600 collector/.env

# 3. Start Collector + Prometheus (Phase 4)
cd collector
docker compose up -d collector prometheus

# 4. Verify Collector
docker compose ps
curl http://127.0.0.1:13133/health

# 5. Verify Prometheus
curl http://127.0.0.1:9090/-/healthy
curl http://127.0.0.1:9090/-/ready
```

Expected health responses:

```
# Collector
{"status":"Server available","upSince":"...","uptime":"..."}

# Prometheus
Prometheus Server is Healthy.
Prometheus Server is Ready.
```

---

## Validation checklist (Phase 4)

Run after every deployment or config change. Mirrors [prometheus-deployment.md](../docs/specs/observability-foundation/mvp/prometheus-deployment.md) §9.

```bash
# ---- Collector ----

# 1. Collector running
docker compose ps collector
# Expected: running (healthy via host curl)

# 2. Collector health endpoint
curl -s http://127.0.0.1:13133/health | jq .
# Expected: {"status":"Server available",...}

# 3. Collector self-metrics available
curl -s http://127.0.0.1:8888/metrics | grep otelcol_
# Expected: otelcol_* metric lines

# 4. Unauthenticated OTLP — expect 401
curl -v http://127.0.0.1:4318/v1/traces
# Expected: 401 Unauthorized

# ---- Prometheus ----

# 5. Prometheus running
docker compose ps prometheus
# Expected: running (healthy)

# 6. Prometheus health endpoints
curl http://127.0.0.1:9090/-/healthy
curl http://127.0.0.1:9090/-/ready
# Expected: "Prometheus Server is Healthy." / "Ready."

# 7. TSDB healthy (no data yet — metrics arrive after app SDK Phase 7)
curl -s http://127.0.0.1:9090/api/v1/status/tsdb | jq .data.headStats
# Expected: JSON with numSeries, numSamples fields

# 8. Collector self-metrics visible in Prometheus
# (otelcol_* series arrive via prometheusremotewrite from prometheus/self receiver)
curl -s 'http://127.0.0.1:9090/api/v1/query?query=otelcol_process_uptime_seconds' \
  | jq .data.result
# Expected: non-empty result array after first scrape interval (~30s)

# 9. Prometheus self-metrics visible
curl -s 'http://127.0.0.1:9090/api/v1/query?query=prometheus_tsdb_head_series' \
  | jq .data.result
# Expected: non-empty result array

# 10. Remote write queue healthy (no errors)
curl -s 'http://127.0.0.1:9090/api/v1/query?query=prometheus_remote_storage_failed_samples_total' \
  | jq .data.result
# Expected: 0 or no result (no failures)

# 11. Retention flag confirmed
docker compose exec prometheus \
  prometheus --help 2>&1 | grep retention
# Or verify via API:
curl -s http://127.0.0.1:9090/api/v1/status/flags | jq '."storage.tsdb.retention.time"'
# Expected: "30d"

# 12. Persistence: restart and verify data survives
docker compose restart prometheus
sleep 10
curl -s 'http://127.0.0.1:9090/api/v1/query?query=prometheus_tsdb_head_series' \
  | jq .data.result
# Expected: same result as before restart (data from named volume)

# ---- Security ----

# 13. Prometheus not publicly reachable (from outside VM)
# This test runs from a different machine:
# curl http://<VM_PUBLIC_IP>:9090/-/healthy
# Expected: Connection refused or firewall drop

# 14. No application /metrics endpoints exposed
# Confirm no scrape_configs reference app containers:
grep -E 'targets|job_name' collector/prometheus/prometheus.yml
# Expected: only 'prometheus' job with 'localhost:9090'
```

---

## Upgrade strategy

```bash
# --- Collector upgrade ---
# 1. Update version in .env
OTEL_COLLECTOR_VERSION=0.116.0

# 2. Pull and restart without touching Prometheus
docker compose pull collector
docker compose up -d --no-deps collector

# 3. Validate
curl http://127.0.0.1:13133/health
docker compose logs collector --since=2m

# --- Prometheus upgrade ---
# 1. Update version in .env
PROMETHEUS_VERSION=v2.55.0

# 2. Pull and restart without touching Collector
docker compose pull prometheus
docker compose up -d --no-deps prometheus

# 3. Validate
curl http://127.0.0.1:9090/-/healthy
docker compose logs prometheus --since=2m

# 4. Confirm TSDB data survived (named volume persists across upgrade)
curl -s 'http://127.0.0.1:9090/api/v1/query?query=prometheus_tsdb_head_series' \
  | jq .data.result
```

Pin both services to specific versions — **never use `:latest`**.

---

## Environment variables

See [`.env.example`](.env.example) for full reference.

| Variable | Required | Description |
| --- | --- | --- |
| `OTEL_DEPLOYMENT_ENVIRONMENT` | ✅ | `staging` or `production` |
| `OTEL_INGEST_API_KEY_BACKEND` | ✅ | Bearer token for `back_vibes-*` clients |
| `OTEL_INGEST_API_KEY_MOBILE` | ✅ | Bearer token for `front_vibes-android` |
| `OTEL_COLLECTOR_VERSION` | ✅ | Collector image tag to pin |
| `PROMETHEUS_VERSION` | ✅ | Prometheus image tag to pin (default `v2.54.1`) |
| `PROMETHEUS_REMOTE_WRITE_ENDPOINT` | ✅ | `http://prometheus:9090/api/v1/write` |
| `PROMETHEUS_PORT` | Optional | Host port for Prometheus UI — defaults to `9090` |
| `OTEL_MEMORY_LIMIT_MIB` | Optional | Defaults to `512` |
| `OTEL_MEMORY_SPIKE_LIMIT_MIB` | Optional | Defaults to `128` |

---

## Ports reference

| Port | Service | Exposure | Purpose |
| --- | --- | --- | --- |
| `4317` | Collector | Public (TLS via proxy) | OTLP gRPC — backend |
| `4318` | Collector | Public (TLS via proxy) | OTLP HTTP — backend + mobile |
| `4319` | Collector | Public (TLS via proxy) | OTLP HTTP — mobile-dedicated |
| `8888` | Collector | Internal (`127.0.0.1`) | Collector self-metrics |
| `13133` | Collector | Internal (`127.0.0.1`) | Health check |
| `1777` | Collector | Internal (`127.0.0.1`) | pprof |
| `55679` | Collector | Internal (`127.0.0.1`) | zPages |
| `9090` | Prometheus | Internal (`127.0.0.1`) | Prometheus API + UI (Grafana Phase 9) |

Full firewall policy: [infrastructure-review.md §5](../docs/specs/observability-foundation/mvp/infrastructure-review.md).

---

## Security

- **Never commit `.env`** — git-ignored; store secrets in DO env or `chmod 600` file.
- **API keys** — rotate via `.env` rebuild; keep separate backend/mobile keys.
- **TLS** — terminate with Caddy or nginx in front of ports 4317/4318. For direct Collector TLS, uncomment `tls:` blocks in `config.yaml`.
- **Redaction** — `attributes/redact_secrets` processor drops all credential + PII keys per [ADR-030](../docs/decisions/ADR-030-observability-security-and-privacy.md).
- See [security-review.md](../docs/specs/observability-foundation/mvp/security-review.md) and [collector-hardening-checklist.md](../docs/operations/collector-hardening-checklist.md).

---

## Adding Phase 5–9 backends

1. Uncomment the relevant stub service in `docker-compose.yml`.
2. Create the required config directory (e.g. `collector/loki/loki.yaml`).
3. Add exporter block in `config.yaml` and reference in the pipeline.
4. Run `docker compose up -d <service>`.
5. Follow the phase-specific spec in `docs/specs/observability-foundation/mvp/`.

---

## Related documents

| Document | Role |
| --- | --- |
| [infrastructure-review.md](../docs/specs/observability-foundation/mvp/infrastructure-review.md) | VM topology and ports |
| [security-review.md](../docs/specs/observability-foundation/mvp/security-review.md) | Auth, TLS, redaction |
| [collector-hardening-checklist.md](../docs/operations/collector-hardening-checklist.md) | Deploy verification |
| [prometheus-deployment.md](../docs/specs/observability-foundation/mvp/prometheus-deployment.md) | Phase 4 — full Prometheus deployment spec |
| [telemetry-naming-convention.md](../docs/architecture/telemetry-naming-convention.md) | Naming in config |
| [observability-operational-limits.md](../docs/architecture/observability-operational-limits.md) | Memory/batch limits |
| [collector-deployment.md](../docs/specs/observability-foundation/mvp/collector-deployment.md) | Phase 3 — Collector deployment spec |
