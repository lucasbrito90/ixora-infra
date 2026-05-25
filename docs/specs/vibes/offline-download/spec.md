# Offline Download — guaranteed offline vibe playback

**Status:** Active feature specification (source of truth)  
**Version:** 2.0 (consolidated; matches current `front_vibes` native implementation)  
**Feature ID:** `vibes/offline-download`  
**Platform:** Mobile native only (`front_vibes` on Android/iOS installable builds)

---

## Goal

Enable an **authenticated mobile user** on a **native install** to **explicitly download** a vibe’s playable sound layers for **guaranteed offline playback**: full audio files on disk, a manifest mapping layers to remote URLs, and a **vibe metadata snapshot** so the player can rebuild the execution plan without calling the API.

**Success criteria:**

- Offline full-file download is triggered only by an **explicit “Download for offline”** user action — not automatic on play or stream.
- Downloads use **`CapacitorHttp.request()`** (native HTTP) + **`Filesystem.writeFile()`** — **not** WebView **`fetch()`**.
- Audio bytes live under **`Directory.Data/offline_audio/`** with manifest **`ixora_offline_audio_manifest_v1`** in **`@capacitor/preferences`**.
- Vibe plan + UI metadata live in **`offline_vibe_manifest_v1`** after a **successful** download batch (**`failed === 0`**, **`succeeded > 0`**).
- Playback resolves to **`file://`** only when manifest **`remoteUrl` exactly equals** **`layer.fileUrl`** and the file exists; otherwise **HTTPS CDN** fallback.
- **`NativeAudio.preload()`** prepares playback — **not** offline download.
- **ExoPlayer SimpleCache** is **best-effort streaming only** — separate from guaranteed offline.
- **Live reload** (`ionic capacitor run … -l`) is **invalid** for offline QA.
- **Backend unchanged** — no offline sync endpoints; mobile consumes **stable HTTPS CDN URLs** from existing API responses.

---

## Scope

### In scope

- **Explicit download** from **VibePlayerPage** overflow menu (⋮) → **Download for offline**.
- **Remove offline download** — deletes audio files, audio manifest rows, and vibe snapshot for that vibe.
- **Native download pipeline:** `CapacitorHttp.request()` → base64 body → `Filesystem.writeFile()` → audio manifest update.
- **Metadata snapshot:** vibe fields + `VibeSound[]` for offline **`buildVibeExecutionPlan`** via **`buildPlan()`**.
- **Playback resolution:** `AudioEngine.resolvePlaybackAssetUrl()` → offline `file://` or HTTPS fallback.
- **Offline player hydration** on mount when API sounds unavailable.
- **Settings** — offline download list, remove per vibe, **Clear streaming cache** (ExoPlayer only).
- **Vibes list badge** — “Available offline” when snapshot exists.
- **Platform guard:** native only — browser shows informative toast, no download.

### Out of scope

- **Backend offline API**, sync endpoints, or push reconciliation — **`back_vibes` has no offline routes**.
- **Automatic background sync** when server data changes.
- **Delta / partial-file downloads**, resume queues, or download managers.
- **Offline vibe browse** without prior download — list screens still need network unless separately cached; only the **player** for a **previously downloaded** vibe is supported offline.
- **Cover / artwork byte download** — visual URLs remain HTTPS strings in snapshot (WebView may fail to load images offline).
- **Web/PWA offline download** — not supported.
- **Admin (`ixora-admin`)** offline flows.
- **`NativeAudio.preload()`** as full-file persistence.
- **WebView `fetch()`** for audio bytes.
- **ExoPlayer SimpleCache** as offline guarantee.
- **Presigned URLs**, **DRM**, **cloud sync**, **transcoding** pipelines.
- **Seamless offline reconciliation** when vibe layers change on server without re-download.

---

## Actors

| Actor | Role |
| --- | --- |
| **End user** | Triggers **Download for offline** while online on a native build; plays vibe in airplane mode after success. |
| **Mobile app (`front_vibes`)** | Downloads layers, writes manifests, resolves playback URLs, hydrates player offline. |
| **Laravel API (`back_vibes`)** | **Unchanged for offline** — serves stable **`file_url`** / CDN HTTPS URLs when online; no offline-specific endpoints. |
| **Capacitor native stack** | **`CapacitorHttp`**, **`Filesystem`**, **`Preferences`**. |
| **`AudioEngine` / `nativeAudioEngine`** | `cacheVibeAudio`, `resolvePlaybackAssetUrl`, `clearAudioCache`. |
| **`@capgo/native-audio` / ExoPlayer** | Streaming playback + optional LRU SimpleCache — **not** the offline download primitive. |

---

## User Journey

### Download (online, native app)

1. User opens a vibe on **VibePlayerPage** (online) with playable layers in the execution plan.
2. User opens overflow menu (⋮) → **Download for offline**.
3. App validates: native platform, **`navigator.onLine`**, playable layers exist.
4. App calls **`playerStore.cacheVibeAudio(vibeId, executionPlan)`** → per-layer **`CapacitorHttp.request()`** + **`Filesystem.writeFile`** under **`Directory.Data/offline_audio/`**.
5. Each success updates **`ixora_offline_audio_manifest_v1`** entry **`vibeId:soundId`** → `{ relativePath, remoteUrl, savedAt }`.
6. If **`failed === 0`** and **`succeeded > 0`**, **VibePlayerPage** saves **`offline_vibe_manifest_v1`** snapshot (vibe meta + `vibeSounds[]`).
7. Toast **“Downloaded for offline”**; UI shows **Available offline** state.

### Play offline

1. User enables airplane mode (or loses network).
2. User opens the **same vibe** player route.
3. **`onMounted`**: parallel **`GET /api/vibes/:id`** + **`GET …/sounds`**. If API returns sounds → **`buildPlan()`** from API. If sounds missing → **`getOfflineVibeSnapshot(vibeId)`** → hydrate vibe + sounds → **`buildPlan()`**.
4. **Play** uses **`resolvePlaybackAssetUrl`**: when **`entry.remoteUrl === layer.fileUrl.trim()`** and file exists → **`file://`** via **`Filesystem.getUri`**; otherwise HTTPS (likely fails offline).
5. Playback orchestration follows normal runtime: [`playback-runtime/spec.md`](../playback-runtime/spec.md).

### Stale snapshot / server changes

- User edits vibe layers online (attach/detach, volume, URLs) **without** re-downloading → offline snapshot and audio manifest remain **previous download state**.
- If **`file_url`** changes on server → manifest **`remoteUrl !== layer.fileUrl`** → HTTPS fallback until user **Download for offline** again successfully.
- **Re-download** overwrites per-layer audio manifest entries and replaces snapshot **only** when **`failed === 0`**.

### Remove download

- **VibePlayerPage** menu or **Settings** → **Remove offline download** → **`removeDownloadedVibe(vibeId)`**: deletes `offline_audio` files, audio manifest rows, and vibe snapshot.

### Not available offline

- Vibe never downloaded → toast **“This vibe is not available offline.”**
- Partial download (`failed > 0`) → **no snapshot saved**; partial audio files may exist on disk without consistent offline plan.

---

## Related Domain Model

```
Online API (unchanged)              Mobile (native only)
──────────────────────              ────────────────────
GET /api/vibes/:id                  VibePlayerPage UI fields
GET /api/vibes/:id/sounds    ──►    vibeSounds[] → buildVibeExecutionPlan()
  └── sounds.file_url (CDN HTTPS)         │
                                          │ explicit "Download for offline"
                                          ▼
                               ┌──────────────────────────────────────┐
                               │ ixora_offline_audio_manifest_v1       │
                               │   key: vibeId:soundId                 │
                               │   → { relativePath, remoteUrl, savedAt }│
                               └─────────────────┬────────────────────┘
                                                 │
                               Directory.Data/offline_audio/
                                 vibe_{id}/sound_{soundId}.{ext}
                                                 │
                               ┌─────────────────▼────────────────────┐
                               │ offline_vibe_manifest_v1              │
                               │   vibe meta + VibeSound[] snapshot    │
                               └──────────────────────────────────────┘

Playback: entry.remoteUrl === layer.fileUrl.trim() ? file:// : HTTPS
```

| Store | Key / path | Contents |
| --- | --- | --- |
| **Audio manifest** | Preferences **`ixora_offline_audio_manifest_v1`** | Map **`vibeId:soundId`** → `{ relativePath, remoteUrl, savedAt }` |
| **Audio files** | **`Directory.Data/offline_audio/vibe_{vibeId}/sound_{soundId}.{ext}`** | Full-file binary per layer |
| **Vibe snapshot** | Preferences **`offline_vibe_manifest_v1`** | `{ version: 1, vibes: { "<id>": { vibeId, downloadedAt, vibe, vibeSounds } } }` |
| **Streaming cache (separate)** | `getCacheDir()/media` | ExoPlayer SimpleCache — **best-effort**, not offline guarantee |

**CDN URLs remain canonical identity:** manifest matching uses the **exact HTTPS string** returned as **`layer.fileUrl`** (from catalog **`sounds.file_url`**). No separate offline asset IDs.

**Backend:** no `offline_*` tables, no sync webhooks. Layer changes: [`manage-vibe-sounds/spec.md`](../manage-vibe-sounds/spec.md).

---

## Functional Requirements

| ID | Requirement |
| --- | --- |
| FR-1 | **Download for offline** is **user-initiated only** — no silent full-file download on play or preload. |
| FR-2 | Download runs **only on native** (`Capacitor.isNativePlatform()`). |
| FR-3 | Download requires **network** (`navigator.onLine`) at start. |
| FR-4 | Each playable layer with **HTTPS `fileUrl`** is downloaded via **`CapacitorHttp.request({ method: 'GET', responseType: 'blob' })`**. |
| FR-5 | Response body written with **`Filesystem.writeFile({ directory: Directory.Data, path, data: base64, recursive: true })`** — **no** `encoding` option (binary-safe base64 decode). |
| FR-6 | **Do not** use WebView **`fetch()`** for offline audio bytes. |
| FR-7 | **Do not** use **`NativeAudio.preload()`** as download or full-file persistence. |
| FR-8 | After each layer success, update **`ixora_offline_audio_manifest_v1`** with **`remoteUrl`** = trimmed **`layer.fileUrl`**. |
| FR-9 | Save **`offline_vibe_manifest_v1`** only when **`failed === 0`** and **`succeeded > 0`** (handled in **VibePlayerPage** after `cacheVibeAudio`). |
| FR-10 | **`resolvePlaybackAssetUrl`** returns local URI only if **`entry.remoteUrl === currentRemoteUrl.trim()`** (exact string) and **`Filesystem.stat`** succeeds. |
| FR-11 | Otherwise playback uses remote **`layer.fileUrl`** (HTTPS) — may use ExoPlayer streaming cache **online only** (best-effort). |
| FR-12 | **`clearAudioCache()`** clears ExoPlayer **`getCacheDir()/media`** only — **does not** delete **`offline_audio/`** or Preferences manifests. |
| FR-13 | **`removeDownloadedVibe`** clears audio files, audio manifest rows, and vibe snapshot for that vibe. |
| FR-14 | **Backend unchanged** — no new endpoints; stable CDN URLs in API responses are the mobile dependency. |
| FR-15 | **Live reload** dev builds are **not valid** for offline QA — use installable build without `-l`. |
| FR-16 | Offline player rebuilds plan via **`buildVibeExecutionPlan(vibeSounds)`** — same function as online ([`playback-runtime/spec.md`](../playback-runtime/spec.md)). |
| FR-17 | **`audioPlayerService.setPlaybackVibeContext(vibeId)`** must be set before preload/play so URL resolution uses correct vibe id. |
| FR-18 | Snapshot **not** updated when server vibe changes until user successfully downloads again. |
| FR-19 | **No presigned URLs**, **no direct Spaces access**, **no transcoding** on download path. |
| FR-20 | **No background sync engine** — no queued reconciliation with server state. |

---

## Validation Rules

### Download preconditions (client)

| Check | Failure behaviour |
| --- | --- |
| **`Capacitor.isNativePlatform()`** | Toast: available in installed app only |
| **`navigator.onLine`** | Toast: connect to internet |
| **`executionPlan.length > 0`** and **`hasPlayableLayers`** | Toast: no sounds to download |
| **`layer.fileUrl`** starts with `http://` or `https://` | Layer **`skipped`** (not **`failed`**) |
| HTTP 2xx + non-empty base64 body | Layer success |
| HTTP error / timeout / invalid body | Layer **`failed`** |

### Per-layer timeouts (native HTTP)

| Setting | Value |
| --- | --- |
| Connect timeout | **30 s** |
| Read timeout | **180 s** |

### Snapshot write gate

| Condition | Snapshot saved? |
| --- | --- |
| **`failed === 0`** and **`succeeded > 0`** | **Yes** |
| **`failed > 0`** (any layer) | **No** — even if some layers succeeded |
| **`succeeded === 0`** | **No** |

### Playback URL resolution

| Condition | Resolved URL |
| --- | --- |
| Native + `vibeId > 0` + manifest entry + **`remoteUrl === layer.fileUrl.trim()`** + file exists | **`file://`** (`Filesystem.getUri`) |
| Otherwise | **`layer.fileUrl`** (HTTPS CDN) |

### Backend (online only — unchanged)

| Endpoint | Role for offline |
| --- | --- |
| **`GET /api/vibes/{id}`** | Vibe metadata when online; snapshot substitutes offline |
| **`GET /api/vibes/{id}/sounds`** | Layer config + **`file_url`** when online; snapshot substitutes offline |

No offline-specific validation on server.

---

## API Contract

**There are no offline download endpoints.** Offline is **100% client-side** persistence of data already returned by existing authenticated read APIs.

### APIs consumed while online (before / during download)

| Method | Path | Auth | Used for |
| --- | --- | --- | --- |
| `GET` | `/api/vibes/{id}` | `firebase.auth` | Vibe metadata for UI + snapshot |
| `GET` | `/api/vibes/{id}/sounds` | `firebase.auth` | `VibeSound[]` → execution plan + snapshot |

### Backend responsibilities (implicit contract)

| Requirement | Reason |
| --- | --- |
| **`sounds.file_url`** is **stable public HTTPS CDN URL** | Manifest match uses **exact string equality** |
| URLs reachable via **native GET** while online | **`CapacitorHttp.request()`** download |
| **Byte-range** support on CDN (online streaming) | ExoPlayer progressive play — separate from offline |
| **No presigned / expiring URLs** on playback paths | Predictable manifest keys |
| **No Spaces credentials** in mobile | Public HTTPS only |

When offline, these endpoints may fail — mobile falls back to **`offline_vibe_manifest_v1`** for plan rebuild. Audio bytes come from **`Directory.Data/offline_audio/`**, not API.

---

## Download Pipeline

### Entry point

| Step | Component |
| --- | --- |
| UI | **`VibePlayerPage.vue`** → **`handleDownloadForOffline`** |
| Store | **`playerStore.cacheVibeAudio(vibeId, executionPlan)`** |
| Engine | **`nativeAudioEngine.cacheVibeAudio`** → **`downloadLayerForOffline`** |

### Per-layer algorithm (`downloadLayerForOffline`)

1. Require native platform (throws if browser — caught as **`failed`** at engine layer).
2. `remoteUrl = layer.fileUrl.trim()`.
3. **`CapacitorHttp.request`** GET, `responseType: 'blob'`, connect **30s**, read **180s**.
4. Validate HTTP 2xx; body non-empty **string** (base64 on native).
5. Guess extension from `Content-Type` or URL path via **`guessAudioExtension`** (default `.audio`).
6. **`Filesystem.writeFile({ directory: Directory.Data, path: offline_audio/vibe_{vibeId}/sound_{soundId}{ext}, data: base64, recursive: true })`**.
7. Read/modify/write **`ixora_offline_audio_manifest_v1`** key **`${vibeId}:${soundId}`**.

### Batch result (`CacheVibeResult`)

| Status | Meaning |
| --- | --- |
| **`cached`** | Layer downloaded + manifest updated |
| **`skipped`** | Non-HTTPS URL or non-native platform |
| **`failed`** | HTTP/IO/validation error |

### Snapshot write (`saveOfflineVibeSnapshot`)

Called from **VibePlayerPage** (not inside `cacheVibeAudio`) when batch succeeds with zero failures. Copies **`vibeToOfflineMeta(vibe)`** + shallow copy of **`vibeSounds[]`** into **`offline_vibe_manifest_v1`**.

### Relationship with `buildVibeExecutionPlan`

- Download uses **current `executionPlan`** layers (already built from online **`vibeSounds`**).
- Snapshot stores **`vibeSounds[]`** in API shape so offline **`buildPlan()`** → **`buildVibeExecutionPlan`** produces the **same plan structure** as online (including **`layer.fileUrl`** strings used for manifest match).

---

## Playback Resolution Rules

### Resolution chain

```
audio-player.service._resolvedAssetPath(layer)
  → audioEngine.resolvePlaybackAssetUrl(layer, playbackVibeId)
    → getOfflinePlaybackUriIfValid(vibeId, soundId, layer.fileUrl)
      → entry.remoteUrl === layer.fileUrl.trim() && stat OK ?
           Filesystem.getUri → file://
         : null
  → return uri ?? layer.fileUrl
```

### Exact URL matching rule

```typescript
entry.remoteUrl !== currentRemoteUrl.trim()  →  no local file (HTTPS fallback)
```

**CDN URL string is identity.** Path, host, or query change on server → offline **`file://`** disabled until re-download with matching URLs.

### Relationship with `AudioEngine` and `NativeAudio.preload`

| Step | Component | Role |
| --- | --- | --- |
| URL resolve | **`AudioEngine.resolvePlaybackAssetUrl`** | Choose **`file://`** or HTTPS **before** preload |
| Preload | **`NativeAudio.preload({ assetPath: resolvedUrl, isUrl: true })`** | Load asset into ExoPlayer for **playback session** — **not** download |
| Play / loop | **`NativeAudio.play` / `loop`** | Normal runtime ([`playback-runtime/spec.md`](../playback-runtime/spec.md)) |

**`NativeAudio.preload()` is NOT download.** It prepares the resolved URI (local or remote) for the current session. Full-file persistence happens only via **`downloadLayerForOffline`**.

Fade fields in plan are **ignored at runtime** — offline does not change that ([`audio-engine-fade-limitations.md`](../../../architecture/audio/audio-engine-fade-limitations.md)).

---

## Offline Manifest Rules

### Audio manifest — `ixora_offline_audio_manifest_v1`

| Property | Rule |
| --- | --- |
| Storage | **`@capacitor/preferences`** single JSON object |
| Key format | **`${vibeId}:${soundId}`** via **`offlineAudioKey()`** |
| Entry shape | `{ relativePath, remoteUrl, savedAt }` |
| **`remoteUrl`** | Trimmed **`layer.fileUrl`** at download time |
| **`relativePath`** | e.g. **`offline_audio/vibe_12/sound_5.mp3`** (under **`Directory.Data`**) |
| Update timing | After **each** successful layer write |
| Remove | **`removeAllOfflineAudioForVibe`** deletes files + keys for vibe prefix |

### Vibe snapshot manifest — `offline_vibe_manifest_v1`

| Property | Rule |
| --- | --- |
| Storage | **`@capacitor/preferences`** |
| Top-level shape | `{ version: 1, vibes: Record<string, OfflineVibeSnapshot> }` |
| Snapshot shape | `{ vibeId, downloadedAt, vibe: OfflineVibeMeta, vibeSounds: VibeSound[] }` |
| **`vibeSounds`** | Same shape as **`GET /api/vibes/:id/sounds`** — feeds **`buildVibeExecutionPlan`** |
| **`OfflineVibeMeta`** | Subset of vibe fields for player UI (name, description, visual URLs, etc.) |
| Written when | **`failed === 0`** and **`succeeded > 0`** after download |
| Stale behaviour | **Not auto-updated** when server vibe/layers change — remains last successful download |
| Remove | **`removeOfflineVibeSnapshot(vibeId)`** on remove download |
| **`isVibeDownloaded` / list UIs** | Snapshot exists with **`vibeSounds.length > 0`** |

### Two-manifest requirement

Audio bytes alone are **insufficient** offline: **VibePlayerPage** must hydrate **`vibeSounds`** without API. Both manifests are required for guaranteed offline play.

---

## Cache Rules

### ExoPlayer SimpleCache (streaming — separate system)

| Property | Value |
| --- | --- |
| Location | **`getCacheDir()/media`** |
| Size | **100 MiB LRU** (mirrors `RemoteAudioAsset.MAX_CACHE_SIZE`) |
| Purpose | Progressive buffer during **HTTPS** streaming |
| Guarantee | **Best-effort only** — partial files, eviction under storage pressure |
| Cleared by | **`audioEngine.clearAudioCache()`** / Settings **Clear streaming cache** |
| **Not cleared by** | Remove offline download |

### Guaranteed offline storage

| Property | Value |
| --- | --- |
| Location | **`Directory.Data/offline_audio/`** |
| Written by | **`CapacitorHttp` + `Filesystem.writeFile`** only |
| Manifest | **`ixora_offline_audio_manifest_v1`** |
| Cleared by | **`removeDownloadedVibe`**, app uninstall, user clearing app data |
| **Not cleared by** | **`clearAudioCache()`** |

### HLS note

**`.m3u8`** streams use **`StreamAudioAsset`** and **bypass** SimpleCache. Offline download targets **non-HLS HTTPS `file_url`** catalog assets.

Align with [`audio-cache.md`](../../../architecture/audio/audio-cache.md).

---

## Mobile UX Rules

| Rule | Detail |
| --- | --- |
| Menu location | **VibePlayerPage** overflow (⋮) |
| Labels | **Download for offline** / **Downloading…** / **Remove offline download** |
| Browser | Toast: offline download available in installed app only |
| Offline without snapshot | Empty state + toast **“This vibe is not available offline.”** |
| Partial failure | Toast with success/fail counts; **no** snapshot saved |
| Status chips | **Offline mode** (device offline), **Available offline** (downloaded) |
| **VibesPage** | Badge when vibe id in **`getDownloadedVibeIds()`** |
| **Settings** | Lists offline downloads; remove per row; explains streaming cache vs offline |
| **Clear audio cache** | Alert: *“Cached streamed audio will be deleted. Offline downloads are not removed.”* |
| **Play enabled offline** | When snapshot hydrates plan + **`hasPlayableLayers`** — not tied to network |

Visual assets (thumbnail, player background) in snapshot are **URL strings only** — may not render offline without separate WebView cache.

---

## Storage / CDN Rules

| Rule | Detail |
| --- | --- |
| Download source | **Public HTTPS `layer.fileUrl`** from API — typically **DO Spaces CDN** |
| **No direct Spaces access** | No bucket SDK, keys, or presigned PUT/GET on mobile |
| **No presigned URLs** | Stable public CDN URLs expected for manifest stability |
| **No transcoding** | Bytes stored as downloaded |
| File layout | **`Directory.Data/offline_audio/vibe_{vibeId}/sound_{soundId}.{ext}`** |
| Extension | From **`Content-Type`** or URL path — not client filename alone |
| CDN identity | **`remoteUrl` in manifest === `layer.fileUrl` trim** at playback time |
| Legacy Firebase HTTPS | Treated as opaque HTTPS — same rules if API still returns them |
| CORS | **Irrelevant** for download — **`CapacitorHttp`** bypasses WebView CORS |

Align with [`storage-strategy.md`](../../../architecture/storage/storage-strategy.md) and [`mobile-cdn-validation.md`](../../../architecture/storage/mobile-cdn-validation.md).

---

## Failure Cases

| Case | Expected behaviour |
| --- | --- |
| Not native (browser) | Toast; layers **`skipped`** / download aborted |
| Offline at download start | Toast: connect to internet |
| No playable layers | Toast: no sounds to download |
| HTTP error / timeout on layer | Layer **`failed`** |
| Any layer **`failed`** | **No** vibe snapshot; toast may report partial success |
| Partial success (`failed > 0`) | Some audio manifest entries may exist; **no** snapshot — inconsistent offline UX |
| All layers fail | Error toast; snapshot unchanged |
| API **`file_url`** changes after download | **`remoteUrl !== layer.fileUrl`** → HTTPS fallback; **re-download required** |
| Server layer config changes without re-download | **Stale snapshot** — offline plays old layer list/settings |
| File deleted manually on disk | **`stat`** fails → HTTPS fallback |
| Open undownloaded vibe offline | No snapshot → not available offline |
| Snapshot save throws after audio success | Audio on disk + manifest; snapshot missing — offline plan may fail |
| **`clearAudioCache()`** | Streaming cache cleared; offline files **kept** |
| **`removeDownloadedVibe`** | Files + both manifest entries for vibe removed |
| App data cleared / uninstall | All manifests + files gone — download again |
| Live reload dev build | **Unreliable** — not valid for offline sign-off |

---

## Security Rules

| Rule | Requirement |
| --- | --- |
| URLs | Download only **`layer.fileUrl`** from authenticated API-loaded execution plan — opaque HTTPS |
| **No bucket credentials** | Mobile never uses **`DO_SPACES_*`** |
| **No presigned secrets** | No short-lived signed URLs required for download path |
| Local storage | **`Directory.Data`** app sandbox — not shared across apps |
| Auth offline | Player may open offline without live token refresh; snapshot is local-only metadata |
| Download auth | Requires user to have loaded vibe online with valid Firebase session (implicit — no offline download without prior API data) |

---

## Future Considerations

| Topic | Notes |
| --- | --- |
| Re-download prompt | When online **`fileUrl`** differs from manifest **`remoteUrl`** |
| Offline vibe list UX | Browse downloaded vibes without network (partial today via Settings list) |
| Cover image byte cache | Separate from audio offline strategy |
| iOS parity | Same pipeline; validate on **installable iOS build** without live reload |
| Background download | **Not implemented** |

**Explicitly excluded (do not implement without new spec):** backend offline endpoints, sync queues, delta updates, partial/resume downloads, DRM, cloud sync, transcoding, WebView **`fetch()`** downloads, **`preload()`** as download, seamless server reconciliation.

---

## Related Docs

| Document | Path |
| --- | --- |
| **This spec** | `docs/specs/vibes/offline-download/spec.md` |
| Playback runtime | [`../playback-runtime/spec.md`](../playback-runtime/spec.md) |
| Manage vibe sounds | [`../manage-vibe-sounds/spec.md`](../manage-vibe-sounds/spec.md) |
| Create vibe | [`../create-vibe/spec.md`](../create-vibe/spec.md) |
| Audio cache architecture | [`docs/architecture/audio/audio-cache.md`](../../../architecture/audio/audio-cache.md) |
| Mobile CDN validation | [`docs/architecture/storage/mobile-cdn-validation.md`](../../../architecture/storage/mobile-cdn-validation.md) |
| Storage / CDN policy | [`docs/architecture/storage/storage-strategy.md`](../../../architecture/storage/storage-strategy.md) |
| Fade limitations | [`docs/architecture/audio/audio-engine-fade-limitations.md`](../../../architecture/audio/audio-engine-fade-limitations.md) |
| Upload validation (admin) | [`docs/standards/upload-validation.md`](../../../standards/upload-validation.md) |
| **front_vibes (repo copy)** | `docs/audio-cache.md`, `docs/mobile-cdn-validation.md` |
| **Implementation** | `src/services/audio-engine/offline-audio-storage.ts` |
| | `src/services/offline-vibe-cache.service.ts` |
| | `src/services/offline-downloads.service.ts` |
| | `src/services/audio-engine/native-audio.engine.ts` |
| | `src/services/audio-player.service.ts` |
| | `src/stores/player.store.ts` |
| | `src/views/VibePlayerPage.vue` |
| | `src/views/SettingsPage.vue` |
| | `capacitor.config.ts` |

### Manual validation (Android — installable build, **not live reload**)

1. `ionic build` → `npx cap sync android` → `npx cap run android` (**no** `-l`)
2. Online: open vibe → **Download for offline** → success toast
3. Airplane mode: reopen same vibe → **Play** enabled; audio from **`file://`**
4. Undownloaded vibe offline → **not available offline**
5. **Remove offline download** → files + snapshot cleared; online playback uses HTTPS
6. Settings → **Clear streaming cache** → offline downloads **retained**

**Logs:** `[AudioCache]` (download, manifest, URI resolve), `[OfflineVibe]` (snapshot save/remove).

When behaviour changes, update **this file first**, then sync [`audio-cache.md`](../../../architecture/audio/audio-cache.md) and implementation.
