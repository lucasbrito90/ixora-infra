# Ixora Observability — Collector

**Phase:** 3 — Collector Deployment  
**Stack:** OpenTelemetry Collector (contrib) via Docker Compose  
**VM:** DigitalOcean Droplet `observability-staging` (tor1) — [infrastructure-review.md](../docs/specs/observability-foundation/mvp/infrastructure-review.md)

> This directory contains the **complete Collector deployment** for the Ixora Observability Platform.  
> All other stack components (Prometheus, Loki, Tempo, Grafana) are stubbed and will be enabled in Phases 4–9.

---

## Directory structure

```
collector/
├── config.yaml          ← OpenTelemetry Collector configuration
├── docker-compose.yml   ← Compose file (Collector active; backends stubbed)
├── .env.example         ← Environment variable template (NEVER commit .env)
└── README.md            ← This file
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

# 3. Start Collector
cd collector
docker compose up -d collector

# 4. Verify
docker compose ps
docker compose logs collector --tail=40
curl http://127.0.0.1:13133/health
```

Expected health response:

```json
{"status":"Server available","upSince":"...","uptime":"..."}
```

---

## Validation checklist (Phase 3)

Run after every deployment or config change. Mirrors [collector-hardening-checklist.md](../docs/operations/collector-hardening-checklist.md) §11.

```bash
# 1. Container running
docker compose ps collector
# Expected: Status "healthy"

# 2. Health endpoint
curl -s http://127.0.0.1:13133/health | jq .
# Expected: {"status":"Server available",...}

# 3. Ports exposed
ss -tlnp | grep -E '4317|4318|4319|8888|13133'

# 4. gRPC OTLP reachable (requires grpcurl)
grpcurl -plaintext 127.0.0.1:4317 list
# Expected: grpc.health.v1.Health, opentelemetry.proto.collector.*

# 5. HTTP OTLP reachable (no auth — expect 401)
curl -v http://127.0.0.1:4318/v1/traces
# Expected: 401 Unauthorized (auth extension active)

# 6. Authenticated test span (replace TOKEN with OTEL_INGEST_API_KEY_BACKEND)
curl -s -w "\nHTTP %{http_code}\n" \
  -H "Authorization: Bearer TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"resourceSpans":[]}' \
  http://127.0.0.1:4318/v1/traces
# Expected: HTTP 200 (empty payload accepted)

# 7. Config validation
docker compose exec collector \
  /otelcol-contrib validate --config=/etc/otelcol/config.yaml
# Expected: Config validated successfully

# 8. Self-metrics scrape
curl -s http://127.0.0.1:8888/metrics | head -20
# Expected: otelcol_* metric lines

# 9. zPages diagnostics
curl -s http://127.0.0.1:55679/debug/servicez
# Expected: HTML page listing running components
```

---

## Upgrade strategy

```bash
# 1. Pull new image
OTEL_COLLECTOR_VERSION=0.116.0   # update in .env
docker compose pull collector

# 2. Rolling restart (zero-downtime on single VM: accept brief gap)
docker compose up -d --no-deps collector

# 3. Validate health
curl http://127.0.0.1:13133/health

# 4. Check logs for errors
docker compose logs collector --since=2m
```

Pin to a specific version — **never use `:latest`**.

---

## Environment variables

See [`.env.example`](.env.example) for full reference.

| Variable | Required | Description |
| --- | --- | --- |
| `OTEL_DEPLOYMENT_ENVIRONMENT` | ✅ | `staging` or `production` |
| `OTEL_INGEST_API_KEY_BACKEND` | ✅ | Bearer token for `back_vibes-*` clients |
| `OTEL_INGEST_API_KEY_MOBILE` | ✅ | Bearer token for `front_vibes-android` |
| `OTEL_COLLECTOR_VERSION` | ✅ | Image tag to pin |
| `OTEL_MEMORY_LIMIT_MIB` | Optional | Defaults to `512` |
| `OTEL_MEMORY_SPIKE_LIMIT_MIB` | Optional | Defaults to `128` |

---

## Ports reference

| Port | Exposure | Purpose |
| --- | --- | --- |
| `4317` | Public (TLS via proxy) | OTLP gRPC — backend |
| `4318` | Public (TLS via proxy) | OTLP HTTP — backend + mobile |
| `4319` | Public (TLS via proxy) | OTLP HTTP — mobile-dedicated |
| `8888` | Internal (`127.0.0.1`) | Collector self-metrics |
| `13133` | Internal (`127.0.0.1`) | Health check |
| `1777` | Internal (`127.0.0.1`) | pprof |
| `55679` | Internal (`127.0.0.1`) | zPages |

Full firewall policy: [infrastructure-review.md §5](../docs/specs/observability-foundation/mvp/infrastructure-review.md).

---

## Security

- **Never commit `.env`** — git-ignored; store secrets in DO env or `chmod 600` file.
- **API keys** — rotate via `.env` rebuild; keep separate backend/mobile keys.
- **TLS** — terminate with Caddy or nginx in front of ports 4317/4318. For direct Collector TLS, uncomment `tls:` blocks in `config.yaml`.
- **Redaction** — `attributes/redact_secrets` processor drops all credential + PII keys per [ADR-030](../docs/decisions/ADR-030-observability-security-and-privacy.md).
- See [security-review.md](../docs/specs/observability-foundation/mvp/security-review.md) and [collector-hardening-checklist.md](../docs/operations/collector-hardening-checklist.md).

---

## Adding Phase 4–9 backends

1. Uncomment the relevant stub service in `docker-compose.yml`.
2. Create the required config directory (e.g. `collector/prometheus/prometheus.yml`).
3. Add exporter block in `config.yaml` and reference in the pipeline.
4. Run `docker compose up -d`.
5. Follow the phase-specific spec in `docs/specs/observability-foundation/mvp/`.

---

## Related documents

| Document | Role |
| --- | --- |
| [infrastructure-review.md](../docs/specs/observability-foundation/mvp/infrastructure-review.md) | VM topology and ports |
| [security-review.md](../docs/specs/observability-foundation/mvp/security-review.md) | Auth, TLS, redaction |
| [collector-hardening-checklist.md](../docs/operations/collector-hardening-checklist.md) | Deploy verification |
| [telemetry-naming-convention.md](../docs/architecture/telemetry-naming-convention.md) | Naming in config |
| [observability-operational-limits.md](../docs/architecture/observability-operational-limits.md) | Memory/batch limits |
| [collector-deployment.md](../docs/specs/observability-foundation/mvp/collector-deployment.md) | Full deployment spec |
