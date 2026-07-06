# Observability Foundation MVP — implementation plan

**Status:** Phase 1 complete — pre-implementation  
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

---

## Current state

| Area | State |
| --- | --- |
| **App Platform runtime logs** | ✅ Shipped — stderr JSON on DO |
| **Laravel structured logs** | ✅ Shipped — `Log::` with context |
| **Product observability (automation)** | ✅ Shipped — execution rows + worker logs ([ADR-024](../../../decisions/ADR-024-automation-notifications-and-observability.md)) |
| **OpenTelemetry Collector** | ❌ Not deployed |
| **Prometheus / Loki / Tempo / Grafana** | ❌ Not deployed |
| **OTel SDK (backend)** | ❌ Not integrated |
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
Phase 4    ──► Prometheus
Phase 5    ──► Loki
Phase 6    ──► Tempo
Phase 7    ──► Backend SDK (back_vibes)
Phase 8    ──► Frontend SDK (front_vibes)
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

## Phase 4 — Prometheus

**Goal:** Metrics backend with 30-day retention.

### Exit criteria

- Collector exports metrics to Prometheus.
- `up` metric visible; retention flag set per ADR-031.

---

## Phase 5 — Loki

**Goal:** Log aggregation with 14-day retention.

### Exit criteria

- Collector exports logs to Loki.
- Test log queryable in Grafana Explore (Grafana may deploy in Phase 9 — Loki CLI OK for Phase 5).

---

## Phase 6 — Tempo

**Goal:** Trace backend with 7-day retention and sampling.

### Exit criteria

- Collector exports traces to Tempo with head sampling per ADR-031.
- Test trace searchable by `trace_id`.

---

## Phase 7 — Backend SDK

**Goal:** `back_vibes` emits OTLP to Collector.

### Scope

- OpenTelemetry PHP SDK (or Laravel-compatible package — evaluate in phase).
- Auto-instrument HTTP requests, queue jobs, console commands.
- Manual spans for Smart Home adapter, push delivery.
- `trace_id` injected into Laravel log context.
- Env: `OTEL_EXPORTER_OTLP_ENDPOINT`, `OTEL_SERVICE_NAME`.

### Exit criteria

- Staging API + worker export telemetry.
- Collector receives signals; no forbidden fields in spot check.

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
| Backend SDK before dashboards | 7 before 9 |
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
