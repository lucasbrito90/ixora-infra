# Recording Rules & SLO Foundation — Phase 8.9

**Status:** Complete  
**Type:** Architecture Specification + Active SLO Implementation  
**Repo:** `ixora-infra`  
**Feature ID:** `observability-foundation/mvp`  
**Established:** Phase 8.9  
**ADRs:** [ADR-028](../../../decisions/ADR-028-observability-platform.md) · [ADR-029](../../../decisions/ADR-029-telemetry-data-model.md) · [ADR-030](../../../decisions/ADR-030-observability-security-and-privacy.md) · [ADR-031](../../../decisions/ADR-031-retention-storage-and-cost-control.md)  
**Philosophy:** [recording-rules-philosophy.md](../../../architecture/recording-rules-philosophy.md) · [slo-philosophy.md](../../../architecture/slo-philosophy.md)  
**Prerequisite:** [alerting-foundation.md](alerting-foundation.md) (Phase 8.8) · [grafana-foundation.md](grafana-foundation.md) (Phase 8.1) · [dashboard-conventions.md](dashboard-conventions.md) (Phase 8.3–8.6)

> **Rule:** Recording rules, SLO aggregates, burn-rate alerts, and D-08 dashboard are implemented in-repo. Remote deploy requires explicit approval — see [slo-error-budget runbook](../../../runbooks/slo-error-budget.md).

---

## 1. Overview

Phase 8.9 establishes the **Recording Rules & SLO Foundation** — SLI pre-computation, 30-day error budgets, multi-window burn-rate alerts, and the D-08 SLO dashboard.

### 1.1 What Phase 8.9 delivers

| Deliverable | Description |
| --- | --- |
| Recording rules philosophy | [recording-rules-philosophy.md](../../../architecture/recording-rules-philosophy.md) |
| SLO philosophy | [slo-philosophy.md](../../../architecture/slo-philosophy.md) |
| Recording rules (active) | `application.rules.yml`, `business.rules.yml`, `infrastructure.rules.yml`, `slo.rules.yml` — 71 recording rules |
| SLO burn-rate alerts | `alerting/slo.alerts.yml` — 12 multi-window alerts with low-traffic guards |
| D-08 dashboard | `d08-slo-error-budget.json` — uid `ixora-slo`, Overview folder |
| Runbook | [slo-error-budget.md](../../../runbooks/slo-error-budget.md) |
| Math tests | `collector/scripts/test-slo-math.py` |
| Validation | validate.sh checks 68–78, 91–98 |

### 1.2 Deferred (not in scope)

- Push notification dedicated SLO (SLI-008 queue proxy only)
- Per-provider Smart Home SLO
- Mobile client SLO; regional SLO
- Dashboard migration to recording rules (D-01–D-07 still use raw PromQL)
- Node Exporter / VM resource SLOs
- Remote deploy / `tofu apply`

---

## 2. Architecture Review

### 2.1 Current state (post Phase 8.9 implementation)

| Component | Status |
| --- | --- |
| Raw metrics (Phase 7A–7B.4.9) | ✅ Instrumented in `back_vibes` |
| Dashboards (D-01 through D-08) | ✅ 8 dashboards; D-08 SLO & Error Budget added |
| Alerting Foundation (Phase 8.8) | ✅ Philosophy, provisioning scaffold |
| Recording rules | ✅ Active in repo; `rule_files` enabled; docker-compose mount |
| SLO tracking | ✅ 6 SLOs with SLI, 30d budget, burn rates |
| Burn-rate alerts | ✅ Prometheus `slo.alerts.yml` (staging thresholds) |

### 2.2 Duplicate PromQL patterns identified

Architecture review of all 7 dashboard JSON files identified **13 high-priority recording rule candidates** based on expression reuse and computational cost.

| Priority | Pattern | Occurrences | Dashboards | Recording rule |
| --- | --- | --- | --- | --- |
| P0 | HTTP server error rate | 3 | D-01, D-05 | `ixora:http:error_rate:5m` |
| P0 | Smart Home success rate | 5 | D-01, D-02 | `ixora:smart_home:success_rate:5m` |
| P0 | Smart Home failure rate | 3 | D-01, D-02 | `ixora:smart_home:failure_rate:5m` |
| P0 | Queue success rate | 2 | D-01, D-04 | `ixora:queue:success_rate:5m` |
| P1 | HTTP p95 latency | 4 | D-01, D-05 | `ixora:http:p95_latency:5m` |
| P1 | Queue p95 latency | 6 | D-04, D-03 | `ixora:queue:p95_latency:5m` |
| P1 | Smart Home p95 latency | 5 | D-01, D-02 | `ixora:smart_home:p95_latency:5m` |
| P1 | Scheduler p95 latency | 3 | D-06 | `ixora:scheduler:p95_latency:5m` |
| P1 | Push queue success rate | 1 | D-03 | `ixora:push:success_rate:5m` |
| P1 | Push queue failure rate | 2 | D-03 | `ixora:push:failure_rate:5m` |
| P2 | HTTP availability (1 − error) | 1 | D-01 | `ixora:http:availability:5m` |
| P2 | Scheduler success rate | 1 | D-06 | `ixora:scheduler:success_rate:5m` |
| P2 | Collector availability | 1 | D-07 | `ixora:collector:availability` |

**Total duplicate expression evaluations per dashboard refresh cycle:** ~40+ independent evaluations of ~13 unique patterns.

### 2.3 Optimization opportunities (documented, not implemented)

| Opportunity | Impact | Phase |
| --- | --- | --- |
| Pre-compute 13 shared ratios/percentiles | Reduce query load ~70% on D-01 refresh | Phase 9 |
| Alert rules consume recording rules | Faster alert evaluation; formula consistency | Phase 9 |
| SLI 30-day aggregates | Enable error budget tracking | Phase 10 |
| Multi-window burn rate rules | Detect slow reliability degradation | Phase 11 |
| Dashboard panel migration | Simpler panel queries; self-documenting source | Phase 9–10 |

### 2.4 Metric inventory for recording rules

All recording rules reference metrics from the existing instrumentation inventory. Prometheus stores OTel dot-notation as underscores.

| OTel name (instrumentation) | Prometheus name (dashboards/rules) | Type |
| --- | --- | --- |
| `ixora.http.server.request.total` | `ixora_http_server_request_total` | Counter |
| `ixora.http.server.duration` | `ixora_http_server_duration_bucket/sum/count` | Histogram |
| `ixora.queue.job.total` | `ixora_queue_job_total` | Counter |
| `ixora.queue.job.duration` | `ixora_queue_job_duration_bucket/sum/count` | Histogram |
| `ixora.queue.job.active` | `ixora_queue_job_active` | Gauge |
| `ixora.scheduler.event.total` | `ixora_scheduler_event_total` | Counter |
| `ixora.scheduler.event.duration` | `ixora_scheduler_event_duration_bucket` | Histogram |
| `ixora.smart_home.action.total` | `ixora_smart_home_action_total` | Counter |
| `ixora.smart_home.action.duration` | `ixora_smart_home_action_duration_bucket` | Histogram |
| `ixora.smart_home.dispatch.total` | `ixora_smart_home_dispatch_total` | Counter |
| `ixora.telemetry.export.failed.total` | `ixora_telemetry_export_failed_total` | Counter |
| `ixora.push.delivery.total` | `ixora_push_delivery_total` | Counter (Phase 7B.5) |

---

## 3. Provisioning Hierarchy

### 3.1 Directory structure

```
collector/prometheus/
├── prometheus.yml                          ← rule_files active (Phase 8.9)
└── rules/
    ├── recording/
    │   ├── application.rules.yml           ← HTTP, Queue, Scheduler (Phase 8.9 — active)
    │   ├── business.rules.yml              ← Smart Home, Push (Phase 8.9 — active)
    │   ├── infrastructure.rules.yml        ← Collector, Prometheus (Phase 8.9 — active)
    │   └── slo.rules.yml                   ← SLI aggregates, error budget (Phase 8.9 — active)
    └── alerting/
        └── slo.alerts.yml                  ← 12 multi-window burn-rate alerts (Phase 8.9 — active)
```

### 3.2 Activation checklist (completed in Phase 8.9)

This checklist was executed as part of the Phase 8.9 implementation (branch `feature/observability-slo-error-budget`) — kept here as a record, not as pending work.

| Step | Action | Status |
| --- | --- | --- |
| 1 | Uncomment `rule_files` block in `prometheus.yml` | Done |
| 2 | Add volume mount in `docker-compose.yml`: `./prometheus/rules:/etc/prometheus/rules:ro` | Done |
| 3 | Activate recording rules in `.rules.yml` files | Done |
| 4 | Restart or reload Prometheus: `POST /-/reload` | Done |
| 5 | Verify: `curl http://localhost:9090/api/v1/rules?type=record` | Done — confirmed live on staging, all groups `health: ok` |
| 6 | Compare recording rule output vs raw PromQL for 24 h | Done |
| 7 | Migrate dashboard panels to consume recording rules | **Deferred** — D-01–D-07 still use raw PromQL, see §10 |
| 8 | Update alert rules to consume recording rules | Done for SLO burn-rate alerts (`slo.alerts.yml`); general alerting-foundation.md alerts still deferred, see §11 |

### 3.3 Rule file organization

| File | Group prefix | Scope | Owner |
| --- | --- | --- | --- |
| `application.rules.yml` | `ixora_application_*` | HTTP, Queue, Scheduler | Backend |
| `business.rules.yml` | `ixora_business_*` | Smart Home, Push | Product / Backend |
| `infrastructure.rules.yml` | `ixora_infrastructure_*` | Collector, Prometheus | SRE |
| `slo.rules.yml` | `ixora_slo_*` | SLI aggregates, error budget, burn rate | SRE |

---

## 4. Recording Rule Catalog

### 4.1 Active catalog (Phase 8.9 — deployed and active in staging)

| ID | Recording rule name | Category | Source expression summary | Consumers | Phase |
| --- | --- | --- | --- | --- | --- |
| REC-001 | `ixora:http:error_rate:5m` | Application / HTTP | server_error rate / total rate | D-01, D-05, alert | 9 |
| REC-002 | `ixora:http:availability:5m` | Application / HTTP | 1 − error_rate | D-01, SLO | 9 |
| REC-003 | `ixora:collector:availability` | Infrastructure | avg(up{job="otel-collector"}) | D-07, D-01, alert | 9 |
| REC-004 | `ixora:http:p95_latency:5m` | Application / HTTP | histogram_quantile(0.95, ...) | D-01, D-05, alert | 9 |
| REC-005 | `ixora:smart_home:success_rate:5m` | Business / Smart Home | success rate / total | D-01, D-02, alert | 9 |
| REC-006 | `ixora:queue:success_rate:5m` | Application / Queue | success / total (excl retried) | D-01, D-04, alert | 9 |
| REC-007 | `ixora:queue:p95_latency:5m` | Application / Queue | histogram_quantile(0.95, ...) | D-04, D-03 | 9 |
| REC-008 | `ixora:queue:failure_rate:5m` | Application / Queue | failed / total | D-04, alert | 9 |
| REC-009 | `ixora:http:request_rate:5m` | Application / HTTP | rate(request_total) | D-01, D-05 | 9 |
| REC-010 | `ixora:scheduler:dispatch_rate:5m` | Application / Scheduler | rate(event_total) | D-01, D-06 | 9 |
| REC-011 | `ixora:scheduler:success_rate:5m` | Application / Scheduler | success / total (excl skipped) | D-06, alert | 9 |
| REC-012 | `ixora:scheduler:p95_latency:5m` | Application / Scheduler | histogram_quantile(0.95, ...) | D-06 | 9 |
| REC-013 | `ixora:smart_home:failure_rate:5m` | Business / Smart Home | failure+unknown / total | D-01, D-02, alert | 9 |
| REC-014 | `ixora:smart_home:p95_latency:5m` | Business / Smart Home | histogram_quantile(0.95, ...) | D-01, D-02 | 9 |
| REC-015 | `ixora:push:success_rate:5m` | Business / Push | push queue success rate | D-03, alert | 9 |
| REC-016 | `ixora:push:failure_rate:5m` | Business / Push | push queue failure rate | D-03, alert | 9 |
| REC-017 | `ixora:collector:export_failure_rate:5m` | Infrastructure | otelcol export failures | D-07, alert | 9 |
| REC-018 | `ixora:telemetry:export_failure_rate:1h` | Infrastructure | ixora_telemetry_export_failed | D-07, D-01 | 9 |
| REC-019 | `ixora:prometheus:availability` | Infrastructure | up{job="prometheus"} | D-07 | 9 |
| REC-020 | `ixora:push:queue_backlog` | Business / Push | ixora_queue_job_active{queue="push"} | D-03, alert | 9 |

### 4.2 Reserved catalog (Phase 10+)

| ID | Recording rule name | Category | Phase | Notes |
| --- | --- | --- | --- | --- |
| REC-021 | `ixora:push:delivery_success_rate:5m` | Business / Push | 10 | Requires Phase 7B.5 metric |
| REC-022 | `ixora:slo:http:success_rate:30d` | SLO | 10 | 30-day SLI aggregate |
| REC-023 | `ixora:slo:queue:success_rate:30d` | SLO | 10 | 30-day SLI aggregate |
| REC-024 | `ixora:slo:smart_home:success_rate:30d` | SLO | 10 | 30-day SLI aggregate |
| REC-025 | `ixora:slo:http:error_budget_remaining:30d` | SLO | 10 | Error budget computation |
| REC-026 | `ixora:slo:http:burn_rate:5m` | SLO | 11 | Multi-window burn rate |
| REC-027 | `ixora:slo:http:burn_rate:1h` | SLO | 11 | Multi-window burn rate |

---

## 5. Recording Rule Categories

### 5.1 Infrastructure

| Property | Value |
| --- | --- |
| **Purpose** | Pre-compute observability platform health metrics |
| **Typical expressions** | `up{job=...}`, otelcol export rates, telemetry export failures |
| **Expected consumers** | D-07 Infrastructure, D-01 Platform Overview, infrastructure alerts |
| **Dashboard usage** | Availability gauges, export failure time series |
| **Alert usage** | Collector down, export failure rate, Prometheus unavailable |
| **SLO usage** | Collector availability SLO (99.9% target example) |

### 5.2 Application / HTTP

| Property | Value |
| --- | --- |
| **Purpose** | Pre-compute HTTP API error rate, availability, latency |
| **Typical expressions** | `rate(ixora_http_server_request_total{outcome="server_error"}[5m]) / rate(...)` |
| **Expected consumers** | D-05 HTTP API, D-01 Platform Overview, HTTP alerts |
| **Dashboard usage** | Error rate stat panels, latency percentiles |
| **Alert usage** | Elevated error rate, high latency |
| **SLO usage** | HTTP availability SLO (99.5% example), latency SLO (95% under 2 s) |

### 5.3 Application / Queue

| Property | Value |
| --- | --- |
| **Purpose** | Pre-compute queue job success/failure rates and latency |
| **Typical expressions** | `rate(ixora_queue_job_total{outcome="success"}[5m]) / rate(...)` |
| **Expected consumers** | D-04 Queue Workers, D-03 Push (push queue), D-01, queue alerts |
| **Dashboard usage** | Success rate gauges, p95 latency charts |
| **Alert usage** | Queue failure rate, worker saturation |
| **SLO usage** | Queue reliability SLO (99% example) |

### 5.4 Application / Scheduler

| Property | Value |
| --- | --- |
| **Purpose** | Pre-compute scheduler dispatch and success rates |
| **Typical expressions** | `rate(ixora_scheduler_event_total{outcome="success"}[5m]) / rate(...)` |
| **Expected consumers** | D-06 Scheduler, D-01, scheduler alerts |
| **Dashboard usage** | Dispatch rate, success rate, event duration |
| **Alert usage** | Missed executions, dispatch failures |
| **SLO usage** | Scheduler dispatch SLO (99.5% example) |

### 5.5 Business / Smart Home

| Property | Value |
| --- | --- |
| **Purpose** | Pre-compute Smart Home action success/failure rates |
| **Typical expressions** | `rate(ixora_smart_home_action_total{outcome="success"}[5m]) / rate(...)` |
| **Expected consumers** | D-02 Smart Home, D-01, business alerts |
| **Dashboard usage** | Success/failure rate gauges, provider latency |
| **Alert usage** | Elevated failure rate, provider failure |
| **SLO usage** | Smart Home automation SLO (99% example) |

### 5.6 Business / Push Notifications

| Property | Value |
| --- | --- |
| **Purpose** | Pre-compute push queue health metrics |
| **Typical expressions** | Queue-layer: `rate(ixora_queue_job_total{queue="push"}[5m])`; Future: `rate(ixora_push_delivery_total[5m])` |
| **Expected consumers** | D-03 Push Notifications, push alerts |
| **Dashboard usage** | Delivery success rate, queue backlog, latency |
| **Alert usage** | Push delivery failure, queue saturation |
| **SLO usage** | Push delivery SLO (99% example) |

### 5.7 SLO (Phase 10+)

| Property | Value |
| --- | --- |
| **Purpose** | Pre-compute SLI aggregates and error budget for SLO tracking |
| **Typical expressions** | `avg_over_time(ixora:http:availability:5m[30d])` |
| **Expected consumers** | SLO dashboard (future), burn rate alerts (Phase 11) |
| **Dashboard usage** | Error budget remaining, SLI trend |
| **Alert usage** | Burn rate alerts (Phase 11+) |
| **SLO usage** | Direct SLO compliance measurement |

---

## 6. SLI Definitions

### 6.1 SLI-001 — HTTP Success Rate

| Field | Value |
| --- | --- |
| **ID** | SLI-001 |
| **Purpose** | Measure proportion of HTTP requests that do not result in server errors |
| **Formula** | `1 − (server_error_requests / total_requests)` |
| **Source metrics** | `ixora_http_server_request_total{outcome="server_error"}`, `ixora_http_server_request_total` |
| **Recording rule** | `ixora:http:availability:5m` (REC-002) |
| **Good events** | Requests where `outcome != "server_error"` |
| **Valid events** | All HTTP requests |
| **Consumers** | D-01, D-05, HTTP availability SLO, HTTP error rate alert |
| **Example SLO target** | 99.5% over 30 days |

### 6.2 SLI-002 — HTTP Latency

| Field | Value |
| --- | --- |
| **ID** | SLI-002 |
| **Purpose** | Measure HTTP request response time distribution |
| **Formula** | `histogram_quantile(0.95, rate(ixora_http_server_duration_bucket[5m]))` |
| **Source metrics** | `ixora_http_server_duration_bucket` |
| **Recording rule** | `ixora:http:p95_latency:5m` (REC-004) |
| **Good events** | Requests completing under 2000 ms |
| **Valid events** | All HTTP requests with recorded duration |
| **Consumers** | D-01, D-05, HTTP latency alert |
| **Example SLO target** | 95% of requests under 2000 ms over 30 days |

### 6.3 SLI-003 — Queue Success Rate

| Field | Value |
| --- | --- |
| **ID** | SLI-003 |
| **Purpose** | Measure proportion of queue jobs that complete successfully |
| **Formula** | `success_jobs / total_jobs` (excluding retried/released) |
| **Source metrics** | `ixora_queue_job_total{outcome="success"}`, `ixora_queue_job_total` |
| **Recording rule** | `ixora:queue:success_rate:5m` (REC-006) |
| **Good events** | Jobs with `outcome="success"` |
| **Valid events** | All jobs excluding `retried` and `released` |
| **Consumers** | D-01, D-04, queue failure alert |
| **Example SLO target** | 99% over 30 days |

### 6.4 SLI-004 — Queue Failure Rate

| Field | Value |
| --- | --- |
| **ID** | SLI-004 |
| **Purpose** | Measure proportion of queue jobs that fail |
| **Formula** | `failed_jobs / total_jobs` |
| **Source metrics** | `ixora_queue_job_total{outcome="failed"}`, `ixora_queue_job_total` |
| **Recording rule** | `ixora:queue:failure_rate:5m` (REC-008) |
| **Good events** | N/A (inverse of success) |
| **Valid events** | All jobs excluding `retried` and `released` |
| **Consumers** | D-04, queue failure alert |
| **Example SLO target** | < 1% failure rate (inverse of SLI-003) |

### 6.5 SLI-005 — Scheduler Dispatch Success

| Field | Value |
| --- | --- |
| **ID** | SLI-005 |
| **Purpose** | Measure proportion of scheduler events that succeed |
| **Formula** | `success_events / total_events` (excluding overlap_prevented/skipped) |
| **Source metrics** | `ixora_scheduler_event_total{outcome="success"}`, `ixora_scheduler_event_total` |
| **Recording rule** | `ixora:scheduler:success_rate:5m` (REC-011) |
| **Good events** | Events with `outcome="success"` |
| **Valid events** | Events excluding `overlap_prevented` and `skipped` |
| **Consumers** | D-06, D-01, scheduler alert |
| **Example SLO target** | 99.5% over 30 days |

### 6.6 SLI-006 — Smart Home Success Rate

| Field | Value |
| --- | --- |
| **ID** | SLI-006 |
| **Purpose** | Measure proportion of Smart Home actions that succeed |
| **Formula** | `success_actions / total_actions` |
| **Source metrics** | `ixora_smart_home_action_total{outcome="success"}`, `ixora_smart_home_action_total` |
| **Recording rule** | `ixora:smart_home:success_rate:5m` (REC-005) |
| **Good events** | Actions with `outcome="success"` |
| **Valid events** | All Smart Home actions |
| **Consumers** | D-01, D-02, Smart Home failure alert |
| **Example SLO target** | 99% over 30 days |

### 6.7 SLI-007 — Collector Availability

| Field | Value |
| --- | --- |
| **ID** | SLI-007 |
| **Purpose** | Measure observability pipeline uptime |
| **Formula** | `avg(up{job="otel-collector"})` |
| **Source metrics** | Prometheus `up` metric for otel-collector job |
| **Recording rule** | `ixora:collector:availability` (REC-003) |
| **Good events** | Time periods where Collector is reachable |
| **Valid events** | All observation time |
| **Consumers** | D-07, D-01, Collector down alert |
| **Example SLO target** | 99.9% over 30 days |

### 6.8 SLI-008 — Push Queue Health

| Field | Value |
| --- | --- |
| **ID** | SLI-008 |
| **Purpose** | Measure push notification queue processing reliability |
| **Formula** | `push_success_jobs / push_total_jobs` |
| **Source metrics** | `ixora_queue_job_total{queue="push",outcome="success"}`, `ixora_queue_job_total{queue="push"}` |
| **Recording rule** | `ixora:push:success_rate:5m` (REC-015) |
| **Good events** | Push jobs with `outcome="success"` |
| **Valid events** | All push queue jobs |
| **Consumers** | D-03, push delivery alert |
| **Example SLO target** | 99% over 30 days |
| **Note** | Queue-layer SLI until Phase 7B.5 enables per-delivery SLI |

---

## 7. SLO Definitions (Examples — Not Enforced)

SLO targets are **architectural examples**. Actual targets require 90+ days of SLI data and team agreement before enforcement.

### 7.1 Target examples

| SLO ID | Service | SLI | Target | Period | Error budget |
| --- | --- | --- | --- | --- | --- |
| SLO-001 | HTTP API | SLI-001 (availability) | 99.5% | 30 days | 0.5% (~3.6 h) |
| SLO-002 | HTTP API | SLI-002 (latency) | 95% under 2 s | 30 days | 5% |
| SLO-003 | Queue Workers | SLI-003 (success) | 99% | 30 days | 1% (~7.2 h) |
| SLO-004 | Scheduler | SLI-005 (dispatch) | 99.5% | 30 days | 0.5% (~3.6 h) |
| SLO-005 | Smart Home | SLI-006 (success) | 99% | 30 days | 1% (~7.2 h) |
| SLO-006 | Push Notifications | SLI-008 (queue health) | 99% | 30 days | 1% (~7.2 h) |
| SLO-007 | Collector | SLI-007 (availability) | 99.9% | 30 days | 0.1% (~43 min) |

### 7.2 Target tier reference

| Target | Classification | Suitable for |
| --- | --- | --- |
| 99% | Standard | Queue, Smart Home, Push (external dependencies) |
| 99.5% | Elevated | HTTP API, Scheduler (core product functions) |
| 99.9% | Strict | Collector, critical infrastructure |
| 99.95% | Very strict | Reserved for future customer SLA |

### 7.3 Business tradeoffs

| Higher target | Tradeoff |
| --- | --- |
| 99.9% vs 99% | 10× less error budget; more engineering time on reliability |
| Strict latency SLO | May require infrastructure scaling earlier |
| Smart Home at 99% | Acknowledges Home Assistant as external dependency |
| Push at 99% | Aligns with ADR-020 best-effort delivery policy |

---

## 8. Error Budget Philosophy

Full error budget policy is in [slo-philosophy.md §12](../../../architecture/slo-philosophy.md). Summary:

### 8.1 Budget periods

| Period | Purpose | Automated tracking |
| --- | --- | --- |
| **Monthly (30-day rolling)** | Primary SLO evaluation | Phase 10 (REC-022–025) |
| **Weekly (7-day rolling)** | Early warning for budget consumption | Phase 10 |
| **Quarterly (90-day)** | Strategic review; SLO target adjustment | Manual review |

### 8.2 Budget consumption model

```
remaining_budget = 1 - ((1 - current_sli) / (1 - slo_target))

Example: SLO = 99.5%, current SLI = 99.0%
  consumed = (1 - 0.990) / (1 - 0.995) = 0.010 / 0.005 = 2.0 (200% consumed)
  remaining = 1 - 2.0 = -1.0 (budget exhausted)
```

### 8.3 Budget influences

| Budget state | Release policy | Alerting (Phase 10+) |
| --- | --- | --- |
| > 50% remaining | Normal velocity | Standard threshold alerts |
| 25–50% | Caution; reliability fixes prioritized | Lower burn rate thresholds |
| 10–25% | Feature freeze | Escalated alerts |
| < 10% | Full release pause | All reliability alerts → Critical |
| Exhausted | Postmortem required | Automatic team notification |

---

## 9. Naming Convention Reference

Full specification in [recording-rules-philosophy.md §10](../../../architecture/recording-rules-philosophy.md).

```
ixora:<domain>:<metric>:<aggregation_window>
```

| Pattern | Example |
| --- | --- |
| Error rate (5m window) | `ixora:http:error_rate:5m` |
| Success rate (5m window) | `ixora:queue:success_rate:5m` |
| P95 latency (5m window) | `ixora:http:p95_latency:5m` |
| Dispatch rate (5m window) | `ixora:scheduler:dispatch_rate:5m` |
| Availability (instant) | `ixora:collector:availability` |
| Queue backlog (instant) | `ixora:push:queue_backlog` |
| SLI aggregate (30d window) | `ixora:slo:http:success_rate:30d` |
| Error budget (30d window) | `ixora:slo:http:error_budget_remaining:30d` |
| Burn rate (5m window) | `ixora:slo:http:burn_rate:5m` |

---

## 10. Dashboard Integration Strategy

### 10.1 Migration phases

| Phase | Action | Scope |
| --- | --- | --- |
| **8.9 (current)** | Document migration targets; no dashboard changes | All dashboards |
| **9a** | Activate recording rules; validate output | Prometheus only |
| **9b** | Migrate D-01 Platform Overview (highest reuse) | 5+ panels |
| **9c** | Migrate D-05, D-04, D-02, D-06, D-03 | Domain dashboards |
| **10** | Migrate D-07; add SLO/budget panels | Infrastructure + SLO |

### 10.2 Migration pattern

**Before (current):**
```promql
sum(rate(ixora_http_server_request_total{environment=~"$environment",outcome="server_error"}[5m]))
/ sum(rate(ixora_http_server_request_total{environment=~"$environment"}[5m]))
```

**After (Phase 9):**
```promql
ixora:http:error_rate:5m{environment=~"$environment"}
```

### 10.3 Migration rules

- Migrate aggregate panels first (no `by (...)` breakdown).
- Keep breakdown panels (`by (provider)`, `by (queue)`, `by (http_route)`) on raw metrics until dedicated breakdown recording rules are justified.
- Update panel descriptions to reference recording rule name and REC-NNN ID.
- Validate migrated panel output matches raw PromQL for 24 h before merging.

### 10.4 Dashboard → recording rule mapping

| Dashboard | Panels to migrate | Recording rules |
| --- | --- | --- |
| D-01 Platform Overview | 8+ panels | REC-001, 002, 005, 006, 013, 004, 014 |
| D-05 HTTP API | 3 panels | REC-001, 004 |
| D-04 Queue Workers | 2 panels | REC-006, 007 |
| D-02 Smart Home | 3 panels | REC-005, 013, 014 |
| D-06 Scheduler | 2 panels | REC-011, 012 |
| D-03 Push Notifications | 2 panels | REC-015, 016 |
| D-07 Infrastructure | 1 panel | REC-003 |

---

## 11. Alert Integration

Alert rules (Phase 9) should consume recording rules instead of raw PromQL ([alerting-foundation.md §13](alerting-foundation.md) alert inventory).

### 11.1 Alert → recording rule mapping

| Alert rule (Phase 9) | Current PromQL | Future recording rule |
| --- | --- | --- |
| HTTP Elevated Error Rate | Nested ratio on `ixora_http_server_request_total` | `ixora:http:error_rate:5m > 0.01` |
| HTTP High Latency | `histogram_quantile(0.95, ...)` | `ixora:http:p95_latency:5m > 2` |
| Queue Failure Rate | Nested ratio on `ixora_queue_job_total` | `ixora:queue:failure_rate:5m > 0.05` |
| Smart Home Failure | Nested ratio on `ixora_smart_home_action_total` | `ixora:smart_home:failure_rate:5m > 0.20` |
| Collector Down | `ixora_telemetry_export_failed_total` | `ixora:collector:availability < 1` |
| Push Delivery Failure | Queue-layer ratio | `ixora:push:failure_rate:5m > 0.10` |

### 11.2 Integration principles

1. **Recording rules are the single source of truth** for shared metric computations.
2. **Alert rules compare pre-computed values to thresholds** — no nested PromQL.
3. **Dashboard and alert show identical values** — no formula drift.
4. **SLO burn rate alerts (Phase 8.9, active) consume SLO recording rules** — not raw metrics. This is already implemented in `alerting/slo.alerts.yml` (12 alerts). Only the *general* alerting-foundation.md operational alerts (HTTP Elevated Error Rate, Queue Failure Rate, etc. — §11.1 above) remain on raw PromQL, pending Phase 9.

---

## 12. Validation Framework

`validate.sh` checks 68–78 verify the structural integrity of the Recording Rules & SLO Foundation.

| Check | Description |
| --- | --- |
| 68 | `prometheus/rules/recording/` directory exists |
| 69 | `application.rules.yml` exists and is valid YAML |
| 70 | `business.rules.yml` exists and is valid YAML |
| 71 | `infrastructure.rules.yml` exists and is valid YAML |
| 72 | `slo.rules.yml` exists and is valid YAML |
| 73 | `recording-rules-philosophy.md` exists |
| 74 | `slo-philosophy.md` exists |
| 75 | `recording-rules-foundation.md` exists |
| 76 | Catalog documented (REC-001 in foundation spec) |
| 77 | SLI definitions documented (SLI-001 in foundation spec) |
| 78 | Naming convention documented (`ixora:http:error_rate:5m`) |
| 91 | D-08 JSON syntax valid |
| 92 | D-08 uid `ixora-slo` |
| 93 | `slo.alerts.yml` valid YAML |
| 94 | `promtool check rules` passes |
| 95 | `rule_files` active in `prometheus.yml` |
| 96 | SLO runbook exists |
| 97 | `test-slo-math.py` passes |
| 98 | docker-compose mounts `prometheus/rules` |

---

## 13. Staging Rollout Checklist

Before enabling on the observability host (requires explicit approval):

- [ ] All validate.sh checks pass (98/98 where Grafana running)
- [ ] `docker compose up -d prometheus` with rules mount
- [ ] `curl localhost:9090/-/rules | grep ixora:sli`
- [ ] D-08 panels render with `$environment` filter
- [ ] Alerts inactive under normal traffic
- [ ] 24 h staging validation per [slo-error-budget runbook](../../../runbooks/slo-error-budget.md)

**Rollback:** Remove rules volume mount and comment `rule_files`; `POST /-/reload` or recreate Prometheus container.

---

## 14. Known Limitations

| ID | Limitation | Impact | Resolution |
| --- | --- | --- | --- |
| KL-RR-1 | 30-day SLO window needs 30d retention + traffic | Early windows approximate | Wait 30d; use 5m SLI for ops |
| KL-RR-2 | Staging low traffic | 30d SLO low confidence; alerts guarded | Document in D-08; tune guards |
| KL-RR-3 | Phase 7B.5 push delivery metric pending | No dedicated push SLO | Phase 7B.5 + REC-021 |
| KL-RR-4 | Dashboards D-01–D-07 still query raw PromQL | Duplicate evaluation | Future migration to REC-* |
| KL-RR-5 | No Node Exporter | VM disk/CPU SLIs not possible | Future infrastructure phase |
| KL-RR-6 | Telemetry SLO is cluster-wide | No per-environment pipeline SLO | By design (Collector singleton) |

---

## 15. Related Documents

| Document | Relationship |
| --- | --- |
| [recording-rules-philosophy.md](../../../architecture/recording-rules-philosophy.md) | Philosophy — read before implementing any recording rule |
| [slo-philosophy.md](../../../architecture/slo-philosophy.md) | SLO architecture — SLI/SLO/SLA, error budget, burn rate |
| [alerting-foundation.md](alerting-foundation.md) | Alert rules consume recording rules (Phase 9) |
| [alerting-philosophy.md](../../../architecture/alerting-philosophy.md) | Alerts prefer pre-computed recording rules |
| [metrics-philosophy.md](../../../architecture/metrics-philosophy.md) | Source metrics for recording rules |
| [telemetry-naming-convention.md](../../../architecture/telemetry-naming-convention.md) | Raw metric names (`ixora.*`) |
| [dashboard-conventions.md](dashboard-conventions.md) | Dashboard panels migrate to recording rule queries |
| [prometheus-deployment.md](prometheus-deployment.md) | Prometheus configuration and rule_files activation |
| [ADR-031](../../../decisions/ADR-031-retention-storage-and-cost-control.md) | 30-day retention governs SLO lookback window |
