# Create Cover Bundle — task checklist

**Status:** Feature **shipped** — checklist for regression, verification, and maintenance (not greenfield)  
**Spec:** [`spec.md`](spec.md)  
**Plan:** [`plan.md`](plan.md)  
**Feature ID:** `covers/create-cover-bundle`

**Status legend**

| Status | Meaning |
| --- | --- |
| **Completed** | Implemented and in codebase |
| **To verify** | Re-run or confirm on each relevant change / staging promotion |
| **Future / separate spec** | Out of scope for create-cover-bundle |

---

## Task List

| Area | Completed | To verify | Future / separate spec |
| --- | ---: | ---: | ---: |
| Documentation | 2 | 1 | 2 |
| Backend | 11 | 2 | 0 |
| Admin | 7 | 1 | 0 |
| Mobile | 3 | 1 | 2 |
| Infra / Ops | 1 | 3 | 0 |
| Validation | 4 | 4 | 0 |

---

## Backend Tasks

| ID | Task | Status | Reference |
| --- | --- | --- | --- |
| B-1 | `POST /api/cover-bundles` accepts **multipart/form-data** create | **Completed** | `CoverBundleController::store`, `routes/api.php` |
| B-2 | **`StoreCoverBundleRequest`** requires **`thumbnail_file`**, **`artwork_file`**, and **`player_background_file`** on create | **Completed** | `StoreCoverBundleRequest.php` |
| B-3 | **`StoreCoverBundleRequest`** **prohibits** URL fields on create (`thumbnail_url`, `artwork_url`, `player_background_url`) | **Completed** | `StoreCoverBundleRequest.php`, `CoverBundleApiTest` |
| B-4 | **`CreateCoverBundleWithUploadedFiles`** uploads to Spaces and sets CDN URLs on `thumbnail_url` / `artwork_url` / `player_background_url` | **Completed** | `CreateCoverBundleWithUploadedFiles.php` |
| B-5 | **`CreateCoverBundleWithUploadedFiles`** **rolls back partial Spaces uploads** (deletes keys in `catch` on failure) | **Completed** | `CreateCoverBundleWithUploadedFiles.php` |
| B-6 | Create path uses **`UploadAssetValidator::assertValidCoverCatalogImage`** (5 MiB per image, JPEG/PNG/WebP) | **Completed** | `UploadAssetValidator.php` |
| B-7 | **`CoverBundleResource`** returns **`thumbnail_url`**, **`artwork_url`**, **`player_background_url`** as CDN HTTPS URLs | **Completed** | `CoverBundleResource.php` |
| B-8 | Create guarded by **`firebase.auth`** + **`admin.approved`** | **Completed** | `routes/api.php` |
| B-9 | **`CoverBundleController::store`** / create action **does not create `vibes` rows** | **Completed** | No vibe writes in store or action — catalog-only |
| B-10 | Create action **does not set `preset_vibes.cover_bundle_id`** | **Completed** | No preset writes in store or action |
| B-11 | Canonical Spaces keys: `covers/{id}/thumbnail/…`, `covers/{id}/artwork/…`, `covers/{id}/player-background/…` | **Completed** | `StoragePathBuilder`, tests |
| B-12 | **`SafeAssetDeletionService`** protections remain active — **409** when presets or vibes reference bundle URLs | **To verify** | `CoverBundleSafeDeletionTest.php`, delete flow |
| B-13 | Keep **`StoreCoverBundleRequest` max file size** aligned with `UploadAssetValidator::IMAGE_MAX_BYTES` after any limit change | **To verify** | On upload-limit changes |

---

## Admin Tasks

| ID | Task | Status | Reference |
| --- | --- | --- | --- |
| A-1 | **`/covers/create`** page with **`CoverBundleForm`** `mode="create"` | **Completed** | `pages/covers/create.vue` |
| A-2 | Create uses **single multipart POST** via **`createCoverBundleWithFiles`** → `/api/cover-bundles` | **Completed** | `cover-bundle.service.ts` — no pre-upload on create |
| A-3 | **Create button disabled** until name, category, ≥1 tag, and **all three image files** selected | **Completed** | `CoverBundleForm.vue` `canSubmit` |
| A-4 | File inputs use **`IMAGE_ACCEPT_ATTR`** and upload hints (5 MB, JPEG/PNG/WebP) | **Completed** | `shared/upload-limits.ts` |
| A-5 | API errors mapped with **`friendlyCoverBundleApiMessage`** (422, 401, 403, 5xx) | **Completed** | `laravel-api-error.ts` |
| A-6 | Success → redirect to **`/covers`** list | **Completed** | `CoverBundleForm.vue` `submit` |
| A-7 | **No `DO_SPACES_*` or Spaces SDK** in ixora-admin | **Completed** | Env/docs — API base + Firebase only |
| A-8 | Submit not stuck disabled when upload ref nested (`uploadBusy` / `toValue(upload.uploading)` pattern) | **To verify** | After `CoverBundleForm` / `useUpload` changes |

---

## Mobile Tasks

| ID | Task | Status | Reference |
| --- | --- | --- | --- |
| M-1 | Mobile **does not implement catalog cover bundle create** | **Completed** | By design — admin-only create |
| M-2 | Mobile consumes bundle / vibe **visual URLs** (opaque HTTPS CDN) for list and player imagery | **Completed** | `cover-bundle` services, vibe URL columns |
| M-3 | **Optional smoke:** apply bundle to test vibe and confirm imagery renders (not part of create) | **To verify** | After staging create + apply flow |
| M-4 | **No `DO_SPACES_*`** in front_vibes | **Completed** | Storage architecture |
| — | **Apply cover bundle to vibe** (copy URLs → POST/PATCH vibe) | **Future / separate spec** | Separate from create — see [`spec.md`](spec.md) § Applying vs creating |
| — | **Preset `cover_bundle_id` assignment** | **Future / separate spec** | Admin preset editor — not create-cover-bundle |

---

## Infra / Ops Tasks

| ID | Task | Status | Reference |
| --- | --- | --- | --- |
| I-1 | Laravel only holds **`DO_SPACES_*`** write credentials | **Completed** | `storage-strategy.md` |
| I-2 | **`CORS_ALLOWED_ORIGINS`** on staging API includes **staging ixora-admin origin** | **To verify** | `ixora-infra` / `back_vibes` CORS config |
| I-3 | **Upload/body limits** (Frankenphp, Caddy, App Platform) support **3×5 MiB** multipart payloads | **To verify** | `zz-uploads.ini`, edge config — match app validator |
| I-4 | Staging **CDN URLs** reachable from browser (all three image GETs) | **To verify** | Manual create-cover-bundle test |

---

## Validation Tasks

| ID | Task | Status | Command / notes |
| --- | --- | --- | --- |
| V-1 | Run **Laravel CoverBundle** feature tests | **To verify** | `cd back_vibes && php artisan test --filter=CoverBundle` |
| V-2 | Run **ixora-admin production build** | **To verify** | `cd ixora-admin && npm ci && npm run build` |
| V-3 | **Manual staging create-cover-bundle** (full checklist) | **To verify** | See [Manual staging checklist](#manual-staging-checklist) below |
| V-4 | Negative: API create with URL fields in body → **422** | **Completed** | Covered by `CoverBundleApiTest` |
| V-5 | Negative: non-approved admin → **403** | **Completed** | Covered by tests |
| V-6 | Negative: missing any image file / invalid MIME → **422** | **Completed** | Covered by tests |
| V-7 | Confirm **no vibe** auto-created and **no preset** auto-linked on create | **To verify** | Manual staging + code review of store action |
| V-8 | Safe delete: bundle referenced by preset or vibe URLs → **409** | **Completed** | `CoverBundleSafeDeletionTest.php` |

### Manual staging checklist

Prerequisites: approved admin, staging admin + API deployed, CORS OK.

- [ ] Sign in to staging **ixora-admin**
- [ ] **Cover bundles → Create** — name, category, tags
- [ ] Select **thumbnail**, **artwork**, and **player background** (each ≤5 MB, JPEG/PNG/WebP)
- [ ] **Create cover bundle** → **201**, redirect to `/covers`
- [ ] Bundle detail shows CDN **`thumbnail_url`**, **`artwork_url`**, **`player_background_url`**
- [ ] Open all three URLs in browser — images load over HTTPS
- [ ] No new **vibe** row; no **`preset_vibes.cover_bundle_id`** set for this bundle
- [ ] UI blocks submit without all three files; API **422** if forced without files
- [ ] Oversized file → **422** or **413** with readable admin message

### Optional mobile smoke (after apply to test vibe)

- [ ] New bundle appears in mobile bundle list (staging)
- [ ] **Apply** bundle to test vibe via existing flow — URLs copied to vibe form; save vibe separately
- [ ] Vibe player/hero renders imagery from copied CDN URLs on device

---

## Documentation Tasks

| ID | Task | Status | Reference |
| --- | --- | --- | --- |
| D-1 | **`spec.md`** includes **Related Domain Model** (`cover_bundles` / `sounds` / `vibes` / `preset_vibes`) | **Completed** | [`spec.md`](spec.md) § Related Domain Model |
| D-2 | **`spec.md`** + **`plan.md`** published under `docs/specs/covers/create-cover-bundle/` | **Completed** | This folder |
| D-3 | **`tasks.md`** kept aligned when create behaviour changes | **To verify** | Update on API/admin contract changes |
| — | **Apply cover bundle to vibe** spec (future) | **Future / separate spec** | Domain model in [`spec.md`](spec.md) only |
| — | **Preset cover bundle assignment** spec (future) | **Future / separate spec** | Admin preset domain |

---

## Done Criteria

Create Cover Bundle is **done** for this feature slice when all of the following hold:

### Shipped (maintain — already true)

- [x] Admin can create a cover bundle with **multipart** thumbnail + artwork + player background + metadata
- [x] Laravel writes Spaces objects and persists **CDN URLs** only on `cover_bundles`
- [x] **No** client URL fields on create; **no** direct Spaces upload from admin/mobile
- [x] Create **does not** create **`vibes`** rows or set **`preset_vibes.cover_bundle_id`**
- [x] **`CoverBundleResource`** exposes all three CDN URL fields
- [x] **`CreateCoverBundleWithUploadedFiles`** rolls back partial uploads on failure
- [x] **`spec.md`** documents **Related Domain Model** and links **`plan.md`** / **`tasks.md`**

### Verify on each staging promotion or create/upload change

- [ ] **V-1** Laravel `CoverBundle` tests pass
- [ ] **V-2** ixora-admin build passes
- [ ] **V-3** Manual staging create-cover-bundle checklist complete
- [ ] **I-2** CORS includes staging admin origin
- [ ] **I-3** Edge/body limits support **3×5 MiB** multipart payloads
- [ ] **B-12** `SafeAssetDeletionService` reference checks still return **409** when expected
- [ ] **B-13** Request validator max matches `UploadAssetValidator`
- [ ] **V-7** No vibe or preset side effects on create

### Optional

- [ ] **M-3** Mobile smoke after applying bundle to test vibe

### Explicitly not required for create-cover-bundle done

- Image processing / resize / WebP transcoding pipeline
- Direct client-to-Spaces uploads
- **Apply cover bundle to vibe** implementation (separate spec)
- **Preset `cover_bundle_id`** assignment (separate spec)
- Optional image slots on create
- Bulk import API
- **Any audio behaviour**

---

## Related Docs

| Document | Path |
| --- | --- |
| Spec | [`spec.md`](spec.md) |
| Plan | [`plan.md`](plan.md) |
| Storage | [`docs/architecture/storage/storage-strategy.md`](../../../architecture/storage/storage-strategy.md) |
| Artwork / background | [`docs/architecture/storage/artwork-background-strategy.md`](../../../architecture/storage/artwork-background-strategy.md) |
| Tests | `back_vibes/tests/Feature/CoverBundleApiTest.php`, `CoverBundleSafeDeletionTest.php` |
