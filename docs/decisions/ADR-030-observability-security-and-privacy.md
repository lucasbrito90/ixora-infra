# ADR-030: Observability security and privacy

## Status

**Accepted** — governs **telemetry privacy, redaction, and credential boundaries** ([ADR-028](ADR-028-observability-platform.md), [`specs/observability-foundation/mvp/spec.md`](../specs/observability-foundation/mvp/spec.md)).

## Date

2026-07-05

---

## Context

Observability systems aggregate logs, traces, and metrics in searchable stores (Loki, Tempo, Grafana). Unlike application databases protected by auth policies, telemetry backends are often **readable by the entire engineering team** and may retain data longer than request logs on App Platform.

Ixora already enforces notification privacy ([ADR-021](ADR-021-notification-security-and-privacy.md)):

- No secrets in push payloads
- No full FCM tokens in logs
- Generic user-facing copy

**Observability must never become a data leak.** Telemetry can accidentally expose more than push notifications because traces capture HTTP headers, SQL, and mobile client context.

This ADR extends ADR-021 principles to **all telemetry signals** and defines Collector-side redaction as a second line of defense.

---

## Decision

### Core principle

> **Observability exists to debug systems — not to archive user secrets.**

### PII policy

| Classification | Telemetry treatment |
| --- | --- |
| **User email, name, phone** | ❌ Forbidden in logs, traces, metrics |
| **`user_id` (integer)** | ✅ Allowed in logs and trace attributes — not as Prometheus label |
| **`firebase_uid`** | ❌ Forbidden — use `user_id` only |
| **IP address** | ⚠️ Avoid; if required for abuse debugging, hash or truncate; never in mobile client telemetry |
| **Device model / OS version** | ✅ Allowed (low sensitivity) |
| **Vibe/schedule names** | ⚠️ Avoid in mobile telemetry; backend may log `schedule_id` only |
| **Home Assistant entity IDs** | ⚠️ Avoid in user-visible paths; `device_id` integer preferred |

### Credential policy

| Secret type | Forbidden everywhere in telemetry |
| --- | --- |
| Firebase ID tokens / refresh tokens | ✅ always forbidden |
| FCM registration tokens | ✅ always forbidden |
| Home Assistant long-lived access tokens | ✅ always forbidden |
| Laravel `APP_KEY`, DB passwords | ✅ always forbidden |
| Spaces / DO API keys | ✅ always forbidden |
| Firebase service account JSON fields | ✅ always forbidden |
| `Authorization` header value | ✅ always forbidden — may log `Authorization: Bearer [REDACTED]` |

### Token policy

| Token | Logs | Traces | Metrics |
| --- | --- | --- | --- |
| Push token (full) | ❌ | ❌ | ❌ |
| Push token (last 4 chars) | ⚠️ correlation only if needed | ❌ | ❌ |
| `token_hash` (internal id) | ✅ | ✅ | ❌ |
| Session/JWT payload | ❌ | ❌ | ❌ |

Align with [ADR-018](ADR-018-device-token-registration.md) and [ADR-021](ADR-021-notification-security-and-privacy.md).

### Log redaction

**Application responsibility (Phase 7–8):**

- Never pass secrets to `Log::` context arrays.
- Use existing Laravel patterns: log `exception_class`, sanitized `error` message — not full provider response bodies containing tokens.

**Collector responsibility (Phase 3+):**

- `attributes` processor: drop keys matching `password`, `token`, `authorization`, `secret`, `credential`, `api_key`, `private_key`.
- Regex redaction for Bearer tokens and JWT-shaped strings in log bodies.

### Trace redaction

| Span attribute | Allowed |
| --- | --- |
| `http.url` | Path only — strip query strings containing tokens |
| `http.request.header.authorization` | ❌ never record |
| `db.statement` | ❌ full SQL forbidden in MVP — use operation name + table if needed |
| `exception.message` | Sanitized — no env var values |

### Allowed fields (safe telemetry)

| Field | Example |
| --- | --- |
| `service.name` | `back_vibes-worker` |
| `deployment.environment` | `staging` |
| `trace_id`, `span_id` | W3C format |
| `schedule_id`, `vibe_id`, `device_id`, `user_id` | integers |
| `exception_class` | `ProviderConnectionException` |
| `error` (sanitized) | `Connection timed out` |
| `job.name`, `queue.name` | `SmartHomeActionJob`, `smart-home` |
| `notification.type` | `smart_home_action_failed` |
| `outcome` | `success`, `failure`, `skipped` |
| `http.route` | `/api/schedules` |
| `http.status_code` | `502` |

### Forbidden fields (never emit)

| Field | Why |
| --- | --- |
| `access_token`, `id_token`, `refresh_token` | Auth secrets |
| `fcm_token`, `push_token` | Device impersonation risk |
| `ha_token`, `provider_credentials` | Smart Home takeover |
| `password`, `encrypted_credentials` | Account security |
| Raw HTTP response body from HA/FCM | May contain secrets or home layout |
| User email in span name | PII in searchable trace list |

### Examples

#### ✅ Safe log

```json
{
  "message": "Schedule Smart Home dispatch skipped: validation failed.",
  "schedule_id": 42,
  "vibe_id": 7,
  "user_id": 123,
  "validator_failed": true,
  "trace_id": "4bf92f3577b34da6a3ce929d0e0e4736"
}
```

#### ❌ Unsafe log

```json
{
  "message": "HA request failed",
  "authorization": "Bearer eyJhbGciOiJIUzI1NiIs...",
  "provider_response": "{ \"access_token\": \"...\" }",
  "user_email": "user@example.com"
}
```

#### ✅ Safe trace attribute

```
smart_home.action_type = turn_off
device_id = 5
outcome = failure
exception_class = ProviderException
```

#### ❌ Unsafe trace attribute

```
http.request.header.authorization = Bearer eyJ...
provider_device_id = light.bedroom_main
fcm_token = dXyz...
```

### Reference to notification security ADRs

| ADR | Relationship |
| --- | --- |
| [ADR-019](ADR-019-notification-event-taxonomy.md) | Event `type` strings are safe to log |
| [ADR-021](ADR-021-notification-security-and-privacy.md) | Push payload rules ⊆ telemetry rules |
| [ADR-026](ADR-026-automation-execution-security.md) | Background validators must not log secrets |

### Grafana access

| Rule | MVP |
| --- | --- |
| **Authentication** | Required — not public internet without auth |
| **Team access** | Engineering only |
| **Production data** | Separate Grafana org or datasource per environment |
| **Export** | No bulk export of logs containing `user_id` without justification |

---

## Consequences

### Positive

- Telemetry usable for debugging without compliance risk.
- Collector redaction catches application mistakes.
- Consistent with existing notification privacy posture.

### Negative

- Some debugging detail requires reproducing with sanitized IDs only.
- Redaction processors must be tested — false positives may hide useful context.

### Related ADRs

- [ADR-021](ADR-021-notification-security-and-privacy.md)
- [ADR-028](ADR-028-observability-platform.md)
- [ADR-029](ADR-029-telemetry-data-model.md)
- [ADR-031](ADR-031-retention-storage-and-cost-control.md)
