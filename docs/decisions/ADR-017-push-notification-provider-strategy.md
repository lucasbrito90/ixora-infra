# ADR-017: Push notification provider strategy

## Status

**Accepted** — governs the **FCM / Push Notifications Foundation** ([`specs/push-notifications/mvp/spec.md`](../specs/push-notifications/mvp/spec.md)).

## Date

2026-06-21

## Context

IXORA already ships:

- **Firebase Authentication** on mobile and Laravel ([ADR-001](ADR-001-firebase-auth-laravel-sync.md))
- **Android mobile app** (Ionic + Vue + Capacitor) with Firebase-related configuration for auth
- **Scheduler MVP** with **local notifications** as the sole reminder mechanism ([ADR-011](ADR-011-scheduler-local-notifications-vs-future-fcm.md))
- **Smart Home MVP** with async, queue-backed device action execution ([ADR-016](ADR-016-smart-home-async-execution.md))

The product roadmap now includes **FCM / Push Notifications** as the next major capability. The team needs a provider strategy before any runtime code ships.

Constraints:

1. **Laravel remains the source of truth** for notification intent — what to send, to whom, and when.
2. **FCM is transport only** — not business logic, not a second auth system, not a campaign platform.
3. **Mobile must not send push directly** — all outbound notifications originate from the backend after domain events.
4. **Android first** — the current primary client is Android; iOS/APNs is a future phase.
5. **No marketing scope** — MVP is operational/system notifications only.
6. **Existing Firebase project** — auth already uses Firebase; FCM reuses the same project infrastructure where possible.

---

## Decision

**Use Firebase Cloud Messaging (FCM) as the first push transport provider. Android FCM first. Backend sends push through a provider abstraction. Mobile registers device tokens with Laravel. Laravel remains the source of truth for notification intent. FCM is transport only. Do not send push directly from mobile. Do not implement marketing or campaign notifications in MVP.**

### Provider model

| Layer | Role |
| --- | --- |
| **Domain event** | Scheduler failure, Smart Home failure, account security notice, etc. |
| **Laravel notification service** | Resolves recipients, builds payload, enqueues send job |
| **`PushProvider` interface** | Abstracts transport — FCM first, APNs future |
| **`FcmPushProvider`** | Sends to FCM HTTP v1 API using server credentials |
| **FCM** | Delivers to device — best-effort transport |
| **Mobile** | Registers token, receives notification, handles tap |

### Transport rules

| Rule | Detail |
| --- | --- |
| **Backend-only send** | Only Laravel queue jobs / services call FCM. Mobile never sends push. |
| **Provider abstraction** | `PushProvider` contract allows future APNs without rewriting domain logic. |
| **FCM first** | MVP ships `FcmPushProvider` for production and `NoopPushProvider` for tests / local dev. |
| **iOS deferred** | APNs provider is a future ADR + phase. |
| **No campaigns** | No broadcast, segmentation, A/B testing, or promotional push in MVP. |
| **No analytics push** | No behavioural nudges or analytics-triggered notifications. |

### Provider contract

All push sending goes through the `PushProvider` interface. The interface operates on **one token at a time** — fan-out to multiple user devices is the responsibility of the `PushNotificationService` / job layer, not the provider.

```
PushProvider::send(
    PushToken $token,
    NotificationPayload $payload
): PushResult
```

| Boundary rule | Detail |
| --- | --- |
| **One token per call** | Provider receives a single `PushToken` — no batch array |
| **Fan-out belongs upstream** | `PushNotificationJob` iterates tokens; provider handles one |
| **No domain knowledge** | Provider must not know Scheduler or Smart Home logic |
| **No full token in logs** | Provider uses `PushToken::tokenPreview()` for any log output ([ADR-021](ADR-021-notification-security-and-privacy.md)) |
| **Explicit failure** | Provider throws or returns a failed `PushResult` — never silently drops |

### `NotificationPayload` — provider-agnostic domain DTO

`NotificationPayload` is a **provider-agnostic domain DTO**. It expresses IXORA notification intent (title, body, routing data, event type) and must **not** mirror FCM HTTP v1 JSON directly.

Each provider maps `NotificationPayload` into its own transport format:

| Provider | Transport mapping |
| --- | --- |
| **`FcmPushProvider`** | Maps to FCM HTTP v1 `message` JSON (`notification`, `data`, optional `android`) |
| **`ApnsPushProvider`** *(future)* | Maps to APNs JSON payload |
| **`NoopPushProvider`** | No transport — returns a dry-run `PushResult` only |

Domain services and queue jobs build `NotificationPayload` only. Raw FCM/APNs request bodies are constructed **inside** the provider implementation, never in callers.

### `PushResult.messageId` — optional and provider-dependent

`messageId` is **optional** and **provider-dependent**:

| Provider | `messageId` on success |
| --- | --- |
| **`FcmPushProvider`** | FCM response `name` (e.g. `projects/{project}/messages/{id}`) |
| **`ApnsPushProvider`** *(future)* | APNs `apns-id` header value |
| **`NoopPushProvider`** | Always `null` |

Callers must not assume every successful send returns a transport ID. Use `messageId` for audit/tracing when present; omit from required downstream logic in MVP.

### Future payload extensions (deferred)

The following may be added to `NotificationPayload` in a later phase to improve delivery semantics. They are **not** part of MVP Phase 6 unless explicitly added in a follow-up task:

| Field | Purpose |
| --- | --- |
| **`collapseKey` / `tag`** | Avoid duplicate notification stacking when the same logical event fires repeatedly (e.g. repeated schedule failures) |
| **`priority`** | Route as `low` \| `normal` \| `high` for provider-specific urgency handling |

Do not implement collapse/deduplication or priority routing in Phase 6.

### Provider implementations (MVP)

| Implementation | Role |
| --- | --- |
| **`FcmPushProvider`** | Production provider — calls FCM HTTP v1 API with server credentials |
| **`NoopPushProvider`** | Tests + local dev — returns a successful dry-run `PushResult` without contacting FCM |

**`NoopPushProvider` rules:**

- Returns a successful `PushResult` (or configurable result) without any HTTP call.
- Logs a safe, preview-only dry-run notice for diagnostic visibility.
- **Must never reach production accidentally** — provider selection is config-driven (see `config/push_notifications.php`).
- Is the **default for unsupported or missing credential** environments only when the config explicitly opts in.
- Unsupported provider values in config must **fail explicitly** at boot (not silently fall back).

### Provider selection

Provider is resolved at service-container binding time from config:

```
config('push_notifications.provider')  →  'fcm' | 'noop'
```

- `'fcm'` → binds `FcmPushProvider` (requires FCM credentials env vars).
- `'noop'` → binds `NoopPushProvider` (safe for local dev / CI without Firebase credentials).
- Any other value → **exception at boot** — no silent fallback.

### Relationship to ADR-011

[ADR-011](ADR-011-scheduler-local-notifications-vs-future-fcm.md) established **local notifications** for schedule reminders in the Scheduler MVP. This ADR does **not** replace local notifications immediately. FCM **complements** local notifications for remote/system events (see [ADR-020](ADR-020-push-delivery-and-fallback-strategy.md)).

---

## Consequences

### Positive

| Outcome | Why it matters |
| --- | --- |
| **Reuses Firebase project** | Auth infrastructure already in place; lower setup friction |
| **Backend authority preserved** | Notification intent stays in Laravel — consistent with Scheduler and Smart Home ADRs |
| **Provider abstraction** | Future APNs without rewriting event taxonomy or mobile registration |
| **`NoopPushProvider`** | Tests and local dev work without Firebase credentials; CI never calls FCM |
| **Clear MVP boundary** | No campaign/marketing scope creep |

### Negative / tradeoffs

| Tradeoff | Impact |
| --- | --- |
| **Android-only MVP** | iOS users receive no remote push until APNs phase |
| **FCM dependency** | Push delivery depends on Google infrastructure and server credentials |
| **Dual notification paths** | Local notifications (Scheduler) + FCM (remote events) coexist — mobile must handle both |
| **Server credential management** | FCM service account / server key must be stored securely on backend |
| **Noop misconfiguration risk** | `NoopPushProvider` must be blocked from production by config guard — not purely a code concern |

---

## Alternatives Considered

| Alternative | Why not chosen (MVP) |
| --- | --- |
| **Mobile sends push directly** | Rejected — no business logic on client; no cross-device targeting |
| **OneSignal / Pusher / third-party campaign platform** | Rejected — adds vendor; marketing scope excluded |
| **Email/SMS as primary channel** | Out of scope — push-first for mobile operational events |
| **FCM-only, no abstraction** | Rejected — iOS will need APNs; abstraction cost is low |
| **Replace local notifications with FCM immediately** | Rejected — local notifications remain useful offline ([ADR-020](ADR-020-push-delivery-and-fallback-strategy.md)) |
| **Web push first** | Rejected — mobile Android is primary client |
| **No `NoopPushProvider`, mock only in tests** | Rejected — Noop behind the same contract allows local dev without Firebase credentials and tests the real binding path |

---

## Related Docs

| Document | Relationship |
| --- | --- |
| [`ADR-001`](ADR-001-firebase-auth-laravel-sync.md) | Firebase project shared with auth |
| [`ADR-011`](ADR-011-scheduler-local-notifications-vs-future-fcm.md) | Local notifications remain; FCM is additive |
| [`ADR-016`](ADR-016-smart-home-async-execution.md) | Smart Home failures enqueue push async — same non-blocking pattern |
| [`ADR-018`](ADR-018-device-token-registration.md) | Token registry model |
| [`ADR-019`](ADR-019-notification-event-taxonomy.md) | Event types and payload schema |
| [`ADR-020`](ADR-020-push-delivery-and-fallback-strategy.md) | Delivery semantics |
| [`ADR-021`](ADR-021-notification-security-and-privacy.md) | Payload privacy rules |
| [`../specs/push-notifications/mvp/spec.md`](../specs/push-notifications/mvp/spec.md) | MVP scope |
| [`../specs/push-notifications/mvp/plan.md`](../specs/push-notifications/mvp/plan.md) | Implementation phases |

---

When iOS/APNs support ships, create a follow-up ADR documenting APNs provider implementation and certificate/key management. Reference this ADR as the provider strategy foundation.
