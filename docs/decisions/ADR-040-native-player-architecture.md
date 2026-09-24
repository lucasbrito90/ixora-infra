# ADR-040: Native player architecture, and the fade specification

## Status

**Accepted** (2026-09-24) — governs how vibe playback is built in `ixora-app`: what the shared module decides, what the platform executes, and the semantics of fade — which is specified here for the first time, because no runtime fade exists to copy.

**Approved by the PO on 2026-09-24**, accepting the six points recorded in §11, including the two genuinely new specification choices: the logarithmic fade curve (§8.1) and the proportional clamp for `interval` ticks (§8.5). All thirteen code citations were verified line by line before acceptance. This ADR closes Phase 0 of the KMP migration.

Supersedes [ADR-008](ADR-008-nativeaudio-limitations-over-unstable-dsp.md) **in part**: its prohibition on runtime fades falls, its prohibitions on host-language gain automation and timing hacks stand and are generalized. §9 states exactly which rows change and which survive. ADR-008 anticipated this supersession and required it to happen through a new ADR; this is that ADR.

Builds on three accepted decisions and reopens none of them. [ADR-038](ADR-038-kmp-shared-layer.md) is the authority on what belongs to `shared` and already places layer scheduling there and audio transport on the platforms. [ADR-039](ADR-039-native-ui.md) governs the player's UI, which is native. [ADR-041](ADR-041-state-swift-interop.md) governs how playback state reaches that UI. [ADR-007](ADR-007-execution-plan-runtime-contract.md) is reaffirmed: the execution plan remains the runtime contract and the backend gains no playback engine. [ADR-042](ADR-042-migration-repository.md) governs where the work happens.

## Date

2026-09-24

---

## 1. Problem

The audio runtime is the single most intricate part of the application and the one the migration cannot approximate. `audio-player.service.ts` is 1.887 lines, `audio-engine/` a further 903, `audio-focus.service.ts` 59 more. Most of that is not audio — it is **timing**: when each layer starts, when it stops, what happens to a silence gap when the user pauses inside it, and how a finished tick schedules the next one.

Three questions have to be answered before any of it is rebuilt:

1. **What is shared and what is native**, given that ADR-038 already places the scheduler in `shared` and the transport on the platforms but does not say where the line falls in practice.
2. **How the existing semantics survive** a rewrite, when they are currently expressed as 1.887 lines of TypeScript with subtle guards that no test enumerates.
3. **What fade actually means** — because the PO decided fade must be recovered, and there is no behaviour to recover from. It has to be specified.

The third is the unusual one, and §3 explains why.

## 2. Context — what exists today, verified

Every claim in this section was read in `front_vibes` @ `1cf858e` and is cited by file and line.

### 2.1 Play modes and their meaning

`PlayMode` is `'loop' | 'once' | 'interval'` (`src/services/vibe-sound.service.ts:6`).

`interval` is the mode most often misread, and the code documents it explicitly (`src/services/audio-player.service.ts:68-80`):

> `repeat_interval_seconds` — silence gap between the **END** of one playback and the **START** of the next. This is NOT a period; it is the wait.
> `play_duration_seconds` — total wall-clock time the layer stays active inside the vibe session.

So `repeat_interval_seconds = 30` with a 12-second asset means play 12 s, wait 30 s, play 12 s — a 42-second cycle, not a 30-second one. Any reimplementation that treats it as a period is wrong.

### 2.2 The guards that are easy to lose

Three behaviours are load-bearing and invisible unless read closely:

- **Overlap prevention.** If a tick's completion callback is still registered when the next tick would start, the new tick is skipped with a structured warning (`audio-player.service.ts:1265`, guard at `:1185`).
- **Pause inside the silence gap.** The gap timer is cleared and the remaining time stored in `pendingIntervalRemainingMs` (field at `audio-player.service.ts:334`); resume reschedules from that remainder (`:48-49`, race guard at `:1189-1192`).
- **Hard stop at duration.** A layer with `durationSeconds` is stopped hard, with no ramp (`audio-player.service.ts:805-808`).

### 2.3 The execution plan already carries fade, and nothing plays it

The contract is complete end to end **except** in the transport:

| Layer | State | Evidence |
| --- | --- | --- |
| Database and API | Persist and expose | `vibe_sounds.fade_in_seconds` / `fade_out_seconds`; `VibeSoundResource`, `AttachVibeSoundRequest`, `UpdateVibeSoundRequest` in `back_vibes` |
| Execution plan | Computes and propagates | `player-engine.service.ts:168-169` maps them to `fadeInSeconds` / `fadeOutSeconds`, defaulting to 0 |
| UI | **Announces to the user** | `VibePlayerPage.vue:240-245` renders "fade in Ns" / "fade out Ns"; `VibeSoundsPage.vue:279-280` renders "fade↑ / fade↓" |
| Debug panel | States the gap | `PlayerDebugPanel.vue:141-147` prints the value followed by "(stored but ignored)" |
| Transport | **Ignores** | `audio-player.service.ts:15-18` — *"fadeIn/fadeOut are intentionally NOT applied at runtime"*; `audio-engine/native-audio.engine.ts:70` passes `fade: false` |

**There is therefore no fade behaviour to reproduce.** What exists is a contract honoured everywhere except where it would be audible.

One consequence deserves naming: ADR-008 requires that *"UI must not imply fades work in production without engine change + new ADR"*. The UI announces fade values today. The current application is, by ADR-008's own rule, in violation — and has been since the fade chips were added. This ADR resolves that by making the fades real rather than by removing the labels.

### 2.4 ADR-008 anticipated this exact ADR

ADR-008 did not forbid fades forever. It forbade them **on that stack**, and wrote down the conditions for their return:

- *"`fade_in_seconds` / `fade_out_seconds` may remain on `vibe_sounds` and in `VibeExecutionLayer` for compatibility and **future native work**."*
- *"**`AudioEngine`** adapter as future swap point for a **reviewed native engine**."*
- *"Re-enabling fades without ADR supersession | **Forbidden**."*

The `AudioEngine` interface even lists the methods a future engine would need — `fadeIn(soundId, targetVolume, durationSeconds)` and `fadeOut(soundId, durationSeconds)` (`audio-engine/types.ts:22-23`, under the header *"Future additions (when a proper engine is built)"* at `:20`).

This ADR is the supersession ADR-008 required, on the engine change ADR-008 named.

### 2.5 Background playback today

Android background playback needs a foreground service in addition to the audio plugin: `backgroundAudio.service.ts` (239 lines) imports `@capawesome-team/capacitor-android-foreground-service` (`:34`), requests its permission (`:75-85`) and creates a notification channel (`:127`). Audio focus and the becoming-noisy event are handled separately in `audio-focus.service.ts` (59 lines, `setAudioFocusCallbacks({ onBecomingNoisy })` at `:35`).

None of that survives as code. All of it survives as requirement.

## 3. Why fade must be specified rather than ported

Reproducing behaviour is the migration's governing rule ([ADR-042](ADR-042-migration-repository.md) Decision 8). Fade is the one place where that rule cannot be followed literally, because the behaviour does not exist (§2.3).

The instruction "do not invent a different fade behaviour" is therefore read as: **do not extrapolate beyond what the existing fields describe.** The fields describe a duration in seconds for a fade in and a fade out, per layer. The specification below decides only what is necessary to make those two numbers audible, and marks each choice as a specification decision rather than a recovered behaviour.

Nothing in §8 adds a field, a control, or a product capability beyond what `vibe_sounds` already stores and the UI already displays.

---

## Decision

### Decision 1 — The split: shared decides, platform sounds

```
┌──────────────────── shared/commonMain ─────────────────────┐
│  buildVibeExecutionPlan   VibeSound[] → VibeExecutionLayer[] │
│  PlaybackScheduler        (plan, session state, instant t)   │
│                           → List<LayerCommand>               │
│  Deterministic · no I/O · no timers · no audio               │
└───────────────────────────┬─────────────────────────────────┘
                            │  LayerCommand
              ┌─────────────┴─────────────┐
      AudioTransport (Android)     AudioTransport (iOS)
      Media3 / ExoPlayer           AVAudioEngine
      MediaSessionService          AVAudioSession
      Foreground service           Background audio mode
```

The rule: **`shared` decides what should be sounding at instant *t*; the platform makes it sound.**

This is ADR-038's matrix applied, not extended — that matrix already places *layer scheduling* in `shared` and *audio transport* and *background playback* on the platforms.

Why the line falls here: of the 2.849 lines being replaced, the majority is timing logic, not audio. Written once as a deterministic function it can be covered by table tests in `commonTest`; written twice it will diverge, and the divergence will be inaudible in tests and audible to users.

### Decision 2 — `PlaybackScheduler` is deterministic and owns no clock

The scheduler is a **pure function of (plan, session state, instant)**. It performs no I/O, starts no timers, touches no audio API, and reads no wall clock of its own — the instant is an argument.

It emits `LayerCommand` values: start a layer at a volume, stop it, set a volume, schedule the next interval tick. It does not emit sample data, frames, or gain curves (Decision 5).

Two consequences follow. The scheduler is exhaustively testable without a device, which is how the semantics of §2.2 stop being folklore. And the platform keeps ownership of the clock, which is where it must live: the audio thread and the foreground service are the only places that can keep time reliably while the screen is off.

### Decision 3 — The existing semantics are preserved exactly, and become tests

The following are **contract**, not implementation detail, and each must be covered by a `commonTest` case before the transport is written:

| Behaviour | Source |
| --- | --- |
| `interval` gap is the silence **between playbacks**, not a period | `audio-player.service.ts:68-80` |
| A tick is skipped when the previous one has not completed | `:1265`, `:1185` |
| Pause inside the gap stores the remainder; resume continues from it | `:48-49`, `:334`, `:1189-1192` |
| A layer with `durationSeconds` stops hard at its end | `:805-808` |
| `endsAtSeconds = startsAtSeconds + durationSeconds` when a duration exists | `player-engine.service.ts:140` |
| `loop`, `once` and `interval` coexist as concurrent layers in one session | `audio-player.service.ts` throughout |

Parity is verified against the frozen `front_vibes` on a real device before Phase 4 is considered complete ([ADR-042](ADR-042-migration-repository.md) Decision 7).

### Decision 4 — Platform transports

**Android:** `androidx.media3` (ExoPlayer) for playback, `MediaSessionService` for media controls and lock-screen presence, a foreground service for process survival, and `AudioManager` for focus and the becoming-noisy event. The requirements carried over from `backgroundAudio.service.ts` and `audio-focus.service.ts` (§2.5) survive as requirements, not as code.

**iOS:** `AVAudioEngine` with one `AVAudioPlayerNode` per layer into a mixer, `AVAudioSession` configured for background audio, and `MPNowPlayingInfoCenter` for controls. **Not implemented in this phase** — ADR-042 Decision 5 keeps iOS architecturally targeted and unbuilt.

No cross-platform audio abstraction is introduced in `shared`. The `AudioTransport` interface exists so the scheduler can be tested against a fake, not so the two platforms can share an implementation — a distinction ADR-038 Decision 3 already drew, and the one `@capgo/native-audio` failed.

### Decision 5 — Ramps are declared, never driven

The shared module **must not compute gain over time**. It declares intent — *start this layer at volume v with a fade-in of d* — and the transport performs the ramp natively, on the audio thread.

This is ADR-008's real lesson, generalized. ADR-008 forbade *"`setTimeout` / `requestAnimationFrame` volume ramps"* and a *"JS crossfade engine"*. The failure was not JavaScript; it was **driving a ramp from the host language across an async bridge**. A Kotlin coroutine stepping volume every 50 ms would reproduce that failure with a different syntax, and is equally forbidden.

Media3 and AVAudioEngine both apply volume changes on the audio thread, which is the only place a ramp can be smooth. `shared` says what the ramp is; the platform runs it.

---

## 8. The fade specification

Specification, not recovered behaviour (§3). Every rule below exists to make `fadeInSeconds` and `fadeOutSeconds` audible; none adds a product capability.

### 8.1 Curve

Fades are **logarithmic in amplitude — linear in decibels**, from silence to the layer's configured `volume` and back.

A linear amplitude ramp is the obvious implementation and the wrong one: perceived loudness is roughly logarithmic, so a linear ramp sounds like it rises fast and then stalls near the top. For ambient material, where the whole point is that a layer arrives without being noticed, that is audible as a lump. Both transports expose linear gain, so the curve is computed by the app at ramp definition time, not per frame (Decision 5).

### 8.2 Anchors

**Fade-in** starts when the layer starts and lasts `fadeInSeconds`.

**Fade-out ends at the layer's end — it does not extend it.** For a layer with a duration, the ramp begins at `endsAtSeconds - fadeOutSeconds` and reaches silence at `endsAtSeconds`.

This is the conservative anchor, and deliberately so: it preserves the existing contract that a layer with `durationSeconds` is over at `endsAtSeconds` (`audio-player.service.ts:805-808`, `player-engine.service.ts:140`). Anchoring the fade-out to the end of the *file* instead would change when layers stop, which would be a behaviour change rather than a fade.

For a layer with no duration — `endsAtSeconds == null`, a loop that runs until the user stops it — the fade-out applies **on stop**, as a ramp to silence before teardown.

### 8.3 `loop` — fades at the layer's edges, never at the wrap

Fade-in applies to the layer's **first** start; fade-out applies when the layer ends or is stopped. **Neither applies at a loop wrap.**

Fading at every wrap would duck the audio once per iteration, producing a pulsing that no field asks for and no user configured. It would also contradict ADR-008's surviving position that a loop wrap may have an audible edge and that seamless looping is not promised (§9) — the wrap is not the fade's business.

### 8.4 `once` — the straightforward case

Fade-in at the start; fade-out ending at `endsAtSeconds`, or at the asset's natural end when the layer has no duration.

### 8.5 `interval` — per tick, clamped

Each tick fades in and out, because a tick is a discrete playback: the field's own definition is the silence **between the end of one playback and the start of the next** (§2.1). A tick that started at full volume would contradict the fade the user configured for that layer.

**Clamp rule.** When `fadeInSeconds + fadeOutSeconds` exceeds the tick's own playable length, both are scaled proportionally so they fit, preserving their ratio and never overlapping. The tick's duration is not extended and no tick is skipped.

This clamp is a specification decision, made explicit because the fields permit the case — a 30-second fade on an 8-second asset — and some rule must exist. Scaling was chosen over truncating because it keeps both fades audible instead of silently dropping one.

The silence gap is silence. No fade is applied across it.

### 8.6 Pause and resume introduce no fades

Pausing does not ramp down and resuming does not ramp up. The existing behaviour is an immediate pause, and nothing in the two fields asks for a pause ramp.

A fade interrupted mid-ramp by a pause **preserves its remaining time** and continues from that point on resume. This mirrors the existing treatment of the interval gap, where the remainder is stored and rescheduled (`audio-player.service.ts:334`, `:48-49`) — the same principle applied to a ramp instead of a timer.

### 8.7 Out of scope, explicitly

Crossfade between layers, fade on seek, per-vibe master fades, and any fade not derived from `fade_in_seconds` / `fade_out_seconds` are **not** in scope. Adding them is a product decision under ADR-042 Decision 8, not an implementation detail of this one.

Sample-accurate loop transitions remain unpromised (§9).

---

## 9. Relationship to ADR-008 — what falls and what stands

[ADR-008](ADR-008-nativeaudio-limitations-over-unstable-dsp.md) becomes **Superseded in part**. It is not revoked: it was correct about the stack it governed, and most of its reasoning survives intact.

**Superseded** — these rows applied to the Capacitor/`@capgo/native-audio` stack, which `ixora-app` does not use:

| ADR-008 row | Why it falls |
| --- | --- |
| *Runtime fade-in / fade-out — **Not applied*** | Replaced by §8. Media3 and AVAudioEngine apply ramps on the audio thread; the plugin could not. |
| *`fadeIn: true` on remote assets — **Not used*** | Moot: the plugin with the dispatch bug is gone. |
| *Postinstall Java patches for fade — **Not shipped*** | Moot: nothing is patched. |
| *Re-enabling fades without ADR supersession — **Forbidden*** | Satisfied: this ADR is the supersession ADR-008 required. |

**Still in force**, and generalized beyond JavaScript:

| ADR-008 row | Status under this ADR |
| --- | --- |
| *JS crossfade engine — **Forbidden*** | Stands, generalized: **no host-language gain automation**, Kotlin or Swift (Decision 5). |
| *Unstable timing hacks — **Forbidden*** | Stands, generalized: no coroutine or timer stepping volume across a bridge (Decision 5). |
| *Seamless loop guarantees — **Not promised*** | Stands. §8.3 keeps fades off the wrap. |
| *Sample-accurate loop transitions — **Not achievable*** | Stands as unpromised. |
| *Deterministic playback — **Preferred*** | Stands, and is strengthened: Decision 2 makes the scheduler deterministic by construction. |
| *Stability over artificial smoothness — **Preferred*** | Stands. §8.7 keeps crossfade out. |

ADR-008 is amended with a status note pointing here **when Phase 4 completes**, not before — until then it still describes the shipping application. [`audio-engine-fade-limitations.md`](../architecture/audio/audio-engine-fade-limitations.md) and [`playback-runtime.md`](../architecture/audio/playback-runtime.md) become historical at the same moment, for the same reason.

## 10. Relationship to other ADRs

- **[ADR-038](ADR-038-kmp-shared-layer.md)** is the authority on the shared boundary. Decision 1 applies its matrix — layer scheduling shared, audio transport and background playback native — and adds no classification.
- **[ADR-039](ADR-039-native-ui.md)** governs the player's UI. This ADR decides nothing about how the player looks; the mini-player surface is native under ADR-039, driven by `hasPresentableSession` under ADR-041 Decision 4.
- **[ADR-041](ADR-041-state-swift-interop.md)** governs how playback state reaches the UI. This ADR produces that state and consumes that contract; it does not restate it.
- **[ADR-007](ADR-007-execution-plan-runtime-contract.md)** is reaffirmed. The execution plan remains the playback runtime contract and the backend still has no playback engine. Its reference to the TypeScript implementation needs an addendum when the Kotlin scheduler ships, not now.
- **[ADR-042](ADR-042-migration-repository.md)** places this work in Phase 4 and makes device-verified parity its completion criterion.

## 11. What acceptance meant

Accepted by the PO on 2026-09-24. Acceptance covered, specifically:

1. The scheduler/transport split of Decision 1, with the scheduler deterministic and clockless (Decision 2).
2. The six preserved semantics of Decision 3 as contract, each covered by a test before the transport is built.
3. Media3 and `MediaSessionService` on Android, AVAudioEngine on iOS, with no shared audio abstraction (Decision 4).
4. That ramps are declared by `shared` and executed natively — no host-language gain automation in any language (Decision 5).
5. The fade specification of §8 as **specification**: logarithmic curve, fade-out anchored to the layer's end, no fade at loop wraps, per-tick fades in `interval` with proportional clamping, and no fades introduced by pause or resume.
6. That ADR-008 becomes Superseded in part, with the four rows in §9 falling and the six standing, amended when Phase 4 completes.

## Consequences

**Positive**

- The most intricate logic in the application is written once, in a form that can be tested exhaustively without a device.
- Fade becomes real, closing a gap where the UI has been announcing a feature the audio never delivered (§2.3) — and closing an ADR-008 violation that exists today.
- The semantics most likely to be lost in a rewrite are written down with citations, instead of living only in the code that is being replaced.
- ADR-008's actual lesson is carried forward rather than discarded: the prohibition on driven ramps survives the stack that motivated it.

**Negative, accepted**

- The audio transport is written twice, once per platform. That is inherent to Decision 4 and to ADR-039.
- Fade adds scope to the highest-risk phase of the migration, by PO decision.
- The clamp rule of §8.5 will occasionally produce a fade shorter than configured. The alternative — refusing the configuration — would be a product change.

**Risks**

- **Silent semantic loss.** A guard from §2.2 omitted in the port would be invisible in tests and audible only in a specific sequence. Decision 3 turns each into a required test case; that is the mitigation and the only one.
- **Fade sounding wrong despite being correct.** §8.1's curve is reasoned, not tuned by ear on the real catalogue. Expect adjustment during Phase 4; the adjustment is to the curve constant, not to the architecture.
- **The clamp surprising a user.** Someone configuring a 30-second fade on an 8-second interval asset gets something shorter. Considered preferable to silence or to refusal.
- **iOS transport unverified.** As everywhere else, the AVAudioEngine design is reasoned and uncompiled.

## Sources

Code read 2026-09-24 in `front_vibes` @ `1cf858e`, cited inline above: `src/services/audio-player.service.ts` (1.887 lines — `:15-18` fade ignored, `:68-80` interval semantics, `:334` and `:48-49` gap remainder, `:805-808` hard stop, `:1185` and `:1265` overlap guard), `src/services/audio-engine/native-audio.engine.ts:70` (`fade: false`), `src/services/audio-engine/types.ts:22-23` (anticipated `fadeIn`/`fadeOut` API, under the `:20` header), `src/services/player-engine.service.ts:140` and `:168-169`, `src/services/vibe-sound.service.ts:6` (`PlayMode`), `src/services/backgroundAudio.service.ts` (239 lines, `:34`, `:75-85`, `:127`), `src/services/audio-focus.service.ts` (59 lines, `:35`), `src/views/VibePlayerPage.vue:240-245`, `src/views/VibeSoundsPage.vue:279-280`, `src/components/debug/PlayerDebugPanel.vue:141-147`. Backend fields verified in `back_vibes`: `VibeSoundResource`, `AttachVibeSoundRequest`, `UpdateVibeSoundRequest`, `VibeSound` model.

Internal: [ADR-007](ADR-007-execution-plan-runtime-contract.md), [ADR-008](ADR-008-nativeaudio-limitations-over-unstable-dsp.md), [ADR-038](ADR-038-kmp-shared-layer.md), [ADR-039](ADR-039-native-ui.md), [ADR-041](ADR-041-state-swift-interop.md), [ADR-042](ADR-042-migration-repository.md), [`kmp-migration-plan.md`](../architecture/mobile/kmp-migration-plan.md) (§10 player architecture, §10.4 fade finding), [`playback-runtime.md`](../architecture/audio/playback-runtime.md), [`audio-engine-fade-limitations.md`](../architecture/audio/audio-engine-fade-limitations.md).
