# Observability Foundation — Collector Validation Report

**Status:** Phase 3.5 complete — validation and hardening  
**Date:** 2026-07-05  
**Environment:** Local Docker validation (mirrors staging VM deployment model)  
**Collector image:** `otel/opentelemetry-collector-contrib:0.115.1`  
**References:** [collector-deployment.md](collector-deployment.md) · [collector-hardening-checklist.md](../../../operations/collector-hardening-checklist.md)

> **Scope:** Validate Collector operational, security, and failure behaviour **before** Phase 4 (Prometheus). No backends deployed.

---

## 1. Executive summary

Phase 3.5 executed a full validation and hardening cycle against the running Collector. **Six configuration defects** were found during validation and corrected in-place. After fixes, **all critical checklist items pass**. The Collector is **ready for Phase 4** with documented exceptions (TLS termination, firewall on VM, debug exporter removal).

| Category | Result |
| --- | --- |
| Configuration syntax | **PASS** |
| Startup / restart | **PASS** |
| Health endpoint | **PASS** |
| Authentication | **PASS** |
| Processors (config present + ordered) | **PASS** |
| Failure isolation | **PASS** |
| Security (secrets, ports, auth) | **PASS** (with noted exceptions) |
| Performance baseline | **PASS** |

---

## 2. Defects found and fixed (Phase 3.5)

| # | Defect | Impact | Fix |
| --- | --- | --- | --- |
| D1 | `auth:` at receiver level (invalid in 0.115.x) | Collector failed to start | Moved `auth.authenticator` under `protocols.grpc` / `protocols.http` |
| D2 | Image tag `0.115.0` not published on Docker Hub | `docker compose up` failed | Updated default to `0.115.1` |
| D3 | Invalid feature gate `-component.UseLocalHostAsDefaultHost` | Collector crash loop | Removed from `docker-compose.yml` command |
| D4 | Docker healthcheck used `wget` (not in distroless image) | Healthcheck always failed | Disabled in-container healthcheck; host-side curl documented |
| D5 | Internal endpoints bound to `127.0.0.1` inside container | Host port mapping to `:8888`, `:55679`, `:1777` unreachable | Bind `0.0.0.0` inside container; restrict via compose `127.0.0.1:` host binding |
| D6 | Obsolete `version:` key in compose file | Warning on every compose command | Removed |

**Files modified during hardening:** `collector/config.yaml`, `collector/docker-compose.yml`, `collector/.env.example`

---

## 3. Operational validation results

### 3.1 Configuration and startup

| Test | Expected | Result | Evidence |
| --- | --- | --- | --- |
| `otelcol-contrib validate --config` | Exit 0 | **PASS** | Config validates with env vars set |
| Invalid YAML config | Rejected at validate | **PASS** | `cannot resolve the configuration` |
| Missing `OTEL_INGEST_API_KEY_*` | Fail fast at startup | **PASS** | `no bearer token provided` |
| Container starts | Status `Up` | **PASS** | `docker compose ps` |
| Restart policy | `unless-stopped` | **PASS** | Verified in compose |
| Cold start to healthy | < 5 s | **PASS** | **1163 ms** to `/health` OK |
| Restart to healthy | < 10 s | **PASS** | **5866 ms** (includes compose restart overhead) |

### 3.2 Health and self-metrics

| Test | Expected | Result | Evidence |
| --- | --- | --- | --- |
| `GET :13133/health` | HTTP 200, `Server available` | **PASS** | JSON response |
| Health latency (10 samples) | < 10 ms avg | **PASS** | **~1 ms** average |
| `GET :8888/metrics` | `otelcol_*` lines | **PASS** (after D5 fix) | Prometheus-format metrics |
| zPages `:55679/debug/servicez` | HTML service list | **PASS** (after D5 fix) | Internal diagnostics |

### 3.3 Processors (configuration verification)

| Processor | Configured | Pipeline order | Result |
| --- | --- | --- | --- |
| `memory_limiter` | 512 MiB / 128 MiB spike | First in all pipelines | **PASS** |
| `resource` | `deployment.environment` upsert | After memory_limiter | **PASS** |
| `attributes/redact_secrets` | 18 forbidden keys | Before batch | **PASS** |
| `attributes/drop_high_cardinality` | 7 forbidden labels | Metrics pipeline | **PASS** |
| `transform/normalize_http` | Trace pipeline | Before sampler | **PASS** |
| `probabilistic_sampler` | 10% | Traces pipeline | **PASS** |
| `batch` | 1000 / 10s / 2000 max | Last before exporters | **PASS** |

Redaction spot check: span with `authorization` attribute accepted (HTTP 200) but attribute **not present** in debug exporter output.

---

## 4. Authentication validation

| Test | Expected | Result |
| --- | --- | --- |
| No `Authorization` header | HTTP 401 | **PASS** |
| Invalid bearer token | HTTP 401 | **PASS** |
| Valid backend key on `:4318` | HTTP 200 | **PASS** |
| Valid mobile key on `:4319` | HTTP 200 | **PASS** |
| Backend key on mobile port `:4319` | HTTP 401 | **PASS** |
| API keys not in container logs | No match | **PASS** |
| API keys not in committed config | `${env:VAR}` only | **PASS** |

---

## 5. Failure tests

| Test | Expected | Result |
| --- | --- | --- |
| Malformed JSON payload | HTTP 400; Collector stays up | **PASS** |
| Oversized payload (~5000 empty spans) | Rejected or accepted without crash | **PASS** (HTTP 200; survived) |
| Invalid config file | Startup rejected | **PASS** |
| Missing environment variables | Startup rejected | **PASS** |
| Container restart | Health restored | **PASS** |
| Health unavailable during restart | Brief gap; recovers | **PASS** |

---

## 6. Security verification

| Check | Result | Notes |
| --- | --- | --- |
| No secrets in git | **PASS** | `.env` gitignored; config uses `${env:}` |
| No secrets in logs | **PASS** | Grep for test keys — no match |
| No unnecessary ports | **PASS** | Only 4317–4319 public; ops ports on `127.0.0.1` |
| No localhost leakage (ops ports) | **PASS** | 8888, 13133, 1777, 55679 bound to host `127.0.0.1` only |
| Auth on all OTLP receivers | **PASS** | gRPC, HTTP backend, HTTP mobile |
| Separate backend/mobile keys | **PASS** | Cross-port rejection verified |
| Redaction processor active | **PASS** | Spot check passed |
| **Debug exporter active** | **EXCEPTION** | Intentional for Phase 3–3.5 validation; **remove in Phase 4** |
| **TLS on OTLP (plain HTTP locally)** | **DEFERRED** | TLS via reverse proxy on VM — not tested locally |
| **Firewall rules** | **DEFERRED** | Applied on DO Droplet at VM provisioning |

---

## 7. Performance summary

Measured on local Docker (4-core host, Collector limit 768 MiB):

| Metric | Value |
| --- | --- |
| Cold start to healthy | **1163 ms** |
| Container restart to healthy | **5866 ms** |
| Health endpoint latency (avg) | **~1 ms** |
| CPU idle | **0.13%** |
| Memory usage (idle) | **30.56 MiB / 768 MiB** (4%) |
| Memory RSS (from self-metrics) | **~158 MiB** (includes Go runtime) |

Baseline is well within [observability-operational-limits.md](../../../architecture/observability-operational-limits.md) expectations for a single Collector on a 4 vCPU / 8 GB VM.

---

## 8. Port exposure matrix (validated)

| Port | Host bind | Container | Purpose | Public? |
| --- | --- | --- | --- | --- |
| 4317 | `0.0.0.0` | 4317 | OTLP gRPC | Yes (TLS at proxy) |
| 4318 | `0.0.0.0` | 4318 | OTLP HTTP backend | Yes (TLS at proxy) |
| 4319 | `0.0.0.0` | 4319 | OTLP HTTP mobile | Yes (TLS at proxy) |
| 8888 | `127.0.0.1` | 8888 | Self-metrics | No |
| 13133 | `127.0.0.1` | 13133 | Health check | No |
| 1777 | `127.0.0.1` | 1777 | pprof | No |
| 55679 | `127.0.0.1` | 55679 | zPages | No |

---

## 9. Hardening checklist completion

See [collector-hardening-checklist.md](../../../operations/collector-hardening-checklist.md) §Phase 3.5 for item-by-item sign-off.

| Section | Items | Pass | Deferred | N/A |
| --- | ---: | ---: | ---: | ---: |
| Pre-deploy | 5 | 3 | 2 | 0 |
| Firewall | 5 | 0 | 5 | 0 |
| TLS | 4 | 0 | 3 | 1 |
| Authentication | 4 | 4 | 0 | 0 |
| Receivers | 4 | 4 | 0 | 0 |
| Processors | 5 | 5 | 0 | 0 |
| Exporters | 4 | 2 | 1 | 1 |
| Health | 4 | 4 | 0 | 0 |
| OS/service | 6 | 3 | 2 | 1 |
| Backups | 4 | 3 | 1 | 0 |
| Validation tests | 5 | 4 | 1 | 0 |

**Deferred items** require VM provisioning (firewall, TLS certs, flood test on DO Droplet).

---

## 10. Remaining recommendations (before / during Phase 4)

| Priority | Item | Owner | Phase |
| --- | --- | --- | --- |
| **P0** | Remove `debug` exporter; wire `prometheusremotewrite` | Infra | Phase 4 start |
| **P0** | Deploy TLS reverse proxy (Caddy) in front of 4317–4319 | Infra | VM deploy |
| **P0** | Apply DO firewall: allow 4317–4319 from App Platform egress only | Infra | VM deploy |
| **P1** | Replace deprecated `service.telemetry.metrics.address` with `readers` | Infra | Phase 4 |
| **P1** | Add `tail_sampling` for 100% error traces (ADR-031) | Infra | Phase 6 |
| **P2** | Host-side health monitoring script (cron/systemd timer) | Infra | Phase 10 |
| **P2** | VM snapshot policy | Infra | Phase 10 |

---

## Related documents

| Document | Role |
| --- | --- |
| [collector/config.yaml](../../../../collector/config.yaml) | Validated configuration |
| [collector/docker-compose.yml](../../../../collector/docker-compose.yml) | Validated deployment |
| [collector/README.md](../../../../collector/README.md) | Quick start + validation commands |
| [collector-deployment.md](collector-deployment.md) | Deployment spec |
| [telemetry-availability-policy.md](../../../architecture/telemetry-availability-policy.md) | Non-blocking export policy |
