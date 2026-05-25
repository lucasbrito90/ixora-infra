# Create Sound — catalog audio asset (admin)

**Status:** Active feature specification (source of truth)  
**Version:** 1.0 (matches current `back_vibes` + `ixora-admin` implementation)  
**Feature ID:** `sounds/create-sound`

---

## Goal

Enable an **approved Ixora admin** to create a **reusable catalog Sound** in one operation: submit metadata plus **audio and thumbnail files**, have **Laravel** validate uploads, write objects to **DigitalOcean Spaces**, persist **CDN HTTPS URLs** on the sound row, and expose the sound to **mobile** and admin consumers via the standard sounds API.

**Success criteria:**

- Admin creates a sound without pasting URLs or holding Spaces credentials.
- Database row contains metadata + **`file_url`** + **`thumbnail_url`** only (no raw object keys from client).
- Mobile and admin read the same public CDN URLs for playback and preview.
- Invalid files or metadata fail **server-side** with field-level errors surfaced in admin UI.

---

## Scope

### In scope

- **Create** flow only (`POST /api/admin/sounds` / `POST /api/sounds`).
- Multipart upload of **`audio_file`** + **`thumbnail_file`** with metadata.
- Server-side validation, Spaces write, CDN URL assignment, transactional rollback on failure.
- **ixora-admin** create page (`/sounds/create`, `SoundForm` mode `create`).
- Auth: Firebase Bearer + Laravel **`admin.approved`** middleware.
- Mobile **read** consumption of created sounds (list/show) — not mobile create.

### Out of scope

- **Edit / replace** media on existing sounds (separate flow: `POST /api/admin/uploads` + `PATCH /api/sounds/{id}`).
- **Delete** sound (409 when attached to vibes).
- **Audio transcoding**, normalization, loudness processing, or HLS packaging (future).
- **Image resizing** or forced WebP conversion (future pipeline).
- **Cover bundle** artwork / player backgrounds (sounds are **audio-only** assets).
- **Mobile** or **admin** direct upload to Spaces.
- **Attaching sounds to vibes** (`vibe_sounds` — separate spec).
- **Preset vibe** composition (references sounds after creation).

---

## Actors

| Actor | Role |
| --- | --- |
| **Approved admin** | Human operator using **ixora-admin**; Firebase-authenticated; Laravel `role === admin` and `admin_access_status === approved`. |
| **ixora-admin** | Nuxt admin UI; sends multipart to Laravel; displays validation errors; never touches Spaces SDK. |
| **Laravel API (`back_vibes`)** | Validates input, creates DB row, uploads to Spaces, returns `SoundResource`. |
| **DigitalOcean Spaces** | Object storage behind CDN; **write access only from Laravel**. |
| **Mobile app (`front_vibes`)** | End-user client; **reads** `GET /api/sounds` / layer URLs; **does not create** catalog sounds. |

---

## User Journey

1. Admin signs in to **ixora-admin** (Firebase → `POST /api/auth/sync`).
2. Admin navigates to **Sounds → Create**.
3. Admin enters **name**, **category**, **tags** (comma-separated), **duration (seconds)**, **active** flag.
4. Admin selects **audio file** and **thumbnail image** (local files only).
5. Admin clicks **Create sound**.
6. **ixora-admin** builds `multipart/form-data` and `POST`s to **`/api/admin/sounds`** with Firebase Bearer token.
7. Laravel validates metadata and files, creates `sounds` row, uploads to Spaces, updates URLs, returns **201** + sound JSON.
8. Admin is redirected to **edit page** for the new sound (`/sounds/{id}/edit`) with CDN URLs populated (read-only display in edit mode).

---

## Functional Requirements

| ID | Requirement |
| --- | --- |
| FR-1 | Only **approved admins** may create sounds. |
| FR-2 | Create accepts **`multipart/form-data` only** — not JSON-with-URLs. |
| FR-3 | **`audio_file`** and **`thumbnail_file`** are **required** on create. |
| FR-4 | **`name`**, **`category`**, **`duration_seconds`**, and **`tags`** (≥1) are **required**. |
| FR-5 | Laravel creates the sound row, uploads both files, sets **`file_url`** and **`thumbnail_url`** to **CDN HTTPS URLs**. |
| FR-6 | Client-supplied URL fields (`file_url`, `thumbnail_url`, `audio_url`, etc.) are **prohibited** on create. |
| FR-7 | Default **`is_active`** is **`true`** when omitted. |
| FR-8 | Response uses **`SoundResource`** wrapper `{ data: { … } }` with HTTP **201**. |
| FR-9 | Sound entity stores **metadata + URL strings only** — no binary in PostgreSQL. |
| FR-10 | Sounds do **not** own `artwork_url` or `player_background_url` (cover-bundle / vibe domain). |
| FR-11 | On upload failure after partial Spaces write, Laravel **deletes uploaded keys** and **does not** leave orphan objects when the action aborts. |
| FR-12 | **`GET /api/sounds`** remains available to authenticated Firebase users (mobile catalog read); create remains admin-only. |
| FR-13 | Create **does not** attach the sound to any vibe — no `vibe_sounds` rows are created by this flow. |

---

## Related Domain Model

Ixora separates **catalog assets** from **compositions** and **layer configuration**:

| Entity | Role |
| --- | --- |
| **`sounds`** | Reusable **catalog audio assets** — name, category, tags, duration, `file_url`, `thumbnail_url`, `is_active`. Created by admin; consumed by mobile and composition APIs. |
| **`vibes`** | User or preset **ambient compositions** — visual identity (cover bundle / artwork) and a set of layered sounds. Not created by Create Sound. |
| **`vibe_sounds`** | **Pivot / layer configuration** linking a vibe to a catalog sound. Owns playback behaviour for that layer — not sound metadata. |

**`vibe_sounds` owns (examples):**

- Layer **volume**
- **Playback order** (`sort_order`)
- **Loop behaviour** (`loop`, `play_mode`, interval/offset/duration fields)
- **Fade configuration** (`fade_in_seconds`, `fade_out_seconds` — stored but **ignored at runtime** today; see audio architecture docs)
- Other **layer timing** fields (`repeat_interval_seconds`, `start_offset_seconds`, `play_duration_seconds`)

**Create Sound** only inserts a **`sounds`** row (+ Spaces objects). Attaching a sound to a vibe is **`vibe_sounds`** work — see placeholder [`../../vibes/vibe-sounds/spec.md`](../../vibes/vibe-sounds/spec.md) (future active spec). Mobile playback reads **`file_url`** from the sound via the vibe’s loaded layers, not from create-sound.

---

## Validation Rules

### Metadata (Laravel `StoreSoundRequest`)

| Field | Rules |
| --- | --- |
| `name` | Required, string, max 255 |
| `category` | Required, string, max 255 |
| `duration_seconds` | Required, integer, min 0 |
| `tags` | Required array, min 1 item; each tag string, max 128; empty strings filtered |
| `is_active` | Optional boolean (`true`/`false`/`1`/`0`); defaults true |
| `file_url`, `thumbnail_url`, `audio_url`, `artwork_url`, `player_background_url`, `description` | **Prohibited** on create |

### Admin UI pre-submit (`SoundForm` create mode)

- Disable submit while saving or upload in progress.
- Require non-empty **name**, **category**, **duration ≥ 0**, **≥1 tag**, **both files** selected.
- Show inline hints matching server limits (from `shared/upload-limits.ts`).

---

## Upload Rules

### Transport

| Rule | Detail |
| --- | --- |
| Destination | **`POST /api/admin/sounds`** (preferred) or **`POST /api/sounds`** (same handler) |
| Content-Type | `multipart/form-data` |
| Auth | `Authorization: Bearer <Firebase ID token>` |
| Accept | `application/json` |
| Direct to Spaces | **Forbidden** — admin sends files **to Laravel only** |

### Multipart fields (create)

| Field | Required | Notes |
| --- | --- | --- |
| `name` | Yes | Trimmed in admin before send |
| `category` | Yes | |
| `duration_seconds` | Yes | Integer string in FormData |
| `tags[]` | Yes | Repeated field per tag |
| `is_active` | No | Admin sends `1` or `0` |
| `audio_file` | Yes | File part |
| `thumbnail_file` | Yes | File part |

### Server upload pipeline (`CreateSoundWithUploadedFiles`)

1. Validate audio + thumbnail via **`UploadAssetValidator`**.
2. Resolve canonical extensions from **detected MIME** (not client filename alone).
3. **DB transaction:** insert `Sound` → upload audio → upload thumbnail → update URLs.
4. Object keys:
   - `sounds/{id}/audio/original.{ext}`
   - `sounds/{id}/thumbnail/thumbnail.{ext}`
5. Public URLs built from **`DO_SPACES_CDN_URL`** + key.

### CORS and edge limits

- **ixora-admin** (browser) calls the **Laravel API origin** — not Spaces. **`CORS_ALLOWED_ORIGINS`** on the API must include the admin deployment origin(s) for `POST` multipart (see infra staging config).
- If the **reverse proxy / App Platform** rejects the body before Laravel (e.g. **413 Payload Too Large**), the browser may show a **generic or CORS-masked error** — admin UX maps **413** to a friendly size message; ops must align **server upload limits** with **25 MB audio** validation.
- Laravel application validation remains authoritative for MIME and 25 MB / 5 MB limits when the request reaches the app.

---

## Audio Rules

| Rule | Value |
| --- | --- |
| Max size | **25 MiB** (`UploadAssetValidator::AUDIO_MAX_BYTES`) |
| Allowed MIME / formats | **MP3, OGG, WAV, M4A, AAC** (content-detected) |
| Storage path | `sounds/{sound_id}/audio/original.{ext}` |
| Canonical DB field | **`file_url`** (HTTPS CDN URL) |
| API alias | **`audio_url`** read-only in responses, equal to `file_url` |
| Processing | **None** in current architecture — bytes stored as uploaded |
| Playback (mobile) | **HTTPS progressive streaming** via native player (ExoPlayer) from CDN URL — no transcoding step required for streaming after upload |
| Future | Dedicated transcoding/normalization service **allowed** but **not part of current architecture** — must not be assumed in this spec |

---

## Thumbnail Rules

| Rule | Value |
| --- | --- |
| On **create** | **Required** — `thumbnail_file` must be present (server + admin UI) |
| On **update** (out of scope here) | Thumbnail may be cleared (`thumbnail_url` null) via PATCH |
| Max size | **5 MiB** |
| Allowed MIME / formats | **JPEG, PNG, WebP** |
| Storage path | `sounds/{sound_id}/thumbnail/thumbnail.{ext}` |
| DB field | **`thumbnail_url`** (HTTPS CDN URL) |
| Purpose | Catalog preview in admin and optional mobile UI — **not** vibe artwork / player background |

---

## API Contract

### Create sound

```
POST /api/admin/sounds
POST /api/sounds          ← identical handler
```

**Middleware:** `firebase.auth`, `admin.approved`

**Request:** `multipart/form-data` (see Upload Rules)

**Success: 201 Created**

```json
{
  "data": {
    "id": 42,
    "name": "Rain on glass",
    "file_url": "https://{cdn}/sounds/42/audio/original.mp3",
    "audio_url": "https://{cdn}/sounds/42/audio/original.mp3",
    "thumbnail_url": "https://{cdn}/sounds/42/thumbnail/thumbnail.png",
    "category": "Weather",
    "duration": 90,
    "duration_seconds": 90,
    "tags": ["ambient", "loop"],
    "is_active": true,
    "created_at": "2026-05-23T12:00:00.000000Z"
  }
}
```

**Error responses**

| HTTP | Condition | Body shape |
| --- | --- | --- |
| **401** | Missing/invalid Firebase token, or user not found | `{ "message": "…" }` |
| **403** | Authenticated but not admin-approved | `{ "message": "Admin access is not approved." }` |
| **422** | Validation failure | Laravel `{ "message": "…", "errors": { "field": ["…"] } }` |
| **413** | Body too large (edge/server) | May lack Laravel JSON — treat as upload size failure |
| **5xx** | Server/Spaces failure | Generic error message |

### Related read endpoints (post-create)

| Method | Path | Auth | Purpose |
| --- | --- | --- | --- |
| GET | `/api/sounds` | `firebase.auth` | List catalog (mobile + admin) |
| GET | `/api/sounds/{id}` | `firebase.auth` | Show one sound |

Mobile maps **`file_url`** (or legacy **`audio_url`**) to layer playback URL — **opaque HTTPS**, no Spaces credentials.

---

## Admin UX Rules

| Rule | Requirement |
| --- | --- |
| Page | `/sounds/create` → **`SoundForm`** `mode="create"` |
| File inputs | **`accept`** attributes match server MIME lists (`AUDIO_ACCEPT_ATTR`, `IMAGE_ACCEPT_ATTR`) |
| Hints | Show **25 MB / 5 MB** and format lists under Media section |
| Previews | Local `blob:` preview for selected files before submit |
| Submit | Single multipart request — **do not** pre-upload to `/api/admin/uploads` on create |
| Success | Navigate to **`/sounds/{id}/edit`** |
| Errors | Map API failures via **`friendlySoundApiMessage`** — surface **422** validation lines joined; **401** session message; **403** admin-access redirect hint |
| Admin not approved | Redirect to access-request flow (`isAdminAccessNotApprovedError`) |
| CDN URLs | **Not editable** on create; shown read-only on edit page only |
| Busy state | Disable submit when `saving` or upload busy (`toValue(upload.uploading)`) |

---

## Storage/CDN Rules

Aligned with [`../../../architecture/storage/storage-strategy.md`](../../../architecture/storage/storage-strategy.md):

| Rule | Detail |
| --- | --- |
| Writer | **Laravel only** (`DigitalOceanSpacesService`) |
| Reader | Admin + mobile via **public CDN HTTPS URLs** in JSON |
| URL hostname | **`DO_SPACES_CDN_URL`** — not raw origin endpoint in DB |
| Credentials | **`DO_SPACES_*`** on Laravel/workers only — **never** on ixora-admin or front_vibes |
| Key layout | Canonical paths under `sounds/{id}/…` |
| Legacy | Existing Firebase URLs on old rows may still exist platform-wide; **new creates** use Spaces CDN |
| Deletion | Not part of create; safe delete rules apply on destroy when unreferenced |

---

## Failure Cases

| Case | Expected behaviour |
| --- | --- |
| Missing audio or thumbnail | **422** — field errors on `audio_file` / `thumbnail_file` |
| Invalid MIME | **422** — allowed format message |
| File over size limit | **422** from Laravel; **413** from edge — admin shows size guidance |
| Pasted `file_url` in body | **422** — prohibited field |
| Non-admin user | **403** admin not approved |
| Expired Firebase token | **401** — admin prompts re-login |
| Spaces upload fails mid-action | Transaction rolls back; uploaded keys **deleted** in catch path |
| Network error from admin | Friendly network message; no partial local state persisted as “created” |
| CORS misconfiguration | Browser blocked request — fix **`CORS_ALLOWED_ORIGINS`** on API; not worked around via direct Spaces upload |

---

## Security Rules

| Rule | Requirement |
| --- | --- |
| Identity | Firebase ID token on every write — see [`../../../standards/front-vibes-auth-core.md`](../../../standards/front-vibes-auth-core.md) |
| Authorization | **`admin.approved`** — catalog create is not available to standard mobile users |
| Trust boundary | Laravel verifies token; **does not trust** client-supplied URLs or object keys on create |
| Secrets | No Spaces keys in admin bundle or mobile app |
| Upload surface | Files scanned/validated server-side (size, MIME, validity) |
| Prohibited fields | URL injection via create body rejected |
| CDN URLs | Public read by design; bucket write remains server-only |

---

## Future Considerations

Documented directions **not in current scope**:

| Topic | Notes |
| --- | --- |
| **Transcoding service** | Optional post-upload job (format normalization, loudness) — would produce new keys/URLs; requires ADR |
| **Waveform / duration auto-detect** | Could derive `duration_seconds` from file analysis — today **admin supplies duration manually** |
| **Optional thumbnail on create** | Would require API + admin + spec change — **currently required** |
| **Bulk import** | Admin CSV/zip ingest — separate spec |
| **WebP-only thumbnails** | Uniform extension policy via processing pipeline |
| **Direct admin uploads endpoint on create** | Explicitly **not** used — single-shot multipart preferred |

---

## Related Docs

| Document | Path |
| --- | --- |
| **This spec** | `docs/specs/sounds/create-sound/spec.md` |
| **Implementation plan** | [`docs/specs/sounds/create-sound/plan.md`](plan.md) |
| **Task checklist** | [`docs/specs/sounds/create-sound/tasks.md`](tasks.md) |
| Storage policy | [`docs/architecture/storage/storage-strategy.md`](../../../architecture/storage/storage-strategy.md) |
| Mobile CDN QA | [`docs/architecture/storage/mobile-cdn-validation.md`](../../../architecture/storage/mobile-cdn-validation.md) |
| Audio streaming / cache | [`docs/architecture/audio/audio-cache.md`](../../../architecture/audio/audio-cache.md) |
| Auth standard | [`docs/standards/front-vibes-auth-core.md`](../../../standards/front-vibes-auth-core.md) |
| Git workflow | [`docs/standards/git-flow.md`](../../../standards/git-flow.md) |
| **back_vibes** | `docs/laravel-upload-endpoints.md` |
| **ixora-admin** | `docs/sound-model.md`, `README.md` |
| **Implementation** | `back_vibes/app/Http/Requests/StoreSoundRequest.php`, `app/Actions/Sound/CreateSoundWithUploadedFiles.php`, `app/Services/Storage/UploadAssetValidator.php` |
| **Admin UI** | `ixora-admin/components/SoundForm.vue`, `services/api/sound.service.ts` |
| **Tests** | `back_vibes/tests/Feature/SoundCatalogAuthorizationTest.php` |

When behaviour changes, update **this spec first**, then align API, admin UI, tests, [`plan.md`](plan.md), and [`tasks.md`](tasks.md).
