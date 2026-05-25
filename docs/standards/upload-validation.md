# Upload validation — Laravel-authoritative multipart uploads

**Status:** Active engineering standard (source of truth)  
**Scope:** File upload validation, size/MIME policy, multipart contracts, and client/server responsibilities across Ixora catalog and asset flows  
**Applies to:** `back_vibes`, `ixora-admin`, `front_vibes` (read-only consumer today)

---

## Purpose

Define the **mandatory upload validation architecture** for Ixora: which asset types are allowed, how size and MIME checks run, who may write to object storage, how public CDN URLs are produced, and how clients must treat validation (**UX hints only — Laravel is authoritative**).

**Laravel is the only writer to DigitalOcean Spaces.** Admin and mobile **never upload directly to Spaces**. All bytes pass through authenticated Laravel endpoints as **`multipart/form-data`**, are validated server-side, stored under **canonical object keys**, and exposed to clients as **CDN HTTPS URLs** built from **`DO_SPACES_CDN_URL`**.

This document is the **source of truth** for humans and AI-assisted work on uploads. Feature specs and repo-local copies must stay aligned.

---

## Scope

### In scope

- MIME and size limits for **audio** and **image** uploads
- **`UploadAssetValidator`** as the single policy implementation in Laravel
- Multipart create flows that **require files** and **prohibit URL fields**
- Generic admin replace upload: **`POST /api/admin/uploads`**
- Catalog create-with-files: **`POST /api/sounds`**, **`POST /api/cover-bundles`**
- Layered validation: **FormRequest** + **`UploadAssetValidator`**
- KB vs bytes alignment on Laravel **`max:`** file rules
- **413** vs **422** distinction
- Client UX hints (`ixora-admin/shared/upload-limits.ts`)
- Edge/body limit alignment (Caddy, PHP, App Platform)
- CORS implications for admin multipart POST
- Security boundaries (no Spaces credentials on clients)

### Out of scope

- **Direct client-to-Spaces** uploads, presigned PUT policies, or bucket secrets in admin/mobile
- **Chunk uploads, resumable uploads, signed upload URLs**
- **Transcoding, normalization, image processing, virus scanning, media optimization queues**
- **Mobile end-user upload flows** — not shipped; mobile consumes CDN URLs only
- **Vibe create / preset import** — URL string copy only; no upload pipeline
- **Safe delete / reference counting** — see [`storage-strategy.md`](../architecture/storage/storage-strategy.md)
- CI/CD and OpenTofu secret provisioning

### Applies to

| Layer | Location |
| --- | --- |
| Validator (authoritative) | `back_vibes/app/Services/Storage/UploadAssetValidator.php` |
| Path builder | `back_vibes/app/Services/Storage/StoragePathBuilder.php` |
| Spaces writer | `back_vibes/app/Services/Storage/DigitalOceanSpacesService.php` |
| Generic upload | `UploadAssetController`, `UploadAssetRequest` |
| Sound create | `StoreSoundRequest`, `CreateSoundWithUploadedFiles` |
| Cover create | `StoreCoverBundleRequest`, `CreateCoverBundleWithUploadedFiles` |
| Admin UX hints | `ixora-admin/shared/upload-limits.ts` |
| Edge limits | `back_vibes/docker/frankenphp/Caddyfile`, `zz-uploads.ini` |

---

## Validation Architecture

```
┌─────────────┐   multipart/form-data    ┌──────────────┐   S3 API    ┌─────────────────────┐
│ ixora-admin │ ───────────────────────► │ Laravel API  │ ──────────► │ DigitalOcean Spaces │
│ (browser)   │   Bearer auth only       │ (back_vibes) │ DO_SPACES_* │ (canonical keys)    │
└─────────────┘                          └──────┬───────┘             └──────────┬──────────┘
       │                                        │                                │ CDN
       │  CDN HTTPS URLs from API JSON          │  publicUrl() → DB columns      │
       └────────────────────────────────────────┴────────────────────────────────┘
                                         PostgreSQL (file_url, thumbnail_url, …)
```

### Layered validation pipeline

| Step | Layer | Responsibility |
| --- | --- | --- |
| 1 | **Middleware** | `firebase.auth`; catalog/admin writes also **`admin.approved`** |
| 2 | **FormRequest `rules()`** | Required metadata, **`file`** parts, Laravel **`max:`** (kilobytes), **`prohibited`** URL fields on create |
| 3 | **`UploadAssetValidator`** | Upload validity, **byte** size, MIME → extension (authoritative MIME map) |
| 4 | **Entity checks** (generic upload only) | `entity_id` exists; `asset_type` allowed for `entity_type` |
| 5 | **Write** | `StoragePathBuilder` key → `DigitalOceanSpacesService::putFile` → **`publicUrl()`** → persist CDN URL on row |

### Where `UploadAssetValidator` runs

| Flow | FormRequest | Validator invocation |
| --- | --- | --- |
| **`POST /api/admin/uploads`** | `UploadAssetRequest` | **`withValidator` after hook** → `validateAfterBaseRules()` |
| **`POST /api/sounds`** | `StoreSoundRequest` | **`CreateSoundWithUploadedFiles`** → `assertValidSoundAudio()`, `assertValidSoundThumbnail()` |
| **`POST /api/cover-bundles`** | `StoreCoverBundleRequest` | **`CreateCoverBundleWithUploadedFiles`** → `assertValidCoverCatalogImage()` × 3 |

**Rule:** MIME lists and byte limits live **only** in **`UploadAssetValidator`**. FormRequests derive **`max:`** from constants; actions/assertions enforce bytes + MIME after base rules pass.

### Core principles

| Principle | Rule |
| --- | --- |
| **Single writer** | Only **Laravel** may `put` / `delete` in Spaces |
| **Multipart only** | Upload endpoints accept **`multipart/form-data`** — not JSON-with-URLs on create |
| **No direct client uploads** | Admin and mobile **must not** hold `DO_SPACES_*` or PUT to bucket endpoints |
| **Server validation authoritative** | Client `<input accept>`, hints, and pre-checks are **UX only** |
| **No client-supplied paths** | Object keys from **entity type**, **entity id**, **asset type**, **validated MIME extension** |
| **CDN URLs after success** | DB and API JSON store **`publicUrl()`** strings — not origin endpoints |
| **No transcoding** | Bytes stored as uploaded |
| **Rollback on failure** | Create actions delete partial Spaces keys when DB/upload transaction fails |

Align with [`laravel-form-request-patterns.md`](laravel-form-request-patterns.md) and [`storage-strategy.md`](../architecture/storage/storage-strategy.md).

---

## MIME Rules

Extension is resolved from **detected/reported MIME** via **`UploadAssetValidator::resolveExtension()`** — **not** from client filename alone. Unknown MIME → **422** with field-specific message.

### Audio (catalog sound — `sound` + `audio`)

| Reported MIME (lowercase) | Canonical extension |
| --- | --- |
| `audio/mpeg`, `audio/mp3` | `mp3` |
| `audio/wav`, `audio/x-wav`, `audio/wave` | `wav` |
| `audio/ogg`, `application/ogg` | `ogg` |
| `audio/mp4`, `audio/x-m4a` | `m4a` |
| `audio/aac`, `audio/x-aac` | `aac` |

**User-facing allowed list:** MP3, OGG, WAV, M4A, AAC.

**Sound create requirement:** **`audio_file`** required — validated by **`assertValidSoundAudio()`**.

### Images (thumbnails, artwork, backgrounds, avatar)

| Reported MIME (lowercase) | Canonical extension |
| --- | --- |
| `image/jpeg` | `jpg` |
| `image/png` | `png` |
| `image/webp` | `webp` |

**User-facing allowed list:** JPEG, PNG, WebP (JPEG stored as extension **`jpg`**).

### Image roles by entity

| Entity | Asset type(s) | Create requirement |
| --- | --- | --- |
| **`sound`** | `thumbnail` | **`thumbnail_file`** required on **`POST /api/sounds`** |
| **`cover`** | `thumbnail`, `artwork`, `player_background` | All three **`*_file`** parts required on **`POST /api/cover-bundles`** |
| **`vibe`** | `thumbnail`, `artwork`, `player_background` | Generic **`POST /api/admin/uploads`** only (no shipped vibe multipart create) |
| **`user`** | `avatar` | Generic **`POST /api/admin/uploads`** only |

Cover bundle image requirements: **three separate image files**, each JPEG/PNG/WebP, each ≤ **5 MiB** — see [`create-cover-bundle/spec.md`](../specs/covers/create-cover-bundle/spec.md).

Sound thumbnail requirement: **one image file**, JPEG/PNG/WebP, ≤ **5 MiB** — see [`create-sound/spec.md`](../specs/sounds/create-sound/spec.md).

### `asset_type` by `entity_type` (`POST /api/admin/uploads`)

| `entity_type` | Allowed `asset_type` |
| --- | --- |
| `sound` | `audio`, `thumbnail` |
| `cover` | `thumbnail`, `artwork`, `player_background` |
| `vibe` | `thumbnail`, `artwork`, `player_background` |
| `user` | `avatar` |

---

## File Size Rules

### Authoritative constants (bytes)

| Constant | Bytes | Human limit | Used for |
| --- | ---: | --- | --- |
| `UploadAssetValidator::AUDIO_MAX_BYTES` | **26 214 400** | **25 MiB** | Sound **`audio_file`**; generic `sound`+`audio` upload |
| `UploadAssetValidator::IMAGE_MAX_BYTES` | **5 242 880** | **5 MiB** | All image roles (sound thumbnail, cover images, vibe visuals, avatar) |

**MiB vs MB in copy:** Constants are **binary MiB** (1024²). Admin hint strings say **"25 MB"** / **"5 MB"** for UX — limits are enforced in **bytes** by **`UploadAssetValidator`**.

### Laravel FormRequest `max:` (kilobytes)

Laravel’s **`file` `max:`** rule uses **kilobytes**, not bytes:

```php
intdiv(UploadAssetValidator::AUDIO_MAX_BYTES, 1024)   // 25600 KB
intdiv(UploadAssetValidator::IMAGE_MAX_BYTES, 1024)  // 5120 KB
```

| Field | FormRequest `max:` | Validator byte check |
| --- | ---: | ---: |
| `audio_file` | **25600** KB | **26 214 400** bytes |
| `thumbnail_file` | **5120** KB | **5 242 880** bytes |
| `thumbnail_file`, `artwork_file`, `player_background_file` (cover) | **5120** KB each | **5 242 880** bytes each |
| Generic `file` (admin upload) | *(no FormRequest max)* | **`maxBytes(entity, asset)`** in validator |

**Rule:** When constants change, update **both** FormRequest **`max:`** and **`UploadAssetValidator`** assertions in the same change.

### Worst-case multipart bodies (edge planning)

| Endpoint | Approx. payload |
| --- | --- |
| **`POST /api/sounds`** | 25 MiB audio + 5 MiB thumbnail + metadata overhead |
| **`POST /api/cover-bundles`** | 3 × 5 MiB images + metadata overhead |
| **`POST /api/admin/uploads`** | Single file ≤ 25 MiB (audio) or ≤ 5 MiB (image) |

Edge and PHP limits must be **≥** largest expected **entire request body** before Laravel runs.

---

## Multipart Rules

### Transport

| Rule | Detail |
| --- | --- |
| Content-Type | **`multipart/form-data`** only on upload endpoints |
| Auth | **`Authorization: Bearer <Firebase ID token>`** |
| Admin writes | **`admin.approved`** middleware on catalog create and **`POST /api/admin/uploads`** |
| Client target | **Laravel API origin** — never Spaces bucket URL |
| Create-with-files | **Single POST** with all file parts — ixora-admin does **not** pre-upload via `/api/admin/uploads` on sound/cover **create** |

### Endpoints

| Method | Path | Required file parts | Sets entity URLs on response |
| --- | --- | --- | --- |
| `POST` | `/api/sounds`, `/api/admin/sounds` | `audio_file`, `thumbnail_file` | Yes — **201** **`SoundResource`** |
| `POST` | `/api/cover-bundles` | `thumbnail_file`, `artwork_file`, `player_background_file` | Yes — **201** **`CoverBundleResource`** |
| `POST` | `/api/admin/uploads` | `file` + `entity_type`, `entity_id`, `asset_type` | No — returns `{ key, url, … }`; caller PATCHes entity when not using create-with-files |

### Canonical object keys (after validation)

Extensions match **validated MIME** (`mp3`, `ogg`, `wav`, `m4a`, `aac`, `jpg`, `png`, `webp`):

```
sounds/{sound_id}/audio/original.{ext}
sounds/{sound_id}/thumbnail/thumbnail.{ext}

covers/{cover_bundle_id}/thumbnail/thumbnail.{ext}
covers/{cover_bundle_id}/artwork/artwork.{ext}
covers/{cover_bundle_id}/player-background/background.{ext}

vibes/{vibe_id}/thumbnail/thumbnail.{ext}
vibes/{vibe_id}/artwork/artwork.{ext}
vibes/{vibe_id}/player-background/background.{ext}

users/{user_id}/avatar/avatar.{ext}
```

### Post-upload URL persistence

| Rule | Detail |
| --- | --- |
| Public URL host | **`DO_SPACES_CDN_URL`** via **`DigitalOceanSpacesService::publicUrl()`** |
| DB columns | Full HTTPS CDN strings (`file_url`, `thumbnail_url`, `artwork_url`, …) |
| API response | **`SoundResource`** / **`CoverBundleResource`** expose persisted URLs — see [`api-resource-patterns.md`](api-resource-patterns.md) |
| Generic upload JSON | `{ "data": { "key", "url", "mime_type", "size", "entity_type", "asset_type" } }` |

**CDN URLs exist only after successful upload** — clients must not assume URLs before **201** response.

### Edge / PHP body limits (shipped reference)

| Layer | Setting | Value |
| --- | --- | --- |
| **Caddy** `request_body.max_size` | `back_vibes/docker/frankenphp/Caddyfile` | **64 MiB** |
| **PHP** `upload_max_filesize` / `post_max_size` | `zz-uploads.ini` | **64M** |

**DigitalOcean App Platform / reverse proxy:** Platform body limits must also allow worst-case multipart (cover create ~15 MiB files + overhead). If the platform rejects first → **413** before Laravel.

**Ops rule:** Edge + PHP + platform limits **≥** largest multipart body; Laravel **`max:`** + **`UploadAssetValidator`** enforce per-file limits when the request reaches the app.

---

## UploadAssetValidator Rules

**Class:** `App\Services\Storage\UploadAssetValidator` — **central authority** for MIME maps, byte limits, extension resolution, and entity/asset pairing.

### Public API

| Method | Purpose |
| --- | --- |
| `AUDIO_MAX_BYTES`, `IMAGE_MAX_BYTES` | Size constants — imported by FormRequests |
| `assetTypesForEntity(string $entityType)` | Allowed `asset_type` list per entity |
| `expectsAudio(string $entityType, string $assetType)` | True for `sound` + `audio` |
| `maxBytes(string $entityType, string $assetType)` | **26 214 400** or **5 242 880** |
| `resolveExtension(UploadedFile, entity, asset)` | MIME → extension or **null** |
| `validateAfterBaseRules(Validator)` | Generic upload after-hook: entity exists, asset pairing, file validity, size, MIME |
| `assertValidSoundAudio(UploadedFile)` | Sound create — throws **422** on `audio_file` |
| `assertValidSoundThumbnail(UploadedFile)` | Sound create — throws **422** on `thumbnail_file` |
| `assertValidCoverCatalogImage(UploadedFile, assetType)` | Cover create — throws **422** on `{assetType}_file` |

### Validation checks (in order)

1. **`$file->isValid()`** — PHP upload error → *"The upload failed."*
2. **`$file->getSize()`** vs **`maxBytes()`** — *"Audio must not exceed 25 MB."* / *"Image must not exceed 5 MB."*
3. **`resolveExtension()`** non-null — allowed MIME list message
4. (Generic upload) **`entity_id`** exists in entity table
5. (Generic upload) **`asset_type`** ∈ **`assetTypesForEntity()`**

### Error field names

| Flow | Validator throws on |
| --- | --- |
| Sound create | `audio_file`, `thumbnail_file` |
| Cover create | `thumbnail_file`, `artwork_file`, `player_background_file` |
| Generic upload | `file`, `entity_id`, `asset_type` |

### Policy change procedure

1. Update **`UploadAssetValidator`** constants and/or MIME maps
2. Update FormRequest **`max:`** via **`intdiv(..., 1024)`**
3. Update **`ixora-admin/shared/upload-limits.ts`**
4. Run feature tests (`AdminUploadAssetTest`, sound/cover create tests)
5. Verify edge **64 MiB** (or higher) still covers worst-case multipart

---

## URL Prohibition Rules

Create-with-files flows **`prohibit`** URL string fields so admins cannot bypass the upload pipeline.

### `StoreSoundRequest` (`POST /api/sounds`)

| Required files | Prohibited fields |
| --- | --- |
| `audio_file`, `thumbnail_file` | `file_url`, `thumbnail_url`, `audio_url`, `artwork_url`, `player_background_url`, `description` |

### `StoreCoverBundleRequest` (`POST /api/cover-bundles`)

| Required files | Prohibited fields |
| --- | --- |
| `thumbnail_file`, `artwork_file`, `player_background_file` | `thumbnail_url`, `artwork_url`, `player_background_url` |

### Edit/update flows (separate)

**PATCH** endpoints may accept optional HTTPS URL strings where documented (e.g. **`UpdateSoundRequest`**, **`UpdateCoverBundleRequest`**) — metadata correction without re-upload. That is **not** a substitute for create-with-files.

### Flows with no upload

| Flow | URL handling |
| --- | --- |
| Vibe create/update (mobile) | JSON URL strings only — **no multipart**; separate validation gap on manual create |
| Preset import | Server copies bundle URLs — **no client upload** |

---

## Security Rules

| Rule | Requirement |
| --- | --- |
| **Credentials** | `DO_SPACES_KEY`, `DO_SPACES_SECRET`, bucket config — **Laravel runtime only** |
| **No client secrets** | Admin and mobile get Firebase client config + public API base URL only |
| **No direct Spaces writes** | No presigned upload URLs for browser/mobile to bypass API |
| **No mobile uploads** | `front_vibes` consumes CDN URLs only — [`mobile-cdn-validation.md`](../architecture/storage/mobile-cdn-validation.md) |
| **Auth on every upload route** | `firebase.auth`; catalog/admin uploads also **`admin.approved`** |
| **No path injection** | Clients cannot supply arbitrary object keys |
| **MIME enforcement** | Do not trust filename extension or client `Content-Type` without validator mapping |
| **Prohibited URL fields** | Prevents catalog create without validated bytes |
| **CORS** | Admin deployment origin(s) must be in API **`CORS_ALLOWED_ORIGINS`** for multipart **`POST`** to Laravel API |
| **Git hygiene** | Never commit `.env`, Spaces keys, or real bucket secrets |

---

## Error Response Rules

### HTTP status mapping

| HTTP | Typical cause | Response body | Client UX |
| --- | --- | --- | --- |
| **401** | Missing/invalid Firebase token or unknown user | `{ "message": "…" }` | Re-sign in |
| **403** | Authenticated but not **`admin.approved`** | `{ "message": "Admin access is not approved." }` | Access-request flow |
| **413** | Body too large at **edge/reverse proxy/platform** **before** Laravel | Often **no** Laravel JSON; browser may show generic/CORS error | Admin: friendly size message |
| **422** | Laravel validation — MIME, byte size, missing file, **prohibited** URL field, bad entity | `{ "message", "errors": { "field": ["…"] } }` | Flatten **`errors`** for inline display |
| **5xx** | Server or Spaces failure | Generic message | Retry; check logs / rollback |
| **0** (XHR) | Network failure or wrong API base URL | — | Connection / config message |

### 413 vs 422 (critical distinction)

| Status | When | Laravel JSON? | Example |
| --- | --- | --- | --- |
| **422** | Request **reached Laravel**; FormRequest or **`UploadAssetValidator`** rejected a field | **Yes** — `errors` bag | 26 MiB audio file; `text/plain` as audio; `file_url` prohibited |
| **413** | Request rejected **before** Laravel (Caddy **`max_size`**, App Platform body limit, PHP **`post_max_size`**) | **Often no** | Entire multipart body exceeds edge limit |

**Mitigation:** Align Caddy (**64 MiB**), PHP (**64M**), platform limits, and Laravel per-file rules. Cover create needs headroom for **three 5 MiB** images plus multipart boundaries.

**Admin reference:**

```typescript
// ixora-admin/services/api/laravel-api-error.ts
if (status === 413) {
  return 'File is too large. Audio max 25 MB, images max 5 MB.';
}
```

### CORS implications

- **ixora-admin** POSTs multipart to the **API origin**, not CDN.
- **`CORS_ALLOWED_ORIGINS`** must include admin deployment URL(s).
- **413** or network failures at the edge may surface as **opaque browser errors** without Laravel **`errors`** JSON — clients must not assume **422** shape for oversize bodies rejected early.
- **Mobile (`front_vibes`)** has **no upload CORS path** today — consumption-only per [`mobile-cdn-validation.md`](../architecture/storage/mobile-cdn-validation.md).

---

## Client Responsibilities

### ixora-admin (only upload client today)

| Responsibility | Implementation |
| --- | --- |
| Send files to **Laravel API origin** | Catalog forms: single multipart POST; replace flow: `upload.service.ts` |
| **Never** call Spaces directly | No `DO_SPACES_*` in Nuxt env or static build |
| UX hints only | `shared/upload-limits.ts` — `AUDIO_ACCEPT_ATTR`, `IMAGE_ACCEPT_ATTR`, hint strings |
| Match server limits in copy | Audio **25 MB**; images **5 MB**; same format lists as validator |
| `<input accept>` | File picker hint — server may reject spoofed types |
| Auth header | `Authorization: Bearer <Firebase ID token>` |
| Error display | `friendlyLaravelUploadHttpError()` — **413** and **422** |
| Pre-validation | Optional client size checks — **not authoritative** |

**Client constants** mirror server bytes for UX:

```typescript
export const AUDIO_UPLOAD_MAX_BYTES = 25 * 1024 * 1024;  // 26_214_400
export const IMAGE_UPLOAD_MAX_BYTES = 5 * 1024 * 1024;   // 5_242_880
```

Changing limits **starts in Laravel**, then updates **`upload-limits.ts`**.

### front_vibes (mobile)

| Responsibility | Implementation |
| --- | --- |
| **No upload pipeline** | Consumes **HTTPS CDN URLs** from API JSON only |
| **No Spaces credentials** | No bucket keys in app bundle or env |
| Future user uploads | Must use same Laravel-multipart pattern — **not** direct-to-Spaces |

Server validation is **authoritative**; client-side pre-validation is **UX only**.

---

## Risks

| Risk | Impact | Mitigation |
| --- | --- | --- |
| **KB/byte drift** | FormRequest passes Laravel **`max:`** but validator rejects (or vice versa) | Derive **`max:`** from **`UploadAssetValidator`** constants only |
| **Edge 413 before Laravel** | Admin sees generic error without field-level **`errors`** | Keep Caddy/PHP/platform ≥ worst-case multipart; map **413** in admin UX |
| **CORS misconfiguration** | Admin multipart POST blocked in browser | Maintain **`CORS_ALLOWED_ORIGINS`** for admin origin |
| **Duplicate MIME lists** | Policy copied outside validator — inconsistent rejection | All MIME/size checks through **`UploadAssetValidator`** |
| **URL bypass on create** | Catalog rows without validated bytes | **`prohibited`** on URL fields in create FormRequests |
| **Partial upload on failure** | Orphan Spaces objects | **`CreateSoundWithUploadedFiles`** / **`CreateCoverBundleWithUploadedFiles`** delete keys on rollback |
| **Client-only validation** | Admins think file is valid but server rejects | Document server as authoritative; keep hints aligned |
| **Assuming CDN URL before 201** | Broken links in UI | URLs only after successful upload + **`publicUrl()`** persist |
| **Platform body limit < 64 MiB** | Cover create fails with **413** on App Platform | Ops verify platform ingress limit vs 3×5 MiB + overhead |

**Explicitly not mitigated today (out of scope):** virus scanning, transcoding, chunk/resumable uploads, presigned direct uploads, image optimization queues.

---

## Validation

### Automated (Laravel — required on policy changes)

| Test area | Location |
| --- | --- |
| Generic admin upload | `tests/Feature/AdminUploadAssetTest.php` |
| Sound create authorization / multipart | `tests/Feature/SoundCatalogAuthorizationTest.php` |
| Cover create | Cover bundle feature tests |
| Storage fakes | `Storage::fake('spaces')` in feature tests |

**Change checklist:**

1. Update **`UploadAssetValidator`**
2. Update FormRequest **`max:`** rules
3. Update **`ixora-admin/shared/upload-limits.ts`**
4. Run upload feature tests
5. Verify edge **64 MiB** (or higher) covers worst-case multipart

### Manual / staging checklist

- [ ] Create sound with valid MP3 + PNG → **201**; CDN URLs load in browser
- [ ] Create cover bundle with three WebP/JPEG files → **201**; all three CDN URLs set
- [ ] Oversized audio (>25 MiB) → **422** on `audio_file` (or **413** if edge rejects first)
- [ ] Oversized image (>5 MiB) → **422** on image field
- [ ] Disallowed MIME (e.g. `text/plain` as audio) → **422**
- [ ] `POST /api/sounds` with `file_url` instead of `audio_file` → **422** (`prohibited`)
- [ ] `POST /api/cover-bundles` with `thumbnail_url` → **422** (`prohibited`)
- [ ] Non-admin user → **403** on upload routes
- [ ] No `DO_SPACES_*` in ixora-admin build env or front_vibes bundle
- [ ] Failed mid-create rolls back partial Spaces keys
- [ ] Admin multipart works from deployed origin (CORS + body limit)

### Code review gates

- [ ] New upload routes use **`UploadAssetValidator`** — no duplicated MIME lists
- [ ] New create-with-files flows **`prohibit`** URL bypass fields
- [ ] **`publicUrl()`** uses CDN host in responses and DB
- [ ] No transcoding assumptions in upload handlers
- [ ] Response uses JsonResources per [`api-resource-patterns.md`](api-resource-patterns.md)

---

## Related Files

### Standards and architecture

| Document | Path |
| --- | --- |
| **This standard** | `docs/standards/upload-validation.md` |
| Form Request patterns | [`laravel-form-request-patterns.md`](laravel-form-request-patterns.md) |
| API Resource patterns | [`api-resource-patterns.md`](api-resource-patterns.md) |
| Storage policy | [`docs/architecture/storage/storage-strategy.md`](../architecture/storage/storage-strategy.md) |
| Mobile CDN validation | [`docs/architecture/storage/mobile-cdn-validation.md`](../architecture/storage/mobile-cdn-validation.md) |
| Auth (Bearer on uploads) | [`front-vibes-auth-core.md`](front-vibes-auth-core.md) |

### Feature specs

| Document | Path |
| --- | --- |
| Create sound | [`docs/specs/sounds/create-sound/spec.md`](../specs/sounds/create-sound/spec.md) |
| Create cover bundle | [`docs/specs/covers/create-cover-bundle/spec.md`](../specs/covers/create-cover-bundle/spec.md) |

### Implementation (`back_vibes`)

| File | Role |
| --- | --- |
| `app/Services/Storage/UploadAssetValidator.php` | MIME maps, byte limits, assertions |
| `app/Services/Storage/StoragePathBuilder.php` | Canonical object keys |
| `app/Services/Storage/DigitalOceanSpacesService.php` | Spaces I/O, **`publicUrl()`** |
| `app/Http/Requests/StoreSoundRequest.php` | Sound create multipart + prohibited URLs |
| `app/Http/Requests/StoreCoverBundleRequest.php` | Cover create multipart + prohibited URLs |
| `app/Http/Requests/Admin/UploadAssetRequest.php` | Generic admin upload + after-hook validator |
| `app/Actions/Sound/CreateSoundWithUploadedFiles.php` | Sound create transaction + rollback |
| `app/Actions/CoverBundle/CreateCoverBundleWithUploadedFiles.php` | Cover create transaction + rollback |
| `app/Http/Controllers/Api/Admin/UploadAssetController.php` | Generic upload endpoint |
| `docker/frankenphp/Caddyfile` | **`request_body max_size 64MiB`** |
| `docker/frankenphp/conf.d/zz-uploads.ini` | PHP **64M** upload/post limits |

### Implementation (`ixora-admin`)

| File | Role |
| --- | --- |
| `shared/upload-limits.ts` | Client UX constants and accept attributes |
| `services/api/laravel-api-error.ts` | **413** / **422** friendly messages |
| `SoundForm.vue`, `CoverBundleForm.vue` | Multipart create UI |

When upload policy changes, update **this file first**, then Laravel validator, FormRequests, admin hints, feature tests, edge/PHP/platform limits, and aligned feature specs.
