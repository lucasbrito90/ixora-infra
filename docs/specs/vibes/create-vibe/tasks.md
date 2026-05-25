# Create Vibe — task checklist

**Status:** Feature **shipped** — checklist for regression, verification, and maintenance (not greenfield)  
**Spec:** [`spec.md`](spec.md)  
**Plan:** [`plan.md`](plan.md)  
**Feature ID:** `vibes/create-vibe`

**Status legend**

| Status | Meaning |
| --- | --- |
| **Completed** | Implemented and in codebase |
| **To verify** | Re-run or confirm on each relevant change / staging promotion |
| **Future / separate spec** | Out of scope for create-vibe |

---

## Task List

| Area | Completed | To verify | Future / separate spec |
| --- | ---: | ---: | ---: |
| Documentation | 2 | 1 | 2 |
| Backend | 11 | 2 | 1 |
| Mobile | 8 | 2 | 2 |
| Storage / CDN | 5 | 1 | 0 |
| Validation | 1 | 8 | 0 |

---

## Backend Tasks

| ID | Task | Status | Reference |
| --- | --- | --- | --- |
| B-1 | `POST /api/vibes` accepts **JSON** create with metadata | **Completed** | `VibeController::store`, `routes/api.php` |
| B-2 | **`user_id` set server-side** on create — client cannot set owner | **Completed** | `VibeController::store` |
| B-3 | **`StoreVibeRequest`** validates **`name`** (required), **`description`**, **`is_active`** | **Completed** | `StoreVibeRequest.php` |
| B-4 | **`VibeController::store`** **does not create `sounds` or `cover_bundles` rows** | **Completed** | Catalog-only boundary |
| B-5 | **`VibeController::store`** **does not insert `vibe_sounds` rows** | **Completed** | Layers via nested routes only |
| B-6 | **`VibeController::store`** **does not create or link `preset_vibes`** | **Completed** | No preset writes in store |
| B-7 | **`VibePolicy`** — owner match for **view / update / delete**; **`create`** for authenticated users | **Completed** | `VibePolicy.php` |
| B-8 | **`VibeController::index`** scoped to **`auth()->id()`** | **Completed** | `VibeController.php` |
| B-9 | **`VibeResource`** returns visual URL fields with **`thumbnail_url` fallbacks** | **Completed** | `VibeResource.php` |
| B-10 | Vibe routes use **`firebase.auth`** only (no **`admin.approved`**) | **Completed** | `routes/api.php` |
| B-11 | Nested **`VibeSoundController`** attach/detach requires **`authorize('update', $vibe)`** | **Completed** | `VibeSoundController.php` |
| B-12 | **`play_mode` → `loop` derivation** on attach (not trusted from client alone) | **Completed** | `VibeSoundController::store` |
| B-13 | **`StoreVibeRequest` / `UpdateVibeRequest` whitelist** visual URL fields (`thumbnail_url`, `artwork_url`, `player_background_url`) | **To verify** | Alignment gap — see [`artwork-background-strategy.md`](../../../architecture/storage/artwork-background-strategy.md) |
| B-14 | Dedicated **`POST /api/vibes` feature tests** (201, ownership, 422, 403, no pivot on create) | **To verify** | Gap vs `PresetVibeImportApiTest` |
| — | **Atomic create + initial `vibe_sounds`** in one request | **Future / separate spec** | Not implemented today |

---

## Mobile Tasks

| ID | Task | Status | Reference |
| --- | --- | --- | --- |
| M-1 | **`/vibes/create`** + **`CreateVibePage.vue`** | **Completed** | `router/index.ts` |
| M-2 | **`applyCoverBundleToFormFields`** — only **non-empty** bundle URLs overwrite form fields | **Completed** | `cover-bundle-apply.ts` |
| M-3 | **`createVibe`** → **`POST /api/vibes`** JSON with metadata + visual URL keys when set | **Completed** | `vibe.service.ts` |
| M-4 | **Name required** — submit disabled when empty | **Completed** | `CreateVibePage.vue` |
| M-5 | Success → **`router.replace('/vibes')`** — **no auto sound attach** on create | **Completed** | `CreateVibePage.vue` |
| M-6 | Imagery resolution via **`artwork.ts`** — no duplicated fallback chains in pages | **Completed** | `utils/artwork.ts` |
| M-7 | **No `DO_SPACES_*`** in front_vibes | **Completed** | Storage architecture |
| M-8 | **No offline snapshot** written on create — snapshot only after download-for-offline | **Completed** | `offline-vibe-cache.service.ts`, `VibePlayerPage.vue` |
| M-9 | **`VibePayload` parity** with backend URL whitelist after alignment | **To verify** | After **B-13** lands |
| M-10 | **Optional smoke:** create with cover → attach sound → play on staging device | **To verify** | After staging create flow |
| — | **Preset import** (`POST /api/preset-vibes/{id}/import`) | **Future / separate spec** | Parallel create path — not manual create |
| — | **Auto-attach sounds** on create submit | **Future / separate spec** | Not implemented — by design |

---

## Storage / CDN Tasks

| ID | Task | Status | Reference |
| --- | --- | --- | --- |
| S-1 | Vibe create **does not write new Spaces objects** — URL strings only | **Completed** | [`storage-strategy.md`](../../../architecture/storage/storage-strategy.md) |
| S-2 | Visual URLs on vibe are **copied HTTPS CDN strings** (e.g. from applied cover bundle) | **Completed** | Domain model in [`spec.md`](spec.md) |
| S-3 | Mobile consumes **opaque HTTPS URLs** only — no bucket credentials | **Completed** | No upload pipeline on create |
| S-4 | Catalog object writes remain **Laravel-only** (sounds / cover bundles — separate specs) | **Completed** | Not invoked by vibe create |
| S-5 | Offline snapshot stores vibe meta URLs + layers at **download** time — requires **stable URLs** | **Completed** | [`audio-cache.md`](../../../architecture/audio/audio-cache.md) |
| S-6 | Cover bundle **safe delete** still returns **409** when vibe URL columns reference bundle URLs | **To verify** | `CoverBundleSafeDeletionTest.php` — catalog boundary |

---

## Validation Tasks

| ID | Task | Status | Command / notes |
| --- | --- | --- | --- |
| V-1 | Run **Laravel PresetVibeImport** tests (preset→vibe path) | **To verify** | `cd back_vibes && php artisan test --filter=PresetVibeImport` |
| V-2 | Add/run **`POST /api/vibes` feature tests** when implemented | **To verify** | See **B-14** |
| V-3 | Run **front_vibes production build** | **To verify** | `cd front_vibes && npm ci && npm run build` |
| V-4 | **Manual staging create-vibe** (full checklist) | **To verify** | See [Manual staging checklist](#manual-staging-checklist) below |
| V-5 | Missing **`name`** → **422** (API); blocked in mobile UI | **Completed** | Mobile guard; API via `StoreVibeRequest` |
| V-6 | Cross-user **view / update / delete / attach** → **403** | **To verify** | Policy + nested routes |
| V-7 | Confirm create **does not** insert catalog rows or **`vibe_sounds`** | **To verify** | Manual staging + code review of `store` |
| V-8 | Visual URLs **persist** on refetch after cover apply (**after B-13**) | **To verify** | Manual + feature test |
| V-9 | **Optional:** download-for-offline writes snapshot **only after** download success — not on create | **To verify** | `VibePlayerPage.vue` |

### Manual staging checklist

Prerequisites: synced Firebase user, staging API, mobile against staging.

- [ ] Sign in to **staging app**
- [ ] **New Vibe** — name, optional description
- [ ] **Choose cover** — apply bundle → local previews update
- [ ] **Create Vibe** → **201**, redirect to My Vibes
- [ ] Refetch vibe — visual URLs on row (**after B-13**)
- [ ] Confirm **no new** `sounds` or `cover_bundles` from this action
- [ ] **Manage sounds** — attach one catalog sound → appears on `GET .../sounds`
- [ ] UI blocks empty name
- [ ] Optional: play attached layer from CDN **`file_url`**
- [ ] Optional: offline download → snapshot written; create alone did not write snapshot

---

## Documentation Tasks

| ID | Task | Status | Reference |
| --- | --- | --- | --- |
| D-1 | **`spec.md`** includes **Related Domain Model** (`vibes` / `sounds` / `cover_bundles` / `vibe_sounds`) | **Completed** | [`spec.md`](spec.md) § Related Domain Model |
| D-2 | **`spec.md`** + **`plan.md`** published under `docs/specs/vibes/create-vibe/` | **Completed** | This folder |
| D-3 | **`tasks.md`** kept aligned when create behaviour changes | **To verify** | Update on API/mobile contract changes |
| — | Active **`vibe-sounds`** spec (`plan.md` / `tasks.md`) | **Future / separate spec** | [`../vibe-sounds/spec.md`](../vibe-sounds/spec.md) |
| — | **Preset import** formal spec | **Future / separate spec** | `POST /api/preset-vibes/{id}/import` |

---

## Done Criteria

Create Vibe is **done** for this feature slice when all of the following hold:

### Shipped (maintain — already true)

- [x] Authenticated user can create a **user-owned** vibe via **`POST /api/vibes`**
- [x] **`user_id`** set server-side; **`VibePolicy`** enforces owner for view/update/delete
- [x] Create **does not** create **`sounds`**, **`cover_bundles`**, or **`preset_vibes`**
- [x] Create **does not** insert **`vibe_sounds`** in `store`
- [x] Mobile **apply cover bundle** copies non-empty CDN URLs into form + POST body
- [x] Sound layers belong to **`vibe_sounds`** — attached separately after create
- [x] **No Spaces upload pipeline** on vibe create — copied URL strings only
- [x] **No offline snapshot** on create — only on download-for-offline
- [x] **`spec.md`** documents domain model and links **`plan.md`** / **`tasks.md`**

### Verify on each staging promotion or vibe create/validation change

- [ ] **V-1** Laravel `PresetVibeImport` tests pass
- [ ] **V-3** front_vibes build passes
- [ ] **V-4** Manual staging create-vibe checklist complete
- [ ] **V-6** Cross-user access returns **403**
- [ ] **V-7** No catalog or pivot side effects on create
- [ ] **B-13** Visual URL fields whitelisted and **V-8** persistence confirmed
- [ ] **B-14** / **V-2** Dedicated `POST /api/vibes` feature tests pass
- [ ] **S-6** Cover bundle safe-delete **409** still active when vibes reference URLs

### Optional

- [ ] **M-10** / **V-9** Play + offline smoke after attach / download

### Explicitly not required for create-vibe done

- Vibe create multipart / Spaces upload pipeline
- Image or audio **transcoding**
- **Public / shared / collaborative** vibes
- **Direct client-to-Spaces** uploads
- **Atomic create + layers** in one API
- **Preset import** spec or admin user-vibe tooling
- Runtime **fade** playback (fields may exist on pivot — ignored at runtime)

---

## Related Docs

| Document | Path |
| --- | --- |
| Spec | [`spec.md`](spec.md) |
| Plan | [`plan.md`](plan.md) |
| Vibe sounds (layers) | [`../vibe-sounds/spec.md`](../vibe-sounds/spec.md) |
| Create Cover Bundle | [`../../covers/create-cover-bundle/spec.md`](../../covers/create-cover-bundle/spec.md) |
| Create Sound | [`../../sounds/create-sound/spec.md`](../../sounds/create-sound/spec.md) |
| Storage | [`docs/architecture/storage/storage-strategy.md`](../../../architecture/storage/storage-strategy.md) |
| Artwork / background | [`docs/architecture/storage/artwork-background-strategy.md`](../../../architecture/storage/artwork-background-strategy.md) |
| Audio cache / offline | [`docs/architecture/audio/audio-cache.md`](../../../architecture/audio/audio-cache.md) |
| **Tests** | `back_vibes/tests/Feature/PresetVibeImportApiTest.php`; `POST /api/vibes` tests TBD |
