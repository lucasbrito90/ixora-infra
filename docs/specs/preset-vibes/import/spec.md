# Import Preset Vibe — copy curated template to My Vibes

**Status:** Active feature specification (source of truth)  
**Version:** 2.0 (consolidated; matches current `PresetVibeController::import` + `front_vibes` implementation)  
**Feature ID:** `preset-vibes/import`  
**Platform:** Mobile-first (`front_vibes`); Laravel API contract shared with future clients

---

## Goal

Enable an **authenticated mobile user** to **import an active preset vibe** — a **curated admin template** ([`../spec.md`](../spec.md)) — into a **new user-owned vibe** in **one synchronous transaction**: copy preset **metadata**, copy **visual HTTPS URL strings** from the preset’s optional **cover bundle**, create **`vibe_sounds`** rows from **`preset_vibe_sounds`**, and return **`VibeResource`** **201** — **without** creating catalog sounds or cover bundles, **without** linking the user vibe back to the preset, and **without** live sync when the preset changes later.

**Success criteria:**

- **`POST /api/preset-vibes/{preset_vibe}/import`** creates **one new `vibes` row** with **`user_id`** assigned server-side.
- **`vibe_sounds`** pivot rows reference **existing catalog `sounds`** — **no duplicate `sounds` rows**.
- Visual URLs copied from **`cover_bundle`** when preset has **`cover_bundle_id`** — **no `cover_bundle_id` FK** on user vibe.
- Import is **transactional** — all-or-nothing; **no partial inserts**.
- Response includes **`sounds_count`** and embedded **`sounds`** (relationship loaded post-commit).
- Imported vibe is **immediately playable** via normal playback-runtime when layers exist.
- Imported vibe is **compatible with offline-download** after user runs **Download for offline** — no auto-snapshot on import.
- **No** background jobs, async import, AI remix, version sync, or partial layer selection.

---

## Scope

### In scope

- **Import endpoint only:** **`POST /api/preset-vibes/{preset_vibe}/import`**
- **Browse context:** **`GET /api/preset-vibes`**, **`GET /api/preset-vibes/{id}`** (preset catalog — parent spec)
- **Server transaction:** **`Vibe::create`** + **`vibe->sounds()->attach(...)`** per **`preset_vibe_sounds`**
- **URL copy:** `thumbnail_url`, `artwork_url`, `player_background_url` from linked bundle
- **Mobile:** **`PresetVibeDetailPage`** → **Import to My Vibes** → **`fetchVibes()`** → **`/vibes`**
- **Response:** **`VibeResource`** **201** with **`loadCount('sounds')`** + **`load(['sounds'])`**
- **Tests:** **`PresetVibeImportApiTest`**

### Out of scope

- **Preset catalog CRUD** — [`../spec.md`](../spec.md) admin routes
- **Manual vibe create** ([`../../vibes/create-vibe/spec.md`](../../vibes/create-vibe/spec.md)) — empty shell, layers attached separately
- **Apply cover bundle** client flow ([`../../vibes/apply-cover-bundle/spec.md`](../../vibes/apply-cover-bundle/spec.md)) — import copies server-side
- **Manage sounds after import** ([`../../vibes/manage-vibe-sounds/spec.md`](../../vibes/manage-vibe-sounds/spec.md)) — same nested APIs as manual vibes
- **Creating `sounds` or `cover_bundles`** on import
- **Upload / transcoding / Spaces writes** on import
- **Live preset sync** to previously imported vibes
- **Partial import** (subset of layers, custom name) — not supported
- **Background jobs, async queues, webhooks**
- **Purchase, subscription, entitlement gates**

---

## Actors

| Actor | Role |
| --- | --- |
| **End user** | Imports active preset into personal My Vibes library. |
| **Mobile app (`front_vibes`)** | **`POST …/import`** with empty JSON body; refreshes vibe list on success. |
| **Laravel API (`back_vibes`)** | **`PresetVibeController::import`** — active check, DB transaction, **`VibeResource`**. |
| **`preset_vibes`** | Read-only template source — **not mutated** by import. |
| **`preset_vibe_sounds`** | Layer template rows copied to **`vibe_sounds`**. |
| **`cover_bundles`** | Optional visual source via preset FK — URLs copied as strings. |
| **`sounds`** | Catalog audio referenced by **`sound_id`** — **not duplicated**. |

---

## User Journey

1. User signs in (Firebase → **`POST /api/auth/sync`** per [`front-vibes-auth-core.md`](../../standards/front-vibes-auth-core.md)).
2. User browses **`GET /api/preset-vibes`** → opens **`PresetVibeDetailPage`** → **`GET /api/preset-vibes/{id}`**.
3. Detail shows read-only metadata, layer preview, hero from nested **`cover_bundle`** (when present).
4. User taps **Import to My Vibes**.
5. Mobile **`POST /api/preset-vibes/{id}/import`** with body **`{}`** and Firebase Bearer token.
6. Laravel runs **one DB transaction**: create **`vibes`** row + attach all **`vibe_sounds`** from preset layers.
7. Response **201** + **`VibeResource`** with **`sounds_count`** and embedded **`sounds`**.
8. Mobile **`fetchVibes()`**, success toast, **`router.push('/vibes')`**.
9. User may **play** imported vibe immediately (if layers exist) or **manage layers** like any user vibe.

**Not in journey:** preset editing, re-sync when admin changes template, automatic offline download.

---

## Related Domain Model

```
preset_vibes ── cover_bundle_id? ──► cover_bundles
     │
     │ preset_vibe_sounds (template pivot)
     ▼
   sounds (catalog — file_url)

POST /import  ──►  vibes (user-owned)
                      │  NO preset_vibe_id
                      │  NO cover_bundle_id
                      │  copied URL strings on row
                      │
                      │ vibe_sounds (new pivot rows)
                      ▼
                   sounds (same catalog rows — NOT duplicated)
```

### Import semantics (authoritative)

| Rule | Detail |
| --- | --- |
| Creates **new** user vibe | Always **`INSERT`** — never updates existing vibe |
| Copies **metadata** | **`name`**, **`description`** from preset |
| Copies **visual URLs** | From preset’s **`coverBundle`** when FK set — HTTPS strings only |
| Creates **layers** | One **`vibe_sounds`** attach per **`preset_vibe_sounds`** row |
| **Independent copy** | No **`preset_vibe_id`**, no live binding to preset |
| **No sync after import** | Admin preset edits affect **future imports only** |
| Re-import same preset | **Another** vibe — duplicates allowed |
| Catalog unchanged | **`sounds`**, **`cover_bundles`**, **`preset_vibes`** not modified |

### Manual create vs preset import

| Aspect | **Manual create-vibe** | **Preset import** |
| --- | --- | --- |
| Endpoint | **`POST /api/vibes`** | **`POST /api/preset-vibes/{id}/import`** |
| Vibe shell | Metadata (+ optional URLs from client form) | Metadata + URLs from preset bundle |
| Layers at birth | **`sounds_count: 0`** — attach later | **Copied** from **`preset_vibe_sounds`** in same transaction |
| Sound rows | References catalog on attach | References **same** catalog rows — **no new `sounds`** |
| Visual source | Client apply-cover-bundle (persistence gap on manual create) | **Server-side** URL copy from bundle |
| Playback ready | After user attaches layers | **Immediately** when preset has layers |
| Form Request | **`StoreVibeRequest`** | **No Form Request** — empty body, server-driven copy |

See [`../../vibes/create-vibe/spec.md`](../../vibes/create-vibe/spec.md).

---

## Functional Requirements

| ID | Requirement |
| --- | --- |
| FR-1 | Only **authenticated Firebase-synced users** may import (`firebase.auth`). |
| FR-2 | Import allowed only when **`preset_vibes.is_active === true`** — inactive → **404**. |
| FR-3 | Import creates a **new** **`vibes` row** — never updates an existing vibe. |
| FR-4 | **`user_id = (int) $request->user()->id`** — never from client body. |
| FR-5 | Copied metadata: **`name`**, **`description`** from preset; **`is_active`** = **true**. |
| FR-6 | When preset has **`coverBundle`**, copy **`thumbnail_url`**, **`artwork_url`**, **`player_background_url`** — even if bundle **`is_active`** is false. |
| FR-7 | **`card_image_url`** on new vibe stays **null** on model — **`VibeResource`** resolves display via fallback chain. |
| FR-8 | When preset has **no** **`cover_bundle_id`**, all four vibe URL columns remain **null**. |
| FR-9 | For each **`preset_vibe_sounds`** row, **`attach(sound_id, pivot…)`** — **no new `sounds` row**. |
| FR-10 | **`play_mode`** copied; default **`loop`** when empty; **`loop`** pivot = **`play_mode === 'loop'`**. |
| FR-11 | **`repeat_interval_seconds`** copied only when **`play_mode === 'interval'`**; else **null**. |
| FR-12 | **`fade_in_seconds`**, **`fade_out_seconds`** set **null** on attach (preset pivot has no fade columns). |
| FR-13 | Entire import wrapped in **`DB::transaction`** — rollback on any failure. |
| FR-14 | Import **does not insert** **`sounds`**, **`cover_bundles`**, or mutate **`preset_vibes`**. |
| FR-15 | Post-commit: **`load(['sounds'])`**, **`loadCount('sounds')`**, return **`VibeResource`** **201**. |
| FR-16 | Same user may import same preset **multiple times** — independent vibes. |
| FR-17 | Preset with **zero layers** still creates vibe (**`sounds_count: 0`**). |
| FR-18 | Imported vibe uses **`buildVibeExecutionPlan`** like any user vibe — [`playback-runtime`](../../vibes/playback-runtime/spec.md). |
| FR-19 | **No** dedicated Form Request — no client-controlled import fields today. |

---

## Validation Rules

### Request (shipped)

| Rule | Detail |
| --- | --- |
| Method / path | **`POST /api/preset-vibes/{preset_vibe}/import`** |
| Content-Type | **`application/json`** |
| Body | Empty **`{}`** — **no whitelisted client fields** |
| Form Request | **None** — controller uses **`Illuminate\Http\Request`** directly |

Per [`laravel-form-request-patterns.md`](../../standards/laravel-form-request-patterns.md): import is **server-driven copy** — trust boundary is controller logic, not client payload.

### Server preconditions

| Check | Failure |
| --- | --- |
| Valid Firebase token + synced user | **401** |
| Preset exists (route model binding) | **404** |
| Preset **`is_active`** | **404** (same as missing for mobile) |
| Each **`sound_id`** exists | FK integrity — transaction **rolls back** on attach failure |

### Not validated / not accepted

| Topic | Behaviour |
| --- | --- |
| Custom vibe name | **Not supported** — preset name copied |
| Layer subset | **Not supported** — all preset layers copied |
| Target **`user_id`** | **Ignored** — always auth user |
| Duplicate-import prevention | **None** — multiple imports allowed |
| Purchase / entitlement | **None** |

---

## API Contract

### Import preset

```
POST /api/preset-vibes/{preset_vibe}/import
```

**Middleware:** `firebase.auth`  
**Authorization:** Any authenticated user — **no** admin approval required  
**Policy:** **No** `$this->authorize()` call on import today

**Request body:** `{}` (empty object)

**Success: 201 Created** — **`VibeResource`** envelope

```json
{
  "data": {
    "id": 88,
    "name": "Storm Kit",
    "description": "Layered storm",
    "thumbnail_url": "https://{cdn}/covers/1/thumbnail/thumbnail.webp",
    "card_image_url": "https://{cdn}/covers/1/thumbnail/thumbnail.webp",
    "player_background_url": "https://{cdn}/covers/1/player-background/background.webp",
    "artwork_url": "https://{cdn}/covers/1/artwork/artwork.jpg",
    "is_active": true,
    "sounds_count": 2,
    "sounds": [
      {
        "id": 5,
        "name": "Rain",
        "file_url": "https://{cdn}/sounds/rain.mp3",
        "thumbnail_url": null,
        "category": "Nature",
        "duration": 120,
        "volume": 77,
        "loop": false,
        "sort_order": 1,
        "play_mode": "once",
        "repeat_interval_seconds": null,
        "start_offset_seconds": 3,
        "play_duration_seconds": 90,
        "fade_in_seconds": null,
        "fade_out_seconds": null
      }
    ],
    "created_at": "2026-05-23T12:00:00.000000Z",
    "updated_at": "2026-05-23T12:00:00.000000Z"
  }
}
```

### `VibeResource` response behaviour

Per [`api-resource-patterns.md`](../../standards/api-resource-patterns.md):

| Field | Import behaviour |
| --- | --- |
| **`sounds_count`** | From **`loadCount('sounds')`** after attach — matches pivot row count |
| **`sounds`** | Embedded because controller **`load(['sounds'])`** — **`VibeSoundResource::collection(whenLoaded('sounds'))`** |
| **`thumbnail_url`** | Stored copied value (may be null) |
| **`card_image_url`** | **`card_image_url ?? thumbnail_url`** in resource — import stores **`card_image_url` null**, so response falls back to **`thumbnail_url`** when copied |
| **`player_background_url`** | Stored value, else **`?? thumbnail_url`** in resource |
| **`artwork_url`** | Stored value, else **`?? thumbnail_url`** in resource |
| **`user_id`** | **Not exposed** in **`VibeResource`** |

**Nested `sounds`:** Each item is **`VibeSoundResource`** — catalog fields + pivot fields; **`file_url`** from **`sounds`** table (not duplicated).

**When `sounds` not loaded:** Key omitted — import **always** loads relationship before response.

### Error responses

| HTTP | Condition |
| --- | --- |
| **401** | Missing/invalid Firebase token or user not synced |
| **404** | Preset not found or **inactive** |
| **5xx** | Server/transaction failure — **no partial vibe** persisted |

**No other import endpoints** (bulk, preview, async status) in current architecture.

### Related read endpoints (browse before import)

| Method | Path | Notes |
| --- | --- | --- |
| `GET` | `/api/preset-vibes` | Active presets only (unless admin `include_inactive`) |
| `GET` | `/api/preset-vibes/{id}` | Preset detail — **`PresetVibeResource`**, not used for playback |

Catalog read contract: [`../spec.md`](../spec.md).

---

## Import Behaviour

### Transaction steps (`PresetVibeController::import`)

1. **`abort(404)`** if **`! $presetVibe->is_active`**.
2. **`loadMissing(['coverBundle', 'presetVibeSounds'])`**.
3. **`DB::transaction`**:
   - Build URL map — all **null**, or from **`$presetVibe->coverBundle`** when present.
   - **`Vibe::create([user_id, name, description, ...urls, is_active: true])`**.
   - For each **`presetVibeSounds`** row: derive **`playMode`**, **`attach(sound_id, pivot…)`**.
4. **`$vibe->load(['sounds'])`**, **`$vibe->loadCount('sounds')`**.
5. Return **`(new VibeResource($vibe))->response()->setStatusCode(201)`**.

### Metadata copy

| Source | Target (`vibes` column) |
| --- | --- |
| Preset **`name`** | **`name`** |
| Preset **`description`** | **`description`** |
| Auth user | **`user_id`** |
| — | **`is_active`** = **true** |
| — | **No `preset_vibe_id`** |
| — | **No `cover_bundle_id`** |

### Visual URL copy (cover bundle optionality)

| Preset state | Copied to vibe |
| --- | --- |
| **`cover_bundle_id` null** | All URL columns **null** |
| Bundle linked, **`is_active` false** | URLs **still copied** (tested) |
| Bundle linked, active | **`thumbnail_url`**, **`artwork_url`**, **`player_background_url`** from bundle row |
| **`card_image_url`** | **Not copied** — remains **null** on model |

**Copied URL semantics:** Strings are **snapshotted** onto the user vibe row at import time. They may reference the same CDN objects as the catalog bundle. User vibe **owns the strings** — bundle delete safe-check may **409** if URLs still match ([`storage-strategy.md`](../../architecture/storage/storage-strategy.md)).

**Fallback chains after import:**

- **API (`VibeResource`):** `card_image_url ?? thumbnail_url`, `player_background_url ?? thumbnail_url`, `artwork_url ?? thumbnail_url`
- **Mobile (`artwork.ts`):** Same priority chains for list/player/MiniPlayer — [`artwork-background-strategy.md`](../../architecture/storage/artwork-background-strategy.md)

Import **persists URLs server-side** (unlike manual create’s Form Request gap).

### Pivot field mapping (`preset_vibe_sounds` → `vibe_sounds`)

| Preset pivot | User pivot | Notes |
| --- | --- | --- |
| **`sound_id`** | **`sound_id`** | Same catalog row — **no duplicate sound** |
| **`volume`** | **`volume`** | Copied |
| **`sort_order`** | **`sort_order`** | Copied |
| **`play_mode`** | **`play_mode`** | Default **`loop`** if empty on preset row |
| — | **`loop`** | **`play_mode === 'loop'`** |
| **`repeat_interval_seconds`** | **`repeat_interval_seconds`** | Copied when mode **`interval`**; else **null** |
| **`start_offset_seconds`** | **`start_offset_seconds`** | Copied |
| **`play_duration_seconds`** | **`play_duration_seconds`** | Copied |
| — | **`fade_in_seconds`** | **null** |
| — | **`fade_out_seconds`** | **null** |

### Independence and re-import

| Scenario | Result |
| --- | --- |
| Import preset twice | **Two** vibes for same user |
| Admin edits preset layers | **Past imports unchanged** |
| Admin deactivates preset | **Past imports unchanged**; new imports **404** |
| User edits imported vibe | Normal update/manage-sounds — **no preset coupling** |

---

## Cover Bundle Behaviour

| Topic | Import behaviour |
| --- | --- |
| Preset FK | **`preset_vibes.cover_bundle_id`** — admin-maintained |
| User vibe | **No FK** — only copied URL strings |
| Copy fields | **`thumbnail_url`**, **`artwork_url`**, **`player_background_url`** |
| Inactive bundle | URLs copied when preset still references bundle |
| No bundle | All vibe visual columns **null** — mobile uses **`artwork.ts`** gradients |
| Spaces / upload | **No** new objects — string copy only |
| Client apply-cover | **Not used** — server copies in transaction |

See [`../../covers/create-cover-bundle/spec.md`](../../covers/create-cover-bundle/spec.md) and [`../../architecture/storage/artwork-background-strategy.md`](../../architecture/storage/artwork-background-strategy.md).

---

## Sound Layer Behaviour

| Topic | Behaviour |
| --- | --- |
| Source rows | **`preset_vibe_sounds`** on preset |
| Target rows | **`vibe_sounds`** on new vibe |
| Catalog audio | **`sounds.file_url`** — **same row** referenced, bytes not duplicated |
| Empty preset | Zero attachments — **`sounds_count: 0`**; user adds via manage-sounds |
| After import | **`GET/PATCH/DELETE /api/vibes/{vibe}/sounds`** — same as manual vibes |
| Playback | **`buildVibeExecutionPlan`** from **`vibe_sounds`** + catalog **`file_url`** |
| Fade pivot fields | **null** on import; **ignored at runtime** if set later |

Historical pivot vocabulary: [`../../vibes/vibe-sounds/spec.md`](../../vibes/vibe-sounds/spec.md) redirects to [`manage-vibe-sounds`](../../vibes/manage-vibe-sounds/spec.md).

### Relationship with manage-vibe-sounds

Import **creates** initial layers; **manage-vibe-sounds** owns post-import attach/detach/configure. Import does **not** replace manage-sounds APIs — it **seeds** them.

### Relationship with playback-runtime

| Rule | Detail |
| --- | --- |
| Preset id **not** used at play time | Player loads **user vibe id** |
| Layers required for audio | **`GET /api/vibes/{id}/sounds`** or embedded import response |
| Execution plan | Same **`buildVibeExecutionPlan`** as manual vibes with layers |
| Zero layers | Import succeeds; playback has **no layers** until user attaches sounds |

See [`../../vibes/playback-runtime/spec.md`](../../vibes/playback-runtime/spec.md).

### Relationship with offline-download

| Rule | Detail |
| --- | --- |
| Auto offline snapshot | **Not created** on import |
| Compatibility | Imported vibe is a normal user vibe — offline works **after** explicit download |
| Manifest URLs | Snapshot stores **`VibeResource`**-shaped meta + exact **`file_url`** strings at download time |
| Edit after import | Offline stale until re-download — same as manual vibes |

See [`../../vibes/offline-download/spec.md`](../../vibes/offline-download/spec.md).

---

## Mobile UX Rules

| Rule | Detail |
| --- | --- |
| Detail screen | **`PresetVibeDetailPage`** — **`/presets/:id`** |
| CTA | Footer **Import to My Vibes** — disabled while **`importing`** |
| API | **`presetVibeService.importPresetVibe(id)`** → **`POST …/import`**, body **`{}`** |
| Normalization | Response via **`normalizeImportedVibe`** — **`sounds_count`**, optional **`sounds`** |
| Success | Toast `"${name}" added to My Vibes.`; **`fetchVibes()`**; **`router.push('/vibes')`** |
| Error | Inline **`importError`** + danger toast |
| Layer preview | Read-only on preset detail — **not** editable pre-import |
| Empty layers | Copy explains user can import and add sounds later |
| Hero art | **`presetForCardArtwork`** + **`artwork.ts`** on preset browse — post-import uses vibe URLs |
| Post-import play | Standard player flow on **new vibe id** |

---

## Storage / CDN Rules

| Rule | Detail |
| --- | --- |
| Import writer | Laravel **DB only** — **no Spaces writes** |
| Visual URLs | Copied **HTTPS strings** onto **`vibes`** columns |
| Audio | **`sounds.file_url`** unchanged — pivot references catalog id |
| Mobile | Consumes URLs from **`VibeResource`** — **no `DO_SPACES_*`**, no presigned uploads |
| Direct Spaces access | **Forbidden** on mobile |
| Broken CDN URL | Import **still succeeds** — failure at **image/audio fetch** time in client |
| Transcoding | **None** |

Align with [`../../architecture/storage/storage-strategy.md`](../../architecture/storage/storage-strategy.md) and [`../../standards/upload-validation.md`](../../standards/upload-validation.md).

---

## Failure Cases

| Case | Expected behaviour |
| --- | --- |
| **Inactive preset** | **404**; **`Vibe::count`** for user unchanged |
| **Unauthenticated** | **401**; no vibe created |
| **Invalid preset id** | **404** |
| **Missing sound reference** on preset layer | FK/attach failure → transaction **rollback** → **5xx**; **no partial vibe** |
| **Transaction error mid-attach** | Full **rollback** — no orphan vibe without layers or half-attached layers |
| **Duplicate import** | **Two independent vibes** — allowed by design |
| **Import preset with zero sounds** | **201**; **`sounds_count: 0`**; empty **`sounds`** array in response |
| **Wrong user ownership** | Impossible — **`user_id`** always from auth (tested: Alice import does not affect Bob) |
| **Broken CDN URLs** (404/403 at fetch) | Import **201** succeeds; playback imagery/audio fails at **runtime consume** — not validated at import |
| **Network error before response** | Client shows error; server either committed full transaction or rolled back |
| **User edits imported vibe** | Independent of preset — no sync |
| **Admin changes preset after import** | **No effect** on existing user vibes |

**Partial insert prevention:** **`DB::transaction`** wraps **`Vibe::create`** and **all** **`attach`** calls — atomic all-or-nothing.

---

## Security Rules

| Rule | Requirement |
| --- | --- |
| Identity | Firebase Bearer — [`front-vibes-auth-core.md`](../../standards/front-vibes-auth-core.md) |
| Ownership | **`user_id`** from **`$request->user()->id`** only |
| Cross-user import | **Impossible** — no client **`user_id`** field |
| Preset mutation | Import endpoint **does not write** **`preset_vibes`** |
| Catalog integrity | Layers reference existing **`sound_id`** only |
| Authorization | Any authenticated user may import **active** presets — no purchase gate |
| Secrets | No Spaces credentials on mobile |
| Admin-only preset writes | Separate routes — [`../spec.md`](../spec.md) |

---

## Future Considerations

| Topic | Notes |
| --- | --- |
| **`ImportPresetVibeRequest`** | Could add explicit empty-body Form Request — not shipped |
| Import customization | Name suffix, layer subset — **not supported** |
| **`card_image_url` copy** | Could copy bundle thumbnail to dedicated column — today **null** + resource fallback |
| Preset fade columns | If added to **`preset_vibe_sounds`**, define import mapping |
| Idempotent import | Dedupe by user+preset — **not today** |
| Dedicated import policy | **`authorize()`** hook — not wired today |

**Explicitly excluded:** background jobs, async import, AI remix, live preset sync, version engine, partial imports, cloud processing pipelines.

---

## Related Docs

| Document | Path |
| --- | --- |
| **This spec** | `docs/specs/preset-vibes/import/spec.md` |
| Preset catalog (parent) | [`../spec.md`](../spec.md) |
| Create vibe (manual) | [`../../vibes/create-vibe/spec.md`](../../vibes/create-vibe/spec.md) |
| Manage vibe sounds | [`../../vibes/manage-vibe-sounds/spec.md`](../../vibes/manage-vibe-sounds/spec.md) |
| Vibe sounds (redirect) | [`../../vibes/vibe-sounds/spec.md`](../../vibes/vibe-sounds/spec.md) |
| Playback runtime | [`../../vibes/playback-runtime/spec.md`](../../vibes/playback-runtime/spec.md) |
| Offline download | [`../../vibes/offline-download/spec.md`](../../vibes/offline-download/spec.md) |
| Apply cover bundle | [`../../vibes/apply-cover-bundle/spec.md`](../../vibes/apply-cover-bundle/spec.md) |
| Create cover bundle | [`../../covers/create-cover-bundle/spec.md`](../../covers/create-cover-bundle/spec.md) |
| API Resource patterns | [`../../standards/api-resource-patterns.md`](../../standards/api-resource-patterns.md) |
| Form Request patterns | [`../../standards/laravel-form-request-patterns.md`](../../standards/laravel-form-request-patterns.md) |
| Artwork / background | [`../../architecture/storage/artwork-background-strategy.md`](../../architecture/storage/artwork-background-strategy.md) |
| Storage policy | [`../../architecture/storage/storage-strategy.md`](../../architecture/storage/storage-strategy.md) |
| Auth | [`../../standards/front-vibes-auth-core.md`](../../standards/front-vibes-auth-core.md) |
| **back_vibes** | `PresetVibeController::import`, `VibeResource`, `VibeSoundResource`, `PresetVibeImportApiTest.php` |
| **front_vibes** | `PresetVibeDetailPage.vue`, `preset-vibe.service.ts` (`importPresetVibe`, `normalizeImportedVibe`) |

When behaviour changes, update **this file first**, then [`../spec.md`](../spec.md) if catalog boundaries shift, then API, mobile, and tests.
