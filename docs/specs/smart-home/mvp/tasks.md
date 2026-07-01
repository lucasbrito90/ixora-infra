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
| 7A — Vibe Device Action backend API | 0 | 0 | 7 | 0 |
| 7 — Device action association UI (mobile) | 0 | 0 | 6 | 0 |
| 8 — Async execution foundation | 0 | 0 | 4 | 0 |
| 9 — HA real execution | 0 | 0 | 5 | 0 |
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
| P7-1 | **`vibe-device-action.service.ts`** — REST client (list, create, update, delete, reorder) | **Done** | `front_vibes/src/services/vibe-device-action.service.ts` |
| P7-2 | **Device Actions section / page** for a vibe | **Done** | `front_vibes/src/views/VibeDeviceActionsPage.vue` |
| P7-3 | **Action type picker** — `turn_on`, `turn_off`, `toggle` (MVP) | **Done** | `front_vibes/src/utils/device-action.ts`, `VibeDeviceActionEditModal.vue` |
| P7-4 | **Device picker** — select from user's registered devices | **Done** | `VibeDeviceActionEditModal.vue` (via `useDevices`) |
| P7-5 | **Delay input** — optional `delay_seconds` per action | **Done** | `VibeDeviceActionEditModal.vue` |
| P7-6 | **Reorder actions** — up/down buttons; persist `sort_order` | **Done** | `VibeDeviceActionsPage.vue` → `reorder` endpoint |

**Branch:** `feature/smart-home-vibe-action-ui` from **`develop`**

> **✅ Phase 7 mobile UI complete (2026-06-20).** Backend prerequisite Phase 7A
> (see below) shipped first; this phase consumes that REST API. Mobile calls the
> Laravel API only — no direct Home Assistant calls and no on-device execution.

**Phase 7 notes:** New `vibe-device-action.service.ts` reuses the Firebase Bearer + `laravelFetch` transport and the shared `DeviceOfflineError` (`"Devices can only be changed while online."`) — list/create/update/delete/reorder; create/update/delete/reorder are blocked offline at the service layer. Singleton composable `useVibeDeviceActions.ts` follows the `useDevices` ref pattern (no Pinia, **no SQLite mirror** — offline keeps the last in-memory list). Focused page **`/vibes/:id/device-actions`** (mirrors the existing `/vibes/:id/sounds` sub-page) lists actions ordered by `sort_order`, each card showing device name, device **status badge** (reuses `utils/device-status.ts`: online→green, offline→red, unknown→grey), action-type label, and `delay_seconds`; up/down buttons call the `reorder` endpoint; edit/delete with confirm alert; offline shows a banner + toast and disables mutations. Add/edit via `VibeDeviceActionEditModal.vue`: device picker (from `useDevices`), action-type picker (MVP `turn_on`/`turn_off`/`toggle` only via `utils/device-action.ts`), and `delay_seconds` input (0–3600). Navigation entry added to the vibe card on `VibesPage.vue`. Tests: `vibe-device-action.service` (10), `useVibeDeviceActions` (9), `device-action` utils (12) — 31 new; full suite **161 passing**. Validation: `npm run lint`, `npm run typecheck`, `npm run build`, `npm run test:unit` all green. **No execution engine, queue jobs, Scheduler changes, HA calls, or brightness/color/temperature/scenes added.**

---

## Phase 7A — Vibe Device Action backend API (mobile prerequisite)

| ID | Task | Status | Reference |
| --- | --- | --- | --- |
| P7A-1 | Routes inside `vibes/{vibe}` group — index/store/reorder/update/destroy (`reorder` registered before `{action}` wildcard) | **Done** | `back_vibes/routes/api.php` |
| P7A-2 | **`VibeDeviceActionController`** — owner-scoped CRUD + reorder | **Done** | `back_vibes/app/Http/Controllers/Api/VibeDeviceActionController.php` |
| P7A-3 | **`StoreVibeDeviceActionRequest`** — device owned by user, `action_type` in `ActionType::mvpAllowed()`, `delay_seconds` 0–3600 | **Done** | `back_vibes/app/Http/Requests/StoreVibeDeviceActionRequest.php` |
| P7A-4 | **`UpdateVibeDeviceActionRequest`** — partial update (`sometimes`), same constraints | **Done** | `back_vibes/app/Http/Requests/UpdateVibeDeviceActionRequest.php` |
| P7A-5 | **`ReorderVibeDeviceActionsRequest`** — `ordered_ids` required/distinct, all ids belong to vibe | **Done** | `back_vibes/app/Http/Requests/ReorderVibeDeviceActionsRequest.php` |
| P7A-6 | **`VibeDeviceActionResource`** — includes nested device (id/name/type/provider/status/provider_device_id) | **Done** | `back_vibes/app/Http/Resources/VibeDeviceActionResource.php` |
| P7A-7 | Pest feature tests — auth, CRUD, ownership, reorder, no execution/job/HA call | **Done** | `back_vibes/tests/Feature/SmartHome/VibeDeviceActionApiTest.php` (28 tests) |

**Branch:** `feature/smart-home-vibe-action-api` from **`develop`**

**Endpoints (inside `firebase.auth` middleware):**

- `GET    /api/vibes/{vibe}/device-actions` — owner lists actions ordered by `sort_order`, device eager-loaded
- `POST   /api/vibes/{vibe}/device-actions` — create; `sort_order` appended to end when omitted, `delay_seconds` defaults to 0
- `POST   /api/vibes/{vibe}/device-actions/reorder` — `ordered_ids` → `sort_order` 0,1,2…; returns ordered resources
- `PATCH  /api/vibes/{vibe}/device-actions/{action}` — partial update; action must belong to vibe (else 404)
- `DELETE /api/vibes/{vibe}/device-actions/{action}` — 204; action must belong to vibe (else 404)

**Phase 7A notes:** Authorization reuses `VibePolicy` (`view` for index, `update` for mutations) — cross-user vibe access returns **403**; an action that exists but belongs to a different vibe returns **404** via an explicit ownership guard. Device ownership is enforced in the FormRequest `after()` hook (foreign `device_id` → 422), matching the `StoreDeviceRequest` pattern. Only MVP action types (`turn_on`, `turn_off`, `toggle`) are accepted. **No execution engine, queue jobs, Scheduler changes, or Home Assistant calls were added** — a dedicated test asserts `Bus::assertNothingDispatched()` and `Http::assertNothingSent()` on store. Validation: `php artisan test` → 489 passing, `--filter=SmartHome` → 191 passing, `--filter=VibeDeviceActionApiTest` → 28 passing, `pint --test` clean.

---

## Phase 8 — Async execution foundation

| ID | Task | Status | Reference |
| --- | --- | --- | --- |
| P8-1 | **`SmartHomeActionJob`** queue job (stub — logs intent, no HA call) | **Done** | `back_vibes/app/Jobs/SmartHome/SmartHomeActionJob.php` |
| P8-2 | `POST /api/vibes/{vibe}/smart-home/dispatch` trigger endpoint + `VibeSmartHomeDispatchService` + mobile fire-and-forget hook | **Done** | `back_vibes/app/Http/Controllers/Api/VibeSmartHomeDispatchController.php`, `back_vibes/app/SmartHome/Services/VibeSmartHomeDispatchService.php`, `front_vibes/src/services/smart-home-dispatch.service.ts` |
| P8-3 | Pest: assert job dispatched per action, sort_order respected, 401/403, no HA HTTP; job: graceful missing action, no adapter call, logs intent | **Done** | `tests/Feature/SmartHome/VibeSmartHomeDispatchApiTest.php`, `tests/Feature/SmartHome/SmartHomeActionJobTest.php`, `front_vibes/src/services/__tests__/smart-home-dispatch.service.test.ts` |
| P8-4 | Queue `smart-home`, timeout 30s, tries 3 documented in `config/smart_home.php` `queue` key | **Done** | `back_vibes/config/smart_home.php` |

**Branch:** `feature/smart-home-async-foundation`

**Phase 8 implementation notes:**

- `SmartHomeActionJob` — queue `smart-home`, timeout 30 s, tries 3. Phase 8 stub: loads action + logs intent only. Gracefully skips missing/deleted actions. No HA call, no HTTP.
- `VibeSmartHomeDispatchService` — loads `vibe_device_actions` ordered by `sort_order`, dispatches one job per action, returns `SmartHomeDispatchResult` DTO (vibe_id, dispatched, skipped, action_ids). Skips actions whose device has been deleted.
- `POST /api/vibes/{vibe}/smart-home/dispatch` — single-action invokable controller, authorises via `VibePolicy::view`, delegates to dispatch service, returns JSON summary `{ data: { vibe_id, dispatched, skipped, action_ids } }`.
- Queue config documented in `config/smart_home.php` under key `queue` (name, job_timeout, job_tries) with env overrides `SMART_HOME_QUEUE_NAME`, `SMART_HOME_JOB_TIMEOUT`, `SMART_HOME_JOB_TRIES`. Staging worker must use `--queue=push,smart-home,default` (see [staging-digitalocean.md](../../../architecture/backend/staging-digitalocean.md)).
- Mobile integration: `front_vibes/src/services/smart-home-dispatch.service.ts` — fire-and-forget, skips silently when offline, never throws. Called in `VibePlayerPage.vue#togglePlayback()` immediately after `store.playVibe()` returns `started = true`. Audio path unchanged.
- Validation: `php artisan test --filter=VibeSmartHomeDispatchApiTest` → 11 passing; `--filter=SmartHomeActionJobTest` → 9 passing; `php artisan test` → all passing; `pint --test` clean; `npm run lint`, `npm run typecheck`, `npm run build`, `npm run test:unit` clean.

---

## Phase 9 — Home Assistant real execution

| ID | Task | Status | Reference |
| --- | --- | --- | --- |
| P9-1 | `SmartHomeActionJob` calls **`HomeAssistantAdapter::executeAction()`** via `ProviderAdapterResolver` | **Done** | `back_vibes/app/Jobs/SmartHome/SmartHomeActionJob.php` |
| P9-2 | Resolve `ProviderConnection` from `device.providerConnection`; credentials decrypted only inside adapter (`decryptedCredentials()`), never in job | **Done** | `back_vibes/app/Jobs/SmartHome/SmartHomeActionJob.php`, `HomeAssistantAdapter` |
| P9-3 | Structured log of success / failure / timeout (no DB table this phase — log only) | **Done** | `SmartHomeActionJob::logResult()` |
| P9-4 | Graceful failure — failed `ActionResult` + all `Throwable` caught & logged; never rethrown; audio unaffected | **Done** | `SmartHomeActionJob::handle()` |
| P9-5 | Pest: `Http::fake()` — success 2xx, failure 5xx, connection failure, unsupported action, missing action/device, no credential logging, single adapter-routed call | **Done** | `tests/Feature/SmartHome/SmartHomeActionJobTest.php` (14 tests) |

**Branch:** `feature/smart-home-ha-execution`

**Phase 9 implementation notes:**

- `SmartHomeActionJob` now executes real provider actions: loads action with `device` + `device.providerConnection`, resolves the adapter via `ProviderAdapterResolver::forProvider()`, and calls `executeAction(connection, provider_device_id, action_type, parameters ?? [])`.
- Failure policy (MVP): a failed `ActionResult` (provider 4xx/5xx/timeout) is a **completed failure** — logged, not retried. `UnsupportedSmartHomeActionException` and any unexpected `Throwable` are caught and logged; the job never rethrows, so audio flow and the queue are never disrupted. Queue/timeout/tries unchanged (`smart-home` / 30s / 3).
- Structured log context: `vibe_device_action_id`, `vibe_id`, `device_id`, `provider_connection_id`, `provider`, `provider_device_id`, `action_type`, `success`, `status_code`, `error_message`. Credentials (`access_token` / `encrypted_credentials`) are never logged — verified by test.
- No `action_execution_logs` table introduced (log-only for MVP, per task scope). No new migrations.
- Dispatch endpoint unchanged and still asynchronous: `POST /api/vibes/{vibe}/smart-home/dispatch` only queues jobs (`Bus::fake()` tests assert no inline HA HTTP); HA execution happens exclusively inside the queued job.
- Worker command: `php artisan queue:work --queue=push,smart-home,default --tries=3 --sleep=3 --timeout=90` (shared staging worker; `push` added for FCM — see [staging-digitalocean.md](../../../architecture/backend/staging-digitalocean.md)).
- Validation: `--filter=SmartHomeActionJobTest` → 14 passing; `--filter=VibeSmartHomeDispatchApiTest` → 9 passing; `--filter=SmartHome` → 214 passing; `php artisan test` → 512 passing; `pint --test` clean. Frontend untouched (no mobile changes in Phase 9).

---

## Phase 10 — E2E QA

| ID | Task | Status | Reference |
| --- | --- | --- | --- |
| P10-1 | Staging: add HA provider connection → test connection passes | **Done** (API) | [`plan.md`](plan.md) § Phase 10 |
| P10-2 | Staging: sync → devices appear; re-sync → no duplicates | **Pending** (on-device) | [`ADR-014`](../../../decisions/ADR-014-device-abstraction-and-deduplication.md) |
| P10-3 | Staging: device status badge correct (online / offline / unknown) | **Pending** (on-device) | |
| P10-4 | Staging: attach action to vibe → API persists `vibe_device_action` | **Done** (API) | |
| P10-5 | Staging: trigger play event → `SmartHomeActionJob` dispatched → HA receives call | **Done** (dispatch API) / **Pending** (HA entity) | |
| P10-6 | Security: `GET /api/provider-connections/{id}` → no `access_token` in response | **Done** | |
| P10-7 | Security: cross-user device access → 403 | **Done** (automated tests) | |
| P10-8 | Offline: device mutation UI blocked → toast shown | **Pending** (on-device) | |

**Phase 10 implementation notes:**

- Full QA report: [`docs/qa/smart-home-e2e/summary.md`](../../../qa/smart-home-e2e/summary.md)
- **Verdict:** ✅ CONDITIONAL PASS — all automated checks pass; on-device manual QA pending (no Android device connected in QA session).
- Staging migrations applied manually (BUG-001 resolved); `POST /api/provider-connections` returns 201 (was 500 before migrations).
- Automated: backend 512/512, SmartHome 214/214, pint clean; frontend lint/typecheck clean, 168 unit tests, staging build + APK (33 MB).
- Staging API flow verified with Firebase auth: provider connection create → device CRUD → vibe device action CRUD → dispatch (`dispatched=1, action_ids=[1]`) → delete.
- Pending manual: HA sync UI, device status badges, real HA entity state change, offline toast, invalid-token failure path on device.

---

## Cross-cutting validation tasks

| ID | Task | Status | When |
| --- | --- | --- | --- |
| X-1 | Laravel full test suite on **`back_vibes`** touch | **Done** | Phase 10 QA — 512/512 passing |
| X-2 | **`front_vibes` production build** clean | **Done** | Phase 10 QA — build:staging + APK OK |
| X-3 | Confirm **no Scheduler code modified** | **Done** | Phases 7–9 — no scheduler files touched |
| X-4 | Confirm **`access_token` never in API response** | **Done** | Phase 4 + Phase 10 boundary checks |
| X-5 | Confirm **no duplicate devices** after repeated sync | **Pending** (on-device sync) | Phase 10 QA |
| X-6 | Confirm **audio plays** even when device action fails | **Done** (code) / **Pending** (on-device) | Phase 9 fire-and-forget + job never rethrows |
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
- [x] `SmartHomeActionJob` dispatched for play events and executes via HA adapter (Phase 9)

### Mobile

- [x] Devices tab at root navigation
- [x] Device list with status badges
- [x] Add / delete provider connection (HA, write-only token)
- [x] Device sync — no duplicate entries
- [x] Device action association on vibe detail
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
