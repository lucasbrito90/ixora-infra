# Smart Home Foundation MVP — device management + vibe action model

**Status:** Active feature specification (source of truth for Phase 1 delivery)  
**Version:** 1.0 (MVP scope — documentation only; no runtime code implemented)  
**Feature ID:** `smart-home/mvp`  
**Platform:** `back_vibes` (authoritative), `front_vibes` Android + iOS (mobile client)

> **Phase 1 = ADRs + Spec only.** No migrations, controllers, mobile screens, or runtime behaviour changes are part of Phase 1. The next phase (Phase 2) is existing schema/domain review before any implementation begins.

**Architecture decisions:** [ADR-012](../../../decisions/ADR-012-smart-home-provider-strategy.md) (provider strategy), [ADR-013](../../../decisions/ADR-013-home-assistant-first-provider.md) (Home Assistant first), [ADR-014](../../../decisions/ADR-014-device-abstraction-and-deduplication.md) (device abstraction + dedup), [ADR-015](../../../decisions/ADR-015-vibe-device-action-architecture.md) (vibe device action architecture), [ADR-016](../../../decisions/ADR-016-smart-home-async-execution.md) (async execution).

---

## 1. Product goal

Enable users to **connect their smart home devices** to IXORA and, in a later phase, **attach simple device actions to vibes** so that playing a vibe can trigger physical effects (e.g. dimming lights, switching on a speaker).

**Smart Home complements the audio experience — it does not replace it.** Audio playback is always the primary event; device actions are optional ambient side effects.

---

## 2. MVP scope

### 2.1 Devices tab

- A **Devices** tab is added to the bottom navigation bar alongside Vibes and other existing tabs.
- Devices is a **first-class navigation surface** — not a settings sub-screen.
- The tab shows all devices registered to the authenticated user across all their provider connections.

### 2.2 Device list

- List all registered devices for the current user.
- Each list row shows:
  - Device name
  - Device type (light, switch, speaker, …)
  - Provider (Home Assistant, …)
  - **Status badge:** `online`, `offline`, or `unknown`
- No duplicate entries for the same provider identity (see [ADR-014](../../../decisions/ADR-014-device-abstraction-and-deduplication.md)).

### 2.3 Provider connection management

- User can **add a provider connection** (MVP: Home Assistant only).
- Fields: display name, base URL, long-lived access token.
- On add: **test connection** is called automatically; connection is not saved if unreachable.
- User can **delete a provider connection** (cascades to its devices).

### 2.4 Device sync

- After connecting a provider, user triggers a **sync** to import devices from the provider.
- Sync is an upsert — existing devices are updated, new ones added, no duplicates created.
- Devices removed from the provider are marked `offline` or `unknown`.

### 2.5 Device CRUD

- **Add device** manually (optional for MVP — may be import-only from sync).
- **Edit device** — rename, change type label.
- **Delete device** — removes device and any associated `vibe_device_actions`.
- **Test connection** — ping provider to verify device is reachable (MVP: returns status only).

### 2.6 Device status

- Status values: `online`, `offline`, `unknown`.
- Displayed as a visual badge in the device list and device detail.
- Status is refreshed from the provider on sync.
- If provider is unreachable, status becomes `unknown`.

### 2.7 Actions MVP

MVP includes three action types for `vibe_device_actions`:

| Action | Effect |
| --- | --- |
| `turn_on` | Switch device on |
| `turn_off` | Switch device off |
| `toggle` | Toggle device state |

The UI for associating actions to vibes is a **later phase** (Phase 7). MVP establishes the backend model and API for actions; the vibe action UI is deferred.

### 2.8 First provider

**Home Assistant** is the only real provider in MVP. See [ADR-013](../../../decisions/ADR-013-home-assistant-first-provider.md).

---

## 3. Non-goals (MVP)

| Non-goal | Reason |
| --- | --- |
| **Amazon Alexa** | Voice ecosystem — future provider ADR required |
| **Google Home** | Voice ecosystem — future provider ADR required |
| **Apple HomeKit** | Requires local pairing — future provider ADR required |
| **Matter** | No local network from DO App Platform — future phase |
| **Thread, Zigbee, Z-Wave direct** | Protocol integrations require dedicated hardware gateway; handled by HA internally |
| **MQTT broker** | Message bus integration — future phase |
| **LAN discovery / mDNS** | Backend cannot reach user's LAN — user enters URL manually |
| **Device auto-discovery** | No automatic scanning for devices on local network |
| **Voice commands** | Out of scope — Smart Home is about playback-triggered actions |
| **Scenes** | HA scenes are a future action type |
| **Brightness / color / temperature controls** | Future action types beyond MVP `turn_on / turn_off / toggle` |
| **Conditional automations** | No if/then logic — actions fire unconditionally on play |
| **Offline device control** | Requires local API access; backend cannot guarantee provider reachability |
| **Smart Home schedules (separate from Scheduler)** | Device actions are vibe-scoped, not schedule-scoped ([ADR-015](../../../decisions/ADR-015-vibe-device-action-architecture.md)) |
| **ActionExecutionLog UI** | Log exists in future; no mobile UI for action history in MVP |
| **Multiple HA instances per user** | One provider connection per provider type per user in MVP |
| **Token rotation / refresh** | HA long-lived access tokens do not expire by default; rotation is a future spec |
| **Admin panel Smart Home management** | Not in MVP — mobile-first |

---

## 4. Navigation decision

The bottom navigation bar in `front_vibes` will include a **Devices tab**:

| Tab | Existing / New |
| --- | --- |
| Vibes | Existing |
| **Devices** | **New — MVP** |
| Schedules | Existing (Scheduler MVP) |
| (other existing tabs as appropriate) | Existing |

**Devices must be a first-class navigation surface.** It must not be buried in settings or profile. Users discover Smart Home through the tab, not through a deep link from vibes.

The exact tab order and icon are implementation decisions for Phase 6 (mobile). This spec mandates only that the tab exists at the root navigation level.

---

## 5. Domain model

```
┌─────────────────┐
│     users       │
│  (Firebase sync)│
└────────┬────────┘
         │
         ▼
┌────────────────────────────┐
│   provider_connections     │
│  provider + credentials    │
│  (encrypted server-side)   │
└────────┬───────────────────┘
         │ 1:N
         ▼
┌────────────────────────────┐
│         devices            │
│  name, type, provider,     │
│  provider_device_id,       │
│  status, last_seen_at      │
└────────┬───────────────────┘
         │ 1:N (via device_id)
         ▼
┌────────────────────────────┐     ┌─────────────────┐
│    vibe_device_actions     │◄────│      vibes      │
│  action_type, parameters,  │     │  user-owned     │
│  sort_order, delay_seconds │     └─────────────────┘
└────────────────────────────┘

Future:
  ActionExecutionLog — per-execution audit (Phase 9)
```

| Entity | Role |
| --- | --- |
| **`users`** | Owner of all Smart Home data — Firebase sync ([ADR-001](../../../decisions/ADR-001-firebase-auth-laravel-sync.md)) |
| **`provider_connections`** | One record per user × provider. Stores encrypted credentials. **Not in existing stubs — new table in schema review.** |
| **`devices`** | IXORA device registry — deduplicated per `(user_id, provider, provider_device_id)` |
| **`vibe_device_actions`** | Actions attached to a vibe — ordered, generic parameters |
| **`ActionExecutionLog`** | Future — audit of action execution attempts |

### Existing stubs (review in Phase 2)

| Stub table | Path | MVP changes required |
| --- | --- | --- |
| `devices` | `back_vibes/database/migrations/2026_05_01_000005_create_devices_table.php` | Rename `external_id` → `provider_device_id`; add `status`, `last_seen_at`, `updated_at` |
| `vibe_device_actions` | `back_vibes/database/migrations/2026_05_01_000006_create_vibe_device_actions_table.php` | Add `sort_order`, `updated_at` |

**Phase 2 (schema review) documents required changes before any migration is written.**

---

## 6. Deduplication

See [ADR-014](../../../decisions/ADR-014-device-abstraction-and-deduplication.md).

| Rule | Detail |
| --- | --- |
| **No duplicate devices** | A device from the same provider appearing twice in sync must update the existing record, not create a second row. |
| **MVP uniqueness key** | `(user_id, provider, provider_device_id)` |
| **HA entity_id mapping** | Home Assistant `entity_id` (e.g. `light.living_room`) maps directly to `provider_device_id`. |
| **Re-sync / upsert** | Every sync run must `INSERT ... ON CONFLICT ... DO UPDATE` — never blind insert. |
| **Unique index** | `UNIQUE (user_id, provider, provider_device_id)` enforced at DB level. |

---

## 7. Device status

See [ADR-014](../../../decisions/ADR-014-device-abstraction-and-deduplication.md).

| Status | Meaning |
| --- | --- |
| **`online`** | Provider returned state for this device on last sync. |
| **`offline`** | Provider confirmed device is unavailable or unreachable. |
| **`unknown`** | Status cannot be determined — provider unreachable, first sync not run, or connection failed. |

**Status update policy:**

| Event | Status action |
| --- | --- |
| Successful sync — device present | Set `status = online`, update `last_seen_at = now()` |
| Successful sync — device absent from provider response | Set `status = offline` |
| Provider connection unreachable on sync | Set all provider's devices to `status = unknown` |
| Device never synced | Default `status = unknown` |

**Mobile display:** Each device row in the Devices list must show a status badge with colour differentiation (green / red / grey or equivalent).

---

## 8. Security

| Rule | Implementation |
| --- | --- |
| **Provider tokens stored backend-side only** | `access_token` and `base_url` stored in `provider_connections` table; never returned in API responses. |
| **Encrypt provider credentials at rest** | Use Laravel `Crypt::encryptString()` on `access_token` before insert; decrypt on use only. |
| **Never expose token to mobile** | `ProviderConnectionResource` omits `access_token` field entirely. |
| **Mobile calls Laravel API only** | Mobile does not call HA (or any provider) directly — all provider communication is server-side. |
| **Firebase Bearer on all routes** | All Smart Home API routes use `firebase.auth` middleware ([front-vibes-auth-core.md](../../../standards/front-vibes-auth-core.md)). |
| **Ownership policies** | `DevicePolicy`, `ProviderConnectionPolicy` — same scoping pattern as `SchedulePolicy` and `VibePolicy`. |
| **`user_id` from auth only** | Never trust `user_id` in request body — derive from `auth()->id()` per [back-vibes-api-rules](../../../../back_vibes/.cursor/rules). |

---

## 9. API outline

**Draft only — no implementation in Phase 1. Detailed contracts are Phase 4 deliverables.**

**Middleware:** `firebase.auth` on all routes.

### Provider connections

| Method | Path | Action |
| --- | --- | --- |
| `GET` | `/api/provider-connections` | List current user's provider connections |
| `POST` | `/api/provider-connections` | Create (test connection before save) |
| `GET` | `/api/provider-connections/{id}` | Show (no token in response) |
| `DELETE` | `/api/provider-connections/{id}` | Delete (cascade devices) |
| `POST` | `/api/provider-connections/{id}/sync` | Trigger device sync from provider |
| `POST` | `/api/provider-connections/{id}/test` | Test connection health |

### Devices

| Method | Path | Action |
| --- | --- | --- |
| `GET` | `/api/devices` | List current user's devices (all providers) |
| `POST` | `/api/devices` | Create device manually (optional MVP) |
| `GET` | `/api/devices/{device}` | Show device detail |
| `PATCH` | `/api/devices/{device}` | Update device (rename, type label) |
| `DELETE` | `/api/devices/{device}` | Delete device |
| `POST` | `/api/devices/{device}/test` | Test individual device reachability |

### Vibe device actions (draft)

| Method | Path | Action |
| --- | --- | --- |
| `GET` | `/api/vibes/{vibe}/device-actions` | List actions for a vibe |
| `POST` | `/api/vibes/{vibe}/device-actions` | Add action to vibe |
| `PATCH` | `/api/vibes/{vibe}/device-actions/{action}` | Update action |
| `DELETE` | `/api/vibes/{vibe}/device-actions/{action}` | Remove action from vibe |
| `POST` | `/api/vibes/{vibe}/device-actions/reorder` | Reorder actions (sort_order) |

**Response conventions:** Follow [`api-resource-patterns.md`](../../../standards/api-resource-patterns.md).  
**Validation:** Follow [`laravel-form-request-patterns.md`](../../../standards/laravel-form-request-patterns.md).

---

## 10. Mobile outline

**Draft only — no implementation in Phase 1.**

### Screens (Phase 6)

| Screen | Purpose |
| --- | --- |
| **Devices tab root** | Device list with status badges; entry to provider connection management |
| **Add provider connection** | Form: provider type selector (Home Assistant only MVP), base URL, token; test connection on submit |
| **Device list** | Grouped or flat list; status badge per device; pull-to-refresh triggers sync |
| **Device detail / edit** | Rename, type label; test device; delete |
| **Provider connection detail** | Show connection (no token); sync button; delete |

### Mobile constraints

| Rule | Detail |
| --- | --- |
| **No duplicate entries** | Mobile shows exactly one row per IXORA `device_id`. |
| **No offline mutations** | Creating/editing/deleting devices or connections requires network; block UI + toast when offline. |
| **Status badge required** | Each device row must show online / offline / unknown indicator. |
| **Token never displayed** | Provider connection form shows token as password input on create; after save, token field is hidden. |
| **No direct provider calls from mobile** | All provider communication is via Laravel API. |

### Device action association (Phase 7)

- A vibe detail screen gains a **Device Actions** section.
- User selects a device from their registered list, picks an action type, sets optional delay.
- Actions are ordered and can be reordered.
- Saving persists `vibe_device_actions` via API.
- No action execution in mobile MVP — execution is server-side async ([ADR-016](../../../decisions/ADR-016-smart-home-async-execution.md)).

---

## 11. Functional requirements

| ID | Requirement |
| --- | --- |
| SH-1 | All Smart Home data is **user-scoped** — `user_id` from `auth()->id()` only. |
| SH-2 | Provider connection `access_token` is **encrypted at rest** and **never returned** in API responses. |
| SH-3 | `POST /api/provider-connections` calls `testConnection()` before persisting — rejects if provider unreachable. |
| SH-4 | `POST /api/provider-connections/{id}/sync` upserts devices — no duplicates created per `(user_id, provider, provider_device_id)`. |
| SH-5 | Device `status` is one of `online \| offline \| unknown`. |
| SH-6 | Devices absent from a sync response are marked `offline` (or `unknown` per [ADR-014](../../../decisions/ADR-014-device-abstraction-and-deduplication.md)). |
| SH-7 | Provider connection unavailability sets all provider's devices to `unknown`. |
| SH-8 | `vibe_device_actions.action_type` ∈ `turn_on \| turn_off \| toggle` (MVP). |
| SH-9 | Device actions are **ordered** via `sort_order`; execution order matches ascending `sort_order`. |
| SH-10 | Device action failure **does not** block audio playback. |
| SH-11 | Device action execution is **async** — not in CRUD request path ([ADR-016](../../../decisions/ADR-016-smart-home-async-execution.md)). |
| SH-12 | `DevicePolicy` and `ProviderConnectionPolicy` enforce owner match on all mutations. |
| SH-13 | Mobile **blocks mutations offline** — no offline device CRUD. |
| SH-14 | Devices tab exists at **root navigation level** (bottom tab bar). |
| SH-15 | No direct provider calls from mobile — all via Laravel API. |

---

## 12. Acceptance criteria (Phase 1)

Phase 1 is complete when:

- [x] `spec.md` published and cross-linked
- [x] `plan.md` published
- [x] `tasks.md` published
- [x] ADR-012 — Provider strategy — accepted
- [x] ADR-013 — Home Assistant first provider — accepted
- [x] ADR-014 — Device abstraction + deduplication — accepted
- [x] ADR-015 — Vibe device action architecture — accepted
- [x] ADR-016 — Async execution — accepted
- [ ] `docs/README.md` updated with Smart Home section
- [ ] No runtime code changed
- [ ] Scope is clear enough to begin Phase 2: existing schema/domain review

---

## Delivery phases (reference)

| Phase | Deliverable |
| --- | --- |
| **1** | This spec + ADR-012, ADR-013, ADR-014, ADR-015, ADR-016 |
| **2** | Existing schema/domain review — stubs analysis, column changes documented |
| **3** | `provider_connections` model and migration |
| **4** | Device CRUD backend + `DevicePolicy` + Pest tests |
| **5** | Home Assistant adapter contract (PHP interface + HA implementation) |
| **6** | Devices mobile tab + device list + provider connection add/delete |
| **7** | Device action association UI — attach actions to vibes |
| **8** | Async execution foundation — `SmartHomeActionJob` stub + queue dispatch |
| **9** | Home Assistant real execution — job calls HA REST API |
| **10** | E2E QA — staging, device sync, action execution, dedup verification |

See [`plan.md`](plan.md) and [`tasks.md`](tasks.md).

---

## Related docs

| Document | Relationship |
| --- | --- |
| **ADR-012** — Provider strategy | [`decisions/ADR-012-smart-home-provider-strategy.md`](../../../decisions/ADR-012-smart-home-provider-strategy.md) |
| **ADR-013** — Home Assistant first | [`decisions/ADR-013-home-assistant-first-provider.md`](../../../decisions/ADR-013-home-assistant-first-provider.md) |
| **ADR-014** — Device abstraction + dedup | [`decisions/ADR-014-device-abstraction-and-deduplication.md`](../../../decisions/ADR-014-device-abstraction-and-deduplication.md) |
| **ADR-015** — Vibe device action architecture | [`decisions/ADR-015-vibe-device-action-architecture.md`](../../../decisions/ADR-015-vibe-device-action-architecture.md) |
| **ADR-016** — Async execution | [`decisions/ADR-016-smart-home-async-execution.md`](../../../decisions/ADR-016-smart-home-async-execution.md) |
| **Scheduler MVP spec** | [`specs/scheduler/mvp/spec.md`](../../scheduler/mvp/spec.md) — Smart Home is explicitly excluded from Scheduler MVP |
| **Execution plan** | [`specs/vibes/execution-plan/spec.md`](../../vibes/execution-plan/spec.md) — device actions hook into vibe play path |
| **Auth** | [`standards/front-vibes-auth-core.md`](../../../standards/front-vibes-auth-core.md) |
| **API resource patterns** | [`standards/api-resource-patterns.md`](../../../standards/api-resource-patterns.md) |
| **Laravel form request patterns** | [`standards/laravel-form-request-patterns.md`](../../../standards/laravel-form-request-patterns.md) |
| **Git Flow** | [`standards/git-flow.md`](../../../standards/git-flow.md) |
| **DigitalOcean staging** | [`architecture/backend/staging-digitalocean.md`](../../../architecture/backend/staging-digitalocean.md) — existing queue worker |
| **Plan / tasks** | [`plan.md`](plan.md), [`tasks.md`](tasks.md) |

### Schema reference (stubs)

| Artifact | Path |
| --- | --- |
| `devices` migration (stub) | `back_vibes/database/migrations/2026_05_01_000005_create_devices_table.php` |
| `vibe_device_actions` migration (stub) | `back_vibes/database/migrations/2026_05_01_000006_create_vibe_device_actions_table.php` |

When behaviour changes, update **this file first**, then ADRs, [`plan.md`](plan.md), and [`tasks.md`](tasks.md).
