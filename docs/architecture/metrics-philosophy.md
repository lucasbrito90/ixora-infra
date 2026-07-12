# Metrics Philosophy

**Status:** Active architecture guide  
**ADRs:** [ADR-028](../decisions/ADR-028-observability-platform.md) · [ADR-029](../decisions/ADR-029-telemetry-data-model.md) · [ADR-030](../decisions/ADR-030-observability-security-and-privacy.md) · [ADR-031](../decisions/ADR-031-retention-storage-and-cost-control.md)  
**Complements:** [`telemetry-naming-convention.md`](telemetry-naming-convention.md) · [`telemetry-decision-guide.md`](telemetry-decision-guide.md) · [`specs/observability-foundation/mvp/spec.md`](../specs/observability-foundation/mvp/spec.md)  
**Applies to:** All engineers instrumenting `back_vibes`, `front_vibes`, or observability stack components — **mandatory before Phases 7A and 7B (backend instrumentation)**

> **Rule of thumb:** This document defines **how engineers think about metrics**. It is not a Prometheus manual, an OpenTelemetry tutorial, or a naming reference. For names, see [telemetry-naming-convention.md](telemetry-naming-convention.md). For signal choice (metric vs log vs trace), see [telemetry-decision-guide.md](telemetry-decision-guide.md).

---

## 1. Purpose

Metrics exist to answer **operational questions about system behaviour over time** — at a glance, across thousands of requests, without reading individual records.

| Signal | What it captures | Time horizon |
| --- | --- | --- |
| **Metrics** | Aggregated measurements — counts, rates, distributions | Continuous trends (minutes → weeks) |
| **Logs** | Discrete events with context — one record per occurrence | Point-in-time detail |
| **Traces** | Workflow structure — one execution, step by step | Single request or job run |

### Why metrics are different from logs

Logs record **what happened once**, with enough detail to debug that occurrence. Metrics record **how often and how fast things happen**, rolled up across all occurrences.

A single failed Smart Home action belongs in a **log** (with `trace_id`, `device_id`, exception class). The **failure rate** of Smart Home actions over the last hour belongs in a **metric** (`ixora.smart_home.action.total{outcome=failure}`).

Logs are searchable text stores with higher per-event cost. Metrics are pre-aggregated numeric time series optimized for dashboards and alerts.

### Why metrics are different from traces

Traces answer: **What happened in this one workflow, in order, and how long did each step take?** Metrics answer: **What is the system doing in aggregate right now and over time?**

You cannot build a reliable p95 latency dashboard from traces alone — sampling drops most successful requests ([ADR-031](../decisions/ADR-031-retention-storage-and-cost-control.md)). Histogram metrics capture latency across **every** request.

Traces expire after 7 days in MVP. Metrics retain 30 days. Trends and SLOs require metrics.

### The core idea

> Metrics describe **system behaviour over time** — not individual users, devices, or requests.

Observability Foundation Phases 1–3.5 established **what** the platform collects ([ADR-028](../decisions/ADR-028-observability-platform.md)), **how signals relate** ([ADR-029](../decisions/ADR-029-telemetry-data-model.md)), **what must never be exported** ([ADR-030](../decisions/ADR-030-observability-security-and-privacy.md)), and **how the Collector enforces limits** ([Collector Validation](../specs/observability-foundation/mvp/collector-validation-report.md)). This guide establishes **how engineers decide what deserves a metric** — before Phases 7A and 7B add instrumentation to `back_vibes`.

---

## 2. Metrics first principles

These principles govern every metric decision at Ixora.

| Principle | Meaning |
| --- | --- |
| **Metrics describe trends** | A metric shows whether latency is rising, failures are spiking, or throughput is falling — not the story of one request. |
| **Metrics answer operational questions** | Every metric must answer a question an on-call engineer or SRE would ask: "Is the API slow?", "Are pushes failing?", "Is the queue backing up?" |
| **Metrics should be inexpensive** | Each active time series consumes Prometheus memory and disk. Fewer, well-designed metrics beat many granular ones. |
| **Metrics should be aggregated** | Counts, rates, and percentiles across many events — never one series per user, device, or request. |
| **Metrics should be stable** | Metric names and label keys change rarely. Renaming breaks dashboards and alerts. |
| **Metrics must never expose user information** | No emails, names, tokens, or unbounded identifiers as labels ([ADR-030](../decisions/ADR-030-observability-security-and-privacy.md)). |
| **Metrics must never depend on individual requests** | A metric value at time T reflects aggregate system state — not "request #48291 took 300 ms". |

**Cardinality is a cost decision, not a debugging convenience.** High-cardinality labels (`user_id`, `schedule_id`) explode storage and query cost ([ADR-031](../decisions/ADR-031-retention-storage-and-cost-control.md)). The Collector drops forbidden labels before Prometheus — but application code must not emit them in the first place.

---

## 3. When to create a metric

Create a metric when you need to **measure aggregate behaviour** that supports operations, SLOs, or capacity planning.

| Scenario | Metric type | Example |
| --- | --- | --- |
| **Request duration** | Histogram | `ixora.http.server.duration` — p50/p95/p99 latency by route |
| **Queue depth** | UpDownCounter or Gauge | Current jobs waiting in `smart-home` queue |
| **Scheduler executions** | Counter | `ixora.scheduler.execution.total{outcome=*}` — dispatched, skipped, failed |
| **Push deliveries** | Counter | `ixora.push.delivery.total{notification_type=*,outcome=*}` |
| **Smart Home actions** | Counter + Histogram | `ixora.smart_home.action.total`, `ixora.smart_home.action.duration` |
| **Database latency** | Histogram | Query duration by operation (bounded labels only — not raw SQL) |
| **Provider failures** | Counter | `ixora.smart_home.action.total{outcome=failure,provider=home_assistant}` |
| **Retry count** | Counter | Increment on each retry attempt — label `outcome`, not attempt number per job |
| **Worker throughput** | Counter | `ixora.queue.job.total{queue=*,outcome=*}` — jobs processed per interval |

**Test:** Can you plot this on a Grafana dashboard and learn something useful without knowing which user or entity triggered any single event? If yes, it is probably a good metric candidate.

---

## 4. When NOT to create a metric

Do not create a metric when the data is **identifying**, **unbounded**, **one-off**, or **better served by logs or traces**.

| Do not metric | Why | Use instead |
| --- | --- | --- |
| **Every API endpoint parameter** | Query params and path IDs create unbounded cardinality | `http.route` template label; IDs on span attributes |
| **User IDs** | One series per user — millions of series | `user.id` on trace/log only ([ADR-030](../decisions/ADR-030-observability-security-and-privacy.md)) |
| **Email addresses** | PII + unbounded | Never in telemetry |
| **Trace IDs** | Unique per request — destroys Prometheus | Trace store (Tempo); correlate via exemplars post-MVP |
| **Schedule IDs, Device IDs, Vibe IDs** | Unbounded product identifiers | Span attributes + structured log fields |
| **Payload values** | Unbounded text; may contain secrets | Sanitized log message |
| **Debug information** | Ephemeral troubleshooting detail | `debug` level logs |
| **One-off events** | No trend to observe | Log or span event |

**Why logs are more appropriate:** Stack traces, validation messages, provider response summaries, and retry context need full text and entity IDs. Logs in Loki support search by `schedule_id` without creating a Prometheus series per schedule.

**Why traces are more appropriate:** End-to-end workflow timing for **one** execution — HTTP request → job → provider call — requires parent-child span hierarchy. A metric cannot show that schedule 42's dispatch triggered three Smart Home jobs in sequence.

See [telemetry-decision-guide.md §3](telemetry-decision-guide.md) for the full signal choice tree.

---

## 5. Choosing the correct metric type

OpenTelemetry instrument types map to operational intent. Default choices for Ixora:

| Type | Use when | Do not use when | Ixora example |
| --- | --- | --- | --- |
| **Counter** | Something happened; value only increases | You need current depth or latest latency | `ixora.scheduler.execution.total{outcome=failure}` |
| **Histogram** | Distribution of values — latency, size, duration | You only need the latest single value | `ixora.http.server.duration` — enables p95 without per-request Gauge |
| **Gauge** | Point-in-time snapshot of a resource | Per-request latency (use Histogram) | PHP memory usage, Collector queue size (infra) |
| **UpDownCounter** | Active count that rises and falls | A Counter would suffice for monotonic events | In-flight HTTP requests, queue depth |
| **ObservableGauge** | Async observation of external state | Application-level business events | Poll external API health; scrape target `up` |

### Decision shortcuts

```
Did something happen (count it)?
  → Counter

How long did it take (many samples)?
  → Histogram

What is the value right now (may go up or down)?
  → UpDownCounter or Gauge

Need percentiles (p50, p95, p99)?
  → Histogram (never Gauge sampled per request)
```

**One metric, many outcomes:** Prefer `outcome=success|failure|skipped` label on a Counter — not three separate metric names.

**Default for latency:** Histogram — not Gauge. See [telemetry-naming-convention.md §5](telemetry-naming-convention.md).

---

## 6. Labels

Labels (Prometheus) / attributes (OTel metrics) group aggregates. They must stay **low cardinality** — bounded sets of values known at design time.

### Allowed labels

| Label | Example values | Purpose |
| --- | --- | --- |
| `environment` | `development`, `staging`, `production` | Filter by deployment |
| `service.name` | `back_vibes-api`, `back_vibes-worker` | Identify producer ([§3 naming guide](telemetry-naming-convention.md)) |
| `provider` | `home_assistant`, `fcm`, `noop` | External integration |
| `queue` | `smart-home`, `push`, `default` | Queue worker routing |
| `http.method` | `GET`, `POST`, `PATCH` | HTTP verb |
| `http.route` | `/api/v1/schedules/{id}` | Route template — not resolved URL |
| `status` / `http.status_code` | `200`, `502` | Bounded HTTP codes |
| `outcome` | `success`, `failure`, `skipped` | Domain result |
| `notification_type` | Values from [ADR-019](../decisions/ADR-019-notification-event-taxonomy.md) | Push event taxonomy |
| `action_type` | `turn_on`, `turn_off`, `toggle` | Smart Home action enum |

### Forbidden labels

| Label | Why forbidden |
| --- | --- |
| `user_id` | Unbounded; PII risk as label |
| `email` | PII + unbounded |
| `trace_id` | Unique per request |
| `schedule_id`, `device_id`, `vibe_id` | Unbounded product IDs |
| `provider_connection_id`, `session_id` | Unbounded |
| **Anything with unbounded cardinality** | Exception messages, URLs with IDs, raw error text |

### Cardinality — practical example

**Bad:** `ixora.http.server.duration{user_id=123,http.route=/api/v1/schedules/42}`

- 10 000 users × 50 routes = 500 000 series — exceeds MVP budget (< 10 000 per service) in one metric.

**Good:** `ixora.http.server.duration{environment=staging,http.route=/api/v1/schedules/{id},http.status_code=201}`

- 3 environments × ~30 routes × ~10 status codes ≈ 900 series — manageable.

**Debugging schedule 42:** Query Tempo or Loki with `schedule_id=42` — not a Prometheus label.

The Collector `drop_high_cardinality` processor enforces the allowlist ([Collector Validation](../specs/observability-foundation/mvp/collector-validation-report.md)). Application instrumentation must comply at source.

---

## 7. Relationship between metrics, logs, and traces

All three signals complement each other. Healthy observability uses each for its strength.

### Example: HTTP 500 on schedule creation

```
HTTP 500 on POST /api/v1/schedules
         │
         ▼
    ┌─────────┐
    │ Metric  │  ixora.http.server.total or duration histogram
    │         │  labels: http.route, http.status_code=500, environment
    │         │  → Dashboard shows error rate spike
    └────┬────┘
         │
         ▼
    ┌─────────┐
    │ Trace   │  Root span: POST /api/v1/schedules
    │         │  attributes: user.id, outcome=failure, http.status_code=500
    │         │  → Tempo shows which step failed and how long each took
    └────┬────┘
         │
         ▼
    ┌─────────┐
    │ Log     │  level=error, exception_class, sanitized message, trace_id
    │         │  schedule_id, user_id in structured fields
    │         │  → Loki shows stack trace and domain context
    └─────────┘
```

### When all three are needed

| Situation | Metric | Trace | Log |
| --- | --- | --- | --- |
| **SLO dashboard** | ✅ rate, latency | Optional exemplar link | ❌ |
| **Incident: "API is slow"** | ✅ p95 rising | ✅ sample slow requests | Optional |
| **Incident: "Why did this fail?"** | ✅ failure rate context | ✅ workflow path | ✅ stack trace, IDs |
| **Post-mortem trend** | ✅ 30-day history | ⚠️ 7-day retention | ⚠️ 14-day retention |

**Workflow:** Dashboard metric anomaly → filter traces by time/route → jump to correlated logs via `trace_id` ([observability-playbook.md](../operations/observability-playbook.md)).

Do not duplicate the same fact three times. Emit the **metric for the trend**, the **trace for the workflow**, and the **log for the detail**.

---

## 8. Metric lifecycle

Metrics are long-lived platform contracts. Treat them like API endpoints — with review, deprecation, and backward compatibility.

| Stage | Activity |
| --- | --- |
| **Creation** | Propose metric in instrumentation PR; complete §9 review checklist; name per [telemetry-naming-convention.md §5](telemetry-naming-convention.md). |
| **Validation** | Verify series count in staging Prometheus; confirm Collector does not drop labels; spot-check for forbidden fields ([ADR-030](../decisions/ADR-030-observability-security-and-privacy.md)). |
| **Review** | Code review checks cardinality, type choice, and overlap with existing metrics. Platform owner approves new `ixora.*` domains. |
| **Deprecation** | Mark dashboard panels as deprecated; add `deprecated` note in naming guide; stop emitting in next major instrumentation release. |
| **Removal** | Remove instrument from code only after deprecation period; update Grafana dashboards; document in release notes. |
| **Backward compatibility** | Do not rename metrics or labels without migration plan — dashboards and alerts break silently. |
| **Naming stability** | Metric names are immutable contracts. Add labels or new metrics; do not rename in place. |

New domains (`ixora.ai.*`, `ixora.marketplace.*`) require rows in [telemetry-naming-convention.md §15](telemetry-naming-convention.md) and review against [ADR-030](../decisions/ADR-030-observability-security-and-privacy.md) and [ADR-031](../decisions/ADR-031-retention-storage-and-cost-control.md).

---

## 9. Review checklist

Before adding a metric in an instrumentation PR, answer every question:

| # | Question | If "no" or "yes" wrongly… |
| --- | --- | --- |
| 1 | **Can an existing metric be reused?** | Extend with a label — do not create a duplicate. |
| 2 | **Does this metric answer an operational question?** | Do not add "nice to have" metrics — remove or defer. |
| 3 | **Does it introduce high cardinality?** | Move IDs to traces/logs; reduce label set. |
| 4 | **Should this be a log instead?** | One-off detail, stack traces, payload context → log. |
| 5 | **Should this be a trace instead?** | Single-workflow timing → span + histogram aggregate. |
| 6 | **Does it expose sensitive data?** | Remove — see [ADR-030](../decisions/ADR-030-observability-security-and-privacy.md). |
| 7 | **Does it belong to another service?** | Emit from the service that performs the work (`back_vibes-worker` for jobs, not API). |
| 8 | **Is the instrument type correct?** | See §5 — Counter vs Histogram vs Gauge. |
| 9 | **Does the name follow `ixora.*`?** | See [telemetry-naming-convention.md §5](telemetry-naming-convention.md). |
| 10 | **Are labels on the allowlist?** | See §6 and [Security Review](../specs/observability-foundation/mvp/security-review.md). |

Also verify: signal choice per [telemetry-decision-guide.md](telemetry-decision-guide.md); feature design per [feature-design-checklist.md](feature-design-checklist.md) observability questions.

---

## 10. Anti-patterns

| Anti-pattern | Why it fails | Correct approach |
| --- | --- | --- |
| **Metric per user** | Unbounded series; privacy risk | Aggregate counter; `user.id` on trace only |
| **Metric per device** | Thousands of devices → thousands of series | `ixora.smart_home.action.total{outcome=*}` + trace/log for device |
| **Gauge for totals** | Gauges can decrease; totals drift | Counter for cumulative counts |
| **Counter that decreases** | Violates Counter semantics; breaks `rate()` | Use UpDownCounter or Gauge |
| **Duplicated metrics** | `http.errors` + `http.failed` + `http.5xx` for same fact | One counter + `http.status_code` or `outcome` label |
| **Debug metrics** | Left in production; cardinality creep | Debug logs at `debug` level; remove before merge |
| **Metrics used for auditing** | Metrics lack per-event integrity; 30-day retention | Audit tables + structured logs |
| **Business reports from metrics** | Product analytics ≠ operational telemetry | Future `ixora.business.*` / analytics pipeline — separate spec |
| **Histogram for queue depth** | Histograms record distributions, not current depth | UpDownCounter or Gauge |
| **Separate metric per outcome** | `*.success.total` + `*.failure.total` | One `*.total{outcome=*}` |
| **Dynamic metric names** | `ixora.schedule.42.duration` | One metric + ID on span/log |

---

## 11. Ixora examples

Domain-specific metrics aligned with [ADR-029](../decisions/ADR-029-telemetry-data-model.md) and [telemetry-naming-convention.md §5](telemetry-naming-convention.md).

### Scheduler

| Metric | Type | Labels | Operational question |
| --- | --- | --- | --- |
| `ixora.scheduler.dispatch.duration` | Histogram | `environment`, `outcome` | Is the dispatch tick slow? |
| `ixora.scheduler.execution.total` | Counter | `environment`, `outcome` | How many schedules dispatched vs skipped vs failed? |

Do not label by `schedule_id`. Investigate individual schedules via traces (`DispatchDueSchedulesCommand.handle`) and logs (`schedule_id` field).

### Smart Home

| Metric | Type | Labels | Operational question |
| --- | --- | --- | --- |
| `ixora.smart_home.action.duration` | Histogram | `environment`, `action_type`, `outcome`, `provider` | Are HA calls slow? |
| `ixora.smart_home.action.total` | Counter | `environment`, `action_type`, `outcome`, `provider` | What is the failure rate by action type? |

Provider span attributes carry `device.id`; metrics aggregate across all devices.

### Push Notifications

| Metric | Type | Labels | Operational question |
| --- | --- | --- | --- |
| `ixora.push.delivery.total` | Counter | `environment`, `notification_type`, `outcome` | Are FCM deliveries failing? Which event types? |

Never label by push token or `user_id`. Token failures belong in logs with `token_hash` if needed ([ADR-030](../decisions/ADR-030-observability-security-and-privacy.md)).

### Queue Workers

| Metric | Type | Labels | Operational question |
| --- | --- | --- | --- |
| `ixora.queue.job.duration` | Histogram | `environment`, `queue`, `job`, `outcome` | Which job types are slow? |
| `ixora.queue.job.total` | Counter | `environment`, `queue`, `job`, `outcome` | Throughput and failure rate per queue |

`job` label uses bounded job class names — not job UUID.

### HTTP API

| Metric | Type | Labels | Operational question |
| --- | --- | --- | --- |
| `ixora.http.server.duration` | Histogram | `environment`, `http.method`, `http.route`, `http.status_code` | p95 latency? Error rate by route? |

Optional: request rate derived from histogram `_count` — separate Counter only if needed for clarity.

### Future AI (reserved)

| Metric | Type | Labels | Operational question |
| --- | --- | --- | --- |
| `ixora.ai.inference.duration` | Histogram | `environment`, `model`, `outcome` | Is inference latency acceptable? |
| `ixora.ai.inference.total` | Counter | `environment`, `model`, `outcome` | Failure rate by model? |

**Forbidden:** prompt content, user queries, or PII in any label or metric name. Requires future spec + ADR before implementation ([telemetry-naming-convention.md §15](telemetry-naming-convention.md)).

### Future Marketplace (reserved)

| Metric | Type | Labels | Operational question |
| --- | --- | --- | --- |
| `ixora.marketplace.transaction.total` | Counter | `environment`, `outcome` | Transaction success/failure rate |

**Forbidden:** payment instrument data, buyer/seller IDs as labels, transaction amounts as high-cardinality labels. PCI/PII rules apply ([ADR-030](../decisions/ADR-030-observability-security-and-privacy.md)).

---

## 12. Relationship with other documents

| Document | Role relative to this guide |
| --- | --- |
| [ADR-028](../decisions/ADR-028-observability-platform.md) | **Where** metrics go — Collector → Prometheus; apps never write Prometheus directly |
| [ADR-029](../decisions/ADR-029-telemetry-data-model.md) | **What** signals exist — metrics vs logs vs traces; correlation rules |
| [ADR-030](../decisions/ADR-030-observability-security-and-privacy.md) | **What not to emit** — forbidden labels and fields |
| [ADR-031](../decisions/ADR-031-retention-storage-and-cost-control.md) | **How much** — cardinality caps, retention, sampling context |
| [telemetry-naming-convention.md](telemetry-naming-convention.md) | **Names** — `ixora.*` format, official metric list, label allowlist |
| [telemetry-decision-guide.md](telemetry-decision-guide.md) | **Signal choice** — metric vs trace vs log vs event (use before this guide for non-metric questions) |
| [observability-playbook.md](../operations/observability-playbook.md) | **Operations** — investigate using metrics → traces → logs |
| [feature-design-checklist.md](feature-design-checklist.md) | **Pre-spec** — observability questions before new features |
| [security-review.md](../specs/observability-foundation/mvp/security-review.md) | **Threat model** — PII, redaction, Collector enforcement |
| [collector-validation-report.md](../specs/observability-foundation/mvp/collector-validation-report.md) | **Validation** — cardinality processor, auth, hardening sign-off |

### Document boundaries (avoid duplication)

| Topic | Owner document |
| --- | --- |
| Metric **names** and label spelling | [telemetry-naming-convention.md](telemetry-naming-convention.md) |
| Metric **vs** log **vs** trace | [telemetry-decision-guide.md](telemetry-decision-guide.md) |
| Metric **thinking**, lifecycle, anti-patterns | **This document** |
| Investigation procedures | [observability-playbook.md](../operations/observability-playbook.md) |

---

## Review checklist (summary)

Before merging instrumentation PRs that add or change metrics:

- [ ] Existing metric reused where possible
- [ ] Answers a clear operational question
- [ ] No high-cardinality or forbidden labels (§6)
- [ ] Correct instrument type (§5)
- [ ] Name follows `ixora.*` ([telemetry-naming-convention.md §5](telemetry-naming-convention.md))
- [ ] Not duplicating logs or traces for the same purpose
- [ ] No PII or secrets ([ADR-030](../decisions/ADR-030-observability-security-and-privacy.md))
- [ ] Emitted from the correct `service.name`
- [ ] Cardinality within ADR-031 budget (< 10 000 series per service in staging)
