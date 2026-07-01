# Scheduler + Smart Home Automations MVP — dispatch integration review

**Status:** Phase 3 complete — documentation only (no runtime changes)  
**Feature ID:** `scheduler-smart-home-automations/mvp`  
**Branch:** `feature/scheduler-smart-home-dispatch-review`  
**Reviewed against:** `back_vibes` at 2026-06-28

**References:** [spec.md](spec.md) · [schema-domain-review.md](schema-domain-review.md) · [ADR-023](../../../decisions/ADR-023-automation-execution-order-and-failure-policy.md) · [ADR-026](../../../decisions/ADR-026-automation-execution-security.md)

> **Scope:** Inspect and document the exact Smart Home integration point for Phase 4. No runtime code, migrations, or behaviour changes in this phase.

---

## 1. Executive summary

The scheduler dispatch loop in `DispatchDueSchedulesCommand` is **idempotent**, **transaction-bound for recurrence state**, and **already isolated from push failures**. Smart Home integration is a **single post-commit hook** in `handle()` when `processSchedule()` returns `'dispatched'`.

| Decision | Recommendation |
| --- | --- |
| **Integration location** | `handle()` foreach loop — **after** `processSchedule()` returns `'dispatched'` |
| **Inside transaction?** | **No** |
| **Inside `processSchedule()`?** | **No** — keep scheduler method focused; side effects in caller |
| **Idempotency gate** | Smart Home dispatch **only** when result === `'dispatched'` |
| **Log update** | **After commit** — merge `smart_home` summary into `schedule_executions.log` |
| **Service reuse** | Call `VibeSmartHomeDispatchService::dispatch($vibe)` directly |
| **Ownership validation** | New domain validation layer in Phase 4 ([ADR-026](../../../decisions/ADR-026-automation-execution-security.md)) |
| **Phase 4 ready?** | **Yes** — no remaining architectural blockers |

---

## 2. P3-1 — Complete execution flow of `DispatchDueSchedulesCommand`

**Class:** `back_vibes/app/Console/Commands/DispatchDueSchedulesCommand.php`  
**Entry:** `php artisan schedules:dispatch-due`  
**Dependencies:** `RecurrenceService`, `PushNotificationEvents`

### 2.1 High-level flow

```
handle()
  │
  ├─► Parse options (--batch, --dry-run)
  ├─► Query due schedules (is_enabled, next_run_at <= now UTC, limit batch)
  │
  ├─► IF dry-run → log count → return SUCCESS (no writes)
  │
  └─► FOR EACH due schedule:
        TRY
          result = processSchedule(schedule, recurrenceService, nowUtc)
          IF result === 'dispatched'     → dispatched++
          IF result === 'skipped_duplicate' → skippedDuplicate++
          [Phase 4: Smart Home hook HERE when 'dispatched']
        CATCH Throwable
          failed++
          warn log
          notifyScheduleFailure(schedule, pushEvents)  → schedule_execution_failed push
        END
      outputSummary()
      return SUCCESS
```

### 2.2 `processSchedule()` — step by step

All steps below run inside **`DB::transaction()`** unless noted.

| Step | Action | Details |
| --- | --- | --- |
| **1** | Parse `scheduledFor` | From `$schedule->next_run_at` (UTC) |
| **2** | Compute `occurrence_key` | `RecurrenceService::computeOccurrenceKey($schedule->id, $scheduledFor)` → `"{id}:{unix}"` |
| **3** | Pre-check duplicate | Query `schedule_executions` for existing `(schedule_id, occurrence_key)` |
| **3a** | If exists | Return `'skipped_duplicate'` — **no writes** |
| **4** | Insert `ScheduleExecution` | `status = 'dispatched'`, `log = json_encode([command, batch_time_utc])` |
| **4a** | On `UniqueConstraintViolationException` | Return `'skipped_duplicate'` (race between workers) |
| **5** | Build `ScheduleInput` | From schedule timezone, start_time, recurrence_type, config |
| **6** | Compute next occurrence | `RecurrenceService::computeNextRunAt($input, $scheduledFor)` |
| **7** | Update schedule | `last_run_at = scheduledFor`, `next_run_at = result`, disable if `once` |
| **8** | Save schedule | `$schedule->save()` |
| **9** | Return `'dispatched'` | Transaction commits |

### 2.3 Transaction boundary

```
┌─────────────────────────────────────────────────────────────┐
│  DB::transaction()  — BEGIN                                 │
│    occurrence_key check                                     │
│    INSERT schedule_executions                               │
│    UPDATE schedules (last_run_at, next_run_at, is_enabled) │
│  COMMIT                                                     │
└─────────────────────────────────────────────────────────────┘
         │
         ▼  (outside transaction)
  return 'dispatched' | 'skipped_duplicate'
         │
         ▼  (in handle(), Phase 4)
  Smart Home enqueue + optional log UPDATE
```

**Commit point:** When `DB::transaction()` closure returns successfully — before `processSchedule()` returns to `handle()`.

### 2.4 Catch block and push path

| Event | Transaction state | Push |
| --- | --- | --- |
| `RecurrenceService` throws (e.g. invalid weekly config, monthly) | **Rolled back** — no execution row, schedule unchanged | `notifyScheduleExecutionFailed()` via `schedule->user` |
| DB error during insert/save | Rolled back | Same failure push |
| Success | Committed | **No push** (success path is silent) |

`notifyScheduleFailure()`:

- Loads `$schedule->user` (no eager-load today — lazy query per failure)
- Creates transient `ScheduleExecution(['schedule_id' => ...])` for payload
- Calls `PushNotificationEvents::notifyScheduleExecutionFailed()` — **never throws**

**Test coverage:** `DispatchDueSchedulesCommandTest` — failure isolation, idempotency, push on failure, no push on success.

### 2.5 `RecurrenceService` role

**Class:** `back_vibes/app/Services/Scheduling/RecurrenceService.php`

- **Pure** — no DB, no side effects
- `computeOccurrenceKey()` — ADR-010 format
- `computeNextRunAt()` — may throw `UnsupportedRecurrenceTypeException`, `InvalidRecurrenceConfigurationException`
- Called **inside** transaction after execution insert — exception rolls back execution row

---

## 3. P3-2 — Exact Smart Home integration point

### Decision: **After commit, in `handle()`, when `processSchedule()` returns `'dispatched'`**

```php
// Phase 4 pseudocode — NOT implemented yet
$result = $this->processSchedule($schedule, $recurrenceService, $nowUtc);

if ($result === 'dispatched') {
    $this->dispatchSmartHomeForSchedule($schedule, $nowUtc); // new private method
}
```

### Option analysis

| Option | Verdict | Why |
| --- | --- | --- |
| **Before transaction** | ❌ Reject | Would run even when duplicate or when recurrence fails later |
| **Inside transaction** | ❌ Reject | Queue enqueue must not participate in DB rollback; violates ADR-016; job dispatch latency in transaction |
| **Inside `processSchedule()` after transaction** | ⚠️ Possible | Works technically, but mixes scheduler + Smart Home concerns; harder to test in isolation |
| **In `handle()` after `processSchedule()` returns `'dispatched'`** | ✅ **Recommended** | Clear separation; matches push failure pattern in same method; try/catch isolated from transaction |
| **After commit via DB event/listener** | ❌ Overkill | Unnecessary indirection for MVP |

### Why after commit

1. **Recurrence must advance first** — ADR-023: Smart Home failure must not block recurrence; conversely, recurrence commit must succeed before side effects.
2. **Job enqueue is not transactional** — if enqueue failed inside transaction, we'd roll back a valid schedule tick.
3. **Idempotency** — `'dispatched'` guarantees a **new** execution row was committed; `'skipped_duplicate'` means no new occurrence.

### Why in `handle()` not `processSchedule()`

1. `processSchedule()` stays scheduler-only (audit + recurrence).
2. Smart Home dispatch can be wrapped in **try/catch** without affecting transaction semantics.
3. `VibeSmartHomeDispatchService` injected into command `handle()` — no change to `processSchedule()` signature.
4. Consistent with push notification orchestration already living in `handle()` catch block.

### Dry-run

When `--dry-run` is set, `handle()` returns early — **no `processSchedule()` calls**. Smart Home dispatch must **never** run on dry-run.

---

## 4. P3-3 — Idempotency review

### Duplicate tick prevention (existing)

| Layer | Mechanism |
| --- | --- |
| **Optimistic pre-check** | `ScheduleExecution::exists(schedule_id, occurrence_key)` |
| **DB unique index** | `uq_sch_exec_schedule_occurrence` on `(schedule_id, occurrence_key)` |
| **Race handling** | Catch `UniqueConstraintViolationException` → `'skipped_duplicate'` |
| **Recurrence guard** | On `'skipped_duplicate'`, transaction returns early — **`next_run_at` not advanced** |

**Test:** `pre-existing execution with same occurrence_key skips without double-advancing` — confirms duplicate tick does not advance recurrence.

**Test:** `running command twice does not create duplicate execution` — with manual reset of `next_run_at`, second tick is `'skipped_duplicate'`.

### Smart Home idempotency rule (Phase 4)

```
processSchedule() result     Smart Home dispatch?
─────────────────────────    ────────────────────
'dispatched'                 YES — new occurrence committed
'skipped_duplicate'          NO  — occurrence already recorded
(thrown exception)           NO  — transaction rolled back
dry-run                      NO  — no processSchedule call
```

### Why `'skipped_duplicate'` must never enqueue

1. **Same occurrence already processed** — a prior tick (or race winner) already recorded the execution and likely already enqueued Smart Home jobs in Phase 4.
2. **Double-enqueue** — dispatching again would duplicate `SmartHomeActionJob` for the same logical occurrence (e.g. turn off light twice).
3. **Recurrence not advanced** — duplicate path means we're re-processing the same `next_run_at` instant; Smart Home should have fired on the first `'dispatched'`.

### Phase 4 optional hardening

Include `occurrence_key` in job log context or a future job payload field for audit correlation — **not required** for idempotency if dispatch is gated on `'dispatched'`.

---

## 5. P3-4 — Ownership guarantees review

Background jobs and console commands **do not** have an authenticated HTTP user. Laravel Policies (`SchedulePolicy`, `VibePolicy`) **do not apply** to `schedules:dispatch-due` ([ADR-026](../../../decisions/ADR-026-automation-execution-security.md)).

### Assumption matrix

| Assumption | DB-enforced? | API-enforced? | Always true at runtime? |
| --- | --- | --- | --- |
| `Schedule.user_id == Vibe.user_id` | **No** — only separate FKs | **Yes** — `StoreScheduleRequest` / `UpdateScheduleRequest` `validateVibeOwnership()` | **Only if data created via API** |
| `Device.user_id == Schedule.user_id` | **No** | **Partial** — `StoreVibeDeviceActionRequest` validates device belongs to auth user; vibe authorized via `VibePolicy` | **Only if actions created via API** |
| `ProviderConnection.user_id == Schedule.user_id` | **No** | **Partial** — device creation/sync validates connection ownership | **Expected via normal API flows** |
| `Vibe.user_id == VibeDeviceAction.vibe.user_id` | **Yes** — FK cascade on vibe | N/A | **Yes** |

### Gaps (runtime security considerations for Phase 4)

| Gap | Risk | Phase 4 mitigation |
| --- | --- | --- |
| Schedule references another user's vibe (tinker, bad migration, bug) | Could dispatch another user's vibe actions from wrong schedule context | Domain validator: `$schedule->vibe->user_id === $schedule->user_id` — on failure: log + skip SH, **do not** fail recurrence |
| Vibe action references another user's device | Could trigger wrong user's HA devices | Validator: each action's `device.user_id === schedule.user_id` — skip offending actions |
| Orphan vibe (deleted between query and dispatch) | Unlikely — vibe loaded after commit | Null vibe → skip SH, log warning |

**Important:** Security validation failures **must not** roll back schedule execution or block recurrence ([ADR-026](../../../decisions/ADR-026-automation-execution-security.md)).

### What API validation covers today

| Path | Validation |
| --- | --- |
| Schedule create/update | `vibe_id` exists + `vibes.user_id == auth()->id()` |
| Device action create | `device_id` exists + `devices.user_id == auth()->id()` + `VibePolicy::update` |
| Manual SH dispatch | `VibePolicy::view` + service loads actions for that vibe only |

**None of this runs in the console command today.**

---

## 6. P3-5 — `schedule_executions.log` review

### Current format

Set at execution **create** inside transaction:

```json
{
  "command": "schedules:dispatch-due",
  "batch_time_utc": "2026-06-28T22:00:00+00:00"
}
```

| Property | Value |
| --- | --- |
| Column | `text`, nullable |
| Model cast | **None** — string in/out |
| Resource | `ScheduleExecutionResource` returns raw `log` string |

### Recommended Smart Home summary (Phase 4)

Merge after successful dispatch:

```json
{
  "command": "schedules:dispatch-due",
  "batch_time_utc": "2026-06-28T22:00:00+00:00",
  "smart_home": {
    "dispatched": 2,
    "skipped": 0,
    "action_ids": [10, 11],
    "vibe_id": 45
  }
}
```

On ownership validation skip:

```json
{
  "command": "schedules:dispatch-due",
  "batch_time_utc": "...",
  "smart_home": {
    "skipped_reason": "ownership_mismatch",
    "dispatched": 0,
    "skipped": 0,
    "action_ids": []
  }
}
```

### When to update log

| Timing | Verdict | Why |
| --- | --- | --- |
| **During transaction (initial create)** | ❌ | Smart Home summary unknown until after commit and dispatch |
| **During transaction (before commit, after enqueue inside processSchedule)** | ❌ | Enqueue must not be in transaction |
| **After commit** | ✅ **Recommended** | Execution row exists; dispatch result available; failure to update log must not affect recurrence |

### Post-commit update pattern (Phase 4)

```php
ScheduleExecution::query()
    ->where('schedule_id', $schedule->id)
    ->where('occurrence_key', $occurrenceKey)
    ->update(['log' => json_encode($mergedLog)]);
```

Compute `$occurrenceKey` from `$schedule->last_run_at` (just committed) or recompute via `RecurrenceService` from pre-advance `next_run_at` snapshot.

**Log update failure:** catch, log warning, continue — must not throw to `handle()` catch (would incorrectly emit `schedule_execution_failed` push).

---

## 7. P3-6 — `VibeSmartHomeDispatchService` review

**Class:** `back_vibes/app/SmartHome/Services/VibeSmartHomeDispatchService.php`

### Dependencies

| Dependency | Type | Notes |
| --- | --- | --- |
| None injected | — | Stateless service; uses facades/models directly |
| `VibeDeviceAction` | Model query | `where('vibe_id')->with('device')->orderBy('sort_order')` |
| `SmartHomeActionJob` | Queue dispatch | `SmartHomeActionJob::dispatch($action->id)` |

### Input / output

| | Detail |
| --- | --- |
| **Input** | `Vibe $vibe` — Eloquent model |
| **Output** | `SmartHomeDispatchResult` — `vibe_id`, `dispatched`, `skipped`, `action_ids[]` |
| **Auth context** | **Not required** |

### Behaviour

| Behaviour | Detail |
| --- | --- |
| Order | `sort_order ASC` |
| Missing device | Skip, increment `skipped` |
| Provider calls | **None** — enqueue only |
| Empty action list | Returns `dispatched: 0`, `action_ids: []` |
| `delay_seconds` | **Not applied** — all jobs enqueue immediately (pre-existing) |

### Possible exceptions

| Source | Likelihood | Phase 4 handling |
| --- | --- | --- |
| DB query failure | Low | try/catch in hook — log, skip SH, recurrence already committed |
| Queue connection failure | Low–medium | Same — log enqueue failure |
| Service code | No explicit throws | — |

### Queue behaviour

- `SmartHomeActionJob` uses queue name **`smart-home`**
- Job: `$tries = 3`, `$timeout = 30`
- Job handles missing action/device/connection gracefully — logs, returns without throw
- Provider failure → push `smart_home_action_failed` — does not affect scheduler

### Reusable from scheduler?

**Yes — directly, without wrapper.**

Mobile path (`VibeSmartHomeDispatchController`) already:

1. Authorizes vibe (HTTP only)
2. Calls `$this->dispatchService->dispatch($vibe)`
3. Returns JSON summary

Scheduler path (Phase 4):

1. Domain-validates ownership ([ADR-026](../../../decisions/ADR-026-automation-execution-security.md))
2. Loads `$schedule->vibe` (eager-load in batch query)
3. Calls same `dispatch($vibe)`
4. Optionally merges result into `schedule_executions.log`

### Test coverage (existing)

**`VibeSmartHomeDispatchApiTest`** — auth, job count, sort order, no HTTP inline, empty actions.  
**`SmartHomeActionJobTest`** — provider execution, failure push, skip paths.  
**Gap for Phase 4:** `DispatchDueSchedulesCommandTest` — scheduler-triggered enqueue (Phase 7).

---

## 8. Phase 4 implementation blueprint

### 8.1 Command changes (sketch)

```php
public function handle(
    RecurrenceService $recurrenceService,
    PushNotificationEvents $pushEvents,
    VibeSmartHomeDispatchService $smartHomeDispatch,  // NEW
): int {
    // ... existing query — consider ->with('vibe') ...

    foreach ($due as $schedule) {
        try {
            $result = $this->processSchedule(...);

            if ($result === 'dispatched') {
                $this->dispatchSmartHomeAfterSchedule($schedule, $smartHomeDispatch, $nowUtc);
            }
            // ... existing counters ...
        } catch (Throwable $e) {
            // ... unchanged ...
        }
    }
}
```

### 8.2 New private method responsibilities

1. Load vibe (already on schedule if eager-loaded)
2. Run domain ownership validation ([ADR-026](../../../decisions/ADR-026-automation-execution-security.md))
3. Call `VibeSmartHomeDispatchService::dispatch($vibe)`
4. Optionally update `schedule_executions.log`
5. try/catch — **never rethrow** to outer catch

### 8.3 Eager loading (Phase 4)

```php
Schedule::query()
    ->with('vibe')
    // optional: ->with('vibe.deviceActions.device')
    ...
```

---

## 9. Remaining risks before Phase 4

| ID | Risk | Mitigation in Phase 4 |
| --- | --- | --- |
| R-1 | Ownership mismatch in DB | Domain validator — skip SH, log |
| R-2 | Log update throws → false failure push | Isolate log update in inner try/catch |
| R-3 | Queue down → silent SH miss | Log; recurrence still advances (accepted) |
| R-4 | `delay_seconds` ignored | Document; defer staggered dispatch |
| R-5 | No `schedule_id` in SH failure push | Phase 6 payload extension |
| R-6 | Batch N+1 on vibe load | Eager-load `vibe` on due query |

---

## 10. Sign-off

| Item | Status |
| --- | --- |
| P3-1 Dispatch flow documented | ✅ |
| P3-2 Integration point defined | ✅ — `handle()`, after commit, `'dispatched'` only |
| P3-3 Idempotency confirmed | ✅ |
| P3-4 Ownership reviewed | ✅ — Phase 4 validator required |
| P3-5 Log strategy defined | ✅ — post-commit merge |
| P3-6 Service reuse confirmed | ✅ — direct reuse |
| ADR-026 security model | ✅ |
| Ready for Phase 4 implementation | ✅ |

---

## Appendix — files inspected (read-only)

| File | Purpose |
| --- | --- |
| `app/Console/Commands/DispatchDueSchedulesCommand.php` | Dispatch flow |
| `app/Services/Scheduling/RecurrenceService.php` | Occurrence key + recurrence |
| `app/Models/ScheduleExecution.php` | Execution model |
| `app/SmartHome/Services/VibeSmartHomeDispatchService.php` | SH enqueue |
| `app/SmartHome/DTOs/SmartHomeDispatchResult.php` | Result DTO |
| `app/Jobs/SmartHome/SmartHomeActionJob.php` | Async execution |
| `app/PushNotifications/Services/PushNotificationEvents.php` | Failure push |
| `tests/Feature/Scheduling/DispatchDueSchedulesCommandTest.php` | Scheduler tests |
| `tests/Feature/SmartHome/VibeSmartHomeDispatchApiTest.php` | Dispatch API tests |
| `tests/Feature/SmartHome/SmartHomeActionJobTest.php` | Job tests |

**No files in `back_vibes` or `front_vibes` were modified during Phase 3.**
