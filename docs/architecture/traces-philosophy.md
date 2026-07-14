# Traces Philosophy

**Status:** Active architecture guide  
**ADRs:** [ADR-028](../decisions/ADR-028-observability-platform.md) · [ADR-029](../decisions/ADR-029-telemetry-data-model.md) · [ADR-030](../decisions/ADR-030-observability-security-and-privacy.md) · [ADR-031](../decisions/ADR-031-retention-storage-and-cost-control.md)  
**Complements:** [`metrics-philosophy.md`](metrics-philosophy.md) · [`logs-philosophy.md`](logs-philosophy.md) · [`telemetry-naming-convention.md`](telemetry-naming-convention.md) · [`telemetry-decision-guide.md`](telemetry-decision-guide.md) · [`specs/observability-foundation/mvp/tempo-deployment.md`](../specs/observability-foundation/mvp/tempo-deployment.md) · [`operations/observability-playbook.md`](../operations/observability-playbook.md)  
**Applies to:** All engineers instrumenting `back_vibes`, `front_vibes`, or observability stack components — **mandatory before Phases 7 and 8 (application instrumentation)**

> **Rule of thumb:** This document defines **how engineers think about traces**. It is not a Tempo manual, an OpenTelemetry tutorial, or a naming reference. For span names and attribute spelling, see [telemetry-naming-convention.md §6–§7](telemetry-naming-convention.md). For signal choice (trace vs metric vs log), see [telemetry-decision-guide.md §4](telemetry-decision-guide.md). For Tempo deployment and retention, see [tempo-deployment.md](../specs/observability-foundation/mvp/tempo-deployment.md).

---

## 1. Purpose of tracing

Traces exist to answer **what happened in one workflow, in what order, and how long each step took** — across HTTP requests, queue jobs, scheduler ticks, provider calls, and mobile sessions.

| Signal | What it captures | Time horizon |
| --- | --- | --- |
| **Traces** | Workflow structure — one execution, step by step | Single request or job run (7 days in MVP) |
| **Metrics** | Aggregated measurements — counts, rates, distributions | Continuous trends (30 days in MVP) |
| **Logs** | Discrete events with context — one record per occurrence | Point-in-time detail (14 days in MVP) |
| **Events** | Named moments inside a span or log stream | Attached to a trace or log record |

### Why traces are different from metrics

Metrics answer: **How often does this happen? Is latency rising across all requests?** Traces answer: **Which step in this one execution was slow? Did the scheduler tick dispatch three jobs or one?**

You cannot reconstruct a single workflow from Prometheus alone — sampling drops most successful traces ([ADR-031](../decisions/ADR-031-retention-storage-and-cost-control.md)), and metrics aggregate away individual paths. Traces preserve parent-child structure and per-step duration for **one** `trace_id`.

### Why traces are different from logs

Logs answer: **What did the application observe or decide at a point in time?** Traces answer: **How did operations relate in time and hierarchy?**

A log at `level=error` explains that Home Assistant returned HTTP 503. The trace shows that `SmartHomeActionJob.handle` waited 4.2 s inside `HomeAssistantAdapter.executeAction` before failing — without duplicating every decision as a log line.

### Why traces are different from events

**Span events** mark a moment inside a span — e.g. `schedule.execution.completed`. **Spans** represent operations with measurable duration. Events are cheaper annotations; spans are the workflow graph.

### The core idea

> Traces describe **one logical execution** — not system trends, not arbitrary text dumps, and not every function call.

Observability Foundation Phases 1–6 established **what** the platform collects ([ADR-028](../decisions/ADR-028-observability-platform.md)), **how signals relate** ([ADR-029](../decisions/ADR-029-telemetry-data-model.md)), **what must never be exported** ([ADR-030](../decisions/ADR-030-observability-security-and-privacy.md)), **retention and sampling** ([ADR-031](../decisions/ADR-031-retention-storage-and-cost-control.md)), and **where traces are stored** ([tempo-deployment.md](../specs/observability-foundation/mvp/tempo-deployment.md)). This guide establishes **how engineers decide what deserves a span** — before Phases 7 and 8 add instrumentation to `back_vibes` and `front_vibes`.

---

## 2. Core principles

These principles govern every trace decision at Ixora.

| Principle | Meaning |
| --- | --- |
| **Workflow visibility** | A trace should let an engineer see the full path of one operation — entrypoint through jobs to providers — without reading code. |
| **Cause and effect** | Parent-child spans express causality: the HTTP request caused a job; the job caused a provider call. Sibling spans express parallelism. |
| **Distributed execution** | Traces link work across processes (`back_vibes-api` → `back_vibes-worker` → Home Assistant) via propagated `trace_id` / W3C `traceparent`. |
| **Correlation** | `trace_id` is the primary key linking Tempo ↔ Loki ↔ (future) Prometheus exemplars. Logs emitted during a span **must** include `trace_id`. |
| **Spans are scarce** | Each span consumes ingest, storage, and operator attention. Instrument boundaries — not internals. |
| **Spans are not logs** | Do not create a span per log line. Use span events for milestones; logs for textual detail. |
| **Spans are not metrics** | Do not use spans to compute rates or percentiles — use histograms. Traces complement metrics; they do not replace them. |
| **Spans must be safe** | No credentials, tokens, emails, or raw payloads on attributes ([ADR-030](../decisions/ADR-030-observability-security-and-privacy.md)). |
| **Spans respect sampling** | Not every successful request is stored. Design for metrics + logs when the trace is missing. |

**Depth is a design decision.** A trace tree with 50 spans per HTTP request overwhelms Tempo and obscures the workflow. Default to **one root span per entrypoint** plus **one child per meaningful boundary** (validator, service, job, provider).

---

## 3. When to create spans

Create a span when an engineer investigating **one execution** needs to know **which step ran, how long it took, and what it depended on**.

| Scenario | Span type | Example span name | Service |
| --- | --- | --- | --- |
| **HTTP requests** | Root | `POST /api/v1/schedules` | `back_vibes-api` |
| **Queue jobs** | Root (per job) | `SmartHomeActionJob.handle` | `back_vibes-worker` |
| **Scheduler** | Root (per tick) | `DispatchDueSchedulesCommand.handle` | `back_vibes-worker` |
| **Automation execution** | Child under dispatch | `VibeSmartHomeDispatchService.dispatch` | `back_vibes-worker` |
| **Smart Home** | Child under job | `HomeAssistantAdapter.executeAction` | `back_vibes-worker` |
| **Push notifications** | Root or child | `PushNotificationJob.handle`, `FcmPushProvider.send` | `back_vibes-worker` |
| **Background jobs** | Root | `{JobClass}.handle` | `back_vibes-worker` |
| **External APIs** | Child under caller | `HomeAssistantAdapter.executeAction`, `FcmPushProvider.send` | `back_vibes-worker` |
| **Mobile navigation** | Root or child | `screen.SchedulesPage` | `front_vibes-android` |

Follow [asynchronous-orchestration.md](asynchronous-orchestration.md): **entrypoint → validator → service → job → provider**. Each layer is a span candidate when it has measurable duration or distinct failure semantics.

**Test:** Would an on-call engineer looking at **this one failure** need to see step-by-step timing and hierarchy? If yes, span it. If the answer is already on a Grafana panel as a trend, use a metric instead.

---

## 4. When NOT to create spans

Do not create spans when the operation is **trivial**, **internal**, **already captured**, or **better as a metric, log, or event**.

| Do not span | Why | Use instead |
| --- | --- | --- |
| **Tiny helper methods** | Noise; no operational boundary | Inline in parent span duration |
| **Getters / accessors** | No meaningful duration | Parent span attribute if needed |
| **Pure calculations** | No I/O; microseconds | Parent span — or omit |
| **Loops over entities** | 1 000 devices → 1 000 spans | One provider span per batch; metric for count |
| **Repositories / Eloquent** | ORM noise at scale | Optional single `db.query` span in debug only — not MVP default |
| **Every function** | Unreadable trace trees | Span at architectural boundaries only |
| **Validation that returns instantly** | Sub-millisecond | Span event on parent — e.g. `schedule.smart_home.skipped` |
| **Queue wait time** | Idle time, not work | Metric `ixora.queue.job.duration` includes wait if measured at job level |
| **Routine success logging** | Duplicates metric | Counter increment only |
| **Business payloads** | Size + secret risk | Entity IDs on attributes; detail in sanitized logs |

**Why metrics are more appropriate:** Success rates, p95 latency, and queue throughput require aggregation across thousands of executions. Histograms capture every request; traces sample most successes away.

**Why logs are more appropriate:** Exception messages, validator reasons, and provider response summaries need searchable text. A span status `ERROR` points to the step; the log explains why.

See [telemetry-decision-guide.md §4–§5](telemetry-decision-guide.md) for the full signal choice tree.

---

## 5. Span hierarchy

A **trace** is a tree of **spans** sharing one `trace_id`. Spans express **who called whom** and **how long each step took**.

### Root span

The **root span** is the entrypoint of a workflow — the first operation that starts a new `trace_id`.

| Trigger | Root span | Notes |
| --- | --- | --- |
| Incoming HTTP | `GET /api/v1/...` | Auto-instrumented in Phase 7 |
| Scheduler tick | `DispatchDueSchedulesCommand.handle` | One root per cron invocation |
| Queue job picked up | `SmartHomeActionJob.handle` | **Default: new root trace per job** unless parent context propagated |
| Mobile screen | `screen.SchedulesPage` | Sampled aggressively on mobile |

### Child span

A **child span** represents work **caused by** the parent — a service call, validator, nested job step, or provider round-trip.

```
POST /api/v1/schedules                    ← root (HTTP)
  └── VibeSmartHomeDispatchService.dispatch   ← child (service)
```

### Nested spans

**Nested spans** are children of children — arbitrary depth, but **keep depth shallow** (typically ≤ 4 levels in MVP).

```
DispatchDueSchedulesCommand.handle        ← root (scheduler)
  └── VibeSmartHomeDispatchService.dispatch   ← child
        └── ScheduleAutomationValidator.validate   ← nested child
```

Prefer **events** over deeper nesting when duration is not meaningful (see §7).

### Fan-out

**Fan-out** occurs when one parent span triggers **multiple parallel children** — e.g. one scheduler tick dispatches several Smart Home jobs.

```
DispatchDueSchedulesCommand.handle        ← root
  ├── SmartHomeActionJob.handle (schedule 42)   ← child (async — separate trace by default)
  ├── SmartHomeActionJob.handle (schedule 43)   ← child (separate trace)
  └── PushNotificationJob.handle                ← child (separate trace)
```

**Ixora default:** Enqueued jobs start **new root traces** unless explicit trace context is serialized into the job payload. The dispatch span records **that** jobs were enqueued (events + attributes); each job's execution is its own trace linked by `schedule.id` and time — not necessarily parent-child in Tempo.

### Fan-in

**Fan-in** occurs when **multiple upstream operations** contribute to one outcome — e.g. several device actions for one automation, or API middleware + controller both contributing to one HTTP response.

For HTTP, auto-instrumentation typically produces one root with middleware as optional children. For automations, **one dispatch span** with **multiple sequential or parallel job traces** is fan-in at the product level — correlate via `schedule.id`, `automation.id`, and timestamp in Grafana.

**Rule:** Fan-out/fan-in is a **product concept**. The trace tree shows **direct call hierarchy**; cross-trace correlation uses **shared attributes** and `trace_id` bridges in logs.

---

## 6. Span attributes

Attributes carry **context** on spans. Use **dot notation** on spans per [telemetry-naming-convention.md §7](telemetry-naming-convention.md). Logs use **snake_case** for the same entities — both refer to the same ID.

| Span attribute | Log field (when correlated) | When required | Purpose |
| --- | --- | --- | --- |
| `service.name` | `service.name` | Always (resource) | `back_vibes-api`, `back_vibes-worker`, `front_vibes-android` |
| `deployment.environment` | `deployment.environment` | Always (resource) | `staging`, `production` |
| `trace_id` | `trace_id` | Auto on span; required in logs | Cross-signal correlation |
| `span_id` | `span_id` | Auto on span; required in logs | Pinpoint log to span |
| `provider.name` | `provider` | Provider spans | `home_assistant`, `fcm` — bounded enum |
| `schedule.id` | `schedule_id` | Scheduler / automation flows | Which schedule was processed |
| `automation.id` | `automation_id` | Automation executions | Product automation row reference |
| `job.name` | `job` (class name) | Job spans | `SmartHomeActionJob` — bounded |
| `job.id` | `job_id` | Job spans (optional) | Laravel job UUID — per execution, not metric label |
| `device.id` | `device_id` | Smart Home spans | Target device integer ID |
| `request_id` | `request_id` | HTTP requests (optional) | Alias for root span or `X-Request-Id` header |
| `user.id` | `user_id` | When domain-relevant | Integer only — never email ([ADR-030](../decisions/ADR-030-observability-security-and-privacy.md)) |
| `queue.name` | `queue` | Job spans | `smart-home`, `push`, `default` |
| `http.route` | `http.route` | HTTP spans | Route template — not resolved URL |
| `http.method` | — | HTTP spans | `GET`, `POST`, … |
| `http.status_code` | — | HTTP spans | Set when response known |
| `outcome` | `outcome` | Domain results | `success`, `failure`, `skipped` |
| `exception.type` | `exception_class` | On failure | OTel convention — sanitized |
| `action_type` | — | Smart Home spans | `turn_on`, `turn_off`, `toggle` |
| `notification.type` | `notification_type` | Push spans | Per [ADR-019](../decisions/ADR-019-notification-event-taxonomy.md) |

Include attributes when context exists — do not emit empty placeholders. **Never** put unbounded or sensitive values on attributes (see §13).

High-cardinality IDs (`schedule.id`, `device.id`, `user.id`) belong on **span attributes** — acceptable in Tempo. They are **forbidden as Prometheus metric labels** ([ADR-031](../decisions/ADR-031-retention-storage-and-cost-control.md)).

---

## 7. Span events

**Span events** are timestamped annotations **on an existing span**. Use them when you need a **milestone** without a separate duration-bearing operation.

### When to use events instead of child spans

| Prefer **span event** | Prefer **child span** |
| --- | --- |
| Milestone with no meaningful duration | Operation with measurable duration (HTTP, HA call) |
| State transition after DB commit | Sub-operation you need latency for |
| Notification handoff (`push.notification.queued`) | Provider round-trip |
| Validator returned false (instant) | Validator that performs I/O |

### Official Ixora event examples

| Event | Span context | Why event, not span |
| --- | --- | --- |
| `schedule.execution.completed` | `DispatchDueSchedulesCommand.handle` | DB commit milestone — no separate duration |
| `schedule.execution.failed` | Same | Terminal state marker |
| `schedule.smart_home.skipped` | Dispatch or validator span | Validator outcome — instant |
| `smart_home.action.dispatched` | `VibeSmartHomeDispatchService.dispatch` | Job enqueued — handoff point |
| `push.notification.queued` | `PushNotificationJob.handle` | Job accepted by queue |
| `telemetry.export.failed` | SDK export span | Non-fatal export drop |

Full event list: [telemetry-naming-convention.md §10](telemetry-naming-convention.md).

**Do not** emit an event for every line you would have logged. Events mark **domain milestones** inside an active trace.

---

## 8. Exceptions

Failures must be visible in traces **and** logs — each signal serves a different purpose.

### Recording failures

| Mechanism | What to set |
| --- | --- |
| **Span status** | `ERROR` when the operation failed and affected outcome |
| **Span attributes** | `outcome=failure`, `exception.type`, sanitized `exception.message` |
| **Span event** | Optional `exception.recorded` with timestamp — if SDK pattern requires |
| **Log** | `level=error`, `exception_class`, `trace_id`, entity IDs — full investigation context |

Record the exception on the **span that owns the failure** — typically the provider span or job span, not every ancestor.

### Status

| Outcome | Span status | Metric | Log |
| --- | --- | --- | --- |
| Success | `OK` / unset | `outcome=success` | Usually none on hot path |
| Expected skip | `OK` / unset | `outcome=skipped` | Optional `warning` with reason |
| Failure | `ERROR` | `outcome=failure` | `error` with `trace_id` |

Do not set `ERROR` on parent spans unless the parent itself failed (e.g. unhandled exception in controller). A failed child provider span may leave the HTTP root span as `OK` with `http.status_code=502` — the error detail lives on the child.

### Error propagation

| Layer | Behaviour |
| --- | --- |
| **Provider** | Provider span `ERROR`; rethrow or return failure to job |
| **Job** | Job span `ERROR` if job fails after retries; log with `job_id`, `trace_id` |
| **HTTP** | Root span reflects `http.status_code`; 5xx → span `ERROR` |
| **Scheduler** | Dispatch span `ERROR` only on unhandled tick failure; per-schedule skips are events + `outcome=skipped` |

**Always** inject `trace_id` into Laravel log context when a span is active (Phase 7 requirement). Sampling may drop the trace for successful requests — logs with `request_id` provide a fallback correlation path.

---

## 9. Sampling

Trace volume is the highest among the three signals. Sampling is **mandatory** for cost control ([ADR-031](../decisions/ADR-031-retention-storage-and-cost-control.md)).

### Relationship with ADR-031

| Signal | MVP sampling policy | Configured in |
| --- | --- | --- |
| **Traces (backend)** | **10%** successful HTTP/jobs; **100%** errors (`http.status_code >= 500`, failed jobs) | Collector `probabilistic_sampler` |
| **Traces (mobile)** | **5%** success; **100%** crash / unhandled error spans | Collector — separate mobile pipeline |
| **Logs** | No sampling for `error` / `warning` | — |
| **Metrics** | No sampling | — |

Head sampling runs in the Collector **before** Tempo storage ([tempo-deployment.md §7](../specs/observability-foundation/mvp/tempo-deployment.md)). Tail sampling for guaranteed 100% error retention is documented as a **Phase 7+ evolution** — not MVP default.

### 100% errors

Engineers expect **every failed job and 5xx** to be traceable. ADR-031 mandates 100% error retention intent. Until tail sampling ships, rely on:

- Span `ERROR` status + metrics (`outcome=failure`)
- Logs with `trace_id` when span was sampled in
- `request_id` / `job_id` in logs when trace was dropped

Instrumentation must still **create spans for errors** even when sampling may drop them — the Collector policy evolves independently.

### Sample successes

Successful requests are **intentionally sparse** in Tempo. Use metrics for SLOs and latency percentiles; use sampled traces for **slow path debugging** and **workflow verification**.

### Why sampling exists

| Risk without sampling | Impact |
| --- | --- |
| Disk exhaustion | Tempo blocks consume ≤ 25% VM disk budget |
| Query noise | Trace search unusable at full traffic volume |
| Mobile cellular cost | OTLP export size on every screen navigation |

**Design implication:** Never assume a trace exists for a given successful request. Always emit metrics; emit logs on failure; propagate `trace_id` when present.

---

## 10. Relationship — Metrics → Traces → Logs

Healthy observability uses each signal for its strength. Investigation flows **down** from aggregate to detail.

```
                    ┌─────────────┐
                    │   Metrics   │  Is something wrong in aggregate?
                    │ Prometheus  │  Error rate up? p95 slow?
                    └──────┬──────┘
                           │ anomaly detected
                           ▼
                    ┌─────────────┐
                    │   Traces    │  Which workflow path? Which step slow?
                    │    Tempo    │  Parent-child hierarchy, per-step duration
                    └──────┬──────┘
                           │ trace_id known
                           ▼
                    ┌─────────────┐
                    │    Logs     │  Why did this step fail?
                    │    Loki     │  Exception, validator reason, entity IDs
                    └─────────────┘
```

### Correlation via trace_id

| Step | Action |
| --- | --- |
| 1 | Grafana dashboard shows `ixora.smart_home.action.total{outcome=failure}` spike |
| 2 | Filter Tempo traces by time, `service.name`, `http.route`, or `outcome=failure` |
| 3 | Open trace `abc123...` — identify failing span `HomeAssistantAdapter.executeAction` |
| 4 | Query Loki: `{service_name="back_vibes-worker"} \| json \| trace_id="abc123..."` |
| 5 | Log reveals `exception_class`, `device_id`, sanitized message |

**Workflow:** Dashboard metric anomaly → filter traces by time/route → jump to correlated logs via `trace_id` ([observability-playbook.md](../operations/observability-playbook.md)).

Do not duplicate the same fact three times. Emit the **metric for the trend**, the **trace for the workflow**, and the **log for the detail**.

### When all three are needed

| Situation | Metric | Trace | Log |
| --- | --- | --- | --- |
| **SLO dashboard** | ✅ rate, latency | Optional sampled link | ❌ |
| **Incident: "API is slow"** | ✅ p95 rising | ✅ sample slow requests | Optional |
| **Incident: "Why did this fail?"** | ✅ failure rate context | ✅ workflow path | ✅ stack trace, IDs |
| **Post-mortem trend** | ✅ 30-day history | ⚠️ 7-day retention | ⚠️ 14-day retention |

See [metrics-philosophy.md §7](metrics-philosophy.md) and [logs-philosophy.md §10–§11](logs-philosophy.md) for complementary perspectives.

---

## 11. Ixora examples

Domain-specific trace patterns aligned with [ADR-029](../decisions/ADR-029-telemetry-data-model.md) and [asynchronous-orchestration.md](asynchronous-orchestration.md).

### HTTP request

```
POST /api/v1/schedules                         ← root, back_vibes-api
  attributes: http.route, http.method, http.status_code, user.id, outcome
  metrics: ixora.http.server.duration
  logs: only on 5xx or unhandled error (trace_id injected)
```

Routine 201 responses: **metric + trace** — no success log.

### Queue worker

```
SmartHomeActionJob.handle                      ← root, back_vibes-worker
  attributes: job.name, queue.name, schedule.id, device.id, outcome
  child: HomeAssistantAdapter.executeAction
  metrics: ixora.queue.job.duration, ixora.smart_home.action.total
  logs: error only after retries exhausted (job_id, trace_id)
```

### Scheduler

```
DispatchDueSchedulesCommand.handle             ← root, back_vibes-worker
  attributes: outcome (aggregate for tick)
  child: VibeSmartHomeDispatchService.dispatch (per schedule processed in-process)
  events: schedule.execution.completed, schedule.smart_home.skipped
  metrics: ixora.scheduler.execution.total, ixora.scheduler.dispatch.duration
  logs: warning on validator skip (schedule_id); error on tick exception
```

Routine successful ticks: **metric only** — no log per tick.

### Automation

```
DispatchDueSchedulesCommand.handle
  └── VibeSmartHomeDispatchService.dispatch
        attributes: schedule.id, automation.id, vibe.id, user.id
        events: smart_home.action.dispatched (per action enqueued)
        └── (async) SmartHomeActionJob.handle  ← separate trace per job
```

Correlate automation fan-out via `schedule.id` + `automation.id` across traces and logs.

### Smart Home

```
SmartHomeActionJob.handle
  └── HomeAssistantAdapter.executeAction
        attributes: provider.name=home_assistant, device.id, action_type, outcome
        metrics: ixora.smart_home.action.duration, ixora.smart_home.action.total
        logs: error on provider timeout (device_id, connection_id, trace_id)
```

Never attribute raw HA entity IDs or tokens ([ADR-030](../decisions/ADR-030-observability-security-and-privacy.md)).

### Push notification

```
PushNotificationJob.handle                     ← root
  └── FcmPushProvider.send                     ← child
        attributes: notification.type, outcome
        events: push.notification.queued
        metrics: ixora.push.delivery.total
        logs: warning on invalid token (hash only); error on FCM API failure
```

### Background synchronization

```
ProviderDeviceSyncService.sync                 ← root or child under scheduled command
  attributes: provider.name, outcome
  metrics: counter for devices synced / failed (aggregate)
  logs: summary on completion — `{devices_synced, devices_failed}` — not per-device spans
```

**Anti-pattern avoided:** One span per device in a 500-device sync. One span for the sync operation; per-device failures in logs + aggregate metrics.

---

## 12. Anti-patterns

| Anti-pattern | Why it fails | Correct approach |
| --- | --- | --- |
| **Huge spans** | Root span open for entire job lifetime including queue wait | Start span at `handle()`; metric for queue wait if needed |
| **Everything as a span** | 50 spans per request — unreadable Tempo UI | Boundaries only: entrypoint, service, job, provider |
| **Very deep trees** | Depth > 6 — navigation fatigue | Flatten; use events for instant milestones |
| **Sensitive attributes** | Tokens, emails in span attributes — ADR-030 violation | IDs and enums only; Collector redaction is second line |
| **Business payloads** | Full request/response bodies on spans | Truncated summary in logs; IDs on span |
| **Span per repository method** | ORM noise | Parent span covers DB work; optional single `db` span |
| **Span per loop iteration** | Cardinality explosion in trace UI | One span + event or log summary |
| **Duplicate trace per log line** | Logs are not spans | One trace per workflow; logs at decision points |
| **IDs in span names** | `SmartHomeActionJob.handle.42` breaks grouping | Stable name + `schedule.id` attribute |
| **Tracing without metrics** | Cannot see aggregate impact | Always pair spans with histograms/counters |
| **Assuming 100% trace coverage** | Sampling drops successes | Metrics for SLOs; logs for errors with `job_id` |
| **Dynamic span names** | Cannot filter in Tempo | Stable `ClassName.method` or route template |

---

## 13. Review checklist

Before adding or changing spans in an instrumentation PR, answer every question:

| # | Question | If "no" or "yes" wrongly… |
| --- | --- | --- |
| 1 | **Is this an architectural boundary?** | Remove internal/helper spans. |
| 2 | **Does an existing span cover this operation?** | Extend attributes — do not duplicate. |
| 3 | **Should this be a span event instead?** | Instant milestone → event on parent. |
| 4 | **Should this be a metric instead?** | Aggregate rate/latency → Prometheus. |
| 5 | **Should this be a log instead?** | Textual detail, stack trace → Loki. |
| 6 | **Is the span name stable and ID-free?** | See [telemetry-naming-convention.md §6](telemetry-naming-convention.md). |
| 7 | **Are attributes on the allowlist?** | See §6 and [ADR-030](../decisions/ADR-030-observability-security-and-privacy.md). |
| 8 | **Does it expose forbidden data?** | Remove secrets, tokens, emails, raw payloads. |
| 9 | **Is `outcome` set on domain spans?** | Enables Tempo filtering and metric alignment. |
| 10 | **Will logs include `trace_id` when this span is active?** | Required for correlation (Phase 7). |
| 11 | **Is tree depth ≤ 4 levels (MVP target)?** | Flatten or replace with events. |
| 12 | **Is there a matching metric for SLO monitoring?** | Traces alone are insufficient. |
| 13 | **Does it belong to the correct `service.name`?** | Worker spans from `back_vibes-worker`, not API. |
| 14 | **Is sampling impact understood?** | Critical paths must have metric + log fallback. |

Also verify: signal choice per [telemetry-decision-guide.md](telemetry-decision-guide.md); metric overlap per [metrics-philosophy.md §9](metrics-philosophy.md); log overlap per [logs-philosophy.md §14](logs-philosophy.md); feature design per [feature-design-checklist.md](feature-design-checklist.md) observability questions.

---

## Cross-references

| Document | Relationship |
| --- | --- |
| [ADR-028](../decisions/ADR-028-observability-platform.md) | Collector-only ingestion — apps never write Tempo |
| [ADR-029](../decisions/ADR-029-telemetry-data-model.md) | Trace structure, span hierarchy, correlation IDs |
| [ADR-030](../decisions/ADR-030-observability-security-and-privacy.md) | Forbidden span attributes — mandatory reading |
| [ADR-031](../decisions/ADR-031-retention-storage-and-cost-control.md) | 7-day trace retention; 10% / 100% sampling |
| [metrics-philosophy.md](metrics-philosophy.md) | Complementary guide — when metrics beat traces |
| [logs-philosophy.md](logs-philosophy.md) | Complementary guide — when logs beat traces |
| [telemetry-naming-convention.md](telemetry-naming-convention.md) | Span names §6, attributes §7, events §10 |
| [telemetry-decision-guide.md](telemetry-decision-guide.md) | Signal choice tree — §4 traces, §5 events |
| [observability-playbook.md](../operations/observability-playbook.md) | Investigation workflow — metrics → traces → logs |
| [asynchronous-orchestration.md](asynchronous-orchestration.md) | Where spans attach in async flows |
| [security-review.md](../specs/observability-foundation/mvp/security-review.md) | Threat model, trace redaction policy |
| [collector-validation-report.md](../specs/observability-foundation/mvp/collector-validation-report.md) | Sampling processor validation |
| [tempo-deployment.md](../specs/observability-foundation/mvp/tempo-deployment.md) | Tempo backend — not a tracing tutorial |
| [telemetry-availability-policy.md](telemetry-availability-policy.md) | Export must not block business logic |
| [observability-operational-limits.md](observability-operational-limits.md) | Ingestion and query limits |
| [specs/observability-foundation/mvp/spec.md](../specs/observability-foundation/mvp/spec.md) | Feature specification and roadmap |

### Document boundaries (avoid duplication)

| Topic | Owner document |
| --- | --- |
| Span **names** and attribute spelling | [telemetry-naming-convention.md](telemetry-naming-convention.md) |
| Trace **vs** metric **vs** log | [telemetry-decision-guide.md](telemetry-decision-guide.md) |
| Trace **thinking**, hierarchy, sampling, anti-patterns | **This document** |
| Tempo **deployment** and Collector wiring | [tempo-deployment.md](../specs/observability-foundation/mvp/tempo-deployment.md) |
| Investigation procedures | [observability-playbook.md](../operations/observability-playbook.md) |

---

## Review checklist (summary)

Before merging instrumentation PRs that add or change spans:

- [ ] Architectural boundary — not internal helper
- [ ] Stable span name without entity IDs
- [ ] Attributes on allowlist; no secrets or PII
- [ ] `outcome` set on domain spans
- [ ] Matching metric exists for SLO monitoring
- [ ] Logs include `trace_id` when span active
- [ ] Tree depth ≤ 4 levels (MVP target)
- [ ] Events used for instant milestones where appropriate
- [ ] Correct `service.name` for producer
- [ ] Sampling fallback understood (metrics + logs)
- [ ] Names follow [telemetry-naming-convention.md §6–§7](telemetry-naming-convention.md)
- [ ] No duplication of [metrics-philosophy.md](metrics-philosophy.md) or [logs-philosophy.md](logs-philosophy.md) concerns
