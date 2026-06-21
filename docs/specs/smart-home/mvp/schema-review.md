# Smart Home Foundation MVP — schema and domain review

**Status:** Phase 2 complete — review only; no migrations or runtime code changed  
**Date:** 2026-06-14  
**Feature ID:** `smart-home/mvp`  
**Branch (reference):** `feature/smart-home-schema-review`

> This document is the **gate** for Phase 3 (`provider_connections`) and Phase 4 (device CRUD + schema hardening). No migration or model code should be written until this review is accepted.

**Inputs reviewed:**

| Source | Path |
| --- | --- |
| Feature spec | [`spec.md`](spec.md) |
| Implementation plan | [`plan.md`](plan.md) |
| ADR-012 | [`ADR-012-smart-home-provider-strategy.md`](../../../decisions/ADR-012-smart-home-provider-strategy.md) |
| ADR-013 | [`ADR-013-home-assistant-first-provider.md`](../../../decisions/ADR-013-home-assistant-first-provider.md) |
| ADR-014 | [`ADR-014-device-abstraction-and-deduplication.md`](../../../decisions/ADR-014-device-abstraction-and-deduplication.md) |
| ADR-015 | [`ADR-015-vibe-device-action-architecture.md`](../../../decisions/ADR-015-vibe-device-action-architecture.md) |
| ADR-016 | [`ADR-016-smart-home-async-execution.md`](../../../decisions/ADR-016-smart-home-async-execution.md) |

**Backend artifacts inspected:**

| Artifact | Path |
| --- | --- |
| `devices` migration (stub) | `back_vibes/database/migrations/2026_05_01_000005_create_devices_table.php` |
| `vibe_device_actions` migration (stub) | `back_vibes/database/migrations/2026_05_01_000006_create_vibe_device_actions_table.php` |
| `user_settings` migration (related FK) | `back_vibes/database/migrations/2026_05_01_000009_create_user_settings_table.php` |
| `Device` model | `back_vibes/app/Models/Device.php` |
| `VibeDeviceAction` model | `back_vibes/app/Models/VibeDeviceAction.php` |
| `Vibe` model | `back_vibes/app/Models/Vibe.php` |
| `User` model | `back_vibes/app/Models/User.php` |
| `UserSettings` model | `back_vibes/app/Models/UserSettings.php` |
| `DevicePolicy` | `back_vibes/app/Policies/DevicePolicy.php` |

---

## 1. Current schema inventory

### 1.1 `devices` table

**Migration:** `2026_05_01_000005_create_devices_table.php`  
**Runtime status:** Table exists if migrations have run; **no API, no sync, no seed data** in codebase.

| Column | Type | Nullable / default | Notes |
| --- | --- | --- | --- |
| `id` | `bigint` PK | NOT NULL, auto-increment | |
| `user_id` | `bigint` FK → `users.id` | NOT NULL | `cascadeOnDelete` on parent delete |
| `name` | `string` | NOT NULL | No length constraint in migration |
| `type` | `string` | NOT NULL | DB comment: `light, speaker, coffee_maker, tv, etc.` |
| `provider` | `string` | NOT NULL | DB comment: `Home Assistant, Tuya, Alexa, etc.` — **free-form string today; spec requires slug** (`home_assistant`) |
| `external_id` | `string` | NOT NULL | Provider-native identifier; **to be renamed** `provider_device_id` |
| `metadata` | `json` | NULLABLE | Provider-specific attributes |
| `created_at` | `timestamp` | NOT NULL, `useCurrent()` | Present |
| `updated_at` | — | **MISSING** | Model sets `const UPDATED_AT = null` |

**Indexes:**

| Name | Columns | Unique |
| --- | --- | --- |
| *(implicit)* | `user_id` | No — from `foreignId()->index()` |
| *(unnamed composite)* | `(user_id, provider, external_id)` | **No** — non-unique index only |

**Foreign keys:**

| Column | References | On delete |
| --- | --- | --- |
| `user_id` | `users.id` | CASCADE |

**Timestamps:** `created_at` only. No `updated_at`.

**Downstream references:**

| Table | Column | On delete |
| --- | --- | --- |
| `vibe_device_actions` | `device_id` | CASCADE |
| `user_settings` | `preferred_device_id` | **NULL ON DELETE** |

Deleting a device nullifies `user_settings.preferred_device_id` but does not block device deletion.

---

### 1.2 `vibe_device_actions` table

**Migration:** `2026_05_01_000006_create_vibe_device_actions_table.php`  
**Runtime status:** Table exists if migrations have run; **no API, no runtime usage**.

**Migration note:** Uses explicit `DROP TABLE IF EXISTS ... CASCADE` on PostgreSQL before create — defensive against partial prior state.

| Column | Type | Nullable / default | Notes |
| --- | --- | --- | --- |
| `id` | `bigint` PK | NOT NULL, auto-increment | |
| `vibe_id` | `unsignedBigInteger` FK | NOT NULL | Named FK `fk_vda_vibe` |
| `device_id` | `unsignedBigInteger` FK | NOT NULL | Named FK `fk_vda_device` |
| `action_type` | `string` | NOT NULL | Unconstrained; no DB enum |
| `parameters` | `json` | NULLABLE | Generic action parameters |
| `delay_seconds` | `unsignedSmallInteger` | NOT NULL, default `0` | |
| `created_at` | `timestamp` | NOT NULL, `useCurrent()` | Present |
| `updated_at` | — | **MISSING** | Model sets `const UPDATED_AT = null` |
| `sort_order` | — | **MISSING** | Required per ADR-015 |

**Indexes:**

| Name | Columns | Unique |
| --- | --- | --- |
| `idx_vda_vibe` | `vibe_id` | No |
| `idx_vda_device` | `device_id` | No |

**Foreign keys:**

| Column | References | On delete | Constraint name |
| --- | --- | --- | --- |
| `vibe_id` | `vibes.id` | CASCADE | `fk_vda_vibe` |
| `device_id` | `devices.id` | CASCADE | `fk_vda_device` |

**Timestamps:** `created_at` only. No `updated_at`.

**Unique constraints:** None.

---

### 1.3 Related table: `user_settings` (not Smart Home MVP scope, but FK-relevant)

| Column | FK | On delete |
| --- | --- | --- |
| `preferred_device_id` | `devices.id` | **NULL ON DELETE** |

If Smart Home device deletion ships, UX should handle `preferred_device_id` becoming null. No schema change required for MVP.

---

### 1.4 `provider_connections` table

**Does not exist.** New table required in Phase 3.

---

## 2. Current Eloquent model inventory

### 2.1 `Device`

| Property | Current state |
| --- | --- |
| **Exists** | Yes |
| **Path** | `back_vibes/app/Models/Device.php` |
| **Namespace** | `App\Models` |
| **Final class** | Yes (`final class Device`) |
| **HasFactory** | Yes — **no `DeviceFactory` exists** |
| **Timestamps** | `const UPDATED_AT = null` — only `created_at` managed |

**Fillable (attribute):**

```php
['user_id', 'name', 'type', 'provider', 'external_id', 'metadata']
```

**Casts:**

| Attribute | Cast |
| --- | --- |
| `metadata` | `array` |

**Relationships:**

| Method | Type | Target |
| --- | --- | --- |
| `user()` | `BelongsTo` | `User` |
| `vibeActions()` | `HasMany` | `VibeDeviceAction` |

**Naming note:** Relationship is `vibeActions()`, not `vibeDeviceActions()`. Vibe model uses `deviceActions()` — asymmetric naming; align in Phase 4 if desired (non-breaking alias acceptable).

**Constants / enums:** None. No `status` constants. No `provider` slug enum.

**Missing vs MVP target:**

- `external_id` in fillable → rename to `provider_device_id`
- `status`, `last_seen_at` not in fillable or casts
- `provider_connection_id` not present
- `UPDATED_AT = null` must be removed when `updated_at` column added
- No `providerConnection()` relationship

---

### 2.2 `VibeDeviceAction`

| Property | Current state |
| --- | --- |
| **Exists** | Yes |
| **Path** | `back_vibes/app/Models/VibeDeviceAction.php` |
| **Namespace** | `App\Models` |
| **Final class** | Yes |
| **HasFactory** | Yes — **no `VibeDeviceActionFactory` exists** |
| **Timestamps** | `const UPDATED_AT = null` |

**Fillable:**

```php
['vibe_id', 'device_id', 'action_type', 'parameters', 'delay_seconds']
```

**Casts:**

| Attribute | Cast |
| --- | --- |
| `parameters` | `array` |

**Relationships:**

| Method | Type | Target |
| --- | --- | --- |
| `vibe()` | `BelongsTo` | `Vibe` |
| `device()` | `BelongsTo` | `Device` |

**Constants / enums:** None. No `action_type` validation constants.

**Missing vs MVP target:**

- `sort_order` not in fillable
- `UPDATED_AT = null` must be removed
- No default ordering scope (`orderBy('sort_order')`)

---

### 2.3 `User`

| Property | Current state |
| --- | --- |
| **Path** | `back_vibes/app/Models/User.php` |

**Smart Home relationships:**

| Method | Exists | Notes |
| --- | --- | --- |
| `devices()` | **Yes** | `HasMany(Device::class)` |
| `providerConnections()` | **No** | **Add in Phase 3** |

---

### 2.4 `Vibe`

| Property | Current state |
| --- | --- |
| **Path** | `back_vibes/app/Models/Vibe.php` |

**Smart Home relationships:**

| Method | Exists | Notes |
| --- | --- | --- |
| `deviceActions()` | **Yes** | `HasMany(VibeDeviceAction::class)` — no default `sort_order` ordering |

---

### 2.5 `ProviderConnection`

**Does not exist.** New model required in Phase 3.

---

### 2.6 Policies, factories, API layer

| Artifact | Exists | Notes |
| --- | --- | --- |
| `DevicePolicy` | **Yes** | Owner scoping on view/update/delete; `viewAny`/`create` return true (list scoped in controller) — matches `SchedulePolicy` pattern |
| `ProviderConnectionPolicy` | **No** | Create in Phase 4 |
| `VibeDeviceActionPolicy` | **No** | Create in Phase 7 (or nested under vibe authorization) |
| `DeviceFactory` | **No** | Create in Phase 4 |
| `VibeDeviceActionFactory` | **No** | Create in Phase 7 |
| `ProviderConnectionFactory` | **No** | Create in Phase 3 |
| Device API routes | **No** | `routes/api.php` has no device endpoints |
| Device controllers | **No** | |
| Device Form Requests | **No** | |
| Device API Resources | **No** | |
| Smart Home tests | **No** | No Pest tests reference `Device` or `VibeDeviceAction` |

**Policy discovery:** Laravel auto-discovers policies by convention (`Device` → `DevicePolicy`). No explicit registration found — same pattern as Scheduler.

---

## 3. Target schema delta

### 3.1 `devices` — required changes

| Change | Detail |
| --- | --- |
| **Add `provider_connection_id`** | `bigint` FK → `provider_connections.id`, `cascadeOnDelete` — **see §4 key decision** |
| **Rename `external_id` → `provider_device_id`** | `string`, NOT NULL — HA `entity_id` maps here ([ADR-014](../../../decisions/ADR-014-device-abstraction-and-deduplication.md)) |
| **Add `status`** | `string(32)`, NOT NULL, default `'unknown'` — values: `online`, `offline`, `unknown` |
| **Add `last_seen_at`** | `timestamp`, NULLABLE — last successful provider status fetch |
| **Add `updated_at`** | `timestamp`, NULLABLE → backfill → NOT NULL (or Laravel default nullable) |
| **Keep `provider`** | Denormalized provider slug (`home_assistant`) for list/filter without join — populated at sync from connection |
| **Drop non-unique index** | `(user_id, provider, external_id)` — replaced after rename |
| **Add unique constraint** | **`UNIQUE (provider_connection_id, provider_device_id)`** — see §4 |
| **Optional list index** | `(user_id, provider)` — non-unique, for Devices tab filter by provider type |

**Index strategy:**

| Index | Unique | Justification |
| --- | --- | --- |
| `(provider_connection_id, provider_device_id)` | **Yes** | Enforces dedupe per connection; supersedes non-unique stub index |
| `(user_id)` | No | Already exists via FK; supports `GET /api/devices` owner scope |
| `(user_id, provider)` | No | Optional — filter devices by provider slug in list API |

**Do not keep** the old non-unique `(user_id, provider, external_id)` index once the unique constraint is in place — redundant for lookups and weaker than unique enforcement.

**Provider slug normalization:** Migration should not change existing `provider` string values automatically. Application layer enforces slug `home_assistant` on write. If stub rows exist with display names (`Home Assistant`), backfill to slug in hardening migration.

---

### 3.2 `vibe_device_actions` — required changes

| Change | Detail |
| --- | --- |
| **Add `sort_order`** | `unsignedInteger`, NOT NULL, default `0` — execution order within vibe ([ADR-015](../../../decisions/ADR-015-vibe-device-action-architecture.md)) |
| **Add `updated_at`** | `timestamp`, NULLABLE → backfill from `created_at` |
| **Keep `action_type`** | `string` — app-layer validation only; MVP values: `turn_on`, `turn_off`, `toggle` |
| **Keep `parameters`** | `json`, NULLABLE |
| **Keep `delay_seconds`** | `unsignedSmallInteger`, default `0` |

**Index recommendations:**

| Index | Unique | Recommend | Justification |
| --- | --- | --- | --- |
| `(vibe_id)` | No | **Keep** (`idx_vda_vibe`) | List all actions for a vibe |
| `(device_id)` | No | **Keep** (`idx_vda_device`) | Find actions referencing a device (delete guard, diagnostics) |
| `(vibe_id, sort_order)` | No | **Add (optional)** | Ordered fetch without sort in query plan — low cost |
| `(vibe_id, device_id)` | No | **Do not add** | Spec allows multiple actions on same device (e.g. `turn_on` then `turn_off` with different delays) |
| `(vibe_id, sort_order)` unique | No | **Do not add** | App assigns `sort_order`; duplicates are a validation concern, not a DB constraint |

**No unique constraint** on `vibe_device_actions` in MVP.

---

### 3.3 `provider_connections` — new table (precise schema)

| Column | Type | Nullable | Default | Semantics |
| --- | --- | --- | --- | --- |
| `id` | `bigint` PK | NOT NULL | auto | |
| `user_id` | `bigint` FK → `users.id` | NOT NULL | — | Owner; `cascadeOnDelete` |
| `name` | `string(255)` | NOT NULL | — | User-visible label (e.g. "Home HA") |
| `provider` | `string(32)` | NOT NULL | — | Provider slug: `home_assistant` ([`ProviderType`](../../../decisions/ADR-012-smart-home-provider-strategy.md)) |
| `config` | `json` | NOT NULL | — | Non-sensitive config; MVP: `{ "base_url": "https://..." }` |
| `encrypted_credentials` | `text` | NOT NULL | — | `Crypt::encryptString(json_encode(['access_token' => '...']))` — never exposed in API ([ADR-013](../../../decisions/ADR-013-home-assistant-first-provider.md)) |
| `status` | `string(32)` | NOT NULL | `'unknown'` | `connected`, `unreachable`, `unknown` |
| `last_tested_at` | `timestamp` | NULLABLE | — | Last successful `testConnection()` |
| `created_at` | `timestamp` | NOT NULL | `useCurrent()` | |
| `updated_at` | `timestamp` | NOT NULL | — | Laravel timestamps |

**Indexes and constraints:**

| Name | Columns | Unique | Recommendation |
| --- | --- | --- | --- |
| `uq_provider_connections_user_provider` | `(user_id, provider)` | **Yes** | **Enforce at DB level for MVP** |

**Justification for DB unique `(user_id, provider)`:**

- MVP explicitly allows **one connection per user per provider type** ([ADR-013](../../../decisions/ADR-013-home-assistant-first-provider.md), [`spec.md`](spec.md) § 2.3).
- DB constraint fails fast on duplicate `POST /api/provider-connections` — no race between app check and insert.
- Future multiple HA instances per user requires a **new migration** to drop `uq_provider_connections_user_provider` and possibly add a disambiguator (`label`, `instance_key`, or allow duplicate `provider` with distinct `name`). Document as known future breaking change.

**App-layer-only alternative rejected for MVP:** Duplicate connections are a data integrity issue, not just UX — DB unique is cheaper to enforce correctly.

**No FK from `provider_connections` to `devices` reverse direction needed** — `devices.provider_connection_id` is sufficient.

---

## 4. Domain model delta

### 4.1 Key decision: `provider_connection_id` on `devices`

**Recommendation: YES — add `provider_connection_id` FK to `devices` in MVP.**

| Option | Summary |
| --- | --- |
| **A) `user_id` + `provider` only** | Simpler columns; dedupe via `(user_id, provider, provider_device_id)` per ADR-014 |
| **B) `user_id` + `provider` + `provider_connection_id` FK** | **Recommended** — connection-scoped devices with cascade delete |

**Why B for MVP:**

| Factor | With `provider_connection_id` | Without |
| --- | --- | --- |
| **Delete connection → remove devices** | `cascadeOnDelete` on FK — automatic, correct | Requires explicit cleanup job/query in controller |
| **Sync scope** | Sync connection X → upsert/mark offline only devices for X | Must filter by `user_id` + `provider` — ambiguous if multiple connections same provider (future) |
| **Future multiple HA instances** | `UNIQUE (provider_connection_id, provider_device_id)` distinguishes vacation-home HA from primary HA | `(user_id, provider, provider_device_id)` **collides** when two HA instances expose same `entity_id` or when user adds second `home_assistant` connection |
| **MVP one HA per user** | Equivalent behaviour today | Works today |
| **Dedupe precision** | Per-connection identity | Per-provider-type identity only |

**Updated dedupe key (recommended for DB enforcement):**

```
UNIQUE (provider_connection_id, provider_device_id)
```

**Conceptual identity (ADR-014 alignment):**

ADR-014 states `(user_id, provider, provider_device_id)`. With one connection per provider per user in MVP, this is **functionally equivalent** to `(provider_connection_id, provider_device_id)` because `provider_connection_id` implies a single `user_id` + `provider` pair.

**When multiple connections per provider ship (post-MVP):** ADR-014's `(user_id, provider, provider_device_id)` key is **insufficient** — two HA instances would incorrectly dedupe across instances. The `provider_connection_id` FK future-proofs the schema. **Document ADR-014 addendum in Phase 3** noting DB enforcement uses `(provider_connection_id, provider_device_id)`.

**Keep denormalized `provider` on `devices`:** Populated from `provider_connections.provider` at sync time. Enables `GET /api/devices?provider=home_assistant` without joining `provider_connections`.

**Relationship model:**

```
User 1──N ProviderConnection 1──N Device
User 1──N Device (via user_id — retained for policy scope)
Vibe 1──N VibeDeviceAction N──1 Device
```

`Device::providerConnection()` → `BelongsTo(ProviderConnection::class)`  
`ProviderConnection::devices()` → `HasMany(Device::class)`

No direct `ProviderConnection` → `Vibe` relationship.

---

### 4.2 `Device` — model changes (Phase 4)

| Area | Target |
| --- | --- |
| **Fillable** | `user_id`, `provider_connection_id`, `name`, `type`, `provider`, `provider_device_id`, `status`, `metadata`, `last_seen_at` — `user_id` assigned server-side |
| **Casts** | `metadata` → `array`; `last_seen_at` → `datetime` |
| **Timestamps** | Remove `const UPDATED_AT = null` |
| **Hidden** | None (no secrets on device row) |
| **Status constants** | `App\SmartHome\DeviceStatus` enum or class — `Online`, `Offline`, `Unknown` (mirror `RecurrenceType` pattern in `App\Services\Scheduling\`) |
| **Relationships** | `user()`, `providerConnection()`, `vibeActions()` (or alias `vibeDeviceActions()`) |
| **Scopes (optional)** | `scopeForUser($userId)`, `scopeForProvider($slug)` |

---

### 4.3 `VibeDeviceAction` — model changes (Phase 7 API / Phase 4 schema)

| Area | Target |
| --- | --- |
| **Fillable** | `vibe_id`, `device_id`, `action_type`, `parameters`, `sort_order`, `delay_seconds` |
| **Casts** | `parameters` → `array`; `delay_seconds` → `integer`; `sort_order` → `integer` |
| **Timestamps** | Remove `const UPDATED_AT = null` |
| **Action type constants** | `App\SmartHome\ActionType` — `TurnOn`, `TurnOff`, `Toggle` + `mvpAllowed(): array` |
| **Relationships** | `vibe()`, `device()` — unchanged |
| **Default order** | `protected static function booted()` or relationship on Vibe: `deviceActions()->orderBy('sort_order')` |

**Authorization:** Validate `device_id` belongs to same `user_id` as vibe owner in Form Request — device is user-scoped, vibe is user-scoped.

---

### 4.4 `ProviderConnection` — new model (Phase 3)

| Area | Target |
| --- | --- |
| **Path** | `app/Models/ProviderConnection.php` |
| **Fillable** | `name`, `provider`, `config`, `encrypted_credentials`, `status`, `last_tested_at` — **not** `user_id` (server assigns) |
| **Hidden** | `encrypted_credentials` — always |
| **Casts** | `config` → `array`; `last_tested_at` → `datetime` |
| **Credentials access** | Custom accessor/mutator or dedicated `ProviderCredentials` value object — decrypt only in adapter layer, never in Resource |
| **Status constants** | `App\SmartHome\ConnectionStatus` — `Connected`, `Unreachable`, `Unknown` |
| **Relationships** | `user()`, `devices()` |

**`devices()` via `provider_connection_id` FK** — not via `user_id` + `provider` string match.

---

### 4.5 `User` — relationship additions (Phase 3)

| Method | Add |
| --- | --- |
| `providerConnections()` | `HasMany(ProviderConnection::class)` |

`devices()` already exists — keep.

---

### 4.6 `Vibe` — relationship updates (Phase 7)

| Method | Change |
| --- | --- |
| `deviceActions()` | Add `->orderBy('sort_order')` on relationship definition |

---

## 5. Migration strategy proposal

**No migration code in Phase 2.** Proposed execution order and safe patterns for Phase 3–4:

### 5.1 Execution order

```
Phase 3 migration: create provider_connections
Phase 4 migration A: harden devices (depends on provider_connections existing)
Phase 4 migration B: harden vibe_device_actions (independent; can same PR)
```

**`provider_connections` must land before `devices` hardening** because `devices.provider_connection_id` FK references it.

### 5.2 `provider_connections` create (Phase 3)

Single `create_provider_connections_table` migration:

1. Create table with all columns
2. Add `UNIQUE (user_id, provider)` — `uq_provider_connections_user_provider`
3. Index `user_id` (implicit from FK)

No backfill — empty table.

### 5.3 `devices` harden (Phase 4)

Follow **Scheduler MVP two-step pattern** (`2026_06_12_000001_add_scheduler_mvp_columns_to_schedules_table.php`): add nullable → backfill → constrain.

**Pre-flight (run in migration or manual staging check):**

```sql
SELECT COUNT(*) FROM devices;
SELECT user_id, provider, external_id, COUNT(*)
FROM devices
GROUP BY user_id, provider, external_id
HAVING COUNT(*) > 1;
```

**Expected result:** `COUNT(*) = 0` on fresh/staging environments. If rows exist, run dedupe before unique index.

**Steps:**

| Step | Action |
| --- | --- |
| 1 | Add `provider_connection_id` **nullable** FK → `provider_connections.id` `cascadeOnDelete` |
| 2 | Rename column `external_id` → `provider_device_id` (PostgreSQL: `ALTER TABLE ... RENAME COLUMN`; Laravel `renameColumn` requires `doctrine/dbal` or raw `DB::statement`) |
| 3 | Add `status` string(32) **nullable** |
| 4 | Add `last_seen_at` timestamp **nullable** |
| 5 | Add `updated_at` timestamp **nullable** |
| 6 | **Backfill** `status = 'unknown'` where null |
| 7 | **Backfill** `updated_at = created_at` where null |
| 8 | **Backfill** `provider` slug if legacy display values exist (`Home Assistant` → `home_assistant`) |
| 9 | If `devices` rows exist without connection: **delete orphan rows** (no production data expected) OR block migration with explicit error |
| 10 | Alter `status` to NOT NULL default `'unknown'` |
| 11 | Drop old non-unique index on `(user_id, provider, external_id)` — name may be `devices_user_id_provider_external_id_index` (verify `pg_indexes` / `SHOW INDEX`) |
| 12 | Add **unique** index `uq_devices_connection_provider_device_id` on `(provider_connection_id, provider_device_id)` |
| 13 | Optional: add non-unique index `(user_id, provider)` |

**Rename risk mitigation:**

- PostgreSQL `RENAME COLUMN` is metadata-only — fast, no data rewrite.
- Update `Device` model fillable and any raw queries in same PR as migration.
- Factories and tests must use `provider_device_id` from first write.

**Unique index risk mitigation:**

- Run duplicate detection query before step 12.
- If duplicates found: keep row with latest `created_at`, reassign `vibe_device_actions` FKs if needed, delete duplicates.
- If `provider_connection_id` still null on any row: resolve or delete before NOT NULL enforcement.

**`provider_connection_id` NOT NULL:**

- After backfill, alter to NOT NULL.
- On empty table: can add as NOT NULL immediately in single migration (simpler).

### 5.4 `vibe_device_actions` harden (Phase 4)

| Step | Action |
| --- | --- |
| 1 | Add `sort_order` unsignedInteger NOT NULL default `0` |
| 2 | Add `updated_at` timestamp nullable |
| 3 | Backfill `updated_at = created_at` |
| 4 | Optional: add index `(vibe_id, sort_order)` |

No unique constraints. Existing rows get `sort_order = 0` — acceptable; app reassigns on first edit.

### 5.5 Factories and tests (Phase 3–4)

| Factory | Phase | Notes |
| --- | --- | --- |
| `ProviderConnectionFactory` | 3 | Encrypt test token with `Crypt::encryptString()`; `provider: home_assistant` |
| `DeviceFactory` | 4 | Requires `ProviderConnection::factory()`; `provider_device_id: 'light.living_room'` |
| `VibeDeviceActionFactory` | 7 | `action_type: turn_on`, `sort_order: 0` |

**Tests to write (Phase 4):**

- `tests/Feature/SmartHome/ProviderConnectionApiTest.php`
- `tests/Feature/SmartHome/DeviceApiTest.php`
- `tests/Feature/SmartHome/DeviceSyncTest.php` — upsert dedupe, no duplicate on second sync
- `tests/Unit/SmartHome/DeviceStatusTest.php` — enum values (optional)

---

## 6. Risks and open questions

| # | Risk / question | Severity | Mitigation |
| --- | --- | --- | --- |
| R1 | **Existing `devices` rows** | Low (expected empty) | Pre-flight `COUNT(*)` in migration; document delete-orphans strategy |
| R2 | **Rename `external_id` column** | Medium | Metadata-only in PostgreSQL; same-PR model update; grep codebase for `external_id` (currently only `Device` fillable) |
| R3 | **Unique index on duplicates** | Medium | Dedupe query before index; migration aborts with message if duplicates remain |
| R4 | **`provider_connection_id` decision** | High — **resolved** | **Add FK** — see §4.1; update ADR-014 cross-reference in Phase 3 PR description |
| R5 | **One connection per provider vs multiple future** | Medium | DB `UNIQUE (user_id, provider)` for MVP; future migration drops constraint |
| R6 | **HTTPS-only HA URL** | Medium | `StoreProviderConnectionRequest` rejects non-HTTPS; env `SMART_HOME_ALLOW_HTTP=true` for local dev only ([`plan.md`](plan.md) open question #4) |
| R7 | **`provider` slug vs display name in stub** | Low | App normalizes to `home_assistant`; backfill in migration if rows exist |
| R8 | **`user_settings.preferred_device_id`** | Low | `nullOnDelete` already safe; Smart Home MVP does not expose preferred device UI |
| R9 | **`DevicePolicy` exists but no API** | Low | Policy is ready; wire in Phase 4 controller |
| R10 | **ADR-014 dedupe key vs `provider_connection_id`** | Medium | Document equivalence for MVP; DB uses `(provider_connection_id, provider_device_id)` — ADR-014 conceptual key remains valid until multi-connection |
| R11 | **`renameColumn` / `change()` deps** | Low | Verify `doctrine/dbal` or use raw SQL in migration — match existing project pattern |
| R12 | **Encrypted credentials rotation** | Low | Out of MVP; `APP_KEY` rotation would invalidate stored tokens — document ops note |

**Open questions for Phase 3 PR:**

1. Confirm staging/production `devices` table row count is zero before hardening migration.
2. Confirm `SMART_HOME_ALLOW_HTTP` env flag name and default (`false`).
3. Whether `Device::vibeActions()` should be renamed to `vibeDeviceActions()` for symmetry (cosmetic).

---

## 7. Recommendation

### Phase 3 — implement first

| Deliverable | Priority |
| --- | --- |
| Migration `create_provider_connections_table` | **First** |
| Model `ProviderConnection` with `$hidden`, casts, credential handling | **First** |
| `App\SmartHome\ProviderType` enum/constants | **First** |
| `ProviderConnectionFactory` | **First** |
| `User::providerConnections()` relationship | **First** |

**Rationale:** `devices.provider_connection_id` FK depends on this table. Do not harden `devices` before `provider_connections` exists.

### Phase 4 — device schema + CRUD (after Phase 3)

| Deliverable | Priority |
| --- | --- |
| Migration harden `devices` (rename, new columns, FK, unique index) | **Before API** |
| Migration harden `vibe_device_actions` (`sort_order`, `updated_at`) | Same PR or immediately after |
| Update `Device`, `VibeDeviceAction` models | Same PR as migrations |
| `App\SmartHome\DeviceStatus`, `ActionType` constants | Same PR |
| `DeviceFactory` | Before Pest tests |
| `ProviderConnectionPolicy` | Before controllers |
| `DeviceController`, `ProviderConnectionController` | After models + policies |
| Form Requests + API Resources | With controllers |
| Pest feature tests (CRUD, sync dedupe, 403, no token leak) | With controllers |

**Rationale:** Schema must be stable before API contract is implemented. `vibe_device_actions` hardening can ship in Phase 4 even though action **API/UI** is Phase 7 — avoids a second migration pass later.

### Phase 5 — Home Assistant adapter

| Deliverable | Depends on |
| --- | --- |
| `ProviderAdapter` interface + `HomeAssistantAdapter` | Phase 3 model (credentials decrypt), Phase 4 sync endpoint shell |

**Rationale:** Adapter needs `ProviderConnection` model to decrypt credentials. Sync endpoint (Phase 4) calls adapter (Phase 5) — **Phase 4 can ship CRUD with sync returning 501 or stub until Phase 5**, or Phase 4+5 land together. Prefer **Phase 3 → Phase 4 (CRUD without sync) → Phase 5 (adapter + sync)** OR **Phase 4+5 single feature branch** if sync is required for MVP demo.

**Recommended:** Phase 4 ships device list CRUD + connection CRUD; `POST .../sync` implemented in Phase 5 when adapter exists.

### Phase 7 — vibe device action API

Uses hardened `vibe_device_actions` schema from Phase 4. No additional migration expected.

### Summary table

| Question | Answer |
| --- | --- |
| Implement `provider_connections` before device CRUD? | **Yes — Phase 3 before Phase 4** |
| Harden `devices` schema before HA adapter? | **Yes — Phase 4 migration before Phase 5 adapter** |
| Add `provider_connection_id` to `devices`? | **Yes** |
| DB unique on `provider_connections (user_id, provider)`? | **Yes for MVP** |
| DB unique on `devices`? | **`UNIQUE (provider_connection_id, provider_device_id)`** |
| Unique on `vibe_device_actions`? | **No in MVP** |

---

## Related docs

| Document | Path |
| --- | --- |
| Feature spec | [`spec.md`](spec.md) |
| Implementation plan | [`plan.md`](plan.md) |
| Task checklist | [`tasks.md`](tasks.md) |
| ADR-012 | [`decisions/ADR-012-smart-home-provider-strategy.md`](../../../decisions/ADR-012-smart-home-provider-strategy.md) |
| ADR-013 | [`decisions/ADR-013-home-assistant-first-provider.md`](../../../decisions/ADR-013-home-assistant-first-provider.md) |
| ADR-014 | [`decisions/ADR-014-device-abstraction-and-deduplication.md`](../../../decisions/ADR-014-device-abstraction-and-deduplication.md) |
| ADR-015 | [`decisions/ADR-015-vibe-device-action-architecture.md`](../../../decisions/ADR-015-vibe-device-action-architecture.md) |
| ADR-016 | [`decisions/ADR-016-smart-home-async-execution.md`](../../../decisions/ADR-016-smart-home-async-execution.md) |
| Scheduler schema hardening reference | `back_vibes/database/migrations/2026_06_12_000001_add_scheduler_mvp_columns_to_schedules_table.php` |

When schema decisions change, update **this file first**, then [`plan.md`](plan.md), [`tasks.md`](tasks.md), and affected ADRs.
