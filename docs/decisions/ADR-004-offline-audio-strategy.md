# ADR-004: Guaranteed offline audio via explicit native download

## Status

**Accepted** — reflects the **current shipped architecture** in `front_vibes` (`offline-audio-storage.ts`, `offline-vibe-cache.service.ts`, `AudioEngine.cacheVibeAudio`).

## Date

2026-05-23

## Context

Ixora mobile plays catalog audio from **HTTPS CDN URLs** returned by Laravel. On Android, **`@capgo/native-audio`** / ExoPlayer also maintains a **transparent streaming disk cache** (`SimpleCache`, ~100 MiB LRU) during online playback. That cache improves repeat streaming but **does not guarantee** a complete file on disk — partial buffers, eviction, and non-HLS behaviour make it **unsuitable as an offline contract**.

Users expect **deterministic offline playback** after an explicit action: airplane mode, weak connectivity, or cold start without API access. The Capacitor WebView origin is typically **`https://localhost`**, so **WebView `fetch()`** to CDN hosts hits **CORS** constraints and is a poor download primitive.

The team needed a **second, explicit path** for guaranteed offline: native HTTP download, app-private filesystem writes, Preferences manifests, exact URL identity for playback resolution, and a **vibe metadata snapshot** so the execution plan can rebuild without the API — distinct from streaming cache and from **`NativeAudio.preload()`** (playback preparation only).

---

## Decision

**Guaranteed offline playback uses explicit native download + manifest persistence — not ExoPlayer SimpleCache, not WebView fetch, not preload-as-download.**

### Two-tier audio storage model

| Tier | Mechanism | Guarantee |
| --- | --- | --- |
| **Streaming cache** | ExoPlayer **`SimpleCache`** under **`getCacheDir()/media`** | **Best-effort only** — progressive buffer during HTTPS play; LRU eviction; not full-file |
| **Guaranteed offline** | **`CapacitorHttp.request()`** + **`Filesystem.writeFile()`** + Preferences manifests | **Full file** on disk after successful explicit download |

These tiers are **independent**. **`clearAudioCache()`** clears **only** SimpleCache — **not** `Directory.Data/offline_audio/`.

### Guaranteed offline pipeline (mandatory)

| Step | Component | Rule |
| --- | --- | --- |
| 1 | **User action** | **Download for offline** on native install — **not** automatic on play, stream, or background sync |
| 2 | **Download bytes** | **`CapacitorHttp.request()`** (native GET) → base64 → **`Filesystem.writeFile`** under **`Directory.Data/offline_audio/`** |
| 3 | **Audio manifest** | Preferences **`ixora_offline_audio_manifest_v1`**: key **`vibeId:soundId`** → `{ relativePath, remoteUrl, savedAt }` |
| 4 | **Metadata snapshot** | After **`failed === 0`** and **`succeeded > 0`**, save **`offline_vibe_manifest_v1`** (vibe UI fields + **`VibeSound[]`**) |
| 5 | **Playback resolve** | **`audioEngine.resolvePlaybackAssetUrl(layer, vibeId)`** |
| 6 | **`file://` use** | **Only** when manifest **`remoteUrl === layer.fileUrl.trim()`** (exact string) **and** file exists on disk |
| 7 | **Fallback** | Otherwise **HTTPS CDN** (SimpleCache may buffer — **not** offline guarantee) |

### Explicit prohibitions

| Pattern | Status |
| --- | --- |
| **Rely on ExoPlayer cache for offline** | **Rejected** as guarantee |
| **WebView `fetch()` for audio download** | **Forbidden** (CORS / reliability) |
| **Service worker / PWA cache for native offline audio** | **Not used** — native app path only |
| **Automatic background mirroring** of vibes or layers | **Not shipped** — no sync when server changes |
| **Streaming-to-offline magic** (play until “fully cached”) | **Rejected** — no implicit full-file promise |
| **`NativeAudio.preload()` as download** | **Forbidden** — preload prepares playback only |
| **Backend offline download API** | **None** — mobile uses existing HTTPS URLs when online |

### Offline snapshots are explicit

- **`offline_vibe_manifest_v1`** is written **only** after a **successful** download batch — not on import, not on play, not on API fetch alone.
- Snapshot is **not** updated when server layer config changes until user **re-downloads** successfully.
- Player hydrates from snapshot when API sounds unavailable — audio bytes alone are **insufficient** without plan data.

### Runtime identity

Playback and manifests key on:

- **`vibeId`** + catalog **`soundId`** (audio manifest)
- **`layer.fileUrl`** exact match to stored **`remoteUrl`**
- Same **`buildVibeExecutionPlan`** as online — offline changes **URL resolution**, not plan semantics ([`execution-plan/spec.md`](../specs/vibes/execution-plan/spec.md))

---

## Consequences

### Positive (motivations)

| Motivation | How explicit download delivers it |
| --- | --- |
| **Deterministic offline playback** | Full file on disk + manifest proof before **`file://`** |
| **WebView CORS limitations avoided** | Native HTTP stack, not cross-origin WebView fetch |
| **Native filesystem reliability** | **`Directory.Data`** binary writes under app sandbox |
| **Explicit user control** | User chooses which vibes to store; no silent background fill |
| **Predictable manifests** | Two Preferences documents with documented keys and shapes |
| **Stable runtime identity** | Exact URL match ties playback to downloaded bytes; **`soundId`** keys survive session |

### Negative (tradeoffs)

| Tradeoff | Impact |
| --- | --- |
| **Manual download flow** | User must tap **Download for offline** while online |
| **Stale manifests possible** | Layer edits or URL changes on server without re-download → old snapshot / mismatch |
| **Re-download required after changes** | **`remoteUrl !== layer.fileUrl`** → HTTPS fallback; offline play fails until fresh download |
| **Duplicated local storage** | Full files under **`offline_audio/`** plus ExoPlayer cache may both exist for same URL during online use |
| **Partial failure ambiguity** | **`failed > 0`** → no vibe snapshot; partial files may exist without coherent offline plan |
| **Native-only** | Browser / `ionic serve` does not support guaranteed offline download |
| **QA constraint** | Live reload invalid for offline validation — installable build required |

### Operational expectations

- **`AudioEngine.cacheVibeAudio`** / **`playerStore.cacheVibeAudio`** — only entry points for full-file download.
- **`setPlaybackVibeContext(vibeId)`** must be set before resolve so offline paths key correctly.
- Stable **Spaces CDN public URLs** from API align well with exact-match manifests ([`mobile-cdn-validation.md`](../architecture/storage/mobile-cdn-validation.md)).
- Backend **unchanged** for offline — no new routes; ADR-002 CDN URL policy still applies.

---

## Alternatives Considered

| Alternative | Why not chosen (for Ixora today) |
| --- | --- |
| **ExoPlayer SimpleCache only** | Partial/evicted buffers; no full-file or plan snapshot contract |
| **WebView `fetch()` downloads** | CORS from `https://localhost`; unreliable for CDN bytes |
| **Service worker caching** | PWA pattern; not primary Capacitor native offline strategy |
| **Automatic background mirroring** | Hidden mutations, stale/sync complexity, battery and storage cost — **explicitly out of scope** |
| **`NativeAudio.preload()` persistence** | Prepares decode pipeline; plugin does not guarantee complete file on disk |
| **Backend push / sync of offline bundles** | No offline API; mobile owns local manifests |
| **Assume play “fills” cache offline-ready** | Undeterministic; rejected as product guarantee |

---

## Related Docs

| Document | Relationship |
| --- | --- |
| [`../specs/vibes/offline-download/spec.md`](../specs/vibes/offline-download/spec.md) | **Feature spec** — user journey, manifests, failure cases |
| [`../specs/vibes/playback-runtime/spec.md`](../specs/vibes/playback-runtime/spec.md) | Playback stack — **`file://`** resolve, preload vs download |
| [`../architecture/audio/audio-cache.md`](../architecture/audio/audio-cache.md) | **Architecture detail** — two mechanisms, rules, validation |
| [`../architecture/storage/mobile-cdn-validation.md`](../architecture/storage/mobile-cdn-validation.md) | CDN URL stability and device QA |
| [`../specs/vibes/execution-plan/spec.md`](../specs/vibes/execution-plan/spec.md) | Offline URL identity + plan rebuild |
| [`../decisions/ADR-003-preset-import-independent-vibes.md`](ADR-003-preset-import-independent-vibes.md) | Imported vibes need per-vibe download — no auto-offline on import |
| [`../decisions/ADR-002-laravel-only-storage-writes.md`](ADR-002-laravel-only-storage-writes.md) | Mobile consumes HTTPS URLs only — no direct Spaces |

### Implementation reference (current)

| Artifact | Path |
| --- | --- |
| Native download + audio manifest | `front_vibes/src/services/audio-engine/offline-audio-storage.ts` |
| Vibe metadata snapshot | `front_vibes/src/services/offline-vibe-cache.service.ts` |
| Download orchestration | `front_vibes/src/services/offline-downloads.service.ts` |
| Engine facade | `front_vibes/src/services/audio-engine/native-audio.engine.ts` |
| Player UI | `front_vibes/src/views/VibePlayerPage.vue` |
| Settings / remove | `front_vibes/src/views/SettingsPage.vue` |
| Manifest keys | `ixora_offline_audio_manifest_v1`, `offline_vibe_manifest_v1` |

---

When offline strategy changes (e.g. background sync, delta downloads), supersede this ADR with a new numbered decision and update [`audio-cache.md`](../architecture/audio/audio-cache.md) and [`offline-download/spec.md`](../specs/vibes/offline-download/spec.md) in the same change set.
