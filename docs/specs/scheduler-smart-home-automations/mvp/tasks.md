# Scheduler + Smart Home Automations MVP — task checklist

**Status:** Phase 4 complete — backend execution integration shipped  
**Spec:** [`spec.md`](spec.md)  
**Plan:** [`plan.md`](plan.md)  
**Feature ID:** `scheduler-smart-home-automations/mvp`

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
| 1 — ADRs + Spec | 0 | 0 | 9 | 0 |
| 2 — Schema/domain review | 0 | 0 | 5 | 0 |
| 3 — Dispatch integration review | 0 | 0 | 6 | 0 |
| 4A — ScheduleAutomationValidator | 0 | 0 | 1 | 0 |
| 4 — Backend execution integration | 0 | 0 | 6 | 0 |
| 5 — Mobile UX surface | 0 | 0 | 6 | 0 |
| 6 — Push/local alignment | 0 | 0 | 5 | 0 |
| 7 — QA automation tests | 0 | 0 | 5 | 0 |
| 8 — Staging + Android E2E QA | 2 | 0 | 4 | 0 |

---

## Phase 1 — ADRs + Spec

| ID | Task | Status | Reference |
| --- | --- | --- | --- |
| P1-1 | Draft **ADR-022** — Automation model | **Done** | [`ADR-022`](../../../decisions/ADR-022-scheduler-smart-home-automation-model.md) |
| P1-2 | Draft **ADR-023** — Execution order and failure policy | **Done** | [`ADR-023`](../../../decisions/ADR-023-automation-execution-order-and-failure-policy.md) |
| P1-3 | Draft **ADR-024** — Notifications and observability | **Done** | [`ADR-024`](../../../decisions/ADR-024-automation-notifications-and-observability.md) |
| P1-4 | Draft **ADR-025** — Mobile UX | **Done** | [`ADR-025`](../../../decisions/ADR-025-automation-mobile-ux.md) |
| P1-5 | Publish **`spec.md`** (MVP source of truth) | **Done** | [`spec.md`](spec.md) |
| P1-6 | Publish **`plan.md`** | **Done** | [`plan.md`](plan.md) |
| P1-7 | Publish **`tasks.md`** | **Done** | This file |
| P1-8 | Add Scheduler + Smart Home Automations entry to **`docs/README.md`** | **Done** | [`README.md`](../../../README.md) |
| P1-9 | Confirm **no runtime code** changed in Phase 1 | **Done** | This phase |

**Branch:** `feature/scheduler-smart-home-automations-spec-adrs` from **`develop`**

**Phase 1 implementation notes:**

- Four ADRs (022–025) document composition model, execution order, notifications, and mobile UX.
- Spec defines Schedule + Vibe + VibeDeviceAction automation view, backend/mobile proposals, and acceptance criteria.
- Plan defines 8-phase roadmap from domain review through E2E QA.
- Explicit decision: **no `automations` table**, **no automation engine**, **no background autoplay**.
- No migrations, controllers, scheduler runtime, Smart Home runtime, push runtime, or mobile code modified.

---

## Phase 2 — Backend schema/domain review

| ID | Task | Status | Reference |
| --- | --- | --- | --- |
| P2-1 | Verify `schedules` → `vibes` FK and cascade semantics | **Done** | [`schema-domain-review.md`](schema-domain-review.md) §4 |
| P2-2 | Verify `vibe_device_actions` schema (`sort_order`, FKs) | **Done** | [`schema-domain-review.md`](schema-domain-review.md) §5 |
| P2-3 | Confirm `schedule_executions.log` sufficient for dispatch summary | **Done** | [`schema-domain-review.md`](schema-domain-review.md) §6 |
| P2-4 | Document: **no new tables required for MVP** | **Done** | [`schema-domain-review.md`](schema-domain-review.md) §10 |
| P2-5 | List API embed fields needed for mobile surfacing | **Done** | [`schema-domain-review.md`](schema-domain-review.md) §9 |

**Branch:** `feature/scheduler-smart-home-domain-review`

**Phase 2 implementation notes:**

- Published [`schema-domain-review.md`](schema-domain-review.md) — full inventory, model graph, migration decision **Option A (no migrations)**.
- Verified: required `schedules.vibe_id` with `cascadeOnDelete`; complete `vibe_device_actions` with `sort_order` and `idx_vda_vibe_sort`.
- Verified: `schedule_executions.log` (`text`, nullable) stores JSON strings today — sufficient for Smart Home dispatch summary.
- Verified: `VibeSmartHomeDispatchService` reusable from scheduler path without schema changes; no wrapper required for MVP.
- Documented Phase 5 API embed fields (`device_actions_count`, `device_actions_summary`, `has_active_schedule`, etc.) — resource-only, no migration.
- Open questions: `delay_seconds` not applied at job enqueue (pre-existing); optional schedule/vibe ownership defensive check in Phase 3.
- **No runtime code changed** in `back_vibes` or `front_vibes`.

---

## Phase 3 — Scheduler dispatch integration review

| ID | Task | Status | Reference |
| --- | --- | --- | --- |
| P3-1 | Document complete execution flow of `DispatchDueSchedulesCommand` | **Done** | [`dispatch-integration-review.md`](dispatch-integration-review.md) §2 |
| P3-2 | Determine EXACT Smart Home dispatch integration point | **Done** | [`dispatch-integration-review.md`](dispatch-integration-review.md) §3 |
| P3-3 | Review idempotency — SH dispatch only on `'dispatched'` | **Done** | [`dispatch-integration-review.md`](dispatch-integration-review.md) §4 |
| P3-4 | Review ownership guarantees for background execution | **Done** | [`dispatch-integration-review.md`](dispatch-integration-review.md) §5 · [`ADR-026`](../../../decisions/ADR-026-automation-execution-security.md) |
| P3-5 | Review `schedule_executions.log` update strategy | **Done** | [`dispatch-integration-review.md`](dispatch-integration-review.md) §6 |
| P3-6 | Review `VibeSmartHomeDispatchService` reuse from scheduler | **Done** | [`dispatch-integration-review.md`](dispatch-integration-review.md) §7 |

**Branch:** `feature/scheduler-smart-home-dispatch-review`

**Phase 3 implementation notes:**

- Published [`dispatch-integration-review.md`](dispatch-integration-review.md) — full dispatch flow, transaction analysis, integration point, idempotency, ownership, log strategy, Phase 4 blueprint.
- Published [`ADR-026`](../../../decisions/ADR-026-automation-execution-security.md) — background execution security: no Policies in console/queue; domain validation in Phase 4; safe skip semantics; no secret logging.
- Integration point signed off: **`handle()` after commit, when `processSchedule()` returns `'dispatched'`** — not inside transaction.
- Log update signed off: **post-commit merge** of `smart_home` summary into existing JSON.
- **No runtime code changed** in `back_vibes` or `front_vibes`.

---

## Phase 4A — ScheduleAutomationValidator

| ID | Task | Status | Reference |
| --- | --- | --- | --- |
| P4A-1 | Create **`ScheduleAutomationValidator`** + unit tests | **Done** | [`ADR-026`](../../../decisions/ADR-026-automation-execution-security.md) · `back_vibes/app/SmartHome/Validation/ScheduleAutomationValidator.php` |

**Branch:** `feature/schedule-automation-validator` from **`develop`**

**Phase 4A implementation notes:**

- Added `ScheduleAutomationValidator::validate(Schedule): bool` — ownership chain checks per ADR-026; returns `false` for expected failures, never throws.
- Validation order: vibe exists → schedule/vibe user match → each action has device → device user match → provider connection exists → connection user match.
- No logs in validator; no Policy/Gate/auth usage; not wired to dispatcher or `VibeSmartHomeDispatchService` (Phase 4B).
- Pest unit tests in `tests/Unit/SmartHome/ScheduleAutomationValidatorTest.php` — 9 cases including multi-action and zero-action valid paths.

---

## Phase 4 — Backend execution integration (Phase 4B)

| ID | Task | Status | Reference |
| --- | --- | --- | --- |
| P4-1 | Wire `VibeSmartHomeDispatchService` into dispatcher after new execution | **Done** | [`ADR-023`](../../../decisions/ADR-023-automation-execution-order-and-failure-policy.md) |
| P4-2 | Eager-load vibe + device actions in dispatch batch | **Done** | |
| P4-3 | Catch/log enqueue errors — do not fail recurrence | **Done** | [`spec.md`](spec.md) AUTO-4 |
| P4-4 | Optional: append SH summary to `schedule_executions.log` | **Deferred** | [`ADR-024`](../../../decisions/ADR-024-automation-notifications-and-observability.md) |
| P4-5 | Pest: schedule with actions → jobs enqueued | **Done** | |
| P4-6 | Pest: duplicate tick → no double dispatch; no actions → no jobs | **Done** | |

**Branch:** `feature/scheduler-smart-home-dispatch-integration`

**Phase 4B implementation notes:**

- Wired `ScheduleAutomationValidator` + `VibeSmartHomeDispatchService` into `DispatchDueSchedulesCommand::handle()` — post-commit only when `processSchedule()` returns `'dispatched'`.
- Eager-load: `vibe.deviceActions.device.providerConnection` on due schedules query.
- Validator failure: `Log::warning` with `validator_failed: true`, no throw, no push, recurrence already committed.
- Dispatch exception: isolated try/catch with `Log::warning` + `exception_class`; batch continues; no `schedule_execution_failed` push.
- `schedule_executions.log` not modified (deferred).
- Pest integration tests in `DispatchDueSchedulesCommandTest` — 6 Smart Home cases (dispatched, skipped_duplicate, dry-run, validator fail, dispatch exception, multi-schedule isolation).

---

## Phase 5 — Mobile UX surface

| ID | Task | Status | Reference |
| --- | --- | --- | --- |
| P5-1 | Schedules list: badge when vibe has device actions | **Done** | [`ADR-025`](../../../decisions/ADR-025-automation-mobile-ux.md) · `AppAutomationBadge.vue` |
| P5-2 | Schedule form: read-only device action summary | **Done** | [`spec.md`](spec.md) §6 · `ScheduleFormPage.vue` |
| P5-3 | Vibe card: Scheduled / Smart Home / combined badges | **Done** | `VibesPage.vue` · `automation-badges.ts` |
| P5-4 | Helper copy on schedule form and vibe detail | **Done** | `automation-summary.ts` · `EditVibePage.vue` |
| P5-5 | API embeds: `device_actions_count`, `has_device_actions`, `active_schedules_count`, `has_active_schedule` | **Done** | `ScheduleResource.php` · `VibeResource.php` |
| P5-6 | Link from schedule form to vibe Device Actions | **Deferred** | ADR-025 — discovery via vibe detail; no inline link in MVP |

**Branch:** `feature/automation-mobile-ux-surface` — merged to `develop`

---

## Phase 6 — Push/local notification alignment

| ID | Task | Status | Reference |
| --- | --- | --- | --- |
| P6-1 | Verify local notifications unchanged | **Done** | `schedule-notification.service.test.ts` — 19 tests; no change to local path |
| P6-2 | Optional: `schedule_id` in `smart_home_action_failed` payload | **Deferred** | [`ADR-024`](../../../decisions/ADR-024-automation-notifications-and-observability.md) — deferred per spec |
| P6-3 | Mobile tap routing for schedule context | **Done** | `push-notification-handler.service.ts` · UX alignment tests |
| P6-4 | Confirm no success push by default | **Done** | No `automation_completed` event; unit-tested |
| P6-5 | Staging: failure push on SH job failure during scheduled dispatch | **Done** | Automated: `SmartHomeActionJobTest` · `PushNotificationEventsTest` |

**Branch:** `feature/automation-notification-alignment` — merged to `develop`

---

## Phase 7 — QA automation tests

| ID | Task | Status | Reference |
| --- | --- | --- | --- |
| P7-1 | Expand `DispatchDueSchedulesCommandTest` for SH integration | **Done** | 33 Scheduler tests; SH enqueue, validator, isolation |
| P7-2 | Test failure isolation — SH error, recurrence advances | **Done** | `test('Smart Home dispatch exception does not fail scheduler …')` |
| P7-3 | Test idempotency — single dispatch batch per occurrence | **Done** | `test('duplicate tick does not create duplicate execution …')` |
| P7-4 | Queue fake assertions for job count / ids | **Done** | `Bus::assertDispatchedTimes(SmartHomeActionJob::class, …)` |
| P7-5 | CI green on `develop` | **Done** | 710 tests / 2 058 assertions ✅ |

**Branch:** `feature/automation-integration-tests` — merged to `develop`

---

## Phase 8 — Staging + Android E2E QA

| ID | Task | Status | Reference |
| --- | --- | --- | --- |
| P8-1 | Staging: schedule + vibe with HA device actions | **Done** (automated) / ⏸ (on-device) | Automated: 710 BV tests + 309 FV tests ✅ |
| P8-2 | Verify dispatcher tick enqueues jobs | **Done** | 33 Scheduler tests — enqueue assertions ✅ |
| P8-3 | Verify HA device state change (or job success log) | **Pending** | Requires live HA instance — QA-005 |
| P8-4 | Verify local notification on Android device | **Pending** | Requires connected Android device — QA-004 |
| P8-5 | Verify failure path — unreachable HA → push | **Done** | `ProviderConnectionSyncApiTest` — 5xx push path ✅ |
| P8-6 | Publish QA summary | **Done** | [`docs/qa/scheduler-smart-home-e2e/summary.md`](../../../qa/scheduler-smart-home-e2e/summary.md) |

**Branch:** `feature/automation-e2e-qa` — merged to `develop`

**Open items:** QA-004 (on-device Android local reminder) and QA-005 (live HA device state) require a connected device and HA sandbox. All automated coverage complete.

---

When a phase completes, update this file and [`plan.md`](plan.md) — do not mark future phases **Done** until merged and verified.
