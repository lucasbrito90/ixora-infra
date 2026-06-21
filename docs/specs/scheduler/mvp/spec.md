# Scheduler MVP — time-based vibe reminders (Android-first)

**Status:** Active feature specification (source of truth for MVP delivery)  
**Version:** 1.0 (MVP scope — not implemented)  
**Feature ID:** `scheduler/mvp`  
**Platform:** `back_vibes` (authoritative), `front_vibes` Android native (client mirror + local notifications)

> **Supersedes planning-only language** in [`scheduling-model.md`](../../../architecture/backend/scheduling-model.md) for MVP delivery. That architecture doc remains the long-range boundary reference; **this spec is the contract to implement**.

**Architecture decisions:** [ADR-009](../../../decisions/ADR-009-scheduler-timezone-utc-storage.md) (timezone + UTC), [ADR-010](../../../decisions/ADR-010-scheduler-idempotency-occurrence-key.md) (idempotency), [ADR-011](../../../decisions/ADR-011-scheduler-local-notifications-vs-future-fcm.md) (local notifications vs FCM).

---

## Goal

Enable an **authenticated user** to define **when a vibe should start**, with simple recurrence, **online CRUD on the backend**, a **read-only SQLite mirror on Android**, and **OS local notifications** as the first reminder path — while the backend maintains **authoritative schedule state**, **`next_run_at`**, and an **execution audit log**.

**Success criteria:**

- User can **create, list, update, enable/disable, and delete** schedules **only while online** (API is source of truth).
- Each schedule stores its own **IANA timezone**; recurrence expands in that timezone; **`next_run_at`** is stored in **UTC** for dispatcher queries.
- Supported recurrence (MVP): **`once`**, **`daily`**, **`weekdays`**, **`weekly`** — no RRULE, no `custom` JSON rules beyond weekly day selection.
- **`monthly`** is **reserved** in the domain enum for future expansion — **not part of MVP** (no logic, tests, API, or UI).
- A **DigitalOcean App Platform worker** (`scheduler`) runs a Laravel **dispatcher loop** (`schedules:dispatch-loop`) that calls the dispatcher command every ~60 seconds to advance due schedules and append **`schedule_executions`** rows **idempotently**.
- Android mirrors schedules in **SQLite (read-only offline)** and schedules **local notifications** from mirrored **`next_run_at`** / recurrence data when online sync succeeds.
- **No FCM**, **no Smart Home**, **no iOS scheduling**, **no offline schedule editing**, and **no guaranteed auto-play** when the app process is killed.

---

## Goals

| # | Goal |
| --- | --- |
| G-1 | Backend owns schedule CRUD, validation, ownership, recurrence math, and **`next_run_at`**. |
| G-2 | **`RecurrenceService`** is pure, deterministic, **database-agnostic**, and covered by **TDD before schema hardening** (Phase 2). |
| G-3 | Dispatcher command evaluates **`next_run_at <= now(UTC)`** and writes **`schedule_executions`** without duplicate ticks (idempotency). |
| G-4 | Mobile (Android) provides schedule management UI **online only**; offline shows mirrored schedules **read-only**. |
| G-5 | Local notifications remind the user at due times; tapping opens the app toward playback — **user or in-app action** starts **`playVibe`**, not server push. |
| G-6 | Scheduled playback reuses existing **execution plan + player stack** ([`execution-plan/spec.md`](../../vibes/execution-plan/spec.md), [`playback-runtime/spec.md`](../../vibes/playback-runtime/spec.md)). |
| G-7 | Offline vibe bytes remain governed by [`offline-download/spec.md`](../../vibes/offline-download/spec.md) — scheduling does not bypass download requirements. |
| G-8 | Infra adds a **DO App Platform `scheduler` worker** running a dispatch loop via OpenTofu — no new queue semantics required for MVP dispatch. |

---

## Non-goals

| # | Non-goal | MVP stance |
| --- | --- | --- |
| NG-1 | **Guaranteed auto-play** with killed app / force-stop | **Not promised** — local notification only; user may need to open app |
| NG-2 | **Offline create/edit/delete** schedules | **Forbidden** — mirror is read-only offline |
| NG-3 | **Advanced RRULE** / iCal import / natural language | **Out of scope** — four MVP recurrence enums only |
| NG-3b | **`monthly` recurrence logic** | **Reserved for future** — enum slot only; **not in MVP** |
| NG-4 | **FCM / APNs push** to wake app for play | **Future phase** — not in MVP |
| NG-5 | **Smart Home** (`devices`, `vibe_device_actions`) | **Future boundary** — schema stubs exist; no connectors |
| NG-6 | **iOS local notification scheduling** | **Out of MVP** — Android first; iOS follow-up spec |
| NG-7 | **Server-side audio execution** | **Never** — backend does not build execution plans or stream audio |
| NG-8 | **Admin schedule UI** (`ixora-admin`) | **Out of MVP** — mobile-first |
| NG-9 | **Queue worker dispatch jobs** | **Future phase** — MVP uses synchronous dispatcher command in the scheduler worker loop |
| NG-10 | **Background JS cron** in WebView | **Unreliable** — not used for due-time evaluation |

---

## Actors

| Actor | Role |
| --- | --- |
| **End user** | Creates schedules online; receives local notifications; may play vibe manually or from notification deep link. |
| **Laravel API (`back_vibes`)** | Authoritative CRUD, policies, **`RecurrenceService`**, **`next_run_at`**, execution audit. |
| **Dispatcher command** | Periodic tick — due schedules → idempotent execution row → advance **`next_run_at`**. |
| **Scheduler worker (`scheduler`)** | Long-running App Platform worker — runs `schedules:dispatch-loop`, calling the dispatcher every ~60 s. |
| **Mobile app (`front_vibes` Android)** | Online CRUD via API; SQLite mirror; local notification registration; optional execution ack sync. |
| **Firebase Auth** | Identity for all schedule API calls — [`front-vibes-auth-core.md`](../../../standards/front-vibes-auth-core.md). |

---

## Domain model

```
┌─────────────────┐         ┌─────────────────┐
│     users       │         │     vibes       │
│  (Firebase sync)│         │  user-owned     │
└────────┬────────┘         └────────┬────────┘
         │                           │
         │         ┌─────────────────▼─────────────────┐
         └────────►│           schedules              │
                   │  WHAT (vibe) + WHEN (recurrence)   │
                   │  timezone (IANA) + next_run_at UTC │
                   └─────────────────┬─────────────────┘
                                     │ 1:N
                                     ▼
                   ┌─────────────────────────────────────┐
                   │      schedule_executions               │
                   │  audit per occurrence (idempotent)   │
                   └─────────────────────────────────────┘

Mobile (Android, online write path):
  API CRUD ──► SQLite mirror (read-only offline) ──► LocalNotifications schedule

Playback (manual or notification tap):
  vibeSounds ──► buildVibeExecutionPlan ──► playVibe  (unchanged stack)
```

| Entity | MVP role |
| --- | --- |
| **`schedules`** | User-owned rule: target **vibe**, wall-clock anchor, **timezone**, recurrence, **`next_run_at`**, enabled flag |
| **`schedule_executions`** | Append-only audit of **dispatcher ticks** (and optional mobile ack metadata in `log`) |
| **`vibes`** | Must belong to same **`user_id`** as schedule; deleted vibe cascades schedule (FK) |
| **`devices` / `vibe_device_actions`** | **Not used in MVP** — future Smart Home boundary |

---

## `schedules` table

### Current stub (reference)

Existing migration: `back_vibes/database/migrations/2026_05_01_000007_create_schedules_table.php`

| Column (stub) | Notes |
| --- | --- |
| `user_id`, `vibe_id`, `name` | Present |
| `start_time` | `dateTime` — no timezone column today |
| `recurrence_type` | Comment: `none, daily, weekly, custom` |
| `recurrence_config` | Nullable JSON |
| `is_enabled` | Default true |
| `created_at` | Present; **no `updated_at`** on model today |

### MVP target schema (hardening — Phase 3)

| Column | Type | Required | Semantics |
| --- | --- | --- | --- |
| `id` | bigint PK | yes | |
| `user_id` | FK → `users` | yes | Owner — server assigns; never from client body |
| `vibe_id` | FK → `vibes` | yes | Target vibe — must belong to **`user_id`** |
| `name` | string(255) | yes | User-visible label |
| `timezone` | string(64) | yes | **IANA** identifier (e.g. `America/Sao_Paulo`) — **belongs to schedule** |
| `start_time` | timestamp UTC | yes | **First anchor instant** — stored UTC, interpreted with **`timezone`** for recurrence expansion |
| `recurrence_type` | string(32) | yes | MVP allowed: **`once` \| `daily` \| `weekdays` \| `weekly`** — see **`RecurrenceType`** below |
| `recurrence_config` | json nullable | conditional | **Required shape for `weekly` only** — see below |
| `next_run_at` | timestamp UTC nullable | yes | **Next due instant** in UTC — maintained by **`RecurrenceService`** |
| `last_run_at` | timestamp UTC nullable | no | Last dispatcher-processed occurrence (optional materialized field) |
| `is_enabled` | boolean | yes | Default true; false skips dispatcher and should cancel local notifications on sync |
| `created_at` | timestamp | yes | |
| `updated_at` | timestamp | yes | **Add in hardening** |

**Indexes (MVP):**

- `(user_id, is_enabled)`
- `(next_run_at, is_enabled)` — dispatcher query
- `(user_id, vibe_id)` — optional list filters

**Migration note:** Rename stub value **`none` → `once`** at API boundary or via data migration. Drop **`custom`** from allowed MVP values. Reserve **`monthly`** in enum/constants — reject at validation until a future spec ships.

### `RecurrenceType` — domain enum (planned)

Central constant / enum (documentation target — **not implemented yet**):

| Value | MVP | Notes |
| --- | --- | --- |
| **`once`** | ✅ Shipped in MVP | Single fire |
| **`daily`** | ✅ Shipped in MVP | Every calendar day |
| **`weekdays`** | ✅ Shipped in MVP | Mon–Fri |
| **`weekly`** | ✅ Shipped in MVP | Selected ISO weekdays in **`recurrence_config`** |
| **`monthly`** | ❌ **Reserved — not MVP** | **Monthly is reserved for future implementation and is not part of the MVP.** No recurrence logic, tests, API fields, or mobile UI in MVP. Enum slot only for forward-compatible schema/API validation lists. |

**MVP validation:** accept only **`once`**, **`daily`**, **`weekdays`**, **`weekly`**. Reject **`monthly`** with **422** until a future delivery phase.

### `recurrence_config` (MVP)

| `recurrence_type` | `recurrence_config` |
| --- | --- |
| **`once`** | **`null`** |
| **`daily`** | **`null`** |
| **`weekdays`** | **`null`** (implicit Mon–Fri in schedule **`timezone`**) |
| **`weekly`** | `{ "days_of_week": [1, 2, 3, 4, 5, 6, 7] }` — **ISO-8601**: Monday = 1 … Sunday = 7; at least one day |

**Not allowed in MVP:** interval counts, exception dates, RRULE strings, end-date ranges, **`monthly` logic** (open question on end-date — see [`plan.md`](plan.md)).

### Recurrence types — behaviour summary

| Type | Fires |
| --- | --- |
| **`once`** | Single occurrence at first valid **`start_time`**; after dispatch **`next_run_at = null`** and **`is_enabled = false`** ([ADR-009](../../../decisions/ADR-009-scheduler-timezone-utc-storage.md)) |
| **`daily`** | Every calendar day at the local wall time derived from anchor in **`timezone`** |
| **`weekdays`** | Monday–Friday at that local wall time |
| **`weekly`** | On selected **`days_of_week`** at that local wall time |
| **`monthly`** | **Not in MVP** — reserved enum only; behaviour TBD in future spec |

All **MVP-implemented** expansion uses **timezone-aware** semantics. DST policy: **skip** nonexistent local times (spring forward); **first occurrence wins** on fall back — [ADR-009](../../../decisions/ADR-009-scheduler-timezone-utc-storage.md).

---

## `schedule_executions` table

### Current stub (reference)

Migration: `back_vibes/database/migrations/2026_05_01_000008_create_schedule_executions_table.php`

### MVP target schema (hardening — Phase 3)

| Column | Type | Required | Semantics |
| --- | --- | --- | --- |
| `id` | bigint PK | yes | |
| `schedule_id` | FK → `schedules` | yes | Cascade on schedule delete |
| `occurrence_key` | string(64) | yes | **Idempotency key** — `{schedule_id}:{scheduled_for_unix}` — [ADR-010](../../../decisions/ADR-010-scheduler-idempotency-occurrence-key.md) |
| `scheduled_for` | timestamp UTC | yes | The logical occurrence instant this row represents |
| `executed_at` | timestamp UTC | yes | When dispatcher (or sync) recorded the event |
| `status` | string(32) | yes | **`dispatched`** (MVP default) — future: `acknowledged`, `failed`, `skipped` |
| `log` | text nullable | no | JSON or text diagnostics (dispatcher version, mobile ack, errors) |
| `created_at` | timestamp | yes | |

**Constraints:**

- **Unique** `(schedule_id, occurrence_key)` — enforces idempotency at DB level

**Boundary:** One execution row = **backend tick recorded**, not proof of audible playback. Mobile ack (Phase 10) may append to **`log`** or transition **`status`** in a later iteration.

---

## Timezone strategy

See [ADR-009](../../../decisions/ADR-009-scheduler-timezone-utc-storage.md).

| Topic | MVP decision |
| --- | --- |
| **Ownership** | **`timezone` column on each schedule** — not inferred from device offset |
| **Storage** | Instants (**`start_time`**, **`next_run_at`**, **`scheduled_for`**) persisted in **UTC** |
| **Expansion** | **`RecurrenceService`** expands “local wall time in **`timezone`**” → UTC for comparisons |
| **Display** | Mobile formats using schedule **`timezone`**, not device timezone (device TZ may differ when traveling) |
| **Validation** | Reject invalid IANA strings server-side |
| **Worker clock** | Dispatcher uses **`now()` UTC**; Laravel **`APP_TIMEZONE`** is irrelevant to user intent |
| **DST** | Skip nonexistent local times; first wins on ambiguous fall-back — [ADR-009](../../../decisions/ADR-009-scheduler-timezone-utc-storage.md) |
| **GPS / location** | **Not used** for timezone in MVP |

**Today (pre-MVP):** stub has no **`timezone`** column — Phase 3 schema hardening adds it. **`RecurrenceService`** (Phase 2) is implemented and tested **before** migration lands.

---

## `next_run_at` behaviour

| Event | Action |
| --- | --- |
| **Create schedule** | Compute first due instant ≥ anchor from **`start_time`**, **`recurrence_type`**, **`timezone`**, config → set **`next_run_at`** |
| **Update schedule** | Recompute **`next_run_at`** from new fields (does not rewrite past executions) |
| **Disable (`is_enabled = false`)** | Leave row; dispatcher skips; **`next_run_at`** may remain for re-enable |
| **Dispatcher tick** | For each due row: insert execution (idempotent) → set **`last_run_at`** → advance **`next_run_at`** to **next** occurrence via **`RecurrenceService`** |
| **`once` after fire** | **`next_run_at = null`** and **`is_enabled = false`** — [ADR-009](../../../decisions/ADR-009-scheduler-timezone-utc-storage.md) |
| **Deleted / invalid vibe** | FK cascade removes schedule; mobile mirror purge on sync |

**Query (dispatcher):**

```sql
SELECT * FROM schedules
WHERE is_enabled = true
  AND next_run_at IS NOT NULL
  AND next_run_at <= :now_utc
ORDER BY next_run_at ASC
LIMIT :batch_size;
```

**Batch size:** configurable; MVP default small (e.g. 100) — open in [`plan.md`](plan.md).

---

## Local notification strategy (Android MVP)

See [ADR-011](../../../decisions/ADR-011-scheduler-local-notifications-vs-future-fcm.md).

| Topic | Decision |
| --- | --- |
| **Purpose** | **Remind** user at due time — primary offline-capable reminder path |
| **Trigger data** | Derived from **SQLite mirror** after successful online sync |
| **Registration** | On schedule create/update/delete sync: **cancel all** schedule notifications for user → **re-register** from mirror |
| **Identifier** | Stable notification id from **`schedule_id`** + **`occurrence_key`** or hashed **`next_run_at`** |
| **Payload** | Minimal: **`schedule_id`**, **`vibe_id`**, schedule name — enough to deep link to player |
| **Due time source** | Prefer backend **`next_run_at`**; for recurring futures, mobile may pre-compute **N upcoming** occurrences locally using same rules as **`RecurrenceService`** (shared test vectors) or schedule one notification at a time and reschedule on fire |
| **Offline** | Notifications already scheduled **continue** if OS permits; **no new schedules** offline |
| **Auto-play** | **Not guaranteed** — notification opens app; user taps Play or optional in-app “Start now” action |
| **Permissions** | Android 13+ **`POST_NOTIFICATIONS`** — required for reminders; document UX if denied |
| **Killed app** | OS may defer/drop alarms — **no warranty** (hard boundary) |
| **iOS** | **Out of MVP** |

**Relationship to dispatcher:** Backend tick records audit even if device offline; local notification is **parallel**, not replaced by dispatcher in MVP.

---

## Online / offline sync strategy

See [ADR-009](../../../decisions/ADR-009-scheduler-timezone-utc-storage.md) (mirror **`next_run_at`**) and [ADR-011](../../../decisions/ADR-011-scheduler-local-notifications-vs-future-fcm.md) (no offline mutations).

| Mode | Backend | Mobile SQLite mirror | Local notifications |
| --- | --- | --- | --- |
| **Online** | Source of truth | **Upsert** from `GET /api/schedules` (+ delta sync TBD) | Rebuilt after sync |
| **Offline** | Unavailable for writes | **Read-only** list/detail | Previously scheduled alarms may still fire |
| **Create / edit / delete** | API only | Updated **after** successful API response | Updated **after** mirror write |
| **Conflict** | Server wins | Client replaces mirror row by `id` + `updated_at` | Rebuilt from server state |

**Sync triggers (MVP minimum):**

- App foreground + network restored
- After each schedule CRUD success
- Optional periodic pull (e.g. on vibes list refresh)

**No offline outbox** for schedule mutations.

**Auth:** All schedule endpoints require Firebase Bearer — [`front-vibes-auth-core.md`](../../../standards/front-vibes-auth-core.md).

---

## Idempotency strategy

See [ADR-010](../../../decisions/ADR-010-scheduler-idempotency-occurrence-key.md).

| Layer | Mechanism |
| --- | --- |
| **Occurrence key** | `occurrence_key = "{schedule_id}:{scheduled_for_unix}"` |
| **Database** | Unique index on `(schedule_id, occurrence_key)` |
| **Dispatcher** | Insert execution in transaction; on unique violation → **skip** (duplicate cron tick) |
| **Advance `next_run_at`** | Only after successful insert (or within same transaction) |
| **Mobile notifications** | Idempotent replace per schedule id — cancel before reschedule |
| **Future FCM** | Same **`occurrence_key`** in push payload to dedupe on device |

**Duplicate ticks:** Scheduler worker restart or brief overlap + manual runs must not double-advance recurrence — transaction + unique constraint is the guard.

---

## Dispatcher worker strategy

| Topic | MVP decision |
| --- | --- |
| **Mechanism** | **App Platform `worker`** (`scheduler`) running `schedules:dispatch-loop` (OpenTofu Phase 7 — supersedes Scheduled Job approach) |
| **Loop command** | `php artisan schedules:dispatch-loop` — long-running process; calls `schedules:dispatch-due` every ~60 seconds |
| **Dispatch command** | `php artisan schedules:dispatch-due` |
| **Cadence** | **~60 seconds** (configurable via `--interval`; default 60 s) |
| **Why worker instead of Scheduled Job** | DO App Platform Scheduled Jobs are limited to ≥15-minute minimum cadence, and the `digitalocean/digitalocean` provider v2.87.0 does not support `SCHEDULED` kind / `cron_expression` ([issue #1529](https://github.com/digitalocean/terraform-provider-digitalocean/issues/1529)) |
| **Runtime** | Same **`back_vibes` Docker image** and env as **`api`** / **`queue`** worker |
| **Concurrency** | **`instance_count = 1`** — restart or brief overlap acceptable because dispatch is idempotent (ADR-010) |
| **Failure** | Loop catches exceptions per tick; logs to App Platform stderr; SIGTERM triggers graceful shutdown after current tick |
| **Not in MVP** | Separate queue job per schedule; Horizon scaling |

**Reference infra:** [`staging-digitalocean.md`](../../../architecture/backend/staging-digitalocean.md) — `scheduler` worker in OpenTofu staging stack; production follow-up out of MVP doc scope.

---

## Future FCM strategy (post-MVP boundary)

Documented for alignment only — **not implemented in MVP**. See [ADR-011](../../../decisions/ADR-011-scheduler-local-notifications-vs-future-fcm.md).

| Topic | Direction |
| --- | --- |
| **Transport** | FCM (Android) / APNs (iOS) when product adds wake-to-play |
| **Payload** | `vibe_id`, `schedule_id`, **`occurrence_key`** — not full `VibeSound[]` |
| **Handler** | Native → Capacitor → fetch sounds or offline snapshot → **`playVibe`** |
| **Queue** | **`DispatchVibeSchedule`** jobs processed by existing **`queue`** worker |
| **Audit** | Extend **`status`** beyond **`dispatched`** — `acknowledged`, `failed` |
| **Opt-in** | Notification permission + user setting for automation vs reminder-only |

See [`scheduling-model.md`](../../../architecture/backend/scheduling-model.md) § Push notification.

---

## Future Smart Home boundary

| Topic | MVP stance |
| --- | --- |
| **`devices` table** | Stub only — no API |
| **`vibe_device_actions`** | Stub only — actions attach to **vibe**, not schedule row |
| **Providers** (Home Assistant, Tuya, Alexa, Google Home) | **Out of scope** — provider-specific ADR required per integration |
| **Schedule tick** | MVP does **not** invoke device actions; playback path only |

When Smart Home ships, side effects remain **vibe-scoped** unless a future **`schedule_device_actions`** extension is specified.

---

## Playback integration

Scheduled reminder → user opens player → **same stack as manual play:**

```
notification tap / user action
  → load vibe + sounds (API or offline snapshot)
  → buildVibeExecutionPlan(vibeSounds)
  → player.store.playVibe
```

| Requirement | Source |
| --- | --- |
| Execution plan rules | [`execution-plan/spec.md`](../../vibes/execution-plan/spec.md) |
| Player / FGS constraints | [`playback-runtime/spec.md`](../../vibes/playback-runtime/spec.md) |
| Offline bytes | [`offline-download/spec.md`](../../vibes/offline-download/spec.md) |
| No backend play API | [`scheduling-model.md`](../../../architecture/backend/scheduling-model.md) |

**Offline playback at scheduled time:** Only if user previously downloaded vibe; otherwise notification opens app and playback may fail until online — honest UX copy required.

---

## Functional requirements

| ID | Requirement |
| --- | --- |
| SCH-1 | Schedule CRUD is **user-scoped**; **`user_id`** from auth only. |
| SCH-2 | **`vibe_id`** must reference a vibe owned by the same user. |
| SCH-3 | **`timezone`** is required valid IANA on every schedule. |
| SCH-4 | **`recurrence_type`** ∈ **`once`, `daily`, `weekdays`, `weekly`** only — reject **`monthly`** until future phase. |
| SCH-5 | **`weekly`** requires **`recurrence_config.days_of_week`** non-empty ISO weekdays. |
| SCH-6 | **`next_run_at`** computed on create/update; stored UTC. |
| SCH-7 | Dispatcher runs idempotently; unique **`occurrence_key`** per tick. |
| SCH-8 | Mobile SQLite mirror is **read-only offline** — no offline mutations. |
| SCH-9 | Android registers local notifications after successful sync. |
| SCH-10 | **No FCM** sends in MVP backend. |
| SCH-11 | **No iOS** schedule notification registration in MVP. |
| SCH-12 | **No Smart Home** invocations in MVP. |
| SCH-13 | **No RRULE** parsing. |
| SCH-14 | All schedule routes use **`firebase.auth`** middleware. |
| SCH-15 | **`SchedulePolicy`** enforces owner match on view/update/delete. |

---

## API contract (outline — Phase 4 detail)

**Base path:** `/api/schedules`  
**Middleware:** `firebase.auth`

| Method | Path | Action |
| --- | --- | --- |
| `GET` | `/api/schedules` | List current user's schedules |
| `POST` | `/api/schedules` | Create |
| `GET` | `/api/schedules/{id}` | Show |
| `PATCH` | `/api/schedules/{id}` | Update |
| `DELETE` | `/api/schedules/{id}` | Delete |

**Response resource fields (minimum):** `id`, `name`, `vibe_id`, `timezone`, `start_time`, `recurrence_type`, `recurrence_config`, `next_run_at`, `last_run_at`, `is_enabled`, `created_at`, `updated_at`

**Phase 10 — execution sync (outline):**

| Method | Path | Action |
| --- | --- | --- |
| `GET` | `/api/schedules/{id}/executions` | List audit rows (owner) |
| `POST` | `/api/schedules/{id}/executions/{occurrence_key}/ack` | Mobile ack optional — TBD in Phase 10 |

Form Requests, Resources, and Pest tests are Phase 4 deliverables — not duplicated here.

---

## Security rules

| Rule | Requirement |
| --- | --- |
| Identity | Firebase Bearer — [`front-vibes-auth-core.md`](../../../standards/front-vibes-auth-core.md) |
| Ownership | **`SchedulePolicy`** — same pattern as vibes |
| **`user_id` in body** | Rejected / ignored — server assigns |
| **`vibe_id`** | Validated against **`auth()->id()`** ownership |
| Cross-user access | **403** on show/update/delete |
| Admin | No schedule admin routes in MVP |

---

## Hard boundaries (MVP)

| Boundary | Implication |
| --- | --- |
| **No guaranteed auto-play (killed app)** | Product copy and support docs must set expectations |
| **No offline editing** | Disable create/edit/delete UI when offline |
| **No advanced RRULE** | Reject unknown recurrence types at validation |
| **No FCM in MVP** | Dispatcher is audit + **`next_run_at`** only |
| **No Smart Home in MVP** | Ignore device action stubs |
| **No iOS scheduling in MVP** | Feature flag or platform guard on Android-only code paths |

---

## Delivery phases (reference)

| Phase | Deliverable |
| --- | --- |
| 1 | This spec + [ADR-009](../../../decisions/ADR-009-scheduler-timezone-utc-storage.md), [ADR-010](../../../decisions/ADR-010-scheduler-idempotency-occurrence-key.md), [ADR-011](../../../decisions/ADR-011-scheduler-local-notifications-vs-future-fcm.md) |
| 2 | **TDD `RecurrenceService`** — first code deliverable; no DB/migrations |
| 3 | Schema hardening migration (informed by Phase 2 behaviour) |
| 4 | Backend Schedule CRUD API + Pest |
| 5 | **`schedules:dispatch-due`** command |
| 6 | OpenTofu Laravel Scheduler Worker (`scheduler` worker + `schedules:dispatch-loop`) |
| 7 | Mobile Schedule CRUD (online) |
| 8 | SQLite mirror |
| 9 | Local notifications (Android) |
| 10 | Execution log sync (mobile ack / list executions) |

See [`plan.md`](plan.md) and [`tasks.md`](tasks.md).

### Phase 2 — TDD `RecurrenceService` (first code)

**Mandatory order:** (1) write tests → (2) red → (3) minimal implementation → (4) refactor → (5) full suite.

**Scope:** `computeNextRunAt()`, `computeOccurrenceKey()` only — **no** migrations, HTTP, Eloquent in unit tests, mobile, or OpenTofu. Input via DTO / typed array + **`CarbonImmutable`**. **`monthly`** — no tests or logic.

Details: [`plan.md`](plan.md) § First implementation / Phase 2.

---

## Related docs

| Document | Relationship |
| --- | --- |
| **ADR-009** — timezone + UTC | [`decisions/ADR-009-scheduler-timezone-utc-storage.md`](../../../decisions/ADR-009-scheduler-timezone-utc-storage.md) |
| **ADR-010** — idempotency | [`decisions/ADR-010-scheduler-idempotency-occurrence-key.md`](../../../decisions/ADR-010-scheduler-idempotency-occurrence-key.md) |
| **ADR-011** — local notifications | [`decisions/ADR-011-scheduler-local-notifications-vs-future-fcm.md`](../../../decisions/ADR-011-scheduler-local-notifications-vs-future-fcm.md) |
| **Scheduling model (planning / long-range)** | [`architecture/backend/scheduling-model.md`](../../../architecture/backend/scheduling-model.md) |
| **Execution plan** | [`specs/vibes/execution-plan/spec.md`](../../vibes/execution-plan/spec.md) |
| **Playback runtime** | [`specs/vibes/playback-runtime/spec.md`](../../vibes/playback-runtime/spec.md) |
| **Offline download** | [`specs/vibes/offline-download/spec.md`](../../vibes/offline-download/spec.md) |
| **Auth** | [`standards/front-vibes-auth-core.md`](../../../standards/front-vibes-auth-core.md) |
| **Git Flow** | [`standards/git-flow.md`](../../../standards/git-flow.md) |
| **DigitalOcean staging** | [`architecture/backend/staging-digitalocean.md`](../../../architecture/backend/staging-digitalocean.md) |
| **Android native constraints** | [`architecture/mobile/android-native-customizations.md`](../../../architecture/mobile/android-native-customizations.md) |
| **Plan / tasks** | [`plan.md`](plan.md), [`tasks.md`](tasks.md) |

### Schema reference (stubs + MVP deltas)

| Artifact | Path |
| --- | --- |
| `schedules` migration (stub) | `back_vibes/database/migrations/2026_05_01_000007_create_schedules_table.php` |
| `schedule_executions` migration (stub) | `back_vibes/database/migrations/2026_05_01_000008_create_schedule_executions_table.php` |
| Models | `back_vibes/app/Models/Schedule.php`, `ScheduleExecution.php` |

When behaviour changes, update **this file first**, then ADRs, [`plan.md`](plan.md), and [`tasks.md`](tasks.md).
