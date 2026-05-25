# Playback runtime — mobile audio stack

**Status:** Active architecture (source of truth)  
**Scope:** Multi-layer vibe playback on mobile (`front_vibes`, Android primary)  
**Applies to:** Pinia player store, `audio-player.service`, `AudioEngine`, `@capgo/native-audio`, Android foreground service

---

## Purpose

Describe the **technical architecture** of Ixora mobile playback: how reactive UI state, layer scheduling, native audio, process keep-alive, notifications, and interruptions fit together — **without** prescribing product journeys or API contracts.

This document states **layering, ownership, and constraints**. Feature behaviour and acceptance criteria live in the playback spec; plan field mapping lives in the execution-plan spec.

---

## Context

Ixora plays **user-owned vibes** as **concurrent ambient layers** (loop, once, interval). Audio bytes arrive as **HTTPS CDN URLs** from Laravel; the mobile app builds an **execution plan** client-side and drives playback entirely on device.

The stack is **Capacitor + Ionic Vue** on Android (ExoPlayer via **`@capgo/native-audio`**). There is **no backend playback or execution engine**. Web builds (`ionic serve`) use **`HTMLAudioElement`** fallback for development — not the production architecture target.

Android background playback requires **both** NativeAudio **`backgroundPlayback: true`** and a separate **foreground service** — the plugin alone does not prevent process death after ~1–2 minutes in background.

---

## Current Decision

1. **`player.store.ts` (Pinia)** is the **single reactive source of truth** for UI playback state (`playbackState`, vibe context, elapsed clock). Components **must not** call **`NativeAudio`** directly.
2. **`audio-player.service.ts`** owns **runtime orchestration**: layer timers, mode dispatch (loop / once / interval), native + HTML fallback, prepare handshake, session pause/resume, and the global NativeAudio **`playbackState`** listener (focus + remote controls).
3. **`AudioEngine`** (`src/services/audio-engine/`) is a **partial abstraction today**: **`resolvePlaybackAssetUrl`**, **`cacheVibeAudio`**, **`clearAudioCache`**, and cache metadata. **Mode scheduling still calls `NativeAudio` from `audio-player.service.ts`** — not through `AudioEngine.preloadLayer` / `playLayer` (interface exists; migration is future-only).
4. **`NativeAudio.configure`** runs **once at module load** in **`audio-player.service.ts`** with **`backgroundPlayback: true`**, **`showNotification: true`**, **`focus: true`**.
5. **Android foreground service** (`backgroundAudio.service.ts`, `@capawesome-team/capacitor-android-foreground-service`) starts on **`playVibe`** / **`restartPlayback`**, stops on **`stopPlayback`** or natural session end — **Android only**.
6. **Two notifications on Android**: NativeAudio **MediaStyle** (controls + artwork) + low-importance **FGS indicator** (`vibes_bg_service`).
7. **Audio focus** (transient/permanent) is handled via NativeAudio **`playbackState`** reasons → store **`pausePlayback`** / **`resumePlayback`** / **`stopPlayback`** with **`_pausedByAudioFocus`** guard for auto-resume.
8. **Headset disconnect** uses **`ACTION_AUDIO_BECOMING_NOISY`** → **`audioBecomingNoisy`** window event → **`pausePlayback`** — **no auto-resume** on focus gain for this path.
9. **Task removal** (swipe from recents) **kills the process** via patched **`AndroidForegroundService.onTaskRemoved()`** — JS bridge is already dead; intentional **`killProcess()`**.
10. **Runtime fades are not applied**; fade pivot/plan fields are compatibility-only ([`audio-engine-fade-limitations.md`](audio-engine-fade-limitations.md)).
11. **Do not introduce unsupported native engine changes** in architecture docs or ad-hoc patches without an explicit ADR and device validation — document **shipped** behaviour only.

---

## Architecture

### Layering

```
┌─────────────────────────────────────────────────────────────────────────┐
│  UI: VibePlayerPage, MiniPlayer (TabsLayout), Settings cache actions     │
│  Rule: import usePlayerStore / usePlayerEngine — NOT @capgo/native-audio │
└───────────────────────────────┬─────────────────────────────────────────┘
                                │
                                ▼
┌─────────────────────────────────────────────────────────────────────────┐
│  player.store.ts (Pinia)                                                 │
│  • playbackState machine   • currentVibe* context   • elapsedSeconds     │
│  • playVibe / pause / resume / stop / restart                            │
│  • callbacks: session ended, prepare, media controls, headset noisy      │
└───────────────┬─────────────────────────────┬───────────────────────────┘
                │                             │
                ▼                             ▼
┌───────────────────────────┐   ┌─────────────────────────────────────────┐
│ audio-player.service.ts   │   │ backgroundAudio.service.ts (Android)     │
│ • playPlan / pauseAll     │   │ • start / stop / update FGS                │
│ • NativeAudio direct      │   │ • POST_NOTIFICATIONS (API 33+)             │
│ • HTMLAudio fallback      │   └─────────────────────────────────────────┘
│ • focus + remote listener │
└───────────────┬───────────┘
                │ resolve URL per layer
                ▼
┌───────────────────────────┐   ┌─────────────────────────────────────────┐
│ audioEngine (adapter)     │   │ audio-focus.service.ts                   │
│ • resolvePlaybackAssetUrl │   │ • audioBecomingNoisy → pausePlayback     │
│ • cacheVibeAudio          │   │ (init once in App.vue)                   │
│ • clearAudioCache         │   └─────────────────────────────────────────┘
└───────────────┬───────────┘
                │
                ▼
┌───────────────────────────┐   ┌─────────────────────────────────────────┐
│ @capgo/native-audio       │   │ MainActivity.java + AndroidManifest      │
│ ExoPlayer (Android)       │   │ noisy receiver, FGS permissions/types    │
│ MediaSession notification │   │ task-removal patch (capawesome plugin)   │
└───────────────────────────┘   └─────────────────────────────────────────┘

Planning (pure, separate concern):
  VibeSound[] ──► buildVibeExecutionPlan ──► VibeExecutionLayer[]
  (see execution-plan spec)
```

### Data path (playback start)

```
VibePlayerPage
  → buildPlan(vibeSounds)                    [usePlayerEngine / player-engine.service]
  → store.playVibe({ layers, vibeId, … })
       ├─ setCurrentVibe + setPlaybackVibeContext(vibeId)
       ├─ setNotificationVibeName / setNotificationArtworkUrl
       ├─ playbackState → preparing
       ├─ audioPlayerService.playPlan(layers)
       │     ├─ stopAll() previous session (_playPlanInProgress guard)
       │     ├─ per layer: start_offset timer → resolve URL → preload → mode
       │     └─ prepare handshake (25s timeout)
       └─ startBackgroundAudio(vibeName)     [Android]
  → onPrepared → playing + elapsed ticker
```

Cross-link: [`../../specs/vibes/execution-plan/spec.md`](../../specs/vibes/execution-plan/spec.md), [`../../specs/vibes/playback-runtime/spec.md`](../../specs/vibes/playback-runtime/spec.md).

---

## Player state machine

**Type:** `PlaybackState = 'idle' | 'preparing' | 'playing' | 'paused' | 'error'`

**Owner:** `player.store.ts` — the audio service mutates native/HTML state; Pinia holds the **authoritative UI state** synced via store actions and registered callbacks.

### States

| State | Meaning | MiniPlayer (when mounted) |
| --- | --- | --- |
| **`idle`** | No session; `currentVibeId === null` | Hidden |
| **`preparing`** | `playPlan` registered; native preload / first audible pending | Visible (spinner on play/pause) |
| **`playing`** | Prepare handshake succeeded; elapsed ticker running | Visible |
| **`paused`** | `pauseAll`; vibe context retained | Visible |
| **`error`** | Prepare failed (25s timeout or hard failure) | Hidden (vibe cleared) → **`idle`** after ~2.4s |

### Transitions

| From | Event | To | Side effects |
| --- | --- | --- | --- |
| **`idle`** | **`playVibe`** (valid layers) | **`preparing`** | Set vibe context, FGS start, `playPlan` |
| **`preparing`** | **`onPrepared`** | **`playing`** | `beginSessionClock()` |
| **`preparing`** | **`onFailed`** | **`error`** → **`idle`** | `stopAll`, toast, clear vibe, stop FGS; auto-idle ~2.4s |
| **`playing`** | **`pausePlayback`** | **`paused`** | `pauseAll`, pause elapsed ticker |
| **`paused`** | **`resumePlayback`** | **`playing`** | `resumeAll`, resume ticker |
| **`playing` / `paused` / `preparing`** | **`stopPlayback`** | **`idle`** | `stopAll`, clear vibe, stop FGS |
| **any active** | Session ended (all layers natural end) | **`idle`** | Callback from `audio-player.service`; stop FGS |
| **`playing`** | Transient audio focus loss | **`paused`** | `_pausedByAudioFocus = true` |
| **`paused`** | Focus gain (if focus-paused) | **`playing`** | Auto-resume via store |
| **active** | Permanent audio focus loss | **`idle`** | `stopPlayback` via remote-stop callback |
| **`playing`** | Headset noisy | **`paused`** | No auto-resume on focus gain |
| **`playing` / `preparing`** | App background (no FGS) | **`paused`** | `useAppLifecycleAudio` fallback only |

**Guards:**

- **`pausePlayback`** / remote pause ignored while **`preparing`**.
- **`_playPlanInProgress`** suppresses session-ended callback during plan rebuild (restart / vibe switch).
- **`_stopAllExplicit`** suppresses session-ended callback on user **`stopPlayback`**.

---

## Pinia store ownership

| Concern | Owner | Notes |
| --- | --- | --- |
| **`playbackState`** | **`player.store`** | All transitions via store actions or registered callbacks |
| **`currentVibeId`**, name, summary, artwork | **`player.store`** | Set before audio starts so MiniPlayer shows during **`preparing`** |
| **`elapsedSeconds`** | **`player.store`** | `setInterval` outside Pinia reactivity tree |
| **`hasActiveLayers`** | **`player.store`** | Mirrors service after play/pause/stop |
| Layer registry, timers, native assets | **`audio-player.service`** | Not reactive — UI reads store |
| Notification title/artwork for preload | **`audio-player.service`** module vars | Set by store before **`playPlan`** |
| Offline URL resolve context | **`audio-player.service`** | `setPlaybackVibeContext(vibeId)` from store |
| FGS running flag | **`backgroundAudio.service`** | `isBackgroundAudioRunning()` for lifecycle composable |

**Registered once at store init:**

- **`setSessionEndedCallback`** — natural layer completion → **`idle`**
- **`setPlaybackPrepareCallbacks`** — **`onPrepared`** / **`onFailed`**
- **`setMediaControlCallbacks`** — lock-screen / notification transport
- **`setAudioFocusCallbacks`** — headset disconnect → **`pausePlayback`**

**Primary API for UI:** **`playVibe`**, **`pausePlayback`**, **`resumePlayback`**, **`stopPlayback`**, **`restartPlayback`**, **`cacheVibeAudio`** (delegates to **`audioEngine`**).

---

## AudioEngine abstraction

**Location:** `front_vibes/src/services/audio-engine/` — barrel export **`audioEngine`** → **`nativeAudioEngine`**.

### Shipped responsibilities

| Method | Role |
| --- | --- |
| **`resolvePlaybackAssetUrl(layer, vibeId)`** | Offline **`file://`** when manifest **`remoteUrl === layer.fileUrl.trim()`** and file exists; else HTTPS |
| **`cacheVibeAudio(vibeId, layers)`** | Full-file offline download (CapacitorHttp + Filesystem) — **not** playback |
| **`clearAudioCache()`** | ExoPlayer **`SimpleCache`** only (`getCacheDir()/media`) |
| **`getCacheInfo()`** | Static cache metadata for Settings UI |

### Boundary (important)

| In `AudioEngine` interface | Shipped caller |
| --- | --- |
| **`preloadLayer` / `loopLayer` / `playLayer` / pause / resume / stop** | Implemented on **`NativeAudioEngine`** but **not used** by **`audio-player.service`** |
| Mode orchestration, interval ticks, HTML fallback | **`audio-player.service.ts`** calls **`NativeAudio`** directly |
| **`NativeAudio.configure`** | **`audio-player.service.ts`** at module load (not **`audioEngine.configure`**) |

The interface is a **swap point for a future engine** — documenting or building against full **`AudioEngine`** playback methods without a migration plan would **overstate** current architecture.

Cross-link: [`audio-cache.md`](audio-cache.md), [`audio-engine-fade-limitations.md`](audio-engine-fade-limitations.md).

---

## NativeAudio boundaries

### What calls NativeAudio (shipped)

| Caller | Calls |
| --- | --- |
| **`audio-player.service.ts`** | **`configure`**, **`preload`**, **`play`**, **`loop`**, **`pause`**, **`stop`**, **`unload`**, **`addListener('playbackState')`**, **`addListener('complete')`** |
| **`native-audio.engine.ts`** | **`configure`** (alternate path), cache helpers — partial |

### What must not call NativeAudio

- Vue components (**`VibePlayerPage`**, **`MiniPlayer`**, pages, modals)
- Pinia store (delegates to services only)

### Asset identity

- Stable **`assetId`**: `vibe-layer-{soundId}` where **`soundId`** is catalog **`sounds.id`** on the execution layer.
- Preload uses **`isUrl: true`** with resolved HTTPS or **`file://`** URI.
- Loop mode uses **`isComplex: true`** so Java preload reads **volume** (0.1–1.0 from layer 0–100).

### Plugin configuration (once)

```typescript
NativeAudio.configure({
  backgroundPlayback: true,  // do not auto-pause on app background
  showNotification: true,    // MediaStyle + MediaSession
  focus: true,               // AudioFocus + playbackState focus reasons
});
```

---

## ExoPlayer role

On Android, **`@capgo/native-audio`** wraps **ExoPlayer** for non-HLS HTTPS (and **`file://`**) assets.

| Role | Detail |
| --- | --- |
| **Decode + play** | Loop, once, interval ticks via plugin Java (`RemoteAudioAsset`) |
| **SimpleCache** | ~100 MiB LRU under **`getCacheDir()/media`** — **progressive streaming buffer** during HTTPS play |
| **Not offline guarantee** | SimpleCache ≠ full file; explicit download uses separate path ([`audio-cache.md`](audio-cache.md)) |
| **Loop boundaries** | **Not sample-accurate** — gaps/clicks at loop wrap are a known limitation |
| **Cache clear** | **`audioEngine.clearAudioCache()`** — must not run during active playback (shared cache instance) |

ExoPlayer is **opaque** to the Vue layer — behaviour changes require plugin upgrades or a **new native engine**, not WebView DSP.

---

## Foreground service relationship

**Module:** `backgroundAudio.service.ts`  
**Plugin:** `@capawesome-team/capacitor-android-foreground-service`  
**Platform:** Android only — no-op on web/iOS.

### Why it exists

NativeAudio **`backgroundPlayback: true`** prevents the **plugin’s** auto-pause on background, but Android still **kills the process** without a foreground service after roughly 1–2 minutes. The FGS keeps the **WebView + JS bridge + ExoPlayer** alive for continuous ambient sessions.

### Lifecycle (store-driven)

| Store action | FGS |
| --- | --- |
| **`playVibe`** / **`restartPlayback`** | **`startBackgroundAudio(vibeName)`** — permission check → channel → **`startForegroundService`** |
| Vibe switch while FGS running | **`updateBackgroundAudioTitle(vibeName)`** |
| **`stopPlayback`** | **`stopBackgroundAudio()`** |
| Natural session end | **`stopBackgroundAudio()`** via session-ended callback |

**Constants:** channel `vibes_bg_service`, notification id `101`, icon `ic_stat_audio`, **`FOREGROUND_SERVICE_TYPE_MEDIA_PLAYBACK`**.

### Relationship to NativeAudio

| Component | Responsibility |
| --- | --- |
| **NativeAudio notification** | User-facing media controls, artwork, lock-screen |
| **Capawesome FGS** | Process keep-alive; low-importance silent indicator |

Both run concurrently by design — see [`../mobile/android-native-customizations.md`](../mobile/android-native-customizations.md).

---

## Media notification relationship

### Metadata flow

1. **`store.playVibe`** → **`setNotificationVibeName(vibeName)`**, **`setNotificationArtworkUrl(artworkUrl)`**
2. Each **`NativeAudio.preload`** embeds **`notificationMetadata`**: title = vibe name, artist = layer name, optional artwork URL
3. Lock-screen / shade controls emit **`playbackState`** with **`reason`**: **`remotePlay`**, **`remotePause`**, **`remoteStop`**
4. **`audio-player.service`** global listener → **`setMediaControlCallbacks`** → store **`resumePlayback`** / **`pausePlayback`** / **`stopPlayback`**

### Constraints

- Remote **play** ignored while **`preparing`**.
- Artwork is **best-effort HTTPS** — CDN must be reachable when preload runs for lock-screen image.
- Notification reflects **first preloaded layers**; not a per-layer rotating UI.

---

## Audio focus and interruption handling

### Plugin audio focus (`focus: true`)

NativeAudio registers as **`AudioManager.OnAudioFocusChangeListener`**. The plugin pauses/stops/resumes native audio internally; JS syncs Pinia via **`playbackState`** listener:

| `reason` | Native (plugin) | App (`player.store`) |
| --- | --- | --- |
| **`audioFocusLossTransient`** | Pauses | **`pausePlayback()`**; **`_pausedByAudioFocus = true`** |
| **`audioFocusGain`** | Resumes native | **`resumePlayback()`** **only if** **`_pausedByAudioFocus`** |
| **`audioFocusLoss`** | Stops native | **`stopPlayback()`** via remote-stop callback; clears focus flag |
| **`remotePlay` / `Pause` / `Stop`** | Transport | **`resumePlayback`** / **`pausePlayback`** / **`stopPlayback`** |

**User-initiated pause** must not auto-resume on **`audioFocusGain`** — guarded by **`_pausedByAudioFocus`**.

Brief ducking for transient interruptions may be handled by **Android OS** (`AUDIOFOCUS_GAIN_TRANSIENT_MAY_DUCK`); JS reacts to **`playbackState`** reasons, not raw focus ints.

### Headset / Bluetooth disconnect (`audioBecomingNoisy`)

**Not** exposed by NativeAudio. Native bridge:

```
MainActivity BroadcastReceiver (ACTION_AUDIO_BECOMING_NOISY)
  → triggerWindowJSEvent('audioBecomingNoisy')
  → audio-focus.service.ts window listener
  → store.pausePlayback()
```

**No auto-resume** when focus returns after noisy event — user must tap resume.

Init: **`initAudioFocusService()`** in **`App.vue`** (once).

---

## Task removal behaviour

**Trigger:** User swipes app from Android recents.

**Problem:** Activity and Capacitor bridge are destroyed while ExoPlayer / FGS may continue — audio with dead UI and log spam (“No listeners found”).

**Solution (shipped):** Postinstall patch on **`@capawesome`** **`AndroidForegroundService.onTaskRemoved()`**:

1. Stop foreground notification / service teardown
2. **`Process.killProcess(myPid())`** — intentional; JS cannot run cleanup

**Scope:** Recents swipe only — **not** Home, app switch, or screen lock.

**Re-apply:** `scripts/patch-android-foreground-service.cjs` on **`postinstall`** and **`capacitor:sync:after`**.

Detail: [`../mobile/android-native-customizations.md`](../mobile/android-native-customizations.md).

---

## Background playback constraints

| Constraint | Detail |
| --- | --- |
| **Android production path** | NativeAudio **`backgroundPlayback`** + FGS + **`POST_NOTIFICATIONS`** (API 33+) |
| **Web / `ionic serve`** | No FGS; **`useAppLifecycleAudio`** pauses on background unless FGS flag false |
| **Lifecycle composable** | If **`isBackgroundAudioRunning()`** → **no pause** on **`appStateChange`** background |
| **Return from lifecycle pause** | **No auto-resume** — toast prompts manual resume |
| **iOS** | FGS no-op; NativeAudio background behaviour depends on plugin/iOS — **Android is reference platform** |
| **Live reload** | Invalid for validating background/offline — use installable build |
| **Battery** | Multi-layer ExoPlayer + FGS — ambient use case; no sample-accurate DSP |

---

## MiniPlayer lifecycle

**Mount:** **`TabsLayout.vue`** only — fixed above tab bar (`z-index: 200`, height **68px**).

**Visibility (`MiniPlayer.vue` computed):**

```
visible =
  !route.meta.hideMiniPlayer
  && currentVibeId !== null
  && playbackState ∈ { preparing, playing, paused }
```

**Hidden when:** **`idle`**, **`error`**, or route **`meta.hideMiniPlayer`** (e.g. **`/vibes/:id/sounds`** inside tabs).

**Full player route (`/vibes/:id/player`):** Lives **outside** **`TabsLayout`** — MiniPlayer **not mounted** at all on that screen. User returns to tab routes to see MiniPlayer again.

**Controls:**

- Play/pause disabled while **`preparing`** (spinner)
- Stop → **`stopPlayback()`**
- Tap bar → navigate **`/vibes/:id/player`**

**Padding:** **`--app-mini-player-height`** on **`TabsLayout`** ion-page cascades bottom padding to scroll areas when visible.

---

## Route lifecycle

| Route / action | Playback |
| --- | --- |
| **`/vibes/:id/player`** mount | Load vibe + sounds → **`buildPlan`** → user taps play |
| **`VibePlayerPage` unmount** | **Does not** **`stopAll`** — session continues for MiniPlayer |
| **Back from player** | **`router.back()`** — audio continues |
| **Navigate tabs with active session** | MiniPlayer visible (unless **`hideMiniPlayer`**) |
| **User Stop** (player menu or MiniPlayer) | **`stopPlayback()`** — full teardown |

**Execution plan:** Built on player mount; shared **`usePlayerEngine`** ref may retain plan when returning from manage-sounds flow.

Cross-link routing standard: [`../../standards/front-vibes-ionic-routing.md`](../../standards/front-vibes-ionic-routing.md).

---

## Known limitations

| Area | Limitation |
| --- | --- |
| **Fades** | Pivot/plan fade fields **ignored** at runtime |
| **Seamless loop** | ExoPlayer / plugin loop — **not** gapless; see [`native-loop-fadein.md`](native-loop-fadein.md) |
| **Interval mode** | Tick length = file duration; gap after **`ended`**; chain **stalls** if **`complete`** never fires |
| **`tick_duration_seconds`** | **Not implemented** (code comments only) |
| **Partial layers** | Invalid URL / bad interval skipped; play may proceed with toast |
| **Prepare timeout** | **25s** → **`error`** → **`idle`** |
| **Permanent focus loss** | **`stopPlayback`** — session cleared (not pause-with-resume) |
| **Offline URL drift** | Manifest exact-match only; API URL change invalidates local file until re-download |
| **AudioEngine split** | Playback orchestration **not** fully behind **`AudioEngine`** interface |
| **Web fallback** | **`HTMLAudioElement`** — dev convenience; different pause/background semantics |
| **Volume silence** | Plugin volume floor ~0.1 — true silence via **stop**, not volume 0 |
| **Multi-notification Android** | Two notifications by design — not a bug |
| **Task kill** | Recents swipe terminates process — by design |

---

## Rules

### Ownership

| Rule | Requirement |
| --- | --- |
| UI → store | Components call **`usePlayerStore`** actions only |
| Store → services | Store orchestrates; does not import **`NativeAudio`** |
| Services → native | **`audio-player.service`** and cache path in **`audio-engine`** only |
| Plan | **`buildVibeExecutionPlan`** is pure — no audio I/O |

### Native integration

| Rule | Requirement |
| --- | --- |
| Configure once | **`NativeAudio.configure`** at **`audio-player.service`** load — do not duplicate conflicting configs |
| Asset ids | **`vibe-layer-{soundId}`** — stable per catalog sound id |
| FGS pairing | Start FGS on **`playVibe`**; stop on **`stopPlayback`** and session end |
| Task removal | Keep **`patch-android-foreground-service.cjs`** applied after **`cap sync`** |
| Platform regen | Re-apply [`android-native-customizations.md`](../mobile/android-native-customizations.md) after **`cap rm/add android`** |

### State sync

| Rule | Requirement |
| --- | --- |
| Prepare | UI **`playing`** only after **`onPrepared`** — not immediately after **`playPlan`** |
| Focus resume | Auto-resume **only** when **`_pausedByAudioFocus`** |
| Session end | Natural layer completion → store callback → **`idle`** + stop FGS |
| Plan rebuild | **`_playPlanInProgress`** must suppress premature session-ended |

### What not to do

- Do **not** add JS crossfade / volume ramp “fades” without architecture review.
- Do **not** use **`NativeAudio.preload`** as offline download.
- Do **not** document or ship **unsupported** native engine APIs as current behaviour.
- Do **not** bypass **`resolvePlaybackAssetUrl`** for playback URL selection.

---

## Risks

| Risk | Mitigation |
| --- | --- |
| Direct **`NativeAudio`** in components | Code review; store/service boundary |
| Lost FGS / MainActivity patch after **`cap sync`** | **`capacitor:sync:after`** patch script; checklist doc |
| Pinia/native desync on focus | Single global **`playbackState`** listener + store callbacks |
| Interval stall | Document; monitor **`complete`** events; future native work TBD |
| SimpleCache mistaken for offline | [`audio-cache.md`](audio-cache.md) + Settings copy |
| **`AudioEngine` interface drift** | Document partial adoption; migrate orchestration only with ADR |

---

## Validation

**Architecture review**

- [ ] New playback code goes through **`player.store`** / **`audio-player.service`**
- [ ] No **`NativeAudio`** imports in `views/` or `components/` (except service layer)
- [ ] FGS start/stop paired with store session lifecycle
- [ ] Focus/noisy handlers update Pinia, not local component state

**Manual (Android installable build)**

1. Play vibe → background app → audio continues ≥5 min; MiniPlayer still **`playing`**
2. Lock screen → media notification controls pause/resume
3. Unplug wired headset → playback pauses
4. Transient focus (e.g. voice assistant) → pause → resume when focus returns (if focus-paused)
5. Swipe from recents → process killed; audio stops
6. Player page back → MiniPlayer on tab routes; audio continues

---

## Related docs

| Document | Relationship |
| --- | --- |
| [`../../specs/vibes/playback-runtime/spec.md`](../../specs/vibes/playback-runtime/spec.md) | Feature spec — journeys, FRs, failure cases |
| [`../../specs/vibes/execution-plan/spec.md`](../../specs/vibes/execution-plan/spec.md) | Plan contract — `VibeExecutionLayer`, timing, offline URL identity |
| [`../mobile/android-native-customizations.md`](../mobile/android-native-customizations.md) | Manifest, MainActivity, FGS patch, two-notification model |
| [`audio-engine-fade-limitations.md`](audio-engine-fade-limitations.md) | Why fades / seamless loops are not shipped |
| [`audio-cache.md`](audio-cache.md) | ExoPlayer SimpleCache vs offline download vs snapshot |
| [`native-loop-fadein.md`](native-loop-fadein.md) | Historical native loop investigation |
| [`../../standards/front-vibes-ionic-routing.md`](../../standards/front-vibes-ionic-routing.md) | Routes, **`hideMiniPlayer`**, tab layout |

### Implementation map

| Module | Path |
| --- | --- |
| Pinia store | `front_vibes/src/stores/player.store.ts` |
| Orchestration | `front_vibes/src/services/audio-player.service.ts` |
| Planner | `front_vibes/src/services/player-engine.service.ts` |
| AudioEngine | `front_vibes/src/services/audio-engine/` |
| FGS | `front_vibes/src/services/backgroundAudio.service.ts` |
| Headset | `front_vibes/src/services/audio-focus.service.ts` |
| App lifecycle | `front_vibes/src/composables/useAppLifecycleAudio.ts` |
| MiniPlayer | `front_vibes/src/components/MiniPlayer.vue` |
| Tabs shell | `front_vibes/src/views/TabsLayout.vue` |
| Player page | `front_vibes/src/views/VibePlayerPage.vue` |

When playback architecture changes, update **this file first**, then the playback spec and linked architecture notes.
