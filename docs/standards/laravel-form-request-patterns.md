# Laravel Form Request Patterns — validation and request boundaries

**Status:** Active engineering standard (source of truth)  
**Scope:** Input validation, authorization boundaries, and error contracts for **`back_vibes`** API  
**Applies to:** `app/Http/Requests/**`, API controllers, admin and mobile clients

---

## Purpose

Define the **mandatory Form Request architecture** for Ixora’s Laravel API: where validation lives, how **`validated()`** forms the trust boundary, how file and URL rules align with **`UploadAssetValidator`**, and how nested resources (e.g. **`vibe_sounds`**) enforce playback semantics.

**Every mutable API endpoint must use a dedicated Form Request.** Controllers stay thin: **authorize → validate → persist** using **`$request->validated()`** only. **Never trust raw `$request->all()`** or client-supplied identity/ownership fields.

This document is the **source of truth** for humans and AI-assisted backend work. Feature specs reference concrete rules but do not replace this standard.

---

## Scope

### In scope

- **Form Request classes** under `app/Http/Requests/`
- **`authorize()`** vs middleware vs **`$this->authorize()`** (policies)
- **`rules()`**, **`prepareForValidation()`**, **`withValidator()`** / **`after`** hooks
- **`validated()`** as the only input passed to models/actions
- **`prohibited`** fields on create-with-files flows
- **Multipart** file validation + **`UploadAssetValidator`**
- **URL string** validation (admin PATCH; required vibe whitelist gap)
- **PATCH `sometimes`** semantics
- **Nested** attach/update: **`AttachVibeSoundRequest`**, **`UpdateVibeSoundRequest`**
- **`play_mode`**, **`repeat_interval_seconds`**, server-derived **`loop`**
- **422** error shape — shared by mobile and admin

### Out of scope

- **DTO frameworks**, **CQRS validation pipelines**, **schema registries**
- **Client-side Zod/Yup** as server replacement — UX hints only ([`upload-validation.md`](upload-validation.md))
- **GraphQL / protobuf** validation
- **Firebase token verification** implementation (middleware/controller) — only boundary rules here

### Applies to

| Layer | Location |
| --- | --- |
| Form Requests | `back_vibes/app/Http/Requests/` |
| Upload MIME/size policy | `App\Services\Storage\UploadAssetValidator` |
| Controllers | `app/Http/Controllers/Api/` |
| Policies | `app/Policies/` |
| Clients | `front_vibes`, `ixora-admin` (parse **422** `errors`) |

---

## Validation Architecture

```
HTTP Request
     │
     ├── Middleware (firebase.auth, admin.approved)
     │
     ├── FormRequest::authorize()     ← usually true; not primary auth gate
     │
     ├── prepareForValidation()         ← optional normalization (e.g. is_active)
     │
     ├── rules() + withValidator()      ← Laravel rules + UploadAssetValidator after hook
     │
     ├── validated()                    ← TRUST BOUNDARY — whitelist only
     │
     └── Controller
            ├── $this->authorize(...)   ← Policy for resource ownership (nested routes)
            ├── $request->validated()   ← spread into create/update/attach
            └── derive server fields    ← user_id, loop, repeat_interval cleanup
```

| Rule | Detail |
| --- | --- |
| **Form Request mandatory** | All **POST / PUT / PATCH** domain writes type-hint a Form Request |
| **Controller thinness** | No inline `$request->validate([...])` in controllers for domain endpoints |
| **`validated()` only** | Persist **`$request->validated()`** (or Request helper methods built on it) |
| **Helper methods on Request** | e.g. **`resolvedTags()`**, **`resolvedMetadata()`**, **`normalizedLayers()`** — encapsulate trim/normalize after validation |
| **Shared API** | Same Form Request + **422** shape for **mobile** and **admin** on the same route |

### Current Form Request inventory

| Request | Endpoint(s) | Content-Type |
| --- | --- | --- |
| `StoreVibeRequest` | `POST /api/vibes` | JSON |
| `UpdateVibeRequest` | `PATCH /api/vibes/{id}` | JSON |
| `AttachVibeSoundRequest` | `POST /api/vibes/{vibe}/sounds` | JSON |
| `UpdateVibeSoundRequest` | `PATCH /api/vibes/{vibe}/sounds/{sound}` | JSON |
| `StoreSoundRequest` | `POST /api/sounds` | multipart |
| `UpdateSoundRequest` | `PATCH /api/sounds/{id}` | JSON |
| `StoreCoverBundleRequest` | `POST /api/cover-bundles` | multipart |
| `UpdateCoverBundleRequest` | `PATCH /api/cover-bundles/{id}` | JSON |
| `UploadAssetRequest` | `POST /api/admin/uploads` | multipart |
| `StorePresetVibeRequest` / `UpdatePresetVibeRequest` | Admin preset CRUD | JSON |
| `SyncPresetVibeSoundsRequest` | `PUT /api/preset-vibes/{id}/sounds` | JSON |
| `SyncFirebaseUserRequest` | `POST /api/auth/sync` | JSON (empty rules) |

---

## Authorization Rules

### Three layers (do not collapse)

| Layer | Responsibility | Example |
| --- | --- | --- |
| **Route middleware** | Authenticated user; admin gate | `firebase.auth`, `admin.approved` |
| **FormRequest `authorize()`** | Returns **`true`** today for most domain requests | Policy checks **not** duplicated here |
| **Controller `$this->authorize()`** | Resource ownership / ability | `VibeSoundController`: **`update`**, **`view`** on **`Vibe`** |

**Form Request `authorize(): true` does not mean “anyone may call.”** Middleware and policies enforce access.

### Identity and ownership (never from body)

| Field | Rule |
| --- | --- |
| **`user_id`** | **Never** accepted in vibe create/update requests — set in controller: **`'user_id' => $request->user()->id`** |
| **Firebase identity** | From verified **Bearer token** / middleware — **never** from JSON body (`firebase_uid`, email override) |
| **`SyncFirebaseUserRequest`** | **Empty `rules()`** — body ignored; sync uses verified token claims in controller |

### Nested vibe sounds

| Action | Authorization |
| --- | --- |
| `GET …/sounds` | **`$this->authorize('view', $vibe)`** |
| `POST/PATCH/DELETE …/sounds` | **`$this->authorize('update', $vibe)`** |

Attach/update Form Requests do **not** re-check ownership — controller policy runs first.

---

## File Validation Rules

### Two-tier validation

| Tier | Where | What |
| --- | --- | --- |
| **1. FormRequest `file` + `max:`** | `StoreSoundRequest`, `StoreCoverBundleRequest`, `UploadAssetRequest` | Laravel file presence + **KB limit** aligned with bytes |
| **2. `UploadAssetValidator`** | Action (`CreateSoundWithUploadedFiles`) or **`withValidator` after hook** (`UploadAssetRequest`) | MIME map, byte size, extension resolution |

### Max KB alignment

Laravel’s **`max:`** on file rules is in **kilobytes**. Derive from **`UploadAssetValidator`** constants:

```php
// Audio — 25 MiB
'audio_file' => ['required', 'file', 'max:'.intdiv(UploadAssetValidator::AUDIO_MAX_BYTES, 1024)],

// Image — 5 MiB
'thumbnail_file' => ['required', 'file', 'max:'.intdiv(UploadAssetValidator::IMAGE_MAX_BYTES, 1024)],
```

| Constant | Bytes | KB (`intdiv(..., 1024)`) |
| --- | --- | --- |
| `AUDIO_MAX_BYTES` | 26 214 400 | 25 600 |
| `IMAGE_MAX_BYTES` | 5 242 880 | 5 120 |

**Rule:** When **`UploadAssetValidator`** limits change, update **FormRequest `max:`** in the same change.

### Multipart create flows

| Request | Required files | Prohibited URL bypass |
| --- | --- | --- |
| **`StoreSoundRequest`** | `audio_file`, `thumbnail_file` | `file_url`, `thumbnail_url`, `audio_url`, … **`prohibited`** |
| **`StoreCoverBundleRequest`** | `thumbnail_file`, `artwork_file`, `player_background_file` | `thumbnail_url`, `artwork_url`, `player_background_url` **`prohibited`** |

See [`upload-validation.md`](upload-validation.md).

### Generic admin upload (`UploadAssetRequest`)

```php
'entity_type' => ['required', 'string', Rule::in(['sound', 'cover', 'vibe', 'user'])],
'entity_id'   => ['required', 'integer', 'min:1'],
'asset_type'  => ['required', 'string'],
'file'        => ['required', 'file'],
// + withValidator → UploadAssetValidator::validateAfterBaseRules($validator)
```

MIME/size/entity pairing enforced in **`validateAfterBaseRules`** after base rules pass.

### Multipart normalization

**`prepareForValidation()`** on store requests normalizes **`is_active`** from form strings (`"true"`, `"1"`, `"0"`) via **`filter_var(..., FILTER_VALIDATE_BOOLEAN)`** before boolean rule runs.

---

## URL Validation Rules

### Admin catalog PATCH (reference pattern)

**`UpdateCoverBundleRequest`** whitelists visual URLs:

```php
'thumbnail_url'         => ['sometimes', 'nullable', 'url', 'max:2048'],
'artwork_url'           => ['sometimes', 'nullable', 'url', 'max:2048'],
'player_background_url' => ['sometimes', 'nullable', 'url', 'max:2048'],
```

**`UpdateSoundRequest`** allows optional **`file_url`** / **`thumbnail_url`** strings (`max:2048`) for admin metadata PATCH — separate from multipart create.

### Vibe visual URLs — **required whitelist (current gap)**

Mobile create/edit send **`thumbnail_url`**, **`artwork_url`**, **`player_background_url`** JSON strings. **Intended rules** (not shipped):

```php
'thumbnail_url'         => ['nullable', 'string', 'max:2048'], // or 'url' when present
'artwork_url'           => ['nullable', 'string', 'max:2048'],
'player_background_url' => ['nullable', 'string', 'max:2048'],
```

| Request | Shipped rules | Visual URLs persisted? |
| --- | --- | --- |
| **`StoreVibeRequest`** | `name`, `description`, `is_active` only | **No** — dropped by **`validated()`** |
| **`UpdateVibeRequest`** | Same | **No** |

Documented in [`create-vibe/spec.md`](../specs/vibes/create-vibe/spec.md) and [`update-vibe/spec.md`](../specs/vibes/update-vibe/spec.md). **Fix:** add whitelist to both requests — mirror **`UpdateCoverBundleRequest`** URL rules.

### URL vs upload authority

- **Create-with-files:** URL fields **`prohibited`** — forces upload pipeline.
- **Vibe create/edit:** URL **strings only** (copied from cover bundle) — **no files** — requires whitelist, not prohibition.

---

## Nested Resource Rules

### Vibe sounds — attach (`AttachVibeSoundRequest`)

| Field | Rules |
| --- | --- |
| **`sound_id`** | **`required`**, **`integer`**, **`exists:sounds,id`** |
| **`volume`** | **`sometimes`**, 0–100 |
| **`sort_order`** | **`sometimes`**, **`integer`**, **`min:0`** |
| **`play_mode`** | **`sometimes`**, **`in:loop,once,interval`** |
| **`repeat_interval_seconds`** | **`nullable`**, **`integer`**, **`min:1`**, **`required_if:play_mode,interval`** |
| **`start_offset_seconds`** | **`nullable`**, **`integer`**, **`min:0`** |
| **`play_duration_seconds`** | **`nullable`**, **`integer`**, **`min:1`** |
| **`fade_in_seconds` / `fade_out_seconds`** | **`nullable`**, **`integer`**, **`min:0`** |

**Not in rules:** **`loop`** — **derived server-side** in controller:

```php
'loop' => $playMode === 'loop',
'repeat_interval_seconds' => $playMode === 'interval' ? (...) : null,
```

See [`manage-vibe-sounds/spec.md`](../specs/vibes/manage-vibe-sounds/spec.md).

### Vibe sounds — update (`UpdateVibeSoundRequest`)

All pivot fields **`sometimes`** (PATCH partial update). Same **`play_mode`** / **`required_if:play_mode,interval`** for **`repeat_interval_seconds`**.

**Controller post-validation logic:** if **`play_mode`** absent but **`repeat_interval_seconds`** sent → **strip** interval to avoid orphaned pivot data. If **`play_mode`** present → re-derive **`loop`** and interval nulling (same as attach).

### Preset sounds sync (`SyncPresetVibeSoundsRequest`)

- Nested array **`sounds.*.sound_id`** — **`required`**, **`distinct`**, **`exists:sounds,id`**
- **`play_mode`** — **`Rule::in(['loop', 'once', 'interval'])`**
- **`withValidator` after** — interval required per row when mode is **`interval`** (mirrors attach semantics)
- **`normalizedLayers()`** — maps aliases (`start_delay_seconds`, `duration_seconds`), derives **`loop`**, sorts by **`sort_order`**

---

## PATCH Semantics

| Pattern | Usage |
| --- | --- |
| **`sometimes`** | Field validated **only if present** in request body |
| **`sometimes`, `required`** | If key sent, value must be non-empty — e.g. **`name`** on update |
| **`nullable`** | Explicit null allowed (clearable fields) |
| **Absent key** | Ignored — no change to that column on update |

Examples:

```php
// UpdateVibeRequest — partial metadata
'name'        => ['sometimes', 'string', 'max:255'],
'description' => ['nullable', 'string'],
'is_active'   => ['sometimes', 'boolean'],

// UpdateVibeSoundRequest — partial pivot
'volume' => ['sometimes', 'integer', 'min:0', 'max:100'],
```

**Create (POST)** uses **`required`** for mandatory fields, not **`sometimes`**.

---

## Security Rules

| Rule | Requirement |
| --- | --- |
| **Trust boundary** | Only **`validated()`** keys reach Eloquent **`create`/`update`/`attach`** |
| **Prohibited fields** | Block URL/upload bypass on file-create endpoints |
| **No client `user_id`** | Ownership assigned from **`$request->user()`** |
| **No Firebase body trust** | Identity from verified token only |
| **`exists:sounds,id`** | Prevents attaching non-catalog **`sound_id`** |
| **`exists:cover_bundles,id`** | Preset admin only — valid FK references |
| **Enum closed sets** | **`play_mode`**, **`entity_type`** — **`Rule::in()`** / **`in:`** — no free-form modes |
| **Admin routes** | **`admin.approved`** middleware on catalog writes — Form Request does not replace it |
| **Mass assignment** | Model **`$fillable`** + **`validated()`** intersection — never **`$request->except()`** |

---

## Error Response Rules

Failed validation returns **HTTP 422** with Laravel shape:

```json
{
  "message": "The name field is required. (and 1 more error)",
  "errors": {
    "name": ["The name field is required."],
    "audio_file": ["Audio must not exceed 25 MB."]
  }
}
```

| Aspect | Rule |
| --- | --- |
| **Status** | **422 Unprocessable Entity** |
| **`errors`** | Object keyed by **field name** (dot notation for nested: **`sounds.0.repeat_interval_seconds`**) |
| **Messages** | Human-readable strings per rule failure |
| **Clients** | Mobile/admin flatten **`errors`** for UI — e.g. **`friendlyLaravelUploadHttpError`** |
| **Auth failures** | **401** / **403** — **`{ "message": "…" }`**, not Form Request validation |

**413** (body too large) may occur **before** Form Request runs — see [`upload-validation.md`](upload-validation.md).

---

## Risks

| Risk | Impact |
| --- | --- |
| **Missing whitelist** (`StoreVibeRequest`) | Client sends valid URLs; server silently drops them |
| **`$request->all()` in controller** | Unvalidated fields persisted — security/data corruption |
| **`loop` trusted from client** | Incorrect playback semantics — must derive from **`play_mode`** |
| **KB/byte drift** | FormRequest **`max:`** out of sync with **`UploadAssetValidator`** |
| **`authorize(): true` misunderstood** | Developers skip middleware/policy — open endpoints |
| **Orphan `repeat_interval_seconds`** | Interval set without **`play_mode=interval`** — mitigated in **`UpdateVibeSoundController`** |
| **Duplicate validation** | MIME rules copied outside **`UploadAssetValidator`** — inconsistent policy |
| **Breaking rule changes** | Mobile/admin **422** on previously accepted payloads |

---

## Validation

### Code review checklist

- [ ] New write endpoint has dedicated **Form Request** class
- [ ] Controller uses **`$request->validated()`** only (or Request helper built on it)
- [ ] **`user_id`**, **`firebase_uid`**, and ownership fields **not** in rules
- [ ] File creates use **`prohibited`** on URL bypass fields
- [ ] File **`max:`** uses **`intdiv(UploadAssetValidator::*_MAX_BYTES, 1024)`**
- [ ] MIME/size for uploads goes through **`UploadAssetValidator`**
- [ ] **`play_mode`** uses closed enum; **`loop`** derived in controller
- [ ] PATCH updates use **`sometimes`** appropriately
- [ ] Nested **`sound_id`** uses **`exists:sounds,id`**
- [ ] Vibe visual URLs whitelisted when product requires persistence

### Automated

- Feature tests assert **422** + **`errors`** key paths
- Upload tests cover oversize file, prohibited URL field, invalid MIME

### Known alignment tasks

- [ ] Add visual URL rules to **`StoreVibeRequest`** and **`UpdateVibeRequest`**

---

## Related Files

| Document | Path |
| --- | --- |
| **This standard** | `docs/standards/laravel-form-request-patterns.md` |
| Upload validation | [`docs/standards/upload-validation.md`](upload-validation.md) |
| API Resource output | [`docs/standards/api-resource-patterns.md`](api-resource-patterns.md) |
| Manage vibe sounds | [`docs/specs/vibes/manage-vibe-sounds/spec.md`](../specs/vibes/manage-vibe-sounds/spec.md) |
| Create vibe | [`docs/specs/vibes/create-vibe/spec.md`](../specs/vibes/create-vibe/spec.md) |
| Update vibe | [`docs/specs/vibes/update-vibe/spec.md`](../specs/vibes/update-vibe/spec.md) |
| Create sound | [`docs/specs/sounds/create-sound/spec.md`](../specs/sounds/create-sound/spec.md) |
| Create cover bundle | [`docs/specs/covers/create-cover-bundle/spec.md`](../specs/covers/create-cover-bundle/spec.md) |
| Auth | [`docs/standards/front-vibes-auth-core.md`](front-vibes-auth-core.md) |
| **back_vibes — Requests** | `app/Http/Requests/StoreVibeRequest.php` |
| | `app/Http/Requests/UpdateVibeRequest.php` |
| | `app/Http/Requests/AttachVibeSoundRequest.php` |
| | `app/Http/Requests/UpdateVibeSoundRequest.php` |
| | `app/Http/Requests/StoreSoundRequest.php` |
| | `app/Http/Requests/StoreCoverBundleRequest.php` |
| | `app/Http/Requests/Admin/UploadAssetRequest.php` |
| **Validator** | `app/Services/Storage/UploadAssetValidator.php` |
| **Controllers** | `VibeController.php`, `VibeSoundController.php`, `SoundController.php`, `CoverBundleController.php` |

When validation behaviour changes, update **this file first**, then Form Request classes, feature specs, and client error handling.
