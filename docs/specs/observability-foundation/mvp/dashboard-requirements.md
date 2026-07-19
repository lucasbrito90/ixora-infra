# Dashboard Requirements — Phase 8.0

**Status:** Complete  
**Type:** Documentation-only — no Grafana JSON, no PromQL, no dashboard implementation  
**Repo:** `ixora-infra` (architecture spec only)  
**Feature ID:** `observability-foundation/mvp`  
**Prerequisite:** [business-telemetry-foundation.md](../business-telemetry/business-telemetry-foundation.md) (Phase 7B.4.9) · [backend-business-telemetry-validation.md](../business-telemetry/backend-business-telemetry-validation.md) (Phase 7B.4.8) · [metrics-philosophy.md](../../../architecture/metrics-philosophy.md) · [telemetry-naming-convention.md](../../../architecture/telemetry-naming-convention.md) · [telemetry-decision-guide.md](../../../architecture/telemetry-decision-guide.md)

> **Rule of thumb:** Dashboards are built from signals, not from wishes. Every panel in this document maps to at least one metric, span, or log that already exists or has a documented future phase. No panel is speculative.

---

## 1. Dashboard inventory

| # | Dashboard | Audience | Primary signal | Status |
| --- | --- | --- | --- | --- |
| D-01 | **Platform Overview** | On-call, SRE | HTTP + Queue + Scheduler metrics | Phase 9 (all infra signals available) |
| D-02 | **Smart Home** | Product + On-call | Smart Home business metrics + spans | Phase 9 (signals complete — Phase 7B.4.8) |
| D-03 | **Push Notifications** | Product + On-call | Push metrics + spans | Phase 9 (after Phase 7B.5) |
| D-04 | **Queue Workers** | On-call, SRE | Queue metrics + spans | Phase 9 (infra signals available) |
| D-05 | **HTTP API** | On-call, SRE | HTTP metrics + spans | Phase 9 (infra signals available) |
| D-06 | **Scheduler** | On-call, product | Scheduler metrics + spans | Phase 9 (infra signals available) |
| D-07 | **Collector & Infrastructure** | SRE | Collector self-metrics + system | Phase 9 (available now) |

Implementation order for Phase 9: D-07 → D-04 → D-05 → D-06 → D-02 → D-01 → D-03 (D-03 after Phase 7B.5).

---

## 2. Signals available today

Before defining every dashboard, this table maps what signals are available right now (after Phases 7A–7B.4.9) and what is pending.

### Metrics

| Metric | Type | Labels | Source | Available |
| --- | --- | --- | --- | --- |
| `ixora.http.server.duration` | Histogram | `environment`, `http.method`, `http.route`, `http.status_code` | Phase 7B.1 | ✅ |
| `ixora.queue.job.total` | Counter | `environment`, `queue`, `job`, `outcome` | Phase 7B.2 | ✅ |
| `ixora.queue.job.duration` | Histogram | `environment`, `queue`, `job`, `outcome` | Phase 7B.2 | ✅ |
| `ixora.console.command.total` | Counter | `environment`, `command`, `outcome` | Phase 7B.2 | ✅ |
| `ixora.console.command.duration` | Histogram | `environment`, `command`, `outcome` | Phase 7B.2 | ✅ |
| `ixora.scheduler.execution.total` | Counter | `environment`, `outcome` | Phase 7B.3 | ✅ |
| `ixora.scheduler.dispatch.duration` | Histogram | `environment`, `outcome` | Phase 7B.3 | ✅ |
| `ixora.smart_home.dispatch.total` | Counter | `environment`, `entry_point`, `outcome` | Phase 7B.4.6 | ✅ |
| `ixora.smart_home.action.total` | Counter | `environment`, `outcome`, `provider` | Phase 7B.4.6 | ✅ |
| `ixora.smart_home.action.duration` | Histogram | `environment`, `outcome`, `provider` | Phase 7B.4.6 | ✅ |
| `ixora.push.delivery.total` | Counter | `environment`, `notification_type`, `outcome` | Phase 7B.5 | ⏳ pending |
| `ixora.telemetry.export.failed.total` | Counter | `environment` | Phase 7A | ✅ |

### Key spans

| Span | Attributes | Source | Available |
| --- | --- | --- | --- |
| HTTP server span | `http.route`, `http.method`, `http.status_code` | auto-laravel Phase 7B.1 | ✅ |
| Queue Consumer span | `messaging.destination`, `ixora.queue.attempt` | auto-laravel Phase 7B.2 | ✅ |
| `smart_home.dispatch` | `ixora.dispatch.entry_point`, `.dispatched_actions`, `.skipped_actions` | Phase 7B.4.2 | ✅ |
| `smart_home.action` | `ixora.action.provider`, `.outcome`, `.retry` | Phase 7B.4.3 | ✅ |
| `smart_home.provider` | `ixora.provider.device_domain` | Phase 7B.4.4 | ✅ |
| `POST` (Guzzle CLIENT) | `url.full`, `http.request.method`, `http.response.status_code` | auto-guzzle Phase 7A | ✅ |
| Push delivery span | `ixora.push.outcome`, `notification_type` | Phase 7B.5 | ⏳ pending |

### Log sources

| Log source | Correlation | Available |
| --- | --- | --- |
| `SmartHomeActionJob` domain logs (J1–J3, A2/A3/A4/A5) | `trace_id`, `span_id` via `TraceCorrelationLogTap` | ✅ |
| HTTP error context (`HttpErrorContextLogTap`) | `route`, `method`, `status_code` | ✅ |
| Queue error context (`QueueErrorContextLogTap`) | `job`, `queue`, `attempt` | ✅ |
| Console error context (`ConsoleErrorContextLogTap`) | `command` | ✅ |
| Scheduler error context (`SchedulerErrorContextLogTap`) | `schedule` | ✅ |
| Laravel default logs (all channels) | `trace_id`, `span_id` via `TraceCorrelationLogTap` | ✅ |

---

## 3. D-01 — Platform Overview

### Purpose

Single-pane health view for the entire `back_vibes` platform. Answers "Is the system healthy right now?" in under 30 seconds without drilling into any domain.

### Audience

On-call engineer, SRE, Engineering Lead.

### Operational questions answered

| Question | Panel type |
| --- | --- |
| Is the API responding? | HTTP request rate + error rate |
| Are queue workers running? | Job throughput + failure rate |
| Is the scheduler firing? | Scheduler execution rate |
| Are Smart Home actions working? | Smart Home action success rate |
| Is there anything alarming? | Multi-row failure rate heatmap |

### Panels

| Panel | Signal | Metric / span | Notes |
| --- | --- | --- | --- |
| API Request Rate | Time series | `ixora.http.server.duration` (count rate) | All routes, by environment |
| API Error Rate (5xx) | Stat + time series | `ixora.http.server.duration{http.status_code=~"5.."}` rate | Alert threshold: > 1% |
| API p95 Latency | Stat + time series | `ixora.http.server.duration` histogram_quantile(0.95) | Alert threshold: > 2 s |
| Queue Job Throughput | Time series | `ixora.queue.job.total` rate by `queue` | All queues |
| Queue Failure Rate | Stat | `ixora.queue.job.total{outcome=failed}` / total | Per queue |
| Scheduler Dispatch Rate | Stat | `ixora.scheduler.execution.total{outcome=dispatched}` rate | — |
| Smart Home Action Success Rate | Stat | `ixora.smart_home.action.total{outcome=success}` / total | — |
| Telemetry Export Failures | Stat | `ixora.telemetry.export.failed.total` | Non-zero = Collector issue |

### Drill-down workflow

```
Anomaly on Platform Overview
      ↓
Navigate to domain-specific dashboard (D-02 Smart Home, D-04 Queue, D-05 HTTP, D-06 Scheduler)
      ↓
Identify time range + failing component
      ↓
Use domain dashboard's Trace link → Tempo
      ↓
Copy trace_id → Loki log query
```

### Refresh interval

30 seconds (operational monitoring use-case).

### Future expansion

- Push Notifications row (D-03 signals, after Phase 7B.5).
- Mobile app health row (after Phase 8 Frontend SDK).
- SLO summary panels (post-MVP alerting).

---

## 4. D-02 — Smart Home

### Purpose

Deep-dive into the Smart Home execution pipeline — from Vibe dispatch to Home Assistant HTTP call. Answers every operational question about whether Smart Home automations are working and, when they are not, narrows the failure to a boundary, provider, and device type category.

### Audience

On-call engineer, product team monitoring automation reliability.

### Operational questions answered

| Question | Panel type |
| --- | --- |
| Are Smart Home actions succeeding? | Success rate over time |
| Which entry point (manual vs scheduled) dispatches most? | Stacked bar by `entry_point` |
| How many actions were skipped at dispatch? | Skip rate counter |
| What is the action execution latency? | p50/p95 histogram |
| Which outcome is failing? | Breakdown by `outcome` |
| Which provider is degraded? | Failure rate by `provider` |
| Which device type category fails most? | Span attribute pivot (Tempo) |
| Are unsupported action types accumulating? | Unsupported rate counter |

### Panels

| Panel | Signal | Metric / span | Notes |
| --- | --- | --- | --- |
| Action Success Rate | Stat + sparkline | `action.total{outcome=success}` / `action.total` | Target ≥ 95% |
| Action Failure Rate | Stat + time series | `action.total{outcome=failure}` / total | — |
| Unsupported Action Rate | Stat | `action.total{outcome=unsupported}` / total | Should be near 0 |
| Action Volume | Time series | `action.total` rate (all outcomes) | Shows traffic trend |
| Dispatch Volume | Time series | `dispatch.total{outcome=dispatched}` rate | By `entry_point` (manual vs scheduled) |
| Dispatch Skip Rate | Stat | `dispatch.total{outcome=skipped}` / dispatched total | High = stale device/action references |
| Action p50 / p95 / p99 Latency | Stat + histogram | `action.duration` histogram | Segmented by `outcome` and `provider` |
| Failure Breakdown by Provider | Bar | `action.total{outcome=failure}` by `provider` | Today: `home_assistant` only |
| Outcome Breakdown | Pie / bar | `action.total` by `outcome` | success / failure / unsupported |
| Recent Failing Traces | Table (Tempo datasource) | Tempo query: `smart_home.action` span, `ixora.action.outcome=failure` | Links to trace detail |

### Panels pending future data

| Panel | Blocked by | Phase |
| --- | --- | --- |
| Failure breakdown by action type | `action_type` label missing on `action.total` | TD-2, Phase 7B.5 |
| Guard-clause skip count (J1–J3) | No metric for guard skips | TD-3, Phase 7B.5/7B.6 |
| Device domain failure breakdown | No metric; Tempo span attribute only | Tempo pivot (no metric needed) |

### Investigation workflow — "Smart Home actions not executing"

```
1. D-02 Action Success Rate drops
      ↓
2. Outcome Breakdown: failure vs unsupported vs unknown?
      ↓
3a. outcome=failure → check Failure Breakdown by Provider
      → is_home_assistant the only provider? yes → Home Assistant issue
      → Tempo: smart_home.provider span, check nested Guzzle POST status_code
      → Loki: trace_id → A2 log with status_code + provider_connection_id
      ↓
3b. outcome=unsupported → Loki A3 logs → action_type field reveals which config is broken
      ↓
3c. Any path → Tempo trace: smart_home.dispatch → queue consumer → smart_home.action → smart_home.provider → POST
      → Check which span has ERROR status
      → Copy trace_id → Loki → logs with exception_class, outcome, device_id
```

### Refresh interval

1 minute (automation monitoring; not a real-time wall board).

### Future expansion

- `action_type` breakdown once TD-2 label is added (Phase 7B.5).
- Guard-clause skip panel once TD-3 metric is added (Phase 7B.5/7B.6).
- Additional provider rows when Matter / Google Home / Alexa adapters ship.
- Vibe-level fan-in panel if a fan-in mechanism is implemented (currently deferred per domain-execution-review §14 U-5).

---

## 5. D-03 — Push Notifications

### Purpose

Monitor the Push Notification delivery pipeline — from domain event trigger to FCM acknowledgement. Answers whether push notifications are reaching users and which event types are failing.

### Audience

On-call engineer, product team.

### Operational questions answered

| Question | Panel |
| --- | --- |
| Are push notifications being delivered? | Delivery success rate |
| Which notification type fails most? | Failure breakdown by `notification_type` |
| Is FCM unavailable? | FCM provider error rate |
| Are Smart Home failure pushes being sent? | `notification_type=smart_home_action_failed` rate |
| Are schedule failure pushes being sent? | `notification_type=schedule_execution_failed` rate |

### Panels

| Panel | Signal | Metric / span | Notes |
| --- | --- | --- | --- |
| Delivery Success Rate | Stat | `push.delivery.total{outcome=success}` / total | — |
| Delivery Volume | Time series | `push.delivery.total` rate | By `notification_type` |
| Failure Rate by Notification Type | Bar | `push.delivery.total{outcome=failure}` by `notification_type` | — |
| FCM Provider Error Rate | Time series | `push.delivery.total{outcome=failure,provider=fcm}` | FCM-specific |
| Recent Failing Push Traces | Table (Tempo) | Push delivery span, `outcome=failure` | — |

### Status

**All panels pending Phase 7B.5** (`ixora.push.delivery.total` not yet implemented). Dashboard structure is defined; implementation begins when Phase 7B.5 ships.

### Refresh interval

1 minute.

---

## 6. D-04 — Queue Workers

### Purpose

Monitor the `back_vibes` queue workers across all queues (`smart-home`, `push`, `default`). Answers whether jobs are being processed, which queues are backing up, and which job types are slow or failing.

### Audience

On-call engineer, SRE.

### Operational questions answered

| Question | Panel |
| --- | --- |
| Are workers processing jobs? | Throughput per queue |
| Is any queue backing up? | Job rate vs completion rate |
| Which job types are failing? | Failure rate by `job` |
| Are jobs timing out? | Timeout rate by `job` |
| How long do Smart Home jobs take? | Duration histogram by `job` |
| Are retries accumulating? | Retry attempt rate (`ixora.queue.attempt > 1`) |

### Panels

| Panel | Signal | Metric / span | Notes |
| --- | --- | --- | --- |
| Job Throughput | Time series | `queue.job.total` rate by `queue` | `smart-home`, `push`, `default` |
| Job Failure Rate | Stat | `queue.job.total{outcome=failed}` / total | Per queue |
| Job Duration p50/p95 | Stat | `queue.job.duration` by `job` | — |
| Timeout Rate | Stat | `queue.job.total{outcome=timed_out}` rate | — |
| Failure Breakdown by Job Class | Bar | `queue.job.total{outcome=failed}` by `job` | — |
| Retry Rate | Time series | `queue.job.total{outcome=retried}` | — |
| Dead Letter Volume | Stat | `queue.job.total{outcome=failed}` + Laravel `failed_jobs` count (if scraped) | — |

### Drill-down workflow

```
Failure rate spike on a queue
      ↓
Failure Breakdown: which job class?
      ↓
Tempo: filter by JobClass.handle span → find ERROR spans
      ↓
Loki: trace_id → job-class-specific logs (queue error context tap fields: job, queue, attempt)
```

### Refresh interval

30 seconds.

---

## 7. D-05 — HTTP API

### Purpose

Monitor the `back_vibes-api` HTTP layer. Answers whether the API is healthy, which routes are slow or erroring, and whether there are authentication or authorization failures.

### Audience

On-call engineer, SRE.

### Operational questions answered

| Question | Panel |
| --- | --- |
| Is the API healthy overall? | Request rate + error rate |
| Which routes are slow? | p95 by `http.route` |
| Which routes have the most errors? | Error count by `route` + `status_code` |
| Are there auth failures (401/403)? | 401/403 rate over time |
| Is the dispatch endpoint working? | `POST /api/vibes/{vibe}/smart-home/dispatch` rate |

### Panels

| Panel | Signal | Metric / span | Notes |
| --- | --- | --- | --- |
| Request Rate | Time series | `http.server.duration` count rate | All routes |
| Error Rate (5xx) | Stat + time series | `http.server.duration{status_code=~"5.."}` rate | Alert candidate |
| p50 / p95 Latency | Stat | `http.server.duration` histogram | By route via variable |
| Auth Failure Rate | Time series | `http.server.duration{status_code="401"}` + `{status_code="403"}` | — |
| Top Slow Routes | Table | `http.server.duration` p95 by `http.route` | Top 10 |
| Top Error Routes | Bar | `http.server.duration{status_code=~"4..|5.."}` by `http.route` | — |
| Smart Home Dispatch Endpoint | Stat | `http.server.duration{http.route="/api/vibes/{vibe}/smart-home/dispatch"}` | Success rate + latency |

### Drill-down workflow

```
5xx spike on a route
      ↓
Filter Tempo: HTTP server span, http.route=<route>, status=ERROR
      ↓
Identify which child span has ERROR (controller? service? queue dispatch?)
      ↓
Loki: trace_id → http error context tap + domain logs
```

### Refresh interval

30 seconds.

---

## 8. D-06 — Scheduler

### Purpose

Monitor the `DispatchDueSchedulesCommand` scheduler loop — execution rate, dispatch outcomes per schedule batch, skipped-duplicate rate, and failure rate.

### Audience

On-call engineer, product team.

### Operational questions answered

| Question | Panel |
| --- | --- |
| Is the scheduler loop running? | Execution rate |
| Are schedules dispatching? | Dispatch outcome breakdown |
| How many ticks are being skipped (duplicate)? | Skipped rate |
| Are dispatch batches slow? | Duration histogram |
| Did any batch fail? | Failure rate |

### Panels

| Panel | Signal | Metric / span | Notes |
| --- | --- | --- | --- |
| Scheduler Execution Rate | Stat | `scheduler.execution.total` rate | `dispatched` + `skipped_duplicate` combined |
| Dispatch Success Rate | Stat | `scheduler.execution.total{outcome=dispatched}` / total | — |
| Skipped Duplicate Rate | Time series | `scheduler.execution.total{outcome=skipped_duplicate}` | High = idempotency guard firing normally |
| Failure Rate | Stat | `scheduler.execution.total{outcome=failed}` | Should stay 0 |
| Batch Duration p50/p95 | Stat | `scheduler.dispatch.duration` histogram | — |
| Smart Home Dispatch Rate | Time series | `smart_home.dispatch.total{entry_point=scheduled}` rate | Cross-linked from D-02 |

### Drill-down workflow

```
Failure spike on Scheduler
      ↓
Tempo: DispatchDueSchedulesCommand.handle span, outcome=failed
      ↓
Identify which step failed (processSchedule transaction? validator? dispatch?)
      ↓
Loki: trace_id → scheduler error context (SchedulerErrorContextLogTap)
       + domain warning logs from dispatchSmartHomeAfterSchedule
```

### Refresh interval

1 minute.

---

## 9. D-07 — Collector & Infrastructure

### Purpose

Monitor the OpenTelemetry Collector itself — export pipeline health, queue depth, drop rate, and self-reported health. This is the telemetry system's own health dashboard.

### Audience

SRE, on-call engineer (escalated from domain dashboards when Collector is suspected).

### Operational questions answered

| Question | Panel |
| --- | --- |
| Is the Collector exporting traces? | Trace export rate |
| Is the Collector exporting metrics? | Metric scrape / push rate |
| Is the Collector dropping data? | Drop rate |
| Is the Collector queue full? | Queue depth |
| Are export failures accumulating? | `ixora.telemetry.export.failed.total` from `back_vibes` |
| Is the Collector process alive? | `up` Prometheus target |

### Panels

| Panel | Signal | Source | Notes |
| --- | --- | --- | --- |
| Collector Process Up | Stat | Prometheus `up{job="otel-collector"}` | — |
| Trace Export Rate | Time series | `otelcol_exporter_sent_spans` | From Collector self-metrics |
| Metric Export Rate | Time series | `otelcol_exporter_sent_metric_points` | — |
| Log Export Rate | Time series | `otelcol_exporter_sent_log_records` | — |
| Refused/Dropped Data | Stat | `otelcol_processor_dropped_*` + `otelcol_exporter_send_failed_*` | Alert candidate |
| Export Queue Depth | Time series | `otelcol_exporter_queue_size` | UpDownCounter |
| Application Export Failures | Stat | `ixora.telemetry.export.failed.total` | From `back_vibes` — non-fatal OTLP failures |

### Refresh interval

30 seconds (infrastructure health).

---

## 10. Investigation workflows

These are the complete Metric → Trace → Log workflows for every major operational scenario. Each workflow is a runbook entry.

### 10.1 "Smart Home lights are not turning on"

| Step | Tool | Query / action |
| --- | --- | --- |
| 1 | Grafana D-02 | Check Action Success Rate — is it below threshold? |
| 2 | Grafana D-02 | Outcome Breakdown — failure vs unsupported? |
| 3a — failure | Grafana D-02 | Failure Breakdown by Provider — `home_assistant` rate |
| 3b — unsupported | Loki | `{} \| json \| outcome="unsupported"` → `action_type` field reveals misconfigured action |
| 4 | Tempo | Search `smart_home.action` spans, `ixora.action.outcome=failure`, time range from step 1 |
| 5 | Tempo | Open trace → `smart_home.provider` span → nested `POST` span → `http.response.status_code` |
| 6 | Loki | Copy `trace_id` → `{} \| json \| trace_id="<id>"` → A2 log with `status_code`, `provider_connection_id` |
| 7 | Loki | If no A2 log, look for A4/A5 with `exception_class` — unexpected error |
| Diagnosis | — | `status_code=401` → token expired; `status_code=503` → HA unavailable; `exception_class=ConnectionException` → network |

### 10.2 "Scheduled automations not firing"

| Step | Tool | Query / action |
| --- | --- | --- |
| 1 | Grafana D-06 | Scheduler Execution Rate — is it at expected frequency (~1/min)? |
| 2 | Grafana D-06 | Dispatch Success Rate — are schedules reaching `dispatched` outcome? |
| 3a — rate is 0 | Grafana D-04 | Queue Worker Throughput on `smart-home` queue — are workers running? |
| 3b — rate is normal, dispatches = 0 | Loki | Scheduler warning logs — `ScheduleAutomationValidator` failure messages |
| 4 | Tempo | `DispatchDueSchedulesCommand.handle` span in expected time window |
| 5 | Tempo | Check child `smart_home.dispatch` span — is `dispatched_actions=0`? `skipped_actions=N`? |
| 6 | Loki | `trace_id` → scheduler error context tap + `dispatchSmartHomeAfterSchedule` warning logs |
| Diagnosis | — | `skipped_duplicate=high` → normal idempotency; `dispatched=0, no_spans` → loop not running; `validator_failure_log` → ownership mismatch |

### 10.3 "API returning 5xx errors"

| Step | Tool | Query / action |
| --- | --- | --- |
| 1 | Grafana D-05 | Error Rate (5xx) — spike visible? Which route? |
| 2 | Grafana D-05 | Top Error Routes table — isolate to one route |
| 3 | Tempo | Filter by `http.route=<route>`, `http.status_code=5xx`, ERROR span status |
| 4 | Tempo | Drill into trace — which child span (controller? service? DB? queue dispatch?) has ERROR? |
| 5 | Loki | `trace_id` → HTTP error context tap fields (`route`, `method`, `status_code`) + domain error logs |
| Diagnosis | — | DB error → connection/query issue; queue dispatch error → queue unavailable; domain exception → application bug |

### 10.4 "Queue jobs failing"

| Step | Tool | Query / action |
| --- | --- | --- |
| 1 | Grafana D-04 | Job Failure Rate by queue — which queue, which job class? |
| 2 | Grafana D-04 | Job Duration — are jobs timing out before failing? |
| 3 | Tempo | `{JobClass}.handle` span with ERROR status |
| 4 | Loki | `trace_id` → queue error context tap (`job`, `queue`, `attempt`) + job-specific error logs |
| 3 (alt — no spans) | Loki | `{} \| json \| level="error" \| json \| queue="smart-home"` — catch jobs that died before span was created |
| Diagnosis | — | `attempt=3,outcome=failed` → exhausted retries; `outcome=timed_out` → provider too slow; guard-clause WARNING → stale data |

### 10.5 "Push notifications not arriving"

| Step | Tool | Query / action |
| --- | --- | --- |
| 1 | Grafana D-03 | Delivery Success Rate — below threshold? *(after Phase 7B.5)* |
| 2 | Grafana D-03 | Failure Rate by Notification Type — which event type? |
| 3 | Tempo | Push delivery span, `outcome=failure` |
| 4 | Loki | `trace_id` → push delivery logs + `exception_class` field |
| Diagnosis | — | FCM token expired → `notification_type` specific; FCM unavailable → all types failing; Smart Home action failure pushes blocked → check `smart_home_action_failed` rate |

### 10.6 "Collector is dropping telemetry"

| Step | Tool | Query / action |
| --- | --- | --- |
| 1 | Grafana D-07 | `otelcol_processor_dropped_*` rising? Refused spans/metrics? |
| 2 | Grafana D-07 | `otelcol_exporter_queue_size` near max? |
| 3 | Grafana D-01 | `ixora.telemetry.export.failed.total` rising from application side? |
| 4 | Collector logs | Direct SSH to VM: `journalctl -u otelcol --since "1h ago"` for export errors |
| Diagnosis | — | Queue full → downstream (Tempo/Prometheus/Loki) backpressure; export timeout → network; `back_vibes` export failures → OTLP endpoint unreachable |

---

## 11. Operational questions — signal mapping

Every question that an on-call engineer might ask and which dashboard / panel answers it.

| Question | Dashboard | Panel | Signal |
| --- | --- | --- | --- |
| **System healthy?** | D-01 | Platform Overview top row | HTTP error rate + queue failure rate |
| **API responding?** | D-05 | Request Rate + Error Rate | `ixora.http.server.duration` |
| **Dispatch working?** | D-02 / D-06 | Smart Home Dispatch Rate + Scheduler Execution Rate | `smart_home.dispatch.total`, `scheduler.execution.total` |
| **Actions failing?** | D-02 | Action Success Rate / Outcome Breakdown | `smart_home.action.total` |
| **Provider degraded?** | D-02 | Failure Breakdown by Provider | `smart_home.action.total{provider=*}` + `smart_home.provider` span |
| **Queue backlog?** | D-04 | Job Throughput vs Failure Rate | `queue.job.total` + `queue.job.duration` |
| **Unsupported actions?** | D-02 | Unsupported Action Rate | `smart_home.action.total{outcome=unsupported}` |
| **Latency increasing?** | D-05 / D-02 | API p95 / Action p95 | `http.server.duration` + `smart_home.action.duration` |
| **Push working?** | D-03 | Delivery Success Rate | `push.delivery.total` *(Phase 7B.5)* |
| **Scheduler loop alive?** | D-06 | Scheduler Execution Rate | `scheduler.execution.total` |
| **Collector healthy?** | D-07 | Process Up + Export Rate | `otelcol_*` self-metrics |
| **Why did X fail?** | Any domain → Tempo → Loki | Trace drill-down | `trace_id` correlation |

---

## 12. Grafana variables (standard across dashboards)

Every dashboard must support these standard variables:

| Variable | Values | Usage |
| --- | --- | --- |
| `$environment` | `development`, `staging`, `production` | All queries — mandatory filter |
| `$time_range` | `Last 1h`, `Last 6h`, `Last 24h`, `Last 7d` | All panels |
| `$queue` (D-04 only) | `smart-home`, `push`, `default`, `All` | Queue-specific panels |
| `$route` (D-05 only) | Dynamic from metric label values | Route-specific panels |
| `$provider` (D-02 only) | `home_assistant`, `All` | Provider-specific panels |
| `$outcome` (D-02 only) | `success`, `failure`, `unsupported`, `All` | Outcome breakdown panels |

**Mandatory:** `$environment` must be applied to every panel query. Never deploy a dashboard without this variable — staging data must never contaminate production views.

---

## 13. Data retention policy (per ADR-031)

| Signal | Retention | Impact on dashboards |
| --- | --- | --- |
| Metrics (Prometheus) | 30 days | All trend panels work up to 30 days |
| Traces (Tempo) | 7 days | "Recent Failing Traces" panels limited to 7-day window |
| Logs (Loki) | 14 days | Log drill-down available for 14 days |

Consequence: **post-mortem analysis > 7 days** must rely on metrics only (no trace drill-down). Dashboard panels showing Tempo data should display a "7-day retention" annotation. Long-term trend analysis (> 30 days) is outside MVP scope and requires a future data warehouse or extended retention tier.

---

## 14. Panels deferred (signal not yet available)

The following panels are designed but deferred because the required signal does not yet exist.

| Panel | Missing signal | Blocked by | Dashboard |
| --- | --- | --- | --- |
| Action Type Failure Breakdown | `action_type` label on `smart_home.action.total` | TD-2, Phase 7B.5 | D-02 |
| Guard-Clause Skip Count | J1–J3 skip counter | TD-3, Phase 7B.5/7B.6 | D-02 |
| All Push panels | `ixora.push.delivery.total` | Phase 7B.5 | D-03 |
| Provider Performance by Device Domain | Metric with `device_domain` label | Future phase | D-02 |
| Mobile screen / network panels | `ixora.mobile.*` | Phase 8 Frontend SDK | D-01 |
| SLO panel (error budget burn rate) | SLO config + alerting | Post-MVP | D-01 |

---

## 15. Phase 9 implementation checklist

This document is the architecture contract for Phase 9 (Grafana Dashboards). The Phase 9 engineer must, for each dashboard:

- [ ] Create the dashboard in Grafana with `$environment` variable.
- [ ] Implement all panels listed in the corresponding section above.
- [ ] Verify every PromQL/TraceQL/LogQL query returns data in `staging` environment.
- [ ] Validate `$environment` filter is applied to every panel.
- [ ] Mark deferred panels with a "Pending: Phase X" annotation instead of omitting.
- [ ] Link domain dashboards to each other via Grafana panel links (D-01 → D-02, D-04, D-05, D-06).
- [ ] Annotate 7-day Tempo retention on any Trace-linked panel.
- [ ] Save dashboard JSON to `ixora-infra/grafana/dashboards/` for version control.

---

## Related documents

| Document | Relationship |
| --- | --- |
| [business-telemetry-foundation.md](../business-telemetry/business-telemetry-foundation.md) | Platform Business Telemetry standard — defines all signals dashboards consume |
| [backend-business-telemetry-validation.md](../business-telemetry/backend-business-telemetry-validation.md) | Phase 7B.4.8 validation — confirmed D-02 Smart Home is 6/8 panels ready |
| [metrics-philosophy.md](../../../architecture/metrics-philosophy.md) | Metric design principles — prevents anti-patterns in panel queries |
| [telemetry-naming-convention.md](../../../architecture/telemetry-naming-convention.md) | Canonical metric/span names used throughout this document |
| [observability-playbook.md](../../../operations/observability-playbook.md) | Operational investigation runbook built from the workflows in §10 |
| [spec.md](spec.md) | Phase 9 (Grafana dashboards) implementation scope |
| [ADR-031](../../../decisions/ADR-031-retention-storage-and-cost-control.md) | Retention limits that constrain §13 |
