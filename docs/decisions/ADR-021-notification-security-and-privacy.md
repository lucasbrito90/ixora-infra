# ADR-021: Notification security and privacy

## Status

**Accepted** — governs **push payload privacy and token security** ([`specs/push-notifications/mvp/spec.md`](../specs/push-notifications/mvp/spec.md)).

## Date

2026-06-21

## Context

Push notifications traverse third-party infrastructure (Google FCM). Payloads may appear on lock screens, notification trays, and device logs. IXORA stores sensitive data server-side (Firebase auth, Home Assistant tokens, user content).

Constraints:

1. **No secrets in push payload** — FCM data is not encrypted end-to-end for display.
2. **Minimal PII in notification body** — lock screen visibility.
3. **Token isolation** — users must not access other users' device tokens.
4. **OS-level revocation** — user can disable notifications via Android settings; backend must respect deactivated tokens.
5. **Audit without exposure** — logs may record event type and IDs, not tokens or credentials.

---

## Decision

**Push payloads are minimal and privacy-safe. Do not include secrets, credentials, or sensitive user content. Include IDs only when needed for tap routing. Backend must not expose other users' device tokens. Store only necessary token metadata.**

### Payload rules

| Rule | Detail |
| --- | --- |
| **No secrets** | Never include HA access tokens, Firebase ID tokens, API keys, or passwords |
| **No credentials in `data`** | FCM `data` map contains `type` + integer IDs only |
| **Generic display text** | Title/body use safe templates — e.g. "A scheduled vibe could not start" not "Failed: light.living_room token expired" |
| **IDs for routing** | `schedule_id`, `vibe_id`, `device_id`, `notification_type` / `type` as needed |
| **No full error dumps** | Provider HTTP responses stay in server logs — not in push |

### Allowed payload fields (MVP)

| Field | Allowed | Notes |
| --- | --- | --- |
| `type` | ✅ | Event discriminator |
| `schedule_id` | ✅ | Integer |
| `vibe_id` | ✅ | Integer |
| `device_id` | ✅ | Integer |
| `access_token` | ❌ | Never |
| `encrypted_credentials` | ❌ | Never |
| `provider_device_id` | ❌ | Avoid — may reveal home layout |
| User email / name | ❌ | Avoid in push body |

### Token security

| Rule | Detail |
| --- | --- |
| **Auth-scoped API** | `POST /api/push-tokens` — `user_id` from `auth()->id()` only |
| **No cross-user read** | User cannot list or delete another user's tokens |
| **No token in API responses to other clients** | Token registry is write-oriented; list endpoint optional and owner-scoped |
| **No full token in logs** | Log `token_hash` or last 4 chars for correlation only |
| **FCM server credentials server-side only** | Service account JSON in Laravel env — never mobile |

### User control

| Mechanism | Behaviour |
| --- | --- |
| **Android OS notification settings** | User disables channel/app — FCM may still deliver but OS may hide; backend cannot force display |
| **Logout unregister** | Backend deactivates token — stops server-initiated sends to that device |
| **Future preferences** | Optional `notification_preferences` — user opt-out per event type (future phase) |

### Logging

| Log | Allowed fields |
| --- | --- |
| Push send attempt | `user_id`, `type`, `push_token_id`, `success`, `fcm_error_code` |
| Push send failure | Same — no `token` value |
| Token registration | `user_id`, `platform`, `push_token_id`, `device_model` — no full token |

---

## Consequences

### Positive

| Outcome | Why it matters |
| --- | --- |
| **Lock screen safe** | Generic copy reduces PII exposure |
| **Credential isolation** | HA/Firebase secrets never leave server trust boundary |
| **Compliance-friendly baseline** | Minimal data in third-party transport |

### Negative / tradeoffs

| Tradeoff | Impact |
| --- | --- |
| **Less informative notifications** | User may need to open app for details |
| **Generic copy only in MVP** | No personalised "Your Morning Vibe failed" with vibe name — future product decision |

---

## Alternatives Considered

| Alternative | Why not chosen |
| --- | --- |
| **Encrypt payload client-side** | Over-engineered for MVP; FCM display still needs plaintext |
| **Include vibe name in push body** | Rejected — PII on lock screen; fetch after tap |
| **Include HA error message in push** | Rejected — may leak provider/infrastructure details |
| **Public token list API** | Rejected — token is bearer-like for FCM targeting |

---

## Related Docs

| Document | Relationship |
| --- | --- |
| [`ADR-017`](ADR-017-push-notification-provider-strategy.md) | Backend-only send |
| [`ADR-018`](ADR-018-device-token-registration.md) | Token registry |
| [`ADR-019`](ADR-019-notification-event-taxonomy.md) | Event types |
| [`ADR-013`](ADR-013-home-assistant-first-provider.md) | HA credential handling precedent |
| [`../standards/front-vibes-auth-core.md`](../standards/front-vibes-auth-core.md) | Auth lifecycle |
| [`../specs/push-notifications/mvp/spec.md`](../specs/push-notifications/mvp/spec.md) | Security section |

---

When notification preference UI ships, extend this ADR with opt-out matrix per event type.
