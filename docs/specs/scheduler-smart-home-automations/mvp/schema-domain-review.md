# Scheduler + Smart Home Automations MVP — schema & domain review

**Status:** Phase 2 complete — review only (no runtime changes)  
**Feature ID:** `scheduler-smart-home-automations/mvp`  
**Branch:** `feature/scheduler-smart-home-domain-review`  
**Reviewed against:** `back_vibes` at time of Phase 2 (2026-06-28)

**References:** [spec.md](spec.md) · [ADR-022](../../../decisions/ADR-022-scheduler-smart-home-automation-model.md) · [ADR-023](../../../decisions/ADR-023-automation-execution-order-and-failure-policy.md) · [ADR-024](../../../decisions/ADR-024-automation-notifications-and-observability.md) · [ADR-025](../../../decisions/ADR-025-automation-mobile-ux.md)

> **Scope:** Documentation/review only. No migrations, models, controllers, or runtime changes were made in this phase.

---

## 1. Executive summary

**Conclusion: Option A — no migrations required for MVP.**

The existing schema and Eloquent model layer **fully supports** the Scheduler + Smart Home Automations composition model (`Schedule` → `Vibe` → `VibeDeviceAction[]`) without new tables, columns, or indexes.

| Area | Verdict |
| --- | --- |
| **`schedules` → `vibes` FK** | ✅ Required `vibe_id`, cascade on vibe delete |
| **`vibe_device_actions` schema** | ✅ Complete — includes `sort_order`, timestamps, indexes |
| **Model relationships** | ✅ `Schedule::vibe()`, `Vibe::deviceActions()`, `Vibe::schedules()` |
| **`schedule_executions.log`** | ✅ Nullable `text`; JSON string storage sufficient for Smart Home summary |
| **`VibeSmartHomeDispatchService`** | ✅ Reusable from scheduler path — no wrapper required for MVP |
| **`automations` table** | ❌ Not needed |
| **`schedule_device_actions` table** | ❌ Not needed |
| **`action_execution_logs` table** | ❌ Not needed for MVP |

**Gaps are API/resource and runtime-integration only** (Phase 4–5), not schema:

- Scheduler dispatch does not yet call `VibeSmartHomeDispatchService` (Phase 4).
- `ScheduleResource` / `VibeResource` lack embed fields for mobile surfacing (Phase 5).
- `delay_seconds` is stored but **not enforced** at job dispatch time (pre-existing Smart Home behaviour — document as open question).
- `VibeSmartHomeDispatchService` performs no ownership check — scheduler caller must load vibe via authorized schedule context (Phase 3/4 design note).

---

## 2. Current schema inventory

### 2.1 `schedules`

| Source | Path |
| --- | --- |
| Create migration | `back_vibes/database/migrations/2026_05_01_000007_create_schedules_table.php` |
| MVP hardening | `back_vibes/database/migrations/2026_06_12_000001_add_scheduler_mvp_columns_to_schedules_table.php` |

| Column | Type | Nullable | Notes |
| --- | --- | --- | --- |
| `id` | bigint PK | no | |
| `user_id` | FK → `users` | no | `cascadeOnDelete` |
| `vibe_id` | FK → `vibes` | no | **Required** — `unsignedBigInteger`, no `nullable()` |
| `name` | string | no | |
| `timezone` | string(64) | no | Added in MVP hardening |
| `start_time` | datetime | no | |
| `recurrence_type` | string | no | Default `'once'` after data migration |
| `recurrence_config` | json | yes | |
| `is_enabled` | boolean | no | Default `true` |
| `next_run_at` | timestamp | yes | Dispatcher query index |
| `last_run_at` | timestamp | yes | |
| `created_at` | timestamp | no | |
| `updated_at` | timestamp | yes | Added in MVP hardening |

**Indexes:** `idx_schedules_user`, `idx_schedules_vibe`, `idx_schedules_user_enabled`, `idx_schedules_user_start`, `idx_schedules_next_run_enabled`, `idx_schedules_user_vibe`.

### 2.2 `schedule_executions`

| Source | Path |
| --- | --- |
| Create migration | `back_vibes/database/migrations/2026_05_01_000008_create_schedule_executions_table.php` |
| MVP hardening | `back_vibes/database/migrations/2026_06_12_000002_add_scheduler_mvp_columns_to_schedule_executions_table.php` |

| Column | Type | Nullable | Notes |
| --- | --- | --- | --- |
| `id` | bigint PK | no | |
| `schedule_id` | FK → `schedules` | no | `cascadeOnDelete` |
| `occurrence_key` | string(64) | no | Unique with `schedule_id` (ADR-010) |
| `scheduled_for` | timestamp | no | |
| `executed_at` | datetime | no | |
| `status` | string | no | Default `'dispatched'` |
| `log` | **text** | **yes** | Stores JSON string today |
| `created_at` | timestamp | no | No `updated_at` on model |

**Unique index:** `uq_sch_exec_schedule_occurrence` on `(schedule_id, occurrence_key)`.

### 2.3 `vibe_device_actions`

| Source | Path |
| --- | --- |
| Create migration | `back_vibes/database/migrations/2026_05_01_000006_create_vibe_device_actions_table.php` |
| Hardening | `back_vibes/database/migrations/2026_06_14_000003_harden_vibe_device_actions_table.php` |

| Column | Type | Nullable | Notes |
| --- | --- | --- | --- |
| `id` | bigint PK | no | |
| `vibe_id` | FK → `vibes` | no | `cascadeOnDelete` |
| `device_id` | FK → `devices` | no | `cascadeOnDelete` |
| `action_type` | string | no | MVP: `turn_on`, `turn_off`, `toggle` |
| `parameters` | json | yes | |
| `delay_seconds` | unsigned small int | no | Default `0` |
| `sort_order` | unsigned int | no | Default `0` — added in hardening |
| `created_at` | timestamp | no | |
| `updated_at` | timestamp | yes | Added in hardening |

**Indexes:** `idx_vda_vibe`, `idx_vda_device`, `idx_vda_vibe_sort` on `(vibe_id, sort_order)`.

### 2.4 Tables explicitly not required

| Table | Needed? | Reason |
| --- | --- | --- |
| `automations` | **No** | Composition uses existing entities ([ADR-022](../../../decisions/ADR-022-scheduler-smart-home-automation-model.md)) |
| `schedule_device_actions` | **No** | Actions stay vibe-scoped ([ADR-015](../../../decisions/ADR-015-vibe-device-action-architecture.md)) |
| `action_execution_logs` | **No (MVP)** | `schedule_executions.log` + worker logs sufficient ([ADR-024](../../../decisions/ADR-024-automation-notifications-and-observability.md)) |

---

## 3. Current model relationships

```
User
 ├── hasMany Schedule          app/Models/User.php::schedules()
 ├── hasMany Vibe              app/Models/User.php::vibes()
 └── hasMany Device            app/Models/User.php::devices()

Schedule
 ├── belongsTo User            app/Models/Schedule.php::user()
 ├── belongsTo Vibe            app/Models/Schedule.php::vibe()
 └── hasMany ScheduleExecution app/Models/Schedule.php::executions()

Vibe
 ├── belongsTo User            app/Models/Vibe.php::user()
 ├── hasMany VibeDeviceAction  app/Models/Vibe.php::deviceActions()  ← orderBy sort_order
 └── hasMany Schedule          app/Models/Vibe.php::schedules()

VibeDeviceAction
 ├── belongsTo Vibe            app/Models/VibeDeviceAction.php::vibe()
 └── belongsTo Device          app/Models/VibeDeviceAction.php::device()

ScheduleExecution
 └── belongsTo Schedule        app/Models/ScheduleExecution.php::schedule()

Device
 └── hasMany VibeDeviceAction  app/Models/Device.php::vibeDeviceActions()
```

All relationships required for automation composition **exist today**. No new Eloquent relationships are strictly required for Phase 4 dispatch integration.

---

## 4. Schedule → Vibe verification

### Questions & answers

| Question | Answer |
| --- | --- |
| Does `schedules` have `vibe_id`? | **Yes** — column defined in create migration |
| Is `vibe_id` required or nullable? | **Required** — `unsignedBigInteger('vibe_id')` with no `nullable()` |
| FK behaviour on vibe delete? | **`cascadeOnDelete`** — deleting a vibe deletes its schedules (`fk_schedules_vibe`) |
| Does `Schedule` define `vibe()`? | **Yes** — `belongsTo(Vibe::class)` |
| Does `Vibe` define schedule relationship? | **Yes** — `schedules(): HasMany` |
| Does `User` define schedules? | **Yes** — `schedules(): HasMany` |
| Does `ScheduleResource` expose vibe? | **`vibe_id` only** — no nested `vibe` object or name |
| Enough to know which vibe runs when due? | **Yes (backend)** — `$schedule->vibe_id` / `$schedule->vibe` resolves target vibe. API list does not yet expose action summary (Phase 5). |

### API validation

`StoreScheduleRequest` / `UpdateScheduleRequest` validate:

- `vibe_id` required, exists in `vibes`
- Custom `validateVibeOwnership()` — vibe must belong to `auth()->id()`

**Files:**

- Migration: `database/migrations/2026_05_01_000007_create_schedules_table.php` (lines 22–34)
- Model: `app/Models/Schedule.php` (lines 43–46)
- Resource: `app/Http/Resources/ScheduleResource.php` (line 14: `'vibe_id'`)
- Request: `app/Http/Requests/StoreScheduleRequest.php` (lines 21, 51–66)

### Cascade implications for automation

When a vibe is deleted, schedules referencing it are **removed** (cascade). Device actions on the vibe are also cascade-deleted via `vibe_device_actions.vibe_id`. No orphan automation state is possible at the schema level.

---

## 5. Vibe → VibeDeviceAction verification

### Questions & answers

| Question | Answer |
| --- | --- |
| Does `vibe_device_actions` exist? | **Yes** |
| All expected columns present? | **Yes** — see §2.3 |
| Indexes sufficient? | **Yes** — vibe FK, device FK, `(vibe_id, sort_order)` for ordered fetch |
| FKs correct? | **Yes** — both `vibe_id` and `device_id` cascade on delete |
| `Vibe::deviceActions()` ordered? | **Yes** — `hasMany(...)->orderBy('sort_order')` |
| `VibeDeviceAction::vibe()` / `device()`? | **Yes** |
| Action types limited to MVP set? | **Yes (API layer)** — `ActionType` enum + `Rule::in()` in Form Requests |
| Enough for automation dispatch? | **Yes** — service loads by `vibe_id`, orders by `sort_order`, enqueues jobs |

### Action type enforcement

| Layer | Enforcement |
| --- | --- |
| **Database** | Open `string` — no DB enum |
| **API** | `StoreVibeDeviceActionRequest` / `UpdateVibeDeviceActionRequest` — `Rule::in(ActionType::mvpAllowed())` |
| **Enum** | `app/SmartHome/ActionType.php` — `turn_on`, `turn_off`, `toggle` |
| **Dispatch service** | No re-validation — trusts stored rows |
| **Job** | Adapter may throw `UnsupportedSmartHomeActionException` for unknown types |

### Gaps (non-schema)

| Gap | Severity | Notes |
| --- | --- | --- |
| **`delay_seconds` not applied at dispatch** | Low (pre-existing) | Column exists; `VibeSmartHomeDispatchService` and `SmartHomeActionJob` enqueue/run immediately. Automation spec does not require delay for MVP — document in Phase 3 if product wants staggered actions. |
| **No `is_active` flag on actions** | None for MVP | All rows dispatch; matches current manual play path |
| **No ownership check in dispatch service** | Expected | Controller uses `VibePolicy`; scheduler must load vibe via schedule (same user owns both) |

**Files:**

- Migrations: `2026_05_01_000006_create_vibe_device_actions_table.php`, `2026_06_14_000003_harden_vibe_device_actions_table.php`
- Model: `app/Models/VibeDeviceAction.php`, `app/Models/Vibe.php` (lines 47–50)
- Enum: `app/SmartHome/ActionType.php`
- Resource: `app/Http/Resources/VibeDeviceActionResource.php`

---

## 6. ScheduleExecution.log review

### Questions & answers

| Question | Answer |
| --- | --- |
| Does `schedule_executions` have `log`? | **Yes** — `text`, nullable |
| JSON or text? | **`text`** column — not PostgreSQL `json` type |
| Cast to array/json in model? | **No** — `ScheduleExecution` model has no `log` cast; stored/returned as string |
| Can it store Smart Home dispatch summary? | **Yes** |
| Migration required? | **No** |

### Current usage

`DispatchDueSchedulesCommand` already writes JSON to `log` on create:

```php
'log' => json_encode([
    'command' => 'schedules:dispatch-due',
    'batch_time_utc' => $nowUtc->toIso8601String(),
]),
```

**Suggested Phase 4 shape** (merge into existing object or post-commit update):

```json
{
  "command": "schedules:dispatch-due",
  "batch_time_utc": "2026-06-28T22:00:00+00:00",
  "smart_home": {
    "dispatched": 2,
    "skipped": 0,
    "action_ids": [10, 11]
  }
}
```

### Storage safety

| Concern | Assessment |
| --- | --- |
| Text column holds JSON string | ✅ Standard pattern — same as current dispatcher |
| Nullable | ✅ Safe — log optional; dispatcher always sets it today |
| Size | ✅ Summary is small (few action IDs) — well within `text` limits |
| Model cast | Optional improvement in Phase 4 — `log` could cast to `array` for cleaner updates; **not required for MVP** |

**Files:**

- Migration: `2026_05_01_000008_create_schedule_executions_table.php` (line 25)
- Model: `app/Models/ScheduleExecution.php` — `log` in fillable, no cast
- Resource: `app/Http/Resources/ScheduleExecutionResource.php` (line 19) — returns raw `log`
- Command: `app/Console/Commands/DispatchDueSchedulesCommand.php` (lines 122–125)

---

## 7. Dispatch service review

**Class:** `app/SmartHome/Services/VibeSmartHomeDispatchService.php`  
**DTO:** `app/SmartHome/DTOs/SmartHomeDispatchResult.php`

### Behaviour summary

| Question | Answer |
| --- | --- |
| Input to `dispatch()`? | **`Vibe $vibe`** — Eloquent model instance |
| Requires authenticated user? | **No** — no auth/session access |
| Ownership check? | **No** — assumes caller already authorized the vibe |
| Dispatch order? | **`sort_order` ASC** — explicit `orderBy('sort_order')` |
| Return value? | **`SmartHomeDispatchResult`** — `vibe_id`, `dispatched`, `skipped`, `action_ids[]` |
| Skips missing devices? | **Yes** — `$action->device === null` → increment `skipped`, continue |
| Inline provider calls? | **No** — only `SmartHomeActionJob::dispatch($action->id)` |
| Safe from scheduler command? | **Yes** — enqueue-only, no HTTP, no auth dependency |
| Throws exceptions? | **Unlikely** — no explicit throws; queue dispatch could theoretically fail — Phase 4 should wrap in try/catch per ADR-023 |

### Phase 4 recommendation

**Reuse directly — no wrapper required for MVP.**

```php
// Pseudocode — Phase 4 only
if ($result === 'dispatched') {
    $vibe = $schedule->vibe; // eager-load in batch query
    $summary = $dispatchService->dispatch($vibe);
    // optional: update ScheduleExecution.log with $summary
}
```

**Ownership note:** Scheduler processes schedules from DB without HTTP auth. Security is implicit: schedule row is user-owned; vibe FK ensures target vibe exists. Phase 3 should confirm schedule and vibe share the same `user_id` if vibe is loaded independently (defensive check — application layer, not migration).

**Mobile path today:** `VibeSmartHomeDispatchController` authorizes `view` on vibe, then calls same service.

---

## 8. DispatchDueSchedulesCommand review (inspect only)

**Class:** `app/Console/Commands/DispatchDueSchedulesCommand.php`

| Question | Answer |
| --- | --- |
| `processSchedule()` location? | Private method, lines 94–156 |
| Return values? | `'dispatched'` \| `'skipped_duplicate'` |
| Transaction boundary? | Entire idempotency + execution insert + recurrence advance inside `DB::transaction()` |
| `ScheduleExecution` after commit? | **Not returned** — created inside transaction; model instance not passed to caller. Phase 4 can re-query by `occurrence_key` or extend method to return execution ID if log update needed |
| Smart Home hook placement (later)? | **After** `processSchedule()` returns `'dispatched'`, **outside** transaction — in `handle()` foreach loop (~line 66–70) |
| Push on failure? | **Yes** — `catch (Throwable)` → `notifyScheduleFailure()` → `PushNotificationEvents::notifyScheduleExecutionFailed()` |
| Double dispatch risk? | **Mitigated** — gate Smart Home call on `$result === 'dispatched'` only; duplicate ticks return `'skipped_duplicate'` |

### Idempotency alignment (ADR-010 + ADR-023)

```
processSchedule()
  → skipped_duplicate  →  NO Smart Home dispatch
  → dispatched         →  Smart Home dispatch (Phase 4)
  → throws             →  transaction rollback, push failure notification, NO Smart Home dispatch
```

Phase 3 will document exact hook placement and optional log update strategy.

---

## 9. Mobile API embed field needs (Phase 5 — not implemented)

Per [ADR-025](../../../decisions/ADR-025-automation-mobile-ux.md). **No schema migration required** — computed fields / eager loads on existing resources.

### ScheduleResource (list + show)

| Field | Purpose | Source |
| --- | --- | --- |
| `vibe_id` | ✅ Already exposed | Column |
| `vibe.name` or `vibe_name` | Display linked vibe | Join / `whenLoaded('vibe')` |
| `device_actions_count` | List badge “+ Smart Home” | `$schedule->vibe->deviceActions()->count()` or `withCount` |
| `device_actions_summary` | Optional compact list | Nested array from vibe actions + device names |

**Suggested `device_actions_summary[]` item shape:**

```json
{
  "id": 10,
  "device_name": "Bedroom Light",
  "action_type": "turn_off",
  "device_status": "online"
}
```

### Schedule form (client)

Uses same data as show — may call existing `GET /api/vibes/{id}/device-actions` today without API changes; embed reduces round-trips.

### VibeResource (card + detail)

| Field | Purpose | Source |
| --- | --- | --- |
| `device_actions_count` | “Smart Home” badge | `withCount('deviceActions')` |
| `has_device_actions` | Boolean convenience | `device_actions_count > 0` |
| `active_schedules_count` | “Scheduled” badge | `schedules()->where('is_enabled', true)->count()` |
| `has_active_schedule` | Boolean convenience | `active_schedules_count > 0` |

### Existing endpoints usable without embeds (fallback)

| Endpoint | Use |
| --- | --- |
| `GET /api/vibes/{vibe}/device-actions` | Full action list with `device` embed |
| `GET /api/schedules` | `vibe_id` only — client must fetch vibe/actions separately |

**Recommendation:** Prefer server-side embeds on `ScheduleResource` and `VibeResource` in Phase 5 to avoid N+1 on schedules list.

---

## 10. Migration decision

### **Option A: No migrations required for MVP** ✅

| Question | Answer |
| --- | --- |
| Need `automations` table? | **No** |
| Need `schedule_device_actions` table? | **No** |
| Need `action_execution_logs` table? | **No for MVP** |
| Need `schedule_executions.log` migration? | **No** — column exists, nullable text, JSON string compatible |

All automation behaviour can be implemented by:

1. Calling existing `VibeSmartHomeDispatchService` from dispatcher (Phase 4).
2. Optionally updating `schedule_executions.log` JSON string (Phase 4).
3. Adding API resource embeds via Eloquent `withCount` / `load` (Phase 5).

**No new tables. No new columns. No new indexes.**

---

## 11. Risks / open questions

| ID | Risk / question | Severity | Owner phase |
| --- | --- | --- | --- |
| R-1 | **`delay_seconds` ignored** — actions fire immediately despite stored delay | Low | Phase 3 — confirm product accepts; implement `->delay()` on job dispatch if needed |
| R-2 | **Schedule/vibe user_id mismatch** — FK does not enforce same owner | Low | Phase 3 — defensive check when loading vibe from schedule |
| R-3 | **Double Smart Home dispatch** if hook placed inside transaction or ignores return value | Medium | Phase 3 — gate on `'dispatched'` only |
| R-4 | **Log update race** — post-commit log merge requires execution lookup by `occurrence_key` | Low | Phase 4 — design log update pattern |
| R-5 | **N+1 on schedules list** if mobile fetches actions per vibe | Medium | Phase 5 — embed counts |
| R-6 | **`schedule_id` not in SH failure push** today | Low | Phase 6 — optional payload extension |
| R-7 | **Deleted vibe mid-tick** — unlikely; cascade removes schedule before dispatch | Very low | Document only |
| R-8 | **Queue unavailable** — jobs not enqueued; recurrence still advances | Low | Accept per ADR-023 best-effort semantics; log enqueue failure |

---

## 12. Recommended next phases

| Phase | Focus | Blocked by |
| --- | --- | --- |
| **Phase 3** | Dispatch integration review — hook placement, idempotency, ownership check, log update | This review ✅ |
| **Phase 4** | Implement scheduler → `VibeSmartHomeDispatchService` wiring + Pest tests | Phase 3 sign-off |
| **Phase 5** | Mobile UX — `ScheduleResource` / `VibeResource` embeds | Phase 4 optional (can parallel after API contract sketched) |
| **Phase 6** | Push payload `schedule_id` alignment | Phase 4 |
| **Phase 7–8** | Integration tests + staging E2E | Phase 4 |

---

## Appendix — files inspected (read-only)

| Category | Path |
| --- | --- |
| Migrations | `database/migrations/2026_05_01_000007_create_schedules_table.php` |
| | `database/migrations/2026_06_12_000001_add_scheduler_mvp_columns_to_schedules_table.php` |
| | `database/migrations/2026_05_01_000008_create_schedule_executions_table.php` |
| | `database/migrations/2026_06_12_000002_add_scheduler_mvp_columns_to_schedule_executions_table.php` |
| | `database/migrations/2026_05_01_000006_create_vibe_device_actions_table.php` |
| | `database/migrations/2026_06_14_000003_harden_vibe_device_actions_table.php` |
| Models | `app/Models/Schedule.php`, `Vibe.php`, `VibeDeviceAction.php`, `ScheduleExecution.php`, `User.php` |
| Services | `app/SmartHome/Services/VibeSmartHomeDispatchService.php` |
| Commands | `app/Console/Commands/DispatchDueSchedulesCommand.php` |
| Resources | `app/Http/Resources/ScheduleResource.php`, `VibeResource.php`, `VibeDeviceActionResource.php`, `ScheduleExecutionResource.php` |
| Enums | `app/SmartHome/ActionType.php` |

**No files in `back_vibes` were modified during Phase 2.**
