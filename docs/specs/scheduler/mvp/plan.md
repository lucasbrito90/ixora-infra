# Scheduler MVP — implementation plan

**Status:** Active implementation plan (pre-implementation)  
**Spec:** [`spec.md`](spec.md)  
**Feature ID:** `scheduler/mvp`

---

## Implementation summary

The Scheduler MVP delivers **time-based vibe reminders** with **backend-authoritative** schedule state, a **minute-granularity dispatcher** on DigitalOcean, **Android local notifications**, and a **read-only SQLite mirror** for offline viewing. It **does not** ship FCM wake-to-play, Smart Home actions, iOS scheduling, offline schedule editing, or guaranteed background auto-play.

**Strategy anchors:**

| Principle | Implementation |
| --- | --- |
| Backend = source of truth | CRUD API, **`RecurrenceService`**, **`next_run_at`**, execution audit |
| Mobile SQLite = offline read-only mirror | Upsert on sync; no offline mutation queue |
| Offline cannot create/edit/delete | UI + service guards when `!navigator.onLine` |
| Timezone per schedule | IANA column; UTC instants in DB |
| Local notifications first | Android **`@capacitor/local-notifications`** (or equivalent) |
| DO Scheduler worker dispatches | `schedules:dispatch-loop` → `schedules:dispatch-due` every ~60 s |
| Queue + FCM | **Future phase** — document boundary only |
| Smart Home | **Out of MVP** |

**Git Flow:** All work on **`feature/*`** branches from **`develop`** — [`git-flow.md`](../../../standards/git-flow.md). Promote to **`staging`** for homologation via merge **`develop` → `staging`**.

---

## First implementation — `RecurrenceService` (Phase 2)

**The first Scheduler MVP code deliverable is `RecurrenceService` — nothing else.**

Phase 2 starts implementation. All prior phases are documentation-only (Phase 1 complete).

| In scope (Phase 2) | Out of scope (Phase 2) |
| --- | --- |
| **`computeNextRunAt()`** | Migrations |
| **`computeOccurrenceKey()`** | Controllers, Form Requests, Resources, Policies |
| Pest unit tests (TDD) | Eloquent models, database, factories |
| Pure PHP — **`CarbonImmutable`**, DTOs / typed arrays | OpenTofu, mobile, local notifications |

**Decoupling rule:** The service must be **testable without Laravel Database** — no `Schedule` Eloquent model in unit tests; pass a **schedule input DTO** or typed array shaped like the future row.

**Rationale:** Recurrence behaviour is the heart of the Scheduler. Define rules through **TDD before freezing schema** (Phase 3).

**Branch:** `feature/scheduler-recurrence-service`

---

## Current state

| Area | State |
| --- | --- |
| **Schema stubs** | `schedules`, `schedule_executions` migrations + Eloquent models exist — **no API, no runtime** |
| **`recurrence_type` stub** | Comment allows `none`, `daily`, `weekly`, `custom` — **MVP narrows to `once`, `daily`, `weekdays`, `weekly`**; **`monthly` reserved** (enum slot, not MVP) |
| **`timezone` / `next_run_at`** | **Missing** — Phase 3 schema hardening |
| **`occurrence_key` on executions** | **Missing** — Phase 3 schema hardening |
| **`RecurrenceService`** | **Not started** — **Phase 2 first code deliverable** |
| **Schedule API** | **None** |
| **Dispatcher command** | **None** |
| **Scheduler worker** | **Not in OpenTofu** — [`staging-digitalocean.md`](../../../architecture/backend/staging-digitalocean.md) documents `api` + `queue` only |
| **Mobile schedule UI** | **None** |
| **SQLite schedule mirror** | **None** |
| **Local notifications for schedules** | **None** |
| **Planning doc** | [`scheduling-model.md`](../../../architecture/backend/scheduling-model.md) marked planning-only — **this MVP supersedes for delivery scope** |
| **Scheduler ADRs** | **Accepted** — [ADR-009](../../../decisions/ADR-009-scheduler-timezone-utc-storage.md), [ADR-010](../../../decisions/ADR-010-scheduler-idempotency-occurrence-key.md), [ADR-011](../../../decisions/ADR-011-scheduler-local-notifications-vs-future-fcm.md) |

---

## Phase overview

```
Phase 1 ──► Spec + ADRs
Phase 2 ──► TDD RecurrenceService (pure PHP, DST matrix) — FIRST CODE
Phase 3 ──► Schema hardening (timezone, next_run_at, occurrence_key, updated_at)
Phase 4 ──► Backend Schedule CRUD API + SchedulePolicy + Pest
Phase 5 ──► Artisan schedules:dispatch-due
Phase 6 ──► OpenTofu Laravel Scheduler Worker (staging — `scheduler` worker + `schedules:dispatch-loop`)
Phase 7 ──► Mobile Schedule CRUD (online, Android)
Phase 8 ──► SQLite mirror (read-only offline)
Phase 9 ──► Local notifications (Android)
Phase 10 ─► Execution log sync (list + optional mobile ack)
```

Phases **4–6** can overlap after Phases **2 + 3** land; **7–9** depend on API contract; **10** depends on dispatcher producing stable **`occurrence_key`**.

---

## Phase 1 — Spec + ADRs

### Deliverables

| Item | Output |
| --- | --- |
| Feature spec | [`spec.md`](spec.md) (this folder) |
| Implementation plan | [`plan.md`](plan.md) |
| Task checklist | [`tasks.md`](tasks.md) |
| **ADR-009** | [`ADR-009-scheduler-timezone-utc-storage.md`](../../../decisions/ADR-009-scheduler-timezone-utc-storage.md) — timezone + UTC storage, DST, recurrence |
| **ADR-010** | [`ADR-010-scheduler-idempotency-occurrence-key.md`](../../../decisions/ADR-010-scheduler-idempotency-occurrence-key.md) — **`occurrence_key`**, transactional dispatcher |
| **ADR-011** | [`ADR-011-scheduler-local-notifications-vs-future-fcm.md`](../../../decisions/ADR-011-scheduler-local-notifications-vs-future-fcm.md) — local notifications vs future FCM |

### Decisions locked in ADRs

| Topic | Decision (see ADR) |
| --- | --- |
| **`once` post-fire** | **`next_run_at = null`** and **`is_enabled = false`** — [ADR-009](../../../decisions/ADR-009-scheduler-timezone-utc-storage.md) |
| **DST spring forward** | Skip nonexistent local time — [ADR-009](../../../decisions/ADR-009-scheduler-timezone-utc-storage.md) |
| **DST fall back** | First (earlier) occurrence wins — [ADR-009](../../../decisions/ADR-009-scheduler-timezone-utc-storage.md) |
| **Idempotency** | **`occurrence_key`** + unique `(schedule_id, occurrence_key)` — [ADR-010](../../../decisions/ADR-010-scheduler-idempotency-occurrence-key.md) |
| **Reminders** | Android local notifications only; no FCM in MVP — [ADR-011](../../../decisions/ADR-011-scheduler-local-notifications-vs-future-fcm.md) |
| **Auto-play** | Not guaranteed — user action required — [ADR-011](../../../decisions/ADR-011-scheduler-local-notifications-vs-future-fcm.md) |

### Open items (not ADR-blockers)

- **Weekly notification horizon:** single **`next_run_at`** alarm vs pre-schedule N occurrences on device
- **Dispatcher batch size** and optional cache lock key

### Cross-links

- Supersedes planning-only constraints in [`scheduling-model.md`](../../../architecture/backend/scheduling-model.md) for MVP
- Playback unchanged — [`execution-plan/spec.md`](../../vibes/execution-plan/spec.md)

---

## Phase 2 — TDD RecurrenceService

**First Scheduler MVP implementation.** No migrations, no HTTP layer, no mobile.

### Mandatory TDD workflow

Every behaviour in this phase **must** follow this order:

1. **Write tests first** (Pest unit tests describing expected **`computeNextRunAt`** / **`computeOccurrenceKey`** outcomes)
2. **Run tests — expect failure** (red)
3. **Implement minimum code** to pass (green)
4. **Refactor** while keeping tests green
5. **Run full test suite** (`php artisan test` or targeted filter + regression)

Do **not** write production service code before its failing test exists.

### Service contract (pure, database-agnostic)

**Class:** `App\Services\Scheduling\RecurrenceService` (path TBD)

| Method | Purpose |
| --- | --- |
| **`computeNextRunAt(ScheduleInput $input, ?CarbonImmutable $afterUtc = null)`** | Next occurrence strictly after reference instant |
| **`computeOccurrenceKey(int $scheduleId, CarbonImmutable $scheduledForUtc)`** | Stable idempotency key |

**Input shape:** DTO or typed array — **`timezone`**, **`start_time`**, **`recurrence_type`**, **`recurrence_config`**, **`is_enabled`** — **not** Eloquent.

**Out of scope for Phase 2:**

- **`monthly`** — enum reserved; **no tests, no logic**
- **`expandNextNOccurrences(...)`** — optional helper; defer unless needed for mobile parity fixtures

### Test matrix (minimum — MVP types only)

| Case | Types |
| --- | --- |
| **`once`** | Before anchor, at anchor, after fired |
| **`daily`** | Normal day, DST spring forward, DST fall back |
| **`weekdays`** | Fri → Mon skip; holiday-agnostic (calendar weekdays only) |
| **`weekly`** | Single day, multi-day, week boundary |
| **Timezone** | `America/Sao_Paulo`, `UTC`, `Europe/London` |
| **`computeOccurrenceKey`** | Stable key for same `(schedule_id, scheduled_for)` |

**Explicitly excluded from Phase 2 tests:** **`monthly`** recurrence calculations.

### Dependencies

- PHP **`CarbonImmutable`** + IANA **`DateTimeZone`**
- **No** `RefreshDatabase`, **no** factories, **no** migrations in unit tests

### Verify

```bash
cd back_vibes && php artisan test --filter=RecurrenceService
```

---

## Phase 3 — Schema hardening

**Runs after Phase 2** — migration shape informed by tested recurrence behaviour.

### Migration goals

**`schedules`:**

- Add **`timezone`** (string, not null)
- Add **`next_run_at`** (timestamp nullable, indexed)
- Add **`last_run_at`** (timestamp nullable)
- Add **`updated_at`**
- Migrate **`recurrence_type`**: `none` → **`once`** where present in seed/dev data
- Document enum constraint at application layer — include **`monthly`** as **reserved/rejected** until future spec

**`schedule_executions`:**

- Add **`occurrence_key`** (string, not null)
- Add **`scheduled_for`** (timestamp UTC, not null)
- Rename/clarify **`executed_at`** semantics (dispatcher run time)
- Expand **`status`** vocabulary — MVP default **`dispatched`**
- Unique index **`(schedule_id, occurrence_key)`**

### Backend touchpoints

- Update **`Schedule`** / **`ScheduleExecution`** models, casts, fillable
- Introduce **`RecurrenceType`** enum/constant — MVP values + **`monthly`** reserved
- Factory stubs for Pest (Phase 4)

### Out of scope

- **`devices`**, **`vibe_device_actions`** schema changes
- **`monthly`** recurrence logic

**Branch:** `feature/scheduler-schema-hardening`

---

## Phase 4 — Backend Schedule CRUD API

### Endpoints

Per [`spec.md`](spec.md) — `/api/schedules` REST + **`ScheduleResource`**

### Laravel conventions

Follow [`back-vibes-api-rules`](../../../../.cursor/rules/back-vibes-api-rules.mdc):

- **`StoreScheduleRequest` / `UpdateScheduleRequest`**
- **`ScheduleController`** — authorize, delegate recurrence recompute, return Resource
- **`SchedulePolicy`** — owner scoping
- **`user_id`** from **`auth()->id()`**; validate **`vibe_id`** ownership

### Side effects on write

- On create/update: invoke **`RecurrenceService`** → persist **`next_run_at`**
- On delete: cascade executions (FK); mobile purges on sync

### Tests (Pest feature)

- CRUD happy paths
- 403 cross-user
- 422 invalid timezone / recurrence / weekly config
- Vibe not owned → 422
- **`next_run_at`** present on create response

### Explicitly not in Phase 4

- FCM
- Queue jobs
- Admin routes

---

## Phase 5 — Dispatcher command

### Command

```bash
php artisan schedules:dispatch-due [--batch=100] [--dry-run]
```

### Algorithm

1. **`$now = now('UTC')`**
2. Select due schedules (**`is_enabled`**, **`next_run_at <= $now`**, limit batch)
3. For each schedule in transaction:
   - **`scheduled_for = next_run_at`**
   - **`occurrence_key = RecurrenceService::computeOccurrenceKey(...)`**
   - Insert **`schedule_executions`** — on unique violation, skip advance (idempotent)
   - Set **`last_run_at = scheduled_for`**
   - **`next_run_at = RecurrenceService::computeNextRunAt(...)`** (null for exhausted **`once`**)
   - Optionally disable **`once`** schedule (ADR)
4. Log summary counts

### Failure handling

- Row-level failure must not abort entire batch (try/catch per schedule)
- Failed row → **`schedule_executions.status = failed`** + **`log`** (optional MVP)

### Tests

- Pest feature/integration with frozen clock
- Double invocation does not duplicate executions or skip recurrence advance incorrectly

### Not in MVP

- Dispatching FCM
- Invoking **`vibe_device_actions`**

---

## Phase 6 — OpenTofu Laravel Scheduler Worker

> **Strategy changed from Phase 7 (previous):** The initial approach used a DO App Platform Scheduled Job (`scheduler-dispatch`). This was replaced because:
> - The `digitalocean/digitalocean` provider v2.87.0 does not support `SCHEDULED` kind / `cron_expression` ([issue #1529](https://github.com/digitalocean/terraform-provider-digitalocean/issues/1529)).
> - DO App Platform enforces a ≥15-minute minimum cadence for scheduled jobs, incompatible with the MVP's ~60-second requirement.
> - An App Platform `worker` running a PHP loop is fully supported by the current provider and achieves the desired cadence.

### Infra change

Extend [`ixora-infra/opentofu/staging/`](../../../../opentofu/staging/) App spec with a `worker` block:

| Component | Config |
| --- | --- |
| **Type** | `worker` (App Platform long-running process) |
| **Name** | `scheduler` |
| **Image** | Same as `api` / `queue` |
| **Run command** | `php artisan schedules:dispatch-loop` |
| **Cadence** | ~60 s (internal loop; no cron required) |
| **Env** | `local.api_worker_runtime_env` — same RUN_TIME env as API / queue |

### Backend change

New Artisan command `schedules:dispatch-loop` (`app/Console/Commands/DispatchSchedulesLoopCommand.php`):

- Runs indefinitely; SIGTERM sets `$shouldStop = true` → clean exit after current tick
- Every `--interval=60` seconds: calls `schedules:dispatch-due` via `callSilently`
- Options: `--interval=60`, `--once` (single tick), `--max-iterations=N` (tests)

### Documentation

- Update [`staging-digitalocean.md`](../../../architecture/backend/staging-digitalocean.md) — replace Scheduled Job section with Scheduler Worker section
- Update this plan, spec.md, tasks.md, and ADR-011 references

### Validation

- `php artisan test --filter=DispatchSchedulesLoopCommandTest` — 14 tests pass
- `tofu fmt -recursive && tofu validate` pass
- Staging: create test schedule with **`next_run_at`** in past → wait ≤60 s → execution row appears in `schedule_executions`

---

## Phase 7 — Mobile Schedule CRUD (online)

### Scope

- **Android native build** first
- Screens: list, create/edit form, delete confirm
- Fields: name, vibe picker (user vibes), timezone selector, date/time, recurrence, weekly day picker
- **`schedule.service.ts`** → REST with Firebase Bearer

### UX rules

- **Block mutations offline** — toast explaining online-only
- Default timezone: device IANA as **suggestion** on create; stored value is user-editable schedule timezone
- Link to vibe detail / player from schedule row

### Routing

- Add routes per [`front-vibes-ionic-routing.md`](../../../standards/front-vibes-ionic-routing.md)

### Out of MVP

- iOS QA sign-off
- Admin panel

---

## Phase 8 — SQLite mirror

### Purpose

Offline **read-only** copy of server schedules for list/detail UI and notification payload source.

### Design

| Topic | Decision |
| --- | --- |
| Store | Capacitor SQLite plugin or existing local DB pattern (TBD — align with app conventions) |
| Table | Mirror API resource columns + **`synced_at`** |
| Write path | **API success** and **pull sync** only |
| Read path | Schedule list when offline |
| Delete | Remove row when API delete succeeds or sync diff absent |

### Sync

- **`pullSchedules()`** → replace/upsert by `id`
- Compare **`updated_at`** — server wins

### Hard rule

**No INSERT/UPDATE/DELETE** to SQLite from offline UI code paths.

---

## Phase 9 — Local notifications (Android)

### Integration

- Capacitor Local Notifications plugin
- **`schedule-notification.service.ts`**: cancel + register from SQLite mirror

### Behaviour

- After sync: for each enabled schedule, schedule notification at **`next_run_at`** (and optionally pre-compute weekly/daily chain per ADR)
- Tap action: deep link to **`VibePlayerPage`** with **`vibe_id`**
- **No auto `playVibe`** on cold start without user action (hard boundary)

### Permissions

- Request **`POST_NOTIFICATIONS`** on Android 13+
- Degraded mode: schedules work online without reminders

### Parity

- Share recurrence fixtures with **`RecurrenceService`** tests — mobile TS helper or API-provided **`next_run_at`** only (prefer backend **`next_run_at`** as source for first alarm)

### Offline download interaction

- Notification may fire when vibe not offline-ready — player handles missing snapshot per [`offline-download/spec.md`](../../vibes/offline-download/spec.md)

---

## Phase 10 — Execution log sync

### Backend

- **`GET /api/schedules/{id}/executions`** — paginated audit for owner
- Optional **`POST .../ack`** — mobile reports user opened from notification / played / dismissed

### Mobile

- Optional sync on app open: fetch recent executions for diagnostics UI
- POST ack when user taps notification (best-effort, online)

### Status evolution

| Status | Meaning (MVP → future) |
| --- | --- |
| **`dispatched`** | Backend tick recorded |
| **`acknowledged`** | Mobile reported handling (Phase 10+) |
| **`failed`** | Dispatcher or mobile error |

**Boundary:** **`dispatched`** ≠ audible playback.

---

## Backend plan summary

| Keep / build | Detail |
| --- | --- |
| Authoritative CRUD | Form Requests, Policies, Resources |
| **`RecurrenceService`** | Single source for **`next_run_at`** |
| Idempotent dispatcher | Unique **`occurrence_key`** |
| No FCM | MVP |
| No device actions | MVP |

---

## Mobile plan summary

| Keep / build | Detail |
| --- | --- |
| Online CRUD | API only |
| SQLite mirror | Read-only offline |
| Local notifications | Android MVP |
| Playback | Reuse **`playVibe`** — [`execution-plan/spec.md`](../../vibes/execution-plan/spec.md) |
| iOS scheduling | **Deferred** |

---

## Infra / CDN impact

| Topic | Impact |
| --- | --- |
| Spaces / CDN | **None** — schedules are metadata only |
| PostgreSQL | New indexes + columns; execution growth (audit) |
| App Platform | **+1 `worker`** component (`scheduler`) |
| Queue worker | **Unchanged** for MVP dispatch |
| Secrets | No new secrets for dispatcher |

---

## Validation plan

### Phase 2 (TDD RecurrenceService)

```bash
cd back_vibes && php artisan test --filter=RecurrenceService
```

### Phase 3–5

```bash
cd back_vibes && php artisan test --filter=Schedule
```

### Phase 6 (staging)

- OpenTofu apply staging
- Confirm `scheduler` worker is running in DO App Platform dashboard (Runtime Logs show `[schedules:dispatch-loop] tick #N` approximately every 60 seconds)
- Seed schedule with past **`next_run_at`** → wait ≤60 seconds → execution row appears

### Phase 7–9 (Android installable build — **not live reload**)

1. Online: create daily schedule → notification fires at due time
2. Offline: open schedule list (mirror) — no edit buttons
3. Airplane mode at due time: notification may still fire if pre-scheduled
4. Tap notification → player opens; manual Play works if offline snapshot exists
5. Kill app from recents before due time → **no guarantee** of play (documented)

### Auth

- All API calls use Firebase Bearer — manual test with expired token → **401**

---

## Rollout plan

| Step | Action |
| --- | --- |
| 1 | Merge phases via **`feature/scheduler-*`** → **`develop`** ([`git-flow.md`](../../../standards/git-flow.md)) |
| 2 | Backend phases **2–3** (RecurrenceService + schema) → promote **`develop` → `staging`** on `back_vibes` when ready |
| 3 | Run Pest + OpenTofu plan/apply on staging |
| 4 | Mobile phases 7–9 → **`front_vibes`** staging build (`build:staging`) |
| 5 | QA on Android installable against staging API |
| 6 | Phase 10 ack sync can follow initial MVP release if needed |

**iOS:** separate release spec after MVP Android sign-off.

---

## Open questions

| # | Question | Default / note |
| --- | --- | --- |
| 1 | **`once` after fire:** auto **`is_enabled = false`**? | **Locked yes** — [ADR-009](../../../decisions/ADR-009-scheduler-timezone-utc-storage.md) |
| 2 | **DST gap/overlap** local times | **Locked** — skip spring gap; first wins on fall back — [ADR-009](../../../decisions/ADR-009-scheduler-timezone-utc-storage.md) |
| 3 | **Mobile pre-schedule horizon** for recurring types | Start with **single `next_run_at` alarm** + reschedule on fire/sync — simpler |
| 4 | **SQLite plugin** choice in `front_vibes` | Match existing native storage patterns if any |
| 5 | **Dispatcher cache lock** (`Cache::lock`) needed on staging? | Add if double job overlap observed |
| 6 | **Execution ack API** required for MVP launch? | Phase 10 can ship immediately after 9 or in fast-follow |
| 7 | **List schedules on vibes home** vs dedicated tab | Product UX — not blocking backend |
| 8 | **Stale mirror TTL warning** when offline > N days | Future UX polish |

---

## Future work (explicitly out of MVP)

| Topic | Phase |
| --- | --- |
| FCM wake-to-play | Post-MVP + queue jobs |
| iOS local notifications | Post-MVP |
| Smart Home **`vibe_device_actions`** | Provider ADRs |
| RRULE / custom recurrence | Not planned |
| **`monthly` recurrence logic** | Reserved enum — future spec ([`spec.md`](spec.md)) |
| Offline schedule edit with outbox | **Rejected** |
| Admin schedule management | Not planned |
| “Only run if offline-ready” schedule flag | Future field — see [`scheduling-model.md`](../../../architecture/backend/scheduling-model.md) |

---

## Related docs

| Document | Path |
| --- | --- |
| **Feature spec** | [`spec.md`](spec.md) |
| **Task checklist** | [`tasks.md`](tasks.md) |
| **ADR-009** — timezone + UTC | [`decisions/ADR-009-scheduler-timezone-utc-storage.md`](../../../decisions/ADR-009-scheduler-timezone-utc-storage.md) |
| **ADR-010** — idempotency | [`decisions/ADR-010-scheduler-idempotency-occurrence-key.md`](../../../decisions/ADR-010-scheduler-idempotency-occurrence-key.md) |
| **ADR-011** — local notifications | [`decisions/ADR-011-scheduler-local-notifications-vs-future-fcm.md`](../../../decisions/ADR-011-scheduler-local-notifications-vs-future-fcm.md) |
| Scheduling model (long-range) | [`architecture/backend/scheduling-model.md`](../../../architecture/backend/scheduling-model.md) |
| Execution plan | [`specs/vibes/execution-plan/spec.md`](../../vibes/execution-plan/spec.md) |
| Offline download | [`specs/vibes/offline-download/spec.md`](../../vibes/offline-download/spec.md) |
| Auth | [`standards/front-vibes-auth-core.md`](../../../standards/front-vibes-auth-core.md) |
| Git Flow | [`standards/git-flow.md`](../../../standards/git-flow.md) |
| DigitalOcean staging | [`architecture/backend/staging-digitalocean.md`](../../../architecture/backend/staging-digitalocean.md) |
| Android native | [`architecture/mobile/android-native-customizations.md`](../../../architecture/mobile/android-native-customizations.md) |

When behaviour changes, update **`spec.md` first**, then this plan and [`tasks.md`](tasks.md).
