# ADR-026: Automation execution security

## Status

**Accepted** — governs **platform-wide security boundaries for asynchronous execution** across all Ixora backend features. First concrete application: Scheduler + Smart Home automations ([`specs/scheduler-smart-home-automations/mvp/spec.md`](../specs/scheduler-smart-home-automations/mvp/spec.md)).

**Practical guide:** [`domain-validation.md`](../architecture/domain-validation.md)

## Date

2026-06-28

---

## Problem

Laravel **Policies** protect **HTTP access** — they answer “may this authenticated user perform this action on this resource through the API?”

Policies depend on:

- An **authenticated user** (`auth()->user()`)
- An **HTTP Request** context
- **Controllers** (or equivalent HTTP entry points) invoking `$this->authorize()` or `Gate::`
- Laravel's **Gate / Authorization** layer

**Console commands**, **queue workers**, **cron jobs**, **scheduled tasks**, **event listeners**, and **background workers** execute **without an authenticated user**. There is no Firebase JWT, no session, and no `Request` carrying identity.

Therefore:

- `$this->authorize('view', $schedule)` in a command **cannot** reliably enforce ownership — there is no user to authorize.
- `Gate::authorize()` in a job assumes a user context that does not exist.
- Policies written for REST/mobile/admin **do not run automatically** in background paths.

Relying on Policies (or Form Request validation that ran at write time) as the **only** safety layer leaves asynchronous execution vulnerable to:

- Data inserted outside the API (tinker, migrations, bugs, future admin tools)
- Stale cross-table references (schedule pointing at another user's vibe)
- Replay or duplicate side effects when idempotency is not enforced at the execution layer

This is a **platform architectural gap**, not a Scheduler-only concern. Every async feature — Smart Home jobs, push dispatch, future analytics, AI recommendations, marketplace flows — must follow the same rule.

---

## Decision

### Core principle

> **Policies protect HTTP access.**
>
> **Domain Validators protect asynchronous execution.**

Every asynchronous execution path must **validate domain integrity explicitly** before performing side effects. HTTP authorization and background validation are **complementary layers** — neither replaces the other.

| Layer | When | Mechanism |
| --- | --- | --- |
| **HTTP authorization** | REST API, mobile, admin panel | Laravel **Policies** + Form Requests |
| **Background safety** | Queue, scheduler, console, cron, listeners | **Domain Validators** (explicit, user-less) |

See [`domain-validation.md`](../architecture/domain-validation.md) for the practical guide, flow diagrams, and anti-patterns.

---

## Execution sources

This ADR applies to **all** background entry points:

| Execution source | Auth user? | Use Policies? | Use Domain Validator? |
| --- | --- | --- | --- |
| **Queue jobs** | No | ❌ | ✅ |
| **Scheduler** (`schedules:dispatch-due`, dispatch loop) | No | ❌ | ✅ |
| **Console commands** | No | ❌ | ✅ |
| **Cron / scheduled Artisan** | No | ❌ | ✅ |
| **Event listeners** (queued or sync) | No* | ❌ | ✅ |
| **Background workers** (DO App Platform workers) | No | ❌ | ✅ |

\*Unless the listener is explicitly invoked synchronously from an HTTP request **and** carries the authenticated user through — even then, re-validate domain state at execution time if work is deferred.

**HTTP entry points** (REST API, mobile, admin) continue to use **Policies** as today.

---

## Responsibilities

### Policies — HTTP authorization

Responsible for:

- REST API route protection
- Mobile request authorization
- Admin panel authorization (when shipped)
- Controller-level CRUD gates (`view`, `update`, `delete`, …)
- “Does **this authenticated user** own or may access **this resource** right now?”

Policies answer **access control at the HTTP boundary**. They do **not** guarantee data integrity at a later async tick.

### Domain Validators — asynchronous execution safety

Responsible for:

- **Ownership consistency** — e.g. `schedule.user_id === vibe.user_id === device.user_id`
- **Domain integrity** — referenced entities exist and belong together
- **Missing entities** — deleted vibe, device, provider connection, action row
- **Replay protection** — coordinate with idempotency keys ([ADR-010](ADR-010-scheduler-idempotency-occurrence-key.md))
- **Asynchronous execution safety** — skip or abort side effects safely without corrupting scheduler state

Validators answer **“Is it safe to execute this side effect now?”** without assuming HTTP auth ran.

---

## Future validator pattern (example only — not implemented)

Do **not** implement in this ADR phase. Document the expected shape for Phase 4+ features.

### Example: `ScheduleAutomationValidator`

**Invoked:** After schedule execution commits, before Smart Home enqueue ([`dispatch-integration-review.md`](../specs/scheduler-smart-home-automations/mvp/dispatch-integration-review.md)).

**Responsibilities:**

| Check | Purpose |
| --- | --- |
| Schedule belongs to user | `schedule.user_id` is the authority for this tick |
| Vibe belongs to same user | `schedule.vibe.user_id === schedule.user_id` |
| Devices belong to same user | Each action's `device.user_id === schedule.user_id` |
| ProviderConnection belongs to same user | `device.providerConnection.user_id === schedule.user_id` |
| Missing vibe | Skip SH dispatch |
| Missing device | Skip individual action |
| Missing provider connection | Skip individual action |
| Missing action row | Skip (job layer handles) |
| Replay protection | Caller gates on `'dispatched'` + `occurrence_key` — validator does not replace idempotency |

**Return contract:**

```php
// Pseudocode — NOT implemented
public function validate(Schedule $schedule): bool
{
    // Return false for expected validation failures — do NOT throw.
    // Caller: log, skip side effects, continue batch.
}
```

- Return **`true`** — safe to proceed with side effects
- Return **`false`** — skip safely; log structured context; **do not throw** for expected failures

Throwing is reserved for **unexpected infrastructure errors** (optional — caller may still catch and log without stopping recurrence).

---

## Failure policy

### Security failures must not stop Scheduler recurrence

When domain validation fails **after** a schedule execution row has committed:

| Rule | Detail |
| --- | --- |
| **Do not roll back** | Recurrence already advanced — valid tick must stand |
| **Do not throw to outer catch** | Would incorrectly emit `schedule_execution_failed` push |
| **Skip side effects** | Do not enqueue Smart Home jobs |
| **Log and continue** | Process remaining schedules in batch |

Aligns with [ADR-023](ADR-023-automation-execution-order-and-failure-policy.md).

### Background validation failures — general rules

| Rule | Detail |
| --- | --- |
| **Must be logged** | Structured context — safe IDs only (see Logging) |
| **Must skip safely** | No partial cross-user execution |
| **Must allow remaining work** | One bad row must not abort entire worker/command batch |
| **Must not stop unrelated recurrence** | Scheduler, cron, and queue batches continue |

Platform-wide: **validation failure ≠ infrastructure failure**. Expected domain skips are **soft failures** (log + skip). Unexpected throwables may be caught per feature policy but must not violate recurrence isolation where ADR-023 applies.

---

## Logging

### Allowed in logs and structured context

| Field | Example use |
| --- | --- |
| `schedule_id` | Scheduler automation |
| `vibe_id` | Vibe context |
| `device_id` | Smart Home target |
| `provider_connection_id` | Provider context |
| `action_id` / `vibe_device_action_id` | Action audit |
| `notification_type` | Push taxonomy |
| `job_id` | Queue correlation |
| `queue` | Worker routing |
| `user_id` | Ownership audit (integer ID only) |
| `occurrence_key` | Idempotency |
| `skip_reason` | Validation outcome |

### Forbidden — never log

| Category | Examples |
| --- | --- |
| OAuth tokens | Google, Firebase refresh tokens |
| FCM tokens | Push registration tokens |
| Home Assistant tokens | Long-lived access tokens |
| API keys | Third-party integrations |
| Provider credentials | `access_token`, `encrypted_credentials` |
| Private keys | Signing keys, JWT secrets |
| Secrets | `.env` values, webhook secrets |

Aligns with [ADR-021](ADR-021-notification-security-and-privacy.md). Domain validators and jobs must follow the same hygiene as `SmartHomeActionJob` and `PushNotificationEvents`.

---

## Relationship with existing ADRs

ADR-026 **complements** prior decisions by defining the **runtime security boundary** they assume but do not state explicitly:

| ADR | Relationship |
| --- | --- |
| [ADR-010](ADR-010-scheduler-idempotency-occurrence-key.md) | **Replay protection** — `occurrence_key` idempotency; validators gate *whether* to act, ADR-010 gates *duplicate ticks* |
| [ADR-016](ADR-016-smart-home-async-execution.md) | **Async execution** — jobs run without HTTP; validators required before enqueue |
| [ADR-022](ADR-022-scheduler-smart-home-automation-model.md) | **Composition model** — Schedule → Vibe → VibeDeviceAction; validator enforces cross-entity ownership |
| [ADR-023](ADR-023-automation-execution-order-and-failure-policy.md) | **Failure isolation** — validation skip must not block recurrence |
| [ADR-024](ADR-024-automation-notifications-and-observability.md) | **Observability** — log skip reasons in `schedule_executions.log`; no success push on skip |

ADR-026 is **broader** than ADR-022–025: it is the platform rule; Scheduler + Smart Home is the first implementation reference.

---

## First application — Scheduler + Smart Home (Phase 4)

Concrete integration (documented, not implemented here):

1. `schedules:dispatch-due` commits schedule execution + recurrence
2. On `'dispatched'` only — invoke domain validator (e.g. `ScheduleAutomationValidator`)
3. If valid — `VibeSmartHomeDispatchService::dispatch($vibe)`
4. If invalid — log, optional `schedule_executions.log` skip reason, **no SH jobs**
5. `SmartHomeActionJob` continues to skip missing device/provider at job layer

Details: [`dispatch-integration-review.md`](../specs/scheduler-smart-home-automations/mvp/dispatch-integration-review.md)

---

## Future reuse

This pattern is **required** for all future async features:

| Feature area | Validator concern (examples) |
| --- | --- |
| **Scheduler** | Schedule/vibe ownership, occurrence idempotency |
| **Smart Home** | Device/provider ownership, missing entities |
| **Push Notifications** | Token belongs to user; event targets correct user |
| **Analytics** (future) | Event scoped to user; no cross-tenant aggregation leaks |
| **AI Recommendations** (future) | Input vibe/user ownership |
| **Marketplace** (future) | Purchase/subscription ownership |
| **Admin** (future) | Explicit system-user or elevated context — separate ADR if impersonation |
| **Scenes** (future) | Scene/device ownership chain |
| **Matter / future providers** | Provider connection ownership |

New async features must document their validator in the feature spec and reference ADR-026.

---

## Consequences

### Positive

| Outcome | Why it matters |
| --- | --- |
| **Clear platform rule** | One answer for “why can't I use Policy in a job?” |
| **Defence-in-depth** | Write-time API validation + execute-time domain validation |
| **Safe async scaling** | New features inherit the same pattern |
| **Recurrence protected** | Security skips don't break scheduling |

### Negative / tradeoffs

| Tradeoff | Impact |
| --- | --- |
| **Duplicate checks** | API + validator overlap — intentional |
| **Validator maintenance** | Each async feature needs explicit validator design |
| **Silent skip on mismatch** | Rare edge case — log-only, no user push |

---

## Alternatives Considered

| Alternative | Why not chosen |
| --- | --- |
| **Policies in console/queue** | No auth user — wrong abstraction |
| **Synthetic system user for all jobs** | Masks ownership; dangerous for cross-user bugs |
| **DB-only constraints** | Cannot express all rules; migrations heavy; still need runtime missing-entity checks |
| **Trust API validation only** | Background path bypasses HTTP |
| **Fail recurrence on validation failure** | Punishes user for data corruption |

---

## Related Docs

| Document | Relationship |
| --- | --- |
| [`domain-validation.md`](../architecture/domain-validation.md) | **Practical guide** — flows, table, anti-patterns |
| [`dispatch-integration-review.md`](../specs/scheduler-smart-home-automations/mvp/dispatch-integration-review.md) | First integration point |
| [`schema-domain-review.md`](../specs/scheduler-smart-home-automations/mvp/schema-domain-review.md) | Schema supports validators without migration |
| [ADR-010](ADR-010-scheduler-idempotency-occurrence-key.md) | Replay protection |
| [ADR-016](ADR-016-smart-home-async-execution.md) | Async execution |
| [ADR-021](ADR-021-notification-security-and-privacy.md) | Log/payload privacy |
| [ADR-022](ADR-022-scheduler-smart-home-automation-model.md) | Automation model |
| [ADR-023](ADR-023-automation-execution-order-and-failure-policy.md) | Failure policy |

---

When implementing a Domain Validator, reference this ADR in the PR and add Pest tests for ownership mismatch and safe-skip behaviour.
