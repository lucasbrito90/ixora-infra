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
| 2 — Token registry schema | 0 | 0 | 5 | 0 |
| 3 — Push token API | 0 | 0 | 8 | 0 |
| 4 — Android FCM setup | 0 | 0 | 5 | 0 |
| 5 — Mobile token registration | 0 | 0 | 7 | 0 |
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
| P2-1 | Migration: create **`push_tokens`** table | **Done** | [`spec.md`](spec.md) §4 |
| P2-2 | **`PushToken`** Eloquent model — fillable, casts, `active()` scope | **Done** | [`ADR-018`](../../../decisions/ADR-018-device-token-registration.md) |
| P2-3 | **`User::pushTokens()`** relationship | **Done** | |
| P2-4 | **`PushTokenFactory`** for Pest | **Done** | |
| P2-5 | Feature tests: schema, unique token, user FK, active scope | **Done** | |

**Branch:** `feature/push-notifications-token-model`

**Phase 2 implementation notes:**

- Migration `2026_06_22_000001_create_push_tokens_table.php` — columns per spec; indexes `uq_push_tokens_token` and `idx_push_tokens_user_active`; optional `unique(user_id, device_id, provider)` documented as comment only (deferred until stable device_id).
- `PushToken` model — `$hidden = ['token']`, `tokenPreview()`, `tokenHash()`, `scopeActive()`; `user_id` not fillable (assigned via factory unguard or future service).
- Enums: `PushProvider` (fcm), `PushPlatform` (android/ios/web; MVP android only).
- `PushTokenFactory` with `inactive()`, `android()`, `fcm()` states.
- Tests: `tests/Feature/PushNotifications/PushTokenModelTest.php` — 22 tests covering schema, privacy helpers, casts, scope, unique constraint, relationships, factory states, enums.
- No API routes, controllers, FCM provider, queue jobs, mobile, Scheduler, or Smart Home changes.

---

## Phase 3 — Backend push token API

| ID | Task | Status | Reference |
| --- | --- | --- | --- |
| P3-1 | **`PushTokenService`** — register, refresh, deactivate | **Done** | [`spec.md`](spec.md) §6 |
| P3-2 | **`StorePushTokenRequest` / `RefreshPushTokenRequest`** | **Done** | |
| P3-3 | **`PushTokenPolicy`** — owner scoping | **Done** | |
| P3-4 | **`PushTokenController`** — store, refresh, destroy | **Done** | [`spec.md`](spec.md) §5 |
| P3-5 | Routes: `POST /api/push-tokens`, `POST /api/push-tokens/refresh`, `DELETE /api/push-tokens/{id}` | **Done** | |
| P3-6 | **`PushTokenResource`** — response shape | **Done** | |
| P3-7 | Pest: auth required, upsert dedupe, refresh deactivates old, cross-user 403 | **Done** | |
| P3-8 | Pest: full token never logged | **Done** | [`ADR-021`](../../../decisions/ADR-021-notification-security-and-privacy.md) |

**Branch:** `feature/push-notifications-token-api`

**Phase 3 implementation notes:**

- `PushTokenService` — `register()` upserts by token with `firstOrNew`; ownership always set to authenticated user (MVP reassignment behavior, ADR-018). `refresh()` deactivates old_token only if owned by current user. `deactivate()` soft-deactivates. `safeTokenContext()` returns id, token_preview, platform, provider for structured logging.
- `PushTokenPolicy` — owner scoping on view/update/delete; viewAny/create open to any authenticated user.
- `StorePushTokenRequest` / `RefreshPushTokenRequest` — platform limited to `PushPlatform::mvpAllowed()` (android only); provider limited to `PushProvider::mvpAllowed()` (fcm only); user_id/is_active/revoked_at/last_seen_at prohibited.
- `PushTokenResource` — exposes id, platform, provider, device_id, app_version, device_model, is_active, last_seen_at, revoked_at, created_at, updated_at, token_preview. Raw token is never exposed (ADR-021).
- `PushTokenController` — store returns 201 on create / 200 on upsert via `wasRecentlyCreated`. refresh route registered before `{pushToken}` wildcard to avoid route conflict.
- Routes — `POST /api/push-tokens/refresh` before `POST /api/push-tokens` and `DELETE /api/push-tokens/{pushToken}` inside `firebase.auth` middleware group.
- Tests — 28 Pest tests in `tests/Feature/PushNotifications/PushTokenApiTest.php` covering: auth guard (3), store happy path (2), user_id injection (1), platform/provider validation (4), prohibited field injection (3), upsert/dedupe (3), provider default (1), refresh happy path (4), destroy happy path (2), token privacy (5), unique constraint upsert (1).
- No FCM sending, PushProvider interface, PushNotificationJob, mobile, Scheduler, Smart Home, marketing, or analytics logic added.

---

## Phase 4 — Android FCM setup

| ID | Task | Status | Reference |
| --- | --- | --- | --- |
| P4-1 | Evaluate and add Capacitor Firebase Messaging dependency | **Done** | [`plan.md`](plan.md) § Phase 4 |
| P4-2 | Configure **`google-services.json`** for staging build | **Done** | |
| P4-3 | Document FCM server credentials for Laravel env | **Done** | |
| P4-4 | Verify FCM token obtainable on installable debug build | **Done** (implementation) / QA pending (requires physical device) | |
| P4-5 | Document Android 13+ notification permission flow | **Done** | [`ADR-011`](../../../decisions/ADR-011-scheduler-local-notifications-vs-future-fcm.md) |

**Branch:** `feature/push-notifications-android-fcm-setup`

**Phase 4 implementation notes:**

- **Plugin selected:** `@capacitor-firebase/messaging@8.3.0` — peer-compatible with `@capacitor/core@8.3.1` and `firebase@12.12.1`. Added `.npmrc` with `legacy-peer-deps=true` to resolve pre-existing `@codetrix-studio/capacitor-google-auth` peer conflict.
- **P4-2 — `google-services.json`:** File already present at `android/app/google-services.json`. `android/build.gradle` already has `classpath 'com.google.gms:google-services:4.4.4'`. `android/app/build.gradle` already conditionally applies the plugin when the file exists. No changes required.
- **P4-3 — FCM server credentials for Laravel:** The backend (`back_vibes`) will need a Firebase service account key (`FIREBASE_CREDENTIALS` env) for Phase 6 (FcmPushProvider). The `google-services.json` in the Android project is the **client** config; the server needs the separate service account JSON from Firebase Console → Project Settings → Service Accounts → Generate new private key. Store as `FIREBASE_CREDENTIALS` (base64 or path) in Laravel `.env`. Do not commit to source control.
- **P4-4 — FCM token obtainable:** `getFcmToken()` implemented via `@capacitor-firebase/messaging`. Physical device QA: run `devVerifyFcmToken()` from the debug console on a real Android device after building the APK. Token preview will be logged (not the full token). Full E2E device verification deferred to Phase 10.
- **P4-5 — Android 13+ permission:** `requestFcmPermission()` calls `FirebaseMessaging.requestPermissions()` which handles `POST_NOTIFICATIONS` permission on Android 13+ (API 33+). On Android < 13, permission is granted implicitly. The service returns `false` and degrades gracefully if denied. No UI is required at this phase — Phase 5 will integrate permission request into the auth/login flow.
- **`fcmTokenService`:** `src/services/fcm-token.service.ts` — `isFcmAvailable()`, `requestFcmPermission()`, `getFcmToken()`, `fcmTokenPreview()` (ADR-021 compliant), `devVerifyFcmToken()` (dev-only, logs preview only). Web is a safe no-op. No backend calls, no token storage, no full token logging.
- **Tests:** `src/services/__tests__/fcm-token.service.test.ts` — 20 Vitest tests covering: tokenPreview (4), isFcmAvailable (2), requestFcmPermission (5), getFcmToken (4), devVerifyFcmToken (4), service shape (1).
- No backend/token registration/PushProvider/PushNotificationJob/Scheduler/Smart Home/marketing logic added.

---

## Phase 5 — Mobile token registration

| ID | Task | Status | Reference |
| --- | --- | --- | --- |
| P5-1 | **`push-token.service.ts`** — register, refresh, unregister | **Done** | [`spec.md`](spec.md) §7 |
| P5-2 | Hook register after auth sync / login success | **Done** | `useAuth.ts` — fire-and-forget after `persistToken` in all three login paths |
| P5-3 | Hook FCM `onTokenRefresh` → refresh API | **Done** | `initPushTokenRefreshListener()` via `addListener('tokenReceived')` — registered in `App.vue` |
| P5-4 | Hook logout → deactivate token | **Done** | `useAuth.logout()` — non-fatal `deactivateCurrentDevicePushToken()` |
| P5-5 | Request notification permission before first register | **Done** | `registerCurrentDevicePushToken()` calls `requestFcmPermission()` first |
| P5-6 | Fire-and-forget on register failure — do not block login | **Done** | `void pushTokenService.registerCurrentDevicePushToken()` — errors caught internally |
| P5-7 | Unit tests for service | **Done** | `src/services/__tests__/push-token.service.test.ts` — 27 tests |

**Branch:** `feature/push-notifications-mobile-token-registration`

**Phase 5 implementation notes:**

- **`push-token.service.ts`** — `registerPushToken()`, `refreshPushToken()`, `deactivatePushToken()` (raw API calls with Firebase Bearer); `registerCurrentDevicePushToken()` and `deactivateCurrentDevicePushToken()` (high-level device helpers); `initPushTokenRefreshListener()` (singleton FCM token-rotation listener). All functions follow existing `laravelFetch` + `getRequiredIdToken` pattern.
- **Preferences storage:** only `id` (number as string) and `token_preview` are persisted — full FCM token is never stored (ADR-021). Keys: `ixora_push_token_id_v1`, `ixora_push_token_value_preview_v1`.
- **`old_token` on refresh:** intentionally omitted from `RefreshPushTokenPayload`. The backend upserts by `new_token` value — no full token storage required.
- **`useAuth.ts`:** `void pushTokenService.registerCurrentDevicePushToken()` added after `persistToken()` in `loginWithGoogle`, `loginWithEmail`, and `signUpWithEmail`. `deactivateCurrentDevicePushToken()` added as non-fatal step in `logout()` (same pattern as `scheduleMirrorService.clearMirror()`).
- **`App.vue`:** `pushTokenService.initPushTokenRefreshListener()` called once at root component setup — ensures the FCM rotation listener is always active regardless of navigation.
- **`_resetListenerForTest()`:** exported test helper following `useScheduleNotificationHandler.ts` pattern.
- **Tests — 27 Vitest tests** covering: `registerPushToken` (4), `refreshPushToken` (4), `deactivatePushToken` (2), `registerCurrentDevicePushToken` (8: web no-op, permission denied, null token, success path, stores id, stores preview not full token, failure no-throw, network error no-throw, warn output clean), `deactivateCurrentDevicePushToken` (6: calls DELETE, skips when no id, clears prefs, clears prefs on error, no-throw on error, no-throw on prefs failure), `initPushTokenRefreshListener` (7: web no-op, registers listener, singleton guard, reset + re-register, callback calls refresh, callback updates prefs, no full token in warn), service shape (1).
- No FCM sending, PushProvider, PushNotificationJob, backend, Scheduler, Smart Home, tap routing, marketing, or analytics logic added.

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
