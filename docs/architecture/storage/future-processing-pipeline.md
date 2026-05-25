# Future media processing pipeline — storage placeholder (planning only)

**Status:** Future architecture — **NOT implemented**  
**Scope:** Possible post-upload media transforms (audio, images, derived assets)  
**Applies to:** Future workers, queue infrastructure, extended object keys — **nothing shipped today**

> **Planning-only.** This document is a **future placeholder** for media processing boundaries. It does **not** authorize implementation, prescribe tasks, or modify current upload specs. Until an explicit delivery phase begins, all processing beyond validation + store-as-is is **out of scope**.

---

## Purpose

Reserve a coherent architecture for **when** Ixora might transform uploaded bytes after they reach object storage: transcoding, resizing, waveforms, loudness normalization, metadata extraction, async jobs, status tracking, versioning, and CDN URL stability — **without** contradicting today’s **store-as-is** policy or the rule that **only Laravel writes to Spaces**.

This document states **possible directions and boundaries**. Current upload behaviour remains defined by [`storage-strategy.md`](storage-strategy.md) and feature specs — **unchanged by this file**.

---

## Context

### Shipped today (unchanged)

| Policy | State |
| --- | --- |
| **No transcoding** | Uploaded audio and images are stored **as validated** — no derivative generation |
| **Laravel-only Spaces writer** | `back_vibes` holds `DO_SPACES_*`; admin and mobile upload **via API only** |
| **No direct client → Spaces** | No presigned put policies, no bucket credentials in Nuxt or Capacitor builds |
| **CDN URLs on rows** | PostgreSQL stores full public **CDN hostname** strings (`file_url`, `thumbnail_url`, …) |
| **Canonical key layout** | Entity-scoped paths under `sounds/`, `covers/`, `vibes/`, `users/` — see storage strategy |
| **Sync upload path** | Multipart request → validate → `put` → persist URL — **no processing queue** |
| **Playback** | Mobile streams HTTPS CDN URLs; **no** server-side HLS/transcode for playback ([`../audio/audio-cache.md`](../audio/audio-cache.md)) |

Reference: [`../../standards/upload-validation.md`](../../standards/upload-validation.md) — explicitly excludes transcoding, normalization queues, and image optimization today.

### Why a future doc exists

Product and infra may later want **smaller mobile payloads**, **consistent image dimensions**, **preview waveforms**, or **normalized loudness** — work that should **not** be bolted onto synchronous Laravel request threads or client-side uploads without an ADR. This file holds **design space** until then.

---

## Current Decision (today)

1. **Bytes in = bytes out** (after MIME/size validation) — no ffmpeg/ImageMagick in the upload hot path.
2. **Laravel remains the only Spaces writer** — any future worker **reads/writes through the same credential boundary** (Laravel job dispatch, trusted sidecar, or worker with scoped keys — **not decided**).
3. **Admin and mobile do not upload directly to Spaces** — future processing does **not** relax this; clients still POST multipart to Laravel (or future API that Laravel owns).
4. **Go / Rust / dedicated media workers** may be **considered later** — **not required** for current architecture; PHP/Laravel queue + ffmpeg sidecar is equally valid planning space.
5. **This document must not be cited as implementation tasks** or used to change existing upload specs without a dedicated delivery spec + ADR.

---

## Future architecture (conceptual)

When processing ships, the intended **shape** separates **acceptance** from **derivation**:

```
┌─────────────┐   multipart    ┌──────────────┐   put original   ┌─────────────────┐
│ Admin/Mobile│ ─────────────► │ Laravel API  │ ───────────────► │ Spaces (original)│
└─────────────┘                └──────┬───────┘                  └────────┬────────┘
                                      │                                   │
                                      │ enqueue ProcessMediaJob           │ read source
                                      ▼                                   │
                               ┌──────────────┐                           │
                               │ Queue worker │ ◄─────────────────────────┘
                               │ (future)     │
                               └──────┬───────┘
                                      │ put derivatives + update DB status
                                      ▼
                               ┌─────────────────┐
                               │ Spaces (derived) │  + CDN URLs on entity / side table
                               └─────────────────┘
                                      │
                                      ▼
                               Mobile / admin consume CDN URLs (unchanged read model)
```

**Principle:** Upload API returns **quick acceptance** (original stored or staged); heavy work runs **async**. Exact UX (blocking vs `processing` status) is **TBD at implementation**.

---

## Possible processing capabilities (future)

Each row is **planning vocabulary only** — not a commitment or task.

| Capability | Typical inputs | Possible outputs | Notes |
| --- | --- | --- | --- |
| **Audio transcoding** | Catalog sound `original.*` | `playback.mp3`, `playback.aac`, optional `hls/` | Mobile today expects single HTTPS URL — transcode would update **`file_url`** or add variant columns |
| **Image resizing** | Cover/vibe/avatar uploads | Max-dimension WebP/JPEG variants (`thumbnail`, `artwork`, `background`) | Aligns with storage strategy **WebP preference** when pipeline exists |
| **Waveform generation** | Audio original | JSON peaks or PNG/SVG sprite under `sounds/{id}/waveform/` | UI preview only — not required for playback |
| **Loudness normalization** | Audio original | New audio object (EBU R128 / LUFS target TBD) | Distinct from **runtime** volume on `vibe_sounds` pivot |
| **Metadata extraction** | Audio/image bytes | Duration, sample rate, channels, EXIF stripped fields → DB columns or JSON | May backfill `sounds.duration` automatically |

**Explicit non-goals in planning (unless product revises):**

- Real-time streaming transcoding on play requests
- Client-side ffmpeg in WebView
- Virus/malware scanning (separate concern; not covered here)
- AI generation of catalog assets (separate product)

---

## Async queue / job pipeline (future boundary)

**Not implemented.** Likely components when needed:

| Layer | Future role |
| --- | --- |
| **Laravel dispatch** | After successful original `put`, dispatch `ProcessSoundMedia`, `ProcessImageMedia`, etc. |
| **Queue driver** | Redis, SQS, database — **TBD**; same infra as other async work |
| **Worker process** | PHP `queue:work`, Horizon, or **external** Go/Rust/ffmpeg service polling jobs |
| **Idempotency** | Job keyed by `entity_type + entity_id + asset_role + content_hash` to skip duplicate work |
| **Concurrency** | Per-entity lock to avoid racing two jobs on same sound id |

**Boundary rules (planning):**

- Web request **must not** block on ffmpeg completion beyond agreed SLA (seconds for accept, minutes for process).
- Workers **must not** receive admin/mobile Spaces credentials — use server-side keys only.
- Failed jobs **retry with backoff**; permanent failure surfaces in **processing status** (below).

**Go/Rust/media worker:** Optional for CPU-heavy batch or isolated ffmpeg crashes — Laravel would still **own job enqueue, DB updates, and CDN URL publication**. Not required for v1 planning sketch.

---

## Processing status fields (future)

**Not in current schema.** Possible patterns (choose one at implementation — not prescriptive now):

| Pattern | Description |
| --- | --- |
| **Column on entity** | e.g. `sounds.processing_status`: `pending` \| `processing` \| `ready` \| `failed` |
| **Side table** | `media_processing_jobs` with `entity_type`, `entity_id`, `kind`, `status`, `error`, `attempts` |
| **Version pointer** | `file_url` stable; `processing_generation` increments on re-process |

**API behaviour (future):**

- Admin UI may poll or subscribe until `ready`
- Mobile **should not** assume derivatives exist until status `ready` (or original URL still valid fallback)
- Failed processing: entity may remain with **original only** or block publish — product TBD

---

## Object replacement, versioning, and CDN URL stability

Today each upload **overwrites** the canonical key or writes once at create — URLs on the row match that object.

Future processing introduces **tension between immutable URLs and new bytes**:

| Strategy | CDN stability | Tradeoff |
| --- | --- | --- |
| **In-place replace** | Same URL string; CDN/browser cache may serve stale bytes until TTL purge | Simplest row model; cache invalidation risk |
| **Versioned keys** | New key `…/audio/v2/playback.mp3`; DB URL updated atomically | Old URL orphans unless reference-checked delete |
| **Immutable original + derived keys** | `original.{ext}` never changes; `playback.mp3` updated independently | Clear audit; more keys to garbage-collect |

**Planning direction:**

- **`file_url` on API** should remain the **single canonical playback/read URL** for mobile unless a spec explicitly adds variant selection.
- Prefer **atomic DB update** (transaction: put derivative → update URL + status → delete superseded key if unreferenced).
- Align deletion rules with [`storage-strategy.md`](storage-strategy.md) — **exact URL string** reference checks before `delete`.
- CDN cache: plan for **Cache-Control** on derived assets, short TTL on processing flip, or version query param — **TBD** ([`mobile-cdn-validation.md`](mobile-cdn-validation.md) must be updated when behaviour changes).

---

## Rollback and failure handling (future)

| Scenario | Planning direction |
| --- | --- |
| **Job fails mid-pipeline** | Leave `original` intact; set status `failed`; optional admin retry |
| **Partial derivatives written** | Transaction or cleanup step deletes orphan keys; never point DB at missing object |
| **DB update fails after put** | Job retries; orphan scan command removes unreferenced keys (storage strategy already anticipates orphan risk) |
| **Re-process same upload** | Idempotent job; bump version or overwrite derived key only |
| **Rollback to original-only** | Restore `file_url` to original CDN path; delete derived keys if unreferenced |
| **User deletes entity during job** | Job aborts gracefully; cascade delete per existing safe-delete rules |

**Today:** Laravel upload actions already roll back DB and delete partial keys on **sync** failure where implemented — async processing would extend that pattern, not replace it.

---

## Local vs worker responsibility (future boundary)

| Concern | Laravel (API) | Worker (future) |
| --- | --- | --- |
| Auth, validation, MIME/size | Yes | No |
| Original `put` to Spaces | Yes | Optional read-only if staged elsewhere |
| Enqueue job | Yes | Consumes |
| ffmpeg/ImageMagick/waveform | No (hot path) | Yes |
| Update `file_url` / status | Yes (via job completion handler) | Proposes paths; Laravel commits |
| Expose URLs to clients | Yes (resources unchanged read model) | No direct public API |

**Admin/mobile:** unchanged — multipart to Laravel only; never direct Spaces or worker endpoints.

---

## Relationship to playback and offline

Future audio derivatives must stay compatible with:

- **Mobile execution plan** — `layer.fileUrl` from API ([`../../specs/vibes/execution-plan/spec.md`](../../specs/vibes/execution-plan/spec.md))
- **Offline download** — manifest **`remoteUrl` exact match** ([`../audio/audio-cache.md`](../audio/audio-cache.md))
- **No backend play/transcode endpoint** ([`../../specs/vibes/playback-runtime/spec.md`](../../specs/vibes/playback-runtime/spec.md))

If `file_url` changes after processing completes, **offline copies invalidate** until re-download — same as any CDN URL change today.

---

## Risks (if implemented without boundaries)

| Risk | Mitigation (future design) |
| --- | --- |
| Stale CDN after in-place replace | Versioned keys or cache headers; document in mobile-cdn-validation |
| Broken `file_url` pointer | Transactional publish; status `failed` keeps last good URL |
| Worker holds overly broad S3 keys | Scoped IAM/prefix per job type |
| Sync upload timeout | Never block on ffmpeg in request thread |
| Orphan derivatives | Reference checks + inventory job |
| Scope creep | Separate ADR per capability (transcode vs waveform vs resize) |

---

## What this document does not contain

- Implementation tasks, timelines, or sprint plans
- Changes to [`../../specs/sounds/create-sound/spec.md`](../../specs/sounds/create-sound/spec.md), [`../../specs/covers/create-cover-bundle/spec.md`](../../specs/covers/create-cover-bundle/spec.md), or [`../../standards/upload-validation.md`](../../standards/upload-validation.md)
- Mandate to adopt Go/Rust workers
- ffmpeg flags, queue driver choice, or schema migrations
- Commitments to HLS, WebP-only policy, or LUFS targets

When processing moves from planning to delivery, expect: dedicated **feature spec(s)**, **ADR(s)** for URL/versioning strategy, updates to **storage-strategy** and upload standards — not the reverse.

---

## Related docs

| Document | Relationship |
| --- | --- |
| [`storage-strategy.md`](storage-strategy.md) | **Current** Spaces policy — remains authoritative |
| [`mobile-cdn-validation.md`](mobile-cdn-validation.md) | CDN URL expectations for mobile QA |
| [`artwork-background-strategy.md`](artwork-background-strategy.md) | Image URL consumption — no server resize today |
| [`../../standards/upload-validation.md`](../../standards/upload-validation.md) | **Current** validation — no transcoding |
| [`../../specs/sounds/create-sound/spec.md`](../../specs/sounds/create-sound/spec.md) | **Current** sound upload — bytes as-is |
| [`../../specs/covers/create-cover-bundle/spec.md`](../../specs/covers/create-cover-bundle/spec.md) | **Current** cover upload — no resize pipeline |
| [`../audio/audio-cache.md`](../audio/audio-cache.md) | Playback/offline URL identity |
| [`../backend/scheduling-model.md`](../backend/scheduling-model.md) | Separate future concern — not media processing |

### Code reference (current upload path only)

| Artifact | Path |
| --- | --- |
| Spaces service | `back_vibes/app/Services/Storage/DigitalOceanSpacesService.php` |
| Path builder | `back_vibes/app/Services/Storage/StoragePathBuilder.php` |
| Reference-safe delete | `back_vibes/app/Services/Storage/StorageAssetReferenceService.php` |
| Upload validator | `back_vibes/app/Services/Storage/UploadAssetValidator.php` (or equivalent) |

---

**Reminder:** Media processing beyond validate-and-store is **not implemented**. Uploaded bytes are stored **as-is** today. This file is **planning-only**.
