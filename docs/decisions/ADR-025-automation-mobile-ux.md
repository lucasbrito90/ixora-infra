# ADR-025: Automation mobile UX

## Status

**Accepted** — governs **mobile UX scope** for Scheduler + Smart Home automations ([`specs/scheduler-smart-home-automations/mvp/spec.md`](../specs/scheduler-smart-home-automations/mvp/spec.md)).

## Date

2026-06-28

## Context

Users can already manage schedules, vibes, and vibe device actions on separate screens. The automation feature does not introduce a new domain object — it composes existing ones ([ADR-022](ADR-022-scheduler-smart-home-automation-model.md)).

The UX question: should MVP ship a **dedicated Automations tab / builder**, or **surface the relationship** on existing screens so users understand “schedule runs vibe, vibe includes device actions”?

### User confusion risks

| Risk | Mitigation |
| --- | --- |
| User schedules vibe but does not know lights will turn on | Show device action summary on schedule form |
| User adds device actions but does not know schedule exists | Show schedule + action badges on vibe card/detail |
| User expects a separate “Automations” product area | Copy explains composition; no false tab promise in MVP |

---

## Decision

**MVP does not ship a complex automation builder or dedicated Automations tab. UX reuses existing Schedules, Vibes, and Device Actions screens with lightweight surfacing of the Schedule → Vibe → VibeDeviceAction relationship.**

### MVP screen reuse

| Screen | Existing purpose | Automation addition |
| --- | --- | --- |
| **Schedules list** | List user schedules | Badge or subtitle when linked vibe has device actions — e.g. “+ Smart Home” |
| **Schedule form (create/edit)** | Pick vibe, recurrence, timezone | When vibe selected, show **read-only summary** of that vibe’s device actions (count, device names, action types) |
| **Vibes list / card** | Browse vibes | Badge when vibe has **both** an active schedule and device actions — e.g. “Scheduled · Smart Home” |
| **Vibe detail** | Edit vibe metadata, sounds | Existing Device Actions section unchanged — primary edit surface for actions |
| **Device Actions (on vibe)** | Attach/reorder actions | No change to edit flow — remains authoritative for action configuration |

### Schedule form — device action summary (read-only)

When user selects a `vibe_id` on schedule create/edit:

- Fetch or use cached vibe device actions (from vibe detail API or embedded resource).
- Display compact list: e.g. “Turn off Bedroom Light · Toggle Desk Lamp (2 actions)”.
- If zero actions: “No Smart Home actions — schedule will only remind you to play this vibe.”
- **No inline action editing on schedule form** — link to vibe Device Actions section if user wants to add actions.

### Vibe card / detail — automation badges

| Condition | Badge / label |
| --- | --- |
| Vibe has ≥1 active schedule | “Scheduled” (or schedule count) |
| Vibe has ≥1 device action | “Smart Home” (or action count) |
| Both | “Scheduled + Smart Home” |

Badges are **informational** — not interactive automation controls.

### Copy / mental model (recommended strings)

- Schedule form helper: “At the scheduled time, IXORA will run this vibe’s Smart Home actions and remind you to play.”
- Vibe detail: “Device actions run when you play this vibe or when a schedule triggers it.”

### Explicit non-goals (mobile MVP)

| Non-goal | Reason |
| --- | --- |
| **Dedicated Automations tab** | No new entity — deferred until rules engine exists |
| **Visual automation builder (nodes/triggers)** | Scope — future |
| **Conditional triggers (if/then)** | Out of MVP |
| **Scenes picker** | Future action type |
| **Multi-step automation wizard** | Surfaces on existing forms sufficient |
| **Inline action editing on schedule screen** | Actions stay vibe-scoped ([ADR-022](ADR-022-scheduler-smart-home-automation-model.md)) |
| **Automation history screen** | No `action_execution_logs` UI in MVP |

### Future UX (documented, not MVP)

When product adds conditional automations or a dedicated engine:

- **Automations tab** — list composed and conditional rules
- **Automation builder** — trigger + conditions + actions
- **Scene integration** — pick HA scenes as actions
- **Multi-step flows** — ordered steps beyond vibe bundle
- **If/then logic** — sensor/time/geofence triggers

Any dedicated tab requires a new spec phase and likely ADR for the `automations` entity.

### API / data requirements (surfacing only)

Mobile surfacing may require backend to expose:

| Field / embed | Purpose |
| --- | --- |
| `vibe.device_actions_count` on schedule resource | List badge without N+1 |
| `vibe.device_actions_summary[]` on schedule show/form | Read-only summary (name, action_type) |
| `vibe.schedules_count` or `has_active_schedule` on vibe resource | Vibe card badge |
| Existing `GET /api/vibes/{id}/device-actions` | Detail screen — already ships |

Exact API shape is an implementation-phase deliverable — not Phase 1.

---

## Consequences

### Positive

| Outcome | Why it matters |
| --- | --- |
| **Small mobile diff** | Badges + summary components — no new navigation tree |
| **Consistent edit flows** | Actions edited in one place (vibe Device Actions) |
| **Honest product language** | Users learn composition model without fake “Automations” product |

### Negative / tradeoffs

| Tradeoff | Impact |
| --- | --- |
| **Discoverability** | Users may not find Smart Home + Schedule connection without badges/copy |
| **No single “my automations” view** | Power users may want unified list — future tab |
| **Extra API fields** | Schedule/vibe resources may need lightweight embeds |

---

## Alternatives Considered

| Alternative | Why not chosen |
| --- | --- |
| **New Automations tab in MVP** | Implies new entity; over-scoped for composition-only feature |
| **Schedule-level action picker** | Violates ADR-015 / ADR-022 — duplicates vibe configuration |
| **Hidden integration (no UI)** | Users surprised when lights turn on — bad UX |
| **Full IFTTT-style builder** | Disproportionate engineering for time + vibe + actions MVP |

---

## Related Docs

| Document | Relationship |
| --- | --- |
| [`ADR-015`](ADR-015-vibe-device-action-architecture.md) | Device Actions on vibe detail |
| [`ADR-022`](ADR-022-scheduler-smart-home-automation-model.md) | Composition model |
| [`../specs/scheduler/mvp/spec.md`](../specs/scheduler/mvp/spec.md) | Schedules screens |
| [`../specs/smart-home/mvp/spec.md`](../specs/smart-home/mvp/spec.md) | Device Actions UI |
| [`../specs/scheduler-smart-home-automations/mvp/spec.md`](../specs/scheduler-smart-home-automations/mvp/spec.md) | Feature spec |

---

When a dedicated Automations tab is scoped, create a new ADR for navigation IA and reference this decision as the MVP surfacing baseline.
