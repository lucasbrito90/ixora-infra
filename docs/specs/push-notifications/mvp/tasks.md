# FCM / Push Notifications Foundation MVP — task checklist

**Status:** Phase 1 complete — pre-implementation  
**Spec:** [`spec.md`](spec.md)  
**Plan:** [`plan.md`](plan.md)  
**Feature ID:** `push-notifications/mvp`

**Status legend**

| Status | Meaning |
| --- | --- |
| **Pending** | Not started |
| **In progress** | Active work on branch |
| **Done** | Merged to `develop` / verified on staging |
| **Deferred** | Post-MVP or fast-follow |

---

## Task list summary

| Phase | Pending | In progress | Done | Deferred |
| --- | ---: | ---: | ---: | ---: |
| 1 — ADRs + Spec | 0 | 0 | 10 | 0 |
| 2 — Token registry schema | 5 | 0 | 0 | 0 |
| 3 — Push token API | 8 | 0 | 0 | 0 |
| 4 — Android FCM setup | 5 | 0 | 0 | 0 |
| 5 — Mobile token registration | 7 | 0 | 0 | 0 |
| 6 — Push provider abstraction | 6 | 0 | 0 | 0 |
| 7 — Queue-backed send job | 6 | 0 | 0 | 0 |
| 8 — Event integration | 6 | 0 | 0 | 0 |
| 9 — Tap handling | 5 | 0 | 0 | 0 |
| 10 — E2E QA | 8 | 0 | 0 | 0 |

---

## Phase 1 — ADRs + Spec

| ID | Task | Status | Reference |
| --- | --- | --- | --- |
| P1-1 | Publish **`spec.md`** (MVP source of truth) | **Done** | [`spec.md`](spec.md) |
| P1-2 | Publish **`plan.md`** | **Done** | [`plan.md`](plan.md) |
| P1-3 | Publish **`tasks.md`** | **Done** | This file |
| P1-4 | Draft **ADR-017** — Push notification provider strategy | **Done** | [`ADR-017`](../../../decisions/ADR-017-push-notification-provider-strategy.md) |
| P1-5 | Draft **ADR-018** — Device token registration | **Done** | [`ADR-018`](../../../decisions/ADR-018-device-token-registration.md) |
| P1-6 | Draft **ADR-019** — Notification event taxonomy | **Done** | [`ADR-019`](../../../decisions/ADR-019-notification-event-taxonomy.md) |
| P1-7 | Draft **ADR-020** — Push delivery and fallback strategy | **Done** | [`ADR-020`](../../../decisions/ADR-020-push-delivery-and-fallback-strategy.md) |
| P1-8 | Draft **ADR-021** — Notification security and privacy | **Done** | [`ADR-021`](../../../decisions/ADR-021-notification-security-and-privacy.md) |
| P1-9 | Add Push Notifications entry to **`docs/README.md`** index | **Done** | [`README.md`](../../../README.md) |
| P1-10 | Confirm **no runtime code** changed in Phase 1 | **Done** | This phase |

**Branch:** `feature/push-notifications-spec-adrs` from **`develop`**

**Phase 1 implementation notes:**

- Five ADRs (017–021) document provider strategy, token registry, event taxonomy, delivery semantics, and security/privacy.
- Spec defines `push_tokens` schema, draft API, services, mobile outline, Scheduler/Smart Home relationships, and payload examples.
- Plan defines 10-phase roadmap from schema through E2E QA.
- Explicit exclusions: iOS, marketing, campaigns, analytics push, rich notifications, notification inbox.
- No migrations, controllers, mobile runtime, Scheduler, or Smart Home code modified.

---

## Phase 2 — Backend token registry schema + model

| ID | Task | Status | Reference |
| --- | --- | --- | --- |
| P2-1 | Migration: create **`push_tokens`** table | **Pending** | [`spec.md`](spec.md) §4 |
| P2-2 | **`PushToken`** Eloquent model — fillable, casts, `active()` scope | **Pending** | [`ADR-018`](../../../decisions/ADR-018-device-token-registration.md) |
| P2-3 | **`User::pushTokens()`** relationship | **Pending** | |
| P2-4 | **`PushTokenFactory`** for Pest | **Pending** | |
| P2-5 | Feature tests: schema, unique token, user FK, active scope | **Pending** | |

**Branch:** `feature/push-notifications-token-model`

---

## Phase 3 — Backend push token API

| ID | Task | Status | Reference |
| --- | --- | --- | --- |
| P3-1 | **`PushTokenService`** — register, refresh, deactivate | **Pending** | [`spec.md`](spec.md) §6 |
| P3-2 | **`StorePushTokenRequest` / `RefreshPushTokenRequest`** | **Pending** | |
| P3-3 | **`PushTokenPolicy`** — owner scoping | **Pending** | |
| P3-4 | **`PushTokenController`** — store, refresh, destroy | **Pending** | [`spec.md`](spec.md) §5 |
| P3-5 | Routes: `POST /api/push-tokens`, `POST /api/push-tokens/refresh`, `DELETE /api/push-tokens/{id}` | **Pending** | |
| P3-6 | **`PushTokenResource`** — response shape | **Pending** | |
| P3-7 | Pest: auth required, upsert dedupe, refresh deactivates old, cross-user 403 | **Pending** | |
| P3-8 | Pest: full token never logged | **Pending** | [`ADR-021`](../../../decisions/ADR-021-notification-security-and-privacy.md) |

**Branch:** `feature/push-notifications-token-api`

---

## Phase 4 — Android FCM setup

| ID | Task | Status | Reference |
| --- | --- | --- | --- |
| P4-1 | Evaluate and add Capacitor Firebase Messaging dependency | **Pending** | [`plan.md`](plan.md) § Phase 4 |
| P4-2 | Configure **`google-services.json`** for staging build | **Pending** | |
| P4-3 | Document FCM server credentials for Laravel env | **Pending** | |
| P4-4 | Verify FCM token obtainable on installable debug build | **Pending** | |
| P4-5 | Document Android 13+ notification permission flow | **Pending** | [`ADR-011`](../../../decisions/ADR-011-scheduler-local-notifications-vs-future-fcm.md) |

**Branch:** `feature/push-notifications-android-fcm-setup`

---

## Phase 5 — Mobile token registration

| ID | Task | Status | Reference |
| --- | --- | --- | --- |
| P5-1 | **`push-token.service.ts`** — register, refresh, unregister | **Pending** | [`spec.md`](spec.md) §7 |
| P5-2 | Hook register after auth sync / login success | **Pending** | |
| P5-3 | Hook FCM `onTokenRefresh` → refresh API | **Pending** | |
| P5-4 | Hook logout → deactivate token | **Pending** | |
| P5-5 | Request notification permission before first register | **Pending** | |
| P5-6 | Fire-and-forget on register failure — do not block login | **Pending** | |
| P5-7 | Unit tests for service | **Pending** | |

**Branch:** `feature/push-notifications-mobile-token-registration`

---

## Phase 6 — Backend push provider abstraction

| ID | Task | Status | Reference |
| --- | --- | --- | --- |
| P6-1 | **`PushProvider`** interface | **Pending** | [`spec.md`](spec.md) §6 |
| P6-2 | **`NotificationPayload`** DTO | **Pending** | |
| P6-3 | **`FcmPushProvider`** — FCM HTTP v1 send | **Pending** | [`ADR-017`](../../../decisions/ADR-017-push-notification-provider-strategy.md) |
| P6-4 | **`config/push_notifications.php`** | **Pending** | |
| P6-5 | Register provider in service provider | **Pending** | |
| P6-6 | Pest tests with HTTP fake | **Pending** | |

**Branch:** `feature/push-notifications-fcm-provider`

---

## Phase 7 — Queue-backed push send job

| ID | Task | Status | Reference |
| --- | --- | --- | --- |
| P7-1 | **`PushNotificationService::sendToUser()`** | **Pending** | [`ADR-020`](../../../decisions/ADR-020-push-delivery-and-fallback-strategy.md) |
| P7-2 | **`PushNotificationJob`** — load tokens, call provider | **Pending** | |
| P7-3 | Deactivate invalid tokens on FCM unregistered response | **Pending** | |
| P7-4 | Queue config (name, timeout, tries) | **Pending** | |
| P7-5 | Structured logging — no full tokens | **Pending** | [`ADR-021`](../../../decisions/ADR-021-notification-security-and-privacy.md) |
| P7-6 | Pest: job queued, failure logged not thrown | **Pending** | |

**Branch:** `feature/push-notifications-send-job`

---

## Phase 8 — Scheduler + Smart Home event integration

| ID | Task | Status | Reference |
| --- | --- | --- | --- |
| P8-1 | Emit **`schedule_execution_failed`** from scheduler failure path | **Pending** | [`ADR-019`](../../../decisions/ADR-019-notification-event-taxonomy.md) |
| P8-2 | Emit **`smart_home_action_failed`** from `SmartHomeActionJob` | **Pending** | |
| P8-3 | Emit **`smart_home_provider_unreachable`** from provider failures | **Pending** | |
| P8-4 | All emits async via `PushNotificationService` only | **Pending** | [`ADR-020`](../../../decisions/ADR-020-push-delivery-and-fallback-strategy.md) |
| P8-5 | Confirm Scheduler dispatch loop unchanged | **Pending** | |
| P8-6 | Confirm Smart Home job never rethrows on push failure | **Pending** | [`ADR-016`](../../../decisions/ADR-016-smart-home-async-execution.md) |

**Branch:** `feature/push-notifications-event-integration`

---

## Phase 9 — Android notification tap handling

| ID | Task | Status | Reference |
| --- | --- | --- | --- |
| P9-1 | Foreground notification handler (minimal) | **Pending** | [`plan.md`](plan.md) § Phase 9 |
| P9-2 | Background tap → route by `data.type` | **Pending** | |
| P9-3 | `schedule_*` → player / schedule screen | **Pending** | |
| P9-4 | `smart_home_*` → devices tab | **Pending** | |
| P9-5 | Unit tests for routing logic | **Pending** | |

**Branch:** `feature/push-notifications-tap-handling`

---

## Phase 10 — E2E QA

| ID | Task | Status | Reference |
| --- | --- | --- | --- |
| P10-1 | Staging: register token via authenticated API | **Pending** | |
| P10-2 | Staging: send test notification (command or test endpoint) | **Pending** | |
| P10-3 | Device: login → token registered | **Pending** | |
| P10-4 | Device: logout → token deactivated | **Pending** | |
| P10-5 | Device: tap notification → correct screen | **Pending** | |
| P10-6 | Security: no secrets in FCM payload or logs | **Pending** | [`ADR-021`](../../../decisions/ADR-021-notification-security-and-privacy.md) |
| P10-7 | Regression: Scheduler local notifications still work | **Pending** | [`ADR-011`](../../../decisions/ADR-011-scheduler-local-notifications-vs-future-fcm.md) |
| P10-8 | Regression: Smart Home execution unaffected by push failure | **Pending** | [`ADR-016`](../../../decisions/ADR-016-smart-home-async-execution.md) |

**Branch:** `feature/push-notifications-e2e-qa`

---

## Cross-cutting validation tasks

| ID | Task | Status | When |
| --- | --- | --- | --- |
| X-1 | Confirm **no marketing/campaign** notification types | **Done** | Phase 1 — [ADR-019](../../../decisions/ADR-019-notification-event-taxonomy.md) |
| X-2 | Confirm **no analytics-triggered** push | **Done** | Phase 1 |
| X-3 | Confirm **no Scheduler code modified** in Phase 1 | **Done** | Phase 1 |
| X-4 | Confirm **no Smart Home execution modified** in Phase 1 | **Done** | Phase 1 |
| X-5 | Confirm **no mobile runtime modified** in Phase 1 | **Done** | Phase 1 |
| X-6 | Confirm **local notifications preserved** | **Done** | [ADR-020](../../../decisions/ADR-020-push-delivery-and-fallback-strategy.md) |
| X-7 | Confirm **backend-only push send** | **Done** | [ADR-017](../../../decisions/ADR-017-push-notification-provider-strategy.md) |
| X-8 | Laravel full test suite on **`back_vibes`** touch | **Pending** | Each backend PR |
| X-9 | **`front_vibes` production build** clean | **Pending** | Each mobile PR |

---

## Done criteria (MVP)

### Documentation (Phase 1)

- [x] `spec.md`, `plan.md`, `tasks.md` published under `docs/specs/push-notifications/mvp/`
- [x] ADR-017, ADR-018, ADR-019, ADR-020, ADR-021 accepted
- [x] `docs/README.md` updated with Push Notifications section
- [x] No runtime code changed in Phase 1

### Implementation (Phases 2–10)

- [ ] `push_tokens` table migrated and tested
- [ ] Push token API live on staging
- [ ] Android FCM token registration on login
- [ ] FCM push send via queue worker
- [ ] Scheduler / Smart Home failure events enqueue push
- [ ] Notification tap routing on Android
- [ ] E2E QA report published

---

## Explicit non-goals (reminder)

| Non-goal | ADR / spec reference |
| --- | --- |
| iOS / APNs | [ADR-017](../../../decisions/ADR-017-push-notification-provider-strategy.md) |
| Marketing / campaigns | [ADR-019](../../../decisions/ADR-019-notification-event-taxonomy.md) |
| Analytics push | [spec.md](spec.md) §3 |
| Rich notifications / inbox | [spec.md](spec.md) §3 |
| Replace local notifications | [ADR-020](../../../decisions/ADR-020-push-delivery-and-fallback-strategy.md) |
| Guaranteed delivery | [ADR-020](../../../decisions/ADR-020-push-delivery-and-fallback-strategy.md) |
