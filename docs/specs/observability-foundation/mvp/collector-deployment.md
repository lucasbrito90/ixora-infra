# Observability Foundation — Collector Deployment

**Status:** Phase 3 complete — Collector configuration and Docker Compose ready  
**Spec:** [`spec.md`](spec.md) · **Infrastructure:** [`infrastructure-review.md`](infrastructure-review.md) · **Security:** [`security-review.md`](security-review.md)  
**Implementation:** [`../../../../collector/`](../../../../collector/)  
**ADRs:** [ADR-028](../../../decisions/ADR-028-observability-platform.md) · [ADR-030](../../../decisions/ADR-030-observability-security-and-privacy.md) · [ADR-031](../../../decisions/ADR-031-retention-storage-and-cost-control.md)

> **Goal:** Running OpenTelemetry Collector on the observability VM accepting authenticated OTLP, applying redaction and sampling, and ready for Phase 4 backend wiring.

---

## 1. Deployment model

The Collector runs as a **Docker container** on the observability VM managed by Docker Compose.

| Property | Value |
| --- | --- |
| Container name | `ixora-otel-collector` |
| Image | `otel/opentelemetry-collector-contrib` (pinned version) |
| Restart policy | `unless-stopped` |
| Config | bind-mounted read-only from `collector/config.yaml` |
| Secrets | injected via `.env` (never in config.yaml) |
| Health endpoint | `:13133/health` |
| Self-metrics | `:8888/metrics` |

### Why Docker Compose (not bare binary)

| Factor | Docker Compose |
| --- | --- |
| **Reproducibility** | Pinned image version; same config across VM rebuilds |
| **Isolation** | Container resource limits (CPU/memory) |
| **Upgrade** | Pull + recreate — no package manager dependency |
| **Backend stubs** | Single file to uncomment Phase 4–9 services |
| **Consistency** | Same toolchain engineers use locally for testing |

---

## 2. Docker Compose architecture

All observability services are declared in one file (`collector/docker-compose.yml`). Only the Collector service is enabled in Phase 3.

```
collector/
├── config.yaml           ← OTel Collector configuration
├── docker-compose.yml    ← Collector (active) + Phase 4–9 stubs (commented)
├── .env.example          ← Env var template
├── .env                  ← Runtime secrets (gitignored)
├── .gitignore
└── README.md
```

### Container naming

| Container | Name |
| --- | --- |
| Collector | `ixora-otel-collector` |
| Prometheus *(Phase 4)* | `ixora-prometheus` |
| Loki *(Phase 5)* | `ixora-loki` |
| Tempo *(Phase 6)* | `ixora-tempo` |
| Grafana *(Phase 9)* | `ixora-grafana` |

All containers share the `ixora-observability` Docker bridge network.

---

## 3. Configuration architecture

### Receivers

| Receiver | Port | Auth | Purpose |
| --- | --- | --- | --- |
| `otlp/backend` | 4317 (gRPC) + 4318 (HTTP) | Bearer token | `back_vibes-api`, `back_vibes-worker` |
| `otlp/mobile` | 4319 (HTTP) | Bearer token (separate key) | `front_vibes-android` |
| `prometheus/self` | 8888 (internal) | None | Collector self-monitoring |

### Processors (ordered per pipeline)

| # | Processor | Purpose |
| --- | --- | --- |
| 1 | `memory_limiter` | OOM guard — always first |
| 2 | `resource` | Stamp `deployment.environment` from env |
| 3 | `attributes/redact_secrets` | Drop credentials + PII ([ADR-030](../../../decisions/ADR-030-observability-security-and-privacy.md)) |
| 4 | `attributes/drop_high_cardinality` | Drop `user_id`, `trace_id`, etc. from metrics ([ADR-031](../../../decisions/ADR-031-retention-storage-and-cost-control.md)) |
| 5 | `transform/normalize_http` | Enforce `http.route` template over raw URLs |
| 6 | `probabilistic_sampler` | 10% success traces ([ADR-031](../../../decisions/ADR-031-retention-storage-and-cost-control.md)) |
| 7 | `batch` | Group before export — always last before exporters |

### Extensions

| Extension | Port | Exposure |
| --- | --- | --- |
| `health_check` | 13133 | Internal |
| `pprof` | 1777 | Internal |
| `zpages` | 55679 | Internal |
| `bearertokenauth/backend` | — | Ingest auth |
| `bearertokenauth/mobile` | — | Ingest auth |

### Pipelines

| Pipeline | Receivers | Notes |
| --- | --- | --- |
| `metrics` | backend + mobile + self | No exporter yet (Phase 4) |
| `logs` | backend + mobile | No exporter yet (Phase 5) |
| `traces` | backend + mobile | 10% sampled (Phase 6); error traces 100% via tail_sampling in Phase 6 |

### Exporter stubs

| Exporter | Status | Phase |
| --- | --- | --- |
| `debug` | **Active** (Phase 3 validation) | Remove in Phase 4+ steady state |
| `prometheusremotewrite` | Commented | Phase 4 |
| `loki` | Commented | Phase 5 |
| `otlp/tempo` | Commented | Phase 6 |

---

## 4. Security implementation

All requirements from [security-review.md](security-review.md) and [collector-hardening-checklist.md](../../../operations/collector-hardening-checklist.md):

| Requirement | Implementation |
| --- | --- |
| API Key auth | `bearertokenauth` extension + env vars |
| Separate backend/mobile keys | `bearertokenauth/backend` + `bearertokenauth/mobile` |
| Credential redaction | `attributes/redact_secrets` processor — 18 forbidden keys |
| High-cardinality drop | `attributes/drop_high_cardinality` — 7 forbidden metric labels |
| Memory protection | `memory_limiter` — 512 MiB hard limit |
| Batch protection | `batch` — `send_batch_max_size: 2000` |
| Backends localhost only | Exporter endpoints use `127.0.0.1` |
| TLS-ready | `tls:` block commented in receivers — uncomment when cert paths confirmed |
| Internal ports | 8888, 13133, 1777, 55679 bound to `127.0.0.1` |
| No secrets in config | All secrets via `${env:VAR}` references |
| Dedicated service user | Container runs as non-root (`otelcol` user in contrib image) |
| Restart policy | `unless-stopped` |

---

## 5. Environment variables

Full reference: [`collector/.env.example`](../../../../collector/.env.example).

| Variable | Required | Default |
| --- | --- | --- |
| `OTEL_DEPLOYMENT_ENVIRONMENT` | ✅ | `staging` |
| `OTEL_INGEST_API_KEY_BACKEND` | ✅ | — |
| `OTEL_INGEST_API_KEY_MOBILE` | ✅ | — |
| `OTEL_COLLECTOR_VERSION` | ✅ | `0.115.0` |
| `OTEL_MEMORY_LIMIT_MIB` | Optional | `512` |
| `OTEL_MEMORY_SPIKE_LIMIT_MIB` | Optional | `128` |
| `OTEL_TLS_CERT_FILE` | Optional | — |
| `OTEL_TLS_KEY_FILE` | Optional | — |

---

## 6. Volumes and config

| Path on VM | Purpose |
| --- | --- |
| `collector/config.yaml` | Collector config (bind-mounted read-only) |
| `collector/.env` | Runtime secrets (`chmod 600`) |
| Named volume `prometheus_data` | Reserved for Phase 4 |
| Named volume `loki_data` | Reserved for Phase 5 |
| Named volume `tempo_data` | Reserved for Phase 6 |
| Named volume `grafana_data` | Reserved for Phase 9 |

---

## 7. Logging strategy

| Layer | Approach |
| --- | --- |
| Collector process logs | JSON to stdout; captured by `docker compose logs` |
| Docker log driver | `json-file` — 50 MB × 3 files per container |
| Collector self-metrics | Scraped from `:8888`; ingested via `prometheus/self` receiver |
| Log level | `info` default; `debug` only during troubleshooting, then revert |

---

## 8. Upgrade strategy

1. Update `OTEL_COLLECTOR_VERSION` in `.env`.
2. `docker compose pull collector`.
3. `docker compose up -d --no-deps collector`.
4. Verify health (`curl http://127.0.0.1:13133/health`).
5. Review `docker compose logs collector --since=2m`.

---

## 9. Phase 3 validation

Full validation steps: [`collector/README.md`](../../../../collector/README.md) §Validation checklist.

| Check | Expected |
| --- | --- |
| `docker compose ps` | `ixora-otel-collector` — healthy |
| `curl :13133/health` | `{"status":"Server available",...}` |
| `curl :8888/metrics` | `otelcol_*` metric lines |
| Unauthenticated OTLP | HTTP 401 |
| Authenticated test span | HTTP 200 |
| Redaction spot check | `authorization` attribute absent from debug output |
| Collector stopped | `back_vibes` API still responds (Phase 11 QA test) |

---

## 10. Outstanding work for Phase 3.5

Phase 3 delivers a running, hardened Collector. Before Phase 4 (Prometheus):

| Item | Notes |
| --- | --- |
| **TLS on OTLP ports** | Reverse proxy (Caddy/nginx) — or uncomment `tls:` in `config.yaml` |
| **Firewall rules** | Apply allowlist from [security-review.md §5](security-review.md) on DO Droplet |
| **API key distribution** | Set `OTEL_INGEST_API_KEY_BACKEND` in App Platform secrets; mobile build secret |
| **Collector self-monitoring** | Phase 4+ wires `prometheus/self` → Prometheus; observe `otelcol_processor_dropped_data_points_total` |
| **Smoke test with telemetrygen** | `telemetrygen traces --otlp-insecure --otlp-endpoint=127.0.0.1:4317` |

---

## Related documents

| Document | Relationship |
| --- | --- |
| [`collector/config.yaml`](../../../../collector/config.yaml) | Production-ready Collector config |
| [`collector/docker-compose.yml`](../../../../collector/docker-compose.yml) | Container deployment |
| [`collector/.env.example`](../../../../collector/.env.example) | Secret template |
| [infrastructure-review.md](infrastructure-review.md) | VM topology and ports |
| [security-review.md](security-review.md) | Auth and redaction requirements |
| [collector-hardening-checklist.md](../../../operations/collector-hardening-checklist.md) | Deploy verification |
| [plan.md](plan.md) | Phase 4+ sequence |
