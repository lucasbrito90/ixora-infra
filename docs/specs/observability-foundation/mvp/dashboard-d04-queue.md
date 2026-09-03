# Dashboard D-04 — Queue Workers (Phase 8.3)

**Status:** Complete  
**Type:** Runtime changes (dashboard JSON + validation) + documentation  
**Repo:** `ixora-infra`  
**Feature ID:** `observability-foundation/mvp`  
**Prerequisite:** [dashboard-conventions.md](dashboard-conventions.md) · [grafana-foundation.md](grafana-foundation.md) (Phase 8.1) · [dashboard-d07-infrastructure.md](dashboard-d07-infrastructure.md) (Phase 8.2)

> **Goal:** D-04 answers: "Are queue workers processing jobs? Which queues are backed up? Which job types are failing or slow?" Exclusively application-scoped.

---

## 1. Executive Summary

Phase 8.3 delivers D-04 — Queue Workers, the queue execution monitoring dashboard for the Ixora platform.

Key outcomes:
- Dashboard JSON provisioned from `collector/grafana/provisioning/dashboards/application/d04-queue.json`.
- Permanent dashboard UID `ixora-queue` — immutable, version-controlled.
- 17 panels across 4 sections: Health, Throughput, Errors, Performance.
- All datasource references use `ixora-prometheus` exclusively.
- `$environment` variable applied to every panel query.
- `$queue` variable for per-queue drill-down (smart-home, push, default).
- Validation: 26/26 PASS (including post-restart idempotency).

---

## 2. Architecture Review

### 2.1 Available queue metrics (verified against `QueueExecutionTelemetry.php`)

| Metric (Prometheus name) | Type | Labels | Description |
| --- | --- | --- | --- |
| `ixora_queue_job_total` | Counter | `environment`, `service_name`, `queue`, `connection`, `job_name`, `outcome` | Total job execution attempts |
| `ixora_queue_job_duration_bucket/_count/_sum` | Histogram (ms) | same as above | Job execution duration in milliseconds |
| `ixora_queue_job_active` | Gauge (UpDownCounter) | `environment`, `service_name`, `queue`, `connection`, `job_name` | Currently executing jobs |

### 2.2 Queue outcome values (verified against `QueueOutcome.php`)

| Value | Description |
| --- | --- |
| `success` | Job completed successfully |
| `failed` | Job permanently failed (max attempts exhausted) |
| `released` | Job released back to queue without exception |
| `retried` | Job released after exception (retried) |
| `timed_out` | Job killed by SIGALRM timeout |
| `cancelled` | Reserved for forward compatibility |
| `unknown` | Fallback case |

### 2.3 Label names (note — not the same as `dashboard-requirements.md` §6)

The `job_name` label (not `job`) is used in the implementation. The `connection` label tracks the queue connection (`redis`, `database`, etc.). The `dashboard-requirements.md` referred to `job` as the label name — the actual implementation uses `job_name`.

### 2.4 Architectural decisions

| Decision | Choice | Rationale |
| --- | --- | --- |
| `$queue` variable | `label_values(ixora_queue_job_total{}, queue)`, `includeAll: true` | Operators can view all queues together or drill into one |
| Active jobs metric | `ixora_queue_job_active` (UpDownCounter) | Available as a gauge; reset on worker restart — documented in panel description |
| Success rate denominator | Excludes `retried` and `released` from denominator | These are intermediate states, not terminal outcomes; dividing by them distorts the "permanent success" fraction |
| Duration histogram | Per queue and job class via `sum by(le, job_name)` for table | Identifies slowest job types |

---

## 3. Dashboard Design

### 3.1 Dashboard properties

| Property | Value |
| --- | --- |
| UID | `ixora-queue` (permanent, immutable) |
| Title | D-04 — Queue Workers |
| Folder | Application |
| Tags | `application`, `queue`, `workers`, `d-04` |
| Refresh | 30 seconds |
| Schema version | 39 (Grafana 11.x) |
| Default time range | Last 1 hour |
| Datasource | `ixora-prometheus` (all panels) |

### 3.2 Variables

| Variable | Type | Values / Query | Default | Applied to |
| --- | --- | --- | --- | --- |
| `$environment` | custom | `development`, `staging`, `production` | `staging` | Every panel query |
| `$queue` | query | `label_values(ixora_queue_job_total{environment="$environment"}, queue)` | All | Queue-specific panels |

### 3.3 Panel inventory

**Section 1: Health** (Row ID 1)

| ID | Panel | Type | Query | Unit |
| --- | --- | --- | --- | --- |
| 101 | Job Success Rate | Stat | `sum(rate(...outcome="success"...)) / sum(rate(...outcome!="retried",outcome!="released"...))` | percentunit |
| 102 | Failure Rate | Stat | `sum(rate(...outcome="failed"...))` | ops |
| 103 | Active Jobs | Stat | `sum(ixora_queue_job_active{environment=~"$environment"})` | short |
| 104 | Timeout Rate | Stat | `sum(rate(...outcome="timed_out"...))` | ops |

**Section 2: Throughput** (Row ID 200)

| ID | Panel | Type | Query | Unit |
| --- | --- | --- | --- | --- |
| 201 | Job Throughput by Queue | Time series | `sum by(queue)(rate(ixora_queue_job_total{queue=~"$queue"}[5m]))` | ops |
| 202 | Retry Rate by Queue | Time series | `sum by(queue)(rate(...outcome="retried"...))` | ops |
| 203 | Outcome Breakdown | Time series | `sum by(outcome)(rate(...))` | ops |

**Section 3: Errors** (Row ID 300)

| ID | Panel | Type | Query | Unit |
| --- | --- | --- | --- | --- |
| 301 | Failure Breakdown by Job Class | Bar chart | `topk(10, sum by(job_name)(increase(...outcome="failed"...[$__range])))` | short |
| 302 | Failed Jobs Rate by Queue | Time series | `sum by(queue)(rate(...outcome="failed"...))` | ops |

**Section 4: Performance** (Row ID 400)

| ID | Panel | Type | Query | Unit |
| --- | --- | --- | --- | --- |
| 401 | Job Duration p50 | Stat | `histogram_quantile(0.50, ...)` | ms |
| 402 | Job Duration p95 | Stat | `histogram_quantile(0.95, ...)` | ms |
| 403 | Job Duration p99 | Stat | `histogram_quantile(0.99, ...)` | ms |
| 404 | Job Duration Percentiles over Time | Time series | p50, p95, p99 series | ms |
| 405 | Slowest Job Classes (p95) | Table | `topk(15, histogram_quantile(0.95, sum by(le, job_name)(rate(...))))` | ms |

---

## 4. Dashboard Navigation

### 4.1 Dashboard-level links

| Link | URL | keepTime |
| --- | --- | --- |
| D-05 HTTP API | `/d/ixora-http` | true |
| D-06 Scheduler | `/d/ixora-scheduler` | true |
| D-07 Infrastructure | `/d/ixora-collector` | true |

### 4.2 Drill-down workflow (10.4 — "Queue jobs failing")

```
1. D-04 Failure Rate by Queue — which queue, which job class?
      ↓
2. D-04 Failure Breakdown by Job Class — identify the worst job type
      ↓
3. D-04 Job Duration — are jobs timing out before failing?
      ↓
4. Tempo — {job_name}.handle span with ERROR status
      ↓
5. Loki — trace_id → queue error context tap (job, queue, attempt) + job-specific logs
      ↓
Diagnosis: exhausted retries / timed_out (provider slow) / guard-clause WARNING
```

---

## 5. Security Review

| Category | Status |
| --- | --- |
| PII in panel queries | None — metric labels are `queue`, `connection`, `job_name`, `outcome` |
| Device/entity IDs | None — `job_name` is the normalized class name, not a payload |
| Credentials | None |
| Payloads | None |
| Sensitive URLs | None |

---

## 6. Files Created / Modified

### Created

| File | Description |
| --- | --- |
| `collector/grafana/provisioning/dashboards/application/d04-queue.json` | D-04 dashboard JSON (17 panels, uid=ixora-queue) |
| `docs/specs/observability-foundation/mvp/dashboard-d04-queue.md` | This document |

---

## Related Documents

| Document | Relationship |
| --- | --- |
| [dashboard-conventions.md](dashboard-conventions.md) | Conventions this dashboard follows |
| [dashboard-requirements.md](dashboard-requirements.md) | Phase 8.0 — D-04 panel specification (§6) |
| [grafana-foundation.md](grafana-foundation.md) | Phase 8.1 — provisioning foundation |
