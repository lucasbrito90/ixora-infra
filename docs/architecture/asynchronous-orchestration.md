# Asynchronous Orchestration

**Status:** Active architecture guide  
**ADRs:** [ADR-026](../decisions/ADR-026-automation-execution-security.md) · [ADR-027](../decisions/ADR-027-asynchronous-orchestration-pattern.md)  
**Complements:** [`domain-validation.md`](domain-validation.md)  
**Applies to:** `back_vibes` and all future Ixora backend async features

> **Purpose:** ADR-026 and ADR-027 explain **why** async execution is structured this way. This guide explains **how to implement it correctly**.

---

## Introduction

Every asynchronous execution path in Ixora — scheduler ticks, Smart Home jobs, push delivery, future analytics or marketplace flows — must follow a **predictable architecture**. Without it, console commands and queue jobs become God Objects that mix validation, domain rules, external I/O, notifications, and retry policy in one class.

### Goals

| Goal | How the pattern helps |
| --- | --- |
| **Separation of responsibilities** | Each layer has one job; entrypoints stay thin |
| **Security** | Domain Validators re-check ownership at execution time ([ADR-026](../decisions/ADR-026-automation-execution-security.md)) |
| **Testability** | Fake bus/queue; mock providers; unit-test validators and services in isolation |
| **Reuse** | Same domain service from HTTP controller and background command |
| **Failure isolation** | One bad item must not stop an entire batch when policy allows |
| **Observability** | Structured logs at clear boundaries — safe IDs only |

### When to read which document

| Document | Answers |
| --- | --- |
| [ADR-026](../decisions/ADR-026-automation-execution-security.md) | *How do we protect security and ownership in background execution?* |
| [ADR-027](../decisions/ADR-027-asynchronous-orchestration-pattern.md) | *How do we organize commands, jobs, and workers without business rules in entrypoints?* |
| **This guide** | *How do I implement a new async feature correctly?* |
| [`domain-validation.md`](domain-validation.md) | *How do I write a Domain Validator?* |

---

## Standard flow

Every new async feature should map to this pipeline:

```
Async Entrypoint
    ↓
Domain Validator
    ↓
Domain Service
    ↓
Queue Job
    ↓
Provider / Adapter
    ↓
External System
```

### Step summary

| Step | Role |
| --- | --- |
| **Async Entrypoint** | Receives the trigger (cron, queue message, Artisan, listener). Loads minimal entities. Orchestrates the pipeline. Catches exceptions. Logs safe context. Continues batch when required. |
| **Domain Validator** | Confirms ownership, entity integrity, and idempotency gates **before** side effects. Returns `false` for expected failures — does not call external systems. |
| **Domain Service** | Executes **domain intent** — what the product should do, independent of HTTP vs background. May enqueue jobs or return a DTO/summary. |
| **Queue Job** | Performs **one isolated unit of work** with retries/timeouts. Handles expected failures at the unit boundary. |
| **Provider / Adapter** | Translates internal DTOs to external API calls. Maps responses back. Never owns domain ownership rules. |
| **External System** | Home Assistant, FCM, payment gateway, analytics warehouse, AI model API — outside Ixora's control. |

Short form ([ADR-027](../decisions/ADR-027-asynchronous-orchestration-pattern.md)):

> **Commands and Jobs orchestrate. Validators protect. Services decide. Providers integrate.**

---

## Layer responsibilities

| Layer | Responsible for | Must NOT do |
| --- | --- | --- |
| **Async Entrypoint** | Trigger handling; minimal entity load; call validator → service; exception isolation; safe structured logging; batch continuation | Complex business rules; direct HTTP to external APIs; `Policy` / `Gate` / `auth()`; inline ownership checks; provider calls |
| **Domain Validator** | Ownership consistency; missing-entity safety; replay/idempotency coordination; safe skip (`false`, not throw) | External I/O; enqueue jobs; send push; call providers |
| **Domain Service** | Domain intent; reusable rules; DTO/summary return; shared HTTP + background logic | HTTP auth; provider wire format; traversing unrelated aggregates in loops |
| **Queue Job** | One unit of work; retries/timeouts; unit-level failure handling; idempotency at job scope | Broad orchestration; controller calls; `Gate::authorize()`; duplicating service logic |
| **Provider / Adapter** | External API/SDK; request/response mapping; transport errors | Business rules; Eloquent domain graph traversal; scheduler/vibe/marketplace concepts |
| **External System** | Authoritative external state (device state, push delivery, payment status) | — (not Ixora code) |

---

## Real Ixora examples

### Scheduler + Smart Home (shipped — Phase 4B)

```
DispatchDueSchedulesCommand          ← Async Entrypoint
    ↓
processSchedule()                    ← Scheduler transaction (recurrence + execution)
    ↓  post-commit, result === 'dispatched'
ScheduleAutomationValidator          ← Domain Validator
    ↓
VibeSmartHomeDispatchService         ← Domain Service
    ↓
SmartHomeActionJob (×N)              ← Queue Job
    ↓
HomeAssistantAdapter                 ← Provider / Adapter
    ↓
Home Assistant REST API              ← External System
```

| Component | Responsibility |
| --- | --- |
| `DispatchDueSchedulesCommand` | Orchestrates due schedules; commits recurrence; delegates Smart Home to post-commit hook |
| `ScheduleAutomationValidator` | Validates schedule → vibe → device → provider connection ownership chain |
| `VibeSmartHomeDispatchService` | Loads device actions in `sort_order`; enqueues one job per action |
| `SmartHomeActionJob` | Executes one action; handles retries; emits failure push on provider error |
| `HomeAssistantAdapter` | HTTP call to HA; maps result to `ActionResult` DTO |

The command **never** calls Home Assistant. Ownership is **never** checked inline in the command.

Reference: [`dispatch-integration-review.md`](../specs/scheduler-smart-home-automations/mvp/dispatch-integration-review.md)

---

### Push Notifications (shipped)

```
PushNotificationEvents               ← Domain-facing orchestration entry
    ↓
Notification Builder                 ← Payload assembly (e.g. ScheduleExecutionFailedNotification)
    ↓
PushNotificationService              ← Domain Service
    ↓
PushNotificationJob                  ← Queue Job
    ↓
PushProviderResolver                 ← Provider selection
    ↓
FcmPushProvider / NoopPushProvider   ← Provider / Adapter
    ↓
Firebase Cloud Messaging             ← External System
```

| Component | Responsibility |
| --- | --- |
| `PushNotificationEvents` | Typed API for domain modules (Scheduler, Smart Home); never throws to caller |
| Notification Builder | Builds `NotificationPayload` per event taxonomy ([ADR-019](../decisions/ADR-019-notification-event-taxonomy.md)) |
| `PushNotificationService` | Enqueues `PushNotificationJob` for a user — fire-and-forget |
| `PushNotificationJob` | Fan-out to active tokens; handles delivery failure; deactivates bad tokens |
| `PushProviderResolver` | Selects FCM or noop provider per environment |
| `FcmPushProvider` | OAuth + HTTP to FCM; no domain knowledge |

Scheduler and Smart Home only call `PushNotificationEvents`. They never import FCM or read `push_tokens`.

Reference: [push-notifications/mvp/spec.md](../specs/push-notifications/mvp/spec.md)

---

### HTTP + background reuse (pattern)

When the same intent exists on HTTP and async paths, **one Domain Service** serves both:

```
HTTP:       Controller → Policy → Form Request → Domain Service → (optional) Job → Provider
Background: Entrypoint → Validator ──────────→ Domain Service → Job → Provider
```

Example: `VibeSmartHomeDispatchService` is used by the mobile dispatch API and by `DispatchDueSchedulesCommand`.

---

## Future features

Apply the same six-layer template before writing runtime code. Document the mapping in the feature spec.

| Feature | Entrypoint | Validator (examples) | Service | Job | Provider | External |
| --- | --- | --- | --- | --- | --- | --- |
| **Analytics** | Cron / queue listener | Event user scope | Aggregation service | Chunk processing job | Warehouse adapter | BigQuery / ClickHouse |
| **AI Recommendations** | Queue | Input vibe/user ownership | Recommendation service | Generate job | Model API adapter | LLM / embedding API |
| **Marketplace** | Webhook listener | Purchase entitlement | Fulfillment service | Fulfill job | Payment adapter | Stripe / gateway |
| **Admin Panel** | Artisan bulk command | Elevated context (separate spec) | Bulk operation service | Per-row job | — | — |
| **Scenes** | Scheduler / manual trigger | Scene → device → connection chain | Scene dispatch service | Per-action jobs | HA adapter | Home Assistant |
| **Matter** | Device sync job | Connection ownership | Device sync service | Sync unit job | Matter adapter | Matter controller |
| **Multi-provider Smart Home** | Same as today | Connection ownership | `VibeSmartHomeDispatchService` | `SmartHomeActionJob` | Resolver → adapters | HA + future providers |
| **Background Sync** | Scheduled command | User/resource scope | Sync orchestration service | Per-entity sync job | Provider adapter | External catalog API |

---

## Best practices

- ✓ **Keep commands small** — orchestration fits on one screen
- ✓ **Keep jobs small** — one action, one push fan-out, one import chunk
- ✓ **Make services reusable** — HTTP and background call the same service
- ✓ **Keep validators independent** — no provider calls, no side effects
- ✓ **Keep providers free of business rules** — receive DTOs + connection primitives
- ✓ **Use DTOs between layers when needed** — `SmartHomeDispatchResult`, `NotificationPayload`, `ActionResult`
- ✓ **Use structured logs** — `schedule_id`, `vibe_id`, `user_id`, `exception_class`; never tokens
- ✓ **Isolate side effects** — enqueue and push **after** DB commit when recurrence must not roll back
- ✓ **Fail fast when appropriate** — throw for unexpected infrastructure errors inside the right boundary
- ✓ **Continue batch on expected failures** — validation skip and isolated side-effect catch must not abort unrelated schedules ([ADR-023](../decisions/ADR-023-automation-execution-order-and-failure-policy.md))

---

## Anti-patterns

### ❌ Command → Provider → HTTP (no validator)

```
DispatchDueSchedulesCommand
    ↓
HomeAssistantAdapter
    ↓
HTTP
```

**Why bad:** No ownership re-check at execution time; command depends on provider uptime; untestable without HTTP; violates [ADR-026](../decisions/ADR-026-automation-execution-security.md) and [ADR-027](../decisions/ADR-027-asynchronous-orchestration-pattern.md).

---

### ❌ Job → Gate::authorize()

```
SmartHomeActionJob
    ↓
Gate::authorize('view', $device)
```

**Why bad:** No authenticated user in background. Use Domain Validator — see [`domain-validation.md`](domain-validation.md).

---

### ❌ Provider → Model → Business rule

```
HomeAssistantAdapter
    ↓
Schedule::with('vibe.deviceActions')
    ↓
if ($schedule->user_id !== $device->user_id) { ... }
```

**Why bad:** Ownership belongs in Domain Validator. Provider should receive connection + device id + action from the job.

---

### ❌ Scheduler → Controller

```
DispatchDueSchedulesCommand
    ↓
VibeSmartHomeDispatchController
```

**Why bad:** Controllers are HTTP entrypoints, not callable services. Call the **Domain Service** directly.

---

### ❌ Everything in one class

```
DispatchDueSchedulesCommand
    validates ownership
    enqueues Smart Home jobs
    sends push notifications
    calls Home Assistant
    updates logs
    decides retry
```

**Why bad:** God Object — impossible to test, reuse, or change one concern without breaking others.

---

## How to choose the correct layer

Use this decision tree when writing code:

```
"Where does this logic belong?"
    │
    ├─ Is it the async trigger (cron, command, listener, batch loop)?
    │       → Async Entrypoint
    │
    ├─ Is it validating ownership, integrity, or idempotency gate?
    │       → Domain Validator
    │
    ├─ Is it deciding domain behaviour ("dispatch actions for vibe X")?
    │       → Domain Service
    │
    ├─ Is it one isolated async unit (one action, one push send batch)?
    │       → Queue Job
    │
    ├─ Is it talking to an external API (HA, FCM, payment, AI)?
    │       → Provider / Adapter
    │
    └─ Is it the external system itself?
            → External System (not Ixora code)
```

**When in doubt:** if the logic would be duplicated in a Controller and a Command, extract it to a **Domain Service**. If it checks "does this user own this entity at execution time" without HTTP, it belongs in a **Domain Validator**.

---

## Code review checklist

Before approving async code, confirm:

- [ ] **No business rules inside the Command** — only orchestration
- [ ] **No business rules inside the Job** — only unit-of-work execution
- [ ] **No HTTP calls outside Provider/Adapter** — jobs and services enqueue; providers integrate
- [ ] **No Policy/Gate in background paths** — Domain Validator used instead
- [ ] **Validator exists** for new async features that touch user-owned resources
- [ ] **Safe structured logging** — IDs only; no tokens, credentials, or payloads with secrets
- [ ] **Retry policy is appropriate** — job `$tries` / `$timeout`; not infinite retry on validation skip
- [ ] **Domain and integration are separated** — service decides intent; provider executes I/O
- [ ] **Side effects after commit** when DB state must not roll back (scheduler pattern)
- [ ] **Batch continues** on expected validation skip and isolated side-effect failure
- [ ] **Service is reusable** from HTTP where the same intent exists
- [ ] **Spec documents the five-layer mapping** for new features

---

## Relationship with other documents

| Document | When to consult |
| --- | --- |
| [ADR-026](../decisions/ADR-026-automation-execution-security.md) | Security model — Policies vs Domain Validators |
| [ADR-027](../decisions/ADR-027-asynchronous-orchestration-pattern.md) | Accepted orchestration decision and layer definitions |
| [`domain-validation.md`](domain-validation.md) | How to write validators; HTTP vs background flows |
| [scheduler-smart-home-automations/mvp/spec.md](../specs/scheduler-smart-home-automations/mvp/spec.md) | Schedule + Vibe + device action automations |
| [push-notifications/mvp/spec.md](../specs/push-notifications/mvp/spec.md) | Push event taxonomy and delivery model |
| [dispatch-integration-review.md](../specs/scheduler-smart-home-automations/mvp/dispatch-integration-review.md) | Scheduler + Smart Home integration reference |
| [ADR-010](../decisions/ADR-010-scheduler-idempotency-occurrence-key.md) | Idempotency at entrypoint |
| [ADR-016](../decisions/ADR-016-smart-home-async-execution.md) | Smart Home job + adapter execution |
| [ADR-023](../decisions/ADR-023-automation-execution-order-and-failure-policy.md) | Failure isolation — recurrence must not block |

### ADR-026 + ADR-027 together

```
[ADR-027 structure]  Entrypoint → Validator → Service → Job → Provider
[ADR-026 security]              ↑ Validator layer (ownership + integrity)
```

- **ADR-026** without **ADR-027** → safe but messy (validation inline in commands).
- **ADR-027** without **ADR-026** → clean layers but unsafe (no ownership re-check).

Implement both on every new async feature.

---

## Related docs

| Document | Relationship |
| --- | --- |
| [ADR-027](../decisions/ADR-027-asynchronous-orchestration-pattern.md) | Architectural decision this guide implements |
| [ADR-026](../decisions/ADR-026-automation-execution-security.md) | Security complement |
| [`domain-validation.md`](domain-validation.md) | Validator practical guide |
