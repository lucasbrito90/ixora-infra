# Observability Foundation MVP — implementation plan

**Status:** Phase 7B.4.2 complete — Smart Home dispatch boundary (`smart_home.dispatch` Business Span) shipped in `back_vibes` (Phases 7A Backend SDK Foundation, 7B.1 HTTP + Routing, 7B.2 Queue + Console, 7B.3 generic Scheduler, and 7B.4.1 Business Telemetry domain execution review also complete)  
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
| **Grafana** | ❌ Not deployed — Phase 9 |
| **OTel SDK (backend)** | ✅ Foundation shipped — Phase 7A (`back_vibes`); ✅ HTTP + Routing shipped — Phase 7B.1; ✅ Queue + Console shipped — Phase 7B.2; ✅ generic Scheduler shipped — Phase 7B.3; ✅ Business Telemetry domain execution review (discovery only) — Phase 7B.4.1; ✅ Smart Home dispatch boundary (`smart_home.dispatch` span) — Phase 7B.4.2; remaining domain instrumentation pending (Phases 7B.4.3–7B.6) |
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
Phase 7B.4.3 ──► Smart Home Action Execution (back_vibes)
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

#### Phase 7B.4.3 — Smart Home Action Execution (`back_vibes`) — Next

**Goal:** Manual spans for `SmartHomeActionJob::handle()`, `ProviderAdapterResolver`, and `HomeAssistantAdapter` execution — the downstream half of the pipeline Phase 7B.4.2 deliberately stopped short of at the queue boundary. Its span(s) will automatically nest under `smart_home.dispatch` for free (existing trace propagation, no correlation work needed).

---

### Phase 7B.5 — Push Notifications (`back_vibes`)

**Goal:** Manual spans for push delivery, `ixora.push.*` metrics — no device tokens, Firebase UIDs, or notification body content in labels or attributes.

---

### Phase 7B.6 — External Providers (`back_vibes`)

**Goal:** Manual spans/metrics for outbound calls to external providers not already covered by generic HTTP-client auto-instrumentation (Phase 7A) — provider-specific outcome classification, no credentials or PII exported.

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
