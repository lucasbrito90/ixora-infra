# ADR-027: Asynchronous orchestration pattern

## Status

**Accepted** — governs **platform-wide structure for asynchronous execution** across all Ixora backend features. Complements [ADR-026](ADR-026-automation-execution-security.md) (security) with an orchestration model (layering).

**Practical guide:** [`asynchronous-orchestration.md`](../architecture/asynchronous-orchestration.md)

## Date

2026-06-28

---

## Problem

Console commands, queue jobs, scheduler loops, and event listeners tend to accumulate **business logic** when there is no clear orchestration pattern. Without explicit layering, the async entrypoint becomes a **God Object** that owns validation, domain rules, external I/O, notifications, logging, and retry policy in one place.

### Anti-pattern (forbidden)

```
DispatchDueSchedulesCommand
    ↓
validates ownership inline
    ↓
computes domain rules
    ↓
calls Home Assistant directly
    ↓
sends push notification
    ↓
updates execution logs
    ↓
decides retry policy
```

This couples unrelated concerns, makes testing painful, and duplicates logic that already exists (or should exist) in domain services.

The problem repeats across every async surface:

| Area | Risk if entrypoint grows |
| --- | --- |
| **Scheduler** | Recurrence + Smart Home + push + logging in one command |
| **Smart Home** | Provider HTTP inside jobs or commands |
| **Push Notifications** | FCM details leaking into Scheduler or Smart Home |
| **Analytics** (future) | Aggregation rules inside cron commands |
| **AI Recommendations** (future) | Model calls inside queue workers |
| **Marketplace** (future) | Payment/provider logic inside listeners |
| **Admin bulk jobs** (future) | Cross-tenant rules inline in commands |
| **Scenes** (future) | Multi-device orchestration in one job |
| **Multi-provider Smart Home** (future) | Provider selection inside scheduler |

**ADR-026** answers: *“How do we protect security and ownership in background execution?”*

**ADR-027** answers: *“How do we organize commands, jobs, and workers so they do not become classes full of business rules?”*

---

## Decision

### Core principle

> **Async entrypoints orchestrate.**
>
> **Domain validators validate.**
>
> **Domain services decide and execute domain intent.**
>
> **Jobs perform isolated side effects.**
>
> **Providers perform external I/O.**

Short form:

> **Commands and Jobs orchestrate. Validators protect. Services decide. Providers integrate.**

### Official flow

```
Async Entrypoint
    ↓
Domain Validator
    ↓
Domain Service
    ↓
Queue / Side Effects
    ↓
Provider / Adapter (when external I/O is required)
```

Async entrypoints **coordinate** the pipeline. They do **not** own domain rules or external integration details.

---

## Layers

### 1. Async Entrypoint

**Examples:** Console command, scheduler command, queue job (when acting as batch coordinator), event listener, cron task.

**Responsible for:**

| Responsibility | Detail |
| --- | --- |
| Receive trigger | Cron tick, queue message, Artisan invocation, domain event |
| Load minimal entities | Eager-load only what the next layers need |
| Invoke validator | Before side effects — see [ADR-026](ADR-026-automation-execution-security.md) |
| Invoke domain service | Delegate intent; do not reimplement service logic |
| Catch exceptions | Isolate failures; do not abort unrelated batch items |
| Log safe context | IDs and structured fields only — never secrets |
| Continue batch | One failure must not stop the whole run when policy allows |

**Must not:**

- Contain complex business rules
- Call external providers directly (HTTP, SDK, FCM, Home Assistant)
- Duplicate logic that belongs in a domain service
- Use `Policy`, `Gate`, or `auth()` for background safety
- Decide ownership inline (use Domain Validator)

---

### 2. Domain Validator

**Responsible for:**

- Ownership consistency across related entities
- Entity integrity (missing vibe, device, connection, token)
- Replay / idempotency gate coordination when applicable ([ADR-010](ADR-010-scheduler-idempotency-occurrence-key.md))
- Safe skip semantics — return `false` for expected failures; do not throw for expected domain mismatches

**Must not:**

- Call external providers
- Perform side effects (enqueue, push, HTTP)
- Know HTTP request context

See [ADR-026](ADR-026-automation-execution-security.md) and [`domain-validation.md`](../architecture/domain-validation.md).

---

### 3. Domain Service

**Responsible for:**

- Execute **domain intent** — “dispatch Smart Home actions for this vibe”, “send push to this user”, “compute next occurrence”
- Encapsulate reusable rules shared by HTTP and background paths when possible
- Return DTO / summary when useful for logging or API responses
- Remain unaware of **which** entrypoint invoked it (command vs controller)

**Examples (current or expected):**

| Service | Domain intent |
| --- | --- |
| `VibeSmartHomeDispatchService` | Enqueue one job per vibe device action in `sort_order` |
| `PushNotificationService` | Dispatch `PushNotificationJob` for a user + payload |
| `RecurrenceService` | Pure recurrence / occurrence_key computation |
| `PushNotificationEvents` | Domain-facing notification orchestration (typed events → builders → service) |

**Must not:**

- Know FCM, Home Assistant, or other provider wire format
- Authorize HTTP users (Policies belong at controller)
- Own broad batch loops across unrelated aggregates (that is the entrypoint’s job)

---

### 4. Queue Job

**Responsible for:**

- Execute **one isolated unit of work** (one device action, one user’s push fan-out, one import chunk)
- Retries, timeouts, and queue routing
- Catch expected failures at the unit boundary
- Never block unrelated units in the same batch

**Must not:**

- Become a second orchestrator for unrelated domains
- Call controllers or HTTP layer
- Use `Gate::authorize()` — use Domain Validator at handle time if re-validation is needed

Aligns with [ADR-016](ADR-016-smart-home-async-execution.md) and [ADR-020](ADR-020-push-delivery-and-fallback-strategy.md).

---

### 5. Provider / Adapter

**Responsible for:**

- External service I/O (HTTP, SDK, FCM, Home Assistant REST)
- Map external responses to internal DTOs
- Surface transport failures without leaking secrets in logs

**Must not:**

- Read Eloquent domain models directly (receive connection + device id + action from job/service)
- Know Scheduler, Vibe, Marketplace, or other product concepts
- Decide ownership (validator + service already decided)

Aligns with [ADR-012](ADR-012-smart-home-provider-strategy.md) and [ADR-017](ADR-017-push-notification-provider-strategy.md).

---

## Reference example — Scheduler + Smart Home (Phase 4)

Current shipped flow (`back_vibes`):

```
DispatchDueSchedulesCommand          ← Async Entrypoint (orchestrator)
    ↓
processSchedule()                    ← Scheduler domain (transaction + recurrence)
    ↓  (post-commit, 'dispatched' only)
ScheduleAutomationValidator          ← Domain Validator
    ↓
VibeSmartHomeDispatchService         ← Domain Service
    ↓
SmartHomeActionJob (×N)              ← Queue Job (one action each)
    ↓
HomeAssistantAdapter                 ← Provider / Adapter
```

**Why this is correct:**

- `DispatchDueSchedulesCommand` stays thin: recurrence in `processSchedule()`, Smart Home in `dispatchSmartHomeAfterSchedule()`.
- Ownership checks live in `ScheduleAutomationValidator` — not in the command.
- Enqueue semantics live in `VibeSmartHomeDispatchService` — reused from mobile dispatch API.
- Provider HTTP runs only inside `SmartHomeActionJob` → adapter — never in the scheduler transaction.

Details: [`dispatch-integration-review.md`](../specs/scheduler-smart-home-automations/mvp/dispatch-integration-review.md)

---

## Reference example — Push Notifications

Current shipped flow (`back_vibes`):

```
PushNotificationEvents               ← Domain-facing orchestration (typed events)
    ↓
Notification Builder                 ← ScheduleExecutionFailedNotification, etc.
    ↓
PushNotificationService              ← Domain Service (enqueue only)
    ↓
PushNotificationJob                  ← Queue Job (fan-out per token)
    ↓
PushProviderResolver                 ← Provider selection
    ↓
FcmPushProvider / NoopPushProvider   ← Provider / Adapter
```

**Why this is correct:**

- Scheduler and Smart Home call `PushNotificationEvents` — they never import FCM or token tables.
- Builders own payload shape ([ADR-019](ADR-019-notification-event-taxonomy.md), [ADR-021](ADR-021-notification-security-and-privacy.md)).
- `PushNotificationJob` performs delivery fan-out; domain modules do not know transport details.
- Provider swap (FCM → future APNs) stays behind `PushProviderResolver`.

---

## Best practices

| Practice | Rationale |
| --- | --- |
| **Keep entrypoints thin** | One screen of orchestration per method; delegate everything else |
| **Reuse services from HTTP and background** | Same `VibeSmartHomeDispatchService` for API play and scheduler |
| **Validators never call providers** | Validation is synchronous and local |
| **Providers never know product domains** | Adapters receive primitives + DTOs |
| **Jobs are idempotent or key-guarded** | [ADR-010](ADR-010-scheduler-idempotency-occurrence-key.md) at scheduler; job-level skips for missing rows |
| **Logs use IDs and safe previews** | [ADR-026 § Logging](ADR-026-automation-execution-security.md#logging) |
| **One item failure ≠ batch failure** | [ADR-023](ADR-023-automation-execution-order-and-failure-policy.md) |
| **External I/O only in adapters** | Keeps commands and jobs testable with `Bus::fake()` / HTTP fake |
| **Post-commit side effects** | Enqueue and push after DB commit when recurrence must not roll back |

---

## Anti-patterns (forbidden)

| Anti-pattern | Why forbidden |
| --- | --- |
| **Fat command with business rules** | Untestable; duplicates services |
| **Job calling `Gate::authorize()`** | No HTTP user in background — use Domain Validator |
| **Job calling Controller** | Wrong direction; HTTP is not a service layer |
| **Controller dispatching job with secrets in payload** | [ADR-021](ADR-021-notification-security-and-privacy.md) |
| **Provider reading Eloquent models** | Couples integration to ORM; hard to mock |
| **Duplicate rule in HTTP + command** | Drift; extract to service or validator |
| **Scheduler + push + provider in one class** | God Object |
| **`AutomationEngine` before real need** | [ADR-022](ADR-022-scheduler-smart-home-automation-model.md) — compose existing entities first |

---

## Relationship with ADR-026

| ADR | Question answered | Mechanism |
| --- | --- | --- |
| **ADR-026** | How do we secure async execution? | Policies = HTTP; Domain Validators = background |
| **ADR-027** | How do we structure async execution? | Entrypoints orchestrate; validators guard; services decide; jobs work; providers integrate |

They are **complementary**:

- ADR-026 without ADR-027 → safe but still messy (validation inline in commands).
- ADR-027 without ADR-026 → clean layers but unsafe (Policies in jobs, or no ownership re-check).

Together they define the **Ixora async architecture**:

```
[ADR-027 layering]  +  [ADR-026 security at validator layer]
```

Practical guides: [`domain-validation.md`](../architecture/domain-validation.md) · [`asynchronous-orchestration.md`](../architecture/asynchronous-orchestration.md)

---

## Relationship with existing ADRs

| ADR | How ADR-027 uses it |
| --- | --- |
| [ADR-010](ADR-010-scheduler-idempotency-occurrence-key.md) | Entrypoint gates side effects on `'dispatched'` + `occurrence_key`; validator does not replace idempotency |
| [ADR-016](ADR-016-smart-home-async-execution.md) | Smart Home provider calls only in job + adapter layer |
| [ADR-017](ADR-017-push-notification-provider-strategy.md) | Push provider behind resolver; not in domain modules |
| [ADR-020](ADR-020-push-delivery-and-fallback-strategy.md) | Push delivery as isolated job + provider path |
| [ADR-023](ADR-023-automation-execution-order-and-failure-policy.md) | Entrypoint catches SH failures without blocking recurrence |
| [ADR-026](ADR-026-automation-execution-security.md) | Validator layer mandatory before service/side effects |

---

## Consequences

### Positive

| Outcome | Why it matters |
| --- | --- |
| **Reduced God Objects** | Commands and coordinator jobs stay readable |
| **Easier testing** | Fake bus/queue; mock providers; unit-test validators and services |
| **Reuse across HTTP and async** | One service, two entrypoints |
| **Thin commands** | Scheduler changes do not entangle Smart Home |
| **Isolated providers** | Swap FCM or HA without touching scheduler |
| **Better observability** | Clear log boundaries per layer |

### Tradeoffs

| Tradeoff | Impact |
| --- | --- |
| **More small classes** | Slightly more files to navigate |
| **Architectural discipline** | Reviews must enforce layering |
| **MVP overhead** | Justified by Smart Home + Push + Scheduler already intersecting |

---

## Alternatives considered

| Alternative | Why not chosen |
| --- | --- |
| **Single `AutomationEngine` service** | Over-abstraction before need — [ADR-022](ADR-022-scheduler-smart-home-automation-model.md) |
| **Fat jobs only (no commands)** | Scheduler recurrence still needs transactional command; jobs are unit-of-work |
| **Providers called from commands** | Breaks testability; couples cron to external uptime |
| **Controllers invoke providers for async work** | HTTP layer must not own background integration |
| **Implicit convention without ADR** | Pattern already emerging in code; needs platform documentation |

---

## Related docs

| Document | Relationship |
| --- | --- |
| [`asynchronous-orchestration.md`](../architecture/asynchronous-orchestration.md) | **Practical guide** — layer table, good/bad flows |
| [`domain-validation.md`](../architecture/domain-validation.md) | Security layer (ADR-026) inside orchestration flow |
| [`dispatch-integration-review.md`](../specs/scheduler-smart-home-automations/mvp/dispatch-integration-review.md) | Scheduler + Smart Home reference implementation |
| [ADR-026](ADR-026-automation-execution-security.md) | Complementary security model |
| [ADR-010](ADR-010-scheduler-idempotency-occurrence-key.md) | Idempotency at entrypoint |
| [ADR-016](ADR-016-smart-home-async-execution.md) | Job + adapter execution |
| [ADR-017](ADR-017-push-notification-provider-strategy.md) | Push provider abstraction |
| [ADR-020](ADR-020-push-delivery-and-fallback-strategy.md) | Async push delivery |
| [ADR-023](ADR-023-automation-execution-order-and-failure-policy.md) | Failure isolation |

---

When adding a new async feature, reference ADR-027 in the spec and PR. Document the five layers in the feature’s integration review before runtime changes.
