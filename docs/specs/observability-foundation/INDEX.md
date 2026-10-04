# Observability Foundation — Index

**Current state:** All phases complete (Phase 1 through 8.9). Backend SDK, HTTP, Queue, Console, Scheduler, Smart Home Business Telemetry, 7 Grafana dashboards, Alerting Foundation, Recording Rules & SLO Foundation — all shipped in `back_vibes` and operational on staging.

---

## Start here for most tasks

| Task | Document |
| --- | --- |
| Understand the foundation | [`mvp/spec.md`](mvp/spec.md) |
| Add telemetry to backend code | [`mvp/backend-sdk-foundation.md`](mvp/backend-sdk-foundation.md) + [`../../architecture/telemetry-decision-guide.md`](../../architecture/telemetry-decision-guide.md) |
| Naming a metric / span / log | [`../../architecture/telemetry-naming-convention.md`](../../architecture/telemetry-naming-convention.md) |
| Business telemetry standard | [`business-telemetry/business-telemetry-foundation.md`](business-telemetry/business-telemetry-foundation.md) |
| Dashboard conventions | [`mvp/dashboard-conventions.md`](mvp/dashboard-conventions.md) |
| Alerting rules | [`mvp/alerting-foundation.md`](mvp/alerting-foundation.md) |
| Recording rules / SLOs | [`mvp/recording-rules-foundation.md`](mvp/recording-rules-foundation.md) |
| Collector operations | `ixora-infra/collector/README.md` |
| Investigate an incident | [`../../operations/observability-playbook.md`](../../operations/observability-playbook.md) |

---

## Implementation phase docs (historical — all done)

Load these only when investigating how something was built, not for new implementation.

### Infrastructure
`mvp/infrastructure-review.md` · `mvp/security-review.md` · `mvp/collector-deployment.md` · `mvp/collector-validation-report.md` · `mvp/prometheus-deployment.md` · `mvp/loki-deployment.md` · `mvp/tempo-deployment.md` · `mvp/observability-infrastructure-provisioning.md`

### Backend SDK (Phase 7A–7B.3)
`mvp/backend-sdk-foundation.md` · `mvp/backend-http-routing-instrumentation.md` · `mvp/backend-queue-console-instrumentation.md` · `mvp/backend-generic-scheduler-instrumentation.md`

### Smart Home Business Telemetry (Phase 7B.4)
`business-telemetry/domain-execution-review.md` · `business-telemetry/backend-smart-home-dispatch-boundary.md` · `business-telemetry/backend-smart-home-action-execution.md` · `business-telemetry/backend-smart-home-provider-boundary.md` · `business-telemetry/backend-business-failure-semantics.md` · `business-telemetry/backend-smart-home-business-metrics.md` · `business-telemetry/backend-smart-home-business-logging.md` · `business-telemetry/backend-business-telemetry-validation.md`

### Dashboards (Phase 8.0–8.7)
`mvp/grafana-foundation.md` · `mvp/dashboard-requirements.md` · `mvp/dashboard-conventions.md` · `mvp/dashboard-d01-platform-overview.md` · `mvp/dashboard-d02-smart-home.md` · `mvp/dashboard-d03-push.md` · `mvp/dashboard-d04-queue.md` · `mvp/dashboard-d05-http.md` · `mvp/dashboard-d06-scheduler.md` · `mvp/dashboard-d07-infrastructure.md` · `mvp/dashboard-operational-validation.md`

### Alerting + Recording Rules (Phase 8.8–8.9)
`mvp/alerting-foundation.md` · `mvp/recording-rules-foundation.md`

---

## ADRs (Observability)
ADR-028 through ADR-031 — in `ixora-infra/docs/decisions/`.
