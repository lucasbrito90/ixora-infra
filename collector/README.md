# Ixora Observability — Collector + Prometheus + Loki

**Phase:** 5 — Loki Log Backend  
**Stack:** OpenTelemetry Collector (contrib) + Prometheus + Loki via Docker Compose  
**VM:** DigitalOcean Droplet `observability-staging` (tor1) — [infrastructure-review.md](../docs/specs/observability-foundation/mvp/infrastructure-review.md)

> This directory contains the **complete Collector + Prometheus + Loki deployment** for the Ixora Observability Platform.  
> Tempo (Phase 6) and Grafana (Phase 9) are stubbed and will be enabled in their respective phases.  
> **Collector is the only log ingestion point.** Applications write OTLP Logs → Collector only. Loki never receives data from applications directly.

---

## Directory structure

```
collector/
├── config.yaml                  ← OpenTelemetry Collector configuration
├── docker-compose.yml           ← Compose file (Collector + Prometheus + Loki active)
├── .env.example                 ← Environment variable template (NEVER commit .env)
├── prometheus/
│   └── prometheus.yml           ← Prometheus configuration (Phase 4)
├── loki/
│   └── loki.yaml                ← Loki configuration (Phase 5)
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

# 3. Start Collector + Prometheus + Loki (Phase 5)
cd collector
docker compose up -d collector prometheus loki

# 4. Verify Collector
docker compose ps
curl http://127.0.0.1:13133/health

# 5. Verify Prometheus
curl http://127.0.0.1:9090/-/healthy
curl http://127.0.0.1:9090/-/ready

# 6. Verify Loki
curl http://127.0.0.1:3100/ready
curl http://127.0.0.1:3100/metrics | grep loki_ingester
```

Expected health responses:

```
# Collector
{"status":"Server available","upSince":"...","uptime":"..."}

# Prometheus
Prometheus Server is Healthy.
Prometheus Server is Ready.

# Loki
ready
```

---

## Validation checklist (Phase 5)

Run after every deployment or config change. Mirrors [loki-deployment.md](../docs/specs/observability-foundation/mvp/loki-deployment.md) §9 and [prometheus-deployment.md](../docs/specs/observability-foundation/mvp/prometheus-deployment.md) §9.

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
curl -s http://127.0.0.1:9090/api/v1/status/flags | jq '."storage.tsdb.retention.time"'
# Expected: "30d"

# 12. Persistence: restart and verify data survives
docker compose restart prometheus
sleep 10
curl -s 'http://127.0.0.1:9090/api/v1/query?query=prometheus_tsdb_head_series' \
  | jq .data.result
# Expected: same result as before restart (data from named volume)

# ---- Loki ----

# 13. Loki running
docker compose ps loki
# Expected: running (healthy)

# 14. Loki ready endpoint
curl http://127.0.0.1:3100/ready
# Expected: "ready"

# 15. Loki ring healthy (ingester member)
curl -s http://127.0.0.1:3100/ring | grep -i ingester
# Expected: ACTIVE state for ingester entry

# 16. Loki metrics exposed
curl -s http://127.0.0.1:3100/metrics | grep loki_ingester_streams_created_total
# Expected: metric line present (value may be 0 before first log push)

# 17. Manual push test — verify Collector → Loki path
# Send a test log payload via Collector (OTLP HTTP); check Loki received it:
curl -s 'http://127.0.0.1:3100/loki/api/v1/query_range' \
  --data-urlencode 'query={service_name="otel-collector"}' \
  --data-urlencode "start=$(date -d '1 minute ago' +%s)000000000" \
  --data-urlencode "end=$(date +%s)000000000" \
  | jq .data.result
# Expected: non-empty after Collector emits its first self-log (may take ~30s)

# 18. Loki retention confirmed in config
grep retention_period collector/loki/loki.yaml
# Expected: retention_period: 336h

# 19. Persistence: restart and verify log data survives
docker compose restart loki
sleep 15
curl http://127.0.0.1:3100/ready
# Expected: "ready"

# ---- Security ----

# 20. Loki not publicly reachable (from outside VM)
# This test runs from a different machine:
# curl http://<VM_PUBLIC_IP>:3100/ready
# Expected: Connection refused or firewall drop

# 21. Prometheus not publicly reachable (from outside VM)
# curl http://<VM_PUBLIC_IP>:9090/-/healthy
# Expected: Connection refused or firewall drop

# 22. No application /metrics endpoints exposed
grep -E 'targets|job_name' collector/prometheus/prometheus.yml
# Expected: only 'prometheus' job with 'localhost:9090'

# 23. Applications cannot reach Loki directly (network isolation)
# Loki is on ixora-observability Docker network — not accessible from
# application containers on other networks. Verify by checking compose networks:
docker network inspect ixora-observability | jq '.[].Containers | keys'
# Expected: only collector and loki container IDs
```

---

## Upgrade strategy

```bash
# --- Collector upgrade ---
# 1. Update version in .env
OTEL_COLLECTOR_VERSION=0.116.0

# 2. Pull and restart without touching Prometheus or Loki
docker compose pull collector
docker compose up -d --no-deps collector

# 3. Validate
curl http://127.0.0.1:13133/health
docker compose logs collector --since=2m

# --- Prometheus upgrade ---
# 1. Update version in .env
PROMETHEUS_VERSION=v2.55.0

# 2. Pull and restart without touching Collector or Loki
docker compose pull prometheus
docker compose up -d --no-deps prometheus

# 3. Validate
curl http://127.0.0.1:9090/-/healthy
docker compose logs prometheus --since=2m

# 4. Confirm TSDB data survived (named volume persists across upgrade)
curl -s 'http://127.0.0.1:9090/api/v1/query?query=prometheus_tsdb_head_series' \
  | jq .data.result

# --- Loki upgrade ---
# 1. Update version in .env
LOKI_VERSION=3.3.0

# 2. Review Loki release notes for schema migration requirements
#    before upgrading between minor versions.
#    https://grafana.com/docs/loki/latest/setup/upgrade/

# 3. Pull and restart without touching Collector or Prometheus
docker compose pull loki
docker compose up -d --no-deps loki

# 4. Validate
curl http://127.0.0.1:3100/ready
docker compose logs loki --since=2m

# 5. Confirm log data survived (loki_data named volume persists)
curl -s 'http://127.0.0.1:3100/loki/api/v1/query_range' \
  --data-urlencode 'query={service_name=~".+"}' \
  --data-urlencode "start=$(date -d '10 minutes ago' +%s)000000000" \
  --data-urlencode "end=$(date +%s)000000000" \
  | jq '.data.result | length'
# Expected: > 0 if logs were ingested before restart
```

Pin all services to specific versions — **never use `:latest`**.

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
| `LOKI_VERSION` | ✅ | Loki image tag to pin (default `3.2.0`) |
| `LOKI_ENDPOINT` | ✅ | `http://loki:3100/loki/api/v1/push` |
| `LOKI_PORT` | Optional | Host port for Loki API — defaults to `3100` |
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
| `3100` | Loki | Internal (`127.0.0.1`) | Loki push API + LogQL queries (Grafana Phase 9) |

Full firewall policy: [infrastructure-review.md §5](../docs/specs/observability-foundation/mvp/infrastructure-review.md).

---

## Security

- **Never commit `.env`** — git-ignored; store secrets in DO env or `chmod 600` file.
- **API keys** — rotate via `.env` rebuild; keep separate backend/mobile keys.
- **TLS** — terminate with Caddy or nginx in front of ports 4317/4318. For direct Collector TLS, uncomment `tls:` blocks in `config.yaml`.
- **Redaction** — `attributes/redact_secrets` processor drops all credential + PII keys per [ADR-030](../docs/decisions/ADR-030-observability-security-and-privacy.md).
- See [security-review.md](../docs/specs/observability-foundation/mvp/security-review.md) and [collector-hardening-checklist.md](../docs/operations/collector-hardening-checklist.md).

---

## Adding Phase 6–9 backends

Phase 5 (Loki) is now active. To enable remaining backends:

1. Uncomment the relevant stub service in `docker-compose.yml`.
2. Create the required config directory (e.g. `collector/tempo/tempo.yaml`).
3. Add exporter block in `config.yaml` and wire the pipeline.
4. Run `docker compose up -d <service>`.
5. Follow the phase-specific spec in `docs/specs/observability-foundation/mvp/`.

---

## Related documents

| Document | Role |
| --- | --- |
| [infrastructure-review.md](../docs/specs/observability-foundation/mvp/infrastructure-review.md) | VM topology and ports |
| [security-review.md](../docs/specs/observability-foundation/mvp/security-review.md) | Auth, TLS, redaction |
| [collector-hardening-checklist.md](../docs/operations/collector-hardening-checklist.md) | Deploy verification |
| [loki-deployment.md](../docs/specs/observability-foundation/mvp/loki-deployment.md) | Phase 5 — full Loki deployment spec |
| [prometheus-deployment.md](../docs/specs/observability-foundation/mvp/prometheus-deployment.md) | Phase 4 — full Prometheus deployment spec |
| [collector-deployment.md](../docs/specs/observability-foundation/mvp/collector-deployment.md) | Phase 3 — Collector deployment spec |
| [telemetry-naming-convention.md](../docs/architecture/telemetry-naming-convention.md) | Naming in config |
| [observability-operational-limits.md](../docs/architecture/observability-operational-limits.md) | Memory/batch limits |
| [metrics-philosophy.md](../docs/architecture/metrics-philosophy.md) | Metrics instrumentation philosophy |
| [telemetry-decision-guide.md](../docs/architecture/telemetry-decision-guide.md) | When to use logs vs metrics vs traces |
| [observability-playbook.md](../docs/operations/observability-playbook.md) | Operational runbook |
