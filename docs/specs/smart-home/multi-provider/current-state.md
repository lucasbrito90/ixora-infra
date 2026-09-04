# Smart Home — current state audit (back_vibes)

**Status:** Investigation report (v1.4.0 T01 — read-only audit)  
**Date:** 2026-09-02  
**Feature ID:** `smart-home/multi-provider`  
**Source repo:** `back_vibes` (authoritative runtime)  
**Spec baseline compared:** [`../mvp/spec.md`](../mvp/spec.md), [`../mvp/schema-review.md`](../mvp/schema-review.md)

> This document describes **what exists in code today**, with file-and-line evidence for every claim. It does not propose architecture, refactors, or fixes. Divergences from the MVP spec are consolidated in §10.

---

## 1. Provider abstraction layer

Inventory of `back_vibes/app/SmartHome/**` (20 PHP files).

### 1.1 `Contracts/ProviderAdapter.php`

**Responsibility:** Normalised contract every Smart Home provider adapter implements; decouples sync/action logic from provider specifics (`ProviderAdapter.php:15-20`).

**Public surface:** Four methods on `ProviderAdapter` interface.

**Error handling policy (interface docblock, verbatim):**

```22:28:back_vibes/app/SmartHome/Contracts/ProviderAdapter.php
 * Error handling policy:
 * - testConnection(): never throws; returns ConnectionHealth(reachable=false) on failure.
 * - readStatus(): never throws; returns DeviceStatusResult(status=Unknown) on failure.
 * - executeAction(): never throws for transport/HTTP failures (returns failed
 *   ActionResult); throws UnsupportedSmartHomeActionException for unmappable actions.
 * - listDevices(): throws ProviderConnectionException when the provider is
 *   unreachable or returns a non-2xx response (so sync can mark devices unknown).
```

**Method signatures (verbatim transcription):**

```39:63:back_vibes/app/SmartHome/Contracts/ProviderAdapter.php
    public function listDevices(ProviderConnection $connection): array;

    /**
     * Read the current status of a single device.
     */
    public function readStatus(ProviderConnection $connection, string $deviceId): DeviceStatusResult;

    /**
     * Execute an action against a device.
     *
     * @param  array<string, mixed>  $parameters
     *
     * @throws UnsupportedSmartHomeActionException When the action is not mappable.
     */
    public function executeAction(
        ProviderConnection $connection,
        string $deviceId,
        string $action,
        array $parameters = []
    ): ActionResult;

    /**
     * Verify the connection credentials are reachable and report health.
     */
    public function testConnection(ProviderConnection $connection): ConnectionHealth;
```

`listDevices()` docblock additionally documents `@throws ProviderConnectionException` (`ProviderAdapter.php:37-37`).

### 1.2 Concrete adapters

| File | Responsibility | Public API |
| --- | --- | --- |
| `Adapters/HomeAssistantAdapter.php` | Home Assistant REST adapter (`HomeAssistantAdapter.php:24-31`) | Implements all four `ProviderAdapter` methods; private HTTP/client helpers |

No other concrete adapters exist under `app/SmartHome/Adapters/` (`Glob` over `app/SmartHome/Adapters/` returns only `HomeAssistantAdapter.php`).

### 1.3 `ProviderAdapterResolver.php`

**Responsibility:** Resolves the correct `ProviderAdapter` for a provider slug or enum (`ProviderAdapterResolver.php:11-17`).

**Public API:**

- `__construct(HomeAssistantAdapter $homeAssistant)` — constructor injection of the sole adapter (`ProviderAdapterResolver.php:20-22`)
- `forProvider(ProviderType|string $provider): ProviderAdapter` — `match` on `ProviderType`; `HomeAssistant` → `$this->homeAssistant`; `default` throws `InvalidArgumentException` (`ProviderAdapterResolver.php:27-38`)

**Adding a new provider today requires:**

1. A new concrete adapter class implementing `ProviderAdapter`.
2. A new `ProviderType` case (if not already reserved).
3. Constructor injection of the new adapter in `ProviderAdapterResolver::__construct()` (`ProviderAdapterResolver.php:20-22`).
4. A new arm in the `match` inside `forProvider()` (`ProviderAdapterResolver.php:33-38`).

### 1.4 Enums

#### `ProviderType.php`

| Case | Value |
| --- | --- |
| `HomeAssistant` | `home_assistant` |
| `Tuya` | `tuya` |
| `PhilipsHue` | `philips_hue` |
| `Alexa` | `alexa` |
| `GoogleHome` | `google_home` |
| `Matter` | `matter` |

(`ProviderType.php:17-33`)

- `mvpAllowed(): array` returns `[self::HomeAssistant]` only (`ProviderType.php:36-39`).
- `isMvpSupported(): bool` returns `$this === self::HomeAssistant` (`ProviderType.php:41-44`).

**Practical restriction:** HTTP FormRequests for provider connections validate `provider` with `Rule::in(...ProviderType::mvpAllowed())` — only `home_assistant` is accepted on create/update (`StoreProviderConnectionRequest.php:22-25`, `UpdateProviderConnectionRequest.php:22-25`). Reserved enum cases (`tuya`, etc.) are rejected by `ProviderAdapterResolver::forProvider()` with `InvalidArgumentException` (`ProviderAdapterResolver.php:35-37`).

#### `ActionType.php`

| Case | Value |
| --- | --- |
| `TurnOn` | `turn_on` |
| `TurnOff` | `turn_off` |
| `Toggle` | `toggle` |

(`ActionType.php:17-20`)

- `mvpAllowed()` returns all three cases (`ActionType.php:23-26`).
- `isMvpSupported()` always returns `true` (`ActionType.php:29-32`).

Used in `StoreSceneActionRequest` / `UpdateSceneActionRequest` validation (`StoreSceneActionRequest.php:72-78`).

#### `DeviceStatus.php`

| Case | Value |
| --- | --- |
| `Online` | `online` |
| `Offline` | `offline` |
| `Unknown` | `unknown` |

(`DeviceStatus.php:17-20`)

- `values(): array` — all case value strings for validation (`DeviceStatus.php:23-26`).
- No `mvpAllowed()` / `isMvpSupported()` methods.

#### `ConnectionStatus.php`

| Case | Value |
| --- | --- |
| `Connected` | `connected` |
| `Unreachable` | `unreachable` |
| `Unknown` | `unknown` |

(`ConnectionStatus.php:15-18`)

- `values(): array` — all case value strings (`ConnectionStatus.php:21-24`).
- No `mvpAllowed()` / `isMvpSupported()` methods.

### 1.5 DTOs

| DTO | Fields (name → type) |
| --- | --- |
| `DTOs/ProviderDevice.php` | `provider_device_id: string`, `name: string`, `type: string`, `status: DeviceStatus`, `metadata: array<string,mixed>`, `last_seen_at: ?Carbon` (`ProviderDevice.php:22-28`) |
| `DTOs/ActionResult.php` | `success: bool`, `status_code: ?int`, `response: ?array`, `error_message: ?string` (`ActionResult.php:19-24`) |
| `DTOs/ConnectionHealth.php` | `reachable: bool`, `status_code: ?int`, `latency_ms: ?int`, `error_message: ?string` (`ConnectionHealth.php:16-21`) |
| `DTOs/DeviceStatusResult.php` | `provider_device_id: string`, `status: DeviceStatus`, `raw_state: ?string`, `attributes: array`, `last_changed: ?string` (`DeviceStatusResult.php:19-25`) |
| `DTOs/SyncResult.php` | `provider_connection_id: int`, `synced: int`, `created: int`, `updated: int`, `offline: int`, `status: string` (`SyncResult.php:15-22`) |
| `DTOs/SmartHomeDispatchResult.php` | `vibe_id: int`, `dispatched: int`, `skipped: int`, `action_ids: list<int>` (`SmartHomeDispatchResult.php:17-22`) |
| `DTOs/SceneDispatchResult.php` | `scene_id: int`, `dispatched: int`, `skipped: int`, `action_ids: list<int>` (`SceneDispatchResult.php:17-22`) |

All DTOs are `final readonly class` with public constructor-promoted properties.

### 1.6 Services

| File | Responsibility | Public API |
| --- | --- | --- |
| `Services/ProviderDeviceSyncService.php` | Orchestrates device sync for one connection (`ProviderDeviceSyncService.php:19-32`) | `sync(ProviderConnection $connection): SyncResult` |
| `Services/VibeSmartHomeDispatchService.php` | Enqueues `SceneActionJob` per scene action linked to vibe's scene (`VibeSmartHomeDispatchService.php:13-26`) | `dispatch(Vibe $vibe): SmartHomeDispatchResult` |
| `Services/SceneDispatchService.php` | Enqueues `SceneActionJob` per scene action (`SceneDispatchService.php:12-24`) | `dispatch(Scene $scene): SceneDispatchResult` |

### 1.7 Exceptions

| File | Responsibility | Public API |
| --- | --- | --- |
| `Exceptions/ProviderConnectionException.php` | Thrown when provider unreachable / bad status on `listDevices()` (`ProviderConnectionException.php:9-16`) | `unreachable(string $provider): self`, `badStatus(string $provider, int $statusCode): self` |
| `Exceptions/UnsupportedSmartHomeActionException.php` | Thrown for unmappable action types (`UnsupportedSmartHomeActionException.php:9-14`) | `forAction(string $action): self` |

### 1.8 Validation

| File | Responsibility | Public API |
| --- | --- | --- |
| `Validation/ScheduleAutomationValidator.php` | Validates schedule-triggered Smart Home automation integrity (`ScheduleAutomationValidator.php:13-20`) | `validate(Schedule $schedule): bool` — returns `false` on failure, never throws (`ScheduleAutomationValidator.php:17-18`) |

---

## 2. Capabilities

| Question | Answer | Evidence |
| --- | --- | --- |
| Column `capabilities` (or equivalent) on `devices`? | **No** | `devices` create migration defines `id`, `user_id`, `name`, `type`, `provider`, `external_id`, `metadata`, `created_at` only (`2026_05_01_000005_create_devices_table.php:11-22`). Hardening adds `provider_connection_id`, `status`, `last_seen_at`, `updated_at` — no `capabilities` (`2026_06_14_000002_harden_devices_table.php:39-47`). `Device` model `$fillable` has no capabilities field (`Device.php:33-43`). Workspace-wide grep for `capabilities` in `back_vibes` returns zero matches. |
| Field `capabilities` on DTO `ProviderDevice`? | **No** | Constructor fields are `provider_device_id`, `name`, `type`, `status`, `metadata`, `last_seen_at` only (`ProviderDevice.php:22-28`). |
| Capability discovery method on `ProviderAdapter`? | **No** | Interface exposes `listDevices`, `readStatus`, `executeAction`, `testConnection` only (`ProviderAdapter.php:39-63`). |
| Validation of action against device capability in any layer? | **No** | Scene action validation checks `action_type` against `ActionType::mvpAllowed()` and device ownership (`StoreSceneActionRequest.php:28-31`, `52-69`). No capability check. `HomeAssistantAdapter::executeAction()` maps action string via static `ACTION_SERVICE_MAP`; unknown actions throw `UnsupportedSmartHomeActionException` at runtime (`HomeAssistantAdapter.php:48-52`, `133-137`), not against stored device capabilities. |
| What `HomeAssistantAdapter` stores in `metadata`? | See below | `mapDevice()` builds metadata (`HomeAssistantAdapter.php:258-269`) |

**`HomeAssistantAdapter::mapDevice()` metadata keys:**

| Key | Source | Interpreted or pass-through |
| --- | --- | --- |
| `domain` | Derived from `entity_id` via `domainFor()` | **Interpreted** — used for HA service path and device `type` |
| `raw_state` | HA state string | **Interpreted** — fed to `mapStatus()` for `DeviceStatus`; also stored raw in metadata |
| `supported_features` | HA attributes, if present | **Pass-through** — copied into metadata only when key exists (`HomeAssistantAdapter.php:263-265`) |
| `device_class` | HA attributes, if present | **Pass-through** — copied into metadata only when key exists (`HomeAssistantAdapter.php:267-269`) |

Device `type` column receives the HA domain string (`HomeAssistantAdapter.php:276`), not a separate capability model.

---

## 3. Real schema (migrations)

Composite view after all altering migrations.

### 3.1 `provider_connections`

**Created:** `2026_06_14_000001_create_provider_connections_table.php`

| Column | Type | Nullable / default |
| --- | --- | --- |
| `id` | bigint PK | NOT NULL, auto-increment |
| `user_id` | bigint FK → `users.id` | NOT NULL, `cascadeOnDelete` |
| `name` | string(255) | NOT NULL |
| `provider` | string(32) | NOT NULL |
| `config` | json | NOT NULL |
| `encrypted_credentials` | text | NOT NULL |
| `status` | string(32) | NOT NULL, default `'unknown'` |
| `last_tested_at` | timestamp | NULLABLE |
| `created_at`, `updated_at` | timestamps | NOT NULL |

**Indexes / constraints:**

| Name | Columns | Unique |
| --- | --- | --- |
| `uq_provider_connections_user_provider` | `(user_id, provider)` | **Yes** |

(`2026_06_14_000001_create_provider_connections_table.php:13-25`)

**Practical consequence of unique index:** A user may have **at most one row per provider slug** (e.g. one `home_assistant` connection). Attempting to insert a second connection with the same `(user_id, provider)` violates the unique constraint.

No subsequent migration alters this table.

### 3.2 `devices`

**Created:** `2026_05_01_000005_create_devices_table.php`  
**Altered:** `2026_06_14_000002_harden_devices_table.php`, `2026_06_17_000001_make_devices_type_nullable.php`

| Column | Type | Nullable / default |
| --- | --- | --- |
| `id` | bigint PK | NOT NULL |
| `user_id` | bigint FK → `users.id` | NOT NULL, `cascadeOnDelete` |
| `provider_connection_id` | bigint FK → `provider_connections.id` | NOT NULL, `cascadeOnDelete` (hardened from nullable) |
| `name` | string | NOT NULL |
| `type` | string | **NULLABLE** (Phase 4B) |
| `provider` | string | NOT NULL |
| `provider_device_id` | string | NOT NULL (renamed from `external_id`) |
| `metadata` | json | NULLABLE |
| `status` | string(32) | NOT NULL, default `'unknown'` |
| `last_seen_at` | timestamp | NULLABLE |
| `created_at` | timestamp | NOT NULL |
| `updated_at` | timestamp | NULLABLE → backfilled |

**Foreign keys:**

| Column | References | On delete | Constraint name |
| --- | --- | --- | --- |
| `user_id` | `users.id` | CASCADE | implicit |
| `provider_connection_id` | `provider_connections.id` | CASCADE | `fk_devices_provider_connection_id` |

**Indexes:**

| Name | Columns | Unique |
| --- | --- | --- |
| *(implicit from FK)* | `user_id` | No |
| `uq_devices_connection_provider_device_id` | `(provider_connection_id, provider_device_id)` | **Yes** |
| `idx_devices_user_provider` | `(user_id, provider)` | No |

(`2026_06_14_000002_harden_devices_table.php:97-103`)

**Practical consequence of device unique key:** Upsert/dedup is scoped to **connection + provider device id**, not `(user_id, provider, provider_device_id)` as the MVP plan once stated.

### 3.3 `scenes`

**Created:** `2026_08_30_192809_create_scenes_table.php`

| Column | Type | Nullable / default |
| --- | --- | --- |
| `id` | bigint PK | NOT NULL |
| `user_id` | bigint FK → `users.id` | NOT NULL, `cascadeOnDelete`, indexed |
| `name` | string | NOT NULL |
| `description` | string | NULLABLE |
| `created_at`, `updated_at` | timestamps | NOT NULL |

No altering migrations.

### 3.4 `scene_actions`

**Created:** `2026_08_30_192810_create_scene_actions_table.php`

| Column | Type | Nullable / default |
| --- | --- | --- |
| `id` | bigint PK | NOT NULL |
| `scene_id` | unsigned bigint FK → `scenes.id` | NOT NULL, `cascadeOnDelete` |
| `device_id` | unsigned bigint FK → `devices.id` | NOT NULL, `cascadeOnDelete` |
| `action_type` | string | NOT NULL |
| `parameters` | json | NULLABLE |
| `delay_seconds` | unsigned smallint | NOT NULL, default `0` |
| `sort_order` | unsigned int | NOT NULL, default `0` |
| `created_at`, `updated_at` | timestamps | NOT NULL |

**Foreign keys:** `fk_sa_scene`, `fk_sa_device` (`2026_08_30_192810_create_scene_actions_table.php:23-26`)

**Indexes:**

| Name | Columns | Unique |
| --- | --- | --- |
| `idx_sa_scene_sort` | `(scene_id, sort_order)` | No |

### 3.5 Related: `vibes.scene_id`

**Added:** `2026_09_02_230449_add_scene_id_to_vibes_table.php`

- `scene_id` — nullable FK → `scenes.id`, `nullOnDelete` (`2026_09_02_230449_add_scene_id_to_vibes_table.php:14-18`)

### 3.6 Removed: `vibe_device_actions`

**Dropped:** `2026_09_02_232728_drop_vibe_device_actions_table.php` (`2026_09_02_232728_drop_vibe_device_actions_table.php:23-29`)

Earlier create/harden migrations for `vibe_device_actions` remain in history but the table is dropped on forward migrate.

---

## 4. Models and persistence

### 4.1 `Device`

- **`$fillable`:** `user_id`, `provider_connection_id`, `name`, `type`, `provider`, `provider_device_id`, `status`, `metadata`, `last_seen_at` (`Device.php:33-43`)
- **`casts()`:** `metadata` → `array`, `last_seen_at` → `datetime` (`Device.php:45-50`)
- **`$hidden`:** none defined
- **Relationships:** `user()` BelongsTo, `providerConnection()` BelongsTo (`Device.php:57-65`)
- **Helper:** `isOnline(): bool` (`Device.php:71-74`)

### 4.2 `ProviderConnection`

- **`$fillable`:** `name`, `provider`, `config`, `encrypted_credentials`, `status`, `last_tested_at` — **`user_id` is not fillable**; set on create in controller (`ProviderConnection.php:40-47`, `ProviderConnectionController.php:46`)
- **`casts()`:** `config` → `array`, `last_tested_at` → `datetime` (`ProviderConnection.php:49-55`)
- **`$hidden`:** `encrypted_credentials` (`ProviderConnection.php:38`)
- **Relationships:** `user()` BelongsTo, `devices()` HasMany (`ProviderConnection.php:93-101`)
- **Credential encryption:**
  - **Encrypt:** `setEncryptedCredentials(array $credentials)` — JSON-encode then `Crypt::encryptString()` (`ProviderConnection.php:70-73`)
  - **Decrypt:** `decryptedCredentials(): array` — `Crypt::decryptString()` then `json_decode` (`ProviderConnection.php:84-87`)
- **Decryption call site in production:** `HomeAssistantAdapter::client()` reads `(string) ($connection->decryptedCredentials()['access_token'] ?? '')` for Bearer token (`HomeAssistantAdapter.php:218-223`). No HTTP controller or resource calls `decryptedCredentials()`.

### 4.3 `Scene`

- **`#[Fillable]`:** `user_id`, `name`, `description` (`Scene.php:23`)
- **`casts()`:** none declared
- **`$hidden`:** none
- **Relationships:** `user()` BelongsTo, `actions()` HasMany ordered by `sort_order` (`Scene.php:29-38`)

### 4.4 `SceneAction`

- **`#[Fillable]`:** `scene_id`, `device_id`, `action_type`, `parameters`, `delay_seconds`, `sort_order` (`SceneAction.php:25-32`)
- **`casts()`:** `parameters` → `array`, `sort_order` / `delay_seconds` → `integer` (`SceneAction.php:38-44`)
- **Relationships:** `scene()` BelongsTo, `device()` BelongsTo (`SceneAction.php:47-55`)

### 4.5 `Vibe` (Smart Home linkage)

- **`scene_id`** in `#[Fillable]` (`Vibe.php:12`)
- **Relationship:** `scene()` BelongsTo (`Vibe.php:29-32`)

---

## 5. Discovery vs execution flows

### 5.1 Device synchronization (discovery)

| Aspect | Behaviour | Evidence |
| --- | --- | --- |
| **Entry point** | `POST` sync on provider connection — `ProviderConnectionController::sync()` | `ProviderConnectionController.php:86-107` |
| **Sync/async** | **Synchronous** HTTP request; no queue job | Controller calls `$syncService->sync()` inline (`ProviderConnectionController.php:90-91`); `ProviderDeviceSyncService` docblock: "Does not dispatch jobs" (`ProviderDeviceSyncService.php:30-31`) |
| **Orchestrator** | `ProviderDeviceSyncService::sync()` | `ProviderDeviceSyncService.php:44-80` |
| **Adapter resolution** | `ProviderAdapterResolver::forProvider($connection->provider)` | `ProviderDeviceSyncService.php:46` |
| **Provider fetch** | `$adapter->listDevices($connection)` | `ProviderDeviceSyncService.php:49` |
| **Upsert key** | `(provider_connection_id, provider_device_id)` via `Device::updateOrCreate()` | `ProviderDeviceSyncService.php:101-105` |
| **Devices absent from response** | Marked **`offline`** (only rows where status ≠ offline already) | `markAbsentDevicesOffline()` (`ProviderDeviceSyncService.php:135-145`) |
| **Provider unreachable** | Connection → `unreachable`; **all** connection devices → **`unknown`**; push notification; exception rethrown → HTTP 502 | `markConnectionUnreachable()` (`ProviderDeviceSyncService.php:155-162`); catch block (`ProviderDeviceSyncService.php:50-61`); controller 502 (`ProviderConnectionController.php:92-96`) |
| **Successful sync** | Connection → `connected`, `last_tested_at = now()` | `markConnectionConnected()` (`ProviderDeviceSyncService.php:148-153`) |

**Note:** `ProviderAdapter::readStatus()` and `testConnection()` are **not** invoked by the sync service or any HTTP controller (`grep readStatus` / `testConnection` under `app/Http` returns no matches). Status on sync comes from HA `/api/states` payload via `listDevices()` → `mapDevice()` → `mapStatus()`.

### 5.2 Action execution

| Aspect | Behaviour | Evidence |
| --- | --- | --- |
| **Manual vibe dispatch** | `VibeSmartHomeDispatchController` → `VibeSmartHomeDispatchService::dispatch()` | `VibeSmartHomeDispatchController.php:48-51` |
| **Manual scene dispatch** | `SceneDispatchController` → `SceneDispatchService::dispatch()` | `SceneDispatchController.php:48-51` |
| **Scheduled dispatch** | `DispatchDueSchedulesCommand::dispatchSmartHomeAfterSchedule()` after schedule occurrence committed | `DispatchDueSchedulesCommand.php:190-228` |
| **Job enqueued** | `SceneActionJob::dispatch($action->id)` — one job per action | `VibeSmartHomeDispatchService.php:53`, `SceneDispatchService.php:45` |
| **Queue name** | `smart-home` (constructor `$this->onQueue('smart-home')`) | `SceneActionJob.php:52`, `SceneActionJob.php:49-53` |
| **`$timeout`** | `30` | `SceneActionJob.php:45` |
| **`$tries`** | `3` | `SceneActionJob.php:47` |
| **Job handler flow** | Load action + device + connection; resolve adapter; `executeAction()` inside telemetry wrap | `SceneActionJob.php:60-124` |
| **Exception handling in job** | See below | `SceneActionJob.php:104-145` |

**What `SceneActionJob` does with caught exceptions:**

1. **`UnsupportedSmartHomeActionException`:** Logs warning with `outcome=unsupported`; **does not rethrow**; **no push notification** (`SceneActionJob.php:131-136`).
2. **Generic `Throwable`:** Logs error with `outcome=failure`; calls `notifyActionFailed()`; **does not rethrow** (`SceneActionJob.php:137-145`).
3. **`ActionResult` with `success: false`:** Logs warning; calls `notifyActionFailed()`; no exception thrown (`SceneActionJob.php:128-130`, `165-176`).
4. **Guard paths** (action/device/connection missing): Log warning and **return** early — no exception (`SceneActionJob.php:63-93`).

Because all exceptions are swallowed inside `handle()`, Laravel queue **`tries = 3` is not exercised for provider failures** in practice (`SmartHomeActionTelemetry.php:73-82` documents this as pre-existing).

**`delay_seconds`:** Stored on `scene_actions` and exposed via API (`SceneAction.php:30`, `SceneActionResource.php:21`) but **`SceneActionJob` does not read or honour `delay_seconds`** — jobs dispatch immediately in sort order with no inter-action delay (`VibeSmartHomeDispatchService.php:46-57`, `SceneActionJob.php:55-124`).

---

## 6. Observability (`app/Telemetry/SmartHome/**`)

Eight PHP files. Spans, attributes, outcomes, and dependency rules:

### 6.1 Spans

| Span name | Owner class | When created | Key attributes |
| --- | --- | --- | --- |
| `smart_home.dispatch` | `SmartHomeDispatchTelemetry` | Wraps `VibeSmartHomeDispatchService::dispatch()` or `SceneDispatchService::dispatch()` at controller/command call sites | `ixora.dispatch.entry_point`, `ixora.dispatch.dispatched_actions`, `ixora.dispatch.skipped_actions` (`SmartHomeDispatchTelemetry.php:102`, `155-158`, `193-195`) |
| `smart_home.action` | `SmartHomeActionTelemetry` | Wraps provider resolution + `executeAction()` inside `SceneActionJob` | `ixora.action.provider`, `ixora.action.outcome` (`SmartHomeActionTelemetry.php:127`, `259-261`, `192`) |
| `smart_home.provider` | `SmartHomeProviderTelemetry` | Wraps HA adapter I/O segments (`listDevices`, `readStatus`, `executeAction`, `testConnection`) | `ixora.provider.device_domain` when domain known (`SmartHomeProviderTelemetry.php:78`, `137-139`) |

### 6.2 Telemetry enums

| Enum | Cases / purpose |
| --- | --- |
| `SmartHomeDispatchEntryPoint` | `manual`, `scene_manual`, `scheduled`, `future` (`SmartHomeDispatchEntryPoint.php:26-29`) |
| `SmartHomeActionOutcome` | `success`, `failure`, `unsupported`, `unknown` (`SmartHomeActionOutcome.php:22-25`) |
| `SmartHomeActionProvider` | `home_assistant`, `future` + `fromProviderSlug()` (`SmartHomeActionProvider.php:29-35`) |
| `SmartHomeActionType` | `turn_on`, `turn_off`, `toggle`, `other` + `fromActionTypeSlug()` (`SmartHomeActionType.php:32-40`) |
| `SmartHomeProviderDeviceDomain` | `light`, `switch`, `media_player`, `fan`, `other` + `fromDomainSlug()` (`SmartHomeProviderDeviceDomain.php:32-41`) |

### 6.3 Metrics (recorded by telemetry classes)

| Metric | Labels | Recorder |
| --- | --- | --- |
| `ixora.smart_home.dispatch.total` | `environment`, `service_name`, `entry_point`, `outcome` | `SmartHomeDispatchTelemetry` (`SmartHomeDispatchTelemetry.php:104`, `173-180`) |
| `ixora.smart_home.action.total` | `environment`, `service_name`, `outcome`, `provider`, `action_type` | `SmartHomeActionTelemetry` (`SmartHomeActionTelemetry.php:129`, `234-243`) |
| `ixora.smart_home.action.duration` | same as action.total | `SmartHomeActionTelemetry` (`SmartHomeActionTelemetry.php:131`, `232-243`) |

### 6.4 Dependency rules enforced by tests

| Test file | What it prevents |
| --- | --- |
| `SmartHomeDispatchTelemetryDependencyRuleTest.php` | OpenTelemetry SDK imports; concrete OTel/Noop imports; Models/SmartHome/Jobs/Controllers/Console/Push imports under `app/Telemetry/SmartHome`; metrics only on approved files; no logging facades (`SmartHomeDispatchTelemetryDependencyRuleTest.php:34-125`) |
| `SmartHomeActionTelemetryDependencyRuleTest.php` | Same class of forbidden imports for action telemetry; allowed imports limited to Telemetry Contracts + `Throwable`; metrics instrument restrictions (`SmartHomeActionTelemetryDependencyRuleTest.php:28-96`) |
| `SmartHomeProviderTelemetryDependencyRuleTest.php` | Provider telemetry must not import domain/HTTP/Models; no metrics on provider telemetry; no url/method/status attributes on provider span (`SmartHomeProviderTelemetryDependencyRuleTest.php:27-93`) |
| `SmartHomeBusinessMetricsDependencyRuleTest.php` | Metric names must be `ixora.smart_home.*`; bounded label sets; provider telemetry remains metric-free (`SmartHomeBusinessMetricsDependencyRuleTest.php:51-133`) |
| `SmartHomeBusinessLoggingTest.php` | SceneActionJob logs must not include `provider_device_id` or `error_message`; must include `outcome` on failures (`SmartHomeBusinessLoggingTest.php:30-67`) |

---

## 7. Business-layer provider coupling

**Question:** Do controllers, business jobs, scheduler, scenes, or vibes contain `if ($provider === …)` / `switch ($device->provider)` style conditionals?

**Answer: No** in controllers, dispatch services, scheduler command, or `SceneActionJob`.

Evidence:

- Grep for `if ($.*provider`, `match ($.*provider`, `ProviderType::` under `back_vibes/app` returns matches **only** in:
  - `ProviderAdapterResolver.php` — central resolver `match` (`ProviderAdapterResolver.php:33-38`)
  - `HomeAssistantAdapter.php` — returns HA slug constant (`HomeAssistantAdapter.php:240`)
  - `StoreProviderConnectionRequest.php` / `UpdateProviderConnectionRequest.php` — MVP allow-list validation (`StoreProviderConnectionRequest.php:24`)
- `ProviderConnectionController`, `VibeSmartHomeDispatchController`, `SceneDispatchController`, `DispatchDueSchedulesCommand`, `VibeSmartHomeDispatchService`, `SceneDispatchService`, `SceneActionJob`, and `ScheduleAutomationValidator` contain **no** provider slug conditionals (verified by grep and file reads above).

Provider-specific logic is isolated to `HomeAssistantAdapter` and registration in `ProviderAdapterResolver`.

---

## 8. v1.3.0 presence verification

| Artifact | Present? | Evidence |
| --- | --- | --- |
| `scenes` table | **Yes** | Migration `2026_08_30_192809_create_scenes_table.php` |
| `scene_actions` table | **Yes** | Migration `2026_08_30_192810_create_scene_actions_table.php` |
| `vibes.scene_id` FK | **Yes** | Migration `2026_09_02_230449_add_scene_id_to_vibes_table.php`; model `Vibe::scene()` (`Vibe.php:29-32`) |
| `vibe_device_actions` table dropped | **Yes** | Migration `2026_09_02_232728_drop_vibe_device_actions_table.php:23-29` |
| `VibeDeviceAction` model | **No** — removed | `Glob **/VibeDeviceAction*` returns 0 files |
| `SmartHomeActionJob` | **No** — removed | `Glob **/SmartHomeActionJob*` returns 0 files |
| Dispatch reads scene actions | **Yes** | `VibeSmartHomeDispatchService` loads `$vibe->scene()->actions()` (`VibeSmartHomeDispatchService.php:70-88`) |
| Sole action job | **`SceneActionJob`** | `SceneActionJob.php:24-37` docblock confirms replacement |

**No broken v1.3.0 dependencies detected** in schema or runtime code paths audited above.

Historical migrations referencing `vibe_device_actions` remain in the repo for migration history but forward migrate drops the table.

---

## 9. Test coverage

### 9.1 Test file inventory

**Feature — `tests/Feature/SmartHome/`**

| File | Area |
| --- | --- |
| `DeviceApiTest.php` | Device HTTP CRUD |
| `ProviderConnectionApiTest.php` | Provider connection CRUD |
| `ProviderConnectionModelTest.php` | ProviderConnection model / credentials |
| `ProviderConnectionSyncApiTest.php` | Sync endpoint + upsert/offline/unreachable behaviour |
| `VibeSmartHomeDispatchApiTest.php` | Vibe smart-home dispatch API |
| `VibeSceneLinkTest.php` | Vibe ↔ scene linkage |
| `SceneDomainTest.php` | Scene model/factory domain |
| `SceneLifecycleIntegrationTest.php` | Scene lifecycle integration |
| `SceneActionJobTest.php` | SceneActionJob execution, push, logging |

**Feature — Scene HTTP (outside SmartHome folder)**

| File | Area |
| --- | --- |
| `SceneApiTest.php` | Scene CRUD API |
| `SceneActionApiTest.php` | Scene action CRUD API |
| `SceneExecuteApiTest.php` | Scene manual execute / dispatch API |

**Feature — Scheduler integration**

| File | Area |
| --- | --- |
| `Scheduling/DispatchDueSchedulesCommandTest.php` | Scheduler + SceneActionJob enqueue, validator skip, failure isolation (`DispatchDueSchedulesCommandTest.php:635+`) |

**Feature — Telemetry**

| File | Area |
| --- | --- |
| `Feature/Telemetry/SmartHome/SmartHomeDispatchTelemetryTest.php` | Dispatch span + metrics |
| `Feature/Telemetry/SmartHome/SmartHomeDispatchBoundaryIntegrationTest.php` | End-to-end dispatch boundary |
| `Feature/Telemetry/SmartHome/SmartHomeActionTelemetryTest.php` | Action span + metrics |
| `Feature/Telemetry/SmartHome/SmartHomeActionBoundaryIntegrationTest.php` | Action boundary integration |
| `Feature/Telemetry/SmartHome/SmartHomeProviderTelemetryTest.php` | Provider span |
| `Feature/Telemetry/SmartHome/SmartHomeProviderBoundaryIntegrationTest.php` | Provider boundary integration |

**Unit — `tests/Unit/SmartHome/`**

| File | Area |
| --- | --- |
| `HomeAssistantAdapterTest.php` | All four adapter methods |
| `ProviderAdapterResolverTest.php` | Resolver routing + rejection |
| `ScheduleAutomationValidatorTest.php` | Schedule automation validation via scenes |

**Unit — Telemetry**

| File | Area |
| --- | --- |
| `Unit/Telemetry/SmartHome/SmartHomeActionTelemetryDependencyRuleTest.php` | Dependency rules |
| `Unit/Telemetry/SmartHome/SmartHomeDispatchTelemetryDependencyRuleTest.php` | Dependency rules |
| `Unit/Telemetry/SmartHome/SmartHomeProviderTelemetryDependencyRuleTest.php` | Dependency rules |
| `Unit/Telemetry/SmartHome/SmartHomeBusinessMetricsDependencyRuleTest.php` | Metrics rules |
| `Unit/Telemetry/SmartHome/SmartHomeBusinessLoggingTest.php` | Logging field rules |

**Push notification**

| File | Area |
| --- | --- |
| `Unit/PushNotifications/Notifications/SmartHomeSceneActionFailedNotificationTest.php` | Scene action failure notification |

### 9.2 Coverage gaps (not exercised by tests found)

| Area | Gap |
| --- | --- |
| `ProviderDeviceSyncService` | No dedicated unit test file; behaviour covered via `ProviderConnectionSyncApiTest.php` HTTP tests only |
| `ProviderAdapter::readStatus()` in production paths | Adapter unit tests exist; **no HTTP or sync integration** calls `readStatus()` |
| `ProviderAdapter::testConnection()` on connection create | Adapter unit tests exist; **`ProviderConnectionController::store()` does not call `testConnection()`** |
| `delay_seconds` at execution time | API persistence tested; **job ignores delay** — no test asserts delayed execution |
| Multi-provider | Only Home Assistant adapter/resolver paths tested |
| Capabilities | N/A — feature absent |
| Queue retry semantics | Tests document exceptions are swallowed; no test expects Laravel retry after provider failure |

---

## 10. Divergences spec × code

| # | Topic | Spec / doc says | Code does | Classification |
| --- | --- | --- | --- | --- |
| D1 | Action ownership model | MVP spec §2.7, §5: actions on `vibe_device_actions`; vibe owns action list (`spec.md:69-77`, domain diagram) | Actions live on `scene_actions`; vibes link via `vibes.scene_id`; `vibe_device_actions` dropped | **Post-MVP (v1.3.0)** — intentional unification; MVP spec not updated |
| D2 | Scenes | MVP spec §3 non-goals: "Scenes — HA scenes are a future action type" (`spec.md:98`) | First-class `scenes` + `scene_actions` tables and full HTTP/dispatch stack | **Post-MVP (v1.3.0)** |
| D3 | Dedup unique key | MVP plan: `UNIQUE (user_id, provider, provider_device_id)` (`plan.md:21`) | `UNIQUE (provider_connection_id, provider_device_id)` (`2026_06_14_000002_harden_devices_table.php:98-101`) | **Pre-existing to v1.4.0** (Phase 4A hardening) |
| D4 | Test connection on add | MVP spec §2.3: "On add: test connection is called automatically; connection is not saved if unreachable" (`spec.md:44-45`) | `ProviderConnectionController::store()` saves connection without calling adapter `testConnection()` (`ProviderConnectionController.php:34-50`) | **Pre-existing to v1.4.0** |
| D5 | Device removal status on sync | MVP spec §2.4: absent devices marked `offline` **or** `unknown` (`spec.md:51`) | Absent devices → `offline`; unreachable provider → all devices `unknown` (`ProviderDeviceSyncService.php:135-145`, `155-161`) | **Pre-existing to v1.4.0** — partial overlap; code picks `offline` for absence, not `unknown` |
| D6 | Scheduler automation spec | Scheduler+SH spec references `VibeDeviceAction` + `SmartHomeActionJob` (`scheduler-smart-home-automations/mvp/spec.md:38-53`) | Scheduler dispatches via `VibeSmartHomeDispatchService` → `SceneActionJob` (`DispatchDueSchedulesCommand.php:190-217`) | **Post-MVP (v1.3.0)** — downstream spec not updated |
| D7 | Capabilities | Not defined in MVP smart-home specs (grep `capabilities` in `ixora-infra/docs/specs/smart-home` → no matches) | No DB column, DTO field, adapter method, or validation | **N/A** — gap is absence in both spec and code, not a spec/code conflict |

---

## Verification (T01 acceptance)

### Git status

- `back_vibes`: no production/test/migration changes made during this audit (investigation only).
- `ixora-infra`: only this new file added under `docs/specs/smart-home/multi-provider/`.

### Spot-check — three random citations

| # | Claim | File:line check |
| --- | --- | --- |
| V1 | Unique index `uq_provider_connections_user_provider` on `(user_id, provider)` | **Confirmed** — `2026_06_14_000001_create_provider_connections_table.php:24` |
| V2 | `SceneActionJob` `$tries = 3` | **Confirmed** — `SceneActionJob.php:47` |
| V3 | No `capabilities` anywhere in `back_vibes` | **Confirmed** — workspace grep returns zero matches |

### Production code changes

**None.** Only `ixora-infra/docs/specs/smart-home/multi-provider/current-state.md` was written.
