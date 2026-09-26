# Adding a Smart Home provider

**Status:** Canonical operator/developer guide  
**Release anchor:** v1.4.0 multi-provider infrastructure ([ADR-032](../decisions/ADR-032-multi-provider-scope.md))  
**Repos:** `back_vibes` (required), `front_vibes` (no changes for new providers since T25)

This guide describes how to register a **production** Smart Home provider in `back_vibes`. It is grounded in the code as of v1.4.0 — do not copy stale ADR-032 §D.2 front-end entries without reading this document first.

---

## Overview

IXORA integrates with **provider platforms** (Home Assistant, future aggregators), not OEM clouds directly ([ADR-012](../decisions/ADR-012-smart-home-provider-strategy.md)). Each platform is a slug registered in config and implemented as one adapter class that satisfies `App\SmartHome\Contracts\ProviderAdapter`.

After v1.4.0:

- Business layers (Scenes, Vibes, Scheduler, `SceneActionJob`) resolve adapters through `ProviderAdapterRegistry` — **no per-provider branches** in controllers or jobs.
- The mobile app loads provider labels and connection form fields from `GET /api/provider-types` — **no `front_vibes` changes** when a new slug is registered on the API (T25).
- Device capabilities and normalised device types are **adapter responsibilities** ([ADR-033](../decisions/ADR-033-device-capabilities.md)); sync persists them automatically (T18).

---

## Step-by-step (`back_vibes`)

### 1. Create the adapter

**File:** `app/SmartHome/Adapters/{Name}Adapter.php`  
**Contract:** `app/SmartHome/Contracts/ProviderAdapter.php`

Implement all four methods with the error policy documented on the interface:

| Method | Throws? | On failure |
| --- | --- | --- |
| `listDevices()` | Yes — `ProviderConnectionException` | Provider unreachable or non-2xx |
| `readStatus()` | Never | Returns `DeviceStatusResult` with `DeviceStatus::Unknown` |
| `executeAction()` | Only for unmappable actions (`UnsupportedSmartHomeActionException`) | Transport/HTTP failures → failed `ActionResult` |
| `testConnection()` | Never | Returns `ConnectionHealth` with `reachable: false` |

Reference implementations:

- **Production:** `app/SmartHome/Adapters/HomeAssistantAdapter.php`
- **Test-only:** `app/SmartHome/Adapters/FakeProviderAdapter.php` (T10 — never in committed production config)

Use `ProviderRequestTimeout::forSlug($connection->provider)` (or the connection's slug constant) when making HTTP calls so per-provider timeouts from config apply (T23).

#### 1a. Map native identifiers → `DeviceType`

Inside the adapter, map provider-native taxonomy (e.g. Home Assistant entity domain) to `App\SmartHome\DeviceType` enum values (`lighting`, `switchable`, `media`, `ventilation`, `other`).

Example from `HomeAssistantAdapter::mapDeviceType()`:

```php
private function mapDeviceType(string $domain): DeviceType
{
    return match ($domain) {
        'light' => DeviceType::Lighting,
        'switch' => DeviceType::Switchable,
        'media_player' => DeviceType::Media,
        'fan' => DeviceType::Ventilation,
        default => DeviceType::Other,
    };
}
```

Pass `mapDeviceType(...)->value` as the `type` field on each `ProviderDevice` DTO. Without this mapping, devices still sync but appear as `other` with generic mobile icons.

#### 1b. Derive capabilities on each `ProviderDevice`

Each `listDevices()` entry must populate `ProviderDevice::$capabilities` when derivable ([ADR-033](../decisions/ADR-033-device-capabilities.md)). Keys are Ixora capability strings; values are constraint objects (empty `{}` for boolean capabilities):

| Capability key | Typical `ActionType` |
| --- | --- |
| `can_turn_on` | `turn_on` |
| `can_turn_off` | `turn_off` |
| `can_toggle` | `toggle` |
| `can_set_brightness` | `set_brightness` |

Example from `HomeAssistantAdapter::deriveCapabilities()` — boolean on/off/toggle per domain, plus brightness when HA `supported_features` confirms dimming.

If `capabilities` is `null`, sync still succeeds and the capability gate **fail-opens** (actions dispatch as in pre-v1.4.0). For full UX (capability-filtered action editor on mobile, T26) and meaningful gate behaviour (T20), derive capabilities in the adapter.

`ProviderDeviceSyncService` upserts `capabilities` automatically from the DTO — no sync-service changes are required (`app/SmartHome/Services/ProviderDeviceSyncService.php`, line 114):

```php
'capabilities' => $dto->capabilities,
```

### 2. Register in config

**File:** `config/smart_home.php`

Three sections must be updated for each **production** slug:

#### `adapters.{slug}`

Maps slug → adapter FQCN. Resolved by `ProviderAdapterRegistry::forSlug()` — no edits to `ProviderAdapterResolver` required.

```php
'adapters' => [
    'home_assistant' => HomeAssistantAdapter::class,
    'my_platform'    => MyPlatformAdapter::class,
],
```

#### `provider_descriptors.{slug}`

Static metadata for `GET /api/provider-types` (T09). Every registered adapter slug **must** have a matching descriptor or `ProviderDescriptorRegistry` throws at boot when the slug is resolved.

Shape (field schemas only — never credential values):

```php
'provider_descriptors' => [
    'my_platform' => [
        'label' => 'My Platform',
        'config' => [
            'base_url' => [
                'type' => 'string',
                'format' => 'url:https',
                'required' => true,
            ],
        ],
        'credentials' => [
            'access_token' => [
                'type' => 'string',
                'required' => true,
            ],
        ],
    ],
],
```

`StoreProviderConnectionRequest` / `UpdateProviderConnectionRequest` validate `config` and `credentials` keys against this descriptor dynamically (T14) — no per-provider FormRequest edits.

#### `providers.{slug}`

Runtime tuning (non-secret). Minimum for HTTP providers:

```php
'providers' => [
    'my_platform' => [
        'timeout' => env('SMART_HOME_MY_PLATFORM_TIMEOUT', 10),
    ],
],
```

`App\SmartHome\ProviderRequestTimeout::forSlug()` reads `config('smart_home.providers.{slug}.timeout')` and falls back to the Home Assistant timeout when the slug has no entry.

Optional flags (see HA block): `allow_http` and other provider-specific policy keys as needed.

### 3. Add enum case when slug is not already reserved

**File:** `app/SmartHome/ProviderType.php`

If the slug is not already a reserved case (`tuya`, `philips_hue`, `alexa`, `google_home`, `matter`, …), add:

```php
case MyPlatform = 'my_platform';
```

Reserved slugs already exist in the enum for documentation and telemetry alignment — wire the adapter without adding a duplicate case.

The test-only `fake` slug is **not** in `ProviderType` and must never appear in production config.

### 4. Container wiring (usually no edit)

**File:** `app/Providers/SmartHomeServiceProvider.php`

The service provider registers every class listed in `config('smart_home.adapters')` as a singleton. Adding the config entry is sufficient — do not hard-code slugs in the provider.

### 5. Telemetry enums (recommended, not required for functionality)

The Telemetry layer deliberately does **not** import `App\SmartHome\ProviderType` or `DeviceType` (dependency rule enforced in `tests/Unit/Telemetry/`). For full dashboard granularity (T24), mirror new slugs/types in:

| File | Method | Fallback when unmapped |
| --- | --- | --- |
| `app/Telemetry/SmartHome/SmartHomeActionProvider.php` | `fromProviderSlug()` | `Future` |
| `app/Telemetry/SmartHome/SmartHomeProviderDeviceType.php` | `fromTypeSlug()` | `Other` |

A registered provider without a dedicated telemetry case still works — spans and metrics use the fallback values.

### 6. Tests

#### Contract suite (required for every adapter)

**File:** `tests/Unit/SmartHome/ProviderAdapterContractTest.php`

This file runs the **same** contract assertions against every adapter via a Pest dataset (`contractAdapterFixtures()`). It verifies:

- Interface method signatures
- `listDevices` unreachable / bad-status → `ProviderConnectionException`
- `readStatus` never throws; returns `Unknown` on failure
- `executeAction` never throws on transport/HTTP failure
- `UnsupportedSmartHomeActionException` for unmappable actions
- `testConnection` never throws on failure
- `listDevices` returns `ProviderDevice` entries with ADR-033 capability maps when derivable

**To register a new adapter in the contract suite:** add an entry to `contractAdapterFixtures()` with slug, factory callable, and connection factory callable (see existing `fake` and `home_assistant` entries).

#### Adapter-specific tests

**File:** `tests/Unit/SmartHome/{Name}AdapterTest.php` (recommended)

Add focused tests for provider-specific mapping (domain → type, attribute → capabilities, action → API call). The fake provider does not have a separate file — it is covered entirely by the contract suite plus feature tests that override config at runtime.

#### Registry tests

**File:** `tests/Unit/SmartHome/ProviderAdapterRegistryTest.php`

Extend when adding slugs if registry resolution edge cases need coverage.

#### Feature tests

**Directory:** `tests/Feature/SmartHome/`

Add or extend feature tests when the new provider participates in connection CRUD, sync, or scene execution flows. For the fake provider pattern, tests override config only:

```php
config(['smart_home.adapters.fake' => FakeProviderAdapter::class]);
$this->app->singleton(FakeProviderAdapter::class, fn () => new FakeProviderAdapter);
```

#### API descriptor test

**File:** `tests/Feature/SmartHome/ProviderTypeApiTest.php`

When adding a production slug, extend assertions so `GET /api/provider-types` returns the new descriptor.

---

## No `front_vibes` changes (since T25)

Adding a provider slug on the API is sufficient for the mobile client:

| Concern | Implementation | Why no provider-specific edit |
| --- | --- | --- |
| Provider picker + form fields | `src/views/ProviderConnectionFormPage.vue` | Renders `config` / `credentials` from selected `ProviderType` schema |
| Provider types fetch | `src/services/provider-connection.service.ts` → `getProviderTypes()` | Calls `GET /api/provider-types` |
| Provider labels in device list | `src/utils/device-status.ts` → `providerLabel()` | Looks up slug in API-provided list; falls back to raw slug |

ADR-032 §D.2 originally listed these three paths as **expected** diffs. T25 moved them to **intocável** — see [ADR-032](../decisions/ADR-032-multi-provider-scope.md) post-T25 note.

---

## Extensibility checklist (ADR-032 §D)

Paths are relative to workspace repo roots. T29 compares provider-add diffs against these lists.

### D.1 — Intocável ao adicionar um provider

No file below may change when registering a **second** provider slug (including the v1.4.0 fake provider in tests). T29 treats any diff hunk in these paths as a regression unless clearly unrelated.

**`back_vibes` — HTTP & routing**

- `routes/api.php`

**`back_vibes` — Controllers (business layer)**

- `app/Http/Controllers/Api/DeviceController.php`
- `app/Http/Controllers/Api/SceneController.php`
- `app/Http/Controllers/Api/SceneActionController.php`
- `app/Http/Controllers/Api/SceneDispatchController.php`
- `app/Http/Controllers/Api/VibeSmartHomeDispatchController.php`

**`back_vibes` — Jobs**

- `app/Jobs/SmartHome/SceneActionJob.php`

**`back_vibes` — Smart Home business services (non-adapter)**

- `app/SmartHome/Services/ProviderDeviceSyncService.php`
- `app/SmartHome/Services/VibeSmartHomeDispatchService.php`
- `app/SmartHome/Services/SceneDispatchService.php`
- `app/SmartHome/Validation/ScheduleAutomationValidator.php`

**`back_vibes` — Scheduler (must not gain provider branches)**

- `app/Console/Commands/DispatchDueSchedulesCommand.php`
- `app/Console/Commands/DispatchSchedulesLoopCommand.php`
- `app/Services/Scheduling/` *(entire directory tree)*

**`back_vibes` — Domain models (Scene / Vibe automation path)**

- `app/Models/Scene.php`
- `app/Models/SceneAction.php`
- `app/Models/Vibe.php`
- `app/Models/Device.php`

**`back_vibes` — Migrations (Scene / Vibe automation schema — frozen for provider add)**

- `database/migrations/2026_08_30_192809_create_scenes_table.php`
- `database/migrations/2026_08_30_192810_create_scene_actions_table.php`
- `database/migrations/2026_09_02_230449_add_scene_id_to_vibes_table.php`
- `database/migrations/2026_09_02_232728_drop_vibe_device_actions_table.php`

**`front_vibes` — Dispatch & scene action clients (provider-agnostic API consumers)**

- `src/services/smart-home-dispatch.service.ts`
- `src/services/scene-dispatch.service.ts`
- `src/services/scene-device-action.service.ts`
- `src/services/device.service.ts`

**`front_vibes` — Scene / Vibe UX (no provider slug in business flow)**

- `src/views/ScenesPage.vue`
- `src/views/SceneDeviceActionsPage.vue`
- `src/views/SceneDeviceActionEditModal.vue`
- `src/composables/useScenes.ts`
- `src/composables/useSceneDeviceActions.ts`

**`front_vibes` — Connection UX & labels (schema-driven since T25 — moved from D.2)**

- `src/services/provider-connection.service.ts`
- `src/utils/device-status.ts`
- `src/views/ProviderConnectionFormPage.vue`

**`ixora-admin`**

- *(entire repo — must remain untouched for provider add)*

### D.2 — Esperado ao adicionar um provider

These paths **must** contain the provider-add diff (or new files under listed directories).

**`back_vibes` — Adapter & registry (decision B)**

- `app/SmartHome/Adapters/` — **new file** `{ProviderName}Adapter.php` (required)
- `app/SmartHome/ProviderAdapterRegistry.php` — **created once in T08**; thereafter **immutable** except bugfixes that do not add slug-specific logic
- `app/SmartHome/ProviderAdapterResolver.php` — **refactored once in T08** to delegate; no further provider-specific edits
- `app/Providers/SmartHomeServiceProvider.php` — wiring only; no per-provider hard-coding after T08 (config-driven)
- `config/smart_home.php` — **`adapters.{slug}`** + **`provider_descriptors.{slug}`** + **`providers.{slug}`** (timeout and policy flags) (required)

**`back_vibes` — Adapter mapping (ADR-033 / T15–T16 — not in original ADR-032 D.2)**

- Inside `app/SmartHome/Adapters/{ProviderName}Adapter.php`:
  - Native taxonomy → `App\SmartHome\DeviceType` mapping (e.g. `mapDeviceType()`)
  - Native attributes → ADR-033 `capabilities` map (e.g. `deriveCapabilities()`)

**`back_vibes` — Slug catalog**

- `app/SmartHome/ProviderType.php` — new enum case when slug not already reserved

**`back_vibes` — Connection API allow-list (descriptor-driven, not HA-hardcoded)**

- `app/Http/Requests/StoreProviderConnectionRequest.php` — **only** if validation switches from `ProviderType::mvpAllowed()` to `ProviderAdapterRegistry::registeredSlugs()` *(one-time T12 change; no per-provider rules)*
- `app/Http/Requests/UpdateProviderConnectionRequest.php` — same one-time change as store

**`back_vibes` — Telemetry (T24 — recommended, not in original ADR-032 D.2)**

- `app/Telemetry/SmartHome/SmartHomeActionProvider.php` — add case when slug is not already reserved
- `app/Telemetry/SmartHome/SmartHomeProviderDeviceType.php` — add case only if introducing a new normalised type slug beyond existing vocabulary

**`back_vibes` — Tests**

- `tests/Unit/SmartHome/{ProviderName}AdapterTest.php` — **new file** (recommended; fake uses contract suite only)
- `tests/Unit/SmartHome/ProviderAdapterContractTest.php` — add adapter to `contractAdapterFixtures()` dataset
- `tests/Unit/SmartHome/ProviderAdapterRegistryTest.php` — **created in T08/T10**
- `tests/Feature/SmartHome/` — new or extended feature tests for fake/second provider as required by T10/T29

**`back_vibes` — v1.4.0 fake provider (test-only)**

- `app/SmartHome/Adapters/FakeProviderAdapter.php` — **new**; registered only in `testing`/`local` config override
- `config/smart_home.php` — `adapters.fake` **absent** from committed production config (tests override at runtime)

**Removed from D.2 (absorbed by D.1 after T25)**

- ~~`src/services/provider-connection.service.ts`~~
- ~~`src/utils/device-status.ts`~~
- ~~`src/views/ProviderConnectionFormPage.vue`~~
- ~~`src/services/__tests__/provider-connection.service.test.ts`~~ (no provider-specific test required on add)
- ~~`src/utils/__tests__/device-status.test.ts`~~ (same)

### D.3 — Schema migrations when adding a provider

**Default: no migration** if credentials fit the existing JSON shape on `provider_connections`:

```json
{ "encrypted_credentials": { "access_token": "<string>" }, "config": { "base_url": "<https-url>" } }
```

**Migration required only if** the provider needs a genuinely different credential or config schema that cannot live in existing JSON columns. Scope migrations to `provider_connections` (or an FK extension table) — never `devices`, `scenes`, `scene_actions`, or `vibes`.

---

## Verification: walk through `FakeProviderAdapter` (T10)

Use the test-only fake adapter as a concrete checklist. Every production provider follows the same steps except where noted.

| Step | Fake provider (T10) | Production provider |
| --- | --- | --- |
| Adapter file | ✅ `app/SmartHome/Adapters/FakeProviderAdapter.php` implements `ProviderAdapter` | ✅ Same pattern |
| `DeviceType` on DTOs | ✅ `DeviceType::Lighting`, `DeviceType::Switchable` in `defaultDevices()` | ✅ Required in adapter |
| `capabilities` on DTOs | ✅ `can_turn_on`, `can_turn_off`, `can_toggle`, `can_set_brightness` with range | ✅ Required for full UX/gate |
| Config `adapters.fake` | ❌ **Not** in committed `config/smart_home.php` | ✅ Must add `adapters.{slug}` |
| Config `provider_descriptors.fake` | ❌ Not in production config (fake never exposed via API in prod) | ✅ Required — boot fails without descriptor for registered slug |
| Config `providers.fake.timeout` | ❌ Not needed (no HTTP); uses HA fallback if called | ✅ Set explicit timeout for HTTP adapters |
| `ProviderType` case | ❌ Not added (`fake` is test-only) | ✅ Add case if slug not reserved |
| Telemetry enums | ❌ Not added (falls back to `Future` / `Other`) | ⚠️ Recommended |
| Contract suite | ✅ Entry in `contractAdapterFixtures()` | ✅ Add dataset entry |
| Dedicated unit test file | ❌ Uses contract suite only | ✅ Recommended `{Name}AdapterTest.php` |
| `front_vibes` changes | ✅ None | ✅ None |

Run contract tests after changes:

```bash
cd back_vibes && php artisan test --compact tests/Unit/SmartHome/ProviderAdapterContractTest.php
```

---

## Related documentation

| Document | Relationship |
| --- | --- |
| [ADR-032](../decisions/ADR-032-multi-provider-scope.md) | Multi-provider scope, registry format, D.1/D.2 origin |
| [ADR-033](../decisions/ADR-033-device-capabilities.md) | Capabilities vocabulary and fail-open gate |
| [ADR-012](../decisions/ADR-012-smart-home-provider-strategy.md) | Platform-only integrations policy |
| [ADR-013](../decisions/ADR-013-home-assistant-first-provider.md) | First production adapter reference |
| [`specs/smart-home/multi-provider/`](../specs/smart-home/multi-provider/) | v1.4.0 audit reports (T01–T03) |
