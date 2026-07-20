# Observability Foundation MVP — task checklist

**Status:** Phase 1 + 1.5 + 2 + 2.5 + 9.5 + 3 + 3.5 + 3.75 + 4 + 5 + 5.5 + 6 + 6.5 + 7A + 7B.1 + 7B.2 + 7B.3 + 7B.4.1 + 7B.4.2 + 7B.4.3 + 7B.4.4 + 7B.4.5 + 7B.4.6 + 7B.4.7 + 7B.4.8 + 7B.4.9 + 8.0 + 8.1 + 8.2 + 8.3 + 8.4 + 8.5 + 8.6 + 8.7 + 8.8 + **8.9** complete — ADRs + Spec + Infra + Security + Guides + Collector + Validation + Metrics Philosophy + Prometheus + Loki + Logs Philosophy + Tempo + Traces Philosophy + Backend SDK Foundation + HTTP + Routing Instrumentation + Queue + Console Instrumentation + Generic Scheduler Instrumentation + Business Telemetry Domain Execution Review (discovery only) + Smart Home Dispatch Boundary + Smart Home Action Execution + Smart Home Provider Boundary + Business Failure Semantics + Business Metrics + Business Logging + Business Telemetry Foundation Baseline + Dashboard Requirements + Grafana Foundation & Provisioning + D-07 Infrastructure Dashboard + Application Dashboards (D-04 Queue, D-05 HTTP, D-06 Scheduler) + Smart Home Business Dashboard (D-02) + Platform Overview Dashboard (D-01) + Dashboard Integration & Operational Validation + D-03 Push Notifications Dashboard + Alerting Foundation + **Recording Rules & SLO Foundation**  
**Spec:** [`spec.md`](spec.md)  
**Plan:** [`plan.md`](plan.md)  
**Feature ID:** `observability-foundation/mvp`

**Status legend**

| Status | Meaning |
| --- | --- |
| **Pending** | Not started |
| **In progress** | Active work on branch |
| **Done** | Merged to `develop` / verified on staging |
| **Deferred** | Post-MVP or fast-follow |

---

## Task list summary

| Phase | Pending | In progress | Done | Deferred |
| --- | ---: | ---: | ---: | ---: |
| 1 — ADRs + Spec | 0 | 0 | 9 | 0 |
| 1.5 — Naming Convention | 0 | 0 | 1 | 0 |
| 2 — Infrastructure review | 0 | 0 | 5 | 0 |
| 2.5 — Security review | 0 | 0 | 5 | 0 |
| 3 — Collector deployment | 0 | 0 | 9 | 0 |
| 3.5 — Validation & hardening | 2 | 0 | 8 | 0 |
| 3.75 — Metrics Philosophy | 0 | 0 | 1 | 0 |
| 4 — Prometheus | 0 | 0 | 3 | 0 |
| 5 — Loki | 0 | 0 | 3 | 0 |
| 5.5 — Logs Philosophy | 0 | 0 | 1 | 0 |
| 6 — Tempo | 0 | 0 | 3 | 0 |
| 6.5 — Traces Philosophy | 0 | 0 | 1 | 0 |
| 7A — Backend SDK Foundation | 0 | 0 | 9 | 0 |
| 7B.1 — HTTP + Routing | 0 | 0 | 10 | 0 |
| 7B.2 — Queue + Console | 0 | 0 | 5 | 0 |
| 7B.3 — Generic Scheduler | 0 | 0 | 7 | 0 |
| 7B.4.1 — Business Telemetry: Domain Execution Review | 0 | 0 | 14 | 0 |
| 7B.4.2 — Smart Home Dispatch Boundary | 0 | 0 | 13 | 0 |
| 7B.4.3 — Smart Home Action Execution | 0 | 0 | 13 | 0 |
| 7B.4.4 — Smart Home Provider Boundary | 0 | 0 | 12 | 0 |
| 7B.4.5 — Business Failure Semantics | 0 | 0 | 16 | 0 |
| 7B.4.6 — Business Metrics | 0 | 0 | 14 | 0 |
| 7B.4.7 — Business Logging | 0 | 0 | 8 | 0 |
| 7B.4.8 — Telemetry Validation & Architecture Review | 0 | 0 | 7 | 0 |
| 7B.4.9 — Business Telemetry Foundation Baseline | 0 | 0 | 5 | 0 |
| 8.0 — Dashboard Requirements Review | 0 | 0 | 4 | 0 |
| 8.1 — Grafana Foundation & Provisioning | 0 | 0 | 7 | 0 |
| 8.2 — D-07 Infrastructure Dashboard | 0 | 0 | 7 | 0 |
| 8.3 — Application Infrastructure Dashboards | 0 | 0 | 9 | 0 |
| 8.4 — Smart Home Business Dashboard (D-02) | 0 | 0 | 7 | 0 |
| 7B.5 — Push Notifications | 3 | 0 | 0 | 0 |
| 7B.6 — External Providers | 3 | 0 | 0 | 0 |
| 8 — Frontend SDK | 5 | 0 | 0 | 0 |
| 9 — Dashboards | 5 | 0 | 0 | 0 |
| 9.5 — Decision Guide + Playbook | 0 | 0 | 2 | 0 |
| 10 — Operational readiness | 4 | 0 | 0 | 0 |
| 11 — QA | 5 | 0 | 0 | 0 |
| 11.5 — Appium telemetry QA | 3 | 0 | 0 | 0 |
| Release | 3 | 0 | 0 | 0 |

---

## Phase 1 — ADRs + Spec

| ID | Task | Status | Reference |
| --- | --- | --- | --- |
| P1-1 | Draft **ADR-028** — Observability platform | **Done** | [`ADR-028`](../../../decisions/ADR-028-observability-platform.md) |
| P1-2 | Draft **ADR-029** — Telemetry data model | **Done** | [`ADR-029`](../../../decisions/ADR-029-telemetry-data-model.md) |
| P1-3 | Draft **ADR-030** — Security and privacy | **Done** | [`ADR-030`](../../../decisions/ADR-030-observability-security-and-privacy.md) |
| P1-4 | Draft **ADR-031** — Retention and cost control | **Done** | [`ADR-031`](../../../decisions/ADR-031-retention-storage-and-cost-control.md) |
| P1-5 | Publish **`spec.md`** | **Done** | [`spec.md`](spec.md) |
| P1-6 | Publish **`plan.md`** | **Done** | [`plan.md`](plan.md) |
| P1-7 | Publish **`tasks.md`** | **Done** | This file |
| P1-8 | Update **`docs/README.md`** | **Done** | [`README.md`](../../../README.md) |
| P1-9 | Confirm **no runtime code** in Phase 1 | **Done** | This phase |

**Branch:** `feature/observability-foundation-spec-adrs` from **`develop`**

**Phase 1 implementation notes:**

- Four ADRs (028–031) define platform topology, data model, security, and retention.
- Spec defines goals, non-goals, architecture mapping, and review checklist.
- Collector-only ingestion is mandatory; apps never talk directly to Prometheus/Loki/Tempo.
- MVP targets single DigitalOcean VM; staging first.
- No OpenTelemetry SDK, Collector configs, Docker, Terraform, or Grafana in Phase 1.

---

## Phase 1.5 — Telemetry Naming Convention

| ID | Task | Status | Reference |
| --- | --- | --- | --- |
| P1.5-1 | Publish **`telemetry-naming-convention.md`** | **Done** | [`telemetry-naming-convention.md`](../../../architecture/telemetry-naming-convention.md) |

**Phase 1.5 implementation notes:**

- Platform-wide naming standard for services, metrics, spans, logs, events, labels, dashboards, and alerts.
- Documentation only — no runtime code, SDK, Collector, Grafana, or infrastructure changes.
- All implementation phases (2–11.5) must follow this guide.

---

## Phase 2 — Infrastructure review

| ID | Task | Status | Reference |
| --- | --- | --- | --- |
| P2-1 | Document DO VM sizing (CPU/RAM/disk) vs ADR-031 budgets | **Done** | [`infrastructure-review.md`](infrastructure-review.md) §6, §10 |
| P2-2 | Document firewall / OTLP ingress from App Platform + mobile | **Done** | [`infrastructure-review.md`](infrastructure-review.md) §4, §5 |
| P2-3 | Document Collector endpoint DNS/TLS strategy | **Done** | [`infrastructure-review.md`](infrastructure-review.md) §5 |
| P2-4 | Review App Platform egress to observability VM | **Done** | [`infrastructure-review.md`](infrastructure-review.md) §1, §3 · [staging-digitalocean](../../../architecture/backend/staging-digitalocean.md) |
| P2-5 | Publish infrastructure review note | **Done** | [`infrastructure-review.md`](infrastructure-review.md) |

**Branch:** `feature/observability-infra-review`

**Phase 2 implementation notes:**

- Single DO Droplet topology validated; all components co-located for MVP staging.
- Communication matrix, ports, storage budgets, failure analysis, and scaling path documented.
- Documentation only — no runtime code, OpenTofu, Docker, Collector config, or DO resources created.
- Implementation begins in **Phase 3 — Collector Deployment**.

---

## Phase 2.5 — Security review + telemetry availability

| ID | Task | Status | Reference |
| --- | --- | --- | --- |
| P2.5-1 | Publish **`security-review.md`** — threat model, auth, TLS, PII, redaction | **Done** | [`security-review.md`](security-review.md) |
| P2.5-2 | Publish **`telemetry-availability-policy.md`** — non-blocking export rules | **Done** | [`telemetry-availability-policy.md`](../../../architecture/telemetry-availability-policy.md) |
| P2.5-3 | Publish **`observability-operational-limits.md`** — architectural caps | **Done** | [`observability-operational-limits.md`](../../../architecture/observability-operational-limits.md) |
| P2.5-4 | Publish **`collector-hardening-checklist.md`** — Phase 3 deploy checklist | **Done** | [`collector-hardening-checklist.md`](../../../operations/collector-hardening-checklist.md) |
| P2.5-5 | Update **`spec.md`**, **`README.md`**, cross-links | **Done** | This file |

**Branch:** `feature/observability-security-review`

**Phase 2.5 implementation notes:**

- MVP ingest auth: **OTLP API Keys + TLS** (mTLS deferred for mobile).
- Collector redaction is second line of defense after application discipline.
- Telemetry must never block business logic — aligns with ADR-028/029 and push best-effort.
- Operational limits are architectural; concrete values set in Phase 3+.
- Documentation only — no runtime code, Collector config, Docker, OpenTofu, or DO resources.
- **Next:** Phase 3 — Collector Deployment using collector-hardening-checklist.

---

## Phase 3 — Collector deployment

| ID | Task | Status | Reference |
| --- | --- | --- | --- |
| P3-1 | Create `collector/config.yaml` — OTLP receivers, processors, extensions, pipelines | **Done** | [`collector-deployment.md`](collector-deployment.md) |
| P3-2 | Configure OTLP receivers: gRPC `:4317`, HTTP `:4318`, mobile `:4319` | **Done** | [`ADR-028`](../../../decisions/ADR-028-observability-platform.md) |
| P3-3 | Configure processors: memory_limiter, batch, resource, redact_secrets, drop_high_cardinality, transform, probabilistic_sampler | **Done** | [`ADR-030`](../../../decisions/ADR-030-observability-security-and-privacy.md) · [`ADR-031`](../../../decisions/ADR-031-retention-storage-and-cost-control.md) |
| P3-4 | Configure extensions: health_check, pprof, zpages, bearertokenauth (backend + mobile) | **Done** | [`security-review.md`](security-review.md) |
| P3-5 | Create `collector/docker-compose.yml` — Collector active; Phase 4–9 backends stubbed | **Done** | [`infrastructure-review.md`](infrastructure-review.md) |
| P3-6 | Create `collector/.env.example` — all secrets via env vars | **Done** | [`security-review.md §6`](security-review.md) |
| P3-7 | Create `collector/README.md` — quick start, validation checklist, upgrade strategy | **Done** | |
| P3-8 | Create `collector-deployment.md` — full deployment spec with security, limits, phase stubs | **Done** | |
| P3-9 | Deploy Collector on DO VM and verify health endpoint (runtime step) | **Done** (local Docker validation; VM deploy deferred) | [`collector-hardening-checklist.md`](../../../operations/collector-hardening-checklist.md) |

**Phase 3 implementation notes:**

- Collector is the ONLY active Docker Compose service; all backends are documented stubs.
- API key authentication via `bearertokenauth` extension — separate keys for backend and mobile.
- Redaction processor drops 18 forbidden credential + PII keys per ADR-030.
- Cardinality control processor drops 7 high-cardinality metric labels per ADR-031.
- Memory limiter (512 MiB) and batch processor protect VM per observability-operational-limits.md.
- All exporter sections commented — debug exporter only for Phase 3 validation.
- TLS-ready: `tls:` block in receivers commented; activate when cert paths confirmed.
- No application repositories modified. No back_vibes. No front_vibes. No other infra changes.
- **P3-9 validated locally via Docker; DO VM firewall/TLS deferred to VM provisioning.**

**Branch:** `feature/observability-collector-deploy`

---

## Phase 3.5 — Collector validation & hardening

| ID | Task | Status | Reference |
| --- | --- | --- | --- |
| P3.5-1 | Validate config syntax (`otelcol-contrib validate`) | **Done** | [`collector-validation-report.md`](collector-validation-report.md) |
| P3.5-2 | Validate startup, restart, health endpoint | **Done** | Cold start 1163 ms; restart 5866 ms |
| P3.5-3 | Validate authentication (401/200 matrix) | **Done** | Backend + mobile keys; cross-port rejection |
| P3.5-4 | Validate processors (redaction, sampling, batch, memory) | **Done** | Spot check + config audit |
| P3.5-5 | Run failure tests (malformed, oversized, missing env) | **Done** | Collector survives all failure cases |
| P3.5-6 | Security validation (secrets, ports, debug exporter) | **Done** | [`collector-hardening-checklist.md §13`](../../../operations/collector-hardening-checklist.md) |
| P3.5-7 | Performance baseline (CPU, memory, latency) | **Done** | ~30 MiB idle; ~1 ms health latency |
| P3.5-8 | Fix defects found during validation (auth, image, healthcheck, bind) | **Done** | 6 defects fixed — see validation report |
| P3.5-9 | Publish `collector-validation-report.md` | **Done** | |
| P3.5-10 | VM firewall + TLS termination on DO Droplet | **Pending** | [`security-review.md`](security-review.md) |
| P3.5-11 | Flood test on observability VM | **Pending** | VM deploy |

**Phase 3.5 implementation notes:**

- Six configuration defects found and fixed during validation (auth placement, image tag, feature gate, healthcheck, internal bind addresses, compose version).
- All testable hardening checklist items pass; VM-dependent items (firewall, TLS, flood) deferred.
- `debug` exporter remains active until Phase 4 — documented exception.
- Collector ready for Phase 4 (Prometheus) after removing debug exporter.
- No application repositories modified.

**Branch:** `feature/observability-collector-validation`

---

## Phase 3.75 — Metrics Philosophy

| ID | Task | Status | Reference |
| --- | --- | --- | --- |
| P3.75-1 | Publish **`metrics-philosophy.md`** | **Done** | [`metrics-philosophy.md`](../../../architecture/metrics-philosophy.md) |

**Phase 3.75 implementation notes:**

- Platform-wide guide for how engineers think about metrics — not a Prometheus manual or OTel tutorial.
- Mandatory reading before Phases 7A and 7B (backend instrumentation).
- Complements naming convention (names) and decision guide (signal choice).
- Documentation only — no runtime code, SDK, Collector, Prometheus, Grafana, or infrastructure changes.
- Validated against ADRs 028–031, security review, and collector validation report.

**Branch:** `feature/observability-metrics-philosophy`

---

## Phase 4 — Prometheus

| ID | Task | Status | Reference |
| --- | --- | --- | --- |
| P4-1 | Deploy Prometheus with 30-day retention | **Done** | [`ADR-031`](../../../decisions/ADR-031-retention-storage-and-cost-control.md) · [`prometheus-deployment.md`](prometheus-deployment.md) |
| P4-2 | Wire Collector → Prometheus exporter | **Done** | [`ADR-028`](../../../decisions/ADR-028-observability-platform.md) · [`collector/config.yaml`](../../../../collector/config.yaml) |
| P4-3 | Verify `up` metric and retention flag | **Done** | [`prometheus-deployment.md §9`](prometheus-deployment.md) |

**Branch:** `feature/observability-prometheus`

**Phase 4 implementation notes:**

- `collector/prometheus/prometheus.yml` created — self-scrape only; no application targets.
- `prometheusremotewrite` exporter enabled in `collector/config.yaml`; endpoint via Docker service name `http://prometheus:9090/api/v1/write`.
- `debug` exporter removed from metrics pipeline; retained in logs and traces pipelines until Phase 5/6.
- Prometheus service enabled in `collector/docker-compose.yml`: `127.0.0.1:9090` host binding (internal only), 30-day retention, WAL compression, remote write receiver, lifecycle API.
- `collector/.env.example` updated: `PROMETHEUS_VERSION`, `PROMETHEUS_REMOTE_WRITE_ENDPOINT`, `PROMETHEUS_PORT`.
- `collector/README.md` updated: Phase 4 quick start, validation checklist, ports table, upgrade strategy.
- `prometheus-deployment.md` published: architecture, container spec, volumes, retention, security, Collector changes, validation steps, upgrade strategy.
- No application repositories modified. No back_vibes. No front_vibes. No Grafana. No Loki. No Tempo.

---

## Phase 5 — Loki

| ID | Task | Status | Reference |
| --- | --- | --- | --- |
| P5-1 | Deploy Loki with 14-day retention | **Done** | [`loki-deployment.md`](loki-deployment.md) · [`ADR-031`](../../../decisions/ADR-031-retention-storage-and-cost-control.md) |
| P5-2 | Wire Collector → Loki exporter | **Done** | [`collector/config.yaml`](../../../../collector/config.yaml) |
| P5-3 | Verify log ingest + query | **Done** | [`loki-deployment.md §9`](loki-deployment.md) |

**Branch:** `feature/observability-loki`

---

## Phase 5.5 — Logs Philosophy

| ID | Task | Status | Reference |
| --- | --- | --- | --- |
| P5.5-1 | Publish **`logs-philosophy.md`** | **Done** | [`logs-philosophy.md`](../../../architecture/logs-philosophy.md) |

**Phase 5.5 implementation notes:**

- Documentation-only phase — no Collector, Loki, Prometheus, Tempo, Grafana, or application changes.
- Mandatory reading before Phases 7 and 8 (application instrumentation).
- Complements [metrics-philosophy.md](../../../architecture/metrics-philosophy.md) (Phase 3.75).

**Branch:** `feature/observability-logs-philosophy`

---

## Phase 6 — Tempo

| ID | Task | Status | Reference |
| --- | --- | --- | --- |
| P6-1 | Deploy Tempo with 7-day retention | **Done** | [`tempo-deployment.md`](tempo-deployment.md) · [`ADR-031`](../../../decisions/ADR-031-retention-storage-and-cost-control.md) |
| P6-2 | Wire Collector → Tempo with head sampling; remove debug exporter | **Done** | [`collector/config.yaml`](../../../../collector/config.yaml) |
| P6-3 | Verify trace ingest + `trace_id` search | **Done** | [`tempo-deployment.md §9`](tempo-deployment.md) |

**Branch:** `feature/observability-tempo`

**Phase 6 implementation notes:**

- `collector/tempo/tempo.yaml` created — Tempo 2.6.0, filesystem storage, 7-day retention, OTLP receivers (gRPC + HTTP), WAL, compactor, search, `metrics_generator` disabled.
- `otlp/tempo` exporter enabled in `collector/config.yaml`; endpoint via Docker service name `http://tempo:4317`.
- `debug` exporter **fully removed** — eliminated from all three pipelines (metrics Phase 4, logs Phase 5, traces Phase 6).
- Tempo service enabled in `collector/docker-compose.yml`: `127.0.0.1:3200` (HTTP query) and `127.0.0.1:4317` (OTLP gRPC) host bindings, 7-day retention, WAL, named volume `tempo_data`.
- `collector/.env.example` updated: `TEMPO_VERSION`, `TEMPO_ENDPOINT`, `TEMPO_PORT`, `TEMPO_OTLP_GRPC_PORT`.
- `collector/README.md` updated: Phase 6 quick start, validation checklist, ports table, upgrade strategy.
- `tempo-deployment.md` published: architecture, container spec, volumes, sampling, retention, security, Collector changes, object-storage migration note, validation steps, upgrade strategy.
- Traces pipeline sampling: probabilistic_sampler retained (10% success). Tail sampling documented as Phase 7+ evolution.
- Metrics pipeline (Prometheus) and logs pipeline (Loki) are **unchanged**.
- No application repositories modified. No `back_vibes`. No `front_vibes`. No Grafana. No Prometheus. No Loki changes.

---

## Phase 6.5 — Traces Philosophy

| ID | Task | Status | Reference |
| --- | --- | --- | --- |
| P6.5-1 | Publish **`traces-philosophy.md`** | **Done** | [`traces-philosophy.md`](../../../architecture/traces-philosophy.md) |

**Phase 6.5 implementation notes:**

- Platform-wide guide for how engineers think about traces — not a Tempo manual or OTel tutorial.
- Mandatory reading before Phases 7 and 8 (application instrumentation).
- Complements [metrics-philosophy.md](../../../architecture/metrics-philosophy.md) (Phase 3.75) and [logs-philosophy.md](../../../architecture/logs-philosophy.md) (Phase 5.5).
- Documentation only — no runtime code, SDK, Collector, Tempo, Prometheus, Loki, Grafana, or infrastructure changes.
- Validated against ADRs 028–031, security review, collector validation report, and tempo deployment.

**Branch:** `feature/observability-traces-philosophy`

---

## Phase 7A — Backend SDK Foundation

**Prerequisite:** [metrics-philosophy.md](../../../architecture/metrics-philosophy.md) (Phase 3.75) · [logs-philosophy.md](../../../architecture/logs-philosophy.md) (Phase 5.5) · [traces-philosophy.md](../../../architecture/traces-philosophy.md) (Phase 6.5).

| ID | Task | Status | Reference |
| --- | --- | --- | --- |
| P7A-1 | Evaluate OpenTelemetry PHP ecosystem; select official SDK + auto-instrumentation packages | **Done** | [`backend-sdk-foundation.md §2`](backend-sdk-foundation.md) |
| P7A-2 | Install `open-telemetry/{api,sdk,sem-conv,exporter-otlp}` + `opentelemetry-auto-{laravel,guzzle,pdo}` in `back_vibes` | **Done** | `back_vibes/composer.json` |
| P7A-3 | Build Telemetry Abstraction Layer (`app/Telemetry/{Contracts,OpenTelemetry,Noop,Providers,Context,Configuration,Resources,Logging}`) | **Done** | [`backend-sdk-foundation.md §3`](backend-sdk-foundation.md) |
| P7A-4 | Wire `TelemetryServiceProvider`; bind Telemetry Contracts to the OpenTelemetry implementation (or No-op when disabled) | **Done** | [`backend-sdk-foundation.md §3.2`](backend-sdk-foundation.md) |
| P7A-5 | Enable generic auto-instrumentation (HTTP, routing, console, queue, DB) via env — no domain instrumentation | **Done** | [`backend-sdk-foundation.md §7`](backend-sdk-foundation.md) |
| P7A-6 | Inject `trace_id` / `span_id` into Laravel log context without altering messages | **Done** | [`backend-sdk-foundation.md §8`](backend-sdk-foundation.md) |
| P7A-7 | Configuration via env vars; resource attributes; `.env.example` documented | **Done** | [`backend-sdk-foundation.md §5–6`](backend-sdk-foundation.md) · `back_vibes/.env.example` |
| P7A-8 | Validate failure policy — Collector unavailable never fails requests/jobs | **Done** | [`backend-sdk-foundation.md §4.3, §7`](backend-sdk-foundation.md) |
| P7A-9 | Tests: bootstrap, config, contract resolution, log correlation, failure isolation, dependency rule | **Done** | [`backend-sdk-foundation.md §11`](backend-sdk-foundation.md) · `back_vibes/tests/{Unit,Feature}/Telemetry` |

**Phase 7A implementation notes:**

- `app/Telemetry/` module created in `back_vibes` — Contracts, OpenTelemetry implementation, No-op implementation, Configuration, Resources, Context, Logging, Providers.
- Dependency Rule enforced structurally and by an automated test (`DependencyRuleTest`) — no `OpenTelemetry\*` import exists outside `app/Telemetry/OpenTelemetry`.
- SDK bootstrap uses the OpenTelemetry SDK's own `SdkAutoloader` (`OTEL_PHP_AUTOLOAD_ENABLED=true`, real process env) rather than a custom bootstrap — avoids a race with auto-instrumentation hooks; see `backend-sdk-foundation.md §4`.
- No manual spans, no custom metrics, no custom logs, no Scheduler/Smart Home/Push/Marketplace/AI instrumentation — verified by review and by `DependencyRuleTest`.
- No business rules, controllers, policies, validators, existing providers, jobs, commands, services, repositories, or database schema modified.
- Redis auto-instrumentation **not enabled** — no official `open-telemetry`-org package exists; documented gap (`backend-sdk-foundation.md §9`).
- 27 new tests added; full `back_vibes` suite (737 tests) green after this phase.
- 737/737 tests pass; no forbidden ADR-030 fields present in resource attributes (tested).
- **Next:** Phase 7B.1 — HTTP + Routing (now complete, see below), followed by Phases 7B.2–7B.6 (Queue + Console, Scheduler, Smart Home, Push, External Providers), using only the Telemetry Contracts from this phase.

**Branch:** `feature/observability-backend-sdk-foundation`

---

## Phase 7B.1 — HTTP + Routing

**Prerequisite:** Phase 7A (Backend SDK Foundation) · [metrics-philosophy.md](../../../architecture/metrics-philosophy.md) · [logs-philosophy.md](../../../architecture/logs-philosophy.md) · [traces-philosophy.md](../../../architecture/traces-philosophy.md) · [telemetry-decision-guide.md](../../../architecture/telemetry-decision-guide.md).

**Complete.**

| ID | Task | Status | Reference |
| --- | --- | --- | --- |
| P7B1-1 | Review `opentelemetry-auto-laravel` HTTP Kernel hook — root span naming, route/status attributes, exception recording, 404/405/401/422 behavior | **Done** | [`backend-http-routing-instrumentation.md §2`](backend-http-routing-instrumentation.md) |
| P7B1-2 | Build `app/Telemetry/Http/` (`HttpRequestTelemetry`, `HttpRouteNormalizer`, `HttpOutcome`, `HttpExceptionStatus`) | **Done** | [`backend-http-routing-instrumentation.md §3`](backend-http-routing-instrumentation.md) |
| P7B1-3 | Add `Tracer::activeSpan()` — documented, additive contract change for span enrichment | **Done** | [`backend-http-routing-instrumentation.md §4`](backend-http-routing-instrumentation.md) |
| P7B1-4 | Implement `HttpTelemetryMiddleware` at the HTTP lifecycle boundary (global, appended) | **Done** | [`backend-http-routing-instrumentation.md §5`](backend-http-routing-instrumentation.md) |
| P7B1-5 | Wire `ixora.http.server.request.total` (Counter) + `ixora.http.server.duration` (Histogram, ms) | **Done** | [`backend-http-routing-instrumentation.md §6`](backend-http-routing-instrumentation.md) |
| P7B1-6 | Enrich existing active HTTP span with safe attributes | **Done** | [`backend-http-routing-instrumentation.md §7`](backend-http-routing-instrumentation.md) |
| P7B1-7 | Add `HttpErrorContextLogTap` — enrich existing error logs with HTTP context, no routine success logs | **Done** | [`backend-http-routing-instrumentation.md §8`](backend-http-routing-instrumentation.md) |
| P7B1-8 | Document `Log::build()` on-demand channel limitation | **Done** | [`backend-sdk-foundation.md §8.5`](backend-sdk-foundation.md#85-known-limitation-logbuild-on-demand-channels-are-not-tapped) |
| P7B1-9 | Tests: success, 404, 405, validation, auth failure, server exception, Collector unavailable, cardinality safety, dependency rule, no double-counting | **Done** | [`backend-http-routing-instrumentation.md §10`](backend-http-routing-instrumentation.md) · `back_vibes/tests/{Unit,Feature}/Telemetry/Http` |
| P7B1-10 | Verify no forbidden fields (labels/attributes) in exported telemetry | **Done** | [`ADR-030`](../../../decisions/ADR-030-observability-security-and-privacy.md) · [`backend-http-routing-instrumentation.md §6–7`](backend-http-routing-instrumentation.md) |

**Phase 7B.1 implementation notes:**

- Existing auto-instrumented HTTP server span reused and enriched — no second root span created.
- Only one additive Telemetry Contract change across all of Phase 7B.1: `Tracer::activeSpan()` — a real, proven blocker (no way to enrich an ambient span otherwise), fully documented (`backend-http-routing-instrumentation.md §4`). `Meter`, `Counter`, `Histogram`, `Span`, `LoggerCorrelation` untouched.
- Verified empirically that `Illuminate\Routing\Pipeline` converts every exception (404/405/422/401/5xx) into a `Response` before it reaches global middleware — `HttpRequestTelemetry::recordResponse()` is therefore the path taken by every real request; `recordException()` is a defensive fallback exercised directly in tests.
- 48 new tests added; full `back_vibes` suite (785 tests) green after this phase; `pint --test` passes.
- No Queue, Console, Scheduler, Smart Home, Push, or external-provider instrumentation added.
- **Next:** Phase 7B.2 — Queue + Console (now complete, see below), using the same Telemetry Contracts (including `activeSpan()`).

**Branch:** `feature/observability-http-routing-instrumentation`

---

## Phase 7B.2 — Queue + Console

**Prerequisite:** Phase 7B.1 (HTTP + Routing).

| ID | Task | Status | Reference |
| --- | --- | --- | --- |
| P7B2-1 | Review `opentelemetry-auto-laravel` queue/console hooks — span reuse vs. new spans | **Done** | [`backend-queue-console-instrumentation.md §2–§3`](backend-queue-console-instrumentation.md) |
| P7B2-2 | Queue telemetry: enrich existing auto-instrumented span, `ixora.queue.job.*` metrics | **Done** | Uses `App\Telemetry\Contracts\{Tracer,Meter}` only — `back_vibes/app/Telemetry/Queue/` |
| P7B2-3 | Console telemetry: best-effort span enrichment, `ixora.console.command.*` metrics | **Done** | `back_vibes/app/Telemetry/Console/` |
| P7B2-4 | Custom metrics (`ixora.queue.job.total/duration/active`, `ixora.console.command.total/duration`) per metrics-philosophy.md | **Done** | [`backend-queue-console-instrumentation.md §5`](backend-queue-console-instrumentation.md) |
| P7B2-5 | Verify no forbidden fields in exported telemetry | **Done** | [`ADR-030`](../../../decisions/ADR-030-observability-security-and-privacy.md) · [`backend-queue-console-instrumentation.md §5–6`](backend-queue-console-instrumentation.md) |

**Phase 7B.2 implementation notes:**

- Existing auto-instrumented queue consumer/sync span reused and enriched — no second root span created. Console's per-command auto-instrumented span exists but is unreachable from `CommandStarting`/`CommandFinished` (timing gap, documented) — metrics and log context are unaffected.
- Zero Telemetry Contract changes — Phase 7B.2 consumes `Tracer`, `Meter`, `Counter`, `Histogram`, `UpDownCounter` exactly as they existed after Phase 7B.1 (`activeSpan()` included).
- Verified empirically that `CommandStarting`/`CommandFinished` never fire during `back_vibes`'s own `APP_ENV=testing` test runs — console tests dispatch these events directly rather than through `$this->artisan()`.
- 51 new tests added; full `back_vibes` suite (836 tests) green after this phase; `pint --test` passes.
- No Scheduler, Smart Home, Push, or external-provider instrumentation added.
- **Next:** Phase 7B.3 — Generic Scheduler (now complete, see below), using the same Telemetry Contracts.

**Branch:** `feature/observability-queue-console-instrumentation`

---

## Phase 7B.3 — Generic Scheduler

**Prerequisite:** Phase 7B.1 (HTTP + Routing), Phase 7B.2 (Queue + Console).

| ID | Task | Status | Reference |
| --- | --- | --- | --- |
| P7B3-1 | Review `opentelemetry-auto-laravel` + Laravel Scheduler lifecycle — no official span exists for a scheduled-event boundary; Strategy B (new boundary span) | **Done** | [`backend-generic-scheduler-instrumentation.md §2`](backend-generic-scheduler-instrumentation.md) |
| P7B3-2 | Scheduler telemetry: `Tracer::startSpan()` boundary span, `ixora.scheduler.event.*` metrics | **Done** | Uses `App\Telemetry\Contracts\{Tracer,Meter}` only — `back_vibes/app/Telemetry/Scheduler/` |
| P7B3-3 | Event normalization (`SchedulerEventNormalizer`/`SchedulerEventType`) — bounded command/closure/callback/shell names, never full command line or closure source | **Done** | [`backend-generic-scheduler-instrumentation.md §8`](backend-generic-scheduler-instrumentation.md) |
| P7B3-4 | Custom metrics (`ixora.scheduler.event.total/duration`) per metrics-philosophy.md — `ixora.scheduler.event.active` deliberately omitted | **Done** | [`backend-generic-scheduler-instrumentation.md §6`](backend-generic-scheduler-instrumentation.md) |
| P7B3-5 | Scheduled-versus-manual command strategy evaluated — `invocation_source` not added to Console metrics (not reliable across the command-event process boundary); limitation documented instead | **Done** | [`backend-generic-scheduler-instrumentation.md §15`](backend-generic-scheduler-instrumentation.md) |
| P7B3-6 | `App\Telemetry\Logging\SchedulerErrorContextLogTap` — safe error-log context, verified isolated from HTTP/Queue/Console | **Done** | `back_vibes/app/Telemetry/Logging/` |
| P7B3-7 | Verify no forbidden fields in exported telemetry (cron expressions, mutex keys, process IDs, `Schedule`/Vibe/user/device IDs) | **Done** | [`ADR-030`](../../../decisions/ADR-030-observability-security-and-privacy.md) · [`backend-generic-scheduler-instrumentation.md §6, §14`](backend-generic-scheduler-instrumentation.md) |

**Phase 7B.3 implementation notes:**

- No existing span or metric represents a scheduled-event boundary anywhere in this stack (`opentelemetry-auto-laravel` ships no Scheduling hook) — Strategy B was the only option, not a preference over Strategy A. One new boundary span is created per executed event via `Tracer::startSpan()` — the first caller of that Contract method in this Telemetry Abstraction Layer; `RecordingTracer`/`TelemetryRecorder` test fakes were extended accordingly.
- Zero Telemetry Contract changes — Phase 7B.3 consumes `Tracer`, `Meter`, `Counter`, `Histogram`, `Span` exactly as they existed after Phase 7B.2.
- Verified empirically that a command scheduled event always shells out to a separate OS process with no trace-context propagation — a documented, honest limitation, not something this phase's Contracts-only module could close without editing Scheduler business logic (forbidden).
- `back_vibes` does not currently register any native `Schedule::` entry — it uses a custom `schedules:dispatch-loop` domain command instead; this phase's telemetry covers the generic framework surface for forward compatibility, not `back_vibes`'s current domain dispatch path.
- 33 new tests added; full `back_vibes` suite (869 tests) green after this phase; `pint --test` passes.
- Level 2 (Ixora Domain Scheduling — Vibe scheduling, `Schedule` model orchestration, Smart Home, Push, provider execution) is explicitly deferred — no domain knowledge added to `app/Telemetry/Scheduler`.
- No Smart Home, Push, or external-provider instrumentation added.
- **Next:** Phase 7B.4.1 — Business Telemetry Domain Execution Review (now complete, see below), then Phase 7B.4.2 — Smart Home Dispatch Boundary (now also complete, see below), using the same Telemetry Contracts.

**Branch:** `feature/observability-generic-scheduler-instrumentation`

---

## Phase 7B.4.1 — Business Telemetry: Domain Execution Review (discovery only)

**Prerequisite:** Phase 7B.3 (Generic Scheduler) — Infrastructure Telemetry foundation considered complete; this phase is the first to target the **Business Telemetry** layer instead of generic Laravel infrastructure.

**Type:** Architecture review only. No telemetry, spans, metrics, logs, OpenTelemetry code, behavior changes, refactors, database/API/frontend changes, or new abstractions permitted — the only acceptable source-code changes were documentation comments (none were needed).

| ID | Task | Status | Reference |
| --- | --- | --- | --- |
| P7B4.1-1 | Find every Smart Home execution entry point (manual dispatch, scheduled dispatch, provider sync as adjacent-not-execution; confirmed no native Scheduler/event-listener/webhook/Artisan-command/queue-retry entry points exist) | **Done** | [`domain-execution-review.md §1`](../business-telemetry/domain-execution-review.md) |
| P7B4.1-2 | Trace the complete execution pipeline / call graph from every entry point to the final provider HTTP call | **Done** | [`domain-execution-review.md §2`](../business-telemetry/domain-execution-review.md) |
| P7B4.1-3 | Identify the orchestrator(s) — found two sibling entry-point orchestrators converging on a shared dispatch service + job layer, matching ADR-027's layering exactly | **Done** | [`domain-execution-review.md §3`](../business-telemetry/domain-execution-review.md) |
| P7B4.1-4 | Identify domain boundaries actually present in code (Trigger Resolution → Automation Validation → Vibe Action Resolution → Job Enqueue → Device Action Resolution → Provider Resolution → Provider Call → Result → Notification) | **Done** | [`domain-execution-review.md §4`](../business-telemetry/domain-execution-review.md) |
| P7B4.1-5 | Identify domain objects, ownership, and lifecycle (`Vibe`, `Device`, `VibeDeviceAction`, `ProviderConnection`, `Schedule`, `ScheduleExecution`, DTOs) — confirmed no persisted "execution" object exists for Smart Home | **Done** | [`domain-execution-review.md §5`](../business-telemetry/domain-execution-review.md) |
| P7B4.1-6 | Identify current execution model (sequential batch, fan-out enqueue, no fan-in) | **Done** | [`domain-execution-review.md §6`](../business-telemetry/domain-execution-review.md) |
| P7B4.1-7 | Identify failure model (best-effort, isolate-and-continue, log-only; no retry/dead-letter/compensation/rollback in practice) | **Done** | [`domain-execution-review.md §7`](../business-telemetry/domain-execution-review.md) |
| P7B4.1-8 | Identify cancellation model — confirmed not implemented (no cancel/abort/pause/resume/scheduled-retry domain concept) | **Done** | [`domain-execution-review.md §8`](../business-telemetry/domain-execution-review.md) |
| P7B4.1-9 | Identify the provider boundary (`ProviderAdapter` contract / `HomeAssistantAdapter`) without reviewing provider internals | **Done** | [`domain-execution-review.md §9`](../business-telemetry/domain-execution-review.md) |
| P7B4.1-10 | Recommend candidate future telemetry boundaries based only on discovered architecture | **Done** | [`domain-execution-review.md §10`](../business-telemetry/domain-execution-review.md) |
| P7B4.1-11 | Review current observability (logs, events, metrics, exceptions, history, audit, state transitions) | **Done** | [`domain-execution-review.md §11`](../business-telemetry/domain-execution-review.md) |
| P7B4.1-12 | Review duplication risks against existing HTTP/Queue/Console/Scheduler/Push telemetry | **Done** | [`domain-execution-review.md §12`](../business-telemetry/domain-execution-review.md) |
| P7B4.1-13 | Review existing test coverage (covered / partially covered / not covered) — no tests added | **Done** | [`domain-execution-review.md §13`](../business-telemetry/domain-execution-review.md) |
| P7B4.1-14 | Write `domain-execution-review.md` with unknowns, open questions, and recommendations for Phase 7B.4.2 | **Done** | [`domain-execution-review.md`](../business-telemetry/domain-execution-review.md) |

**Phase 7B.4.1 implementation notes:**

- Zero source-code changes to `back_vibes` — this phase produced documentation only, cross-referencing existing ADRs (022, 023, 024, 026, 027) and the existing `scheduler-smart-home-e2e.md` QA reference rather than duplicating them.
- Key finding: both real entry points (manual mobile dispatch via `VibeSmartHomeDispatchController`, scheduled dispatch via `DispatchDueSchedulesCommand`) converge on the same `VibeSmartHomeDispatchService` → `SmartHomeActionJob` → `HomeAssistantAdapter` pipeline — there is no separate business logic per entry point.
- Key gap identified (not fixed in this phase): no correlation ID connects a trigger (schedule tick or manual API call) to the `SmartHomeActionJob` instances it causes — the job carries only an integer `vibe_device_action_id`. This must be resolved as a design decision before Phase 7B.4.2 writes any span code.
- Key gap identified (not fixed in this phase): no persisted execution-outcome record exists for Smart Home actions — only structured logs. `ScheduleExecution` audits the schedule tick, never the actions it triggered.
- No tests added or modified — this was a read-only discovery phase.
- **Next:** Phase 7B.4.2 — Smart Home Dispatch Boundary, using this review as its starting brief.

**Branch:** `feature/observability-business-telemetry-domain-execution-review`

---

## Phase 7B.4.2 — Smart Home Dispatch Boundary

**Prerequisite:** Phase 7B.1 (HTTP + Routing), Phase 7B.2 (Queue + Console), Phase 7B.4.1 (Domain Execution Review — authoritative architectural reference, never contradicted by this phase).

**Type:** First Business Telemetry implementation. Owns exactly one boundary — `VibeSmartHomeDispatchService::dispatch()` — and nothing else (not `SmartHomeActionJob`, not `ProviderAdapterResolver`/`HomeAssistantAdapter`, no business metrics, no business logging).

| ID | Task | Status | Reference |
| --- | --- | --- | --- |
| P7B4.2-1 | Pre-implementation review: auto-instrumentation, Phase 7B.2 Queue trace-context propagation, active-span reuse across `dispatch()` → `SmartHomeActionJob::dispatch()` → Queue → `handle()` | **Done** | [`backend-smart-home-dispatch-boundary.md §2`](../business-telemetry/backend-smart-home-dispatch-boundary.md) |
| P7B4.2-2 | Implementation Gate decision — confirmed OTel already propagates TraceContext correctly across the queue boundary; reuse it, implement no custom correlation ID/context/propagation | **Done** | [`backend-smart-home-dispatch-boundary.md §2`](../business-telemetry/backend-smart-home-dispatch-boundary.md) |
| P7B4.2-3 | Decide instrumentation point — wrap the two call sites (Controller, Command) instead of editing `VibeSmartHomeDispatchService` itself, since no Laravel event exists to hook | **Done** | [`backend-smart-home-dispatch-boundary.md §3`](../business-telemetry/backend-smart-home-dispatch-boundary.md) |
| P7B4.2-4 | Create `App\Telemetry\SmartHome\SmartHomeDispatchEntryPoint` enum (`manual`/`scheduled`/`future`, reserved) | **Done** | `app/Telemetry/SmartHome/SmartHomeDispatchEntryPoint.php` |
| P7B4.2-5 | Create `App\Telemetry\SmartHome\SmartHomeDispatchTelemetry` — one `smart_home.dispatch` span via `Tracer::startSpan()`, fail-open `wrap()` helper, inert-span fallback | **Done** | `app/Telemetry/SmartHome/SmartHomeDispatchTelemetry.php` |
| P7B4.2-6 | Wire the manual entry point into `VibeSmartHomeDispatchController::__invoke()` | **Done** | `app/Http/Controllers/Api/VibeSmartHomeDispatchController.php` |
| P7B4.2-7 | Wire the scheduled entry point into `DispatchDueSchedulesCommand::dispatchSmartHomeAfterSchedule()` | **Done** | `app/Console/Commands/DispatchDueSchedulesCommand.php` |
| P7B4.2-8 | Register the `SmartHomeDispatchTelemetry` singleton in `TelemetryServiceProvider` | **Done** | `app/Telemetry/Providers/TelemetryServiceProvider.php` |
| P7B4.2-9 | Dependency-rule test: no OpenTelemetry SDK import, Contracts-only, no domain/controller/console/logging/metric-contract import under `app/Telemetry/SmartHome` | **Done** | `tests/Unit/Telemetry/SmartHome/SmartHomeDispatchTelemetryDependencyRuleTest.php` |
| P7B4.2-10 | Unit-level telemetry tests: span creation/naming/entry_point, count attributes, forbidden-attribute exhaustiveness, lifetime, no duplicates, `startSpan()` (never `activeSpan()`), exception recording + rethrow, fail-open, zero metrics | **Done** | `tests/Feature/Telemetry/SmartHome/SmartHomeDispatchTelemetryTest.php` |
| P7B4.2-11 | Real-wiring integration tests: manual (HTTP) and scheduled (Console) entry points, no span on 403/validator failure, multiple schedules never merged/duplicated, no action/provider execution observed | **Done** | `tests/Feature/Telemetry/SmartHome/SmartHomeDispatchBoundaryIntegrationTest.php` |
| P7B4.2-12 | Run full `back_vibes` suite + `pint --test`; confirm pre-existing Smart Home/Scheduling suites still green unmodified | **Done** | 894/894 passing, `pint` clean |
| P7B4.2-13 | Write `backend-smart-home-dispatch-boundary.md`; update README/plan/tasks | **Done** | [`backend-smart-home-dispatch-boundary.md`](../business-telemetry/backend-smart-home-dispatch-boundary.md) |

**Phase 7B.4.2 implementation notes:**

- `App\SmartHome\Services\VibeSmartHomeDispatchService.php` has **zero diff** — the span wraps the call at its two call sites instead of editing the business method, per the Domain Execution Review's "observe, never redesign" principle and because no Laravel event exists around this call to listen to (unlike Queue/Console/Scheduler).
- Trace propagation across the queue boundary was verified to already work correctly via existing OTel auto-instrumentation + `Tracer::startSpan()`'s own `activate()` call — no custom correlation ID, `BusinessCorrelationId`, `ExecutionContext`, or `DispatchContext` was introduced, honoring the Implementation Gate.
- 25 new tests added; full `back_vibes` suite (894 tests) green after this phase; `pint --test` passes; 2 pre-existing risky tests (`HttpRequestTelemetryMiddlewareTest`, Phase 7B.1) unrelated to this phase.
- No metrics, no logging changes — both explicitly deferred to Phases 7B.4.6/7B.4.7.
- **Next:** Phase 7B.4.3 — Smart Home Action Execution, using this phase's span as the automatic parent for its own.

**Branch:** `feature/observability-smart-home-dispatch-boundary`

---

## Phase 7B.4.3 — Smart Home Action Execution

**Prerequisite:** Phase 7B.4.2 (Smart Home Dispatch Boundary).

**Type:** Second Business Telemetry implementation. Owns exactly one boundary — the provider-resolution + `ProviderAdapter::executeAction()` segment of `SmartHomeActionJob::handle()` — and nothing else (not the entire `handle()` method, not `HomeAssistantAdapter`'s HTTP internals, no business metrics, no business logging).

| ID | Task | Status | Reference |
| --- | --- | --- | --- |
| P7B4.3-1 | Mandatory architecture review: `SmartHomeActionJob::handle()`, `ProviderAdapterResolver`, `HomeAssistantAdapter`, retry behavior, queue consumer lifecycle | **Done** | [`backend-smart-home-action-execution.md §2`](../business-telemetry/backend-smart-home-action-execution.md) |
| P7B4.3-2 | Boundary discovery — determined the natural Business Boundary is narrower than `handle()` (excludes the three guard clauses; excludes `logResult()`/`notifyActionFailed()`) | **Done** | [`backend-smart-home-action-execution.md §2.5`](../business-telemetry/backend-smart-home-action-execution.md) |
| P7B4.3-3 | Create `App\Telemetry\SmartHome\SmartHomeActionProvider` enum (`home_assistant`/`future`, reserved) with `fromProviderSlug()` normalizer | **Done** | `app/Telemetry/SmartHome/SmartHomeActionProvider.php` |
| P7B4.3-4 | Create `App\Telemetry\SmartHome\SmartHomeActionOutcome` enum (`success`/`failure`/`unsupported`/`unknown`, reserved) | **Done** | `app/Telemetry/SmartHome/SmartHomeActionOutcome.php` |
| P7B4.3-5 | Create `App\Telemetry\SmartHome\SmartHomeActionTelemetry` — one `smart_home.action` span via `Tracer::startSpan()`, fail-open `wrap()` helper taking caller-supplied `classifyResult`/`classifyException` closures, inert-span fallback | **Done** | `app/Telemetry/SmartHome/SmartHomeActionTelemetry.php` |
| P7B4.3-6 | Wire the wrapper into `SmartHomeActionJob::handle()` around only the discovered boundary; both pre-existing `catch` blocks left byte-for-byte unchanged | **Done** | `app/Jobs/SmartHome/SmartHomeActionJob.php` |
| P7B4.3-7 | Register the `SmartHomeActionTelemetry` singleton in `TelemetryServiceProvider` | **Done** | `app/Telemetry/Providers/TelemetryServiceProvider.php` |
| P7B4.3-8 | Dependency-rule test: no OpenTelemetry SDK import, Contracts-only, no domain/job/controller/console/logging/metric-contract import for the three new files | **Done** | `tests/Unit/Telemetry/SmartHome/SmartHomeActionTelemetryDependencyRuleTest.php` |
| P7B4.3-9 | Unit-level telemetry tests: span creation/naming/`provider`/`retry`, outcome from closures, forbidden-attribute exhaustiveness, lifetime, no duplicates, `startSpan()` (never `activeSpan()`), exception recording + rethrow (identity-checked), fail-open (Tracer and classifier), zero metrics, provider-slug normalization | **Done** | `tests/Feature/Telemetry/SmartHome/SmartHomeActionTelemetryTest.php` |
| P7B4.3-10 | Real-wiring integration tests: success/failure/unsupported/unexpected-error outcomes, no span for the three guard-clause skip paths, exactly one provider call per span, `retry` attribute from Laravel's own attempt counter, fail-open end-to-end | **Done** | `tests/Feature/Telemetry/SmartHome/SmartHomeActionBoundaryIntegrationTest.php` |
| P7B4.3-11 | Run full `back_vibes` suite + `pint --test`; confirm pre-existing `SmartHomeActionJobTest` still green (only its test helper updated for the new constructor argument) | **Done** | 929/929 passing, `pint` clean |
| P7B4.3-12 | Write `backend-smart-home-action-execution.md`; update README/plan/tasks | **Done** | [`backend-smart-home-action-execution.md`](../business-telemetry/backend-smart-home-action-execution.md) |
| P7B4.3-13 | Verify no forbidden fields (action/device/entity/provider/schedule/vibe/user IDs, provider URLs, credentials, payloads, trace/span IDs) in exported telemetry | **Done** | [`ADR-030`](../../../decisions/ADR-030-observability-security-and-privacy.md); `SmartHomeActionTelemetryTest` "never sets a forbidden attribute" |

**Phase 7B.4.3 implementation notes:**

- The natural Business Boundary is **narrower** than `SmartHomeActionJob::handle()` — it begins only once the three leading guard clauses (action/device/provider-connection not found) have already passed, and ends before `logResult()`/`notifyActionFailed()` run. No span is created at all for the guard-clause skip paths, mirroring Phase 7B.4.2's own precedent for preconditions checked before the real boundary.
- `App\SmartHome\ProviderAdapterResolver.php`, `App\SmartHome\Adapters\HomeAssistantAdapter.php`, `App\SmartHome\Contracts\ProviderAdapter.php`, `App\SmartHome\DTOs\ActionResult.php`, and `App\SmartHome\Exceptions\UnsupportedSmartHomeActionException.php` all have **zero diff**.
- `SmartHomeActionTelemetry::wrap()` takes caller-supplied `classifyResult`/`classifyException` closures instead of importing Smart Home domain types — generalizes Phase 7B.4.2's `extractCounts` technique to exception classification as well as result classification.
- Confirmed `SmartHomeActionJob`'s two pre-existing `catch` blocks swallow every exception unconditionally today, so Laravel's queue retry mechanism (`tries = 3`) has never actually been triggered by this job in practice — a pre-existing fact this phase documents but does not change. `ixora.action.retry` reflects Laravel's own job-attempt counter and is `false` in every real execution today.
- 35 new tests added; full `back_vibes` suite (929 tests) green after this phase; `pint --test` passes; 2 pre-existing risky tests (`HttpRequestTelemetryMiddlewareTest`, Phase 7B.1) unrelated to this phase.
- No metrics, no logging changes — both explicitly deferred to Phases 7B.4.6/7B.4.7.
- **Next:** Phase 7B.4.4 — Smart Home Provider Boundary, which will nest its `smart_home.provider` span under `smart_home.action` for free (§4 of this phase's doc) — no correlation work needed.

**Branch:** `feature/observability-smart-home-action-execution`

---

## Phase 7B.4.4 — Smart Home Provider Boundary

**Prerequisite:** Phase 7B.4.3 (Smart Home Action Execution).

**Type:** Third Business Telemetry implementation. Owns exactly one boundary — the domain/payload-construction-through-`ActionResult` segment of `HomeAssistantAdapter::executeAction()` — and nothing else (not the unsupported-action check, not the HTTP client transport itself, no business metrics, no business logging).

| ID | Task | Status | Reference |
| --- | --- | --- | --- |
| P7B4.4-1 | Mandatory architecture review: `HomeAssistantAdapter::executeAction()`, `ProviderAdapter` interface, `ProviderAdapterResolver`, `SmartHomeActionTelemetry`, `SmartHomeActionJob`, `HttpRequestTelemetry`, HTTP client auto-instrumentation (`opentelemetry-auto-guzzle`) | **Done** | [`backend-smart-home-provider-boundary.md §2`](../business-telemetry/backend-smart-home-provider-boundary.md) |
| P7B4.4-2 | Boundary discovery — determined the natural Provider Boundary is narrower than `executeAction()` (excludes the unsupported-action check); validated the span hierarchy against the real code rather than assuming the brief's sketch | **Done** | [`backend-smart-home-provider-boundary.md §3.1, §3.3`](../business-telemetry/backend-smart-home-provider-boundary.md) |
| P7B4.4-3 | HTTP auto-instrumentation duplication analysis — confirmed `opentelemetry-auto-guzzle` already creates a `SpanKind::CLIENT` span with url/method/status/duration/exception-recording for every provider HTTP call; new span records none of that | **Done** | [`backend-smart-home-provider-boundary.md §2.7, §3.2`](../business-telemetry/backend-smart-home-provider-boundary.md) |
| P7B4.4-4 | Attribute-ownership re-review of Phase 7B.4.3's own choices — confirmed `ixora.action.provider` and the `unsupported` outcome correctly stay on `smart_home.action`; flagged `ixora.action.retry` as a documented duplicate of `ixora.queue.attempt` for future cleanup (no change made this phase) | **Done** | [`backend-smart-home-provider-boundary.md §3.4, §3.5, §3.6`](../business-telemetry/backend-smart-home-provider-boundary.md) |
| P7B4.4-5 | Create `App\Telemetry\SmartHome\SmartHomeProviderDeviceDomain` enum (`light`/`switch`/`media_player`/`fan`/`other`, reserved) with `fromDomainSlug()` normalizer | **Done** | `app/Telemetry/SmartHome/SmartHomeProviderDeviceDomain.php` |
| P7B4.4-6 | Create `App\Telemetry\SmartHome\SmartHomeProviderTelemetry` — one `smart_home.provider` span via `Tracer::startSpan()`, fail-open `wrap()` helper, inert-span fallback; no outcome/provider-identity/url/method/status/duration attribute (§4) | **Done** | `app/Telemetry/SmartHome/SmartHomeProviderTelemetry.php` |
| P7B4.4-7 | Wire the wrapper into `HomeAssistantAdapter::executeAction()` around only the discovered boundary (after the unsupported-action check); the check itself and every other adapter method left byte-for-byte unchanged | **Done** | `app/SmartHome/Adapters/HomeAssistantAdapter.php` |
| P7B4.4-8 | Register the `SmartHomeProviderTelemetry` singleton in `TelemetryServiceProvider` | **Done** | `app/Telemetry/Providers/TelemetryServiceProvider.php` |
| P7B4.4-9 | Dependency-rule test: no OpenTelemetry SDK import, Contracts-only, no domain/job/controller/console/HTTP-client/logging/metric-contract import; no url/method/status/duration attribute set | **Done** | `tests/Unit/Telemetry/SmartHome/SmartHomeProviderTelemetryDependencyRuleTest.php` |
| P7B4.4-10 | Unit-level telemetry tests: span creation/naming/`device_domain` (all four domains + normalization), forbidden/duplicated-attribute exhaustiveness, lifetime, no duplicates, `startSpan()` (never `activeSpan()`), exception recording + rethrow (identity-checked), non-error on a returned failure value, fail-open, zero metrics | **Done** | `tests/Feature/Telemetry/SmartHome/SmartHomeProviderTelemetryTest.php` |
| P7B4.4-11 | Real-wiring integration tests through the full `SmartHomeActionJob::handle()` → `HomeAssistantAdapter::executeAction()` pipeline: parent/child hierarchy proof, no span for unsupported/unknown-provider outcomes, non-error on failed `ActionResult`/transport exception, exactly one provider call per span, no `provider_device_id` leak, fail-open end-to-end | **Done** | `tests/Feature/Telemetry/SmartHome/SmartHomeProviderBoundaryIntegrationTest.php` |
| P7B4.4-12 | Run full `back_vibes` suite + `pint --test`; confirm pre-existing `HomeAssistantAdapterTest`/`ProviderAdapterResolverTest`/`SmartHomeActionBoundaryIntegrationTest` still green (only test helpers/span-count assertions updated for the new constructor argument and the now-real nested span) | **Done** | 960/960 passing, `pint` clean |

**Phase 7B.4.4 implementation notes:**

- The natural Provider Boundary is **narrower** than `HomeAssistantAdapter::executeAction()` — it begins only once the unsupported-action check has already passed, and ends at `ActionResult` construction. No span is created at all for an unsupported action or an unknown-provider resolver rejection, mirroring Phase 7B.4.3's own precedent for preconditions checked before the real boundary.
- `App\SmartHome\Contracts\ProviderAdapter.php`, `App\SmartHome\ProviderAdapterResolver.php`, `App\SmartHome\DTOs\ActionResult.php`, `App\SmartHome\Exceptions\UnsupportedSmartHomeActionException.php`, `App\Jobs\SmartHome\SmartHomeActionJob.php`, and `App\Telemetry\SmartHome\SmartHomeActionTelemetry.php` all have **zero diff**. `App\SmartHome\Adapters\HomeAssistantAdapter.php` gains only a constructor dependency and the `wrap()` call around the discovered boundary — every other method is byte-for-byte unchanged.
- Confirmed the existing `opentelemetry-auto-guzzle` HTTP client auto-instrumentation already covers url/method/status/duration/exception-recording for the one provider HTTP call inside this boundary — `smart_home.provider` therefore records exactly one attribute (`ixora.provider.device_domain`) and nothing else, avoiding any duplication.
- Re-reviewed (not merely re-stated) Phase 7B.4.3's own `ixora.action.provider` and `unsupported`-outcome ownership decisions per the brief's explicit instruction not to assume they were correct — both confirmed structurally necessary at the Action Boundary, since a Provider span cannot exist for either case (no adapter is ever reached). `ixora.action.retry` was found to duplicate Phase 7B.2's own `ixora.queue.attempt` with lower fidelity — documented as a recommendation for a future cleanup phase, not changed here (no new home for it exists within this phase's own scope).
- This is the one deliberate departure from "wrap only at the call site, never touch the wrapped file" (Phases 7B.4.2/7B.4.3's preferred pattern where possible) — justified because the unsupported-action knowledge needed to exclude that check from the span lives only inside the concrete adapter, with no external call site able to replicate it without duplicating `ACTION_SERVICE_MAP`.
- 31 new tests added; full `back_vibes` suite (960 tests) green after this phase; `pint --test` passes; 2 pre-existing risky tests unrelated to this phase (confirmed via isolated run of the new files: 31/31, zero risky).
- No metrics, no logging changes — both explicitly deferred to Phases 7B.4.6/7B.4.7.
- **Next:** Phase 7B.4.5 — recommended to address the `ixora.action.retry` duplication finding; a future second provider adapter would add its own, independent `SmartHomeProviderTelemetry::wrap()` call following this phase's pattern.

**Branch:** `feature/observability-smart-home-provider-boundary`

---

## Phase 7B.4.5 — Business Failure Semantics

**Prerequisite:** Phase 7B.4.4 (Smart Home Provider Boundary).

**Type:** Architecture-review phase. Owns exactly one thing — formally defining Business Failure Semantics for Smart Home execution — and explicitly not metrics, logs, dashboards, retry implementation, or any boundary redesign. Documentation is an acceptable, sufficient outcome; code changes are permitted only where the review clearly justifies them.

| ID | Task | Status | Reference |
| --- | --- | --- | --- |
| P7B4.5-1 | Mandatory architecture review: re-read `SmartHomeActionJob`, `SmartHomeActionTelemetry`, `SmartHomeProviderTelemetry`, `SmartHomeDispatchTelemetry`, `HomeAssistantAdapter`, `ProviderAdapter`, `ProviderAdapterResolver`, `ActionResult`, `UnsupportedSmartHomeActionException`, `QueueExecutionTelemetry`, `QueueOutcome`, the Telemetry contracts, and the Traces/Logs/Metrics Philosophy + Telemetry Decision Guide docs | **Done** | [`backend-business-failure-semantics.md §2`](../business-telemetry/backend-business-failure-semantics.md) |
| P7B4.5-2 | Produce an exhaustive failure taxonomy across the dispatch → queue → action → provider → HTTP-client pipeline | **Done** | [`backend-business-failure-semantics.md §3`](../business-telemetry/backend-business-failure-semantics.md) |
| P7B4.5-3 | Classify every discovered failure as Business, Infrastructure, Platform, Telemetry, or Unknown, with reasoning; discovered `ProviderConnectionException` is **unreachable** in this pipeline (device-sync only), correcting an assumption in the brief's example list | **Done** | [`backend-business-failure-semantics.md §4`](../business-telemetry/backend-business-failure-semantics.md) |
| P7B4.5-4 | Determine exception ownership (span `ERROR` vs `OK` + business outcome) for `UnsupportedSmartHomeActionException`, the internal `ConnectionException` catch, `ActionResult(success=false)`, `ProviderConnectionException`, and generic `Throwable` | **Done** | [`backend-business-failure-semantics.md §5`](../business-telemetry/backend-business-failure-semantics.md) |
| P7B4.5-5 | Decide `ActionResult(success=false)` semantics — successful execution with an unsuccessful business outcome, not an infrastructure failure; document the accepted conflation of provider rejection vs. transport failure at this level | **Done** | [`backend-business-failure-semantics.md §6`](../business-telemetry/backend-business-failure-semantics.md) |
| P7B4.5-6 | Document the Span Status policy — adopt OpenTelemetry's recommendation that business failures are not usually span errors; `unsupported` is a recognized business outcome (never `ERROR`), unexpected `Throwable`s escaping a boundary still are | **Done** | [`backend-business-failure-semantics.md §7`](../business-telemetry/backend-business-failure-semantics.md) |
| P7B4.5-7 | Review the existing `ixora.action.outcome` vocabulary (`success`/`failure`/`unsupported`/`unknown`); confirm no new outcome values are justified | **Done** | [`backend-business-failure-semantics.md §8`](../business-telemetry/backend-business-failure-semantics.md) |
| P7B4.5-8 | Document failure propagation across the full span hierarchy (HTTP/Console/Scheduler → `smart_home.dispatch` → Queue Consumer → `smart_home.action` → `smart_home.provider` → HTTP Client) | **Done** | [`backend-business-failure-semantics.md §9`](../business-telemetry/backend-business-failure-semantics.md) |
| P7B4.5-9 | Document retry semantics — a retried job attempt is an independent event producing a new `smart_home.action` span, not a continuation or a "failure" of the prior attempt | **Done** | [`backend-business-failure-semantics.md §10`](../business-telemetry/backend-business-failure-semantics.md) |
| P7B4.5-10 | Classify logging ownership (trace only / log only / trace + log / no telemetry) per failure type, for future Business Logging phases — no implementation | **Done** | [`backend-business-failure-semantics.md §11`](../business-telemetry/backend-business-failure-semantics.md) |
| P7B4.5-11 | Classify metrics ownership per failure type, for future Business Metrics phases — no implementation | **Done** | [`backend-business-failure-semantics.md §12`](../business-telemetry/backend-business-failure-semantics.md) |
| P7B4.5-12 | Implementation gate: review concluded exactly one inconsistency exists with the adopted Span Status policy — implement the justified fix in `SmartHomeActionTelemetry::wrap()` (no `setError()` for `outcome === Unsupported`; `recordException()` still always fires) | **Done** | `app/Telemetry/SmartHome/SmartHomeActionTelemetry.php` |
| P7B4.5-13 | Update/add unit + integration tests for the fix: `spanErrorCalls` stays `0` for `unsupported` while `recordException` still fires; `failure`/`unknown` outcomes and unexpected resolver errors still set `spanErrorCalls` to `1` | **Done** | `tests/Feature/Telemetry/SmartHome/SmartHomeActionTelemetryTest.php`, `tests/Feature/Telemetry/SmartHome/SmartHomeActionBoundaryIntegrationTest.php` |
| P7B4.5-14 | Run full `back_vibes` suite + `pint --test`; confirm no business/queue/retry/provider behavior changed | **Done** | 929/929 passing, `pint` clean |
| P7B4.5-15 | Write `backend-business-failure-semantics.md`; update README/plan/tasks | **Done** | [`backend-business-failure-semantics.md`](../business-telemetry/backend-business-failure-semantics.md) |
| P7B4.5-16 | Security review — confirm no forbidden fields (credentials, payloads, entity/device IDs, headers, request/response bodies, tokens, URLs with credentials) introduced; confirm fail-open preserved throughout | **Done** | [`ADR-030`](../../../decisions/ADR-030-observability-security-and-privacy.md); [`backend-business-failure-semantics.md §13`](../business-telemetry/backend-business-failure-semantics.md) |

**Phase 7B.4.5 implementation notes:**

- This phase is a discovery/documentation phase by design — the brief explicitly allows "documentation is an acceptable outcome" if the review concludes existing telemetry already models failures correctly. The review found telemetry was **almost** correct: one narrowly-scoped Span Status inconsistency was discovered and fixed, nothing else changed.
- `ProviderConnectionException` was confirmed **unreachable** in the Smart Home action execution pipeline (it is only thrown by device-sync code, never by `HomeAssistantAdapter::executeAction()` or anything it calls) — an important correction to an assumption implicit in the brief's own example failure list.
- `App\SmartHome\Adapters\HomeAssistantAdapter.php`, `App\SmartHome\Contracts\ProviderAdapter.php`, `App\SmartHome\ProviderAdapterResolver.php`, `App\SmartHome\DTOs\ActionResult.php`, `App\SmartHome\Exceptions\UnsupportedSmartHomeActionException.php`, `App\Jobs\SmartHome\SmartHomeActionJob.php`, `App\Telemetry\SmartHome\SmartHomeProviderTelemetry.php`, and `App\Telemetry\SmartHome\SmartHomeDispatchTelemetry.php` all have **zero diff**. `App\Telemetry\SmartHome\SmartHomeActionTelemetry.php` gains only the conditional guard around `setError()` — everything else in `wrap()` is unchanged.
- No new metrics, no new logs, no dashboards, no retry/queue/provider/dispatch behavior changes, no new persistence or correlation IDs — all explicitly forbidden by this phase's brief and confirmed absent.
- Full `back_vibes` suite green after this phase; `pint --test` passes.
- **Next:** Phase 7B.4.6 — first Business Metrics implementation, now unblocked by this phase's outcome/failure classification (§11–§12 of this phase's doc supply the ownership groundwork).

**Branch:** `feature/observability-business-failure-semantics`

---

## Phase 7B.4.6 — Business Metrics

**Prerequisite:** Phase 7B.4.5 (Business Failure Semantics).

**Type:** Metrics Design Review + implementation of the metrics it justifies. Explicitly not logging, dashboards, or alerts. No Business Metric may contradict the failure taxonomy Phase 7B.4.5 established.

| ID | Task | Status | Reference |
| --- | --- | --- | --- |
| P7B4.6-1 | Mandatory architecture review: re-read `backend-business-failure-semantics.md`, all three Smart Home boundary docs, Metrics/Traces/Logs Philosophy, Telemetry Naming Convention, Telemetry Decision Guide; review `SmartHomeDispatchTelemetry`, `SmartHomeActionTelemetry`, `SmartHomeProviderTelemetry`, `QueueExecutionTelemetry`, the `Meter` abstractions, existing metric registration, and OpenTelemetry metric conventions | **Done** | [`backend-smart-home-business-metrics.md §2`](../business-telemetry/backend-smart-home-business-metrics.md) |
| P7B4.6-2 | Metrics Design Review — produce a Design Record (name, type, business question, boundary owner, counting unit, label set, cardinality analysis, failure-semantics alignment, duplication analysis, decision) for every candidate metric | **Done** | [`backend-smart-home-business-metrics.md §3`](../business-telemetry/backend-smart-home-business-metrics.md) |
| P7B4.6-3 | Decide `ixora.smart_home.dispatch.total` — Counter, owned by Dispatch, labeled `entry_point`/`outcome` (`dispatched`/`skipped`/`error`) | **Done — Implement** | [`backend-smart-home-business-metrics.md §3.1`](../business-telemetry/backend-smart-home-business-metrics.md) |
| P7B4.6-4 | Decide `ixora.smart_home.action.total` + `.duration` — Counter + Histogram, owned by Action, labeled `outcome`/`provider`, reusing the existing `SmartHomeActionOutcome` classification verbatim (never re-derived, never merging `unsupported` into `failure`) | **Done — Implement** | [`backend-smart-home-business-metrics.md §3.2`](../business-telemetry/backend-smart-home-business-metrics.md) |
| P7B4.6-5 | Decide `ixora.smart_home.provider.total` — rejected: 1:1 duplication with the Action counter in today's single-provider-per-attempt pipeline | **Done — Reject** | [`backend-smart-home-business-metrics.md §3.3`](../business-telemetry/backend-smart-home-business-metrics.md) |
| P7B4.6-6 | Decide the J1–J3 guard-clause-skip metric candidate (surfaced by Phase 7B.4.5 §14/§11, not named in this phase's own candidate list) — deferred: no clean boundary owner exists yet before any span is created | **Done — Defer** | [`backend-smart-home-business-metrics.md §3.4`](../business-telemetry/backend-smart-home-business-metrics.md) |
| P7B4.6-7 | Cardinality review for every implemented metric — confirm every label is bounded, no forbidden field (IDs, URLs, payloads, exception messages), and estimate total time series (54 + 96 ≪ 10 000/service budget) | **Done** | [`backend-smart-home-business-metrics.md §3.1–§3.2`](../business-telemetry/backend-smart-home-business-metrics.md) |
| P7B4.6-8 | Failure-alignment review — map every metric outcome value to Phase 7B.4.5's own taxonomy and Span Status policy; confirm no metric ever contradicts a span's own status | **Done** | [`backend-smart-home-business-metrics.md §3.1–§3.2`](../business-telemetry/backend-smart-home-business-metrics.md) |
| P7B4.6-9 | Duplication review against `ixora.http.server.*`, `ixora.queue.job.*`, `ixora.console.command.*`, `ixora.scheduler.event.*`, and all three existing Smart Home spans | **Done** | [`backend-smart-home-business-metrics.md §3.1–§3.3`](../business-telemetry/backend-smart-home-business-metrics.md) |
| P7B4.6-10 | Implement the two justified metrics: register `Counter`/`Histogram` via the injected `Meter` in `SmartHomeDispatchTelemetry`/`SmartHomeActionTelemetry`; record them from inside each class's existing `safely()` fail-open guard, reusing the already-classified outcome each span attribute is set from | **Done** | `app/Telemetry/SmartHome/SmartHomeDispatchTelemetry.php`, `app/Telemetry/SmartHome/SmartHomeActionTelemetry.php` |
| P7B4.6-11 | Wire `Meter`/`environment`/`service_name` into both singleton definitions in `TelemetryServiceProvider`, mirroring the existing `QueueExecutionTelemetry`/`ConsoleCommandTelemetry`/`SchedulerExecutionTelemetry` pattern | **Done** | `app/Telemetry/Providers/TelemetryServiceProvider.php` |
| P7B4.6-12 | Add/update unit, integration, and dependency-rule tests: metric registration, counter increments per outcome (including the zero-count and error paths), label correctness, bounded cardinality, fail-open on a broken Counter/Histogram, no metric on `SmartHomeProviderTelemetry`/enums, no undocumented metric name or label | **Done** | `tests/Feature/Telemetry/SmartHome/SmartHomeDispatchTelemetryTest.php`, `tests/Feature/Telemetry/SmartHome/SmartHomeActionTelemetryTest.php`, `tests/Unit/Telemetry/SmartHome/SmartHomeDispatchTelemetryDependencyRuleTest.php`, `tests/Unit/Telemetry/SmartHome/SmartHomeActionTelemetryDependencyRuleTest.php`, `tests/Unit/Telemetry/SmartHome/SmartHomeBusinessMetricsDependencyRuleTest.php` (new) |
| P7B4.6-13 | Run full `back_vibes` suite + `pint --test`; confirm no business/queue/retry/provider/trace-hierarchy behavior changed | **Done** | 980/980 passing (358/358 SmartHome-scoped), `pint` clean |
| P7B4.6-14 | Write `backend-smart-home-business-metrics.md`; security review; update README/plan/tasks | **Done** | [`backend-smart-home-business-metrics.md`](../business-telemetry/backend-smart-home-business-metrics.md) |

**Phase 7B.4.6 implementation notes:**

- Both implemented metrics reuse an already-classified value the span's own attribute is set from (`SmartHomeActionOutcome`, `SmartHomeDispatchEntryPoint`) — no metric ever computes a second, independently-derived classification that could drift from its own span's status.
- `action_type` is deliberately **omitted** from `ixora.smart_home.action.total`/`.duration`'s label set this phase, even though `metrics-philosophy.md` §11 and `telemetry-naming-convention.md` §14 both show it in their own reserved/illustrative examples — it is not an existing `smart_home.action` span attribute, and this phase's own brief lists only `outcome`/`provider` for this metric. Recorded as a Phase 7B.4.7 recommendation (adding a label to an existing metric, never a rename).
- `ixora.smart_home.provider.total` was rejected on a duplication basis, independently re-derived from the current code (one Provider call is 1:1 with one Action attempt in every reachable path today) rather than assumed from Phase 7B.4.5's own preview.
- `SmartHomeProviderTelemetry.php` and every Smart Home enum remain completely metric-free — guarded by a new phase-specific dependency-rule test in addition to the narrowed pre-existing directory-wide scan.
- No logs, no dashboards, no alerts, no business/retry/queue/provider/dispatch behavior changes, no new persistence or correlation IDs — all explicitly forbidden by this phase's brief and confirmed absent.
- Full `back_vibes` suite green after this phase; `pint --test` passes.
- **Next:** Phase 7B.4.7 — Business Logging, which should treat §9 of this phase's doc (the `action_type` label, the J1–J3 skip visibility question, and the `Log::info`-on-success question) as its own starting brief.

**Branch:** `feature/observability-business-metrics`

---

## Phase 7B.4.7 — Business Logging

**Prerequisite:** Phase 7B.4.5 (Business Failure Semantics) · Phase 7B.4.6 (Business Metrics).

**Type:** Logging Design Review + the improvements it justified. No new log statements added at any Telemetry boundary. No metrics, no spans, no dashboards, no alerts, no business behavior change.

| ID | Task | Status | Reference |
| --- | --- | --- | --- |
| P7B4.7-1 | Mandatory architecture review: re-read all six prerequisite docs (`backend-business-failure-semantics.md`, `backend-smart-home-business-metrics.md`, three boundary docs, Logs/Traces/Metrics Philosophy, Telemetry Decision Guide, Naming Convention); review `SmartHomeDispatchTelemetry`, `SmartHomeActionTelemetry`, `SmartHomeProviderTelemetry`, `SmartHomeActionJob`, existing Log contracts, `TraceCorrelationLogTap`, `QueueErrorContextLogTap`, `SchedulerErrorContextLogTap` | **Done** | [`backend-smart-home-business-logging.md §2`](../business-telemetry/backend-smart-home-business-logging.md) |
| P7B4.7-2 | Logging Design Review — produce a Design Record (name, business question, boundary owner, trigger, log level, structured fields, failure-semantics alignment, duplication analysis, security review, decision) for every candidate log | **Done** | [`backend-smart-home-business-logging.md §3`](../business-telemetry/backend-smart-home-business-logging.md) |
| P7B4.7-3 | Decide `smart_home.dispatch.completed` — rejected: D1 is Trace+Metric-only; D2 already logged at call-site (duplicating would violate single-boundary-ownership) | **Done — Reject** | [`backend-smart-home-business-logging.md §3.1`](../business-telemetry/backend-smart-home-business-logging.md) |
| P7B4.7-4 | Decide `smart_home.action.completed` — rejected as new log; resolve L-2 instead (remove existing `Log::info` on success) | **Done — Reject / Resolve L-2** | [`backend-smart-home-business-logging.md §3.2`](../business-telemetry/backend-smart-home-business-logging.md) |
| P7B4.7-5 | Decide `smart_home.action.failed` — rejected as new log; improve existing failure logs (remove `provider_device_id`, add `outcome`, replace `error_message` with `exception_class`) | **Done — Reject / Improve** | [`backend-smart-home-business-logging.md §3.3`](../business-telemetry/backend-smart-home-business-logging.md) |
| P7B4.7-6 | Decide `smart_home.provider.failed` — rejected: 1:1 duplication with A2/A5 logs one layer up; violates single-boundary-ownership rule | **Done — Reject** | [`backend-smart-home-business-logging.md §3.4`](../business-telemetry/backend-smart-home-business-logging.md) |
| P7B4.7-7 | Implement: resolve L-2 (remove `Log::info` on success), remove `provider_device_id`, replace `error_message` with `exception_class`, remove redundant `success`/`status_code => null` from catch blocks, add `outcome` to failure logs | **Done** | `app/Jobs/SmartHome/SmartHomeActionJob.php` |
| P7B4.7-8 | Add/update unit and dependency-rule tests: no `Log::info` on success, no `provider_device_id`, no `error_message`, `exception_class` in catch blocks, `outcome` in failure logs, no `success` key; update all affected feature tests | **Done** | `tests/Feature/SmartHome/SmartHomeActionJobTest.php`, `tests/Unit/Telemetry/SmartHome/SmartHomeBusinessLoggingTest.php` (new) |
| P7B4.7-9 | Run full `back_vibes` suite + `pint --test`; confirm no business/queue/retry/provider/trace-hierarchy/metric behavior changed | **Done** | 986/986 passing (364/364 SmartHome-scoped), `pint` clean |
| P7B4.7-10 | Write `backend-smart-home-business-logging.md`; security review; update README/plan/tasks | **Done** | [`backend-smart-home-business-logging.md`](../business-telemetry/backend-smart-home-business-logging.md) |

**Phase 7B.4.7 implementation notes:**

- All four candidate Business Logs were rejected — no new log statement was introduced at any Telemetry boundary. Every failure path across the Smart Home pipeline was already correctly logged by pre-existing domain logs in `SmartHomeActionJob`.
- L-2 (flagged by Phase 7B.4.5 §14, reiterated by Phase 7B.4.6 §9 recommendation #4) is resolved: `Log::info` on every successful action execution is removed. Metric + trace covers this outcome.
- `provider_device_id` is removed from every log context — it is the HA physical entity ID, which `telemetry-naming-convention.md` §8 explicitly names as a forbidden field (may reveal home layout).
- `exception_class` replaces raw `error_message` (`$e->getMessage()`) in both catch blocks — the FQCN is bounded, safe, and the standard field name for exception context.
- `outcome` is added to every failure/unsupported log using the `SmartHomeActionOutcome` vocabulary already used by the Business Metrics, enabling direct cross-signal Loki queries (`outcome=failure` in logs ↔ `outcome="failure"` in metrics).
- Trace correlation is handled automatically by `TraceCorrelationLogTap` (already registered globally) — no `trace_id` injection needed in application code.
- No new `SmartHomeActionContextLogTap` was introduced — the domain-layer logs already carry the full investigation context; a tap would add no value.
- Full `back_vibes` suite green after this phase; `pint --test` passes.
- **Next:** Phase 7B.4.8 or 7B.5 (Push Notifications) — open question is the J1–J3 guard-clause skip visibility (aggregate Counter), `action_type` label on metrics, and connection_id field naming.

**Branch:** `feature/observability-business-logging`

---

## Phase 7B.4.8 — Business Telemetry Validation & Architecture Review

| ID | Task | Status | Reference |
| --- | --- | --- | --- |
| P7B4.8-1 | Read every required doc: 7 Business Telemetry docs + 6 Core Observability docs | **Done** | All docs listed in §1 of validation doc |
| P7B4.8-2 | Review every implementation file: `app/Telemetry/SmartHome/`, `app/Jobs/SmartHome/`, `app/Telemetry/Providers/TelemetryServiceProvider.php` | **Done** | Confirmed against source |
| P7B4.8-3 | Produce Ownership Matrix (spans, metrics, logs — exactly one owner each) | **Done** | `backend-business-telemetry-validation.md §2` |
| P7B4.8-4 | Validate Trace Architecture: hierarchy, attributes, status policy, fail-open, propagation | **Done** | `backend-business-telemetry-validation.md §3` |
| P7B4.8-5 | Validate Metrics Architecture: naming, cardinality, deferred items (guard-clause, action_type) | **Done** | `backend-business-telemetry-validation.md §4` |
| P7B4.8-6 | Validate Logging Architecture: ownership, fields, sanitization, naming consistency (`provider_connection_id`) | **Done** | `backend-business-telemetry-validation.md §5` |
| P7B4.8-7 | Cross-Signal Consistency Matrix (all 4 outcomes × span/metric/log) | **Done** | `backend-business-telemetry-validation.md §6` |
| P7B4.8-8 | Correlation Review: Metric→Trace→Log workflow, `trace_id`, `span_id`, `outcome`, `exception_class` | **Done** | `backend-business-telemetry-validation.md §7` |
| P7B4.8-9 | Security Review: all signal types, all forbidden fields | **Done — PASS** | `backend-business-telemetry-validation.md §8` |
| P7B4.8-10 | Dashboard Readiness Review (8 dashboard types) | **Done** | `backend-business-telemetry-validation.md §9` |
| P7B4.8-11 | Operational Readiness Review ("Lights are not turning on" investigation) | **Done** | `backend-business-telemetry-validation.md §10` |
| P7B4.8-12 | Future Extensibility Review (Push, Matter, Google Home, Alexa, additional providers) | **Done** | `backend-business-telemetry-validation.md §11` |
| P7B4.8-13 | Technical Debt Register: 4 items classified (TD-1 through TD-4) | **Done** | `backend-business-telemetry-validation.md §13` |
| P7B4.8-14 | Write `backend-business-telemetry-validation.md`; update README/plan/tasks | **Done** | [`backend-business-telemetry-validation.md`](../business-telemetry/backend-business-telemetry-validation.md) |

**Phase 7B.4.8 implementation notes:**

- Architecture review is complete and conclusive: the Smart Home Business Telemetry is internally consistent, production-ready, and reusable for future domains without redesign.
- Every signal has exactly one owner. Trace hierarchy is valid and propagates through the queue boundary via W3C `traceparent` (no custom correlation IDs). Metrics and spans share the same `SmartHomeActionOutcome` vocabulary by construction. Logs complement rather than duplicate the other signals.
- Security review passes on all three signal types (spans, metrics, logs).
- No runtime code changes were made — the review found no genuine architectural inconsistency.
- Four technical debt items documented: TD-1 (`ixora.action.retry` duplication, Medium), TD-2 (`action_type` label absent, Low), TD-3 (guard-clause J1–J3 invisible to metrics, Medium), TD-4 (`provider_connection_id` naming, Low).
- Full `back_vibes` suite green (986/986, verified before this phase); no test changes made.
- **Next:** Phase 7B.5 — Push Notifications. Recommend addressing TD-2 (`action_type` label) and TD-1 (`ixora.action.retry` removal) in early 7B.5 scope.

**Branch:** `feature/observability-telemetry-validation`

---

## Phase 7B.4.9 — Business Telemetry Foundation Baseline

| ID | Task | Status | Reference |
| --- | --- | --- | --- |
| P7B4.9-1 | Read all mandatory docs: validation, Smart Home boundary/failure/metrics/logging docs, platform philosophy guides | **Done** | All docs listed in §1 of foundation doc |
| P7B4.9-2 | Extract reusable architectural rules: boundary ownership, signal ownership, failure taxonomy, outcome vocabulary, cross-signal consistency, correlation, security, fail-open, cardinality, logging/metrics/tracing policies | **Done** | `business-telemetry-foundation.md §3` |
| P7B4.9-3 | Document Business Boundary Pattern: standard lifecycle, layer responsibilities, boundary discovery method | **Done** | `business-telemetry-foundation.md §4` |
| P7B4.9-4 | Document Required Business Telemetry Components and standard Telemetry class pattern | **Done** | `business-telemetry-foundation.md §5` |
| P7B4.9-5 | Document Standard Design Reviews: Architecture, Failure Semantics, Metrics, Logging, Security, Validation | **Done** | `business-telemetry-foundation.md §6` |
| P7B4.9-6 | Document Extension Rules for future domains (Push, Marketplace, AI, Matter, Google Home, Alexa) | **Done** | `business-telemetry-foundation.md §7` |
| P7B4.9-7 | Document Anti-patterns: duplication, ownership violations, security, correlation, design violations | **Done** | `business-telemetry-foundation.md §8` |
| P7B4.9-8 | Write `business-telemetry-foundation.md`; update README/plan/tasks | **Done** | [`business-telemetry-foundation.md`](../business-telemetry/business-telemetry-foundation.md) |

**Phase 7B.4.9 implementation notes:**

- Documentation-only phase — no runtime code, telemetry, metrics, spans, logs, or tests changed.
- Generalizes the validated Smart Home architecture (Phases 7B.4.1–7B.4.8) into platform-wide Business Telemetry standards.
- No Smart Home-specific assumptions remain — all rules stated in domain-neutral terms with Smart Home as reference implementation only.
- Future domains (Push Notifications, Marketplace, AI, Matter, Google Home, Alexa) can implement Business Telemetry by following this foundation without redefining architecture.
- **Next:** Phase 8.0 — Dashboard Requirements Review.

**Branch:** `feature/observability-business-telemetry-foundation`

---

## Phase 8.0 — Dashboard Requirements Review

**Prerequisite:** business-telemetry-foundation.md (Phase 7B.4.9), backend-business-telemetry-validation.md (Phase 7B.4.8), metrics-philosophy.md, logs-philosophy.md, traces-philosophy.md, telemetry-decision-guide.md.

| ID | Task | Status | Reference |
| --- | --- | --- | --- |
| P8.0-1 | Read all mandatory docs: business-telemetry-foundation, metrics-philosophy, logs-philosophy, traces-philosophy, telemetry-decision-guide, backend-business-telemetry-validation | **Done** | Docs listed in §1 of dashboard-requirements.md |
| P8.0-2 | Produce dashboard inventory (D-01 → D-07) with audience, purpose, and implementation order | **Done** | `dashboard-requirements.md §1` |
| P8.0-3 | Design every dashboard: panels, signals, drill-down workflows, refresh intervals, future expansion | **Done** | `dashboard-requirements.md §3–9` |
| P8.0-4 | Document Metric → Trace → Log investigation workflows for every operational scenario + operational questions mapping | **Done** | `dashboard-requirements.md §10–11` |

**Phase 8.0 implementation notes:**

- Documentation-only phase — no Grafana JSON, no PromQL, no dashboard implementation.
- Defined 7 dashboards (D-01 Platform Overview, D-02 Smart Home, D-03 Push Notifications, D-04 Queue Workers, D-05 HTTP API, D-06 Scheduler, D-07 Collector & Infrastructure).
- Mapped all available signals (metrics, spans, logs) to dashboard panels.
- Documented 6 investigation workflows covering every major operational scenario.
- Identified deferred panels and their blockers (TD-2 `action_type` label, TD-3 guard-clause metric, Phase 7B.5 Push signals).
- Phase 9 implementation checklist included in §15 for Grafana dashboard construction.
- **Next:** Phase 7B.5 — Push Notifications Business Telemetry.

**Branch:** `feature/observability-dashboard-requirements`

---

## Phase 8.1 — Grafana Foundation & Provisioning

**Prerequisite:** dashboard-requirements.md (Phase 8.0), Prometheus/Loki/Tempo healthy (Phases 4–6).

| ID | Task | Status | Reference |
| --- | --- | --- | --- |
| P8.1-1 | Read mandatory docs: dashboard-requirements, business-telemetry-foundation, metrics/traces/logs-philosophy, telemetry-decision-guide, telemetry-naming-convention; review Collector/docker-compose/OpenTofu infrastructure | **Done** | All docs in §1 of grafana-foundation.md |
| P8.1-2 | Implement provisioning: grafana/ directory, datasources.yaml (stable UIDs), providers.yaml (4 folder providers), activate Grafana service in docker-compose.yml, update .env.example | **Done** | `collector/grafana/provisioning/datasources/datasources.yaml`, `collector/grafana/provisioning/dashboards/providers.yaml`, `collector/docker-compose.yml` |
| P8.1-3 | Fix Tempo 2.6.0 and Loki 3.2.0 config files (9 deprecated/renamed fields) blocking container startup | **Done** | `collector/tempo/tempo.yaml`, `collector/loki/loki.yaml` |
| P8.1-4 | Start Grafana, validate 12/12 checks (health, UIDs, defaults, connectivity, read-only, count), confirm idempotent post-restart | **Done** | `collector/grafana/validate.sh` — 12/12 PASS (initial + restart) |
| P8.1-5 | Write grafana-foundation.md (provisioning arch, datasource strategy, folder strategy, dashboard-as-code standard, variables, navigation, plugins, security, environment strategy, extensibility) | **Done** | `grafana-foundation.md` |
| P8.1-6 | Update tasks.md, plan.md, README.md | **Done** | Roadmap files |
| P8.1-7 | Git flow: commit → develop → staging → push → back to develop | **Done** | `feature/observability-grafana-foundation` |

**Phase 8.1 implementation notes:**

- Grafana OSS 11.3.0 active on `127.0.0.1:3000` via Docker Compose.
- Three datasources provisioned with stable UIDs: `ixora-prometheus` (default), `ixora-loki`, `ixora-tempo`.
- Cross-signal linking wired: Prometheus→Tempo exemplars, Loki derived fields for `trace_id`→Tempo, Tempo→Loki/Prometheus drill-down.
- Four folder providers defined: Infrastructure (`ixora-folder-infrastructure`), Application (`ixora-folder-application`), Business (`ixora-folder-business`), Overview (`ixora-folder-overview`). Folders will be created in Grafana when Phase 9 dashboard JSONs are deployed.
- All config expressed as env vars in docker-compose.yml — no `grafana.ini` needed.
- Tempo 2.6.0 config: 6 deprecated fields removed. Loki 3.2.0 config: 3 deprecated fields removed.
- Validation: 12/12 checks pass on first start and after restart (idempotency confirmed).
- **Next:** Phase 8.2 — D-07 Collector & Infrastructure dashboard (first Grafana dashboard).

**Branch:** `feature/observability-grafana-foundation`

---

## Phase 8.2 — D-07 Infrastructure Dashboard

**Prerequisite:** grafana-foundation.md (Phase 8.1), dashboard-requirements.md §9 (Phase 8.0).

| ID | Task | Status | Reference |
| --- | --- | --- | --- |
| P8.2-1 | Architecture review: read ADRs 028–031, all observability docs, collector config, grafana-foundation, dashboard-requirements | **Done** | Architecture review in dashboard-d07-infrastructure.md §2 |
| P8.2-2 | Fix 3 pre-existing Collector bugs (Loki exporter labels, missing endpoint env vars, Tempo port conflict) that blocked full-stack startup | **Done** | `collector/config.yaml`, `collector/docker-compose.yml`, `collector/.env`, `collector/.env.example` |
| P8.2-3 | Implement d07-infrastructure.json (21 panels, uid=ixora-collector, Infrastructure folder, ixora-prometheus datasource only) | **Done** | `collector/grafana/provisioning/dashboards/infrastructure/d07-infrastructure.json` |
| P8.2-4 | Extend validate.sh to 24 checks: folder names, JSON syntax, UID, provisioning, datasource binding, folder assignment | **Done** | `collector/grafana/validate.sh` — 24/24 PASS (initial + restart) |
| P8.2-5 | Write dashboard-d07-infrastructure.md (architecture, ownership, panel descriptions, datasource usage, drill-down strategy, known limitations) | **Done** | `docs/specs/observability-foundation/mvp/dashboard-d07-infrastructure.md` |
| P8.2-6 | Update tasks.md, plan.md, README.md | **Done** | Roadmap files |
| P8.2-7 | Git flow: commit → develop → staging → push → back to develop | **Done** | `feature/observability-d07-infrastructure` |

**Phase 8.2 implementation notes:**

- D-07 `ixora-collector` dashboard provisioned automatically via file-based provider.
- 21 panels: Platform Health (5 stats), Metric Export Pipeline (2 time series), Trace & Log Export (2 time series), Error Signals (3 stats), Prometheus Platform (2 stats + 2 time series).
- All datasource references use `ixora-prometheus` UID — no name-based references.
- Grafana 11.3 limitation: folder UIDs are auto-generated on first creation (folder **names** are stable). Documented in KL-1 of dashboard-d07-infrastructure.md.
- Three pre-existing infrastructure bugs fixed: Loki exporter `labels` key removed (OTel 0.115.x), endpoint env vars added to docker-compose, Tempo host port changed to `14317` to avoid Collector OTLP port conflict.

---

## Phase 8.3 — Application Infrastructure Dashboards

**Prerequisite:** dashboard-conventions.md (Phase 8.3), grafana-foundation.md (Phase 8.1), dashboard-requirements.md §6–8 (Phase 8.0).

| ID | Task | Status | Reference |
| --- | --- | --- | --- |
| P8.3-1 | Architecture review: verify all HTTP/Queue/Scheduler metrics against implementation; discover discrepancies with dashboard-requirements.md | **Done** | `HttpRequestTelemetry.php`, `QueueExecutionTelemetry.php`, `SchedulerExecutionTelemetry.php` |
| P8.3-2 | Create dashboard-conventions.md (permanent Grafana standard: UIDs, folders, datasources, refresh, time range, variables, panels, panel IDs, JSON standards, security, navigation) | **Done** | `docs/specs/observability-foundation/mvp/dashboard-conventions.md` |
| P8.3-3 | Implement d05-http.json (D-05 HTTP API, 15 panels, uid=ixora-http, Application folder, ixora-prometheus) | **Done** | `collector/grafana/provisioning/dashboards/application/d05-http.json` |
| P8.3-4 | Implement d04-queue.json (D-04 Queue Workers, 17 panels, uid=ixora-queue, Application folder, ixora-prometheus) | **Done** | `collector/grafana/provisioning/dashboards/application/d04-queue.json` |
| P8.3-5 | Implement d06-scheduler.json (D-06 Scheduler, 17 panels, uid=ixora-scheduler, Application folder, ixora-prometheus) | **Done** | `collector/grafana/provisioning/dashboards/application/d06-scheduler.json` |
| P8.3-6 | Extend validate.sh with Check 25 (UID uniqueness) and Check 26 (UID naming); verify 26/26 PASS + restart idempotency | **Done** | `collector/grafana/validate.sh` — 26/26 PASS (initial + restart) |
| P8.3-7 | Write dashboard-d05-http.md, dashboard-d04-queue.md, dashboard-d06-scheduler.md | **Done** | `docs/specs/observability-foundation/mvp/` |
| P8.3-8 | Update tasks.md, plan.md, README.md | **Done** | Roadmap files |
| P8.3-9 | Git flow: commit → develop → staging → push → back to develop | **Done** | `feature/observability-application-dashboards` |

**Phase 8.3 implementation notes:**

- Three application dashboards provisioned: D-04 Queue Workers, D-05 HTTP API, D-06 Scheduler.
- **Critical discrepancy found and documented:** `dashboard-requirements.md §8` (Phase 8.0) listed incorrect Scheduler metric names (`ixora.scheduler.execution.total`, `ixora.scheduler.dispatch.duration`) and outcome values (`dispatched`, `skipped_duplicate`). The actual implementation uses `ixora.scheduler.event.total` / `ixora.scheduler.event.duration` and outcomes from `SchedulerOutcome.php` (`success`, `failed`, `overlap_prevented`, etc.). All dashboards use the verified implementation values.
- Dashboard-as-Code conventions documented in `dashboard-conventions.md` — covers UIDs, folders, datasources, refresh, variables, panel IDs (reserved ranges), JSON standards, and security.
- Validation extended: Check 25 (UID uniqueness across all dirs), Check 26 (all UIDs start with `ixora-`). Both use single-assertion design to maintain 26 total pass count.
- HTTP `status_code_class` label used (`2xx`, `4xx`, `5xx`) — individual status code isolation (401/403) requires Tempo drill-down. Documented in D-05 and conventions.
- Queue `job_name` label (not `job` as dashboard-requirements.md stated). `ixora_queue_job_active` UpDownCounter available for active job count.
- All three Application folder dashboards include navigation links to each other and to D-07 Infrastructure.
- Validation: 24/24 checks pass on first start and after restart.
- Dashboard UID `ixora-collector` establishes the standard for all future dashboards (see §5 of dashboard-d07-infrastructure.md).

**Branch:** `feature/observability-d07-infrastructure`

---

## Phase 8.4 — Smart Home Business Dashboard (D-02)

**Prerequisite:** dashboard-conventions.md (Phase 8.3), backend-smart-home-business-metrics.md (Phase 7B.4.6), backend-business-failure-semantics.md (Phase 7B.4.5).

| ID | Task | Status | Reference |
| --- | --- | --- | --- |
| P8.4-1 | Mandatory architecture review: read all ADRs, philosophy docs, grafana docs, Smart Home business telemetry docs | **Done** | ADR-028–031, dashboard-conventions.md, business telemetry docs |
| P8.4-2 | Metric verification: verify every metric, label, histogram, outcome value directly against implementation (no trust of docs alone) | **Done** | `SmartHomeDispatchTelemetry.php`, `SmartHomeActionTelemetry.php`, `SmartHomeProviderTelemetry.php`, all enums |
| P8.4-3 | Implement d02-smart-home.json (D-02 Smart Home Business, 23 panels, uid=ixora-smart-home, Business folder, ixora-prometheus, refresh=1m) | **Done** | `collector/grafana/provisioning/dashboards/business/d02-smart-home.json` |
| P8.4-4 | Extend validate.sh with checks 13–16 for D-02; verify 33/33 PASS + restart idempotency | **Done** | `collector/grafana/validate.sh` — 33/33 PASS (initial + restart) |
| P8.4-5 | Write dashboard-d02-smart-home.md | **Done** | `docs/specs/observability-foundation/mvp/dashboard-d02-smart-home.md` |
| P8.4-6 | Update tasks.md, plan.md, README.md | **Done** | Roadmap files |
| P8.4-7 | Git flow: commit → develop → staging → push → back to develop | **Done** | `feature/observability-smart-home-dashboard` |

**Phase 8.4 implementation notes:**

- First Business dashboard provisioned: D-02 Smart Home (23 panels across 5 sections: Health, Throughput, Failures, Performance, Business Relationships).
- **Metrics verified directly against implementation:** `ixora_smart_home_dispatch_total` (outcome: dispatched/skipped/error, entry_point: manual/scheduled/future), `ixora_smart_home_action_total` (outcome: success/failure/unsupported/unknown, provider: home_assistant/future), `ixora_smart_home_action_duration` (Histogram, ms, same labels as action_total).
- **`ixora_smart_home_provider_total` / `ixora_smart_home_provider_duration` NOT implemented** — Provider-level metrics were rejected in Phase 7B.4.6 §3.3 as 1:1 duplications. No panels for these metrics.
- **No `action_type` label** — deliberately deferred in Phase 7B.4.6 §3.2. No panels filter by action_type.
- **Queue/Business orthogonality** (Phase 7B.4.5 §8.3) explicitly documented in panel 501: `ixora_queue_job_total{outcome=success}` ≠ "Smart Home action succeeded". Both metrics shown together with explanation.
- **`unsupported` ≠ `failure`** — unsupported is a Business outcome (span stays OK), not a failure. Documented in panels 102, 303 and failures section.
- Validation extended: Checks 13–16 for D-02 (JSON syntax, UID, provisioned+folder, datasource refs). Total: 33/33 PASS.
- Variables: `$environment` (mandatory, custom, default staging), `$provider` (query-based from `label_values(action_total)`, includeAll=true).
- Business folder confirmed working — dashboard placed in Business folder automatically via providers.yaml (pre-existing provider definition from Phase 8.1).

**Branch:** `feature/observability-smart-home-dashboard`

---

## Phase 8.5 — Platform Overview Dashboard (D-01)

**Prerequisite:** dashboard-conventions.md (Phase 8.3), D-02 (Phase 8.4), D-04/D-05/D-06 (Phase 8.3), D-07 (Phase 8.2).

| ID | Task | Status | Reference |
| --- | --- | --- | --- |
| P8.5-1 | Mandatory review: dashboard-conventions, requirements, all dashboard docs, philosophy docs | **Done** | All docs read before implementation |
| P8.5-2 | Architecture review: verify all metrics from existing dashboards, UID map, folder structure | **Done** | All metrics traced to source dashboards; no new metrics introduced |
| P8.5-3 | Implement d01-platform-overview.json (D-01, 32 panels, uid=ixora-platform, Overview folder, ixora-prometheus, refresh=30s) | **Done** | `collector/grafana/provisioning/dashboards/overview/d01-platform-overview.json` |
| P8.5-4 | Extend validate.sh with checks 34–42; verify 42/42 PASS + restart idempotency | **Done** | `collector/grafana/validate.sh` — 42/42 PASS (initial + restart) |
| P8.5-5 | Write dashboard-d01-platform-overview.md | **Done** | `docs/specs/observability-foundation/mvp/dashboard-d01-platform-overview.md` |
| P8.5-6 | Update dashboard-conventions.md §1.2 (UID: ixora-overview → ixora-platform) | **Done** | `docs/specs/observability-foundation/mvp/dashboard-conventions.md` |
| P8.5-7 | Update tasks.md, plan.md, README.md | **Done** | Roadmap files |

**Phase 8.5 implementation notes:**

- First Overview/Platform dashboard provisioned: D-01 Platform Overview (32 panels: 5 row headers + 27 content panels across 5 sections).
- **Sections:** Platform Health (100–105), Business Summary (200–204), Application Summary (300–304), Infrastructure Summary (400–405), Navigation (500–504).
- **All metrics reused from existing verified dashboards** — no new metric names introduced. HTTP from D-05, Queue from D-04, Scheduler from D-06, Smart Home from D-02, Collector/Prometheus from D-07.
- **UID discrepancy:** `dashboard-conventions.md §1.2` planned `ixora-overview`; Phase 8.5 spec requires `ixora-platform`. Used `ixora-platform` per implementation spec; conventions updated.
- **Navigation panels** (Section 5): text-type panels with markdown links using stable UID-style URLs only. Check 38 validates no numeric IDs across all 6 dashboards.
- **Infrastructure panels not filtered by `$environment`**: `otelcol_*` and `up{job=...}` are platform-wide; `ixora_telemetry_export_failed_total` uses `deployment_environment` label (consistent with D-07).
- **D-03 Push Notifications absent**: `ixora_push_delivery_total` not yet implemented (Phase 7B.5). D-01 Business Summary can be extended when D-03 ships.
- Validation extended: Checks 34–42 (JSON syntax, UID, provisioned+folder, datasource refs, link style, panel ID uniqueness, panel ID ranges, description completeness, datasource UID completeness). Total: **42/42 PASS**.
- Restart idempotency verified: `docker compose restart grafana` → 42/42 PASS.

**Branch:** `feature/observability-platform-overview-dashboard`

---

## Phase 8.6 — Dashboard Integration & Operational Validation

**Prerequisite:** D-01 (Phase 8.5), D-02 (Phase 8.4), D-04/D-05/D-06 (Phase 8.3), D-07 (Phase 8.2).

| ID | Task | Status | Reference |
| --- | --- | --- | --- |
| P8.6-1 | Mandatory review: all dashboard docs, conventions, requirements, philosophy docs | **Done** | All docs read before implementation |
| P8.6-2 | Part 1: Add D-01 back-link to D-02, D-04, D-05, D-06, D-07 | **Done** | 5 dashboard JSON files updated |
| P8.6-3 | Part 2: Review + fix all link arrays (duplicates, order, broken, titles) | **Done** | All 30 links validated; D-02/D-04/D-05/D-06 also received D-02 cross-links; D-07 received all 5 links |
| P8.6-4 | Part 3: Extend dashboard-conventions.md with Overview Dashboard Principles (§13) | **Done** | `docs/specs/observability-foundation/mvp/dashboard-conventions.md` |
| P8.6-5 | Part 4: Document 4 operational investigation workflows | **Done** | `dashboard-operational-validation.md §6` |
| P8.6-6 | Part 5: Dashboard navigation matrix | **Done** | `dashboard-operational-validation.md §4` |
| P8.6-7 | Part 6: Extend validate.sh with checks 43–48; verify 48/48 PASS + restart idempotency | **Done** | `collector/grafana/validate.sh` — 48/48 PASS (initial + restart) |
| P8.6-8 | Part 7: Create dashboard-operational-validation.md | **Done** | `docs/specs/observability-foundation/mvp/dashboard-operational-validation.md` |
| P8.6-9 | Part 8: Architecture review (responsibilities, navigation, conventions, docs) | **Done** | `dashboard-operational-validation.md §7` |
| P8.6-10 | Update tasks.md, plan.md, README.md | **Done** | Roadmap files |

**Phase 8.6 implementation notes:**

- **Navigation mesh completed:** Phase 8.6 identified 5 dashboards with missing back-links (D-02: missing D-01; D-04/D-05/D-06: missing D-01 and D-02; D-07: **zero links**). All 30 navigation links (6 × 5 peers) are now present and validated.
- **Standard order established:** D-01 → D-02 → D-04 → D-05 → D-06 → D-07 (self excluded) enforced in all 6 dashboards and checked by validate.sh #44.
- **Overview Dashboard Principles:** New permanent architectural rule added to `dashboard-conventions.md §13`. Documents what overview dashboards must not and should do. Enforced by validate.sh checks 43–47.
- **Operational validation:** 4 complete investigation workflows documented (HTTP Server Error, Scheduler Failure, Queue Backlog, Smart Home Failure). Each includes navigation flow, evidence, usability observations, and recommendations.
- **Panel ID note (Check 48):** D-07 uses legacy sequential IDs (1–44, predating the convention). D-04/D-05/D-06 use section-range-start row IDs (200, 300, 400, 500 for row panels) — explicitly allowed by `dashboard-conventions.md §8`. Check 48 validates no duplicates + all IDs positive (the universally enforceable subset).
- **Navigation conventions §12 rewritten:** Phase 8.5 §12.1 documented per-folder link subsets. Phase 8.6 replaces this with the full bidirectional mesh standard, including `targetBlank: false` rule documented as §12.3.
- Validation extended: Checks 43–48 (back-link to D-01, link order, no duplicates, keepTime, no targetBlank, panel ID integrity). Total: **48/48 PASS**.
- Restart idempotency verified: `docker compose restart grafana` → 48/48 PASS (verified twice).

**Branch:** `feature/observability-dashboard-integration`

---

## Phase 8.7 — D-03 Push Notifications Dashboard

**Prerequisite:** D-01 (Phase 8.5), D-02 (Phase 8.4), D-04/D-05/D-06 (Phase 8.3), D-07 (Phase 8.2), dashboard-conventions.md (Phase 8.6).

| ID | Task | Status | Reference |
| --- | --- | --- | --- |
| P8.7-1 | Mandatory review: dashboard-conventions, dashboard-requirements, operational-validation, grafana-foundation, philosophy docs, push spec | **Done** | All docs read before implementation |
| P8.7-2 | Architecture review: verify push telemetry availability, UID map, folder, variables | **Done** | Phase 7B.5 not complete — build on queue layer (see notes) |
| P8.7-3 | Implement d03-push.json (23 panels: Platform Health, Business Throughput, Failures, Performance) | **Done** | `collector/grafana/provisioning/dashboards/business/d03-push.json` |
| P8.7-4 | Update all 6 existing dashboards to insert D-03 in navigation mesh at position 3 | **Done** | All 6 dashboard JSON files updated |
| P8.7-5 | Update validate.sh check 44 (new standard ordering includes D-03) + add checks 49–57 | **Done** | `collector/grafana/validate.sh` — 57/57 PASS (initial + restart) |
| P8.7-6 | Update dashboard-conventions.md §1.2 (D-03 status), §12.1 (new ordering table + example) | **Done** | `docs/specs/observability-foundation/mvp/dashboard-conventions.md` |
| P8.7-7 | Create dashboard-d03-push.md | **Done** | `docs/specs/observability-foundation/mvp/dashboard-d03-push.md` |
| P8.7-8 | Update tasks.md, plan.md, README.md | **Done** | Roadmap files |

**Phase 8.7 implementation notes:**

- **Phase 7B.5 not complete:** Architecture review found that `ixora.push.delivery.total` (the push-specific metric) does not exist in `back_vibes`. `PushNotificationJob` emits only logs, no custom metrics. D-03 is built on `ixora_queue_job_total{queue="push"}` and `ixora_queue_job_duration_bucket{queue="push"}` — the existing queue telemetry layer. This is real, production-ready observability at the queue level.
- **Navigation mesh expanded:** D-03 inserted at position 3 (D-01 → D-02 → D-03 → D-04 → D-05 → D-06 → D-07). All 6 existing dashboards updated. Total navigation links now: **42** (7 × 6).
- **Phase 7B.5 readiness:** `$provider` and `$notification_type` variables defined as static custom variables. Notification type values sourced from `PushNotificationEvents.php`: `smart_home_action_failed`, `schedule_execution_failed`, `smart_home_provider_unreachable`, `account_security_notice`. Providers: `fcm`, `noop`. These become `label_values()` queries when `ixora_push_delivery_total` ships.
- **validate.sh:** Check 44 ordering updated (was 6 dashboards, now 7). All count messages updated. Checks 49–57 validate D-03 JSON, UID, folder, datasource, links, variables, descriptions, duplicate IDs, and panel ranges.
- Validation extended: Checks 49–57 (D-03 file, UID, Grafana provisioning+folder, datasource, links, variables, descriptions, duplicates, ranges). Total: **57/57 PASS**.
- Restart idempotency verified: `docker compose restart grafana` → 57/57 PASS (verified twice).

**Branch:** `feature/observability-d03-push-dashboard`

---

## Phase 8.8 — Alerting Foundation

**Prerequisite:** All Phase 8.x dashboards complete; dashboard-conventions.md established; validate.sh at 57/57.

| ID | Task | Status | Reference |
| --- | --- | --- | --- |
| P8.8-1 | Mandatory review: dashboard-conventions, operational-validation, grafana-foundation, dashboard-requirements, all philosophy docs, telemetry-availability-policy, ADR-028–031 | **Done** | All docs read before implementation |
| P8.8-2 | Architecture review: integration with existing ecosystem, provisioning structure, existing alerting directory | **Done** | alerting/ already existed as .gitkeep; contact-points/notification-policies/mute-timings/templates did not exist |
| P8.8-3 | Create docs/architecture/alerting-philosophy.md | **Done** | 27-section document covering purpose, severity model, Golden Signals, USE/RED, categories, fatigue, lifecycle, runbook standard, label/annotation conventions, naming, investigation workflow |
| P8.8-4 | Create docs/specs/observability-foundation/mvp/alerting-foundation.md | **Done** | Implementation spec: provisioning hierarchy, category definitions (9 categories), contact points, notification policies, mute timings, templates, runbook standard, validation framework, Phase 9 readiness checklist |
| P8.8-5 | Create provisioning scaffold: contact-points/, notification-policies/, mute-timings/, templates/ | **Done** | 4 new directories + 4 placeholder YAML files (all valid YAML) |
| P8.8-6 | Extend validate.sh header + checks 58–67 | **Done** | 67/67 PASS |
| P8.8-7 | Update grafana-foundation.md known limitation (alerting is Phase 10+ → Phase 9) | **Done** | docs/specs/observability-foundation/mvp/grafana-foundation.md |
| P8.8-8 | Update tasks.md, plan.md, README.md | **Done** | Roadmap files |

**Phase 8.8 implementation notes:**

- **No runtime alert rules created.** validate.sh checks 58–67 verify structural integrity only — directories, documentation, YAML validity.
- **Provisioning scaffold:** 4 new provisioning sub-directories. `contact-points.yaml` defines the `ixora-default` placeholder receiver (Grafana UI only). `policies.yaml` routes everything to `ixora-default`. `mute-timings.yaml` has an empty placeholder. `templates/` has Go template definitions for Phase 9 use.
- **Philosophy document:** `alerting-philosophy.md` follows the same depth and structure as `metrics-philosophy.md`, `logs-philosophy.md`, and `traces-philosophy.md`. 27 sections covering the complete alerting lifecycle, alert maturity model (Levels 0–4), and review checklist.
- **Alert maturity:** Current state is Level 0 (no alerts). Phase 9 targets Level 1 (threshold alerts). Phase 10 targets Level 2 (tuned alerts). Phase 11+ targets Level 3–4 (predictive + SLO).
- **ADR-030 compliance enforced:** All label/annotation conventions explicitly prohibit PII. Contact point placeholder uses no credentials. Templates document the constraint.
- **validate.sh check count:** 57 → 67 (10 new checks).

**Branch:** `feature/observability-alerting-foundation`

---

## Phase 8.9 — Recording Rules & SLO Foundation

**Prerequisite:** Alerting Foundation complete (Phase 8.8); 67/67 validation checks; full dashboard ecosystem; Prometheus operational.

| ID | Task | Status | Reference |
| --- | --- | --- | --- |
| P8.9-1 | Mandatory review: metrics/logs/traces/alerting philosophy, telemetry docs, dashboard ecosystem, ADR-028–031 | **Done** | Architecture review before implementation |
| P8.9-2 | Architecture review: duplicate PromQL patterns, SLI candidates, dashboard/alert consumers | **Done** | 13 high-priority recording rule candidates identified |
| P8.9-3 | Create docs/architecture/recording-rules-philosophy.md | **Done** | 19 sections: purpose, benefits, when/when-not, naming, lifecycle, dashboard/alert/SLO relationships |
| P8.9-4 | Create docs/architecture/slo-philosophy.md | **Done** | 16 sections: SLI/SLO/SLA, error budget, Golden Signals, RED/USE, multi-window, burn rate concepts |
| P8.9-5 | Create docs/specs/observability-foundation/mvp/recording-rules-foundation.md | **Done** | Catalog (REC-001–027), 8 SLI definitions, SLO examples, error budget, migration strategy |
| P8.9-6 | Create prometheus/rules/recording/ placeholder YAML files | **Done** | application, business, infrastructure, slo — valid YAML, empty rules arrays |
| P8.9-7 | Extend validate.sh checks 68–78 | **Done** | 78/78 PASS |
| P8.9-8 | Update tasks.md, plan.md, README.md | **Done** | Roadmap files |

**Phase 8.9 implementation notes:**

- **No active recording rules.** `rule_files` remains commented out in `prometheus.yml`. Placeholder groups have `rules: []` with Phase 9 templates commented inline.
- **Architecture review:** 13 duplicate PromQL patterns identified across 7 dashboards (~40+ redundant evaluations per refresh). REC-001 through REC-020 catalogued with dashboard and alert consumer mappings.
- **SLI definitions:** 8 SLIs documented (SLI-001 through SLI-008) with formulas, source metrics, recording rule references, and example SLO targets.
- **SLO philosophy:** Error budget policy, multi-window and burn rate concepts documented without runtime implementation. SLO maturity model Level 1 achieved.
- **Integration:** Dashboard migration strategy (Phase 9b–9c) and alert integration mapping documented. Alert rules will consume recording rules instead of raw PromQL.
- **validate.sh check count:** 67 → 78 (11 new checks).

**Branch:** `feature/observability-recording-rules-slo-foundation`

---

## Phase 8.8.5 — Observability Infrastructure Provisioning

**Prerequisite:** Full observability stack in `collector/` (Phases 3–8.9); staging VPC exists in OpenTofu.

| ID | Task | Status | Reference |
| --- | --- | --- | --- |
| P8.85-1 | Mandatory review: collector/, opentofu/staging/, infrastructure-review, security-review, ADR-028–031 | **Done** | Architecture review before implementation |
| P8.85-2 | Create `observability.tf` — Droplet, firewall, optional volume | **Done** | `opentofu/staging/observability.tf` |
| P8.85-3 | Create cloud-init template (Docker, Compose v2, Caddy, systemd) — no secrets | **Done** | `templates/observability-cloud-init.yaml.tftpl` |
| P8.85-4 | Add observability variables and outputs | **Done** | `variables.tf`, `outputs.tf`, `terraform.tfvars.example` |
| P8.85-5 | Create `bootstrap-collector-env.sh` and `deploy-observability.sh` | **Done** | `scripts/` |
| P8.85-6 | Create provisioning doc and operational runbook | **Done** | `observability-infrastructure-provisioning.md`, `runbooks/observability-host.md` |
| P8.85-7 | Update collector/README.md, plan.md, tasks.md, docs/README.md, infrastructure-review.md | **Done** | Roadmap files |
| P8.85-8 | Static validation: tofu fmt/validate/plan, compose config, shellcheck | **Done** | See implementation report |

**Phase 8.8.5 implementation notes:**

- **Gap closed:** Previous `tofu plan` showed `0 to add` because no Droplet existed in OpenTofu. Now adds `digitalocean_droplet.observability` + `digitalocean_firewall.observability`.
- **Storage:** Strategy A (root disk) default; Strategy B (block volume) optional via `observability_use_block_volume`.
- **Network:** Public HTTPS (443) via Caddy only; internal backends on 127.0.0.1; OTLP via `https://otel-staging.ixora-app.app`.
- **Secrets:** Separate from OpenTofu — `bootstrap-collector-env.sh` with env vars; never in cloud-init or outputs.
- **App Platform OTEL:** Documented manual step; not wired in OpenTofu to avoid env churn.
- **No `tofu apply`:** IaC prepared only; host deployment is manual post-apply.

**Branch:** `feature/observability-infrastructure-provisioning`

---

| ID | Task | Status | Reference |
| --- | --- | --- | --- |
| P7B5-1 | Manual spans: push delivery | **Pending** | Uses `App\Telemetry\Contracts\Tracer` only |
| P7B5-2 | Custom metrics (`ixora.push.*`) per metrics-philosophy.md | **Pending** | |
| P7B5-3 | Verify no forbidden fields (device tokens, Firebase UIDs, notification content) in exported telemetry | **Pending** | [`ADR-030`](../../../decisions/ADR-030-observability-security-and-privacy.md) |

**Branch:** `feature/observability-push-instrumentation`

---

## Phase 7B.6 — External Providers

**Prerequisite:** Phase 7B.1 (HTTP + Routing).

| ID | Task | Status | Reference |
| --- | --- | --- | --- |
| P7B6-1 | Manual spans/metrics: outbound external-provider calls not covered by generic HTTP-client auto-instrumentation | **Pending** | Uses `App\Telemetry\Contracts\Tracer`/`Meter` only |
| P7B6-2 | Custom metrics (`ixora.<provider>.*`) per metrics-philosophy.md | **Pending** | |
| P7B6-3 | Verify no forbidden fields (credentials, PII) in exported telemetry | **Pending** | [`ADR-030`](../../../decisions/ADR-030-observability-security-and-privacy.md) |

**Branch:** `feature/observability-external-providers-instrumentation`

---

## Phase 8 — Frontend SDK

| ID | Task | Status | Reference |
| --- | --- | --- | --- |
| P8-1 | Evaluate OTel JS SDK for Capacitor Android | **Pending** | |
| P8-2 | Instrument errors and key navigation spans | **Pending** | [`ADR-029`](../../../decisions/ADR-029-telemetry-data-model.md) |
| P8-3 | Mobile sampling per ADR-031 | **Pending** | |
| P8-4 | Staging build exports to Collector | **Pending** | |
| P8-5 | Verify no PII in mobile telemetry | **Pending** | [`ADR-030`](../../../decisions/ADR-030-observability-security-and-privacy.md) |

**Branch:** `feature/observability-frontend-sdk`

---

## Phase 9 — Grafana dashboards

| ID | Task | Status | Reference |
| --- | --- | --- | --- |
| P9-1 | Deploy Grafana with authenticated access | **Pending** | |
| P9-2 | Dashboard: API latency and errors | **Pending** | |
| P9-3 | Dashboard: Scheduler + Smart Home + Push | **Pending** | |
| P9-4 | Dashboard: Queue worker health | **Pending** | |
| P9-5 | Document dashboard URLs in runbook | **Pending** | |

**Branch:** `feature/observability-grafana-dashboards`

---

## Phase 9.5 — Telemetry Decision Guide + Observability Playbook

| ID | Task | Status | Reference |
| --- | --- | --- | --- |
| P9.5-1 | Publish **`telemetry-decision-guide.md`** | **Done** | [`telemetry-decision-guide.md`](../../../architecture/telemetry-decision-guide.md) |
| P9.5-2 | Publish **`observability-playbook.md`** | **Done** | [`observability-playbook.md`](../../../operations/observability-playbook.md) |

**Phase 9.5 implementation notes:**

- Decision guide: which signal (metric, trace, span, event, log, label) — complements naming convention.
- Playbook: operational investigation workflows for scheduler, Smart Home, push, and observability stack.
- Documentation only — no runtime code, SDK, Collector, Grafana, or infrastructure changes.
- Placed in roadmap between Phase 9 (dashboards) and Phase 10 (operational readiness).

---

## Phase 10 — Operational readiness

| ID | Task | Status | Reference |
| --- | --- | --- | --- |
| P10-1 | Publish observability operational checklist | **Pending** | |
| P10-2 | Disk usage alert thresholds documented | **Pending** | [`ADR-031`](../../../decisions/ADR-031-retention-storage-and-cost-control.md) |
| P10-3 | Collector restart / recovery procedure | **Pending** | |
| P10-4 | Link from staging-digitalocean.md | **Pending** | |

**Branch:** `feature/observability-operational-readiness`

---

## Phase 11 — QA

| ID | Task | Status | Reference |
| --- | --- | --- | --- |
| P11-1 | Telemetry export integration tests | **Pending** | |
| P11-2 | Failure isolation: Collector down → API healthy | **Pending** | [`spec.md`](spec.md) OBS-8 |
| P11-3 | Security spot check (ADR-030 samples) | **Pending** | |
| P11-4 | Retention verification | **Pending** | [`ADR-031`](../../../decisions/ADR-031-retention-storage-and-cost-control.md) |
| P11-5 | Publish QA summary | **Pending** | |

**Branch:** `feature/observability-qa`

---

## Phase 11.5 — Appium mobile telemetry validation

| ID | Task | Status | Reference |
| --- | --- | --- | --- |
| P11.5-1 | Run Appium critical path; verify traces in Tempo | **Pending** | [mobile-e2e-testing.md](../../../testing/mobile-e2e-testing.md) |
| P11.5-2 | Verify mobile telemetry contains no forbidden fields | **Pending** | [`ADR-030`](../../../decisions/ADR-030-observability-security-and-privacy.md) |
| P11.5-3 | Document results in QA report | **Pending** | |

**Branch:** `feature/observability-appium-telemetry-qa`

---

## Release

| ID | Task | Status | Reference |
| --- | --- | --- | --- |
| REL-1 | Tag release across repos | **Pending** | |
| REL-2 | Publish release notes | **Pending** | `docs/releases/` |
| REL-3 | Staging sign-off before production VM | **Pending** | |

---

When a phase completes, update this file and [`plan.md`](plan.md) — do not mark future phases **Done** until merged and verified.
