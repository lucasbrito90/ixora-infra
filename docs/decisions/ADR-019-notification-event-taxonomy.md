# ADR-019: Notification event taxonomy

## Status

**Accepted** — governs **MVP notification event types and payload schema** ([`specs/push-notifications/mvp/spec.md`](../specs/push-notifications/mvp/spec.md)).

## Date

2026-06-21

## Context

IXORA needs a controlled vocabulary of notification events so that:

1. Backend services emit **explicit, typed events** — not free-form strings.
2. Mobile handlers can **route taps** to the correct screen based on `type`.
3. MVP scope stays **operational** — no marketing, campaigns, or analytics-driven nudges.
4. Payloads remain **minimal and privacy-safe** ([ADR-021](ADR-021-notification-security-and-privacy.md)).

Future integrations (Scheduler remote failure, Smart Home failure) must enqueue notifications through this taxonomy — not ad-hoc push calls.

---

## Decision

**Use explicit notification event types and a minimal payload schema. MVP event types are operational/system only. Marketing, campaigns, promotions, newsletters, behavioural nudges, and analytics-driven notifications are out of scope.**

### MVP event types

| Type | Trigger (future phase) | Purpose |
| --- | --- | --- |
| **`schedule_due`** | Remote schedule reminder (optional future) | Notify user a schedule is due — complements local notifications |
| **`schedule_execution_failed`** | Scheduler dispatcher / execution audit failure | Alert user that a scheduled vibe failed to execute remotely |
| **`smart_home_action_failed`** | `SmartHomeActionJob` failure | Alert user that a device action failed during vibe play |
| **`smart_home_provider_unreachable`** | Provider connection test or job failure | Alert user that Home Assistant (or provider) is unreachable |
| **`account_security_notice`** | Auth/security events | Password change, suspicious login, account deletion warning |

> **Phase 1 (this ADR):** taxonomy and schema documented only. No runtime emission.

### Out of scope (explicit)

| Category | Examples |
| --- | --- |
| **Marketing** | Promotions, feature announcements, upsell |
| **Campaigns** | Broadcast to segments, drip campaigns |
| **Newsletters** | Weekly digest, content recommendations |
| **Behavioural nudges** | "You haven't played a vibe in 3 days" |
| **Analytics-driven** | Push triggered by usage patterns or ML models |

### Payload schema

All push data payloads use a **`type`** discriminator plus **IDs only** — no secrets, no sensitive content in body.

```json
{
  "type": "<event_type>",
  "<id_field>": <integer>,
  ...
}
```

| Field | Rule |
| --- | --- |
| **`type`** | Required — one of MVP event types |
| **`schedule_id`** | Present when type is schedule-related |
| **`vibe_id`** | Present when vibe context exists |
| **`device_id`** | Present when Smart Home device context exists |
| **`notification_type`** | Alias of `type` if FCM requires nested `data` key — implementation detail |

### Notification title/body (display)

| Rule | Detail |
| --- | --- |
| **Generic copy** | User-facing title/body uses safe, generic messages |
| **No secrets in body** | Never include tokens, passwords, or HA credentials |
| **Minimal PII** | Avoid full names, emails, or device names in push body when possible |
| **IDs in data payload** | Mobile resolves detail from API after tap if needed |

### Payload examples

**`schedule_execution_failed`**

```json
{
  "type": "schedule_execution_failed",
  "schedule_id": 123,
  "vibe_id": 45
}
```

**`smart_home_action_failed`**

```json
{
  "type": "smart_home_action_failed",
  "vibe_id": 45,
  "device_id": 9
}
```

**`smart_home_provider_unreachable`**

```json
{
  "type": "smart_home_provider_unreachable",
  "device_id": null
}
```

**`account_security_notice`**

```json
{
  "type": "account_security_notice"
}
```

---

## Consequences

### Positive

| Outcome | Why it matters |
| --- | --- |
| **Typed events** | Mobile tap routing is predictable |
| **Scope control** | Marketing/campaign requests rejected by taxonomy |
| **Integration-ready** | Scheduler and Smart Home hook into same enum |

### Negative / tradeoffs

| Tradeoff | Impact |
| --- | --- |
| **New event = schema change** | Each new type needs ADR/spec update |
| **Generic display copy** | Less personalised notification text in MVP |

---

## Alternatives Considered

| Alternative | Why not chosen |
| --- | --- |
| **Free-form notification strings** | Rejected — no mobile routing; scope creep |
| **FCM topics for broadcast** | Rejected — campaign pattern; out of MVP scope |
| **Rich HTML bodies with user content** | Rejected — privacy risk ([ADR-021](ADR-021-notification-security-and-privacy.md)) |
| **Include full error messages from HA** | Rejected — may leak provider details |

---

## Related Docs

| Document | Relationship |
| --- | --- |
| [`ADR-017`](ADR-017-push-notification-provider-strategy.md) | Provider strategy |
| [`ADR-020`](ADR-020-push-delivery-and-fallback-strategy.md) | Async delivery |
| [`ADR-021`](ADR-021-notification-security-and-privacy.md) | Payload privacy |
| [`ADR-011`](ADR-011-scheduler-local-notifications-vs-future-fcm.md) | Schedule events |
| [`ADR-016`](ADR-016-smart-home-async-execution.md) | Smart Home failure events |
| [`../specs/push-notifications/mvp/spec.md`](../specs/push-notifications/mvp/spec.md) | Full spec |

---

When adding new event types post-MVP, update this ADR or supersede with a versioned taxonomy document.
