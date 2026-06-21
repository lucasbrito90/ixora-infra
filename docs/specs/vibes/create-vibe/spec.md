# Create Vibe — create user-owned ambient composition

**Status:** Active feature specification (source of truth)  
**Version:** 2.0 (consolidated; matches current `back_vibes` + `front_vibes` implementation)  
**Feature ID:** `vibes/create-vibe`  
**Platform:** Mobile-first (`front_vibes`); Laravel API contract shared with future clients

---

## Goal

Enable an **authenticated mobile user** to create a **personal ambient composition (`vibe`)**: enter metadata, optionally **apply a cover bundle** (copying visual CDN URL strings into the form), **save the vibe** via **`POST /api/vibes`**, and **attach existing catalog sounds** later through **`vibe_sounds`** nested routes — **without** creating catalog sounds, cover bundles, or sound layers in the same request.

**Success criteria:**

- **`POST /api/vibes`** inserts **one row** into **`vibes`** with **`user_id`** set server-side.
- Create **does not** insert **`vibe_sounds`**, **`sounds`**, or **`cover_bundles`**.
- Visual identity is stored as **copied HTTPS CDN URL strings** on the vibe row (no **`cover_bundle_id` FK**, no upload pipeline).
- Sound layers are managed in a **separate flow** ([`manage-vibe-sounds/spec.md`](../manage-vibe-sounds/spec.md)).
- Response is **`VibeResource`** with **`sounds_count: 0`** on create.
- Playback ([`playback-runtime/spec.md`](../playback-runtime/spec.md)) and offline download ([`offline-download/spec.md`](../offline-download/spec.md)) consume the vibe **after** layers exist — not at create time.

---

## Scope

### In scope

- **Manual mobile create:** **`CreateVibePage`** → **`POST /api/vibes`** JSON body.
- **Optional cover apply:** **`applyCoverBundleToFormFields`** before submit ([`apply-cover-bundle/spec.md`](../apply-cover-bundle/spec.md)).
- **Ownership:** **`user_id = auth()->id()`**; **`VibePolicy`** for view/update/delete.
- **List/show:** **`GET /api/vibes`**, **`GET /api/vibes/{id}`** scoped to owner.
- **Sound attach:** separate **`VibeSoundsPage`** + nested **`/api/vibes/{vibe}/sounds`** routes (not part of create submit).
- **Known gap:** **`StoreVibeRequest`** visual URL whitelist — documented under Validation Rules.

### Out of scope

- **Creating catalog sounds** ([`../../sounds/create-sound/spec.md`](../../sounds/create-sound/spec.md)).
- **Creating cover bundles** ([`../../covers/create-cover-bundle/spec.md`](../../covers/create-cover-bundle/spec.md)).
- **Preset import** ([`../../preset-vibes/import/spec.md`](../../preset-vibes/import/spec.md)) — server creates vibe + layers in one transaction; not manual create.
- **Embedded sound attach on create** — no atomic create+layers API today.
- **Multipart / upload pipeline** on vibe create — JSON only.
- **Direct Spaces access** from mobile — no credentials, no presigned uploads.
- **Image/audio processing, transcoding, AI generation**.
- **Collaborative, shared, or public vibes** — not implemented.
- **Admin end-user vibe create UI** — mobile-first today.
- **Offline snapshot on create** — offline is post-download only.

---

## Actors

| Actor | Role |
| --- | --- |
| **End user** | Firebase-authenticated mobile user; owns vibes via **`user_id`**. |
| **Mobile app (`front_vibes`)** | Create form, cover picker, JSON submit; attaches sounds in separate screen. |
| **Laravel API (`back_vibes`)** | Validates metadata, persists **`vibes`** row, enforces **`VibePolicy`**, returns **`VibeResource`**. |
| **Catalog sounds (`sounds`)** | Reusable audio — referenced by **`sound_id`** on nested attach; never created by vibe create. |
| **Cover bundles (`cover_bundles`)** | Read-only visual catalog — URLs copied into form; no FK on user vibes. |
| **DigitalOcean Spaces / CDN** | Stores catalog object bytes; **Laravel-only writes**. Vibe create stores **URL strings only**. |

---

## User Journey

### Primary path — manual create (mobile)

1. User signs in (Firebase → **`POST /api/auth/sync`** per [`front-vibes-auth-core.md`](../../../standards/front-vibes-auth-core.md)).
2. User opens **New Vibe** → **`/vibes/create`** (**`CreateVibePage`**).
3. User enters **name** (required), optional **description**, toggles **Active** (defaults **on** in UI).
4. User optionally taps **Choose cover** → **`CoverBundlePickerModal`** → **`GET /api/cover-bundles`** → selects bundle → **`applyCoverBundleToFormFields(form, bundle)`** copies non-empty bundle URLs into form (previews update locally).
5. User taps **Create Vibe**.
6. Mobile **`POST /api/vibes`** with **`application/json`**: `name`, `description`, `is_active`, and visual URL fields when set.
7. Laravel **`VibeController::store`**: **`authorize('create')`**, **`Vibe::create([...validated(), user_id])`**, returns **`VibeResource`** (**201**).
8. Mobile **`router.replace('/vibes')`** — does **not** open sound attach automatically.

### Separate path — attach sounds (required for playback)

9. User opens vibe from list → **Manage sounds** → **`/vibes/:id/sounds`** (**`VibeSoundsPage`**).
10. User selects catalog sounds → **Save Sounds** → **`POST` / `DELETE`** on **`/api/vibes/{id}/sounds`**.

Documented in [`manage-vibe-sounds/spec.md`](../manage-vibe-sounds/spec.md). **Create vibe and manage vibe sounds are separate flows.**

### Alternate path (boundary only)

**Preset import:** **`POST /api/preset-vibes/{id}/import`** creates a user vibe with server-copied bundle URLs and **`vibe_sounds`** in one transaction — not **`POST /api/vibes`**. See [`preset-vibes/import/spec.md`](../../preset-vibes/import/spec.md).

---

## Related Domain Model

```
┌─────────────────┐     apply (form only)      ┌─────────────────┐
│  cover_bundles  │ ── copy HTTPS strings ───► │     vibes       │
│ (visual catalog)│   (no FK on user vibe)     │ user-owned      │
└─────────────────┘                            │ composition     │
                                               └────────┬────────┘
┌─────────────────┐                                    │
│     sounds      │◄──── vibe_sounds (pivot) ──────────┘
│ (audio catalog) │      attached AFTER create
└─────────────────┘      via nested routes

preset_vibes ── import (separate) ──► new vibes row + vibe_sounds
              NOT manual POST /api/vibes
```

| Entity | Role in create |
| --- | --- |
| **`vibes`** | **Created** — metadata + optional visual URL columns; **`user_id`** from auth |
| **`vibe_sounds`** | **Not created** on **`POST /api/vibes`** |
| **`sounds`** | **Not created** — referenced only after attach |
| **`cover_bundles`** | **Not created** — read for picker; URLs copied as strings |
| **`preset_vibes`** | **Not involved** in manual create |

### Vibe row fields (manual create)

| Column | Set on create? |
| --- | --- |
| `user_id` | **Server-side only** — never from client body |
| `name`, `description`, `is_active` | From validated request (or DB default for `is_active` when omitted) |
| `thumbnail_url`, `artwork_url`, `player_background_url` | Intended from mobile when cover applied — **see validation gap** |
| `card_image_url` | **Not sent** by mobile create; **`VibeResource`** falls back to `thumbnail_url` |

**No `cover_bundle_id`** on user vibes. Copied URLs may reference the same CDN objects as a bundle until the user edits fields.

Imagery resolution after persist: [`artwork-background-strategy.md`](../../../architecture/storage/artwork-background-strategy.md).

---

## Functional Requirements

| ID | Requirement |
| --- | --- |
| FR-1 | Only **authenticated Firebase-synced users** may create (`firebase.auth` middleware). |
| FR-2 | Create accepts **`application/json`** only — **no** multipart upload flow. |
| FR-3 | **`POST /api/vibes`** inserts **only** into **`vibes`** table. |
| FR-4 | **`user_id`** is **`$request->user()->id`** — client cannot set owner. |
| FR-5 | **`name`** is **required**. |
| FR-6 | **`description`** is optional (nullable). |
| FR-7 | **`is_active`** optional in request; DB defaults **`true`** when omitted. |
| FR-8 | Create **does not** insert **`vibe_sounds`**, **`sounds`**, or **`cover_bundles`**. |
| FR-9 | Visual fields are **HTTPS CDN URL strings** when persisted — not uploads. |
| FR-10 | **`card_image_url`** not set by mobile create; API response uses **`thumbnail_url` fallback** via **`VibeResource`**. |
| FR-11 | Response **`VibeResource`** wrapper **`{ data: { … } }`**, HTTP **201**. |
| FR-12 | **`sounds_count`** is **0** on create (no layers; **`withCount` not loaded on store**). |
| FR-13 | **`sounds`** relationship **omitted** on create response unless explicitly loaded (not today). |
| FR-14 | **`GET /api/vibes`** returns **only** authenticated user’s rows (`where user_id = auth id`). |
| FR-15 | **`VibePolicy::create`** allows any authenticated user; **`view` / `update` / `delete`** require **`user_id` match**. |
| FR-16 | Cover apply uses **`applyCoverBundleToFormFields`** — non-empty bundle URLs only. |
| FR-17 | Mobile **does not** auto-navigate to sound attach after create. |
| FR-18 | **No Spaces credentials** on mobile; **no direct uploads**. |
| FR-19 | Playback requires separate layer attach + [`playback-runtime/spec.md`](../playback-runtime/spec.md). |
| FR-20 | Offline snapshot requires separate [`offline-download/spec.md`](../offline-download/spec.md) — **not** on create. |
| FR-21 | **No** public sharing, collaboration, or visibility fields on vibes. |

---

## Validation Rules

### Server — `StoreVibeRequest` (current shipped rules)

| Field | Rules |
| --- | --- |
| `name` | Required, string, max 255 |
| `description` | Nullable string |
| `is_active` | Optional boolean (`sometimes`) |

**Not in rules today (validation gap):**

| Field | Mobile sends on create? | Persisted today? |
| --- | --- | --- |
| `thumbnail_url` | Yes, when cover applied | **No** — omitted from **`validated()`** |
| `artwork_url` | Yes, when cover applied | **No** |
| `player_background_url` | Yes, when cover applied | **No** |
| `card_image_url` | No | N/A |

**Cause:** **`VibeController::store`** uses **`$request->validated()`** only. Fields not whitelisted in **`StoreVibeRequest`** are **silently dropped** even though **`Vibe` model is fillable**.

**Unaffected paths:** **Preset import** sets URLs in **`PresetVibeController::import`** directly — not via **`StoreVibeRequest`**.

**Intended fix (documented, not shipped):** Add nullable URL rules to **`StoreVibeRequest`** / **`UpdateVibeRequest`** per [`apply-cover-bundle/spec.md`](../apply-cover-bundle/spec.md) and [`artwork-background-strategy.md`](../../../architecture/storage/artwork-background-strategy.md).

### Mobile pre-submit (`CreateVibePage`)

| Rule | Detail |
| --- | --- |
| Name | Required non-empty trim; submit disabled when empty |
| Description | Optional; empty → **`null`** |
| Visual URLs | Sent when non-empty after cover apply |
| Cover apply | **`applyCoverBundleToFormFields`** — empty bundle fields do **not** clear form |
| Payload | **`JSON.stringify`** via **`vibeService.createVibe`** — not **`FormData`** |

### Authorization (`VibePolicy` + controller)

| Action | Rule |
| --- | --- |
| **`store`** | **`authorize('create', Vibe::class)`** — any authenticated user |
| **`index`** | **`authorize('viewAny')`** + query **`where user_id = auth id`** |
| **`show` / `update` / `delete`** | Owner only — **`user.id === vibe.user_id`** |
| **`user_id` in body** | Ignored / not accepted — server assigns |

---

## API Contract

### Create vibe

```
POST /api/vibes
```

**Middleware:** `firebase.auth` (no `admin.approved`)

**Content-Type:** `application/json`

**Request body**

| Field | Required | Notes |
| --- | --- | --- |
| `name` | Yes | |
| `description` | No | Nullable |
| `is_active` | No | Mobile sends boolean; DB default **`true`** if omitted |
| `thumbnail_url` | No | HTTPS CDN string when cover applied |
| `artwork_url` | No | HTTPS CDN string when cover applied |
| `player_background_url` | No | HTTPS CDN string when cover applied |

**Not accepted:** multipart files, `user_id`, `sound_id`, `cover_bundle_id`, embedded layers array.

**Success: 201 Created**

```json
{
  "data": {
    "id": 42,
    "name": "Sleep with Rain",
    "description": null,
    "thumbnail_url": null,
    "card_image_url": null,
    "player_background_url": null,
    "artwork_url": null,
    "is_active": true,
    "sounds_count": 0,
    "created_at": "2026-05-23T14:00:00.000000Z",
    "updated_at": "2026-05-23T14:00:00.000000Z"
  }
}
```

When visual URLs **are persisted** (after validation fix or preset import), **`VibeResource`** applies fallbacks:

| Response field | Resolution |
| --- | --- |
| `thumbnail_url` | Stored value (may be null) |
| `card_image_url` | **`card_image_url ?? thumbnail_url`** |
| `player_background_url` | **`player_background_url ?? thumbnail_url`** |
| `artwork_url` | **`artwork_url ?? thumbnail_url`** |
| `sounds_count` | **`(int) ($this->sounds_count ?? 0)`** — **0** on create |
| `sounds` | Only when **`sounds`** relationship loaded (preset import **201**; not manual create) |

**Error responses**

| HTTP | Condition |
| --- | --- |
| **401** | Missing/invalid Firebase token or Laravel user not synced |
| **422** | Validation failure (e.g. missing `name`) |
| **403** | Not used on create (`create` allowed for authenticated users) |
| **5xx** | Server error |

### Related endpoints (post-create — separate flows)

| Method | Path | Policy | Purpose |
| --- | --- | --- | --- |
| `GET` | `/api/vibes` | `firebase.auth`; owner scope | My vibes list |
| `GET` | `/api/vibes/{id}` | `view` (owner) | Vibe detail |
| `PATCH` | `/api/vibes/{id}` | `update` (owner) | Edit metadata / visuals |
| `DELETE` | `/api/vibes/{id}` | `delete` (owner) | Remove vibe |
| `GET` | `/api/vibes/{vibe}/sounds` | `view` | List layers — [`manage-vibe-sounds`](../manage-vibe-sounds/spec.md) |
| `POST` | `/api/vibes/{vibe}/sounds` | `update` | Attach catalog sound |
| `PATCH` | `/api/vibes/{vibe}/sounds/{sound}` | `update` | Update pivot |
| `DELETE` | `/api/vibes/{vibe}/sounds/{sound}` | `update` | Detach sound |
| `GET` | `/api/cover-bundles` | `firebase.auth` | Cover picker |
| `GET` | `/api/sounds` | `firebase.auth` | Catalog for layer picker |

**Not manual create:** `POST /api/preset-vibes/{id}/import`, admin catalog writes, `POST /api/admin/uploads`.

---

## Cover Bundle Behaviour

Cover bundles are **optional visual helpers** — not linked by FK on user vibes.

| Topic | Behaviour |
| --- | --- |
| Catalog read | **`GET /api/cover-bundles`** — active bundles for authenticated users |
| Apply UX | **`CoverBundlePickerModal`** on **`CreateVibePage`** |
| Merge helper | **`applyCoverBundleToFormFields(form, bundle)`** in **`cover-bundle-apply.ts`** |
| Overwrite rule | For each of `thumbnail_url`, `artwork_url`, `player_background_url`: bundle value **non-empty after trim** → overwrite form field; **empty bundle field leaves form unchanged** |
| Submit | Mobile sends three URL keys in **`VibePayload`** JSON |
| Persistence | Copied **HTTPS strings** on **`vibes`** columns — **no `cover_bundle_id`** |
| Catalog mutation | **None** — apply does not PATCH bundle row |
| Upload | **None** on create — references existing CDN objects only |

Full apply semantics: [`apply-cover-bundle/spec.md`](../apply-cover-bundle/spec.md).

**Safe delete:** Deleting a cover bundle is blocked (**409**) when vibe URL columns still reference bundle CDN URLs ([`storage-strategy.md`](../../../architecture/storage/storage-strategy.md)).

---

## Sound Layer Behaviour

Sound layers are **not part of vibe create**.

| Topic | Behaviour |
| --- | --- |
| **`POST /api/vibes`** | Inserts **`vibes` only** — **zero** **`vibe_sounds`** rows |
| After create | User opens **`VibeSoundsPage`** → attach/detach via nested routes |
| Attach | **`POST /api/vibes/{vibe}/sounds`** with existing **`sound_id`** |
| Catalog | Create **never** inserts **`sounds`** rows |
| **`sounds_count`** | **0** until layers attached; list/show use **`withCount('sounds')`** |
| Playback URL | Layers use catalog **`file_url`** (HTTPS CDN) via **`VibeSoundResource`** |
| Execution plan | **`buildVibeExecutionPlan(vibeSounds)`** after **`GET …/sounds`** — [`playback-runtime/spec.md`](../playback-runtime/spec.md) |
| Empty vibe | Create succeeds with **no layers** — player has nothing playable until attach |

Full layer management: [`manage-vibe-sounds/spec.md`](../manage-vibe-sounds/spec.md).

### Relationship with playback-runtime

Create produces a **vibe shell**. Playback requires:

1. Attached **`vibe_sounds`** (separate flow).
2. **`GET /api/vibes/{id}/sounds`** (or offline snapshot).
3. **`buildVibeExecutionPlan`** → **`audioPlayerService.playPlan`**.

Create does **not** invoke **`AudioEngine`** or preload audio.

### Relationship with offline-download

| Topic | Behaviour |
| --- | --- |
| On create | **No** **`offline_vibe_manifest_v1`** or audio byte manifest write |
| Offline playback | Requires later **Download for offline** on **`VibePlayerPage`** with layers present |
| Snapshot | Stores **`OfflineVibeMeta`** + **`vibeSounds[]`** — only after successful download |
| Create + offline | User must create vibe → attach sounds → play online → download |

See [`offline-download/spec.md`](../offline-download/spec.md).

### Relationship with preset import

| | **Manual create (`POST /api/vibes`)** | **Preset import** |
| --- | --- | --- |
| Entry | **`CreateVibePage`** | **`PresetVibeDetailPage`** |
| Layers on create | **No** | **Yes** — server attaches **`preset_vibe_sounds`** |
| Visual URLs | Form apply (client) | Server copies from preset **`coverBundle`** |
| Response | **`sounds_count: 0`** | **`sounds_count > 0`**, optional embedded **`sounds`** |

See [`preset-vibes/import/spec.md`](../../preset-vibes/import/spec.md).

---

## Mobile UX Rules

| Rule | Detail |
| --- | --- |
| Screen | **`CreateVibePage.vue`** at **`/vibes/create`** |
| Required input | **Name** — submit disabled when empty or loading |
| Active toggle | Defaults **`true`** in form |
| Cover block | **Choose cover** → modal → live previews via **`vibePreviewFromImageFields`** + **`artwork.ts`** |
| Submit | **`useVibes().createVibe`** → **`POST /api/vibes`** JSON |
| Success | **`router.replace('/vibes')`** — list refresh on enter |
| Sound attach | **Not** on create submit — separate navigation from vibe list/card |
| Imagery | Use **`getVibeCardBackgroundStyle`**, **`getVibeArtworkUrl`**, **`getVibePlayerBackgroundStyle`** — do not duplicate fallback chains in pages |
| Auth | Firebase Bearer on every request — [`front-vibes-auth-core.md`](../../../standards/front-vibes-auth-core.md) |
| Routing | [`front-vibes-ionic-routing.md`](../../../standards/front-vibes-ionic-routing.md) |
| Secrets | **`VITE_API_BASE_URL`** + Firebase client config only — **no `DO_SPACES_*`** |

---

## Storage / CDN Rules

| Rule | Detail |
| --- | --- |
| Vibe create writer | **Laravel** persists URL **strings** on **`vibes`** — **no binary upload** |
| Mobile create | **JSON only** — **no** multipart, **no** direct Spaces access |
| Catalog bytes | Written only by **Laravel admin catalog flows** ([`upload-validation.md`](../../../standards/upload-validation.md)) |
| Visual URLs | **Public HTTPS CDN** strings (typically **`DO_SPACES_CDN_URL`** objects from cover bundles) |
| Copied URLs | Same CDN object as source bundle until user edits vibe fields — shared reference semantics |
| **`cover_bundle_id`** | **Not stored** on user vibes |
| Safe delete | Bundle delete blocked when vibe columns reference bundle URLs |
| Transcoding | **None** |
| Offline | Create does **not** download bytes — see offline spec |

Align with [`storage-strategy.md`](../../../architecture/storage/storage-strategy.md) and [`mobile-cdn-validation.md`](../../../architecture/storage/mobile-cdn-validation.md).

---

## Failure Cases

| Case | Expected behaviour |
| --- | --- |
| Missing `name` | **422**; mobile blocks submit when name empty |
| Invalid / missing Firebase token | **401** |
| User not synced to Laravel | **401** `User not found.` |
| Visual URLs sent but not in **`StoreVibeRequest`** | URLs **not persisted** — previews may show form state until refetch; **known gap** |
| Create without sounds | **201** success — **`sounds_count: 0`**; playback unavailable until attach |
| Attach invalid `sound_id` | **422** on nested POST (separate flow) |
| Access another user’s vibe | **403** on `view` / `update` / `delete` |
| Network / CORS error on create | Mobile surfaces error from **`useVibes`** |
| Offline create attempt | **Fails** — create requires live API; no offline create path |
| Broken CDN URL on vibe (if persisted) | Broken previews — not an upload failure on create |

---

## Security Rules

| Rule | Requirement |
| --- | --- |
| Identity | Firebase Bearer — [`front-vibes-auth-core.md`](../../../standards/front-vibes-auth-core.md) |
| Middleware | **`firebase.auth`** on **`POST /api/vibes`** |
| Ownership | **`user_id`** assigned server-side — never trust client owner field |
| **`VibePolicy`** | **`create`**: any auth user; **`view`/`update`/`delete`**: owner match |
| List isolation | Controller **`where user_id = auth id`** — users cannot list others’ vibes |
| Catalog writes | Create cannot create **`sounds`** or **`cover_bundles`** |
| Layer attach | Requires **`update`** on vibe — owner only (separate flow) |
| CDN URLs | Public HTTPS references — no Spaces secrets on mobile |
| Sharing | **No** public or cross-user vibe access today |

---

## Future Considerations

| Topic | Notes |
| --- | --- |
| **`StoreVibeRequest` / `UpdateVibeRequest` URL whitelist** | **Required** for cover URLs to persist on manual create/edit |
| Atomic create + initial layers | Optional single API — **not shipped** |
| Admin vibe tooling | Future **`ixora-admin`** — separate spec |
| Public / shared vibes | **Not implemented** |
| Vibe-specific image upload | Would need upload ADR — **not current** |
| AI vibe generation | **Not implemented** |

**Explicitly excluded:** collaborative vibes, embedded sound attach on create, client-to-Spaces uploads, transcoding, public sharing, offline create.

---

## Related Docs

| Document | Path |
| --- | --- |
| **This spec** | `docs/specs/vibes/create-vibe/spec.md` |
| Manage vibe sounds | [`../manage-vibe-sounds/spec.md`](../manage-vibe-sounds/spec.md) |
| Playback runtime | [`../playback-runtime/spec.md`](../playback-runtime/spec.md) |
| Apply cover bundle | [`../apply-cover-bundle/spec.md`](../apply-cover-bundle/spec.md) |
| Preset import | [`../../preset-vibes/import/spec.md`](../../preset-vibes/import/spec.md) |
| Offline download | [`../offline-download/spec.md`](../offline-download/spec.md) |
| Storage policy | [`docs/architecture/storage/storage-strategy.md`](../../../architecture/storage/storage-strategy.md) |
| Artwork / background | [`docs/architecture/storage/artwork-background-strategy.md`](../../../architecture/storage/artwork-background-strategy.md) |
| Mobile CDN QA | [`docs/architecture/storage/mobile-cdn-validation.md`](../../../architecture/storage/mobile-cdn-validation.md) |
| Upload validation (admin catalog) | [`docs/standards/upload-validation.md`](../../../standards/upload-validation.md) |
| Auth | [`docs/standards/front-vibes-auth-core.md`](../../../standards/front-vibes-auth-core.md) |
| **Plan / tasks** | [`plan.md`](plan.md), [`tasks.md`](tasks.md) |
| **back_vibes** | `VibeController.php`, `StoreVibeRequest.php`, `UpdateVibeRequest.php`, `VibeResource.php`, `VibePolicy.php`, `Vibe.php` |
| **front_vibes** | `CreateVibePage.vue`, `vibe.service.ts`, `cover-bundle-apply.ts`, `CoverBundlePickerModal.vue`, `VibeSoundsPage.vue` |

When behaviour changes, update **this file first**, then align API validation, mobile payloads, and tests.
