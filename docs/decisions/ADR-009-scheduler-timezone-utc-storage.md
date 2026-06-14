# ADR-009: Scheduler timezone and UTC storage

## Status

**Accepted** — governs **Scheduler MVP** delivery ([`specs/scheduler/mvp/spec.md`](../specs/scheduler/mvp/spec.md)). Schema hardening and **`RecurrenceService`** must follow this ADR.

## Date

2026-06-12

## Context

The Scheduler MVP lets users define **when a vibe should run** with simple recurrence. Stub schema today stores **`start_time`** as `dateTime` **without** a timezone column, and the planning doc ([`scheduling-model.md`](../architecture/backend/scheduling-model.md)) left timezone policy unsettled.

Without an explicit decision, implementations drift:

- Recurrence evaluated in **device local offset** vs **user profile timezone** vs **per-schedule timezone**
- **`start_time`** stored as ambiguous local wall clock or mixed UTC/local strings
- **DST** transitions producing double-fires or skipped days
- Mobile offline mirror recomputing **`next_run_at`** differently from backend dispatcher

The MVP spec requires:

- **Backend = source of truth** for schedule state and **`next_run_at`**
- **Each schedule owns its IANA timezone** — not inferred from GPS or device travel
- **Mobile SQLite mirror** is read-only offline; alarms use **server-computed `next_run_at`**
- Recurrence types **`once`**, **`daily`**, **`weekdays`**, **`weekly`** only
- **No GPS / location permission** for timezone in MVP

Laravel **`APP_TIMEZONE`** (typically UTC on workers) must not be treated as user scheduling intent.

---

## Decision

**Every schedule stores a required IANA `timezone`. All scheduling instants (`start_time`, `next_run_at`, `scheduled_for`) are persisted as UTC. Recurrence expands in the schedule’s timezone. Display uses schedule timezone, not the device’s current offset. Schedule timezone does not auto-update when the user travels.**

### Timezone ownership

| Topic | Rule |
| --- | --- |
| **`timezone` column** | **Required** on every schedule — valid IANA string (e.g. `America/Sao_Paulo`, `Europe/London`) |
| **Create UX** | Mobile may **suggest** device IANA as default — user confirms or edits before save |
| **After save** | Stored **`timezone` is authoritative** — does **not** follow device when user travels |
| **Display / edit forms** | Format **`start_time`** and recurrence labels in **schedule `timezone`**, not `Intl` device default alone |
| **GPS / location** | **Not used** in MVP — no location permission for timezone |
| **User profile timezone** | **Not used** as schedule default source of truth — optional UX suggestion only |

### UTC storage

| Column | Storage | Meaning |
| --- | --- | --- |
| **`start_time`** | **UTC instant** | First anchor occurrence — converted from user’s local date/time + **`timezone`** on write |
| **`next_run_at`** | **UTC instant** (nullable) | Next due tick for dispatcher and mobile alarm seed — **computed by backend `RecurrenceService`** |
| **`scheduled_for`** (executions) | **UTC instant** | Logical occurrence instant for audit row |
| **`last_run_at`** | **UTC instant** (nullable) | Optional materialized last processed occurrence |

**Rule:** PostgreSQL timestamps represent **absolute instants**. Recurrence math converts **local wall time in schedule timezone → UTC** for persistence and comparison.

**Worker clock:** Dispatcher and queries use **`now('UTC')`**. Laravel **`APP_TIMEZONE`** is infrastructure only — **not** user intent.

### Recurrence expansion

All expansion runs in **`schedule.timezone`** via timezone-aware datetimes (PHP **`CarbonImmutable`** + IANA), then results are stored/compared in UTC.

| `recurrence_type` | Behaviour |
| --- | --- |
| **`once`** | Single fire at first valid anchor ≥ **`start_time`**. After dispatch: **`next_run_at = null`** and **`is_enabled = false`** (one-shot complete) |
| **`daily`** | Every calendar day at the **same local wall time** as anchor in **`timezone`** |
| **`weekdays`** | Monday–Friday at that local wall time (ISO weekday 1–5 in schedule timezone) |
| **`weekly`** | On selected **`recurrence_config.days_of_week`** (ISO 1=Mon … 7=Sun) at that local wall time |
| **`monthly`** | **Reserved — not MVP.** Enum slot only; no recurrence logic, tests, or API in MVP |

Stub enum **`none`** maps to **`once`** at API/migration boundary. **`custom`** and RRULE are **rejected** in MVP.

### DST strategy

Recurrence must use **timezone-aware** semantics, not fixed UTC offsets.

| Transition | Policy |
| --- | --- |
| **Spring forward** (nonexistent local time) | **Skip** the occurrence — no fire at a time that does not exist (e.g. 02:30 on jump-forward day). **`RecurrenceService`** advances to next valid local wall time. |
| **Fall back** (ambiguous local time) | **First occurrence wins** — when local time repeats, use the **earlier** UTC instant (before offset rolls back). Prevents duplicate ticks for the same labeled local time in one transition. |

These rules are **mandatory test cases** in Phase 2 TDD (`America/Sao_Paulo`, `Europe/London` minimum) — **before** schema hardening (Phase 3).

### Offline mirror

| Topic | Rule |
| --- | --- |
| **SQLite mirror** | Read-only cache of API schedule rows including **`next_run_at`** |
| **Alarm seed** | Mobile local notifications prefer **server `next_run_at`** — do **not** re-expand recurrence offline as source of truth |
| **Sync** | On successful pull/CRUD sync, replace mirror; server wins on **`updated_at`** |
| **Offline editing** | **Forbidden** — no mirror writes from offline UI |

Optional mobile pre-expansion for UI preview may exist but must not diverge from server **`next_run_at`** for the next alarm.

---

## Consequences

### Positive

| Outcome | Why it matters |
| --- | --- |
| **Deterministic recurrence** | Same schedule + timezone → same UTC occurrences — testable in **`RecurrenceService`** |
| **Travel-safe semantics** | “7:00 in São Paulo” stays São Paulo — product intent is explicit |
| **Dispatcher/mobile alignment** | Single backend computes **`next_run_at`**; mirror copies it — fewer drift bugs |
| **No location permission** | Simpler privacy story for MVP |
| **Clear DST behaviour** | Documented skip/first-wins policies reduce support ambiguity |

### Negative / tradeoffs

| Tradeoff | Impact |
| --- | --- |
| **User travel confusion** | Device clock may differ from schedule timezone labels — UX must show schedule TZ |
| **DST edge-case support** | Skip/first-wins may surprise users once per year — copy and tests required |
| **Dual conversion layer** | API accepts local intent + timezone; DB stores UTC — Form Request + service must stay aligned |
| **No “follow device” mode** | Users who want travel-local scheduling must edit schedule timezone manually (future product) |

### Implementation expectations

- **Phase 2:** **`RecurrenceService`** TDD — pure PHP, no database
- **Phase 3:** migration adds **`timezone`**, **`next_run_at`**, **`last_run_at`**, **`updated_at`**
- **`RecurrenceService::computeNextRunAt`** is sole writer of **`next_run_at`** on create/update/dispatch (from Phase 4)
- Pest DST matrix required **in Phase 2** before schema lands

---

## Alternatives Considered

| Alternative | Why not chosen (MVP) |
| --- | --- |
| **Store local wall time without timezone** | Ambiguous across DST and travel; breaks dispatcher |
| **Infer timezone from device on every sync** | Violates “schedule owns timezone”; changes rules silently when traveling |
| **User profile default timezone only** | Insufficient for users with multiple schedules across regions |
| **GPS / geolocation timezone** | Permission friction; privacy; out of MVP scope |
| **Use Laravel `APP_TIMEZONE` for recurrence** | Conflates server config with user intent |
| **Expand recurrence on mobile only** | Conflicts with backend source of truth and offline mirror |
| **RRULE / iCal** | Out of MVP — four enums only |

---

## Related Docs

| Document | Relationship |
| --- | --- |
| [`../specs/scheduler/mvp/spec.md`](../specs/scheduler/mvp/spec.md) | Feature spec — timezone, **`next_run_at`**, recurrence |
| [`../specs/scheduler/mvp/plan.md`](../specs/scheduler/mvp/plan.md) | Phase 2 TDD, Phase 3 schema |
| [`../specs/scheduler/mvp/tasks.md`](../specs/scheduler/mvp/tasks.md) | Checklist |
| [`ADR-010`](ADR-010-scheduler-idempotency-occurrence-key.md) | **`scheduled_for`** UTC instant + **`occurrence_key`** |
| [`ADR-011`](ADR-011-scheduler-local-notifications-vs-future-fcm.md) | Mobile alarms from mirror **`next_run_at`** |
| [`../architecture/backend/scheduling-model.md`](../architecture/backend/scheduling-model.md) | Long-range planning — MVP supersedes for delivery |
| [`../architecture/backend/staging-digitalocean.md`](../architecture/backend/staging-digitalocean.md) | Worker runs UTC |

### Schema reference (stub — hardening pending)

| Artifact | Path |
| --- | --- |
| `schedules` migration | `back_vibes/database/migrations/2026_05_01_000007_create_schedules_table.php` |
| `Schedule` model | `back_vibes/app/Models/Schedule.php` |

---

When timezone or DST policy changes, supersede this ADR and update [`specs/scheduler/mvp/spec.md`](../specs/scheduler/mvp/spec.md) and **`RecurrenceService`** tests in the same change set.
