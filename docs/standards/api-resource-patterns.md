# API Resource Patterns — Laravel response architecture

**Status:** Active engineering standard (source of truth)  
**Scope:** JSON response shape for **`back_vibes`** public API consumed by **`front_vibes`** and **`ixora-admin`**  
**Applies to:** `app/Http/Resources/*`, API controllers, client TypeScript services

---

## Purpose

Define the **mandatory Laravel API Resource architecture** for Ixora: how domain models are serialized for HTTP responses, how relationships and fallbacks are exposed, and what clients may rely on as a **stable mobile/admin contract**.

**All public domain API responses must go through API Resources** (or the same `{ data: … }` envelope where a dedicated Resource class is not yet used). **Never return raw Eloquent models** or uncontrolled `toArray()` output from controllers.

This document is the **source of truth** for humans and AI-assisted API work. Feature specs reference resource fields but do not replace this standard.

---

## Scope

### In scope

- **Domain resources (primary):** `VibeResource`, `VibeSoundResource`, `SoundResource`, `CoverBundleResource`, `PresetVibeResource` (+ nested `PresetVibeSoundResource`)
- **JSON envelope:** `{ "data": … }` for Resource responses
- **`whenLoaded()`**, conditional nesting, **`withCount`** / **`sounds_count`**
- **Fallback rules** in `VibeResource` (visual URL columns)
- **Pivot flattening** in `VibeSoundResource`
- **Alias fields** for backward compatibility (`audio_url`, `duration_seconds`, etc.)
- **Security:** opaque HTTPS URLs only; no bucket internals on public domain responses
- **Error response shapes** (validation, auth, simple messages)
- **Client dependency** — mobile/admin parse `body.data`

### Out of scope

- **GraphQL**, **JSON:API**, **HAL**, **protobuf**, versioned API gateways — **not used**
- **Web routes** and Blade responses
- **Firebase auth token exchange** raw JSON (non-Resource auth endpoints)
- **Health check** (`GET /health`) — non-domain
- **Pagination implementation** — not shipped today; compatibility rules documented for future adoption

### Supplementary resources (same patterns, auth/admin)

| Resource | Use |
| --- | --- |
| `SyncedUserResource` | `POST /api/auth/sync` |
| `AdminAccessStatusResource` | Admin access request status |
| `PresetVibeSoundResource` | Nested under `PresetVibeResource` |

### Applies to

| Layer | Location |
| --- | --- |
| Resources | `back_vibes/app/Http/Resources/` |
| Controllers | `back_vibes/app/Http/Controllers/Api/` |
| Mobile consumers | `front_vibes/src/services/*.service.ts` |
| Admin consumers | `ixora-admin/services/api/` |

---

## Resource Architecture

```
Controller
    │
    ├── authorize / validate / query (+ eager load / withCount)
    │
    └── return new XxxResource($model)
        or XxxResource::collection($models)
                │
                ▼
        JsonResource::toArray()
                │
                ▼
        HTTP JSON  { "data": { ... } }   ← single resource
        HTTP JSON  { "data": [ ... ] }   ← collection (no pagination today)
```

| Rule | Detail |
| --- | --- |
| **Mandatory Resources** | Domain CRUD/list/show responses use a Resource class |
| **No raw models** | Do not `return $vibe` or `return response()->json($model->toArray())` for domain entities |
| **Controller loads data** | Eager-load relationships **before** wrapping in Resource |
| **Resource shapes output** | Field names, fallbacks, aliases, and conditional keys live in **`toArray()`** |
| **Shared contract** | Same Resource serves **mobile** and **admin** for a given endpoint |

### Current domain resources

| Resource | Model / source | Typical endpoints |
| --- | --- | --- |
| **`VibeResource`** | `Vibe` | `GET/POST/PATCH /api/vibes`, preset import **201** |
| **`VibeSoundResource`** | `Sound` + **`vibe_sounds` pivot** | `GET/POST/PATCH /api/vibes/{vibe}/sounds` |
| **`SoundResource`** | `Sound` | `GET/POST/PATCH /api/sounds`, nested in preset layers |
| **`CoverBundleResource`** | `CoverBundle` | `GET/POST/PATCH /api/cover-bundles` |
| **`PresetVibeResource`** | `PresetVibe` | `GET/POST/PATCH /api/preset-vibes` |
| **`PresetVibeSoundResource`** | `PresetVibeSound` | Nested under preset show/index when loaded |

---

## Serialization Rules

### Envelope

| Response type | JSON shape |
| --- | --- |
| Single resource | `{ "data": { …fields } }` |
| Collection | `{ "data": [ { … }, … ] }` |
| Delete / simple action | `{ "message": "…" }` — no Resource wrapper |

Laravel **`JsonResource`** default wrapping produces **`data`**. Clients **must** read **`response.data`** (see `handleResponse` in mobile services).

### Field conventions

| Convention | Rule |
| --- | --- |
| **Timestamps** | ISO-8601 strings via **`$this->created_at?->toISOString()`** |
| **Booleans** | Explicit casts where needed — e.g. `(bool) ($this->is_active ?? true)` |
| **Tags** | `tags` → `$this->tags ?? []` (array, never null in JSON) |
| **Nullable strings** | URL columns may be **`null`** when unset |
| **IDs** | Integer primary keys only — no UUID exposure unless model uses UUID (not today) |

### Fields intentionally omitted

| Omitted | Reason |
| --- | --- |
| **`user_id`** on `VibeResource` | Ownership enforced server-side; clients infer “my vibes” from scoped list |
| **Pivot table name / pivot row id** | Internal schema — flattened into layer fields |
| **Spaces bucket, region, origin URL, credentials** | Storage internals |
| **Soft internal columns** | Only expose product-facing fields |

### Alias fields (backward compatibility)

| Resource | Alias | Canonical source |
| --- | --- | --- |
| **`SoundResource`** | `audio_url` | `file_url` (read-only duplicate) |
| **`SoundResource`** | `duration_seconds` | `duration` |
| **`PresetVibeSoundResource`** | `start_delay_seconds` | `start_offset_seconds` |
| **`PresetVibeSoundResource`** | `duration_seconds` | `play_duration_seconds` |

Mobile may normalize aliases client-side (e.g. `normalizeSoundFileUrlFromApi`) but **must tolerate** both shapes from API.

---

## Relationship Rules

### `whenLoaded()`

Include nested collections **only** when the relationship was eager-loaded:

```php
'sounds' => VibeSoundResource::collection($this->whenLoaded('sounds')),
```

| Behaviour | Detail |
| --- | --- |
| Relationship **loaded** | Nested **`data.sounds`** array present |
| Relationship **not loaded** | Key **omitted** from JSON (Laravel `MissingValue`) |
| **Preset import** | Loads **`sounds`** + **`loadCount('sounds')`** → embeds layers on **201** |
| **Manual vibe create** | **`sounds`** not loaded → key absent; **`sounds_count: 0`** |

### Conditional nested resources (`when()`)

**`PresetVibeResource`** embeds **`cover_bundle`** only when relation loaded:

```php
'cover_bundle' => $this->when(
    $preset->relationLoaded('coverBundle'),
    fn () => $preset->coverBundle !== null
        ? new CoverBundleResource($preset->coverBundle)
        : null,
),
```

| Rule | Detail |
| --- | --- |
| Loaded + null FK | **`cover_bundle: null`** |
| Not loaded | Key **omitted** |
| Nested bundle | Full **`CoverBundleResource`** shape |

### Eager-load expectations (controllers)

| Endpoint | Typical `load` / `with` |
| --- | --- |
| `GET /api/vibes` | **`withCount('sounds')`** only |
| `GET /api/vibes/{id}` | **`loadCount('sounds')`** |
| Preset import **201** | **`load(['sounds'])`**, **`loadCount('sounds')`** |
| `GET /api/preset-vibes` | **`with(['coverBundle', 'presetVibeSounds.sound'])`** |
| `GET /api/vibes/{vibe}/sounds` | Pivot via **`$vibe->sounds()->get()`** |

Controllers **must** eager-load before returning Resources — avoid N+1 and ensure nested keys appear when intended.

### `whenCounted()`

**Not used today.** **`sounds_count`** comes from **`withCount('sounds')`** on the query and is read in **`VibeResource`** as:

```php
'sounds_count' => (int) ($this->sounds_count ?? 0),
```

If adopting **`loadCount`** without **`withCount`**, prefer **`whenCounted('sounds')`** in future refactors — until then, **`?? 0`** avoids null in JSON.

---

## Fallback Rules

### `VibeResource` — visual URL fallbacks (server-side)

Applied in **`toArray()`** so mobile/admin receive **resolved** display fields:

```php
$thumb = $this->thumbnail_url;

'thumbnail_url'         => $thumb,
'card_image_url'        => $this->card_image_url ?? $thumb,
'player_background_url' => $this->player_background_url ?? $thumb,
'artwork_url'           => $this->artwork_url ?? $thumb,
```

| Response field | Fallback chain |
| --- | --- |
| **`thumbnail_url`** | Stored value only (may be null) |
| **`card_image_url`** | `card_image_url` → **`thumbnail_url`** |
| **`player_background_url`** | `player_background_url` → **`thumbnail_url`** |
| **`artwork_url`** | `artwork_url` → **`thumbnail_url`** |

**Rationale:** Backward compatibility while dedicated image columns populate independently. Mobile **`artwork.ts`** applies **similar** client-side chains for offline snapshots — see [`artwork-background-strategy.md`](../architecture/storage/artwork-background-strategy.md).

### Resources **without** visual fallbacks

| Resource | Behaviour |
| --- | --- |
| **`CoverBundleResource`** | Raw **`thumbnail_url`**, **`artwork_url`**, **`player_background_url`** — no cross-field fallback |
| **`SoundResource`** | **`thumbnail_url`** nullable; no artwork fallbacks |
| **`VibeSoundResource`** | Catalog + pivot fields only |

Fallback policy is **resource-specific** — do not copy `VibeResource` chains to catalog resources without product review.

---

## Collection Rules

### Current behaviour

| Pattern | Shipped today |
| --- | --- |
| Pagination | **`->get()`** — full lists in **`data`** array |
| **`::collection()`** | `VibeResource::collection`, `SoundResource::collection`, etc. |
| Ordering | Controller/query responsibility (e.g. **`orderBy('name')`**, **`latest()`**) |
| Empty list | `{ "data": [] }` |

### Pagination compatibility (future)

If **`paginate()`** is introduced:

- Continue using **`Resource::collection($paginator)`**
- Laravel adds **`links`** and **`meta`** alongside **`data`** — clients must not assume **`data`** is the only top-level key
- **Breaking change policy:** document new pagination in feature spec + bump client parsing if needed

**Do not** return unpaginated mega-lists from new high-cardinality endpoints without review.

---

## Naming Rules

| Rule | Convention |
| --- | --- |
| Resource class | **`{Model}Resource`** — e.g. `VibeResource` |
| JSON keys | **snake_case** — matches Laravel columns and mobile TypeScript interfaces |
| URL fields | `*_url` suffix — `file_url`, `thumbnail_url`, `artwork_url` |
| Count fields | `{relation}_count` — `sounds_count` |
| Play mode | `play_mode` — `loop` \| `once` \| `interval` |
| Pivot timing | `start_offset_seconds`, `play_duration_seconds`, `repeat_interval_seconds` |
| Legacy aliases | Keep when clients depend on them — mark read-only in docblocks |

**Stability:** Renaming or removing JSON keys is a **breaking change** for mobile/admin. Prefer **additive** fields and deprecated aliases.

---

## Security Rules

| Rule | Requirement |
| --- | --- |
| **Opaque HTTPS URLs** | `file_url`, `thumbnail_url`, etc. are **full public CDN strings** — not bucket paths |
| **No bucket internals** | Do not expose `DO_SPACES_*`, origin endpoints, or object keys on **domain** Resources |
| **No signed URL machinery** | Resources return stable public URLs as stored on rows |
| **Ownership fields** | Do not expose **`user_id`** on vibes to clients — list scoped server-side |
| **Admin upload exception** | `POST /api/admin/uploads` returns **`data.key`** + **`data.url`** for admin workflow only — **not** a domain Resource; **`key`** is admin-facing, not mobile playback |

Clients treat URL strings as **opaque** — no parsing bucket layout. See [`upload-validation.md`](upload-validation.md) and [`storage-strategy.md`](../architecture/storage/storage-strategy.md).

---

## Error Response Rules

Resources apply to **success** payloads. Errors use Laravel defaults unless documented:

| HTTP | Shape | Typical cause |
| --- | --- | --- |
| **422** | `{ "message": "…", "errors": { "field": ["…"] } }` | FormRequest validation |
| **401** | `{ "message": "…" }` | Missing/invalid Firebase token, user not found |
| **403** | `{ "message": "…" }` | Policy denial (e.g. not vibe owner) |
| **404** | `{ "message": "…" }` or empty body | Model not found / inactive preset |
| **409** | `{ "message": "…" }` | Safe delete conflict (cover bundle referenced) |
| **5xx** | `{ "message": "…" }` | Server error |

**Delete success:** `{ "message": "Vibe deleted." }` — no **`data`** wrapper.

Admin/mobile map **422** / **401** / **403** to user-facing copy — not Resource responsibility.

---

## Performance Rules

| Rule | Detail |
| --- | --- |
| **Eager load** | Load nested relations in controller when Resource will serialize them |
| **`withCount`** | Use for **`sounds_count`** on vibe list/show — avoid loading all layers for count only |
| **Avoid N+1** | `PresetVibeResource::collection` with **`presetVibeSounds.sound`** preloaded |
| **Conditional embed** | Use **`whenLoaded`** — do not serialize heavy nested graphs by default |
| **Full collections** | Acceptable for current catalog sizes; revisit before scaling |

**Preset import** intentionally loads **`sounds`** for immediate client use — exception for UX, not default for all vibe responses.

---

## Risks

| Risk | If ignored |
| --- | --- |
| Raw model JSON leak | Internal columns, pivot noise, inconsistent shapes |
| Missing **`whenLoaded`** | Accidental lazy-load N+1 or unexpected nested payloads |
| Changing **`VibeResource` fallbacks** | Mobile card/player/artwork break without code change |
| Removing **`audio_url` alias** | Legacy admin/mobile clients break |
| Exposing **`user_id`** or storage keys | Privacy leak; client coupling to infra |
| **`sounds` key always present** | Clients assume layers exist when relationship empty/unloaded |
| Unpaginated growth | Large **`data`** arrays — memory and slow mobile parse |
| Resource/controller drift | Field in DB but not in Resource — clients never see updates |

---

## Validation

### Code review checklist

- [ ] New/changed domain endpoints return a **Resource** (or documented `{ data }` envelope)
- [ ] No **`return $model`** from API controllers for domain entities
- [ ] Nested data uses **`whenLoaded`** / explicit **`when()`**
- [ ] Counts use **`withCount`** + Resource field (or **`whenCounted`** if adopted)
- [ ] URL fields are **HTTPS CDN strings** only — no origin URLs
- [ ] No **`user_id`**, pivot ids, or bucket keys on public domain Resources
- [ ] Additive JSON changes preferred; breaking renames documented

### Automated (Laravel)

- Feature tests assert **`assertJsonPath('data.…')`** and **`assertJsonStructure`**
- Example: preset import **`data.sounds_count`**, embedded **`data.sounds`**

### Client contract smoke

- [ ] Mobile **`vibe.service.ts`** parses **`body.data`** for vibes
- [ ] Mobile **`vibe-sound.service.ts`** parses **`body.data`** array for layers
- [ ] Admin sound/cover create parses **`body.data`** from **`SoundResource`** / **`CoverBundleResource`**

---

## Related Files

| Document | Path |
| --- | --- |
| **This standard** | `docs/standards/api-resource-patterns.md` |
| Playback runtime (consumes layer JSON) | [`docs/specs/vibes/playback-runtime/spec.md`](../specs/vibes/playback-runtime/spec.md) |
| Create vibe | [`docs/specs/vibes/create-vibe/spec.md`](../specs/vibes/create-vibe/spec.md) |
| Manage vibe sounds | [`docs/specs/vibes/manage-vibe-sounds/spec.md`](../specs/vibes/manage-vibe-sounds/spec.md) |
| Artwork fallbacks (client + server) | [`docs/architecture/storage/artwork-background-strategy.md`](../architecture/storage/artwork-background-strategy.md) |
| Upload validation | [`docs/standards/upload-validation.md`](upload-validation.md) |
| Storage policy | [`docs/architecture/storage/storage-strategy.md`](../architecture/storage/storage-strategy.md) |
| Auth responses | [`docs/standards/front-vibes-auth-core.md`](front-vibes-auth-core.md) |
| **back_vibes — Resources** | `app/Http/Resources/VibeResource.php` |
| | `app/Http/Resources/VibeSoundResource.php` |
| | `app/Http/Resources/SoundResource.php` |
| | `app/Http/Resources/CoverBundleResource.php` |
| | `app/Http/Resources/PresetVibeResource.php` |
| | `app/Http/Resources/PresetVibeSoundResource.php` |
| **back_vibes — Controllers** | `app/Http/Controllers/Api/VibeController.php` |
| | `app/Http/Controllers/Api/VibeSoundController.php` |
| | `app/Http/Controllers/Api/SoundController.php` |
| | `app/Http/Controllers/Api/CoverBundleController.php` |
| | `app/Http/Controllers/Api/PresetVibeController.php` |
| **front_vibes consumers** | `src/services/vibe.service.ts`, `vibe-sound.service.ts`, `sound.service.ts`, `cover-bundle.service.ts`, `preset-vibe.service.ts` |

When Resource behaviour changes, update **this file first**, then feature specs, mobile TypeScript interfaces, and feature tests.
