# Smart Home Foundation MVP — task checklist

**Status:** Phase 1 complete — pre-implementation  
**Spec:** [`spec.md`](spec.md)  
**Plan:** [`plan.md`](plan.md)  
**Feature ID:** `smart-home/mvp`

**Status legend**

| Status | Meaning |
| --- | --- |
| **Pending** | Not started |
| **In progress** | Active work on branch |
| **Done** | Merged to `develop` / verified on staging |
| **Deferred** | Post-MVP or fast-follow |

---

## Task list summary

| Phase | Pending | In progress | Done | Deferred |
| --- | ---: | ---: | ---: | ---: |
| 1 — Spec + ADRs | 2 | 0 | 7 | 0 |
| 2 — Schema review | 0 | 0 | 4 | 0 |
| 3 — provider_connections model | 0 | 0 | 4 | 0 |
| 4 — Device CRUD backend | 0 | 0 | 10 | 0 |
| 5 — HA adapter contract | 0 | 0 | 6 | 0 |
| 6 — Devices mobile tab | 0 | 0 | 8 | 0 |
| 7 — Device action association UI | 6 | 0 | 0 | 0 |
| 8 — Async execution foundation | 4 | 0 | 0 | 0 |
| 9 — HA real execution | 5 | 0 | 0 | 0 |
| 10 — E2E QA | 8 | 0 | 0 | 0 |

---

## Phase 1 — Spec + ADRs

| ID | Task | Status | Reference |
| --- | --- | --- | --- |
| P1-1 | Publish **`spec.md`** (MVP source of truth) | **Done** | [`spec.md`](spec.md) |
| P1-2 | Publish **`plan.md`** | **Done** | [`plan.md`](plan.md) |
| P1-3 | Publish **`tasks.md`** | **Done** | This file |
| P1-4 | Draft **ADR-012** — Provider strategy | **Done** | [`ADR-012`](../../../decisions/ADR-012-smart-home-provider-strategy.md) |
| P1-5 | Draft **ADR-013** — Home Assistant first provider | **Done** | [`ADR-013`](../../../decisions/ADR-013-home-assistant-first-provider.md) |
| P1-6 | Draft **ADR-014** — Device abstraction + deduplication | **Done** | [`ADR-014`](../../../decisions/ADR-014-device-abstraction-and-deduplication.md) |
| P1-7 | Draft **ADR-015** — Vibe device action architecture | **Done** | [`ADR-015`](../../../decisions/ADR-015-vibe-device-action-architecture.md) |
| P1-8 | Draft **ADR-016** — Async execution | **Done** | [`ADR-016`](../../../decisions/ADR-016-smart-home-async-execution.md) |
| P1-9 | Add Smart Home entry to **`docs/README.md`** index | **Pending** | [`README.md`](../../../README.md) |
| P1-10 | Remove Smart Home from "Intentionally not implemented" in `README.md` | **Pending** | [`README.md`](../../../README.md) |

**Branch:** `feature/smart-home-spec-adrs` from **`develop`**

---

## Phase 2 — Existing schema/domain review

**No migrations. Review and documentation only.**

| ID | Task | Status | Reference |
| --- | --- | --- | --- |
| P2-1 | Document required changes to **`devices`** stub (rename `external_id`, add `status`, `last_seen_at`, `updated_at`, `provider_connection_id`) | **Done** | [`schema-review.md`](schema-review.md) § 1.1, § 3.1 |
| P2-2 | Document required changes to **`vibe_device_actions`** stub (add `sort_order`, `updated_at`) | **Done** | [`schema-review.md`](schema-review.md) § 1.2, § 3.2 |
| P2-3 | Document **`provider_connections`** new table schema | **Done** | [`schema-review.md`](schema-review.md) § 3.3 |
| P2-4 | Review existing `Device` and `VibeDeviceAction` Eloquent models — document current state vs MVP target | **Done** | [`schema-review.md`](schema-review.md) § 2 |

**Deliverable:** [`schema-review.md`](schema-review.md) — includes `provider_connection_id` decision, migration strategy, risks, Phase 3/4 recommendation.

**Branch:** `feature/smart-home-schema-review`

---

## Phase 3 — `provider_connections` model and migration

| ID | Task | Status | Reference |
| --- | --- | --- | --- |
| P3-1 | Migration: create **`provider_connections`** table | **Done** | [`plan.md`](plan.md) § Phase 3 |
| P3-2 | **`ProviderConnection`** Eloquent model — casts, fillable, `$hidden` | **Done** | `back_vibes/app/Models/ProviderConnection.php` |
| P3-3 | **`ProviderType`** constant/enum — `home_assistant` + reserved future slugs | **Done** | `back_vibes/app/SmartHome/ProviderType.php` |
| P3-4 | Factory for `ProviderConnection` (Pest) | **Done** | `back_vibes/database/factories/ProviderConnectionFactory.php` |

**Phase 3 notes:** `ConnectionStatus` enum added at `back_vibes/app/SmartHome/ConnectionStatus.php`. Credential encryption helpers (`setEncryptedCredentials` / `decryptedCredentials`) on model. `User::providerConnections()` relationship added. Feature tests at `tests/Feature/SmartHome/ProviderConnectionModelTest.php` — 25 passing assertions covering schema, casts, encryption, hidden attribute, unique constraint, relationships, and enum helpers.

**Branch:** `feature/smart-home-provider-connection-model`

---

## Phase 4 — Device CRUD backend

| ID | Task | Status | Reference |
| --- | --- | --- | --- |
| P4-1 | Migration: update **`devices`** — rename `external_id` → `provider_device_id`, add `status`, `last_seen_at`, `updated_at`, unique constraint | **Done** | [`ADR-014`](../../../decisions/ADR-014-device-abstraction-and-deduplication.md) |
| P4-2 | Migration: update **`vibe_device_actions`** — add `sort_order`, `updated_at` | **Done** | [`ADR-015`](../../../decisions/ADR-015-vibe-device-action-architecture.md) |

**Phase 4A Schema Hardening completed. Phase 4B Device CRUD API complete.** Additions: `DeviceStatus`, `ActionType` enums, `DeviceFactory`, `VibeDeviceActionFactory`, `Vibe::deviceActions()` ordered by `sort_order`. Tests at `tests/Feature/SmartHome/SmartHomeSchemaHardeningTest.php` — 32 passing assertions.
| P4-3 | **`DevicePolicy`** / **`ProviderConnectionPolicy`** — owner scoping | **Done** | `back_vibes/app/Policies/` |
| P4-4 | **`StoreProviderConnectionRequest` / `UpdateProviderConnectionRequest`** | **Done** | Validate HTTPS base URL, token present |
| P4-5 | **`StoreDeviceRequest` / `UpdateDeviceRequest`** | **Done** | Scoped to `auth()->id()` |
| P4-6 | **`ProviderConnectionResource`** — omit `access_token` | **Done** | [`ADR-013`](../../../decisions/ADR-013-home-assistant-first-provider.md) security |
| P4-7 | **`DeviceResource`** — include `status`, `provider_device_id`, `last_seen_at` | **Done** | [`ADR-014`](../../../decisions/ADR-014-device-abstraction-and-deduplication.md) |
| P4-8 | **`ProviderConnectionController`** + **`DeviceController`** — CRUD routes | **Done** | [`spec.md`](spec.md) § 9 API outline |
| P4-9 | `POST .../sync` — upsert devices from provider; absent → `offline`; unreachable → `unknown` | **Done** | `back_vibes/app/SmartHome/Services/ProviderDeviceSyncService.php`, `tests/Feature/SmartHome/ProviderConnectionSyncApiTest.php` |
| P4-10 | Pest feature tests — CRUD, 403, 422, sync dedup, no token in response | **Done** | `tests/Feature/SmartHome/` |

**Branch:** `feature/smart-home-device-crud`

**Verify:**

```bash
cd back_vibes && php artisan test --filter=SmartHome
cd back_vibes && php artisan test
cd back_vibes && ./vendor/bin/pint --test
```

---

## Phase 5 — Home Assistant adapter contract

| ID | Task | Status | Reference |
| --- | --- | --- | --- |
| P5-1 | Define **`ProviderAdapter`** PHP interface | **Done** | `back_vibes/app/SmartHome/Contracts/ProviderAdapter.php` |
| P5-2 | Define DTOs: **`DeviceStatusResult`**, **`ProviderDevice`**, **`ActionResult`**, **`ConnectionHealth`** | **Done** | `back_vibes/app/SmartHome/DTOs/` |
| P5-3 | Implement **`HomeAssistantAdapter`** — `listDevices`, `readStatus`, `executeAction`, `testConnection` | **Done** | `back_vibes/app/SmartHome/Adapters/HomeAssistantAdapter.php` |
| P5-4 | Map IXORA action types to HA service calls (`turn_on` → `light.turn_on`, etc.) | **Done** | [`ADR-013`](../../../decisions/ADR-013-home-assistant-first-provider.md) § HA REST API |
| P5-5 | Unit tests with mocked HTTP — happy paths + HA unreachable | **Done** | `tests/Unit/SmartHome/HomeAssistantAdapterTest.php`, `ProviderAdapterResolverTest.php` |
| P5-6 | Register adapter in service container (`ProviderType::HOME_ASSISTANT → HomeAssistantAdapter`) | **Done** | `App\Providers\SmartHomeServiceProvider` + `App\SmartHome\ProviderAdapterResolver` |

**Branch:** `feature/smart-home-ha-adapter`

**Phase 5 notes:** Contract `ProviderAdapter` + four immutable DTOs (`DeviceStatusResult`, `ProviderDevice`, `ActionResult`, `ConnectionHealth`). `HomeAssistantAdapter` uses the Laravel HTTP facade with Bearer auth (token decrypted at call time, never logged), `config('smart_home.providers.home_assistant.timeout', 10)` timeout, and filters actionable HA domains (`light`, `switch`, `media_player`, `fan`). Action mapping: `turn_on`/`turn_off`/`toggle` → `{domain}.turn_on|turn_off|toggle`; unsupported actions throw `UnsupportedSmartHomeActionException`. Error policy: `testConnection`/`readStatus`/`executeAction` return failure DTOs (never throw on transport/HTTP errors); `listDevices` throws `ProviderConnectionException` on unreachable/non-2xx so sync can mark devices unknown. `ProviderAdapterResolver::forProvider()` resolves `home_assistant` and rejects unsupported providers. New `config/smart_home.php`. Tests: `tests/Unit/SmartHome/HomeAssistantAdapterTest.php` (27) + `ProviderAdapterResolverTest.php` (6) — 33 passing with `Http::fake()`, no real HA calls. **Sync endpoint P4-9 remains Pending.**

**Verify:**

```bash
cd back_vibes && php artisan test --filter=HomeAssistantAdapter
cd back_vibes && php artisan test --filter=ProviderAdapterResolver
```

---

## Phase 6 — Devices mobile tab + provider connection UI

| ID | Task | Status | Reference |
| --- | --- | --- | --- |
| P6-1 | Add **Devices** tab to bottom navigation bar (root level) | **Done** | `front_vibes/src/views/TabsLayout.vue`, `src/router/index.ts` |
| P6-2 | **`provider-connection.service.ts`** — REST client (create, delete, sync, test) | **Done** | `front_vibes/src/services/provider-connection.service.ts` |
| P6-3 | **`device.service.ts`** — REST client (list, show, update, delete, test) | **Done** | `front_vibes/src/services/device.service.ts` |
| P6-4 | **Device list page** — status badge per device; pull-to-refresh | **Done** | `front_vibes/src/views/DevicesPage.vue` |
| P6-5 | **Add provider connection form** — provider selector (HA only MVP), base URL, token (write-only); test on submit | **Done** | `front_vibes/src/views/ProviderConnectionFormPage.vue` |
| P6-6 | **Provider connection detail** — show (no token); sync button; delete | **Done** | `front_vibes/src/views/ProviderConnectionDetailPage.vue` |
| P6-7 | **Device detail / edit** — rename, type label; test device; delete | **Done** | `front_vibes/src/views/DeviceDetailPage.vue` |
| P6-8 | **Block mutations offline** — toast + disable actions | **Done** | service-layer `DeviceOfflineError` + page banners/toasts |

**Branch:** `feature/smart-home-devices-mobile`

**Platform:** Android + iOS

**Phase 6 notes:** Online-only Smart Home mobile UI. Two REST clients (`provider-connection.service.ts`, `device.service.ts`) reuse the Firebase Bearer + `laravelFetch` transport from `schedule.service.ts`; both block create/update/delete/sync offline via a shared `DeviceOfflineError` (`"Devices can only be changed while online."`) and never call Home Assistant directly. The HA access token is write-only: sent once nested under `encrypted_credentials.access_token` on create, cleared from form state after submit, never returned/logged/stored. Composables `useProviderConnections` / `useDevices` follow the `useSchedules` singleton-ref pattern (no Pinia, **no SQLite mirror** — offline keeps last in-memory list). New root **Devices** tab + routes `/devices`, `/devices/providers/new`, `/devices/providers/:id`, `/devices/:id` under the existing auth guard. Status badges via `utils/device-status.ts`: online→green (`success`), offline→red (`danger`), unknown→grey (`medium`). Tests: `provider-connection.service` (11), `device.service` (7), `device-status` (6), `useProviderConnections` (6), `useDevices` (5) — 35 new, full suite 130 passing. No backend / Scheduler / queue-job / execution / vibe-action-UI code added.

**Verify:**

```bash
cd front_vibes && npm run lint && npm run typecheck && npm run build && npm run test:unit
```

---

## Phase 7 — Device action association UI

| ID | Task | Status | Reference |
| --- | --- | --- | --- |
| P7-1 | **`vibe-device-action.service.ts`** — REST client (list, create, update, delete, reorder) | **Pending** | `front_vibes/src/services/` |
| P7-2 | **Device Actions section** in vibe detail screen | **Pending** | [`ADR-015`](../../../decisions/ADR-015-vibe-device-action-architecture.md) |
| P7-3 | **Action type picker** — `turn_on`, `turn_off`, `toggle` (MVP) | **Pending** | |
| P7-4 | **Device picker** — select from user's registered devices | **Pending** | |
| P7-5 | **Delay input** — optional `delay_seconds` per action | **Pending** | |
| P7-6 | **Reorder actions** — drag or up/down buttons; persist `sort_order` | **Pending** | [`ADR-015`](../../../decisions/ADR-015-vibe-device-action-architecture.md) |

**Branch:** `feature/smart-home-vibe-action-ui`

---

## Phase 8 — Async execution foundation

| ID | Task | Status | Reference |
| --- | --- | --- | --- |
| P8-1 | **`SmartHomeActionJob`** queue job (stub — logs intent, no HA call) | **Pending** | `back_vibes/app/Jobs/SmartHome/SmartHomeActionJob.php` |
| P8-2 | Job dispatch triggered by vibe play event (trigger endpoint TBD) | **Pending** | [`ADR-016`](../../../decisions/ADR-016-smart-home-async-execution.md) |
| P8-3 | Pest: assert job is dispatched; assert graceful failure on bad action ID | **Pending** | `tests/Feature/SmartHome/SmartHomeActionJobTest.php` |
| P8-4 | Document queue name and timeout config | **Pending** | [`plan.md`](plan.md) § Phase 8 |

**Branch:** `feature/smart-home-async-foundation`

---

## Phase 9 — Home Assistant real execution

| ID | Task | Status | Reference |
| --- | --- | --- | --- |
| P9-1 | `SmartHomeActionJob` calls **`HomeAssistantAdapter::executeAction()`** | **Pending** | [`ADR-013`](../../../decisions/ADR-013-home-assistant-first-provider.md), [`ADR-016`](../../../decisions/ADR-016-smart-home-async-execution.md) |
| P9-2 | Resolve `ProviderConnection` from device; decrypt credentials | **Pending** | |
| P9-3 | Log execution result — success / failure / timeout | **Pending** | `action_execution_logs` table or column (design in Phase 9) |
| P9-4 | Graceful failure — catch all exceptions; audio unaffected | **Pending** | [`ADR-015`](../../../decisions/ADR-015-vibe-device-action-architecture.md) |
| P9-5 | Pest: mocked HA HTTP — success, unreachable provider, token failure | **Pending** | |

**Branch:** `feature/smart-home-ha-execution`

---

## Phase 10 — E2E QA

| ID | Task | Status | Reference |
| --- | --- | --- | --- |
| P10-1 | Staging: add HA provider connection → test connection passes | **Pending** | [`plan.md`](plan.md) § Phase 10 |
| P10-2 | Staging: sync → devices appear; re-sync → no duplicates | **Pending** | [`ADR-014`](../../../decisions/ADR-014-device-abstraction-and-deduplication.md) |
| P10-3 | Staging: device status badge correct (online / offline / unknown) | **Pending** | |
| P10-4 | Staging: attach action to vibe → API persists `vibe_device_action` | **Pending** | |
| P10-5 | Staging: trigger play event → `SmartHomeActionJob` dispatched → HA receives call | **Pending** | |
| P10-6 | Security: `GET /api/provider-connections/{id}` → no `access_token` in response | **Pending** | |
| P10-7 | Security: cross-user device access → 403 | **Pending** | |
| P10-8 | Offline: device mutation UI blocked → toast shown | **Pending** | |

---

## Cross-cutting validation tasks

| ID | Task | Status | When |
| --- | --- | --- | --- |
| X-1 | Laravel full test suite on **`back_vibes`** touch | **Pending** | Each backend PR |
| X-2 | **`front_vibes` production build** clean | **Pending** | Each mobile PR |
| X-3 | Confirm **no Scheduler code modified** | **Pending** | Phase 1 sign-off |
| X-4 | Confirm **`access_token` never in API response** | **Pending** | Phase 4 sign-off |
| X-5 | Confirm **no duplicate devices** after repeated sync | **Pending** | Phase 10 QA |
| X-6 | Confirm **audio plays** even when device action fails | **Pending** | Phase 9 |
| X-7 | Confirm **no direct HA calls from mobile** | **Done** | Phase 6 — mobile calls Laravel API only (`laravelFetch`) |

---

## Done criteria (MVP)

### Documentation (Phase 1)

- [x] `spec.md`, `plan.md`, `tasks.md` published under `docs/specs/smart-home/mvp/`
- [x] ADR-012, ADR-013, ADR-014, ADR-015, ADR-016 accepted
- [ ] `docs/README.md` updated with Smart Home section
- [ ] No runtime code changed in Phase 1

### Documentation (Phase 2)

- [x] `schema-review.md` published — current schema inventory, model inventory, target delta, migration strategy
- [x] `provider_connection_id` decision documented (recommend: **yes**)
- [x] Phase 2 tasks P2-1 through P2-4 complete
- [x] No runtime code changed in Phase 2

### Backend

- [ ] `provider_connections` table created with encrypted credentials
- [ ] `devices` stub updated — `provider_device_id`, `status`, `last_seen_at`, `updated_at`
- [ ] `vibe_device_actions` stub updated — `sort_order`, `updated_at`
- [ ] Device CRUD API + Policies + Pest tests green
- [x] Sync endpoint — upsert, no duplicates verified
- [x] `HomeAssistantAdapter` unit tests green
- [ ] `SmartHomeActionJob` dispatched for play events

### Mobile

- [x] Devices tab at root navigation
- [x] Device list with status badges
- [x] Add / delete provider connection (HA, write-only token)
- [x] Device sync — no duplicate entries
- [ ] Device action association on vibe detail
- [x] Offline mutations blocked

### Hard boundaries verified

- [ ] **No `access_token` in any API response**
- [x] **No direct provider calls from mobile**
- [ ] **No Scheduler code modified**
- [ ] **Audio unaffected by device action failure**
- [ ] **No duplicate devices after repeated sync**
- [ ] **No complex automations / conditions**

### Explicitly not required for MVP done

- Alexa, Google Home, Apple HomeKit adapters
- Matter / Thread / Zigbee direct
- Conditional automations
- Brightness / color / temperature action types
- `ActionExecutionLog` mobile UI
- Token rotation
- Admin panel Smart Home views
- Smart Home schedules separate from Scheduler

---

## Git workflow reminder

All implementation branches:

```bash
git checkout develop && git pull origin develop
git checkout -b feature/smart-home-<phase-short-name>
# PR → develop (never commit directly to develop/main/staging)
```

Promote to homologation:

```bash
git checkout staging && git pull origin staging
git merge --no-ff develop -m "Merge branch 'develop' into staging"
git push origin staging
```

Full policy: [`git-flow.md`](../../../standards/git-flow.md).

---

## Related docs

| Document | Path |
| --- | --- |
| Spec | [`spec.md`](spec.md) |
| Plan | [`plan.md`](plan.md) |
| Schema review | [`schema-review.md`](schema-review.md) |
| ADR-012 | [`decisions/ADR-012-smart-home-provider-strategy.md`](../../../decisions/ADR-012-smart-home-provider-strategy.md) |
| ADR-013 | [`decisions/ADR-013-home-assistant-first-provider.md`](../../../decisions/ADR-013-home-assistant-first-provider.md) |
| ADR-014 | [`decisions/ADR-014-device-abstraction-and-deduplication.md`](../../../decisions/ADR-014-device-abstraction-and-deduplication.md) |
| ADR-015 | [`decisions/ADR-015-vibe-device-action-architecture.md`](../../../decisions/ADR-015-vibe-device-action-architecture.md) |
| ADR-016 | [`decisions/ADR-016-smart-home-async-execution.md`](../../../decisions/ADR-016-smart-home-async-execution.md) |
| Scheduler MVP spec | [`specs/scheduler/mvp/spec.md`](../../scheduler/mvp/spec.md) |
| Execution plan | [`specs/vibes/execution-plan/spec.md`](../../vibes/execution-plan/spec.md) |
| Auth | [`standards/front-vibes-auth-core.md`](../../../standards/front-vibes-auth-core.md) |
| Git Flow | [`standards/git-flow.md`](../../../standards/git-flow.md) |
| DigitalOcean staging | [`architecture/backend/staging-digitalocean.md`](../../../architecture/backend/staging-digitalocean.md) |
