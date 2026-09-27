# Vibe Categories — admin catalog and preset-driven user labels

**Status:** Draft for PO review  
**Version:** 0.1  
**Feature ID:** `vibe-categories`  
**Platform:** Laravel API (`back_vibes`) + admin maintainer (`ixora-admin`) + mobile consumer (`ixora-app`; `front_vibes` frozen)

---

## Goal

Introduce a **fixed admin-managed catalog** of vibe categories so that:

- A **user vibe** may belong to **zero or more** categories (N:N).
- The **admin assigns categories to preset vibes**; on **preset import**, the new user vibe **inherits a copy** of the preset’s **active** category links inside the existing import transaction — **one-time copy**, **no live sync** afterward ([ADR-003](../../decisions/ADR-003-preset-import-independent-vibes.md), [ADR-005](../../decisions/ADR-005-no-realtime-preset-sync.md)).
- A vibe **created from scratch** (manual create) has **no categories** and appears only under an **“All”** (Tudo) filter on Home in `ixora-app` (CAT-04).
- **End users never edit** category membership on their vibes.

This is **PO decision D7** in [`kmp-migration-plan.md`](../../architecture/mobile/kmp-migration-plan.md) §0 — the **only exception** to migration rule D2 (`front_vibes` stays feature-frozen and does **not** receive UI or client logic for the new field).

**Success criteria:**

- Change is **additive** and **backward compatible**: existing JSON fields (including legacy `preset_vibes.category`) remain; new `categories` arrays are optional for clients.
- Clients that **ignore unknown keys** (e.g. frozen `front_vibes`, K15 `ixora-app` with `ignoreUnknownKeys`) **keep working** when the API adds `categories`.
- Category membership on user vibes is **only** set at **preset import** (copy) or left empty on manual create — never via user vibe CRUD.
- After import, **changing preset categories does not change** previously imported vibes.

---

## Scope

### In scope

- **`vibe_categories`** catalog table and admin CRUD API.
- **N:N** links: preset ↔ categories, user vibe ↔ categories (separate pivot tables).
- **Admin assignment** of categories to presets (CAT-03 UI; CAT-02 API).
- **Copy active category links** on **`POST /api/preset-vibes/{id}/import`** inside the current DB transaction.
- **`categories`** on **`VibeResource`** and **`PresetVibeResource`** (active categories only, ordered by `sort_order`, eager-loaded to avoid N+1).
- **Data migration (CAT-02):** backfill from legacy **`preset_vibes.category`** string into catalog + pivots; **keep** legacy column and API field during coexistence.

### Out of scope

- **User editing** categories on owned vibes (no API, no mobile UI).
- **Categories on `sounds` or `cover_bundles`** — those entities already expose their own optional **`category`** string columns ([`2026_05_01_000003_create_sounds_table.php`](../../../../back_vibes/database/migrations/2026_05_01_000003_create_sounds_table.php), [`2026_05_18_160000_create_cover_bundles_table.php`](../../../../back_vibes/database/migrations/2026_05_18_160000_create_cover_bundles_table.php)); **unchanged** by this feature.
- **Server-side filtering** of vibes or presets by category (no query params on list endpoints).
- **Per-user custom categories** or community tagging.
- **Automatic translation** of category labels (admin supplies localized names in JSON; clients pick locale).
- **Removing** legacy **`preset_vibes.category`** column (future card after `front_vibes` and `ixora-admin` stop relying on it).
- **Any change** to `front_vibes` (frozen per D7).

---

## Decisions

| # | Decision | Rationale |
| --- | --- | --- |
| **D-1 Catalog** | Table **`vibe_categories`**: `id`; **`slug`** (unique, stable, regex `[a-z0-9-]`, length 2–40, **immutable after create**); **`names`** JSON with required **`en`**, optional **`pt`**, **`fr`**, **`es`** (client picks by app locale, falls back to **`en`**); **`sort_order`** integer (admin-defined); **`is_active`** boolean default **`true`**; timestamps. | Fixed catalog controlled by admin; slug is stable API identifier; localized display names align with multilanguage product direction ([`kmp-migration-plan.md`](../../architecture/mobile/kmp-migration-plan.md) §16.1). *Assumption **A-1** (PO review before CAT-02):* JSON `names` instead of a single `name` column. |
| **D-2 N:N pivots** | Two pivot tables: **`vibe_vibe_categories`** (`vibe_id`, `vibe_category_id`) and **`preset_vibe_vibe_categories`** (`preset_vibe_id`, `vibe_category_id`). Unique pairs; indexes on both FK columns. **FK behaviour:** `cascadeOnDelete()` on **`vibe_id`** / **`preset_vibe_id`** (same as [`vibe_sounds`](../../../../back_vibes/database/migrations/2026_05_01_000004_create_vibe_sounds_table.php) and [`preset_vibe_sounds`](../../../../back_vibes/database/migrations/2026_05_19_120001_create_preset_vibe_sounds_table.php)); **`restrictOnDelete()`** on **`vibe_category_id`** so hard-delete of a category row fails while pivots exist (DB backstop; app still enforces D-8). | Naming follows existing pivots: **`vibe_sounds`** = owner **`vibe`** + related table **`sounds`**; **`preset_vibe_sounds`** = **`preset_vibe`** + **`sounds`**. Here the related catalog table is **`vibe_categories`**, so pivots are **`vibe_vibe_categories`** and **`preset_vibe_vibe_categories`**. The repo today uses **`cascadeOnDelete`** on both sides of sound pivots; category is catalog glue — cascade must not delete user vibes when a category is removed, hence **restrict** on the category FK (no existing `restrictOnDelete()` in migrations today; cover-bundle delete blocking is app-level **409** in [`CoverBundleController::destroy`](../../../../back_vibes/app/Http/Controllers/Api/CoverBundleController.php)). |
| **D-3 Resources** | **`VibeResource`** and **`PresetVibeResource`** add **`categories`**: `[{ id, slug, names, sort_order }]` — **active only**, ordered by **`sort_order`**, embedded via Eloquent relation + **`whenLoaded`** / conditional load (same pattern as nested **`cover_bundle`** and **`sounds`** today). Index/show controllers eager-load **`vibeCategories`** / **`vibeCategories`** (or equivalent relation name) on **`GET /api/vibes`** and **`GET /api/preset-vibes`** to avoid N+1. | Matches current resource style ([`VibeResource.php`](../../../../back_vibes/app/Http/Resources/VibeResource.php), [`PresetVibeResource.php`](../../../../back_vibes/app/Http/Resources/PresetVibeResource.php)); list endpoints already eager-load relations in [`VibeController::index`](../../../../back_vibes/app/Http/Controllers/Api/VibeController.php) and [`PresetVibeController::index`](../../../../back_vibes/app/Http/Controllers/Api/PresetVibeController.php). |
| **D-4 Catalog API** | Mirror **`cover-bundles`** / **`preset-vibes`**: under **`firebase.auth`**: **`GET /api/vibe-categories`**, **`GET /api/vibe-categories/{id}`** (active only for regular users; **`include_inactive=1`** when **`$request->user()->isAdminApproved()`**, same boolean gate as [`PresetVibeController::index`](../../../../back_vibes/app/Http/Controllers/Api/PresetVibeController.php):29–34). Writes **`POST`**, **`PATCH`/`PUT`**, **`DELETE`** inside **`admin.approved`** group like [`routes/api.php`](../../../../back_vibes/routes/api.php):62–85. | Confirmed route layout: authenticated reads at lines 62–67; admin writes nested at 69–85. No separate `IndexPresetVibeRequest` — list filtering uses inline **`Request`** on the controller. |
| **D-5 Preset assignment** | **`PUT /api/preset-vibes/{preset_vibe}/categories`** with body **`{ "category_ids": [1, 2, ...] }`** — **full replace** of preset↔category links in a transaction (same product semantics as **`PUT …/sounds`**). **Not** bundled into **`store`/`update`**. | Layers use a dedicated sync endpoint ([`PresetVibeController::syncSounds`](../../../../back_vibes/app/Http/Controllers/Api/PresetVibeController.php):169–191): delete-all + insert in transaction; metadata **`store`/`update`** only touch scalar fields (lines 50–95). Categories are N:N like sounds, not a single scalar (legacy **`category`** string remains for coexistence only). |
| **D-6 Import copy** | Inside existing **`DB::transaction`** in **`PresetVibeController::import`** ([lines 110–154](../../../../back_vibes/app/Http/Controllers/Api/PresetVibeController.php)), after creating the vibe and attaching sounds, **attach pivot rows** for each **active** category linked to the preset. **No `preset_vibe_id`** (or other live FK) on the user vibe. Manual **`VibeController::store`** creates vibes with **zero** category links. | ADR-003/005: import is one-time copy; tests today assert independent rows and no preset FK ([`PresetVibeImportApiTest.php`](../../../../back_vibes/tests/Feature/PresetVibeImportApiTest.php)). |
| **D-7 User cannot assign** | **`StoreVibeRequest`** / **`UpdateVibeRequest`** do **not** validate **`categories`** or **`category_ids`**; controllers use **`$request->validated()`** only ([`VibeController::store`](../../../../back_vibes/app/Http/Controllers/Api/VibeController.php):38–40). **`Vibe`** **`#[Fillable]`** lists no category fields ([`Vibe.php`](../../../../back_vibes/app/Models/Vibe.php):12). Extra JSON keys are dropped by **`validated()`**. CAT-02 may add **`prohibited`** rules for clarity. | Defense in depth: even if a client sends category IDs, they never reach mass assignment. |
| **D-8 Archive, don’t delete in use** | Category referenced by any preset or user vibe pivot **cannot** be hard-deleted; admin sets **`is_active = false`**. Inactive categories are **omitted** from **`categories`** in resources and from default catalog lists; **pivot rows remain** (historical/imported vibes keep internal links but clients only see active entries in the embedded array). **`DELETE`** when pivots exist returns **409** with the same **JSON message pattern** as cover bundle delete ([`CoverBundleController::destroy`](../../../../back_vibes/app/Http/Controllers/Api/CoverBundleController.php):88–95). **`DELETE`** with no pivots removes the row. | Aligns with “resource in use” behaviour already shipped for cover bundles (409 + human-readable **`message`**). |
| **D-9 Legacy column** | Keep **`preset_vibes.category`** (nullable string, max 100, free text) — created in [`2026_05_19_120000_create_preset_vibes_table.php`](../../../../back_vibes/database/migrations/2026_05_19_120000_create_preset_vibes_table.php):18 and still exposed as **`category`** in [`PresetVibeResource`](../../../../back_vibes/app/Http/Resources/PresetVibeResource.php):32. CAT-02 migration **backfills** distinct trimmed non-empty values into **`vibe_categories`** + **`preset_vibe_vibe_categories`** (slug via slugify + numeric suffix on collision; **`names.en`** = original string; **`sort_order`** by alphabetical order of distinct values). **Dropping the column is out of scope** for CAT-02. | `front_vibes` / `ixora-admin` still send/read legacy **`category`** today ([`PresetVibeForm.vue`](../../../../ixora-admin/components/PresetVibeForm.vue):52,568; [`preset-vibe.service.ts`](../../../../ixora-admin/services/api/preset-vibe.service.ts):164–175). |
| **D-10 Client-side filter** | **No** server query parameter to filter vibes by category. Mobile loads **`GET /api/vibes`** (and optionally **`GET /api/vibe-categories`**) and filters locally (works offline). Which Home chips to show (all active catalog categories vs only categories present on the user’s vibes) is **UX for CAT-04**; this spec only requires both datasets to be available. | Matches device-side playback/filter patterns; server stores config only for schedules, not vibe list filtering. |

---

## Data model

### `vibe_categories` (new)

| Column | Type | Notes |
| --- | --- | --- |
| `id` | bigint PK | |
| `slug` | string(40) | Unique index; immutable after create; `[a-z0-9-]`, length 2–40 |
| `names` | json | Object; **`en`** required; **`pt`**, **`fr`**, **`es`** optional |
| `sort_order` | integer | Admin ordering for chips/lists; ties allowed (stable secondary sort by `id` in API) |
| `is_active` | boolean | Default `true` |
| `created_at`, `updated_at` | timestamps | |

Indexes: unique on **`slug`**; index on **`(is_active, sort_order)`** for list queries.

### `vibe_vibe_categories` (new pivot)

| Column | Notes |
| --- | --- |
| `id` | Optional surrogate PK (match `preset_vibe_sounds` style) |
| `vibe_id` | FK → `vibes.id`, **`cascadeOnDelete`** |
| `vibe_category_id` | FK → `vibe_categories.id`, **`restrictOnDelete`** |
| `created_at` | Optional |

Unique: **`(vibe_id, vibe_category_id)`**. Indexes on both FKs.

### `preset_vibe_vibe_categories` (new pivot)

| Column | Notes |
| --- | --- |
| `id` | Optional surrogate PK |
| `preset_vibe_id` | FK → `preset_vibes.id`, **`cascadeOnDelete`** |
| `vibe_category_id` | FK → `vibe_categories.id`, **`restrictOnDelete`** |
| `created_at`, `updated_at` | Optional (align with `preset_vibe_sounds` timestamps if desired) |

Unique: **`(preset_vibe_id, vibe_category_id)`**. Indexes on both FKs.

### Unchanged (reference)

| Artifact | Relevant columns |
| --- | --- |
| **`preset_vibes`** | **`category`** nullable string(100) — legacy coexistence ([migration](../../../../back_vibes/database/migrations/2026_05_19_120000_create_preset_vibes_table.php):18) |
| **`vibes`** | No category columns — membership only via pivot |
| **`sounds`**, **`cover_bundles`** | Own **`category`** string fields — out of scope |

---

## API contract

Base URL prefix: **`/api`**. All routes below require **`firebase.auth`** + **`throttle:api`** unless noted ([`routes/api.php`](../../../../back_vibes/routes/api.php):39–67).

### `GET /api/vibe-categories`

| | |
| --- | --- |
| **Auth** | Authenticated user |
| **Query** | **`include_inactive=1`** — only when user **`isAdminApproved()`**; otherwise ignore / active-only |
| **Response** | **200** — JSON array or `{ "data": [...] }` per existing resource collection convention |
| **Ordering** | **`sort_order`**, then **`id`** |

### `GET /api/vibe-categories/{id}`

| | |
| --- | --- |
| **Auth** | Authenticated user |
| **Inactive** | **404** for non-admin (same as [`PresetVibeController::show`](../../../../back_vibes/app/Http/Controllers/Api/PresetVibeController.php):41–43) |
| **Response** | **200** — single **`VibeCategoryResource`** (shape mirrors embedded category objects in D-3) |

### Admin — `POST /api/vibe-categories`

| | |
| --- | --- |
| **Auth** | **`admin.approved`** |
| **Body** | `{ "slug", "names": { "en": "...", ... }, "sort_order?", "is_active?" }` |
| **Response** | **201** + resource |

### Admin — `PATCH|PUT /api/vibe-categories/{id}`

| | |
| --- | --- |
| **Auth** | **`admin.approved`** |
| **Body** | Partial update; **`slug`** not mutable |
| **Response** | **200** |

### Admin — `DELETE /api/vibe-categories/{id}`

| | |
| --- | --- |
| **Auth** | **`admin.approved`** |
| **In use** | **409** `{ "message": "…" }` — same pattern as cover bundle ([`CoverBundleController::destroy`](../../../../back_vibes/app/Http/Controllers/Api/CoverBundleController.php):93–95) |
| **Unused** | **200** or **204** + confirmation message (match sibling catalog controllers) |

### Admin — `PUT /api/preset-vibes/{preset_vibe}/categories`

| | |
| --- | --- |
| **Auth** | **`admin.approved`** |
| **Body** | `{ "category_ids": [1, 3] }` — each id must exist; **replaces** all preset category links |
| **Response** | **200** — **`PresetVibeResource`** with **`categories`** loaded |
| **Validation** | Distinct ids; reject unknown ids with **422** |

### Unchanged user vibe routes

| Route | Category behaviour |
| --- | --- |
| **`GET /api/vibes`**, **`GET /api/vibes/{id}`** | Include **`categories`** when relation loaded |
| **`POST /api/vibes`**, **`PATCH /api/vibes/{id}`** | Ignore / prohibit category fields (D-7) |
| **`POST /api/preset-vibes/{id}/import`** | Extends transaction to copy active preset categories (D-6) |

### Example — category object (embedded or standalone)

```json
{
  "id": 3,
  "slug": "sleep",
  "names": {
    "en": "Sleep",
    "pt": "Sono",
    "fr": "Sommeil",
    "es": "Sueño"
  },
  "sort_order": 10
}
```

### Example — `PresetVibeResource` (after CAT-02)

```json
{
  "id": 12,
  "name": "Storm Kit",
  "category": "Weather",
  "categories": [
    { "id": 3, "slug": "weather", "names": { "en": "Weather" }, "sort_order": 20 }
  ],
  "is_active": true
}
```

Legacy **`category`** string remains during coexistence (D-9).

### Example — `VibeResource` (after CAT-02)

```json
{
  "id": 501,
  "name": "Storm Kit",
  "categories": [
    { "id": 3, "slug": "weather", "names": { "en": "Weather" }, "sort_order": 20 }
  ],
  "sounds_count": 2
}
```

### Resource shapes — before / after (minimal)

| Resource | Before (today) | After (CAT-02) |
| --- | --- | --- |
| **`VibeResource`** | No category fields ([`VibeResource.php`](../../../../back_vibes/app/Http/Resources/VibeResource.php):17–35) | Adds optional **`categories`** array (empty `[]` when none) |
| **`PresetVibeResource`** | **`category`** string + no **`categories`** ([`PresetVibeResource.php`](../../../../back_vibes/app/Http/Resources/PresetVibeResource.php):32–33) | Adds **`categories`** array; keeps **`category`** |

---

## Import behaviour

Executed inside the existing transaction in **`PresetVibeController::import`** ([`PresetVibeController.php`](../../../../back_vibes/app/Http/Controllers/Api/PresetVibeController.php):110–154):

1. **Guard:** preset must be **`is_active`** (unchanged — **404** otherwise).
2. **Load** preset with **`presetVibeSounds`** (and **`coverBundle`** as today).
3. **Begin transaction** (already wrapped).
4. **Create `vibes` row** — copy name, description, visual URLs from cover bundle (unchanged).
5. **Attach `vibe_sounds`** from each **`preset_vibe_sounds`** row (unchanged).
6. **New:** Load preset’s category pivots where linked **`vibe_categories.is_active = true`**; **`attach`** each to the new vibe on **`vibe_vibe_categories`** (insert-only copy).
7. **Commit.**
8. **Post-commit:** **`load(['sounds'])`**, **`loadCount('sounds')`**, return **`VibeResource` 201** (extend eager load to include **`categories`** for response consistency).

**Not copied:** inactive category links; legacy **`preset_vibes.category`** string (only structured catalog links). **No update path** when admin later changes preset categories.

---

## Compatibility

| Client | Behaviour |
| --- | --- |
| **`front_vibes` (frozen)** | Does not read **`categories`**; continues to use preset **`category`** string where implemented. Unknown JSON keys ignored by typical parsing. |
| **`ixora-app` (K15+)** | **`Json { ignoreUnknownKeys = true }`** on API client ([`IxoraApiClient.kt`](../../../../ixora-app/shared/src/commonMain/kotlin/app/ixora/shared/data/remote/IxoraApiClient.kt):90). CAT-04 adds optional **`categories`** to domain models; until then, extra field is ignored. Existing vibe list fixtures remain valid without **`categories`**. |
| **`ixora-admin`** | CAT-03: CRUD catalog + multi-select on preset form replaces free-text **`category`** for new workflow; legacy field still returned until column removal. |

---

## Security & authorization

| Area | Rule |
| --- | --- |
| **Middleware** | Reads: **`firebase.auth`**. Catalog/preset writes: **`admin.approved`** (same as preset/cover routes in [`routes/api.php`](../../../../back_vibes/routes/api.php):69–85). |
| **Policies** | New **`VibeCategoryPolicy`**: mirror **`CoverBundlePolicy`** / **`PresetVibePolicy`** — any authenticated user **`view*`**, mutations require **`isAdminApproved()`** ([`PresetVibePolicy.php`](../../../../back_vibes/app/Policies/PresetVibePolicy.php):28–40). Preset category sync: admin only. |
| **User vibes** | **`VibePolicy`** ownership unchanged ([`VibePolicy.php`](../../../../back_vibes/app/Policies/VibePolicy.php)); users never mutate category pivots. |
| **Validation** | Dedicated Form Requests per write endpoint (project standard); no trusted category ids from user vibe bodies. |
| **PII / storage** | Category labels are catalog metadata only; **no Spaces** keys or uploads. |

---

## Failure & edge cases

| Case | Expected behaviour |
| --- | --- |
| **Category archived (`is_active = false`)** | Hidden from **`categories`** in resources and default catalog lists; pivots remain. |
| **Import while preset linked to archived category** | Copy step skips inactive categories; imported vibe gets only active links. |
| **Preset with no categories** | Import creates vibe with empty **`categories`**; Home shows only under “All”. |
| **Duplicate slug on create** | **422** validation error (unique constraint). |
| **`names.en` missing on write** | **422** validation error. |
| **Delete category with pivots** | **409** with message pattern like cover bundle in use. |
| **Delete unused category** | Success; row removed. |
| **Equal `sort_order` values** | Stable tie-break by **`id`** in API ordering. |
| **Concurrent admin edits** | Last **`PUT …/categories`** wins (same as sound sync replace-all semantics). |
| **Legacy `category` string without catalog link** | Backfill in CAT-02; until backfill runs, **`categories`** may be empty while **`category`** string still present. |

---

## Testing requirements for CAT-02 (Pest)

Objective checks for **`back_vibes`**:

1. **Catalog CRUD + auth:** admin can create/update/deactivate/delete (unused); regular authenticated user can **GET** active; non-admin cannot **POST/PATCH/DELETE**; unauthenticated **401** on all.
2. **`slug` unique** and **immutable** on update (attempt to change slug → **422** or ignored per implementation spec).
3. **N:N pivots:** attach/detach via preset sync; deleting vibe removes **`vibe_vibe_categories`** rows (cascade).
4. **`PUT /api/preset-vibes/{id}/categories`:** replace-all semantics; invalid **`category_ids`** → **422**.
5. **Import copies only active categories** into **`vibe_vibe_categories`**; assert counts and ids.
6. **No live link:** after import, change preset categories → imported vibe pivots **unchanged** (ADR-003/005).
7. **`VibeResource` / `PresetVibeResource`:** embed **`categories`**; inactive categories excluded; order by **`sort_order`**.
8. **N+1:** **`GET /api/vibes`** and **`GET /api/preset-vibes`** with categories — assert bounded query count (same class of test as other list endpoints with eager loads).
9. **Manual vibe create** → **`categories`** empty in JSON and no pivot rows.
10. **User cannot assign:** **`POST/PATCH /api/vibes`** with **`category_ids`** → no pivot changes (and **422** if **`prohibited`** added).
11. **Legacy field:** **`preset_vibes.category`** still returned on **`PresetVibeResource`** after backfill.
12. **Backfill migration test:** distinct values, duplicates, empty/whitespace skipped, slug collision suffix, presets linked correctly.
13. **Delete category in use** → **409** message pattern consistent with cover bundle test expectations.

Extend **`PresetVibeImportApiTest`** (or sibling feature tests) rather than replacing existing import coverage ([`PresetVibeImportApiTest.php`](../../../../back_vibes/tests/Feature/PresetVibeImportApiTest.php)).

---

## Task breakdown

| Card | Repo | Depends on | Deliverable |
| --- | --- | --- | --- |
| **CAT-01** | `ixora-infra` | PO D7 | This spec (contract source of truth) |
| **CAT-02** | `back_vibes` | CAT-01 approved | Migrations, models, policies, requests, controllers, resources, import transaction, backfill, Pest suite |
| **CAT-03** | `ixora-admin` | CAT-02 deployed or staged | Catalog CRUD UI; preset form multi-select categories; admin warning if many active categories (A-2); stop relying on free-text **`category`** for new edits |
| **CAT-04** | `ixora-app` | CAT-02 API available | Domain **`categories`** field; Home category chips + client-side filter (A-3 UX) |

Order: **CAT-01 → CAT-02 → CAT-03** and **CAT-04** (CAT-04 can parallel CAT-03 once API is stable; both need CAT-02).

---

## Assumptions to confirm with the PO before CAT-02

| ID | Assumption |
| --- | --- |
| **A-1** | Localized **`names`** JSON (en required) vs single display name column. |
| **A-2** | Soft guideline ~**8 active** categories for Home chip layout (Design System); admin UI shows a **warning** in CAT-03 — not a hard server limit. |
| **A-3** | Home chips: all active catalog categories vs only categories present on the user’s vibe list (CAT-04 UX). |
| **A-4** | Timeline to **drop `preset_vibes.category`** after frozen `front_vibes` and admin no longer need it. |

---

## Sources

Files read to confirm facts cited in this spec (workspace-relative paths).

| File | What it confirmed |
| --- | --- |
| [`back_vibes/routes/api.php`](../../../../back_vibes/routes/api.php) | Auth groups; read routes for cover bundles / preset vibes (62–67); admin writes including **`PUT preset-vibes/{id}/sounds`** (69–85). |
| [`back_vibes/app/Http/Controllers/Api/PresetVibeController.php`](../../../../back_vibes/app/Http/Controllers/Api/PresetVibeController.php) | **`include_inactive`** gate (29–34); import transaction scope (110–154); **`syncSounds`** replace-all (169–191); scalar **`category`** on store/update (58, 75). |
| [`back_vibes/app/Http/Controllers/Api/VibeController.php`](../../../../back_vibes/app/Http/Controllers/Api/VibeController.php) | User vibe CRUD uses **`validated()`** + **`user_id`** scoping (23–29, 38–40). |
| [`back_vibes/app/Http/Controllers/Api/CoverBundleController.php`](../../../../back_vibes/app/Http/Controllers/Api/CoverBundleController.php) | **`include_inactive`** pattern (28–33); delete blocked **409** + **`message`** (88–95). |
| [`back_vibes/app/Http/Resources/VibeResource.php`](../../../../back_vibes/app/Http/Resources/VibeResource.php) | Current vibe JSON fields; no categories yet (17–35). |
| [`back_vibes/app/Http/Resources/PresetVibeResource.php`](../../../../back_vibes/app/Http/Resources/PresetVibeResource.php) | Legacy **`category`** field (32); **`whenLoaded`** patterns (26–35). |
| [`back_vibes/app/Models/Vibe.php`](../../../../back_vibes/app/Models/Vibe.php) | **`#[Fillable]`** list without categories (12); **`vibe_sounds`** pivot name (36). |
| [`back_vibes/app/Models/PresetVibe.php`](../../../../back_vibes/app/Models/PresetVibe.php) | Legacy **`category`** fillable (17); **`preset_vibe_sounds`** relation (41–49). |
| [`back_vibes/app/Http/Requests/StorePresetVibeRequest.php`](../../../../back_vibes/app/Http/Requests/StorePresetVibeRequest.php) | Legacy **`category`** validation max 100 (25). |
| [`back_vibes/app/Http/Requests/StoreVibeRequest.php`](../../../../back_vibes/app/Http/Requests/StoreVibeRequest.php) | No category fields in rules (21–26). |
| [`back_vibes/app/Http/Requests/UpdateVibeRequest.php`](../../../../back_vibes/app/Http/Requests/UpdateVibeRequest.php) | No category fields in rules (21–26). |
| [`back_vibes/database/migrations/2026_05_19_120000_create_preset_vibes_table.php`](../../../../back_vibes/database/migrations/2026_05_19_120000_create_preset_vibes_table.php) | Legacy **`category`** column (18). |
| [`back_vibes/database/migrations/2026_05_01_000004_create_vibe_sounds_table.php`](../../../../back_vibes/database/migrations/2026_05_01_000004_create_vibe_sounds_table.php) | Pivot naming + **`cascadeOnDelete`** on vibe/sound FKs (41–44). |
| [`back_vibes/database/migrations/2026_05_19_120001_create_preset_vibe_sounds_table.php`](../../../../back_vibes/database/migrations/2026_05_19_120001_create_preset_vibe_sounds_table.php) | **`preset_vibe_sounds`** pivot + cascades (15–16). |
| [`back_vibes/tests/Feature/PresetVibeImportApiTest.php`](../../../../back_vibes/tests/Feature/PresetVibeImportApiTest.php) | Import creates independent user vibe; uses legacy **`category`** on preset seed (59). |
| [`back_vibes/app/Policies/VibePolicy.php`](../../../../back_vibes/app/Policies/VibePolicy.php) | Ownership gates for user vibes (19–36). |
| [`back_vibes/app/Policies/PresetVibePolicy.php`](../../../../back_vibes/app/Policies/PresetVibePolicy.php) | Admin-only mutations (28–40). |
| [`ixora-admin/components/PresetVibeForm.vue`](../../../../ixora-admin/components/PresetVibeForm.vue) | Free-text **`category`** input (52, 568). |
| [`ixora-admin/services/api/preset-vibe.service.ts`](../../../../ixora-admin/services/api/preset-vibe.service.ts) | API payload includes **`category`** (164–175); **`syncPresetVibeSounds`** via **PUT** (238–246). |
| [`ixora-infra/docs/decisions/ADR-003-preset-import-independent-vibes.md`](../../decisions/ADR-003-preset-import-independent-vibes.md) | Copy-on-import; no preset FK on user vibe. |
| [`ixora-infra/docs/decisions/ADR-005-no-realtime-preset-sync.md`](../../decisions/ADR-005-no-realtime-preset-sync.md) | Preset edits do not mutate imported vibes. |
| [`ixora-infra/docs/architecture/mobile/kmp-migration-plan.md`](../../architecture/mobile/kmp-migration-plan.md) | **D7** decision (§0); multilanguage §16.1 (741–745). |
| [`ixora-infra/docs/specs/preset-vibes/spec.md`](../preset-vibes/spec.md) | Spec house format; legacy **`category`** on presets (135). |
| [`ixora-infra/docs/specs/preset-vibes/import/spec.md`](../preset-vibes/import/spec.md) | Import transaction scope and success criteria. |
| [`ixora-app/shared/src/commonMain/kotlin/app/ixora/shared/data/remote/IxoraApiClient.kt`](../../../../ixora-app/shared/src/commonMain/kotlin/app/ixora/shared/data/remote/IxoraApiClient.kt) | **`ignoreUnknownKeys = true`** for API JSON (90). |

---

## Related documents

- [Preset vibes](../preset-vibes/spec.md)
- [Import preset vibe](../preset-vibes/import/spec.md)
- [ADR-003 — Preset import independent vibes](../../decisions/ADR-003-preset-import-independent-vibes.md)
- [ADR-005 — No realtime preset sync](../../decisions/ADR-005-no-realtime-preset-sync.md)
- [KMP migration plan — D7](../../architecture/mobile/kmp-migration-plan.md)
