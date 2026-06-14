# ADR-010: Scheduler idempotency and occurrence_key

## Status

**Accepted** — governs **Scheduler MVP** dispatcher and **`schedule_executions`** schema ([`specs/scheduler/mvp/spec.md`](../specs/scheduler/mvp/spec.md)).

## Date

2026-06-12

## Context

The Scheduler MVP runs a **backend dispatcher** on a **DigitalOcean App Platform Scheduled Job** (target: every minute). Real-world triggers are **at-least-once**:

- Cron may overlap if a run exceeds one minute
- Platform may retry failed job invocations
- Operators may run **`php artisan schedules:dispatch-due`** manually in staging
- Multiple app instances are unlikely in MVP (`instance_count = 1`) but idempotency must not depend on single-run luck

Without a dedupe key, duplicate ticks would:

- Insert multiple **`schedule_executions`** rows for the same logical occurrence
- **Double-advance `next_run_at`**, skipping future occurrences
- Corrupt audit trails and future FCM dedupe

The domain separates:

- **`Schedule`** — configuration rule (what, when, recurrence)
- **`ScheduleExecution`** — **append-only audit** of a **single occurrence tick** — **not** a playback session

MVP explicitly states **`dispatched` ≠ audible playback**. Mobile may later ack via the same **`occurrence_key`** ([ADR-011](ADR-011-scheduler-local-notifications-vs-future-fcm.md), Phase 10).

Stub **`schedule_executions`** today lacks **`occurrence_key`** and **`scheduled_for`** — Phase 3 schema hardening adds them; **no migration in this ADR change set**. **`computeOccurrenceKey`** is implemented in Phase 2 TDD before migrations.

---

## Decision

**Each schedule occurrence is identified by a required `occurrence_key`, unique per `(schedule_id, occurrence_key)`. The dispatcher inserts an execution row and advances `next_run_at` in a transaction; duplicate inserts must not double-advance recurrence. Execution rows are append-only audit — not proof of playback.**

### Domain roles

| Entity | Role |
| --- | --- |
| **`schedules`** | **Rule** — vibe target, timezone, recurrence, **`next_run_at`**, enabled flag |
| **`schedule_executions`** | **Audit occurrence** — one row per **logical tick** of a schedule at a specific **`scheduled_for`** instant |

**Boundary:** A **`ScheduleExecution`** records that the **backend processed a due occurrence** (and optionally later that mobile acked). It does **not** guarantee the user heard audio or that **`playVibe`** ran.

### `occurrence_key` format

**Required** on every execution row.

```
occurrence_key = "{schedule_id}:{scheduled_for_unix}"
```

Where:

- **`schedule_id`** — parent schedule primary key
- **`scheduled_for_unix`** — UTC **`scheduled_for`** instant as Unix timestamp (integer seconds)

**Rules:**

- **`scheduled_for`** equals the schedule’s **`next_run_at`** at tick start (UTC instant of the occurrence being processed)
- Key is **stable** across retries — same occurrence → same key
- Future FCM payloads and mobile ack endpoints **reuse the same key** for dedupe

Alternative hashing (e.g. SHA-256) is acceptable if canonical string above is preserved in logs; **MVP standard is the colon-separated form** for debuggability.

### Database constraint

**Unique index:** `(schedule_id, occurrence_key)`

Enforces idempotency at the database layer even if application logic regresses.

### Dispatcher algorithm (mandatory)

For each due schedule (`is_enabled`, **`next_run_at <= now(UTC)`**):

1. Begin **database transaction**
2. **`scheduled_for = next_run_at`** (UTC)
3. **`occurrence_key = "{id}:{scheduled_for->unix()}"`**
4. **Insert** **`schedule_executions`** with:
   - **`status = dispatched`** (MVP default)
   - **`executed_at = now(UTC)`**
   - **`scheduled_for`**, **`occurrence_key`**
5. On **unique violation** (duplicate tick):
   - **Rollback only this schedule’s work** or catch duplicate — **do not advance `next_run_at` again**
   - Treat as **successful idempotent no-op** for that occurrence
6. On **successful insert**:
   - Set **`last_run_at = scheduled_for`**
   - **`next_run_at = RecurrenceService::computeNextRunAt(...)`** ([ADR-009](ADR-009-scheduler-timezone-utc-storage.md))
   - For exhausted **`once`**: **`next_run_at = null`**, **`is_enabled = false`**
7. **Commit transaction**

**Rule:** **`next_run_at` must never advance twice for the same `scheduled_for`.**

### Status vocabulary (MVP)

| Status | Meaning |
| --- | --- |
| **`dispatched`** | Backend recorded tick (MVP default on insert) |
| **`failed`** | Dispatcher or infrastructure error (optional per-row catch) |

Future phases may add **`acknowledged`**, **`skipped`** via mobile ack or FCM handler — same **`occurrence_key`**.

### Append-only audit

| Rule | Detail |
| --- | --- |
| **Insert** | Executions are **inserted**, not updated in MVP — except optional **`log`** append in Phase 10 |
| **Delete** | Cascade when schedule deleted — no standalone user “delete execution” API in MVP |
| **Playback proof** | **Never** infer play success from **`dispatched`** alone |

### Future FCM / mobile ack

| Topic | Direction |
| --- | --- |
| **FCM payload** | Include **`schedule_id`**, **`occurrence_key`**, **`vibe_id`** |
| **Device dedupe** | Ignore push if execution row already acked for key |
| **Ack API** | **`POST .../executions/{occurrence_key}/ack`** — Phase 10 |

---

## Consequences

### Positive

| Outcome | Why it matters |
| --- | --- |
| **Safe cron retries** | Manual and overlapping job runs do not corrupt recurrence |
| **Honest audit** | One row per logical occurrence |
| **Future-proof dedupe** | FCM and mobile share key with DB constraint |
| **Testable** | Double **`schedules:dispatch-due`** invocation is a standard Pest case |

### Negative / tradeoffs

| Tradeoff | Impact |
| --- | --- |
| **Schema migration required** | Phase 3 adds columns + unique index on existing stub table |
| **Transaction per schedule** | Slightly higher DB load vs blind update — acceptable at MVP scale |
| **Key collision discipline** | **`scheduled_for`** must come from **`next_run_at`**, not wall clock at insert time |
| **Audit ≠ playback** | Product/support must not treat **`dispatched`** as “played” |

### Implementation expectations

- **Phase 2:** implement **`computeOccurrenceKey`** via TDD (no DB)
- **Phase 3** migration: **`occurrence_key`**, **`scheduled_for`**, unique `(schedule_id, occurrence_key)`
- **Phase 5** command: transactional insert + advance per ADR
- **Phase 5** tests: invoke dispatcher twice → **one** execution row, **`next_run_at`** advanced once

---

## Alternatives Considered

| Alternative | Why not chosen (MVP) |
| --- | --- |
| **Advance `next_run_at` before insert** | Retry skips audit row but may lose occurrence record |
| **Application-only dedupe (no unique index)** | Race conditions under concurrent workers |
| **Distributed lock only (Redis)** | Extra infra; DB unique index is sufficient for MVP |
| **Replace execution row on retry** | Violates append-only audit |
| **Use `executed_at` as occurrence identity** | Retries produce different timestamps — poor dedupe |
| **Single global “last_run_id” on schedule** | Loses per-occurrence history |

---

## Related Docs

| Document | Relationship |
| --- | --- |
| [`../specs/scheduler/mvp/spec.md`](../specs/scheduler/mvp/spec.md) | Idempotency, executions table |
| [`../specs/scheduler/mvp/plan.md`](../specs/scheduler/mvp/plan.md) | Phase 2 TDD, Phase 3 schema, Phase 5 dispatcher |
| [`../specs/scheduler/mvp/tasks.md`](../specs/scheduler/mvp/tasks.md) | Checklist |
| [`ADR-009`](ADR-009-scheduler-timezone-utc-storage.md) | **`scheduled_for`** UTC instant source |
| [`ADR-011`](ADR-011-scheduler-local-notifications-vs-future-fcm.md) | Reminder path parallel to audit |
| [`../architecture/backend/scheduling-model.md`](../architecture/backend/scheduling-model.md) | Future queue idempotency — aligns on occurrence keys |
| [`../architecture/backend/staging-digitalocean.md`](../architecture/backend/staging-digitalocean.md) | Scheduled Job component |

### Schema reference (stub — hardening pending)

| Artifact | Path |
| --- | --- |
| `schedule_executions` migration | `back_vibes/database/migrations/2026_05_01_000008_create_schedule_executions_table.php` |
| `ScheduleExecution` model | `back_vibes/app/Models/ScheduleExecution.php` |

---

When idempotency or key format changes, supersede this ADR and migrate existing execution rows in a dedicated migration plan.
