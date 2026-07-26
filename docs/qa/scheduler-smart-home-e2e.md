# Scheduler + Smart Home Automations — End-to-End QA

**Phase:** 8 — Staging + Android E2E QA  
**Feature:** `scheduler-smart-home-automations/mvp`  
**Feature ID:** `scheduler-smart-home-automations/mvp`  
**Document type:** Comprehensive E2E QA reference — scenarios, regression checklist, operational validation, architecture compliance  
**Status:** CONDITIONAL PASS — automated suite complete; on-device (Android) and live-HA steps pending

**Spec:** [`specs/scheduler-smart-home-automations/mvp/spec.md`](../specs/scheduler-smart-home-automations/mvp/spec.md)  
**Tasks:** [`specs/scheduler-smart-home-automations/mvp/tasks.md`](../specs/scheduler-smart-home-automations/mvp/tasks.md)  
**Summary report:** [`qa/scheduler-smart-home-e2e/summary.md`](scheduler-smart-home-e2e/summary.md)  
**Operational runbook:** [`operations/scheduler-smart-home-operational-checklist.md`](../operations/scheduler-smart-home-operational-checklist.md)

**Architecture decisions:** [ADR-022](../decisions/ADR-022-scheduler-smart-home-automation-model.md) · [ADR-023](../decisions/ADR-023-automation-execution-order-and-failure-policy.md) · [ADR-024](../decisions/ADR-024-automation-notifications-and-observability.md) · [ADR-025](../decisions/ADR-025-automation-mobile-ux.md) · [ADR-026](../decisions/ADR-026-automation-execution-security.md) · [ADR-027](../decisions/ADR-027-asynchronous-orchestration-pattern.md)

---

## Table of contents

1. [Environment and test suite](#1-environment-and-test-suite)
2. [Happy-path validation](#2-happy-path-validation)
3. [Failure validation](#3-failure-validation)
4. [Mobile validation](#4-mobile-validation)
5. [Notification validation](#5-notification-validation)
6. [Operational validation](#6-operational-validation)
7. [Architecture validation](#7-architecture-validation)
8. [Regression checklist](#8-regression-checklist)
9. [Acceptance](#9-acceptance)

---

## 1. Environment and test suite

### 1.1 Runtime topology

```
Scheduler worker (schedules:dispatch-loop ~60s)
    ↓
schedules:dispatch-due
    ↓  DB transaction
ScheduleExecution + next_run_at advance
    ↓  post-commit (dispatched only)
ScheduleAutomationValidator
    ↓
VibeSmartHomeDispatchService → jobs table (smart-home queue)
    ↓
Queue worker (queue:work)
    ↓
SmartHomeActionJob
    ↓
HomeAssistantAdapter → Home Assistant REST API
    ↓  on failure
PushNotificationEvents → jobs table (push queue)
    ↓
PushNotificationJob → FCM

Mobile (parallel, device-local):
Schedule SQLite mirror → local OS reminders (Capacitor)
```

### 1.2 Environment

| Item | Value |
|---|---|
| `back_vibes` branch | `develop` |
| `back_vibes` tests | 710 passed / 2 058 assertions ✅ |
| `front_vibes` branch | `develop` |
| `front_vibes` tests | 309 passed / 28 files ✅ |
| `ixora-infra` branch | `develop` |
| Staging API | `https://staging-api.ixora-app.app` |
| Android device | **Not connected** — on-device steps ⏸ |
| Home Assistant | Not configured for this QA session — HA-specific steps ⏸ |
| Queue worker command | `php artisan queue:work --queue=push,smart-home,default --tries=3 --sleep=3 --timeout=90` |

### 1.3 Test suite commands

```bash
# back_vibes
php artisan test                                      # 710 tests / 2 058 assertions ✅
php artisan test --filter=Scheduler                   # 33 tests ✅
php artisan test --filter=SmartHome                   # 247 tests ✅
php artisan test --filter=PushNotifications           # 149 tests ✅
php artisan test --filter=ScheduleAutomationValidator # 9 unit tests ✅
./vendor/bin/pint --test                              # clean ✅

# front_vibes
npm run lint          # clean ✅
npm run typecheck     # clean ✅
npm run build         # built ✅
npm run test:unit     # 309 tests / 28 files ✅
```

### 1.4 Key test files

| File | Tests | Scope |
|---|---|---|
| `tests/Feature/Scheduling/DispatchDueSchedulesCommandTest.php` | 33 | Dispatcher + SH integration |
| `tests/Unit/SmartHome/ScheduleAutomationValidatorTest.php` | 9 | Validator ownership chain |
| `tests/Feature/PushNotifications/PushNotificationEventsTest.php` | — | Push orchestrator |
| `tests/Unit/PushNotifications/NotificationUxAlignmentTest.php` | — | Notification copy / UX |
| `src/services/__tests__/schedule-notification.service.test.ts` | 19 | Local reminder service |
| `src/services/__tests__/push-notification-handler.service.test.ts` | — | Push tap routing |

### 1.5 Functional requirement coverage

| ID | Requirement | Status | Evidence |
|---|---|---|---|
| **AUTO-1** | No new `automations` table or engine | ✅ | No migrations added; composition model only |
| **AUTO-2** | SH dispatch uses `VibeSmartHomeDispatchService` (same as manual) | ✅ | `DispatchDueSchedulesCommand` calls `VibeSmartHomeDispatchService::dispatch()` |
| **AUTO-3** | SH dispatch only on newly created `ScheduleExecution` | ✅ | Gated on `$result === 'dispatched'` — not `'skipped_duplicate'` |
| **AUTO-4** | SH failure must not prevent `next_run_at` advance | ✅ | Post-commit try/catch; recurrence already committed |
| **AUTO-5** | One action failure must not block other actions | ✅ | Per-job isolation; `SmartHomeActionJob` per action |
| **AUTO-6** | Push failure must not block scheduler or SH | ✅ | `PushNotificationEvents` swallows exceptions |
| **AUTO-7** | No server-side audio autoplay | ✅ | No audio calls in command or jobs |
| **AUTO-8** | Local notification behaviour unchanged | ✅ | 19 local-notification tests; no changes to service |
| **AUTO-9** | Mobile surfaces Schedule ↔ Vibe ↔ Device Actions | ✅ | API embeds + `AppAutomationBadge` + `automation-badges.ts` |
| **AUTO-10** | Integration tests for dispatcher + SH enqueue | ✅ | 33 scheduler tests with `Bus::assertDispatched` assertions |
| **AUTO-11** | `schedule_executions.log` may record SH summary | ⏸ | Deferred (P4-4) — no user-facing impact |
| **AUTO-12** | All existing auth rules preserved | ✅ | `ScheduleAutomationValidator` — no Policies in background path |

---

## 2. Happy-path validation

### SC-HP-1: Schedule with Smart Home actions — full automation flow

**Precondition:** User A owns:
- `Schedule` with `is_enabled = true`, `next_run_at <= now UTC`
- `vibe_id` → `Vibe` owned by User A
- `Vibe` has ≥1 `VibeDeviceAction` with `sort_order` ASC
- Each action's `Device` is owned by User A, has active `ProviderConnection`

**Flow:**

```
next_run_at arrives
    ↓
Scheduler worker ticks schedules:dispatch-due
    ↓  DB transaction
ScheduleExecution INSERT (occurrence_key unique)
next_run_at / last_run_at updated; once-schedules disabled
    ↓  post-commit, result === 'dispatched'
ScheduleAutomationValidator::validate() → true
    ↓
VibeSmartHomeDispatchService::dispatch(vibe)
    → SmartHomeActionJob dispatched per action (sort_order ASC)
    ↓
Queue worker drains smart-home queue
    → HomeAssistantAdapter::executeAction()
    → HA device changes state
    ↓
No push emitted (success path)
    ↓  parallel, device-local
Local OS reminder fires at next_run_at in user timezone
User taps → vibe player (no auto-play)
```

**Assertions:**

| Step | Assertion | Automated | On-device |
|---|---|---|---|
| 1. Scheduler tick | `tick #N` in Runtime Logs ~60s | ✅ loop test | ⏸ |
| 2. Execution row | `schedule_executions` has row with correct `occurrence_key` | ✅ | ⏸ staging |
| 3. `next_run_at` | `schedules.next_run_at` advanced correctly per recurrence type | ✅ | ⏸ staging |
| 4. Validator | No warning log `validator_failed: true` in output | ✅ | ⏸ staging |
| 5. SH jobs | `SmartHomeActionJob` dispatched ×N (`Bus::assertDispatchedTimes`) | ✅ | ⏸ staging |
| 6. Queue drain | Job log: "action executed successfully." | ✅ (mock) | ⏸ HA |
| 7. HA state | Device light/switch state changes | ⏸ | ⏸ HA |
| 8. No push | `PushNotificationJob` not dispatched | ✅ | — |
| 9. Local reminder | OS notification fires at correct time | ⏸ | ⏸ Android |
| 10. Tap → player | `scheduleNotificationService` → `/vibes/:id/player` | ✅ | ⏸ Android |
| 11. No auto-play | Audio requires manual tap | ⏸ | ⏸ Android |

**Test reference:** `test('dispatched schedule enqueues Smart Home action jobs')` — ✅

---

### SC-HP-2: Schedule without Smart Home actions

**Precondition:** User A owns Schedule → Vibe with zero `vibe_device_actions`.

**Flow:**

```
next_run_at arrives
    ↓
processSchedule() commits — ScheduleExecution created
    ↓  result === 'dispatched'
ScheduleAutomationValidator::validate() → true (zero actions = valid)
    ↓
VibeSmartHomeDispatchService::dispatch()
    → actions loop: empty → zero SmartHomeActionJob dispatched
    ↓
No SH jobs in queue
    ↓  parallel
Local reminder fires as before
No push (no failure)
```

**Assertions:**

| Step | Assertion | Status |
|---|---|---|
| Execution row created | `schedule_executions` row exists | ✅ |
| `next_run_at` advanced | Recurrence computed correctly | ✅ |
| Zero SH jobs | `Bus::assertNotDispatched(SmartHomeActionJob::class)` | ✅ |
| No push | `Bus::assertNotDispatched(PushNotificationJob::class)` | ✅ |
| Local reminder | OS alarm scheduled for next_run_at | ⏸ Android |
| Schedule list badge | No automation badge shown (no device actions) | ✅ unit |

**Test reference:** `test('schedule without device actions enqueues no Smart Home jobs')` — ✅

---

### SC-HP-3: `once` schedule — auto-disables after single execution

**Precondition:** Schedule with `recurrence_type = 'once'`.

**Flow:**

```
Tick fires
    ↓
ScheduleExecution created, next_run_at = NULL, is_enabled = false
    ↓
SH dispatch runs normally (if vibe has actions)
    ↓
Next tick — schedule not in query (is_enabled = false)
```

**Assertions:**

| Step | Assertion | Status |
|---|---|---|
| Execution row | `status = 'dispatched'` | ✅ |
| `next_run_at` | `NULL` after once execution | ✅ |
| `is_enabled` | `false` after once execution | ✅ |
| Second tick | Schedule not in due query | ✅ |
| SH actions | Dispatched once if vibe has actions | ✅ |

---

### SC-HP-4: Recurrence types advance correctly

| Type | Expected `next_run_at` | ADR |
|---|---|---|
| `once` | `NULL` → `is_enabled = false` | ADR-009 |
| `daily` | `+1 day` same UTC time | ADR-009 |
| `weekdays` | Skip Saturday/Sunday; next weekday | ADR-009 |
| `weekly` | Next matching day in `days_of_week` | ADR-009 |

**UTC storage:** All `next_run_at` stored in UTC; displayed in user's timezone on mobile (ADR-009).

**Test references:** `DispatchDueSchedulesCommandTest` recurrence suite — ✅

---

### SC-HP-5: Multiple schedules in same batch

**Precondition:** N schedules are due simultaneously.

**Flow:**

```
Batch of N due schedules loaded (ORDER BY next_run_at, LIMIT 100)
    ↓
foreach schedule:
    processSchedule() — independent transaction
    dispatchSmartHomeAfterSchedule() — independent post-commit hook
    ↓
All N schedules processed
```

**Assertions:**

| Assertion | Status |
|---|---|
| Each schedule gets its own `ScheduleExecution` | ✅ |
| Each `next_run_at` advances independently | ✅ |
| SH dispatch per schedule is isolated (one failure does not stop others) | ✅ |
| Batch summary log shows correct `dispatched` / `skipped_duplicate` / `failed` counts | ✅ |

**Test reference:** `test('two due schedules are dispatched independently')` — ✅

---

### SC-HP-6: Dry-run mode produces no side effects

**Command:**

```bash
php artisan schedules:dispatch-due --dry-run
```

**Assertions:**

| Assertion | Status |
|---|---|
| No `ScheduleExecution` rows created | ✅ |
| No `next_run_at` changes | ✅ |
| No SH jobs dispatched | ✅ |
| No push notifications dispatched | ✅ |
| Output reports count of would-be due schedules | ✅ |

---

## 3. Failure validation

### SC-F-1: Validator failure — user/vibe ownership mismatch

**Trigger:** `schedule.user_id !== vibe.user_id` (e.g. data corruption, tinker).

**Flow:**

```
processSchedule() commits — ScheduleExecution created, next_run_at advances
    ↓  result === 'dispatched'
ScheduleAutomationValidator::validate()
    vibe.user_id !== schedule.user_id → returns false
    ↓
dispatchSmartHomeAfterSchedule: Log::warning('Schedule Smart Home dispatch skipped...')
    context: schedule_id, vibe_id, user_id, validator_failed: true
    ↓
No SmartHomeActionJob dispatched
No push notification (ADR-026 — expected skip, not actionable)
Batch continues to next schedule
```

**Assertions:**

| Assertion | Status |
|---|---|
| `ScheduleExecution` row exists | ✅ |
| `next_run_at` advanced | ✅ |
| Warning log `validator_failed: true` | ✅ |
| `Bus::assertNotDispatched(SmartHomeActionJob::class)` | ✅ |
| `Bus::assertNotDispatched(PushNotificationJob::class)` | ✅ |
| Next schedule in batch processes normally | ✅ |

**Test reference:** `test('validator failure skips Smart Home dispatch but keeps schedule execution')` — ✅  
**Grep pattern:** `Schedule Smart Home dispatch skipped`

---

### SC-F-2: Validator failure — missing vibe

**Trigger:** `schedule.vibe_id` references a deleted `Vibe`.

**Flow:**

```
processSchedule() commits — ScheduleExecution created
    ↓
ScheduleAutomationValidator::validate()
    resolveVibe() → null → returns false
    ↓
Same skip path as SC-F-1
```

**Assertions:**

| Assertion | Status |
|---|---|
| `schedule_executions` row exists | ✅ |
| `next_run_at` advanced | ✅ |
| Warning log with `validator_failed: true` | ✅ |
| Zero SH jobs | ✅ |
| No push | ✅ |

**Test reference:** `ScheduleAutomationValidatorTest` — missing vibe case — ✅

---

### SC-F-3: Validator failure — missing device

**Trigger:** `vibe_device_actions` row references deleted `Device`.

**Flow:**

```
ScheduleAutomationValidator::validate()
    resolveDeviceActions() → one action with device = null
    isActionValidForSchedule() → device null → returns false
    ↓
validator returns false → same skip path
```

**Assertions:** Same as SC-F-1 — ✅  
**Test reference:** `ScheduleAutomationValidatorTest` — missing device — ✅

---

### SC-F-4: Validator failure — missing provider connection

**Trigger:** `Device` has no associated `ProviderConnection`.

**Flow:**

```
ScheduleAutomationValidator::validate()
    isActionValidForSchedule():
        device resolved, device.user_id matches
        providerConnection → null → returns false
    ↓
Same skip path
```

**Assertions:** Same as SC-F-1 — ✅  
**Test reference:** `ScheduleAutomationValidatorTest` — missing connection — ✅

---

### SC-F-5: Validator failure — device owner mismatch

**Trigger:** `device.user_id !== schedule.user_id` (cross-user data drift).

**Flow:**

```
ScheduleAutomationValidator::validate()
    isActionValidForSchedule():
        device.user_id !== scheduleUserId → returns false
    ↓
Same skip path — no push
```

**Assertions:** Same as SC-F-1 — ✅  
**Test reference:** `ScheduleAutomationValidatorTest` — device user mismatch — ✅

---

### SC-F-6: Duplicate tick — idempotency guard

**Trigger:** Two scheduler instances run simultaneously; same `occurrence_key` attempted twice.

**Flow:**

```
Tick 1: processSchedule() — INSERT schedule_executions → success → 'dispatched'
    ↓  SH dispatch runs
Tick 2 (race): processSchedule()
    pre-check: alreadyExists = true → 'skipped_duplicate'
    OR: INSERT throws UniqueConstraintViolationException → 'skipped_duplicate'
    ↓
result !== 'dispatched' → dispatchSmartHomeAfterSchedule NOT called
No duplicate SH jobs
```

**Assertions:**

| Assertion | Status |
|---|---|
| `schedule_executions` has exactly 1 row | ✅ |
| `SmartHomeActionJob` dispatched exactly N times (not 2×N) | ✅ |
| No `schedule_execution_failed` push | ✅ |
| Batch summary: `skipped_duplicate: 1` | ✅ |

**Test reference:** `test('duplicate tick does not create duplicate execution or Smart Home dispatch')` — ✅

---

### SC-F-7: Invalid recurrence — transaction failure

**Trigger:** `weekly` schedule with `recurrence_config = null` — `RecurrenceService` throws inside transaction.

**Flow:**

```
processSchedule() — DB::transaction()
    RecurrenceService::computeNextRunAt() throws
    Transaction rolls back — NO ScheduleExecution created
    ↓
Outer catch: $failed++
$this->warn("Schedule [id] failed: {message}") → stdout
    ↓
notifyScheduleFailure():
    PushNotificationEvents::notifyScheduleExecutionFailed(user, execution)
    → schedule_execution_failed push dispatched
    ↓
Batch continues — other schedules unaffected
```

**Assertions:**

| Assertion | Status |
|---|---|
| `schedule_executions` row does NOT exist | ✅ |
| `next_run_at` does NOT advance | ✅ |
| `PushNotificationJob` dispatched with `type = schedule_execution_failed` | ✅ |
| Payload has `schedule_id` | ✅ |
| Batch summary: `failed: 1` | ✅ |
| Other schedules in batch unaffected | ✅ |

**Test reference:** `test('a failed schedule notifies the owner via PushNotificationEvents')` — ✅

---

### SC-F-8: SH dispatch exception — queue unavailable

**Trigger:** `VibeSmartHomeDispatchService::dispatch()` throws (DB lock, queue driver error).

**Flow:**

```
processSchedule() commits — ScheduleExecution exists, next_run_at advanced
    ↓  result === 'dispatched'
dispatchSmartHomeAfterSchedule():
    validator.validate() → true
    smartHomeDispatch.dispatch() throws RuntimeException
    ↓
Catch(Throwable): Log::warning('Schedule Smart Home dispatch failed.')
    context: schedule_id, vibe_id, user_id, exception_class, error
    ↓
No SH jobs in queue
No schedule_execution_failed push (recurrence already committed)
Batch continues
```

**Assertions:**

| Assertion | Status |
|---|---|
| `ScheduleExecution` row exists | ✅ |
| `next_run_at` advanced | ✅ |
| Warning log: `Schedule Smart Home dispatch failed.` with `exception_class` | ✅ |
| `Bus::assertNotDispatched(SmartHomeActionJob::class)` | ✅ |
| `Bus::assertNotDispatched(PushNotificationJob::class)` | ✅ |
| Batch continues | ✅ |

**Test reference:** `test('Smart Home dispatch exception logs safely and does not emit schedule failure push')` — ✅

---

### SC-F-9: Provider returns HTTP 5xx — Smart Home action failure

**Trigger:** `HomeAssistantAdapter::executeAction()` returns `ActionResult { success: false }`.

**Flow:**

```
SmartHomeActionJob::handle()
    HomeAssistantAdapter::executeAction()
        HA returns 5xx → ActionResult { success: false }
    ↓
Job: Log::warning('action execution failed (provider returned failure).')
    context: vibe_device_action_id, device_id, provider, action_type, status_code
    ↓
PushNotificationEvents::notifySmartHomeActionFailed(user, vibeDeviceAction)
    → smart_home_action_failed push
    ↓
Job completes — does NOT go to failed_jobs
Scheduler next_run_at already advanced — unaffected
Other actions in same occurrence run independently (ADR-023 AUTO-5)
```

**Assertions:**

| Assertion | Status |
|---|---|
| Warning log "action execution failed" | ✅ |
| `PushNotificationJob` dispatched with `type = smart_home_action_failed` | ✅ |
| Payload: `device_id`, `vibe_id`, `action_type` as strings | ✅ |
| Job NOT in `failed_jobs` | ✅ |
| Other jobs in same batch run independently | ✅ |

**Test reference:** `test('notifies the owner via PushNotificationEvents on a failed action result')` — ✅

---

### SC-F-10: Provider unreachable during connection sync

**Trigger:** `ProviderDeviceSyncService::sync()` → connection timeout or `ProviderConnectionException`.

**Flow:**

```
POST /api/smart-home/connections/{id}/sync
    ↓
HomeAssistantAdapter::fetchDevices() — timeout / 5xx
    ↓
provider_connections.status = 'unreachable'
devices.status = 'unknown'
    ↓
PushNotificationEvents::notifySmartHomeProviderUnreachable(user, connection)
    → smart_home_provider_unreachable push
API returns 502
    ↓
Scheduler unaffected (separate flow)
```

**Assertions:**

| Assertion | Status |
|---|---|
| API returns 502 | ✅ |
| `provider_connections.status = 'unreachable'` | ✅ |
| `PushNotificationJob` with `type = smart_home_provider_unreachable` | ✅ |
| Payload: `provider_connection_id`, `provider` as strings | ✅ |
| Scheduler `next_run_at` unaffected | ✅ |

**Test reference:** `ProviderConnectionSyncApiTest` — connection timeout — ✅

---

### SC-F-11: Unsupported action type

**Trigger:** `vibe_device_actions.action_type` not in `HomeAssistantAdapter::ACTION_SERVICE_MAP`.

**Flow:**

```
SmartHomeActionJob::handle()
    ActionType::from($action->action_type) → UnsupportedSmartHomeActionException
    ↓
Log::warning('unsupported action — skipping.')
    ↓
No push (ADR-026 — log + skip; retrying would not help)
Job completes
```

**Assertions:**

| Assertion | Status |
|---|---|
| Warning log "unsupported action — skipping" | ✅ |
| `Bus::assertNotDispatched(PushNotificationJob::class)` | ✅ |
| Job NOT in `failed_jobs` | ✅ |

**Test reference:** `test('does not notify via PushNotificationEvents for an unsupported action type')` — ✅

---

### SC-F-12: Push delivery failure

**Trigger:** `PushNotificationService` cannot enqueue job (DB unavailable, exception in orchestrator).

**Flow:**

```
PushNotificationEvents::notifySmartHomeActionFailed()
    PushNotificationService::sendToUser() throws
    ↓
PushNotificationEvents catches internally
Log::error('PushNotificationEvents: failed to queue notification.')
    ↓
Domain flow (scheduler tick, SH execution) already complete — unaffected (AUTO-6)
```

**Assertions:**

| Assertion | Status |
|---|---|
| Error log "failed to queue notification" | ✅ |
| Scheduler recurrence / SH jobs not rolled back | ✅ |
| No exception propagated to command | ✅ |

**Test reference:** `PushNotificationEventsTest` — dispatch failure — ✅

---

### SC-F-13: No push tokens registered

**Trigger:** User has zero active `push_tokens` rows.

**Flow:**

```
PushNotificationJob::handle()
    fan-out: no active tokens
    ↓
Log::info('user has no active push tokens — skipping.')
    ↓
Job completes — no crash, no retry
Domain unaffected
```

**Assertions:**

| Assertion | Status |
|---|---|
| Info log "no active push tokens — skipping" | ✅ |
| Job NOT in `failed_jobs` | ✅ |
| Domain unaffected | ✅ |

---

## 4. Mobile validation

### 4.1 API enrichment

The schedule and vibe resources expose automation embed fields. These enable badge rendering without N+1 queries.

| Endpoint | Field | Type | Source | Status |
|---|---|---|---|---|
| `GET /api/schedules` | `vibe_name` | `string\|null` | `ScheduleResource` | ✅ |
| `GET /api/schedules` | `device_actions_count` | `integer ≥ 0` | `ScheduleResource` | ✅ |
| `GET /api/schedules` | `has_device_actions` | `boolean` | `ScheduleResource` | ✅ |
| `GET /api/schedules/{id}` | Same fields | — | `ScheduleResource` | ✅ |
| `GET /api/vibes` | `active_schedules_count` | `integer ≥ 0` | `VibeResource` | ✅ |
| `GET /api/vibes` | `has_active_schedule` | `boolean` | `VibeResource` | ✅ |

**N+1 prevention:**
- `ScheduleController`: eager-load `vibe → deviceActions` with count
- `VibeController`: eager-count `schedules where is_enabled = true`

---

### 4.2 Schedule list

| Check | Expected | Status |
|---|---|---|
| Loading state | `AppLoadingState` with title ("Loading your schedules…") + description | ✅ unit |
| Empty state | "No schedules yet" + actionable description + "New schedule" CTA | ✅ unit |
| Error state | `AppErrorState` with human-language message + Retry button | ✅ unit |
| Schedule card | Name + `vibe_name` below + next_run_at in local timezone | ✅ unit |
| Automation badge | `AppAutomationBadge` visible when `has_device_actions = true` | ✅ unit |
| No badge when no actions | Badge absent when `has_device_actions = false` | ✅ unit |
| Accessibility | Loading: `role="status"` / `aria-busy`; error: `role="alert"` | ✅ unit |
| Dark mode | Loading/empty/error states render in dark theme | ⏸ on-device |
| Offline | Cached list from SQLite mirror; no empty state confusion | ⏸ on-device |

---

### 4.3 Schedule detail / form

| Check | Expected | Status |
|---|---|---|
| Loading (edit mode) | `AppLoadingState` "Loading schedule…" + description | ✅ unit |
| Read-only automation summary | Vibe name + automation badge in dedicated section | ✅ unit |
| Zero actions | "No Smart Home actions — schedule will only remind you…" copy | ✅ unit |
| Actions summary | "Turn off Bedroom Light · Toggle Desk Lamp (N actions)" | ✅ unit |
| No inline action editing | Actions cannot be edited from schedule form (ADR-025) | ✅ — no control |
| Helper copy | "At the scheduled time, IXORA will run this vibe's Smart Home actions and remind you to play." | ✅ copy test |
| No vibes | Empty state: "No vibes to schedule" + CTA | ✅ unit |
| Back navigation | `router.back()` from form — no surprise redirect | ✅ unit |
| Accessibility | Sections labeled; automation summary as `aria-label` region | ✅ unit |

---

### 4.4 Vibe list

| Check | Expected | Status |
|---|---|---|
| Loading | `AppLoadingState` with title + description | ✅ unit |
| Empty | "No vibes yet" + CTA | ✅ unit |
| Automation badge when scheduled | "Used by an active schedule" badge (`automation-active` preset) | ✅ unit |
| No badge when not scheduled | Badge absent when `has_active_schedule = false` | ✅ unit |
| Badge: icon + text | Never icon-only (ADR-025 — colour-only forbidden) | ✅ |
| `a11yLabel` | "Smart home automation active" or "Used by an active schedule" | ✅ unit |

---

### 4.5 Vibe detail (Edit Vibe)

| Check | Expected | Status |
|---|---|---|
| Loading | `AppLoadingState` (Phase 5C.2 upgrade from bare spinner) | ✅ unit |
| Error | `AppErrorState` with Retry | ✅ unit |
| Schedule summary | "Used by N active schedule(s)" or "Not scheduled yet" | ✅ unit |
| Smart Home section | Device actions listed (existing — unchanged) | ✅ |
| Helper copy | "Device actions run when you play this vibe or when a schedule triggers it." | ✅ copy test |

---

### 4.6 Automation badges

| Badge status | Label | Icon | Colour-only? | `a11yLabel` | Status |
|---|---|---|---|---|---|
| `automation-enabled` | "Smart Home automation enabled" | flash | No — text present | "Smart home automation enabled" | ✅ |
| `automation-active` | "Used by an active schedule" | alarm | No — text present | "Smart home automation active" | ✅ |
| `no-smart-home-actions` | "No Smart Home actions" | flash-off | No — text present | "No smart home actions" | ✅ |
| `no-active-schedules` | "No active schedules" | alarm | No — text present | "No active schedules" | ✅ |

Source: `automation-badges.ts` presets (Object.frozen, unit-tested) — ✅

---

### 4.7 Loading states — compliance

Every loading state must conform to the `user-experience-principles.md` §2 pattern:

| Screen | Component | Title | Description | `aria-busy` | Status |
|---|---|---|---|---|---|
| Schedules list | `AppLoadingState` | "Loading your schedules…" | Present | ✅ | ✅ unit |
| Vibes list | `AppLoadingState` | "Loading your vibes…" | Present | ✅ | ✅ unit |
| Schedule form (edit) | `AppLoadingState` | "Loading schedule…" | Present | ✅ | ✅ unit |
| Vibe detail | `AppLoadingState` | Present | Present | ✅ | ✅ unit |

No bare `<ion-spinner>` with no label accepted.

---

### 4.8 Empty states — compliance

| Screen | Title | Description | CTA | Status |
|---|---|---|---|---|
| Schedules list | "No schedules yet" | Actionable guidance | "New schedule" | ✅ |
| Vibes list | "No vibes yet" | Actionable guidance | "Create vibe" | ✅ |
| Schedule form — no vibes | "No vibes to schedule" | Guidance to create vibe first | CTA | ✅ |

No "No data." empty state accepted without description and guidance.

---

### 4.9 Microcopy — user language

Backend terms must not appear in user-visible copy.

| Avoid | Use instead | Status |
|---|---|---|
| "execution" / "executed" | "run" / "ran" / "completed" | ✅ |
| "provider" (when meaning HA) | "Smart Home" / "connection" | ✅ |
| "job" / "queue" / "worker" | (omit — not user-facing) | ✅ |
| "occurrence_key" | (omit — internal) | ✅ |
| "dispatch" / "dispatcher" | "schedule" / "reminder" | ✅ |
| "validator / validation failed" | (log only — not in toast) | ✅ |
| Technical IDs in sentences | Names when available | ✅ |

**Notification copy (Phase 6B upgrades):**

| Type | Before | After | Status |
|---|---|---|---|
| `schedule_execution_failed` body | "One of your scheduled executions failed." | "One of your schedules could not run." | ✅ |
| `smart_home_provider_unreachable` body | "Your Smart Home provider is currently unreachable." | "Your Smart Home connection is temporarily unavailable." | ✅ |

---

### 4.10 Dark mode

| Check | Expected | Status |
|---|---|---|
| Loading states readable | Tokens applied; contrast passes | ⏸ on-device |
| Empty state text readable | — | ⏸ on-device |
| Badges readable | Tone tokens (`primary`, `neutral`) correct in dark | ⏸ on-device |
| Error states readable | — | ⏸ on-device |

Dark mode is verified via design tokens — no colour-only state → acceptable fallback.

---

### 4.11 Accessibility

| Requirement | Check | Status |
|---|---|---|
| Loading: `role="status"` / `aria-busy="true"` | Loading regions announced | ✅ unit |
| Error: `role="alert"` | Error regions announced | ✅ unit |
| Decorative icons: `aria-hidden="true"` | Icons not read as meaningful alone | ✅ |
| Badge: icon + text + `a11yLabel` | Never icon-only | ✅ |
| Headings hierarchy | Card titles as headings; sections labeled | ✅ unit |
| Automation summary section | `aria-label="…"` region | ✅ unit |
| No colour-only state | Enabled/disabled uses text + icon | ✅ |

---

### 4.12 Tap routing

| Notification type | Route | User lands on | Status |
|---|---|---|---|
| `schedule_execution_failed` | `/schedules` | Schedules list | ✅ |
| `smart_home_action_failed` | `/devices` | Devices list | ✅ |
| `smart_home_provider_unreachable` | `/devices` | Devices list | ✅ |
| `account_security_notice` | `/settings` | Settings | ✅ |
| Unknown type | No navigation + console.warn | — | ✅ |
| Local reminder tap | `/vibes/:id/player` (no auto-play) | Vibe player | ✅ unit |

**Routing rules:**
- Uses `router.push()` — never `window.location` or `reload`
- Cold-start: awaits `router.isReady()` before push
- Single `notificationActionPerformed` listener (singleton guard prevents double-registration)
- Android native only — no-op on web

---

### 4.13 No duplicate notifications

| Scenario | Expected | Status |
|---|---|---|
| Due-time local reminder + happy-path backend | Only local fires; no push on success | ✅ |
| SH failure push + local reminder | Different triggers, different moments — no overlap | ✅ |
| Two taps on same notification | Singleton listener guard prevents double-nav | ✅ unit |
| Push + local same occurrence | Different channels, separate listeners — no conflict | ✅ |

---

## 5. Notification validation

### 5.1 Local reminder

| Check | Expected | Status |
|---|---|---|
| Channel created | `schedule_reminders` Android channel on app startup | ✅ unit |
| Reminder copy | "Time to start your scheduled vibe." | ✅ unit |
| Only future schedules | Past `next_run_at` excluded from SQLite mirror | ✅ unit |
| Rebuild on sync | Cancel-all → re-register (ADR-011 idempotent) | ✅ unit |
| Offline-capable | Device OS alarms — no server dependency | ✅ by design |
| Tap → vibe player | `scheduleNotificationService` → `/vibes/:id/player` | ✅ unit |
| No auto-play | Audio requires manual user action | ✅ by design |

**Reference:** `schedule-notification.service.test.ts` — 19 tests — ✅

---

### 5.2 Push failure notifications

| Type | Trigger | Payload fields (strings) | Tap route | Status |
|---|---|---|---|---|
| `schedule_execution_failed` | Dispatcher transaction failure | `type`, `schedule_id` | `/schedules` | ✅ |
| `smart_home_action_failed` | `SmartHomeActionJob` provider failure | `type`, `device_id`, `vibe_id`, `action_type` | `/devices` | ✅ |
| `smart_home_provider_unreachable` | Provider sync failure | `type`, `provider_connection_id`, `provider` | `/devices` | ✅ |

**Payload requirements (ADR-019, ADR-021):**
- `type` always present and stable
- All `data` values are strings (FCM requirement)
- Business identifiers only — no secrets, no tokens, no provider config
- No PII in body copy

---

### 5.3 What is never sent

| Scenario | Push sent? | Status |
|---|---|---|
| Schedule executes successfully | ❌ No (ADR-024) | ✅ |
| Validator returns `false` (ownership mismatch) | ❌ No (ADR-026) | ✅ |
| SH dispatch exception (queue unavailable) | ❌ No (not a recurrence failure) | ✅ |
| Unsupported action type | ❌ No (log + skip) | ✅ |
| Duplicate tick / `skipped_duplicate` | ❌ No | ✅ |
| `automation_completed` event | ❌ Not emitted (deferred, ADR-024) | ✅ |
| `automation_due` event | ❌ Not emitted (deferred, ADR-024) | ✅ |

---

### 5.4 Push delivery isolation

| Failure | Domain impact | Push impact |
|---|---|---|
| Queue unavailable | Domain operation completes | Log error; no user alert |
| Provider HTTP error | Domain operation completes | Log warning; retry per config |
| Invalid / expired FCM token | Domain operation completes | Deactivate token; continue batch |
| Orchestrator throws | Domain operation completes | Caught internally; logged |
| Single token fails | N/A | Other tokens in same job attempted |

**Rule:** push failure never rolls back domain operations — ✅

---

### 5.5 Local vs push — no duplication contract

```
Schedule due (device-local)
    │
    ├─► Local notification — "Time to start your scheduled vibe."
    │       Tap → /vibes/:vibe_id/player
    │
    └─► Backend dispatch (parallel, server-side)
            │
            ├─► Smart Home actions enqueue (best-effort)
            │
            └─► On failure only → push notification
                    schedule_execution_failed       → /schedules
                    smart_home_action_failed        → /devices
                    smart_home_provider_unreachable → /devices
```

- Local tap handler (`scheduleNotificationService`) and push tap handler (`pushNotificationHandlerService`) are separate listeners on separate channels — they never compete
- Due-time local reminder and failure push are triggered by different events — no overlap by design

---

## 6. Operational validation

### 6.1 Pre-flight checklist

Verify before declaring ops-ready or after any deploy touching scheduler, Smart Home, or push.

#### Workers

| # | Check | Pass criteria | Status |
|---|---|---|---|
| 6.1.1 | Scheduler worker running | `[schedules:dispatch-loop] tick #N` ~every 60 s in Runtime Logs | ⏸ staging |
| 6.1.2 | Queue worker running | `queue` component healthy; no crash loop | ⏸ staging |
| 6.1.3 | Queue command includes all queues | `--queue=push,smart-home,default` | ✅ IaC |
| 6.1.4 | Worker timeout sufficient | `--timeout=90` ≥ job timeout (30 s) + headroom | ✅ IaC |
| 6.1.5 | API service healthy | HTTP responds; migrations applied | ⏸ staging |

#### Environment variables

| Variable | Expected | Purpose |
|---|---|---|
| `QUEUE_CONNECTION` | `database` | Job persistence |
| `PUSH_PROVIDER` | `fcm` (or `noop` in dev) | Push transport |
| `FIREBASE_*` / `FIREBASE_CREDENTIALS` | Set in App Platform secrets | FCM OAuth |
| `PUSH_NOTIFICATIONS_QUEUE` | `push` (default) | Push queue name |
| `SMART_HOME_QUEUE_NAME` | `smart-home` (default) | SH job queue name |
| `SMART_HOME_HA_TIMEOUT` | `10` (default) | HA HTTP timeout (seconds) |
| `SMART_HOME_ALLOW_HTTP` | `false` (production/staging) | HTTPS-only HA URLs |
| `LOG_CHANNEL` | `stderr` (App Platform) | Logs in component stream |

**Secrets never in git.** HA access tokens live in `provider_connections` (encrypted), not env vars.

#### Database

| # | Check | Pass criteria | Status |
|---|---|---|---|
| 6.1.6 | Migrations current | `schedule_executions`, `schedules`, `vibe_device_actions`, `jobs` tables exist | ✅ migration |
| 6.1.7 | Unique index | `(schedule_id, occurrence_key)` on `schedule_executions` (ADR-010) | ✅ migration |
| 6.1.8 | No runaway backlog | `jobs` queue depth for `smart-home` and `push` not growing | ⏸ staging |

---

### 6.2 Health check commands

```bash
# One bounded tick (API or scheduler component console)
php artisan schedules:dispatch-loop --once

# Inspect without writes
php artisan schedules:dispatch-due --dry-run

# Queue health
php artisan queue:monitor push,smart-home,default

# Inspect jobs table
# (run from mysql/psql console or tinker)
SELECT queue, COUNT(*) AS pending FROM jobs GROUP BY queue ORDER BY pending DESC;

# Scheduler tick log
# grep in Runtime Logs:
[schedules:dispatch-loop] tick #
```

---

### 6.3 Log catalog — grep patterns

| Log message | Level | Grep pattern |
|---|---|---|
| Validator skip | warning | `Schedule Smart Home dispatch skipped` |
| SH dispatch exception | warning | `Schedule Smart Home dispatch failed` |
| Action execution failed (provider) | warning | `SmartHomeActionJob: action execution failed` |
| Unexpected action error | error | `SmartHomeActionJob: unexpected error` |
| Push queue failure | error | `PushNotificationEvents: failed to queue` |
| Push delivery failed | warning | `PushNotificationJob: push failed` |
| No push tokens | info | `PushNotificationJob: user has no active push tokens` |

---

### 6.4 Operational checklist compliance

Cross-reference with [`operations/scheduler-smart-home-operational-checklist.md`](../operations/scheduler-smart-home-operational-checklist.md):

| Runbook check | Executable? | Outdated? | Notes |
|---|---|---|---|
| §2.1 Scheduler worker ticking | ✅ Yes — `tick #N` pattern verifiable | No | — |
| §2.2 Queue worker running | ✅ Yes — component health + `queue:monitor` | No | — |
| §2.3 Queue command correct | ✅ Yes — IaC + `ps aux` | No | — |
| §2.4 Worker timeout | ✅ Yes — `--timeout=90` in IaC | No | — |
| §2.5 API service healthy | ✅ Yes — `curl /api/health` | No | — |
| §3 Health check commands | ✅ All executable | No | — |
| §4 Log catalog | ✅ Grep patterns verified against implementation | No | — |
| §5 Failure matrix | ✅ Matches Phase 4B implementation | No | — |
| §6 Deployment checklist | ✅ Runnable | No | — |
| §7 Manual verification | ✅ Steps executable | ⏸ HA/Android steps require hardware | — |
| §8 Recovery checklist | ✅ Recovery paths valid | No | — |
| §9 Troubleshooting | ✅ Diagnosis flow matches implementation | No | — |
| §10 ADR compliance | ✅ Sign-off questions match behavior | No | — |

**No outdated commands, no obsolete env vars, no missing workers found.**

---

### 6.5 Manual verification scenarios

| # | Scenario | Expected | Status |
|---|---|---|---|
| 7.1 | Due schedule, no device actions | Execution row; `next_run_at` advanced; no SH jobs | ✅ automated |
| 7.2 | Due schedule + device actions | Execution + N `SmartHomeActionJob`s processed | ✅ automated / ⏸ HA live |
| 7.3 | Duplicate tick (same occurrence) | `skipped_duplicate`; no duplicate rows | ✅ automated |
| 7.4 | Validator fail (foreign vibe) | Execution committed; warning log; no SH job; no push | ✅ automated |
| 7.5 | Invalid recurrence (forced bad config) | Transaction fails; `schedule_execution_failed` push | ✅ automated |
| 7.6 | HA returns 500 | Job completes; warning log; `smart_home_action_failed` push | ✅ automated |
| 7.7 | Provider sync timeout | 502 API; connection `unreachable`; `smart_home_provider_unreachable` push | ✅ automated |
| 7.8 | Push token missing | "no active push tokens" log; scheduler unaffected | ✅ automated |
| 7.9 | Mobile local reminder | OS notification at due time; tap → vibe player (no auto-play) | ⏸ Android |
| 7.10 | Offline mobile | Cached schedules; local reminders from mirror; sync when online | ⏸ Android |

---

## 7. Architecture validation

### 7.1 Layer compliance — ADR-027

The implemented architecture maps exactly to the ADR-027 standard flow:

```
DispatchDueSchedulesCommand          ← Async Entrypoint
    ↓  processSchedule()
    (DB transaction: ScheduleExecution + next_run_at)
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

**Layer violation checks:**

| Rule | Verified | Status |
|---|---|---|
| Entrypoint does not call HA directly | `DispatchDueSchedulesCommand` has no `Http::` or adapter calls | ✅ |
| Entrypoint does not inline ownership checks | Ownership only in `ScheduleAutomationValidator` | ✅ |
| Validator makes no external I/O | `ScheduleAutomationValidator` — DB reads only, no HTTP | ✅ |
| Validator does not emit notifications | No `PushNotificationEvents` call in validator | ✅ |
| Service is reusable from HTTP and background | `VibeSmartHomeDispatchService` used by both mobile dispatch API and command | ✅ |
| Jobs do not call controllers | `SmartHomeActionJob` — no controller invocation | ✅ |
| Provider has no domain knowledge | `HomeAssistantAdapter` receives connection + device id + action — no `Schedule`, `Vibe` | ✅ |
| Push called via orchestrator only | `PushNotificationEvents` is the single entry point — no direct `PushNotificationJob::dispatch()` | ✅ |

---

### 7.2 ADR-022 compliance — Automation model

| Rule | Status |
|---|---|
| No `automations` table created | ✅ No new migrations |
| No automation engine | ✅ Composition model only |
| `VibeSmartHomeDispatchService` reused from mobile path | ✅ Same service, different caller |
| Schedule is "when", Vibe is "what", VibeDeviceAction is "side effects" | ✅ Model unchanged |
| `ScheduleExecution` is occurrence audit | ✅ Unchanged |
| No per-schedule action overrides | ✅ Actions remain on Vibe |
| No server-side audio playback | ✅ No audio in any backend path |

---

### 7.3 ADR-023 compliance — Execution order and failure policy

| Rule | Status |
|---|---|
| Execution order: (1) ScheduleExecution + next_run_at, (2) SH enqueue, (3) local reminder, (4) push failure | ✅ |
| SH dispatch is post-commit only | ✅ `dispatchSmartHomeAfterSchedule` runs outside `DB::transaction()` |
| SH dispatch only on `'dispatched'` — not `'skipped_duplicate'` | ✅ Code: `if ($result === 'dispatched')` |
| SH failure must not block recurrence | ✅ Isolated try/catch; recurrence already committed |
| One action failure must not block others | ✅ Per-job isolation |
| Push failure must not block scheduler or SH | ✅ `PushNotificationEvents` swallows internally |
| Local notification behaviour unchanged | ✅ 19 local tests; no changes to service |
| No server-side audio autoplay | ✅ Forbidden by design |
| Duplicate tick guard | ✅ `(schedule_id, occurrence_key)` unique index + pre-check |

---

### 7.4 ADR-024 compliance — Notifications and observability

| Rule | Status |
|---|---|
| No success push by default | ✅ No `automation_completed` event |
| Reuse existing event types — no new types | ✅ `schedule_execution_failed`, `smart_home_action_failed`, `smart_home_provider_unreachable` |
| Local notifications remain primary reminder path | ✅ Unchanged |
| `schedule_executions` is primary observability | ✅ Execution row per occurrence |
| `action_execution_logs` table | ⏸ Deferred — not MVP |
| `schedule_executions.log` SH summary | ⏸ Deferred (P4-4) |
| Push is best-effort; never blocks automation | ✅ |
| Deferred types: `automation_due`, `automation_completed`, `automation_failed` | ✅ Not emitted |

---

### 7.5 ADR-025 compliance — Mobile UX

| Rule | Status |
|---|---|
| No dedicated Automations tab | ✅ Not introduced |
| No automation builder UI | ✅ Read-only summaries only |
| Schedule form: read-only device action summary | ✅ Implemented Phase 5 |
| Vibe card: badges for scheduled + Smart Home | ✅ `AppAutomationBadge` |
| Schedule list: automation badge when vibe has actions | ✅ |
| No inline action editing on schedule form | ✅ Link to vibe Device Actions only |
| API embeds: `device_actions_count`, `has_device_actions`, `has_active_schedule`, `active_schedules_count` | ✅ Both resources enriched |

---

### 7.6 ADR-026 compliance — Execution security

| Rule | Status |
|---|---|
| No `Policy` / `Gate` in background execution | ✅ `ScheduleAutomationValidator` only |
| Validator returns `false` for expected failures — does not throw | ✅ Return contract respected |
| Validator failure does not emit push | ✅ ADR-026 explicit: log + skip |
| Validator skip does not stop recurrence | ✅ Recurrence already committed when validator runs |
| Validator failure does not emit `schedule_execution_failed` | ✅ Only thrown exception emits that push |
| No secrets logged | ✅ Only IDs in structured context |
| Ownership chain checked: schedule → vibe → device → providerConnection | ✅ All 4 levels |

---

### 7.7 ADR-027 compliance — Async orchestration pattern

| Rule | Status |
|---|---|
| Command orchestrates; does not own business rules | ✅ `processSchedule()` + `dispatchSmartHomeAfterSchedule()` delegate everywhere |
| Domain validator validates; no side effects | ✅ `ScheduleAutomationValidator` — DB reads only |
| Domain service executes intent | ✅ `VibeSmartHomeDispatchService::dispatch()` |
| Job performs one isolated unit of work | ✅ `SmartHomeActionJob` per action |
| Provider translates to external I/O | ✅ `HomeAssistantAdapter` — HTTP + DTO mapping |
| Reuse service from HTTP and background | ✅ `VibeSmartHomeDispatchService` used by both |
| Post-commit side effects | ✅ SH dispatch outside transaction |
| Batch continues on expected failure | ✅ Try/catch per schedule in foreach |

---

## 8. Regression checklist

Reusable before every release touching Scheduler, Smart Home, or Push.

### Scheduler

- [ ] `once` — executes once; `next_run_at = NULL`; `is_enabled = false`; no re-run next tick
- [ ] `daily` — `next_run_at` advances exactly +1 day in UTC
- [ ] `weekdays` — skips Saturday and Sunday; advances to Monday correctly
- [ ] `weekly` — requires `days_of_week` in `recurrence_config`; advances to next matching day
- [ ] `monthly` — blocked (`UnsupportedRecurrenceTypeException`); `schedule_execution_failed` push; batch continues
- [ ] Invalid recurrence config — transaction rolls back; `schedule_execution_failed` push; execution row absent; batch continues
- [ ] Dry-run mode — no side effects; reports would-be count
- [ ] N schedules due — each processed independently; one failure does not abort others

### Validator

- [ ] Schedule owner ≠ Vibe owner → skip + warning log; no SH; no push; recurrence committed
- [ ] Missing vibe (`vibe = null`) → skip; recurrence committed; no push
- [ ] Missing device → skip; recurrence committed; no push
- [ ] Missing provider connection → skip; recurrence committed; no push
- [ ] Device owner ≠ schedule owner → skip; recurrence committed; no push
- [ ] Connection owner ≠ schedule owner → skip; recurrence committed; no push
- [ ] Zero device actions → passes validator; `VibeSmartHomeDispatchService` dispatches zero jobs; no failure

### Idempotency

- [ ] Duplicate tick (same `occurrence_key`) → `skipped_duplicate`; exactly 1 execution row; no duplicate SH jobs
- [ ] `UniqueConstraintViolationException` race condition → handled as `skipped_duplicate`
- [ ] Worker restart mid-tick → idempotent resume; no double execution

### Smart Home execution

- [ ] Provider HTTP 200 → info log "action executed successfully"; no push; job completes
- [ ] Provider HTTP 5xx → warning log "action execution failed"; `smart_home_action_failed` push; job NOT in `failed_jobs`
- [ ] Unsupported action type → warning log "unsupported action — skipping"; no push; job NOT in `failed_jobs`
- [ ] Missing action row (`action not found or deleted`) → warning log; job skips; no push
- [ ] Missing device in `SmartHomeActionJob` → warning log; job skips; no push
- [ ] Missing provider connection in job → warning log; job skips; no push
- [ ] `sort_order` respected — actions dispatched ASC
- [ ] SH dispatch exception in command → recurrence committed; warning log; no push; batch continues

### Notifications

- [ ] `schedule_execution_failed` payload: `type`, `schedule_id` present as strings
- [ ] `smart_home_action_failed` payload: `type`, `device_id`, `vibe_id`, `action_type` present as strings
- [ ] `smart_home_provider_unreachable` payload: `type`, `provider_connection_id`, `provider` present as strings
- [ ] All payload `data` values are strings (never integers, booleans, or objects)
- [ ] No secrets in payload (FCM tokens, HA access tokens, credentials, provider config)
- [ ] No success push by default — no `automation_completed` type emitted
- [ ] No push on validator skip
- [ ] No push on SH dispatch exception
- [ ] No push on unsupported action type
- [ ] Push failure → domain (scheduler, SH jobs) unaffected
- [ ] Local reminder fires at `next_run_at` — offline-capable; no server dependency

### Mobile tap routing

- [ ] `schedule_execution_failed` → `/schedules` (not player, not devices)
- [ ] `smart_home_action_failed` → `/devices`
- [ ] `smart_home_provider_unreachable` → `/devices`
- [ ] `account_security_notice` → `/settings`
- [ ] Unknown type → no navigation; `console.warn` only
- [ ] Cold start → `router.isReady()` awaited before navigation
- [ ] Singleton guard → listener registered only once; no double-nav

### Mobile UX

- [ ] Schedules list loading: `AppLoadingState` with title + description; no bare spinner
- [ ] Schedules list empty: "No schedules yet" + guidance + CTA
- [ ] Schedules list error: `AppErrorState` + Retry; no stack trace in UI
- [ ] Schedule card: vibe name visible; `AppAutomationBadge` when `has_device_actions = true`
- [ ] Schedule form (edit) loading: `AppLoadingState` "Loading schedule…" + description
- [ ] Schedule form: read-only automation summary section with vibe name + badge
- [ ] Schedule form (zero actions): "No Smart Home actions — schedule will only remind you…"
- [ ] Schedule form: no inline action editing (read-only summary only)
- [ ] Vibes list loading: `AppLoadingState` + description
- [ ] Vibes list: automation badge "Used by an active schedule" when `has_active_schedule = true`
- [ ] Vibe detail loading: `AppLoadingState` (not bare spinner)
- [ ] Vibe detail error: `AppErrorState` + Retry
- [ ] Vibe detail: "Used by N active schedule(s)" or "Not scheduled yet" copy
- [ ] All badges: icon + visible text; never colour-only; `a11yLabel` set
- [ ] Local reminder tap: navigates to `/vibes/:id/player`; no audio auto-play
- [ ] No duplicate alert: local reminder and push failure are different events, never overlap

### Operations

- [ ] Scheduler worker ticking: `tick #N` in Runtime Logs ~every 60 s
- [ ] Queue worker consuming `push`, `smart-home`, `default` queues
- [ ] `jobs` table not backlogged on `smart-home` or `push`
- [ ] `QUEUE_CONNECTION = database`
- [ ] `PUSH_PROVIDER = fcm` (or `noop` in dev)
- [ ] Firebase credentials set in App Platform secrets
- [ ] `SMART_HOME_ALLOW_HTTP = false`
- [ ] `LOG_CHANNEL = stderr`
- [ ] `schedule_executions` unique index `(schedule_id, occurrence_key)` exists
- [ ] Validator skip log searchable: grep `Schedule Smart Home dispatch skipped`
- [ ] SH failure log searchable: grep `SmartHomeActionJob: action execution failed`
- [ ] Push failure log searchable: grep `PushNotificationJob: push failed`
- [ ] No secrets in logs (FCM tokens, HA access tokens, credentials)

---

## 9. Acceptance

### 9.1 Files created by Phase 8

| File | Purpose |
|---|---|
| `docs/qa/scheduler-smart-home-e2e.md` | This document — comprehensive E2E QA reference |
| `docs/qa/scheduler-smart-home-e2e/summary.md` | Phase 8 QA session report (detailed per-scenario results) |

### 9.2 Files modified by Phases 4–7 (implementation reference)

| File | Phase | Change |
|---|---|---|
| `back_vibes/app/Console/Commands/DispatchDueSchedulesCommand.php` | 4B | SH dispatch integration |
| `back_vibes/app/SmartHome/Validation/ScheduleAutomationValidator.php` | 4A | New validator |
| `back_vibes/app/SmartHome/Services/VibeSmartHomeDispatchService.php` | 4B | Reused unchanged |
| `back_vibes/app/Http/Resources/ScheduleResource.php` | 5 | API embeds |
| `back_vibes/app/Http/Resources/VibeResource.php` | 5 | API embeds |
| `front_vibes/src/components/ui/AppAutomationBadge.vue` | 5 | Badge component |
| `front_vibes/src/utils/automation-badges.ts` | 5 | Badge presets |
| `front_vibes/src/utils/automation-summary.ts` | 5 | Summary copy helpers |
| `front_vibes/src/services/push-notification-handler.service.ts` | 6 | Push tap routing |
| `back_vibes/tests/Feature/Scheduling/DispatchDueSchedulesCommandTest.php` | 7 | 33 tests |
| `back_vibes/tests/Unit/SmartHome/ScheduleAutomationValidatorTest.php` | 4A | 9 unit tests |

### 9.3 E2E scenarios

| ID | Name | Coverage | Status |
|---|---|---|---|
| SC-HP-1 | Schedule with SH actions — full automation | Happy path end-to-end | ✅ automated / ⏸ on-device |
| SC-HP-2 | Schedule without SH actions | Reminder-only path | ✅ |
| SC-HP-3 | `once` schedule — auto-disable | Recurrence once | ✅ |
| SC-HP-4 | Recurrence types | daily/weekdays/weekly | ✅ |
| SC-HP-5 | Multiple schedules in batch | Batch isolation | ✅ |
| SC-HP-6 | Dry-run mode | No side effects | ✅ |
| SC-F-1 | Validator — user/vibe mismatch | Skip + log | ✅ |
| SC-F-2 | Validator — missing vibe | Skip + log | ✅ |
| SC-F-3 | Validator — missing device | Skip + log | ✅ |
| SC-F-4 | Validator — missing connection | Skip + log | ✅ |
| SC-F-5 | Validator — device owner mismatch | Skip + log | ✅ |
| SC-F-6 | Duplicate tick | Idempotency | ✅ |
| SC-F-7 | Invalid recurrence | Transaction rollback + push | ✅ |
| SC-F-8 | SH dispatch exception | Recurrence preserved | ✅ |
| SC-F-9 | Provider HTTP 5xx | Job + push | ✅ |
| SC-F-10 | Provider unreachable (sync) | Connection + push | ✅ |
| SC-F-11 | Unsupported action type | Log only, no push | ✅ |
| SC-F-12 | Push delivery failure | Domain unaffected | ✅ |
| SC-F-13 | No push tokens | Safe skip | ✅ |

**Total: 19 scenarios — 17 fully automated, 2 requiring hardware (Android + HA)**

### 9.4 Coverage summary

| Layer | Automated | On-device | Result |
|---|---|---|---|
| Backend — dispatch + validator | ✅ 33 + 9 tests | — | **PASS** |
| Backend — failure isolation | ✅ | — | **PASS** |
| Backend — push notifications | ✅ | — | **PASS** |
| Frontend — tap routing | ✅ | — | **PASS** |
| Frontend — local notifications | ✅ 19 tests | ⏸ | **PASS (auto) / PENDING (device)** |
| Mobile UX — badges + enrichment | ✅ | ⏸ | **PASS (auto) / PENDING (device)** |
| Operational — workers + logs | ✅ (local) | ⏸ (staging live) | **PASS (local) / PENDING (staging)** |
| Architecture — ADR compliance | ✅ | — | **PASS** |

**Overall verdict: CONDITIONAL PASS**

All automated checks pass. On-device (Android local reminder, tap-to-player, dark mode) and live-HA (device state change, unreachable HA) steps are pending hardware availability.

### 9.5 Operational validation

- All commands in operational checklist are executable as written
- No outdated commands found
- No obsolete env vars found
- All three required workers (`api`, `queue`, `scheduler`) documented and IaC-verified
- Log grep patterns verified against implementation
- Failure matrix in runbook matches Phase 4B implementation exactly

### 9.6 Architecture validation

- No layer violations found across all 6 ADRs (022–027)
- Entrypoint → Validator → Domain Service → Queue → Provider chain respected in code
- No direct provider calls from command or validator
- No Policy/Gate usage in background paths
- `VibeSmartHomeDispatchService` correctly reused from both HTTP and scheduler paths

### 9.7 Remaining issues (bugs only — do not fix in Phase 8)

| ID | Severity | Description | Phase |
|---|---|---|---|
| **QA-001** | Low — deferred | `schedule_executions.log` does not include Smart Home dispatch summary (P4-4 deferred) | 8.x |
| **QA-002** | Low — coverage gap | No `Log::info` assertion on successful SH dispatch path — observability improvement | 8.x |
| **QA-003** | Low — design note | `SmartHomeActionJob $tries = 3` mostly ineffective for provider failures (exceptions caught internally) | Documented in runbook; working as intended per ADR-023 |
| **QA-004** | ⏸ Environment | On-device Android QA: local reminder, tap handler, player launch | Requires connected Android device |
| **QA-005** | ⏸ Environment | Live HA QA: real device state change on HA, unreachable HA → push | Requires HA test environment |

### 9.8 Recommendations for Phase 8.x

| Topic | Recommendation |
|---|---|
| **On-device QA** | Connect Android device → `adb devices` → install staging APK → run SC-HP-1 and SC-HP-4 manually |
| **HA test environment** | Configure sandbox HA instance → run SC-F-9 and SC-F-10 against live provider |
| **SH dispatch info log** | Add `Log::info` after successful `dispatch()` with `schedule_id`, `dispatched`, `skipped` counts |
| **`schedule_executions.log` summary** | Implement P4-4 if per-occurrence SH audit becomes operationally necessary |
| **`monthly` recurrence** | Implement when roadmap includes monthly automation cadence |
| **`schedule_id` in SH failure push** | Add optional `schedule_id` to `smart_home_action_failed` payload when schedule context is available (ADR-024 allows) |

---

## Related documents

| Document | Role |
|---|---|
| [`specs/scheduler-smart-home-automations/mvp/spec.md`](../specs/scheduler-smart-home-automations/mvp/spec.md) | Feature spec — acceptance criteria |
| [`specs/scheduler-smart-home-automations/mvp/tasks.md`](../specs/scheduler-smart-home-automations/mvp/tasks.md) | Phase-by-phase task status |
| [`operations/scheduler-smart-home-operational-checklist.md`](../operations/scheduler-smart-home-operational-checklist.md) | Operational runbook |
| [`qa/scheduler-smart-home-e2e/summary.md`](scheduler-smart-home-e2e/summary.md) | Phase 8 QA session report |
| [`architecture/notification-architecture.md`](../architecture/notification-architecture.md) | Push taxonomy and pipeline |
| [`architecture/domain-validation.md`](../architecture/domain-validation.md) | Validator design |
| [`architecture/asynchronous-orchestration.md`](../architecture/asynchronous-orchestration.md) | Async layer model |
| [`architecture/user-experience-principles.md`](../architecture/user-experience-principles.md) | UX checklist |
| [ADR-022](../decisions/ADR-022-scheduler-smart-home-automation-model.md) | Automation model |
| [ADR-023](../decisions/ADR-023-automation-execution-order-and-failure-policy.md) | Execution order + failure policy |
| [ADR-024](../decisions/ADR-024-automation-notifications-and-observability.md) | Notifications + observability |
| [ADR-025](../decisions/ADR-025-automation-mobile-ux.md) | Mobile UX |
| [ADR-026](../decisions/ADR-026-automation-execution-security.md) | Execution security |
| [ADR-027](../decisions/ADR-027-asynchronous-orchestration-pattern.md) | Async orchestration pattern |

---

*Last updated: 2026-07-03 — Phase 8 E2E QA (Scheduler + Smart Home Automations MVP).*
