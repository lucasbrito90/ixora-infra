# Scheduler + Smart Home Automations MVP — composed time-based automations

**Status:** Active feature specification (Phase 1 — ADRs + Spec)  
**Version:** 1.0 (MVP scope — documentation only; no runtime code in Phase 1)  
**Feature ID:** `scheduler-smart-home-automations/mvp`  
**Platform:** `back_vibes` (authoritative integration), `front_vibes` Android (UX surfacing)

> **Phase 1 = ADRs + Spec only.** No migrations, controllers, scheduler dispatch changes, Smart Home job changes, mobile runtime changes, or push notification runtime changes are part of Phase 1. Implementation begins in Phase 2+ per [`plan.md`](plan.md).

**Architecture decisions:** [ADR-022](../../../decisions/ADR-022-scheduler-smart-home-automation-model.md) (automation model), [ADR-023](../../../decisions/ADR-023-automation-execution-order-and-failure-policy.md) (execution order + failure policy), [ADR-024](../../../decisions/ADR-024-automation-notifications-and-observability.md) (notifications + observability), [ADR-025](../../../decisions/ADR-025-automation-mobile-ux.md) (mobile UX).

**Builds on (shipped):** [Scheduler MVP](../../scheduler/mvp/spec.md), [Smart Home MVP](../../smart-home/mvp/spec.md), [Push Notifications MVP](../../push-notifications/mvp/spec.md), local notifications ([ADR-011](../../../decisions/ADR-011-scheduler-local-notifications-vs-future-fcm.md)).

---

## 1. Product goal

Allow users to combine **time-based scheduling** with **Smart Home actions** already attached to vibes — as one coherent automation-style experience, without building a separate automation engine.

**Example user story:**

> “At 10 PM every night, remind me to open my Sleep vibe **and** turn off the bedroom light.”

**Mental model:**

- User creates a **schedule** for a **vibe**.
- User attaches **device actions** to that vibe (existing Smart Home flow).
- When the schedule is due, IXORA **records the occurrence**, **dispatches Smart Home jobs** server-side, and **reminds the user** via local notification to play the vibe.

Audio remains **user/device-side** — the server does not autoplay audio.

---

## 2. MVP scope

| Capability | MVP |
| --- | --- |
| **Reuse Schedule → Vibe → VibeDeviceAction model** | ✅ No new `automations` table |
| **Scheduler dispatch integration** | ✅ After new `ScheduleExecution`, enqueue Smart Home jobs via existing `VibeSmartHomeDispatchService` |
| **Failure isolation** | ✅ Smart Home / push failures do not block recurrence |
| **Mobile UX surfacing** | ✅ Schedule form summary + vibe/schedule badges — no automation builder |
| **Local notifications** | ✅ Unchanged — schedule reminder path |
| **Push notifications** | ✅ Reuse failure events only — no success push by default |
| **Integration tests** | ✅ Phase 7 — dispatcher + dispatch service wiring |
| **Documentation + QA** | ✅ Phase 8 — staging + Android E2E |

### What ships vs what already exists

| Layer | Already shipped | This feature adds |
| --- | --- | --- |
| Schedule CRUD + dispatcher | ✅ | Hook Smart Home dispatch on new execution |
| Vibe device actions CRUD | ✅ | — |
| `VibeSmartHomeDispatchService` + `SmartHomeActionJob` | ✅ (mobile-triggered) | Same service from scheduler path |
| Local schedule reminders | ✅ | — |
| Push failure events | ✅ | Optional `schedule_id` in SH failure payload |
| Automation builder UI | ❌ | ❌ Not in MVP — surfacing only |

---

## 3. Non-goals

| Non-goal | Reason |
| --- | --- |
| **Background audio autoplay** | Client-only playback; OS constraints ([ADR-007](../../../decisions/ADR-007-execution-plan-runtime-contract.md)) |
| **Standalone automation engine** | Reuse existing objects ([ADR-022](../../../decisions/ADR-022-scheduler-smart-home-automation-model.md)) |
| **`automations` table** | Deferred until conditional/multi-trigger needs justify it |
| **Complex rules engine** | No if/then, no expression evaluator |
| **Conditional triggers** | Temperature, motion, time ranges beyond schedule recurrence |
| **Geofencing** | Out of scope |
| **Sensor triggers** | Out of scope |
| **Scenes** | Future action type — not this phase |
| **Multi-provider expansion** | HA only today — per existing Smart Home scope |
| **Marketing / campaign notifications** | [ADR-019](../../../decisions/ADR-019-notification-event-taxonomy.md) |
| **AI recommendations** | Out of scope |
| **Admin panel automations UI** | Mobile-first |
| **Marketplace** | Out of scope |
| **Success push on every automation run** | Noisy — [ADR-024](../../../decisions/ADR-024-automation-notifications-and-observability.md) |
| **iOS automation-specific UX** | Android-first surfacing; iOS parity follow-up |
| **Schedule-level device action overrides** | Actions stay on vibe |

---

## 4. Domain model

### Current entities (unchanged)

```
User
  → Vibes
  → Schedules (belongs to Vibe)
  → Devices
  → VibeDeviceActions (belongs to Vibe, references Device)
  → ScheduleExecutions (belongs to Schedule)
```

### Automation view (composition, not new table)

```
┌─────────────────┐
│    Schedule     │  WHEN — recurrence, timezone, next_run_at
│    vibe_id ─────┼──►┌─────────────────┐
└────────┬────────┘    │      Vibe       │  WHAT — sounds, visuals
         │             │  device_actions │
         │             └────────┬────────┘
         │                      │
         ▼                      ▼
┌─────────────────┐    ┌─────────────────────┐
│ScheduleExecution│    │ VibeDeviceAction[]  │  SIDE EFFECTS — ordered SH jobs
│  (audit)        │    │ turn_on/off/toggle  │
└─────────────────┘    └─────────────────────┘
```

| Concept | Persistence | Source of truth |
| --- | --- | --- |
| **When** | `schedules` | Scheduler |
| **What (experience)** | `vibes` + `vibe_sounds` | Vibes |
| **Smart Home effects** | `vibe_device_actions` | Smart Home |
| **Occurrence audit** | `schedule_executions` | Scheduler dispatcher |

---

## 5. Backend behaviour proposal

### Current state (pre-integration)

`schedules:dispatch-due` ([`DispatchDueSchedulesCommand`](../../../../back_vibes/app/Console/Commands/DispatchDueSchedulesCommand.php)):

1. Finds due schedules (`next_run_at <= now UTC`).
2. Creates `ScheduleExecution` idempotently.
3. Advances `next_run_at` / disables `once` schedules.
4. On transaction failure → `schedule_execution_failed` push.
5. **Does not** call `VibeSmartHomeDispatchService`.

Smart Home dispatch today is triggered by mobile:

- `POST /api/smart-home/dispatch` with `vibe_id` → `VibeSmartHomeDispatchService::dispatch()`.

### Target behaviour (implementation phase — Phase 4)

When a schedule is due and execution row is **newly created**:

```
1. DB transaction (existing):
     - INSERT schedule_executions (occurrence_key unique)
     - UPDATE schedules.next_run_at, last_run_at, is_enabled

2. After commit, if result === 'dispatched':
     - Load schedule.vibe with device actions
     - If vibe has resolvable VibeDeviceActions:
         VibeSmartHomeDispatchService.dispatch(vibe)
     - Optionally UPDATE schedule_executions.log with dispatch summary

3. SmartHomeActionJob(s) run async on queue worker (existing)

4. Job failure → smart_home_action_failed push (existing)
     - Optional: include schedule_id in payload
```

| Requirement | Detail |
| --- | --- |
| **Preserve recurrence logic** | Unchanged — `RecurrenceService` |
| **Preserve idempotency** | Smart Home dispatch only on new execution — skip on duplicate tick |
| **Preserve failure isolation** | Enqueue failures logged; do not roll back execution |
| **No inline provider calls** | [ADR-016](../../../decisions/ADR-016-smart-home-async-execution.md) |
| **No blocking dispatcher** | Enqueue only — same as mobile path |

### Implementation note

**If current Scheduler only logs schedule execution and does not dispatch vibe Smart Home actions, wiring `VibeSmartHomeDispatchService` into the dispatcher is explicitly Phase 4** — see [`plan.md`](plan.md).

---

## 6. Mobile behaviour proposal

See [ADR-025](../../../decisions/ADR-025-automation-mobile-ux.md).

| Surface | Behaviour |
| --- | --- |
| **Schedules list** | Show indicator when selected vibe has device actions |
| **Schedule form** | Read-only device action summary for selected vibe |
| **Vibe card / detail** | Badges: “Scheduled”, “Smart Home”, or combined |
| **Device Actions screen** | Unchanged — sole edit surface for actions |

**No new Automations tab.** **No inline action editing on schedule form.**

Optional API embeds (Phase 5):

- `device_actions_count`, `device_actions_summary` on schedule resources.
- `has_active_schedule`, `schedules_count` on vibe resources.

---

## 7. Notifications

| Channel | MVP behaviour |
| --- | --- |
| **Local notification** | Schedule due reminder — **unchanged** ([ADR-011](../../../decisions/ADR-011-scheduler-local-notifications-vs-future-fcm.md)) |
| **Push — schedule_execution_failed** | Dispatcher transaction failure — **existing** |
| **Push — smart_home_action_failed** | Job failure during schedule-triggered dispatch — **existing**; optional `schedule_id` |
| **Push — smart_home_provider_unreachable** | Provider down — **existing** |
| **Push — success / automation_completed** | **Not sent by default** |
| **Push — automation_due** | **Deferred** — local notifications sufficient |

Observability: `schedule_executions` + worker logs; future `action_execution_logs` deferred ([ADR-024](../../../decisions/ADR-024-automation-notifications-and-observability.md)).

---

## 8. Functional requirements

| ID | Requirement |
| --- | --- |
| AUTO-1 | No new `automations` table or automation engine in MVP |
| AUTO-2 | Scheduled Smart Home dispatch uses **`VibeSmartHomeDispatchService`** — same as manual dispatch |
| AUTO-3 | Smart Home dispatch runs **only** when `ScheduleExecution` is newly created (not duplicate tick) |
| AUTO-4 | Smart Home failure **must not** prevent `next_run_at` advance |
| AUTO-5 | One action failure **must not** block other actions in same occurrence |
| AUTO-6 | Push failure **must not** block scheduler or Smart Home enqueue |
| AUTO-7 | **No server-side audio playback** or background autoplay |
| AUTO-8 | Local notification behaviour **unchanged** |
| AUTO-9 | Mobile surfaces Schedule ↔ Vibe ↔ Device Actions relationship |
| AUTO-10 | Integration tests cover dispatcher + Smart Home enqueue path |
| AUTO-11 | `schedule_executions.log` may record Smart Home dispatch summary |
| AUTO-12 | All existing Scheduler and Smart Home authorization rules preserved |

---

## 9. Acceptance criteria

### Phase 1 (this document)

- [x] `spec.md` published
- [x] `plan.md` published
- [x] `tasks.md` published
- [x] ADR-022 — Automation model — accepted
- [x] ADR-023 — Execution order and failure policy — accepted
- [x] ADR-024 — Notifications and observability — accepted
- [x] ADR-025 — Mobile UX — accepted
- [x] `docs/README.md` updated
- [x] **No runtime code changed** in Phase 1

### Phase 2+ (implementation)

See [`tasks.md`](tasks.md) — backend integration, mobile surfacing, QA.

---

## 10. Delivery phases (reference)

| Phase | Deliverable |
| --- | --- |
| **1** | ADRs + Spec (this phase) |
| **2** | Backend schema/domain review — confirm no new tables required |
| **3** | Scheduler dispatch integration review — gap analysis vs current command |
| **4** | Backend execution integration — wire `VibeSmartHomeDispatchService` |
| **5** | Mobile UX surface — badges + schedule form summary |
| **6** | Push/local notification alignment — payload extensions if needed |
| **7** | QA automation tests — Pest integration tests |
| **8** | Staging + Android E2E QA |

See [`plan.md`](plan.md) and [`tasks.md`](tasks.md).

---

## Related docs

| Document | Relationship |
| --- | --- |
| **ADR-022** — Automation model | [`decisions/ADR-022-scheduler-smart-home-automation-model.md`](../../../decisions/ADR-022-scheduler-smart-home-automation-model.md) |
| **ADR-023** — Execution order | [`decisions/ADR-023-automation-execution-order-and-failure-policy.md`](../../../decisions/ADR-023-automation-execution-order-and-failure-policy.md) |
| **ADR-024** — Notifications | [`decisions/ADR-024-automation-notifications-and-observability.md`](../../../decisions/ADR-024-automation-notifications-and-observability.md) |
| **ADR-025** — Mobile UX | [`decisions/ADR-025-automation-mobile-ux.md`](../../../decisions/ADR-025-automation-mobile-ux.md) |
| **Scheduler MVP** | [`specs/scheduler/mvp/spec.md`](../../scheduler/mvp/spec.md) |
| **Smart Home MVP** | [`specs/smart-home/mvp/spec.md`](../../smart-home/mvp/spec.md) |
| **Push Notifications MVP** | [`specs/push-notifications/mvp/spec.md`](../../push-notifications/mvp/spec.md) |
| **ADR-015** — Vibe device actions | [`decisions/ADR-015-vibe-device-action-architecture.md`](../../../decisions/ADR-015-vibe-device-action-architecture.md) |
| **ADR-016** — Async execution | [`decisions/ADR-016-smart-home-async-execution.md`](../../../decisions/ADR-016-smart-home-async-execution.md) |
| **Plan / tasks** | [`plan.md`](plan.md), [`tasks.md`](tasks.md) |

### Runtime reference (existing — not modified in Phase 1)

| Artifact | Path |
| --- | --- |
| Dispatcher command | `back_vibes/app/Console/Commands/DispatchDueSchedulesCommand.php` |
| Smart Home dispatch service | `back_vibes/app/SmartHome/Services/VibeSmartHomeDispatchService.php` |
| Smart Home action job | `back_vibes/app/Jobs/SmartHome/SmartHomeActionJob.php` |

When behaviour changes, update **this file first**, then ADRs, [`plan.md`](plan.md), and [`tasks.md`](tasks.md).
