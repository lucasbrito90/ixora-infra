# Observability Foundation MVP — platform-wide telemetry

**Status:** Active feature specification (Phase 1 — ADRs + Spec)  
**Version:** 1.0 (MVP scope — documentation only; no runtime code in Phase 1)  
**Feature ID:** `observability-foundation/mvp`  
**Platform:** `ixora-infra` (architecture + infra), `back_vibes` (SDK), `front_vibes` (SDK)

> **Phase 1 = ADRs + Spec only.** No OpenTelemetry SDK, Collector configs, Docker, Terraform, Grafana dashboards, or VM deployment in Phase 1. Implementation begins in Phase 2+ per [`plan.md`](plan.md).

**Architecture decisions:** [ADR-028](../../../decisions/ADR-028-observability-platform.md) (platform), [ADR-029](../../../decisions/ADR-029-telemetry-data-model.md) (data model), [ADR-030](../../../decisions/ADR-030-observability-security-and-privacy.md) (security), [ADR-031](../../../decisions/ADR-031-retention-storage-and-cost-control.md) (retention/cost).

**Builds on (shipped):** Push Notifications Foundation, Scheduler MVP, Smart Home MVP, Scheduler + Smart Home Automations ([v1.2.0 release](../../../releases/v1.2.0-scheduler-smart-home-automations.md)).

---

## 1. Overview

Provide **platform-wide observability** for Ixora through a single OpenTelemetry pipeline:

- Applications export telemetry via **OpenTelemetry SDK** → **OpenTelemetry Collector** (sole ingestion endpoint)
- Collector fans out: **metrics → Prometheus**, **logs → Loki**, **traces → Tempo**
- **Grafana** reads all three backends for troubleshooting and dashboards

MVP deploys on a **single DigitalOcean VM** (staging first). No alerting, no HA, no multi-region.

---

## 2. Goals

| ID | Goal |
| --- | --- |
| OBS-1 | Single telemetry pipeline — all apps → Collector only |
| OBS-2 | Support `back_vibes` API and queue workers |
| OBS-3 | Support `front_vibes` Android client |
| OBS-4 | Support future providers (Smart Home, push, analytics) via consistent model |
| OBS-5 | Enable cross-signal troubleshooting (trace ↔ log ↔ metric) |
| OBS-6 | Enable Grafana dashboards (Phase 9) |
| OBS-7 | Enable alerts later — architecture must not block alerting (Phase post-MVP) |
| OBS-8 | Observability failure must never block business logic |
| OBS-9 | Security: observability must never become a data leak ([ADR-030](../../../decisions/ADR-030-observability-security-and-privacy.md)) |
| OBS-10 | Predictable storage cost on single VM ([ADR-031](../../../decisions/ADR-031-retention-storage-and-cost-control.md)) |

---

## 3. Non-goals

| Non-goal | Reason |
| --- | --- |
| **Alerting / PagerDuty** | Phase post-MVP — dashboards first |
| **Sentry replacement** | Crash reporting out of scope |
| **Distributed multi-region deployment** | Single VM MVP |
| **Kubernetes** | DO VM only |
| **Long-term archive / cold storage** | Retention caps in ADR-031 |
| **Production HA for observability stack** | Explicitly deferred |
| **Billing / cost dashboards** | Not product telemetry |
| **AI anomaly detection** | Out of scope |
| **Direct app → Prometheus/Loki/Tempo** | Forbidden by ADR-028 |
| **Production deploy in Phase 1** | Documentation only |

---

## 4. Target architecture

```
┌─────────────────────────────────────────────────────────────┐
│              DigitalOcean VM (observability)                 │
│  ┌──────────────────┐                                       │
│  │ OTel Collector   │ ← sole OTLP ingestion endpoint        │
│  └────────┬─────────┘                                       │
│           ├── metrics  → Prometheus (30d retention)         │
│           ├── logs     → Loki (14d retention)               │
│           └── traces   → Tempo (7d retention)                 │
│  ┌──────────────────┐                                       │
│  │ Grafana          │ → queries Prometheus, Loki, Tempo     │
│  └──────────────────┘                                       │
└─────────────────────────────────────────────────────────────┘
         ▲                              ▲
         │ OTLP                         │ OTLP
         │                              │
┌────────┴────────┐            ┌────────┴────────┐
│   back_vibes    │            │   front_vibes   │
│ API + workers   │            │ Android (Cap.)  │
│ OTel PHP SDK    │            │ OTel JS SDK     │
└─────────────────┘            └─────────────────┘
```

---

## 5. Architecture mapping

Per [feature-spec-template](../../../templates/feature-spec-template.md) and [ADR-027](../../../decisions/ADR-027-asynchronous-orchestration-pattern.md) — adapted for observability (not async domain flow):

| Layer | Component | Role |
| --- | --- | --- |
| **Entrypoint** | OpenTelemetry SDK (app-initiated export) | Applications emit metrics, logs, traces via OTLP |
| **Domain Validator** | **N/A** | Observability is cross-cutting infrastructure — no domain validation gate. Security enforced by [ADR-030](../../../decisions/ADR-030-observability-security-and-privacy.md) redaction rules and code review, not a runtime validator class. |
| **Domain Service** | OpenTelemetry Collector | Receives OTLP; processes (sample, redact, batch); routes to backends |
| **Jobs** | **N/A** | Collector and backends run as daemon processes — not Laravel queue jobs |
| **Providers** | Prometheus, Loki, Tempo | Storage/query backends — **never called directly by applications** |
| **Side effects** | Telemetry export (async, best-effort) | Must not mutate product state |
| **Failure policy** | Application continues if Collector unavailable | Export failures logged locally; business logic unaffected ([ADR-029](../../../decisions/ADR-029-telemetry-data-model.md)) |

**Related ADRs:** [ADR-026](../../../decisions/ADR-026-automation-execution-security.md) · [ADR-027](../../../decisions/ADR-027-asynchronous-orchestration-pattern.md) · [ADR-028](../../../decisions/ADR-028-observability-platform.md) · [ADR-029](../../../decisions/ADR-029-telemetry-data-model.md) · [ADR-030](../../../decisions/ADR-030-observability-security-and-privacy.md) · [ADR-031](../../../decisions/ADR-031-retention-storage-and-cost-control.md)

---

## 6. Telemetry scope (MVP instrumentation targets)

| Domain | Metrics | Logs | Traces |
| --- | --- | --- | --- |
| **HTTP API** | Request duration, status | Errors, 5xx | Per-request span |
| **Scheduler** | Dispatch duration, outcome | Validator skip, SH dispatch failure | Command tick span |
| **Smart Home jobs** | Action duration, outcome | Provider failures | Job → adapter spans |
| **Push pipeline** | Delivery counter | Queue failures | Job span |
| **Queue worker** | Jobs processed | Job exceptions | Per-job span |
| **Mobile app** | Session errors (optional) | JS errors, navigation | Screen load spans (sampled) |

Detailed naming: [ADR-029](../../../decisions/ADR-029-telemetry-data-model.md).

---

## 7. Security and retention summary

| Topic | Decision | ADR |
| --- | --- | --- |
| PII in telemetry | Forbidden — `user_id` only as attribute | ADR-030 |
| Credentials | Never in logs/traces/metrics | ADR-030 |
| Collector redaction | Second line of defense | ADR-030 |
| Metrics retention | 30 days | ADR-031 |
| Logs retention | 14 days | ADR-031 |
| Traces retention | 7 days | ADR-031 |
| Trace sampling | 10% success / 100% errors | ADR-031 |
| Cardinality | No `user_id` as metric label | ADR-031 |

---

## 8. Implementation roadmap

See [`plan.md`](plan.md). Phases intentionally small:

| Phase | Deliverable |
| --- | --- |
| **1** | ADRs + Spec (this phase) |
| **2** | Infrastructure review (VM sizing, networking, firewall) |
| **2.5** | Security review (redaction, access control, secrets) |
| **3** | Collector deployment |
| **3.5** | Collector validation & hardening |
| **3.75** | Metrics Philosophy (architecture guide — before backend instrumentation) |
| **4** | Prometheus — `prometheusremotewrite` active; 30-day retention; internal only |
| **5** | Loki — `loki` exporter active; 14-day retention; Collector sole writer |
| **6** | Tempo |
| **7** | Backend SDK (`back_vibes`) — Phases **7A** and **7B** must follow [metrics-philosophy.md](../../../architecture/metrics-philosophy.md) |
| **8** | Frontend SDK (`front_vibes`) |
| **9** | Grafana dashboards |
| **10** | Operational readiness runbook |
| **11** | QA (automated + staging validation) |
| **11.5** | Appium mobile telemetry validation |
| **Release** | Tag + release notes |

---

## 9. Acceptance criteria

### Phase 1 (this document)

- [x] `spec.md` published
- [x] `plan.md` published
- [x] `tasks.md` published
- [x] ADR-028 — Observability platform — accepted
- [x] ADR-029 — Telemetry data model — accepted
- [x] ADR-030 — Security and privacy — accepted
- [x] ADR-031 — Retention and cost control — accepted
- [x] `docs/README.md` updated
- [x] **No runtime code** in Phase 1

### Phase 2+ (implementation)

See [`tasks.md`](tasks.md).

---

## 10. Review checklist

Before marking any implementation phase **Done**:

- [ ] Applications export **only** to Collector OTLP endpoint
- [ ] No Prometheus/Loki/Tempo credentials in app repos
- [ ] Redaction processor active on Collector
- [ ] Retention configured per ADR-031
- [ ] Sampling configured per ADR-031
- [ ] `trace_id` present in Laravel logs for instrumented paths
- [ ] No forbidden fields in sample telemetry ([ADR-030](../../../decisions/ADR-030-observability-security-and-privacy.md) examples)
- [ ] Business logic passes when Collector is stopped
- [ ] Grafana authenticated; not public without auth
- [ ] Operational runbook published (Phase 10)

---

## Related docs

| Document | Relationship |
| --- | --- |
| [ADR-028](../../../decisions/ADR-028-observability-platform.md) | Platform topology |
| [ADR-029](../../../decisions/ADR-029-telemetry-data-model.md) | Naming and correlation |
| [ADR-030](../../../decisions/ADR-030-observability-security-and-privacy.md) | Privacy |
| [ADR-031](../../../decisions/ADR-031-retention-storage-and-cost-control.md) | Retention/cost |
| [ADR-021](../../../decisions/ADR-021-notification-security-and-privacy.md) | Notification privacy alignment |
| [ADR-024](../../../decisions/ADR-024-automation-notifications-and-observability.md) | Product observability today |
| [telemetry-naming-convention.md](../../../architecture/telemetry-naming-convention.md) | Official naming — services, metrics, spans, logs, events, labels |
| [metrics-philosophy.md](../../../architecture/metrics-philosophy.md) | **Phase 3.75** — how engineers think about metrics; mandatory before Phases 7A/7B |
| [loki-deployment.md](loki-deployment.md) | **Phase 5** — Loki container, config, Collector wiring, validation, retention |
| [prometheus-deployment.md](prometheus-deployment.md) | **Phase 4** — Prometheus container, config, Collector wiring, validation |
| [telemetry-decision-guide.md](../../../architecture/telemetry-decision-guide.md) | Signal choice — metric vs trace vs log vs event |
| [infrastructure-review.md](infrastructure-review.md) | Phase 2 — deployment topology, ports, storage, failure analysis |
| [security-review.md](security-review.md) | Phase 2.5 — threat model, auth, TLS, PII, redaction |
| [telemetry-availability-policy.md](../../../architecture/telemetry-availability-policy.md) | Non-blocking telemetry export policy |
| [observability-operational-limits.md](../../../architecture/observability-operational-limits.md) | Architectural limits for Collector and backends |
| [collector-hardening-checklist.md](../../../operations/collector-hardening-checklist.md) | Phase 3 Collector deploy checklist |
| [collector-deployment.md](collector-deployment.md) | Phase 3 — Collector configuration, Docker Compose, security, validation |
| [collector-validation-report.md](collector-validation-report.md) | Phase 3.5 — validation results, hardening sign-off, performance baseline |
| [mobile-e2e-testing.md](../../../testing/mobile-e2e-testing.md) | Phase 11.5 mobile validation |
| [plan.md](plan.md) · [tasks.md](tasks.md) | Implementation tracking |
