# FCM / Push Notifications Foundation MVP — device token registry + backend abstraction

**Status:** Active feature specification (source of truth for Phase 1 delivery)  
**Version:** 1.0 (MVP scope — documentation only; no runtime code implemented)  
**Feature ID:** `push-notifications/mvp`  
**Platform:** `back_vibes` (authoritative), `front_vibes` Android (mobile client)

> **Phase 1 = ADRs + Spec only.** No migrations, controllers, mobile runtime changes, queue jobs, or FCM integration are part of Phase 1. Phase 2 begins the backend device token registry.

**Architecture decisions:** [ADR-017](../../../decisions/ADR-017-push-notification-provider-strategy.md) (provider strategy), [ADR-018](../../../decisions/ADR-018-device-token-registration.md) (token registration), [ADR-019](../../../decisions/ADR-019-notification-event-taxonomy.md) (event taxonomy), [ADR-020](../../../decisions/ADR-020-push-delivery-and-fallback-strategy.md) (delivery + fallback), [ADR-021](../../../decisions/ADR-021-notification-security-and-privacy.md) (security + privacy).

**Related (existing):** [ADR-011](../../../decisions/ADR-011-scheduler-local-notifications-vs-future-fcm.md) (local notifications — complementary, not replaced), [ADR-016](../../../decisions/ADR-016-smart-home-async-execution.md) (async side effects — same non-blocking pattern).

---

## 1. Product goal

Enable **remote push notifications** for important IXORA operational events so users are informed when something requires attention — even when the app is not in the foreground.

Push complements the existing **local notification** system ([ADR-011](../../../decisions/ADR-011-scheduler-local-notifications-vs-future-fcm.md)). It does **not** replace schedule reminders in MVP.

**Laravel is the source of truth for notification intent.** FCM is transport only ([ADR-017](../../../decisions/ADR-017-push-notification-provider-strategy.md)).

---

## 2. MVP scope

| Capability | MVP |
| --- | --- |
| **Android FCM setup** | Firebase project config + Capacitor/Firebase messaging dependency (Phase 4+) |
| **Device token registration** | Mobile registers FCM token with Laravel after auth |
| **Token refresh handling** | Re-register on FCM `onTokenRefresh` |
| **Token unregister / deactivate on logout** | Current device token soft-deactivated |
| **Backend notification abstraction** | `PushProvider` interface + `FcmPushProvider` |
| **Queue-backed push sending** | `PushNotificationJob` — async, non-blocking |
| **Event taxonomy** | Explicit MVP event types ([ADR-019](../../../decisions/ADR-019-notification-event-taxonomy.md)) |
| **Basic user notification preferences** | Optional — only if aligned with existing patterns; not required Phase 1 |
| **Marketing / campaign notifications** | ❌ Out of scope |

---

## 3. Non-goals

| Non-goal | Reason |
| --- | --- |
| **iOS / APNs** | Android first — future ADR required |
| **Marketing push** | Operational notifications only |
| **Campaigns / broadcast** | No segmentation or mass send |
| **Analytics-triggered push** | No behavioural nudges |
| **Rich notifications** | No images, actions, or custom layouts in MVP |
| **Notification inbox** | No in-app message history UI |
| **Segmentation / A/B testing** | Campaign platform scope |
| **Email / SMS** | Push-only channel |
| **Guaranteed delivery** | Best-effort per [ADR-020](../../../decisions/ADR-020-push-delivery-and-fallback-strategy.md) |
| **Replace local notifications** | Scheduler local reminders remain |
| **Modify Scheduler execution logic** | Push hooks added in later phase only |
| **Modify Smart Home execution logic** | Push hooks added in later phase only |
| **Direct mobile → FCM send** | Backend-only send |

---

## 4. Domain model proposal

### Table: `push_tokens`

> Alternative name `device_tokens` was considered; **`push_tokens`** is the recommended name — emphasises FCM registration token semantics.

| Column | Type | Notes |
| --- | --- | --- |
| `id` | bigint PK | |
| `user_id` | FK → `users.id` | Owner — cascade delete on user |
| `token` | string(512) | FCM registration token |
| `platform` | string | `android` \| `ios` \| `web` — MVP: `android` |
| `provider` | string | `fcm` — extensible |
| `device_id` | string nullable | Stable device identifier if safely available |
| `app_version` | string nullable | e.g. `0.0.1` |
| `device_model` | string nullable | e.g. `Pixel 7` |
| `is_active` | boolean default `true` | Soft-active flag |
| `last_seen_at` | timestamp nullable | Updated on register/refresh |
| `revoked_at` | timestamp nullable | Set on logout/unregister |
| `created_at` / `updated_at` | timestamps | |

### Indexes

| Index | Purpose |
| --- | --- |
| **`UNIQUE (token)`** | Dedupe — one row per FCM token |
| **`INDEX (user_id, is_active)`** | Active tokens per user for send |
| **`UNIQUE (user_id, device_id, provider)`** *(optional)* | Dedupe by device when stable ID exists |

### Eloquent model (future)

- **`PushToken`** — belongs to `User`
- **`User::pushTokens()`** — hasMany active scope

---

## 5. Backend API outline (draft)

All routes under `auth:firebase` (or existing Firebase JWT middleware). **`user_id` forced from authenticated user** — never from request body.

### `POST /api/push-tokens`

Register or upsert token for current user.

**Request:**

```json
{
  "token": "<fcm_registration_token>",
  "platform": "android",
  "provider": "fcm",
  "device_id": "optional-stable-id",
  "app_version": "0.0.1",
  "device_model": "Pixel 7"
}
```

**Response:** `201 Created` or `200 OK` (upsert)

**Rules:**
- Upsert by `token` (unique)
- Set `user_id` from auth
- Set `is_active = true`, `last_seen_at = now()`, clear `revoked_at` on re-register

### `POST /api/push-tokens/refresh`

Handle token rotation.

**Request:**

```json
{
  "old_token": "<optional_previous_token>",
  "token": "<new_fcm_token>",
  "platform": "android",
  "provider": "fcm",
  "device_id": "optional",
  "app_version": "0.0.1",
  "device_model": "Pixel 7"
}
```

**Rules:**
- Upsert new token
- If `old_token` provided, deactivate old row

### `DELETE /api/push-tokens/{id}`

Deactivate token for current user (logout or explicit unregister).

**Response:** `204 No Content`

**Rules:**
- Policy: owner only
- Set `is_active = false`, `revoked_at = now()`

### Optional: `GET /api/notification-preferences`

Future phase — user opt-out per event type. Not required for Phase 1 or early MVP.

### Security

| Rule | Detail |
| --- | --- |
| **Firebase auth middleware** | All routes authenticated |
| **`user_id` from auth** | Never accept `user_id` in request |
| **Owner scoping** | Policy prevents cross-user token access |
| **No token in list for others** | Tokens are private to owner |

---

## 6. Backend services outline (draft)

### Services

| Service | Responsibility |
| --- | --- |
| **`PushTokenService`** | Register, refresh, deactivate tokens; upsert logic |
| **`PushNotificationService`** | Resolve recipients, build `NotificationPayload`, dispatch job |
| **`FcmPushProvider`** | Implements `PushProvider` — calls FCM HTTP v1 API; production only |
| **`NoopPushProvider`** | Implements `PushProvider` — dry-run for tests and local dev without FCM credentials |
| **`PushNotificationJob`** | Queue job — iterate active tokens, call provider once per token, log `PushResult`, deactivate on `UNREGISTERED` |

### Interfaces / DTOs

#### `PushProvider` interface

```php
interface PushProvider
{
    public function send(PushToken $token, NotificationPayload $payload): PushResult;
}
```

Provider receives **one token and one payload**. Fan-out to multiple user devices is the responsibility of `PushNotificationJob`, not the provider ([ADR-017](../../../decisions/ADR-017-push-notification-provider-strategy.md)).

#### `NotificationPayload` DTO

```php
final readonly class NotificationPayload
{
    public function __construct(
        public string $title,
        public string $body,
        /** @var array<string, string> FCM data payload — string key-value pairs only */
        public array $data,
        public string $type,              // notification event type (ADR-019)
        public ?array $android = null,    // optional FCM Android-specific config
    ) {}
}
```

**Payload rules (ADR-021):**

| Rule | Detail |
| --- | --- |
| `data` values are strings | FCM data payloads require string values — no nested objects |
| No secrets in `title`, `body`, or `data` | IDs and type only; no tokens, passwords, or PII |
| `type` drives mobile routing | Same values as ADR-019 event taxonomy |
| `android` is optional | For future platform-specific priority / channel overrides |

#### `PushResult` DTO

```php
final readonly class PushResult
{
    public function __construct(
        public bool $success,
        public string $provider,          // 'fcm' | 'noop'
        public ?int $statusCode = null,
        public ?string $messageId = null,
        public ?string $errorCode = null,
        public ?string $errorMessage = null,
        public ?string $tokenPreview = null, // never the raw token
    ) {}
}
```

**`PushResult` rules:**

| Rule | Detail |
| --- | --- |
| Safe to log | Contains no raw FCM token — uses `tokenPreview` from `PushToken::tokenPreview()` |
| `provider` always set | Identifies which provider produced this result for log correlation |
| `messageId` on FCM success | FCM response message ID for audit/tracing |
| `errorCode` on failure | FCM error code (e.g. `UNREGISTERED`) for token deactivation logic in Phase 7 |
| `NoopPushProvider` returns | `success: true`, `provider: 'noop'`, all other fields `null` |

### Send flow (future)

```
PushNotificationService::sendToUser(User $user, NotificationPayload $payload)
  → Load active push_tokens for user
  → If empty: log info, return
  → Dispatch PushNotificationJob(user_id, payload)
  → Job: FcmPushProvider->send(tokens, payload)
  → On invalid token: PushTokenService->deactivate(token)
  → Log result — never throw to caller
```

---

## 7. Mobile outline (Android — future phases)

> **Phase 1:** documentation only. No mobile runtime changes.

| Step | Detail |
| --- | --- |
| **Dependency** | Add Capacitor Firebase Messaging plugin (or equivalent) when implementing Phase 4 |
| **Permission** | Request `POST_NOTIFICATIONS` on Android 13+ before token registration |
| **Obtain token** | Firebase SDK `getToken()` after auth |
| **Register** | `POST /api/push-tokens` after login / auth sync success |
| **Token refresh** | Listen `onTokenRefresh` → `POST /api/push-tokens/refresh` |
| **Logout** | `DELETE /api/push-tokens/{id}` for current token |
| **Foreground handler** | Optional toast/in-app banner — minimal MVP |
| **Background tap** | Route by `data.type` → schedule player, devices, or home |
| **Do not duplicate local notification logic** | Scheduler local notifications unchanged ([ADR-011](../../../decisions/ADR-011-scheduler-local-notifications-vs-future-fcm.md)) |

---

## 8. Relationship with Scheduler

| Topic | Rule |
| --- | --- |
| **Local notifications** | Continue for schedule due reminders — primary offline path |
| **FCM for schedule** | Optional future: `schedule_execution_failed`, remote `schedule_due` |
| **Scheduler dispatch loop** | Must not block on push ([ADR-020](../../../decisions/ADR-020-push-delivery-and-fallback-strategy.md)) |
| **No Scheduler code changes in Phase 1** | Integration in Phase 8 only |
| **Execution audit** | Push is informational — does not change recurrence or audit semantics |

---

## 9. Relationship with Smart Home

| Topic | Rule |
| --- | --- |
| **Action failure** | May enqueue `smart_home_action_failed` push (Phase 8) |
| **Provider unreachable** | May enqueue `smart_home_provider_unreachable` push |
| **Non-blocking** | `SmartHomeActionJob` completes independently; push is separate enqueue |
| **No Smart Home code changes in Phase 1** | Integration in Phase 8 only |
| **Audio unaffected** | Push failure never blocks vibe playback |

---

## 10. Payload examples

Display title/body are generic; `data` carries routing IDs.

### `schedule_execution_failed`

```json
{
  "type": "schedule_execution_failed",
  "schedule_id": 123,
  "vibe_id": 45
}
```

### `smart_home_action_failed`

```json
{
  "type": "smart_home_action_failed",
  "vibe_id": 45,
  "device_id": 9
}
```

### `smart_home_provider_unreachable`

```json
{
  "type": "smart_home_provider_unreachable"
}
```

### `account_security_notice`

```json
{
  "type": "account_security_notice"
}
```

---

## 11. Hard boundaries

| Boundary | Rule |
| --- | --- |
| **No runtime code in Phase 1** | Docs + ADRs only |
| **No migrations in Phase 1** | Schema documented here; Phase 2 implements |
| **No controllers in Phase 1** | API outline is draft |
| **No mobile runtime changes in Phase 1** | Mobile outline for future phases |
| **No Scheduler modifications** | Phase 8 integration only |
| **No Smart Home execution changes** | Phase 8 integration only |
| **No marketing/campaign push** | Taxonomy excludes ([ADR-019](../../../decisions/ADR-019-notification-event-taxonomy.md)) |
| **No analytics** | No usage-triggered notifications |
| **No secrets in payload** | [ADR-021](../../../decisions/ADR-021-notification-security-and-privacy.md) |
| **Backend-only send** | Mobile registers token; Laravel sends push |

---

## 12. Acceptance criteria

### Phase 1 (this document)

- [x] ADRs 017–021 created and accepted
- [x] `spec.md`, `plan.md`, `tasks.md` published
- [x] `docs/README.md` updated with Push Notifications entry
- [x] No runtime code changed
- [x] No migrations created
- [x] No controllers created
- [x] No mobile runtime modified
- [x] Clear enough for Phase 2: backend `push_tokens` schema + model

### Future phases (reference)

- Phase 2: `push_tokens` migration + `PushToken` model + factory + tests
- Phase 3: Push token API (`POST`, `DELETE`, `refresh`)
- Phase 4: Android FCM Capacitor setup
- Phase 5: Mobile token registration on login/logout
- Phase 6: `PushProvider` + `FcmPushProvider` + server credentials
- Phase 7: `PushNotificationJob` + queue config
- Phase 8: Scheduler + Smart Home event hooks
- Phase 9: Android notification tap routing
- Phase 10: E2E QA

---

## Related docs

| Document | Relationship |
| --- | --- |
| [`plan.md`](plan.md) | Implementation phases |
| [`tasks.md`](tasks.md) | Checklist |
| [`ADR-011`](../../../decisions/ADR-011-scheduler-local-notifications-vs-future-fcm.md) | Local notifications baseline |
| [`ADR-016`](../../../decisions/ADR-016-smart-home-async-execution.md) | Async side-effect pattern |
| [`../scheduler/mvp/spec.md`](../scheduler/mvp/spec.md) | Scheduler MVP |
| [`../smart-home/mvp/spec.md`](../smart-home/mvp/spec.md) | Smart Home MVP |
| [`../../standards/front-vibes-auth-core.md`](../../standards/front-vibes-auth-core.md) | Auth lifecycle for token registration |
