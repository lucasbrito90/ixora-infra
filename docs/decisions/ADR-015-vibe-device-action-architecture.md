# ADR-015: Vibe device action architecture

## Status

**Accepted** — governs the **`vibe_device_actions` model** and the relationship between vibes and Smart Home device actions ([`specs/smart-home/mvp/spec.md`](../specs/smart-home/mvp/spec.md)).

## Date

2026-06-14

## Context

Smart Home allows users to associate device actions with vibes so that playing a vibe can trigger physical effects (e.g. turn on a light). The key design question is: **where does the device action list live — on the vibe or on the schedule?**

### Option A: Actions on the schedule

Device actions fire when the scheduler dispatches a schedule. The `schedules` table (or a `schedule_device_actions` pivot) owns the action list.

Problems:

- A user playing a vibe manually would never trigger device actions — only scheduled plays would.
- Actions are scattered: some in vibe, some in schedule. The same vibe played at different times would need to duplicate action configuration.
- Tight coupling between Scheduler MVP and Smart Home — two unrelated features would be co-dependent.

### Option B: Actions on the vibe

Device actions are properties of the vibe. Playing a vibe (manually or via schedule) includes executing the associated device actions. The vibe is the composition unit: audio + visuals + smart home effects.

Benefits:

- Consistent: whether the user taps Play or a schedule fires, the same action list runs.
- Scheduler MVP is unaffected — the dispatcher does not need to know about device actions at all.
- Future Smart Home schedule triggers can be built by extending the vibe execution path, not the scheduler.
- Vibe is already the core product object — extending it is consistent with how sounds and visuals are attached.

### Existing stub analysis

The current `vibe_device_actions` migration (`2026_05_01_000006_create_vibe_device_actions_table.php`) has:

| Column | Stub value | MVP target note |
| --- | --- | --- |
| `id` | bigint PK | Keep |
| `vibe_id` | FK → `vibes` cascade | Keep |
| `device_id` | FK → `devices` cascade | Keep |
| `action_type` | string | Keep — rename values to match MVP enum (`turn_on`, `turn_off`, `toggle`) |
| `parameters` | json nullable | Keep — generic parameters for future actions |
| `delay_seconds` | unsigned small int, default 0 | Keep |
| `created_at` | timestamp | Keep |
| `updated_at` | **missing** | **Add in schema review** |
| `sort_order` | **missing** | **Add** — execution ordering within a vibe |

The stub lacks `sort_order` and `updated_at`. These are noted for the Phase 2 schema review — no changes in Phase 1.

---

## Decision

**Device actions are attached to vibes, not schedules. The action model is generic and extensible. MVP supports `turn_on`, `turn_off`, and `toggle`. Action failure does not block audio playback.**

### Ownership

| Principle | Rule |
| --- | --- |
| **Vibe owns the action list** | `vibe_device_actions` is a collection on the vibe, not the schedule. |
| **Scheduler is unaffected** | The scheduler dispatcher does not invoke device actions in MVP or in any future phase without a new spec. |
| **Play path** | When a vibe plays (manual or scheduled), the mobile client initiates device action execution via the API. |
| **Actions are optional** | A vibe with no device actions behaves identically to today. |

### MVP action types

| Action | Effect |
| --- | --- |
| **`turn_on`** | Switch device on |
| **`turn_off`** | Switch device off |
| **`toggle`** | Toggle device state |

### Future action types (not in MVP)

| Action | Notes |
| --- | --- |
| `set_brightness` | Requires `parameters.brightness` (0–100) |
| `set_color` | Requires `parameters.color` (RGB / HS) |
| `set_temperature` | Requires `parameters.temperature` (Kelvin) |
| `activate_scene` | Requires `parameters.scene_id` |

### Generic parameters model

Actions use a `parameters` JSON field. MVP actions (`turn_on`, `turn_off`, `toggle`) require no parameters — `null` is valid. Future actions define their parameter schema per action type.

This keeps the model open to future extension without schema migrations for new action types.

### Execution ordering

| Field | Role |
| --- | --- |
| `sort_order` | Integer — actions execute in ascending sort order within a vibe. |
| `delay_seconds` | Optional delay before this action fires (already in stub). |

MVP UI: when attaching actions, user can reorder them. Backend stores `sort_order`.

### Failure isolation

| Rule | Rationale |
| --- | --- |
| **Device action failure does not block audio playback** | Audio is the primary experience. A light that fails to turn on must not prevent the vibe from playing. |
| **Failure is logged** | Action execution results are logged (Phase 9 — `ActionExecutionLog` future model). |
| **Partial success is acceptable** | If 3 of 4 actions succeed, 3 lights turn on and audio plays. |
| **No retry in MVP** | Failed actions are logged; retry strategy is a future spec. |

### MVP UI constraints

- Mobile UI for **associating device actions to a vibe** is a later phase — after Device CRUD and HA adapter are working.
- In MVP, `vibe_device_actions` may have zero rows for all vibes (no actions configured yet).
- No complex automations, conditions, or schedules in the action model.

### Vibe device action record (MVP target)

| Field | Type | Description |
| --- | --- | --- |
| `id` | bigint PK | |
| `vibe_id` | FK → `vibes` cascade | Owner vibe |
| `device_id` | FK → `devices` cascade | Target device |
| `action_type` | string | `turn_on \| turn_off \| toggle` (MVP) |
| `parameters` | json nullable | Generic parameters (null for MVP actions) |
| `sort_order` | unsigned int | Execution order within this vibe |
| `delay_seconds` | unsigned small int, default 0 | Delay before action fires |
| `created_at` | timestamp | |
| `updated_at` | timestamp | **Add in schema review** |

---

## Consequences

### Positive

| Outcome | Why it matters |
| --- | --- |
| **Consistent play behaviour** | Manual play and scheduled play trigger the same action list — no duplication of configuration. |
| **Scheduler is decoupled** | Scheduler MVP does not need to know about devices; this ADR does not add complexity to [ADR-011](ADR-011-scheduler-local-notifications-vs-future-fcm.md). |
| **Generic parameters future-proof** | New action types (brightness, color, scene) add values to `action_type` and define their `parameters` schema — no migration per new type. |
| **Audio isolation** | Action failures cannot break the play experience. |

### Negative / tradeoffs

| Tradeoff | Impact |
| --- | --- |
| **Actions run on play, not on schedule** | If user wants different device actions for a vibe at different times of day, they need separate vibes — acceptable for MVP. |
| **`sort_order` missing from stub** | Must be added in schema review — Phase 2. |
| **No retry** | Failed actions are silent failures until `ActionExecutionLog` ships. |
| **No complex automations** | Conditional logic (if temperature > X, then …) is explicitly out of scope — not a tradeoff but a documented non-goal. |

---

## Alternatives Considered

| Alternative | Why not chosen |
| --- | --- |
| **Actions on schedules** | Rejected — manual plays would not trigger actions; duplicates configuration across schedules. |
| **Actions on `vibe_sounds` (per layer)** | Too granular — device actions are vibe-level effects, not layer-level. |
| **Strongly-typed action columns (brightness int, color string, …)** | Rejected — schema migration required per new action type; `parameters` JSON is more flexible. |
| **Conditions / automation engine in MVP** | Explicitly rejected — not a goal for Smart Home Foundation; adds disproportionate complexity. |
| **Client-side action execution** | Rejected — provider credentials live server-side; mobile cannot call HA directly ([ADR-012](ADR-012-smart-home-provider-strategy.md), [ADR-013](ADR-013-home-assistant-first-provider.md)). |

---

## Related Docs

| Document | Relationship |
| --- | --- |
| [`ADR-012`](ADR-012-smart-home-provider-strategy.md) | Provider adapter architecture |
| [`ADR-013`](ADR-013-home-assistant-first-provider.md) | HA adapter — `executeAction()` implementation |
| [`ADR-014`](ADR-014-device-abstraction-and-deduplication.md) | Device identity used in action record |
| [`ADR-016`](ADR-016-smart-home-async-execution.md) | Action execution is async — not in CRUD path |
| [`ADR-011`](ADR-011-scheduler-local-notifications-vs-future-fcm.md) | Scheduler MVP — explicitly excludes device action invocation |
| [`../specs/smart-home/mvp/spec.md`](../specs/smart-home/mvp/spec.md) | Domain model, actions MVP section |
| [`../specs/smart-home/mvp/plan.md`](../specs/smart-home/mvp/plan.md) | Phase 7 — device action association with vibes |
| [`../../specs/vibes/execution-plan/spec.md`](../../specs/vibes/execution-plan/spec.md) | Vibe execution plan — action execution hooks into play path |

---

When `ActionExecutionLog` is ready to ship, create a new ADR for the execution audit model and reference this decision as the action ownership anchor.
