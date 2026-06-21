# Create Vibe — implementation plan

**Status:** Active implementation plan (aligned with shipped feature)  
**Spec:** [`spec.md`](spec.md)  
**Feature ID:** `vibes/create-vibe`

---

## Implementation Summary

**Create Vibe is already implemented** on mobile: authenticated users submit **`POST /api/vibes`** with metadata and optional visual URL fields; Laravel creates a **user-owned** `vibes` row (`user_id` from auth); **sound layers** are attached separately via **`vibe_sounds`** nested routes. **Creating a vibe does not create catalog `sounds` or `cover_bundles`.** Visual identity may come from an **applied cover bundle** (copied HTTPS CDN URL strings on the vibe row). **No upload pipeline** runs on vibe create — only URL string persistence.

This plan documents **current state**, **guardrails for maintenance**, and **validation/rollout** — not greenfield delivery. **Offline snapshots** are written only during **download-for-offline** on the player page, not at create time. Known **validation alignment gap:** mobile sends visual URL fields but `StoreVibeRequest` / `UpdateVibeRequest` do not whitelist them yet — see Backend Plan.

---

## Current State

### Backend (`back_vibes`) — shipped

| Component | Status |
| --- | --- |
| `POST /api/vibes` | ✅ JSON create; `user_id` set server-side |
| `StoreVibeRequest` | ✅ Validates `name`, `description`, `is_active` |
| Visual URL fields on create/update | ⚠️ **Not in validation rules** — mobile-sent URLs silently dropped by `validated()` |
| `VibeController::store` | ✅ Catalog-only insert — no `sounds`, `cover_bundles`, `vibe_sounds`, `preset_vibes` |
| `VibePolicy` | ✅ Owner match for view/update/delete; `create` allowed for authenticated users |
| `VibeController::index` | ✅ Scoped to `auth()->id()` |
| `VibeResource` | ✅ CDN URL fields + `thumbnail_url` fallbacks for card/artwork/player |
| Nested `VibeSoundController` | ✅ Attach/detach after vibe exists — separate from store |
| Auth | ✅ `firebase.auth` only (no `admin.approved` on user vibes) |
| Tests | ⚠️ No dedicated `POST /api/vibes` feature tests; `PresetVibeImportApiTest` covers preset→vibe path |

### Mobile (`front_vibes`) — shipped

| Component | Status |
| --- | --- |
| `/vibes/create` + `CreateVibePage.vue` | ✅ |
| Cover picker + `applyCoverBundleToFormFields` | ✅ Non-empty bundle URLs → form fields |
| `createVibe` → `POST /api/vibes` JSON | ✅ Sends metadata + three visual URL keys when set |
| Post-create navigation | ✅ `router.replace('/vibes')` — no auto sound attach |
| Sound layers | ✅ Separate `VibeSoundsPage` → `POST/DELETE /api/vibes/{id}/sounds` |
| Execution plan | ✅ `buildVibeExecutionPlan` from loaded `vibe_sounds` |
| Offline snapshot on create | ❌ By design — snapshot only after download-for-offline |
| Spaces credentials | ❌ None — `VITE_API_BASE_URL` + Firebase only |

### Admin (`ixora-admin`) — not in scope

| Component | Status |
| --- | --- |
| End-user vibe create UI | ❌ Mobile-first — no admin create flow |
| Catalog create (sounds / cover bundles) | Separate specs — not invoked by vibe create |

### Domain boundary (confirmed in spec)

- **`vibes`** — user-owned compositions (`user_id`).
- **`cover_bundles`** — visual catalog; URLs **copied** into vibe form, not created on vibe create.
- **`sounds`** — audio catalog; referenced by `sound_id` on attach only.
- **`vibe_sounds`** — layer configuration (volume, order, `play_mode`, timing). **Not inserted in `VibeController::store`.**
- **`preset_vibes`** — separate import path (`POST /api/preset-vibes/{id}/import`).

---

## Backend Plan

### Keep (do not regress)

1. **`user_id` set server-side** on create — never accept owner from client body.
2. **`VibePolicy`** owner checks on view/update/delete; index query scoped to authenticated user.
3. **`VibeController::store`** creates **only** a `vibes` row — **no** catalog inserts, **no** `vibe_sounds` attach in store.
4. **`firebase.auth`** on vibe routes — no `admin.approved` requirement for end-user create.
5. **Nested sound routes** require **`authorize('update', $vibe)`** — cross-user attach blocked.
6. **`VibeResource`** fallback chain for visual fields (`card_image_url`, `artwork_url`, `player_background_url` → `thumbnail_url`).

### Confirm / maintain (priority)

| Task | Action |
| --- | --- |
| **Visual URL validation whitelist** | Add `thumbnail_url`, `artwork_url`, `player_background_url` (nullable URL strings, max ~2048) to **`StoreVibeRequest`** and **`UpdateVibeRequest`** per [`artwork-background-strategy.md`](../../../architecture/storage/artwork-background-strategy.md) |
| URL persistence verify | After whitelist: manual create with cover bundle → refetch vibe → URLs present on row |
| `AttachVibeSoundRequest` | Keep `play_mode` → `loop` derivation in `VibeSoundController` |
| Fade fields | Stored on pivot only — **no runtime fade promise** ([`audio-engine-fade-limitations.md`](../../../architecture/audio/audio-engine-fade-limitations.md)) |
| Tests | Add `POST /api/vibes` feature tests (201, ownership, URL persistence, 422 missing name, 403 cross-user) |

### Explicitly out of this plan

- Vibe create multipart / Spaces upload pipeline (**not implemented** — copied URLs only)
- Atomic create + initial `vibe_sounds` in one request
- Public / shared / collaborative vibes
- Preset import spec and implementation
- Catalog transcoding or image processing
- Admin end-user vibe management UI

---

## Mobile Plan

### Keep (do not regress)

1. **Create flow** — `CreateVibePage` → **`POST /api/vibes`** JSON (not multipart, not Spaces).
2. **Cover apply** — **`applyCoverBundleToFormFields`**: only **non-empty** bundle URLs overwrite form fields; empty bundle fields do not clear existing values.
3. **Required name** — submit disabled when name empty; server mirrors with **422** if forced.
4. **Success path** — redirect to **`/vibes`**; user attaches sounds separately via **Manage sounds**.
5. **Imagery** — resolve display URLs via **`artwork.ts`** — do not duplicate fallback chains in pages.
6. **No `DO_SPACES_*`** in mobile env or bundles.

### Confirm / maintain

| Task | Action |
| --- | --- |
| Cover bundle list | `GET /api/cover-bundles` with Firebase Bearer before picker opens |
| Payload parity | `VibePayload` visual keys match backend whitelist once aligned |
| Edit flow | `EditVibePage` same apply + PATCH semantics — out of create scope but same URL contract |
| Player / offline | **`saveOfflineVibeSnapshot`** only from **`VibePlayerPage`** download success — **not** on create |

### Explicitly out of this plan

- Direct-to-Spaces presigned uploads for vibe visuals
- Auto-attach sounds on create submit
- Fade controls promising runtime behaviour
- Offline-first vibe create without API

---

## Mobile Impact

Create vibe is **mobile-owned** end-user flow.

| Area | Impact |
| --- | --- |
| New vibe in list | Appears on `GET /api/vibes` after **201** — scoped to owner |
| Visual previews | Depend on persisted URL columns; until backend whitelist, list may show fallbacks/gradients after refetch |
| Sound playback | Requires separate attach → `vibe_sounds` → execution plan — not part of create submit |
| Cover bundles | Read-only catalog input; apply copies CDN URLs into form then POST body |
| Auth | Firebase Bearer + sync — [`front-vibes-auth-core.md`](../../../standards/front-vibes-auth-core.md) |
| App release | Backend-only URL whitelist fix may not require store release if mobile payload unchanged |

**Regression check after backend/mobile changes:** staging create with cover bundle → verify URLs on API GET; attach one catalog sound → play on device.

---

## Storage / CDN Impact

| Topic | Plan |
| --- | --- |
| Vibe create writer | Laravel persists **URL strings** on `vibes` — **no new Spaces objects** on manual create |
| Upload pipeline | **None** on vibe create — unlike admin catalog create flows |
| Copied URLs | Same HTTPS CDN strings as cover bundle (shared objects) until user edits vibe fields |
| Mobile reader | Opaque HTTPS only — no `DO_SPACES_*` on device |
| Catalog writer | Laravel only (sounds / cover bundles) — separate specs |
| Safe delete | Cover bundle delete still blocked when vibe URL columns reference bundle URLs — **409** |
| Offline | Snapshot stores vibe meta URLs + `vibeSounds` at **download** time — stable URLs required |

Align with [`storage-strategy.md`](../../../architecture/storage/storage-strategy.md). **No infra change** for steady-state vibe create unless URL validation or CORS policies change.

---

## Validation Plan

### 1. Laravel tests (required on every backend touch)

```bash
cd back_vibes
php artisan test --filter=PresetVibeImport
```

**Existing coverage (preset path):** preset import creates user vibe with bundle URLs + layers.

**Add / maintain for manual create (gap today):**

- [ ] Authenticated user **201** on `POST /api/vibes` with `name`
- [ ] Response **`user_id`** matches auth user (via policy/list scope)
- [ ] Visual URLs **persist** when sent after `StoreVibeRequest` whitelist lands
- [ ] Missing `name` → **422**
- [ ] Cross-user `GET/PATCH/DELETE` → **403**
- [ ] `POST /api/vibes` does **not** create `vibe_sounds` rows

### 2. Mobile build (required on mobile touch)

```bash
cd front_vibes
npm ci
npm run build
```

- [ ] No TypeScript errors in `CreateVibePage.vue`, `vibe.service.ts`, `cover-bundle-apply.ts`
- [ ] `createVibe` still posts JSON with expected `VibePayload` shape

### 3. Manual — staging mobile (required before calling create “verified” on staging)

Prerequisites: synced Firebase user, staging API + mobile against staging.

- [ ] Sign in to **staging app**
- [ ] **New Vibe** — enter name, optional description
- [ ] **Choose cover** — apply bundle → previews update
- [ ] **Create Vibe** → **201**, redirect to My Vibes
- [ ] Refetch vibe (or reopen) — visual URLs persisted on row (**after backend whitelist**)
- [ ] Confirm **no new** `sounds` or `cover_bundles` catalog rows from this action
- [ ] **Manage sounds** — attach one catalog sound → layer appears on `GET .../sounds`
- [ ] Negative: empty name blocked in UI

### 4. Optional smoke (after attach)

- [ ] Play vibe on Android — execution plan streams from sound `file_url` (CDN HTTPS)
- [ ] Download for offline → confirm snapshot written **only after** download success, not on create

---

## Rollout Plan

Feature is **already in production path** on `develop` / `staging`. Use this checklist for **promotions and regressions**, not initial launch.

| Step | Action |
| --- | --- |
| 1 | Merge changes via Git Flow (`feature/*` → `develop`) — see [`git-flow.md`](../../../standards/git-flow.md) |
| 2 | Promote **`develop` → `staging`** on `back_vibes` and `front_vibes` when vibe create/validation touched |
| 3 | Run **Laravel tests** (+ new vibe create tests when added) + **mobile build** |
| 4 | **Manual staging create-vibe** flow (Validation Plan §3) |
| 5 | If **`StoreVibeRequest` URL whitelist** ships: verify cover URLs survive create + edit PATCH |
| 6 | Release cycle: `release/*` → `main` when product signs off |

**Mobile app store release** optional for backend-only validation fixes if API contract and mobile payload unchanged.

---

## Open Questions

| # | Question | Default / note |
| --- | --- | --- |
| 1 | When to land **`StoreVibeRequest` / `UpdateVibeRequest` URL whitelist**? | **High priority alignment** — blocks cover persistence on manual create |
| 2 | Add dedicated **`POST /api/vibes` feature tests**? | **Recommended** — gap vs preset import coverage |
| 3 | Atomic create + layers in one API? | **Future / separate spec** — not today |
| 4 | Public / shared vibes? | **Not implemented** — would need schema + policies |
| 5 | Preset import formal spec? | **Future / separate spec** — parallel create path |
| 6 | Promote **`vibe-sounds`** placeholder to active spec? | Track separately — layer attach already shipped |

---

## Future Work (out of current scope)

| Topic | Notes |
| --- | --- |
| **`StoreVibeRequest` URL whitelist** | Near-term maintenance — not new product scope |
| Atomic vibe + `vibe_sounds` create | API design + mobile UX — future spec |
| Admin user-vibe tooling | ixora-admin — future |
| Public / collaborative vibes | Not implemented |
| Preset import spec | `POST /api/preset-vibes/{id}/import` |
| Active **`vibe-sounds`** spec | [`../vibe-sounds/spec.md`](../vibe-sounds/spec.md) promotion |
| Fade engine / transcoding | ADR + separate audio/infra work |

---

## Related Docs

| Document | Path |
| --- | --- |
| **Feature spec** | [`spec.md`](spec.md) |
| **Task checklist** | [`tasks.md`](tasks.md) |
| Vibe sounds (layers) | [`../vibe-sounds/spec.md`](../vibe-sounds/spec.md) |
| Create Sound | [`../../sounds/create-sound/spec.md`](../../sounds/create-sound/spec.md) |
| Create Cover Bundle | [`../../covers/create-cover-bundle/spec.md`](../../covers/create-cover-bundle/spec.md) |
| Storage policy | [`docs/architecture/storage/storage-strategy.md`](../../../architecture/storage/storage-strategy.md) |
| Artwork / background | [`docs/architecture/storage/artwork-background-strategy.md`](../../../architecture/storage/artwork-background-strategy.md) |
| Audio cache / offline | [`docs/architecture/audio/audio-cache.md`](../../../architecture/audio/audio-cache.md) |
| Fade limitations | [`docs/architecture/audio/audio-engine-fade-limitations.md`](../../../architecture/audio/audio-engine-fade-limitations.md) |
| Auth | [`docs/standards/front-vibes-auth-core.md`](../../../standards/front-vibes-auth-core.md) |
| Mobile routing | [`docs/standards/front-vibes-ionic-routing.md`](../../../standards/front-vibes-ionic-routing.md) |
| Git Flow | [`docs/standards/git-flow.md`](../../../standards/git-flow.md) |
| **back_vibes** | `VibeController.php`, `StoreVibeRequest.php`, `VibePolicy.php`, `VibeSoundController.php` |
| **front_vibes** | `CreateVibePage.vue`, `vibe.service.ts`, `cover-bundle-apply.ts`, `offline-vibe-cache.service.ts` |
| **Tests** | `tests/Feature/PresetVibeImportApiTest.php` (preset path); manual create tests TBD |

When behaviour changes, update **`spec.md` first**, then this plan and [`tasks.md`](tasks.md).
