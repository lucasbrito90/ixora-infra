# Update Vibe — edit user-owned ambient composition

**Status:** Active feature specification (source of truth)  
**Version:** 2.0 (consolidated; matches current `back_vibes` + `front_vibes` implementation)  
**Feature ID:** `vibes/update-vibe`  
**Platform:** Mobile-first (`front_vibes`); Laravel API contract shared with future clients

---

## Goal

Enable an **authenticated mobile user** who **owns** a vibe to **edit** metadata and optional **visual CDN URL strings** on an existing personal composition: load current state, optionally **re-apply a cover bundle** to local form state, **save** via **`PATCH /api/vibes/{id}`**, and keep **sound layers** on **separate nested routes** — without creating catalog assets, uploading files, or mutating **`vibe_sounds`** through the vibe update endpoint.

**Success criteria:**

- **`PATCH /api/vibes/{id}`** updates **one owned `vibes` row** — owner-only via **`VibePolicy::update`**.
- Update **does not** modify **`vibe_sounds`**, **`sounds`**, **`cover_bundles`**, or **`user_id`**.
- Visual changes are **copied HTTPS URL strings** only — **no** multipart upload, **no** **`cover_bundle_id` FK**.
- **`applyCoverBundleToFormFields`** is **client-only** until save; persistence goes through PATCH.
- Response is **`VibeResource`** (**200**) with server-side visual fallbacks unchanged.
- **Known gap:** **`UpdateVibeRequest`** does not whitelist visual URL fields today — URLs may be **silently dropped** by **`validated()`** (documented below).
- Playback and offline are **downstream consumers** — not updated by vibe PATCH alone.

---

## Scope

### In scope

- **Update flow:** **`EditVibePage`** → **`GET /api/vibes/{id}`** → **`PATCH /api/vibes/{id}`** JSON.
- **Cover apply on edit:** same client merge as create ([`apply-cover-bundle/spec.md`](../apply-cover-bundle/spec.md)).
- **Authorization:** **`VibePolicy::view`** (preload), **`update`** (PATCH).
- **Partial update semantics:** Laravel **`sometimes`** rules; mobile sends full form payload on save.
- **Local form state + previews** before save (`vibe-form-preview.ts`, `artwork.ts`).
- **Success navigation:** **`router.replace('/vibes')`**.
- **Validation gap** for visual URL persistence.

### Out of scope

- **Create vibe** ([`create-vibe/spec.md`](../create-vibe/spec.md)).
- **Delete vibe** (`DELETE /api/vibes/{id}`).
- **Sound layer CRUD** — [`manage-vibe-sounds/spec.md`](../manage-vibe-sounds/spec.md) only.
- **Creating catalog sounds or cover bundles**.
- **Preset import / preset admin** — separate domains.
- **Multipart / upload pipeline** on vibe update — JSON only.
- **Direct Spaces access** from mobile.
- **Transcoding, AI generation, image editing**.
- **Collaborative, shared, or public vibe** editing — not implemented.
- **Automatic offline snapshot refresh** on save ([`offline-download/spec.md`](../offline-download/spec.md)).
- **Admin end-user vibe edit UI** — mobile-first today.
- **Optimistic sync, websockets, realtime reconciliation** — not shipped.

---

## Actors

| Actor | Role |
| --- | --- |
| **End user (owner)** | Edits own vibe metadata and visual URL fields; manages layers elsewhere. |
| **Mobile app (`front_vibes`)** | Loads vibe, applies cover to form, **`PATCH`** JSON; previews from local form state. |
| **Laravel API (`back_vibes`)** | **`authorize('update', $vibe)`**, **`UpdateVibeRequest`**, **`$vibe->update($request->validated())`**, **`VibeResource`**. |
| **Cover bundles (`cover_bundles`)** | Read-only picker input — not mutated by update. |
| **Catalog sounds (`sounds`)** | Unchanged by vibe PATCH — layers via nested routes. |

---

## User Journey

1. User signs in (Firebase → **`POST /api/auth/sync`** per [`front-vibes-auth-core.md`](../../../standards/front-vibes-auth-core.md)).
2. User opens **Edit Vibe** from My Vibes → **`/vibes/:id/edit`** (**`EditVibePage`**).
3. **`onMounted`:** **`fetchVibe(id)`** → **`GET /api/vibes/{id}`**; on error → **`router.back()`**.
4. **`watch(selectedVibe)`** hydrates reactive **form**: `name`, `description`, `is_active`, `thumbnail_url`, `artwork_url`, `player_background_url`.
5. User edits metadata; optionally **Choose cover** → **`applyCoverBundleToFormFields(form, bundle)`** — previews update from **local form** (no API on Apply).
6. User taps **Save Changes**.
7. Mobile **`PATCH /api/vibes/{id}`** with trimmed JSON (metadata + three visual URL keys).
8. Laravel **`VibeController::update`:** **`authorize('update', $vibe)`** → **`$vibe->update($request->validated())`** → **`VibeResource`** (**200**).
9. Mobile **`router.replace('/vibes')`** on success.

**Not in journey:** attach/detach sounds (**`/vibes/:id/sounds`**), offline re-download, admin catalog writes.

**Sound layers:** **Manage sounds** → **`POST` / `PATCH` / `DELETE`** on **`/api/vibes/{vibe}/sounds`** — separate flow.

---

## Related Domain Model

```
cover_bundles ── apply (form only) ──► EditVibePage form state
                                           │
                                           │ PATCH (validated keys only)
                                           ▼
                                      vibes (user-owned row)
                                           │
sounds ◄──── vibe_sounds ──────────────────┘
              NOT updated by PATCH /api/vibes/{id}
```

| Action | Modifies | Does not modify |
| --- | --- | --- |
| **`PATCH /api/vibes/{id}`** | **`vibes`**: `name`, `description`, `is_active`, visual URL columns *(when whitelisted)* | **`user_id`**, **`vibe_sounds`**, **`sounds`**, **`cover_bundles`** |
| **Apply cover (form)** | Local form strings + previews | DB until save |
| **Layer APIs** | **`vibe_sounds`** pivot | **`vibes`** metadata *(unless user also PATCHes vibe)* |

**No `cover_bundle_id`** on user vibes. Saved vibe **owns copied URL strings** until edited again. Catalog bundle changes do **not** auto-update saved vibes.

**Model vs validation:** **`Vibe`** is **`fillable`** for visual URL columns, but **`UpdateVibeRequest::validated()`** is the **authoritative trust boundary** — see [`laravel-form-request-patterns.md`](../../../standards/laravel-form-request-patterns.md).

---

## Functional Requirements

| ID | Requirement |
| --- | --- |
| FR-1 | Only **authenticated Firebase-synced users** may update (`firebase.auth`). |
| FR-2 | **`VibePolicy::update`** requires **`$user->id === $vibe->user_id`** — else **403**. |
| FR-3 | **`PATCH /api/vibes/{id}`** accepts **`application/json`** only — **no** multipart. |
| FR-4 | Update modifies **existing** vibe row — never creates. |
| FR-5 | **`user_id`** is **not** accepted or mutable from client body — set only at create. |
| FR-6 | **`UpdateVibeRequest`** uses **`sometimes`** for partial semantics on whitelisted fields. |
| FR-7 | Controller persists **`$request->validated()`** only — [`VibeController::update`](../../../standards/laravel-form-request-patterns.md). |
| FR-8 | Update **does not** insert/update **`sounds`**, **`cover_bundles`**, or **`preset_vibes`**. |
| FR-9 | Update **does not** insert/update/delete **`vibe_sounds`**. |
| FR-10 | Visual fields are **HTTPS CDN URL strings** when persisted — **not** uploads. |
| FR-11 | **`applyCoverBundleToFormFields`** on edit — non-empty overwrite, empty preserve (separate from PATCH). |
| FR-12 | Response **`VibeResource`** **`{ data: … }`**, HTTP **200** — see [`api-resource-patterns.md`](../../../standards/api-resource-patterns.md). |
| FR-13 | **`GET /api/vibes/{id}`** before edit requires **`view`** (owner). |
| FR-14 | **`sounds`** relationship **not** embedded on update response unless loaded (not today). |
| FR-15 | **`sounds_count`** from **`loadCount`** on show when applicable — unchanged by metadata-only PATCH. |
| FR-16 | **No** public/share/collaboration fields. |
| FR-17 | **Offline manifests** not refreshed by vibe edit alone. |
| FR-18 | **No** automatic sound attach on edit. |

---

## Validation Rules

### Server — `UpdateVibeRequest` (shipped rules)

| Field | Rules |
| --- | --- |
| `name` | **`sometimes`**, string, max 255 |
| `description` | **nullable** string *(always validated when key present)* |
| `is_active` | **`sometimes`**, boolean |

**FormRequest `authorize()`:** returns **`true`** — ownership enforced in controller via **`$this->authorize('update', $vibe)`**.

### Visual URL fields — **current gap**

Mobile **`EditVibePage`** sends on every save:

| Field | In PATCH body? | In **`UpdateVibeRequest`**? | Persisted? |
| --- | --- | --- | --- |
| `thumbnail_url` | Yes | **No** | **No** — dropped by **`validated()`** |
| `artwork_url` | Yes | **No** | **No** |
| `player_background_url` | Yes | **No** | **No** |

**Intended fix** (not shipped): whitelist nullable URL strings — mirror **`UpdateCoverBundleRequest`**:

```php
'thumbnail_url'         => ['sometimes', 'nullable', 'url', 'max:2048'],
'artwork_url'           => ['sometimes', 'nullable', 'url', 'max:2048'],
'player_background_url' => ['sometimes', 'nullable', 'url', 'max:2048'],
```

Same gap as **`StoreVibeRequest`** on create ([`create-vibe/spec.md`](../create-vibe/spec.md)).

### PATCH partial-update semantics

| Client behaviour | Server behaviour |
| --- | --- |
| Mobile sends **all** form fields on save | Each whitelisted key in body is validated |
| Keys **not** in **`validated()`** | **Ignored** — column unchanged |
| **`sometimes`** on `name`, `is_active` | Field validated only if present |
| **`description` nullable** | Explicit **`null`** clears description |

True partial PATCH (single-field body) is **supported by rules**; mobile UI sends full payload today.

### Mobile pre-submit (`EditVibePage`)

| Rule | Detail |
| --- | --- |
| Preload | **`GET /api/vibes/{id}`** → **`watch(selectedVibe)`** fills form |
| Hydration source | API **`VibeResource`** fields (includes **response-time fallbacks** on `artwork_url`, etc.) |
| Name | Required non-empty trim; submit disabled when empty |
| Description | Empty → **`null`** on submit |
| Visual URLs | Trimmed; empty string → **`null`** |
| Cover apply | **`applyCoverBundleToFormFields`** — does not call API |
| Previews | **`vibePreviewFromImageFields`** + **`artwork.ts`** — **display only**, not persistence |

**Important:** Previews reflect **form state**. After apply-cover, previews may show new URLs **before** save. If visual URLs are dropped by **`validated()`**, **refetch/list** shows **previous DB URLs** (metadata may still update).

---

## API Contract

### Show vibe (edit preload)

```
GET /api/vibes/{id}
```

**Middleware:** `firebase.auth`  
**Policy:** **`view`** (owner)

**Success: 200 OK** — **`VibeResource`**

| Field | Notes |
| --- | --- |
| `thumbnail_url` | Stored value (may be null) |
| `card_image_url` | **`card_image_url ?? thumbnail_url`** (server fallback) |
| `player_background_url` | **`player_background_url ?? thumbnail_url`** |
| `artwork_url` | **`artwork_url ?? thumbnail_url`** |
| `sounds_count` | From **`loadCount('sounds')`** on show |
| `sounds` | Omitted unless relationship loaded |

Form hydration uses **`thumbnail_url`**, **`artwork_url`**, **`player_background_url`** from response — which may already include **read-time fallbacks** from **`VibeResource`**.

### Update vibe

```
PATCH /api/vibes/{id}
```

**Middleware:** `firebase.auth`  
**Policy:** **`update`** (owner)

**Content-Type:** `application/json`

**Request body (mobile sends today)**

| Field | Sent | Persisted (shipped) |
| --- | --- | --- |
| `name` | Yes | **Yes** |
| `description` | Yes | **Yes** |
| `is_active` | Yes | **Yes** |
| `thumbnail_url` | Yes | **No** (gap) |
| `artwork_url` | Yes | **No** (gap) |
| `player_background_url` | Yes | **No** (gap) |

**Not accepted:** `user_id`, `sound_id`, `sounds[]`, `cover_bundle_id`, multipart files.

**Success: 200 OK**

```json
{
  "data": {
    "id": 42,
    "name": "Sleep with Rain (edited)",
    "description": "Updated copy",
    "thumbnail_url": "https://{cdn}/…",
    "card_image_url": "https://{cdn}/…",
    "player_background_url": "https://{cdn}/…",
    "artwork_url": "https://{cdn}/…",
    "is_active": true,
    "sounds_count": 3,
    "created_at": "…",
    "updated_at": "…"
  }
}
```

**`VibeResource` fallbacks** apply on **response** regardless of which columns PATCH updated.

**Error responses**

| HTTP | Condition |
| --- | --- |
| **401** | Missing/invalid Firebase token or user not synced |
| **403** | Not owner |
| **404** | Vibe not found |
| **422** | Validation failure — `{ "message", "errors" }` |
| **5xx** | Server error |

**Must not extend** `PATCH /api/vibes/{id}` with embedded **`sounds[]`** without a new spec revision.

---

## Cover Bundle Behaviour

Cover apply on edit is **client form merge** — same as create. Full semantics: [`apply-cover-bundle/spec.md`](../apply-cover-bundle/spec.md).

| Topic | Edit behaviour |
| --- | --- |
| Trigger | **Choose cover** on **`EditVibePage`** |
| Merge | **`applyCoverBundleToFormFields(form, bundle)`** |
| Overwrite | Non-empty bundle URL after **`trim()`** |
| Preserve | Empty bundle slot → unchanged form value |
| Persist | **`PATCH`** with three URL keys — **blocked by validation gap today** |
| Catalog | **No** mutation of **`cover_bundles`** |
| FK | **No `cover_bundle_id`** on user vibe |

### Relationship with apply-cover-bundle

| Phase | Owner |
| --- | --- |
| Apply tap | **apply-cover-bundle** spec — form + previews only |
| Save tap | **This spec** — PATCH persistence |
| Gap | Apply may **appear** to work until list/player **refetch** reveals URLs not saved |

---

## Sound Layer Behaviour

**Update vibe does not change sound layers.**

| Concern | Endpoint |
| --- | --- |
| List layers | **`GET /api/vibes/{vibe}/sounds`** |
| Attach | **`POST /api/vibes/{vibe}/sounds`** |
| Update pivot | **`PATCH /api/vibes/{vibe}/sounds/{sound}`** |
| Detach | **`DELETE /api/vibes/{vibe}/sounds/{sound}`** |
| Bulk UI | **`VibeSoundsPage`** |

All require **`authorize('update', $vibe)`** (or **`view`** for GET). Playback **`file_url`** comes from catalog via pivot — not from vibe PATCH.

### Relationship with manage-vibe-sounds

- **Edit vibe** and **manage vibe sounds** are **separate flows**.
- Changing vibe **name** or visuals does **not** alter **`vibe_sounds`**.
- Layer volume/mode/timing changes do **not** require vibe PATCH.
- Documented in [`manage-vibe-sounds/spec.md`](../manage-vibe-sounds/spec.md).

### Relationship with playback-runtime

- Playback uses **`GET …/sounds`** (or offline snapshot) → **`buildVibeExecutionPlan`**.
- Vibe PATCH updates **session metadata / hero URLs** for player UI when refetched — **not** layer config.
- **`VibeResource` fallbacks** on response shape list/player imagery after reload.
- Fade pivot fields **ignored at runtime** — [`audio-engine-fade-limitations.md`](../../../architecture/audio/audio-engine-fade-limitations.md).
- See [`playback-runtime/spec.md`](../playback-runtime/spec.md).

### Relationship with offline-download

| Topic | Behaviour after vibe edit |
| --- | --- |
| **`offline_vibe_manifest_v1`** | **Not** auto-updated — stale vibe meta until **Download for offline** succeeds |
| **`ixora_offline_audio_manifest_v1`** | **Not** updated — audio bytes unchanged if layers unchanged |
| URL / layer changes elsewhere | Offline playback may use **stale snapshot** or **URL mismatch** until re-download |
| Visual URL gap | If URLs not persisted, offline snapshot meta may **match old DB** anyway |

See [`offline-download/spec.md`](../offline-download/spec.md). **No optimistic sync** on edit.

---

## Mobile UX Rules

| Rule | Detail |
| --- | --- |
| Screen | **`EditVibePage.vue`** at **`/vibes/:id/edit`** |
| Preload error | **`router.back()`** when **`fetchVibe`** fails |
| Form | Reactive local state — unsaved until **Save Changes** |
| Cover block | Same preview row as create (card · artwork · player strip) |
| Previews | **`vibePreviewFromImageFields`** → **`getVibeCardBackgroundStyle`**, **`getVibeArtworkUrl`**, **`getVibePlayerBackgroundStyle`** |
| Gradients | **`artwork.ts`** fallbacks when URL missing in **form** — client display only |
| Submit | **`updateVibe(id, payload)`** → **`vibeService.updateVibe`** → **`PATCH`** |
| Success | **`router.replace('/vibes')`** — does not stay on edit screen |
| Layers | **Not** on this screen — separate **Manage sounds** route |
| Auth | Firebase Bearer — [`front-vibes-auth-core.md`](../../../standards/front-vibes-auth-core.md) |
| Secrets | **`VITE_API_BASE_URL`** + Firebase only — **no `DO_SPACES_*`** |

**`artwork.ts` fallback chains** (e.g. `artwork_url` → `thumbnail_url` → gradient) apply to **pre-save previews** and **post-save UI** that reads API JSON — they do **not** write to the database.

---

## Storage / CDN Rules

| Rule | Detail |
| --- | --- |
| Update writer | Laravel persists **URL strings** on **`vibes`** when whitelisted — **no new Spaces objects** |
| JSON only | **No** multipart, **no** upload pipeline on PATCH |
| Mobile | **Opaque HTTPS URLs** from API — no direct Spaces access |
| Copied URLs | May reference same CDN objects as cover bundle until user changes fields |
| Safe delete | Bundle **DELETE** **409** when vibe columns still match bundle URLs |
| Offline audio | Manifest uses exact **`layer.fileUrl`** — edit does not refresh files |
| Offline snapshot | Stale until explicit re-download |

Align with [`storage-strategy.md`](../../../architecture/storage/storage-strategy.md) and [`upload-validation.md`](../../../standards/upload-validation.md) (catalog upload ≠ vibe update).

---

## Failure Cases

| Case | Expected behaviour |
| --- | --- |
| Non-owner **`PATCH`** / **`GET`** | **403** |
| Invalid Firebase token | **401** |
| Vibe not found | **404** |
| Visual URLs in body, not in **`UpdateVibeRequest`** | URLs **not persisted** — **known gap**; metadata may save |
| Apply cover, save, refetch list | Previews during edit looked correct; **list may show old visuals** until gap fixed |
| Apply cover, navigate away without save | Form changes **discarded** |
| Empty name | Submit **disabled** in UI |
| **`422`** after URL whitelist added | Invalid URL shape rejected |
| Network error on PATCH | **`error`** in composable; user stays on edit if update returns null |
| Layer changed on server; user only edited name | Offline snapshot **stale** until re-download |
| **`file_url`** changed; old offline manifest | **`remoteUrl !== layer.fileUrl`** → HTTPS fallback until re-download |

---

## Security Rules

| Rule | Requirement |
| --- | --- |
| Identity | Firebase Bearer on **`GET`** and **`PATCH`** |
| Ownership | **`VibePolicy::update`** — **`user.id === vibe.user_id`** |
| **`user_id`** | **Never** from client body; immutable on update |
| Trust boundary | **`validated()`** only — [`laravel-form-request-patterns.md`](../../../standards/laravel-form-request-patterns.md) |
| Catalog writes | PATCH cannot create **`sounds`** or **`cover_bundles`** |
| No cross-user edit | List scoped by owner; policy on show/update |
| URLs | When whitelisted, validate URL shape — no Spaces credentials on mobile |
| No sharing | No public or collaborative edit endpoints |

---

## Future Considerations

| Topic | Notes |
| --- | --- |
| **`UpdateVibeRequest` URL whitelist** | **Required** for visual persistence — same as **`StoreVibeRequest`** |
| Auto-refresh offline snapshot on save | **Not implemented** |
| **`card_image_url` on edit form** | Not sent today; **`VibeResource`** fallback handles list/player |
| Admin user-vibe edit | Future **`ixora-admin`** — separate spec |
| Vibe-scoped image upload | Would need upload ADR — **not current** |
| True partial PATCH from mobile | Could send only changed keys — rules already support **`sometimes`** |

**Explicitly excluded:** uploads, websocket sync, cover bundle FK linking, AI generation, public sharing, embedding **`sounds[]`** in vibe PATCH.

---

## Related Docs

| Document | Path |
| --- | --- |
| **This spec** | `docs/specs/vibes/update-vibe/spec.md` |
| Create vibe | [`../create-vibe/spec.md`](../create-vibe/spec.md) |
| Apply cover bundle | [`../apply-cover-bundle/spec.md`](../apply-cover-bundle/spec.md) |
| Manage vibe sounds | [`../manage-vibe-sounds/spec.md`](../manage-vibe-sounds/spec.md) |
| Playback runtime | [`../playback-runtime/spec.md`](../playback-runtime/spec.md) |
| Offline download | [`../offline-download/spec.md`](../offline-download/spec.md) |
| API Resource patterns | [`docs/standards/api-resource-patterns.md`](../../../standards/api-resource-patterns.md) |
| Form Request patterns | [`docs/standards/laravel-form-request-patterns.md`](../../../standards/laravel-form-request-patterns.md) |
| Artwork / background | [`docs/architecture/storage/artwork-background-strategy.md`](../../../architecture/storage/artwork-background-strategy.md) |
| Storage policy | [`docs/architecture/storage/storage-strategy.md`](../../../architecture/storage/storage-strategy.md) |
| Auth | [`docs/standards/front-vibes-auth-core.md`](../../../standards/front-vibes-auth-core.md) |
| Routing | [`docs/standards/front-vibes-ionic-routing.md`](../../../standards/front-vibes-ionic-routing.md) |
| **back_vibes** | `VibeController.php`, `UpdateVibeRequest.php`, `VibePolicy.php`, `VibeResource.php`, `Vibe.php` |
| **front_vibes** | `EditVibePage.vue`, `vibe.service.ts`, `cover-bundle-apply.ts`, `artwork.ts`, `vibe-form-preview.ts` |

When behaviour changes, update **this file first**, then Laravel validation, mobile payloads, and related specs.
