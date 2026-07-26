# Logs Philosophy

**Status:** Active architecture guide  
**ADRs:** [ADR-028](../decisions/ADR-028-observability-platform.md) · [ADR-029](../decisions/ADR-029-telemetry-data-model.md) · [ADR-030](../decisions/ADR-030-observability-security-and-privacy.md) · [ADR-031](../decisions/ADR-031-retention-storage-and-cost-control.md)  
**Complements:** [`metrics-philosophy.md`](metrics-philosophy.md) · [`telemetry-naming-convention.md`](telemetry-naming-convention.md) · [`telemetry-decision-guide.md`](telemetry-decision-guide.md) · [`operations/observability-playbook.md`](../operations/observability-playbook.md) · [`specs/observability-foundation/mvp/loki-deployment.md`](../specs/observability-foundation/mvp/loki-deployment.md)  
**Applies to:** All engineers instrumenting `back_vibes`, `front_vibes`, or observability stack components — **mandatory before Phases 7 and 8 (application instrumentation)**

> **Rule of thumb:** This document defines **how engineers think about logs**. It is not a Loki manual, an OpenTelemetry tutorial, or a naming reference. For field names and schema, see [telemetry-naming-convention.md §9](telemetry-naming-convention.md). For signal choice (log vs metric vs trace), see [telemetry-decision-guide.md](telemetry-decision-guide.md). For Loki deployment and retention, see [loki-deployment.md](../specs/observability-foundation/mvp/loki-deployment.md).

---

## 1. Purpose

Logs exist to explain **what happened**, **why it happened**, and **the context around failures** — for a specific occurrence, at a point in time, with enough detail to investigate.

| Signal | What it captures | Time horizon |
| --- | --- | --- |
| **Logs** | Discrete events with context — one record per occurrence | Point-in-time detail (14 days in MVP) |
| **Metrics** | Aggregated measurements — counts, rates, distributions | Continuous trends (30 days in MVP) |
| **Traces** | Workflow structure — one execution, step by step | Single request or job run (7 days in MVP) |
| **Events** | Named occurrences within a span or log stream | Attached to a trace or log record |

### Why logs are different from metrics

Metrics answer: **How often does this happen? How fast? Is the rate rising?** Logs answer: **What exactly went wrong in this case? What was the exception? Which schedule, device, or job failed?**

A spike in `ixora.smart_home.action.total{outcome=failure}` belongs in **Prometheus**. The sanitized exception message, `device_id`, and `trace_id` for one failed Home Assistant call belong in a **log**.

Logs are not a substitute for dashboards. They are the **detail layer** you reach for after a metric or trace points you to a problem.

### Why logs are different from traces

Traces answer: **What steps ran, in what order, and how long did each take?** Logs answer: **What did the application decide or observe at a specific step?**

A trace shows that `SmartHomeActionJob.handle` took 4.2 s and failed at the provider span. A log at `level=error` explains that Home Assistant returned HTTP 503 with a sanitized message — without replacing the span hierarchy.

### Why logs are different from events

**Span events** (OTel) mark a moment inside a span — e.g. `scheduler.schedule.dispatched`. **Structured logs** are independent records that may or may not be tied to an active span. Use span events for workflow milestones inside a trace; use logs when you need searchable text, stack traces, or context that outlives a single span.

### The core idea

> Logs explain **specific occurrences** — not system trends, not workflow graphs, and not arbitrary application storage.

Observability Foundation Phases 1–5 established **what** the platform collects ([ADR-028](../decisions/ADR-028-observability-platform.md)), **how signals relate** ([ADR-029](../decisions/ADR-029-telemetry-data-model.md)), **what must never be exported** ([ADR-030](../decisions/ADR-030-observability-security-and-privacy.md)), **retention and cost limits** ([ADR-031](../decisions/ADR-031-retention-storage-and-cost-control.md)), and **where logs are stored** ([loki-deployment.md](../specs/observability-foundation/mvp/loki-deployment.md)). This guide establishes **how engineers decide what deserves a log** — before Phases 7 and 8 add instrumentation to `back_vibes` and `front_vibes`.

---

## 2. Core principles

These principles govern every log decision at Ixora.

| Principle | Meaning |
| --- | --- |
| **Logs explain what happened** | Each log record should answer a concrete question: what failed, what was skipped, what external system misbehaved. |
| **Logs explain why it happened** | Include sanitized reason codes, validator outcomes, exception class — not raw payloads. |
| **Logs carry failure context** | When something goes wrong, include entity IDs (`schedule_id`, `device_id`) and `trace_id` — not secrets. |
| **Logs are not metrics** | Do not log every success to simulate a counter. Use Prometheus for rates and histograms. |
| **Logs are not traces** | Do not log step-by-step timing for every request. Use spans for workflow structure. |
| **Logs are not a database** | Never use logs to store business state, audit trails requiring integrity, or user-generated content at volume. |
| **Logs must be structured** | JSON with stable field names — not concatenated strings that require regex parsing. |
| **Logs must be safe** | Redaction at application and Collector ([ADR-030](../decisions/ADR-030-observability-security-and-privacy.md)); assume every log may be queried by operators. |
| **Logs must be sparse** | High-frequency, low-value logs inflate Loki cost and drown signal in noise ([ADR-031](../decisions/ADR-031-retention-storage-and-cost-control.md)). |

**Volume is a design decision.** Every log line consumes ingestion budget, index space, and operator attention. Default to silence on success; speak on failure, anomaly, or lifecycle change.

---

## 3. When to create logs

Create a log when an engineer investigating an incident needs **textual context** that metrics cannot provide and traces alone do not capture.

| Scenario | Level (typical) | Why log |
| --- | --- | --- |
| **Operational failures** | `error` | Exception class, sanitized message, entity IDs for root-cause analysis |
| **Unexpected states** | `warning` | Domain invariant violated but request continued — e.g. schedule skipped |
| **External provider failures** | `error` / `warning` | HA timeout, FCM rejection — provider name, HTTP status, retry intent |
| **Retries** | `warning` | Attempt number, backoff, whether final attempt — not every retry at `info` |
| **Validation failures** | `warning` | Which validator failed, which entity — not raw request body |
| **Infrastructure failures** | `error` | DB connection lost, queue broker unreachable, disk full |
| **Authentication failures** | `warning` | Invalid token, expired session — never log the token itself |
| **Security events** | `warning` / `error` | Repeated auth failures, suspicious patterns — no credential values |
| **Important lifecycle events** | `info` | Service startup, shutdown, config reload, migration complete |
| **Worker lifecycle** | `info` | Worker boot, graceful shutdown, queue subscription change |
| **Startup** | `info` | Application version, environment, dependency health summary |
| **Shutdown** | `info` | Drain started, in-flight jobs count, clean exit |
| **Recovery** | `info` / `warning` | Reconnection after outage, WAL replay, stale lock cleared |

**Test:** Would an on-call engineer searching Loki at 3 a.m. find this record useful — and would they miss it if it were absent? If yes, log it. If the answer is already visible on a Grafana panel as a trend, use a metric instead.

---

## 4. When NOT to create logs

Do not create logs when the information is **routine**, **high-frequency**, **already captured elsewhere**, or **better as a metric or trace**.

| Do not log | Why | Use instead |
| --- | --- | --- |
| **Every successful HTTP request** | Volume explosion; latency belongs in histogram | `ixora.http.server.duration` + trace for sampled requests |
| **Every database query** | Noise; may leak schema/SQL | Span `db.query` (no statement in MVP); slow-query metric if needed |
| **Every cache hit** | Meaningless at scale | Debug locally only; metric for hit ratio if operational |
| **Every queue execution** | Throughput is a metric | `ixora.queue.job.total{outcome=success}` |
| **Every scheduler tick** | Tick runs every minute | Log only when dispatch outcome is non-trivial (skipped, failed) |
| **Every heartbeat** | Pure noise | Health metric or absence-of-metric alert |
| **Repeated polling** | Loop spam | Log once on state change; metric for poll errors |
| **High-frequency loops** | Index and cost blow-up | Aggregate counter; log summary on exit |
| **Duplicate information already in metrics** | "Request succeeded" at `info` × 10 000/min | Counter increment only |
| **Business analytics** | Product metrics ≠ operational logs | Future analytics pipeline — separate spec |
| **Debug dumps in production** | Risk + volume | `debug` level, disabled in production by default |

**Why metrics are more appropriate:** Success rates, latency percentiles, queue depth, and scheduler dispatch counts change continuously. Pre-aggregated time series in Prometheus answer operational questions without reading millions of log lines.

**Why traces are more appropriate:** Per-request timing, parent-child relationships, and cross-service propagation belong in Tempo spans — not duplicated as sequential log lines.

See [telemetry-decision-guide.md §6–§7](telemetry-decision-guide.md) for the full signal choice tree.

---

## 5. Log levels

Use OTel severity / Laravel log levels consistently. Map to Loki stream label `level` via the Collector ([loki-deployment.md §5](../specs/observability-foundation/mvp/loki-deployment.md)).

| Level | When to use | Ixora examples |
| --- | --- | --- |
| **DEBUG** | Local troubleshooting only; disabled in production staging by default | Adapter request/response sizes (no bodies), cache key names, sampler decisions |
| **INFO** | Lifecycle and meaningful business milestones — sparse | `back_vibes-api` started; schedule created (optional — prefer trace event); worker graceful shutdown |
| **WARN** | Recoverable problems, validation skips, retries, degraded mode | Schedule skipped — validator failed; FCM token invalid (hash only); HA action retry attempt 2/3; auth token expired |
| **ERROR** | Failures requiring investigation; operation did not complete | Smart Home action failed after retries; push job exception; DB query failed; unhandled 5xx |
| **FATAL** | Process cannot continue; imminent crash or exit | Worker OOM; cannot connect to database on boot; missing required env var |

### Level discipline

| Rule | Detail |
| --- | --- |
| **Default production minimum** | `info` for API/worker; `warning` for mobile client export |
| **Never `info` on hot paths** | Successful HTTP 200, job success, cache hit → metric only |
| **Escalate, don't duplicate** | One `error` with context beats five `warning` lines for the same failure |
| **Exception = `error` minimum** | Caught exceptions that affect outcome log at `error` with `exception_class` |
| **Align with alerts (Phase 10+)** | `error` rate in Loki may drive alerts — do not inflate with benign messages |

---

## 6. Required log attributes

Structured logs MUST use stable field names per [telemetry-naming-convention.md §9](telemetry-naming-convention.md). Include attributes when the context exists — do not emit empty placeholders.

| Attribute | When required | Purpose |
| --- | --- | --- |
| `service.name` | Always | Identifies producer — `back_vibes-api`, `back_vibes-worker`, `front_vibes-android` |
| `deployment.environment` | Always | `staging` or `production` — stamped by SDK or Collector |
| `level` | Always | Severity for filtering and alerting |
| `message` | Always | Human-readable summary — one sentence |
| `timestamp` | Always | ISO 8601 UTC event time |
| `trace_id` | When span active | Loki → Tempo correlation in Grafana |
| `span_id` | When span active | Pinpoints log to specific span |
| `request_id` | HTTP requests | Correlates logs within one API call when trace sampling dropped the trace |
| `job_id` | Queue jobs | Laravel job UUID — bounded per job, not per user |
| `worker` | Queue / CLI | Worker process identity — e.g. `smart-home`, `default` |
| `provider` | External integrations | `home_assistant`, `fcm` — bounded enum |
| `schedule_id` | Scheduler flows | Which schedule was dispatched, skipped, or failed |
| `automation_id` | Automation executions | Product automation row reference |
| `device_id` | Smart Home | Which device was targeted |
| `connection_id` | Smart Home | Provider connection reference — not credentials |
| `user_id` | When domain-relevant | Integer ID only — never email ([ADR-030](../decisions/ADR-030-observability-security-and-privacy.md)) |
| `exception_class` | On errors | FQCN — e.g. `App\Exceptions\ProviderException` |
| `outcome` | Domain results | `success`, `failure`, `skipped` — when not obvious from level |

**Spans use dot notation** (`schedule.id`). **Logs use snake_case** (`schedule_id`) for Laravel compatibility — both refer to the same entity.

High-cardinality IDs (`schedule_id`, `device_id`, `user_id`) belong in **log body fields**, not Loki stream labels. The Collector promotes only `service_name` and `deployment_environment` to stream labels ([loki-deployment.md §5](../specs/observability-foundation/mvp/loki-deployment.md)).

---

## 7. Forbidden information

Never emit the following in logs — at any level, in any field, including "debug" ([ADR-030](../decisions/ADR-030-observability-security-and-privacy.md)).

| Category | Forbidden | Allowed alternative |
| --- | --- | --- |
| **Credentials** | Passwords, bearer tokens, JWT, cookies, Authorization headers, refresh tokens, FCM tokens, HA tokens | Log `auth_failed=true`; token hash prefix if needed for dedup |
| **Personal data** | Email addresses, phone numbers, full names, Firebase UID, physical addresses | `user_id` integer only |
| **Financial** | Credit card numbers, billing details | Never — out of scope for operational logs |
| **Secrets** | API keys, private keys, encrypted credentials, `.env` values | Log `secret_missing=true` without value |
| **Database** | Raw SQL statements, connection strings with passwords | `exception_class`, operation name, sanitized error |
| **Payloads** | Full request/response bodies, provider JSON responses | Truncated summary, status code, entity IDs |
| **Session data** | Session tokens, CSRF tokens | Session invalidated — no token value |

The Collector `attributes/redact_secrets` processor is a **second line of defense** — not permission to log secrets at the application layer. Application code must never emit forbidden keys; the Collector drops them before Loki storage ([collector-validation-report.md](../specs/observability-foundation/mvp/collector-validation-report.md)).

See also [security-review.md §8](../specs/observability-foundation/mvp/security-review.md).

---

## 8. Structured logging

All production logs exported to Loki MUST be **machine-readable JSON** — not plain text with embedded values.

| Rule | Detail |
| --- | --- |
| **JSON output** | Laravel: `Log::channel` with JSON formatter; mobile: structured OTel log records |
| **No string concatenation** | `"Schedule " . $id . " failed"` → `{"message":"Schedule dispatch failed","schedule_id":42}` |
| **Consistent field names** | Same keys across API, worker, mobile — see [telemetry-naming-convention.md §9](telemetry-naming-convention.md) |
| **Timestamp handling** | UTC ISO 8601; SDK sets `timeUnixNano`; avoid duplicate local-time fields |
| **Resource attributes** | `service.name`, `deployment.environment` on resource — inherited by all log records |
| **Stable message strings** | Message is a template-like summary; variable data in fields — enables LogQL aggregation |
| **One event per record** | Do not bundle unrelated facts into one log line |

### Safe example

```json
{
  "timestamp": "2026-07-12T22:00:00.000Z",
  "level": "error",
  "message": "SmartHomeActionJob: provider call failed after retries",
  "service.name": "back_vibes-worker",
  "deployment.environment": "staging",
  "trace_id": "4bf92f3577b34da6a3ce929d0e0e4736",
  "span_id": "00f067aa0ba902b7",
  "job_id": "9f8e7d6c-5b4a-3210-fedc-ba9876543210",
  "queue": "smart-home",
  "provider": "home_assistant",
  "device_id": 5,
  "connection_id": 2,
  "schedule_id": 42,
  "exception_class": "App\\SmartHome\\Exceptions\\ProviderTimeoutException",
  "outcome": "failure",
  "retry_attempts": 3
}
```

### Unsafe example (never ship)

```json
{
  "message": "HA call failed: Authorization: Bearer eyJhbG...",
  "sql": "SELECT * FROM users WHERE email = 'user@example.com'",
  "response_body": "{ ... full provider payload ... }"
}
```

---

## 9. Relationship — Logs through the platform

Applications never communicate directly with Loki. All logs flow through the OpenTelemetry Collector.

```
back_vibes-api / back_vibes-worker / front_vibes-android
         │
         │  OTLP Logs (gRPC or HTTP)
         │  Bearer token auth
         ▼
┌─────────────────────────────┐
│   OpenTelemetry Collector   │
│   ── memory_limiter         │
│   ── resource               │  ← stamps deployment.environment
│   ── attributes/redact      │  ← drops credentials, PII (ADR-030)
│   ── batch                  │
│   ── loki exporter          │
└─────────────────────────────┘
         │
         │  HTTP POST /loki/api/v1/push
         │  (Docker network only)
         ▼
┌─────────────────────────────┐
│           Loki              │
│   14-day retention          │
│   stream labels:            │
│     service_name,           │
│     deployment_environment, │
│     level, job              │
└─────────────────────────────┘
         │
         │  LogQL (Phase 9)
         ▼
┌─────────────────────────────┐
│          Grafana            │
│   Explore · Dashboards      │
└─────────────────────────────┘
```

**Why applications never write to Loki directly:**

| Reason | Detail |
| --- | --- |
| **Single ingestion path** | [ADR-028](../decisions/ADR-028-observability-platform.md) — auditability and consistent processing |
| **Mandatory redaction** | Collector enforces ADR-030 before storage — apps cannot bypass |
| **Network isolation** | Loki is on internal Docker network; apps have no route ([loki-deployment.md §7](../specs/observability-foundation/mvp/loki-deployment.md)) |
| **Cardinality control** | Collector controls which attributes become stream labels |
| **Auth simplicity** | Apps authenticate to Collector only — not to every backend |

Export failures must never block business logic ([telemetry-availability-policy.md](telemetry-availability-policy.md)).

---

## 10. Relationship with metrics

Use the right signal for the question. Many situations need **both** a metric and a log — but for different purposes.

| Question | Signal | Ixora example |
| --- | --- | --- |
| How many Smart Home actions failed this hour? | **Counter** | `ixora.smart_home.action.total{outcome=failure}` |
| Why did device 5 fail on this job? | **Log** | `level=error`, `device_id=5`, `exception_class`, `trace_id` |
| What is p95 API latency? | **Histogram** | `ixora.http.server.duration` |
| What was the slow query pattern on this request? | **Trace** (+ optional log) | Span attributes — not raw SQL log |
| Is the queue backing up? | **Gauge / UpDownCounter** | Queue depth metric |
| Which job class threw this exception? | **Log** | `job_id`, `exception_class`, bounded `job` name |
| Current PHP memory usage | **Gauge** | Infra metric — not logged every tick |
| Scheduler tick ran successfully | **Neither** (routine success) | Metric: `ixora.scheduler.execution.total{outcome=success}` — no log |
| Scheduler tick skipped schedule 42 | **Log** (and metric) | Metric: `outcome=skipped`; Log: `schedule_id=42`, validator reason |

### Decision shortcuts

```
Need a trend or rate over time?
  → Metric (Counter / Histogram)

Need detail for one failure?
  → Log (with trace_id and entity IDs)

Need both trend AND detail?
  → Metric for the aggregate + Log on failure path only

Routine success on a hot path?
  → Metric only (or neither if already covered)

Neither trend nor investigation value?
  → Neither — do not emit
```

See [metrics-philosophy.md §7](metrics-philosophy.md) for the complementary metrics perspective.

---

## 11. Relationship with traces

Traces and logs are **correlated**, not interchangeable.

| Concept | Role |
| --- | --- |
| **Trace** | One logical workflow — identified by `trace_id` |
| **Span** | One step inside a workflow — identified by `span_id` |
| **Span event** | Moment inside a span — e.g. `scheduler.schedule.dispatched` |
| **Log** | Standalone record — may reference `trace_id` / `span_id` for correlation |
| **Error on span** | Span status `ERROR` — visible in Tempo |
| **Error log** | Textual detail — exception, sanitized message, domain IDs |

### Correlation workflow

1. Grafana dashboard shows metric anomaly (error rate spike).
2. Operator filters **traces** by time range and route — finds failing trace `abc123`.
3. Operator queries **Loki**: `{service_name="back_vibes-api"} | json | trace_id="abc123"`.
4. Log lines reveal exception class and `schedule_id` — trace alone may not include full message.

**Always inject `trace_id` into log context** when a span is active (Phase 7 SDK requirement). This is the primary cross-signal link in MVP.

Do not log every span start/end — that duplicates Tempo. Log at decision points: validation failure, retry, provider error, unexpected branch.

---

## 12. Examples

Domain-specific log patterns aligned with [ADR-029](../decisions/ADR-029-telemetry-data-model.md) and [observability-playbook.md](../operations/observability-playbook.md).

### HTTP API

| Situation | Log? | Example |
| --- | --- | --- |
| `POST /api/v1/schedules` → 201 | ❌ No | Metric + trace only |
| `POST /api/v1/schedules` → 422 validation | ⚠️ Optional `warning` | Only if trace insufficient; include field names, not body |
| `POST /api/v1/schedules` → 500 unhandled | ✅ `error` | `exception_class`, `trace_id`, `http.route`, sanitized message |
| Auth token invalid | ✅ `warning` | `auth_failed=true` — no token value |

### Queue worker

| Situation | Log? | Example |
| --- | --- | --- |
| Job processed successfully | ❌ No | `ixora.queue.job.total{outcome=success}` |
| Job failed after retries | ✅ `error` | `job_id`, `queue`, `exception_class`, `trace_id` |
| Job released back to queue | ✅ `warning` | `retry_attempt`, `job_id`, reason code |

### Scheduler

| Situation | Log? | Example |
| --- | --- | --- |
| Dispatch tick runs | ❌ No | Metric only |
| Schedule skipped — validator | ✅ `warning` | `schedule_id`, `validator_failed=true`, reason |
| Schedule dispatched | ⚠️ Span event preferred | Log only if debugging dispatch logic |
| Dispatch command exception | ✅ `error` | `exception_class`, tick timestamp |

### Smart Home

| Situation | Log? | Example |
| --- | --- | --- |
| HA action succeeded | ❌ No | Metric + trace |
| HA timeout after retries | ✅ `error` | `device_id`, `provider`, `connection_id`, `action_type`, `trace_id` |
| Unsupported action type | ✅ `warning` | `action_type`, `device_id` — before provider call |

### Push notification

| Situation | Log? | Example |
| --- | --- | --- |
| FCM delivery succeeded | ❌ No | `ixora.push.delivery.total{outcome=success}` |
| FCM token invalid | ✅ `warning` | `notification_type`, token hash prefix — not full token |
| FCM API error | ✅ `error` | `notification_type`, HTTP status, sanitized FCM error code |

### Background job (generic)

| Situation | Log? | Example |
| --- | --- | --- |
| Job started | ❌ No | Trace span covers this |
| Job completed | ❌ No | Metric |
| Domain rule rejected processing | ✅ `warning` | Entity IDs + rule name |
| Unhandled exception | ✅ `error` | Full structured error context |

### Authentication

| Situation | Log? | Example |
| --- | --- | --- |
| Successful login / sync | ❌ No | Audit elsewhere if needed — not ops log spam |
| Firebase token verify failed | ✅ `warning` | `auth_failed=true`, failure reason enum |
| Repeated failures from same IP | ✅ `warning` | Security monitoring — no PII |

### External API timeout

| Situation | Log? | Example |
| --- | --- | --- |
| First timeout (will retry) | ✅ `warning` | `provider`, `retry_attempt=1`, `timeout_ms` |
| Final timeout (no retry) | ✅ `error` | `provider`, `trace_id`, `connection_id`, `outcome=failure` |

---

## 13. Anti-patterns

| Anti-pattern | Why it fails | Correct approach |
| --- | --- | --- |
| **Huge payloads** | Cost, index bloat, secret leakage risk | Log IDs and status; truncate summaries to ≤ 256 chars |
| **Logging entire objects** | `$schedule`, `$user` dump secrets and PII | Explicit allowlist of fields |
| **Logging request bodies** | Passwords, tokens, PII in JSON body | Log route + validation errors by field name |
| **Logging credentials** | ADR-030 violation; Collector drops but audit fails | Never emit — use boolean flags |
| **Duplicate logs** | Same failure logged in middleware, controller, and job | One log at the boundary that owns the outcome |
| **Log spam** | Every iteration, poll, or cache access | Log on state change; metric for volume |
| **Exception swallowing** | Silent failures — no metric, no log | Re-throw or log at `error` with `exception_class` |
| **Logging every success** | Drowns Loki; duplicates metrics | Counter increment only |
| **Logging inside loops** | 1 000 devices → 1 000 log lines per sync | Log summary: `{devices_synced=980, devices_failed=20}` |
| **Plain text logs** | Unqueryable in Loki; regex fragility | JSON structured records |
| **Dynamic message keys** | `{ "user_123_failed": true }` | Stable keys; variable values |
| **Using logs as audit trail** | 14-day retention; no integrity guarantees | Domain audit tables for compliance |
| **Debug logs in production** | Volume + accidental secret exposure | `debug` disabled; feature-flagged locally |

---

## 14. Review checklist

Before adding or changing a log statement in an instrumentation PR, answer every question:

| # | Question | If "no" or "yes" wrongly… |
| --- | --- | --- |
| 1 | **Can an existing log pattern cover this?** | Reuse message template and fields — do not invent a parallel format. |
| 2 | **Should this be a metric instead?** | Routine success, rates, latency → Prometheus. |
| 3 | **Should this be a trace/span event instead?** | Workflow milestone inside an active trace → span event. |
| 4 | **Is this on a hot path?** | Remove or downgrade to `debug` — success on hot paths is usually noise. |
| 5 | **Does the log answer a real investigation question?** | Remove "nice to have" logs. |
| 6 | **Are all fields on the allowlist?** | See §6 and [telemetry-naming-convention.md §9](telemetry-naming-convention.md). |
| 7 | **Does it expose forbidden data?** | Remove — see §7 and [ADR-030](../decisions/ADR-030-observability-security-and-privacy.md). |
| 8 | **Is `trace_id` included when a span is active?** | Add — required for correlation. |
| 9 | **Is the message stable and the data in fields?** | Refactor concatenated strings to structured fields. |
| 10 | **Is the level correct?** | See §5 — do not use `error` for expected validation skips. |
| 11 | **Will this log at high frequency in production?** | Aggregate, sample, or metric-only. |
| 12 | **Does it duplicate a metric fact without adding detail?** | Remove the log or add investigation context. |

Also verify: signal choice per [telemetry-decision-guide.md](telemetry-decision-guide.md); metric overlap per [metrics-philosophy.md §9](metrics-philosophy.md); feature design per [feature-design-checklist.md](feature-design-checklist.md) observability questions.

---

## Cross-references

| Document | Relationship |
| --- | --- |
| [ADR-028](../decisions/ADR-028-observability-platform.md) | Collector-only ingestion — apps never write Loki |
| [ADR-029](../decisions/ADR-029-telemetry-data-model.md) | Log record structure, correlation IDs |
| [ADR-030](../decisions/ADR-030-observability-security-and-privacy.md) | Forbidden fields — mandatory reading |
| [ADR-031](../decisions/ADR-031-retention-storage-and-cost-control.md) | 14-day log retention; volume discipline |
| [metrics-philosophy.md](metrics-philosophy.md) | Complementary guide — when metrics beat logs |
| [telemetry-naming-convention.md](telemetry-naming-convention.md) | Field names, levels, structured schema §9 |
| [telemetry-decision-guide.md](telemetry-decision-guide.md) | Signal choice tree |
| [observability-playbook.md](../operations/observability-playbook.md) | Investigation workflow — metrics → traces → logs |
| [security-review.md](../specs/observability-foundation/mvp/security-review.md) | Threat model, redaction policy |
| [collector-validation-report.md](../specs/observability-foundation/mvp/collector-validation-report.md) | Collector redaction processor validation |
| [loki-deployment.md](../specs/observability-foundation/mvp/loki-deployment.md) | Loki backend — not a logging tutorial |
| [telemetry-availability-policy.md](telemetry-availability-policy.md) | Export must not block business logic |
| [observability-operational-limits.md](observability-operational-limits.md) | Ingestion and query limits |
| [specs/observability-foundation/mvp/spec.md](../specs/observability-foundation/mvp/spec.md) | Feature specification and roadmap |
