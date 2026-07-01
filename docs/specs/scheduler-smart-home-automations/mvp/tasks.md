# Scheduler + Smart Home Automations MVP — task checklist

**Status:** Phase 3 complete — pre-implementation  
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
| 4 — Backend execution integration | 6 | 0 | 0 | 0 |
| 5 — Mobile UX surface | 6 | 0 | 0 | 0 |
| 6 — Push/local alignment | 5 | 0 | 0 | 0 |
| 7 — QA automation tests | 5 | 0 | 0 | 0 |
| 8 — Staging + Android E2E QA | 6 | 0 | 0 | 0 |

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

## Phase 4 — Backend execution integration

| ID | Task | Status | Reference |
| --- | --- | --- | --- |
| P4-1 | Wire `VibeSmartHomeDispatchService` into dispatcher after new execution | **Pending** | [`ADR-023`](../../../decisions/ADR-023-automation-execution-order-and-failure-policy.md) |
| P4-2 | Eager-load vibe + device actions in dispatch batch | **Pending** | |
| P4-3 | Catch/log enqueue errors — do not fail recurrence | **Pending** | [`spec.md`](spec.md) AUTO-4 |
| P4-4 | Optional: append SH summary to `schedule_executions.log` | **Pending** | [`ADR-024`](../../../decisions/ADR-024-automation-notifications-and-observability.md) |
| P4-5 | Pest: schedule with actions → jobs enqueued | **Pending** | |
| P4-6 | Pest: duplicate tick → no double dispatch; no actions → no jobs | **Pending** | |

**Branch:** `feature/scheduler-smart-home-dispatch-integration`

---

## Phase 5 — Mobile UX surface

| ID | Task | Status | Reference |
| --- | --- | --- | --- |
| P5-1 | Schedules list: badge when vibe has device actions | **Pending** | [`ADR-025`](../../../decisions/ADR-025-automation-mobile-ux.md) |
| P5-2 | Schedule form: read-only device action summary | **Pending** | [`spec.md`](spec.md) §6 |
| P5-3 | Vibe card: Scheduled / Smart Home / combined badges | **Pending** | |
| P5-4 | Helper copy on schedule form and vibe detail | **Pending** | |
| P5-5 | API embeds: `device_actions_count`, summary (if needed) | **Pending** | |
| P5-6 | Link from schedule form to vibe Device Actions | **Pending** | |

**Branch:** `feature/automation-mobile-ux-surface`

---

## Phase 6 — Push/local notification alignment

| ID | Task | Status | Reference |
| --- | --- | --- | --- |
| P6-1 | Verify local notifications unchanged | **Pending** | [`ADR-011`](../../../decisions/ADR-011-scheduler-local-notifications-vs-future-fcm.md) |
| P6-2 | Optional: `schedule_id` in `smart_home_action_failed` payload | **Pending** | [`ADR-024`](../../../decisions/ADR-024-automation-notifications-and-observability.md) |
| P6-3 | Mobile tap routing for schedule context | **Pending** | |
| P6-4 | Confirm no success push by default | **Pending** | |
| P6-5 | Staging: failure push on SH job failure during scheduled dispatch | **Pending** | |

**Branch:** `feature/automation-notification-alignment`

---

## Phase 7 — QA automation tests

| ID | Task | Status | Reference |
| --- | --- | --- | --- |
| P7-1 | Expand `DispatchDueSchedulesCommandTest` for SH integration | **Pending** | |
| P7-2 | Test failure isolation — SH error, recurrence advances | **Pending** | AUTO-4 |
| P7-3 | Test idempotency — single dispatch batch per occurrence | **Pending** | AUTO-3 |
| P7-4 | Queue fake assertions for job count / ids | **Pending** | |
| P7-5 | CI green on `develop` | **Pending** | |

**Branch:** `feature/automation-integration-tests`

---

## Phase 8 — Staging + Android E2E QA

| ID | Task | Status | Reference |
| --- | --- | --- | --- |
| P8-1 | Staging: schedule + vibe with HA device actions | **Pending** | |
| P8-2 | Verify dispatcher tick enqueues jobs | **Pending** | |
| P8-3 | Verify HA device state change (or job success log) | **Pending** | |
| P8-4 | Verify local notification on Android device | **Pending** | |
| P8-5 | Verify failure path — unreachable HA → push | **Pending** | |
| P8-6 | Publish QA summary (optional `docs/qa/` doc) | **Pending** | |

**Branch:** `feature/automation-e2e-qa`

---

When a phase completes, update this file and [`plan.md`](plan.md) — do not mark future phases **Done** until merged and verified.
