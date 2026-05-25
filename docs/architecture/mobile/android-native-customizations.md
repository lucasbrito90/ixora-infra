# Android native customizations — Capacitor mobile

**Status:** Active architecture (source of truth)  
**Scope:** `front_vibes` Android platform (`android/`), native plugins, manual patches  
**Stack:** Ionic + Vue 3 + Capacitor 8, `@capgo/native-audio`, `@capawesome-team/capacitor-android-foreground-service`

---

## Purpose

Document **manual Android native changes** that Capacitor **does not fully manage**, so upgrades, platform recreation, and AI-assisted work **preserve background audio, notifications, audio focus, Google Sign-In, and task-removal behaviour** without silently losing customizations.

This file is **architecture and operational policy**. Feature-level playback rules live in audio docs; offline download strategy lives in [`../audio/audio-cache.md`](../audio/audio-cache.md).

---

## Context

The Ixora mobile app is **not** a stock Capacitor Android project. Several capabilities require **hand-edited** `AndroidManifest.xml`, `MainActivity.java`, drawable assets, Firebase config, and a **postinstall patch** to the foreground-service plugin.

| Capability | Why native work is required |
| --- | --- |
| Background audio | Android kills background processes without a **Foreground Service** |
| Lock screen / MediaSession | Native `MediaSessionCompat` via `@capgo/native-audio` config |
| Audio focus | `AudioManager` events bridged through plugin + app policy |
| Headset disconnect | `ACTION_AUDIO_BECOMING_NOISY` needs a **`BroadcastReceiver`** in `MainActivity` |
| Runtime notifications | **`POST_NOTIFICATIONS`** on Android 13+ (API 33+) |

Capacitor CLI operations (`cap sync`, upgrades) may **regenerate or merge** manifest and activity files. **`npx cap rm android`** / **`npx cap add android`** regenerate the platform **from scratch** and **erase** manual work documented here.

---

## Current Decision

1. **Manual native customizations are intentional and mandatory** for production Android behaviour; treat this document as the re-application checklist after any platform churn.
2. **Never run `npx cap rm android` or `npx cap add android`** without a **full backup** and a plan to re-apply every item in this doc (including `google-services.json`, `ic_stat_audio`, MainActivity receiver, manifest permissions/services, foreground-service patch).
3. **`AndroidManifest.xml`** declares Foreground Service, **media playback** foreground service type, **wake lock**, and **notification** permissions, plus `@capawesome` receiver/service entries.
4. **`MainActivity.java`** registers **`ACTION_AUDIO_BECOMING_NOISY`**, bridges **`audioBecomingNoisy`** to JS via `getBridge().triggerWindowJSEvent(...)`.
5. **Background audio** requires a **Foreground Service** in addition to `@capgo/native-audio` `backgroundPlayback` — otherwise Android may kill the process after ~1–2 minutes.
6. The app runs **two notification channels by design**:
   - **NativeAudio media notification** (lock screen controls, artwork)
   - **Foreground service indicator** (low-importance process keepalive)
7. **`POST_NOTIFICATIONS`** is declared in the manifest **and** requested at runtime on Android 13+ before starting the foreground service.
8. **`NativeAudio.configure`** uses **`backgroundPlayback: true`**, **`showNotification: true`**, **`focus: true`** (once at startup in `audio-player.service.ts`).
9. **Components must not call `NativeAudio` directly** — **Pinia / store actions** own playback state; services wrap native calls.
10. **Audio focus** and **headset disconnect** events **pause / resume / stop** per the existing policy table (with `_pausedByAudioFocus` guard).
11. **Swipe from recents (task removal)** must **stop audio** — achieved by patching `@capawesome` **`AndroidForegroundService.onTaskRemoved()`** (JS bridge is already dead; **`killProcess()`** is intentional here).
12. **`google-services.json`**, Firebase Android app + SHA-1, and **Web Client ID** for `@codetrix-studio/capacitor-google-auth` remain required and documented.
13. **`npm install --legacy-peer-deps`** for **`capacitor-google-auth`** peer mismatch with Capacitor 8 is **intentional** — do not remove without device testing.
14. **`ic_stat_audio`** must be a **monochrome** (white-on-transparent) vector drawable.
15. **Every Capacitor upgrade** must include diff/review of **`AndroidManifest.xml`** and **`MainActivity.java`**.

---

## Architecture

### Layering (JS)

```
UI components
      │  (no direct NativeAudio)
      ▼
player.store.ts          ← playback state source of truth
      │
      ├── audio-player.service.ts     ← NativeAudio runtime
      ├── backgroundAudio.service.ts  ← ForegroundService keepalive
      └── audio-focus.service.ts      ← audioBecomingNoisy → pause
      ▼
@capgo/native-audio (ExoPlayer) + @capawesome foreground service
      ▼
MainActivity.java (BroadcastReceiver) + AndroidManifest permissions/services
```

### MainActivity — headset / “noisy” audio

**File:** `android/app/src/main/java/io/ionic/starter/MainActivity.java`

- Register `BroadcastReceiver` for **`AudioManager.ACTION_AUDIO_BECOMING_NOISY`** in **`onResume()`**; unregister in **`onPause()`**.
- On broadcast → **`triggerWindowJSEvent("audioBecomingNoisy", "{}")`**.
- JS: **`audio-focus.service.ts`** listens on `window`; **`player.store.ts`** registers **`pausePlayback()`** callback.
- Overrides **`onResume` / `onPause` must stay `public`** (Java cannot narrow `BridgeActivity` visibility).

### AndroidManifest — permissions and services

**File:** `android/app/src/main/AndroidManifest.xml`

**Permissions (beyond Capacitor defaults):**

| Permission | Role |
| --- | --- |
| `FOREGROUND_SERVICE` | Start/maintain foreground service |
| `FOREGROUND_SERVICE_MEDIA_PLAYBACK` | Media playback FGS type (Android 14+) |
| `WAKE_LOCK` | CPU stay awake during background playback |
| `POST_NOTIFICATIONS` | Android 13+ notifications (also **runtime** request) |

**Components:**

- `NotificationActionBroadcastReceiver` (`@capawesome`)
- `AndroidForegroundService` with **`android:foregroundServiceType="mediaPlayback"`**

### Two-notification model

| Notification | Source | Purpose | Channel / importance |
| --- | --- | --- | --- |
| **Media** | `@capgo/native-audio` (`showNotification: true`) | Lock screen controls, artwork, MediaStyle | Plugin channel (`native_audio_channel`), default |
| **Foreground indicator** | `@capawesome-team/capacitor-android-foreground-service` | Process keepalive | `vibes_bg_service`, **low** importance |

The indicator is **low importance** so it does not compete visually with the rich media notification.

**Runtime (Android 13+):** `backgroundAudio.service.ts` calls **`ForegroundService.checkPermissions()`** / **`requestPermissions()`** before **`startForegroundService()`**. Denial may show a toast; behaviour varies by device.

**Typical constants:** `SERVICE_TYPE_MEDIA_PLAYBACK = 2`, channel `vibes_bg_service`, notification id `101`, icon **`ic_stat_audio`**.

**Lifecycle (store-driven):**

- **`playVibe()`** → `startBackgroundAudio(vibeName)` (permissions → channel → start FGS)
- **`stopPlayback()`** → `stopBackgroundAudio()`
- **`switchVibe()`** → `updateBackgroundAudioTitle(...)`

### NativeAudio configuration

One-time at startup (`audio-player.service.ts`):

```typescript
await NativeAudio.configure({
  backgroundPlayback: true,
  showNotification: true,
  focus: true,
});
```

Playback modes use stable asset ids `vibe-layer-{soundId}`. Notification metadata (`title`, `artist`, `artworkUrl`) comes from Pinia via `setNotificationVibeName()` / `setNotificationArtworkUrl()` on each preload.

### Audio focus policy

Plugin registers as **`AudioManager.OnAudioFocusChangeListener`** when `focus: true`. Ducking for brief interruptions is handled by **Android OS** (`AUDIOFOCUS_GAIN_TRANSIENT_MAY_DUCK`); JS reacts to **`playbackState`** reasons:

| Focus situation | `playbackState` reason | App action |
| --- | --- | --- |
| Transient loss (GPS, brief alert) | `audioFocusLossTransient` | `pausePlayback()`; set **`_pausedByAudioFocus = true`** |
| Focus regained | `audioFocusGain` | `resumePlayback()` **only if** `_pausedByAudioFocus` |
| Permanent loss (call, other app) | `audioFocusLoss` | `stopPlayback()`; clear **`_pausedByAudioFocus`** |

**Headset / Bluetooth unplug:** not handled by NativeAudio — **`ACTION_AUDIO_BECOMING_NOISY`** → **`audioBecomingNoisy`** → **`pausePlayback()`** (no auto-resume via focus gain for this path).

Remote controls (`reason.startsWith('remote')`) route to store handlers for play/pause/stop.

### Task removal (swipe from recents)

**Problem:** Activity/WebView and JS bridge are destroyed; **ExoPlayer and FGS can keep running** → “No listeners found” log spam and audio with dead UI.

**Why JS cannot fix it:** bridge gone before cleanup; `NativeAudio.deinitPlugin()` / `stopForegroundService()` from JS fails silently.

**Solution:** **`scripts/patch-android-foreground-service.cjs`** injects **`onTaskRemoved()`** into plugin **`AndroidForegroundService`** (already in merged manifest via AAR — survives `cap sync` manifest rewrite unlike a custom manifest-only service).

On task removal: stop foreground notification, then **`Process.killProcess(myPid())`** — **only** on recents swipe, not Home/lock/app switch. **`START_STICKY` does not restart** after user-initiated task removal.

**Hooks (re-apply patch idempotently):**

```json
"postinstall": "patch-package && node scripts/patch-android-foreground-service.cjs",
"capacitor:sync:after": "node scripts/patch-android-foreground-service.cjs"
```

**adb:** `adb logcat -s IxoraTaskRemoved IxoraForegroundServiceStop IxoraNativeAudioStop NativeAudio`

### Google Sign-In (native)

**Plugin:** `@codetrix-studio/capacitor-google-auth` — native path on device (WebView popup unreliable).

**Requirements (must remain documented):**

1. Firebase Android app with correct package name (`io.ionic.starter`)
2. **SHA-1** for debug and release keystores in Firebase Console
3. **`android/app/google-services.json`** present (lost if platform recreated without backup)
4. Google provider enabled in Firebase Authentication
5. **Web Client ID** (not Android client id) → `VITE_GOOGLE_WEB_CLIENT_ID` / `capacitor.config.ts` `GoogleAuth.serverClientId` + `GoogleAuth.initialize()` in `main.ts`

**Peer dependency:** plugin declares Capacitor 6 peers; project uses Capacitor 8 — works on device; installs require:

```bash
npm install --legacy-peer-deps
```

Do **not** use **`npm install --force`**. Do **not** remove **`--legacy-peer-deps`** or bump google-auth without **physical device** sign-in testing.

---

## Rules

### Platform lifecycle — critical warnings

> **NEVER run `npx cap rm android` or `npx cap add android` without a full backup and re-application plan.**

Recreating `android/` destroys at minimum:

- Custom **`MainActivity.java`** (noisy receiver)
- Custom **`AndroidManifest.xml`** entries
- **`scripts/patch-android-foreground-service.cjs`** target state in `node_modules` (re-run hooks after install)
- **`android/app/google-services.json`**
- **`android/app/src/main/res/drawable/ic_stat_audio.xml`**
- App icons under **`res/mipmap-*`** (regenerate with `capacitor-assets` if needed)

### Capacitor upgrade checklist

After **`npm update @capacitor/*`**:

1. Diff **`AndroidManifest.xml`** — restore permissions and service/receiver blocks from this doc
2. Verify **`MainActivity.java`** — Capacitor may regenerate an empty activity
3. Check **`android/app/build.gradle`** (`compileSdk` / `targetSdk`)
4. **`npx cap sync android`** + test on **physical device**
5. Re-run **`npx capacitor-assets generate --android`** if icons missing
6. Confirm **`patch-android-foreground-service.cjs`** still applied (`postinstall` / `capacitor:sync:after`)

### NativeAudio and stores

- Configure NativeAudio **once** with **`backgroundPlayback`**, **`showNotification`**, **`focus`**.
- **Never** call **`NativeAudio`** from Vue components — use **Pinia actions** only.
- Do **not** call **`NativeAudio.clearCache()`** from UI — use **`AudioEngine.clearAudioCache()`** (see audio-cache doc).
- Apply **audio focus** and **remote control** rules via existing **`playbackState`** listener — do not bypass `_pausedByAudioFocus` semantics.

### Notifications and assets

- Maintain **two channels** — do not collapse into one notification without an architecture review.
- **`ic_stat_audio`**: white-on-transparent vector only; coloured icons render as solid squares on Android 5+.
- Request **`POST_NOTIFICATIONS`** at runtime on API 33+ before starting FGS.

### Dependencies

- **`--legacy-peer-deps`** for **`capacitor-google-auth`** (and related install scripts) is **intentional**.
- After **`npm install`**, ensure foreground-service **patch script** ran.

### Task removal

- Do not rely on JS teardown when the user swipes the app from recents.
- Keep **`onTaskRemoved()`** patch on `@capawesome` foreground service unless an equivalent native stop path is proven on device.

---

## Risks

| Risk | Impact | Mitigation |
| --- | --- | --- |
| `cap rm` / `cap add android` | Total loss of custom native files | Backup + re-apply from this doc; **never** run casually |
| Capacitor upgrade overwrites manifest/activity | Missing FGS permissions or noisy receiver | Post-upgrade diff checklist |
| No FGS while background playing | Process killed; playback stops | Start `@capawesome` FGS on play; two-notification model |
| Missing runtime notification permission | FGS/start failures on Android 13+ | `checkPermissions` / `requestPermissions` before start |
| Direct `NativeAudio` from components | Split brain vs Pinia; broken focus/remote handling | Store-only access |
| Ignoring audio focus policy | Wrong pause/resume; fights with phone/Spotify | Existing reason → action table |
| Swipe from recents without patch | Audio continues with dead WebView | `onTaskRemoved()` + `killProcess()` patch |
| Wrong notification icon | Broken/status bar UX | Monochrome `ic_stat_audio` |
| Removing `--legacy-peer-deps` | Install failures or broken google-auth | Keep intentional flag; test sign-in on device |
| Lost `google-services.json` | Native Google Sign-In fails | Document path; backup before platform recreate |

---

## Validation

**After any native-affecting change (upgrade, sync, manifest edit, patch script change)**

- [ ] `AndroidManifest.xml` contains FGS, `FOREGROUND_SERVICE_MEDIA_PLAYBACK`, `WAKE_LOCK`, `POST_NOTIFICATIONS`, capawesome receiver + service
- [ ] `MainActivity.java` registers/unregisters noisy receiver; public overrides preserved
- [ ] `ic_stat_audio.xml` exists and is monochrome
- [ ] `google-services.json` present; SHA-1 registered in Firebase
- [ ] `postinstall` / `capacitor:sync:after` patch hooks present in `package.json`
- [ ] Physical device test: play → Home → audio continues
- [ ] Physical device test: play → lock → audio continues
- [ ] Physical device test: swipe from recents → **audio stops** (logcat tags above)
- [ ] Headset unplug → playback pauses (`audioBecomingNoisy`)
- [ ] Incoming call / permanent focus loss → stop per policy
- [ ] Google Sign-In on native Android after `npm install --legacy-peer-deps`

**Not valid for native audio/offline validation:** `ionic capacitor run android -l` (live reload) — see [`../audio/audio-cache.md`](../audio/audio-cache.md).

---

## Related Files

| Location | Path |
| --- | --- |
| **Central (this repo)** | `docs/architecture/audio/audio-cache.md` |
| | `docs/architecture/audio/audio-engine-fade-limitations.md` |
| | `docs/architecture/audio/native-loop-fadein.md` |
| **front_vibes (repo copy)** | `docs/android-native-customizations.md` — keep aligned with this file |
| | `android/app/src/main/AndroidManifest.xml` |
| | `android/app/src/main/java/io/ionic/starter/MainActivity.java` |
| | `android/app/google-services.json` |
| | `android/app/src/main/res/drawable/ic_stat_audio.xml` |
| | `scripts/patch-android-foreground-service.cjs` |
| | `src/services/backgroundAudio.service.ts` |
| | `src/services/audio-player.service.ts` |
| | `src/services/audio-focus.service.ts` |
| | `src/stores/player.store.ts` |
| | `src/services/auth.service.ts` |
| | `capacitor.config.ts` |
| | `package.json` (`postinstall`, `capacitor:sync:after`) |
| **Plugins** | `@capgo/native-audio`, `@capawesome-team/capacitor-android-foreground-service`, `@codetrix-studio/capacitor-google-auth` |
| **Issues / detail** | `front_vibes/docs/issues/audio-engine-fade-limitations.md`, `front_vibes/docs/issues/native-loop-fadein.md` |

When changing Android native behaviour, update **this file first**, then sync the `front_vibes` copy and verify on a **physical device**.
