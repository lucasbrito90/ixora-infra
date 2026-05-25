# Audio engine fade limitations — ambient playback stability

**Status:** Active architecture (source of truth)  
**Scope:** Mobile layer fade-in/fade-out and loop transitions (`front_vibes`, `@capgo/native-audio` / ExoPlayer)  
**Runtime note:** Fade effects are **not applied** at playback time (removed May 2026); DB fields may remain for backward compatibility.

---

## Purpose

Document **why Ixora does not rely on fade-in, fade-out, or JS-timed crossfades** in the current native audio stack, what **technical limits** `@capgo/native-audio` / ExoPlayer impose on seamless looping, and how **future native engine work** may be approached—without promising fade behaviour in production today or encouraging unstable JavaScript DSP experiments.

This document states **architecture constraints and policy**. Playback orchestration lives in `audio-player.service.ts` and `player.store.ts`; offline/cache rules live in [`audio-cache.md`](audio-cache.md).

---

## Context

Ixora is an **ambient multi-layer player**: several sounds may loop concurrently with per-layer volume. Users expect **stable, predictable playback** on Android (primary) with reasonable **battery use**—not DJ-style sample-accurate crossfades.

The current stack uses **`@capgo/native-audio`** (ExoPlayer on Android) behind an **`AudioEngine`** adapter in `src/services/audio-engine/`. The Capacitor bridge resolves JS promises **before** ExoPlayer always reaches steady **`STATE_READY`**, and volume APIs gate on **`isPlaying()`** in ways that race with buffering.

Historical attempts to add fades included:

- Post-`loop()` **`setVolume` ramps in JavaScript** — skipped or mis-timed during **`STATE_BUFFERING`**
- **`play({ fadeIn: true })`** — Java **`double`/`float` dispatch bug** → wrong method on empty `audioList`
- **Postinstall patches** to plugin Java (`RemoteAudioAsset`, `loopWithFadeIn`) — fragile on upgrades

Those paths produced **clicks, pops, overlap artefacts**, or maintenance cost. The product **removed runtime fades** and **UI fade controls** while keeping **`fade_in_seconds` / `fade_out_seconds`** in schema/types for compatibility.

**Important:** The current NativeAudio/ExoPlayer layer does **not** provide **sample-accurate loop transitions** or guaranteed seamless loop boundaries.

---

## Current Decision

1. **Fade-in and fade-out are not applied at runtime** in the shipping app. Layers start and stop at **target volume** immediately.
2. **Seamless looping and fade transitions are limited** by plugin/runtime behaviour—not by missing JS effort alone.
3. The project **intentionally prioritizes stable playback** over artificial or pseudo-smooth fades.
4. **Manual JavaScript timing** (timeouts, `requestAnimationFrame` volume ramps, cross-layer scheduling) is **not reliable enough** for seamless looping against ExoPlayer’s async state machine.
5. **Audio overlap, pops, and clicks** are **known risks** when attempting fade transitions with the current plugin; past experiments confirmed this.
6. The strategy **avoids unstable DSP-like behaviour in JavaScript** (no app-layer faux-fades pretending to be native quality).
7. **Future custom or first-party native engine work is allowed** but is **explicitly out of scope** for the **current** architecture—documented as a possible direction, not a commitment.
8. **Deterministic looping** (`NativeAudio.loop` / equivalent) is preferred over **pseudo-smooth** JS-or-patched-native fades.
9. **Do not implement experimental JS crossfade systems** (multi-layer overlap fades, scheduled gain automation in the WebView) **without architecture review** and a native-capable plan.
10. The **current architecture optimizes for ambient stability, battery efficiency, and predictable playback**—not maximum perceptual smoothness at loop boundaries.

---

## Architecture

### Current playback model (no fades)

```
player.store.ts          ← source of truth (play / pause / stop, layer plan)
        │
        ▼
audio-player.service.ts  ← schedules loop | once | interval per layer
        │
        ▼
AudioEngine (adapter)    ← src/services/audio-engine/native-audio.engine.ts
        │
        ▼
@capgo/native-audio      ← ExoPlayer RemoteAudioAsset (HTTPS / file://)
```

| Mode | Native API (today) | Fade behaviour |
| --- | --- | --- |
| Loop | `NativeAudio.loop` | **None** — immediate target volume |
| Once | `NativeAudio.play` | **None** — no `fadeIn: true` |
| Interval | `play` per tick | **None** |

**UI:** Fade fields hidden/ignored in edit flows (e.g. vibe sound modal). **Database:** `fade_in_seconds` / `fade_out_seconds` may still exist on rows for future use but **must not** affect runtime until a reviewed engine ships.

### Why fades failed (technical summary)

| Approach | Failure mode |
| --- | --- |
| JS ramp after `loop()` | Promise resolves during **`STATE_BUFFERING`**; `isPlaying()` false → ramp skipped or applied late → **click** |
| Patched `getPlayWhenReady()` gating | Volumes applied when leaving buffering → **audible jump** |
| `playWithFadeIn` on remote assets | **`double` vs `float`** → wrong overload → **`Index 0 out of bounds`** |
| `node_modules` Java patches | Break on plugin upgrade; high maintenance |

These constraints imply: **fade and seamless loop polish belong in native code on the player thread**, not in opportunistic JS after bridge return.

### AudioEngine abstraction (swap point)

`src/services/audio-engine/`:

| File | Role |
| --- | --- |
| `types.ts` | Engine-agnostic `AudioEngine` interface |
| `native-audio.engine.ts` | Current `@capgo/native-audio` adapter |
| `index.ts` | Exported engine instance |

A **future** first-party or upgraded native plugin could implement a new adapter class and swap the export in `index.ts` **without** rewriting Pinia—**when** such an engine exists and passes review. That is **not** part of current shipping behaviour.

### Future directions (allowed, not current)

Documented options for later ADR/spec work—**no delivery promise**:

- **Option A — Custom Capacitor plugin:** e.g. `loopWithFadeIn` / `fadeOut` running on Android UI thread with buffering-aware ramps (see historical investigation in repo issue notes).
- **Option B — Upstream `@capgo/native-audio`:** only if a release fixes loop fade and type dispatch natively.

Candidate future requirements (planning only): native `loopWithFadeIn`, loop `fadeOut`, once-mode fade without type mismatch, pause/resume fade state, optional per-layer gain automation, iOS parity, optional HTML fallback for web/dev.

---

## Rules

### Runtime (current)

- **Do not** pass `fadeIn: true` to `NativeAudio.play()` for remote assets.
- **Do not** implement post-play JS volume ramps to simulate fades on loop start.
- **Do not** reintroduce **`scripts/patch-native-audio-fade.cjs`** or ad-hoc `node_modules` Java patches without architecture review and an upgrade plan.
- Start/stop layers at **configured target volume**; use **deterministic** `loop` / `play` / `stop` semantics from `audio-player.service.ts`.
- **Ignore** `fade_in_seconds` / `fade_out_seconds` at playback time until a new engine is approved and documented.

### Engineering policy

- **No experimental JS crossfade systems** (scheduled overlap, multi-layer WebView gain automation) without **architecture review**.
- Prefer **predictable ambient playback** and **battery efficiency** over perceptual fade polish in the current stack.
- Do **not** document or ship UI that implies fades work when they do not.
- Do **not** promise seamless/sample-accurate loop transitions with **`@capgo/native-audio` 8.x** as deployed.

### Future work (when explicitly approved)

- Implement fades **natively** (UI thread, buffering-aware), behind **`AudioEngine`** interface.
- Add ADR + update this doc before enabling fade fields in UI again.
- Remove or migrate legacy patch approaches—do not stack patches on patches.

---

## Risks

| Risk | If ignored |
| --- | --- |
| JS timed fades after `loop()` / `play()` | Clicks, full-volume blasts, silent failed ramps |
| Re-enabling `fadeIn: true` on remote assets | `CapacitorException`, crashes |
| Plugin Java patches | Lost on `npm install`; fragile upgrades |
| Cross-layer JS crossfade | Overlap, phase clash, battery drain, non-deterministic mix |
| UI promises fades | User trust / QA mismatch with runtime |
| Sample-accurate loop expectations | Unmet on ExoPlayer loop mode today |
| Premature custom plugin | Maintenance without replacing adapter cleanly |

---

## Validation

### Current release (fades must be absent)

- [ ] Vibe sound edit UI does **not** expose fade-in/fade-out controls (or they are clearly disabled with no runtime effect).
- [ ] Starting a **loop** layer — volume reaches target **immediately** (no audible ramp).
- [ ] Stopping a layer — **no** fade-out ramp before stop.
- [ ] No `fadeIn: true` in `audio-player.service.ts` native calls.
- [ ] No `patch-native-audio-fade` (or similar) in `package.json` hooks.
- [ ] Multi-layer ambient playback stable for **≥ 10 minutes** on device (no drift from fake JS fades).

### Regression audio quality (ambient)

- [ ] Loop restarts do **not** require JS scheduling; native loop mode used.
- [ ] No increase in pops/clicks vs baseline when adding new player features.
- [ ] Background + focus behaviour unchanged (see [`../mobile/android-native-customizations.md`](../mobile/android-native-customizations.md)).

### When a future engine lands (out of scope until then)

- Separate test plan: native fade on loop start/end, pause/resume during fade, once-mode fade, iOS parity—**only after** ADR and doc update.

---

## Related Files

| Location | Path |
| --- | --- |
| **Central (this repo)** | `docs/architecture/audio/audio-cache.md` |
| | `docs/architecture/audio/native-loop-fadein.md` (historical loop/fade investigation) |
| | `docs/architecture/mobile/android-native-customizations.md` |
| **front_vibes (repo copy)** | `docs/issues/audio-engine-fade-limitations.md` — keep aligned with this file |
| | `docs/issues/native-loop-fadein.md` |
| | `src/services/audio-engine/types.ts` |
| | `src/services/audio-engine/native-audio.engine.ts` |
| | `src/services/audio-engine/index.ts` |
| | `src/services/audio-player.service.ts` |
| | `src/stores/player.store.ts` |
| **Plugin** | `@capgo/native-audio` — `RemoteAudioAsset.java`, ExoPlayer integration |

When fade capability changes, update **this file first**, then sync issue copies and only then re-enable UI/schema behaviour with explicit QA sign-off.
