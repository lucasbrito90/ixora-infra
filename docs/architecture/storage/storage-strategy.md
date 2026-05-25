# Storage strategy — DigitalOcean Spaces

**Status:** Active policy (source of truth)  
**Scope:** Sounds, cover bundles, vibes, user avatars across Laravel API, Nuxt Admin, and mobile  
**Applies to:** `back_vibes`, `ixora-admin`, `front_vibes`

---

## Purpose

Define **where** Ixora assets live, **who** may read/write/delete them, **how** public URLs reach clients, and **when** objects may be removed from object storage—so all teams and AI-assisted tooling implement the same contract without leaking credentials or breaking reference integrity.

This document states **policy and layout**. It does **not** migrate data, prescribe a single upload UI, or replace feature-level specs.

---

## Context

Ixora stores references to user-facing assets in PostgreSQL and serves bytes from **DigitalOcean Spaces** (S3-compatible), fronted by a **CDN hostname**.

| Domain | Asset role |
| --- | --- |
| **Sounds** | Catalog audio + square thumbnails |
| **Cover bundles** | Reusable visual kits (thumbnail, artwork, player background) |
| **Vibes** | Per-user (or imported) visuals layered on sounds |
| **Users** | Profile avatars |

The platform is **moving new uploads from Firebase Storage to Spaces**. **Legacy Firebase HTTPS URLs** may remain on rows until a separate migration project replaces them. **Firebase Storage is not authoritative for new writes** once Laravel + Spaces is in use.

**Environment (staging reference — values are env-driven in Laravel, never committed):**

| Setting | Example |
| --- | --- |
| Bucket | `ixora-buckets` |
| Region | `tor1` |
| CDN (public URLs) | `https://ixora-buckets.tor1.cdn.digitaloceanspaces.com` |
| Origin (server SDK) | `https://ixora-buckets.tor1.digitaloceanspaces.com` |

---

## Current Decision

1. **Laravel API (`back_vibes`) is the only component** allowed to **read, write, and delete** objects in DigitalOcean Spaces, using server-side credentials from environment variables (e.g. `DO_SPACES_KEY`, `DO_SPACES_SECRET`).
2. **Nuxt Admin** and **mobile** never receive Spaces write or delete credentials. They **upload only through Laravel** (multipart or future API routes) and **consume public CDN HTTPS URLs** returned by the API.
3. **Public URLs persisted in the database and shown to clients must use the Spaces CDN hostname**, not the raw origin endpoint, for caching and egress economics.
4. **Object keys** follow the canonical layout below; **safe deletion** runs only after relational and URL reference checks.
5. **No secrets in git** — no API keys, bucket secrets, or real `.env` values in repositories or docs.

---

## Architecture

```
┌─────────────┐     multipart / API      ┌──────────────┐     S3 API      ┌─────────────────────┐
│ Nuxt Admin  │ ───────────────────────► │ Laravel API  │ ──────────────► │ DigitalOcean Spaces │
│ Mobile      │   Bearer auth only       │ (back_vibes) │   DO_SPACES_*   │ bucket: ixora-buckets│
└─────────────┘                          └──────┬───────┘                 └──────────┬──────────┘
       │                                         │                                     │
       │  GET CDN URLs from API JSON             │  stores full CDN URL strings        │ CDN
       └─────────────────────────────────────────┴─────────────────────────────────────┘
                                         PostgreSQL (file_url, thumbnail_url, …)
```

**Data flow**

1. Client sends file + metadata to Laravel (authenticated, validated).
2. Laravel writes under the canonical key, builds a **CDN URL**, saves it on the entity row.
3. Admin and mobile render assets from those URLs only.

**Field ownership** — columns store **full public CDN URLs** (nullable when unset):

| Entity | URL columns |
| --- | --- |
| **Sound** | `file_url`, `thumbnail_url` |
| **CoverBundle** | `thumbnail_url`, `artwork_url`, `player_background_url` |
| **Vibe** | `thumbnail_url`, `artwork_url`, `player_background_url` |
| **User** | `avatar_url` |

**Recommended object key layout** (logical paths inside the bucket; no leading slash). Extensions are examples; implementation may use the validated MIME extension (prefer **WebP** for bitmaps where the pipeline supports it):

```
sounds/{sound_id}/audio/original.{ext}
sounds/{sound_id}/thumbnail/thumbnail.{ext}

covers/{cover_bundle_id}/thumbnail/thumbnail.{ext}
covers/{cover_bundle_id}/artwork/artwork.{ext}
covers/{cover_bundle_id}/player-background/background.{ext}

vibes/{vibe_id}/thumbnail/thumbnail.{ext}
vibes/{vibe_id}/artwork/artwork.{ext}
vibes/{vibe_id}/player-background/background.{ext}

users/{user_id}/avatar/avatar.{ext}
```

New uploads **must** follow this layout. Legacy or migrated rows may point at older paths or Firebase URLs until cleanup.

---

## Rules

### Access (non-negotiable)

| Actor | Read assets | Write to Spaces | Delete from Spaces |
| --- | --- | --- | --- |
| **Laravel API** | Yes (server SDK) | Yes | Yes, only with reference checks |
| **Nuxt Admin** | CDN URLs only | **Via Laravel only** | **Via Laravel only** (when implemented) |
| **Mobile** | CDN URLs only | **No direct Spaces** | **No direct Spaces** |

- Admin **must not** embed Spaces keys, presigned upload policies for direct client writes, or bucket secrets in the Nuxt app or static build.
- Mobile **must not** ship Spaces credentials in the binary or device env.

### URLs and credentials

- Persist and return **CDN** URLs (`DO_SPACES_CDN_URL` / configured CDN host), not origin URLs, for client consumption.
- **Never commit secrets.** Credentials live only in Laravel (and worker) runtime env on the host/platform.

### Uploads

- All uploads are **validated server-side** (auth, MIME, size, entity ownership) before `put`.
- Clients send files to Laravel; Laravel derives the object key from entity type, id, asset type, and validated content—**clients do not supply arbitrary bucket paths**.

### Deletion and reference counting

Object deletion in Spaces is **irreversible**. Default to **no delete** when uncertain.

1. **Never delete an object** without confirming **no database row** still stores that **exact URL string** (canonical string match, not path guessing alone).
2. **Sound assets** (`sounds/...`): remove only when the sound row is deleted **and**:
   - the sound is **not** attached to any user vibe (`vibe_sounds`), **and**
   - the sound is **not** attached to any preset vibe (`preset_vibe_sounds`).
3. **Cover bundle assets** (`covers/...`): remove only when:
   - no **PresetVibe** references the bundle via `cover_bundle_id`, **and**
   - no **user Vibe** row still stores URLs pointing at those bundle objects (copied URLs count as references).
   - **Shipped behavior:** Laravel blocks `DELETE /api/cover-bundles/{id}` when referenced; Spaces keys are removed only when no row shares the same URL.
4. **Vibe assets** (`vibes/...`): delete only objects **exclusive** to that vibe—keys under `vibes/{vibe_id}/...` that are not shared elsewhere.
5. **Copy semantics:** When a vibe **copies** URLs from a cover bundle (preset import, “apply bundle”), vibe rows **reference the same URLs** as the bundle until replaced. **Deleting vibe-scoped cleanup must not remove bundle-owned keys** unless files are explicitly forked into `vibes/{id}/...` first.

Operational guideline: implement **reference counting or orphan scans** before delete. **Shipped:** reference-checked cleanup for catalog **sounds** (`DELETE /api/sounds/{sound}`) and **cover bundles** (`DELETE /api/cover-bundles/{cover_bundle}`).

### Migration and legacy

- This policy **does not migrate bytes** from Firebase to Spaces.
- **Legacy Firebase URLs** may coexist on rows until a dedicated migration (with backup and validation) updates them.
- A future Laravel maintenance command may normalize URLs, re-upload, or detach stale paths—design TBD.

### Implementation maturity (for planners; not a change to policy)

| Area | State |
| --- | --- |
| Laravel Spaces disk, path builder, CDN URL helpers | Shipped — see `back_vibes` service docs |
| Admin multipart uploads (sounds, cover bundles) + generic `POST /api/admin/uploads` | Shipped |
| Safe delete (sounds, cover bundles) | Shipped |
| Vibe/user avatar exclusive delete, reset/inventory command, full mobile avatar upload | TBD |

---

## Risks

| Risk | Mitigation |
| --- | --- |
| Spaces credentials in admin or mobile builds | Code review + no `DO_SPACES_*` in client repos; uploads only via API |
| Origin URL stored instead of CDN URL | Laravel `publicUrl()` and review of API resources; validate CDN host in tests |
| Deleting shared URLs when removing one entity | Reference checks on URL strings; block DELETE when presets/vibes still reference |
| Orphan objects after failed transactions | Laravel upload actions roll back DB and delete partial keys on failure where implemented |
| Legacy Firebase + Spaces URLs mixed | Treat both as read-only HTTPS until migration; mobile should tolerate either host |
| Irreversible delete in Spaces | No delete without reference proof; prefer dry-run inventory before bulk cleanup |

---

## Validation

**Policy / code review**

- [ ] No Spaces write/delete credentials in `ixora-admin`, `front_vibes`, or committed config
- [ ] New upload paths match canonical key layout
- [ ] API responses and DB columns use CDN hostname for new assets
- [ ] Delete endpoints enforce relational rules before Spaces `delete`

**Automated (Laravel)**

- Feature tests with `Storage::fake('spaces')` for multipart create and safe delete (sounds, cover bundles)
- Upload validator MIME/size limits aligned with admin docs

**Manual / staging**

- Create sound or cover bundle from staging admin → objects visible at CDN URL, not origin-only
- Delete unused catalog entity → Spaces object removed; shared URL retained when another row references it
- Mobile loads artwork/audio from HTTPS CDN URLs without Spaces SDK

**Future migration project (out of scope here)**

- Inventory Firebase vs Spaces URLs, backup, re-upload, row update, spot-check CDN fetch

---

## Related Files

| Location | Document / code |
| --- | --- |
| **Central (this repo)** | `docs/architecture/storage/artwork-background-strategy.md` |
| | `docs/architecture/storage/mobile-cdn-validation.md` |
| | `docs/specs/sounds/create-sound/` |
| | `docs/specs/covers/create-cover-bundle/` |
| **back_vibes** | `docs/storage-strategy.md` (repo copy — keep aligned with this file) |
| | `docs/safe-asset-deletion.md` |
| | `docs/laravel-spaces-service.md` |
| | `docs/laravel-upload-endpoints.md` |
| | `config/filesystems.php` (`spaces` disk) |
| | `app/Services/Storage/DigitalOceanSpacesService.php` |
| | `app/Services/Storage/StoragePathBuilder.php` |
| | `app/Services/Storage/StorageAssetReferenceService.php` |
| **ixora-admin** | `docs/upload-validation.md`, `docs/cover-bundles-admin.md` |
| **front_vibes** | `docs/artwork-background-strategy.md` |
| **Infra** | `opentofu/staging/` — bucket, CDN, `DO_SPACES_*` on App Platform |

When changing storage policy, update **this file first**, then sync downstream copies and specs.
