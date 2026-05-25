# ADR-008: NativeAudio limitations over unstable JS-driven DSP

## Status

**Accepted** — reflects **current shipped playback policy** (runtime fades removed; deterministic native scheduling).

## Date

2026-05-23

## Context

Ixora is an **ambient multi-layer player** on Android (primary) via **`@capgo/native-audio`** and ExoPlayer. Pivot and execution-plan layers may still carry **`fade_in_seconds` / `fade_out_seconds`**, but **production playback does not apply them**.

Historical work attempted **JavaScript volume ramps**, **`play({ fadeIn: true })`**, and **patched plugin Java** to simulate smooth loop entry and cross-layer blending. Failures were systematic: Capacitor promises resolving during **`STATE_BUFFERING`**, **`isPlaying()`** gating skipping ramps, **`double`/`float` dispatch bugs**, clicks/pops at loop boundaries, and **lost `node_modules` patches** on upgrade.

The product needed an explicit architectural choice: chase **perceived smoothness** through WebView timing hacks, or accept **NativeAudio/ExoPlayer limits** and optimize for **stable, deterministic ambient playback**.

Detailed failure analysis lives in [`audio-engine-fade-limitations.md`](../architecture/audio/audio-engine-fade-limitations.md) and [`native-loop-fadein.md`](../architecture/audio/native-loop-fadein.md).

---

## Decision

**Ixora accepts NativeAudio/ExoPlayer runtime limitations instead of implementing unstable JavaScript-driven DSP, fade, or crossfade workarounds.**

### Current runtime policy (mandatory)

| Behaviour | Status |
| --- | --- |
| **Runtime fade-in / fade-out** | **Not applied** — layers start/stop at target volume immediately |
| **Seamless loop guarantees** | **Not promised** — loop wrap may have audible edge |
| **JS crossfade engine** | **Forbidden** — no multi-layer WebView gain automation |
| **Unstable timing hacks** | **Forbidden** — no `setTimeout` / `requestAnimationFrame` volume ramps after `loop()` / `play()` |
| **Preload-as-fade strategy** | **Forbidden** — **`NativeAudio.preload()`** is playback prep only, not a fade primitive |
| **`fadeIn: true` on remote assets** | **Not used** — known plugin dispatch failures |
| **Postinstall Java patches** for fade | **Not shipped** — fragile on plugin upgrades |
| **Deterministic playback** | **Preferred** — `NativeAudio.loop` / `play` / hard **`stopLayer`** |
| **Stability over artificial smoothness** | **Preferred** — ambient reliability and battery over DJ-style polish |

### Schema vs runtime

- **`fade_in_seconds` / `fade_out_seconds`** may remain on **`vibe_sounds`** and in **`VibeExecutionLayer`** for compatibility and future native work.
- **`buildVibeExecutionPlan`** copies fade fields; **`audio-player.service`** **ignores** them at schedule time ([`ADR-007`](ADR-007-execution-plan-runtime-contract.md)).
- UI must **not** imply fades work in production without engine change + new ADR.

### What remains in scope

- Multi-layer **loop**, **once**, **interval** scheduling via **`audio-player.service.ts`**
- **Hard stop** at **`play_duration_seconds`** — no fade-out ramp
- **`AudioEngine`** adapter as future swap point for a **reviewed native engine** — not ad-hoc JS DSP

### Explicit non-goals (today)

| Pattern | Status |
| --- | --- |
| Sample-accurate loop transitions | **Not achievable** with current plugin as deployed |
| Cinematic crossfades between layers | **Not shipped** |
| FFmpeg / server preprocessing for fades at play time | **Not runtime path** — see [`future-processing-pipeline.md`](../architecture/storage/future-processing-pipeline.md) for optional **future** offline transforms only |
| Re-enabling fades without ADR supersession | **Forbidden** |

---

## Consequences

### Positive (motivations)

| Motivation | How this decision delivers it |
| --- | --- |
| **Mobile stability** | Fewer bridge races and plugin edge cases in hot path |
| **Predictable playback** | Volume and stop semantics match plan fields — no hidden ramps |
| **Android reliability** | ExoPlayer used within supported **`loop` / `play`** APIs |
| **Plugin/runtime honesty** | Docs and ADR match what ExoPlayer + bridge actually guarantee |
| **Maintenance reduction** | No `node_modules` patches or fade-specific JS state machines |
| **Avoid race conditions** | No **`STATE_BUFFERING`** vs JS timer fights |
| **Avoid click/pop regressions** | Past experiments linked fades to audible artefacts — path abandoned |

### Negative (tradeoffs)

| Tradeoff | Impact |
| --- | --- |
| **Audible hard loop edges possible** | Loop wrap may click or gap — user expectation must be set |
| **No cinematic fade transitions today** | Layers enter/exit abruptly at configured volume |
| **Limited ambient blending sophistication** | No cross-layer crossfade or long gentle loop entry |
| **Schema/UI drift** | Fade fields exist but inactive — requires clear docs |
| **Future native work deferred** | Acceptable polish requires **native** engine investment, not JS |

---

## Alternatives Considered

| Alternative | Why not chosen (for Ixora today) |
| --- | --- |
| **JS gain ramps** after `loop()` / `play()` | Buffering races; skipped ramps; clicks — documented in fade-limitations |
| **Preload fade hacks** | Preload ≠ fade; does not fix loop mode API gap |
| **Patched NativeAudio forks** | Lost on install/upgrade; CI fragility — abandoned in investigation |
| **Custom DSP engine** (Capacitor plugin) | Valid **future** direction — requires ADR, QA, **`AudioEngine`** swap; **not current** |
| **FFmpeg preprocessing** | Offline/server transform — not a substitute for runtime loop fade; separate future pipeline |
| **Re-enable `fadeIn: true`** | Remote asset crashes / wrong overload — rejected |
| **HTMLAudioElement faux-DSP on native** | Fallback path for dev only — not production ambient policy |

If a **native-capable fade** ships later, it must implement on the **player thread** behind **`AudioEngine`**, with updated ADR and re-enabled UI — not restored JS workarounds.

---

## Relationship to other decisions

| ADR / doc | Relationship |
| --- | --- |
| **[ADR-007](ADR-007-execution-plan-runtime-contract.md)** | Plan carries fade fields; runtime scheduler ignores them |
| **[ADR-004](ADR-004-offline-audio-strategy.md)** | Offline uses full files + plan — unrelated to fade DSP |
| **[`future-processing-pipeline.md`](../architecture/storage/future-processing-pipeline.md)** | Optional loudness/transcode — **not** runtime fade substitute |

---

## Related Docs

| Document | Relationship |
| --- | --- |
| [`../architecture/audio/audio-engine-fade-limitations.md`](../architecture/audio/audio-engine-fade-limitations.md) | **Active policy** — rules, risks, validation |
| [`../architecture/audio/native-loop-fadein.md`](../architecture/audio/native-loop-fadein.md) | **Historical investigation** — what failed and why |
| [`../specs/vibes/playback-runtime/spec.md`](../specs/vibes/playback-runtime/spec.md) | Feature spec — no runtime fades, no seamless loop promise |
| [`../architecture/audio/playback-runtime.md`](../architecture/audio/playback-runtime.md) | Architecture — player stack, known limitations |
| [`../specs/vibes/execution-plan/spec.md`](../specs/vibes/execution-plan/spec.md) | Fade fields stored, ignored at runtime |

### Implementation reference (current)

| Artifact | Fade-related behaviour |
| --- | --- |
| `front_vibes/src/services/audio-player.service.ts` | No fade ramps; hard **`stopLayer`** at duration |
| `front_vibes/src/services/audio-engine/native-audio.engine.ts` | `configure({ fade: false })` pattern; no fade APIs used |
| `front_vibes/src/services/player-engine.service.ts` | Copies fade seconds into plan — not applied downstream |
| `@capgo/native-audio` | ExoPlayer loop/play — no production fade path |

### Review checklist

- [ ] No post-play JS volume ramps in `audio-player.service.ts`
- [ ] No `fadeIn: true` on native play for CDN assets
- [ ] No `patch-native-audio-fade` (or similar) in package hooks
- [ ] New player features do not introduce WebView crossfade timers
- [ ] UI does not promise fades without engine ADR

---

When fade or seamless-loop capability is intentionally restored, supersede this ADR, update [`audio-engine-fade-limitations.md`](../architecture/audio/audio-engine-fade-limitations.md), and ship native implementation + QA — **do not** revert to JS DSP workarounds alone.
