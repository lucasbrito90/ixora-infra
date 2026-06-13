# Scheduler MVP — task checklist

**Status:** Pre-implementation checklist  
**Spec:** [`spec.md`](spec.md)  
**Plan:** [`plan.md`](plan.md)  
**Feature ID:** `scheduler/mvp`

**Status legend**

| Status | Meaning |
| --- | --- |
| **Pending** | Not started |
| **In progress** | Active work on branch |
| **Done** | Merged to `develop` / verified on staging |
| **Deferred** | Post-MVP or fast-follow |

---

## Task list summary

| Phase | Pending | In progress | Done | Deferred |
| --- | ---: | ---: | ---: | ---: |
| 1 — Spec + ADRs | 2 | 0 | 6 | 0 |
| 2 — TDD RecurrenceService | 0 | 0 | 7 | 0 |
| 3 — Schema hardening | 0 | 0 | 9 | 0 |
| 4 — Backend CRUD API | 1 | 0 | 9 | 0 |
| 5 — Dispatcher command | 0 | 0 | 5 | 0 |
| 6 — OpenTofu Scheduled Job | 5 | 0 | 0 | 0 |
| 7 — Mobile CRUD | 8 | 0 | 0 | 0 |
| 8 — SQLite mirror | 6 | 0 | 0 | 0 |
| 9 — Local notifications | 7 | 0 | 0 | 0 |
| 10 — Execution log sync | 5 | 0 | 0 | 0 |

---

## Phase 1 — Spec + ADRs

| ID | Task | Status | Reference |
| --- | --- | --- | --- |
| P1-1 | Publish **`spec.md`** (MVP source of truth) | **Done** | [`spec.md`](spec.md) |
| P1-2 | Publish **`plan.md`** | **Done** | [`plan.md`](plan.md) |
| P1-3 | Publish **`tasks.md`** | **Done** | This file |
| P1-4 | Draft **ADR-009** — timezone + UTC storage | **Done** | [`ADR-009`](../../../decisions/ADR-009-scheduler-timezone-utc-storage.md) |
| P1-5 | Draft **ADR-010** — idempotency + **`occurrence_key`** | **Done** | [`ADR-010`](../../../decisions/ADR-010-scheduler-idempotency-occurrence-key.md) |
| P1-6 | Draft **ADR-011** — local notifications vs future FCM | **Done** | [`ADR-011`](../../../decisions/ADR-011-scheduler-local-notifications-vs-future-fcm.md) |
| P1-7 | Cross-link [`scheduling-model.md`](../../../architecture/backend/scheduling-model.md) status note | **Pending** | Architecture |
| P1-8 | Add scheduler MVP entry to **`docs/README.md`** index | **Pending** | [`README.md`](../../../README.md) |

**Branch:** `feature/scheduler-spec-adrs` from **`develop`**

---

## Phase 2 — TDD RecurrenceService (first code)

**First Scheduler MVP implementation.** TDD mandatory — see [`plan.md`](plan.md) § Phase 2.

| ID | Task | Status | Reference |
| --- | --- | --- | --- |
| P2-0 | Follow TDD loop: tests → red → minimal code → refactor → full suite | **Done** | [`plan.md`](plan.md) |
| P2-1 | Define **`ScheduleInput`** DTO / typed array (no Eloquent in unit tests) | **Done** | `app/Services/Scheduling/ScheduleInput.php` |
| P2-2 | Pest tests for **`computeNextRunAt`** — **`once`**, **`daily`**, **`weekdays`**, **`weekly`** | **Done** | `tests/Unit/Services/Scheduling/RecurrenceServiceTest.php` |
| P2-3 | Pest tests — DST matrix (`America/Sao_Paulo`, `Europe/London`) | **Done** | [ADR-009](../../../decisions/ADR-009-scheduler-timezone-utc-storage.md) |
| P2-4 | Pest tests for **`computeOccurrenceKey`** | **Done** | [ADR-010](../../../decisions/ADR-010-scheduler-idempotency-occurrence-key.md) |
| P2-5 | Implement **`RecurrenceService`** — **`computeNextRunAt`**, **`computeOccurrenceKey`** | **Done** | `app/Services/Scheduling/RecurrenceService.php` |
| P2-6 | Document **`RecurrenceType`** constant — include **`monthly`** reserved, reject in MVP | **Done** | `app/Services/Scheduling/RecurrenceType.php` |
| P2-7 | Export shared recurrence fixtures (JSON) for mobile parity | **Pending** | Phase 9 |

**Explicitly excluded:** **`monthly`** logic tests; migrations; controllers; DB.

**Branch:** `feature/scheduler-recurrence-service`

**Verify:**

```bash
cd back_vibes && php artisan test --filter=RecurrenceService
```

---

## Phase 3 — Schema hardening

**After Phase 2** — schema informed by tested recurrence behaviour.

> **Roadmap note:** This is **Phase 4** in the user-facing roadmap (Schema hardening step after RecurrenceService). The internal doc numbering (Phase 3) is preserved here.

| ID | Task | Status | Reference |
| --- | --- | --- | --- |
| P3-1 | Migration: add **`timezone`**, **`next_run_at`**, **`last_run_at`**, **`updated_at`** to **`schedules`** | **Done** | `database/migrations/2026_06_12_000001_add_scheduler_mvp_columns_to_schedules_table.php` |
| P3-2 | Migration: add **`occurrence_key`**, **`scheduled_for`** to **`schedule_executions`** | **Done** | `database/migrations/2026_06_12_000002_add_scheduler_mvp_columns_to_schedule_executions_table.php` |
| P3-3 | Unique index **`(schedule_id, occurrence_key)`** | **Done** | `uq_sch_exec_schedule_occurrence` |
| P3-4 | Index **`(next_run_at, is_enabled)`** for dispatcher | **Done** | `idx_schedules_next_run_enabled` |
| P3-5 | Update **`Schedule`** model — casts, fillable, **`UPDATED_AT`** | **Done** | `app/Models/Schedule.php` |
| P3-6 | Update **`ScheduleExecution`** model | **Done** | `app/Models/ScheduleExecution.php` |
| P3-7 | Data migration **`none` → `once`** in dev/staging seeds if any | **Done** | Migration backfill in `2026_06_12_000001` |
| P3-8 | **`RecurrenceType`** enum/constant in codebase — **`monthly`** reserved, not implemented | **Done** | `app/Services/Scheduling/RecurrenceType.php` (Phase 2) |
| P3-9 | Model factories for tests | **Done** | `ScheduleFactory`, `ScheduleExecutionFactory`, `VibeFactory` |

**Branch:** `feature/scheduler-schema-hardening`

**Verify:**

```bash
cd back_vibes && php artisan test --filter=Schedule   # 27 passed
cd back_vibes && php artisan test                     # 203 passed
cd back_vibes && ./vendor/bin/pint --test             # passed
```

---

## Phase 4 — Backend Schedule CRUD API

| ID | Task | Status | Reference |
| --- | --- | --- | --- |
| P4-1 | **`SchedulePolicy`** — owner scoping | **Done** | `app/Policies/SchedulePolicy.php` |
| P4-2 | **`StoreScheduleRequest` / `UpdateScheduleRequest`** | **Done** | `app/Http/Requests/StoreScheduleRequest.php`, `UpdateScheduleRequest.php` |
| P4-3 | **`ScheduleResource`** | **Done** | `app/Http/Resources/ScheduleResource.php` |
| P4-4 | **`ScheduleController`** — index, store, show, update, destroy | **Done** | `app/Http/Controllers/Api/ScheduleController.php` |
| P4-5 | Register routes under **`firebase.auth`** | **Done** | `routes/api.php` — `Route::apiResource('schedules', ScheduleController::class)` |
| P4-6 | Validate **`vibe_id`** belongs to **`auth()->id()`** | **Done** | After-validator in both FormRequests |
| P4-7 | On create/update → **`RecurrenceService`** → **`next_run_at`** | **Done** | Controller builds `ScheduleInput` and calls `computeNextRunAt` |
| P4-8 | Pest feature tests — CRUD, 403, 422 | **Done** | `tests/Feature/Scheduling/ScheduleApiTest.php` — 43 tests |
| P4-9 | Reject **`custom`**, **`monthly`**, RRULE, invalid IANA timezone | **Done** | `Rule::in(RecurrenceType::mvpAllowed())` + `timezone:all` rule |
| P4-10 | Document OpenAPI or inline API examples in spec if needed | **Pending** | Deferred — API contract already in `spec.md` |

**Branch:** `feature/scheduler-crud-api`

**Verify:**

```bash
cd back_vibes && php artisan test --filter=ScheduleApiTest   # 43 passed
cd back_vibes && php artisan test                            # 271 passed
cd back_vibes && ./vendor/bin/pint --test                    # passed
```

---

## Phase 5 — Dispatcher command

| ID | Task | Status | Reference |
| --- | --- | --- | --- |
| P5-1 | Artisan command **`schedules:dispatch-due`** | **Done** | `app/Console/Commands/DispatchDueSchedulesCommand.php` |
| P5-2 | Due query + batch limit + dry-run flag | **Done** | `--batch=100`, `--dry-run` options; query: `is_enabled=true AND next_run_at IS NOT NULL AND next_run_at <= now ORDER BY next_run_at LIMIT batch` |
| P5-3 | Idempotent insert **`schedule_executions`** + advance **`next_run_at`** | **Done** | Pre-check + unique index guard; `RecurrenceService::computeNextRunAt` advances schedule |
| P5-4 | **`once`** exhaustion — **`next_run_at = null`** + **`is_enabled = false`** | **Done** | `computeNextRunAt` returns null for once; command sets `is_enabled = false` |
| P5-5 | Pest integration tests — double dispatch | **Done** | `tests/Feature/Scheduling/DispatchDueSchedulesCommandTest.php` — 25 tests |

**Branch:** `feature/scheduler-dispatcher`

**Verify:**

```bash
cd back_vibes && php artisan schedules:dispatch-due --dry-run
cd back_vibes && php artisan test --filter=DispatchDue
```

---

## Phase 6 — OpenTofu DigitalOcean Scheduled Job

| ID | Task | Status | Reference |
| --- | --- | --- | --- |
| P6-1 | Add **`scheduled_job`** component to staging OpenTofu | **Pending** | [`opentofu/staging/`](../../../../opentofu/staging/) |
| P6-2 | Cron `* * * * *` → **`schedules:dispatch-due`** | **Pending** | [`spec.md`](spec.md) |
| P6-3 | Same Docker image + RUN_TIME env as API | **Pending** | [`staging-digitalocean.md`](../../../architecture/backend/staging-digitalocean.md) |
| P6-4 | Update **`staging-digitalocean.md`** architecture table | **Pending** | Infra docs |
| P6-5 | Staging verification — execution row from job | **Pending** | Manual QA |

**Branch:** `feature/scheduler-do-scheduled-job` ( **`ixora-infra`** + optional **`back_vibes`** if command name in deploy)

**Verify:**

```bash
cd ixora-infra/opentofu/staging && tofu plan
```

Promote via **`develop` → `staging`** merge per [`git-flow.md`](../../../standards/git-flow.md).

---

## Phase 7 — Mobile Schedule CRUD (online)

| ID | Task | Status | Reference |
| --- | --- | --- | --- |
| P7-1 | **`schedule.service.ts`** — REST client with Firebase Bearer | **Pending** | Auth |
| P7-2 | Schedule list page | **Pending** | Android first |
| P7-3 | Create / edit form — vibe picker, timezone, recurrence | **Pending** | [`spec.md`](spec.md) |
| P7-4 | Weekly day-of-week multi-select | **Pending** | **`recurrence_config`** |
| P7-5 | Delete with confirm | **Pending** | |
| P7-6 | **Block mutations when offline** | **Pending** | Hard boundary |
| P7-7 | Router entries | **Pending** | [`front-vibes-ionic-routing.md`](../../../standards/front-vibes-ionic-routing.md) |
| P7-8 | **`npm run build`** clean | **Pending** | CI |

**Branch:** `feature/scheduler-mobile-crud`

**Platform:** Android native installable — **not iOS MVP**

---

## Phase 8 — SQLite mirror

| ID | Task | Status | Reference |
| --- | --- | --- | --- |
| P8-1 | SQLite schema mirroring API schedule fields + **`synced_at`** | **Pending** | [`spec.md`](spec.md) § sync |
| P8-2 | **`pullSchedules()`** upsert from **`GET /api/schedules`** | **Pending** | |
| P8-3 | Invoke sync after CRUD success + app foreground / network restore | **Pending** | |
| P8-4 | Offline read-only list/detail from SQLite | **Pending** | |
| P8-5 | Purge local row on API delete | **Pending** | |
| P8-6 | **No offline write path** — code review guard | **Pending** | Non-goal |

**Branch:** `feature/scheduler-sqlite-mirror`

---

## Phase 9 — Local notifications (Android)

| ID | Task | Status | Reference |
| --- | --- | --- | --- |
| P9-1 | Integrate Local Notifications plugin | **Pending** | Capacitor |
| P9-2 | **`schedule-notification.service.ts`** — cancel + register | **Pending** | [`spec.md`](spec.md) |
| P9-3 | Schedule alarms from mirror **`next_run_at`** (rebuild after sync) | **Pending** | [ADR-011](../../../decisions/ADR-011-scheduler-local-notifications-vs-future-fcm.md) |
| P9-4 | Notification tap → deep link **`VibePlayerPage`** | **Pending** | No auto-play guarantee |
| P9-5 | Android 13+ **`POST_NOTIFICATIONS`** permission UX | **Pending** | |
| P9-6 | Rebuild notifications after every sync | **Pending** | Idempotent replace |
| P9-7 | Manual QA — installable build, not live reload | **Pending** | [`offline-download/spec.md`](../../vibes/offline-download/spec.md) pattern |

**Branch:** `feature/scheduler-local-notifications`

**Deferred:** iOS notification scheduling

---

## Phase 10 — Execution log sync

| ID | Task | Status | Reference |
| --- | --- | --- | --- |
| P10-1 | **`GET /api/schedules/{id}/executions`** | **Pending** | Audit list |
| P10-2 | Optional **`POST .../ack`** for mobile | **Pending** | Best-effort |
| P10-3 | Mobile — optional executions detail UI | **Pending** | |
| P10-4 | Mobile — POST ack on notification tap (online) | **Pending** | |
| P10-5 | Pest tests for executions endpoints | **Pending** | |

**Branch:** `feature/scheduler-execution-sync`

**Note:** May ship as fast-follow after Phase 9 MVP launch — see [`plan.md`](plan.md) open questions.

---

## Cross-cutting validation tasks

| ID | Task | Status | When |
| --- | --- | --- | --- |
| X-1 | Laravel full test suite on **`back_vibes`** touch | **Pending** | Each backend PR |
| X-2 | **`front_vibes` production build** | **Pending** | Each mobile PR |
| X-3 | Manual staging — create schedule → dispatcher tick → execution row | **Pending** | After Phase 6 |
| X-4 | Manual Android — notification at due time → tap → player | **Pending** | After Phase 9 |
| X-5 | Confirm **no FCM** code paths added | **Pending** | MVP sign-off |
| X-6 | Confirm **no Smart Home** invocations | **Pending** | MVP sign-off |
| X-7 | Confirm **no offline schedule edit** UI | **Pending** | MVP sign-off |
| X-8 | Auth smoke — schedule API **401** without token | **Pending** | Phase 4+ |

---

## Done criteria (MVP)

### Documentation

- [x] **`spec.md`**, **`plan.md`**, **`tasks.md`** published under `docs/specs/scheduler/mvp/`
- [x] ADR-009, ADR-010, ADR-011 merged
- [ ] **`docs/README.md`** links scheduler MVP

### Backend

- [x] **`RecurrenceService`** TDD complete (Phase 2) — tests green including DST
- [x] Schema hardening migrated on staging (Phase 3) — migrations + models + factories + tests green
- [x] Schedule CRUD API + Policy + Pest green (Phase 4 — 43 API tests, 246 total)
- [x] Dispatcher command idempotent under double run
- [ ] DO Scheduled Job firing on staging

### Mobile (Android)

- [ ] Online CRUD works against staging API
- [ ] Offline schedule list read-only from SQLite
- [ ] Local notification fires (installable build)
- [ ] Notification tap opens player — **manual Play** acceptable
- [ ] **No iOS** scheduling requirement for MVP done

### Hard boundaries verified

- [ ] **No guaranteed auto-play** when app killed — documented in UX
- [ ] **No offline editing**
- [ ] **No RRULE / custom recurrence**
- [ ] **No `monthly` recurrence logic** (enum reserved only)
- [ ] **No FCM**
- [ ] **No Smart Home**
- [ ] **No iOS scheduling** in MVP release

### Explicitly not required for MVP done

- FCM wake-to-play
- **`monthly` recurrence implementation**
- Queue **`DispatchVibeSchedule`** jobs
- iOS local notifications
- Admin schedule UI
- Smart Home device actions
- Offline schedule outbox
- Execution ack (optional fast-follow — Phase 10)

---

## Git workflow reminder

All implementation branches:

```bash
git checkout develop && git pull origin develop
git checkout -b feature/scheduler-<phase-short-name>
# PR → develop (never commit directly to develop/main/staging)
```

Promote to homologation:

```bash
git checkout staging && git pull origin staging
git merge --no-ff develop -m "Merge branch 'develop' into staging"
git push origin staging
```

Full policy: [`git-flow.md`](../../../standards/git-flow.md).

---

## Related docs

| Document | Path |
| --- | --- |
| Spec | [`spec.md`](spec.md) |
| Plan | [`plan.md`](plan.md) |
| ADR-009 | [`decisions/ADR-009-scheduler-timezone-utc-storage.md`](../../../decisions/ADR-009-scheduler-timezone-utc-storage.md) |
| ADR-010 | [`decisions/ADR-010-scheduler-idempotency-occurrence-key.md`](../../../decisions/ADR-010-scheduler-idempotency-occurrence-key.md) |
| ADR-011 | [`decisions/ADR-011-scheduler-local-notifications-vs-future-fcm.md`](../../../decisions/ADR-011-scheduler-local-notifications-vs-future-fcm.md) |
| Scheduling model | [`architecture/backend/scheduling-model.md`](../../../architecture/backend/scheduling-model.md) |
| Execution plan | [`specs/vibes/execution-plan/spec.md`](../../vibes/execution-plan/spec.md) |
| Offline download | [`specs/vibes/offline-download/spec.md`](../../vibes/offline-download/spec.md) |
| Auth | [`standards/front-vibes-auth-core.md`](../../../standards/front-vibes-auth-core.md) |
| Git Flow | [`standards/git-flow.md`](../../../standards/git-flow.md) |
| DigitalOcean staging | [`architecture/backend/staging-digitalocean.md`](../../../architecture/backend/staging-digitalocean.md) |
