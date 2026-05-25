# Preset Vibes — curated ambient template catalog

**Status:** Active feature specification (source of truth)  
**Version:** 1.0 (consolidated; matches current `back_vibes` + `front_vibes` + `ixora-admin` implementation)  
**Feature ID:** `preset-vibes`  
**Platform:** Mobile catalog consumer (`front_vibes`); admin maintainer (`ixora-admin`); Laravel API shared contract

---

## Goal

Define the **preset vibe catalog domain**: **admin-managed ambient templates** (`preset_vibes` + `preset_vibe_sounds`) that **authenticated mobile users browse read-only** and **import** into **independent user-owned vibes** — without marketplace features, live sync to imports, or client-side catalog writes.

**Success criteria:**

- **`preset_vibes`** are **catalog entities** — not user-owned, not playable directly.
- Templates optionally reference **`cover_bundle_id`** for visuals; layers reference **catalog `sounds` only**.
- Mobile **`GET /api/preset-vibes`** and **`GET /api/preset-vibes/{id}`** return **`PresetVibeResource`** with embedded **`cover_bundle`** and **`sounds`** when eager-loaded.
- **Import** ([`import/spec.md`](import/spec.md)) copies template → **`vibes` + `vibe_sounds`** with **no FK back** to preset.
- **Playback** uses the **imported user vibe** ([`../vibes/playback-runtime/spec.md`](../vibes/playback-runtime/spec.md)) — never a live preset binding.
- **Changing a preset later does not mutate** previously imported vibes.
- **No uploads from mobile**; **no direct Spaces access**; URLs are **HTTPS strings** from API JSON only.

---

## Scope

### In scope

- **Catalog model:** **`preset_vibes`**, **`preset_vibe_sounds`**, optional **`cover_bundles`** FK.
- **Mobile read:** list + detail for **active** presets only.
- **Import:** **`POST /api/preset-vibes/{id}/import`** — detailed in [`import/spec.md`](import/spec.md).
- **Admin write (shipped):** **`POST/PATCH/PUT/DELETE /api/preset-vibes`**, **`PUT …/sounds`** sync — **`admin.approved`** middleware; maintained via **`ixora-admin`**.
- **Serialization:** **`PresetVibeResource`**, **`PresetVibeSoundResource`**, **`whenLoaded`** / conditional embed rules.
- **Active-only filtering** for regular users; **`include_inactive`** for approved admins on list.
- **Visual presentation on mobile** via nested **`cover_bundle`** + **`presetForCardArtwork`** → **`artwork.ts`**.

### Out of scope

- **Manual vibe create** ([`../vibes/create-vibe/spec.md`](../vibes/create-vibe/spec.md)) — empty vibe + separate layer attach.
- **User vibe update** ([`../vibes/update-vibe/spec.md`](../vibes/update-vibe/spec.md)).
- **Manage user vibe sounds** ([`../vibes/manage-vibe-sounds/spec.md`](../vibes/manage-vibe-sounds/spec.md)) — applies to **imported** vibes after import.
- **Preset marketplace, likes, favorites, community uploads, AI generation**.
- **Preset version sync engine** — no propagation to imported vibes.
- **Collaborative or public preset editing** by end users.
- **Mobile preset CRUD** — not shipped.
- **Multipart / upload pipeline** on preset endpoints — JSON only.
- **Purchase, subscription, or entitlement gates** on import.

---

## Actors

| Actor | Role |
| --- | --- |
| **End user** | Browses active presets; imports template to My Vibes (read-only on catalog). |
| **Mobile app (`front_vibes`)** | **`GET`** list/detail; **`POST`** import; displays layers and cover art from API JSON. |
| **Approved admin** | Creates/updates/deletes presets and syncs **`preset_vibe_sounds`** via **`ixora-admin`** + admin API routes. |
| **Laravel API (`back_vibes`)** | Persists catalog; filters **`is_active`**; runs import transaction; returns JsonResources. |
| **`cover_bundles`** | Optional visual package linked by **`cover_bundle_id`** — not copied onto preset row. |
| **`sounds`** | Catalog audio referenced by **`preset_vibe_sounds.sound_id`** — never created by preset read/import. |
| **DigitalOcean Spaces / CDN** | Stores catalog object bytes — **Laravel-only writes** via admin upload pipeline. |

---

## User Journey

### Mobile — browse and import (primary)

1. User signs in (Firebase → **`POST /api/auth/sync`** per [`front-vibes-auth-core.md`](../../standards/front-vibes-auth-core.md)).
2. User opens **Presets** tab → **`PresetVibesPage`** at **`/presets`**.
3. Mobile **`GET /api/preset-vibes`** → active presets ordered by **`name`**.
4. User taps a card → **`PresetVibeDetailPage`** at **`/presets/:id`** → **`GET /api/preset-vibes/{id}`**.
5. Detail shows metadata, read-only layer list, hero from **`cover_bundle`** URLs.
6. User taps **Import to My Vibes** → **`POST /api/preset-vibes/{id}/import`** → new **`VibeResource`** **201**.
7. Mobile refreshes **`GET /api/vibes`**, toast, navigates to **`/vibes`**.
8. User **plays** or **edits** the imported vibe like any manual vibe — preset is no longer involved.

### Admin — maintain catalog (separate)

1. Approved admin opens **`ixora-admin`** → **Preset vibes** list.
2. Admin creates/edits preset metadata (**`cover_bundle_id`**, category, tags, **`is_active`**).
3. Admin syncs layers via **`PUT /api/preset-vibes/{id}/sounds`** (replace-all transaction).
4. When **`is_active`**, preset appears in mobile catalog; inactive presets return **404** on mobile show/import.

**Not in journey:** end-user preset editing, favorites, re-sync imported vibes when preset changes.

---

## Related Domain Model

```
cover_bundles ◄── cover_bundle_id ── preset_vibes (catalog template)
                        │
                        │ preset_vibe_sounds (layer templates)
                        ▼
                    sounds (catalog — file_url)

POST /import  ──►  vibes (user-owned, NO preset_vibe_id)
                      │
                      │ vibe_sounds (copied pivot)
                      ▼
                   sounds (same catalog rows)
```

### Preset ≠ Vibe

| Aspect | **`preset_vibes`** | **`vibes`** (user-owned) |
| --- | --- | --- |
| Ownership | **Catalog** — no **`user_id`** | **`user_id`** = authenticated user |
| Purpose | Curated **template** for import | Personal **composition** for play/edit |
| Visuals | **`cover_bundle_id` FK** (optional) | **Copied URL columns** on row (no bundle FK) |
| Layers | **`preset_vibe_sounds`** | **`vibe_sounds`** |
| Mobile write | **None** (import only) | Create, update, manage sounds |
| Playback | **Not used** at runtime | **`buildVibeExecutionPlan`** source |

### Preset import ≠ live sync

| Rule | Detail |
| --- | --- |
| Import creates **new rows** | One **`vibes`** + N **`vibe_sounds`** per import |
| **No `preset_vibe_id`** on user vibe | Imported copy is **fully independent** |
| Re-import same preset | **Another** vibe — duplicates allowed |
| Admin edits preset later | **Does not** update past imports |
| Admin deactivates preset | Hides from catalog; **does not** delete user vibes |

### Database (shipped)

**`preset_vibes`**

| Column | Notes |
| --- | --- |
| `name`, `description` | Template metadata |
| `cover_bundle_id` | Nullable FK → **`cover_bundles`** (`nullOnDelete`) |
| `category` | Optional string (max 100) |
| `tags` | JSON array |
| `is_active` | Default **true**; inactive hidden from mobile list/show/import |

**`preset_vibe_sounds`**

| Column | Notes |
| --- | --- |
| `preset_vibe_id`, `sound_id` | Unique pair **`uq_preset_vibe_sounds_preset_sound`** |
| `volume`, `loop`, `play_mode`, `sort_order` | Layer config (mirrors **`vibe_sounds`** semantics) |
| `repeat_interval_seconds` | Required when **`play_mode === 'interval'`** (admin sync validation) |
| `start_offset_seconds`, `play_duration_seconds` | Timing caps |
| No fade columns | Import sets **`fade_in/out`** null on user pivot |

Presets **do not store visual URL columns** — list/detail art comes from **nested `cover_bundle`**.

---

## Functional Requirements

| ID | Requirement |
| --- | --- |
| FR-1 | **`preset_vibes`** are **catalog templates** — not user-owned compositions. |
| FR-2 | Authenticated users may **list/show active** presets (`firebase.auth`). |
| FR-3 | **Inactive** presets: **404** on show/import for regular users; omitted from default list. |
| FR-4 | Approved admin may **`include_inactive=1`** on list to see drafts. |
| FR-5 | Approved admin may **CRUD** presets and **sync sounds** — **`admin.approved`** middleware. |
| FR-6 | End users **cannot** mutate **`preset_vibes`** or **`preset_vibe_sounds`** via API. |
| FR-7 | Preset layers reference **existing catalog `sound_id`** only — no sound creation on preset routes. |
| FR-8 | Optional **`cover_bundle_id`** links visual package; preset row stores FK, not URL strings. |
| FR-9 | **`GET`** index/show eager-load **`coverBundle`**, **`presetVibeSounds.sound`**. |
| FR-10 | **`PresetVibeResource`** exposes **`sounds`** when **`presetVibeSounds`** loaded — key **`sounds`**, not `preset_vibe_sounds`. |
| FR-11 | **`PresetVibeResource`** has **no `sounds_count`** field — clients derive count from embedded **`sounds`** array length. |
| FR-12 | Import copies preset → user vibe in one transaction — see [`import/spec.md`](import/spec.md). |
| FR-13 | Import **does not** link user vibe to preset; **no live binding**. |
| FR-14 | Playback consumes **imported `vibe` + `vibe_sounds`**, not preset endpoints. |
| FR-15 | Mobile consumes presets **read-only** — no admin CRUD UI in **`front_vibes`**. |
| FR-16 | JSON-only preset APIs — **no multipart** on preset routes. |
| FR-17 | **`SyncPresetVibeSoundsRequest`** replace-all: delete existing layers, insert validated rows in transaction. |

---

## Validation Rules

### Admin — `StorePresetVibeRequest`

| Field | Rules |
| --- | --- |
| `name` | required, string, max 255 |
| `description` | nullable string |
| `cover_bundle_id` | nullable integer, exists **`cover_bundles.id`** |
| `category` | nullable string, max 100 |
| `tags` | nullable array; `tags.*` string max 50 |
| `is_active` | sometimes boolean (default **true** on create) |

**`resolvedTags()`:** trims, filters empty strings.

### Admin — `UpdatePresetVibeRequest`

| Field | Rules |
| --- | --- |
| `name` | sometimes required, string, max 255 |
| `description` | sometimes nullable string |
| `cover_bundle_id` | sometimes nullable integer, exists |
| `category` | sometimes nullable string, max 100 |
| `tags` | sometimes nullable array |
| `is_active` | sometimes boolean |

Partial PATCH supported; controller merges only keys present in **`validated()`**.

### Admin — `SyncPresetVibeSoundsRequest`

| Field | Rules |
| --- | --- |
| `sounds` | required array |
| `sounds.*.sound_id` | required, distinct, exists **`sounds.id`** |
| `sounds.*.play_mode` | sometimes `loop` \| `once` \| `interval` |
| `sounds.*.volume` | sometimes integer 0–100 (default 100) |
| `sounds.*.sort_order` | sometimes integer ≥ 0 |
| `sounds.*.repeat_interval_seconds` | nullable integer ≥ 1; **required when `play_mode` is `interval`** (`withValidator` after hook) |
| `sounds.*.start_delay_seconds` / `start_offset_seconds` | sometimes nullable integer ≥ 0 |
| `sounds.*.duration_seconds` / `play_duration_seconds` | sometimes nullable integer ≥ 1 |

**`normalizedLayers()`:** sorts by `sort_order` then `sound_id`; derives **`loop`** from **`play_mode === 'loop'`**; maps delay/duration aliases to pivot column names — same pattern as vibe sound attach ([`laravel-form-request-patterns.md`](../../standards/laravel-form-request-patterns.md)).

### Mobile read / import

| Endpoint | Body validation |
| --- | --- |
| `GET` list/show | No body |
| `POST …/import` | Empty **`{}`** — no client fields |

Import preconditions documented in [`import/spec.md`](import/spec.md).

### Authorization boundary

| Layer | Behaviour |
| --- | --- |
| **`firebase.auth`** | All preset routes |
| **`admin.approved`** | Write routes only (store, update, destroy, syncSounds) |
| **`PresetVibePolicy`** | Defines admin rules; **writes gated by middleware** today — controller does not call **`authorize()`** on read/import |
| **`is_active` checks** | Controller aborts **404** for inactive on show (non-admin) and import |

---

## API Contract

### List presets

```
GET /api/preset-vibes
GET /api/preset-vibes?include_inactive=1
```

**Middleware:** `firebase.auth`

**Query**

| Param | Behaviour |
| --- | --- |
| *(default)* | **`where is_active = true`**, **`orderBy name`** |
| `include_inactive=1` | Includes inactive **only if** **`$request->user()->isAdminApproved()`** |

**Eager load:** **`coverBundle`**, **`presetVibeSounds.sound`**

**Success: 200 OK**

```json
{
  "data": [
    {
      "id": 1,
      "name": "Storm Kit",
      "description": "Layered storm ambience",
      "cover_bundle_id": 3,
      "cover_bundle": {
        "id": 3,
        "name": "Storm Cover",
        "thumbnail_url": "https://{cdn}/…",
        "artwork_url": "https://{cdn}/…",
        "player_background_url": "https://{cdn}/…"
      },
      "category": "Weather",
      "tags": ["rain", "thunder"],
      "is_active": true,
      "sounds": [
        {
          "id": 10,
          "sound_id": 5,
          "sound": {
            "id": 5,
            "name": "Rain",
            "file_url": "https://{cdn}/rain.mp3",
            "category": "Nature",
            "duration": 120,
            "thumbnail_url": null
          },
          "volume": 80,
          "loop": true,
          "sort_order": 0,
          "play_mode": "loop",
          "repeat_interval_seconds": null,
          "start_offset_seconds": null,
          "start_delay_seconds": null,
          "play_duration_seconds": null,
          "duration_seconds": null,
          "created_at": "…",
          "updated_at": "…"
        }
      ],
      "created_at": "…",
      "updated_at": "…"
    }
  ]
}
```

**Note:** No **`sounds_count`** key — use **`sounds.length`** when array present.

### Show preset

```
GET /api/preset-vibes/{preset_vibe}
```

**Middleware:** `firebase.auth`

| Condition | Response |
| --- | --- |
| Active preset | **200** + **`PresetVibeResource`** |
| Inactive + regular user | **404** |
| Inactive + approved admin | **200** |

Same eager-load as index.

### Import preset (summary)

```
POST /api/preset-vibes/{preset_vibe}/import
```

**Middleware:** `firebase.auth`  
**Response:** **`VibeResource`** **201** — full contract in [`import/spec.md`](import/spec.md).

### Admin — create preset

```
POST /api/preset-vibes
```

**Middleware:** `firebase.auth`, **`admin.approved`**

**Success: 201** + **`PresetVibeResource`**

### Admin — update preset

```
PATCH /api/preset-vibes/{preset_vibe}
PUT   /api/preset-vibes/{preset_vibe}
```

**Middleware:** `firebase.auth`, **`admin.approved`**

**Success: 200** + **`PresetVibeResource`**

### Admin — delete preset

```
DELETE /api/preset-vibes/{preset_vibe}
```

**Success: 200** — `{ "message": "Preset vibe deleted." }`

Cascade deletes **`preset_vibe_sounds`**. Does **not** delete user vibes that were imported from this preset.

### Admin — sync preset sounds (replace-all)

```
PUT /api/preset-vibes/{preset_vibe}/sounds
```

**Middleware:** `firebase.auth`, **`admin.approved`**

**Body:** `{ "sounds": [ { "sound_id", "volume", "play_mode", "sort_order", … } ] }`

**Success: 200** + **`PresetVibeResource`** with refreshed **`sounds`** array.

**Semantics:** Deletes all existing **`preset_vibe_sounds`** for preset, inserts normalized rows in one transaction.

### Resource serialization patterns

Per [`api-resource-patterns.md`](../../standards/api-resource-patterns.md):

| Resource | Key rules |
| --- | --- |
| **`PresetVibeResource`** | Flat metadata + **`cover_bundle_id`**; nested **`cover_bundle`** via **`when(relationLoaded)`**; **`sounds`** = **`PresetVibeSoundResource::collection(whenLoaded('presetVibeSounds'))`** |
| **`PresetVibeSoundResource`** | Pivot fields + nested **`SoundResource`** when **`sound`** loaded; aliases **`start_delay_seconds`** → stored **`start_offset_seconds`**; **`duration_seconds`** → **`play_duration_seconds`** |
| **`CoverBundleResource`** | Raw URL fields — **no** cross-field fallbacks (unlike **`VibeResource`**) |
| **`VibeResource`** | Import response only — fallbacks on visual fields; optional embedded **`sounds`** |

**`whenLoaded` semantics**

| Relationship loaded? | JSON key |
| --- | --- |
| **`coverBundle`** loaded, FK null | **`cover_bundle: null`** |
| **`coverBundle`** not loaded | **`cover_bundle` key omitted** |
| **`presetVibeSounds`** loaded | **`sounds: [...]`** |
| **`presetVibeSounds`** not loaded | **`sounds` key omitted** |
| **`sound`** on each layer loaded | **`sound: { … SoundResource }`** |

**`sounds_count`:** **Not** on **`PresetVibeResource`**. **`VibeResource`** after import includes **`sounds_count`** via **`loadCount('sounds')`**.

---

## Cover Bundle Behaviour

Presets store **`cover_bundle_id`** only — not copied URL columns on **`preset_vibes`**.

| Topic | Behaviour |
| --- | --- |
| Admin link | Set/clear **`cover_bundle_id`** on create/update |
| API embed | **`cover_bundle`** nested when relation eager-loaded |
| Mobile list/detail art | **`presetForCardArtwork(preset)`** maps bundle URLs into minimal **`Vibe`** shape → **`getVibeCardBackgroundStyle`** (`front_vibes/src/utils/artwork.ts`) |
| Import | Server copies **`thumbnail_url`**, **`artwork_url`**, **`player_background_url`** from bundle onto **new user vibe** — even if bundle **`is_active`** is false |
| User vibe after import | **Owns URL strings** — **no `cover_bundle_id` FK** |
| Inactive bundle on active preset | URLs still returned in nested **`cover_bundle`** and still copied on import |

See [`../covers/create-cover-bundle/spec.md`](../covers/create-cover-bundle/spec.md) and [`../../architecture/storage/artwork-background-strategy.md`](../../architecture/storage/artwork-background-strategy.md).

### Relationship with cover bundles

- Presets **reference** bundles; they do **not** duplicate bundle bytes or URLs on the preset row.
- Mobile **never** calls cover-bundle apply helpers for presets — art is read from nested API JSON.
- Safe-delete **409** on bundle delete may apply when imported user vibes still hold matching URL strings ([`storage-strategy.md`](../../architecture/storage/storage-strategy.md)).

---

## Sound Layer Behaviour

**`preset_vibe_sounds`** are **reusable layer templates** — same playback field vocabulary as **`vibe_sounds`**, maintained separately.

| Topic | Preset catalog | After import (user vibe) |
| --- | --- | --- |
| Table | **`preset_vibe_sounds`** | **`vibe_sounds`** |
| Admin/mobile edit | Admin **`PUT …/sounds`** sync | [`manage-vibe-sounds`](../vibes/manage-vibe-sounds/spec.md) nested routes |
| Audio source | **`sounds.file_url`** (embedded in layer **`sound`**) | Same catalog **`file_url`** via pivot |
| **`play_mode` / `loop`** | Stored; **`loop`** derived on sync | Copied on import; **`loop = play_mode === 'loop'`** |
| Fades | No columns on preset pivot | **`fade_in/out`** null on import |
| Unique constraint | One row per **`(preset_vibe_id, sound_id)`** | One row per **`(vibe_id, sound_id)`** |

**Mobile detail:** read-only layer list — volume, mode, sort order for preview; **not editable** before import.

**Historical note:** [`../vibes/vibe-sounds/spec.md`](../vibes/vibe-sounds/spec.md) redirects to **`manage-vibe-sounds`** for user pivot semantics; preset layers mirror that vocabulary but use admin sync.

---

## Mobile UX Rules

| Rule | Detail |
| --- | --- |
| List | **`PresetVibesPage`** — **`/presets`** tab |
| Detail | **`PresetVibeDetailPage`** — **`/presets/:id`** |
| Intro copy | Curated mixes; import adds **editable copy** to My Vibes |
| Card badge | **Template** + layer count from **`preset.layers.length`** |
| Card imagery | **`presetForCardArtwork`** + **`artwork.ts`** gradients when bundle URLs missing |
| Layer section | Read-only; empty state allows import without layers |
| Import CTA | Footer **Import to My Vibes**; disabled while **`importing`** |
| Success | Toast; **`fetchVibes()`**; **`router.push('/vibes')`** |
| Service | **`presetVibeService`**: **`listPresetVibes`**, **`getPresetVibe`**, **`importPresetVibe`** only — no preset write methods |
| Normalization | API key **`sounds`** → client **`layers`**; tolerates legacy keys **`preset_vibe_sounds`**, **`layers`** in normalizer |
| Auth | Firebase Bearer — no Spaces secrets |

**No preset edit screen** on mobile. Post-import edit uses **`EditVibePage`** and manage-sounds routes.

---

## Storage / CDN Rules

| Rule | Detail |
| --- | --- |
| Preset read/import | **No Spaces writes** — DB + JSON only |
| Visual URLs on preset | Served via nested **`CoverBundleResource`** — HTTPS strings |
| Audio | **`SoundResource.file_url`** on embedded layer **`sound`** |
| Mobile | Opaque HTTPS consumption — **no `DO_SPACES_*`**, no presigned uploads |
| Admin catalog writes | Sounds/bundles uploaded via Laravel admin pipeline ([`upload-validation.md`](../../standards/upload-validation.md)) — not via preset multipart |
| Import | Copies URL strings onto user **`vibes`** row; references existing **`sounds`** by id |

Align with [`../../architecture/storage/storage-strategy.md`](../../architecture/storage/storage-strategy.md).

---

## Failure Cases

| Case | Expected behaviour |
| --- | --- |
| Unauthenticated **`GET`** | **401** |
| Inactive preset show/import (regular user) | **404** |
| Inactive preset show (approved admin) | **200** |
| Regular user **`POST/PATCH/DELETE` preset** | **403** — `Admin access is not approved.` |
| Pending/rejected admin write | **403** |
| Invalid **`cover_bundle_id`** on admin create/update | **422** |
| Sync with duplicate **`sound_id`** in payload | **422** |
| Sync interval mode without interval seconds | **422** |
| Import inactive preset | **404** |
| Preset layer references deleted sound | Admin data integrity issue — FK constraints |
| Admin deletes preset | Catalog row gone; **imported user vibes unchanged** |
| Admin updates preset layers | **Only affects future imports** — not existing user vibes |
| Network error on list | **`AppErrorState`** with retry on **`PresetVibesPage`** |

---

## Security Rules

| Rule | Requirement |
| --- | --- |
| Identity | Firebase Bearer on all preset routes |
| Catalog immutability (mobile) | No preset write methods in **`front_vibes`** |
| Admin gate | **`admin.approved`** middleware on store/update/destroy/syncSounds |
| Import ownership | **`user_id`** from auth on new vibe — see import spec |
| Layer references | **`sound_id`** must exist in catalog — validated on admin sync |
| No cross-user preset ownership | Presets have no **`user_id`** — shared catalog |
| Secrets | No Spaces credentials on mobile |
| No entitlement bypass | Any authenticated user may import **active** presets — no purchase gate |

---

## Future Considerations

| Topic | Notes |
| --- | --- |
| **`sounds_count` on `PresetVibeResource`** | Could add **`loadCount`** for parity with **`VibeResource`** — not shipped |
| **`PresetVibePolicy` in controller** | Policy exists; explicit **`authorize()`** calls not wired on read/write today |
| Preset admin spec split | Full admin UX detail could live beside **`ixora-admin`** pages — API covered here |
| Import customization | Name suffix, layer subset — [`import/spec.md`](import/spec.md) |
| Idempotent import | Dedupe by user+preset — **not today** |
| Version field on presets | Would not auto-sync imports without new product spec |

**Explicitly excluded:** marketplace, likes/favorites, community uploads, AI presets, live sync engine, collaborative editing, mobile preset CRUD.

---

## Relationship with create-vibe

| Aspect | **Preset catalog** | **Manual create-vibe** |
| --- | --- | --- |
| Entry | Browse template → import | Empty form → **`POST /api/vibes`** |
| Layers at birth | **Copied** from **`preset_vibe_sounds`** in import transaction | **Zero** — attach later via manage-sounds |
| Visuals | Copied server-side from preset’s **`cover_bundle`** | Client form + optional apply-cover-bundle; persistence gap on URL whitelist |
| Result | New **`vibes`** row | New **`vibes`** row |
| User ownership | Same — **`user_id`** server-side | Same |

Both paths produce **independent user vibes** editable via update + manage-sounds. Preset path is **faster onboarding**; manual path is **blank canvas**.

See [`../vibes/create-vibe/spec.md`](../vibes/create-vibe/spec.md).

---

## Relationship with preset import

This spec defines the **catalog source**; [`import/spec.md`](import/spec.md) defines the **copy transaction** into My Vibes.

| Concern | Owner doc |
| --- | --- |
| **`preset_vibes` / `preset_vibe_sounds` schema** | **This spec** |
| **`POST …/import` steps, pivot mapping, `VibeResource` 201** | **Import spec** |
| Independence / no live sync | **Both** — boundary repeated intentionally |

Import is the **only** mobile mutation that consumes presets — and it creates **`vibes`**, not preset rows.

---

## Relationship with playback-runtime

| Rule | Detail |
| --- | --- |
| Presets are **not playable** | No execution plan built from **`GET /api/preset-vibes`** |
| After import | Player loads **`GET /api/vibes/{id}`** + **`GET …/sounds`** on **user vibe** |
| Plan builder | **`buildVibeExecutionPlan`** uses **`vibe_sounds`** + catalog **`file_url`** |
| Preset preview on detail | Display-only layer list — **no audio engine start** from preset id |
| Fade fields | Ignored at runtime if present on user pivot — [`audio-engine-fade-limitations.md`](../../architecture/audio/audio-engine-fade-limitations.md) |

See [`../vibes/playback-runtime/spec.md`](../vibes/playback-runtime/spec.md).

---

## Relationship with cover bundles (summary)

Already detailed under **Cover Bundle Behaviour** — presets **optionally FK** to bundles; import **copies URLs** to user vibe; mobile **reads nested bundle** for template cards only.

---

## Related Docs

| Document | Path |
| --- | --- |
| **This spec** | `docs/specs/preset-vibes/spec.md` |
| Import preset | [`import/spec.md`](import/spec.md) |
| Create vibe (manual) | [`../vibes/create-vibe/spec.md`](../vibes/create-vibe/spec.md) |
| Update vibe | [`../vibes/update-vibe/spec.md`](../vibes/update-vibe/spec.md) |
| Manage vibe sounds | [`../vibes/manage-vibe-sounds/spec.md`](../vibes/manage-vibe-sounds/spec.md) |
| Vibe sounds (redirect) | [`../vibes/vibe-sounds/spec.md`](../vibes/vibe-sounds/spec.md) |
| Playback runtime | [`../vibes/playback-runtime/spec.md`](../vibes/playback-runtime/spec.md) |
| Apply cover bundle | [`../vibes/apply-cover-bundle/spec.md`](../vibes/apply-cover-bundle/spec.md) |
| Create cover bundle | [`../covers/create-cover-bundle/spec.md`](../covers/create-cover-bundle/spec.md) |
| Create sound | [`../sounds/create-sound/spec.md`](../sounds/create-sound/spec.md) |
| API Resource patterns | [`docs/standards/api-resource-patterns.md`](../../standards/api-resource-patterns.md) |
| Form Request patterns | [`docs/standards/laravel-form-request-patterns.md`](../../standards/laravel-form-request-patterns.md) |
| Artwork / background | [`docs/architecture/storage/artwork-background-strategy.md`](../../architecture/storage/artwork-background-strategy.md) |
| Storage policy | [`docs/architecture/storage/storage-strategy.md`](../../architecture/storage/storage-strategy.md) |
| Upload validation | [`docs/standards/upload-validation.md`](../../standards/upload-validation.md) |
| Auth | [`docs/standards/front-vibes-auth-core.md`](../../standards/front-vibes-auth-core.md) |
| Routing | [`docs/standards/front-vibes-ionic-routing.md`](../../standards/front-vibes-ionic-routing.md) |
| **back_vibes** | `PresetVibeController.php`, `PresetVibe.php`, `PresetVibeSound.php`, `PresetVibeResource.php`, `PresetVibeSoundResource.php`, `Store/Update/SyncPresetVibe*Request.php`, `PresetVibePolicy.php`, `PresetVibeApiTest.php`, `PresetVibeImportApiTest.php` |
| **front_vibes** | `PresetVibesPage.vue`, `PresetVibeDetailPage.vue`, `preset-vibe.service.ts`, `preset-artwork.ts`, `types/preset-vibe.ts` |
| **ixora-admin** | `pages/preset-vibes/**`, `services/api/preset-vibe.service.ts` |

When behaviour changes, update **this file first**, then [`import/spec.md`](import/spec.md) if import mapping changes, then API, mobile, admin, and tests.
