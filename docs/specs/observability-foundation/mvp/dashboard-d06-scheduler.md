# Dashboard D-06 — Scheduler (Phase 8.3)

**Status:** Complete  
**Type:** Runtime changes (dashboard JSON + validation) + documentation  
**Repo:** `ixora-infra`  
**Feature ID:** `observability-foundation/mvp`  
**Prerequisite:** [dashboard-conventions.md](dashboard-conventions.md) · [grafana-foundation.md](grafana-foundation.md) (Phase 8.1) · [dashboard-d07-infrastructure.md](dashboard-d07-infrastructure.md) (Phase 8.2)

> **Goal:** D-06 answers: "Is the scheduler loop running? Are scheduled events succeeding? Which events are slow or failing?" Exclusively application-scoped.

---

## 1. Executive Summary

Phase 8.3 delivers D-06 — Scheduler, the Laravel Scheduler execution monitoring dashboard for the Ixora platform.

Key outcomes:
- Dashboard JSON provisioned from `collector/grafana/provisioning/dashboards/application/d06-scheduler.json`.
- Permanent dashboard UID `ixora-scheduler` — immutable, version-controlled.
- 17 panels across 5 sections: Health, Throughput, Errors, Performance, Business Link.
- **Critical implementation finding:** `dashboard-requirements.md §8` referenced incorrect metric names (`ixora.scheduler.execution.total`, `ixora.scheduler.dispatch.duration`) and incorrect outcome values (`dispatched`, `skipped_duplicate`). The dashboard uses the verified implementation names and values.
- All datasource references use `ixora-prometheus` exclusively.
- `$environment` variable applied to every panel query.
- Validation: 26/26 PASS (including post-restart idempotency).

---

## 2. Architecture Review

### 2.1 Available scheduler metrics (verified against `SchedulerExecutionTelemetry.php`)

| Metric (Prometheus name) | Type | Labels | Description |
| --- | --- | --- | --- |
| `ixora_scheduler_event_total` | Counter | `environment`, `service_name`, `event_name`, `event_type`, `execution_mode`, `outcome` | Total scheduled event executions |
| `ixora_scheduler_event_duration_bucket/_count/_sum` | Histogram (ms) | same as above | Scheduled event execution duration in milliseconds |

> **Important:** `dashboard-requirements.md §8` listed `ixora.scheduler.execution.total` and `ixora.scheduler.dispatch.duration`. These names are **incorrect** — they were placeholders written before implementation. The correct metric names (from `SchedulerExecutionTelemetry.php` constants `METRIC_EVENT_TOTAL` and `METRIC_DURATION`) are `ixora.scheduler.event.total` and `ixora.scheduler.event.duration`. This discrepancy is documented in `dashboard-conventions.md §13`.

### 2.2 Scheduler outcome values (verified against `SchedulerOutcome.php`)

| Value | Description |
| --- | --- |
| `success` | Foreground event completed with exit code 0 |
| `failed` | Event threw an exception or had non-zero exit code |
| `skipped` | Event skipped by `filtersPass()`/`rejects()` callback or paused |
| `overlap_prevented` | Event skipped because a previous instance was still running (idempotency guard) |
| `background_completed` | Background event launched (process exit code unknown in this process) |
| `cancelled` | Reserved for forward compatibility |
| `unknown` | Fallback case |

> **Important:** `dashboard-requirements.md §8` listed outcomes `dispatched` and `skipped_duplicate`. These are **incorrect** — the actual values are from `SchedulerOutcome.php` as listed above.

### 2.3 Architectural decisions

| Decision | Choice | Rationale |
| --- | --- | --- |
| No `$event_name` variable | Not included | Event names are typically few; grouping by outcome is more informative than isolating one event |
| `overlap_prevented` interpretation | "Normal" — healthy at any rate | This is Laravel's mutex guard working correctly; not an error |
| Business section (ID 500+) | Smart Home dispatch rate cross-reference | The Scheduler is the trigger for Smart Home scheduled dispatches; this panel shows the downstream business effect |
| Success rate denominator | Excludes `overlap_prevented` and `skipped` | These are pre-execution decisions, not outcomes of attempts; including them distorts the completion success fraction |

---

## 3. Dashboard Design

### 3.1 Dashboard properties

| Property | Value |
| --- | --- |
| UID | `ixora-scheduler` (permanent, immutable) |
| Title | D-06 — Scheduler |
| Folder | Application |
| Tags | `application`, `scheduler`, `d-06` |
| Refresh | 30 seconds |
| Schema version | 39 (Grafana 11.x) |
| Default time range | Last 1 hour |
| Datasource | `ixora-prometheus` (all panels) |

### 3.2 Variables

| Variable | Type | Values | Default | Applied to |
| --- | --- | --- | --- | --- |
| `$environment` | custom | `development`, `staging`, `production` | `staging` | Every panel query |

### 3.3 Panel inventory

**Section 1: Health** (Row ID 1)

| ID | Panel | Type | Query | Unit |
| --- | --- | --- | --- | --- |
| 101 | Execution Rate | Stat | `sum(rate(ixora_scheduler_event_total{environment=~"$environment"}[5m]))` | ops |
| 102 | Success Rate | Stat | `sum(rate(...outcome="success"...)) / sum(rate(...outcome!="overlap_prevented",outcome!="skipped"...))` | percentunit |
| 103 | Failure Rate | Stat | `sum(rate(...outcome="failed"...))` | ops |
| 104 | Overlap Prevented Rate | Stat | `sum(rate(...outcome="overlap_prevented"...))` | ops |

**Section 2: Throughput** (Row ID 200)

| ID | Panel | Type | Query | Unit |
| --- | --- | --- | --- | --- |
| 201 | Execution Rate by Outcome | Time series | `sum by(outcome)(rate(ixora_scheduler_event_total{}[5m]))` | ops |

**Section 3: Errors** (Row ID 300)

| ID | Panel | Type | Query | Unit |
| --- | --- | --- | --- | --- |
| 301 | Failed Events by Name | Time series | `sum by(event_name)(rate(...outcome="failed"...))` | ops |
| 302 | Failure Breakdown by Event | Bar chart | `topk(10, sum by(event_name)(increase(...outcome="failed"...[$__range])))` | short |

**Section 4: Performance** (Row ID 400)

| ID | Panel | Type | Query | Unit |
| --- | --- | --- | --- | --- |
| 401 | Event Duration p50 | Stat | `histogram_quantile(0.50, ...)` | ms |
| 402 | Event Duration p95 | Stat | `histogram_quantile(0.95, ...)` | ms |
| 403 | Event Duration p99 | Stat | `histogram_quantile(0.99, ...)` | ms |
| 404 | Event Duration Percentiles over Time | Time series | p50, p95, p99 series | ms |

**Section 5: Business — Smart Home Link** (Row ID 500)

| ID | Panel | Type | Query | Unit |
| --- | --- | --- | --- | --- |
| 501 | Smart Home Dispatch Rate (entry_point=scheduled) | Time series | `sum by(outcome)(rate(ixora_smart_home_dispatch_total{entry_point="scheduled"}[5m]))` | ops |

---

## 4. Dashboard Navigation

### 4.1 Dashboard-level links

| Link | URL | keepTime |
| --- | --- | --- |
| D-04 Queue Workers | `/d/ixora-queue` | true |
| D-05 HTTP API | `/d/ixora-http` | true |
| D-07 Infrastructure | `/d/ixora-collector` | true |

### 4.2 Drill-down workflow (10.2 — "Scheduled automations not firing")

```
1. D-06 Execution Rate — is it at expected frequency (~1/min)?
      ↓
2. D-06 Success Rate — are scheduled events reaching outcome=success?
      ↓
3a. Rate = 0 → D-04 Queue Worker Throughput on smart-home queue — workers running?
      ↓
3b. Rate = normal, dispatches = 0 → Loki ScheduleAutomationValidator failure messages
      ↓
4. Tempo — DispatchDueSchedulesCommand.handle span in expected time window
      ↓
5. Tempo — check child smart_home.dispatch span — dispatched_actions=0? skipped_actions=N?
      ↓
6. Loki — trace_id → scheduler error context tap + dispatchSmartHomeAfterSchedule warning logs
      ↓
Diagnosis: overlap_prevented high (normal); dispatched=0/no spans (loop stopped); validator failure (ownership mismatch)
```

---

## 5. Known Limitations

### KL-1: Metric names differ from `dashboard-requirements.md §8`

`dashboard-requirements.md §8` (Phase 8.0) listed `ixora.scheduler.execution.total` / `ixora.scheduler.dispatch.duration` and outcomes `dispatched` / `skipped_duplicate`. These are incorrect pre-implementation placeholders. The actual names and values are documented above and in `dashboard-conventions.md §13`.

### KL-2: No `event_name` variable

The `$event_name` variable is not implemented because in the current application there are few distinct scheduled events and filtering by outcome is the primary operational need. Adding this variable is low-priority but straightforward if needed.

### KL-3: Background events show `background_completed`, not `success`/`failed`

Background event exit codes are not available in the `schedule:run` process (they arrive later in a separate `schedule:finish` process). The `background_completed` outcome indicates the event was launched, not that it succeeded. True background event success/failure requires checking the console command's own metric (`ixora_console_command_total{command="..."}`) or the trace.

---

## 6. Security Review

| Category | Status |
| --- | --- |
| PII in panel queries | None — labels are `event_name`, `event_type`, `execution_mode`, `outcome` |
| Device/entity IDs | None |
| Credentials | None |
| Payloads | None |
| Sensitive data in event names | `event_name` is normalized (e.g., `DispatchDueSchedulesCommand`, `App\Console\Commands\...`) — no IDs or parameters |

---

## 7. Files Created / Modified

### Created

| File | Description |
| --- | --- |
| `collector/grafana/provisioning/dashboards/application/d06-scheduler.json` | D-06 dashboard JSON (17 panels, uid=ixora-scheduler) |
| `docs/specs/observability-foundation/mvp/dashboard-d06-scheduler.md` | This document |

---

## Related Documents

| Document | Relationship |
| --- | --- |
| [dashboard-conventions.md](dashboard-conventions.md) | Conventions this dashboard follows (§13: known metric name discrepancy) |
| [dashboard-requirements.md](dashboard-requirements.md) | Phase 8.0 — D-06 panel specification (§8) — note metric name corrections above |
| [grafana-foundation.md](grafana-foundation.md) | Phase 8.1 — provisioning foundation |
