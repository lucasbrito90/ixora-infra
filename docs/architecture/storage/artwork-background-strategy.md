# Artwork and background strategy — mobile presentation

**Status:** Active architecture (source of truth)  
**Scope:** How the **mobile app** chooses vibe imagery from API URL fields; cover-bundle apply semantics; Laravel validation contract  
**Applies to:** `front_vibes` (primary consumer), `back_vibes` (vibe persistence rules)

---

## Purpose

Define **how vibe images are resolved and displayed** on cards, the full-screen player, and MiniPlayer/MediaSession artwork—using **only HTTPS URL strings from the API**, centralized front-end helpers, and stable gradient fallbacks—without changing **API field ownership**, introducing **direct Spaces access**, or coupling the app to a specific CDN host.

This document states **presentation architecture and contracts**. Implementation lives in **`front_vibes/src/utils/artwork.ts`**.

---

## Context

Vibes expose several **nullable URL columns** for different visual contexts. **Cover bundles** are catalog visual packages (`thumbnail_url`, `artwork_url`, `player_background_url`). **Sounds** remain **audio-only** (no cover artwork fields on the sound model for this strategy).

The mobile app runs in a Capacitor WebView and renders images via **`<img :src>`** and **CSS `background-image: url(...)`**. URLs are **opaque HTTPS strings** returned by Laravel—typically **DigitalOcean Spaces CDN** for new assets, with **legacy Firebase Storage URLs** still valid until migration completes.

There is **no host whitelist** in the app: any TLS origin the API returns should work the same way.

The API may already **resolve or collapse** some fallbacks server-side (e.g. `card_image_url ?? thumbnail_url`). The front-end **still applies the same priority chain** so offline snapshots, cached vibes, and future API changes stay consistent.

---

## Current Decision

1. **Mobile only consumes image URLs from the API** — no direct bucket/CDN credentials or Spaces SDK on device.
2. **Image URLs are opaque HTTPS strings**; the app does not parse bucket keys or enforce CDN host allowlists.
3. **Spaces CDN URLs and legacy Firebase URLs** must both work when present on vibe/cover rows.
4. **Cover bundles** supply `thumbnail_url`, `artwork_url`, and `player_background_url`; **sounds stay audio-only**.
5. **Applying a cover bundle to a vibe** copies each bundle URL into the vibe form **only when that bundle URL is non-empty**; empty bundle fields leave the vibe’s current value unchanged (`applyCoverBundleToFormFields`).
6. **Laravel must whitelist** `thumbnail_url`, `artwork_url`, and `player_background_url` on **`StoreVibeRequest`** and **`UpdateVibeRequest`** (nullable strings, e.g. `max:2048`) so `validated()` passes them into `Vibe::create` / `update`. Fields omitted from validation rules are **silently dropped** even if the app sends them.
7. **Front-end fallback priority** (when resolving display URLs):
   - **Cards / list / Continue:** `card_image_url` → `thumbnail_url` → **gradient**
   - **Player hero:** `player_background_url` → `thumbnail_url` → **gradient**
   - **Square artwork (MiniPlayer / notifications):** `artwork_url` → `thumbnail_url`
8. **Fallback gradients** are **stable per vibe** (`vibe.id` seed) and **dark enough** for readable white text on cards and player chrome.
9. **All resolution logic stays centralized** in **`src/utils/artwork.ts`** — consumers must not reimplement priority chains.
10. **API field ownership is unchanged** — this doc does not add columns, rename fields, or move upload authority; see [`storage-strategy.md`](storage-strategy.md) for who writes objects.

---

## Architecture

### Data model (read-only on mobile)

| Field | Typical role |
| --- | --- |
| `thumbnail_url` | Base / legacy square; root fallback when others are null |
| `card_image_url` | List and card surfaces (API may resolve `card_image_url ?? thumbnail_url`) |
| `player_background_url` | Full-screen player hero |
| `artwork_url` | Square artwork (MiniPlayer, MediaSession-style metadata) |

**Cover bundle → vibe (create/edit):**

```
GET /api/cover-bundles  →  user picks bundle in "Choose cover"
       │
       ▼
applyCoverBundleToFormFields(form, bundle)
  • thumbnail_url      ← bundle.thumbnail_url      if non-empty
  • artwork_url        ← bundle.artwork_url        if non-empty
  • player_background_url ← bundle.player_background_url if non-empty
       │
       ▼
POST/PATCH /api/vibes  (body includes the three URL keys + metadata)
       │
       ▼
Laravel StoreVibeRequest / UpdateVibeRequest must allow keys → Vibe row persisted
```

Copied URLs **reference the same HTTPS strings** as the bundle (shared CDN objects) until the user replaces them—consistent with storage safe-deletion copy semantics in [`storage-strategy.md`](storage-strategy.md).

### Resolution helpers (`artwork.ts`)

| Surface | URL helper | Style helper | Priority |
| --- | --- | --- | --- |
| Cards, Home “Continue”, lists | `getVibeCardImageUrl` | `getVibeCardBackgroundStyle` | `card_image_url` → `thumbnail_url` → gradient |
| Full-screen player hero | `getVibePlayerBackgroundUrl` | `getVibePlayerBackgroundStyle` | `player_background_url` → `thumbnail_url` → gradient |
| MiniPlayer / `playVibe` artwork | `getVibeArtworkUrl` | — | `artwork_url` → `thumbnail_url` |
| Diagnostics / raw thumb only | `getVibeThumbnailUrl` | — | `thumbnail_url` only |

**Gradients:** `VIBE_ARTWORK_GRADIENTS` + `getVibeFallbackGradient(seed)` — seed usually `vibe.id`; cards may mix `index` into seed via `getVibeCardBackgroundStyle(vibe, index)`.

**Presentation polish (UI only):** CSS classes `CLS_ARTWORK_IMG_FADE`, `CLS_ARTWORK_CARD_ENTER` from `theme/layout.css` / `theme/motion.css`. Player overlays and vignette remain owned by **`VibePlayerPage.vue`**.

### Laravel validation contract

Mobile sends `thumbnail_url`, `artwork_url`, and `player_background_url` on vibe create/update when the user applies a cover or sets images. **Required rules shape (policy):**

```php
'thumbnail_url' => ['nullable', 'string', 'max:2048'],
'artwork_url' => ['nullable', 'string', 'max:2048'],
'player_background_url' => ['nullable', 'string', 'max:2048'],
```

(Exact rule types may match project conventions—`url` rule optional if API already stores full HTTPS strings.) **Without these keys in `rules()`, Laravel ignores the fields.**

---

## Rules

### Mobile consumption

- Treat every image field as an **opaque HTTPS URL** from JSON — no Spaces SDK, presigned upload, or bucket configuration in `front_vibes`.
- **Do not** add a CDN/Firebase host whitelist for `<img>` or CSS backgrounds.
- **Do not** duplicate fallback priority in Vue components — import from **`artwork.ts`**.
- **`playVibe()`** should pass artwork from **`getVibeArtworkUrl(vibe)`** for session/notification consistency.

### Cover bundles

- Bundles are **visual-only**; never attach bundle artwork logic to **sound** catalog rows.
- Apply bundle URLs with **`applyCoverBundleToFormFields`** only (non-empty overwrites).
- Persist via vibe API after validation whitelist is in place.

### Fallbacks

- When no URL resolves, use **`getVibeFallbackGradient`** — same vibe → same gradient (stable `id` seed).
- Gradients must stay **dark** (teal, navy, cyan, purple, ember, forest palette) for **readable white text** in light and dark app chrome.

### API and storage boundaries

- **Do not change API field ownership** or move upload/write responsibility to mobile.
- New distinct crops in API responses should map to **`card_image_url`**, **`player_background_url`**, **`artwork_url`** without scattering new priority logic outside **`artwork.ts`**.

### Known limitations (unchanged)

- Card/player heroes use **CSS `background-image`** — entrance animations are **not** tied to network load completion.
- URLs embedded in `url('…')` assume well-formed HTTPS strings; malicious quoting in API values would be a separate hardening task.

---

## Risks

| Risk | Mitigation |
| --- | --- |
| Laravel drops URL fields on save | Whitelist on `StoreVibeRequest` / `UpdateVibeRequest` |
| Duplicated priority in components | Single module `artwork.ts` |
| Host whitelist breaks legacy Firebase URLs | No whitelist; opaque HTTPS only |
| Direct Spaces access in mobile | Forbidden by storage strategy; URLs from API only |
| Bright gradients harm text contrast | Curated dark `VIBE_ARTWORK_GRADIENTS` |
| Cover apply clears fields unintentionally | Only overwrite when bundle URL is non-empty |
| Shared bundle URLs deleted from Spaces while vibe references them | Storage safe-deletion reference rules (backend) |
| Offline snapshot missing resolved fields | Front-end priority still runs on stored vibe JSON |

---

## Validation

**Mobile (manual / QA)**

- [ ] Vibe with only Spaces CDN URLs — cards, player, MiniPlayer render
- [ ] Vibe with legacy Firebase HTTPS URLs — same surfaces render
- [ ] Vibe with all image fields null — stable dark gradient per vibe id
- [ ] **Choose cover** on create/edit — non-empty bundle URLs appear on vibe; empty bundle fields do not wipe existing values
- [ ] After save + reload — imagery persists (implies Laravel validation whitelist)

**Code review**

- [ ] No new image priority logic outside `artwork.ts`
- [ ] No Spaces credentials or host allowlist in `front_vibes`
- [ ] `StoreVibeRequest` / `UpdateVibeRequest` include the three URL keys when vibe image persistence is in scope

**Regression targets**

| Area | Helpers |
| --- | --- |
| My Vibes cards | `getVibeCardBackgroundStyle`, `getVibeCardImageUrl` |
| Home “Continue your vibe” | same as cards |
| Player background | `getVibePlayerBackgroundStyle`, `getVibePlayerBackgroundUrl` |
| MiniPlayer placeholder | `getVibeFallbackGradient` + vibe id |
| Playback artwork | `getVibeArtworkUrl` |

---

## Related Files

| Location | Path |
| --- | --- |
| **Central (this repo)** | `docs/architecture/storage/storage-strategy.md` |
| | `docs/architecture/storage/mobile-cdn-validation.md` |
| **front_vibes (repo copy)** | `docs/artwork-background-strategy.md` — keep aligned with this file |
| | `src/utils/artwork.ts` |
| | `src/utils/cover-bundle-apply.ts` |
| | `src/views/CreateVibePage.vue`, `src/views/EditVibePage.vue` |
| | `src/views/VibePlayerPage.vue` |
| | `src/components/CoverBundlePickerModal.vue` |
| | `src/theme/layout.css`, `src/theme/motion.css` |
| **back_vibes** | `app/Http/Requests/StoreVibeRequest.php` |
| | `app/Http/Requests/UpdateVibeRequest.php` |
| | `app/Models/Vibe.php` |
| | `docs/cover-bundles.md` |
| **Specs** | `docs/specs/covers/create-cover-bundle/` (if present) |

When changing artwork resolution or cover apply behaviour, update **this file first**, then sync `front_vibes/docs/artwork-background-strategy.md` and keep Laravel validation in sync with the whitelist contract.
