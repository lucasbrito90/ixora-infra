# ADR-016: Smart Home async execution

## Status

**Accepted** — governs the **execution model** for Smart Home device actions ([`specs/smart-home/mvp/spec.md`](../specs/smart-home/mvp/spec.md)).

## Date

2026-06-14

## Context

When IXORA eventually executes Smart Home device actions (calling a provider like Home Assistant to turn on a light), those HTTP calls to the provider introduce latency, timeout risk, and failure modes that do not exist in the current audio-only architecture.

Key constraints:

1. **Provider calls are network I/O** — calling a HA instance over the public internet introduces unpredictable latency (50ms–5000ms).
2. **Provider may be temporarily unreachable** — user's HA instance may be down, the tunnel may have dropped, or the token may have expired.
3. **IXORA API is a synchronous HTTP server** — blocking an API worker thread on a potentially slow external HTTP call degrades the entire API tier.
4. **Schedule dispatch must not be blocked** — the Scheduler dispatcher command runs on a tight loop (`~60s` cadence, [ADR-011](ADR-011-scheduler-local-notifications-vs-future-fcm.md)); adding synchronous provider calls would risk loop stalls.
5. **Audio playback is the primary experience** — device action execution is a side effect; it must not delay or block the play path on mobile.

### Current state

- The existing `queue` worker is already deployed on DigitalOcean App Platform (`back_vibes` queue worker — see [staging-digitalocean.md](../architecture/backend/staging-digitalocean.md)).
- No Smart Home execution exists yet. The ADRs + spec define the model before any code ships.
- Phase 1 (this ADR) documents the execution contract so that the action model and database schema support queued execution from the start.

---

## Decision

**Smart Home device action execution is always asynchronous. Provider calls must never run inside normal CRUD requests or the scheduler dispatch loop. When real execution ships, it uses the existing queue worker. MVP Phase 1 defines the model only — no queue jobs are dispatched yet.**

### Execution model

| Principle | Rule |
| --- | --- |
| **No inline provider calls** | No HTTP call to HA (or any provider) inside a `Controller`, `FormRequest`, or synchronous Artisan command. |
| **Queue-backed execution** | Device action execution is dispatched as a job to the Laravel queue — processed by the existing `queue` worker. |
| **Backend records first, executes second** | The API records the action request (e.g. a vibe play event or explicit trigger) and dispatches the job. The response to the client does not wait for the provider. |
| **Provider failures are isolated** | A provider timeout or 500 does not surface as an IXORA API error to the mobile client. |
| **Schedule dispatch is unaffected** | The `schedules:dispatch-loop` command does not invoke device actions. Device action execution is initiated from the vibe play path, not the scheduler tick. |

### Execution trigger (future — not MVP Phase 1)

```
Mobile: user plays vibe (or notification tap → play)
  → POST /api/vibes/{id}/play (or similar trigger — TBD in future spec)
  → Backend: record play event
  → Backend: dispatch SmartHomeActionJob for each vibe_device_action
  → Queue worker: execute action via adapter.executeAction(connection, device, action, params)
  → Log result in ActionExecutionLog
```

This trigger endpoint is **not implemented in Phase 1**. The spec documents the model so that schema design supports it.

### Queue infrastructure

| Component | Status | Notes |
| --- | --- | --- |
| **`queue` worker** | **Already deployed** — DO App Platform worker (`php artisan queue:work --queue=push,smart-home,default`) | [staging-digitalocean.md](../architecture/backend/staging-digitalocean.md) |
| **`SmartHomeActionJob`** | **Not implemented** — future phase | Will use existing queue; no new infra needed |
| **Queue connection** | Existing (`database` or Redis — per current config) | No change required |
| **`scheduler` worker** | Separate worker — dispatch loop only | Does not execute device actions |

### ActionExecutionLog (future)

A future `action_execution_logs` table (or extended `vibe_device_actions` log column) will record:

| Field | Description |
| --- | --- |
| `vibe_device_action_id` | Which action was executed |
| `status` | `queued \| dispatched \| succeeded \| failed \| timeout` |
| `executed_at` | When the worker processed the job |
| `response_log` | Provider HTTP response summary (sanitised) |
| `error` | Error message if failed |

This is not implemented in Phase 1 — defined here to ensure the action model schema does not block future audit.

### Offline device behaviour

| Scenario | Behaviour |
| --- | --- |
| **User device offline when vibe plays** | Mobile cannot reach backend API — no job dispatched. Action is not queued or retried offline. |
| **Provider offline when job runs** | Worker catches exception, logs failure, marks action as failed. No user-visible error in MVP. |
| **Provider intermittently slow** | Job has a configurable timeout. Timeout is a failure — logged, not retried in MVP. |
| **No guaranteed execution** | Smart Home actions are best-effort. Audio plays regardless. |

### MVP Phase 1 scope

Phase 1 (this ADR + spec + ADRs 012–015) is **documentation only**:

- No queue jobs for device actions.
- No `ActionExecutionLog` table.
- No vibe play endpoint that dispatches jobs.
- Schema stubs (`devices`, `vibe_device_actions`) are reviewed in Phase 2 to ensure the async model can be bolted on without structural changes.

---

## Consequences

### Positive

| Outcome | Why it matters |
| --- | --- |
| **API responsiveness protected** | Provider latency never blocks mobile API requests. |
| **Scheduler loop integrity** | The `~60s` dispatch loop cannot stall from a provider call. |
| **Reuses existing queue worker** | No new infrastructure required when real execution ships. |
| **Failure isolation** | Provider errors are contained in the queue job layer — not propagated to user as IXORA errors. |
| **Audit foundation** | `ActionExecutionLog` design is documented upfront so the schema is not blocked later. |

### Negative / tradeoffs

| Tradeoff | Impact |
| --- | --- |
| **No guaranteed execution** | Users cannot rely on device actions as guaranteed synchronous side effects. Acceptable for ambient/lifestyle use cases; documented in UX copy. |
| **No offline action queuing** | If user is offline, actions are lost for that play event. No outbox on mobile. |
| **Delayed feedback** | Mobile client does not know if the action succeeded — fire and forget (with eventual log). |
| **Job infrastructure dependency** | When real execution ships, it requires the queue worker to be healthy. Degraded queue = silent action failures. |

---

## Alternatives Considered

| Alternative | Why not chosen |
| --- | --- |
| **Synchronous execution in controller** | Rejected — provider latency blocks API workers; provider failure causes API errors. |
| **Synchronous execution in scheduler loop** | Rejected — stalls the dispatch loop; schedule audit is decoupled from device actions (ADR-015). |
| **Mobile calls provider directly** | Rejected — provider credentials are server-side only ([ADR-012](ADR-012-smart-home-provider-strategy.md), [ADR-013](ADR-013-home-assistant-first-provider.md)). |
| **New dedicated queue worker for Smart Home** | Not required — existing `queue` worker handles all Laravel queue jobs; no separate process needed. |
| **Guaranteed retry with backoff in MVP** | Deferred — retry policy is a future spec after execution model is validated. |
| **WebSocket push for action result** | Out of scope — no real-time push infrastructure in current IXORA architecture. |

---

## What changed vs prior ADRs (v1.4.0 supersession)

| Prior statement | Fulfilled by |
| --- | --- |
| This ADR § "ActionExecutionLog (future)": "A future `action_execution_logs` table (or extended `vibe_device_actions` log column) will record" per-action outcomes | [ADR-034](ADR-034-partial-execution-outcome.md) — `scene_action_executions` table (T21) with aggregate read API at `GET /api/scenes/{scene}/executions/{sceneExecutionId}` (T22). This ADR remains the async execution foundation; outcome persistence is documented in ADR-034. |

---

## Related Docs

| Document | Relationship |
| --- | --- |
| [`ADR-012`](ADR-012-smart-home-provider-strategy.md) | Provider adapter architecture |
| [`ADR-013`](ADR-013-home-assistant-first-provider.md) | HA adapter — `executeAction()` called from job |
| [`ADR-014`](ADR-014-device-abstraction-and-deduplication.md) | Device identity used in execution job |
| [`ADR-015`](ADR-015-vibe-device-action-architecture.md) | Action ownership — vibe owns action list |
| [`ADR-011`](ADR-011-scheduler-local-notifications-vs-future-fcm.md) | Scheduler loop must not be blocked — aligned |
| [`../specs/smart-home/mvp/spec.md`](../specs/smart-home/mvp/spec.md) | Execution model section |
| [`../specs/smart-home/mvp/plan.md`](../specs/smart-home/mvp/plan.md) | Phase 8 — async execution foundation |
| [`../architecture/backend/staging-digitalocean.md`](../architecture/backend/staging-digitalocean.md) | Existing `queue` worker |
| [`../../specs/vibes/execution-plan/spec.md`](../../specs/vibes/execution-plan/spec.md) | Vibe play path — device actions hook into play event |

---

When real queue job execution ships, create a follow-up ADR documenting retry policy, timeout configuration, and `ActionExecutionLog` schema. Reference this ADR as the async execution foundation.
