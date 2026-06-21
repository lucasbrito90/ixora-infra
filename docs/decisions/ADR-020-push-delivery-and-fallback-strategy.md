# ADR-020: Push delivery and fallback strategy

## Status

**Accepted** — governs **push delivery semantics** ([`specs/push-notifications/mvp/spec.md`](../specs/push-notifications/mvp/spec.md)).

## Date

2026-06-21

## Context

Push notifications over FCM are **best-effort**. IXORA already has:

- **Local notifications** for Scheduler reminders ([ADR-011](ADR-011-scheduler-local-notifications-vs-future-fcm.md))
- **Async queue jobs** for Smart Home execution ([ADR-016](ADR-016-smart-home-async-execution.md))
- **Non-blocking audio playback** — primary experience must never wait on side effects

The team must define how FCM fits alongside local notifications and ensure that Scheduler and Smart Home execution **never block** on push delivery.

---

## Decision

**Push delivery is async, best-effort, and non-blocking. Local notifications remain useful for offline/on-device schedule reminders. FCM complements local notifications — it does not replace them immediately. Push sending is queued. If FCM fails, log failure and continue. Scheduler and Smart Home action execution must not block on push delivery.**

### Delivery model

| Principle | Rule |
| --- | --- |
| **Async only** | Push send runs in `PushNotificationJob` on queue — never inline in HTTP request or dispatcher loop |
| **Best-effort** | No guaranteed delivery; no retry storm in MVP |
| **Non-blocking** | Domain logic completes before push job is dispatched; push failure does not fail domain operation |
| **Log on failure** | FCM errors logged with context — no user-visible API error from push failure |
| **No blocking Scheduler** | `schedules:dispatch-loop` does not wait for FCM |
| **No blocking Smart Home** | `SmartHomeActionJob` completes/fails independently; push is a separate enqueue |

### Local notifications vs FCM

| Capability | Local notifications (existing) | FCM push (new) |
| --- | --- | --- |
| **Schedule due reminder** | ✅ Primary — offline-capable | Optional future complement |
| **Remote execution failure** | ❌ Cannot fire if app never synced | ✅ Appropriate use case |
| **Provider unreachable** | ❌ | ✅ Appropriate use case |
| **Account security** | ❌ | ✅ Appropriate use case |
| **Works when app killed** | OS-dependent (local alarm) | FCM-dependent |
| **Requires device token** | ❌ | ✅ |

**MVP stance:** Do **not** remove or replace Scheduler local notifications. FCM is added for **remote/system events** in later phases.

### Queue infrastructure

| Component | Role |
| --- | --- |
| **`PushNotificationJob`** | Resolves user tokens, builds payload, calls `PushProvider` |
| **Existing `queue` worker** | Processes push jobs — same worker as Smart Home ([staging-digitalocean.md](../architecture/backend/staging-digitalocean.md)) |
| **Queue name** | TBD in implementation — e.g. `notifications` or `default` |

### Failure handling

```
Domain event (e.g. SmartHomeActionJob failure)
  → Log domain result (existing behaviour)
  → Dispatch PushNotificationJob (fire-and-forget)
  → Queue worker: FcmPushProvider.send(tokens, payload)
  → Success: log info
  → Failure (4xx/5xx/invalid token): log warning, deactivate invalid token if applicable
  → Never rethrow to domain layer
  → Never block audio, scheduler tick, or API response
```

### Invalid / expired tokens

| Scenario | Behaviour |
| --- | --- |
| **FCM returns unregistered token** | Mark `push_tokens.is_active = false`, set `revoked_at` |
| **All tokens invalid for user** | Log warning; no push delivered — acceptable |
| **Transient FCM outage** | Log failure; optional single retry in future ADR — not MVP |

---

## Consequences

### Positive

| Outcome | Why it matters |
| --- | --- |
| **Consistent with Smart Home async model** | Same fire-and-forget pattern as [ADR-016](ADR-016-smart-home-async-execution.md) |
| **Scheduler integrity preserved** | Dispatch loop stays fast |
| **Honest delivery semantics** | No false "guaranteed notification" promise |
| **Local notifications preserved** | Offline schedule reminders still work |

### Negative / tradeoffs

| Tradeoff | Impact |
| --- | --- |
| **Dual notification systems** | Mobile maintains local + FCM handlers |
| **Silent push failures** | User may not know notification was not delivered |
| **Queue dependency** | Unhealthy queue = no push — same as Smart Home |

---

## Alternatives Considered

| Alternative | Why not chosen |
| --- | --- |
| **Synchronous push in controller** | Rejected — FCM latency blocks API |
| **Replace local notifications with FCM** | Rejected — breaks offline reminder story |
| **Guaranteed delivery with aggressive retry** | Rejected — queue flood risk; out of MVP |
| **Push failure fails Smart Home job** | Rejected — violates non-blocking principle |
| **WebSocket instead of push** | Out of scope — no real-time infra |

---

## Related Docs

| Document | Relationship |
| --- | --- |
| [`ADR-011`](ADR-011-scheduler-local-notifications-vs-future-fcm.md) | Local notification fallback |
| [`ADR-016`](ADR-016-smart-home-async-execution.md) | Async execution pattern |
| [`ADR-017`](ADR-017-push-notification-provider-strategy.md) | FCM provider |
| [`ADR-019`](ADR-019-notification-event-taxonomy.md) | Event types |
| [`../architecture/backend/staging-digitalocean.md`](../architecture/backend/staging-digitalocean.md) | Queue worker |
| [`../specs/push-notifications/mvp/spec.md`](../specs/push-notifications/mvp/spec.md) | MVP scope |

---

When retry policy or dedicated notification queue is defined, document in implementation phase or follow-up ADR.
