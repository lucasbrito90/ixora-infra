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
| **FCM first** | MVP implements `FcmPushProvider` only. |
| **iOS deferred** | APNs provider is a future ADR + phase. |
| **No campaigns** | No broadcast, segmentation, A/B testing, or promotional push in MVP. |
| **No analytics push** | No behavioural nudges or analytics-triggered notifications. |

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
| **Clear MVP boundary** | No campaign/marketing scope creep |

### Negative / tradeoffs

| Tradeoff | Impact |
| --- | --- |
| **Android-only MVP** | iOS users receive no remote push until APNs phase |
| **FCM dependency** | Push delivery depends on Google infrastructure and server credentials |
| **Dual notification paths** | Local notifications (Scheduler) + FCM (remote events) coexist — mobile must handle both |
| **Server credential management** | FCM service account / server key must be stored securely on backend |

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
