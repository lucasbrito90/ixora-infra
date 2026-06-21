# ADR-006: No direct client uploads to DigitalOcean Spaces

## Status

**Accepted** — reflects **current shipped architecture** across `ixora-admin`, `front_vibes`, and `back_vibes`.

## Date

2026-05-23

## Context

Ixora stores catalog and user-facing asset bytes in **DigitalOcean Spaces**, exposed to clients as **CDN HTTPS URLs** on Laravel API responses. Upload authorization, MIME/size policy, canonical object keys, transactional DB writes, and safe deletion all assume a **single server-side gate** before any object **`put`**.

**Admin (`ixora-admin`)** uploads catalog audio and images today via **multipart POST to Laravel**. **Mobile (`front_vibes`)** does **not** ship end-user upload flows — it **reads** CDN URLs for playback and artwork only.

A common optimization is **direct client → bucket** uploads using **presigned URLs**, embedded Spaces keys, or hybrid gateways to reduce app-server bandwidth. Those patterns split validation timing, weaken audit trails, risk **irreversible credential leaks** in app binaries, and complicate future post-upload processing ([`future-processing-pipeline.md`](../architecture/storage/future-processing-pipeline.md)).

[ADR-002](ADR-002-laravel-only-storage-writes.md) establishes Laravel as the **only Spaces writer**. This ADR states the **client-side corollary**: **mobile and admin must never upload directly to Spaces** — all uploads **terminate on Laravel**.

---

## Decision

**Mobile and admin clients must never upload directly to DigitalOcean Spaces.**

### Mandatory upload path

```
┌─────────────┐   multipart/form-data    ┌──────────────┐   S3 put    ┌─────────────────────┐
│ ixora-admin │ ───────────────────────► │ Laravel API  │ ──────────► │ DigitalOcean Spaces │
│ front_vibes │   Firebase Bearer        │              │ DO_SPACES_* │                     │
│  (future)   │   (when upload exists)   │              │             │                     │
└─────────────┘                          └──────┬───────┘             └──────────┬──────────┘
       ▲                                        │                                │
       │  CDN HTTPS URLs in JSON only           │ UploadAssetValidator           │ CDN
       │  after DB + object success             │ StoragePathBuilder             │
       └────────────────────────────────────────┴────────────────────────────────┘
```

| Rule | Detail |
| --- | --- |
| **All uploads go through Laravel** | **`multipart/form-data`** to authenticated API routes — bytes do **not** bypass the app server |
| **No Spaces credentials on clients** | No `DO_SPACES_KEY`, secret, or service account in Nuxt build, Capacitor binary, or committed config |
| **No presigned upload URLs** | Clients do **not** receive time-limited PUT/POST policies for direct bucket writes |
| **No client bucket SDK** | No `@aws-sdk/client-s3`, Spaces SDK, or equivalent in admin/mobile for **writes** |
| **`UploadAssetValidator` authoritative** | MIME, size, and extension policy enforced server-side — client hints are UX only ([`upload-validation.md`](../standards/upload-validation.md)) |
| **CDN URLs after persistence** | API returns **`file_url`** / image URL fields **only after** successful Laravel **`put`** + DB update |
| **Mobile read-only today** | No catalog or vibe file upload from mobile — consume opaque HTTPS URLs only |
| **Future mobile upload** | Any shipped user upload (e.g. avatar, vibe artwork) **must still** POST multipart to Laravel — **this ADR still applies** |

### Explicit prohibitions

| Pattern | Status |
| --- | --- |
| **Direct mobile → Spaces** | **Forbidden** |
| **Direct admin browser → Spaces** (bypassing Laravel) | **Forbidden** |
| **Presigned PUT / POST to bucket** | **Forbidden** — not default architecture |
| **Hybrid gateway** (client uploads to edge, Laravel only signs) | **Not shipped** |
| **Firebase Storage direct upload** for new catalog assets | **Not authoritative** — new writes target Spaces via Laravel ([`storage-strategy.md`](../architecture/storage/storage-strategy.md)) |
| **Client-supplied object keys or bucket paths** | **Forbidden** — Laravel derives keys from entity + asset role |
| **Public or anonymous bucket mutation APIs** | **Forbidden** |

### What mobile does today

| Capability | Mobile |
| --- | --- |
| Stream / play audio from **`file_url`** | Yes — HTTPS CDN |
| Render artwork from API URL fields | Yes — HTTPS CDN |
| Offline download of existing CDN URLs | Yes — [`ADR-004`](ADR-004-offline-audio-strategy.md) native GET, **not** upload |
| Upload new catalog sounds or cover bundles | **No** — admin only |
| Upload vibe-scoped images | **No** — not shipped |

---

## Consequences

### Positive (motivations)

| Motivation | How Laravel-terminated uploads deliver it |
| --- | --- |
| **Centralized validation** | One **`UploadAssetValidator`** + FormRequest stack for every file |
| **Centralized auth** | **`firebase.auth`**, **`admin.approved`**, policies before bytes hit disk |
| **Rollback control** | Failed DB write → delete partial Spaces key in same action |
| **Auditability** | Upload tied to authenticated user and Laravel route |
| **Canonical object paths** | **`StoragePathBuilder`** — no client key sprawl |
| **Future processing compatibility** | Post-upload jobs enqueue from Laravel after validated **`put`** ([`future-processing-pipeline.md`](../architecture/storage/future-processing-pipeline.md)) |
| **No irreversible credential leaks** | Spaces secrets never ship in APK/IPA or admin static bundle |

### Negative (tradeoffs)

| Tradeoff | Impact |
| --- | --- |
| **Larger backend bandwidth usage** | Full file transits ingress + PHP/worker path |
| **Higher upload latency** | Extra hop vs direct-to-S3 — acceptable for current catalog sizes |
| **No edge-direct upload optimization** | Large files cannot skip app server without a **new ADR** |
| **Body size / timeout tuning** | Caddy, PHP, and platform limits must match max asset policy |
| **Mobile cannot self-serve catalog** | Catalog creation remains admin-operated today |

---

## Alternatives Considered

| Alternative | Why not chosen (for Ixora today) |
| --- | --- |
| **Direct mobile uploads** | Embedded or presigned credentials; bypasses validation gate; APK leak risk |
| **Signed PUT URLs** (Laravel mints, client PUTs to Spaces) | Split validation; callback integrity; **not shipped** |
| **Hybrid upload gateways** | Extra infra; same trust-boundary problems — deferred |
| **Firebase Storage direct upload** | Legacy read URLs may exist; **new catalog writes** use Laravel → Spaces per storage strategy |
| **Public writable bucket** | Security unacceptable — rejected |
| **Client pastes URL on create** | Prohibited on multipart create flows — files required, URL fields **`prohibited`** |

Presigned uploads for **specific** high-volume flows would require superseding **ADR-002** and **this ADR** with explicit scope, post-upload verification, and updated standards — not incremental client SDK writes.

---

## Relationship to other decisions

| ADR / doc | Relationship |
| --- | --- |
| **[ADR-002](ADR-002-laravel-only-storage-writes.md)** | Server-side “Laravel only writer” — this ADR is the **client corollary** |
| **[ADR-001](ADR-001-firebase-auth-laravel-sync.md)** | Clients authenticate with Firebase; **asset writes** still server-mediated |
| **[ADR-004](ADR-004-offline-audio-strategy.md)** | Mobile downloads CDN bytes via native HTTP — **read** path, not upload |

---

## Related Docs

| Document | Relationship |
| --- | --- |
| [`ADR-002-laravel-only-storage-writes.md`](ADR-002-laravel-only-storage-writes.md) | Complementary server-side decision |
| [`../standards/upload-validation.md`](../standards/upload-validation.md) | Multipart contracts, **`UploadAssetValidator`**, 413 vs 422 |
| [`../architecture/storage/storage-strategy.md`](../architecture/storage/storage-strategy.md) | Access matrix, key layout, deletion |
| [`../architecture/storage/future-processing-pipeline.md`](../architecture/storage/future-processing-pipeline.md) | Processing stays behind Laravel credential boundary |
| [`../architecture/storage/mobile-cdn-validation.md`](../architecture/storage/mobile-cdn-validation.md) | Mobile **read** CDN QA — no write path |
| [`../specs/sounds/create-sound/spec.md`](../specs/sounds/create-sound/spec.md) | Admin multipart create — Laravel only |
| [`../specs/covers/create-cover-bundle/spec.md`](../specs/covers/create-cover-bundle/spec.md) | Admin three-file create — Laravel only |

### Implementation reference (current)

| Client | Upload behaviour |
| --- | --- |
| **`ixora-admin`** | Multipart to **`POST /api/sounds`**, **`POST /api/cover-bundles`**, **`POST /api/admin/uploads`** |
| **`front_vibes`** | **No upload endpoints called** — GET resources with CDN URLs only |
| **`back_vibes`** | **`DigitalOceanSpacesService`**, **`UploadAssetValidator`**, **`StoragePathBuilder`** |

### Review checklist

- [ ] No `DO_SPACES_*` in `front_vibes`, `ixora-admin`, or client env templates committed to git
- [ ] No presigned upload route or client PUT-to-CDN code without ADR supersession
- [ ] New mobile upload features use Laravel multipart — not Spaces SDK

---

When client upload architecture changes (e.g. approved presigned flow for a single asset class), supersede **ADR-002** and **this ADR** together with a new numbered decision and updated upload standards.
