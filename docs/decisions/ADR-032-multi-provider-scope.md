# ADR-032: Multi-provider scope and extensibility strategy (v1.4.0)

## Status

**Accepted** — governs **Smart Home multi-provider infrastructure** for release v1.4.0 ([`specs/smart-home/multi-provider/`](../specs/smart-home/multi-provider/)). Blocks Phase 2 tasks T08–T29 until this ADR is merged.

## Date

2026-09-03

## Context

Release **v1.4.0** extends Smart Home from a single production provider (Home Assistant) to a **multi-provider architecture** without shipping commercial brand integrations. Phase 0 produced three read-only audits that establish facts this ADR must not reopen:

| Report | Key findings relevant here |
| --- | --- |
| [`current-state.md`](../specs/smart-home/multi-provider/current-state.md) (T01) | `ProviderAdapter` is a complete contract (`listDevices`, `readStatus`, `executeAction`, `testConnection`) with per-method error policy. Only `HomeAssistantAdapter` exists. `ProviderAdapterResolver` injects that adapter and `match`es on `ProviderType`. `UNIQUE (user_id, provider)` on `provider_connections` blocks a second connection of the same slug. Device dedupe is `(provider_connection_id, provider_device_id)`, not ADR-014's `(user_id, provider, provider_device_id)`. No `capabilities` column or field anywhere. |
| [`coupling-map.md`](../specs/smart-home/multi-provider/coupling-map.md) (T02) | 150 grep hits for Home Assistant; **19 structural** in production. **Zero** provider slug conditionals in controllers, business jobs, scheduler, or Scene/Vibe dispatch paths. Coupling is at the edge: adapter, resolver, enum allow-list, config, mobile connection form. |
| [`adr-conformance.md`](../specs/smart-home/multi-provider/adr-conformance.md) (T03) | Adapter architecture (ADR-012) is implemented. Dedupe key diverges from ADR-014 text but matches v1.1.0 schema-review §4.1. Removing one-connection-per-provider (decision C below) **breaks** the historical equivalence between ADR-014's triple key and the live `(provider_connection_id, provider_device_id)` key — T18/T19 must treat this ADR as the governing rule. |

[ADR-012](ADR-012-smart-home-provider-strategy.md) already forbids direct brand-native integrations (Tuya, Hue, Alexa, …) as platform policy — IXORA integrates with **provider platforms**, not individual OEM clouds.

[ADR-014](ADR-014-device-abstraction-and-deduplication.md) defines device identity at the ADR level; v1.1.0 schema hardening chose a connection-scoped unique key. This ADR resolves the tension when multiple connections per provider slug are allowed (decision C).

**Out of scope for this ADR:** device capabilities model, partial execution policy, cross-provider deduplication — each gets its own ADR (T05, T06, T07).

---

## Decision

### A — Release scope (PO decision — register and justify)

**v1.4.0 delivers multi-provider infrastructure only.** Extensibility is proven by a **fake test provider** (non-production, no external I/O). **No commercial provider** (Tuya, Philips Hue, Alexa, Google Home, Matter — all reserved in `ProviderType` without adapters) is implemented in this release. **No real external integration** ships without explicit PO approval on a separate card.

#### Technical justification

1. **The contract already exists; the gap is proof, not another brand.** T01 shows `ProviderAdapter` is complete with documented error semantics per method. T02 shows business layers (Scenes, Vibes, Scheduler, `SceneActionJob`) already delegate through `ProviderAdapterResolver` with zero provider branches. What v1.4.0 lacks is a **second implementor** that exercises the registry and validates that adding a slug does not touch the business core — not another OAuth/API lifecycle from a commercial cloud.

2. **ADR-012 policy excludes brand-native work anyway.** Even if the PO later prioritized Tuya or Hue, ADR-012 requires a **provider-platform adapter**, not direct OEM integration. v1.4.0 infrastructure (registry, descriptors, multi-connection schema, fake adapter tests) is prerequisite for *any* future platform adapter — commercial or aggregator — and is orthogonal to picking which platform comes next.

3. **Risk and cost control.** T02 quantifies HA coupling at the boundary (~19 structural production lines). A fake provider proves the boundary holds without operational dependencies (tokens, sandboxes, API drift). Commercial adapters belong to post-v1.4.0 cards with their own ADRs per ADR-012's closing rule.

4. **Production provider unchanged in v1.4.0.** Home Assistant remains the only **production** adapter. The fake provider is registered only in `local` / `testing` environments (T10) and must never appear in staging/production config (enforced in T08/T29).

---

### B — Provider registration format

**Use an explicit slug → class registry in config, resolved through the Laravel container.** Reject convention-based class discovery (fragile, hard to test, implicit naming). Reject tagged services as the primary registration mechanism (slug identity would still require a parallel map or adapter method — no fewer files, less visible in diffs).

#### Specification (T08 implements without reopening)

| Component | Responsibility |
| --- | --- |
| **`config/smart_home.php` → `adapters`** | Associative array `slug => FQCN` implementing `ProviderAdapter`. Production v1.4.0: `home_assistant` only. Testing: may include `fake` slug (see decision A). |
| **`App\SmartHome\ProviderAdapterRegistry`** | New final class. Holds the slug map (from config, validated at boot). **No mutable per-request state** — Octane-safe. |
| **`ProviderAdapterRegistry::forSlug(string $slug): ProviderAdapter`** | Looks up FQCN; `$this->container->make($class)`; throws `InvalidArgumentException` if slug unknown or class does not implement `ProviderAdapter`. |
| **`ProviderAdapterRegistry::registeredSlugs(): list<string>`** | Returns sorted slugs from config — used by T09 descriptors and FormRequest allow-lists. |
| **`ProviderAdapterResolver`** | Refactored to **delegate** to `ProviderAdapterRegistry::forSlug()`. Keeps existing public method `forProvider(ProviderType\|string $provider): ProviderAdapter` for call-site stability. **Must not** inject concrete adapters in constructor or contain `match` arms per provider after T08. |
| **`SmartHomeServiceProvider::register()`** | Binds `ProviderAdapterRegistry` as singleton. Binds each adapter FQCN listed in config (production adapters as singletons). Does **not** hard-code provider slugs beyond reading config. |

#### Config shape (illustrative)

```php
// config/smart_home.php
'adapters' => [
    'home_assistant' => \App\SmartHome\Adapters\HomeAssistantAdapter::class,
    // 'fake' => \App\SmartHome\Adapters\FakeProviderAdapter::class, // testing/local only — T10
],
```

#### Registering a new provider (cost model)

After this ADR, adding a **production** provider touches **exactly these backend areas** (see decision D for full paths):

1. **One** new file: `app/SmartHome/Adapters/{Name}Adapter.php`
2. **One** config block: `config/smart_home.php` → `adapters.{slug}` + `providers.{slug}` tuning (timeouts, policy flags)
3. **One** descriptor entry (T09): `config/smart_home.php` → `provider_descriptors.{slug}` or dedicated descriptor file consumed by T09
4. **`ProviderType` enum**: add case if slug not already reserved
5. **Tests**: unit test for adapter + registry resolution; no resolver edit

**Must not require:** editing `ProviderAdapterResolver` match arms, editing controllers/jobs/dispatch services, or editing Scene/Vibe/Scheduler code.

#### Testability (T10)

Tests register the fake adapter by **config override only**:

```php
config(['smart_home.adapters.fake' => FakeProviderAdapter::class]);
app()->singleton(FakeProviderAdapter::class);
```

No test may edit `ProviderAdapterResolver` source to add a slug.

#### Octane

`ProviderAdapterRegistry` stores only immutable `array<string, class-string<ProviderAdapter>>` loaded once. `forSlug()` resolves from container per call — no request-scoped caches on the registry singleton.

---

### C — Multiple connections per provider slug

**Remove** the unique index `uq_provider_connections_user_provider` on `(user_id, provider)`.

A user **may** create **multiple** `provider_connections` rows sharing the same `provider` slug (e.g. two Home Assistant instances: home + office). This aligns with [`schema-review.md`](../specs/smart-home/mvp/schema-review.md) §5.1, which documented this removal as a planned breaking change.

#### Substitute uniqueness rule

**Add** unique index `uq_provider_connections_user_name` on **`(user_id, name)`**.

| Rule | Detail |
| --- | --- |
| **Enforced** | A user cannot have two connections with the same display `name`. |
| **Not enforced** | Duplicate `provider` slug — explicitly allowed. |
| **Not enforced** | Global uniqueness of `config.base_url` — two connections may point at different URLs with different names. |

Rationale: the UI disambiguates connections by user-chosen `name` ("Home HA", "Office HA"). Slug alone is insufficient once multiple instances of the same platform exist.

Migration ownership: **T12** (schema). This ADR states the invariant; T12 implements drop + add.

#### Device dedupe key — explicit coupling to this decision

| Key | Status after decision C |
| --- | --- |
| **ADR-014 text** | `(user_id, provider, provider_device_id)` — **not** the enforced DB/runtime key (pre-existing divergence, T03). |
| **Live schema + upsert (v1.1.0+)** | `UNIQUE (provider_connection_id, provider_device_id)` — **remains authoritative** for v1.4.0. |
| **Equivalence** | While `UNIQUE (user_id, provider)` existed, at most one connection per slug made ADR-014's triple key *functionally* similar to the connection-scoped key. **Removing that index breaks equivalence permanently.** |

**Decision:** v1.4.0 **does not** revert device dedupe to `(user_id, provider, provider_device_id)`. Devices belong to a **connection**, not to a provider slug alone. The same `provider_device_id` string (e.g. HA `light.living_room`) on two connections of the same user ** correctly produces two IXORA device rows** — one per connection.

T18/T19 cite **this ADR** (not ADR-014 alone) as the governing dedupe rule when implementing or documenting schema changes. ADR-014 addendum is **out of scope for v1.4.0** (T07 owns cross-provider dedup ADR if needed).

---

### D — Objective extensibility criterion (T29 literal checklist)

T29 validates a real diff by comparing changed files against these two lists. A path not on either list is a **T29 failure** unless this ADR is amended.

Paths are relative to workspace repo roots (`back_vibes/`, `front_vibes/`).

#### D.1 — Intocável ao adicionar um provider

No file below may change when registering a **second** provider slug (including the v1.4.0 fake provider in tests). T29 treats any diff hunk in these paths as a regression unless the diff is clearly unrelated (e.g. formatting-only on an untouched line — human judgment; prefer zero hunks).

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

**`ixora-admin`**

- *(entire repo — T02 found zero HA coupling; must remain untouched for provider add)*

#### D.2 — Esperado ao adicionar um provider

These paths **must** contain the provider-add diff (or new files under listed directories). T29 expects at least one change here when a provider is added.

**`back_vibes` — Adapter & registry (decision B)**

- `app/SmartHome/Adapters/` — **new file** `{ProviderName}Adapter.php` (required)
- `app/SmartHome/ProviderAdapterRegistry.php` — **created once in T08**; thereafter **immutable** except bugfixes that do not add slug-specific logic
- `app/SmartHome/ProviderAdapterResolver.php` — **refactored once in T08** to delegate; no further provider-specific edits
- `app/Providers/SmartHomeServiceProvider.php` — wiring only; no per-provider hard-coding after T08 (config-driven)
- `config/smart_home.php` — **`adapters.{slug}`** entry + **`providers.{slug}`** block (required)

**`back_vibes` — Provider descriptor (T09)**

- `config/smart_home.php` — **`provider_descriptors.{slug}`** section *(or path defined by T09 spec if split to `config/smart_home/providers/{slug}.php`)*

**`back_vibes` — Slug catalog**

- `app/SmartHome/ProviderType.php` — new enum case when slug not already reserved

**`back_vibes` — Connection API allow-list (descriptor-driven, not HA-hardcoded)**

- `app/Http/Requests/StoreProviderConnectionRequest.php` — **only** if validation switches from `ProviderType::mvpAllowed()` to `ProviderAdapterRegistry::registeredSlugs()` *(one-time T12 change; no per-provider rules)*
- `app/Http/Requests/UpdateProviderConnectionRequest.php` — same one-time change as store

**`back_vibes` — Tests**

- `tests/Unit/SmartHome/{ProviderName}AdapterTest.php` — **new file** (required)
- `tests/Unit/SmartHome/ProviderAdapterRegistryTest.php` — **created in T08/T10**
- `tests/Feature/SmartHome/` — new or extended feature tests for fake/second provider as required by T10/T29

**`back_vibes` — v1.4.0 fake provider (test-only)**

- `app/SmartHome/Adapters/FakeProviderAdapter.php` — **new**; registered only in `testing`/`local` config
- `config/smart_home.php` — `adapters.fake` present only in environment-specific config or guarded by `app()->environment('local', 'testing')` bootstrap (T08/T10)

**`front_vibes` — Connection UX & labels (edge layer per T02)**

- `src/services/provider-connection.service.ts` — extend `ProviderSlug` union / types from descriptor API
- `src/utils/device-status.ts` — `providerLabel()` map entry for new slug
- `src/views/ProviderConnectionFormPage.vue` — provider picker options from descriptor (not hard-coded single option)

**`front_vibes` — Tests**

- `src/services/__tests__/provider-connection.service.test.ts`
- `src/utils/__tests__/device-status.test.ts`

#### D.3 — Schema migrations when adding a provider

**Default: no migration** for a new provider if credentials fit the existing shape:

```json
{ "encrypted_credentials": { "access_token": "<string>" }, "config": { "base_url": "<https-url>" } }
```

Home Assistant and the v1.4.0 fake provider both use this shape.

**Migration required only if** the new provider needs a **genuinely different credential or config schema** that cannot be stored in existing JSON columns (`config`, `encrypted_credentials`) without breaking decryption/validation contracts — e.g. OAuth refresh pair, MQTT username/password tuple, or multi-field certificate bundle requiring new **top-level** columns.

When migration is required:

- It must be scoped to `provider_connections` (or a new provider-specific extension table via FK) — **never** `devices`, `scenes`, `scene_actions`, or `vibes`.
- It requires a **new ADR snippet or amend card** before implementation — not discovered mid-sprint.

T12 owns `provider_connections` constraint migration from decision C; that is **infrastructure**, not per-provider.

---

## Out of scope for v1.4.0

| Topic | Owner |
| --- | --- |
| Device **capabilities** model (column, DTO, adapter method, validation) | T05 ADR |
| **Partial execution** / failure aggregation policy | T06 ADR |
| **Cross-provider deduplication** / ADR-014 addendum | T07 ADR |
| Commercial provider adapters (Tuya, Hue, Alexa, Google Home, Matter, …) | Future PO card + per-provider ADR per ADR-012 |
| `testConnection()` on connection create (ADR-013 divergence) | Not v1.4.0 unless explicitly scheduled |
| `ActionExecutionLog` table | Future release |
| `delay_seconds` honouring at job dispatch | Not v1.4.0 multi-provider scope |
| **`ixora-admin`** Smart Home UI | No admin Smart Home surface today (T02: zero matches) |

---

## Consequences

### Positive

| Outcome | Why it matters |
| --- | --- |
| **Unblocks T08–T29** | Registry format (B), connection rule (C), and diff checklist (D) are specified without ambiguity. |
| **Proves ADR-012 without brand cost** | Fake adapter validates the adapter boundary T01/T02 already inferred. |
| **Multi-instance HA enabled** | Removing `(user_id, provider)` unique allows home + office on same account. |
| **T29 is executable** | Nominal path lists replace subjective "should not couple" review. |

### Negative / tradeoffs

| Tradeoff | Impact |
| --- | --- |
| **ADR-014 text lags schema** | Device dedupe remains connection-scoped; ADR-014 triple key is documentation debt until T07 or a dedicated addendum. |
| **Connection names must be unique** | Users cannot have two connections named identically; acceptable UX cost for disambiguation. |
| **No commercial provider in v1.4.0** | Real-world multi-platform UX validated only with HA + fake until a follow-up card. |
| **Explicit registry vs. auto-discovery** | One config line per provider — predictable, but not zero-config. |

---

## Alternatives considered

| Alternative | Why not chosen |
| --- | --- |
| **Ship Tuya/Hue as proof provider** | Violates PO scope and ADR-012 brand-native prohibition; high OAuth/ops cost unrelated to architecture proof. |
| **Laravel tagged services only** | Still needs slug map; less visible in T29 diffs; harder for T10 to override without container boot order issues. |
| **Convention-based adapter class names** | Fragile rename/refactor; slug mismatches fail at runtime not boot. |
| **Keep `UNIQUE (user_id, provider)`** | Blocks multi-instance HA — primary user story for v1.4.0 connection work. |
| **Revert dedupe to ADR-014 triple key on multi-connection** | Would incorrectly merge devices across two HA instances exposing the same `entity_id`. |

---

## Related docs

| Document | Relationship |
| --- | --- |
| [`specs/smart-home/multi-provider/current-state.md`](../specs/smart-home/multi-provider/current-state.md) | T01 — runtime inventory |
| [`specs/smart-home/multi-provider/coupling-map.md`](../specs/smart-home/multi-provider/coupling-map.md) | T02 — HA coupling quantification |
| [`specs/smart-home/multi-provider/adr-conformance.md`](../specs/smart-home/multi-provider/adr-conformance.md) | T03 — ADR-012…016 conformance |
| [`specs/smart-home/mvp/schema-review.md`](../specs/smart-home/mvp/schema-review.md) | v1.1.0 schema decisions; predicted `(user_id, provider)` removal |
| [ADR-012](ADR-012-smart-home-provider-strategy.md) | Provider adapter architecture — no brand-native integrations |
| [ADR-013](ADR-013-home-assistant-first-provider.md) | HA as first production provider — unchanged |
| [ADR-014](ADR-014-device-abstraction-and-deduplication.md) | Device registry — dedupe text superseded in practice by connection-scoped key (decision C) |

---

When capabilities, partial execution, or cross-provider dedup are decided, create or extend ADRs in T05–T07 and reference this ADR as the v1.4.0 infrastructure anchor.
