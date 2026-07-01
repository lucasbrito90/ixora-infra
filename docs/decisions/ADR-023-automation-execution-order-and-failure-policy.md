# ADR-023: Automation execution order and failure policy

## Status

**Accepted** — governs **execution sequencing and failure isolation** for Scheduler + Smart Home automations ([`specs/scheduler-smart-home-automations/mvp/spec.md`](../specs/scheduler-smart-home-automations/mvp/spec.md)).

## Date

2026-06-28

## Context

Combining Scheduler and Smart Home introduces a multi-step execution path when a schedule is due:

1. Record the occurrence (`schedule_executions`)
2. Advance recurrence (`next_run_at`)
3. Dispatch Smart Home jobs for the schedule’s vibe
4. Optionally notify the user (local notification already scheduled on device; push for failures)

Each step has different failure modes, latency profiles, and user expectations. The team must define **order**, **isolation**, and **what “success” means** without introducing background audio autoplay or blocking the scheduler loop.

### Current runtime (pre-integration)

| Component | Current behaviour |
| --- | --- |
| **`schedules:dispatch-due`** | Creates `ScheduleExecution`, advances `next_run_at`; does **not** dispatch Smart Home jobs |
| **`VibeSmartHomeDispatchService`** | Enqueues `SmartHomeActionJob` per action in `sort_order`; used by mobile `POST /api/smart-home/dispatch` |
| **`SmartHomeActionJob`** | Async provider call; failures logged; push on failure via existing events |
| **Local notifications** | Scheduled on Android from SQLite mirror — parallel to backend tick |
| **Audio playback** | Client-only — user or notification tap starts `playVibe` |

This ADR defines the **target behaviour** when scheduler dispatch integrates with Smart Home dispatch.

---

## Decision

**Automation execution is best-effort and asynchronous. Failures in Smart Home actions or push notifications must never block scheduler recurrence or other actions in the same occurrence. Audio playback is never server-side autoplay. Execution order is: (1) schedule execution record + recurrence advance, (2) Smart Home jobs enqueued in `sort_order`, (3) user-side audio via existing local notification / manual play path.**

### Execution flow

```
Schedule due (next_run_at <= now UTC)
  │
  ├─► [1] DB transaction: create ScheduleExecution (idempotent)
  │         advance next_run_at / disable once-schedules
  │
  ├─► [2] If schedule.vibe has active VibeDeviceActions:
  │         VibeSmartHomeDispatchService.dispatch(vibe)
  │           → SmartHomeActionJob per action (sort_order ASC)
  │           → each job independent; failure isolated
  │
  ├─► [3] Local notification (already scheduled on device from mirror)
  │         → user may tap → open app → playVibe (client-side)
  │
  └─► [4] Push notifications (failure paths only in MVP)
            → schedule_execution_failed (dispatcher transaction failure)
            → smart_home_action_failed (job failure)
            → best-effort; never blocks steps 1–2
```

### Execution order (strict)

| Step | Action | Blocking? | On failure |
| --- | --- | --- | --- |
| **1** | `ScheduleExecution` insert + `next_run_at` advance | **Must complete in transaction** | Recurrence does **not** advance; push `schedule_execution_failed` |
| **2** | Enqueue `SmartHomeActionJob` for each action | **Non-blocking enqueue only** | Log skip count; individual job failures isolated |
| **3** | Smart Home job executes (queue worker) | Async | Log + optional push; **does not** affect schedule recurrence |
| **4** | Local notification fires (device) | OS-managed | No backend dependency |
| **5** | Push notification (failures) | Async queue | Swallowed — no domain impact |

**Smart Home enqueue happens after successful step 1** — inside the same request/command tick but **outside** the DB transaction that records execution, OR immediately after transaction commit. Enqueue must not roll back `ScheduleExecution` on job dispatch failure.

### Failure isolation rules

| Rule | Detail |
| --- | --- |
| **Smart Home failure must not block scheduler recurrence** | `next_run_at` advances when execution row is committed — regardless of device action outcomes |
| **One Smart Home action failure must not block other actions** | Each `SmartHomeActionJob` is independent; partial success is acceptable |
| **Push notification failure must not block anything** | `PushNotificationEvents` swallows errors ([ADR-020](ADR-020-push-delivery-and-fallback-strategy.md)) |
| **Local notification behaviour preserved** | Android mirror + OS alarms unchanged ([ADR-011](ADR-011-scheduler-local-notifications-vs-future-fcm.md)) |
| **Missing device on action** | Skip action; count in dispatch result — same as manual dispatch today |
| **Vibe with zero device actions** | Step 2 is no-op; schedule behaves as today (reminder-only automation) |

### Audio / playback boundary

| Topic | Policy |
| --- | --- |
| **Server-side autoplay** | **Forbidden** — backend does not stream audio or command device speakers |
| **Background auto-play** | **Not implemented** — no FCM wake-to-play, no silent audio start |
| **User-side playback** | Local notification opens app; user taps Play or optional in-app “Start now” |
| **Offline at due time** | Local notification may still fire; Smart Home jobs run server-side if provider reachable; playback requires online or prior offline download |

### Idempotency

Duplicate dispatcher ticks (worker restart, overlap) must not double-enqueue Smart Home jobs for the same occurrence:

| Guard | Mechanism |
| --- | --- |
| **Execution record** | Unique `(schedule_id, occurrence_key)` — [ADR-010](ADR-010-scheduler-idempotency-occurrence-key.md) |
| **Smart Home dispatch** | Only invoke dispatch when execution row is **newly created** in this tick — skip on `skipped_duplicate` |
| **Job dedupe** | Optional future: include `occurrence_key` in job payload for audit — not required for MVP idempotency if dispatch is gated on new execution |

### Integration point (implementation phase)

After `processSchedule()` returns `'dispatched'` (not `'skipped_duplicate'`):

1. Load `$schedule->vibe` (eager-load or query).
2. If vibe has `vibe_device_actions` with resolvable devices, call `VibeSmartHomeDispatchService::dispatch($vibe)`.
3. Optionally append dispatch summary to `ScheduleExecution.log` JSON in a follow-up update (non-blocking).

**Do not** call provider adapters inline in `DispatchDueSchedulesCommand`.

---

## Consequences

### Positive

| Outcome | Why it matters |
| --- | --- |
| **Scheduler integrity preserved** | Recurrence advances even when HA is down |
| **Reuses proven dispatch service** | Same code path as manual vibe play |
| **Predictable failure semantics** | Users get failure push; schedule keeps running |
| **No autoplay liability** | Avoids OS background audio restrictions and user surprise |

### Negative / tradeoffs

| Tradeoff | Impact |
| --- | --- |
| **Lights may turn on before user plays audio** | By design — Smart Home is server-side; audio is user-initiated |
| **No guaranteed Smart Home execution** | Provider offline = silent failure + optional push |
| **Dispatch without playback** | Schedule fires device actions even if user ignores notification — acceptable for “turn off bedroom light at 10 PM” use case |

---

## Alternatives Considered

| Alternative | Why not chosen |
| --- | --- |
| **Smart Home only after mobile ack / play** | Requires app online; fails for “lights off while away” scenarios |
| **Synchronous Smart Home in dispatcher transaction** | Blocks scheduler loop; violates ADR-016 |
| **Rollback recurrence on Smart Home failure** | Would stall schedules when HA is flaky |
| **Background audio autoplay on schedule due** | Out of scope; OS constraints; user expectation mismatch |
| **Single combined automation job** | Loses per-action failure isolation |

---

## Related Docs

| Document | Relationship |
| --- | --- |
| [`ADR-010`](ADR-010-scheduler-idempotency-occurrence-key.md) | Occurrence idempotency |
| [`ADR-011`](ADR-011-scheduler-local-notifications-vs-future-fcm.md) | Local notifications |
| [`ADR-015`](ADR-015-vibe-device-action-architecture.md) | Vibe owns actions |
| [`ADR-016`](ADR-016-smart-home-async-execution.md) | Async Smart Home execution |
| [`ADR-020`](ADR-020-push-delivery-and-fallback-strategy.md) | Push non-blocking |
| [`ADR-022`](ADR-022-scheduler-smart-home-automation-model.md) | Composition model |
| [`ADR-024`](ADR-024-automation-notifications-and-observability.md) | Notification events |
| [`../specs/scheduler-smart-home-automations/mvp/spec.md`](../specs/scheduler-smart-home-automations/mvp/spec.md) | Feature spec |

---

When retry policy or `ActionExecutionLog` ships, extend this ADR or add ADR-026 for retry/backoff semantics.
