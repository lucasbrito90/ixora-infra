# Audio cache — streaming buffer vs guaranteed offline

**Status:** Active architecture (source of truth)  
**Scope:** Mobile audio playback and offline downloads (`front_vibes`, Android primary)  
**Applies to:** `@capgo/native-audio` / ExoPlayer, Capacitor native HTTP, local filesystem

---

## Purpose

Define how Ixora handles **remote audio URLs** on mobile: what is cached automatically during streaming, what must be **downloaded explicitly** for guaranteed offline playback, and how the player resolves **`file://`** vs **HTTPS** without bypassing backend policy or using WebView CORS for bytes.

This document states **architecture and rules**. It does not specify UI copy or replace feature specs for the vibe player.

---

## Context

Catalog and vibe sounds are served as **public HTTPS URLs** from the Laravel API (typically **DigitalOcean Spaces CDN**). The mobile app does **not** access Spaces directly; it consumes the same stable CDN URLs the API returns in `layer.fileUrl` / sound resources.

On Android, `@capgo/native-audio` plays non-HLS HTTPS audio through ExoPlayer with a **transparent streaming disk cache**. That cache improves repeat playback after online streaming but **does not guarantee** a complete file on disk.

True offline playback requires a **separate** path: native HTTP download, files under app-private storage, and Preferences manifests—plus a **vibe metadata snapshot** so the player can rebuild the execution plan without calling the API.

The Capacitor WebView origin is typically **`https://localhost`**. Cross-origin GET from the WebView (e.g. `fetch()` to storage/CDN) is subject to **browser CORS** and is **unsuitable** for reliable offline file download.

---

## Current Decision

1. **ExoPlayer `SimpleCache`** (100 MiB LRU under `getCacheDir()/media`) is used **automatically** during HTTPS streaming. It is **best-effort only** — not a full-file or offline guarantee.
2. **Guaranteed offline audio** uses **`CapacitorHttp.request()`** + **`@capacitor/filesystem`** (`Directory.Data`) + Preferences manifest **`ixora_offline_audio_manifest_v1`**. **Do not** use WebView **`fetch()`** for offline downloads (CORS). **Do not** use **`NativeAudio.preload()`** as a download primitive.
3. Offline files live under **`Directory.Data/offline_audio/`** (e.g. `offline_audio/vibe_{vibeId}/sound_{soundId}.{ext}`).
4. Playback uses **`file://`** only when the manifest entry’s **`remoteUrl` exactly matches** the current **`layer.fileUrl`** and the file still exists; otherwise playback uses HTTPS (with transparent SimpleCache).
5. A **vibe metadata snapshot** in Preferences (**`offline_vibe_manifest_v1`**) is **required** so **VibePlayerPage** can rebuild **`executionPlan`** offline after a successful download—audio bytes alone are insufficient.
6. **`clearAudioCache()`** clears **only** ExoPlayer **`SimpleCache`** (`getCacheDir()/media`), **not** offline files under `Directory.Data`.
7. **DigitalOcean Spaces CDN URLs** are stable public HTTPS URLs and behave like any other HTTPS audio URL for streaming, ExoPlayer cache, and offline download (manifest matching uses **exact string equality** with `layer.fileUrl`).
8. **Live reload** (`ionic capacitor run android -l`) is **not valid** for validating offline behaviour; use an installable build (`ionic build`, `cap sync`, `cap run` without `-l`).

---

## Architecture

Two independent mechanisms plus a metadata layer:

```
                    ┌─────────────────────────────────────────────────────────┐
                    │              Remote HTTPS (CDN / API URLs)               │
                    └───────────────────────────┬─────────────────────────────┘
                                                │
           ┌────────────────────────────────────┼────────────────────────────────────┐
           │                                    │                                    │
           ▼                                    ▼                                    ▼
┌──────────────────────┐          ┌─────────────────────────┐          ┌─────────────────────────┐
│ ExoPlayer SimpleCache │          │ CapacitorHttp.request() │          │ API (online only)        │
│ (automatic, streaming)│          │ + Filesystem.writeFile  │          │ GET vibe + sounds        │
│ 100 MiB LRU           │          │ Directory.Data/         │          │                          │
│ getCacheDir()/media   │          │   offline_audio/        │          │                          │
└──────────┬───────────┘          └──────────┬──────────────┘          └──────────┬──────────────┘
           │                                  │                                    │
           │ progressive buffer               │ manifest:                          │ on success
           │ during play                      │ ixora_offline_audio_manifest_v1    │ builds plan
           │                                  │ vibeId:soundId → path + remoteUrl  │
           │                                  │                                    │
           └──────────────────┬───────────────┴────────────────────────────────────┘
                              ▼
                   audioEngine.resolvePlaybackAssetUrl(layer, vibeId)
                              │
              remoteUrl === layer.fileUrl && file exists?
                    yes → file:// (NativeAudio ParcelFileDescriptor)
                    no  → HTTPS → RemoteAudioAsset + SimpleCache

Parallel after successful "Download for offline" (failed layers === 0):
  offline_vibe_manifest_v1 → { vibe fields, VibeSound[] } for offline executionPlan
```

### Mechanism comparison

| | **Streaming cache (ExoPlayer)** | **Download for offline** | **Vibe metadata snapshot** |
| --- | --- | --- | --- |
| **Purpose** | Smoother repeat streaming online | Full file on disk for offline play | Rebuild player plan without API |
| **Storage** | `getCacheDir()/media` | `Directory.Data/offline_audio/` | Preferences `offline_vibe_manifest_v1` |
| **Manifest key** | (internal to ExoPlayer) | `ixora_offline_audio_manifest_v1` | `{ version: 1, vibes: { "<id>": snapshot } }` |
| **Guarantee** | **Best-effort** partial buffer | **Full file** when download succeeds | Plan + UI fields when snapshot exists |
| **Written when** | During HTTPS playback | Per layer during user download | After download completes with **zero failed layers** |

### Offline player hydration

On mount, **VibePlayerPage** loads vibe + sounds from the API when online. If sounds are missing (offline / error), it calls **`getOfflineVibeSnapshot(vibeId)`**. With a snapshot, it hydrates **`selectedVibe`** and **`vibeSounds`**, then **`buildPlan()`**. **Play** depends on **`hasPlayableLayers`** (execution plan), not network status—so offline **`file://`** layers enable controls when the snapshot and audio manifest align.

If offline with no snapshot: toast **“This vibe is not available offline.”** List/browse screens still require network unless separately cached; only a **previously downloaded** vibe’s player is supported offline.

### CapacitorHttp configuration note

`plugins.CapacitorHttp.enabled: true` patches global `fetch` / `XHR` to native implementations. It is **not required** for offline downloads—the app calls **`CapacitorHttp.request()`** explicitly (native HTTP). The project keeps **`enabled: false`** unless patched fetch is needed app-wide.

### URL matching

Manifest lookup uses **exact string equality** between stored **`remoteUrl`** and **`layer.fileUrl`**. If the API returns a **new** URL for the same sound (e.g. rotated signed URL), playback falls back to HTTPS until the user downloads again. **Spaces CDN public URLs** are stable and align well with this model.

---

## Rules

### Streaming cache (ExoPlayer)

- Treat SimpleCache as **automatic** and **best-effort** only; **`prepare()`** may buffer only enough to reach smooth playback, not the entire file.
- Non-HLS HTTPS uses **`RemoteAudioAsset`** + **`CacheDataSource`** + **`LeastRecentlyUsedCacheEvictor`** (100 MiB max).
- HLS (`.m3u8`) uses **`StreamAudioAsset`** and **bypasses** SimpleCache.
- **`clearAudioCache()`** / Settings **Clear audio cache** → release SimpleCache and delete **`getCacheDir()/media`** only.
- Do **not** call **`NativeAudio.clearCache()`** from UI or stores; use **`audioEngine.clearAudioCache()`** via the **`AudioEngine`** facade.

### Guaranteed offline download

- Download with **`CapacitorHttp.request({ url, method: 'GET', responseType: 'blob' })`**; on native, body arrives as **base64** → **`Filesystem.writeFile`** **without** `encoding` (binary-safe).
- **Never** use WebView **`fetch()`** for offline audio bytes (CORS against `https://localhost` origin).
- **Never** use **`NativeAudio.preload()`** as a download or full-file guarantee.
- Store under **`Directory.Data/offline_audio/`** with manifest **`ixora_offline_audio_manifest_v1`**: `vibeId:soundId` → `{ relativePath, remoteUrl, savedAt }`.
- Resolve playback with **`audioEngine.resolvePlaybackAssetUrl(layer, vibeId)`**; use **`file://`** only when **`remoteUrl === layer.fileUrl`** and file exists.
- **`NativeAudio.preload()`** in **`audio-player.service.ts`** is for **playback preparation** only (`isUrl: true`, local URI when resolved).

### Metadata snapshot

- After **successful** “Download for offline” (**`failed === 0`**, at least one success), persist snapshot to **`offline_vibe_manifest_v1`** (vibe UI fields + **`VibeSound[]`** matching API shape).
- Snapshot is **not** updated when server data changes until the user downloads again successfully.
- Clearing app data removes Preferences and offline files; both manifests must be repopulated by downloading again.

### API surface (mobile)

All cache/offline capabilities go through **`AudioEngine`** / **`audioEngine`**:

```typescript
await audioEngine.clearAudioCache();           // ExoPlayer cache only
await audioEngine.cacheVibeAudio(vibeId, layers); // full-file native download
await audioEngine.resolvePlaybackAssetUrl(layer, vibeId); // internal + playback
```

Pinia **`playerStore`** / **`audioPlayerService.setPlaybackVibeContext(vibeId)`** must stay in sync so preloads resolve offline paths correctly.

### Mobile ↔ backend boundary

- Mobile consumes **HTTPS CDN URLs from the API only** — **no** Spaces credentials, presigned upload policies, or direct bucket access in the app.
- Offline strategy applies to those URLs as ordinary HTTPS resources.

---

## Risks

| Risk | Mitigation |
| --- | --- |
| Assuming SimpleCache equals offline | Document and UI: only **Download for offline** guarantees full files |
| WebView `fetch()` for downloads | Mandate **`CapacitorHttp.request()`** only |
| Using `preload()` as download | Explicit native download + Filesystem write |
| URL mismatch after API URL change | Exact manifest match; re-download; prefer stable CDN URLs from API |
| Player empty offline without snapshot | Require **`offline_vibe_manifest_v1`** after successful download |
| Testing with live reload | Use production-like installable build without `-l` |
| Clearing wrong storage | **`clearAudioCache()`** documented as SimpleCache-only; offline files retained |
| OS low storage | ExoPlayer cache may evict; offline files under `Directory.Data` separate until uninstall / overwrite |

---

## Validation

**Policy / review**

- [ ] No offline download path uses WebView `fetch()` for audio bytes
- [ ] No use of `NativeAudio.preload()` as full-file download
- [ ] No Spaces credentials in mobile
- [ ] `clearAudioCache()` does not delete `offline_audio/`

**Manual (Android — installable build, not live reload)**

1. `ionic build` → `npx cap sync android` → `npx cap run android` (**no** `-l`)
2. Optional: Settings → Clear audio cache (ExoPlayer only)
3. Online: open vibe → **Download for offline** → wait for success
4. Airplane mode: reopen same vibe → **Offline mode**, **Play** enabled, plan from snapshot
5. **Play** → audio from **`file://`**
6. Open vibe never downloaded while offline → **Play** disabled, “not available offline” toast
7. Restore network → API loads work again

**Logs**

- `[AudioCache]` — native download, manifest, URI resolution
- `[OfflineVibe]` — snapshot save/remove

**adb (paths vary by `applicationId`)**

```bash
adb logcat | grep -i "AudioCache"
adb shell du -sh /data/data/<applicationId>/cache/media
adb shell run-as <applicationId> ls -la files/offline_audio/
```

---

## Related Files

| Location | Document / code |
| --- | --- |
| **Central (this repo)** | `docs/architecture/storage/storage-strategy.md` (CDN URLs, no client Spaces access) |
| | `docs/architecture/audio/audio-engine-fade-limitations.md` |
| | `docs/architecture/audio/native-loop-fadein.md` |
| | `docs/architecture/mobile/android-native-customizations.md` |
| **front_vibes** | `docs/audio-cache.md` (repo copy — keep aligned with this file) |
| | `src/services/audio-engine/offline-audio-storage.ts` |
| | `src/services/audio-engine/native-audio.engine.ts` |
| | `src/services/audio-engine/types.ts` |
| | `src/services/audio-player.service.ts` |
| | `src/services/offline-vibe-cache.service.ts` |
| | `src/stores/player.store.ts` |
| | `src/views/VibePlayerPage.vue` |
| | `src/views/SettingsPage.vue` |
| | `capacitor.config.ts` (`CapacitorHttp`) |
| **Native plugin** | `@capgo/native-audio` — `RemoteAudioAsset.java` (SimpleCache) |
| **ADR (planned)** | ADR-004 CapacitorHttp for offline downloads (`docs/standards/git-flow.md`) |

When changing audio cache or offline behaviour, update **this file first**, then sync the `front_vibes` copy and related architecture notes.
