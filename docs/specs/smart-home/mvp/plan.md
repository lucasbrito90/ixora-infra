# Smart Home Foundation MVP — implementation plan

**Status:** Active implementation plan (Phase 1 complete — pre-implementation)  
**Spec:** [`spec.md`](spec.md)  
**Feature ID:** `smart-home/mvp`

---

## Implementation summary

The Smart Home Foundation MVP delivers a **Devices tab** in the IXORA mobile app, **Home Assistant as the first provider**, a deduplicated **device registry** on the backend, and the **vibe device action model** that allows simple actions (`turn_on`, `turn_off`, `toggle`) to be associated with vibes. Execution of device actions is **async** and will be queue-backed when real execution ships.

**Strategy anchors:**

| Principle | Implementation |
| --- | --- |
| Provider adapter architecture | One normalised interface; new providers = new adapter only |
| Home Assistant first | Manual base URL + long-lived access token |
| Backend is authoritative | Device registry in PostgreSQL; mobile calls Laravel API only |
| Secrets server-side only | Encrypted `access_token`; never returned to mobile |
| Deduplication enforced | `UNIQUE (user_id, provider, provider_device_id)` |
| Device status in list | `online \| offline \| unknown` badge per device |
| Vibe owns action list | Actions are `vibe_device_actions`; scheduler is unaffected |
| Async execution | No provider calls in CRUD request path; queue worker |
| Audio is primary | Device action failure never blocks audio playback |

**Git Flow:** All work on **`feature/*`** branches from **`develop`** — [`git-flow.md`](../../../standards/git-flow.md). Promote to **`staging`** via merge **`develop` → `staging`**.

---

## Current state

| Area | State |
| --- | --- |
| **`devices` stub** | Migration exists — columns: `id, user_id, name, type, provider, external_id, metadata, created_at` + index `(user_id, provider, external_id)` — **no `status`, `last_seen_at`, `updated_at`; `external_id` must be renamed** |
| **`vibe_device_actions` stub** | Migration exists — columns: `id, vibe_id, device_id, action_type, parameters, delay_seconds, created_at` — **no `sort_order`, `updated_at`** |
| **`provider_connections`** | **Does not exist** — new table required |
| **Device API** | **None** |
| **Provider adapter** | **None** |
| **Devices tab (mobile)** | **None** |
| **Device action UI** | **None** |
| **Async execution job** | **None** |
| **ADRs 012–016** | **Accepted** — Phase 1 complete |
| **Scheduler MVP** | ADRs + spec + all 10 phases complete — explicitly excludes Smart Home |

---

## Phase overview

```
Phase 1  ──► Spec + ADRs (complete)
Phase 2  ──► Existing schema/domain review
Phase 3  ──► provider_connections model + migration
Phase 4  ──► Device CRUD backend (API + Policy + Pest)
Phase 5  ──► Home Assistant adapter contract
Phase 6  ──► Devices mobile tab + list + provider connection UI
Phase 7  ──► Device action association UI (attach actions to vibes)
Phase 8  ──► Async execution foundation (SmartHomeActionJob stub)
Phase 9  ──► Home Assistant real execution (job → HA REST API)
Phase 10 ──► E2E QA
```

Phases **3–5** can proceed in parallel after Phase 2. Phases **6–7** depend on the API contract from Phase 4. Phase **8** depends on Phase 5. Phase **9** depends on Phase 8.

---

## Phase 1 — Spec + ADRs

**Complete.**

### Deliverables

| Item | Output |
| --- | --- |
| Feature spec | [`spec.md`](spec.md) |
| Implementation plan | [`plan.md`](plan.md) |
| Task checklist | [`tasks.md`](tasks.md) |
| **ADR-012** | [`ADR-012-smart-home-provider-strategy.md`](../../../decisions/ADR-012-smart-home-provider-strategy.md) |
| **ADR-013** | [`ADR-013-home-assistant-first-provider.md`](../../../decisions/ADR-013-home-assistant-first-provider.md) |
| **ADR-014** | [`ADR-014-device-abstraction-and-deduplication.md`](../../../decisions/ADR-014-device-abstraction-and-deduplication.md) |
| **ADR-015** | [`ADR-015-vibe-device-action-architecture.md`](../../../decisions/ADR-015-vibe-device-action-architecture.md) |
| **ADR-016** | [`ADR-016-smart-home-async-execution.md`](../../../decisions/ADR-016-smart-home-async-execution.md) |

### Decisions locked in ADRs

| Topic | Decision |
| --- | --- |
| **Provider model** | Adapter architecture — normalised interface; new providers = new adapter |
| **First provider** | Home Assistant — base URL + LLAT; no auto-discovery |
| **Deduplication** | `UNIQUE (user_id, provider, provider_device_id)` enforced at DB |
| **Action ownership** | Vibe owns action list — scheduler is unaffected |
| **Execution model** | Async — no provider calls in CRUD path; queue worker |
| **Action failure** | Does not block audio playback |

---

## Phase 2 — Existing schema/domain review

**No migrations. Documentation and review only.**

### Goals

Analyse existing stubs to produce a **delta document** describing every column change, addition, or rename required before any migration is written. This gates Phase 3 (new table) and Phase 4 (CRUD API).

### `devices` stub review

| Current | Required | Change |
| --- | --- | --- |
| `external_id` | `provider_device_id` | **Rename column** — aligns with ADR-014 domain language |
| *(missing)* | `status` string default `unknown` | **Add column** — `online \| offline \| unknown` |
| *(missing)* | `last_seen_at` timestamp nullable | **Add column** |
| *(missing)* | `updated_at` timestamp | **Add column** |
| Index `(user_id, provider, external_id)` | `(user_id, provider, provider_device_id)` | **Update index name** after rename |
| *(missing)* | `UNIQUE (user_id, provider, provider_device_id)` | **Add unique constraint** |

### `vibe_device_actions` stub review

| Current | Required | Change |
| --- | --- | --- |
| *(missing)* | `sort_order` unsigned int default 0 | **Add column** |
| *(missing)* | `updated_at` timestamp | **Add column** |
| `action_type` (unconstrained string) | Constrained to MVP values | **Application-layer validation** — no DB check constraint in MVP |

### `provider_connections` (new table)

| Column | Type | Description |
| --- | --- | --- |
| `id` | bigint PK | |
| `user_id` | FK → `users` cascade | Owner |
| `name` | string(255) | User-visible label (e.g. "My Home HA") |
| `provider` | string(32) | Provider slug: `home_assistant` |
| `config` | json | Non-sensitive connection config (e.g. `base_url`) |
| `encrypted_credentials` | text | Laravel-encrypted JSON blob (`access_token`) |
| `last_tested_at` | timestamp nullable | When connection was last tested successfully |
| `status` | string(32) | `connected \| unreachable \| unknown` |
| `created_at` | timestamp | |
| `updated_at` | timestamp | |

Index: `(user_id, provider)` — one connection per user per provider in MVP (unique constraint optional; enforce at application layer in MVP).

### Models to review/create

| Model | Path | Action |
| --- | --- | --- |
| `Device` | `app/Models/Device.php` | Review existing; update casts/fillable for new columns |
| `VibeDeviceAction` | `app/Models/VibeDeviceAction.php` | Review existing; add sort_order, updated_at |
| `ProviderConnection` | `app/Models/ProviderConnection.php` | **New** |

**Branch:** `feature/smart-home-schema-review`

---

## Phase 3 — `provider_connections` model and migration

### Migration

Create `create_provider_connections_table` migration per schema defined in Phase 2. Include:

- All columns above
- `(user_id, provider)` index
- `encrypted_credentials` — document that raw token is never stored

### Model

- `ProviderConnection` Eloquent model
- `casts`: `config` → `array`, `encrypted_credentials` uses custom accessor that decrypts on read (never in API resource output)
- `fillable`: all except `user_id` (assigned from `auth()->id()`)
- `$hidden`: `encrypted_credentials`

### Provider slug enum/constant

```php
// App\SmartHome\ProviderType
const HOME_ASSISTANT = 'home_assistant';
// Future: TUYA, HUE, ...
```

**Branch:** `feature/smart-home-provider-connection-model`

---

## Phase 4 — Device CRUD backend

### Endpoints

Per [`spec.md`](spec.md) § 9 — `/api/devices` + `/api/provider-connections` REST.

### Laravel conventions

Follow [`back-vibes-api-rules`](../../../../back_vibes/.cursor/rules):

- **`StoreDeviceRequest` / `UpdateDeviceRequest`**
- **`StoreProviderConnectionRequest`** — validates base URL (HTTPS), token present; calls `testConnection()` before save
- **`DeviceController`** — authorize, delegate to service, return Resource
- **`ProviderConnectionController`** — authorize, delegate, return Resource (no token in response)
- **`DevicePolicy`** / **`ProviderConnectionPolicy`** — owner scoping
- `user_id` from `auth()->id()` — never from request body

### `ProviderConnectionResource`

Must omit `encrypted_credentials` / `access_token`. Expose only: `id, name, provider, config (base_url), status, last_tested_at, created_at, updated_at`.

### Sync action (`POST /api/provider-connections/{id}/sync`)

1. Load `ProviderConnection` with policy check
2. Instantiate correct provider adapter (`ProviderType::HOME_ASSISTANT` → `HomeAssistantAdapter`)
3. Call `adapter.listDevices(connection)`
4. Upsert each device: `INSERT ... ON CONFLICT (user_id, provider, provider_device_id) DO UPDATE ...`
5. Devices absent from provider response → set `status = offline`
6. If provider unreachable → set all connection's devices to `status = unknown`
7. Return sync summary: `{ synced: N, updated: M, new: K, errors: [] }`

### Tests (Pest feature)

- CRUD happy paths for devices and provider connections
- 403 cross-user
- 422 invalid provider, invalid base URL, non-HTTPS
- Sync upsert — no duplicates on repeated sync
- Sync offline provider — devices become `unknown`
- `ProviderConnectionResource` — no token in response

**Branch:** `feature/smart-home-device-crud`

---

## Phase 5 — Home Assistant adapter contract

### PHP interface

```php
// App\SmartHome\Contracts\ProviderAdapter
interface ProviderAdapter
{
    public function listDevices(ProviderConnection $connection): array;
    public function readStatus(ProviderConnection $connection, string $deviceId): DeviceStatus;
    public function executeAction(ProviderConnection $connection, string $deviceId, string $action, array $parameters = []): ActionResult;
    public function testConnection(ProviderConnection $connection): ConnectionHealth;
}
```

### `HomeAssistantAdapter` (MVP implementation)

| Method | HA API call |
| --- | --- |
| `listDevices()` | `GET {base_url}/api/states` → parse entity list |
| `readStatus()` | `GET {base_url}/api/states/{entity_id}` |
| `executeAction()` | `POST {base_url}/api/services/{domain}/{service}` |
| `testConnection()` | `GET {base_url}/api/` — expect 200 + `{"message": "API running."}` |

**Auth:** `Authorization: Bearer {decrypted access_token}` on all HA requests.

**Timeout:** Configurable; default 10 s for `testConnection()` and `readStatus()`; configurable for `executeAction()`.

**HTTP client:** Laravel HTTP facade (`Http::timeout(10)->withToken(...)->get(...)`) — mockable in tests.

### DTOs

- `DeviceStatus`: `entity_id`, `state` (on/off/unavailable/…), `attributes`, `last_changed`
- `ActionResult`: `success`, `status_code`, `response`, `error_message`
- `ConnectionHealth`: `reachable`, `latency_ms`, `error`

### Tests

- Unit tests with mocked HTTP — `listDevices`, `readStatus`, `executeAction`, `testConnection`
- Happy paths + HA unreachable (timeout, 401, 500)
- `turn_on` maps to `light.turn_on` HA service; `turn_off` → `light.turn_off`; `toggle` → `light.toggle`

**Branch:** `feature/smart-home-ha-adapter`

---

## Phase 6 — Devices mobile tab + provider connection UI

### Scope

- Add **Devices** to bottom tab bar at root navigation level
- Screens: Device list, Add provider connection, Provider connection detail, Device detail/edit

### Mobile conventions

- All API calls use Firebase Bearer — [`front-vibes-auth-core.md`](../../../standards/front-vibes-auth-core.md)
- **Block mutations offline** — toast + disable actions
- `device.service.ts` and `provider-connection.service.ts` — REST clients
- Status badge: `online` (green) / `offline` (red) / `unknown` (grey)
- No direct HA calls from mobile

### Routing

Per [`front-vibes-ionic-routing.md`](../../../standards/front-vibes-ionic-routing.md):

- `/devices` — device list (tab root)
- `/devices/providers/new` — add provider connection
- `/devices/providers/:id` — provider connection detail
- `/devices/:id` — device detail / edit

**Branch:** `feature/smart-home-devices-mobile`

**Platform:** Android + iOS (cross-platform; no native-only API in this phase)

---

## Phase 7 — Device action association UI

### Scope

- Vibe detail screen gains a **Device Actions** section
- User selects a device + action type + optional delay
- Reorder actions via drag/sort
- Save persists `vibe_device_actions` via API (Phase 4 endpoint)

### Constraints

- No action execution from mobile UI in this phase (async only — Phase 9)
- No complex conditions or automations
- Only MVP action types: `turn_on`, `turn_off`, `toggle`

### API dependency

Requires `GET /api/vibes/{vibe}/device-actions` and related mutations from Phase 4.

**Branch:** `feature/smart-home-vibe-action-ui`

---

## Phase 8 — Async execution foundation

### Scope

Introduce `SmartHomeActionJob` queue job (stub — logs intent but does not call HA yet).

- Job accepts: `vibe_device_action_id`, `vibe_play_event_id` (TBD)
- Job is dispatched when vibe play event is recorded (exact trigger TBD in future spec)
- Job logs dispatch — sets up for Phase 9 real execution
- Reuses existing `queue` worker — no new infra

### Queue configuration

- Job class: `App\Jobs\SmartHome\SmartHomeActionJob`
- Queue: `default` (or dedicated `smart-home` queue — config decision)
- Timeout: 30 s (configurable)
- Retries: 0 in MVP (no retry — see [ADR-016](../../../decisions/ADR-016-smart-home-async-execution.md))

### Tests

- Dispatch job and assert it is queued
- Job fails gracefully on unresolvable `vibe_device_action_id`

**Branch:** `feature/smart-home-async-foundation`

---

## Phase 9 — Home Assistant real execution

### Scope

`SmartHomeActionJob` calls the `HomeAssistantAdapter` to execute the action against the user's HA instance.

- Resolve `ProviderConnection` from `device.provider` + `device.user_id`
- Decrypt credentials
- Call `adapter.executeAction(connection, device.provider_device_id, action.action_type, action.parameters)`
- Log result (success / failure / timeout) — `action_execution_logs` table or `vibe_device_actions.log` column (design decision in Phase 9 spec)
- **Audio playback is not affected** by job outcome

### Tests

- Feature test with mocked HA HTTP — success path
- Provider unreachable — job catches exception, logs failure, does not rethrow
- Token decryption failure — fails gracefully

**Branch:** `feature/smart-home-ha-execution`

---

## Phase 10 — E2E QA

### Staging validation

1. Register HA provider connection via mobile → `POST /api/provider-connections` → test passes
2. Trigger sync → `POST /api/provider-connections/{id}/sync` → devices appear in list
3. Re-trigger sync → no duplicate devices (verify count is unchanged)
4. Devices show correct status badge (online / offline / unknown)
5. Attach action to a vibe → `POST /api/vibes/{vibe}/device-actions`
6. Trigger play event → job dispatched → HA receives service call
7. Delete provider connection → devices cascade-deleted
8. Offline: block mutation UI

### Security validation

- `GET /api/provider-connections/{id}` — `access_token` absent from response
- `GET /api/devices` with different user's token → 403
- Non-HTTPS base URL on create → 422

**Branch:** `feature/smart-home-qa` (or QA notes in `qa/` folder)

---

## Backend plan summary

| Keep / build | Detail |
| --- | --- |
| `provider_connections` | New table — encrypted credentials, test on create |
| `devices` | Stub enhanced — `provider_device_id` rename, `status`, `last_seen_at` |
| `vibe_device_actions` | Stub enhanced — `sort_order`, `updated_at` |
| `DevicePolicy` / `ProviderConnectionPolicy` | Owner scoping |
| `HomeAssistantAdapter` | Implements `ProviderAdapter` interface |
| `SmartHomeActionJob` | Queue job — async execution; no provider call in CRUD path |
| No FCM changes | Smart Home is independent of Scheduler notification path |
| No Scheduler changes | ADR-015 — scheduler does not invoke device actions |

---

## Mobile plan summary

| Keep / build | Detail |
| --- | --- |
| Devices tab | Root navigation — tab bar |
| Device list | Status badge per device |
| Provider connection add/delete | HA form — base URL + token (write-only) |
| Device action association | Vibe detail → add/reorder/delete actions |
| No direct HA calls | Mobile calls Laravel API only |
| No offline mutations | Block UI + toast when offline |

---

## Infra / CDN impact

| Topic | Impact |
| --- | --- |
| Spaces / CDN | **None** — Smart Home is metadata only |
| PostgreSQL | New `provider_connections` table; `devices` + `vibe_device_actions` columns; action execution logs (Phase 9) |
| App Platform | **No new workers** — existing `queue` worker handles `SmartHomeActionJob` |
| OpenTofu | **No changes in MVP** — existing worker configuration sufficient |
| Secrets | `APP_KEY` (already set) used for `Crypt::encryptString()` — no new secrets |

---

## Open questions

| # | Question | Default / note |
| --- | --- | --- |
| 1 | **Vibe play trigger endpoint** for dispatching device action jobs | Deferred — Phase 8 spec; `POST /api/vibes/{vibe}/play` or embedded in existing play flow |
| 2 | **Action execution log storage** — separate table vs column on `vibe_device_actions` | Separate table preferred; detail in Phase 9 |
| 3 | **Multiple HA connections per user** | One per user in MVP; enforce at application layer |
| 4 | **Non-HTTPS base URL for dev/local testing** | Config override (`SMART_HOME_ALLOW_HTTP=true`) — security doc required |
| 5 | **Queue name** for `SmartHomeActionJob` | `default` initially; dedicated `smart-home` queue if volume warrants |
| 6 | **Retry policy** for failed HA calls | Phase 9 spec — 0 retries in MVP per [ADR-016](../../../decisions/ADR-016-smart-home-async-execution.md) |

---

## Future work (explicitly out of MVP)

| Topic | Phase |
| --- | --- |
| Tuya, Philips Hue, Alexa, Google Home adapters | Provider ADR per integration |
| Matter / Thread / Zigbee direct | Requires local network or Matter cloud — future arch ADR |
| Conditional automations / scenes | Not planned for Foundation MVP |
| Brightness / color / temperature actions | Future action types — no migration required (parameters JSON) |
| ActionExecutionLog mobile UI | Post Phase 9 |
| `monthly` recurrence (Scheduler) | Separate Scheduler domain — not related |
| Token rotation / refresh | HA LLAT does not expire; future spec if needed |
| Smart Home schedules separate from Scheduler | Explicitly not planned — actions are vibe-scoped |

---

## Related docs

| Document | Path |
| --- | --- |
| **Feature spec** | [`spec.md`](spec.md) |
| **Task checklist** | [`tasks.md`](tasks.md) |
| **ADR-012** — Provider strategy | [`decisions/ADR-012-smart-home-provider-strategy.md`](../../../decisions/ADR-012-smart-home-provider-strategy.md) |
| **ADR-013** — Home Assistant first | [`decisions/ADR-013-home-assistant-first-provider.md`](../../../decisions/ADR-013-home-assistant-first-provider.md) |
| **ADR-014** — Device abstraction + dedup | [`decisions/ADR-014-device-abstraction-and-deduplication.md`](../../../decisions/ADR-014-device-abstraction-and-deduplication.md) |
| **ADR-015** — Vibe device action architecture | [`decisions/ADR-015-vibe-device-action-architecture.md`](../../../decisions/ADR-015-vibe-device-action-architecture.md) |
| **ADR-016** — Async execution | [`decisions/ADR-016-smart-home-async-execution.md`](../../../decisions/ADR-016-smart-home-async-execution.md) |
| Scheduler MVP spec | [`specs/scheduler/mvp/spec.md`](../../scheduler/mvp/spec.md) |
| Execution plan | [`specs/vibes/execution-plan/spec.md`](../../vibes/execution-plan/spec.md) |
| Auth | [`standards/front-vibes-auth-core.md`](../../../standards/front-vibes-auth-core.md) |
| Git Flow | [`standards/git-flow.md`](../../../standards/git-flow.md) |
| DigitalOcean staging | [`architecture/backend/staging-digitalocean.md`](../../../architecture/backend/staging-digitalocean.md) |

When behaviour changes, update **`spec.md` first**, then this plan and [`tasks.md`](tasks.md).
