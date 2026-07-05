# Domain validation — HTTP authorization vs background execution

**Status:** Active architecture guide  
**ADR:** [ADR-026](../decisions/ADR-026-automation-execution-security.md)  
**Applies to:** `back_vibes` and all future Ixora backend async features

> **Rule of thumb:** If there is no authenticated HTTP user in the call stack, **do not use Policies**. Use a **Domain Validator**.

---

## Why this guide exists

Ixora has two distinct security surfaces:

1. **HTTP boundary** — mobile app, admin panel, REST API. Users authenticate via Firebase JWT. Laravel **Policies** decide whether the authenticated user may access or mutate a resource.

2. **Background boundary** — queue workers, scheduler commands, cron, event listeners. **No user is logged in.** Policies either cannot run or would require artificial hacks (fake users, `Gate::forUser()` with guessed identity).

Form Request validation at API write time ensures **correct data on create/update**. It does **not** guarantee integrity when a job runs minutes later, when data may have been changed outside the API, or when duplicate ticks occur.

**Domain Validators** close the gap: they re-check ownership and entity existence **at execution time**, without an HTTP session.

---

## Validation mechanism by execution source

| Execution source | Validation mechanism | Auth context |
| --- | --- | --- |
| **HTTP Request** | Laravel **Policy** | Firebase JWT → `auth()->user()` |
| **REST API** | Laravel **Policy** + Form Request | Authenticated user |
| **Mobile** | Laravel **Policy** + Form Request | Authenticated user |
| **Admin Panel** | Laravel **Policy** + Form Request | Authenticated admin user |
| **Queue Job** | **Domain Validator** | None |
| **Scheduler** | **Domain Validator** | None |
| **Console Command** | **Domain Validator** | None |
| **Event Listener** | **Domain Validator** | None (unless sync from HTTP with immediate validation) |
| **Cron** | **Domain Validator** | None |

---

## Correct flows

### HTTP path (good)

```
Client (mobile / admin)
    │
    ▼
Controller
    │
    ▼
Policy  ──── "Does auth()->user() own this Schedule?"
    │
    ▼
Form Request  ──── validation rules + ownership hooks
    │
    ▼
Domain (persist / respond)
```

**Example:** `ScheduleController@store` → `SchedulePolicy` → `StoreScheduleRequest::validateVibeOwnership()` → create schedule.

Policies answer: **“Is this user allowed to make this HTTP request?”**

### Background path (good)

```
Scheduler / Queue / Cron / Listener
    │
    ▼
Domain Validator  ──── ownership, missing entities, replay gates
    │
    ▼
Domain (enqueue side effect / mutate state)
    │
    ▼
Queue Job (optional second validator pass at job handle)
```

**Example (future Phase 4):** `DispatchDueSchedulesCommand` → commit execution → `ScheduleAutomationValidator::validate($schedule)` → `VibeSmartHomeDispatchService::dispatch($vibe)`.

Validators answer: **“Is it still safe to execute this side effect given current DB state?”**

---

## Anti-patterns

### Scheduler → Policy (bad)

```
schedules:dispatch-due
    │
    ▼
$this->authorize('view', $schedule)   ❌
```

**Why bad:** No authenticated user. Policy expects `$user->id === $schedule->user_id` but `$user` is null or meaningless. May false-pass, false-fail, or throw inconsistently.

### Queue Job → Gate::authorize() (bad)

```
SmartHomeActionJob::handle()
    │
    ▼
Gate::authorize('update', $vibe)   ❌
```

**Why bad:** Gate/Policies assume an authenticated user and an HTTP authorization context. Jobs receive IDs from the queue — identity must be derived from **domain data** (device.user_id, schedule.user_id), not from `auth()`.

### Trust write-time validation only (bad)

```
// Schedule created via API with correct vibe_id — good at t=0
// ... hours later ...
schedules:dispatch-due
    │
    ▼
VibeSmartHomeDispatchService::dispatch($vibe)   ❌ no re-check
```

**Why bad:** Data may have been corrupted via tinker, bug, or cross-user reference. API validation at create time does not protect execute time.

### Validator throws on expected failure (bad)

```
if ($schedule->vibe->user_id !== $schedule->user_id) {
    throw new SecurityException();   ❌
}
```

**Why bad:** Outer catch may roll back unrelated state, emit wrong push notifications, or abort the entire batch. Expected validation failures should return **`false`** and let the caller skip safely ([ADR-026](../decisions/ADR-026-automation-execution-security.md)).

---

## Policy vs Validator — responsibility split

| Concern | Policy (HTTP) | Domain Validator (async) |
| --- | --- | --- |
| User authenticated? | Yes — required | No — N/A |
| CRUD authorization | ✅ | ❌ |
| Ownership at request time | ✅ | ❌ |
| Ownership at execution time | ❌ | ✅ |
| Missing entity (deleted device) | Partial (404 on show) | ✅ skip safely |
| Replay / duplicate tick | ❌ | ✅ with `occurrence_key` |
| Batch continuation on skip | N/A | ✅ must continue |

**Both layers are required** for features that have HTTP CRUD **and** async side effects.

---

## Domain Validator design guidelines

### Naming

Use explicit names tied to the domain action:

- `ScheduleAutomationValidator` — schedule tick → Smart Home
- `PushNotificationTargetValidator` — (future) ensure tokens belong to event user
- `VibeExportValidator` — (future) offline/export jobs

Avoid generic `SecurityService` — validators should be **scoped to one execution path**.

### Return contract

| Return | Meaning | Caller action |
| --- | --- | --- |
| `true` | Safe to execute side effects | Proceed |
| `false` | Expected validation failure | Log, skip, continue batch |

Do **not** throw for expected failures (ownership mismatch, missing vibe). Throwing is for unexpected infrastructure errors only — and callers should still avoid stopping recurrence ([ADR-023](../decisions/ADR-023-automation-execution-order-and-failure-policy.md)).

### What to validate

| Category | Examples |
| --- | --- |
| **Ownership chain** | schedule.user_id === vibe.user_id === device.user_id |
| **Existence** | vibe, device, provider_connection, action row not null |
| **Idempotency gate** | Caller already confirmed `'dispatched'` / unique job key |
| **Scope** | Push event user matches token owner |

### What not to do

- Call Policies or `Gate::authorize()`
- Log secrets (tokens, credentials) — see ADR-026 logging table
- Stop scheduler recurrence on validation failure
- Assume Form Request ran at execution time

---

## Example validator sketch (not implemented)

```php
// Pseudocode — documentation only
final class ScheduleAutomationValidator
{
    public function validate(Schedule $schedule): bool
    {
        $vibe = $schedule->vibe;

        if ($vibe === null) {
            return false;
        }

        if ($vibe->user_id !== $schedule->user_id) {
            return false;
        }

        // Optional per-action checks when loading actions explicitly
        return true;
    }
}
```

Caller in `DispatchDueSchedulesCommand` (Phase 4):

```php
if ($result === 'dispatched' && $validator->validate($schedule)) {
    $smartHomeDispatch->dispatch($schedule->vibe);
}
```

---

## Logging (safe context only)

When validation fails, log:

```json
{
  "event": "domain_validation_failed",
  "validator": "ScheduleAutomationValidator",
  "schedule_id": 123,
  "vibe_id": 45,
  "user_id": 7,
  "skip_reason": "vibe_user_mismatch"
}
```

Never log tokens, credentials, or provider secrets. Full rules: [ADR-026 § Logging](../decisions/ADR-026-automation-execution-security.md#logging).

---

## Future reuse map

| Feature | Async entry | Validator needed |
| --- | --- | --- |
| **Scheduler + Smart Home** | `schedules:dispatch-due` | `ScheduleAutomationValidator` (Phase 4) |
| **Smart Home jobs** | `SmartHomeActionJob` | Job-layer existence checks (partial today); extend for ownership |
| **Push Notifications** | `PushNotificationJob` | Token/user/event consistency |
| **Analytics** | Future queue jobs | User/event scope |
| **AI Recommendations** | Future jobs | Input resource ownership |
| **Marketplace** | Future jobs | Purchase entitlements |
| **Admin bulk actions** | Future commands | Elevated context — separate spec |
| **Scenes** | Future automation | Scene/device/connection chain |
| **Matter / providers** | Future jobs | Provider connection ownership |

Every new row in this table requires a spec section + reference to ADR-026 before implementation.

---

## Related docs

| Document | Role |
| --- | --- |
| [ADR-026](../decisions/ADR-026-automation-execution-security.md) | Platform decision — authoritative |
| [ADR-010](../decisions/ADR-010-scheduler-idempotency-occurrence-key.md) | Replay protection |
| [ADR-016](../decisions/ADR-016-smart-home-async-execution.md) | Async Smart Home |
| [ADR-023](../decisions/ADR-023-automation-execution-order-and-failure-policy.md) | Failure isolation |
| [dispatch-integration-review.md](../specs/scheduler-smart-home-automations/mvp/dispatch-integration-review.md) | First integration |
| [laravel-form-request-patterns.md](../standards/laravel-form-request-patterns.md) | HTTP validation (complementary) |
