# Observability Foundation MVP — task checklist

**Status:** Phase 1 + 1.5 complete — ADRs + Spec + Naming Convention  
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
| 2 — Infrastructure review | 5 | 0 | 0 | 0 |
| 2.5 — Security review | 4 | 0 | 0 | 0 |
| 3 — Collector deployment | 4 | 0 | 0 | 0 |
| 4 — Prometheus | 3 | 0 | 0 | 0 |
| 5 — Loki | 3 | 0 | 0 | 0 |
| 6 — Tempo | 3 | 0 | 0 | 0 |
| 7 — Backend SDK | 6 | 0 | 0 | 0 |
| 8 — Frontend SDK | 5 | 0 | 0 | 0 |
| 9 — Dashboards | 5 | 0 | 0 | 0 |
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
| P2-1 | Document DO VM sizing (CPU/RAM/disk) vs ADR-031 budgets | **Pending** | [`ADR-031`](../../../decisions/ADR-031-retention-storage-and-cost-control.md) |
| P2-2 | Document firewall / OTLP ingress from App Platform + mobile | **Pending** | [`ADR-028`](../../../decisions/ADR-028-observability-platform.md) |
| P2-3 | Document Collector endpoint DNS/TLS strategy | **Pending** | |
| P2-4 | Review App Platform egress to observability VM | **Pending** | [staging-digitalocean](../../../architecture/backend/staging-digitalocean.md) |
| P2-5 | Publish infrastructure review note | **Pending** | |

**Branch:** `feature/observability-infra-review`

---

## Phase 2.5 — Security review

| ID | Task | Status | Reference |
| --- | --- | --- | --- |
| P2.5-1 | Review ADR-030 against existing Laravel log patterns | **Pending** | [`ADR-030`](../../../decisions/ADR-030-observability-security-and-privacy.md) |
| P2.5-2 | Document Collector redaction processor requirements | **Pending** | |
| P2.5-3 | Define Grafana authentication model | **Pending** | |
| P2.5-4 | Threat model: public OTLP endpoint → API key or mTLS decision | **Pending** | |

**Branch:** `feature/observability-security-review`

---

## Phase 3 — Collector deployment

| ID | Task | Status | Reference |
| --- | --- | --- | --- |
| P3-1 | Deploy OpenTelemetry Collector on DO VM | **Pending** | [`ADR-028`](../../../decisions/ADR-028-observability-platform.md) |
| P3-2 | Configure OTLP receivers (HTTP + gRPC) | **Pending** | |
| P3-3 | Configure redaction + sampling processors | **Pending** | [`ADR-030`](../../../decisions/ADR-030-observability-security-and-privacy.md) · [`ADR-031`](../../../decisions/ADR-031-retention-storage-and-cost-control.md) |
| P3-4 | Verify health endpoint + test OTLP ingest | **Pending** | |

**Branch:** `feature/observability-collector-deploy`

---

## Phase 4 — Prometheus

| ID | Task | Status | Reference |
| --- | --- | --- | --- |
| P4-1 | Deploy Prometheus with 30-day retention | **Pending** | [`ADR-031`](../../../decisions/ADR-031-retention-storage-and-cost-control.md) |
| P4-2 | Wire Collector → Prometheus exporter | **Pending** | [`ADR-028`](../../../decisions/ADR-028-observability-platform.md) |
| P4-3 | Verify `up` metric and retention flag | **Pending** | |

**Branch:** `feature/observability-prometheus`

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
