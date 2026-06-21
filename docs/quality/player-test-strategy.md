# Player test strategy — lightweight sensors

**Status:** Strategy (next implementation step)  
**Scope:** Ixora mobile playback (`front_vibes`) + supporting API (`back_vibes`)  
**Applies to:** Engineers implementing tests after the [quality harness baseline](../quality-harness.md)

> **Strategy only.** No test implementation, no heavy CI, no device farm. Defines **where** to invest automation vs manual diagnosis using **lightweight sensors**.

**Related:** [Quality harness](../quality-harness.md) · [Playback runtime](../architecture/audio/playback-runtime.md) · [Execution plan spec](../specs/vibes/execution-plan/spec.md) · [Mobile CDN validation](../architecture/storage/mobile-cdn-validation.md)

---

## Purpose

Give the team a **shared map** for validating player behaviour without duplicating effort across web, API, native, and manual channels.

Principles:

1. **Automate what is fast and stable** — web UI flows and Laravel contracts.
2. **Smoke what only runs on device** — minimal Appium/WebdriverIO checks for native plugin + process survival.
3. **Diagnose what automation cannot see** — dev-only **Player Debug Harness** on real devices (NativeAudio, offline `file://`, timers, focus).
4. **Do not block PRs on device farms** — native full matrix stays manual + harness until explicitly funded.

---

## Lightweight sensors (tooling roles)

| Sensor | Repo | Role | When to use |
| --- | --- | --- | --- |
| **Pest** | `back_vibes` | API contracts, auth sync, vibe/sound payloads, execution-plan **data** (not playback) | Every PR touching API or resources consumed by the player |
| **Playwright** | `front_vibes` (web) | Fast UI + API-integrated E2E in Chromium (and optionally WebKit) | Transition UX, MiniPlayer visibility, offline UI states **in browser** |
| **WebdriverIO + Appium** | `front_vibes` (native) | **Critical native smoke only** — install, launch, one play path, notification/FGS presence | Before release or after NativeAudio / Android manifest / foreground-service changes |
| **Player Debug Harness** | `front_vibes` (dev builds) | Manual runtime diagnosis — store state, execution plan, playability, resolved URL source, runtime logs | Native device debugging; reproducing timer/orphan/lifecycle bugs |
| **Vitest** | `front_vibes` | Pure unit tests for planners/helpers (`player-engine.service`, diagnostics utils) | Layer validation rules, URL classification — no audio I/O |

### What we are **not** adding in this step

- Device farm (BrowserStack, Sauce, Firebase Test Lab matrix)
- Heavy CI pipelines running Appium on every push
- Replacing the existing Cypress scaffold in one shot — **new E2E work targets Playwright**; Cypress remains optional/legacy until removed by ADR

### Player Debug Harness (manual sensor)

Shipped in dev builds only (`import.meta.env.DEV`):

- **Component:** `front_vibes/src/components/debug/PlayerDebugPanel.vue`
- **Access:** open `/vibes/:id/player` → expand **Player Debug Harness** at bottom of player page
- **Reads:** `usePlayerStore`, `usePlayerEngine`, `audioPlayerService`, `audioEngine.resolvePlaybackAssetUrl` (display-only)
- **Does not:** start/stop audio, mutate plans, or import `@capgo/native-audio` in Vue

Use the harness to confirm hypotheses Playwright/Appium cannot assert (e.g. resolved `file://` vs HTTPS, playable layer count vs attached native layers, prepare handshake timing).

---

## Test areas

Each area lists **behaviour to protect**, **preferred sensor**, and **notes** for the first implementation pass.

### 1. Transition UX

Playback state machine and per-route UI must stay aligned with [`player.store.ts`](../../front_vibes/src/stores/player.store.ts) and the prepare handshake documented in [playback-runtime](../architecture/audio/playback-runtime.md).

| Scenario | Expected behaviour | Primary sensor | Notes |
| --- | --- | --- | --- |
| **Play → preparing → playing** | Center control shows preparing spinner; `playbackState` becomes `playing` only after audio engine confirms audible start; elapsed clock starts on `playing` | Playwright (web HTML audio path) · Harness (native) | Web uses HTMLAudio fallback — native timing must be validated on device with harness |
| **Pause / resume** | Pause stops elapsed ticker; resume restores `playing` without re-entering `preparing` unless session was stopped | Playwright · Harness | Assert MiniPlayer + full player stay in sync |
| **Vibe switching** | Starting vibe B while A plays stops A’s session atomically via `playVibe`; UI shows B context; no double audio | Playwright · Harness | Critical for store + `audioPlayerService.playPlan()` guard |

**Out of scope for first Playwright pass:** lock-screen media controls, audio-focus auto-resume edge cases (manual + harness).

---

### 2. Runtime lifecycle

Navigation must **not** stop audio when leaving the full-screen player — MiniPlayer owns continuity.

| Scenario | Expected behaviour | Primary sensor | Notes |
| --- | --- | --- | --- |
| **Leave player page** | Audio continues; `clearPlan()` on unmount is OK — plan rebuilds on return | Playwright | Route away from `/vibes/:id/player` to `/vibes` or `/home` |
| **MiniPlayer remains visible** | TabsLayout shows MiniPlayer when `currentVibeId` set and route meta does not hide it | Playwright | Player route sets `hideMiniPlayer: true`; tab routes show bar |
| **Return to player** | Same vibe shows pause/playing state; plan rebuilt from API or offline snapshot | Playwright | |
| **Stop playback** | `stopPlayback` → idle, MiniPlayer hides, foreground service stops (Android) | Playwright (web) · Appium smoke (native stop) · Harness | Native FGS stop = one Appium smoke assertion max |

---

### 3. Offline behaviour

Offline spans **UI**, **filesystem manifest**, and **URL resolution** — full fidelity requires device + harness; web Playwright covers **UI states** only.

| Scenario | Expected behaviour | Primary sensor | Notes |
| --- | --- | --- | --- |
| **Download for offline** | Native menu action caches layers + snapshot; `vibeOfflineReady` reflects download state | Manual + Harness · Appium smoke (download completes) | Playwright can mock API offline flags only — not real Filesystem writes |
| **Play offline** | Playback uses resolved `file://` when manifest matches current remote URL | Manual + Harness | Harness **Runtime source visibility** section |
| **Stale manifest warning / fallback** | When cached URL ≠ current `fileUrl`, runtime falls back to remote or skips with user-visible degradation | Manual + Harness · Pest (API payload consistency) | API tests ensure URLs in sync responses; client fallback is harness/manual |
| **Missing file handling** | Deleted local file → graceful skip / error path; no crash; store may enter `error` with toast | Manual + Harness | Document repro steps in harness logs |

Reference: [mobile CDN validation](../architecture/storage/mobile-cdn-validation.md), `front_vibes/docs/audio-cache.md`.

---

### 4. Layer orchestration

Client-side scheduling in `audio-player.service.ts` — modes from [execution plan](../specs/vibes/execution-plan/spec.md).

| Scenario | Expected behaviour | Primary sensor | Notes |
| --- | --- | --- | --- |
| **Loop** | Layer repeats until vibe stop or duration end | Vitest (plan) · Manual/Harness (native loop) | Playwright can assert UI “Loop” chip only |
| **Once** | Single play; `complete` listener removes layer; session ends when all layers done | Vitest · Harness | Watch harness playable count vs active layers |
| **Interval** | Repeats with `repeatIntervalSeconds` gap; invalid interval → layer skipped (planner + runtime) | Vitest · Harness | Harness shows interval missing repeat |
| **No duplicate timers** | Restart / switch / pause must not stack `_timerRef` or layer interval handles | Manual + Harness | Reproduce via rapid play/pause/switch; inspect runtime logs |
| **No orphan playback** | `stopAll` / session end clears native assets; no ghost audio after stop or vibe switch | Manual + Harness · Appium smoke | Smoke: play → stop → assert silence / no notification |

**Pest** validates API fields that feed the planner (`play_mode`, intervals, URLs) — not timer behaviour.

---

## Test matrix

Rows = **test areas**; columns = **who runs what** in the first implementation wave.

| Test area | Pest (`back_vibes`) | Vitest (`front_vibes`) | Playwright (web E2E) | Manual + Debug Harness (native) | WebdriverIO/Appium (native smoke) |
| --- | --- | --- | --- | --- | --- |
| **1. Transition UX** | Auth sync + vibe/sound payloads for player entry | Planner playability helpers | Play, preparing UI, pause/resume, vibe switch | Prepare handshake timing, native audible start, focus interruptions | Optional: one “tap play → notification appears” |
| **2. Runtime lifecycle** | — | — | Leave player, MiniPlayer visible, return, stop | Confirm audio survives navigation; FGS lifecycle | One navigation + stop smoke |
| **3. Offline behaviour** | Stable CDN URLs in API responses | Offline key helpers (if extracted) | Offline empty states / toasts (mocked network) | Download, play from `file://`, stale manifest, missing file | Optional: download menu completes |
| **4. Layer orchestration** | Sound attach rules, interval fields | `buildVibeExecutionPlan`, `isExecutionLayerPlayable` | Layer list UI, muted unplayable cards | Loop/once/interval on device, timer/orphan checks | One multi-layer play smoke |

### Effort guidance (first milestone)

| Tier | Investment | Target |
| --- | --- | --- |
| **T0 — already baseline** | Pest + lint/typecheck/build | Keep green per [quality-harness](../quality-harness.md) |
| **T1 — next** | Vitest for planner + diagnostics utils; 3–5 Playwright specs (auth mock, play lifecycle, MiniPlayer) | Web confidence without device |
| **T2 — native** | Document harness checklist; 1–2 Appium smokes (install, play, stop) | Release gate for native plugin changes |
| **T3 — deferred** | Full offline matrix automation, lock-screen matrix, device farm | Requires ADR + budget |

---

## Playwright setup (planned, not implemented)

Target: **`front_vibes`** against `ionic serve` / Vite dev server with **mocked or staging API**.

Suggested layout (future):

```
front_vibes/
  tests/e2e/playwright/
    auth.setup.ts          # storage state / Firebase stub
    player-transitions.spec.ts
    mini-player-lifecycle.spec.ts
    player-layers-ui.spec.ts
  playwright.config.ts
```

Conventions:

- Use **`data-testid`** on player controls sparingly (center play, MiniPlayer bar) — add only when implementing tests.
- Stub **`/api/auth/sync`** and vibe endpoints with route fixtures or `back_vibes` test DB — do not hit production Firebase in CI.
- **Do not** assert NativeAudio behaviour in Playwright — treat web as **UI + store contract** sensor only.

---

## WebdriverIO / Appium setup (planned, minimal)

Target: **one Android smoke suite**, run locally before release — not per-PR CI.

Suggested scope (≤ 5 scenarios):

1. App launches signed-in (or test account)
2. Open a vibe with known sounds → tap play
3. Assert media notification or playing indicator (platform-specific)
4. Navigate away → assert MiniPlayer still present
5. Stop → assert playback ended

Keep selectors stable; prefer accessibility labels over brittle XPath. No farm — local USB device or emulator only.

---

## Manual harness checklist (native)

Use on a **real Android device** with a **dev build** (`npm run dev` + Capacitor live reload, or debug APK).

Before testing:

- [ ] Player Debug Harness expanded
- [ ] Runtime logs visible
- [ ] Known vibe with loop + once + interval layers (or separate vibes)

During scenario, record:

| Field | Why |
| --- | --- |
| `playbackState` / `isPlaying` / `isPreparing` | Transition UX |
| `currentVibeId` vs route id | Vibe switching |
| Plan vs playable layer count | Skipped layers |
| Plan source vs resolved source | Offline / CDN |
| Service `hasActiveLayers` vs store | Desync bugs |

Paste relevant **Runtime logs** lines into bug reports.

---

## API tests (Pest) — player-adjacent scope

Pest protects **data the player consumes**, not playback itself.

| Domain | Example tests (future) |
| --- | --- |
| Auth | `POST /api/auth/sync` creates user, returns token shape |
| Vibes | Show vibe returns artwork + sound summary fields used by `playVibe` |
| Vibe sounds | Attach/update enforces `play_mode`, interval seconds, CDN `file_url` |
| Authorization | User cannot attach another user’s sounds |

Run: `composer test` in `back_vibes` (baseline).

---

## CI posture (explicitly light)

| Layer | CI (future) | Local (now) |
| --- | --- | --- |
| Pest | Optional single job on `back_vibes` PR | `composer test` |
| Vitest + lint + typecheck | Optional single job on `front_vibes` PR | harness commands |
| Playwright | **Deferred** — run locally until stable | `npx playwright test` (when added) |
| Appium | **Not in CI** | Manual pre-release |
| Debug Harness | Never in CI | Dev builds only |

No device farm. No parallel OS matrix. Expand only via ADR.

---

## Definition of done (implementation phase — later)

When this strategy moves to code, done means:

1. Vitest covers execution-plan playability rules used by the player.
2. Playwright covers **§1 Transition UX** and **§2 Runtime lifecycle** on web.
3. A one-page harness checklist is linked from PR template for native-touching changes.
4. Appium smoke documented with local run instructions (≤ 5 tests).
5. [Quality harness](../quality-harness.md) updated with **optional** Playwright command — not mandatory baseline until team promotes T1.

---

## Related documentation

| Document | Topic |
| --- | --- |
| [quality-harness.md](../quality-harness.md) | Mandatory local commands today |
| [playback-runtime.md](../architecture/audio/playback-runtime.md) | Store / service / native layering |
| [execution-plan spec](../specs/vibes/execution-plan/spec.md) | Layer fields and play modes |
| [mobile-cdn-validation.md](../architecture/storage/mobile-cdn-validation.md) | CDN + offline validation process |
| `front_vibes/src/components/debug/PlayerDebugPanel.vue` | Debug Harness implementation |
