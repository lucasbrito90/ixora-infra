# Domain Execution Review — Phase 7B.4.1 (`back_vibes`)

**Status:** Complete — discovery only, no telemetry implemented
**Repo reviewed:** `back_vibes` (Laravel 13.20.0, PHP 8.3+)
**Feature ID:** `observability-foundation/business-telemetry`
**Type:** Architecture review (read-only). No spans, metrics, logs, OpenTelemetry code, refactors, or behavior changes were introduced by this phase.
**Prerequisite reading:** [backend-generic-scheduler-instrumentation.md](../mvp/backend-generic-scheduler-instrumentation.md) (Phase 7B.3) · [ADR-022](../../../decisions/ADR-022-scheduler-smart-home-automation-model.md) · [ADR-023](../../../decisions/ADR-023-automation-execution-order-and-failure-policy.md) · [ADR-026](../../../decisions/ADR-026-automation-execution-security.md) · [ADR-027](../../../decisions/ADR-027-asynchronous-orchestration-pattern.md) · [dispatch-integration-review.md](../../scheduler-smart-home-automations/mvp/dispatch-integration-review.md) · [scheduler-smart-home-e2e.md](../../../qa/scheduler-smart-home-e2e.md)

---

## 0. Purpose and method

This document is the **Level 2** counterpart to Phase 7B.3's Level 1 (generic Laravel Scheduler) review: it maps the **Ixora business execution pipeline** for a Smart Home automation — i.e. what happens, in code, between "a Vibe's device actions should run" and "a provider received an HTTP call" — with the same rigor and no assumptions.

Every finding below was produced by reading the actual `back_vibes` source (controllers, services, jobs, adapters, models, policies, routes, config, migrations) and the existing `ixora-infra` specs/ADRs/QA docs that already govern this feature (`scheduler-smart-home-automations/mvp`). Nothing here is inferred from naming conventions alone — where a claim depends on a specific line of code, it is cited. Where the codebase and an ADR agree, both are cited. Where a gap exists between what an ADR expects and what code does today, it is called out explicitly (§14).

**No source code was changed to produce this document**, aside from this file itself and its cross-references in the observability-foundation index docs.

---

## 1. Entry points (Part 1)

There are exactly **two** ways a Smart Home execution (`SmartHomeActionJob`) can be enqueued today, plus one adjacent-but-distinct pipeline (provider device sync) that is often confused with "execution" but is not one. A fourth theoretical path (native Laravel Scheduler) does not exist in this codebase (confirmed — see Phase 7B.3 §4 and §1.4 below).

### 1.1 Manual (mobile-triggered) dispatch

| | |
| --- | --- |
| **Class** | `App\Http\Controllers\Api\VibeSmartHomeDispatchController` |
| **Method** | `__invoke(Request $request, Vibe $vibe)` |
| **Route** | `POST /api/vibes/{vibe}/smart-home/dispatch` (`routes/api.php:87`, inside the `firebase.auth` middleware group, nested under `Route::prefix('vibes/{vibe}')`) |
| **Caller** | Mobile client, when the user taps "Play" on a Vibe (per the controller's own docblock: *"Handles a vibe play trigger from mobile"*) |
| **Responsibilities** | Authorize (`$this->authorize('view', $vibe)` → `VibePolicy::view`, owner-only), delegate to `VibeSmartHomeDispatchService::dispatch($vibe)`, return a JSON summary (`vibe_id`, `dispatched`, `skipped`, `action_ids`) |
| **Explicitly not responsible for** | Calling any provider, blocking on any provider, playing audio (docblock: *"Never blocks audio playback on mobile"*, *"Never calls Home Assistant or any provider adapter"*) |

### 1.2 Scheduled (automatic) dispatch

| | |
| --- | --- |
| **Class** | `App\Console\Commands\DispatchDueSchedulesCommand` |
| **Method** | `handle(RecurrenceService, PushNotificationEvents, ScheduleAutomationValidator, VibeSmartHomeDispatchService)`, specifically the private `dispatchSmartHomeAfterSchedule()` helper it calls per due schedule |
| **Caller** | `App\Console\Commands\DispatchSchedulesLoopCommand` — a long-running worker loop (`schedules:dispatch-loop`) that calls `schedules:dispatch-due` via `$this->callSilently('schedules:dispatch-due')` roughly every `--interval` seconds (default 60s). This loop is itself started as a DigitalOcean App Platform **worker component process** (per its own docblock), not via `cron`, not via Laravel's native Scheduler (`Illuminate\Console\Scheduling\Schedule`) |
| **Responsibilities** | Query due `Schedule` rows, record `ScheduleExecution` occurrences idempotently (inside `DB::transaction()`), advance `next_run_at`/`last_run_at`, and — **only for occurrences newly created in this tick** (`$result === 'dispatched'`, never `'skipped_duplicate'`) — validate ownership via `ScheduleAutomationValidator::validate()` and, if valid, call `VibeSmartHomeDispatchService::dispatch($vibe)` |
| **Explicitly not responsible for** | Calling any provider directly (no `Http::`/adapter import in this file — verified by grep), ownership checks inline (delegated to the validator) |

### 1.3 Provider device sync — adjacent, not an execution path

| | |
| --- | --- |
| **Class** | `App\Http\Controllers\Api\ProviderConnectionController` |
| **Method** | `sync(Request, ProviderConnection, ProviderDeviceSyncService)` |
| **Route** | `POST /api/provider-connections/{providerConnection}/sync` (`routes/api.php:36`) |
| **Caller** | Mobile client, user-initiated ("Sync devices" action), not tied to any Vibe or Schedule |
| **Responsibilities** | Authorize (`update` on the connection), delegate to `ProviderDeviceSyncService::sync($connection)`, which calls `ProviderAdapter::listDevices()` **synchronously in the request** (not queued), upserts `Device` rows, marks absent devices offline, updates connection status |
| **Why it is not a "Smart Home execution"** | It never touches a `Vibe`, `VibeDeviceAction`, or `SmartHomeActionJob`. It is a device **inventory** pipeline (discovering/refreshing what devices exist and their raw provider status), not an **action** pipeline (commanding a device to do something on behalf of a Vibe). It is documented separately here because a careless Business Telemetry design could conflate the two and double-count "Smart Home" activity that has nothing to do with a Vibe execution |

### 1.4 Entry points that do **not** exist today (verified, not assumed)

| Candidate entry point | Verified status |
| --- | --- |
| Native Laravel Scheduler (`Schedule::call()`/`Schedule::job()`/`Schedule::command()` in `routes/console.php` or a `Console\Kernel`) | **Does not exist.** `routes/console.php` contains only the stock `Artisan::command('inspire', ...)` closure — no `Schedule::` facade usage anywhere in the repo (grepped for `->everyMinute(`, `->cron(`, `Schedule::command`, `protected function schedule` — zero matches). Confirms Phase 7B.3 §4's finding still holds for the business layer: `back_vibes` never runs `schedule:run`/`schedule:work` |
| Event listener triggering execution (e.g. a domain event like `VibeCreated` auto-dispatching actions) | **Does not exist.** Grepped for `Event::dispatch`, `Event::listen`, and any `EventServiceProvider` registration tying a Laravel event to `SmartHomeActionJob`/`VibeSmartHomeDispatchService` — no matches. There is no domain event bus in the Smart Home or Scheduler modules at all (§11) |
| Webhook (provider-initiated, e.g. Home Assistant pushing a state change to Ixora) | **Does not exist.** No inbound webhook route for any provider. `HomeAssistantAdapter` only makes outbound calls; Ixora never receives provider-initiated callbacks |
| Artisan command for ad-hoc/manual execution (e.g. `smart-home:run-action`) | **Does not exist.** `app/Console/Commands/` contains only `DispatchDueSchedulesCommand` and `DispatchSchedulesLoopCommand` — no standalone Smart Home Artisan command |
| Queue-internal retry/backoff re-trigger | **Does not exist as a business concept.** `SmartHomeActionJob` does have `$tries = 3` (Laravel's generic queue retry), but the job's own `handle()` catches every failure mode internally and returns normally (§7) — it never actually throws in a way that would cause Laravel to re-attempt it. The `tries` property is effectively inert for this job (confirmed independently by the pre-existing QA finding **QA-003** in `scheduler-smart-home-e2e.md`: *"`SmartHomeActionJob $tries = 3` mostly ineffective for provider failures (exceptions caught internally)"*) |
| "Future placeholders" for other providers (Tuya, Philips Hue, Alexa, Google Home, Matter) | **Reserved as enum cases only.** `App\SmartHome\ProviderType` lists all six as enum cases, but only `HomeAssistant` has an adapter registered in `ProviderAdapterResolver`; any other value throws `InvalidArgumentException` at dispatch time. No placeholder execution path exists for them beyond the enum case itself |

---

## 2. Complete execution pipeline / call graph (Part 2)

Both real entry points (§1.1, §1.2) **converge** on the same two classes — `VibeSmartHomeDispatchService` and `SmartHomeActionJob` — which is the single most important structural fact in this codebase (see §3). The call graph below is exhaustive: every class, method, and file involved from entry point to the final provider HTTP call is listed, with nothing omitted.

### 2.1 Manual path — full call graph

```
POST /api/vibes/{vibe}/smart-home/dispatch
  └─ VibeSmartHomeDispatchController::__invoke(Request, Vibe $vibe)
       ├─ AuthorizesRequests::authorize('view', $vibe)
       │    └─ VibePolicy::view(User, Vibe)                              [ownership check: user_id match]
       └─ VibeSmartHomeDispatchService::dispatch(Vibe $vibe)             [Domain Service — §3]
            ├─ VibeDeviceAction::where('vibe_id', ...)->with('device')->orderBy('sort_order')->get()
            ├─ foreach action:
            │    ├─ if action.device === null → skip++, continue
            │    └─ SmartHomeActionJob::dispatch($action->id)            [enqueue only — queue: "smart-home"]
            └─ return SmartHomeDispatchResult(vibe_id, dispatched, skipped, action_ids)
       (controller serializes SmartHomeDispatchResult to JSON, returns 200)
```

### 2.2 Scheduled path — full call graph

```
DispatchSchedulesLoopCommand::handle()                                   [worker loop, schedules:dispatch-loop]
  └─ every --interval seconds: $this->callSilently('schedules:dispatch-due')
       └─ DispatchDueSchedulesCommand::handle(RecurrenceService, PushNotificationEvents,
                                               ScheduleAutomationValidator, VibeSmartHomeDispatchService)
            ├─ Schedule::query()->with(['vibe.deviceActions.device.providerConnection'])
            │       ->where(is_enabled, next_run_at <= now)->orderBy('next_run_at')->limit($batch)->get()
            └─ foreach due Schedule:
                 ├─ processSchedule($schedule, $recurrenceService, $nowUtc)   [DB::transaction — see §4]
                 │    ├─ RecurrenceService::computeOccurrenceKey(schedule_id, scheduledFor)
                 │    ├─ ScheduleExecution::where(schedule_id, occurrence_key)->exists()
                 │    │       → true: return 'skipped_duplicate'
                 │    ├─ ScheduleExecution::create([...])                     [may throw UniqueConstraintViolationException
                 │    │                                                        → caught → 'skipped_duplicate']
                 │    ├─ RecurrenceService::computeNextRunAt(ScheduleInput, scheduledFor)
                 │    ├─ $schedule->last_run_at / next_run_at / is_enabled updated, ->save()
                 │    └─ return 'dispatched'
                 ├─ if result === 'dispatched':
                 │    └─ dispatchSmartHomeAfterSchedule($schedule, $validator, $smartHomeDispatch)   [post-commit,
                 │                                                                                     outside the
                 │                                                                                     transaction]
                 │         ├─ ScheduleAutomationValidator::validate($schedule)      [Domain Validator — §3]
                 │         │    ├─ resolveVibe($schedule) → null? return false
                 │         │    ├─ schedule.user_id !== vibe.user_id? return false
                 │         │    └─ foreach VibeDeviceAction: isActionValidForSchedule()
                 │         │           (device null? device.user_id mismatch? providerConnection null?
                 │         │            connection.user_id mismatch? → false)
                 │         ├─ if false: Log::warning(...) and return (no dispatch, no push)
                 │         ├─ if vibe === null: return
                 │         └─ VibeSmartHomeDispatchService::dispatch($vibe)         [identical call graph to §2.1]
                 │              └─ SmartHomeActionJob::dispatch($action->id) ×N
                 ├─ catch (Throwable $e) [only from processSchedule(), i.e. the transaction]:
                 │    └─ notifyScheduleFailure($schedule, $pushEvents)
                 │         └─ PushNotificationEvents::notifyScheduleExecutionFailed(user, transient ScheduleExecution)
                 │              └─ PushNotificationService::sendToUser(user, ScheduleExecutionFailedNotification::build())
                 │                   └─ PushNotificationJob::dispatch(userId, payload)   [queue: "push" — separate pipeline]
                 └─ outputSummary(...)  [stdout only]
```

Note the exception scope: the `catch (Throwable $e)` in `handle()` wraps only `processSchedule()` (the transaction). `dispatchSmartHomeAfterSchedule()` has **its own internal** `try/catch` (§7) and never lets an exception escape to the outer loop — so a Smart Home dispatch failure never triggers `notifyScheduleFailure()` (that push is reserved for *recurrence*-transaction failures only, confirmed by `scheduler-smart-home-e2e.md` SC-F-8).

### 2.3 Job execution — shared by both paths, full call graph

```
SmartHomeActionJob::handle(ProviderAdapterResolver $resolver, PushNotificationEvents $pushEvents)
  ├─ VibeDeviceAction::with(['device', 'device.providerConnection', 'device.user'])->find($this->vibeDeviceActionId)
  │       → null? Log::warning(...); return                                    [terminal — job completes normally]
  ├─ $device = $action->device → null? Log::warning(...); return               [terminal]
  ├─ $connection = $device->providerConnection → null? Log::warning(...); return  [terminal]
  ├─ try:
  │    ├─ ProviderAdapterResolver::forProvider($connection->provider)          [Provider Resolution — §4]
  │    │       → match: HomeAssistant => HomeAssistantAdapter; default => throw InvalidArgumentException
  │    ├─ HomeAssistantAdapter::executeAction($connection, provider_device_id, action_type, parameters)
  │    │    ├─ ACTION_SERVICE_MAP[$action] ?? null → null: throw UnsupportedSmartHomeActionException
  │    │    ├─ domainFor($deviceId)   [derives HA domain, e.g. "light", from the entity_id prefix]
  │    │    ├─ client($connection)->post(baseUrl/api/services/{domain}/{service}, payload)   [Provider Call — §4]
  │    │    │       ├─ client() decrypts connection->decryptedCredentials()['access_token'] (never logged)
  │    │    │       └─ catch ConnectionException → return ActionResult(success:false, status_code:null, ...)
  │    │    └─ return ActionResult(success, status_code, response, error_message)
  │    ├─ logResult($context, $result)     [Log::info on success, Log::warning on failure — §11]
  │    └─ if !$result->success: notifyActionFailed($action, $pushEvents)
  │             └─ PushNotificationEvents::notifySmartHomeActionFailed(user, action)
  │                  └─ ... → PushNotificationJob::dispatch(...)   [same push pipeline as §2.2]
  ├─ catch (UnsupportedSmartHomeActionException $e):
  │    └─ Log::warning(...)   [no push — ADR-026: log + skip, retrying would not help]
  └─ catch (Throwable $e) [catch-all — provider/infra errors]:
       ├─ Log::error(...)
       └─ notifyActionFailed($action, $pushEvents)
```

**The pipeline terminates inside the job.** There is no step after `logResult()`/`notifyActionFailed()` — no persistence of an execution outcome record (§5, §11), no return value consumed by anything, no chained job, no event dispatched. The job's `handle()` returning `void` normally is the entire "success" signal; nothing downstream observes it.

### 2.4 Components identified, mapped to the requested taxonomy (Part 2)

| Taxonomy category (from the prompt) | Concrete class(es) | Notes |
| --- | --- | --- |
| **Controllers** | `VibeSmartHomeDispatchController`, `ProviderConnectionController` (sync, adjacent pipeline) | Thin — authorize + delegate + serialize only |
| **Actions** | *(none — this codebase does not use an "Action" class convention for Smart Home; `app/Actions/` exists only for `CoverBundle` and `Sound`, unrelated domains)* | |
| **Services** | `VibeSmartHomeDispatchService`, `ProviderDeviceSyncService` (adjacent), `RecurrenceService` (scheduling, not Smart Home) | |
| **Domain Services** | Same as above | This codebase does not distinguish "Service" from "Domain Service" as separate class suffixes; `VibeSmartHomeDispatchService` fills the ADR-027 "Domain Service" role by convention, not by a `DomainService` base class or namespace |
| **Resolvers** | `ProviderAdapterResolver` | Single `match` expression, one real branch (`HomeAssistant`) |
| **Executors** | *(none — no class literally named "Executor"; the closest concept is `SmartHomeActionJob::handle()` itself, which both orchestrates the unit of work and is where "execution" colloquially happens)* | |
| **Factories** | *(none in this pipeline)* | |
| **Repositories** | *(none — no repository abstraction; all data access is direct Eloquent (`VibeDeviceAction::where(...)`, `Schedule::query()`, etc.) inside services/commands/jobs)* | |
| **Adapters** | `HomeAssistantAdapter` (implements `ProviderAdapter`) | The only shipped adapter |
| **Gateways** | *(none — "Gateway" is not a class suffix used anywhere in this codebase; `HomeAssistantAdapter` is the closest concept)* | |
| **Jobs** | `SmartHomeActionJob`, `PushNotificationJob` (downstream, notification pipeline only) | |
| **Events** | *(none — no Laravel domain events dispatched anywhere in this pipeline; see §11)* | |
| **Listeners** | *(none, for the same reason)* | |
| **Commands** | `DispatchDueSchedulesCommand`, `DispatchSchedulesLoopCommand` | Scheduled path only; manual path has no Artisan command |
| **Pipelines** | *(none — no Laravel `Pipeline` facade/class usage anywhere in this call graph)* | |
| **Workflows** | *(none — no workflow/state-machine package or abstraction in use)* | |
| **State Machines** | *(none)* — `Device.status` / `ProviderConnection.status` are plain string enums with direct assignment, not a modeled state machine (no transition guards, no `spatie/laravel-model-states` or similar) | |
| **Transactions** | `DB::transaction()` in `DispatchDueSchedulesCommand::processSchedule()` (schedule-recurrence write only); `DB::transaction()` in `ProviderDeviceSyncService::sync()` (adjacent pipeline) | **No transaction wraps any part of the Smart Home action-execution path itself** — `VibeSmartHomeDispatchService::dispatch()` and `SmartHomeActionJob::handle()` run with zero `DB::transaction()` calls (§6, §7) |

---

## 3. The orchestrator(s) (Part 3)

There is **no single orchestrator** for the end-to-end Smart Home execution. Instead there are **two independent, non-nested entry-point orchestrators**, each responsible only for *getting to* the shared dispatch/job pair, and one shared micro-orchestrator inside the pipeline itself:

| Role | Class | What it actually orchestrates | What it explicitly does not do |
| --- | --- | --- | --- |
| **Entry-point orchestrator (manual)** | `VibeSmartHomeDispatchController` | HTTP request → authorization → one service call → response | No business rules, no provider knowledge |
| **Entry-point orchestrator (scheduled)** | `DispatchDueSchedulesCommand` | Schedule batch iteration, recurrence transaction, per-schedule validator + dispatch call, per-schedule failure isolation, batch summary | No provider knowledge, no ownership logic (delegated), no queue/job knowledge beyond calling the service |
| **Shared dispatch orchestrator** | `VibeSmartHomeDispatchService` | Loading a Vibe's ordered device actions and enqueuing one job per action; this is the **true convergence point** — the only class both entry points call, and the only class that decides "how many jobs, in what order" | Never resolves a provider adapter, never makes an HTTP call (enforced by its own docblock and dependency-free constructor — it has zero constructor dependencies) |
| **Per-unit orchestrator** | `SmartHomeActionJob` | Loading one action's full relation chain, resolving the adapter, calling it, logging, notifying on failure — a self-contained "orchestrator" for exactly one device action | Never touches other actions, never touches the Schedule/ScheduleExecution that (may have) triggered it — it has **no reference back to its trigger** (§14) |

**This matches ADR-027's documented model exactly** (`Async Entrypoint → Domain Validator → Domain Service → Queue Job → Provider/Adapter`, confirmed against `ADR-027-asynchronous-orchestration-pattern.md` §"Reference example — Scheduler + Smart Home"), and the codebase was found to conform to it with no violations detected: no provider call outside `HomeAssistantAdapter`, no ownership check outside `ScheduleAutomationValidator`/`VibePolicy`, no cross-aggregate batch loop outside the two commands/controller.

**No nested orchestration exists** — `VibeSmartHomeDispatchService` does not call back into either command/controller, and `SmartHomeActionJob` does not call `VibeSmartHomeDispatchService` or vice versa. The two "trees" (manual, scheduled) are structurally identical siblings that happen to share their bottom two layers (service + job), not a parent/child orchestration relationship.

---

## 4. Domain boundaries (Part 4)

The boundaries that actually exist in code, in execution order. Each row cites the exact class/method where the boundary is crossed.

```
Trigger Resolution           ─ VibeSmartHomeDispatchController::__invoke()  (a Vibe, direct from HTTP)
                                — or —
                                DispatchDueSchedulesCommand::dispatchSmartHomeAfterSchedule()  (a Vibe, via a Schedule)
      ↓
Automation Validation         ─ ScheduleAutomationValidator::validate()   [scheduled path ONLY — see note below]
      ↓
Vibe Action Resolution        ─ VibeSmartHomeDispatchService::dispatch()
                                 (VibeDeviceAction::where('vibe_id', ...)->orderBy('sort_order')->get())
      ↓
Job Enqueue                   ─ SmartHomeActionJob::dispatch($action->id)   [boundary: sync code → queue]
      ↓  (queue worker process boundary — potentially a different OS process/host)
Action Rehydration             ─ SmartHomeActionJob::handle() re-loads VibeDeviceAction + device + providerConnection
                                 by ID (the job carries only an integer ID — SerializesModels re-fetches everything)
      ↓
Device Action Resolution      ─ SmartHomeActionJob::handle() null-checks device / connection (own boundary,
                                 not delegated to a validator — see gap in §14)
      ↓
Provider Resolution           ─ ProviderAdapterResolver::forProvider($connection->provider)
      ↓
Provider Call                 ─ HomeAssistantAdapter::executeAction()  (HTTP boundary — Ixora code ends here, §9)
      ↓
Result                        ─ ActionResult DTO returned in-process to the job (never persisted, never returned
                                 to any caller — the job is the last consumer)
      ↓
Persistence                   ─ NONE for the action outcome itself (see §11) — only Log:: calls
      ↓
Notification                  ─ PushNotificationEvents::notifySmartHomeActionFailed()   [failure path only]
```

**Important boundary asymmetry — "Automation Validation" is scheduled-path-only.** The manual path (§1.1, §2.1) has **no equivalent validation boundary** between "Trigger Resolution" and "Vibe Action Resolution" beyond the controller's single `authorize('view', $vibe)` policy check. `ScheduleAutomationValidator` exists specifically because the scheduled path runs with no HTTP-authenticated user and must re-verify the entire ownership chain (schedule → vibe → device → connection) itself (per ADR-026); the manual path already has an authenticated, policy-checked user and relies on that instead. This is a **real, intentional architectural asymmetry** (documented in ADR-026's *"No `Policy`/`Gate` in background execution... Policies = HTTP; Domain Validators = background"*), not an inconsistency — but it means any future telemetry boundary named uniformly (e.g. "AutomationValidation") would only ever fire for one of the two entry points, and must be named/labeled so that absence-in-manual-path is not misread as a failure.

**"Device Action Resolution" is duplicated, not shared.** Both `ScheduleAutomationValidator::isActionValidForSchedule()` (scheduled path, pre-enqueue) and `SmartHomeActionJob::handle()`'s own null-checks (both paths, inside the job) independently check for a missing `device`/`providerConnection`. This is not a bug — the validator's check happens *before* enqueue (skip the whole vibe's dispatch); the job's check happens *at* execution time (skip just this one action, protecting against a device/connection deleted in the window between enqueue and job execution) — but it means "device missing" is a condition observable at two different boundaries with two different blast radii, which matters for designing a metric label (§10) that must not conflate the two.

---

## 5. Domain objects (Part 5)

| Object | Purpose | Ownership | Lifecycle |
| --- | --- | --- | --- |
| **`Vibe`** (`App\Models\Vibe`) | The user-facing "experience bundle" — audio layers + optional Smart Home side effects. The unit a user "plays" | Owned by a `User` (`user_id`); has many `VibeDeviceAction` (`deviceActions()`), many `Sound` (via `vibe_sounds` pivot), many `Schedule` | Created/updated/deleted via `VibeController` CRUD (`apiResource('vibes', ...)`). Deleting a Vibe is not traced through this review (out of scope — no cascade behavior for device actions was inspected here) |
| **`Device`** (`App\Models\Device`) | A single provider-side controllable entity (light, switch, media_player, fan), normalized into Ixora's registry | Owned by a `User` (`user_id`) and a `ProviderConnection` (`provider_connection_id`); the *source of truth* for a device's existence is the provider, not Ixora — `Device` rows are upserted by `ProviderDeviceSyncService`, never created directly by a user action | Created/updated by `ProviderDeviceSyncService::sync()` (upsert on `(provider_connection_id, provider_device_id)`); `status` flips to `offline`/`unknown` on sync absence or connection unreachability; CRUD also exposed via `DeviceController` (`apiResource('devices', ...)`) for user-facing metadata (name, etc.) |
| **`VibeDeviceAction`** (`App\Models\VibeDeviceAction`) | One ordered command to run against one `Device` when its `Vibe` is dispatched — the actual unit of work a `SmartHomeActionJob` executes | Belongs to exactly one `Vibe` and one `Device`; user-managed via `VibeDeviceActionController` (`store`/`update`/`destroy`/`reorder`) | Created/reordered/deleted directly by the user through the vibe's device-actions API (`routes/api.php:89-94`); `sort_order` determines dispatch order; `delay_seconds` is persisted and validated (0–3600) but **never read by any execution-path code** — confirmed by grep, this field has no runtime effect today (§14 — open question, not a bug to fix in this phase) |
| **`ProviderConnection`** (`App\Models\ProviderConnection`) | A user's credentials + config for one provider account (e.g. one Home Assistant instance) | Owned by a `User`; has many `Device` | Created/updated via `ProviderConnectionController` CRUD; `status` (`connected`/`unreachable`/`unknown`) updated only by `ProviderDeviceSyncService::sync()` and `HomeAssistantAdapter::testConnection()` call sites — **not** updated by `SmartHomeActionJob`'s own action-execution failures (a failed `executeAction()` call does **not** mark the connection unreachable — only a failed `listDevices()`/sync does) |
| **`Schedule`** (`App\Models\Schedule`) | The recurrence/timing source of truth — "when" — for automatic Vibe dispatch | Owned by a `User`; belongs to one `Vibe`; has many `ScheduleExecution` | Created/updated via `ScheduleController` CRUD; `next_run_at`/`last_run_at`/`is_enabled` mutated exclusively by `DispatchDueSchedulesCommand::processSchedule()` |
| **`ScheduleExecution`** (`App\Models\ScheduleExecution`) | The **audit record of a Schedule occurrence** — proof that a tick fired for a given `(schedule_id, occurrence_key)` | Owned by a `Schedule`; write-once per occurrence (idempotency via unique `(schedule_id, occurrence_key)` index, ADR-010) | Created exactly once per real occurrence inside `processSchedule()`'s transaction; **never updated afterward** — its `log` JSON column is set once at creation (`{command, batch_time_utc}`) and is not appended to with the Smart Home dispatch outcome, despite `scheduler-smart-home-e2e.md` QA-001 and the reference review both explicitly flagging this as a deferred, not-yet-implemented enrichment |
| **`ActionResult`** (`App\SmartHome\DTOs\ActionResult`, readonly DTO) | The immediate outcome of one provider call — `success`, `status_code`, `response`, `error_message` | Created fresh by `HomeAssistantAdapter::executeAction()` per call; consumed once by `SmartHomeActionJob::handle()` | **Not persisted anywhere.** Lives only in-memory for the duration of one job's `handle()` call, then discarded (logged, not stored) |
| **`SmartHomeDispatchResult`** (`App\SmartHome\DTOs\SmartHomeDispatchResult`, readonly DTO) | The summary of one `dispatch()` call — counts + IDs of enqueued jobs | Created by `VibeSmartHomeDispatchService::dispatch()`; consumed by `VibeSmartHomeDispatchController` (serialized to the API response) **or silently discarded** by `dispatchSmartHomeAfterSchedule()` (the scheduled path calls `dispatch()` but never reads its return value — confirmed by reading the caller; the summary exists but nothing captures it in the scheduled path) | Not persisted; ephemeral per call |
| **"Execution" as a first-class object** | **Does not exist for Smart Home.** There is no `SmartHomeExecution`/`ActionExecutionLog`/history table or model anywhere in `database/migrations` (grepped for `execution_id`, `correlation_id`, `trace_id`, `smart_home_action_executions`, `action_history` — zero matches). `ScheduleExecution` records only that a *schedule* fired — it has no column and no relation representing "and here is what happened to each of its Smart Home actions" | — | — |
| **Provider-side concepts** (Capability, Trigger, Condition) | **Do not exist as Ixora domain objects.** There is no `Capability` model (device capabilities are informally encoded as the `ACTIONABLE_DOMAINS` constant + `ActionType` enum, provider-side only, inside `HomeAssistantAdapter`), no `Trigger`/`Condition` model (per ADR-022, MVP explicitly excludes a rules engine — "if temperature > X" style triggers are listed as a *future* justification for a dedicated `automations` table, not something that exists today) | — | — |

---

## 6. Current execution model (Part 6)

| Level | Model | Evidence |
| --- | --- | --- |
| **Across schedules in one batch** (`DispatchDueSchedulesCommand::handle()`) | **Sequential.** `foreach ($due as $schedule)` — a plain PHP loop, one schedule fully processed (transaction + validator + dispatch) before the next begins. No concurrency, no `Bus::batch()`, no fan-out at this level | `DispatchDueSchedulesCommand.php:70-93` |
| **Across device actions within one Vibe dispatch** (`VibeSmartHomeDispatchService::dispatch()`) | **Sequential enqueue, then fan-out.** The `foreach ($actions as $action)` loop that calls `SmartHomeActionJob::dispatch()` is sequential (enqueue order = `sort_order` ASC), but enqueuing is not executing — once on the queue, the *actual* execution of each job is entirely dependent on the queue worker's own concurrency model (note below). This is a **fan-out** at the enqueue boundary: one Vibe dispatch → N independent queue messages | `VibeSmartHomeDispatchService.php:38-49` |
| **Execution of the N queued jobs** | **Not controlled by any Ixora code at all.** A single `queue:work` process processes one job at a time by default (no parallel worker processes are documented in the reviewed ops docs); running multiple worker processes/containers would parallelize it, but that is an infrastructure decision, not a Smart Home domain decision. **From the domain's perspective, there is no guarantee of ordering or concurrency once jobs are on the queue** — the `sort_order` guarantee is an *enqueue-order* guarantee only, not an *execution-order* guarantee (two jobs could be picked up out of order by two concurrent workers) | `php artisan queue:work --queue=push,smart-home,default` (`scheduler-smart-home-e2e.md` §6.1.3) |
| **Within one job** (`SmartHomeActionJob::handle()`) | **Strictly sequential, single provider call.** Rehydrate → resolve adapter → one `executeAction()` HTTP call → log → maybe notify. No parallelism, no recursion, no sub-jobs | `SmartHomeActionJob.php:56-143` |
| **Overall shape** | **Fan-out tree, two levels deep, with no fan-in.** `Schedule → Vibe → N×VibeDeviceAction → N×SmartHomeActionJob`. There is no fan-in step anywhere — no code waits for all N jobs of one dispatch to finish, aggregates their N `ActionResult`s, or reports a combined outcome. Each job's outcome is observed only by that job itself (a log line); nothing "closes the loop" on a Vibe-level or Schedule-level dispatch | Confirmed independently by §2.3's finding that the pipeline terminates inside the job, and by `SmartHomeDispatchResult` never being read by the scheduled caller (§5) |

**Not present:** recursive execution, graph/DAG execution, pipeline-object (`Illuminate\Pipeline`) chaining, or a batch/fan-in primitive (`Bus::batch()`) anywhere in this pipeline.

---

## 7. Failure model (Part 7)

The failure model is **best-effort, isolate-and-continue, log-only** — the strongest signal in the whole review is how deliberately every layer converts failure into "logged, then treated as done" rather than any form of retry/compensation/rollback.

| Failure site | Mechanism | Outcome | Evidence |
| --- | --- | --- | --- |
| `processSchedule()` transaction throws (e.g. invalid recurrence config) | Plain PHP exception (`Throwable`), no custom error/Result type | `DB::transaction()` auto-rolls-back; outer `catch (Throwable $e)` in `handle()` increments `$failed`, logs to stdout, calls `notifyScheduleFailure()` (push); **batch continues to next schedule** — this is the one case with a **stop-on-first-error scope of exactly one schedule**, not the batch | `DispatchDueSchedulesCommand.php:84-92` |
| `ScheduleAutomationValidator::validate()` returns false | **Boolean Result-like contract**, not an exception — validator's own docblock: *"Returns false for expected failures — never throws"* | Caller logs a warning and returns — no dispatch, no push (ADR-026: expected skip, not actionable) | `ScheduleAutomationValidator.php` docblock; `DispatchDueSchedulesCommand.php:182-192` |
| `VibeSmartHomeDispatchService::dispatch()` throws (e.g. DB error) | Plain exception, uncaught by the service itself | Caught by `dispatchSmartHomeAfterSchedule()`'s own `try/catch (Throwable $e)` — logged as a warning with `exception_class`; **no push** (this is not a recurrence failure); schedule's recurrence is already committed and unaffected | `DispatchDueSchedulesCommand.php:181-209` |
| `SmartHomeActionJob` — action/device/connection row missing | Null check, not an exception | `Log::warning(...)`, then `return` — job completes successfully (not marked failed) | `SmartHomeActionJob.php:61-91` |
| `SmartHomeActionJob` — unsupported action type | `UnsupportedSmartHomeActionException` (extends `InvalidArgumentException`), thrown by `HomeAssistantAdapter::executeAction()`, caught inside the job's own `try/catch` | `Log::warning(...)` — no push (retrying can't help); job completes successfully | `SmartHomeActionJob.php:120-129` |
| `SmartHomeActionJob` — provider HTTP failure (timeout, 5xx, etc.) | **Not an exception at all** — `HomeAssistantAdapter::executeAction()`'s own contract explicitly promises never to throw for transport/HTTP failures; it returns `ActionResult(success: false, ...)` instead (a de facto Result-object pattern, though not a named `Result`/`Either` class) | Job logs a warning, sends `notifySmartHomeActionFailed` push; job completes successfully — **never lands in `failed_jobs`** | `HomeAssistantAdapter.php` contract docblock; `ProviderAdapter.php` interface docblock |
| `SmartHomeActionJob` — any other unexpected `Throwable` | Catch-all `catch (Throwable $e)` at the bottom of `handle()` | `Log::error(...)`, sends `notifyActionFailed` push, job completes successfully (again, never actually fails the job in Laravel's sense) | `SmartHomeActionJob.php:130-142` |
| Push notification dispatch itself fails | `PushNotificationEvents::send()`'s own `try/catch` | `Log::error(...)`, swallowed — never rethrown to the domain caller | `PushNotificationEvents.php:113-130` |

**No retry, no dead letter, no compensation, no rollback exists for Smart Home action execution.** Explicitly:

- **Retry:** `SmartHomeActionJob->tries = 3` is configured but inert — every failure mode the job can encounter is caught internally and results in a normal (non-throwing) return, so Laravel's queue retry mechanism never actually triggers for this job in practice (independently confirmed by the pre-existing `scheduler-smart-home-e2e.md` finding QA-003).
- **Dead letter:** Because the job never really "fails" in Laravel's terms, it never reaches `failed_jobs` — the `database-uuids` failed-queue driver configured in `config/queue.php` is simply never exercised by this pipeline.
- **Compensation / rollback:** There is no compensating action if some actions in a Vibe's dispatch succeed and others fail (e.g. "turn on light" succeeds, "turn on fan" fails) — partial failure is not just tolerated, it is the *designed* behavior (ADR-023: *"One Smart Home action failure must not block other actions... partial success is acceptable"*).
- **Continue-on-error is the policy at every level**: one action failing doesn't stop other actions in the same dispatch; one schedule failing doesn't stop the batch; the scheduled path's Smart Home dispatch failing doesn't roll back the already-committed `ScheduleExecution`/`next_run_at` advance.
- **The one true "stop" in the whole pipeline** is the DB transaction rollback in `processSchedule()` — and even that only rolls back the *recurrence bookkeeping* for one schedule, never the batch.

---

## 8. Cancellation model (Part 8)

**None of the following are implemented anywhere in the Smart Home execution pipeline:** cancellation, timeout-as-a-domain-concept, abort, interruption, pause/resume, scheduled retry, retry-later.

Specifics, so "not implemented" is not just an assertion:

| Capability | Status | Detail |
| --- | --- | --- |
| **Cancellation** | Not implemented | No code path exists to cancel an already-enqueued `SmartHomeActionJob` (e.g. if the user cancels a Vibe play, or deletes a Schedule after a tick but before the queue drains) once `dispatch()` has returned. Laravel does not offer job cancellation by ID out of the box, and no correlation ID exists to target one anyway (§14) |
| **Timeout** | Infrastructure-level only, not a domain concept | `SmartHomeActionJob->timeout = 30` (Laravel queue worker kills the job process after 30s) and `HomeAssistantAdapter`'s HTTP client timeout (`config('smart_home.providers.home_assistant.timeout', 10)`, default 10s) exist, but neither is a *business* concept — there is no "this automation must complete within X seconds or be considered failed" domain rule, no user-facing timeout behavior |
| **Abort / interruption** | Not implemented | Once a job starts `handle()`, there is no interrupt point — it runs to completion (success, caught failure, or an actual PHP fatal/OOM/timeout kill from the queue worker) |
| **Resume** | Not implemented / not applicable | Because there is no persisted execution state (§5, §11) beyond the queue message itself, there is nothing to "resume" — a killed job either gets Laravel's normal automatic re-attempt (up to `tries=3`, though as noted in §7 this path is rarely exercised) starting from scratch, or is simply lost if it exceeds `tries` while genuinely fatal-erroring |
| **Retry later / scheduled retry** | Not implemented as a domain concept | Laravel's generic queue `tries`/`retry_after` (90s, per `config/queue.php`) is the only retry mechanism present, and as established above it is effectively inert for this job because the job's own exception handling prevents it from ever needing Laravel's retry |

**Consequence for Business Telemetry design:** there is no cancellation/timeout state machine to instrument — any future span for this pipeline will have exactly two possible terminal states worth naming (completed-with-result / completed-with-unhandled-fatal), never a "cancelled" or "timed out" business state, unless a future phase actually implements one of these capabilities first.

---

## 9. Provider boundary (Part 9)

The boundary between Ixora business logic and provider-specific code is a single, clean seam: the `App\SmartHome\Contracts\ProviderAdapter` interface, with exactly one concrete implementation (`HomeAssistantAdapter`) and one resolver (`ProviderAdapterResolver`) in front of it.

| Side | Owns | Boundary artifact |
| --- | --- | --- |
| **Ixora side (ends at)** | `SmartHomeActionJob` calling `$resolver->forProvider($connection->provider)` then `$adapter->executeAction($connection, $device->provider_device_id, $action->action_type, $action->parameters ?? [])` | The call to `ProviderAdapterResolver::forProvider()` and the four primitive/DTO arguments passed into `executeAction()` — `ProviderConnection` (an Eloquent model, the one exception to "primitives only" — see note), a plain `string` device ID, a plain `string` action type, and a plain `array` of parameters |
| **Provider side (begins at)** | `HomeAssistantAdapter::executeAction()` internals: mapping `action_type` → HA service name (`ACTION_SERVICE_MAP`), deriving the HA "domain" from the entity ID (`domainFor()`), building the HTTP payload, calling `Http::withToken(...)->post(...)`, mapping the HTTP response back into `ActionResult` | Everything inside `HomeAssistantAdapter` — no class outside `app/SmartHome/Adapters/` and `app/SmartHome/` DTOs/enums knows anything about Home Assistant's REST shape, its entity-ID convention, or its service-call naming |
| **Contract enforcing the seam** | `App\SmartHome\Contracts\ProviderAdapter` (interface: `listDevices`, `readStatus`, `executeAction`, `testConnection`) | Per ADR-012 (*"decouples vibe-action / device-sync logic from provider specifics... callers depend on this contract, never on a concrete adapter"*) and ADR-027 (*"Providers never know product domains... Adapters receive primitives + DTOs"*) |

**One boundary nuance worth flagging precisely:** `ProviderAdapter::executeAction()` receives the full `ProviderConnection` Eloquent model, not just a decrypted-credential primitive — this is a partial departure from ADR-027's stated ideal (*"Provider reading Eloquent models directly"* is listed as a named anti-pattern) that the codebase itself accepts as pragmatic: the adapter only reads `$connection->decryptedCredentials()` and `$connection->config['base_url']` from it, never queries relations or persists through it. This is not a bug to fix in this discovery phase — it is simply the literal, current shape of the seam, and matters for telemetry because a future "Provider Call" span's attributes must be built from what the adapter *actually* touches on the connection (credential-free identifiers only: `provider`, `provider_connection_id`), never assume the boundary is a pure-primitive call.

**What is explicitly outside this review, per the prompt's instruction not to review provider implementation:** the internals of `HomeAssistantAdapter`'s HTTP mapping, HA's own domain model, and any other provider are not analyzed further than establishing where the seam is.

---

## 10. Candidate future telemetry boundaries (Part 10)

Recommendations only — **nothing below is implemented in this phase.** Each candidate is a boundary that was found to naturally exist in §2–§4, not an invented abstraction. They are listed in pipeline order; §12 covers exactly why each must avoid duplicating an already-instrumented generic boundary.

| Candidate boundary | Where it would sit | Natural because... |
| --- | --- | --- |
| **`SmartHomeDispatch`** (span) | Wraps `VibeSmartHomeDispatchService::dispatch()` | It is the one real convergence point (§3) — both entry points call exactly this method, exactly once, with a clear start/end and a natural outcome (`dispatched`/`skipped` counts already computed into `SmartHomeDispatchResult`, §5) |
| **`ScheduleAutomationValidation`** (span or span event) | Wraps `ScheduleAutomationValidator::validate()` | A discrete, side-effect-free boundary with a boolean outcome (§4, §7) — but must be labeled so its scheduled-path-only nature (§4) is visible, not implied to run for manual dispatch too |
| **`SmartHomeActionExecution`** (span) | Wraps `SmartHomeActionJob::handle()`, specifically the region from adapter resolution through `ActionResult` (i.e. excluding the initial rehydration null-checks, or including them as sub-attributes) | This is the actual unit of business work (§2.3, §6) — one action, one provider call, one outcome. It is the boundary most directly answering "did this device do what the user/schedule asked?" |
| **`ProviderCall`** (span, nested inside `SmartHomeActionExecution`) | Wraps `ProviderAdapter::executeAction()` specifically (not `listDevices`/`readStatus`/`testConnection` — those belong to the sync pipeline, §1.3) | It is the exact provider boundary (§9) — the only place a business span could carry provider-specific attributes (`provider`, `status_code`) without leaking into Ixora-domain code |
| **`ScheduleOccurrenceDispatch`** (span, scheduled path only) | Wraps `dispatchSmartHomeAfterSchedule()` as a whole (validator + service call together) | This is the scheduled-path's own orchestration boundary (§3) — useful if a future need arises to see "how long did it take from a due tick to all N jobs being enqueued" as one number, distinct from the recurrence-transaction time |

**Explicitly not recommended as boundaries**, with reasons:

| Rejected candidate (from the prompt's example list) | Why it does not naturally exist here |
| --- | --- |
| `ResolveVibe` | There is no dedicated resolution step — `$schedule->vibe` is a plain Eloquent relation access with no branching logic worth a span; wrapping it would create a boundary around a getter, not a business decision |
| `ResolveActions` | Same reasoning — `VibeDeviceAction::where(...)->get()` inside `VibeSmartHomeDispatchService::dispatch()` is a single query, already inside the natural `SmartHomeDispatch` boundary above; splitting it out would fragment one cohesive method into two spans for no decision boundary gained |
| `PersistExecution` | **Cannot be recommended — there is nothing to persist.** No execution-outcome write exists anywhere in this pipeline (§5, §11). Recommending this span would imply a persistence step exists today; it does not. (If Phase 7B.4.2 or later *adds* such persistence, a span for it would become legitimate then — not before) |
| `NotificationDispatch` | This is the existing Push Notifications pipeline's own boundary, not a Smart Home boundary — instrumenting it here would duplicate whatever Push-domain telemetry is scoped for a future phase (§12) |

---

## 11. Current observability (Part 11)

| Observability mechanism | Present for Smart Home execution? | Detail |
| --- | --- | --- |
| **Structured logs** | **Yes — the only real observability mechanism today.** Every failure/skip branch in `SmartHomeActionJob`, `VibeSmartHomeDispatchService`'s callers, and `ScheduleAutomationValidator`'s callers logs via `Log::info`/`warning`/`error` with structured context arrays (`vibe_device_action_id`, `vibe_id`, `device_id`, `provider_connection_id`, `provider`, `action_type`, `success`, `status_code`, `error_message`) — never raw exception dumps, never credentials (verified against `SmartHomeActionJobTest`'s dedicated `'never logs the access token or credentials'` test) | `SmartHomeActionJob.php:93-181`, catalogued exhaustively (grep patterns + levels) in `scheduler-smart-home-e2e.md` §6.3 |
| **Domain events (Laravel `Event::dispatch`)** | **No.** Grepped the entire `app/` tree for `Event::dispatch`, `Event::listen`, and any Smart-Home-related `EventServiceProvider` registration — zero matches tied to Smart Home or Scheduler business logic. There is no `SmartHomeActionExecuted`/`VibeDispatched`-style domain event anywhere | §1.4 |
| **Metrics** | **No.** No `Cache::increment`, no custom counter, no StatsD/Prometheus client call anywhere in `app/SmartHome/`, `app/Jobs/SmartHome/`, or the two scheduler commands. (The generic OpenTelemetry Queue/Console/HTTP/Scheduler metrics from Phases 7B.1–7B.3 do fire *around* this code, per §12 — but they carry zero Smart Home-specific labels) | Confirmed by absence in all files read for this review |
| **Exceptions (unhandled, surfaced to an error tracker)** | **Effectively no**, by design (§7) | Every exception this pipeline can produce is caught internally before it would reach a global exception handler / error-tracking integration. The one exception that *does* escape uncaught is a `processSchedule()` transaction failure (§7), which is a Scheduler/recurrence concern, not a Smart Home one |
| **Execution history / audit records** | **Partially — for the Schedule, not for Smart Home** | `ScheduleExecution` is a genuine audit trail for *schedule occurrences* (one row per tick, with `occurrence_key`, `scheduled_for`, `executed_at`, `status`, `log`), but it has zero visibility into what happened to the Smart Home actions that occurrence triggered (§5). There is no equivalent audit trail for the manual dispatch path at all — a `POST .../smart-home/dispatch` call leaves no persisted record beyond its own API log line (if any HTTP-layer telemetry captures the request, per Phase 7B.1) |
| **State transitions** | Only for `Device.status`/`ProviderConnection.status` | Only as a side effect of the *sync* pipeline (§1.3), not the *execution* pipeline — `SmartHomeActionJob` never writes to `Device.status` or `ProviderConnection.status` even when a provider call fails repeatedly. A device could be actively failing every `executeAction()` call while still showing `status = online` from its last successful sync |
| **API response as observability** | Yes, but ephemeral and caller-only | `SmartHomeDispatchResult` (dispatched/skipped counts + action IDs) is returned synchronously to the manual dispatch API caller (mobile client), giving the *user* visibility into "N actions were queued" at click-time, but this is never logged server-side and never available to the scheduled path (§5) |

**Summary:** today's only durable, queryable signal for "did a Smart Home action actually run and succeed" is grep-ing structured log lines by `vibe_device_action_id`/`device_id` across whatever log aggregation exists — there is no dashboard-friendly counter, no per-provider success-rate metric, and no way to answer "how many actions did user X's 7am schedule fire, and did they all succeed?" without log archaeology.

---

## 12. Duplication risks (Part 12)

Business Telemetry for this pipeline sits directly on top of infrastructure that Phases 7B.1–7B.3 already instrument generically. Every risk below names the exact existing signal that a naive Business Telemetry implementation could re-emit.

| Existing infra signal (already shipped) | What it already captures for this pipeline | Duplication risk if Business Telemetry is careless |
| --- | --- | --- |
| **HTTP telemetry** (Phase 7B.1) | The `POST /api/vibes/{vibe}/smart-home/dispatch` and `POST /api/provider-connections/{id}/sync` requests already get a generic HTTP server span + `ixora.http.*` metrics (route, method, status code) via `opentelemetry-auto-laravel`'s Laravel HTTP hooks | A Business "dispatch" span/metric must **not** re-record request duration, route, or status code — that is the HTTP boundary's job. It should only add *business* attributes (vibe_id, dispatched/skipped counts) as attributes on the **existing active span** (via `Tracer::activeSpan()`, the Phase 7B.1 mechanism already built for exactly this purpose) rather than starting a second, competing span for the same HTTP request |
| **Queue telemetry** (Phase 7B.2, `QueueExecutionTelemetry`) | Every `SmartHomeActionJob` dispatch/consume already gets `ixora.queue.job.total`/`.duration` with the job class name as a label — this fires regardless of which entry point enqueued it | A future `SmartHomeActionExecution` span must not re-emit a generic "job ran, took Xms, succeeded/failed" metric — that duplicates `ixora.queue.job.*` exactly. It should add only the business outcome (which provider, which action type, success/failure *reason* at the domain level) as attributes on the queue job's already-active span, not a competing duration metric |
| **Console telemetry** (Phase 7B.2, `ConsoleCommandTelemetry`) | Every `schedules:dispatch-due` and `schedules:dispatch-loop` invocation already gets `ixora.console.command.total`/`.duration` | A Business Telemetry span for "one batch of due-schedule processing" must not re-emit command duration/outcome — it should nest inside the existing command span and add only batch-level business counts (due/dispatched/skipped_duplicate/failed, already computed by `outputSummary()`, §2.2) |
| **Scheduler telemetry** (Phase 7B.3, `SchedulerExecutionTelemetry`) | Explicitly documented as **inert for `back_vibes` today** (Phase 7B.3 §4 — no native `Schedule::` registration exists) — so there is currently zero overlap risk in practice | **This will change** the moment `back_vibes` ever registers a native scheduled event; until then this is a latent risk, not an active one — flagged here so 7B.4.2 does not need to rediscover it |
| **Provider telemetry** (does not exist yet, any provider) | N/A — no OpenTelemetry auto-instrumentation package hooks Laravel's `Http::` client calls with business semantics beyond the generic outbound-HTTP-client span (if the installed auto-instrumentation covers `GuzzleHttp`/`Illuminate\Http\Client` at all — not verified in this review, out of scope per Part 9's "do not review provider implementation") | If a future "Provider Call" business span (§10) is added, it must be checked against whatever outbound-HTTP auto-instrumentation is active at that time, the same way Phase 7B.1 checked inbound HTTP — this review flags the *need* for that check in 7B.4.2, but does not perform it here (out of scope for Part 9) |
| **Push Notification pipeline** (own domain, not yet instrumented by any phase reviewed here) | `PushNotificationEvents` → `PushNotificationService` → `PushNotificationJob` is a fully separate pipeline (own queue, own job class, own failure model) that Smart Home only *calls into* (§2.3) | A Smart Home business span must stop at the `PushNotificationEvents::notifySmartHomeActionFailed()` call boundary — it should not reach into or duplicate whatever Push-domain telemetry a future phase adds for `PushNotificationJob` itself |

**General principle carried over from Phase 7B.3's signal-ownership table (§3 there):** the rule that let Scheduler and Console both legitimately instrument the *same* scheduled command without duplicating each other (different boundaries, not duplicate signals) applies identically here — Business Telemetry should own *only* the business-outcome dimension (which vibe, which action, which provider, success/skip/fail at the domain level) and must never re-derive or re-emit a dimension (duration, HTTP status, queue name, retry count) that an infra-layer signal already owns.

---

## 13. Test coverage review (Part 13)

No tests were added or modified to produce this review. The table below reflects what already exists.

| Area | Coverage | Evidence |
| --- | --- | --- |
| **`VibeSmartHomeDispatchService`** (dispatch logic — sort order, skip-on-missing-device, result counts) | **Covered** via `VibeSmartHomeDispatchApiTest` (9 tests) exercising it through the controller — no dedicated unit test file for the service in isolation, but behavior is exercised end-to-end (auth, dispatch counts, sort order, empty-vibe case, no-inline-HTTP assertion) | `tests/Feature/SmartHome/VibeSmartHomeDispatchApiTest.php` |
| **`VibeSmartHomeDispatchController`** (auth, response shape) | **Covered** — 401/403/owner-success/response-shape cases | Same file |
| **`ScheduleAutomationValidator`** (ownership chain: schedule↔vibe↔device↔connection) | **Covered** — 9 unit tests covering every false-branch (missing vibe, foreign vibe, missing device, foreign device, missing connection, foreign connection) and the true-branch (multiple valid actions, zero actions, fully valid) | `tests/Unit/SmartHome/ScheduleAutomationValidatorTest.php` |
| **`SmartHomeActionJob`** (rehydration, adapter call, success/failure logging, push notification triggers, credential redaction, single-provider-call guarantee) | **Covered, thoroughly** — 18 tests including queue/timeout/tries config, missing-action/device/connection, unsupported action, provider-connection failure, unexpected resolver error, credential-never-logged, and single-adapter-call assertion | `tests/Feature/SmartHome/SmartHomeActionJobTest.php` |
| **`HomeAssistantAdapter`** (provider translation layer) | **Covered, thoroughly** — 24 tests across `listDevices`/`readStatus`/`executeAction`/`testConnection`, including HTTP failure/timeout/4xx/5xx branches and credential-never-logged | `tests/Unit/SmartHome/HomeAssistantAdapterTest.php` |
| **`ProviderAdapterResolver`** | **Covered** (not read in full for this review, but present) | `tests/Unit/SmartHome/ProviderAdapterResolverTest.php` |
| **`ProviderDeviceSyncService`** (adjacent sync pipeline, §1.3) | **Covered, thoroughly** — 19 tests including upsert/dedup/absent-device-offline/unreachable-provider/notification | `tests/Feature/SmartHome/ProviderConnectionSyncApiTest.php` |
| **Scheduler → Smart Home integration boundary** (`DispatchDueSchedulesCommand` calling the validator + dispatch service) | **Covered at the boundary** — `Bus::assertDispatchedTimes(SmartHomeActionJob::class, N)` / `assertNotDispatched(...)` assertions for: normal dispatch, skipped-duplicate (no dispatch), dry-run (no dispatch), validator failure (no dispatch), dispatch-service exception (logged, isolated), one schedule's SH failure not blocking a second schedule's dispatch | `tests/Feature/Scheduling/DispatchDueSchedulesCommandTest.php` (lines 636-731 specifically) |
| **Full end-to-end chain in one test** (schedule tick → validator → dispatch → job execution → provider HTTP call, all in one assertion) | **Not covered — and not expected to be, given `Bus::fake()` conventions.** Every test above stops at a boundary: the command-level tests fake the bus and assert *dispatch*, never *execution*; the job-level tests execute `SmartHomeActionJob::handle()` directly/via `Bus::dispatchSync()`-style calls with a faked HTTP client, never triggered by an actual due schedule. This is a deliberate and conventional test-isolation choice (not a coverage gap in the traditional sense), but it does mean **no single test proves the full chain wired together** — confidence that "schedule fires → HA gets called" is *composed* from separately-verified boundary contracts, not observed directly in one run | Cross-checked against `scheduler-smart-home-e2e.md` §9.3, which independently reaches the same conclusion — SC-HP-1's own assertion table (§2, "Happy-path validation") marks steps 6-7 ("Queue drain… HA state") as `✅ (mock)` / `⏸ HA` respectively, i.e. even the project's own QA phase documents this as a mocked, not live, end-to-end proof |
| **`delay_seconds` runtime effect** | **Not covered, because there is nothing to cover** | No test exercises `delay_seconds` producing an actual delay, consistent with the code-level finding (§5) that the field has no runtime effect |
| **Manual-path vs. scheduled-path `SmartHomeActionJob` equivalence** (i.e. "the job behaves identically regardless of which entry point enqueued it") | **Implicitly covered, not explicitly asserted** | Both entry points call the same `SmartHomeActionJob::dispatch($action->id)` with only an integer ID (§2.1, §2.2), and `SmartHomeActionJobTest` tests the job in isolation — the equivalence is a structural guarantee of the code (the job cannot know its caller) rather than something a test specifically proves. No test asserts "manual dispatch and scheduled dispatch produce byte-identical job payloads," but the shared code path makes this true by construction |

**Overall verdict:** unit/boundary coverage is strong and deliberate (every layer in ADR-027's model has its own test file); true end-to-end integration coverage is intentionally absent by test-isolation convention, and the project's own QA documentation already flags the live-provider portion as pending hardware/environment (Android device, live HA instance) rather than a backend gap.

---

## 14. Unknowns, open questions, and risks for telemetry design

These are architectural facts discovered during this review that any Business Telemetry implementation (7B.4.2+) must resolve or explicitly accept before adding spans/metrics/logs — none of them are bugs to fix now, and none were touched by this phase.

| # | Finding | Why it matters for telemetry |
| --- | --- | --- |
| **U-1** | **No correlation identifier connects a trigger to its resulting jobs.** `SmartHomeActionJob` is constructed with only `int $vibeDeviceActionId` (§2.3) — it has no `schedule_id`, no `occurrence_key`, no request ID, nothing identifying *why* it was dispatched. This is not an oversight — it is explicitly documented in the codebase itself: `SmartHomeActionFailedNotification`'s docblock (ADR-024) states *"schedule_id is intentionally absent... Propagating schedule_id would require threading it through VibeSmartHomeDispatchService → SmartHomeActionJob, changing the Smart Home runtime — outside the boundary of [that] Phase. Deferred."* | Without a correlation ID, a distributed trace cannot link a "schedule tick" span to the N "action execution" spans it caused, once they cross the queue boundary (§2.3) unless OpenTelemetry's own trace-context propagation across `dispatch()`/queue payload is relied upon instead of a business ID. Any span design must decide: rely on OTel trace-context propagation through the queue payload (if the underlying queue instrumentation supports it), or accept that manual vs. scheduled dispatch are indistinguishable from inside the job today, or introduce a business correlation ID (**which would be a code change, out of scope for 7B.4.1**) |
| **U-2** | **Manual dispatch cannot be distinguished from scheduled dispatch inside `SmartHomeActionJob`.** Following directly from U-1 — the job has no field indicating trigger source | Any metric label like `trigger_source` (manual/scheduled) cannot be derived *inside the job* without a code change. It could only be derived at the two *enqueue* boundaries (§2.1, §2.2) — meaning such a label would need to be attached at dispatch time (e.g. via queue job tagging, if the underlying queue telemetry surfaces job tags) rather than being read from the job's own state |
| **U-3** | **`delay_seconds` has no runtime effect.** Confirmed by grep (§5) — persisted, validated, and returned by the API, but never read by `VibeSmartHomeDispatchService` or `SmartHomeActionJob` | If a future telemetry design assumes actions execute with their configured delay (e.g. to explain gaps between action timestamps), that assumption would be **false** against current code. Either telemetry must not imply per-action delay, or this discrepancy should be raised as a product question (out of scope for this document to resolve) |
| **U-4** | **No persisted execution outcome for Smart Home actions.** Only `ScheduleExecution` (schedule-level) is persisted; nothing records per-action success/failure beyond a log line (§5, §11) | This is likely the single most valuable thing Business Telemetry can add — but it means there is currently no existing table/column to correlate a future span/metric against for historical backfill or reconciliation. A "did this action run" dashboard would, for the first time, be *the* durable source of that answer, not a supplement to one |
| **U-5** | **Partial failure within one Vibe dispatch is invisible in aggregate.** Because there is no fan-in step (§6) and no persisted per-dispatch summary in the scheduled path (`SmartHomeDispatchResult` is discarded, §5), there is no way today — logs or otherwise — to answer "did *all* of this vibe's actions succeed, or just some?" without manually correlating N separate log lines by `vibe_id` and a timestamp window | A future "dispatch-level" metric/span (`SmartHomeDispatch`, §10) would need to either wait synchronously for job outcomes (a design change) or accept that it can only ever report *enqueue* counts, not *execution* outcomes, at the dispatch boundary — execution outcomes will only ever be observable at the per-job boundary unless a fan-in mechanism is added later |
| **U-6** | **`Device`/`ProviderConnection` status is not updated by action-execution failures.** Only the sync pipeline (§1.3) mutates `status` (§5) — a device can be actively failing every command while its stored status still reads `online`/`connected` | A telemetry consumer reading `Device.status` or `ProviderConnection.status` as a health signal would be looking at **stale, sync-pipeline-only data**, not live execution health. Any future "device health" business metric must be sourced from action-execution outcomes directly, not from these columns |
| **U-7** | **Queue execution concurrency/ordering is not a domain guarantee.** (§6) `sort_order` is an enqueue-order guarantee only | A future span/trace that assumes "action N always completes before action N+1 starts" would be asserting something the architecture does not promise. Telemetry must represent each action's execution independently, without implying a sequence guarantee across jobs |
| **U-8** | **The provider boundary passes a full Eloquent model, not a pure primitive/DTO.** (§9) `ProviderAdapter::executeAction()` receives `ProviderConnection` itself | A future `ProviderCall` span's attribute-building code must be written against exactly what `HomeAssistantAdapter` reads off that model today (`provider`, `config['base_url']`, decrypted credentials — never logged) — it cannot assume a clean DTO-only boundary without checking the concrete adapter first, especially if a second provider adapter is added later with different field access patterns |
| **U-9** | **Scheduler telemetry (Phase 7B.3) is currently inert for this pipeline** — confirmed dormant, not absent, per §12 | This is a time-bomb, not a current risk: the moment `back_vibes` adopts native `Schedule::` registrations (Level 2 of the Scheduler roadmap, explicitly deferred per Phase 7B.3 §1), the "no overlap" assumption in §12 becomes false and must be re-checked |

---

## 15. Recommendations for Phase 7B.4.2

1. **Start with `SmartHomeActionExecution` and `ProviderCall` (§10), not the dispatch-level boundaries.** They are the least structurally ambiguous (single job, single provider call, well-tested in isolation, §13) and deliver the highest-value gap (U-4: no persisted/observable per-action outcome today) with the fewest open questions from §14.
2. **Resolve U-1/U-2 (correlation) as a design decision before writing any span code**, not as an implementation detail discovered mid-phase — decide explicitly whether Business Telemetry will (a) rely on OTel trace-context propagation through the queue payload, (b) accept manual/scheduled indistinguishability as a known limitation, or (c) require a small, explicitly-scoped code change to thread a trigger-source/correlation field through `VibeSmartHomeDispatchService` → `SmartHomeActionJob`. Option (c) would itself need its own ADR-style review given ADR-024 already declined this once for a different reason (notification payload scope, not telemetry) — it is not automatically transferable reasoning.
3. **Treat `SmartHomeDispatch` (dispatch-level span, §10) as lower priority and explicitly scoped to "enqueue outcome only."** Do not let it imply an execution-outcome guarantee it cannot deliver (U-5) unless a fan-in mechanism is designed first.
4. **Write the duplication check for outbound provider HTTP instrumentation (§12's flagged gap) before adding a `ProviderCall` span** — determine whether the installed OpenTelemetry auto-instrumentation already wraps Laravel's `Http::` client / Guzzle calls, the same way Phase 7B.1 had to determine this for inbound HTTP. This was explicitly out of scope for Part 9 of this review and must be the first technical task of 7B.4.2, not assumed.
5. **Do not instrument `ProviderDeviceSyncService`/`ProviderConnectionController::sync` under the same "Smart Home execution" umbrella** (§1.3) — if device sync observability is wanted, scope it as an explicitly separate, smaller follow-up (it has its own boundary, its own failure model, and is not a Vibe execution).
6. **Decide, and document as an ADR if it affects product/observability posture, whether the U-6 staleness gap (device status not reflecting execution health) should be closed by telemetry alone (dashboards derived from action-execution spans) or by an application-level change (updating `Device.status` on repeated execution failure)** — this review found the gap but takes no position on which layer should close it, since an application-level fix would be out of scope for a telemetry phase.
7. **Reuse the exact signal-ownership table format from Phase 7B.3 §3** when 7B.4.2 defines its own — this review's §12 duplication table is written to make that transcription mechanical.
8. **Keep the same "fail open" telemetry policy established in Phases 7A–7B.3** (any telemetry call failing must never affect a Smart Home action outcome) — this is especially important here because the domain's own failure policy (§7) is already "log and continue no matter what"; telemetry code must not become the one thing that breaks that guarantee.

---

## Related documents

| Document | Relationship |
| --- | --- |
| [backend-generic-scheduler-instrumentation.md](../mvp/backend-generic-scheduler-instrumentation.md) | Phase 7B.3 — Level 1 Scheduler telemetry; this document is its Level 2/business counterpart |
| [backend-queue-console-instrumentation.md](../mvp/backend-queue-console-instrumentation.md) | Phase 7B.2 — generic Queue/Console telemetry this pipeline runs on top of (§12) |
| [backend-http-routing-instrumentation.md](../mvp/backend-http-routing-instrumentation.md) | Phase 7B.1 — generic HTTP telemetry for the manual dispatch entry point (§1.1, §12) |
| [ADR-022](../../../decisions/ADR-022-scheduler-smart-home-automation-model.md) | Composition model — why there is no `automations` table/engine (§5) |
| [ADR-023](../../../decisions/ADR-023-automation-execution-order-and-failure-policy.md) | Execution order + failure isolation — authoritative source for §6/§7 |
| [ADR-024](../../../decisions/ADR-024-automation-notifications-and-observability.md) | Notification event taxonomy; source of the U-1 `schedule_id` deferral finding |
| [ADR-026](../../../decisions/ADR-026-automation-execution-security.md) | Execution security — authoritative source for §4's validator/policy asymmetry |
| [ADR-027](../../../decisions/ADR-027-asynchronous-orchestration-pattern.md) | Asynchronous orchestration layering — authoritative source for §3 |
| [dispatch-integration-review.md](../../scheduler-smart-home-automations/mvp/dispatch-integration-review.md) | Pre-implementation review of the same pipeline, focused on correctness/idempotency rather than telemetry |
| [scheduler-smart-home-e2e.md](../../../qa/scheduler-smart-home-e2e.md) | End-to-end QA reference independently confirming §2, §7, §13's findings (QA-001/002/003) |

---

*This document is a discovery artifact for Phase 7B.4.1. It introduces no telemetry, no behavior change, and no refactor. Phase 7B.4.2 should treat §14 and §15 as its starting brief.*

