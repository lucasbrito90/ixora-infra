# Spaces CDN policy — DigitalOcean object delivery

**Status:** Active architecture (source of truth)  
**Scope:** CDN hostname usage, public URL shape, cache and invalidation expectations, URL persistence, offline identity, deletion safety, and Firebase migration coexistence  
**Applies to:** `back_vibes`, `ixora-admin`, `front_vibes`, `ixora-infra/opentofu/staging`

> **Current policy only.** Ixora uses **one DigitalOcean Spaces bucket per environment** fronted by the **Spaces CDN hostname**. There is **no CloudFront**, **no signed CDN URLs**, **no multi-CDN routing**, and **no application-level CDN purge API** today.

**Parent policy:** [`storage-strategy.md`](storage-strategy.md) — access matrix, key layout, deletion rules  
**Write authority:** [ADR-002](../../decisions/ADR-002-laravel-only-storage-writes.md)  
**Offline identity:** [ADR-004](../../decisions/ADR-004-offline-audio-strategy.md)  
**Mobile QA:** [`mobile-cdn-validation.md`](mobile-cdn-validation.md)  
**Future derivatives:** [`future-processing-pipeline.md`](future-processing-pipeline.md) (planning only)

---

## Purpose

Define the **CDN and Spaces delivery contract**: how Laravel builds and persists URLs, how clients must consume them, what “stable URL” means for streaming and offline manifests, how public read coexists with private write, and what operators should expect when replacing assets or deleting entities — without leaking bucket implementation details to admin or mobile.

---

## Context

Ixora stores **bytes** in **DigitalOcean Spaces** (S3-compatible) and **references** in PostgreSQL as **full HTTPS URL strings**. Clients never hold Spaces credentials; they request assets with ordinary **GET** to URLs returned in API JSON.

| Layer | Role |
| --- | --- |
| **Origin** | `https://{bucket}.{region}.digitaloceanspaces.com` — Laravel SDK **`put`** / **`delete`** only |
| **CDN** | `https://{bucket}.{region}.cdn.digitaloceanspaces.com` — **client-facing** hostname for reads |
| **Laravel** | Sole writer; **`DigitalOceanSpacesService::publicUrl()`** builds CDN URLs |
| **Admin / mobile** | Read-only HTTPS consumers |

**Staging reference (env-driven, never committed):**

| Setting | Example |
| --- | --- |
| `DO_SPACES_BUCKET` | `ixora-buckets` |
| `DO_SPACES_REGION` | `tor1` |
| `DO_SPACES_CDN_URL` | `https://ixora-buckets.tor1.cdn.digitaloceanspaces.com` |
| `DO_SPACES_ENDPOINT` | `https://tor1.digitaloceanspaces.com` |

OpenTofu provisions a **private ACL** bucket; Laravel uses **server-side keys** for mutation. Public delivery is via **CDN HTTPS URLs** on entity rows — not via client bucket access ([`storage-strategy.md`](storage-strategy.md)).

---

## Current Decision

1. **Only Laravel generates Spaces CDN URLs** for new catalog assets — via **`publicUrl($objectKey)`** after a validated **`put`**.
2. **PostgreSQL and API JSON store and return full HTTPS CDN URL strings** — not origin URLs, not relative paths, not client-constructed URLs.
3. **Public read / private write:** clients **read** with anonymous HTTPS GET to CDN URLs; **writes and deletes** go **only** through Laravel with **`DO_SPACES_*`** credentials ([ADR-002](../../decisions/ADR-002-laravel-only-storage-writes.md)).
4. **URL strings are stable identifiers** for reference counting, safe deletion, and offline manifests — treat changes to the stored string as a **breaking identity change** for offline copies.
5. **No signed, expiring, or tokenized CDN URLs** on playback, download, or image paths.
6. **No CDN invalidation pipeline** is shipped — cache behaviour follows **DigitalOcean Spaces CDN defaults** plus **URL/key discipline**.
7. **Legacy Firebase Storage HTTPS URLs** may remain on rows until migration; they are **opaque HTTPS** to clients and **skipped** for Spaces object deletion when not parseable as bucket URLs.

---

## Architecture

```
                         WRITE (private)                           READ (public HTTPS)
┌──────────────┐  multipart   ┌─────────────┐  S3 API   ┌──────────────┐
│ Admin/Mobile │ ────────────► │ Laravel API │ ────────► │ Spaces origin │
└──────────────┘  Bearer only  │ put/delete  │ DO_SPACES │ (private ACL) │
       ▲                       │ publicUrl() │           └───────┬──────┘
       │                       └──────┬──────┘                   │
       │  GET JSON: full CDN URLs     │ persist exact strings     │ CDN edge
       │                              ▼                           ▼
       └──────────────────────  PostgreSQL ─────────────►  *.cdn.digitaloceanspaces.com
                              (file_url, thumbnail_url, …)
```

**Implementation reference (`back_vibes`):**

| Component | Path |
| --- | --- |
| CDN URL builder | `app/Services/Storage/DigitalOceanSpacesService.php` — **`publicUrl()`**, **`keyFromUrl()`** (server only) |
| Canonical keys | `app/Services/Storage/StoragePathBuilder.php` |
| Disk config | `config/filesystems.php` — `spaces.url` = **`DO_SPACES_CDN_URL`** |
| Reference counting | `app/Services/Storage/StorageAssetReferenceService.php` |
| Safe delete | `app/Services/Storage/SafeAssetDeletionService.php` |

---

## CDN hostname strategy

### Single CDN base per environment

Laravel reads **`DO_SPACES_CDN_URL`** (trimmed, no trailing slash) and appends the **object key**:

```
{DO_SPACES_CDN_URL}/{objectKey}
```

Example:

```
https://ixora-buckets.tor1.cdn.digitaloceanspaces.com/sounds/42/audio/original.mp3
```

| Rule | Detail |
| --- | --- |
| **Client hostname** | Always the **CDN** host (`…cdn.digitaloceanspaces.com`) for new assets |
| **Origin hostname** | `…digitaloceanspaces.com` — **Laravel SDK only**; must not appear in API JSON for new writes |
| **Multi-CDN** | **Not used** — one bucket, one CDN hostname per env |
| **Path-style vs virtual-host** | Laravel **`keyFromUrl()`** accepts CDN host, virtual-host origin, and path-style origin for **server-side** key extraction — clients must not depend on this |

OpenTofu outputs the expected CDN pattern as `spaces_cdn_url_example` ([`staging-digitalocean.md`](../backend/staging-digitalocean.md)). CDN enablement on the bucket is an **operator/DigitalOcean console** concern — not fully automated in IaC today.

---

## Laravel-generated CDN URLs only

| Actor | Allowed URL source |
| --- | --- |
| **Laravel** | **`publicUrl($key)`** after **`putFile` / `put`** |
| **Admin** | Response **`data.url`** from upload/create endpoints — copy into form, then PATCH entity |
| **Mobile** | **`SoundResource` / `VibeResource`** (and related) — fields as returned |
| **Clients** | **Forbidden** — constructing URLs from bucket name, region, or guessed keys |

Upload flow ([`upload-validation.md`](../../standards/upload-validation.md)):

1. Validate auth + MIME + size  
2. **`StoragePathBuilder`** derives key — client does **not** supply arbitrary paths  
3. **`putFile`** to Spaces  
4. **`publicUrl($key)`** → persist on row / return in JSON  

**Presigned PUT/POST, direct browser→Spaces, and embedded Spaces keys** are **forbidden** ([ADR-002](../../decisions/ADR-002-laravel-only-storage-writes.md)).

---

## Public read / private write model

| Operation | Who | How |
| --- | --- | --- |
| **Write (`put`)** | Laravel only | `DO_SPACES_KEY` / `DO_SPACES_SECRET` via S3 API to **origin** |
| **Delete** | Laravel only | After **`StorageAssetReferenceService`** exact-URL checks |
| **Read** | Anyone with URL | **HTTPS GET** to **CDN URL** — no Firebase token, no Spaces secret on asset GET |

**Bucket ACL:** OpenTofu sets **`acl = "private"`** on the bucket resource. Laravel uploads use **`visibility => 'public'`** on object put (Flysystem) so objects are reachable through the **Spaces CDN** public URL model — clients still never receive write credentials.

**Trust boundary:** Authorization for **who may upload or change metadata** is entirely on **Laravel API routes** (Firebase Bearer + policies). The CDN URL itself is a **capability to read bytes** for that object path — catalog design assumes **non-guessable entity-scoped keys**, not secret URLs.

---

## Object key stability expectations

Canonical keys are **entity-scoped** and **deterministic** from entity id, asset slot, and validated extension ([`storage-strategy.md`](storage-strategy.md)):

```
sounds/{sound_id}/audio/original.{ext}
sounds/{sound_id}/thumbnail/thumbnail.{ext}
covers/{cover_bundle_id}/artwork/artwork.{ext}
…
```

| Stability case | Object key | CDN URL string |
| --- | --- | --- |
| **First upload** | New key under entity id | New **`publicUrl()`** persisted |
| **Replace file, same extension** | Same key path | **Same URL string** (in-place overwrite at origin) |
| **Replace file, different extension** | **New key** (extension in path) | **New URL string** — row must update |
| **Entity delete** | Key removed only when URL **unreferenced** | Row gone; URL string may still exist on other rows if shared |

**Extension in the key** is intentional: MIME validation picks **`original.mp3`** vs **`original.wav`**, etc. Replacing format changes the **canonical URL** — plan for offline re-download and reference updates.

**Copy semantics:** Preset import and cover apply **copy URL strings** onto vibe rows — multiple rows may reference the **same exact CDN URL**. Keys are not duplicated in storage until a future “fork bytes to `vibes/{id}/…`” feature exists.

---

## Immutable CDN URL expectations

“Ixora CDN URLs” are **stable for the lifetime of that object identity**, not cryptographic immutability.

### What “stable” means today

| Consumer | Expectation |
| --- | --- |
| **Mobile streaming** | **`layer.fileUrl`** from API is the playback URL — unchanged until API row changes |
| **Offline manifest** ([ADR-004](../../decisions/ADR-004-offline-audio-strategy.md)) | **`remoteUrl === layer.fileUrl.trim()`** (exact string) to use **`file://`** |
| **Safe deletion** | **`StorageAssetReferenceService`** counts rows where column **equals URL string** |
| **Admin previews** | `<img :src="entity.thumbnail_url">` — opaque HTTPS |

### What is explicitly not shipped

| Pattern | Status |
| --- | --- |
| **Signed CDN URLs** | **Not used** |
| **Short-lived query tokens** | **Not used** on asset paths |
| **Content-addressed hashes in URL** | **Not used** (entity id paths instead) |
| **Automatic URL rotation** | **None** |

### Identity change = new bytes or new path

- **Same URL, new bytes** (in-place overwrite): possible when key unchanged; see **stale CDN** below.  
- **New URL string** (extension change, key version bump, manual paste of different URL on PATCH): offline manifests **miss** until user re-downloads; reference counts treat old and new as **different strings**.

---

## Why URLs are persisted as full HTTPS strings

| Reason | Detail |
| --- | --- |
| **Opaque client contract** | Admin and mobile use URLs **as returned** — no bucket parsing ([`mobile-cdn-validation.md`](mobile-cdn-validation.md)) |
| **Exact reference matching** | Deletion safety compares **string equality** across `sounds`, `cover_bundles`, `vibes`, `users` columns |
| **Legacy coexistence** | Firebase URLs and Spaces CDN URLs sit side by side in the same columns during migration |
| **API resources** | [`api-resource-patterns.md`](../../standards/api-resource-patterns.md) — return stored URLs; **no signed URL machinery** |
| **CDN vs origin** | Single env var switch (`DO_SPACES_CDN_URL`) without rewriting all keys in DB |
| **Offline manifests** | Store **`remoteUrl`** as full string for deterministic match |

Relative paths, storage keys only in DB, or client-side URL assembly are **out of policy** for product flows.

---

## Exact URL matching for offline manifests

From [ADR-004](../../decisions/ADR-004-offline-audio-strategy.md) and [`mobile-cdn-validation.md`](mobile-cdn-validation.md):

```
resolvePlaybackAssetUrl(layer):
  if manifest[vibeId:soundId].remoteUrl === layer.fileUrl.trim()
     and file exists on disk
    → use file://
  else
    → HTTPS CDN (streaming; SimpleCache best-effort only)
```

| Rule | Implication for CDN policy |
| --- | --- |
| **Exact string match** | Whitespace, scheme, host, path must match what API stored |
| **No signed URLs** | Manifests remain valid until API changes the stored string |
| **URL change on server** | User must **re-download for offline** — no automatic sync |
| **Firebase legacy URL** | Still works online if HTTPS reachable; offline download keys on that exact string |

**Policy alignment:** prefer **stable `file_url`** over frequent URL churn; when URL must change, treat it as a **product-visible** offline invalidation event.

---

## Cache header philosophy

**Shipped today:** Laravel **`putFile`** does **not** set custom **`Cache-Control`**, **`ETag`**, or **`Expires`** metadata in application code. Behaviour relies on:

- DigitalOcean Spaces object defaults  
- Spaces CDN edge caching defaults  

| Principle | Rationale |
| --- | --- |
| **Prefer stable URLs over cache tricks** | Offline and deletion logic key on URL strings — query-string cache busting is **not** standard today |
| **Long-lived catalog assets** | Sounds and cover art are referenced from many clients; CDN caching is **desirable** for egress and latency |
| **In-place overwrite risk** | Same URL + new bytes may leave **stale bytes at CDN edge** until TTL expires — see operational section |
| **No app middleware on CDN** | No CloudFront/Lambda@Edge-style header injection |

Future derivatives ([`future-processing-pipeline.md`](future-processing-pipeline.md)) may introduce explicit **`Cache-Control`** or versioned keys — **planning only**; would require updating this doc and mobile validation when implemented.

---

## CDN invalidation expectations

| Expectation | Current state |
| --- | --- |
| **Automated purge API** | **Not shipped** — no Laravel job, no DO CDN purge integration in codebase |
| **Deploy invalidation** | App/admin deploy **does not** invalidate media CDN objects ([`deploy-pipeline.md`](../backend/deploy-pipeline.md)) |
| **Delete invalidation** | **`SafeAssetDeletionService`** removes origin object; CDN may briefly 404 or serve stale until edge TTL — acceptable today |
| **Replace same URL** | Operator accepts possible **stale CDN** until natural expiry; no forced purge workflow documented in code |

**Operational stance:** if stale bytes after in-place replace block QA, wait for CDN TTL, rename key (new URL + DB update), or use DigitalOcean console/tools **manually** — not part of the product pipeline.

**Not used:** CloudFront invalidation paths, multi-CDN purge orchestration, signed URL rotation as invalidation substitute.

---

## Deletion and reference safety

Object delete is **irreversible**. Laravel enforces **reference-safe** deletion ([`storage-strategy.md`](storage-strategy.md)):

```
deleteUrlWithStatus(url):
  key = keyFromUrl(url)
  if key is null → skip (external / Firebase URL)
  if countReferencesToUrl(url) > 0 → skip
  else spaces.delete(key)
```

| Status | Meaning |
| --- | --- |
| **`skipped_external_url`** | Not a configured Spaces CDN/origin URL (e.g. Firebase) |
| **`skipped_still_referenced`** | Another row stores the **same exact string** |
| **`deleted`** | Origin object removed |
| **`failed`** | SDK delete failed — row may already be gone |

**Rules:**

- Match on **full URL string**, not inferred path from entity id alone  
- Shared cover URLs on vibes **block** deleting bundle-owned keys until unreferenced  
- Sound delete blocked when attached to vibes or preset vibes — URLs retained  

**Firebase URLs:** never deleted via Spaces SDK — migration project replaces row strings separately.

---

## Old Firebase URLs coexistence during migration

| Topic | Policy |
| --- | --- |
| **New writes** | Laravel → Spaces → **CDN hostname** only |
| **Legacy rows** | May still hold `firebasestorage.googleapis.com` (or similar) HTTPS URLs |
| **Mobile/admin read** | Treat any API HTTPS URL as **opaque** — no host whitelist required for product flows |
| **Safe delete** | **`keyFromUrl`** returns null → **no Spaces delete** for Firebase hosts |
| **Migration** | Separate project: inventory, backup, re-upload, row update — **not** automatic in upload specs |

Both URL families may appear in staging QA simultaneously ([`mobile-cdn-validation.md`](mobile-cdn-validation.md)).

---

## No client-side bucket parsing assumptions

| Client | Rule |
| --- | --- |
| **Admin** | Display and submit URLs from API; **no `DO_SPACES_*`** in Nuxt env |
| **Mobile** | `fileUrl`, `thumbnail_url`, etc. passed to `<img>`, CSS, native audio, **`CapacitorHttp`** — **no key extraction** for normal flows |
| **Server** | **`keyFromUrl()`** may parse CDN/origin URLs for delete/reference — **not exposed to clients** |

**Forbidden client patterns:**

- Building `https://{bucket}.{region}.cdn.digitaloceanspaces.com/...` from env  
- Stripping CDN host to “normalize” URLs (breaks offline exact match)  
- Assuming all assets share one file extension or path template for UI logic  

The only mobile code that inspects URL shape today is **operational** (e.g. **`guessAudioExtension`** for offline file extension from URL + `Content-Type`) — not bucket policy.

---

## Operational expectations

### Replacing assets

| Flow | Behaviour |
| --- | --- |
| **Admin upload to existing entity** | `POST /api/admin/uploads` → **`putFile`** at canonical key → returns new **`publicUrl()`** → form PATCHes entity column |
| **Same slot, same extension** | Overwrites object at **same key** → **same URL string** in DB if admin saves returned URL |
| **Same slot, new extension** | **New key + new URL** — must update DB; old key orphaned unless safe-delete runs after reference drop |
| **Metadata-only PATCH with pasted URL** | Allowed on some entities (e.g. sound **`file_url`**) — operator responsible for valid HTTPS URL; safe-delete still classifies Spaces vs external |

After replace with **same URL string**, expect possible **stale CDN edge content** until cache expires.

### Stale CDN concerns

| Scenario | Risk | Mitigation today |
| --- | --- | --- |
| In-place overwrite, same URL | Edge serves old bytes | Wait TTL; or change key/URL; manual DO purge if urgent |
| DB URL updated, object deleted | 404 at old URL | Correct — clients should use new API JSON |
| Offline manifest old URL | Playback falls back to HTTPS or fails offline | User re-download ([ADR-004](../../decisions/ADR-004-offline-audio-strategy.md)) |

### Asset retention

| State | Retention |
| --- | --- |
| **Active row with URL** | Object should exist at key derived from URL (Spaces or legacy external) |
| **Row deleted, URL unreferenced** | Laravel attempts Spaces delete |
| **Row deleted, URL still referenced** | Object **retained** |
| **Failed upload transaction** | Create actions delete partial keys on rollback ([`upload-validation.md`](../../standards/upload-validation.md)) |
| **Orphan keys** | Possible after manual ops or future async jobs — **no shipped inventory command** (noted in storage strategy) |

### Safe deletion constraints

Before **`spaces.delete`:**

1. URL must map to configured bucket (**not Firebase external**)  
2. **`countReferencesToUrl(url) === 0`** after owning row removed  
3. Sound: not used on vibes / preset vibes (delete blocked earlier)  
4. Cover bundle: delete blocked when presets reference bundle; URL shared on vibes blocks key removal  

See [`storage-strategy.md`](storage-strategy.md) for entity-specific rules.

### Future derivative compatibility

[`future-processing-pipeline.md`](future-processing-pipeline.md) (planning) may add derived keys (`playback.mp3`, resized WebP). Policy constraints that **must carry forward**:

| Constraint | Why |
| --- | --- |
| **Laravel-only writes** | Same credential boundary |
| **`file_url` as canonical client URL** | Mobile execution plan + offline manifests |
| **Atomic URL publish** | Avoid broken pointers mid-job |
| **Reference-checked delete** | Derived keys garbage-collected like originals |
| **URL change invalidates offline** | Same as today — document in release notes |

Versioned keys vs in-place replace and **`Cache-Control`** remain **TBD** at implementation time.

---

## Rules

1. **Persist CDN hostname URLs** for new Spaces assets — never origin URLs in client-facing columns.  
2. **Generate URLs only in Laravel** via **`publicUrl()`** after validated upload.  
3. **Do not ship signed or expiring asset URLs** without a new ADR and mobile/offline spec updates.  
4. **Treat stored URL strings as identity** for references and offline manifests — change deliberately.  
5. **Never delete Spaces objects** without **`StorageAssetReferenceService`** exact-string check.  
6. **Skip Spaces delete** for non-bucket (Firebase) URLs — migration handles those rows.  
7. **Clients consume opaque HTTPS URLs** — no bucket parsing, no URL construction.  
8. **Do not assume CDN purge** — plan for TTL/stale edge after in-place replace.  
9. **Do not introduce CloudFront, second CDN, or multi-region asset routing** without ADR + infra spec.  

---

## Validation

### Code / review

- [ ] New upload paths call **`publicUrl()`** and persist CDN host  
- [ ] API resources return URL columns unchanged (full HTTPS strings)  
- [ ] No **`DO_SPACES_*`** in admin/mobile repos  
- [ ] Delete paths use **`SafeAssetDeletionService`** / reference service  
- [ ] No presigned GET/PUT for catalog assets  

### Staging manual

- [ ] Create sound/cover → URLs start with **`DO_SPACES_CDN_URL`** host  
- [ ] Asset loads in admin `<img>` and mobile device build  
- [ ] Delete unreferenced catalog entity → object gone at origin; shared URL survives when second row references it  
- [ ] Offline download + play with CDN **`file_url`** ([`mobile-cdn-validation.md`](mobile-cdn-validation.md))  

### Policy review triggers

Update this doc when changing: CDN hostname env, URL persistence shape, cache/invalidation strategy, offline matching rules, or Firebase migration completion.

---

## Related documentation

| Document | Relationship |
| --- | --- |
| [`storage-strategy.md`](storage-strategy.md) | **Parent** — access, layout, deletion, migration scope |
| [ADR-002](../../decisions/ADR-002-laravel-only-storage-writes.md) | Laravel-only write/delete authority |
| [ADR-004](../../decisions/ADR-004-offline-audio-strategy.md) | Exact **`remoteUrl`** match for offline |
| [`mobile-cdn-validation.md`](mobile-cdn-validation.md) | Device QA, opaque HTTPS, CDN smoke tests |
| [`future-processing-pipeline.md`](future-processing-pipeline.md) | **Planning** — derivatives, versioning, cache headers TBD |
| [`upload-validation.md`](../../standards/upload-validation.md) | Multipart upload + **`publicUrl()`** flow |
| [`../backend/staging-digitalocean.md`](../backend/staging-digitalocean.md) | `DO_SPACES_*` on App Platform |
| [`../backend/deploy-pipeline.md`](../backend/deploy-pipeline.md) | Deploy does not invalidate media CDN |

When CDN policy changes, update **this file first**, then sync [`storage-strategy.md`](storage-strategy.md) and affected ADRs/specs in the same change set.
