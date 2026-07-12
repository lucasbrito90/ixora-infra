# Telemetry Naming Convention

**Status:** Active architecture guide  
**ADRs:** [ADR-028](../decisions/ADR-028-observability-platform.md) · [ADR-029](../decisions/ADR-029-telemetry-data-model.md) · [ADR-030](../decisions/ADR-030-observability-security-and-privacy.md) · [ADR-031](../decisions/ADR-031-retention-storage-and-cost-control.md)  
**Complements:** [`specs/observability-foundation/mvp/spec.md`](../specs/observability-foundation/mvp/spec.md) · [ADR-029](../decisions/ADR-029-telemetry-data-model.md)  
**Applies to:** All Ixora repositories and observability stack components — `back_vibes`, `front_vibes`, OpenTelemetry Collector, Prometheus, Loki, Tempo, Grafana

> **Rule of thumb:** If it appears in Prometheus, Loki, Tempo, or Grafana, it must follow this guide. No ad-hoc names in application code, dashboards, or alerts.

---

## 1. Purpose

This document is the **single source of truth** for naming every telemetry artifact produced by Ixora:

| Artifact | Covered in |
| --- | --- |
| Services | §3 |
| Metrics | §5, §8 |
| Traces and spans | §6, §7 |
| Logs | §9 |
| Events | §10 |
| Resource attributes | §7 |
| Metric labels | §8 |
| Dashboards | §11 |
| Alerts | §12 |

Observability Foundation Phase 1 established **what** the platform collects ([ADR-028](../decisions/ADR-028-observability-platform.md)), **how signals relate** ([ADR-029](../decisions/ADR-029-telemetry-data-model.md)), **what must never be exported** ([ADR-030](../decisions/ADR-030-observability-security-and-privacy.md)), and **how long data is kept** ([ADR-031](../decisions/ADR-031-retention-storage-and-cost-control.md)).

This guide establishes **how every name is written** — before any SDK, Collector config, or dashboard is implemented.

**Mandatory:** Every Observability Foundation implementation phase (2–11.5) and every future feature that emits telemetry **must** follow this document. Deviations require an ADR amendment or explicit spec exception.

This document plays the same architectural role as [`domain-validation.md`](domain-validation.md), [`asynchronous-orchestration.md`](asynchronous-orchestration.md), [`notification-architecture.md`](notification-architecture.md), and [`user-experience-principles.md`](user-experience-principles.md).

---

## 2. Telemetry hierarchy

Telemetry is organized in a fixed hierarchy. Understanding it prevents duplicate signals and broken correlation.

```
Application                    ← back_vibes, front_vibes (product repos)
    ↓
Service                        ← deployable unit (API, worker, mobile app, Collector)
    ↓
Trace                          ← one logical workflow (HTTP request, job run, screen session)
    ↓
Span                           ← one operation within a trace (controller, job, provider call)
    ↓
Events                         ← named milestones inside a span (dot notation)
    ↓
Metrics                        ← aggregated measurements (counters, histograms)
    ↓
Logs                           ← discrete records (often correlated via trace_id)
```

### How signals relate

| Signal | Relationship |
| --- | --- |
| **Trace** | Root of a workflow. Contains one or more spans. Identified by `trace_id`. |
| **Span** | Child of trace (or parent of nested spans). Identified by `span_id`. Carries attributes (§7). |
| **Event** | Timestamped annotation **on a span** — e.g. `schedule.execution.completed`. Not a separate trace. |
| **Metric** | Aggregated across many traces/requests. Linked to traces via **exemplars** (post-MVP) or shared `service.name` + time. |
| **Log** | Standalone or correlated via `trace_id` / `span_id` injected from active span context. |

**Correlation rule:** Logs emitted during an instrumented operation **must** include `trace_id` when a span is active ([ADR-029](../decisions/ADR-029-telemetry-data-model.md)).

---

## 3. Service naming

Service names identify **who produced the telemetry**. They are **stable across environments** — environment is a separate attribute (§4), not part of the service name.

### Official Ixora service names

| Service name | Component |
| --- | --- |
| `back_vibes-api` | Laravel HTTP API (App Platform `api`) |
| `back_vibes-worker` | Queue + scheduler worker (App Platform `queue` / `scheduler`) |
| `front_vibes-android` | Capacitor Android app |
| `front_vibes-browser` | Web build / Playwright (if instrumented) |
| `otel-collector` | OpenTelemetry Collector |
| `prometheus` | Prometheus TSDB |
| `loki` | Loki log store |
| `tempo` | Tempo trace store |
| `grafana` | Grafana UI |

### Rules

| Rule | Detail |
| --- | --- |
| **Format** | `{repo}-{role}` lowercase, hyphen-separated |
| **Stability** | Same name in `development`, `staging`, `production` |
| **No environment suffix** | ❌ `back_vibes-api-staging` — use `deployment.environment` attribute |
| **No version in name** | Version → `service.version` attribute |
| **OTel resource** | `service.name` MUST match this table |

---

## 4. Environment naming

The attribute `deployment.environment` (OTel) / `environment` (metric label where allowed) uses **only** these values:

| Value | When |
| --- | --- |
| `development` | Local engineer machine |
| `staging` | Homologation (DO App Platform staging) |
| `production` | Production |

### Forbidden aliases

Do **not** use: `dev`, `prod`, `test`, `homolog`, `qa`, `local`, `stg`, `prd`.

**Rationale:** Consistent Grafana variables, alert routing, and log queries across repos.

---

## 5. Metric naming

All Ixora product metrics use the **`ixora.`** namespace. Infrastructure components may use upstream conventions (e.g. Prometheus `up`) — product code must not.

### Format

```
ixora.<domain>.<entity>.<measure>[.<unit>]
```

| Segment | Rule |
| --- | --- |
| `domain` | Product area: `http`, `scheduler`, `smart_home`, `push`, `queue`, `mobile`, `telemetry` |
| `entity` | Noun: `server`, `dispatch`, `action`, `job`, `delivery`, `screen` |
| `measure` | What is measured: `duration`, `total`, `size`, `failed` |
| `unit` | Optional suffix in name — prefer OTel `unit` field: `ms`, `s`, `{request}` |

### Official examples

| Metric | Type | Purpose |
| --- | --- | --- |
| `ixora.http.server.duration` | Histogram | HTTP request latency (ms) |
| `ixora.scheduler.dispatch.duration` | Histogram | `DispatchDueSchedulesCommand` tick duration |
| `ixora.scheduler.execution.total` | Counter | Schedule executions by outcome |
| `ixora.smart_home.action.duration` | Histogram | `SmartHomeActionJob` handle duration |
| `ixora.smart_home.action.total` | Counter | Smart Home actions by outcome |
| `ixora.push.delivery.total` | Counter | Push delivery attempts by event type + outcome |
| `ixora.queue.job.duration` | Histogram | Queue job handle duration |
| `ixora.queue.job.total` | Counter | Jobs processed by queue + outcome |
| `ixora.mobile.screen.duration` | Histogram | Screen load time (Android) |
| `ixora.mobile.network.duration` | Histogram | API call duration from mobile |
| `ixora.telemetry.export.failed.total` | Counter | OTLP export failures (non-fatal) |

### Instrument type selection

| Type | When to use | Ixora examples |
| --- | --- | --- |
| **Counter** | Monotonically increasing counts | `*.total`, requests served, jobs failed |
| **UpDownCounter** | Value that goes up and down | Queue depth, active connections, in-flight requests |
| **Histogram** | Distribution of values (latency, size) | `*.duration`, payload sizes — enables p50/p95/p99 |
| **Gauge** | Point-in-time value | Memory usage, cache size — use sparingly; prefer histograms for latency |

**Default for latency:** Histogram — not Gauge.

**Default for outcomes:** Counter with `outcome` label (`success`, `failure`, `skipped`) — not separate metric names per outcome.

---

## 6. Span naming

Span names identify **what operation ran** — not **which entity** (no IDs in names).

### Format rules

| Rule | Detail |
| --- | --- |
| **HTTP** | `{METHOD} {route template}` — e.g. `GET /api/v1/vibes`, `POST /api/v1/schedules` |
| **Console / command** | `{ClassName}.{method}` — e.g. `DispatchDueSchedulesCommand.handle` |
| **Queue job** | `{JobClass}.handle` — e.g. `SmartHomeActionJob.handle` |
| **Provider** | `{ProviderClass}.{method}` — e.g. `HomeAssistantAdapter.executeAction`, `FcmPushProvider.send` |
| **Mobile screen** | `screen.{ScreenName}` — e.g. `screen.SchedulesPage` |
| **No IDs** | ❌ `GET /api/schedules/42`, ❌ `SmartHomeActionJob.handle.5` |
| **Stable** | Same name across environments and users |

### HTTP examples

```
GET /api/v1/vibes
GET /api/v1/vibes/{id}
POST /api/v1/schedules
PATCH /api/v1/schedules/{id}
DELETE /api/v1/schedules/{id}
```

Use **route templates** (OpenAPI / Laravel route names) — not resolved URLs with IDs.

### Background examples

```
DispatchDueSchedulesCommand.handle
SmartHomeActionJob.handle
PushNotificationJob.handle
VibeSmartHomeDispatchService.dispatch
RecurrenceService.computeNextRunAt
```

### Provider examples

```
HomeAssistantAdapter.executeAction
FcmPushProvider.send
ProviderDeviceSyncService.sync
```

---

## 7. Trace attributes

Attributes carry **context** on spans, logs, and resource descriptors. Prefer **OTel semantic conventions** where they exist; use Ixora names below for domain fields.

### Mandatory (every span)

| Attribute | Example | Notes |
| --- | --- | --- |
| `service.name` | `back_vibes-api` | §3 |
| `service.version` | `1.2.0` or git tag | Release or commit |
| `deployment.environment` | `staging` | §4 |

### Standard optional attributes

| Attribute | Example | When required |
| --- | --- | --- |
| `trace_id` | W3C hex | Logs (§9); auto on spans |
| `span_id` | W3C hex | Logs (§9); auto on spans |
| `user.id` | `123` | When user context exists — integer string, not email |
| `schedule.id` | `42` | Scheduler / automation spans |
| `vibe.id` | `7` | Vibe-related spans |
| `device.id` | `5` | Smart Home spans |
| `provider.name` | `home_assistant` | Provider adapter spans |
| `queue.name` | `smart-home` | Job spans |
| `job.name` | `SmartHomeActionJob` | Job spans |
| `http.route` | `/api/v1/schedules/{id}` | HTTP spans |
| `http.method` | `POST` | HTTP spans |
| `http.status_code` | `502` | HTTP spans — response received |
| `outcome` | `success`, `failure`, `skipped` | Domain operation result |
| `exception.type` | `ProviderConnectionException` | OTel convention (prefer over `exception.class`) |
| `exception.message` | Sanitized message | No secrets — [ADR-030](../decisions/ADR-030-observability-security-and-privacy.md) |
| `notification.type` | `smart_home_action_failed` | Push spans — aligns [ADR-019](../decisions/ADR-019-notification-event-taxonomy.md) |
| `action_type` | `turn_off` | Smart Home action spans |

### Naming convention for attributes

| Convention | Example |
| --- | --- |
| OTel standard | `http.method`, `service.name` — dot notation |
| Ixora domain IDs | `schedule.id`, `vibe.id`, `user.id` — dot notation, lowercase |
| Legacy log fields | `schedule_id`, `user_id` — snake_case in **structured logs only** (§9) |

Spans use **dot notation** (`schedule.id`). Structured logs use **snake_case** (`schedule_id`) for Laravel compatibility — both refer to the same entity.

---

## 8. Metric labels

Labels (Prometheus) / attributes (OTel metrics) must stay **low cardinality**.

### Allowed labels

| Label | Example values |
| --- | --- |
| `environment` | `development`, `staging`, `production` |
| `queue` | `smart-home`, `push`, `default` |
| `provider` | `home_assistant`, `fcm`, `noop` |
| `status` / `http.status_code` | `200`, `502` — bounded HTTP codes |
| `outcome` | `success`, `failure`, `skipped` |
| `action_type` | `turn_on`, `turn_off`, `toggle` — bounded enum |
| `notification_type` | Values from [ADR-019](../decisions/ADR-019-notification-event-taxonomy.md) |
| `job` | Job class short name — bounded set of job types |

### Forbidden labels

| Label | Why forbidden |
| --- | --- |
| `user_id` | Unbounded cardinality |
| `trace_id` | Unique per request — destroys Prometheus |
| `email` | PII + unbounded |
| `device_id`, `schedule_id`, `vibe_id` | Unbounded — use trace attributes instead |
| `provider_entity_id` | Unbounded; may reveal home layout |
| Dynamic URL paths | Use `http.route` template |
| `exception.message` | Unbounded text |

**Target:** < 10 000 active series per `service.name` in staging ([ADR-031](../decisions/ADR-031-retention-storage-and-cost-control.md)).

---

## 9. Structured log fields

Laravel and mobile logs SHOULD use a **consistent structured schema** when exported to Loki via Collector.

### Standard fields

| Field | Type | Required | Notes |
| --- | --- | --- | --- |
| `timestamp` | ISO 8601 UTC | ✅ | Log event time |
| `level` | string | ✅ | `debug`, `info`, `warning`, `error` |
| `message` | string | ✅ | Human-readable summary |
| `trace_id` | string | ⚠️ | Required when span active |
| `span_id` | string | ⚠️ | Required when span active |
| `service.name` | string | ✅ | §3 |
| `deployment.environment` | string | ✅ | §4 |
| `user_id` | integer | Optional | Domain context — not email |
| `schedule_id` | integer | Optional | Scheduler context |
| `vibe_id` | integer | Optional | Vibe context |
| `device_id` | integer | Optional | Smart Home context |
| `exception_class` | string | Optional | Exception FQCN |
| `error` | string | Optional | Sanitized message only |

### Field naming rules

| Rule | Detail |
| --- | --- |
| **snake_case** | All structured log keys: `schedule_id`, not `scheduleId` |
| **Consistency** | Same field names in API, worker, and mobile (where applicable) |
| **No secrets** | Never log tokens, passwords, Authorization headers ([ADR-030](../decisions/ADR-030-observability-security-and-privacy.md)) |
| **trace_id always when available** | Enables Loki → Tempo correlation in Grafana |

### Example (safe)

```json
{
  "timestamp": "2026-07-05T19:00:00.000Z",
  "level": "warning",
  "message": "Schedule Smart Home dispatch skipped: validation failed.",
  "trace_id": "4bf92f3577b34da6a3ce929d0e0e4736",
  "span_id": "00f067aa0ba902b7",
  "service.name": "back_vibes-worker",
  "deployment.environment": "staging",
  "schedule_id": 42,
  "vibe_id": 7,
  "user_id": 123,
  "validator_failed": true
}
```

---

## 10. Event naming

Events are **named occurrences** attached to spans (OTel span events) or emitted as structured log records with an `event.name` field.

### Format

```
<domain>.<entity>.<verb>
```

Use **dot notation** — lowercase, past tense for completed actions.

### Official examples

| Event name | When |
| --- | --- |
| `schedule.execution.started` | Dispatch begins processing a due schedule |
| `schedule.execution.completed` | Execution row committed + recurrence advanced |
| `schedule.execution.failed` | Transaction rolled back / recurrence failure |
| `schedule.smart_home.skipped` | Validator returned false |
| `smart_home.action.dispatched` | Job enqueued |
| `smart_home.action.completed` | Provider returned success |
| `smart_home.action.failed` | Provider returned failure |
| `push.notification.queued` | `PushNotificationJob` dispatched |
| `push.notification.sent` | FCM accepted message |
| `push.notification.failed` | FCM or token failure |
| `http.request.started` | HTTP span opened |
| `http.request.completed` | HTTP response sent |

**Do not** use camelCase, snake_case, or screaming snake for event names — **dots only**.

---

## 11. Dashboard naming

Grafana dashboard titles follow a fixed taxonomy for discoverability.

### Format

```
Ixora / {Domain} / {View}
```

| Domain folder | Dashboards |
| --- | --- |
| **API** | Overview, Latency, Errors |
| **Scheduler** | Dispatch, Executions, Failures |
| **Smart Home** | Actions, Provider health |
| **Push** | Delivery by event type |
| **Queue** | Depth, Job duration, Failures |
| **Mobile** | Errors, Screen performance |
| **Infrastructure** | App Platform health (external) |
| **Observability** | Collector, Prometheus, Loki, Tempo, Grafana health |

### Examples

```
Ixora / API / Overview
Ixora / Scheduler / Dispatch
Ixora / Smart Home / Actions
Ixora / Push / Delivery
Ixora / Queue / Jobs
Ixora / Mobile / Errors
Ixora / Observability / Collector Health
```

**UID convention:** `ixora-{domain}-{view}` lowercase kebab-case — e.g. `ixora-api-overview`.

---

## 12. Alert naming

Alerting is **out of MVP scope** — names are reserved for future phases.

### Format

```
Ixora {Domain} — {Condition}
```

### Official examples

| Alert name | Condition |
| --- | --- |
| `Ixora API — High Error Rate` | 5xx rate > threshold |
| `Ixora Scheduler — Failure Rate` | `schedule.execution.failed` spike |
| `Ixora Queue — Backlog` | Queue depth sustained high |
| `Ixora Observability — Collector Down` | `up{job="otel-collector"} == 0` |
| `Ixora Observability — Prometheus Down` | Prometheus unreachable |
| `Ixora Observability — Loki Down` | Loki unreachable |
| `Ixora Observability — Tempo Down` | Tempo unreachable |
| `Ixora Observability — Grafana Down` | Grafana unreachable |

Alert **labels** reuse §8 allowed labels only — never `user_id`.

---

## 13. Anti-patterns

| Anti-pattern | Correct approach |
| --- | --- |
| Mixing `snake_case` and dot notation in metric names | Metrics: `ixora.domain.entity.measure` only |
| IDs inside metric names | `ixora.schedule.42.duration` ❌ → use `schedule.id` attribute |
| High-cardinality labels (`user_id`, `trace_id`) | Trace attributes + logs |
| Logs without `trace_id` during instrumented flows | Inject from OTel context |
| Spans without `service.name` / `deployment.environment` | Mandatory resource attributes |
| Duplicated metrics for same measure | One metric + `outcome` label |
| Metrics for everything | Metrics for SLOs; logs for detail; traces for workflow |
| Dynamic labels from exception messages | `exception.type` label only |
| Environment in service name | `deployment.environment` attribute |
| Using `dev` / `prod` / `homolog` | §4 official values only |
| Event names in camelCase | Dot notation: `schedule.execution.completed` |
| Dashboard titles without `Ixora /` prefix | §11 taxonomy |

---

## 14. End-to-end example

**Scenario:** User creates a schedule via API; later the scheduler dispatches Smart Home actions; one action fails; push is sent.

### 1. HTTP request (entry)

| Signal | Value |
| --- | --- |
| **Trace** | `trace_id=abc123...` |
| **Span name** | `POST /api/v1/schedules` |
| **Attributes** | `service.name=back_vibes-api`, `deployment.environment=staging`, `http.method=POST`, `http.route=/api/v1/schedules`, `http.status_code=201`, `user.id=123`, `outcome=success` |
| **Event** | `http.request.completed` |
| **Log** | `{ "level": "info", "message": "Schedule created", "trace_id": "abc123...", "user_id": 123, "schedule_id": 42 }` |
| **Metric** | `ixora.http.server.duration` histogram, labels: `environment=staging`, `http.status_code=201` |

### 2. Scheduler dispatch (background)

| Signal | Value |
| --- | --- |
| **Trace** | New trace `trace_id=def456...` (or linked via batch context) |
| **Span name** | `DispatchDueSchedulesCommand.handle` |
| **Child span** | `SmartHomeActionJob.handle` |
| **Event** | `schedule.execution.completed`, then `smart_home.action.dispatched` |
| **Log** | `{ "level": "info", "message": "Schedule dispatched", "trace_id": "def456...", "schedule_id": 42, "outcome": "dispatched" }` |
| **Metric** | `ixora.scheduler.dispatch.duration`, `ixora.scheduler.execution.total{outcome=dispatched}` |

### 3. Smart Home failure

| Signal | Value |
| --- | --- |
| **Span name** | `HomeAssistantAdapter.executeAction` |
| **Attributes** | `device.id=5`, `action_type=turn_off`, `outcome=failure`, `exception.type=ProviderException` |
| **Event** | `smart_home.action.failed` |
| **Log** | `{ "level": "warning", "message": "SmartHomeActionJob: action execution failed", "trace_id": "def456...", "device_id": 5, "exception_class": "ProviderException" }` |
| **Metric** | `ixora.smart_home.action.total{outcome=failure,action_type=turn_off}` |

### 4. Push notification

| Signal | Value |
| --- | --- |
| **Span name** | `PushNotificationJob.handle` → `FcmPushProvider.send` |
| **Event** | `push.notification.sent` or `push.notification.failed` |
| **Metric** | `ixora.push.delivery.total{notification_type=smart_home_action_failed,outcome=success}` |

### 5. Dashboard

Engineer opens **`Ixora / Smart Home / Actions`** — sees elevated `ixora.smart_home.action.total{outcome=failure}`, clicks exemplar/trace link → Tempo trace `def456...` → correlated Loki logs with same `trace_id`.

---

## 15. Future extensions

Reserve namespaces and domains for future platform capabilities. **Do not implement** until a spec + ADR exists.

| Future domain | Metric prefix | Notes |
| --- | --- | --- |
| **Business metrics** | `ixora.business.*` | Active users, schedules created — aggregate only |
| **Analytics** | `ixora.analytics.*` | Event counts — no PII labels |
| **AI / recommendations** | `ixora.ai.*` | Inference latency, outcome — no prompt content in logs |
| **Marketplace** | `ixora.marketplace.*` | Transactions — PCI/PII forbidden in telemetry |
| **Billing** | `ixora.billing.*` | Counters only — no payment instrument data |
| **Admin** | `ixora.admin.*` | Admin panel HTTP — separate service `ixora-admin-web` if instrumented |
| **IoT / sensors** | `ixora.iot.*` | Deferred — geofencing/sensors out of current scope |

New domains require:

1. Rows added to this document
2. Review against [ADR-030](../decisions/ADR-030-observability-security-and-privacy.md) and [ADR-031](../decisions/ADR-031-retention-storage-and-cost-control.md)
3. Dashboard folder in §11

---

## Review checklist

Before merging instrumentation PRs:

- [ ] `service.name` matches §3
- [ ] `deployment.environment` uses §4 values only
- [ ] Metrics use `ixora.*` namespace (§5)
- [ ] Span names contain no IDs (§6)
- [ ] No forbidden labels (§8)
- [ ] Logs include `trace_id` when instrumented (§9)
- [ ] Events use dot notation (§10)
- [ ] No secrets or PII ([ADR-030](../decisions/ADR-030-observability-security-and-privacy.md))

---

## Related documents

| Document | Relationship |
| --- | --- |
| [ADR-028](../decisions/ADR-028-observability-platform.md) | Platform topology |
| [ADR-029](../decisions/ADR-029-telemetry-data-model.md) | Signal definitions |
| [ADR-030](../decisions/ADR-030-observability-security-and-privacy.md) | Forbidden fields |
| [ADR-031](../decisions/ADR-031-retention-storage-and-cost-control.md) | Cardinality limits |
| [observability-foundation/mvp/spec.md](../specs/observability-foundation/mvp/spec.md) | Feature spec |
| [metrics-philosophy.md](metrics-philosophy.md) | How engineers think about metrics — Phases 7A/7B |
| [notification-architecture.md](notification-architecture.md) | Event type alignment |
