# ADR-029: Telemetry data model

## Status

**Accepted** — defines the **official Ixora telemetry model** ([ADR-028](ADR-028-observability-platform.md), [`specs/observability-foundation/mvp/spec.md`](../specs/observability-foundation/mvp/spec.md)).

## Date

2026-07-05

---

## Context

Without a shared data model, each repository invents its own log fields, metric names, and trace attributes. That prevents cross-service correlation (e.g. linking a scheduler tick → Smart Home job → push failure) and causes cardinality explosions in Prometheus.

Ixora already has:

- Structured Laravel logs (`Log::warning` with context arrays)
- Notification event taxonomy ([ADR-019](ADR-019-notification-event-taxonomy.md))
- Async orchestration layers ([ADR-027](ADR-027-asynchronous-orchestration-pattern.md))

Observability must **extend** these conventions — not replace product semantics.

---

## Decision

### Signal types

| Signal | Purpose | Primary use in Ixora |
| --- | --- | --- |
| **Metrics** | Aggregated numeric measurements over time | HTTP latency, queue depth, scheduler tick duration, job success rate |
| **Logs** | Discrete timestamped events with context | Warnings, errors, dispatch summaries, export failures |
| **Traces** | Request/workflow spans with parent-child hierarchy | HTTP request → service → job → provider HTTP |
| **Events** | Named occurrences with attributes (OTel log record or span event) | `schedule.dispatched`, `smart_home.action_failed`, `push.queued` |

**Rule:** Prefer **traces** for workflow timing; **metrics** for SLO dashboards; **logs** for diagnosable detail; **events** for domain milestones inside a span.

### What belongs in each signal

#### Metrics

| Belongs | Does not belong |
| --- | --- |
| Counters: requests, jobs processed, push attempts | Raw request bodies |
| Histograms: HTTP duration, job duration, HA round-trip | Per-user counters as high-cardinality labels |
| Gauges: queue size, active workers | Secrets, tokens, emails |
| Labels: `service`, `environment`, `http.route`, `job.name`, `queue`, `outcome` | Unbounded `user_id` as label (use logs/traces) |

**Examples:**

| Metric (semantic name) | Type | Labels |
| --- | --- | --- |
| `ixora.http.server.duration` | Histogram | `http.method`, `http.route`, `http.status_code` |
| `ixora.scheduler.dispatch.duration` | Histogram | `outcome` (`dispatched`, `skipped_duplicate`, `failed`) |
| `ixora.smart_home.action.duration` | Histogram | `action_type`, `outcome` |
| `ixora.push.delivery.total` | Counter | `event_type`, `outcome` |
| `ixora.queue.jobs.processed.total` | Counter | `queue`, `job`, `outcome` |

#### Logs

| Belongs | Does not belong |
| --- | --- |
| Human-readable message + structured attributes | Full SQL with PII |
| `trace_id`, `span_id` for correlation | Firebase ID tokens, HA access tokens |
| Domain IDs: `schedule_id`, `vibe_id`, `user_id` (integer) | Passwords, API keys, push token values |
| `exception_class`, sanitized `error` message | Stack traces with env secrets in args |

**Examples:**

```
Schedule Smart Home dispatch skipped: validation failed.
  schedule_id=42 vibe_id=7 user_id=123 validator_failed=true trace_id=abc...

SmartHomeActionJob: action execution failed.
  device_id=5 vibe_id=7 action_type=turn_off exception_class=ProviderException trace_id=def...
```

#### Traces

| Belongs | Does not belong |
| --- | --- |
| Span per HTTP request, job handle, provider call | Full HTTP response bodies from HA |
| Parent-child: `DispatchDueSchedulesCommand` → `SmartHomeActionJob` → `HomeAssistantAdapter` | Credential headers |
| Attributes: route, job class, queue, schedule_id | Raw FCM payload |

**Example trace tree:**

```
HTTP POST /api/schedules
  └── SmartHomeActionJob (async)
        └── HomeAssistantAdapter.executeAction
```

#### Events (span events or structured log events)

| Event name | When |
| --- | --- |
| `schedule.execution.created` | New `ScheduleExecution` row committed |
| `schedule.smart_home.skipped` | Validator returned false |
| `smart_home.action.dispatched` | Job enqueued |
| `smart_home.action.completed` | Provider returned success |
| `push.notification.queued` | `PushNotificationJob` dispatched |
| `telemetry.export.failed` | OTLP export to Collector failed (non-fatal) |

### Correlation IDs

| ID | Scope | Propagation |
| --- | --- | --- |
| **`trace_id`** | Single distributed workflow | W3C `traceparent` on HTTP; injected into Laravel log context; passed to queue jobs via serialized context |
| **`span_id`** | Single operation within trace | OTel automatic |
| **`request_id`** | Single HTTP request (optional alias) | Same as root span id or separate header `X-Request-Id` — must map to trace |
| **Domain IDs** | Product entities | `schedule_id`, `vibe_id`, `user_id`, `device_id` as **span/log attributes** — not metric labels unless aggregated |

**Correlation rule:** Any log line emitted during an HTTP request or job **must** include `trace_id` when a trace is active.

**Cross-signal query (Grafana):** `trace_id` links Tempo trace ↔ Loki logs ↔ Prometheus exemplars (post-MVP).

### Standard resource attributes

Every signal MUST include:

| Attribute | Example | Required |
| --- | --- | --- |
| `service.name` | `back_vibes-api`, `back_vibes-worker`, `front_vibes-android` | ✅ |
| `service.version` | git tag or app version | ✅ |
| `deployment.environment` | `staging`, `production` | ✅ |
| `telemetry.sdk.language` | `php`, `javascript` | ✅ (OTel default) |

### Semantic naming conventions

Follow [OpenTelemetry semantic conventions](https://opentelemetry.io/docs/specs/semconv/) where applicable. Ixora-specific names use prefix **`ixora.`**.

| Convention | Rule |
| --- | --- |
| **Metric names** | Dot-separated lowercase: `ixora.<domain>.<metric>` |
| **Span names** | `ClassName.method` or `HTTP METHOD route` — stable, low cardinality |
| **Log keys** | snake_case: `schedule_id`, `exception_class` |
| **Event names** | Dot-separated domain verbs: `schedule.execution.created` |
| **Units** | Explicit on metrics: `ms`, `s`, `{job}`, `{request}` |
| **Boolean outcomes** | Label value `success` / `failure` — not `true`/`false` strings mixed |

### Failure policy (telemetry export)

| Scenario | Application behaviour |
| --- | --- |
| Collector unreachable | Log locally (stderr); **do not** block HTTP response or job completion |
| OTLP timeout | Drop batch; increment `ixora.telemetry.export.failed.total` if SDK supports it |
| Invalid attribute rejected by Collector | Fix in next release — app continues |

> Observability failures **never** block business logic — mirrors [ADR-020](ADR-020-push-delivery-and-fallback-strategy.md) and [ADR-023](ADR-023-automation-execution-order-and-failure-policy.md).

---

## Consequences

### Positive

- Engineers can trace scheduler → Smart Home → push in one workflow.
- Dashboards and alerts (future) use consistent metric names.
- Mobile and backend share `trace_id` when mobile calls API (future header propagation).

### Negative

- SDK instrumentation work in Phases 7–8.
- Strict naming requires code review discipline.

### Related ADRs

- [ADR-019](ADR-019-notification-event-taxonomy.md) — push event names align with `push.notification.*` events
- [ADR-024](ADR-024-automation-notifications-and-observability.md) — product observability complements platform telemetry
- [ADR-028](ADR-028-observability-platform.md) — Collector enforces model at ingest
- [ADR-030](ADR-030-observability-security-and-privacy.md) — forbidden fields
- [ADR-031](ADR-031-retention-storage-and-cost-control.md) — cardinality and sampling
