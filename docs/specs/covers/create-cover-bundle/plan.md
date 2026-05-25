# Create Cover Bundle — implementation plan

**Status:** Active implementation plan (aligned with shipped feature)  
**Spec:** [`spec.md`](spec.md)  
**Feature ID:** `covers/create-cover-bundle`

---

## Implementation Summary

**Create Cover Bundle is already implemented** end-to-end: approved admins use **ixora-admin** to submit **multipart** create requests with **three required image files**; **Laravel** validates uploads, writes to **DigitalOcean Spaces**, persists **CDN HTTPS URLs** on the `cover_bundles` row, and returns **201**. **Admin never uploads directly to Spaces.** **Mobile** only **consumes** bundle URLs (via list/show or copied vibe URL columns) — it does not create catalog bundles.

This plan documents **current state**, **guardrails for maintenance**, and **validation/rollout** — not greenfield delivery. **Create does not create vibes or preset_vibes.** **Applying** a bundle to a vibe is a **separate** product flow. No image-processing/transcoding pipeline, **no audio behaviour**, and **no vibe/preset implementation tasks** belong in this plan.

---

## Current State

### Backend (`back_vibes`) — shipped

| Component | Status |
| --- | --- |
| `POST /api/cover-bundles` | ✅ Multipart create |
| `StoreCoverBundleRequest` | ✅ Requires metadata + `thumbnail_file` + `artwork_file` + `player_background_file`; URL fields **prohibited** |
| `CreateCoverBundleWithUploadedFiles` | ✅ Transaction + Spaces upload + CDN URLs |
| `UploadAssetValidator::assertValidCoverCatalogImage` | ✅ 5 MiB image / JPEG, PNG, WebP MIME rules |
| `CoverBundleResource` | ✅ Returns `thumbnail_url`, `artwork_url`, `player_background_url` |
| Auth | ✅ `firebase.auth` + `admin.approved` |
| Safe delete | ✅ `CoverBundleSafeDeletionTest` — **409** when presets or vibes reference bundle |
| Tests | ✅ `CoverBundleApiTest` (create, prohibited URLs, validation) |

### Admin (`ixora-admin`) — shipped

| Component | Status |
| --- | --- |
| `/covers/create` + `CoverBundleForm` mode `create` | ✅ |
| `createCoverBundleWithFiles` → `POST /api/cover-bundles` | ✅ Single multipart submit |
| Client validation | ✅ Name, category, tags, **all three image files** required |
| Error UX | ✅ `friendlyCoverBundleApiMessage`, admin-access redirect |
| Post-create | ✅ Redirect to `/covers` list |
| Spaces | ❌ No direct upload — files go to Laravel only |

### Mobile (`front_vibes`) — no create work

| Component | Status |
| --- | --- |
| Catalog read `GET /api/cover-bundles` | ✅ Uses Bearer token |
| Apply bundle to vibe | ✅ `applyCoverBundleToFormFields` copies non-empty URLs into vibe form — **separate from create** |
| Vibe imagery | ✅ Renders from **vibe** URL columns (copied HTTPS CDN URLs) |
| Catalog bundle create | ❌ Not in scope — by design |

### Domain boundary (confirmed in spec)

- **`cover_bundles`** — visual catalog packages (this feature).
- **`vibes`** — user compositions with **copied** visual URL fields after apply/save.
- **`preset_vibes`** — curated templates; may reference `cover_bundle_id` — **not set by create**.
- **`sounds`** — audio catalog only — **no overlap with cover bundle create**.
- **`vibe_sounds`** — layer configuration — **not touched by Create Cover Bundle**.

---

## Backend Plan

### Keep (do not regress)

1. **Multipart-only create** — reject JSON bodies with pasted URLs; keep `thumbnail_url`, `artwork_url`, `player_background_url` **prohibited** on `StoreCoverBundleRequest`.
2. **`CreateCoverBundleWithUploadedFiles`** as the single write path for create — DB row → Spaces keys → CDN URL update → rollback keys on failure.
3. **Canonical object keys:**
   - `covers/{id}/thumbnail/thumbnail.{ext}`
   - `covers/{id}/artwork/artwork.{ext}`
   - `covers/{id}/player-background/background.{ext}`
4. **`admin.approved`** gate on create route; list/show remain `firebase.auth` (inactive bundles require approved admin via `include_inactive=1`).
5. **No `vibes` or `preset_vibes` writes** in `CoverBundleController::store` or the create action — create must remain catalog-only.
6. **All three image files required** on create — no optional slots without spec + API change.

### Confirm / maintain

| Task | Action |
| --- | --- |
| Upload limits | Keep `StoreCoverBundleRequest` max aligned with `UploadAssetValidator::IMAGE_MAX_BYTES` (5 MiB per file) |
| Edge limits | Ensure Frankenphp/Caddy/App Platform body limits ≥ **5 MiB × 3** multipart payload (ops; see infra) |
| CORS | Staging/production `CORS_ALLOWED_ORIGINS` includes admin origin for multipart POST |
| Safe deletion | Keep reference checks: `preset_vibes.cover_bundle_id` OR matching URLs on `vibes` columns → **409**; Spaces cleanup via `SafeAssetDeletionService` when unreferenced |
| Tests | Keep/extend `CoverBundleApiTest` and `CoverBundleSafeDeletionTest` on any request/rule change |

### Explicitly out of this plan

- Image processing / resize / forced WebP transcoding pipeline
- Optional image slots on create (would need spec + API change)
- Auto-attach bundle to preset on create success
- Bulk import API
- Vibe create/edit or preset editor implementation
- **Any audio behaviour**

---

## Admin Plan

### Keep (do not regress)

1. **Create = one multipart POST** — do not reintroduce JSON-only create or pre-upload via `/api/admin/uploads` on the create page.
2. **`thumbnail_file`, `artwork_file`, and `player_background_file` required** on create in `CoverBundleForm` (`canSubmit` + server mirror).
3. **File `accept` hints** from shared upload limits (match server MIME lists: JPEG, PNG, WebP).
4. **No Spaces credentials** in Nuxt env — only `NUXT_PUBLIC_API_BASE_URL` + Firebase client config.
5. **Validation errors** surfaced via `friendlyCoverBundleApiMessage` (422 lines, 401, 403, 5xx).
6. **Admin never uploads directly to Spaces** — all files POST to Laravel.

### Confirm / maintain

| Task | Action |
| --- | --- |
| Submit busy state | Use `uploadBusy` / `toValue(upload.uploading)` pattern so Create button is not stuck disabled |
| Success navigation | Stay on redirect to `/covers` list after 201 |
| Local previews | Blob previews for three slots before submit |
| Edit flow | Out of scope here — replace media via uploads + PATCH remains separate |

### Explicitly out of this plan

- Preset assignment UI from create success
- Direct-to-Spaces presigned URLs
- Apply bundle to vibe from admin create page
- **Vibe or preset implementation tasks**

---

## Mobile Impact

**None for create.** Mobile is a **consumer** only.

| Area | Impact |
| --- | --- |
| New bundles in catalog | Appear on `GET /api/cover-bundles` after create — no app release required if API contract unchanged |
| Apply to vibe | **`applyCoverBundleToFormFields`** copies non-empty bundle URLs into vibe form; user **POST/PATCH `/api/vibes`** — **separate from create bundle** |
| Vibe imagery | Uses **`thumbnail_url`**, **`artwork_url`**, **`player_background_url`** on the **vibe row** as opaque HTTPS CDN URLs — see [`artwork-background-strategy.md`](../../../architecture/storage/artwork-background-strategy.md) |
| Presets | **`preset_vibes.cover_bundle_id`** — admin preset domain; **not set by create** |
| Auth | Standard Firebase Bearer — see [`front-vibes-auth-core.md`](../../../standards/front-vibes-auth-core.md) |

**Regression check after backend/admin changes:** confirm a newly created bundle appears in mobile bundle picker (staging) and that applying it copies URLs to a test vibe without auto-creating catalog side effects.

---

## Storage / CDN Impact

| Topic | Plan |
| --- | --- |
| Writer | **Laravel only** — **unchanged** |
| New objects | Three keys per create under `covers/{id}/…` |
| URLs | Public **CDN HTTPS** hostname in DB (`DO_SPACES_CDN_URL`) — **not** origin endpoint |
| Credentials | `DO_SPACES_*` on API/worker only — **not** in admin or mobile |
| Shared URLs | Vibes may **copy** bundle URLs onto vibe rows when applied — same HTTPS string until user changes vibe fields |
| Safe delete | **409** when presets or vibes still reference bundle; Spaces cleanup when unreferenced — **remain important** |
| Orphans | Create action deletes keys on failure — monitor logs if 5xx after partial upload |
| Image processing | **Not in plan** — bytes stored as uploaded |

Align with [`storage-strategy.md`](../../../architecture/storage/storage-strategy.md). No infra change required for steady-state create unless upload size or CORS policies change.

---

## Validation Plan

### 1. Laravel tests (required on every backend touch)

```bash
cd back_vibes
php artisan test --filter=CoverBundle
```

**Must pass:**

- [ ] Approved admin **201** with multipart thumbnail + artwork + player background
- [ ] CDN URLs on `thumbnail_url`, `artwork_url`, `player_background_url` match `covers/{id}/…` layout
- [ ] Spaces objects exist after create (faked disk in tests)
- [ ] **URL fields in body → 422** (prohibited)
- [ ] Non-approved admin → **403**
- [ ] Missing any image file / invalid MIME → **422**
- [ ] Safe delete: bundle referenced by preset or vibe URLs → **409**

Add tests if rules change — do not remove multipart coverage.

### 2. Admin build (required on admin touch)

```bash
cd ixora-admin
npm ci
npm run build
```

- [ ] No TypeScript errors in `CoverBundleForm.vue`, `cover-bundle.service.ts`
- [ ] `createCoverBundleWithFiles` still posts `FormData` with all three file fields

### 3. Manual — staging admin (required before calling create “verified” on staging)

Prerequisites: approved admin user, staging admin + API deployed, CORS allows admin origin.

- [ ] Sign in to **staging ixora-admin**
- [ ] **Cover bundles → Create** — fill name, category, tags
- [ ] Select **valid thumbnail, artwork, and player background** (each ≤5 MB, JPEG/PNG/WebP)
- [ ] **Create cover bundle** → **201**, redirect to `/covers` list
- [ ] Open bundle detail — shows **CDN URLs** for all three image fields
- [ ] Open each URL in browser — images load over HTTPS
- [ ] Confirm **no vibe** was auto-created and **no preset** received `cover_bundle_id` (DB or UI)
- [ ] Negative: submit without any image file → blocked in UI; if forced via API → **422**
- [ ] Negative: oversized file → **422** or **413** with readable admin message

### 4. Mobile smoke (optional after staging create)

- [ ] New bundle appears in mobile bundle list
- [ ] Apply bundle to a test vibe via existing flow — URLs copied to vibe form; save vibe separately
- [ ] Vibe player/hero renders imagery from copied CDN URLs on device (staging)

---

## Rollout Plan

Feature is **already in production path** on `develop` / `staging`. Use this checklist for **promotions and regressions**, not initial launch.

| Step | Action |
| --- | --- |
| 1 | Merge changes via Git Flow (`feature/*` → `develop`) — see [`git-flow.md`](../../../standards/git-flow.md) |
| 2 | Promote **`develop` → `staging`** on `back_vibes` and `ixora-admin` together when create/upload touched |
| 3 | Confirm **`CORS_ALLOWED_ORIGINS`** on staging API includes admin URL (`ixora-infra` if changed) |
| 4 | Run **Laravel tests** + **admin build** |
| 5 | **Manual create-cover-bundle** on staging admin (Validation Plan §3) |
| 6 | Release cycle: `release/*` → `main` when product signs off — mobile optional unless API contract changes |

**No mobile app store release** required for create-cover-bundle-only backend/admin fixes unless response shape changes.

---

## Open Questions

| # | Question | Default / note |
| --- | --- | --- |
| 1 | When will **image processing / resize / WebP normalization** ship? | **Out of scope** — ADR + new keys when proposed; not current architecture |
| 2 | Should any image slot become **optional** on create? | **All three required** today — spec + API change needed |
| 3 | Admin “apply to preset” shortcut from create success? | **Out of scope** — no auto-attach |
| 4 | Edge **413** vs Laravel **422** messaging for 3×5 MiB payloads? | Verify Frankenphp/Caddy limits on each deploy |
| 5 | Vibe URL validation whitelist on Laravel PATCH? | Track in artwork-background doc — not blocking create |

**Explicitly excluded from this plan:** audio behaviour, vibe/preset implementation tasks, transcoding pipeline.

---

## Related Docs

| Document | Path |
| --- | --- |
| **Feature spec** | [`spec.md`](spec.md) |
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

Future: **apply cover bundle to vibe** and **preset assignment** remain separate product flows — reference domain model in [`spec.md`](spec.md), not implementation tasks in this plan.
