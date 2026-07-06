# Telemetry Decision Guide

**Status:** Active architecture guide  
**ADRs:** [ADR-028](../decisions/ADR-028-observability-platform.md) · [ADR-029](../decisions/ADR-029-telemetry-data-model.md) · [ADR-030](../decisions/ADR-030-observability-security-and-privacy.md) · [ADR-031](../decisions/ADR-031-retention-storage-and-cost-control.md)  
**Complements:** [`telemetry-naming-convention.md`](telemetry-naming-convention.md) · [`specs/observability-foundation/mvp/spec.md`](../specs/observability-foundation/mvp/spec.md) · [`operations/observability-playbook.md`](../operations/observability-playbook.md)  
**Applies to:** All engineers instrumenting `back_vibes`, `front_vibes`, or observability stack components

> **Rule of thumb:** Naming tells you **what to call it** ([telemetry-naming-convention.md](telemetry-naming-convention.md)). This guide tells you **which signal to emit** — and when **not** to emit one.

---

## 1. Purpose

[`telemetry-naming-convention.md`](telemetry-naming-convention.md) is the single source of truth for **how** telemetry is named. This document answers **when** to use each signal type:

| Question | Answer in |
| --- | --- |
| Metric, Counter, Histogram, Gauge, or UpDownCounter? | §3 |
| New trace, child span, or provider span? | §4 |
| Span event vs nested span? | §5 |
| Structured log vs trace attribute? | §6–§7 |
| Metric label vs span attribute? | §7 |
| Dashboard or alert? | §2 decision tree |

**Mandatory:** Instrumentation PRs must satisfy **both** this guide (signal choice) and the naming convention (artifact names). Deviations require an ADR amendment or spec exception.

This document plays the same architectural role as [`domain-validation.md`](domain-validation.md), [`asynchronous-orchestration.md`](asynchronous-orchestration.md), and [`telemetry-naming-convention.md`](telemetry-naming-convention.md).

---

## 2. Decision tree

Start with **what you need to know**, not what OpenTelemetry can export.

```
"I want to..."
```

### Count occurrences (how many times X happened)

```
Counter
```

Examples: schedule executions, push deliveries, HTTP 5xx responses, failed Smart Home actions.

→ Metric: `ixora.*.total` with `outcome` label. See [telemetry-naming-convention.md §5](telemetry-naming-convention.md).

---

### Measure latency or distribution (how long X takes)

```
Histogram
```

Examples: HTTP request duration, `SmartHomeActionJob.handle` duration, mobile screen load time.

→ Metric: `ixora.*.duration`. **Not** a Gauge sampled once per request.

---

### Track a value that goes up and down (current depth / in-flight)

```
UpDownCounter
```

Examples: queue depth, active HTTP connections, in-flight provider calls.

→ Use sparingly; prefer Counter + Histogram for most Ixora flows.

---

### Point-in-time snapshot (memory, cache size right now)

```
Gauge
```

Examples: JVM/PHP memory, Collector queue size. Rare in product code — prefer infrastructure metrics.

---

### Investigate one execution end-to-end

```
Trace (root span + child spans)
```

Examples: one HTTP request, one scheduler tick processing a schedule, one queue job run.

→ Create spans per layer ([asynchronous-orchestration.md](asynchronous-orchestration.md)). Correlate logs with `trace_id`.

---

### Annotate a milestone inside an existing operation

```
Span Event
```

Examples: `schedule.execution.completed`, `push.notification.sent`.

→ Event on the **current span** — not a new trace. See §5.

---

### Capture investigation detail (stack trace, retry context, payload summary)

```
Structured Log
```

Examples: exception stack, validator failure reason, HA response body summary (sanitized).

→ Include `trace_id` when a span is active. See §6.

---

### Attach context to one operation (IDs, outcome, route)

```
Span Attributes
```

Examples: `schedule.id`, `device.id`, `outcome`, `http.route`.

→ High-cardinality IDs belong **here**, not on metric labels.

---

### Filter or group aggregates on a dashboard

```
Metric Labels (low cardinality only)
```

Examples: `environment`, `outcome`, `queue`, `notification_type`.

→ Never `user_id`, `schedule_id`, or `trace_id`. See [telemetry-naming-convention.md §8](telemetry-naming-convention.md).

---

### Surface a recurring operational question

```
Dashboard panel
```

Examples: API p95 latency, scheduler failure rate, queue backlog.

→ Built on metrics from §3. Naming: [telemetry-naming-convention.md §11](telemetry-naming-convention.md).

---

### Notify when a condition persists (post-MVP)

```
Alert
```

Examples: high 5xx rate, Collector down, disk almost full.

→ Reserved naming in [telemetry-naming-convention.md §12](telemetry-naming-convention.md). Alerts follow dashboards — do not alert on raw logs.

---

## 3. Metric decision guide

| Instrument | Use when | Do not use when |
| --- | --- | --- |
| **Counter** | Something happened; count only increases | You need current queue depth |
| **Histogram** | Latency, size, duration distributions | You only need latest value |
| **UpDownCounter** | Active count changes up/down | A Counter + separate gauge would suffice and is simpler |
| **Gauge** | Instantaneous resource reading | Per-request latency (use Histogram) |

### Ixora examples by domain

| Domain | Counter | Histogram | UpDownCounter / Gauge |
| --- | --- | --- | --- |
| **HTTP** | `ixora.http.server.total` (optional; rate from histogram count) | `ixora.http.server.duration` | — |
| **Scheduler** | `ixora.scheduler.execution.total{outcome=*}` | `ixora.scheduler.dispatch.duration` | — |
| **Smart Home** | `ixora.smart_home.action.total{outcome=*}` | `ixora.smart_home.action.duration` | — |
| **Push** | `ixora.push.delivery.total{notification_type=*,outcome=*}` | — (duration optional post-MVP) | — |
| **Queue** | `ixora.queue.job.total{queue=*,outcome=*}` | `ixora.queue.job.duration` | UpDownCounter: in-flight jobs (if needed) |
| **Mobile** | Error counts (bounded labels) | `ixora.mobile.screen.duration`, `ixora.mobile.network.duration` | — |

**One metric, many outcomes:** Prefer `outcome=success|failure|skipped` label — not three separate metric names.

**SLO metrics:** HTTP p95 and error rate come from **Histogram + Counter**, not from logging every request.

---

## 4. Trace decision guide

Traces answer: **What happened in this one workflow, in order, and how long did each step take?**

### When to create a new root trace

| Trigger | Root span | Service |
| --- | --- | --- |
| Incoming HTTP request | `GET /api/v1/...` | `back_vibes-api` |
| Scheduler tick | `DispatchDueSchedulesCommand.handle` | `back_vibes-worker` |
| Queue job picked up | `{JobClass}.handle` | `back_vibes-worker` |
| Mobile screen session | `screen.{ScreenName}` | `front_vibes-android` |

Each root trace gets a new `trace_id`. Async jobs **may** start a new root trace or continue context if propagated — default for Ixora queue jobs: **new root trace per job** unless explicit parent context is passed.

### When to create a child span

| Layer | Span name | Parent |
| --- | --- | --- |
| Controller / entrypoint | HTTP route or command | Root |
| Domain service | `{ServiceClass}.{method}` | Entry span |
| Validator | `ScheduleAutomationValidator.validate` | Dispatch span |
| Job handle | `SmartHomeActionJob.handle` | Root (job) |
| Nested service call | `VibeSmartHomeDispatchService.dispatch` | Job or command span |

Follow [asynchronous-orchestration.md](asynchronous-orchestration.md): entrypoint → validator → service → job → provider.

### When to create a provider span

| Provider call | Span | Attributes |
| --- | --- | --- |
| Home Assistant REST | `HomeAssistantAdapter.executeAction` | `provider.name`, `device.id`, `action_type`, `outcome` |
| FCM send | `FcmPushProvider.send` | `notification.type`, `outcome` |
| External HTTP | `{Adapter}.{method}` | `http.status_code`, `outcome` |

Provider spans are **always children** of the job or service span that invoked them.

### When to create a queue span

| Situation | Approach |
| --- | --- |
| Job execution | One root span `{JobClass}.handle` — sufficient for MVP |
| Enqueue only | Optional child span on dispatch span — defer unless debugging enqueue latency |
| Queue wait time | Metric (`ixora.queue.job.duration`) — not a span waiting idle |

### When to create a mobile navigation span

| Situation | Span |
| --- | --- |
| Screen load | `screen.SchedulesPage` |
| API call from app | Child span under screen — `GET /api/v1/schedules` |
| Push tap handling | Short root or child under app session span |

Mobile: sample aggressively ([ADR-031](../decisions/ADR-031-retention-storage-and-cost-control.md)); trace errors and critical paths first.

---

## 5. Events

**Span events** mark **discrete moments** inside a span. They are cheaper than nested spans when you only need a timestamp + name, not duration.

### Event vs nested span

| Prefer **event** | Prefer **nested span** |
| --- | --- |
| Milestone with no meaningful duration | Operation with measurable duration (HTTP, HA call) |
| State transition (`execution.completed`) | Sub-operation you need latency for |
| Notification handoff (`notification.queued`) | Provider round-trip |

### Official Ixora events

| Event | Span context | Why event, not new span |
| --- | --- | --- |
| `schedule.execution.completed` | `DispatchDueSchedulesCommand.handle` | Milestone after DB commit |
| `schedule.execution.failed` | Same | Terminal state marker |
| `smart_home.action.dispatched` | Dispatch or job span | Job enqueued — instant |
| `smart_home.action.failed` | `SmartHomeActionJob.handle` | Outcome marker before log |
| `push.notification.sent` | `FcmPushProvider.send` | FCM accept/reject moment |
| `http.request.completed` | HTTP server span | Response sent |

Events use dot notation — see [telemetry-naming-convention.md §10](telemetry-naming-convention.md).

---

## 6. Logs

Structured logs answer: **What exactly went wrong, with enough detail to fix it?**

### When something belongs **only** in logs

| Content | Log | Not metric | Not span attribute |
| --- | --- | --- | --- |
| Stack trace | ✅ `exception_class` + message | ❌ | ❌ full stack on span |
| Validation failure message | ✅ human-readable `message` | ❌ unbounded label | Optional short `outcome` on span |
| Provider payload summary (sanitized) | ✅ truncated body | ❌ | ❌ raw payload on span |
| Retry attempt N of M | ✅ structured fields | Counter optional | Event optional |
| Debug breadcrumbs | ✅ `debug` level only | ❌ | ❌ |

### When to log **and** emit other signals

| Situation | Log | Trace | Metric |
| --- | --- | --- | --- |
| Smart Home action failed | Warning + `trace_id`, `device_id` | Span `outcome=failure` | `ixora.smart_home.action.total{outcome=failure}` |
| Schedule dispatch skipped | Info + validator reason | Span + event `schedule.smart_home.skipped` | Counter `outcome=skipped` |
| HTTP 502 | Error log | HTTP span | Histogram + status label |

**Always** inject `trace_id` / `span_id` when instrumented ([ADR-029](../decisions/ADR-029-telemetry-data-model.md)).

**Never** log secrets, tokens, emails, or full HA tokens ([ADR-030](../decisions/ADR-030-observability-security-and-privacy.md)).

---

## 7. Attributes, labels, and log fields

Three ways to attach context — each with different cardinality rules and consumers.

### Comparison table

| Aspect | Span attribute | Metric label | Structured log field |
| --- | --- | --- | --- |
| **Purpose** | Context for one operation | Group/filter aggregates | Human investigation detail |
| **Cardinality** | IDs allowed (`schedule.id`) | **Low only** — bounded enums | IDs allowed (`schedule_id`) |
| **Naming** | Dot notation (`schedule.id`) | snake_case (`outcome`, `queue`) | snake_case (`schedule_id`) |
| **Consumer** | Tempo, trace UI | Prometheus, Grafana | Loki |
| **Example** | `device.id=5` on provider span | `outcome=failure` on counter | `"device_id": 5` in JSON log |
| **Forbidden** | Secrets, email | `user_id`, `trace_id`, `schedule_id` | Passwords, tokens |

### Decision rule

```
Is it needed to GROUP metrics on a dashboard?
  YES → low-cardinality metric label (§8 naming guide)
  NO  → Is it tied to ONE request/job?
          YES → span attribute (+ same ID in log field if debugging)
          NO  → log only
```

---

## 8. Decision matrix

| Situation | Telemetry type | Reason |
| --- | --- | --- |
| API latency SLO | Histogram `ixora.http.server.duration` | Percentiles across all requests |
| Count of failed schedule executions | Counter + `outcome=failure` | Aggregate failure rate |
| Why schedule 42 failed once | Trace + logs with `schedule_id` | ID on span/log — not metric label |
| HA call took 8 s | Provider span + Histogram | Span for one run; histogram for trend |
| Push accepted by FCM | Event `push.notification.sent` | Instant milestone on provider span |
| FCM returned 401 | Structured log + span `outcome=failure` | Detail in log; aggregate via counter |
| Queue backing up | UpDownCounter or infra metric | Current depth — not per-job counter |
| User 123 had slow request | Trace in Tempo (sampled) | Never `user_id` label on metric |
| Dashboard: failures by notification type | Counter + `notification_type` label | Bounded enum from ADR-019 |
| Collector export errors | Counter `ixora.telemetry.export.failed.total` | Platform health — not business log spam |
| Mobile screen slow on one device | Trace (sampled) + Histogram | Device ID in span/log only |
| Disk filling on observability VM | Infrastructure Gauge + alert (post-MVP) | Not application Counter |

---

## 9. Common mistakes

| Mistake | Fix |
| --- | --- |
| **Everything becomes a log** | Add metrics for SLOs; traces for workflows; logs for detail |
| **Everything becomes a metric** | Metrics aggregate; do not metric individual IDs |
| **Every exception creates a trace** | One trace per workflow; exception on existing span + log |
| **User IDs as labels** | `user.id` span attribute only ([ADR-030](../decisions/ADR-030-observability-security-and-privacy.md)) |
| **High-cardinality attributes on metrics** | Move IDs to spans/logs ([ADR-031](../decisions/ADR-031-retention-storage-and-cost-control.md)) |
| **Duplicate signals** | Same fact as Counter + log line + event — pick metric + one of log/event |
| **Span per log line** | Logs are not spans |
| **Dynamic metric names** | One metric + labels |
| **Logging without `trace_id`** | Breaks Loki → Tempo correlation |
| **Histogram for queue depth** | Use UpDownCounter or Gauge |
| **Alert on every error log** | Alert on metric thresholds |

---

## 10. Relationship with platform documents

| Document | Role relative to this guide |
| --- | --- |
| [ADR-028](../decisions/ADR-028-observability-platform.md) | **Where** signals go — Collector only; defines stack components |
| [ADR-029](../decisions/ADR-029-telemetry-data-model.md) | **What** signals exist — traces, metrics, logs, events, correlation |
| [ADR-030](../decisions/ADR-030-observability-security-and-privacy.md) | **What not to emit** — informs §6–§7 forbidden fields |
| [ADR-031](../decisions/ADR-031-retention-storage-and-cost-control.md) | **How much** — sampling, cardinality caps; prefer metrics over verbose traces |
| [telemetry-naming-convention.md](telemetry-naming-convention.md) | **Names** — apply after choosing signal type here |
| [asynchronous-orchestration.md](asynchronous-orchestration.md) | **Span layering** — where traces attach in async flows |
| [observability-playbook.md](../operations/observability-playbook.md) | **Operations** — how to investigate using signals chosen here |

---

## Review checklist

Before merging instrumentation PRs:

- [ ] Signal type chosen per this guide (not "default to log")
- [ ] Names follow [telemetry-naming-convention.md](telemetry-naming-convention.md)
- [ ] No high-cardinality metric labels
- [ ] Logs include `trace_id` when span active
- [ ] No secrets or PII ([ADR-030](../decisions/ADR-030-observability-security-and-privacy.md))
- [ ] Cardinality within ADR-031 budgets
