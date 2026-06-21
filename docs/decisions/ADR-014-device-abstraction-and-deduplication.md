# ADR-014: Device abstraction and deduplication

## Status

**Accepted** — governs the **device registry model** and **deduplication policy** for Smart Home ([`specs/smart-home/mvp/spec.md`](../specs/smart-home/mvp/spec.md)).

## Date

2026-06-14

## Context

When IXORA syncs devices from a provider (e.g. Home Assistant), the provider returns a list of entities or devices. Without a deduplication strategy, running sync multiple times or switching provider connections would create duplicate device records in IXORA's database, leading to:

- A user seeing the same light listed multiple times in the Devices tab.
- Device actions attached to stale or duplicate records failing at execution time.
- Orphaned device records after re-sync or provider reconnection.

Additionally, the raw provider data model (HA `entity_id`, Tuya `device_id`, etc.) must not leak into the IXORA domain model. IXORA needs its own normalised device record that:

- Is independent of provider internal identifiers.
- Carries status information relevant to the IXORA UI (online / offline / unknown).
- Supports future cross-provider device merging (e.g. a Zigbee light exposed through both HA and Tuya).

### Existing stub analysis

The current `devices` migration stub (`2026_05_01_000005_create_devices_table.php`) has:

| Column | Stub value | MVP target note |
| --- | --- | --- |
| `id` | bigint PK | Keep |
| `user_id` | FK → `users` | Keep |
| `name` | string | Keep |
| `type` | string (comment: light, speaker, …) | Keep |
| `provider` | string (comment: Home Assistant, Tuya, …) | Keep |
| `external_id` | string | **Rename to `provider_device_id`** — clearer naming; maps to HA `entity_id` |
| `metadata` | json nullable | Keep |
| `created_at` | timestamp | Keep |
| `updated_at` | **missing** | **Add in schema review** |
| `status` | **missing** | **Add** — `online \| offline \| unknown` |
| `last_seen_at` | **missing** | **Add** — timestamp of last successful status fetch |

**The stub has a composite index on `(user_id, provider, external_id)` which is correct for deduplication — the column must be renamed to `provider_device_id` to match the domain language in this ADR and the spec.**

Schema changes are not part of Phase 1 (ADRs + spec). They are addressed in Phase 2 (existing schema/domain review) and Phase 4 (Device CRUD backend).

---

## Decision

**IXORA maintains its own device registry, independent of provider raw data. Devices are deduplicated per provider identity. Status is tracked and exposed in the Devices list.**

### Device identity and deduplication

| Principle | Rule |
| --- | --- |
| **IXORA owns the device record** | Devices are stored in IXORA's PostgreSQL; the provider is a data source, not the registry. |
| **Dedupe key** | **`(user_id, provider, provider_device_id)`** — uniquely identifies a device for a given user and provider. |
| **Upsert on sync** | Sync must **update** existing device records, not insert duplicates. |
| **Home Assistant mapping** | HA `entity_id` (e.g. `light.living_room`) maps directly to `provider_device_id`. |
| **Cross-provider dedupe** | Allowed in future phases but **not required in MVP**. A single device may appear once per provider if the same physical device is registered in two providers. |

### Uniqueness constraint (MVP)

```sql
-- Unique index on devices
UNIQUE (user_id, provider, provider_device_id)
```

On sync: `INSERT ... ON CONFLICT (user_id, provider, provider_device_id) DO UPDATE SET name = ..., status = ..., last_seen_at = ...`

### Device record model (MVP target)

| Field | Type | Description |
| --- | --- | --- |
| `id` | bigint PK | IXORA device identity |
| `user_id` | FK → `users` | Owner |
| `name` | string | Human-readable name (from provider or user-overridden) |
| `type` | string | Normalised device category (light, speaker, switch, …) |
| `provider` | string | Provider slug (`home_assistant`, `tuya`, …) |
| `provider_device_id` | string | Provider-internal identifier (HA `entity_id`, etc.) |
| `status` | string | `online \| offline \| unknown` |
| `last_seen_at` | timestamp nullable | Last time status was successfully fetched from provider |
| `metadata` | json nullable | Provider-specific attributes (domain, supported features, etc.) |
| `created_at` | timestamp | |
| `updated_at` | timestamp | Updated on each sync |

### Status model

| Status | Meaning |
| --- | --- |
| **`online`** | Provider returned state for this device on the most recent fetch. |
| **`offline`** | Provider confirmed the device is unavailable or unreachable. |
| **`unknown`** | Status could not be determined — provider unreachable, connection failed, or device not yet polled. |

**Status update policy:**

- Status is refreshed from the provider when the provider connection is online and sync runs.
- If the provider connection is **unavailable** (timeout, auth failure, unreachable), device status becomes **`unknown`**. It does **not** remain `online` from the prior sync.
- The mobile Devices tab must show status per device with a visual indicator.
- MVP may treat unavailable provider as causing all its devices to flip to `unknown`.

### Sync deduplication flow

```
GET /api/provider-connections/{id}/sync
  → adapter.listDevices(connection)
  → for each provider entity:
      upsert devices WHERE (user_id, provider, provider_device_id)
      update name, type, status, last_seen_at, metadata, updated_at
  → devices absent from provider response: mark status = offline (or unknown)
  → return { synced: N, updated: M, new: K }
```

### Mobile behaviour

- Devices tab shows device list with status badge (online / offline / unknown).
- No duplicate entries visible per provider identity.
- Mobile does not store device status locally in MVP — always fetches from API.

---

## Consequences

### Positive

| Outcome | Why it matters |
| --- | --- |
| **No duplicate devices** | Users never see the same physical device listed multiple times from repeated syncs. |
| **Stable device identity** | `id` is the IXORA device key; `vibe_device_actions` references `id` — safe across re-syncs. |
| **Status transparency** | Users know which devices are reachable before attaching actions to vibes. |
| **Provider-agnostic domain** | Vibe device actions use IXORA `device_id` — not provider entity IDs — making provider swaps possible in future. |

### Negative / tradeoffs

| Tradeoff | Impact |
| --- | --- |
| **Column rename required** | `external_id` → `provider_device_id` is a migration change — addressed in Phase 2 schema review, not Phase 1 ADRs. |
| **Status fields missing from stub** | `status`, `last_seen_at`, `updated_at` must be added — documented, not implemented in Phase 1. |
| **No cross-provider merge in MVP** | A device accessible via two providers appears twice. Acceptable for MVP. |
| **Provider-offline devices show `unknown`** | Users with intermittent HA connectivity may see devices appear unknown/offline frequently. |

---

## Alternatives Considered

| Alternative | Why not chosen |
| --- | --- |
| **Store provider raw ID as-is (`external_id`) without normalisation** | Accepted for the stub but rejected as the canonical domain name — `provider_device_id` is more explicit. |
| **Allow duplicate device records per sync** | Rejected — duplicates break action references and UX. |
| **Mobile stores device list locally** | Rejected — backend is authoritative ([ADR-012](ADR-012-smart-home-provider-strategy.md)); local cache is acceptable but not the source of truth. |
| **Cross-provider deduplication in MVP** | Too complex for MVP; deferred — a physical device may appear once per provider for now. |
| **Keep status as provider-native value** | Rejected — normalise to `online \| offline \| unknown` so UI is provider-agnostic. |

---

## Related Docs

| Document | Relationship |
| --- | --- |
| [`ADR-012`](ADR-012-smart-home-provider-strategy.md) | Provider adapter architecture |
| [`ADR-013`](ADR-013-home-assistant-first-provider.md) | HA `entity_id` → `provider_device_id` mapping |
| [`ADR-015`](ADR-015-vibe-device-action-architecture.md) | Vibe device actions reference IXORA `device_id` |
| [`ADR-016`](ADR-016-smart-home-async-execution.md) | Async execution — status refresh is async |
| [`../specs/smart-home/mvp/spec.md`](../specs/smart-home/mvp/spec.md) | Domain model, deduplication section, device status section |
| [`../specs/smart-home/mvp/plan.md`](../specs/smart-home/mvp/plan.md) | Phase 2 — existing schema review; Phase 4 — Device CRUD backend |

---

When cross-provider device merge is required, create a new ADR extending this decision with the merge key strategy (e.g. MAC address, Matter device ID) and update the unique constraint accordingly.
