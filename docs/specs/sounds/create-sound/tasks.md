# Create Sound — task checklist

**Status:** Feature **shipped** — checklist for regression, verification, and maintenance (not greenfield)  
**Spec:** [`spec.md`](spec.md)  
**Plan:** [`plan.md`](plan.md)  
**Feature ID:** `sounds/create-sound`

**Status legend**

| Status | Meaning |
| --- | --- |
| **Completed** | Implemented and in codebase |
| **To verify** | Re-run or confirm on each relevant change / staging promotion |
| **Future / separate spec** | Out of scope for create-sound |

---

## Task List

| Area | Completed | To verify | Future / separate spec |
| --- | ---: | ---: | ---: |
| Documentation | 2 | 0 | 1 |
| Backend | 10 | 1 | 0 |
| Admin | 7 | 1 | 0 |
| Mobile | 2 | 1 | 1 |
| Infra / Ops | 1 | 3 | 0 |
| Validation | 2 | 4 | 0 |

---

## Backend Tasks

| ID | Task | Status | Reference |
| --- | --- | --- | --- |
| B-1 | `POST /api/admin/sounds` and `POST /api/sounds` accept **multipart/form-data** create | **Completed** | `SoundController::store`, `routes/api.php` |
| B-2 | **`StoreSoundRequest`** requires `audio_file` and `thumbnail_file` on create | **Completed** | `StoreSoundRequest.php` |
| B-3 | **`StoreSoundRequest`** **prohibits** URL fields on create (`file_url`, `thumbnail_url`, `audio_url`, `artwork_url`, `player_background_url`, `description`) | **Completed** | `StoreSoundRequest.php`, test `approved admin cannot create sound with file_url in body` |
| B-4 | **`CreateSoundWithUploadedFiles`** uploads to Spaces and sets CDN URLs on `file_url` / `thumbnail_url` | **Completed** | `CreateSoundWithUploadedFiles.php` |
| B-5 | **`CreateSoundWithUploadedFiles`** **rolls back partial Spaces uploads** (deletes keys in `catch` on failure) | **Completed** | `CreateSoundWithUploadedFiles.php` |
| B-6 | Create path uses **`UploadAssetValidator`** (25 MB audio, 5 MB image, MIME rules) | **Completed** | `UploadAssetValidator.php` |
| B-7 | **`SoundResource`** returns **`file_url`**, read-only **`audio_url`** alias, **`thumbnail_url`** | **Completed** | `SoundResource.php` |
| B-8 | Create guarded by **`firebase.auth`** + **`admin.approved`** | **Completed** | `routes/api.php` |
| B-9 | **`SoundController::store`** / create action **does not insert `vibe_sounds` rows** | **Completed** | No vibe/pivot writes in store or action — catalog-only |
| B-10 | Canonical Spaces keys: `sounds/{id}/audio/original.{ext}`, `sounds/{id}/thumbnail/thumbnail.{ext}` | **Completed** | `StoragePathBuilder`, tests |
| B-11 | Keep **`StoreSoundRequest` max file size** aligned with `UploadAssetValidator::AUDIO_MAX_BYTES` after any limit change | **To verify** | On upload-limit changes |

---

## Admin Tasks

| ID | Task | Status | Reference |
| --- | --- | --- | --- |
| A-1 | **`/sounds/create`** page with **`SoundForm`** `mode="create"` | **Completed** | `pages/sounds/create.vue` |
| A-2 | Create uses **single multipart POST** via **`createSoundWithFiles`** → `/api/admin/sounds` | **Completed** | `sound.service.ts` — no pre-upload on create |
| A-3 | **Create button disabled** until name, category, duration, ≥1 tag, **`pendingAudioFile`**, **`pendingThumbFile`** | **Completed** | `SoundForm.vue` `canSubmit` |
| A-4 | File inputs use **`AUDIO_ACCEPT_ATTR`** / **`IMAGE_ACCEPT_ATTR`** and upload hints | **Completed** | `shared/upload-limits.ts` |
| A-5 | API errors mapped with **`friendlySoundApiMessage`** (422, 401, 403, 5xx) | **Completed** | `laravel-api-error.ts` |
| A-6 | Success → redirect to **`/sounds/{id}/edit`** | **Completed** | `SoundForm.vue` `submit` |
| A-7 | **No `DO_SPACES_*` or Spaces SDK** in ixora-admin | **Completed** | Env/docs — API base + Firebase only |
| A-8 | Submit not stuck disabled when upload ref nested (`toValue(upload.uploading)` pattern) | **To verify** | After `SoundForm` / `useUpload` changes |

---

## Mobile Tasks

| ID | Task | Status | Reference |
| --- | --- | --- | --- |
| M-1 | Mobile **does not implement catalog sound create** | **Completed** | By design — admin-only create |
| M-2 | Mobile consumes **`file_url`** / **`thumbnail_url`** (opaque HTTPS CDN) for catalog/layers | **Completed** | `sound.service.ts`, vibe layer payloads |
| M-3 | **Optional smoke:** play sound on device after attaching to test vibe (not part of create) | **To verify** | After staging create + vibe attach |
| M-4 | **No `DO_SPACES_*`** in front_vibes | **Completed** | Storage architecture |
| — | **`vibe_sounds` attach / layer editor** | **Future / separate spec** | Not create-sound |

---

## Infra / Ops Tasks

| ID | Task | Status | Reference |
| --- | --- | --- | --- |
| I-1 | Laravel only holds **`DO_SPACES_*`** write credentials | **Completed** | `storage-strategy.md` |
| I-2 | **`CORS_ALLOWED_ORIGINS`** on staging API includes **staging ixora-admin origin** | **To verify** | `ixora-infra` / `back_vibes` CORS config |
| I-3 | **Upload/body limits** (Frankenphp, Caddy, App Platform) support **≥ 25 MiB** audio payloads | **To verify** | `zz-uploads.ini`, edge config — match app validator |
| I-4 | Staging **CDN URLs** reachable from browser (audio + thumbnail GET) | **To verify** | Manual create test |

---

## Validation Tasks

| ID | Task | Status | Command / notes |
| --- | --- | --- | --- |
| V-1 | Run **Laravel SoundCatalog** feature tests | **To verify** | `cd back_vibes && php artisan test --filter=SoundCatalog` |
| V-2 | Run **ixora-admin production build** | **To verify** | `cd ixora-admin && npm ci && npm run build` |
| V-3 | **Manual staging create sound** (full checklist) | **To verify** | See [Manual staging checklist](#manual-staging-checklist) below |
| V-4 | Negative: API create with `file_url` in body → **422** | **Completed** | Covered by `SoundCatalogAuthorizationTest` |
| V-5 | Negative: non-approved admin → **403** | **Completed** | Covered by tests |
| V-6 | Confirm **no vibe** auto-created / auto-linked on create | **To verify** | Manual staging + code review of store action |

### Manual staging checklist

Prerequisites: approved admin, staging admin + API deployed, CORS OK.

- [ ] Sign in to staging **ixora-admin**
- [ ] **Sounds → Create** — name, category, tags, duration
- [ ] Select audio (≤25 MB) + thumbnail (≤5 MB)
- [ ] **Create sound** → **201**, redirect to edit
- [ ] Edit page shows CDN **`file_url`** and **`thumbnail_url`**
- [ ] Open URLs in browser — audio streams, image loads
- [ ] No new vibe / no `vibe_sounds` link for this sound
- [ ] UI blocks submit without both files; API **422** if forced without files
- [ ] Oversized file → **422** or **413** with readable admin message

### Optional mobile smoke (after vibe attach)

- [ ] Attach new catalog sound to test vibe via **existing** vibe-sound flow
- [ ] Play layer on Android against staging — streams from CDN **`file_url`**

---

## Documentation Tasks

| ID | Task | Status | Reference |
| --- | --- | --- | --- |
| D-1 | **`spec.md`** includes **Related Domain Model** (`sounds` / `vibes` / `vibe_sounds`) | **Completed** | [`spec.md`](spec.md) § Related Domain Model |
| D-2 | **`spec.md`** + **`plan.md`** published under `docs/specs/sounds/create-sound/` | **Completed** | This folder |
| D-3 | **`tasks.md`** kept aligned when create behaviour changes | **To verify** | Update on API/admin contract changes |
| — | **`vibe_sounds` attach spec** (future) | **Future / separate spec** | [`../../vibes/vibe-sounds/spec.md`](../../vibes/vibe-sounds/spec.md) (placeholder) |

---

## Done Criteria

Create Sound is **done** for this feature slice when all of the following hold:

### Shipped (maintain — already true)

- [x] Admin can create a sound with **multipart** audio + thumbnail + metadata
- [x] Laravel writes Spaces objects and persists **CDN URLs** only on `sounds`
- [x] **No** client URL fields on create; **no** direct Spaces upload from admin/mobile
- [x] Create **does not** create **`vibe_sounds`** rows
- [x] **`SoundResource`** exposes **`file_url`** and **`audio_url`** alias
- [x] **`spec.md`** documents **Related Domain Model** and links **`plan.md`** / **`tasks.md`**

### Verify on each staging promotion or create/upload change

- [ ] **V-1** Laravel `SoundCatalog` tests pass
- [ ] **V-2** ixora-admin build passes
- [ ] **V-3** Manual staging create sound checklist complete
- [ ] **I-2** CORS includes staging admin origin
- [ ] **I-3** Edge/body limits ≥ 25 MiB audio
- [ ] **B-11** Request validator max matches `UploadAssetValidator`

### Optional

- [ ] **M-3** Mobile smoke after attaching sound to test vibe

### Explicitly not required for create-sound done

- Transcoding / normalization pipeline
- Direct client-to-Spaces uploads
- **`vibe_sounds`** implementation (separate spec)
- Optional thumbnail on create
- Auto duration from audio file

---

## Related Docs

| Document | Path |
| --- | --- |
| Spec | [`spec.md`](spec.md) |
| Plan | [`plan.md`](plan.md) |
| Storage | [`docs/architecture/storage/storage-strategy.md`](../../../architecture/storage/storage-strategy.md) |
| Tests | `back_vibes/tests/Feature/SoundCatalogAuthorizationTest.php` |
