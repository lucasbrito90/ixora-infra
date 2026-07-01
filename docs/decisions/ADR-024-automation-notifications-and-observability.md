# ADR-024: Automation notifications and observability

## Status

**Accepted** — governs **notification events and observability** for Scheduler + Smart Home automations ([`specs/scheduler-smart-home-automations/mvp/spec.md`](../specs/scheduler-smart-home-automations/mvp/spec.md)).

## Date

2026-06-28

## Context

Scheduled automations combine scheduler ticks, Smart Home job execution, local reminders, and optional push notifications. The product must avoid **notification fatigue** while giving users actionable alerts when something fails.

Existing infrastructure:

| Layer | Artifact | Role |
| --- | --- | --- |
| **Local notifications** | Android Capacitor plugin | Schedule due reminders — offline-capable ([ADR-011](ADR-011-scheduler-local-notifications-vs-future-fcm.md)) |
| **Push notifications** | `PushNotificationJob`, FCM | Operational failure alerts ([ADR-017](ADR-017-push-notification-provider-strategy.md)–[ADR-021](ADR-021-notification-security-and-privacy.md)) |
| **Event taxonomy** | [ADR-019](ADR-019-notification-event-taxonomy.md) | `schedule_execution_failed`, `smart_home_action_failed`, `smart_home_provider_unreachable` |
| **Execution audit** | `schedule_executions` | Per-occurrence dispatcher record |
| **Smart Home logs** | Structured job logs | Worker stdout / application log channel |

The team must decide which events to emit for automations, whether to introduce automation-specific event types, and where observability data lives.

---

## Decision

**MVP reuses existing notification events where possible. Do not emit success push notifications by default. Local notifications remain the schedule reminder path. Observability stays in `schedule_executions` and Smart Home structured logs; a future `action_execution_logs` table may be added later. Push is best-effort only and must never block automation execution.**

### Notification strategy (MVP)

| Channel | When | Default in MVP |
| --- | --- | --- |
| **Local notification** | Schedule due — remind user to open vibe | ✅ **Unchanged** — primary reminder |
| **Push — failure** | Dispatcher failure, Smart Home action failure, provider unreachable | ✅ **Reuse existing events** |
| **Push — success** | “Automation completed”, “Lights turned on” | ❌ **Not sent by default** — noisy |
| **Push — due reminder** | Remote `schedule_due` complement to local | ❌ **Deferred** — local notifications sufficient |

### Event reuse (preferred over new types)

| Existing event ([ADR-019](ADR-019-notification-event-taxonomy.md)) | Automation context |
| --- | --- |
| **`schedule_execution_failed`** | Dispatcher transaction failed — recurrence did not advance |
| **`smart_home_action_failed`** | `SmartHomeActionJob` failed during schedule-triggered dispatch |
| **`smart_home_provider_unreachable`** | Provider down during scheduled action batch |

**Do not require new event types for MVP integration** — automation context is implied by `schedule_id` + `vibe_id` in payload when available.

### Deferred / future event types

| Proposed type | Status | Notes |
| --- | --- | --- |
| **`automation_due`** | **Deferred** | Overlaps `schedule_due`; local notifications cover MVP |
| **`automation_smart_home_action_failed`** | **Deferred** | Use `smart_home_action_failed` unless payload needs schedule context |
| **`automation_completed`** | **Deferred / likely never default-on** | Success noise — opt-in future setting only |
| **`automation_failed`** | **Deferred** | Aggregate failure — use specific events above |

If schedule context is required in push payload for Smart Home failures triggered by scheduler, **extend** `smart_home_action_failed` payload with optional `schedule_id` — do not fork a parallel event type unless mobile routing requires it.

### Payload extension (optional, implementation phase)

```json
{
  "type": "smart_home_action_failed",
  "vibe_id": 45,
  "device_id": 9,
  "schedule_id": 123
}
```

Follow [ADR-021](ADR-021-notification-security-and-privacy.md) — IDs only, no secrets, minimal PII.

### Observability

| Data | Location | MVP |
| --- | --- | --- |
| **Schedule occurrence audit** | `schedule_executions` | ✅ Primary automation audit |
| **Recurrence state** | `schedules.next_run_at`, `last_run_at` | ✅ |
| **Smart Home dispatch summary** | Optional JSON in `schedule_executions.log` | ✅ Recommended — `dispatched`, `skipped`, `action_ids` |
| **Smart Home job outcome** | Application / worker structured logs | ✅ Existing |
| **`action_execution_logs` table** | Per-action audit row | ❌ **Future** — not MVP |
| **Admin automation dashboard** | ixora-admin | ❌ Out of scope |

### Logging recommendations (implementation phase)

When scheduler integrates Smart Home dispatch, append to `ScheduleExecution.log`:

```json
{
  "command": "schedules:dispatch-due",
  "smart_home": {
    "dispatched": 2,
    "skipped": 0,
    "action_ids": [10, 11]
  }
}
```

Job-level failures continue to log in `SmartHomeActionJob` with `vibe_device_action_id` — correlate via `action_ids` in execution log.

### Push delivery semantics

Unchanged from [ADR-020](ADR-020-push-delivery-and-fallback-strategy.md):

- Async `PushNotificationJob`
- Failure logged, not propagated
- Scheduler and Smart Home completion **never waits** on FCM

---

## Consequences

### Positive

| Outcome | Why it matters |
| --- | --- |
| **No event taxonomy sprawl** | Reuses ADR-019 vocabulary |
| **Quiet success path** | Users are not pinged every time lights turn on |
| **Existing mobile handlers** | Failure tap routing may already exist |
| **Clear audit trail** | `schedule_executions` + logs sufficient for MVP QA |

### Negative / tradeoffs

| Tradeoff | Impact |
| --- | --- |
| **No push confirmation of success** | User must observe device state or check app later |
| **Limited per-action history in DB** | Debugging relies on logs until `action_execution_logs` |
| **Schedule context in SH failure push** | May need payload extension — minor mobile handler update |

---

## Alternatives Considered

| Alternative | Why not chosen |
| --- | --- |
| **New `automation_*` event namespace in MVP** | Duplicates ADR-019 events; more mobile routing code |
| **Success push on every schedule fire** | Notification fatigue; local reminder already exists |
| **Replace local with FCM due reminders** | Worse offline behaviour; violates ADR-011 complement model |
| **`action_execution_logs` in MVP** | Scope creep — logs sufficient for first integration |

---

## Related Docs

| Document | Relationship |
| --- | --- |
| [`ADR-011`](ADR-011-scheduler-local-notifications-vs-future-fcm.md) | Local notifications preserved |
| [`ADR-019`](ADR-019-notification-event-taxonomy.md) | Event vocabulary |
| [`ADR-020`](ADR-020-push-delivery-and-fallback-strategy.md) | Delivery semantics |
| [`ADR-021`](ADR-021-notification-security-and-privacy.md) | Payload privacy |
| [`ADR-022`](ADR-022-scheduler-smart-home-automation-model.md) | Automation model |
| [`ADR-023`](ADR-023-automation-execution-order-and-failure-policy.md) | Execution order |
| [`../specs/push-notifications/mvp/spec.md`](../specs/push-notifications/mvp/spec.md) | Push foundation |
| [`../specs/scheduler-smart-home-automations/mvp/spec.md`](../specs/scheduler-smart-home-automations/mvp/spec.md) | Feature spec |

---

When `action_execution_logs` or opt-in success notifications are proposed, create a follow-up ADR referencing this observability baseline.
