# Observability Foundation MVP — task checklist

**Status:** Phase 1 + 1.5 + 2 + 2.5 + 9.5 + 3 + 3.5 + 3.75 + 4 complete — ADRs + Spec + Infra + Security + Guides + Collector + Validation + Metrics Philosophy + Prometheus  
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
| 5 — Loki | 3 | 0 | 0 | 0 |
| 6 — Tempo | 3 | 0 | 0 | 0 |
| 7 — Backend SDK | 6 | 0 | 0 | 0 |
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
| P5-1 | Deploy Loki with 14-day retention | **Pending** | [`ADR-031`](../../../decisions/ADR-031-retention-storage-and-cost-control.md) |
| P5-2 | Wire Collector → Loki exporter | **Pending** | |
| P5-3 | Verify log ingest + query | **Pending** | |

**Branch:** `feature/observability-loki`

---

## Phase 6 — Tempo

| ID | Task | Status | Reference |
| --- | --- | --- | --- |
| P6-1 | Deploy Tempo with 7-day retention | **Pending** | [`ADR-031`](../../../decisions/ADR-031-retention-storage-and-cost-control.md) |
| P6-2 | Wire Collector → Tempo with head sampling | **Pending** | |
| P6-3 | Verify trace ingest + `trace_id` search | **Pending** | |

**Branch:** `feature/observability-tempo`

---

## Phase 7 — Backend SDK

**Prerequisite:** [metrics-philosophy.md](../../../architecture/metrics-philosophy.md) (Phase 3.75).

| ID | Task | Status | Reference |
| --- | --- | --- | --- |
| P7-1 | Evaluate and integrate OpenTelemetry PHP SDK in `back_vibes` | **Pending** | [`ADR-029`](../../../decisions/ADR-029-telemetry-data-model.md) |
| P7-2 | Auto-instrument HTTP + queue + console | **Pending** | |
| P7-3 | Manual spans: Smart Home adapter, push delivery | **Pending** | |
| P7-4 | Inject `trace_id` into Laravel log context | **Pending** | |
| P7-5 | Staging env vars documented | **Pending** | |
| P7-6 | Verify no forbidden fields in exported telemetry | **Pending** | [`ADR-030`](../../../decisions/ADR-030-observability-security-and-privacy.md) |

**Branch:** `feature/observability-backend-sdk`

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
