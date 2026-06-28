# FCM / Push Notifications Foundation MVP — implementation plan

**Status:** Active implementation plan (Phase 1 complete — pre-implementation)  
**Spec:** [`spec.md`](spec.md)  
**Feature ID:** `push-notifications/mvp`

---

## Implementation summary

The FCM / Push Notifications Foundation delivers **Android FCM transport**, a **backend device token registry**, a **provider abstraction** for push sending, and **queue-backed best-effort delivery** for operational IXORA events. Marketing, campaigns, and analytics-triggered push are explicitly excluded.

**Strategy anchors:**

| Principle | Implementation |
| --- | --- |
| FCM first, Android first | `FcmPushProvider` (production) + `NoopPushProvider` (tests/local) in MVP |
| Backend authoritative | Laravel decides what to send and to whom |
| FCM is transport only | No business logic in FCM layer |
| Token registry with dedupe | `push_tokens` table, unique on `token` |
| Async non-blocking send | `PushNotificationJob` on queue worker |
| Local notifications preserved | Scheduler reminders unchanged ([ADR-011](../../../decisions/ADR-011-scheduler-local-notifications-vs-future-fcm.md)) |
| Privacy-safe payloads | IDs only in data; no secrets ([ADR-021](../../../decisions/ADR-021-notification-security-and-privacy.md)) |
| No campaigns | Event taxonomy operational only ([ADR-019](../../../decisions/ADR-019-notification-event-taxonomy.md)) |

**Git Flow:** All work on **`feature/*`** branches from **`develop`** — [`git-flow.md`](../../../standards/git-flow.md). Promote to **`staging`** via merge **`develop` → `staging`**.

---

## Current state

| Area | State |
| --- | --- |
| **`push_tokens` table** | **Does not exist** |
| **`PushToken` model** | **None** |
| **Push token API** | **None** |
| **`PushProvider` / `FcmPushProvider`** | **None** |
| **`PushNotificationJob`** | **None** |
| **Android FCM integration** | **None** — Firebase used for auth only |
| **Mobile token registration** | **None** |
| **Scheduler push hooks** | **None** — local notifications only |
| **Smart Home push hooks** | **None** |
| **ADRs 017–021** | **Accepted** — Phase 1 complete |
| **Scheduler MVP** | Complete — local notifications shipped |
| **Smart Home MVP** | Complete — async execution shipped |

---

## Phase overview

```
Phase 1  ──► ADRs + Spec (complete)
Phase 2  ──► Backend token registry schema + model
Phase 3  ──► Backend push token API
Phase 4  ──► Android FCM setup (Capacitor + Firebase config)
Phase 5  ──► Mobile token registration (login / refresh / logout)
Phase 6  ──► Backend push provider abstraction (FcmPushProvider)
Phase 7  ──► Queue-backed push send job
Phase 8  ──► Scheduler + Smart Home event integration
Phase 9  ──► Android notification tap handling
Phase 10 ──► E2E QA
```

Phases **2–3** (backend registry) can start immediately after Phase 1. Phase **4–5** (mobile) depends on Phase 3 API contract. Phase **6–7** (provider + job) can proceed in parallel with Phase 5 after API exists. Phase **8** depends on Phase 7 and existing Scheduler/Smart Home code. Phase **9** depends on Phase 5.

---

## Phase 1 — ADRs + Spec

**Complete.**

### Deliverables

| Item | Output |
| --- | --- |
| Feature spec | [`spec.md`](spec.md) |
| Implementation plan | [`plan.md`](plan.md) |
| Task checklist | [`tasks.md`](tasks.md) |
| **ADR-017** | [`ADR-017-push-notification-provider-strategy.md`](../../../decisions/ADR-017-push-notification-provider-strategy.md) |
| **ADR-018** | [`ADR-018-device-token-registration.md`](../../../decisions/ADR-018-device-token-registration.md) |
| **ADR-019** | [`ADR-019-notification-event-taxonomy.md`](../../../decisions/ADR-019-notification-event-taxonomy.md) |
| **ADR-020** | [`ADR-020-push-delivery-and-fallback-strategy.md`](../../../decisions/ADR-020-push-delivery-and-fallback-strategy.md) |
| **ADR-021** | [`ADR-021-notification-security-and-privacy.md`](../../../decisions/ADR-021-notification-security-and-privacy.md) |
| **docs/README.md** | Push Notifications index entry |

### Decisions locked in ADRs

| Topic | Decision |
| --- | --- |
| **Provider** | FCM first; backend abstraction; Android first |
| **Token registry** | `push_tokens` upsert; unique on token; multi-device |
| **Event taxonomy** | 5 MVP operational types; no marketing |
| **Delivery** | Async queue; best-effort; non-blocking |
| **Security** | Minimal payload; no secrets; no cross-user tokens |

---

## Phase 2 — Backend token registry schema + model

**No API yet. Migration + model + tests only.**

### Goals

- Create `push_tokens` table per [`spec.md`](spec.md) §4
- `PushToken` Eloquent model with casts, scopes (`active()`), relationships
- `User::pushTokens()` relationship
- Factory + Pest tests for schema, unique constraint, soft deactivate fields

### Branch

`feature/push-notifications-token-model`

---

## Phase 3 — Backend push token API

### Goals

- `PushTokenController` — register, refresh, delete
- Form requests: `StorePushTokenRequest`, `RefreshPushTokenRequest`
- `PushTokenService` — upsert, deactivate, refresh logic
- `PushTokenPolicy` — owner scoping
- `PushTokenResource` — omit full token in list responses if list endpoint added
- Routes: `POST /api/push-tokens`, `POST /api/push-tokens/refresh`, `DELETE /api/push-tokens/{id}`
- Pest feature tests: auth, upsert dedupe, refresh deactivates old, logout deactivate, cross-user 403

### Branch

`feature/push-notifications-token-api`

---

## Phase 4 — Android FCM setup

### Goals

- Add Capacitor Firebase Messaging dependency (evaluate `@capacitor-firebase/messaging` or project-standard plugin)
- Configure `google-services.json` for staging/production build flavors
- Document FCM server credentials setup for Laravel (service account JSON in env)
- Verify FCM token obtainable on installable debug build
- **No token registration API call yet** — setup only

### Branch

`feature/push-notifications-android-fcm-setup`

---

## Phase 5 — Mobile token registration

### Goals

- `push-token.service.ts` — register, refresh, unregister via Laravel API
- Hook after auth sync success (login)
- Hook on FCM token refresh listener
- Hook on logout — deactivate current token
- Request notification permission (Android 13+) before first register
- Unit tests for service (mock API)
- Fire-and-forget on register failure — do not block login

### Branch

`feature/push-notifications-mobile-token-registration`

---

## Phase 6 — Backend push provider abstraction

### Goals

Prove the provider abstraction layer and FCM HTTP v1 integration. **Phase 6 does not enqueue jobs, does not integrate Scheduler, and does not integrate Smart Home.** It only establishes that `PushProvider` can be swapped, that `FcmPushProvider` can call FCM, and that `NoopPushProvider` gives safe local/test behavior behind the same interface.

### Deliverables

| Item | Notes |
| --- | --- |
| **`PushProvider` interface** | `send(PushToken, NotificationPayload): PushResult` — one token per call |
| **`NotificationPayload` DTO** | `title`, `body`, `data`, `type`, `android?` — per spec §6 |
| **`PushResult` DTO** | `success`, `provider`, `statusCode`, `messageId`, `errorCode`, `errorMessage`, `tokenPreview` |
| **`FcmPushProvider`** | Calls FCM HTTP v1 API; returns `PushResult`; uses `tokenPreview` in logs — no full token |
| **`NoopPushProvider`** | Returns successful dry-run `PushResult`; safe for local dev without Firebase credentials |
| **`config/push_notifications.php`** | `provider` key (`'fcm'` \| `'noop'`); FCM project ID and credentials path |
| **`PushProviderResolver` / service provider binding** | Binds `PushProvider` from config; unsupported values throw at boot — no silent fallback |
| **Pest tests** | `FcmPushProvider` with HTTP fake (no real FCM in CI); `NoopPushProvider` returns correct shape; resolver throws on unknown provider |

### Phase 6 DTO scope (current fields only)

Phase 6 implements **`NotificationPayload`** with these fields only:

| Field | Notes |
| --- | --- |
| `title` | Display title |
| `body` | Display body |
| `data` | String key-value routing payload |
| `type` | ADR-019 event type |
| `android` | Optional — mapped to FCM `android` block by `FcmPushProvider` |

**Future extensions (documented, not implemented in Phase 6):**

- `collapseKey` / `tag` — collapse duplicate notifications for the same logical event
- `priority` — `low` \| `normal` \| `high` delivery urgency hint

These are architecture placeholders only. Do not add them to the Phase 6 runtime DTO unless a later task explicitly scopes them.

### Hard boundaries for Phase 6

| Out of scope | Reason |
| --- | --- |
| `PushNotificationJob` | Phase 7 |
| `PushNotificationService::sendToUser()` | Phase 7 |
| Scheduler event hooks | Phase 8 |
| Smart Home event hooks | Phase 8 |
| Invalid-token deactivation loop | Phase 7 job responsibility |

### Branch

`feature/push-notifications-fcm-provider`

---

## Phase 7 — Queue-backed push send job

### Goals

- `PushNotificationService::sendToUser()`
- `PushNotificationJob` — load active tokens, call provider, deactivate invalid tokens
- Queue config (name, timeout, tries) in `config/push_notifications.php`
- Structured logging — no full tokens in logs
- Pest tests: job dispatched, no inline FCM in controllers, failure logged not thrown

### Branch

`feature/push-notifications-send-job`

---

## Phase 8 — Scheduler + Smart Home event integration

### Goals

- Emit `schedule_execution_failed` from scheduler failure path (when applicable)
- Emit `smart_home_action_failed` from `SmartHomeActionJob` failure log path
- Emit `smart_home_provider_unreachable` from provider connection failures
- All emits via `PushNotificationService` — async dispatch only
- **Do not modify** scheduler dispatch loop blocking behaviour
- **Do not modify** Smart Home job rethrow policy
- Pest tests: domain job completes even when push job fails; push job queued on failure event

### Branch

`feature/push-notifications-event-integration`

---

## Phase 9 — Android notification tap handling

### Goals

- Foreground notification handler (minimal)
- Background/killed tap → parse `data.type` → route:
  - `schedule_*` → schedule or player
  - `smart_home_*` → devices tab
  - `account_security_notice` → settings/security
- Unit tests for routing logic
- Manual QA checklist for tap flows

### Branch

`feature/push-notifications-tap-handling`

---

## Phase 10 — E2E QA

### Goals

- Staging: register token via authenticated API
- Staging: trigger test notification (admin/artisan command or test endpoint — TBD)
- Device: login → token registered
- Device: logout → token deactivated
- Device: tap notification → correct screen
- Verify no secrets in FCM payload (logcat / staging logs)
- Verify Scheduler local notifications still work
- Verify Smart Home execution unaffected by push failure
- QA report under `docs/qa/push-notifications-e2e/` (future)

### Branch

`feature/push-notifications-e2e-qa`

---

## Explicit exclusions (all phases)

| Exclusion | Reason |
| --- | --- |
| iOS / APNs | Future ADR |
| Marketing / campaigns | [ADR-019](../../../decisions/ADR-019-notification-event-taxonomy.md) |
| Analytics-triggered push | Out of roadmap item scope |
| Notification inbox UI | Post-MVP |
| Replacing local notifications | [ADR-020](../../../decisions/ADR-020-push-delivery-and-fallback-strategy.md) |
| Modifying Scheduler recurrence | Out of scope |
| Modifying Smart Home action types | Out of scope |

---

## Related docs

| Document | Relationship |
| --- | --- |
| [`spec.md`](spec.md) | MVP source of truth |
| [`tasks.md`](tasks.md) | Checklist |
| [`ADR-011`](../../../decisions/ADR-011-scheduler-local-notifications-vs-future-fcm.md) | Local notification baseline |
| [`../scheduler/mvp/plan.md`](../scheduler/mvp/plan.md) | Scheduler implementation reference |
| [`../smart-home/mvp/plan.md`](../smart-home/mvp/plan.md) | Smart Home implementation reference |
