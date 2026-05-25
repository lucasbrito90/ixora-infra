# Playback Runtime — mobile ambient multi-layer engine

**Status:** Active feature specification (source of truth)  
**Version:** 2.0 (consolidated; matches current `front_vibes` playback stack)  
**Feature ID:** `vibes/playback-runtime`  
**Platform:** Mobile native (`front_vibes` — Capacitor Android/iOS); **no** backend playback API

---

## Goal

Define how **Ixora plays a user-owned vibe on mobile**: load **`vibe_sounds`** (online or offline snapshot), build an **execution plan**, orchestrate **multi-layer playback** through the **`AudioEngine`** abstraction and **`audio-player.service`**, expose reactive UI via **`player.store`**, and support **background playback** with **media notifications** — **without** backend streaming endpoints, Spaces credentials on device, **runtime fades**, or **promised seamless looping**.

**Success criteria:**

- Playback is **client-only**; Laravel supplies **HTTPS CDN URLs** and pivot config via read APIs.
- **`buildVibeExecutionPlan`** transforms **`VibeSound[]`** → ordered **`VibeExecutionLayer[]`**.
- **`@capgo/native-audio`** (ExoPlayer on Android) is the **current** engine behind **`AudioEngine`**.
- Supported **`play_mode`**: **`loop`**, **`once`**, **`interval`**.
- **`layer.fileUrl`** comes from catalog **`sounds.file_url`** on each layer row — not overridden by pivot.
- **Fade fields** may exist on pivot/plan but are **ignored at runtime**.
- **`NativeAudio.preload()`** prepares playback — **not** offline download.
- Offline **`file://`** only when manifest **`remoteUrl` exactly equals** **`layer.fileUrl`**.

---

## Scope

### In scope

- **Inputs:** vibe metadata + **`vibe_sounds`** from API or offline snapshot
- **Planning:** **`buildVibeExecutionPlan`**, **`isExecutionLayerPlayable`**
- **Orchestration:** **`audio-player.service.ts`** (timers, modes, native/HTML fallback)
- **UI state:** **`player.store.ts`** (Pinia) — **`playbackState`**, vibe context, elapsed clock
- **Engine adapter:** **`AudioEngine`** → **`nativeAudioEngine`** (`@capgo/native-audio`)
- **UI surfaces:** **`VibePlayerPage`**, **`MiniPlayer`**, tab layout padding
- **Background:** Android foreground service + NativeAudio **`backgroundPlayback`**
- **Media notification:** NativeAudio MediaStyle + vibe name/artwork metadata
- **Audio focus:** plugin focus events + headset disconnect (**`audioBecomingNoisy`**)
- **App lifecycle:** **`useAppLifecycleAudio`** — background pause fallback on web
- **Streaming cache:** ExoPlayer SimpleCache (best-effort; separate from offline download)

### Out of scope

- **Backend playback / streaming / transcoding** endpoints — **none exist**
- **Creating or editing** vibes, layers, or catalog sounds — separate specs
- **Download for offline** pipeline — [`offline-download/spec.md`](offline-download/spec.md)
- **Runtime fade-in / fade-out** — explicitly **not applied**
- **JS crossfade / faux DSP** in the WebView
- **Guaranteed seamless loop boundaries** or sample-accurate transitions
- **Admin playback**
- **Direct Spaces access** or bucket credentials on mobile

---

## Actors

| Actor | Role |
| --- | --- |
| **End user** | Starts, pauses, resumes, stops vibe playback on device. |
| **`VibePlayerPage`** | Loads vibe + layers, builds plan, drives play/pause/restart/stop UX. |
| **`player.store`** | Single reactive source for UI — delegates audio to **`audioPlayerService`**. |
| **`audio-player.service`** | Multi-layer scheduler — loop/once/interval, native + HTML fallback. |
| **`AudioEngine`** | URL resolve, cache helpers — swap point for future engines. |
| **`@capgo/native-audio` / ExoPlayer** | Native preload/play/loop/pause; MediaSession notification. |
| **Laravel API** | Read-only — **`GET /api/vibes/{id}`**, **`GET …/sounds`**. |

---

## User Journey

1. User opens vibe → **`/vibes/:id/player`** (**`VibePlayerPage`**).
2. App loads **`GET /api/vibes/{id}`** + **`GET /api/vibes/{id}/sounds`** (or offline snapshot if API empty).
3. **`buildPlan(vibeSounds)`** → **`executionPlan`**.
4. User taps **Play** → **`store.playVibe({ layers, artworkUrl, … })`**:
   - Sets vibe context + **`playbackState: preparing`**
   - **`audioPlayerService.playPlan(layers)`**
   - **`startBackgroundAudio(vibeName)`** (Android)
5. Prepare handshake: first **audible** layer → **`playbackState: playing`** + elapsed ticker.
6. User navigates **back** → audio **continues**; **`MiniPlayer`** visible.
7. User pauses/resumes from player or MiniPlayer, or via **lock-screen notification**.
8. User taps **Stop** → **`stopPlayback()`** tears down layers + foreground service.
9. Headset unplug / audio focus loss may pause or stop per rules below.

**Not in journey:** server “play” command, transcoding, runtime fades.

---

## Related Domain Model

```
GET /api/vibes/:id/sounds  ──►  VibeSound[]  ──►  buildVibeExecutionPlan
        │                              │                    │
        │ sounds.file_url              │ pivot config       ▼
        └──────────────────────────────┴──────────►  VibeExecutionLayer[]
                                                           │
                     VibePlayerPage / MiniPlayer ◄─────────┤
                     player.store (Pinia) ◄────────────────┤
                                                           ▼
                                              audioPlayerService.playPlan()
                                                           │
                                                           ▼
                                              AudioEngine.resolvePlaybackAssetUrl
                                                           │
                                                           ▼
                                              NativeAudio / ExoPlayer (or HTMLAudio fallback)
```

| Layer | Role in playback |
| --- | --- |
| **`sounds`** | **`file_url`** — CDN HTTPS audio bytes |
| **`vibe_sounds`** | Volume, mode, timing on this vibe |
| **`vibes`** | Session identity + hero artwork (not audio bytes) |

Layer configuration: [`manage-vibe-sounds/spec.md`](manage-vibe-sounds/spec.md).

---

## Architecture

### Separation of concerns (shipped)

| Module | Responsibility | Does **not** |
| --- | --- | --- |
| **`player-engine.service.ts`** | Pure **`buildVibeExecutionPlan`**, URL/playability helpers | Play audio |
| **`usePlayerEngine`** | Shared **`executionPlan`** ref; **`buildPlan` / `clearPlan`** | Pinia / UI |
| **`audio-player.service.ts`** | Layer lifecycle, timers, NativeAudio calls, session pause/resume | Reactive UI state |
| **`player.store.ts`** | **`playbackState`**, vibe context, elapsed, **`playVibe`** orchestration | Direct NativeAudio from components |
| **`audio-engine/`** | **`resolvePlaybackAssetUrl`**, offline download (**`cacheVibeAudio`**), cache clear | Mode scheduling |
| **`VibePlayerPage`** | Load data, build plan, call **`store.playVibe`** | Import NativeAudio directly |
| **`MiniPlayer`** | Read store; pause/resume/stop; navigate to player | Build execution plan |

**Rule:** UI components import **`usePlayerStore`** and **`usePlayerEngine`** — not **`@capgo/native-audio`** directly (except centralized config in **`audio-player.service`**).

### Control flow

```
VibePlayerPage.togglePlayback()
  → store.playVibe({ vibeId, layers: executionPlan, artworkUrl, … })
       ├─ setCurrentVibe / notification metadata (setNotificationVibeName/Artwork)
       ├─ playbackState: preparing
       ├─ audioPlayerService.playPlan(layers)
       │     ├─ stopAll() previous session (_playPlanInProgress guard)
       │     ├─ per layer: schedule start_offset → preload → loop|once|interval
       │     └─ prepare handshake → onPrepared → playing
       └─ startBackgroundAudio(vibeName)  [Android]
```

### `playbackState` (`player.store`)

| State | Meaning |
| --- | --- |
| **`idle`** | No active session |
| **`preparing`** | Preload/native setup; UI shows spinner; MiniPlayer visible |
| **`playing`** | Audible start confirmed; elapsed ticker running |
| **`paused`** | Layers paused; vibe context retained |
| **`error`** | Prepare failed → toast → auto-return to **`idle`** (~2.4s) |

**Prepare handshake:** **`audio-player.service`** tracks immediate-start layers; **`onPrepared`** fires when first layer becomes audible (or none expected). Timeout **25s** → **`onFailed`** → **`stopAll`**, toast, **`error`**.

---

## Execution Plan

**Pure function:** **`buildVibeExecutionPlan(vibeSounds)`** in **`player-engine.service.ts`**.

### Output: `VibeExecutionLayer`

| Field | Source |
| --- | --- |
| `soundId` | **`VibeSound.id`** (catalog sound id) |
| `soundName` | Layer name |
| **`fileUrl`** | **`vs.file_url`** (trimmed HTTPS) |
| `volume` | Pivot 0–100 |
| `playMode` | **`play_mode`** |
| `startsAtSeconds` | **`start_offset_seconds`** (default 0) |
| `endsAtSeconds` | `startsAt + play_duration_seconds` when duration set |
| `durationSeconds` | **`play_duration_seconds`** |
| `repeatIntervalSeconds` | **`repeat_interval_seconds`** only if mode **interval** |
| `fadeInSeconds`, `fadeOutSeconds` | Pivot fades (default 0) — **not applied at runtime** |
| `sortOrder` | **`sort_order`** |
| `humanReadableSummary` | Display string |

### Planning rules

1. Sort ascending **`sort_order`**.
2. **Interval mode:** null **`repeatIntervalSeconds`** when mode ≠ interval.
3. **`isExecutionLayerPlayable`:** valid URL; interval requires **`repeatIntervalSeconds ≥ 1`**.

### Lifecycle

- Built on **`VibePlayerPage`** mount after sounds load (or offline hydrate).
- Rebuilt when **`vibeSounds`** change (e.g. manage-sounds page via shared **`usePlayerEngine`** ref).
- **`clearPlan()`** when leaving player context (optional; session may continue via MiniPlayer).

---

## Runtime Behaviour

### Play modes (native primary)

| Mode | Native API | Semantics |
| --- | --- | --- |
| **`loop`** | **`preload`** + **`NativeAudio.loop`** | Continuous repeat until user stops — **not seamless** |
| **`once`** | **`preload`** + **`play`**; global **`complete`** listener | Single play; layer torn down on end |
| **`interval`** | **`preload` once**; repeated **`play`** ticks | Silence **`repeat_interval_seconds`** **after** each tick **ends**; optional wall-clock cap **`play_duration_seconds`** |

**Interval semantics (current):**

- Gap = silence **after** playback **ends**, before next tick starts — **not** a fixed period including play time.
- Tick length = **audio file natural duration** (no **`tick_duration_seconds`** today).
- If **`complete`** never fires, interval chain may **stall** — known risk.

**Web / dev:** non-native builds use **`HTMLAudioElement`** fallback (`ionic serve`).

**Native failure:** preload/loop/play failure → **HTMLAudioElement** fallback for that layer.

### Layer timing

- **`startsAtSeconds > 0`:** **`setTimeout`** before preload/play.
- **`play_duration_seconds`:** hard **`stopLayer`** at wall-clock cap — **no fade-out**.

### What playback does **not** do

- Does **not** call **`cacheVibeAudio`** during play (explicit **Download for offline** only).
- Does **not** apply **`fadeInSeconds` / `fadeOutSeconds`**.
- Does **not** run JS volume ramps or cross-layer crossfades.
- Does **not** guarantee full-file cache (ExoPlayer SimpleCache is progressive / best-effort).
- Does **not** promise **seamless loop** boundaries at file edges.

See [`audio-engine-fade-limitations.md`](../../architecture/audio/audio-engine-fade-limitations.md).

---

## Audio Engine Rules

### Abstraction

| Rule | Detail |
| --- | --- |
| Import | **`import { audioEngine } from '@/services/audio-engine'`** |
| Implementation | **`nativeAudioEngine`** → **`@capgo/native-audio`** |
| Interface | **`AudioEngine`** in **`types.ts`** — future swap without UI rewrite |

**Note:** Mode orchestration lives in **`audio-player.service`** (calls NativeAudio directly). **`AudioEngine`** provides **`resolvePlaybackAssetUrl`**, **`cacheVibeAudio`**, **`clearAudioCache`**.

### Preload vs download

| API | Purpose |
| --- | --- |
| **`NativeAudio.preload`** (via service) | Load asset for **playback** — **`isUrl: true`** |
| **`audioEngine.cacheVibeAudio`** | **Download for offline** — CapacitorHttp + Filesystem |
| ExoPlayer SimpleCache | Progressive streaming cache during play — **not** full offline guarantee |

### URL resolution

```typescript
// audioEngine.resolvePlaybackAssetUrl(layer, vibeId)
// → getOfflinePlaybackUriIfValid: entry.remoteUrl === layer.fileUrl.trim() && file exists → file://
// else → layer.fileUrl (HTTPS)
```

Exact string match required. API URL change invalidates offline file until re-download.

### Volume

- Layer volume 0–100 → native **0.1–1.0** (plugin does not support true silence via volume; **stop** used instead).
- Loop preload uses **`isComplex: true`** so Java **`preloadAsset()`** reads **`volume`** param.

### Cache clear

- **`audioEngine.clearAudioCache()`** → ExoPlayer **`getCacheDir()/media`** only.
- Does **not** delete **`Directory.Data/offline_audio/`**.

---

## Background Playback & Notifications

### NativeAudio configuration (once at startup)

```typescript
NativeAudio.configure({
  backgroundPlayback: true,  // skip plugin auto-pause on background
  showNotification: true,    // MediaStyle lock-screen / shade controls
  focus: true,               // Android AudioFocus + focus events
});
```

### Media notification (NativeAudio)

- Each **`preload`** embeds **`notificationMetadata`**: vibe **title**, layer **artist**, optional **artworkUrl**.
- **`setNotificationVibeName`** / **`setNotificationArtworkUrl`** called from **`store.playVibe`** before **`playPlan`**.
- Lock-screen / notification controls fire **`playbackState`** events with **`reason`**: **`remotePlay`**, **`remotePause`**, **`remoteStop`** → routed to **`player.store`** via **`setMediaControlCallbacks`**.

### Android foreground service (process keep-alive)

- **`backgroundAudio.service.ts`** — **`@capawesome-team/capacitor-android-foreground-service`**
- Started on **`playVibe`**; stopped on **`stopPlayback`** or natural session end.
- **Low-importance** channel (**`vibes_bg_service`**) — separate from NativeAudio media notification.
- Prevents Android from killing process ~1–2 min after backgrounding.
- **Android only** — no-op on web/iOS.

### Two-notification model (Android)

| Notification | Role |
| --- | --- |
| **NativeAudio MediaStyle** | Play/pause/stop + artwork |
| **Foreground service** | Subtle “keeps process alive” indicator |

---

## Audio Focus & Interruptions

### Plugin audio focus (`audio-player.service`)

Global **`NativeAudio.addListener('playbackState')`** handles:

| `reason` | Behaviour |
| --- | --- |
| **`audioFocusLossTransient`** | Plugin pauses → store **`pausePlayback`**; flag **`_pausedByAudioFocus`** |
| **`audioFocusGain`** | Auto-**resume** only if paused due to focus — not user pause |
| **`audioFocusLoss`** | Permanent loss → **`stopPlayback`** |
| **`remotePlay/Pause/Stop`** | Media notification / BT transport → store actions |

### Headset disconnect (`audio-focus.service`)

- **`MainActivity`** bridges **`ACTION_AUDIO_BECOMING_NOISY`** → window event **`audioBecomingNoisy`**
- **`initAudioFocusService()`** (App.vue) → **`setAudioFocusCallbacks`** → **`pausePlayback`**

---

## App Lifecycle

**`useAppLifecycleAudio`** (singleton, App.vue):

| Condition | On background |
| --- | --- |
| **Foreground service running** | **No action** — audio continues; MiniPlayer stays **`playing`** |
| **Web / no foreground service** | **`pausePlayback`** if **`playing`** or **`preparing`** |

On return to foreground after lifecycle pause: **no auto-resume** — toast *“Playback was paused while the app was in background”*; user taps resume manually.

**`handleBack`** on **`VibePlayerPage`**: **`router.back()`** — **does not stop** audio (MiniPlayer persists session).

---

## Mobile UX Rules

### `VibePlayerPage`

| Rule | Detail |
| --- | --- |
| Route | **`/vibes/:id/player`** |
| Load | **`fetchVibe`** + **`fetchVibeSounds`**; offline snapshot fallback |
| Plan | **`buildPlan`** after load |
| Play disabled | When **`!hasPlayableLayers`** or loading/preparing |
| States | Spinner while loading or **`preparing`** |
| Toggle | Pause/resume same vibe; **`playVibe`** when idle or switching vibe |
| Restart | Menu → **`playVibe`** again with same plan |
| Stop | Menu → **`stopPlayback`** |
| Back | **Does not stop** playback |
| Offline download | Separate menu action — [`offline-download/spec.md`](offline-download/spec.md) |
| DEV panel | Optional execution plan diagnostics in dev builds |

### `MiniPlayer`

| Rule | Detail |
| --- | --- |
| Visible when | **`currentVibeId`** set and state **`playing` \| `paused` \| `preparing`**; not on routes with **`meta.hideMiniPlayer`** |
| Artwork | **`currentVibeArtworkUrl`** or gradient fallback |
| Controls | Pause/resume (disabled while **`preparing`**); stop |
| Tap bar | Navigate to **`/vibes/:id/player`** |
| Position | Fixed above tab bar (**68px** + safe area) |

Routing: [`front-vibes-ionic-routing.md`](../../standards/front-vibes-ionic-routing.md).

---

## Offline Behaviour

| Topic | Behaviour |
| --- | --- |
| Load sounds | API first; if empty, **`getOfflineVibeSnapshot`** hydrates **`vibeSounds[]`** |
| Plan | Same **`buildVibeExecutionPlan`** from snapshot rows |
| Audio bytes | **`file://`** only if **`ixora_offline_audio_manifest_v1`** matches **`layer.fileUrl`** exactly |
| Mismatch | Falls back to HTTPS — fails offline without network |
| Snapshot refresh | **Not** updated on layer edit — re **Download for offline** required |

See [`offline-download/spec.md`](offline-download/spec.md).

---

## Failure Cases

| Case | Expected behaviour |
| --- | --- |
| No playable layers | **`playVibe`** returns false; Play disabled; toast |
| Invalid / empty **`file_url`** | Layer excluded by **`isExecutionLayerPlayable`** |
| Interval without interval seconds | Layer non-playable |
| Native preload/loop fails | Fallback to **HTMLAudioElement** (or layer fails logged) |
| Prepare timeout (25s) | **`error`** state → toast → **`idle`** |
| Offline, no snapshot | Empty plan; “not available offline” message |
| Offline, snapshot but URL mismatch | Plan exists; HTTPS fallback fails without network |
| **`complete` never fires (interval)** | Interval chain may stall |
| User stops during prepare | **`stopAll`** tears down layers |
| Partial playable layers | Play starts; toast “Some sounds could not be played” |
| Backend unavailable online | Cannot refresh layers; may use stale snapshot |

---

## Security Rules

| Rule | Requirement |
| --- | --- |
| Playback URLs | From API **`file_url`** only — opaque HTTPS or resolved **`file://`** |
| No Spaces secrets | Mobile never holds **`DO_SPACES_*`** |
| **No backend play API** | No server-side stream authorization in playback path |
| Auth | Layer load requires Firebase Bearer when online |
| Local files | **`Directory.Data`** sandbox only |

---

## Future Considerations

| Topic | Notes |
| --- | --- |
| Native fade support | Requires ADR + engine work — fields kept for compatibility only |
| Seamless loops | **Not promised** — may need custom native engine |
| **`tick_duration_seconds`** | Not implemented |
| Alternative **`AudioEngine`** | Interface allows swap |
| Backend streaming / HLS packaging | **Out of scope** — no transcoding pipeline |
| JS crossfade | **Rejected** without architecture review |

**Explicitly excluded:** runtime fades, fake DSP, backend playback endpoints, seamless loop guarantees, transcoding workers.

---

## Related Docs

| Document | Path |
| --- | --- |
| **This spec** | `docs/specs/vibes/playback-runtime/spec.md` |
| Manage vibe sounds | [`manage-vibe-sounds/spec.md`](manage-vibe-sounds/spec.md) |
| Offline download | [`offline-download/spec.md`](offline-download/spec.md) |
| Create / update vibe | [`create-vibe/spec.md`](create-vibe/spec.md), [`update-vibe/spec.md`](update-vibe/spec.md) |
| Preset import | [`../preset-vibes/import/spec.md`](../preset-vibes/import/spec.md) |
| Fade limitations | [`docs/architecture/audio/audio-engine-fade-limitations.md`](../../architecture/audio/audio-engine-fade-limitations.md) |
| Audio cache | [`docs/architecture/audio/audio-cache.md`](../../architecture/audio/audio-cache.md) |
| Native loop investigation | [`docs/architecture/audio/native-loop-fadein.md`](../../architecture/audio/native-loop-fadein.md) |
| Mobile CDN validation | [`docs/architecture/storage/mobile-cdn-validation.md`](../../architecture/storage/mobile-cdn-validation.md) |
| Storage / CDN URLs | [`docs/architecture/storage/storage-strategy.md`](../../architecture/storage/storage-strategy.md) |
| Routing | [`docs/standards/front-vibes-ionic-routing.md`](../../standards/front-vibes-ionic-routing.md) |
| **front_vibes** | `VibePlayerPage.vue`, `MiniPlayer.vue`, `stores/player.store.ts`, `services/audio-player.service.ts`, `services/player-engine.service.ts`, `services/audio-engine/`, `composables/useAppLifecycleAudio.ts`, `services/audio-focus.service.ts`, `services/backgroundAudio.service.ts` |

When behaviour changes, update **this file first**, then architecture docs and implementation comments.
