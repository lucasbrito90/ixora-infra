# Create Sound — implementation plan

**Status:** Active implementation plan (aligned with shipped feature)  
**Spec:** [`spec.md`](spec.md)  
**Feature ID:** `sounds/create-sound`

---

## Implementation Summary

**Create Sound is already implemented** end-to-end: approved admins use **ixora-admin** to submit **multipart** create requests; **Laravel** validates files, writes to **DigitalOcean Spaces**, persists **CDN URLs** on the `sounds` row, and returns **201**. **Mobile** only **consumes** `file_url` and `thumbnail_url` when sounds appear in catalog or vibe layers — it does not create catalog sounds.

This plan documents **current state**, **guardrails for maintenance**, and **validation/rollout** — not greenfield delivery. No transcoding service, no direct Spaces access from admin/mobile, and **no `vibe_sounds` writes** during create.

---

## Current State

### Backend (`back_vibes`) — shipped

| Component | Status |
| --- | --- |
| `POST /api/admin/sounds` / `POST /api/sounds` | ✅ Multipart create |
| `StoreSoundRequest` | ✅ Requires metadata + `audio_file` + `thumbnail_file`; URL fields **prohibited** |
| `CreateSoundWithUploadedFiles` | ✅ Transaction + Spaces upload + CDN URLs |
| `UploadAssetValidator` | ✅ 25 MB audio / 5 MB image MIME rules |
| `SoundResource` | ✅ Returns `file_url`, `audio_url` alias, `thumbnail_url` |
| Auth | ✅ `firebase.auth` + `admin.approved` |
| Tests | ✅ `SoundCatalogAuthorizationTest` (create, prohibited URLs) |

### Admin (`ixora-admin`) — shipped

| Component | Status |
| --- | --- |
| `/sounds/create` + `SoundForm` mode `create` | ✅ |
| `createSoundWithFiles` → `POST /api/admin/sounds` | ✅ Single multipart submit |
| Client validation | ✅ Name, category, duration, tags, **both files** required |
| Error UX | ✅ `friendlySoundApiMessage`, admin-access redirect |
| Post-create | ✅ Redirect to `/sounds/{id}/edit` |

### Mobile (`front_vibes`) — no create work

| Component | Status |
| --- | --- |
| Catalog read `GET /api/sounds` | ✅ Uses Bearer token |
| Layer playback | ✅ Uses sound `file_url` from vibe payload — opaque HTTPS CDN |
| Catalog sound create | ❌ Not in scope — by design |

### Domain boundary (confirmed in spec)

- **`sounds`** — catalog assets (this feature).
- **`vibes`** — compositions.
- **`vibe_sounds`** — layer configuration (volume, order, play mode, fades, timing). **Not touched by Create Sound.**

---

## Backend Plan

### Keep (do not regress)

1. **Multipart-only create** — reject JSON bodies with pasted URLs; keep `file_url` / `thumbnail_url` **prohibited** on `StoreSoundRequest`.
2. **`CreateSoundWithUploadedFiles`** as the single write path for create — DB row → Spaces keys → CDN URL update → rollback keys on failure.
3. **Canonical object keys:** `sounds/{id}/audio/original.{ext}`, `sounds/{id}/thumbnail/thumbnail.{ext}`.
4. **`admin.approved`** gate on create routes only; list/show remain `firebase.auth`.
5. **No `vibe_sounds` (or preset) inserts** in `SoundController::store` or the create action — create must remain catalog-only.

### Confirm / maintain

| Task | Action |
| --- | --- |
| Upload limits | Keep `StoreSoundRequest` max aligned with `UploadAssetValidator::AUDIO_MAX_BYTES` (25 MiB) |
| Edge limits | Ensure Frankenphp/Caddy/App Platform body limits ≥ 25 MiB audio (ops; see infra) |
| CORS | Staging/production `CORS_ALLOWED_ORIGINS` includes admin origin for multipart POST |
| Tests | Keep/extend `SoundCatalogAuthorizationTest` on any request/rule change |

### Explicitly out of this plan

- Transcoding / normalization workers
- Optional thumbnail on create (would need spec + API change)
- Auto duration detection from audio file
- Bulk import API

---

## Admin Plan

### Keep (do not regress)

1. **Create = one multipart POST** — do not reintroduce JSON-only create or pre-upload via `/api/admin/uploads` on the create page.
2. **`audio_file` and `thumbnail_file` required** on create in `SoundForm` (`canSubmit` + server mirror).
3. **File `accept` hints** from `shared/upload-limits.ts` (match server MIME lists).
4. **No Spaces credentials** in Nuxt env — only `NUXT_PUBLIC_API_BASE_URL` + Firebase client config.
5. **Validation errors** surfaced via `friendlySoundApiMessage` (422 lines, 401, 403, 5xx).

### Confirm / maintain

| Task | Action |
| --- | --- |
| Submit busy state | Use `toValue(upload.uploading)` pattern so Create button is not stuck disabled |
| Success navigation | Stay on redirect to edit page after 201 |
| Edit flow | Out of scope here — replace media via uploads + PATCH remains separate |

### Explicitly out of this plan

- Vibe sound attachment UI
- Direct-to-Spaces presigned URLs
- Waveform preview / duration auto-fill

---

## Mobile Impact

**None for create.** Mobile is a **consumer** only.

| Area | Impact |
| --- | --- |
| New sounds in catalog | Appear on `GET /api/sounds` after create — no app release required if API contract unchanged |
| Playback | Uses **`file_url`** (or legacy **`audio_url`**) as opaque HTTPS — ExoPlayer streaming per [`audio-cache.md`](../../../architecture/audio/audio-cache.md) |
| Thumbnails | Uses **`thumbnail_url`** when UI shows catalog previews — optional display only |
| Vibe layers | Sound must be **attached separately** via vibe APIs (`vibe_sounds`) — future spec |
| Auth | Standard Firebase Bearer — see [`front-vibes-auth-core.md`](../../../standards/front-vibes-auth-core.md) |

**Regression check after backend/admin changes:** smoke-play a newly created sound URL on device (staging) once attached to a test vibe or referenced in catalog browse if exposed.

---

## Storage / CDN Impact

| Topic | Plan |
| --- | --- |
| Writer | Laravel only — **unchanged** |
| New objects | Two keys per create under `sounds/{id}/…` |
| URLs | Public CDN hostname in DB — **not** origin endpoint |
| Credentials | `DO_SPACES_*` on API/worker only |
| Orphans | Create action deletes keys on failure — monitor logs if 5xx after partial upload |
| Transcoding | **Not in plan** — files stored as uploaded |

Align with [`storage-strategy.md`](../../../architecture/storage/storage-strategy.md). No infra change required for steady-state create unless upload size or CORS policies change.

---

## Validation Plan

### 1. Laravel tests (required on every backend touch)

```bash
cd back_vibes
php artisan test --filter=SoundCatalog
```

**Must pass:**

- [ ] Approved admin **201** with multipart audio + thumbnail
- [ ] CDN URLs on `file_url` / `thumbnail_url` match `sounds/{id}/…` layout
- [ ] Spaces objects exist after create (faked disk in tests)
- [ ] **`file_url` in body → 422** (prohibited)
- [ ] Non-approved admin → **403**
- [ ] Missing files / invalid MIME → **422**

Add tests if rules change — do not remove multipart coverage.

### 2. Admin build (required on admin touch)

```bash
cd ixora-admin
npm ci
npm run build
```

- [ ] No TypeScript errors in `SoundForm.vue`, `sound.service.ts`
- [ ] `createSoundWithFiles` still posts `FormData` with both file fields

### 3. Manual — staging admin (required before calling create “verified” on staging)

Prerequisites: approved admin user, staging admin + API deployed, CORS allows admin origin.

- [ ] Sign in to **staging ixora-admin**
- [ ] **Sounds → Create** — fill name, category, tags, duration
- [ ] Select **valid audio** (≤25 MB) and **thumbnail** (≤5 MB)
- [ ] **Create sound** → **201**, redirect to edit
- [ ] Edit page shows **CDN URLs** (read-only) for audio + thumbnail
- [ ] Open **`file_url`** in browser — audio loads (progressive HTTPS)
- [ ] Open **`thumbnail_url`** — image loads
- [ ] Confirm **no vibe** was auto-created or auto-linked (DB or UI)
- [ ] Negative: submit without thumbnail → blocked in UI; if forced via API → **422**
- [ ] Negative: oversized file → **422** or **413** with readable admin message

### 4. Mobile smoke (optional after staging create)

- [ ] Attach new sound to a test vibe via existing vibe-sound flow (separate from create)
- [ ] Play layer on Android build against staging API — stream from CDN URL

---

## Rollout Plan

Feature is **already in production path** on `develop` / `staging`. Use this checklist for **promotions and regressions**, not initial launch.

| Step | Action |
| --- | --- |
| 1 | Merge changes via Git Flow (`feature/*` → `develop`) — see [`git-flow.md`](../../../standards/git-flow.md) |
| 2 | Promote **`develop` → `staging`** on `back_vibes` and `ixora-admin` together when create/upload touched |
| 3 | Confirm **`CORS_ALLOWED_ORIGINS`** on staging API includes admin URL (`ixora-infra` if changed) |
| 4 | Run **Laravel tests** + **admin build** |
| 5 | **Manual create** on staging admin (Validation Plan §3) |
| 6 | Release cycle: `release/*` → `main` when product signs off — mobile optional unless API contract changes |

**No mobile app store release** required for create-sound-only backend/admin fixes unless response shape changes.

---

## Open Questions

| # | Question | Default / note |
| --- | --- | --- |
| 1 | Should **duration** be auto-detected from audio later? | **Manual entry** today — future spec |
| 2 | Should **thumbnail** become optional on create? | **Required** today — spec + API change needed |
| 3 | When will **vibe_sounds attach** get its own spec? | Track separately — not blocking create |
| 4 | Transcoding service timeline? | **Out of scope** — ADR when proposed |
| 5 | Edge **413** vs Laravel **422** messaging in all environments? | Verify Frankenphp/Caddy limits match 25 MiB on each deploy |

---

## Related Docs

| Document | Path |
| --- | --- |
| **Feature spec** | [`spec.md`](spec.md) |
| **Task checklist** | [`tasks.md`](tasks.md) |
| Storage policy | [`docs/architecture/storage/storage-strategy.md`](../../../architecture/storage/storage-strategy.md) |
| Mobile CDN QA | [`docs/architecture/storage/mobile-cdn-validation.md`](../../../architecture/storage/mobile-cdn-validation.md) |
| Audio cache / streaming | [`docs/architecture/audio/audio-cache.md`](../../../architecture/audio/audio-cache.md) |
| Auth | [`docs/standards/front-vibes-auth-core.md`](../../../standards/front-vibes-auth-core.md) |
| Git Flow | [`docs/standards/git-flow.md`](../../../standards/git-flow.md) |
| **back_vibes** | `docs/laravel-upload-endpoints.md` |
| **ixora-admin** | `docs/sound-model.md` |
| **Tests** | `back_vibes/tests/Feature/SoundCatalogAuthorizationTest.php` |

Future: **`specs/vibes/vibe-sounds/`** (or equivalent) for attaching catalog sounds to vibes — references `vibe_sounds` layer model, not this plan. Track tasks in [`tasks.md`](tasks.md) under **Future / separate spec**.
