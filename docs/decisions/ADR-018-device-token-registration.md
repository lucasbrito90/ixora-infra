# ADR-018: Device token registration

## Status

**Accepted** — governs **FCM device token lifecycle** ([`specs/push-notifications/mvp/spec.md`](../specs/push-notifications/mvp/spec.md)).

## Date

2026-06-21

## Context

To deliver push notifications via FCM, IXORA must know which FCM registration tokens belong to which authenticated users. Mobile obtains tokens from the Firebase SDK; Laravel must store and manage them as a **user device token registry**.

Constraints:

1. **One user, many devices** — phone, tablet, reinstalls, token refreshes.
2. **Token refresh** — FCM tokens can change; mobile must re-register on refresh.
3. **Logout** — current device token should be deactivated or unregistered.
4. **No duplicates** — same token must not create multiple active rows.
5. **Tokens are sensitive** — treat like secrets-ish; do not log full token values.
6. **Auth required** — only authenticated users register tokens; `user_id` forced from auth context.

---

## Decision

**Create a user device token registry with dedupe by token. Mobile registers FCM token with Laravel after auth. Token is upserted, not duplicated. Logout deactivates the current token. Token refresh re-registers. Multiple devices per user are allowed.**

### Registry model

Recommended table: **`push_tokens`**

| Field | Purpose |
| --- | --- |
| `user_id` | Owner — forced from authenticated user |
| `token` | FCM registration token — **unique index** |
| `platform` | `android` \| `ios` \| `web` — MVP: `android` only |
| `provider` | `fcm` — extensible for future providers |
| `device_id` | Optional stable device identifier if safely available |
| `app_version` | Optional — debugging and compatibility |
| `device_model` | Optional — debugging |
| `is_active` | Soft-active flag — default `true` |
| `last_seen_at` | Updated on register/refresh |
| `revoked_at` | Set on logout or explicit unregister |

### Indexes

| Index | Purpose |
| --- | --- |
| **`UNIQUE (token)`** | Primary dedupe — same token cannot exist twice |
| **`INDEX (user_id, is_active)`** | Fast lookup of active tokens per user |
| **`UNIQUE (user_id, device_id, provider)`** *(optional)* | Dedupe by device if stable `device_id` is available |

### Registration lifecycle

```
Login / auth sync succeeds
  → Mobile requests notification permission (Android 13+ where required)
  → Mobile obtains FCM token from Firebase SDK
  → POST /api/push-tokens { token, platform, provider, device_id?, app_version?, device_model? }
  → Laravel upserts push_tokens row (user_id from auth)
  → Update last_seen_at

FCM onTokenRefresh
  → POST /api/push-tokens/refresh { old_token?, token, ... }
  → Laravel upserts new token; deactivate old token if provided

Logout
  → DELETE /api/push-tokens/{id} or POST deactivate current token
  → Laravel sets is_active=false, revoked_at=now()
```

### Rules

| Rule | Detail |
| --- | --- |
| **Upsert, not insert-only** | Re-registration updates `last_seen_at`, reactivates if needed |
| **No cross-user access** | User can only manage their own tokens |
| **No token in logs** | Log token prefix/suffix or hash only — never full token |
| **No token in API list for other users** | Tokens never exposed to other users |
| **Inactive tokens retained** | Soft-deactivate for audit; hard delete optional future cleanup job |

---

## Consequences

### Positive

| Outcome | Why it matters |
| --- | --- |
| **Multi-device support** | User can receive push on phone and tablet |
| **Token refresh handled** | FCM token rotation does not orphan rows |
| **Logout hygiene** | Stopped devices do not receive push after logout |
| **Dedupe enforced** | No duplicate sends to same physical token |

### Negative / tradeoffs

| Tradeoff | Impact |
| --- | --- |
| **Stale tokens accumulate** | Inactive rows need periodic cleanup (future job) |
| **device_id reliability** | Not all platforms expose stable IDs — optional dedupe only |
| **Reinstall = new token** | Old token row must be deactivated on refresh or cleanup |

---

## Alternatives Considered

| Alternative | Why not chosen |
| --- | --- |
| **Store token in Firebase only** | Rejected — Laravel cannot target users without server-side registry |
| **One token per user (latest wins)** | Rejected — breaks multi-device |
| **Hard delete on logout** | Soft-deactivate preferred — audit and reactivation on re-login |
| **Token in user profile JSON column** | Rejected — no dedupe, no multi-device, poor query performance |
| **Client-side token storage only** | Rejected — backend cannot send push without server registry |

---

## Related Docs

| Document | Relationship |
| --- | --- |
| [`ADR-017`](ADR-017-push-notification-provider-strategy.md) | FCM as first provider |
| [`ADR-021`](ADR-021-notification-security-and-privacy.md) | Token privacy in logs and API |
| [`../specs/push-notifications/mvp/spec.md`](../specs/push-notifications/mvp/spec.md) | API outline and domain model |
| [`../standards/front-vibes-auth-core.md`](../standards/front-vibes-auth-core.md) | Auth sync after login |

---

When token cleanup policy or retention limits are defined, document in a follow-up ADR or ops runbook.
