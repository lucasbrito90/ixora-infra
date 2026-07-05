# Scheduler + Smart Home Automations MVP — implementation plan

**Status:** Phase 1 complete — pre-implementation  
**Spec:** [`spec.md`](spec.md)  
**Feature ID:** `scheduler-smart-home-automations/mvp`

---

## Implementation summary

This feature delivers a **user-facing automation experience** by composing shipped Scheduler, Smart Home, and Push Notification foundations — **without** a new automation engine or `automations` table.

**Strategy anchors:**

| Principle | Implementation |
| --- | --- |
| No new automation engine | Schedule + Vibe + VibeDeviceAction ([ADR-022](../../../decisions/ADR-022-scheduler-smart-home-automation-model.md)) |
| Reuse dispatch service | `VibeSmartHomeDispatchService` from scheduler path ([ADR-023](../../../decisions/ADR-023-automation-execution-order-and-failure-policy.md)) |
| Async + failure isolated | Queue jobs; recurrence independent of SH outcome |
| Local notifications preserved | Android reminders unchanged ([ADR-011](../../../decisions/ADR-011-scheduler-local-notifications-vs-future-fcm.md)) |
| Push — failures only | Reuse ADR-019 events ([ADR-024](../../../decisions/ADR-024-automation-notifications-and-observability.md)) |
| Mobile — surfacing only | Badges + summary — no builder ([ADR-025](../../../decisions/ADR-025-automation-mobile-ux.md)) |
| No background autoplay | Client playback only |

**Git Flow:** All work on **`feature/*`** branches from **`develop`** — [`git-flow.md`](../../../standards/git-flow.md). Promote to **`staging`** via merge **`develop` → `staging`**.

---

## Current state

| Area | State |
| --- | --- |
| **Scheduler MVP** | ✅ Shipped — CRUD, dispatcher, local notifications |
| **Smart Home MVP** | ✅ Shipped — devices, vibe actions, `SmartHomeActionJob`, HA adapter |
| **Push Notifications MVP** | ✅ Shipped — tokens, FCM, failure events |
| **Local notifications** | ✅ Shipped — schedule reminders on Android |
| **`VibeSmartHomeDispatchService`** | ✅ Shipped — mobile-triggered via `POST /api/smart-home/dispatch` |
| **Scheduler → Smart Home wiring** | ❌ **Not wired** — dispatcher records execution only |
| **Automation UX surfacing** | ❌ Not implemented |
| **ADRs 022–025** | ✅ Accepted — Phase 1 complete |
| **`automations` table** | ❌ Not planned for MVP |

---

## Phase overview

```
Phase 1  ──► ADRs + Spec (complete)
Phase 2  ──► Backend schema/domain review
Phase 3  ──► Scheduler dispatch integration review
Phase 4  ──► Backend execution integration
Phase 5  ──► Mobile UX surface
Phase 6  ──► Push/local notification alignment
Phase 7  ──► QA automation tests
Phase 8  ──► Staging + Android E2E QA
```

Phases are intentionally small. Phase 2 confirms **no migrations** are required. Phase 3 documents the exact integration point before code changes. Phase 4 is the core backend hook. Phases 5–6 can overlap after Phase 4 API contract is stable.

---

## Phase 1 — ADRs + Spec

**Complete.**

### Deliverables

| Item | Output |
| --- | --- |
| Feature spec | [`spec.md`](spec.md) |
| Implementation plan | [`plan.md`](plan.md) |
| Task checklist | [`tasks.md`](tasks.md) |
| **ADR-022** | [`ADR-022-scheduler-smart-home-automation-model.md`](../../../decisions/ADR-022-scheduler-smart-home-automation-model.md) |
| **ADR-023** | [`ADR-023-automation-execution-order-and-failure-policy.md`](../../../decisions/ADR-023-automation-execution-order-and-failure-policy.md) |
| **ADR-024** | [`ADR-024-automation-notifications-and-observability.md`](../../../decisions/ADR-024-automation-notifications-and-observability.md) |
| **ADR-025** | [`ADR-025-automation-mobile-ux.md`](../../../decisions/ADR-025-automation-mobile-ux.md) |
| Docs index | [`README.md`](../../../README.md) |

### Exit criteria

- ADRs accepted; spec published; **no runtime code** in this phase.

---

## Phase 2 — Backend schema/domain review

**Goal:** Confirm existing schema supports automation composition without new tables.

### Tasks

- Verify `schedules.vibe_id` FK and cascade behaviour.
- Verify `vibe_device_actions` has `sort_order`, indexes, and vibe FK.
- Document whether `schedule_executions.log` JSON is sufficient for dispatch summary.
- Confirm no `automations` table needed for MVP — publish short review note in spec or inline comment in tasks.
- Identify any missing API embed fields for mobile surfacing (counts, summaries).

### Exit criteria

- Written confirmation: **no migrations required for MVP** (or explicit list if gap found).
- Domain review signed off in [`tasks.md`](tasks.md).

---

## Phase 3 — Scheduler dispatch integration review

**Goal:** Document exact integration before modifying `DispatchDueSchedulesCommand`.

### Tasks

- Read current `DispatchDueSchedulesCommand` flow — idempotency, transaction boundaries.
- Map `'dispatched'` vs `'skipped_duplicate'` paths for Smart Home hook placement.
- Confirm `VibeSmartHomeDispatchService` is injectable without circular dependencies.
- Define idempotency rule: dispatch SH **only** on new execution row.
- Document optional `schedule_executions.log` update pattern (post-commit).
- Review interaction with `PushNotificationEvents` on dispatcher failure — no change expected.

### Exit criteria

- Integration design note in PR description or spec appendix.
- Team agreement on post-commit dispatch hook.

---

## Phase 4 — Backend execution integration

**Goal:** Wire scheduler dispatch to Smart Home enqueue.

### Tasks

- Inject `VibeSmartHomeDispatchService` into dispatcher (or dedicated listener/service).
- After successful `'dispatched'` result, call `dispatch($schedule->vibe)`.
- Eager-load vibe + device actions to avoid N+1 in batch.
- Append Smart Home summary to `schedule_executions.log` (optional).
- Ensure enqueue exceptions are caught and logged — do not fail recurrence.
- Pest tests: schedule with device actions → jobs dispatched; duplicate tick → no double dispatch; vibe without actions → no jobs; SH enqueue error → recurrence still advances.

### Branch

`feature/scheduler-smart-home-dispatch-integration`

### Exit criteria

- Feature tests pass in `back_vibes`.
- Manual staging verification: due schedule with HA actions enqueues jobs.

---

## Phase 5 — Mobile UX surface

**Goal:** Surface Schedule ↔ Vibe ↔ Device Actions relationship on existing screens.

### Tasks

- Schedules list: badge when vibe has device actions.
- Schedule form: read-only action summary when vibe selected.
- Vibe card/detail: “Scheduled” / “Smart Home” / combined badges.
- Helper copy per [ADR-025](../../../decisions/ADR-025-automation-mobile-ux.md).
- API: add lightweight embeds if needed (`device_actions_count`, summary array).
- Link from schedule form to vibe Device Actions section (navigation only).

### Branch

`feature/automation-mobile-ux-surface`

### Exit criteria

- Android manual QA checklist passed.
- No new Automations tab or builder.

---

## Phase 6 — Push/local notification alignment

**Goal:** Ensure notification behaviour matches ADR-024.

### Tasks

- Confirm local notifications unchanged after backend integration.
- Optional: add `schedule_id` to `smart_home_action_failed` payload when triggered from scheduler path.
- Mobile tap handler: route to schedule or vibe detail if `schedule_id` present.
- Verify no success push added by default.
- Document any copy changes for failure notifications (“during scheduled automation”).

### Exit criteria

- Failure push fires on SH job failure during scheduled dispatch (staging).
- No regression in local notification scheduling.

---

## Phase 7 — QA automation tests

**Goal:** Automated regression coverage for integration path.

### Tasks

- Expand `DispatchDueSchedulesCommandTest` — Smart Home job assertions.
- Test failure isolation — mock job dispatch failure, assert recurrence advanced.
- Test idempotency — second tick same occurrence, assert single dispatch batch.
- Smart Home job tests — correlation with schedule context in logs.
- CI green on `develop`.

### Exit criteria

- Pest suite covers AUTO-1 through AUTO-12 critical paths.
- No flaky queue assertions — use `Queue::fake()` where appropriate.

---

## Phase 8 — Staging + Android E2E QA

**Goal:** End-to-end validation on staging with real HA (or test harness).

### Tasks

- Create schedule for vibe with device actions on staging.
- Wait for dispatcher tick or trigger manual dispatch-due.
- Verify HA device state change (or job log success).
- Verify local notification still fires on device.
- Verify failure path: unreachable HA → push failure notification.
- Publish QA summary under `docs/qa/` (optional follow-up doc).

### Exit criteria

- E2E checklist complete on Android staging build.
- Known limitations documented (no autoplay, best-effort SH).

---

## Risk register

| Risk | Mitigation |
| --- | --- |
| Double Smart Home dispatch on duplicate ticks | Gate on new `ScheduleExecution` only |
| Dispatcher slowdown | Enqueue only — no provider I/O in command |
| User surprise (lights without audio) | UX copy + schedule form summary |
| HA down during schedule | Failure push; recurrence continues |
| ADR-015 doc drift | Cross-link ADR-022 as superseding scheduler integration |

---

## Related docs

| Document | Relationship |
| --- | --- |
| [`spec.md`](spec.md) | Feature contract |
| [`tasks.md`](tasks.md) | Checklist |
| [`../scheduler/mvp/spec.md`](../../scheduler/mvp/spec.md) | Scheduler foundation |
| [`../smart-home/mvp/spec.md`](../../smart-home/mvp/spec.md) | Smart Home foundation |
| ADRs 022–025 | Architecture decisions |
