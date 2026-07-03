# Notification Architecture

**Status:** Active architecture guide  
**ADRs:** [ADR-017](../decisions/ADR-017-push-notification-provider-strategy.md) · [ADR-024](../decisions/ADR-024-automation-notifications-and-observability.md) · [ADR-026](../decisions/ADR-026-automation-execution-security.md) · [ADR-027](../decisions/ADR-027-asynchronous-orchestration-pattern.md)  
**Complements:** [`asynchronous-orchestration.md`](asynchronous-orchestration.md) · [`domain-validation.md`](domain-validation.md)  
**Applies to:** All Ixora backend domains that emit user-facing alerts — Scheduler, Smart Home, Auth, and future channels

> **Rule of thumb:** Notifications communicate **events**. They never own **workflow**, never contain **business logic**, and never **rollback** domain operations when delivery fails.

---

## 1. Introduction

Notifications in Ixora are **side effects** of domain activity. A schedule fails, a device action errors, a security event occurs — the domain completes (or skips) its work first; a notification may follow to inform the user.

| Principle | Meaning |
| --- | --- |
| **Side effect** | Emitted *after* domain intent is resolved — never the primary operation |
| **Event communication** | Tells the user *what happened* — not *how the system decided* |
| **No business logic** | Builders format payloads; they do not validate ownership, compute recurrence, or call providers |
| **No workflow ownership** | Notifications do not enqueue jobs, advance schedules, or trigger Smart Home actions |
| **Domain services stay authoritative** | Scheduler, Smart Home, Auth — each owns its rules; notifications observe outcomes |

If a feature needs to *do something* (dispatch a job, mutate state, call an API), that belongs in a **Domain Service** or **Queue Job** — not in a notification class.

---

## 2. Notification Flow

Every notification — push today, email or SMS tomorrow — follows the same layered pipeline defined in [ADR-027](../decisions/ADR-027-asynchronous-orchestration-pattern.md). The push channel is the first shipped implementation; the pattern is channel-agnostic.

### Standard pipeline

```
Async Entrypoint                    ← Scheduler command, Smart Home job, sync service, HTTP controller
    ↓
Domain Validator                    ← Optional — ownership / integrity at execution time (ADR-026)
    ↓
Domain Service                      ← Domain intent — recurrence, dispatch, sync
    ↓
Notification Orchestrator           ← PushNotificationEvents (push channel today)
    ↓
Notification Builder                ← Assembles channel payload (e.g. ScheduleExecutionFailedNotification)
    ↓
Delivery Service                    ← PushNotificationService — fire-and-forget enqueue
    ↓
Delivery Job                        ← PushNotificationJob — fan-out, retries, token hygiene
    ↓
Provider Resolver                   ← Selects transport (FCM, noop, future APNs)
    ↓
Provider / Adapter                  ← Wire format, HTTP, OAuth — no domain knowledge
    ↓
External System                     ← FCM, APNs, SMTP, Twilio, Slack webhook
```

### Layer responsibilities

| Layer | Role | Must NOT |
| --- | --- | --- |
| **Async Entrypoint** | Triggers domain work; catches exceptions; decides *whether* to notify on failure | Build payloads; call FCM; dispatch `PushNotificationJob` directly |
| **Domain Validator** | Re-checks ownership and entity integrity before side effects ([`domain-validation.md`](domain-validation.md)) | Emit notifications; call providers |
| **Domain Service** | Executes product intent — dispatch vibe actions, advance recurrence, sync devices | Format notification copy; know FCM payload schema |
| **Notification Orchestrator** | Typed public API for domain modules — maps domain outcome → builder → delivery service | HTTP; queue internals; provider credentials; business rules |
| **Notification Builder** | Constructs immutable payload DTO from domain entities | HTTP; queue; logging; provider calls; business decisions |
| **Delivery Service** | Enqueues delivery job for a recipient — always fire-and-forget | Call provider synchronously; throw to domain caller |
| **Delivery Job** | Fan-out to recipients/tokens; per-item failure isolation; deactivate invalid tokens | Modify domain state; re-run business logic |
| **Provider Resolver** | Selects concrete transport by slug / channel config | Domain ownership; payload content decisions |
| **Provider / Adapter** | Single-recipient send; maps result to delivery DTO | Scheduler concepts; vibe rules; build notification copy |
| **External System** | Authoritative delivery (FCM, future SMTP) | — (not Ixora code) |

### Shipped example — Scheduler failure → push

```
DispatchDueSchedulesCommand           ← Entrypoint
    ↓  processSchedule() throws
PushNotificationEvents                ← Orchestrator
    .notifyScheduleExecutionFailed()
    ↓
ScheduleExecutionFailedNotification   ← Builder
    ::build($execution)
    ↓
PushNotificationService               ← Delivery Service
    .sendToUser($user, $payload)
    ↓
PushNotificationJob                   ← Delivery Job (queue: push)
    ↓
PushProviderResolver                  ← Resolver
    ↓
FcmPushProvider                       ← Provider
    ↓
Firebase Cloud Messaging              ← External System
```

Reference: [`asynchronous-orchestration.md`](asynchronous-orchestration.md) · [push-notifications/mvp/spec.md](../specs/push-notifications/mvp/spec.md)

---

## 3. Notification Types

A **notification type** is a stable string identifier in the payload `type` field. It maps a **business event** to a **user-facing alert** and mobile **tap routing**.

### Business event → notification type

```
Domain outcome (business event)
    ↓
Notification Orchestrator method
    ↓
Notification type (stable string in payload.data.type)
    ↓
Mobile tap handler / future channel router
```

### Current MVP types ([ADR-019](../decisions/ADR-019-notification-event-taxonomy.md))

| Notification type | Business event | Domain source | Purpose |
| --- | --- | --- | --- |
| **`schedule_execution_failed`** | Scheduler transaction failed — recurrence did not advance | `DispatchDueSchedulesCommand` | Alert user a scheduled execution could not complete |
| **`smart_home_action_failed`** | Device action returned failure or unexpected error | `SmartHomeActionJob` | Alert user a Smart Home action could not complete |
| **`smart_home_provider_unreachable`** | Provider sync or connection call failed | `ProviderDeviceSyncService` | Alert user their Smart Home provider is unreachable |
| **`account_security_notice`** | Auth / security event (dynamic title/body) | Auth domain (future callers) | Security-related account notice — unrelated to Scheduler / Smart Home |

**Deferred types** (documented in ADR-019, not emitted in MVP): `schedule_due`, marketing/campaign types — explicitly out of scope.

### Future types — same architecture, new channels

New channels reuse the **same type vocabulary** and builder pattern; only the delivery stack below the orchestrator changes.

| Future channel | Example business events | Same type? |
| --- | --- | --- |
| **Email** | `schedule_execution_failed` digest | ✅ Reuse type; new Email builder + provider |
| **SMS** | `account_security_notice` | ✅ Reuse type; SMS-specific copy builder |
| **Slack / Discord / Teams** | Admin ops alerts | New types if needed — still via orchestrator |
| **Matter alerts** | Device state change | New type + builder; same pipeline |
| **Admin Inbox / Notification Center** | Any operational event | Persist + in-app — orchestrator fans out to inbox provider |
| **Web Push / APNs** | Same as FCM types | ✅ Reuse types; new provider in resolver |

**Do not fork parallel types** for the same business event unless mobile routing genuinely requires it ([ADR-024](../decisions/ADR-024-automation-notifications-and-observability.md)).

---

## 4. Notification Builders

**Notification Builders** are pure payload factories. Each builder corresponds to one notification type and returns an immutable DTO (today: `NotificationPayload`).

### Why builders exist

| Without builders | With builders |
| --- | --- |
| Copy/paste payload arrays in every domain module | Single source of truth per event type |
| Domain modules know FCM `data` key names | Domain modules call orchestrator typed methods only |
| Hard to test payload shape | Unit-test builders in isolation |
| Accidental secret leakage in ad-hoc arrays | Builder enforces allowed fields |

### Builder responsibilities

| ✓ Do | ✗ Do not |
| --- | --- |
| Construct title, body, and `data` map | HTTP calls |
| Cast all `data` values to **strings** | Queue dispatch |
| Include only business identifiers (IDs, slugs) | Provider selection or FCM calls |
| Keep copy generic and privacy-safe ([ADR-021](../decisions/ADR-021-notification-security-and-privacy.md)) | Structured logging |
| Stay deterministic for the same input entity | Business decisions (skip vs notify) |

### Current examples (`back_vibes`)

| Builder | Type | Key `data` fields |
| --- | --- | --- |
| `ScheduleExecutionFailedNotification` | `schedule_execution_failed` | `schedule_execution_id` (when set), `schedule_id` (when set) |
| `SmartHomeActionFailedNotification` | `smart_home_action_failed` | `device_id`, `vibe_id`, `action_type` |
| `SmartHomeProviderUnreachableNotification` | `smart_home_provider_unreachable` | `provider_connection_id`, `provider` |
| `AccountSecurityNoticeNotification` | `account_security_notice` | `type` only — title/body supplied by caller |

---

## 5. Notification Orchestrator (`PushNotificationEvents`)

`PushNotificationEvents` is the **orchestration boundary** for the push channel today. Domain modules call its typed methods — nothing else in the push stack.

### Public API (shipped)

| Method | Notification type |
| --- | --- |
| `notifyScheduleExecutionFailed(User, ScheduleExecution)` | `schedule_execution_failed` |
| `notifySmartHomeActionFailed(User, VibeDeviceAction)` | `smart_home_action_failed` |
| `notifySmartHomeProviderUnreachable(User, ProviderConnection)` | `smart_home_provider_unreachable` |
| `notifyAccountSecurityNotice(User, string $title, string $body)` | `account_security_notice` |

### Contract

| Rule | Detail |
| --- | --- |
| **Single entrypoint** | Scheduler, Smart Home, Auth — all call `PushNotificationEvents`, never lower layers |
| **Never throws to caller** | Push dispatch failure is logged and swallowed — domain flow continues |
| **No transport knowledge** | Orchestrator does not import FCM, read tokens, or choose providers |
| **Safe logging only** | Logs `user_id`, `notification_type`, opaque IDs — never raw payloads with secrets |

### What other modules must never do

```
❌ Controller → PushNotificationJob::dispatch()
❌ Scheduler  → FcmPushProvider::send()
❌ Smart Home job → new NotificationPayload(...) inline
❌ Provider   → builds notification copy
```

---

## 6. Payload Design

Payloads are the contract between backend intent and client tap routing. Treat them as **public API** — mobile handlers depend on stable keys.

### Best practices

| Rule | Rationale |
| --- | --- |
| **`type` is always present** | Primary routing key — must match [ADR-019](../decisions/ADR-019-notification-event-taxonomy.md) |
| **All `data` values are strings** | FCM requires string key-value pairs; keeps cross-channel compatibility |
| **Business identifiers only** | `schedule_id`, `vibe_id`, `device_id` — enough to deep-link |
| **No secrets** | Never include access tokens, FCM tokens, provider credentials, or config blobs ([ADR-021](../decisions/ADR-021-notification-security-and-privacy.md)) |
| **No provider configuration** | `base_url`, API keys, connection secrets stay server-side |
| **Minimal PII** | Generic display copy in title/body; no email addresses or full names in `data` |
| **Backward compatible extensions** | Add optional keys; never rename or remove shipped keys without a migration plan |

### Example — schedule failure payload

```json
{
  "title": "Schedule failed",
  "body": "One of your scheduled executions failed.",
  "data": {
    "type": "schedule_execution_failed",
    "schedule_id": "42"
  }
}
```

### Example — Smart Home action failure payload

```json
{
  "title": "Device action failed",
  "body": "A Smart Home action could not be completed.",
  "data": {
    "type": "smart_home_action_failed",
    "device_id": "9",
    "vibe_id": "45",
    "action_type": "turn_on"
  }
}
```

### Tap routing dependency

Mobile reads `data.type` and optional IDs to navigate (e.g. open schedule detail, open vibe editor, open device settings). **Changing `type` values or removing ID keys breaks shipped clients.** Extend payloads additively ([ADR-024](../decisions/ADR-024-automation-notifications-and-observability.md)).

### Optional `schedule_id` in Smart Home failures

ADR-024 allows optional `schedule_id` in `smart_home_action_failed` when scheduler context is available. Current runtime passes `VibeDeviceAction` only — adding `schedule_id` requires threading context through the dispatch path without changing Smart Home execution semantics. Deferred until a product need for schedule-scoped tap routing is confirmed.

---

## 7. Failure Policy

Notification delivery is **best-effort**. It must never affect domain outcomes ([ADR-020](../decisions/ADR-020-push-delivery-and-fallback-strategy.md), [ADR-023](../decisions/ADR-023-automation-execution-order-and-failure-policy.md)).

### Isolation rules

| Failure | Domain impact | Notification impact |
| --- | --- | --- |
| **Queue unavailable** | Domain operation completes | Log error; no user alert — acceptable |
| **Provider HTTP error** | Domain operation completes | Log warning; retry job per config; other tokens still receive |
| **Invalid / expired token** | Domain operation completes | Deactivate token; continue batch |
| **Orchestrator throws** | Domain operation completes | Caught inside orchestrator; logged |
| **Single token fails in batch** | N/A | Other tokens in same job still attempted |

### What never happens

- ❌ Scheduler recurrence **rolls back** because FCM returned 503
- ❌ Smart Home job **retries** because push fan-out failed
- ❌ DB transaction **aborts** because no push tokens registered

### Validator failures — no notification

When a **Domain Validator** returns `false` (expected skip), the system **logs and continues** — it does **not** emit a push notification ([ADR-026](../decisions/ADR-026-automation-execution-security.md)).

Example: `ScheduleAutomationValidator` fails → Smart Home dispatch skipped → no `smart_home_action_failed` push. This is intentional — validation skip is not a user-actionable failure.

### Unsupported action types — no notification

`UnsupportedSmartHomeActionException` is logged and skipped — no push. Retrying or notifying would not help; the action type is not supported by the provider adapter.

---

## 8. Local vs Push Notifications

Ixora uses **two complementary channels** for schedule-related user alerts. They serve different purposes and must not be conflated ([ADR-011](../decisions/ADR-011-scheduler-local-notifications-vs-future-fcm.md), [ADR-024](../decisions/ADR-024-automation-notifications-and-observability.md)).

| Dimension | Local notifications | Push notifications |
| --- | --- | --- |
| **Origin** | Mobile app (Capacitor plugin + SQLite mirror) | Backend (Laravel queue → FCM) |
| **Network** | Offline-capable — scheduled on device | Requires device token + network at delivery time |
| **Primary use** | Schedule **due reminders** — "time to start your vibe" | **Failure alerts**, security notices, provider unreachable |
| **Cross-device** | Device-local only | All registered devices for the user |
| **Success alerts** | N/A (reminder only) | ❌ Not sent by default — avoids notification fatigue |
| **Replaces the other?** | ❌ Never | ❌ Never — push is additive |

```
Schedule due
    │
    ├─► Local notification (mobile)     ← Primary reminder — unchanged
    │
    └─► User opens app / plays vibe     ← Client-side audio — never server autoplay

Schedule or Smart Home failure (backend)
    │
    └─► Push notification (server)      ← Failure alert — best-effort additive
```

**Push complements local. Push never replaces local. Push never suppresses local.**

---

## 9. Adding a New Notification

Use this checklist before implementing a new notification type or extending an existing one.

### Design questions

| # | Question | If "no" → |
| --- | --- | --- |
| 9.1 | **Is this really a business event?** | Maybe it belongs in logs/observability only — not a user notification |
| 9.2 | **Can an existing notification type be reused?** | Extend payload additively instead of creating a parallel type ([ADR-024](../decisions/ADR-024-automation-notifications-and-observability.md)) |
| 9.3 | **Is the user expected to act on this?** | If not, prefer structured logs over push |
| 9.4 | **Would this cause notification fatigue?** | Defer or make opt-in (success pushes are off by default) |
| 9.5 | **Does this belong in MVP scope?** | Marketing, campaigns, behavioural nudges are out of scope ([ADR-019](../decisions/ADR-019-notification-event-taxonomy.md)) |

### Implementation checklist

| # | Step | Owner layer |
| --- | --- | --- |
| 9.6 | Add type to [ADR-019](../decisions/ADR-019-notification-event-taxonomy.md) taxonomy (or extend existing) | ADR / spec |
| 9.7 | Create **Notification Builder** — payload only, all string values | Builder |
| 9.8 | Add typed method to **Notification Orchestrator** | Orchestrator |
| 9.9 | Call orchestrator from **Domain Service / Job / Entrypoint** — never from provider | Domain module |
| 9.10 | Unit-test builder output (type, keys, string values, no secrets) | Tests |
| 9.11 | Feature-test orchestrator dispatch (Bus::fake — no real FCM) | Tests |
| 9.12 | Update **mobile tap routing** if new type or new required ID keys | `front_vibes` (separate phase) |
| 9.13 | Confirm payload is **backward compatible** with shipped clients | Review |

**Block merge if:**

- Domain module dispatches `PushNotificationJob` directly
- Builder performs HTTP, queue, or logging
- Payload contains secrets, tokens, or provider config
- Notification failure can throw to domain caller uncaught
- Validator skip path emits a failure notification

---

## 10. Anti-patterns

### ❌ Controller dispatches `PushNotificationJob`

```
ScheduleController
    ↓
PushNotificationJob::dispatch($userId, $payload)   ❌
```

**Why bad:** Bypasses orchestrator and builder; duplicates payload shape; untestable routing contract.

---

### ❌ Scheduler calls FCM directly

```
DispatchDueSchedulesCommand
    ↓
Http::post('fcm.googleapis.com/...')   ❌
```

**Why bad:** Domain module owns transport; credentials risk; no token fan-out; violates [ADR-017](../decisions/ADR-017-push-notification-provider-strategy.md).

---

### ❌ Provider builds payload

```
FcmPushProvider::send()
    ↓
$payload->title = "Schedule failed"   ❌
```

**Why bad:** Provider must be domain-agnostic; copy belongs in builders.

---

### ❌ Notification contains business logic

```
ScheduleExecutionFailedNotification::build()
    ↓
if (!$execution->schedule->is_enabled) return null;   ❌
```

**Why bad:** Skip/notify decisions belong in the domain entrypoint before calling the orchestrator.

---

### ❌ Notification payload contains secrets

```json
{
  "data": {
    "type": "smart_home_provider_unreachable",
    "access_token": "eyJ..."   ❌
  }
}
```

**Why bad:** FCM data may be logged on device; violates [ADR-021](../decisions/ADR-021-notification-security-and-privacy.md).

---

### ❌ Delivery job modifies domain state

```
PushNotificationJob::handle()
    ↓
$schedule->is_enabled = false;   ❌
```

**Why bad:** Delivery layer must not mutate domain entities — token deactivation only.

---

### ❌ Duplicated notification types

```
smart_home_action_failed
automation_smart_home_action_failed   ❌ parallel fork
```

**Why bad:** Mobile routing complexity; payload drift. Extend existing type instead ([ADR-024](../decisions/ADR-024-automation-notifications-and-observability.md)).

---

### ❌ Validator failure triggers push

```
ScheduleAutomationValidator::validate() → false
    ↓
notifySmartHomeActionFailed()   ❌
```

**Why bad:** Validation skip is expected, not actionable — log + continue only ([ADR-026](../decisions/ADR-026-automation-execution-security.md)).

---

## 11. Relationship with Other Documents

| Document | Relationship |
| --- | --- |
| [ADR-017](../decisions/ADR-017-push-notification-provider-strategy.md) | **Decision** — FCM-first transport, provider abstraction, backend-only send. This guide explains *how* to use that stack. |
| [ADR-024](../decisions/ADR-024-automation-notifications-and-observability.md) | **Decision** — automation event reuse, no success push by default, observability split. This guide operationalises those rules. |
| [ADR-026](../decisions/ADR-026-automation-execution-security.md) | **Decision** — validators vs policies. This guide clarifies validators never emit notifications on skip. |
| [ADR-027](../decisions/ADR-027-asynchronous-orchestration-pattern.md) | **Decision** — six-layer async pattern. Notification delivery is a side-effect branch *after* domain service — see [`asynchronous-orchestration.md`](asynchronous-orchestration.md). |
| [ADR-019](../decisions/ADR-019-notification-event-taxonomy.md) | **Decision** — canonical type vocabulary and payload schema. |
| [ADR-020](../decisions/ADR-020-push-delivery-and-fallback-strategy.md) | **Decision** — async best-effort delivery; local notifications preserved. |
| [ADR-021](../decisions/ADR-021-notification-security-and-privacy.md) | **Decision** — no secrets in payloads; token privacy in logs. |
| [ADR-023](../decisions/ADR-023-automation-execution-order-and-failure-policy.md) | **Decision** — push failures never block scheduler recurrence or Smart Home batch. |
| [`domain-validation.md`](domain-validation.md) | **Guide** — when to validate before side effects; validator skip = no notification. |
| [`asynchronous-orchestration.md`](asynchronous-orchestration.md) | **Guide** — full async pipeline; includes push as a shipped example. |
| [`feature-design-checklist.md`](feature-design-checklist.md) | **Checklist** — §6 failure policy and §9 reuse questions apply before adding notifications. |
| [`feature-spec-template.md`](../templates/feature-spec-template.md) | **Template** — Architecture Mapping must show where notifications emit in the async pipeline. |
| [push-notifications/mvp/spec.md](../specs/push-notifications/mvp/spec.md) | **Spec** — acceptance criteria for the shipped push foundation. |

### When to read which document

| Question | Start here |
| --- | --- |
| *How should notifications be designed platform-wide?* | **This guide** |
| *Why FCM and provider abstraction?* | [ADR-017](../decisions/ADR-017-push-notification-provider-strategy.md) |
| *Which event types exist?* | [ADR-019](../decisions/ADR-019-notification-event-taxonomy.md) |
| *What happens when push fails?* | [ADR-020](../decisions/ADR-020-push-delivery-and-fallback-strategy.md) · §7 above |
| *Automation-specific notification rules?* | [ADR-024](../decisions/ADR-024-automation-notifications-and-observability.md) |
| *Where does notification fit in the async pipeline?* | [`asynchronous-orchestration.md`](asynchronous-orchestration.md) |
| *Implementing a new async feature that notifies?* | [`feature-design-checklist.md`](feature-design-checklist.md) → this guide → spec |

---

## 12. Future Evolution

New notification channels should **reuse this architecture** — not invent parallel dispatch paths.

### Channel extension model

```
Domain module
    ↓
Notification Orchestrator          ← PushNotificationEvents today;
    ↓                              ← EmailNotificationEvents tomorrow, etc.
Notification Builder               ← Channel-specific copy/format
    ↓
Delivery Service                   ← PushNotificationService, EmailNotificationService, …
    ↓
Delivery Job                       ← One job per channel (retries, fan-out)
    ↓
Provider Resolver                  ← fcm | noop | smtp | twilio | …
    ↓
Provider / Adapter
    ↓
External System
```

### Future channels (planning — not shipped)

| Channel | Likely orchestrator method pattern | Reuse existing types? |
| --- | --- | --- |
| **Email** | `notifyScheduleExecutionFailed()` fans out to push + email | ✅ Same business events |
| **SMS** | Security notices only — high cost, narrow scope | Partial — `account_security_notice` |
| **Slack / Discord / Teams** | Admin / ops alerts — separate recipient model | New admin-facing types |
| **Matter** | Device state alerts | New types — same builder pattern |
| **Apple Push (APNs)** | Same as FCM — new provider in resolver | ✅ Same types |
| **Web Push** | Browser clients — new token registration | ✅ Same types |
| **Admin Inbox** | Persist notification row + optional push | New persistence layer; same orchestrator entry |
| **In-app Notification Center** | Mobile polls or WebSocket — separate read model | Same types; delivery service writes to inbox |

### Naming evolution

The shipped class `PushNotificationEvents` is push-specific by name but follows the orchestrator role. When a second channel ships, prefer **channel-specific orchestrators** (`EmailNotificationEvents`) or a thin **facade** that delegates to channel stacks — without moving business logic into a monolithic god class.

### Rules that do not change

- Domain modules never call providers directly
- Builders never perform I/O
- Delivery failures never rollback domain operations
- Local schedule reminders stay on the mobile path
- New types require ADR/spec update before implementation

---

*Last updated: 2026-07-02 — initial guide (Scheduler + Smart Home Automations documentation phase).*
