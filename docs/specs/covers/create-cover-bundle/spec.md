# Create Cover Bundle — catalog visual package (admin)

**Status:** Active feature specification (source of truth)  
**Version:** 1.0 (matches current `back_vibes` + `ixora-admin` implementation)  
**Feature ID:** `covers/create-cover-bundle`

---

## Goal

Enable an **approved Ixora admin** to create a **reusable cover bundle** — a **visual-only catalog package** with thumbnail, artwork, and player background images — in one operation: submit metadata plus **three image files**, have **Laravel** validate uploads, write objects to **DigitalOcean Spaces**, persist **CDN HTTPS URLs** on the `cover_bundles` row, and expose the bundle to **mobile** and admin consumers via the cover-bundles API.

**Success criteria:**

- Admin creates a bundle without pasting URLs or holding Spaces credentials.
- Database row contains metadata + three URL fields only (no raw object keys from client).
- **Sounds remain audio-only**; cover bundles own **visuals only**.
- Mobile and admin read public CDN URLs; **applying** a bundle to a vibe is a **separate** step from **creating** it.
- Invalid files or metadata fail **server-side** with field-level errors surfaced in admin UI.

---

## Scope

### In scope

- **Create** flow only (`POST /api/cover-bundles`).
- Multipart upload of **`thumbnail_file`**, **`artwork_file`**, **`player_background_file`** with metadata.
- Server-side validation, Spaces write, CDN URL assignment, transactional rollback on failure.
- **ixora-admin** create page (`CoverBundleForm` mode `create`).
- Auth: Firebase Bearer + Laravel **`admin.approved`** middleware.
- Mobile **read** of bundles and **consumption of copied vibe URLs** — not admin create.

### Out of scope

- **Edit / replace** images on existing bundles (separate flow: `POST /api/admin/uploads` + `PATCH`, or URL fields on PATCH).
- **Delete** bundle (409 when referenced by presets or user vibes — see Failure Cases).
- **Applying** a cover bundle to a vibe or preset (separate product flows; documented in Related Domain Model only).
- **Creating vibes** or **preset vibes** from this flow.
- **Auto-attach** to preset vibes on create.
- Image processing, resizing, or forced WebP conversion (future pipeline).
- **Sound** catalog create ([`../../sounds/create-sound/spec.md`](../../sounds/create-sound/spec.md)).
- **Audio** behaviour of any kind.
- **Mobile** or **admin** direct upload to Spaces.

---

## Actors

| Actor | Role |
| --- | --- |
| **Approved admin** | Human operator using **ixora-admin**; Firebase-authenticated; Laravel `role === admin` and `admin_access_status === approved`. |
| **ixora-admin** | Nuxt admin UI; sends multipart to Laravel; displays validation errors; never touches Spaces SDK. |
| **Laravel API (`back_vibes`)** | Validates input, creates DB row, uploads three images to Spaces, returns `CoverBundleResource`. |
| **DigitalOcean Spaces** | Object storage behind CDN; **write access only from Laravel**. |
| **Mobile app (`front_vibes`)** | Lists active bundles; **applies** bundle URLs to vibe forms (copy non-empty fields); renders vibe imagery from **vibe** URL columns — does not create bundles. |
| **End user** | Consumes vibe visuals via opaque HTTPS URLs after a bundle was applied to their vibe (separate from create). |

---

## User Journey

1. Admin signs in to **ixora-admin** (Firebase → `POST /api/auth/sync`).
2. Admin navigates to **Cover bundles → Create**.
3. Admin enters **name**, optional **description**, **category**, **tags** (comma-separated), **active** flag.
4. Admin selects **three image files**: thumbnail, artwork, player background (local files only).
5. Admin clicks **Create** (or equivalent submit).
6. **ixora-admin** builds `multipart/form-data` and `POST`s to **`/api/cover-bundles`** with Firebase Bearer token.
7. Laravel validates metadata and files, creates `cover_bundles` row, uploads to Spaces, updates three URL columns, returns **201** + bundle JSON.
8. Admin is redirected to **cover bundle list** (`/covers`).

**Not in this journey:** creating a vibe, assigning a preset, or applying the bundle to a vibe — those are separate flows.

---

## Functional Requirements

| ID | Requirement |
| --- | --- |
| FR-1 | Only **approved admins** may create cover bundles. |
| FR-2 | Create accepts **`multipart/form-data` only** — not JSON-with-URLs. |
| FR-3 | **`thumbnail_file`**, **`artwork_file`**, and **`player_background_file`** are **required** on create. |
| FR-4 | **`name`**, **`category`**, and **`tags`** (≥1) are **required**. |
| FR-5 | **`description`** is **optional** (nullable). |
| FR-6 | **`is_active`** is supported; defaults to **`true`** when omitted. |
| FR-7 | Laravel creates the bundle row, uploads three images, sets **`thumbnail_url`**, **`artwork_url`**, **`player_background_url`** to **CDN HTTPS URLs**. |
| FR-8 | Client-supplied URL fields on create are **prohibited**. |
| FR-9 | Response uses **`CoverBundleResource`** wrapper `{ data: { … } }` with HTTP **201**. |
| FR-10 | Entity stores **metadata + URL strings only** — no binary in PostgreSQL. |
| FR-11 | Cover bundles are **visual packages only** — no audio fields. |
| FR-12 | On upload failure after partial Spaces write, Laravel **deletes uploaded keys** and does not leave orphan objects when the action aborts. |
| FR-13 | **`GET /api/cover-bundles`** remains available to authenticated Firebase users (active bundles by default); create remains admin-only. |
| FR-14 | Create **does not** create **`vibes`** rows. |
| FR-15 | Create **does not** attach the bundle to **`preset_vibes`** (`cover_bundle_id` unchanged by create). |
| FR-16 | **Safe deletion** (out of create scope) must block delete when presets reference `cover_bundle_id` or user vibes reference bundle URLs — per storage strategy. |

---

## Validation Rules

### Metadata (Laravel `StoreCoverBundleRequest`)

| Field | Rules |
| --- | --- |
| `name` | Required, string, max 255 |
| `description` | **Optional**, nullable string |
| `category` | Required, string, max 100 |
| `tags` | Required array, min 1; each tag string, max 50; empty strings filtered |
| `is_active` | Optional boolean (`true`/`false`/`1`/`0`); defaults **true** |
| `thumbnail_url`, `artwork_url`, `player_background_url` | **Prohibited** on create |
| `thumbnail_file`, `artwork_file`, `player_background_file` | Required file, max **5 MiB** each (validator-aligned) |

### Admin UI pre-submit (`CoverBundleForm` create mode)

- Require non-empty **name**, **category**, **≥1 tag**, **all three image files**.
- **Description** optional.
- Disable submit while saving or upload busy (`uploadBusy` / `toValue(upload.uploading)` pattern).
- Show inline hints: JPEG, PNG, WebP; **5 MB** per image.

---

## Upload Rules

### Transport

| Rule | Detail |
| --- | --- |
| Destination | **`POST /api/cover-bundles`** |
| Content-Type | `multipart/form-data` |
| Auth | `Authorization: Bearer <Firebase ID token>` |
| Accept | `application/json` |
| Direct to Spaces | **Forbidden** — admin sends files **to Laravel only** |

### Multipart fields (create)

| Field | Required | Notes |
| --- | --- | --- |
| `name` | Yes | Trimmed in admin |
| `description` | No | Omitted or sent when non-empty |
| `category` | Yes | |
| `tags[]` | Yes | Repeated per tag |
| `is_active` | No | Admin sends `1` or `0` |
| `thumbnail_file` | Yes | Image part |
| `artwork_file` | Yes | Image part |
| `player_background_file` | Yes | Image part |

### Server upload pipeline (`CreateCoverBundleWithUploadedFiles`)

1. Validate each file via **`UploadAssetValidator::assertValidCoverCatalogImage`** (`thumbnail` | `artwork` | `player_background` asset types).
2. Resolve canonical extensions from **detected MIME**.
3. **DB transaction:** insert `CoverBundle` → upload three files → update URL columns.
4. Object keys:
   - `covers/{id}/thumbnail/thumbnail.{ext}`
   - `covers/{id}/artwork/artwork.{ext}`
   - `covers/{id}/player-background/background.{ext}`
5. Public URLs built from **`DO_SPACES_CDN_URL`** + key.
6. On failure: delete any keys already uploaded in the action.

### CORS and edge limits

- **ixora-admin** calls the **Laravel API origin** — not Spaces. **`CORS_ALLOWED_ORIGINS`** must include admin deployment origin(s) for multipart `POST`.
- Edge **413** may occur before Laravel runs — admin maps to friendly size message; ops must align server body limits with **5 MiB × 3** multipart payloads.
- Laravel validation is authoritative for MIME and per-file size when the request reaches the app.

---

## Image Rules

| Rule | Value |
| --- | --- |
| Max size (each file) | **5 MiB** (`UploadAssetValidator::IMAGE_MAX_BYTES`) |
| Allowed MIME / formats | **JPEG, PNG, WebP** (content-detected) |
| Processing | **None** in current architecture — bytes stored as uploaded |
| Recommended dimensions (guidance) | Thumbnail: 512×512 or 1024×1024; Artwork: 1024×1024; Player background: portrait hero (~1440×3200) |
| Storage paths | See Upload Rules — under `covers/{cover_bundle_id}/…` |
| DB fields | **`thumbnail_url`**, **`artwork_url`**, **`player_background_url`** (HTTPS CDN) |

**No audio** — cover bundles must not introduce sound playback fields.

---

## API Contract

### Create cover bundle

```
POST /api/cover-bundles
```

**Middleware:** `firebase.auth`, `admin.approved`

**Request:** `multipart/form-data` (see Upload Rules)

**Success: 201 Created**

```json
{
  "data": {
    "id": 12,
    "name": "Forest dusk",
    "description": "Optional copy",
    "thumbnail_url": "https://{cdn}/covers/12/thumbnail/thumbnail.png",
    "artwork_url": "https://{cdn}/covers/12/artwork/artwork.jpg",
    "player_background_url": "https://{cdn}/covers/12/player-background/background.webp",
    "category": "Nature",
    "tags": ["forest", "dark"],
    "is_active": true,
    "created_at": "2026-05-23T12:00:00.000000Z",
    "updated_at": "2026-05-23T12:00:00.000000Z"
  }
}
```

**Error responses**

| HTTP | Condition | Body shape |
| --- | --- | --- |
| **401** | Missing/invalid Firebase token / user not found | `{ "message": "…" }` |
| **403** | Authenticated but not admin-approved | `{ "message": "Admin access is not approved." }` |
| **422** | Validation failure | Laravel `{ "message": "…", "errors": { "field": ["…"] } }` |
| **413** | Body too large (edge/server) | May lack Laravel JSON |
| **5xx** | Server/Spaces failure | Generic error message |

### Related read endpoints (post-create)

| Method | Path | Auth | Purpose |
| --- | --- | --- | --- |
| GET | `/api/cover-bundles` | `firebase.auth` | List active bundles (mobile + admin) |
| GET | `/api/cover-bundles/{id}` | `firebase.auth` | Show one bundle |
| GET | `/api/cover-bundles?include_inactive=1` | `firebase.auth` + approved admin | Include inactive (admin only) |

**Delete (reference only):** `DELETE /api/cover-bundles/{id}` — **409** when referenced; not part of create spec.

---

## Admin UX Rules

| Rule | Requirement |
| --- | --- |
| Form | **`CoverBundleForm.vue`** `mode="create"` |
| Visual assets | Three required file inputs with **`IMAGE_ACCEPT_ATTR`** |
| Hints | 5 MB / JPEG, PNG, WebP per slot; recommended sizes in UI copy |
| Previews | Local blob previews for selected files before submit |
| Submit | **Single multipart POST** — do not pre-upload via `/api/admin/uploads` on create |
| Success | Navigate to **`/covers`** list |
| Errors | **`friendlyCoverBundleApiMessage`** — 422 validation lines; 401; 403 admin-access redirect |
| CDN URLs | Not editable on create; edit mode may show URL fields separately (out of create scope) |
| Busy state | `uploadBusy` computed — submit disabled while saving or uploading |
| Secrets | No **`DO_SPACES_*`** in Nuxt env |

---

## Storage/CDN Rules

Aligned with [`../../../architecture/storage/storage-strategy.md`](../../../architecture/storage/storage-strategy.md):

| Rule | Detail |
| --- | --- |
| Writer | **Laravel only** |
| Reader | Admin + mobile via **public CDN HTTPS URLs** |
| URL hostname | **`DO_SPACES_CDN_URL`** in DB |
| Credentials | **`DO_SPACES_*`** on Laravel/workers only |
| Key layout | `covers/{cover_bundle_id}/thumbnail|artwork|player-background/…` |
| Shared URLs | Vibes may **copy** bundle URLs onto vibe rows when applied — same HTTPS string until user changes vibe fields |
| Safe delete | **`DELETE`** blocked when **`preset_vibes.cover_bundle_id`** or **vibe URL columns** still reference bundle URLs; Spaces cleanup via **`SafeAssetDeletionService`** when unreferenced |

---

## Related Domain Model

```
cover_bundles          sounds              vibes
(visual catalog)       (audio catalog)     (user compositions)
     │                      │                    │
     │                      │                    ├── thumbnail_url
     │                      │                    ├── artwork_url
     │                      │                    └── player_background_url
     │                      │                         ▲
     │                      │                         │ copy non-empty URLs
     └──── apply (separate) ──────────────────────────┘
              NOT part of POST /api/cover-bundles create

preset_vibes
  └── cover_bundle_id (optional FK) — admin preset domain; NOT set by create cover bundle
```

| Entity | Owns | Does not own |
| --- | --- | --- |
| **`cover_bundles`** | **`thumbnail_url`**, **`artwork_url`**, **`player_background_url`**, name, description, category, tags, `is_active` | Audio, vibe layer config, playback |
| **`sounds`** | **`file_url`**, **`thumbnail_url`** (catalog preview), audio metadata | Artwork, player background, vibe visuals |
| **`vibes`** | User composition + **copied visual URL fields** on the vibe row (after apply/save) | Catalog upload authority; does not replace bundle row on create |
| **`preset_vibes`** | Curated templates; may reference **`cover_bundle_id`** | Not created or linked by **Create Cover Bundle** |
| **`vibe_sounds`** | Layer pivot (volume, play mode, timing) | Visual packages — see [`../../vibes/vibe-sounds/spec.md`](../../vibes/vibe-sounds/spec.md) |

### Applying vs creating (critical)

| Action | When | Behaviour |
| --- | --- | --- |
| **Create cover bundle** | Admin catalog | Inserts **`cover_bundles`** + Spaces objects + CDN URLs |
| **Apply cover bundle** | Mobile vibe create/edit (or future admin) | **`applyCoverBundleToFormFields`** copies each **non-empty** bundle URL into vibe form fields; user then **POST/PATCH `/api/vibes`** — separate from create bundle |
| **Preset assignment** | Admin preset editor | Sets **`preset_vibes.cover_bundle_id`** — separate from create bundle |

Mobile presentation priorities after URLs are on the vibe row: [`artwork-background-strategy.md`](../../../architecture/storage/artwork-background-strategy.md).

---

## Failure Cases

| Case | Expected behaviour |
| --- | --- |
| Missing any image file | **422** — field errors on `*_file` |
| Invalid MIME | **422** — allowed format message |
| File over 5 MiB | **422** from Laravel; **413** from edge |
| JSON-only create with URLs | **422** — prohibited URL fields / missing files |
| Non-admin user | **403** |
| Expired Firebase token | **401** |
| Spaces upload fails mid-action | Rollback DB; delete uploaded keys in catch |
| CORS misconfiguration | Browser blocked request — fix API CORS; no direct Spaces workaround |
| Delete bundle in use | **409** — preset `cover_bundle_id` or vibe URL match (not create flow) |

---

## Security Rules

| Rule | Requirement |
| --- | --- |
| Identity | Firebase ID token on every write — [`front-vibes-auth-core.md`](../../../standards/front-vibes-auth-core.md) |
| Authorization | **`admin.approved`** for create |
| Trust boundary | Laravel verifies token; **does not trust** client-supplied URLs or object keys on create |
| Secrets | No Spaces keys in admin or mobile bundles |
| Upload validation | Server-side MIME and size on all three files |
| Prohibited fields | URL injection via create body rejected |
| CDN URLs | Public read by design; bucket write server-only |

---

## Future Considerations

| Topic | Notes |
| --- | --- |
| Image processing pipeline | Resize/WebP normalization — ADR + new keys; **not current** |
| Optional slots on create | Would require spec + API change — **all three required today** |
| Admin “apply to preset” from create success | Out of scope — no auto-attach |
| Bulk import | Separate spec |
| Vibe URL validation on Laravel | Ensure `StoreVibeRequest` / `UpdateVibeRequest` whitelist visual URL fields per artwork-background doc |

**Explicitly excluded:** transcoding, audio bundles, direct client-to-Spaces uploads, vibe/preset implementation tasks in this spec.

---

## Related Docs

| Document | Path |
| --- | --- |
| **This spec** | `docs/specs/covers/create-cover-bundle/spec.md` |
| Create Sound (audio catalog) | [`../../sounds/create-sound/spec.md`](../../sounds/create-sound/spec.md) |
| Vibe sounds (layers) | [`../../vibes/vibe-sounds/spec.md`](../../vibes/vibe-sounds/spec.md) |
| Storage policy | [`docs/architecture/storage/storage-strategy.md`](../../../architecture/storage/storage-strategy.md) |
| Artwork / background (mobile) | [`docs/architecture/storage/artwork-background-strategy.md`](../../../architecture/storage/artwork-background-strategy.md) |
| Mobile CDN QA | [`docs/architecture/storage/mobile-cdn-validation.md`](../../../architecture/storage/mobile-cdn-validation.md) |
| Auth | [`docs/standards/front-vibes-auth-core.md`](../../../standards/front-vibes-auth-core.md) |
| Git Flow | [`docs/standards/git-flow.md`](../../../standards/git-flow.md) |
| **back_vibes** | `docs/cover-bundles.md`, `docs/laravel-upload-endpoints.md` |
| **ixora-admin** | `docs/cover-bundles-admin.md` |
| **Implementation** | `StoreCoverBundleRequest.php`, `CreateCoverBundleWithUploadedFiles.php`, `CoverBundleController.php`, `UploadAssetValidator.php` |
| **Admin UI** | `ixora-admin/components/CoverBundleForm.vue`, `services/api/cover-bundle.service.ts` |
| **Tests** | `tests/Feature/CoverBundleApiTest.php`, `tests/Feature/CoverBundleSafeDeletionTest.php` |

When behaviour changes, update **this file first**, then align API, admin UI, and tests.
