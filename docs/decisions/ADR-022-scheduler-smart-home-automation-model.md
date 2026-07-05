# ADR-022: Scheduler + Smart Home automation model

## Status

**Accepted** — governs the **MVP automation composition model** ([`specs/scheduler-smart-home-automations/mvp/spec.md`](../specs/scheduler-smart-home-automations/mvp/spec.md)).

## Date

2026-06-28

## Context

Ixora already ships three independent foundations:

| Area | State | Key artifacts |
| --- | --- | --- |
| **Scheduler MVP** | Shipped | `schedules`, `schedule_executions`, `schedules:dispatch-due`, local notifications |
| **Smart Home MVP** | Shipped | `devices`, `vibe_device_actions`, `SmartHomeActionJob`, Home Assistant adapter |
| **Push Notifications MVP** | Shipped | `push_tokens`, `PushNotificationJob`, operational event taxonomy |

Users can schedule vibes and attach Smart Home actions to vibes, but the experience is **fragmented**: schedules remind users to play a vibe; device actions fire when the mobile client explicitly dispatches them via the vibe play path. There is no unified **automation-style** product surface that communicates “at this time, run this vibe experience including its device actions.”

The team must decide whether to introduce a new **Automation engine** (new table, rules engine, triggers) or **compose existing domain objects** into a user-facing automation experience.

### Prior decisions (constraints)

[ADR-015](ADR-015-vibe-device-action-architecture.md) established that **device actions attach to vibes, not schedules**. [ADR-016](ADR-016-smart-home-async-execution.md) established **async queue-backed execution** and that the scheduler dispatch loop must not block on provider calls. [ADR-011](ADR-011-scheduler-local-notifications-vs-future-fcm.md) established **local notifications as reminders**, not guaranteed server-side playback.

This ADR **does not replace** those foundations. It defines how they **compose** for scheduled automations without a new automation engine.

### Option A: New `automations` table + rules engine

A dedicated `automations` entity with triggers, conditions, and actions. Schedules and vibe actions become inputs to a generic automation runtime.

Problems:

- Duplicates recurrence logic already owned by `Schedule` + `RecurrenceService`.
- Duplicates Smart Home action lists already owned by `vibe_device_actions`.
- Introduces a rules engine scope (if/then, sensors, geofencing) the product does not need in MVP.
- Requires migration, new API surface, and a new execution path parallel to existing scheduler and smart-home jobs.

### Option B: Compose Schedule + Vibe + VibeDeviceAction (recommended)

A **scheduled automation** is not a new entity — it is the **existing relationship**:

```
Schedule
  → belongs to Vibe
  → Vibe has sounds (audio experience)
  → Vibe has device actions (Smart Home side effects)
```

When a schedule is due, the platform records the occurrence and **dispatches the vibe’s device actions** through the existing async Smart Home path. Audio playback remains **client-side** (local notification → user opens app → play).

Benefits:

- **Schedule** remains the time/recurrence source of truth ([ADR-009](ADR-009-scheduler-timezone-utc-storage.md), [ADR-010](ADR-010-scheduler-idempotency-occurrence-key.md)).
- **Vibe** remains the experience/action bundle ([ADR-015](ADR-015-vibe-device-action-architecture.md)).
- **VibeDeviceAction** remains the Smart Home action list — ordered, generic parameters, async execution ([ADR-016](ADR-016-smart-home-async-execution.md)).
- No duplicate scheduler logic; no duplicate action dispatch logic.
- Manual play and scheduled dispatch can share **`VibeSmartHomeDispatchService`** (already ships for mobile-triggered dispatch).

---

## Decision

**MVP does not create a standalone automation engine or `automations` table. A scheduled automation is the composition of an existing `Schedule` pointing at a `Vibe` that may have `VibeDeviceAction` rows. The scheduler dispatch path gains a thin integration hook to enqueue Smart Home jobs after recording `schedule_executions`; no new domain entity is introduced.**

### Composition model

| Object | Role in automation |
| --- | --- |
| **`Schedule`** | **When** — recurrence, timezone, `next_run_at`, enabled flag |
| **`Vibe`** | **What** — audio layers, visuals, optional Smart Home action bundle |
| **`VibeDeviceAction`** | **Side effects** — ordered device commands (`turn_on`, `turn_off`, `toggle`) |
| **`ScheduleExecution`** | **Audit** — idempotent occurrence record per dispatch tick |

### User-facing mental model

> “My schedule runs my vibe. My vibe includes Smart Home actions. When the schedule fires, IXORA turns on my lights and reminds me to play the vibe.”

No separate “Automation” object is shown in MVP UI — the connection is **surfaced** on existing Schedules and Vibes screens ([ADR-025](ADR-025-automation-mobile-ux.md)).

### What changes vs prior ADRs

| Prior statement | This ADR |
| --- | --- |
| ADR-015: “Scheduler dispatcher does not invoke device actions” | **Superseded for this feature** — scheduler dispatch **may** call existing `VibeSmartHomeDispatchService` after execution record, without moving actions to the schedule row |
| ADR-016: “Device actions initiated from vibe play path, not scheduler tick” | **Extended** — scheduler tick **delegates** to the same dispatch service; still async via queue, still non-blocking |

### MVP exclusions

| Exclusion | Rationale |
| --- | --- |
| **`automations` table** | No new persistence until conditional/multi-trigger flows justify it |
| **Rules engine** | No if/then, sensors, geofencing, scenes |
| **Schedule-scoped actions** | Actions stay on vibe — one vibe, one action list, consistent for manual and scheduled play |
| **Server-side audio playback** | Unchanged — client-only execution plan ([ADR-007](ADR-007-execution-plan-runtime-contract.md)) |

### Future: when a dedicated `automations` table may be justified

Consider a separate automation entity when the product needs:

- **Conditional automations** — if temperature > X, then …
- **Multi-trigger rules** — schedule OR sensor OR geofence
- **Scenes** — HA scene activation as first-class automation
- **Non-vibe automations** — device-only flows without an associated vibe
- **Cross-vibe orchestration** — multi-step automations spanning several vibes

Any future `automations` table must **reference or wrap** existing `Schedule` / `Vibe` / `VibeDeviceAction` where possible — not duplicate their logic.

---

## Consequences

### Positive

| Outcome | Why it matters |
| --- | --- |
| **Minimal new surface area** | Reuses shipped scheduler, smart home, and push infrastructure |
| **Consistent action list** | Same vibe actions whether user taps Play or schedule fires |
| **Clear ownership boundaries** | Time on schedule; experience on vibe; side effects on vibe_device_actions |
| **Incremental delivery** | Integration hook in dispatcher + mobile UX surfacing — no greenfield engine |

### Negative / tradeoffs

| Tradeoff | Impact |
| --- | --- |
| **No per-schedule action overrides** | User who wants different lights at 7 AM vs 10 PM for the same vibe needs two vibes — acceptable for MVP |
| **“Automation” is implicit** | Product language must explain the Schedule → Vibe → Actions chain on existing screens |
| **ADR-015 wording update needed in docs** | Cross-links must note scheduler integration is now specified in this ADR + spec |

---

## Alternatives Considered

| Alternative | Why not chosen |
| --- | --- |
| **New `automations` table in MVP** | Over-engineering — duplicates schedule recurrence and vibe action lists |
| **Actions on schedule row** | Rejected in ADR-015 — manual play would not trigger same actions; duplicates configuration |
| **Client-only scheduled Smart Home dispatch** | Rejected — requires app foreground; server-side dispatch works when device is offline |
| **Unified automation builder UI in MVP** | Deferred — surfacing on existing screens sufficient ([ADR-025](ADR-025-automation-mobile-ux.md)) |

---

## Related Docs

| Document | Relationship |
| --- | --- |
| [`ADR-009`](ADR-009-scheduler-timezone-utc-storage.md) | Schedule timezone + UTC storage |
| [`ADR-010`](ADR-010-scheduler-idempotency-occurrence-key.md) | Schedule execution idempotency |
| [`ADR-011`](ADR-011-scheduler-local-notifications-vs-future-fcm.md) | Local notifications — unchanged |
| [`ADR-015`](ADR-015-vibe-device-action-architecture.md) | Vibe owns actions — foundation retained |
| [`ADR-016`](ADR-016-smart-home-async-execution.md) | Async execution — foundation retained |
| [`ADR-023`](ADR-023-automation-execution-order-and-failure-policy.md) | Execution order and failure isolation |
| [`ADR-025`](ADR-025-automation-mobile-ux.md) | Mobile surfacing — no automation builder |
| [`../specs/scheduler/mvp/spec.md`](../specs/scheduler/mvp/spec.md) | Scheduler MVP — dispatch behaviour |
| [`../specs/smart-home/mvp/spec.md`](../specs/smart-home/mvp/spec.md) | Smart Home MVP — action model |
| [`../specs/scheduler-smart-home-automations/mvp/spec.md`](../specs/scheduler-smart-home-automations/mvp/spec.md) | Feature spec |

---

When conditional automations or a dedicated `automations` table is proposed, create a new ADR and reference this decision as the MVP composition baseline.
