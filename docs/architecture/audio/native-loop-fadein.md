# Native loop fade-in — historical investigation (Android)

**Status:** Historical investigation / native-engine research — **not current production behaviour**  
**Scope:** Android loop-mode fade-in experiments (`@capgo/native-audio` ~8.4.x, ExoPlayer / Media3)  
**Platform:** Android (primary); iOS noted only where relevant for future parity  
**Runtime note:** **Fades are disabled in production.** Loop layers start at target volume immediately. This document records **what was tried and why it was abandoned**—not what the app does today.

**Current policy:** See [`audio-engine-fade-limitations.md`](audio-engine-fade-limitations.md) for active architecture constraints.

---

## Purpose

Preserve a **detailed engineering record** of Ixora’s investigation into **native fade-in for loop playback** on Android: reproduction steps, root-cause analysis, workaround attempts, observed artefacts, and lessons for **future first-party or upstream native engine work**.

This file is **historical and exploratory**. It does **not** describe shipping runtime behaviour, does **not** authorize re-enabling fades without architecture review, and must **not** be read as a promise that loop fades work or will ship soon.

---

## Context

### Product expectation (unmet at time of investigation)

Ambient vibe layers often use **`play_mode = loop`** with long **`fade_in_seconds`** values (e.g. 120 s) so audio blends in gently. Users configuring fades expected:

1. Layer starts near silence.
2. Volume ramps to target over the configured duration.
3. Loop continues seamlessly at target level.

### Observed behaviour (pre-disable)

**Reproduction (historical):**

1. Add a sound to a vibe: `play_mode = loop`, `volume ≈ 90%`, `fade_in_seconds = 120`.
2. Start the vibe on Android.
3. **Expected:** gradual ramp from silence over ~2 minutes.
4. **Actual:** audio started immediately at ~90% — abrupt intrusion, not ambient blend-in.

### Stack at time of investigation

| Layer | Component |
| --- | --- |
| Bridge | Capacitor — `@capgo/native-audio` (~8.4.2) |
| Android player | ExoPlayer (`RemoteAudioAsset`) |
| Remote sources | HTTPS URLs (CDN); buffering before `STATE_READY` |
| App orchestration | `audio-player.service.ts` → `NativeAudio.loop()` |

### Why loop differed from once-mode

`NativeAudio.play()` could request fade via `playWithFadeIn(...)`. **`NativeAudio.loop()` had no fade parameter** and called Java `asset.loop()` only:

```java
player.setRepeatMode(Player.REPEAT_MODE_ONE);
player.play();
```

No initial volume reset, no `fadeIn()` invocation—so loop layers ignored fade configuration unless workarounds were added.

---

## Investigation Summary

| Phase | Approach | Outcome |
| --- | --- | --- |
| 1 | JS `setVolume` ramp after `loop()` | Failed — buffering race; fades skipped or mis-timed |
| 2 | Patch `setVolume` / `fadeTo` to use `getPlayWhenReady()` | Partial — ramps could start, but audible flash/click remained |
| 3 | Native `loopWithFadeIn()` via `node_modules` postinstall patch | Architecturally sound in theory; abandoned — patch fragility, CI build breakage, unresolved buffering flash |
| 4 | (Parallel) `play({ fadeIn: true })` for remote assets | Failed — Java `double`/`float` dispatch → wrong overload, crash |
| **Resolution** | Disable runtime fades; prefer deterministic `loop()` | **Current production policy** (see Current Decision) |

**Conclusion of investigation:** Reliable loop fade-in requires an **atomic native method on the Android UI thread** with buffering-aware volume handling—not bridge round-trips from JavaScript or fragile plugin patches.

---

## Findings

### F1 — Plugin API gap

- **`loop()`** exposes no `fadeIn`, `volume`, or `fadeInDuration` parameters.
- **`playWithFadeIn`** exists for once-mode but was not wired for loop repeat mode.
- Extending behaviour required **Java changes** in `RemoteAudioAsset`, `NativeAudio`, and possibly `AudioAsset`.

### F2 — ExoPlayer buffering vs bridge timing

- Capacitor resolves the **`loop()` promise** after scheduling `player.play()` on the UI thread—not after `STATE_READY`.
- During **`STATE_BUFFERING`**, Media3 **`player.isPlaying()` returns `false`** even when playback is imminently starting.
- Plugin **`fadeTo()`** gated on **`isPlaying()`**, so JS-initiated ramps after `loop()` were **silently skipped**; audio then appeared at full preloaded volume.

### F3 — Workaround 1: JS volume ramp after `loop()`

```typescript
await NativeAudio.loop({ assetId });
await NativeAudio.setVolume({ assetId, volume: 0.1 });
await NativeAudio.setVolume({ assetId, volume: target, duration: fadeInSeconds });
```

**Observed failure:** Each `setVolume` crossed the bridge while ExoPlayer was still buffering. Fade steps did not run; volume jumped to target when ready.

### F4 — Workaround 2: patch gating to `getPlayWhenReady()`

`RemoteAudioAsset.setVolume()` and `fadeTo()` were patched to gate on **`getPlayWhenReady()`** instead of **`isPlaying()`**.

**Observed failure:** Bridge round-trip still allowed a window where **preloaded volume was applied to AudioTrack** before the ramp took effect → **audible flash** at preloaded level, then ramp (or click when leaving buffering).

### F5 — Workaround 3: `loopWithFadeIn()` native patch

Added **`RemoteAudioAsset.loopWithFadeIn()`** running entirely on the UI thread:

```java
player.setRepeatMode(Player.REPEAT_MODE_ONE);
player.setVolume(0f);          // silence BEFORE play()
player.play();
fadeIn(player, durationMs, volume);
```

Bridge updated to accept optional `fadeIn` / `volume` / `fadeInDuration` on `loop()`; TS layer passed params.

**Implementation mechanism:** Postinstall script **`scripts/patch-native-audio-fade.cjs`** modifying files under `node_modules/@capgo/native-audio/`.

**Observed failures:**

- Patch caused **Android build failure** (75 Java compilation errors) when a script accidentally **truncated `AudioAsset.java`**.
- After repair, further validation was **stopped** due to:
  - **`node_modules` patch fragility** (lost on install/upgrade; CI/CD risk).
  - **Unresolved question** whether ExoPlayer still **pre-applies volume during `STATE_BUFFERING`**, causing flash even with in-thread `setVolume(0)` → `play()` → `fadeIn()`.

**Assessment:** Correct *shape* for a future native API (atomic, UI thread); **wrong delivery mechanism** (postinstall patches).

### F6 — Once-mode `playWithFadeIn` type dispatch bug

`NativeAudio.java` passed `fadeInDurationMs` as **`double`** into `RemoteAudioAsset.playWithFadeIn`, whose third parameter was **`float`**.

Java does not auto-narrow **`double → float`**, so dispatch fell through to base **`AudioAsset.playWithFadeIn(double, float, double)`**, which uses **`audioList.get(0)`** — empty for remote ExoPlayer assets:

```
CapacitorException: Index 0 out of bounds for length 0
```

**Workaround attempted:** Stop `fadeIn: true` on `play()`; use post-play JS ramp — same buffering race as loop (F3).

### F7 — Playback artefacts (cross-cutting)

| Artefact | Typical cause in experiments |
| --- | --- |
| Full-volume blast at loop start | Fade skipped during buffering; target volume applied at `STATE_READY` |
| Click / pop | Volume change while leaving `STATE_BUFFERING`; retroactive ExoPlayer volume application |
| Audible flash before ramp | Preloaded volume on AudioTrack before patched ramp engaged |
| Silent failed ramp | `fadeTo()` never ran because `isPlaying()` was false |

These artefacts motivated **abandoning fade experiments** rather than shipping degraded ambient playback.

### F8 — Why experiments were abandoned

1. **No reliable loop fade path** without native-first, atomic implementation.
2. **JS timing cannot synchronize** with ExoPlayer’s async state machine across the Capacitor bridge.
3. **Plugin patches** were **high maintenance**, broke builds, and did not survive dependency upgrades cleanly.
4. **`loopWithFadeIn` patch** was not fully validated against buffering volume pre-application.
5. Product priority shifted to **stable, deterministic ambient playback** over perceptual fade polish (see Architecture Implications).

---

## Technical Constraints

### ExoPlayer / Media3

- **`STATE_BUFFERING`** precedes audible output; bridge promises may resolve earlier.
- **`isPlaying()` ≠ “about to play”** during buffering; fade logic must use **`getPlayWhenReady()`** (or equivalent) if ramps should run before `STATE_READY`.
- Volume changes may be **buffered and applied at state transitions**—timing-sensitive; not sample-accurate from JS.
- **Loop repeat mode** does not by itself provide seamless/sample-accurate loop *boundaries*—separate from fade, but relevant to “seamless ambient” expectations.

### Capacitor bridge

- Each volume/fade step is an **async round-trip**; not atomic with `play()`.
- Multiple JS calls after `loop()` **race** with native buffering and preloaded gain.

### `@capgo/native-audio` plugin

- **SoundPool vs ExoPlayer** split (`isComplex` flag); remote HTTPS uses ExoPlayer path.
- Undocumented or fragile **JS/Java type contracts** (`double` vs `float`).
- **Not designed for extension** via ad-hoc `node_modules` edits.

### JavaScript layer

- **Manual timing** (`setTimeout`, sequential `await setVolume`) is **not reliable** for seamless loop fade-in.
- **No sample-accurate scheduling** relative to audio clock from the WebView layer.
- Simulating DSP (crossfades, overlapping layers) in JS risks **battery drain**, **non-deterministic mix**, and **artefacts**—explicitly out of scope for ambient stability policy.

---

## Architecture Implications

1. **Fade-in for loops belongs in native code** — single UI-thread method: `setVolume(0)` → configure repeat → `play()` → `fadeIn(...)`, with no intermediate bridge calls.
2. **The `AudioEngine` adapter** (`src/services/audio-engine/`) is the intended swap point for a future engine that exposes e.g. `loopLayer(..., { fadeIn })` — investigation informed the interface comments in `types.ts`.
3. **Current production architecture prefers deterministic looping** — `NativeAudio.loop()` at target volume — over **pseudo-smooth** fades that produced clicks, flashes, or silent ramp failures.
4. **Do not reintroduce postinstall Java patches** without a first-party plugin or upstream merge path.
5. **Do not implement experimental JS crossfade systems** without architecture review ([`audio-engine-fade-limitations.md`](audio-engine-fade-limitations.md)).
6. **DB fields `fade_in_seconds` / `fade_out_seconds`** may remain for backward compatibility and future native engine use; **runtime must ignore them** until a reviewed implementation ships.

---

## Current Decision

> **This section states production policy.** The investigation above is **not** what runs in the app today.

1. **Loop fade-in is disabled at runtime.** Layers start at **target volume immediately**.
2. **Fade-out is also disabled** (broader fade removal, May 2026 — see [`audio-engine-fade-limitations.md`](audio-engine-fade-limitations.md)).
3. **UI:** Fade controls hidden or non-functional for modes where fades cannot be honoured (e.g. loop fade-in hidden in vibe sound edit).
4. **Engine:** `audio-player.service.ts` does **not** apply `layer.fadeInSeconds` / `fadeOutSeconds` during playback.
5. **Database:** Values **preserved** for potential future native engine — **not deleted** solely because runtime ignores them.
6. **Patch script removed:** `scripts/patch-native-audio-fade.cjs` and related `node_modules` Java modifications were **removed** as part of abandoning the patch approach (historical reference may exist in git history only).
7. **Deterministic `NativeAudio.loop`** is the supported loop path until a new native engine is approved and documented.

**Do not read Findings or Future Directions as implying fades work in production today.**

---

## Future Directions

Research output for **potential** native-engine work — **not committed scope**:

### Target native API (illustrative)

```java
// RemoteAudioAsset or @ixora/native-audio — UI thread, atomic
public void loopWithFadeIn(double time, float targetVolume, float fadeInDurationMs) {
    runOnUiThread(() -> {
        ExoPlayer player = getActivePlayer();
        if (time != 0) player.seekTo(Math.round(time * 1000));
        player.setRepeatMode(Player.REPEAT_MODE_ONE);
        player.setVolume(0f);          // MUST happen before play()
        player.play();
        startCurrentTimeUpdates();
        fadeIn(player, fadeInDurationMs, targetVolume);
    });
}
```

```typescript
// Illustrative bridge — NOT current production API
NativeAudio.loop({
  assetId,
  volume: targetVol,
  fadeIn: true,
  fadeInDuration: fadeInSeconds,
});
```

### Implementation requirements (from investigation)

| Requirement | Rationale |
| --- | --- |
| Set volume to **0 synchronously on UI thread before `play()`** | Avoid full-volume start |
| **`fadeIn()` steps use `getPlayWhenReady()`**, not `isPlaying()` | Allow ramp during buffering |
| **Atomic native method** — no JS steps between silence and play | Eliminate bridge race |
| Fix **`double`/`float`** signatures for `playWithFadeIn` | Prevent wrong Java overload on remote assets |
| Validate **no AudioTrack flash** during `STATE_BUFFERING` | Open question from Workaround 3 |
| Deliver via **first-party plugin or upstream PR** — not postinstall patches | Maintenance and CI safety |
| Wire through **`AudioEngine`** adapter | Avoid Pinia/UI churn |

### Delivery options (planning only)

- **Option A — Custom Capacitor plugin** (e.g. `@ixora/native-audio`) with `loopWithFadeIn`, loop `fadeOut`, once-mode fade.
- **Option B — Upstream `@capgo/native-audio`** if a release adds loop fade and fixes type dispatch natively.

Before any re-enable: ADR, update [`audio-engine-fade-limitations.md`](audio-engine-fade-limitations.md), dedicated QA on device (not live reload).

---

## Risks

| Risk | Notes from investigation |
| --- | --- |
| Re-enabling JS ramps after `loop()` | Documented failures F3–F4; high artefact rate |
| Reviving `node_modules` patches | Build breakage (75 errors incident); upgrade fragility |
| Assuming `loopWithFadeIn` patch was production-ready | Validation incomplete; buffering flash unresolved |
| Using `play({ fadeIn: true })` on remote URLs | Crash via `Index 0 out of bounds` |
| UI showing fade fields without native support | User trust / QA mismatch |
| Sample-accurate or seamless loop expectations | ExoPlayer loop mode does not guarantee sample-accurate transitions |
| JS crossfade / DSP simulation | Overlap, pops, battery cost — policy forbids without review |

---

## Validation

### Historical reproduction (investigation era)

Used to **confirm the bug** and compare workarounds — **not** current release acceptance criteria:

- [ ] Vibe with `play_mode = loop`, `fade_in_seconds = 120`, high volume — **without** fade disable: observe immediate full volume (bug).
- [ ] Workaround 1: log or trace `setVolume` / `fadeTo` — confirm skip when `isPlaying() == false` during buffering.
- [ ] Workaround 2: confirm ramp starts but **flash/click** may still occur at loop start.
- [ ] Workaround 3: verify patch applied to correct Java files; full **non-live-reload** Android build (patch era only).

### If native engine work resumes (future — not production today)

- [ ] **Loop + fade-in:** silence → smooth ramp to target over configured duration on **cold start** and **warm start**.
- [ ] **Remote HTTPS URL:** no full-volume blast, no click at buffering → ready transition.
- [ ] **Long fade (120 s):** stable over background/foreground if product requires it.
- [ ] **Once + fadeIn:** no `CapacitorException`; correct overload used.
- [ ] **Pause/resume during fade:** defined behaviour (resume ramp or snap — product decision).
- [ ] **Multi-layer:** no cross-layer artefact regression vs deterministic loop baseline.
- [ ] **Plugin upgrade path:** no postinstall patch; survives `npm ci` and CI Android build.

### Production regression (fades must stay off until approved)

See checklist in [`audio-engine-fade-limitations.md`](audio-engine-fade-limitations.md) — loop layers at immediate target volume, no `fadeIn: true`, no patch hooks.

---

## Related Files

| Location | Path | Role |
| --- | --- | --- |
| **Central (this repo)** | [`audio-engine-fade-limitations.md`](audio-engine-fade-limitations.md) | **Active** fade policy and constraints |
| | [`audio-cache.md`](audio-cache.md) | Offline / streaming (orthogonal) |
| | [`../mobile/android-native-customizations.md`](../mobile/android-native-customizations.md) | Android native limitations summary |
| **front_vibes (repo copy)** | `docs/issues/native-loop-fadein.md` | Keep aligned with this investigation record |
| | `docs/issues/audio-engine-fade-limitations.md` | Issue copy of active policy |
| | `src/services/audio-player.service.ts` | Playback orchestration (no runtime fades) |
| | `src/services/audio-engine/types.ts` | `AudioEngine` interface / future swap point |
| | `src/services/audio-engine/native-audio.engine.ts` | Current adapter |
| **Plugin (historical touch points)** | `node_modules/@capgo/native-audio/android/.../RemoteAudioAsset.java` | ExoPlayer fade + playback |
| | `.../AudioAsset.java` | Base class / overload dispatch |
| | `.../NativeAudio.java` | Capacitor bridge dispatch |
| **Removed (historical)** | `scripts/patch-native-audio-fade.cjs` | Postinstall patch — **removed** with fade disable |

When implementing a future native loop fade, treat **this document as research input**, update **active architecture docs first**, then implement behind **`AudioEngine`** with explicit QA sign-off.
