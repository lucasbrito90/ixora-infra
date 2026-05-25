# ADR-002: Laravel-only writes to DigitalOcean Spaces

## Status

**Accepted** — reflects the **current shipped architecture** across `back_vibes`, `ixora-admin`, and `front_vibes`.

## Date

2026-05-23

## Context

Ixora stores user-facing **audio and image bytes** in **DigitalOcean Spaces** (S3-compatible), fronted by a **CDN hostname**. PostgreSQL holds **full public CDN URL strings** on entity rows (`file_url`, `thumbnail_url`, artwork fields, avatars). Clients — **Nuxt admin** and **Capacitor mobile** — render and stream assets from those HTTPS URLs only.

The platform is **moving new uploads from legacy Firebase Storage URLs to Spaces**. Firebase may still appear on older rows until migration; **Firebase is not the authoritative write path for new catalog assets** once Laravel + Spaces is in use.

Upload flows involve **validation** (MIME, size, auth, admin approval), **canonical object key layout** (`sounds/{id}/…`, `covers/{id}/…`), **transactional DB + object writes**, and **reference-checked deletion**. Exposing Spaces credentials or **direct-to-bucket** upload APIs to browsers or mobile apps would bypass those controls and complicate audit, rollback, and future async processing ([`future-processing-pipeline.md`](../architecture/storage/future-processing-pipeline.md)).

The team needed a single, enforceable rule: **one writer, one validation gate, one URL shape for clients.**

---

## Decision

**The Laravel API (`back_vibes`) is the ONLY component allowed to write to or delete objects in DigitalOcean Spaces.**

### Write path (mandatory)

```
┌─────────────┐   multipart/form-data    ┌──────────────┐   S3 API    ┌─────────────────────┐
│ ixora-admin │ ───────────────────────► │ Laravel API  │ ──────────► │ DigitalOcean Spaces │
│ front_vibes │   Bearer auth only       │ (back_vibes) │ DO_SPACES_* │ canonical keys      │
└─────────────┘   (admin uploads today)  └──────┬───────┘             └──────────┬──────────┘
       ▲                                        │                                │ CDN
       │         GET JSON — CDN HTTPS URLs      │  persist URL columns           │
       └────────────────────────────────────────┴────────────────────────────────┘
                                         PostgreSQL
```

| Step | Owner | Rule |
| --- | --- | --- |
| 1 | **Client** | Sends file + metadata to Laravel — **`multipart/form-data`**, Firebase Bearer auth |
| 2 | **Laravel** | Validates auth, policies, FormRequest rules, **`UploadAssetValidator`** |
| 3 | **Laravel** | Derives **canonical object key** — clients do **not** supply arbitrary bucket paths |
| 4 | **Laravel** | **`put`** via **`DigitalOceanSpacesService`** using server **`DO_SPACES_*`** credentials |
| 5 | **Laravel** | Builds **CDN URL** from **`DO_SPACES_CDN_URL`**, saves on entity row |
| 6 | **Client** | Consumes **opaque HTTPS CDN URLs** from API JSON — read only |

### Explicit prohibitions

| Pattern | Status |
| --- | --- |
| **Spaces credentials in admin or mobile** | **Forbidden** — no `DO_SPACES_KEY` / secret in client builds or repos |
| **Direct-to-Spaces uploads** | **Forbidden** |
| **Presigned PUT / POST upload URLs** | **Forbidden** — not shipped; not planned as default |
| **Client-side bucket SDK access** | **Forbidden** |
| **Public bucket mutation APIs** | **Forbidden** — no unauthenticated or client-scoped object write endpoints |
| **Mobile catalog upload (today)** | **Not shipped** — mobile consumes CDN URLs; any future mobile upload must still go **through Laravel** |

### Delete path

Object **`delete`** in Spaces runs **only from Laravel**, with **reference checks** on exact URL strings before removal ([`storage-strategy.md`](../architecture/storage/storage-strategy.md), **`SafeAssetDeletionService`**). Clients never delete bucket objects directly.

### URL contract for consumers

- Persist and return **CDN hostname** URLs — not raw origin endpoints — for client consumption.
- Mobile and admin treat URLs as **opaque HTTPS** — no bucket parsing required for normal product flows ([`mobile-cdn-validation.md`](../architecture/storage/mobile-cdn-validation.md)).

---

## Consequences

### Positive (motivations)

| Motivation | How Laravel-only writes deliver it |
| --- | --- |
| **Centralized validation** | Single **`UploadAssetValidator`**, FormRequest rules, and middleware stack for every upload |
| **Centralized security** | Secrets stay on server; clients hold Firebase identity tokens only |
| **Simpler auditability** | Upload/delete tied to authenticated Laravel actions and entity lifecycle |
| **Canonical object paths** | **`StoragePathBuilder`** enforces layout — no client-supplied key sprawl |
| **Rollback control** | Failed transactions can delete partial keys and roll back DB rows in one place |
| **Safe deletion enforcement** | **`StorageAssetReferenceService`** runs before Spaces **`delete`** |
| **CDN stability** | One **`publicUrl()`** helper; consistent CDN host on new assets |
| **Future processing compatibility** | Async workers can read originals and write derivatives under the same credential boundary ([`future-processing-pipeline.md`](../architecture/storage/future-processing-pipeline.md)) |

### Negative (tradeoffs)

| Tradeoff | Impact |
| --- | --- |
| **Laravel handles upload bandwidth** | File bytes traverse the app server (or platform ingress) on upload — egress/load on API tier |
| **No browser-direct uploads** | Admin cannot POST large files straight to Spaces — higher latency for very large files vs presigned flow |
| **Larger app server responsibility** | PHP/request timeouts, body size limits (Caddy, `upload_max_filesize`), and memory must be aligned with max asset sizes |
| **Single choke point** | Spaces write outage or misconfiguration blocks all uploads until Laravel path is healthy |

### Operational expectations

- **`DO_SPACES_*`** live only in Laravel runtime env (and secure CI) — documented in storage strategy, never committed.
- Admin uses **`POST /api/sounds`**, **`POST /api/cover-bundles`**, **`POST /api/admin/uploads`** — all Laravel-mediated ([`upload-validation.md`](../standards/upload-validation.md)).
- Code review must reject presigned-upload PRs unless a **future ADR** explicitly supersedes this decision.

---

## Alternatives Considered

| Alternative | Why not chosen (for Ixora today) |
| --- | --- |
| **Direct browser → Spaces uploads** | Bypasses Laravel validation and auth; exposes write policy complexity to clients; weak audit trail |
| **Presigned / signed upload URLs** | Reduces app bandwidth but splits validation timing; requires trust in post-upload callback integrity; **not shipped** |
| **Hybrid upload gateway** (edge accepts file, Laravel signs) | Extra infrastructure; same split-brain risks; deferred |
| **Firebase Storage as primary catalog store** | Legacy URLs may remain on rows; **new writes** target Spaces via Laravel for CDN economics, single deletion model, and alignment with relational catalog in PostgreSQL |
| **Public writable bucket or anonymous PUT** | Unacceptable security posture — rejected |
| **Mobile direct Spaces with embedded keys** | Secrets in binary; irreversible leak risk — rejected |

---

## Related Docs

| Document | Relationship |
| --- | --- |
| [`../architecture/storage/storage-strategy.md`](../architecture/storage/storage-strategy.md) | **Active policy** — access matrix, key layout, deletion rules |
| [`../standards/upload-validation.md`](../standards/upload-validation.md) | **Operational standard** — MIME/size, multipart flows, 413 vs 422 |
| [`../specs/sounds/create-sound/spec.md`](../specs/sounds/create-sound/spec.md) | Sound create — multipart to Laravel, CDN URLs on row |
| [`../specs/covers/create-cover-bundle/spec.md`](../specs/covers/create-cover-bundle/spec.md) | Cover bundle create — three images via Laravel only |
| [`../architecture/storage/mobile-cdn-validation.md`](../architecture/storage/mobile-cdn-validation.md) | Mobile read-side CDN expectations — no Spaces writes |
| [`../architecture/storage/future-processing-pipeline.md`](../architecture/storage/future-processing-pipeline.md) | Future derivatives — workers remain behind Laravel credential boundary |
| [`../decisions/ADR-001-firebase-auth-laravel-sync.md`](ADR-001-firebase-auth-laravel-sync.md) | Complementary — identity via Firebase; asset writes via Laravel |

### Implementation reference (current)

| Artifact | Path |
| --- | --- |
| Spaces service | `back_vibes/app/Services/Storage/DigitalOceanSpacesService.php` |
| Path builder | `back_vibes/app/Services/Storage/StoragePathBuilder.php` |
| Upload validator | `back_vibes/app/Services/Storage/UploadAssetValidator.php` |
| Safe delete | `back_vibes/app/Services/Storage/SafeAssetDeletionService.php` |
| URL reference checks | `back_vibes/app/Services/Storage/StorageAssetReferenceService.php` |
| Filesystem disk | `back_vibes/config/filesystems.php` (`spaces`) |
| Sound create action | `back_vibes/app/Actions/Sound/CreateSoundWithUploadedFiles.php` |
| Cover create action | `back_vibes/app/Actions/CoverBundle/CreateCoverBundleWithUploadedFiles.php` |

---

When storage write policy changes (e.g. approved presigned uploads for a specific flow), supersede this ADR with a new numbered decision and update [`storage-strategy.md`](../architecture/storage/storage-strategy.md) and [`upload-validation.md`](../standards/upload-validation.md) in the same change set.
