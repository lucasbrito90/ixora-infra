# Observability Foundation MVP — implementation plan

**Status:** Phase 8.7 complete — D-03 Push Notifications Dashboard (Phases 7A Backend SDK Foundation, 7B.1 HTTP + Routing, 7B.2 Queue + Console, 7B.3 generic Scheduler, 7B.4.1–7B.4.9 Smart Home Business Telemetry + Foundation Baseline, 8.0 Dashboard Requirements, 8.1 Grafana Foundation, 8.2 D-07 Infrastructure Dashboard, 8.3 Application Dashboards, 8.4 D-02 Smart Home Business Dashboard, 8.5 Platform Overview Dashboard D-01, 8.6 Dashboard Integration & Operational Validation also complete)  
**Spec:** [`spec.md`](spec.md)  
**Feature ID:** `observability-foundation/mvp`

---

## Implementation summary

This capability delivers **platform-wide observability** through OpenTelemetry — a single Collector ingestion point fanning out to Prometheus, Loki, and Tempo, with Grafana for visualization.

**Strategy anchors:**

| Principle | Implementation |
| --- | --- |
| Collector-only ingestion | Apps never talk to Prometheus/Loki/Tempo ([ADR-028](../../../decisions/ADR-028-observability-platform.md)) |
| OTel standard | SDK in apps; Collector processors for redaction/sampling |
| Failure isolation | Telemetry export best-effort; business logic unaffected |
| Security first | Redaction at app + Collector ([ADR-030](../../../decisions/ADR-030-observability-security-and-privacy.md)) |
| Predictable cost | Retention caps + sampling ([ADR-031](../../../decisions/ADR-031-retention-storage-and-cost-control.md)) |
| Staging first | Single DO VM; no production until Phase 10 sign-off |

**Git Flow:** All work on **`feature/*`** from **`develop`**. Promote to **`staging`** when observability VM and app SDKs are ready for homologation.

> **Naming mandate:** All implementation phases (2–11.5) **must** follow [`telemetry-naming-convention.md`](../../../architecture/telemetry-naming-convention.md) for services, metrics, spans, logs, events, labels, dashboards, and alerts. No ad-hoc names in SDK instrumentation, Collector configs, or Grafana artifacts.

> **Metrics mandate:** Phases **7A** and **7B** (backend instrumentation) **must** follow [`metrics-philosophy.md`](../../../architecture/metrics-philosophy.md) before adding or changing product metrics.

> **Logs mandate:** Phases **7** and **8** (application instrumentation) **must** follow [`logs-philosophy.md`](../../../architecture/logs-philosophy.md) before adding or changing product logs.

> **Traces mandate:** Phases **7** and **8** (application instrumentation) **must** follow [`traces-philosophy.md`](../../../architecture/traces-philosophy.md) before adding or changing product spans.

---

## Current state

| Area | State |
| --- | --- |
| **App Platform runtime logs** | ✅ Shipped — stderr JSON on DO |
| **Laravel structured logs** | ✅ Shipped — `Log::` with context |
| **Product observability (automation)** | ✅ Shipped — execution rows + worker logs ([ADR-024](../../../decisions/ADR-024-automation-notifications-and-observability.md)) |
| **OpenTelemetry Collector** | ✅ Shipped — Phases 3–6 |
| **Prometheus / Loki / Tempo** | ✅ Shipped — Phases 4–6 |
| **Grafana** | ✅ Foundation deployed — Phase 8.1; ✅ D-07 Infrastructure dashboard — Phase 8.2; ✅ D-04 Queue Workers + D-05 HTTP API + D-06 Scheduler — Phase 8.3; ✅ D-02 Smart Home Business — Phase 8.4; ✅ D-01 Platform Overview (32 panels, `ixora-platform`, 42/42 validation checks) — Phase 8.5; ✅ Dashboard Integration — bidirectional navigation mesh (30 links), Overview Dashboard Principles, 4 investigation workflows, 48/48 validation checks — Phase 8.6; ✅ D-03 Push Notifications (23 panels, `ixora-push`, queue-layer telemetry, 57/57 validation checks, 7-dashboard mesh 42 links) — Phase 8.7 |
| **OTel SDK (backend)** | ✅ Foundation shipped — Phase 7A (`back_vibes`); ✅ HTTP + Routing shipped — Phase 7B.1; ✅ Queue + Console shipped — Phase 7B.2; ✅ generic Scheduler shipped — Phase 7B.3; ✅ Business Telemetry domain execution review (discovery only) — Phase 7B.4.1; ✅ Smart Home dispatch boundary (`smart_home.dispatch` span) — Phase 7B.4.2; ✅ Smart Home Action Execution boundary (`smart_home.action` span) — Phase 7B.4.3; ✅ Smart Home Provider Boundary (`smart_home.provider` span) — Phase 7B.4.4; ✅ Business Failure Semantics (failure taxonomy + Span Status policy, documentation-only with one narrowly-scoped correction) — Phase 7B.4.5; ✅ Business Metrics (`ixora.smart_home.dispatch.total`, `ixora.smart_home.action.total`/`.duration`) — Phase 7B.4.6; ✅ Business Logging (L-2 resolution + existing log sanitization, no new log statements) — Phase 7B.4.7; ✅ Business Telemetry Validation & Architecture Review (architecture validated as internally consistent + production-ready, 4 tech debt items documented, no runtime changes) — Phase 7B.4.8; ✅ Business Telemetry Foundation Baseline (platform-wide standard, documentation-only) — Phase 7B.4.9; ✅ Dashboard Requirements Review (7 dashboards defined, 6 investigation workflows, Phase 9 checklist, documentation-only) — Phase 8.0; ✅ Grafana Foundation & Provisioning (Grafana active, 3 datasources provisioned, stable UIDs, 4 folder providers, 12/12 validation checks, Tempo/Loki config fixes) — Phase 8.1 |bt items documented, no runtime changes) — Phase 7B.4.8; ✅ Business Telemetry Foundation Baseline (platform-wide standard generalized from Smart Home reference, documentation-only) — Phase 7B.4.9; remaining domain instrumentation pending (Phases 7B.5–7B.6) |
| **OTel SDK (mobile)** | ❌ Not integrated |
| **ADRs 028–031** | ✅ Accepted — Phase 1 complete |

---

## Phase overview

```
Phase 1    ──► ADRs + Spec (complete)
Phase 1.5  ──► Telemetry Naming Convention (complete)
Phase 2    ──► Infrastructure review
Phase 2.5  ──► Security review
Phase 3    ──► Collector deployment
Phase 3.5  ──► Collector validation & hardening
Phase 3.75 ──► Metrics Philosophy (complete)
Phase 4    ──► Prometheus
Phase 5    ──► Loki
Phase 5.5  ──► Logs Philosophy (complete)
Phase 6    ──► Tempo (complete)
Phase 6.5  ──► Traces Philosophy (complete)
Phase 7A     ──► Backend SDK Foundation (back_vibes) (complete)
Phase 7B.1   ──► HTTP + Routing (back_vibes) (complete)
Phase 7B.2   ──► Queue + Console (back_vibes) (complete)
Phase 7B.3   ──► Generic Scheduler (back_vibes) (complete)
Phase 7B.4.1 ──► Business Telemetry — Domain Execution Review (ixora-infra) (complete, discovery only)
Phase 7B.4.2 ──► Smart Home Dispatch Boundary (back_vibes) (complete)
Phase 7B.4.3 ──► Smart Home Action Execution (back_vibes) (complete)
Phase 7B.4.4 ──► Smart Home Provider Boundary (back_vibes) (complete)
Phase 7B.4.5 ──► Business Failure Semantics (back_vibes) (complete)
Phase 7B.4.6 ──► Business Metrics (back_vibes) (complete)
Phase 7B.5   ──► Push Notifications (back_vibes)
Phase 7B.6   ──► External Providers (back_vibes)
Phase 8      ──► Frontend SDK (front_vibes)
Phase 9    ──► Grafana dashboards
Phase 9.5  ──► Telemetry Decision Guide + Observability Playbook (complete)
Phase 10   ──► Operational readiness
Phase 11   ──► QA
Phase 11.5 ──► Appium mobile telemetry validation
Release    ──► Tag + release notes
```

Phases are intentionally small. Infrastructure (2–6) precedes application SDKs (7–8) so staging apps have a working Collector endpoint before instrumentation ships.

---

## Phase 1 — ADRs + Spec

**Complete.**

### Deliverables

| Item | Output |
| --- | --- |
| Feature spec | [`spec.md`](spec.md) |
| Implementation plan | [`plan.md`](plan.md) |
| Task checklist | [`tasks.md`](tasks.md) |
| **ADR-028** | [`ADR-028-observability-platform.md`](../../../decisions/ADR-028-observability-platform.md) |
| **ADR-029** | [`ADR-029-telemetry-data-model.md`](../../../decisions/ADR-029-telemetry-data-model.md) |
| **ADR-030** | [`ADR-030-observability-security-and-privacy.md`](../../../decisions/ADR-030-observability-security-and-privacy.md) |
| **ADR-031** | [`ADR-031-retention-storage-and-cost-control.md`](../../../decisions/ADR-031-retention-storage-and-cost-control.md) |
| Docs index | [`README.md`](../../../README.md) |

### Exit criteria

- ADRs accepted; spec published; **no runtime code** in this phase.

---

## Phase 2 — Infrastructure review

**Goal:** Size and network the observability VM before deployment.

### Tasks

- Document DO VM spec (CPU, RAM, disk) against ADR-031 budgets.
- Define firewall: OTLP ingress from App Platform + mobile staging only.
- Document DNS/TLS for Collector endpoint (`otel-staging.ixora-app.app` or internal IP).
- Review egress from App Platform workers to observability VM.
- Confirm no OpenTofu changes required in Phase 2 — review only (IaC in Phase 3+ if approved).

### Exit criteria

- Written infra review note published in `tasks.md` or inline doc.
- VM sizing signed off.

---

## Phase 2.5 — Security review

**Goal:** Validate redaction, access control, and secrets handling before Collector accepts traffic.

### Tasks

- Review ADR-030 against sample Laravel logs and push/Smart Home flows.
- Define Collector redaction processor config (documentation).
- Define Grafana auth model (basic auth / OAuth — decision doc).
- Confirm no observability credentials in git.
- Threat model: public OTLP endpoint abuse → API key or mTLS decision.

### Exit criteria

- Security review checklist signed off in `tasks.md`.

---

## Phase 3 — Collector deployment

**Goal:** Running OpenTelemetry Collector on DO VM accepting OTLP.

### Deliverables (Phase 3 — config complete)

| Item | Output |
| --- | --- |
| Collector configuration | [`collector/config.yaml`](../../../../collector/config.yaml) |
| Docker Compose | [`collector/docker-compose.yml`](../../../../collector/docker-compose.yml) |
| Environment template | [`collector/.env.example`](../../../../collector/.env.example) |
| Collector README | [`collector/README.md`](../../../../collector/README.md) |
| Deployment spec | [`collector-deployment.md`](collector-deployment.md) |

### Exit criteria

- Collector health endpoint returns OK (`curl :13133/health`).
- Test span from `telemetrygen` or curl reaches Collector (authenticated) — no backends required yet.
- Unauthenticated OTLP returns 401.
- Debug exporter shows received spans in `docker compose logs`.

---

## Phase 3.5 — Collector validation & hardening

**Goal:** Validate every operational and security aspect of the running Collector before backends are introduced.

### Deliverables (Phase 3.5 — complete)

| Item | Output |
| --- | --- |
| Validation report | [`collector-validation-report.md`](collector-validation-report.md) |
| Hardening sign-off | [`collector-hardening-checklist.md §13`](../../../operations/collector-hardening-checklist.md) |
| Config fixes | `collector/config.yaml`, `docker-compose.yml`, `.env.example` |

### Validation scope

- Configuration syntax, startup, restart, health endpoint
- Authentication matrix (401/200), failure tests (malformed, oversized, missing env)
- Processor audit (memory_limiter, batch, redaction, sampling)
- Security (secrets, ports, debug exporter exception)
- Performance baseline (startup time, memory, health latency)

### Exit criteria

- All testable hardening checklist items pass.
- Six config defects found during validation are fixed.
- Collector survives restart and rejects invalid requests.
- Only expected ports exposed (4317–4319 public; ops on `127.0.0.1`).
- **Ready for Phase 4** after removing `debug` exporter.

### Deferred to VM deploy

- Firewall rules, TLS termination, flood test, app isolation test (11.4)

---

## Phase 3.75 — Metrics Philosophy

**Goal:** Define **how engineers think about metrics** — a platform-wide architectural guide required before backend instrumentation (Phases 7A and 7B).

**Complete (documentation only).**

### Deliverables

| Item | Output |
| --- | --- |
| Metrics philosophy guide | [`metrics-philosophy.md`](../../../architecture/metrics-philosophy.md) |

### Exit criteria

- Document published with all 12 sections (purpose, principles, when/when-not, types, labels, signal relationships, lifecycle, checklist, anti-patterns, Ixora examples, cross-references).
- README, plan, tasks, and spec updated.
- Consistent with ADRs 028–031, naming convention, decision guide, security review, and collector validation.
- **No runtime code**, SDK, Collector, Prometheus, Grafana, or infrastructure changes.

> Backend instrumentation PRs (Phases 7A/7B) must follow [metrics-philosophy.md](../../../architecture/metrics-philosophy.md) for metric design and [telemetry-naming-convention.md](../../../architecture/telemetry-naming-convention.md) for names.

---

## Phase 4 — Prometheus

**Goal:** Metrics backend with 30-day retention.

**Complete.**

### Deliverables

| Item | Output |
| --- | --- |
| Prometheus configuration | [`collector/prometheus/prometheus.yml`](../../../../collector/prometheus/prometheus.yml) |
| Prometheus service (docker-compose) | [`collector/docker-compose.yml`](../../../../collector/docker-compose.yml) |
| Collector config updated | [`collector/config.yaml`](../../../../collector/config.yaml) — `prometheusremotewrite` active, `debug` removed from metrics |
| Environment template updated | [`collector/.env.example`](../../../../collector/.env.example) |
| Deployment spec | [`prometheus-deployment.md`](prometheus-deployment.md) |

### Exit criteria

- ✅ Collector exports metrics to Prometheus via `prometheusremotewrite`.
- ✅ Prometheus stores `otelcol_*` series (Collector self-metrics via `prometheus/self` receiver → remote write).
- ✅ Prometheus self-metrics (`prometheus_tsdb_head_series` etc.) visible.
- ✅ Retention flag `30d` confirmed via API.
- ✅ `debug` exporter removed from metrics pipeline.
- ✅ Prometheus bound to `127.0.0.1:9090` only — not publicly accessible.
- ✅ No application scrape targets in `prometheus.yml`.
- ✅ Persistence validated: data survives container restart (named volume).
- ✅ No application instrumentation, no Grafana, no Loki, no Tempo, no SDK changes.

---

## Phase 5 — Loki

**Goal:** Log aggregation with 14-day retention.

**Complete.**

### Deliverables

| Item | Output |
| --- | --- |
| Loki configuration | [`collector/loki/loki.yaml`](../../../../collector/loki/loki.yaml) |
| Loki service (docker-compose) | [`collector/docker-compose.yml`](../../../../collector/docker-compose.yml) |
| Collector config updated | [`collector/config.yaml`](../../../../collector/config.yaml) — `loki` exporter active, `debug` removed from logs pipeline |
| Environment template updated | [`collector/.env.example`](../../../../collector/.env.example) |
| Deployment spec | [`loki-deployment.md`](loki-deployment.md) |

### Exit criteria

- ✅ Loki service running and healthy (`/ready` returns 200).
- ✅ Collector exports logs to Loki via `loki` exporter.
- ✅ `debug` exporter removed from logs pipeline.
- ✅ Logs queryable via LogQL at `http://127.0.0.1:3100`.
- ✅ Retention period `336h` (14 days) configured in `loki.yaml`.
- ✅ Compactor retention enforcement enabled.
- ✅ Loki bound to `127.0.0.1:3100` only — not publicly accessible.
- ✅ No application writes to Loki directly (Collector is sole writer).
- ✅ All redaction applied before Loki push (`attributes/redact_secrets`).
- ✅ Persistence validated: log data survives container restart (named volume + WAL).
- ✅ No application instrumentation, no Grafana, no Tempo, no SDK changes.
- ✅ Metrics pipeline (Prometheus) unchanged.

---

## Phase 5.5 — Logs Philosophy

**Goal:** Define **how engineers think about logs** — a platform-wide architectural guide required before application instrumentation (Phases 7 and 8).

**Complete (documentation only).**

### Deliverables

| Item | Output |
| --- | --- |
| Logs philosophy guide | [`logs-philosophy.md`](../../../architecture/logs-philosophy.md) |

### Exit criteria

- Document published with all 14 sections (purpose, principles, when/when-not, levels, attributes, forbidden info, structured logging, platform relationship, metrics/traces relationships, examples, anti-patterns, review checklist, cross-references).
- README, plan, tasks, and spec updated.
- Consistent with ADRs 028–031, metrics philosophy, naming convention, decision guide, security review, collector validation, and loki deployment.
- **No runtime code**, SDK, Collector, Loki, Prometheus, Tempo, Grafana, or infrastructure changes.

> Application instrumentation PRs (Phases 7 and 8) must follow [logs-philosophy.md](../../../architecture/logs-philosophy.md) for log design and [telemetry-naming-convention.md](../../../architecture/telemetry-naming-convention.md) for field names.

---

## Phase 6 — Tempo

**Goal:** Trace backend with 7-day retention and sampling.

**Complete.**

### Deliverables

| Item | Output |
| --- | --- |
| Tempo configuration | [`collector/tempo/tempo.yaml`](../../../../collector/tempo/tempo.yaml) |
| Tempo service (docker-compose) | [`collector/docker-compose.yml`](../../../../collector/docker-compose.yml) |
| Collector config updated | [`collector/config.yaml`](../../../../collector/config.yaml) — `otlp/tempo` active, `debug` removed from traces pipeline |
| Environment template updated | [`collector/.env.example`](../../../../collector/.env.example) |
| Deployment spec | [`tempo-deployment.md`](tempo-deployment.md) |

### Exit criteria

- ✅ Tempo service running and healthy (`/ready` returns 200).
- ✅ Collector exports traces to Tempo via `otlp/tempo` exporter.
- ✅ `debug` exporter **fully removed** from all pipelines (metrics Phase 4, logs Phase 5, traces Phase 6).
- ✅ Test trace searchable by `trace_id` via Tempo HTTP API.
- ✅ Retention period `168h` (7 days) configured via compactor.
- ✅ Tempo bound to `127.0.0.1:3200` (HTTP) and `127.0.0.1:4317` (OTLP gRPC) — not publicly accessible.
- ✅ No application writes to Tempo directly (Collector is sole writer).
- ✅ All redaction applied before Tempo push (`attributes/redact_secrets`).
- ✅ Persistence validated: trace data survives container restart (named volume + WAL).
- ✅ Sampling: `probabilistic_sampler` (10%) retained; tail sampling documented as Phase 7+ evolution.
- ✅ Metrics pipeline (Prometheus) and logs pipeline (Loki) unchanged.
- ✅ No application instrumentation, no Grafana, no SDK changes.

---

## Phase 6.5 — Traces Philosophy

**Goal:** Define **how engineers think about traces** — a platform-wide architectural guide required before application instrumentation (Phases 7 and 8).

**Complete (documentation only).**

### Deliverables

| Item | Output |
| --- | --- |
| Traces philosophy guide | [`traces-philosophy.md`](../../../architecture/traces-philosophy.md) |

### Exit criteria

- Document published with all 14 sections (purpose, principles, when/when-not, hierarchy, attributes, events, exceptions, sampling, metrics/traces/logs relationship, examples, anti-patterns, review checklist, cross-references).
- README, plan, tasks, and spec updated.
- Consistent with ADRs 028–031, metrics philosophy, logs philosophy, naming convention, decision guide, observability playbook, security review, collector validation, and tempo deployment.
- **No runtime code**, SDK, Collector, Tempo, Prometheus, Loki, Grafana, or infrastructure changes.

> Application instrumentation PRs (Phases 7 and 8) must follow [traces-philosophy.md](../../../architecture/traces-philosophy.md) for span design and [telemetry-naming-convention.md](../../../architecture/telemetry-naming-convention.md) for names.

---

## Phase 7A — Backend SDK Foundation

**Goal:** Introduce the OpenTelemetry PHP SDK into `back_vibes` behind a Telemetry Abstraction Layer, with generic auto-instrumentation and log correlation only — **no** domain instrumentation.

**Prerequisite:** [metrics-philosophy.md](../../../architecture/metrics-philosophy.md) (Phase 3.75) · [logs-philosophy.md](../../../architecture/logs-philosophy.md) (Phase 5.5) · [traces-philosophy.md](../../../architecture/traces-philosophy.md) (Phase 6.5).

**Complete.**

### Deliverables

| Item | Output |
| --- | --- |
| SDK evaluation + chosen packages | [`backend-sdk-foundation.md §2`](backend-sdk-foundation.md) |
| Telemetry Abstraction Layer (`app/Telemetry/`) | [`backend-sdk-foundation.md §3`](backend-sdk-foundation.md) · `back_vibes/app/Telemetry/` |
| `TelemetryServiceProvider` + `config/telemetry.php` | `back_vibes/app/Telemetry/Providers/TelemetryServiceProvider.php` · `back_vibes/config/telemetry.php` |
| Environment template | `back_vibes/.env.example` §"Observability — OpenTelemetry" |
| Tests (bootstrap, config, resolution, log correlation, failure policy, dependency rule) | `back_vibes/tests/{Unit,Feature}/Telemetry/` |
| Spec doc | [`backend-sdk-foundation.md`](backend-sdk-foundation.md) |

### Scope

- Official OpenTelemetry PHP SDK (`open-telemetry/{api,sdk,sem-conv,exporter-otlp}`) + official Laravel/Guzzle/PDO auto-instrumentation.
- Telemetry Abstraction Layer: Contracts, OpenTelemetry implementation (isolated), No-op implementation, `TelemetryServiceProvider`.
- Auto-instrument HTTP requests, Laravel routing, exceptions, queue workers, console commands, HTTP client, database (Eloquent + PDO). Redis not enabled — no official package exists.
- `trace_id` / `span_id` injected into Laravel log context via a Monolog processor tap — messages never altered.
- Configuration entirely via env: `OTEL_SERVICE_NAME`, `OTEL_SERVICE_VERSION`, `OTEL_EXPORTER_OTLP_ENDPOINT`, `OTEL_EXPORTER_OTLP_HEADERS`, `OTEL_EXPORTER_OTLP_PROTOCOL`, `OTEL_RESOURCE_ATTRIBUTES`, `OTEL_TRACES_SAMPLER(_ARG)`, `OTEL_PHP_AUTOLOAD_ENABLED`, `APP_ENV`, `APP_VERSION`.
- **No manual spans, no custom metrics, no custom logs, no Scheduler/Smart Home/Push/Marketplace/AI instrumentation.**

### Exit criteria

- ✅ SDK installed; Telemetry module + Contracts + isolated OpenTelemetry implementation created.
- ✅ Dependency Rule respected and enforced by an automated test — no `OpenTelemetry\*` import outside `app/Telemetry/OpenTelemetry`.
- ✅ Configuration and resource attributes documented and env-driven; no hardcoded URLs.
- ✅ Generic auto-instrumentation enabled (HTTP, routing, console, queue, DB); logging correlation enabled.
- ✅ Failure policy validated — Collector unavailable never fails a request, job, or command (empirical + automated test evidence in `backend-sdk-foundation.md §4.3, §7`).
- ✅ No business logic, Scheduler, Smart Home, Push, database schema, or existing provider/job/command/service/repository changed.
- ✅ 737/737 `back_vibes` tests pass (27 new).
- **Ready for Phase 7B** — Backend Domain Instrumentation, using only the Telemetry Contracts from this phase.

**Branch:** `feature/observability-backend-sdk-foundation`

---

## Phase 7B — Backend Domain Instrumentation

**Goal:** Instrument Ixora's HTTP boundary and business domains (Queue, Console, Scheduler, Smart Home, Push, external providers) through the Phase 7A Telemetry Contracts — span enrichment/manual spans, custom metrics, domain logs. Broken into six narrow subphases so each domain boundary is reviewed and instrumented independently.

**Prerequisite:** Phase 7A (Backend SDK Foundation) · [metrics-philosophy.md](../../../architecture/metrics-philosophy.md) · [logs-philosophy.md](../../../architecture/logs-philosophy.md) · [traces-philosophy.md](../../../architecture/traces-philosophy.md) · [telemetry-decision-guide.md](../../../architecture/telemetry-decision-guide.md).

**Common rule across all 7B.x subphases:** zero changes to `app/Telemetry/Contracts/*` beyond a real, documented, additive blocker (see Phase 7B.1's `Tracer::activeSpan()`) — subsequent subphases consume the contracts as they exist after the prior subphase, never redesigning them.

---

### Phase 7B.1 — HTTP + Routing (`back_vibes`)

**Complete.**

**Goal:** Instrument only the HTTP and routing boundary — enrich the existing auto-instrumented HTTP server span, add the minimum `ixora.http.server.*` metrics, and align error logs — without touching Queue, Console, Scheduler, Smart Home, Push, or external providers.

#### Deliverables

| Item | Output |
| --- | --- |
| Auto-instrumentation review (root span naming, route/status attributes, exception recording, 404/405/401/422 behavior) | [`backend-http-routing-instrumentation.md §2`](backend-http-routing-instrumentation.md) |
| `app/Telemetry/Http/` (`HttpRequestTelemetry`, `HttpRouteNormalizer`, `HttpOutcome`, `HttpExceptionStatus`) | [`backend-http-routing-instrumentation.md §3`](backend-http-routing-instrumentation.md) · `back_vibes/app/Telemetry/Http/` |
| `Tracer::activeSpan()` — one documented, additive contract method | [`backend-http-routing-instrumentation.md §4`](backend-http-routing-instrumentation.md) · `back_vibes/app/Telemetry/Contracts/Tracer.php` |
| `App\Http\Middleware\HttpTelemetryMiddleware` (global, appended) | [`backend-http-routing-instrumentation.md §5`](backend-http-routing-instrumentation.md) · `back_vibes/app/Http/Middleware/HttpTelemetryMiddleware.php` |
| `ixora.http.server.request.total` (Counter) + `ixora.http.server.duration` (Histogram, ms) | [`backend-http-routing-instrumentation.md §6`](backend-http-routing-instrumentation.md) |
| Span enrichment (`http.request.method`, `http.route`, `http.response.status_code`, `ixora.http.outcome`, `url.scheme`, `server.address`) | [`backend-http-routing-instrumentation.md §7`](backend-http-routing-instrumentation.md) |
| `App\Telemetry\Logging\HttpErrorContextLogTap` | [`backend-http-routing-instrumentation.md §8`](backend-http-routing-instrumentation.md) · `back_vibes/app/Telemetry/Logging/HttpErrorContextLogTap.php` |
| `Log::build()` limitation documented | [`backend-sdk-foundation.md §8.5`](backend-sdk-foundation.md#85-known-limitation-logbuild-on-demand-channels-are-not-tapped) |
| Tests (10 scenarios: success, 404, 405, validation, auth failure, server exception, Collector unavailable, cardinality safety, dependency rule, no double-counting) | `back_vibes/tests/{Unit,Feature}/Telemetry/Http/` |
| Spec doc | [`backend-http-routing-instrumentation.md`](backend-http-routing-instrumentation.md) |

#### Scope

- Enrich the existing auto-instrumented HTTP server span (no second root span) via one new additive `Tracer::activeSpan()` method.
- Two new `ixora.*` metrics only — no duplication of anything auto-instrumentation already emits (it emits no HTTP server metrics).
- Stable, bounded route templates (`HttpRouteNormalizer`) and outcome classification (`HttpOutcome`) — never dynamic IDs, query strings, or raw status codes as labels.
- One global middleware (`HttpTelemetryMiddleware`, appended — innermost global middleware) as the lifecycle integration point; telemetry failures swallowed by `HttpRequestTelemetry::safely()`.
- Error log enrichment only (`HttpErrorContextLogTap`) — no routine success logs.
- **No Queue, Console, Scheduler, Smart Home, Push, or external-provider instrumentation.**

#### Exit criteria

- ✅ Existing auto-instrumented span reused, not duplicated (`backend-http-routing-instrumentation.md §2, §4`).
- ✅ Both metrics recorded exactly once per request; no forbidden labels (verified by cardinality-safety test).
- ✅ HTTP/exception behavior byte-for-byte unchanged — full existing suite green with the middleware active.
- ✅ `trace_id`/`span_id` correlation still works on HTTP logs (Phase 7A tap unchanged, unaffected by the new tap).
- ✅ Telemetry failure isolation proven with a deliberately-throwing fake `Tracer`.
- ✅ Dependency Rule respected — no `OpenTelemetry\*` import outside `app/Telemetry/OpenTelemetry`, scoped test added for `app/Telemetry/Http` specifically.
- ✅ 785/785 `back_vibes` tests pass (48 new); `pint --test` passes.
- **Ready for Phase 7B.2** — Queue + Console, using the same Telemetry Contracts (`activeSpan()` included).

**Branch:** `feature/observability-http-routing-instrumentation`

---

### Phase 7B.2 — Queue + Console (`back_vibes`)

**Complete.**

**Goal:** Instrument only the generic queue-execution and console/Artisan-command boundary — enrich the existing auto-instrumented queue/console spans where they exist, add the minimum `ixora.queue.job.*` / `ixora.console.command.*` metrics, and align error logs — without touching Scheduler, Smart Home, Push, or external providers.

#### Deliverables

| Item | Output |
| --- | --- |
| Auto-instrumentation review (producer/consumer span behavior, context propagation, sync queue, exit-code/exception recording, CLI-SAPI gating) | [`backend-queue-console-instrumentation.md §2–§3`](backend-queue-console-instrumentation.md) |
| `app/Telemetry/Queue/` (`QueueExecutionTelemetry`, `QueueJobNormalizer`, `QueueOutcome`, `QueueContext`) | [`backend-queue-console-instrumentation.md §4`](backend-queue-console-instrumentation.md) · `back_vibes/app/Telemetry/Queue/` |
| `app/Telemetry/Console/` (`ConsoleCommandTelemetry`, `ConsoleCommandNormalizer`, `ConsoleOutcome`, `ConsoleContext`) | [`backend-queue-console-instrumentation.md §4`](backend-queue-console-instrumentation.md) · `back_vibes/app/Telemetry/Console/` |
| `ixora.queue.job.total` / `ixora.queue.job.duration` / `ixora.queue.job.active` (Counter/Histogram/UpDownCounter) + `ixora.console.command.total` / `ixora.console.command.duration` | [`backend-queue-console-instrumentation.md §5`](backend-queue-console-instrumentation.md) |
| Span enrichment (`ixora.queue.*` on the auto-instrumented consumer/sync span; `ixora.console.*` best-effort) | [`backend-queue-console-instrumentation.md §6`](backend-queue-console-instrumentation.md) |
| Queue/console lifecycle listeners wired in `TelemetryServiceProvider` (no new middleware/command classes) | [`backend-queue-console-instrumentation.md §7`](backend-queue-console-instrumentation.md) · `back_vibes/app/Telemetry/Providers/TelemetryServiceProvider.php` |
| `App\Telemetry\Logging\{QueueErrorContextLogTap,ConsoleErrorContextLogTap}` | [`backend-queue-console-instrumentation.md §9`](backend-queue-console-instrumentation.md) · `back_vibes/app/Telemetry/Logging/` |
| Tests (16 scenarios: success, failure, retry/release, sync queue, unknown metadata, cardinality safety, telemetry failure, long-running worker safety, arguments/options safety, log separation, dependency rule, no double-counting) | `back_vibes/tests/{Unit,Feature}/Telemetry/{Queue,Console,QueueConsole}/` |
| Spec doc | [`backend-queue-console-instrumentation.md`](backend-queue-console-instrumentation.md) |

#### Scope

- Enrich the existing auto-instrumented queue consumer/sync span (no second root span); best-effort console span enrichment given the documented `CommandStarting`/`CommandFinished` timing gap (§6).
- Four new `ixora.*` metrics only — no duplication of anything auto-instrumentation already emits (it emits no queue/console metrics).
- Stable, bounded job/command names (`QueueJobNormalizer`/`ConsoleCommandNormalizer`) and outcome classification (`QueueOutcome`/`ConsoleOutcome`) — never job IDs, UUIDs, payloads, `argv`, or argument/option values as labels.
- Laravel queue/console events (not new middleware or wrapped command classes) as the lifecycle integration point; telemetry failures swallowed by each service's own `safely()`.
- Error log enrichment only (`QueueErrorContextLogTap`/`ConsoleErrorContextLogTap`) — no routine success logs.
- **No Scheduler, Smart Home, Push, or external-provider instrumentation.**

#### Exit criteria

- ✅ Existing auto-instrumented queue span reused, not duplicated; console per-command span behavior documented (`backend-queue-console-instrumentation.md §2, §3, §6`).
- ✅ Every metric recorded exactly once per job attempt / command execution; no forbidden labels (verified by cardinality-safety and arguments/options-safety tests).
- ✅ Queue/command behavior byte-for-byte unchanged — full existing suite green with the listeners active.
- ✅ `trace_id`/`span_id` correlation still works on queue/console logs (Phase 7A tap unchanged, unaffected by the two new taps); HTTP/queue/console log context proven mutually isolated.
- ✅ Telemetry failure isolation proven with a deliberately-throwing fake `Tracer`.
- ✅ Long-running worker safety proven — lifecycle stack and active-jobs gauge both return to empty/zero after every job, including a failure and a synchronously-nested job.
- ✅ Dependency Rule respected — no `OpenTelemetry\*` import outside `app/Telemetry/OpenTelemetry`, scoped test added for `app/Telemetry/Queue`, `app/Telemetry/Console`, and both new log taps specifically.
- ✅ 836/836 `back_vibes` tests pass (51 new); `pint --test` passes.
- **Ready for Phase 7B.3** — Scheduler, using the same Telemetry Contracts.

**Branch:** `feature/observability-queue-console-instrumentation`

---

### Phase 7B.3 — Generic Scheduler (`back_vibes`)

**Complete.**

**Goal:** Instrument only the generic Laravel Scheduler event-execution boundary (Level 1) — create the one required boundary span (no existing span covers it), add the minimum `ixora.scheduler.event.*` metrics, and align error logs — without instrumenting Ixora Domain Scheduling (Level 2: Vibe scheduling, `Schedule` model orchestration, Smart Home, Push, or provider execution), per [ADR-024](../../../decisions/ADR-024-automation-notifications-and-observability.md).

#### Deliverables

| Item | Output |
| --- | --- |
| Scheduler auto-instrumentation + Laravel lifecycle review (no official span exists for a scheduled-event boundary; five dispatched events; command-event process boundary; callback in-process behavior; double-fire finding) | [`backend-generic-scheduler-instrumentation.md §2`](backend-generic-scheduler-instrumentation.md) |
| `app/Telemetry/Scheduler/` (`SchedulerExecutionTelemetry`, `SchedulerEventNormalizer`, `SchedulerOutcome`, `SchedulerContext`, `SchedulerEventType`, `SchedulerExecutionMode`) | [`backend-generic-scheduler-instrumentation.md §5`](backend-generic-scheduler-instrumentation.md) · `back_vibes/app/Telemetry/Scheduler/` |
| `ixora.scheduler.event.total` / `ixora.scheduler.event.duration` (Counter/Histogram) — `ixora.scheduler.event.active` deliberately not added (lifecycle asymmetry) | [`backend-generic-scheduler-instrumentation.md §6`](backend-generic-scheduler-instrumentation.md) |
| Scheduler boundary span (`Tracer::startSpan()`, Strategy B — first `startSpan()` caller in this Telemetry Abstraction Layer) named `scheduler.event {event_name}` | [`backend-generic-scheduler-instrumentation.md §9`](backend-generic-scheduler-instrumentation.md) |
| Scheduler lifecycle listeners wired in `TelemetryServiceProvider` (`ScheduledTaskStarting`/`Finished`/`Failed`/`Skipped`/`ScheduledBackgroundTaskFinished`) | [`backend-generic-scheduler-instrumentation.md §7`](backend-generic-scheduler-instrumentation.md) · `back_vibes/app/Telemetry/Providers/TelemetryServiceProvider.php` |
| `App\Telemetry\Logging\SchedulerErrorContextLogTap` | [`backend-generic-scheduler-instrumentation.md §11`](backend-generic-scheduler-instrumentation.md) · `back_vibes/app/Telemetry/Logging/` |
| `RecordingTracer::startSpan()` + `TelemetryRecorder::recordStartSpan()`/`$startSpanCalls` test-fake support (new span-creation assertions) | `back_vibes/tests/Support/Telemetry/{RecordingTracer.php,TelemetryRecorder.php}` |
| Tests (18 scenarios: success, failure, closure/callback naming, scheduled job/command boundary separation, manual command isolation, `schedule:run`/`schedule:work` independence, skip, overlap prevention, background, unknown metadata, cardinality safety, telemetry failure, execution-state cleanup, logging context, no double instrumentation, dependency rule) | `back_vibes/tests/{Unit,Feature}/Telemetry/Scheduler/` |
| Spec doc | [`backend-generic-scheduler-instrumentation.md`](backend-generic-scheduler-instrumentation.md) |

#### Scope

- Create one Scheduler boundary span per executed event via `Tracer::startSpan()` (Strategy B) — no existing span represents this boundary; the span is not a second Console or Queue span.
- Two new `ixora.scheduler.*` metrics only — no duplicate `ixora.console.*`/`ixora.queue.*` metric from the Scheduler module.
- Stable, bounded event names/types (`SchedulerEventNormalizer`/`SchedulerEventType`) and outcome classification (`SchedulerOutcome`) — never the full shell command, raw arguments/options, closure source, cron expressions, or timezones as metric labels.
- Laravel Scheduler events (not a wrapped `Schedule::`/`Event` API) as the lifecycle integration point; telemetry failures swallowed by `SchedulerExecutionTelemetry`'s own `safely()`.
- `invocation_source` on Console metrics evaluated and explicitly **not added** — not reliably observable across the command-event process boundary; documented as a limitation instead of a misleading label. `ConsoleCommandTelemetry`/`QueueExecutionTelemetry` (Phase 7B.2) are byte-for-byte unmodified.
- Error log enrichment only (`SchedulerErrorContextLogTap`) — no routine success/skip logs.
- **Level 1 (generic Laravel Scheduler) only — Level 2 (Ixora Domain Scheduling: Vibe scheduling, `Schedule` model orchestration, schedule execution records, device actions, Smart Home, Push, provider execution, domain retries/cancellation) is explicitly deferred and not instrumented.**
- **No Smart Home, Push, or external-provider instrumentation.**

#### Exit criteria

- ✅ No existing span covers a scheduled-event boundary (verified against `opentelemetry-auto-laravel`); the new boundary span is the only one, never duplicating a Console or Queue span (`backend-generic-scheduler-instrumentation.md §2, §9`).
- ✅ Every metric recorded exactly once per scheduled-event lifecycle; no forbidden labels (verified by cardinality-safety tests) — no raw cron expression, mutex key, process ID, or domain ID ever reaches a label, span attribute, or log field.
- ✅ Scheduler/mutex/overlap behavior byte-for-byte unchanged — full existing suite green with the listeners active; `Event::$skippedBecauseOverlapping`/`$exitCode`/`$runInBackground` only ever read, never mutated.
- ✅ `trace_id`/`span_id` correlation still works on Scheduler logs (Phase 7A tap unchanged); HTTP/Queue/Console/Scheduler log context proven mutually isolated.
- ✅ Telemetry failure isolation proven with deliberately-throwing fake `Tracer`/`Counter`/`Histogram`.
- ✅ Execution-state stack proven to return to empty after success, failure, and skip, with no leakage across `schedule:work`-style repeated ticks.
- ✅ Dependency Rule respected — no `OpenTelemetry\*` or `App\Telemetry\{OpenTelemetry,Noop}\*` import outside the approved boundary, and no `Schedule`/Vibe/Smart Home/Push/provider domain import anywhere in `app/Telemetry/Scheduler`; scoped test added for `app/Telemetry/Scheduler` and the new log tap specifically.
- ✅ 869/869 `back_vibes` tests pass (33 new); `pint --test` passes.
- **Ready for Phase 7B.4** — Smart Home, using the same Telemetry Contracts.

**Branch:** `feature/observability-generic-scheduler-instrumentation`

---

### Phase 7B.4 — Smart Home (`back_vibes`)

Split into a discovery sub-phase and an implementation sub-phase, since Smart Home execution is the first **Business Telemetry** target (as opposed to the generic Laravel infrastructure telemetry of Phases 7A–7B.3) and its architecture had never been formally mapped end-to-end.

#### Phase 7B.4.1 — Domain Execution Review (discovery only) — **Complete**

**Goal:** Produce a complete, citation-backed architectural map of how a Smart Home execution flows through `back_vibes` today — entry points, call graph, orchestrator(s), domain boundaries/objects, execution/failure/cancellation models, provider boundary, existing observability, duplication risks against Phases 7B.1–7B.3, and test coverage — **before** writing any telemetry code, so Phase 7B.4.2 can proceed without assumptions.

**Explicitly out of scope for this sub-phase:** spans, metrics, logs, OpenTelemetry code, behavior changes, refactors, database/API/frontend changes, new abstractions. The only source-code change permitted was documentation comments (none were needed).

**Deliverable:** [`domain-execution-review.md`](../business-telemetry/domain-execution-review.md) — findings include: two real entry points (manual mobile dispatch, scheduled dispatch) converging on `VibeSmartHomeDispatchService` → `SmartHomeActionJob` → `HomeAssistantAdapter`; no single orchestrator (two sibling entry-point orchestrators sharing a dispatch service + job layer, matching ADR-027's layering exactly); best-effort/log-only failure model with no retry/dead-letter/compensation in practice; no cancellation/timeout domain concept; no persisted per-action execution outcome anywhere (only `ScheduleExecution` audits the schedule tick, not the Smart Home actions it triggers); no correlation ID linking a trigger to its jobs (`SmartHomeActionJob` carries only an integer action ID).

**Branch:** `feature/observability-business-telemetry-domain-execution-review`

#### Phase 7B.4.2 — Smart Home Dispatch Boundary (`back_vibes`) — **Complete**

**Goal:** Implement the first Business Telemetry boundary — one `smart_home.dispatch` span wrapping `VibeSmartHomeDispatchService::dispatch()` only (loading ordered actions, ordering, enqueueing `SmartHomeActionJob`, counting dispatched/skipped, building `SmartHomeDispatchResult`). Explicitly excludes `SmartHomeActionJob`, `ProviderAdapterResolver`, `HomeAssistantAdapter`, provider execution, business metrics, and business logging (later sub-phases).

**Pre-implementation review (mandatory, performed before any span code):** confirmed `opentelemetry-auto-laravel` already injects a W3C `traceparent` into every queued job's payload at dispatch time and extracts it back as the consumer span's parent in `Worker::process()` (Phase 7B.2 §2) — and that `Tracer::startSpan()` activates the span it creates, so any `SmartHomeActionJob::dispatch()` call made while `smart_home.dispatch` is open automatically gets it injected as its parent. **Implementation Gate result: reuse existing propagation — no custom correlation ID, context object, or propagation code was implemented.**

**Deliverable:** [`backend-smart-home-dispatch-boundary.md`](../business-telemetry/backend-smart-home-dispatch-boundary.md) — instrumented at the two call sites (`VibeSmartHomeDispatchController`, `DispatchDueSchedulesCommand`) via a new `App\Telemetry\SmartHome\SmartHomeDispatchTelemetry` wrapper, rather than inside `VibeSmartHomeDispatchService` itself, since the Domain Execution Review found no Laravel event to hook and wrapping the call is the only way to add a span without editing the (deliberately untouched) business method. `VibeSmartHomeDispatchService.php` has zero diff. Span attributes: `ixora.dispatch.entry_point` (`manual`/`scheduled`/`future`, reserved), `ixora.dispatch.dispatched_actions`, `ixora.dispatch.skipped_actions` — no IDs, payloads, or credentials. Fail-open throughout; exceptions from `dispatch()` are recorded on the span and always rethrown unchanged. No metrics, no logging changes.

**Branch:** `feature/observability-smart-home-dispatch-boundary`

#### Phase 7B.4.3 — Smart Home Action Execution (`back_vibes`) — **Complete**

**Goal:** Implement the Action Execution boundary — one `smart_home.action` span per `SmartHomeActionJob::handle()` invocation, wrapping only the natural Business Boundary the mandatory architecture review discovered (provider resolution + `ProviderAdapter::executeAction()`), not the entire `handle()` method. Explicitly excludes provider communication internals, HTTP client calls, `HomeAssistantAdapter`'s own request/response handling, business metrics, and business logging (later sub-phases).

**Mandatory architecture review (performed before any span code):** read `SmartHomeActionJob::handle()`, `ProviderAdapterResolver::forProvider()`, and `HomeAssistantAdapter::executeAction()` in full. Found the natural boundary is **narrower** than `handle()`: the method's three leading guard clauses (action/device/provider-connection not found) never resolve a provider adapter and have no corresponding value in the brief's `ixora.action.outcome` vocabulary, so they stay outside the span entirely — mirroring Phase 7B.4.2's own precedent (no span for a precondition checked before the real boundary). `HomeAssistantAdapter::executeAction()` throws `UnsupportedSmartHomeActionException` synchronously, *before* any HTTP call, confirming `unsupported` is a legitimate business outcome distinct from provider-communication `failure`. Exactly one provider call happens per action attempt (no internal loop/retry). `handle()`'s own two `catch` blocks swallow every exception unconditionally today, so Laravel's queue retry mechanism (`tries = 3`) has never actually been triggered by this job — a pre-existing fact this phase does not change.

**Deliverable:** [`backend-smart-home-action-execution.md`](../business-telemetry/backend-smart-home-action-execution.md) — a new `App\Telemetry\SmartHome\SmartHomeActionTelemetry` wrapper is called from inside `SmartHomeActionJob::handle()` around only the discovered boundary; both pre-existing `catch` blocks are byte-for-byte unchanged. Span attributes: `ixora.action.provider` (`home_assistant`/`future`, reserved), `ixora.action.outcome` (`success`/`failure`/`unsupported`), `ixora.action.retry` (`true`/`false`, from Laravel's own job-attempt counter) — no IDs, payloads, or credentials. Outcome classification is supplied by the caller via two closures (`classifyResult`/`classifyException`) rather than the Telemetry layer importing `ActionResult`/`UnsupportedSmartHomeActionException` — generalizing Phase 7B.4.2's `extractCounts` technique. Reuses `Tracer::startSpan()` to nest under the Queue Consumer span (itself already under `smart_home.dispatch`) with zero custom propagation. Fail-open throughout; exceptions are recorded on the span and always rethrown unchanged.

**Branch:** `feature/observability-smart-home-action-execution`

#### Phase 7B.4.4 — Smart Home Provider Boundary (`back_vibes`) — **Complete**

**Goal:** Implement the Provider Boundary — one `smart_home.provider` span per `HomeAssistantAdapter::executeAction()` invocation, wrapping only the natural Provider Boundary the mandatory architecture review discovered (domain/payload construction through `ActionResult` construction), not the entire method. Explicitly excludes business metrics and business logging (later sub-phases), and never duplicates the existing HTTP client auto-instrumentation.

**Mandatory architecture review (performed before any span code):** read `HomeAssistantAdapter::executeAction()`, the `ProviderAdapter` interface, `ProviderAdapterResolver`, `SmartHomeActionTelemetry`, `SmartHomeActionJob`, and the HTTP client auto-instrumentation (`open-telemetry/opentelemetry-auto-guzzle`) in full. Found the natural boundary is **narrower** than `executeAction()`: the unsupported-action check (`ACTION_SERVICE_MAP` lookup) returns before any provider I/O and mirrors the guard-clause exclusion precedent from Phase 7B.4.3, so it stays outside the span. Confirmed `opentelemetry-auto-guzzle` already creates a `SpanKind::CLIENT` span (named after the HTTP method) for every `Http::...->post(...)` call this segment makes, with url/method/status/duration/exception-recording already covered — the new span therefore records none of that, avoiding duplication. Re-examined Phase 7B.4.3's own attribute choices per the brief's instruction not to assume they were correct: confirmed `ixora.action.provider` must stay on `smart_home.action` (a Provider span cannot exist for an unsupported action or an unknown-provider resolver rejection, both of which occur before any adapter exists); confirmed `unsupported` correctly stays an `smart_home.action` outcome for the same reason; flagged `ixora.action.retry` as a documented duplicate of Phase 7B.2's own `ixora.queue.attempt` (recommended for future cleanup, not changed this phase, per the brief's "no implementation change required unless clearly justified").

**Deliverable:** [`backend-smart-home-provider-boundary.md`](../business-telemetry/backend-smart-home-provider-boundary.md) — a new `App\Telemetry\SmartHome\SmartHomeProviderTelemetry` wrapper is called from inside `HomeAssistantAdapter::executeAction()` (the one deliberate departure from "wrap only at the call site, never touch the wrapped file", justified because the unsupported-action knowledge needed to exclude that check lives only inside the concrete adapter); the check itself and every other adapter method are byte-for-byte unchanged. Span attribute: `ixora.provider.device_domain` (`light`/`switch`/`media_player`/`fan`/`other`, reserved) — no IDs, payloads, credentials, or duplicated url/method/status/duration attributes. Reuses `Tracer::startSpan()` to nest under `smart_home.action` (itself already under the Queue Consumer span and `smart_home.dispatch`) with zero custom propagation; the Guzzle client span nests one level deeper for free. Fail-open throughout; an exception escaping the wrapped segment is recorded on the span and always rethrown unchanged — a normally-returned failed `ActionResult` is never treated as a span error.

**Branch:** `feature/observability-smart-home-provider-boundary`

#### Phase 7B.4.5 — Business Failure Semantics (`back_vibes`) — **Complete**

**Goal:** Formally define Business Failure Semantics for Smart Home execution — an architecture-review phase, explicitly **not** about adding metrics, logs, or dashboards. Every later Business Telemetry sub-phase (metrics, logging, dashboards, alerts) depends on the decisions made here.

**Mandatory architecture review (performed before any code):** re-read `SmartHomeActionJob`, `SmartHomeActionTelemetry`, `SmartHomeProviderTelemetry`, `SmartHomeDispatchTelemetry`, `HomeAssistantAdapter`, `ProviderAdapter`, `ProviderAdapterResolver`, `ActionResult`, `UnsupportedSmartHomeActionException`, `QueueExecutionTelemetry`, `QueueOutcome`, the Telemetry contracts, and the Traces/Logs/Metrics Philosophy + Telemetry Decision Guide docs in full. Produced an exhaustive failure taxonomy across the dispatch → queue → action → provider → HTTP-client pipeline and classified every entry as Business, Infrastructure, Platform, Telemetry, or Unknown. Confirmed `ProviderConnectionException` is **unreachable** in this pipeline (only thrown by device-sync code, not action execution) — a notable finding, since the brief's example list assumed it was reachable. Confirmed `ActionResult(success=false)` represents "successful execution with an unsuccessful business outcome" rather than an infrastructure failure, while documenting that it conflates provider rejection and transport failure at this level (accepted limitation). Formalized the Span Status policy: OpenTelemetry's recommendation that business failures are not usually span errors is adopted — `unsupported` is a recognized, expected business outcome (analogous to an HTTP 4xx) and must never mark a span `ERROR`, while genuine unexpected `Throwable`s escaping any boundary still do. This review surfaced exactly one inconsistency with that policy: `SmartHomeActionTelemetry::wrap()` unconditionally called `setError()` for every exception, including `unsupported`. Reviewed the existing `ixora.action.outcome` vocabulary (`success`/`failure`/`unsupported`/`unknown`) and confirmed no new outcome values are needed. Documented failure propagation across the full span hierarchy, retry semantics (a retried job is an **independent event** producing a new `smart_home.action` span, not a "failure" of the prior attempt), and classified logging/metrics ownership per failure type for future phases — without implementing any of it.

**Deliverable:** [`backend-business-failure-semantics.md`](../business-telemetry/backend-business-failure-semantics.md) — the reference document for every future Business Telemetry implementation. One narrowly-scoped, review-justified code change: `SmartHomeActionTelemetry::wrap()` now only calls `setError()` when `outcome !== SmartHomeActionOutcome::Unsupported`, while `recordException()` still always fires so the exception remains visible on the span. No new metrics, no new logs, no dashboards, no retry/queue/provider/dispatch behavior changes, no new persistence or correlation IDs.

**Branch:** `feature/observability-business-failure-semantics`

---

#### Phase 7B.4.6 — Business Metrics (`back_vibes`) — **Complete**

**Goal:** Introduce the first Business Metrics for the Smart Home domain, building on Phase 7B.4.5's failure taxonomy — explicitly **not** about logging, dashboards, or alerts. No Business Metric may contradict the failure taxonomy established in that phase.

**Mandatory architecture review (performed before any code):** re-read `backend-business-failure-semantics.md`, all three Smart Home boundary docs (dispatch/action/provider), Metrics/Traces/Logs Philosophy, Telemetry Naming Convention, and Telemetry Decision Guide in full; reviewed `SmartHomeDispatchTelemetry`, `SmartHomeActionTelemetry`, `SmartHomeProviderTelemetry`, `QueueExecutionTelemetry`, the `Meter`/`Counter`/`Histogram` abstractions, existing metric registration patterns, and OpenTelemetry metric conventions. Produced a full Metrics Design Review (Design Record per candidate — business meaning, counting unit, failure semantics, boundary ownership, cardinality, failure alignment, duplication, dashboard preview, decision) for all three metrics named in the brief plus one it surfaced on its own (a J1–J3 guard-clause-skip candidate Phase 7B.4.5 flagged as "worth considering, not decided there").

**Decisions:** `ixora.smart_home.dispatch.total` (Counter, `entry_point`/`outcome`) — **Implement**, narrowest owner is Dispatch, safe cardinality (54 series), no duplication. `ixora.smart_home.action.total`/`.duration` (Counter + Histogram, `outcome`/`provider`) — **Implement**, the platform's own pre-reserved highest-value Smart Home metric pair, reusing the already-classified `SmartHomeActionOutcome` verbatim so it can never contradict its own span's status. `ixora.smart_home.provider.total` — **Reject**, independently re-confirmed 1:1 duplication with the Action counter in today's single-provider-per-attempt pipeline. Guard-clause-skip metric — **Defer**, no clean boundary owner exists yet since J1–J3 never reach a span.

**Deliverable:** [`backend-smart-home-business-metrics.md`](../business-telemetry/backend-smart-home-business-metrics.md). Two Counters + one Histogram registered via the existing `Meter` contract in `SmartHomeDispatchTelemetry`/`SmartHomeActionTelemetry`, recorded from inside each class's pre-existing `safely()` fail-open guard; `TelemetryServiceProvider` wires `Meter`/`environment`/`service_name` into both singletons, mirroring the existing Queue/Console/Scheduler pattern. `SmartHomeProviderTelemetry` and every Smart Home enum remain untouched and metric-free. `action_type` is deliberately omitted from the Action metric's label set this phase (not an existing span attribute; not named in this phase's own brief) and recorded as a Phase 7B.4.7 recommendation. No logs, no dashboards, no alerts, no business/retry/queue/provider/dispatch behavior changes. 980/980 `back_vibes` tests passing (358/358 SmartHome-scoped); `pint --test` clean.

**Branch:** `feature/observability-business-metrics`

---

#### Phase 7B.4.7 — Business Logging (`back_vibes`) — **Complete**

**Goal:** Introduce structured Business Logging for the Smart Home domain, building on Phase 7B.4.5's failure taxonomy and Phase 7B.4.6's Business Metrics — explicitly **not** about metrics, dashboards, or alerts. Business Logs must complement traces and metrics; they must never duplicate them.

**Mandatory architecture review (performed before any code):** re-read `backend-business-failure-semantics.md` (§10 logging-ownership table and §14 L-2 as the primary starting brief), `backend-smart-home-business-metrics.md` (§9 recommendation #4 as the L-2 mandate), all three Smart Home boundary docs, Logs/Traces/Metrics Philosophy, Telemetry Naming Convention, and Telemetry Decision Guide in full; reviewed `SmartHomeDispatchTelemetry`, `SmartHomeActionTelemetry`, `SmartHomeProviderTelemetry`, `SmartHomeActionJob` (five pre-existing log sites), `TraceCorrelationLogTap`, `QueueErrorContextLogTap`, `SchedulerErrorContextLogTap`, and `config/logging.php`. Confirmed `TraceCorrelationLogTap` is registered on every channel, automatically injecting `trace_id`/`span_id` into all log records when a span is active.

**Decisions:** `smart_home.dispatch.completed` — **Reject** (D1 Trace+Metric-only; D2 already logged at call-site; Telemetry-layer duplicate adds no investigation value). `smart_home.action.completed` — **Reject** as new log; **Resolve L-2** instead (remove `Log::info` on success — metric + trace covers this). `smart_home.action.failed` — **Reject** as new Telemetry-layer log; **Improve** existing failure logs (security sanitization + telemetry vocabulary alignment). `smart_home.provider.failed` — **Reject** (1:1 duplication with A2/A5 logs one layer up; violates single-boundary-ownership rule).

**Deliverable:** [`backend-smart-home-business-logging.md`](../business-telemetry/backend-smart-home-business-logging.md). `SmartHomeActionJob` is the only modified file: (1) L-2 resolution — `Log::info` on success removed; (2) `provider_device_id` removed from `$context` (forbidden field per naming-convention §8 — reveals home layout); (3) `exception_class => $e::class` replaces raw `error_message` in both catch blocks; (4) `outcome` added to every failure/unsupported log using the `SmartHomeActionOutcome` vocabulary, enabling cross-signal Loki queries aligned with the Business Metrics. No new log statements, no new Telemetry classes, no metrics, no spans, no dashboards, no business/retry/queue/provider behavior changes. 986/986 `back_vibes` tests passing (364/364 SmartHome-scoped); `pint --test` clean.

**Branch:** `feature/observability-business-logging`

---

#### Phase 7B.4.8 — Business Telemetry Validation & Architecture Review (`back_vibes`) — **Complete**

**Goal:** Validate that all Smart Home Business Telemetry implemented during Phases 7B.4.2–7B.4.7 forms one coherent, internally consistent observability model. Architecture validation phase — not about adding new telemetry, dashboards, or alerts.

**Mandatory architecture review (performed before any decision):** Read all 7 Business Telemetry docs (domain-execution-review, 3 boundary docs, failure-semantics, metrics, logging) + 6 Core Observability guides (naming-convention, decision-guide, metrics-philosophy, logs-philosophy, traces-philosophy, sdk-foundation) in full. Confirmed every telemetry implementation file in `app/Telemetry/SmartHome/`, `app/Jobs/SmartHome/`, and `app/Telemetry/Providers/TelemetryServiceProvider.php` against documentation — no trust in documentation without source verification.

**Key findings:**

- **Ownership:** Every signal (3 spans, 3 metrics, 6 log events) has exactly one owner. No signal is duplicated, missing, or ambiguously owned.
- **Trace hierarchy:** Validated as `HTTP/Console → smart_home.dispatch → Queue Consumer → smart_home.action → smart_home.provider → POST (Guzzle)`. W3C `traceparent` propagation through queue boundary confirmed via existing `opentelemetry-auto-laravel` hook — no custom correlation code exists or is needed.
- **Metrics:** All 3 metrics correctly designed, owned, and cardinality-bounded. `action_type` label and guard-clause skip counter remain correctly deferred.
- **Logging:** All logs are structured, sanitized, at correct levels, and complementary to the other signals. `provider_connection_id` naming is a Low-priority cosmetic inconsistency — no runtime change warranted.
- **Cross-signal consistency:** `SmartHomeActionOutcome` shared between span and metric by construction — a metric value can never contradict its corresponding span. All 4 outcomes (success, failure, unsupported, unknown) produce consistent, non-contradictory signals.
- **Correlation:** Complete Metric→Trace→Log navigation confirmed. `trace_id`/`span_id` injected globally by `TraceCorrelationLogTap`. No custom correlation IDs.
- **Security:** PASS — no forbidden data in any signal type (spans, metrics, logs).
- **Dashboard readiness:** 6 of 8 panels fully supported. "Provider Performance by device type" and "Top Failures by action type" partially supported — gap closed by adding `action_type` label (TD-2).
- **Operational readiness:** Full "Lights are not turning on" investigation workflow demonstrated. 9/9 diagnostic questions answerable from current telemetry.
- **Future extensibility:** Architecture supports Push Notifications, Matter, Google Home, Alexa, and additional Smart Home providers without redesign.

**Technical debt documented:** TD-1 (`ixora.action.retry` duplicate of `ixora.queue.attempt` — Medium, recommend removal in Phase 7B.5); TD-2 (`action_type` label absent — Low, recommend Phase 7B.5); TD-3 (guard-clause J1–J3 invisible to metrics — Medium, recommend Phase 7B.5/7B.6); TD-4 (`provider_connection_id` → `connection_id` naming — Low, bundle with next logging change).

**Runtime changes:** None. No code was changed.

**Deliverable:** [`backend-business-telemetry-validation.md`](../business-telemetry/backend-business-telemetry-validation.md). Full validation report with Ownership Matrix, all review sections, Cross-Signal Consistency Matrix, Correlation analysis, Security review, Dashboard/Operational/Extensibility readiness, and Technical Debt Register.

**Branch:** `feature/observability-telemetry-validation`

---

#### Phase 7B.4.9 — Business Telemetry Foundation Baseline — **Complete**

**Goal:** Transform the validated Smart Home Business Telemetry architecture into a platform-wide Business Telemetry standard. Documentation-only — no runtime code, telemetry, metrics, spans, logs, or tests.

**Mandatory review (performed before writing):** Read `backend-business-telemetry-validation.md`, all Smart Home boundary/failure/metrics/logging docs, and all six Core Observability guides (telemetry-decision-guide, telemetry-naming-convention, metrics-philosophy, logs-philosophy, traces-philosophy, backend-sdk-foundation).

**Deliverable:** [`business-telemetry-foundation.md`](../business-telemetry/business-telemetry-foundation.md). Platform-wide baseline covering:

- **Platform rules (§3):** Business boundary ownership, signal ownership, failure taxonomy, business outcome vocabulary, cross-signal consistency, correlation model, security model, fail-open policy, cardinality/logging/metrics/tracing policies.
- **Business boundary pattern (§4):** Standard lifecycle (Entrypoint → Dispatch → Execution → Provider → External), layer responsibilities, boundary discovery method.
- **Required components (§5):** Mandatory deliverables per domain, standard Telemetry class pattern with Dependency Rule.
- **Standard design reviews (§6):** Architecture, Failure Semantics, Metrics Design, Logging Design, Security, Validation — each with mandatory gate criteria.
- **Extension rules (§7):** How to add new domains, boundaries, and providers without redesign.
- **Anti-patterns (§8):** Prohibited duplication, ownership, security, correlation, and design violations.

No Smart Home-specific assumptions remain — Smart Home is the validated reference implementation, not a special case.

**Branch:** `feature/observability-business-telemetry-foundation`

---

#### Phase 8.0 — Dashboard Requirements Review — **Complete**

**Goal:** Define the complete dashboard architecture for the Observability Foundation MVP. Documentation-only — no Grafana JSON, no PromQL, no dashboard implementation.

**Mandatory review (performed before writing):** Read `business-telemetry-foundation.md`, `backend-business-telemetry-validation.md`, `metrics-philosophy.md`, `logs-philosophy.md`, `traces-philosophy.md`, `telemetry-decision-guide.md`.

**Deliverable:** [`dashboard-requirements.md`](dashboard-requirements.md). Dashboard architecture covering:

- **Dashboard inventory (§1–2):** 7 dashboards (D-01 Platform Overview, D-02 Smart Home, D-03 Push Notifications, D-04 Queue Workers, D-05 HTTP API, D-06 Scheduler, D-07 Collector & Infrastructure) with audience, purpose, and implementation order.
- **Signal inventory (§2):** All available metrics, spans, and log sources mapped with availability status.
- **Dashboard designs (§3–9):** For each dashboard: purpose, audience, operational questions, panel definitions, signal mappings, drill-down workflow, refresh interval, future expansion, and deferred panels.
- **Investigation workflows (§10):** 6 complete Metric → Trace → Log runbooks covering all major operational scenarios.
- **Operational questions mapping (§11):** Every on-call question mapped to the dashboard, panel, and signal that answers it.
- **Standard variables (§12):** `$environment`, `$time_range`, and domain-specific variables required on every dashboard.
- **Retention impact (§13):** Consequence of 7-day Trace / 14-day Log / 30-day Metric retention on dashboard usability.
- **Deferred panels (§14):** Panels blocked by missing signals (TD-2 `action_type`, TD-3 guard-clause metric, Phase 7B.5 Push).
- **Phase 9 checklist (§15):** Implementation checklist for Grafana dashboard construction.

**Branch:** `feature/observability-dashboard-requirements`

---

#### Phase 8.1 — Grafana Foundation & Provisioning — **Complete**

**Goal:** Activate Grafana OSS as a fully provisioned, version-controlled, environment-independent platform. Grafana can be destroyed and recreated with no manual configuration.

**Mandatory review (performed before implementation):** Read `dashboard-requirements.md`, `business-telemetry-foundation.md`, `metrics-philosophy.md`, `logs-philosophy.md`, `traces-philosophy.md`, `telemetry-decision-guide.md`, `telemetry-naming-convention.md`. Reviewed all Collector/Prometheus/Loki/Tempo configs and docker-compose.yml.

**Runtime changes:**
- `docker-compose.yml` — Grafana service activated (replaced Phase 9 stub comment).
- `collector/grafana/provisioning/datasources/datasources.yaml` — 3 datasources with stable UIDs (`ixora-prometheus`, `ixora-loki`, `ixora-tempo`), Tempo→Loki/Prometheus drill-down links, Prometheus→Tempo exemplar links, Loki derived fields for `trace_id` → Tempo.
- `collector/grafana/provisioning/dashboards/providers.yaml` — 4 folder providers (Infrastructure, Application, Business, Overview) with stable `folderUID`s.
- `collector/grafana/provisioning/dashboards/{infrastructure,application,business,overview}/` — directory structure for Phase 9 dashboard JSONs.
- `collector/grafana/validate.sh` — 12-check validation script confirming health, UIDs, defaults, connectivity, read-only status, and datasource count.
- `.env.example` — Grafana variables added (`GRAFANA_VERSION`, `GF_ADMIN_*`, `GF_SERVER_ROOT_URL`, etc.).
- `collector/tempo/tempo.yaml` — Fixed 6 config fields removed/renamed in Tempo 2.6.0 (`ingester.wal`, `block.encoding`, `query_frontend` sub-timeouts, top-level `search` block, `overrides.defaults`).
- `collector/loki/loki.yaml` — Fixed 3 config fields removed/renamed in Loki 3.2.0 (`limits_config.max_label_names`, `querier.query_timeout`, `ingester.wal.recover_from_wal`).

**Documentation:** [`grafana-foundation.md`](grafana-foundation.md) covering provisioning architecture, datasource strategy (stable UIDs, drill-down wiring), folder strategy, dashboard-as-code standard, platform variables strategy, navigation strategy, plugin policy, security review, environment strategy, backend config fixes, extensibility, validation results (12/12), known limitations, and Phase 8.2 recommendations.

**Validation:** `./grafana/validate.sh` → **12/12 PASS** (initial start + post-restart idempotency confirmation).

**Branch:** `feature/observability-grafana-foundation`

---

#### Phase 8.2 — D-07 Infrastructure Dashboard — **Complete**

**Goal:** Implement the first production Grafana dashboard — D-07 Infrastructure. Validates Phase 8.1 foundation, establishes dashboard JSON standards for future dashboards.

**Mandatory review (performed before implementation):** Read ADRs 028–031, all observability philosophy docs, collector config, grafana-foundation.md, dashboard-requirements.md §9, observability-playbook.md. Full architecture review in dashboard-d07-infrastructure.md §2.

**Runtime changes:**
- `collector/grafana/provisioning/dashboards/infrastructure/d07-infrastructure.json` — D-07 dashboard (21 panels, uid=`ixora-collector`, Infrastructure folder, `ixora-prometheus` datasource).
- `collector/grafana/validate.sh` — Extended from 13 to 24 checks: folder names, JSON syntax, UID, provisioning, datasource binding, folder assignment.
- `collector/config.yaml` — Removed invalid `labels:` block from Loki exporter (OTel Collector 0.115.x removed this key).
- `collector/docker-compose.yml` — Added `PROMETHEUS_REMOTE_WRITE_ENDPOINT`, `LOKI_ENDPOINT`, `TEMPO_ENDPOINT` to Collector service environment block.
- `collector/.env` — Added endpoint env vars and `TEMPO_OTLP_GRPC_PORT=14317`.
- `collector/.env.example` — Updated `TEMPO_OTLP_GRPC_PORT` comment and default to `14317`.

**Documentation:** [`dashboard-d07-infrastructure.md`](dashboard-d07-infrastructure.md) covering architecture review, available metrics, 3 pre-existing bugs fixed, dashboard design, 21 panels, datasource usage, UID convention table, validation results, 3 known limitations, and Phase 8.3 recommendations.

**Validation:** `./grafana/validate.sh` → **24/24 PASS** (initial start + post-restart idempotency confirmation).

**Branch:** `feature/observability-d07-infrastructure`

---

#### Phase 8.3 — Application Infrastructure Dashboards — **Complete**

**Goal:** Implement application-runtime dashboards for HTTP API, Queue Workers, and Scheduler. Establish permanent Grafana conventions documented in `dashboard-conventions.md`.

**Mandatory review (performed before implementation):** Read ADRs 028–031, all observability philosophy docs, grafana-foundation.md, dashboard-requirements.md, dashboard-d07-infrastructure.md, all HTTP/Queue/Scheduler metric implementations (`HttpRequestTelemetry.php`, `QueueExecutionTelemetry.php`, `SchedulerExecutionTelemetry.php`).

**Architecture findings:**
- Scheduler metric names in `dashboard-requirements.md §8` were incorrect pre-implementation placeholders. Actual names: `ixora.scheduler.event.total` / `ixora.scheduler.event.duration`. Outcomes: `success`, `failed`, `overlap_prevented`, `skipped`, `background_completed`.
- HTTP metrics use `status_code_class` (2xx/4xx/5xx), not individual status codes. Individual 401/403 isolation requires Tempo drill-down.
- Queue label is `job_name` (not `job`). `ixora_queue_job_active` UpDownCounter available.

**Runtime changes:**
- `collector/grafana/provisioning/dashboards/application/d05-http.json` — D-05 HTTP API (15 panels, uid=`ixora-http`, Application folder, `ixora-prometheus`).
- `collector/grafana/provisioning/dashboards/application/d04-queue.json` — D-04 Queue Workers (17 panels, uid=`ixora-queue`, Application folder, `ixora-prometheus`).
- `collector/grafana/provisioning/dashboards/application/d06-scheduler.json` — D-06 Scheduler (17 panels, uid=`ixora-scheduler`, Application folder, `ixora-prometheus`).
- `collector/grafana/validate.sh` — Extended with Check 25 (UID uniqueness across all dirs) and Check 26 (all UIDs start with `ixora-`). Total: 26/26 PASS.

**Documentation:**
- `dashboard-conventions.md` — Permanent Grafana standard: UID convention, folder convention, datasource convention, refresh convention, time range convention, variable convention, panel convention, panel ID ranges (100–199 Health, 200–299 Throughput, 300–399 Errors, 400–499 Performance, 500–599 Business), JSON standards, security convention, validation requirements, navigation convention, known limitations.
- `dashboard-d05-http.md`, `dashboard-d04-queue.md`, `dashboard-d06-scheduler.md`.

**Validation:** `./grafana/validate.sh` → **26/26 PASS** (initial start + post-restart idempotency confirmation).

**Branch:** `feature/observability-application-dashboards`

---

#### Phase 8.4 — Smart Home Business Dashboard (D-02) — **Complete**

**Goal:** Implement D-02 Smart Home Business Dashboard. First Business dashboard for the platform. Covers dispatch throughput, action success/failure rates, provider performance, and business relationships.

**Mandatory review (performed before implementation):** Read ADRs 028–031, all observability philosophy/architecture docs, all grafana docs (conventions, requirements, existing dashboards), all Smart Home Business Telemetry docs (domain-execution-review, dispatch-boundary, action-execution, provider-boundary, business-failure-semantics, business-metrics, business-logging, business-telemetry-validation, business-telemetry-foundation). Verified every metric, label, histogram, outcome value directly against `SmartHomeDispatchTelemetry.php`, `SmartHomeActionTelemetry.php`, `SmartHomeProviderTelemetry.php`, and all enums.

**Architecture findings:**
- `ixora_smart_home_dispatch_total` verified: labels `entry_point` (manual/scheduled/future), `outcome` (dispatched/skipped/error). Counting unit: actions (not calls) for dispatched/skipped; 1 for error.
- `ixora_smart_home_action_total` verified: labels `outcome` (success/failure/unsupported/unknown), `provider` (home_assistant/future). Unit: `{action}`.
- `ixora_smart_home_action_duration` verified: Histogram, unit `ms`, same label set as action_total.
- **`ixora_smart_home_provider_total` / `_duration` do NOT exist** — Provider metrics were rejected in Phase 7B.4.6 §3.3 as 1:1 duplications of action metrics. No panels for these.
- **No `action_type` label** — deliberately deferred in Phase 7B.4.6 §3.2.
- `unsupported` is a Business outcome (span stays OK), not a failure — panel descriptions document this distinction.
- Queue/Business orthogonality (Phase 7B.4.5 §8.3) explicitly shown in panel 501.

**Runtime changes:**
- `collector/grafana/provisioning/dashboards/business/d02-smart-home.json` — D-02 Smart Home Business (23 panels: 5 rows + 18 content panels, uid=`ixora-smart-home`, Business folder, `ixora-prometheus`, refresh=1m).
- `collector/grafana/validate.sh` — Extended with Checks 13–16 for D-02. Total: 33/33 PASS.

**Documentation:**
- `dashboard-d02-smart-home.md` — Full architecture review, metric verification, panel inventory, PromQL queries, variables, navigation, security review, known limitations.

**Validation:** `./grafana/validate.sh` → **33/33 PASS** (initial start + post-restart idempotency confirmation).

**Branch:** `feature/observability-smart-home-dashboard`

---

#### Phase 8.5 — Platform Overview Dashboard (D-01) — **Complete**

**Goal:** Implement D-01 Platform Overview Dashboard. Default landing page for operators. Cross-domain health summary — HTTP, Queue, Scheduler, Smart Home, Collector/Prometheus. Points to specialized dashboards via panel and dashboard-level navigation links.

**Mandatory review (performed before implementation):** Read all mandatory docs: dashboard-conventions.md, dashboard-requirements.md, all existing dashboard docs (D-02, D-04, D-05, D-06, D-07), metrics/logs/traces philosophy, telemetry-naming-convention. Verified all metrics used by cross-referencing expressions from existing dashboard implementations.

**Architecture findings:**
- No new metrics introduced in D-01. All queries reuse metrics verified in previous phases.
- `ixora_telemetry_export_failed_total` uses label `deployment_environment`, not `environment` — panel 105 uses `deployment_environment=~"$environment"`, consistent with D-07.
- Infrastructure metrics (`otelcol_*`, `up{job=...}`) carry no `environment` label — infrastructure panels explicitly document this.
- **UID discrepancy:** `dashboard-conventions.md §1.2` planned `ixora-overview`; Phase 8.5 spec requires `ixora-platform`. Used `ixora-platform`; conventions doc updated.
- D-03 Push Notifications absent: `ixora_push_delivery_total` not yet implemented (Phase 7B.5 pending).

**Runtime changes:**
- `collector/grafana/provisioning/dashboards/overview/d01-platform-overview.json` — D-01 Platform Overview (32 panels: 5 row headers + 27 content panels, uid=`ixora-platform`, Overview folder, `ixora-prometheus`, refresh=30s).
- `collector/grafana/validate.sh` — Extended with Checks 34–42 (JSON syntax, UID, provisioned+Overview folder, datasource refs, link style, panel ID uniqueness, panel ID ranges, description completeness, datasource UID completeness). Total: **42/42 PASS**.
- `docs/specs/observability-foundation/mvp/dashboard-conventions.md` — §1.2 UID table updated: `ixora-overview` → `ixora-platform`.

**Documentation:**
- `dashboard-d01-platform-overview.md` — Architecture review, metrics inventory, UID discrepancy, panel inventory (all 27 content panels), navigation strategy, security review, known limitations (KL-1 through KL-6), troubleshooting.

**Validation:** `./grafana/validate.sh` → **42/42 PASS** (initial start + post-restart idempotency confirmation).

**Branch:** `feature/observability-platform-overview-dashboard`

---

#### Phase 8.6 — Dashboard Integration & Operational Validation — **Complete**

**Goal:** Finalize the dashboard ecosystem as a cohesive operational platform. No new telemetry, metrics, or infrastructure changes.

**Deliverables:**

- **Bidirectional navigation mesh:** All 5 specialized dashboards (D-02, D-04, D-05, D-06, D-07) now link back to D-01. D-07 had zero links; now has all 5. Total navigation links: 30 (6 × 5 peers).
- **Standard link order:** D-01 → D-02 → D-04 → D-05 → D-06 → D-07 (self excluded). Enforced by check 44.
- **Overview Dashboard Principles:** New permanent architectural section in `dashboard-conventions.md §13`. Documents what overview dashboards must not and should do.
- **Navigation conventions §12 rewritten:** Replaces per-folder subsets with full bidirectional mesh standard. Adds `targetBlank: false` rule (§12.3).
- **Operational investigation workflows:** 4 complete end-to-end scenarios documented (HTTP Server Error → D-01/D-05/D-07/Tempo/Loki; Scheduler Failure → D-01/D-06/D-07/Tempo; Queue Backlog → D-01/D-04/D-07/Loki; Smart Home Failure → D-01/D-02/Tempo/Loki).
- **Dashboard navigation matrix:** Full FROM → TO matrix documenting all 30 links.
- **validate.sh extended to 48 checks:** New checks 43–47 (back-link to D-01, link order, no duplicates, keepTime, no targetBlank) and check 48 (panel ID integrity across all 6 dashboards).
- **dashboard-operational-validation.md created:** Purpose, methodology, navigation matrix, investigation workflows, usability review, architecture review, known limitations, future improvements.

**Result:** 48/48 PASS. Restart idempotency confirmed twice.

**Branch:** `feature/observability-dashboard-integration`

---

#### Phase 8.7 — D-03 Push Notifications Dashboard — **Complete**

**Goal:** Implement D-03 Push Notifications Dashboard using the available push telemetry layer. Integrate into the navigation mesh. Extend validate.sh to 57 checks.

**Architecture finding — Phase 7B.5 not complete:**
Architecture review found that `ixora.push.delivery.total` does not exist. `PushNotificationJob` emits only logs. D-03 is built on `ixora_queue_job_total{queue="push"}` — the existing queue telemetry layer. This provides real operational observability. Per-notification-type and per-provider panels are deferred to Phase 7B.5.

**Deliverables:**

- **D-03 Push Notifications Dashboard:** 23 panels (4 sections: Platform Health, Business Throughput, Failures, Performance). UID `ixora-push`. Business folder. Refresh 1 minute. Built on `ixora_queue_job_*{queue="push"}` metrics.
- **Navigation mesh expanded:** D-03 inserted at position 3 (D-01→D-02→**D-03**→D-04→D-05→D-06→D-07). All 6 existing dashboards updated. Total links: 42 (7×6).
- **Phase 7B.5 readiness:** `$provider` (fcm, noop) and `$notification_type` (4 types) as static variables, ready to convert to `label_values()` when `ixora_push_delivery_total` ships.
- **validate.sh extended to 57 checks:** Check 44 ordering updated. Checks 49–57 validate D-03 file, UID, provisioning, datasource, links, variables, descriptions, duplicate IDs, and panel ranges.
- **dashboard-d03-push.md created:** Purpose, metrics, panel inventory, navigation, investigation workflow, architecture review, known limitations, future improvements.
- **dashboard-conventions.md updated:** D-03 status in UID table; §12.1 ordering table extended to 7 positions.

**Result:** 57/57 PASS. Restart idempotency confirmed twice.

**Branch:** `feature/observability-d03-push-dashboard`

---



---

## Phase 8 — Frontend SDK

**Goal:** `front_vibes` Android emits OTLP to Collector.

### Scope

- OpenTelemetry JavaScript SDK in Capacitor WebView context (evaluate native vs web).
- Error and navigation spans; conservative sampling on mobile.
- No PII in mobile telemetry.

### Exit criteria

- Staging APK exports sample traces/logs on key flows.

---

## Phase 9 — Grafana dashboards

**Goal:** Operational dashboards for API, scheduler, Smart Home, push, queue.

### Dashboards (minimum)

- API: request rate, latency p95, 5xx rate
- Scheduler: dispatch outcomes, duration
- Smart Home: job success/failure
- Push: delivery outcomes by event type
- Queue: depth, processing rate

### Exit criteria

- Dashboards documented with screenshot paths in QA report.

---

## Phase 9.5 — Telemetry Decision Guide + Observability Playbook

**Goal:** Document **which** telemetry signal to emit and **how to investigate** production issues — before and alongside SDK/dashboard implementation.

**Complete (documentation only).**

### Deliverables

| Item | Output |
| --- | --- |
| Signal choice guide | [`telemetry-decision-guide.md`](../../../architecture/telemetry-decision-guide.md) |
| Investigation runbook | [`observability-playbook.md`](../../../operations/observability-playbook.md) |

### Exit criteria

- Both documents published; README, plan, and tasks updated.
- **No runtime code**, SDK, Collector, Grafana, or infrastructure changes.

> Instrumentation PRs must follow [telemetry-decision-guide.md](../../../architecture/telemetry-decision-guide.md) for signal choice and [telemetry-naming-convention.md](../../../architecture/telemetry-naming-convention.md) for names. On-call uses [observability-playbook.md](../../../operations/observability-playbook.md).

---

## Phase 10 — Operational readiness

**Goal:** Runbook for observability VM ops.

### Deliverables

- `docs/operations/observability-operational-checklist.md` (future — VM health, retention verification)
- Complements [`observability-playbook.md`](../../../operations/observability-playbook.md) (investigation workflows)
- Disk alert thresholds, retention verification, Collector restart procedure

### Exit criteria

- Runbook published; staging on-call can troubleshoot Collector down.

---

## Phase 11 — QA

**Goal:** Automated and manual validation.

### Exit criteria

- Telemetry export tests; failure isolation test (Collector stopped → API still 200).
- Security spot check per ADR-030.

---

## Phase 11.5 — Appium mobile telemetry validation

**Goal:** Real-device validation per [mobile-e2e-testing.md](../../../testing/mobile-e2e-testing.md).

### Exit criteria

- Mobile traces appear in Tempo after Appium critical path run.
- No forbidden fields in mobile telemetry sample.

---

## Release

- Tag across repos when all phases complete.
- Release notes in `docs/releases/`.
- **Do not** deploy production observability VM without explicit approval.

---

## Dependencies

| Dependency | Phase |
| --- | --- |
| Staging API reachable from observability VM | 2 |
| App Platform egress to VM OTLP port | 2 |
| ADR-030 redaction rules | 2.5, 3 |
| Backend SDK before dashboards | 7A/7B before 9 |
| Backend SDK Foundation before Domain Instrumentation | 7A before 7B |
| Mobile SDK before Appium telemetry QA | 8 before 11.5 |

---

## Risk register

| Risk | Mitigation |
| --- | --- |
| Disk fill on single VM | ADR-031 retention + alerts |
| Cardinality explosion | Label allowlist in Collector |
| Telemetry data leak | ADR-030 + Collector redaction |
| Mobile battery/data usage | Sampling + batch export |
| Collector SPOF | Accept for MVP; document in runbook |
