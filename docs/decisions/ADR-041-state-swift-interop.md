# ADR-041: State contract across the shared/native boundary, and Kotlin↔Swift interop

## Status

**Proposed** — awaiting PO acceptance (see §10). Governs how application state and one-shot effects cross from the Kotlin Multiplatform shared module into the native user interfaces, and the interop rules that make that crossing survivable on iOS.

Complements [ADR-038](ADR-038-kmp-shared-layer.md) and [ADR-039](ADR-039-native-ui.md); replaces neither. **ADR-038 remains the authority on what belongs to the shared layer**, and **ADR-039 remains the authority on how the native UI is implemented**. This ADR decides only what travels between them, in which direction, and in what shape.

ADR-040 (native player, card K05) is **out of scope**: the player's architecture, its scheduler and its fade semantics are that ADR's subject. This ADR treats playback state only as one consumer of the contract defined here, and does not anticipate any of its decisions. [ADR-042](ADR-042-migration-repository.md) governs the migration strategy and is unaffected.

## Date

2026-09-23

---

## 1. Problem

ADR-038 places domain, rules, repositories and presentation state in `shared`. ADR-039 places theme, components and screens in Compose and, later, SwiftUI. Between those two decisions there is an unspecified gap: **how a screen actually receives what it renders, and how it reports what the user did.**

Left unspecified, three things go wrong, and they are the ordinary failure modes of KMP projects rather than exotic ones:

1. **The UI starts reaching past the boundary.** A screen calls a repository directly "just this once", and the rule that produced the value now exists in two places.
2. **One-shot effects become sticky state.** A navigation event or an error toast is modelled as a `StateFlow` field because that is the easy way to observe it, and then fires again on every recomposition or view reappearance.
3. **The Swift boundary is discovered late.** Kotlin constructs that are perfectly idiomatic — `Flow`, sealed classes, default arguments, thrown exceptions — either do not cross to Swift at all or cross in a degraded form. Discovering this when the iOS application is first compiled means reworking an API surface that by then has many callers.

The third is the expensive one for this project specifically, because there is no Mac (§2.3) and therefore no way to learn it the cheap way.

## 2. Context

### 2.1 What today's application already does

`front_vibes` has a working state architecture, and the target is a faithful port rather than an invention. `stores/player.store.ts` (623 lines, Pinia) is the central playback state — `PlaybackState` is `'idle' | 'preparing' | 'playing' | 'paused' | 'error'`, alongside the current vibe context and an elapsed clock deliberately kept outside the reactive tree. Twenty composables (`useVibes`, `useSchedules`, `useAuth`, `useDevices`, …) hold per-domain state on top of the services.

That shape — a state holder per concern, exposing observable state, driven by explicit actions — is what this ADR formalizes in Kotlin. It is not a new architecture.

### 2.2 The hard cases already exist

`player.store.ts` exposes `showMiniPlayer` as a derived value. It is a useful test of any ownership rule: it derives from business state (is a session active?) but expresses a presentation intent (should the mini player be visible?). A rule that cannot classify it is not a rule. §Decision 4 answers it explicitly.

### 2.3 iOS is unverifiable today

There is no Mac. Every interop decision below is reasoned from the constraints of Kotlin/Native's Objective-C interop, not validated by compiling. That is stated as a limitation of this ADR, not hidden by it — and it is precisely why the interop contract is being decided **now**, before there are hundreds of callers, rather than when a Mac arrives.

## 3. Alternatives considered

| Option | What it means | Assessment |
| --- | --- | --- |
| **A. Shared state holders exposing `StateFlow`** | One state holder per screen in `shared`, platforms observe and dispatch intents | **Chosen.** The presentation logic is written once; the platforms stay thin and native. |
| **B. Platform ViewModels over shared repositories** | Each platform builds its own ViewModel layer on shared data | Rejected: duplicates the presentation logic — loading, error, derivation — on both platforms. That is the exact cost KMP was adopted to avoid, and ADR-038's matrix already places presentation state in `shared`. |
| **C. Callback/listener interfaces instead of Flow** | `shared` pushes updates through interfaces the platform implements | Rejected: it sidesteps the Swift `Flow` problem by giving up structured concurrency, cancellation and backpressure. Retained callbacks across the Kotlin/Swift boundary are also the most common source of reference cycles. |
| **D. Defer the interop rules until iOS starts** | Decide only the Android side now | Rejected. The rules in Decision 7 cost almost nothing when applied from the first file and are expensive to retrofit. Deferring them would turn a design choice into a migration. |

---

## Decision

### Decision 1 — The state pipeline

```
Ktor (API)  ──▶  Repository  ──▶  UseCase (only where a rule exists)
                     │                        │
                SQLDelight              StateHolder  (shared)
                DataStore                     │
                                   StateFlow<UiState>   Channel<Effect>
                          ┌───────────────────┴───────────────────┐
                  Compose (Android)                        SwiftUI (iOS, later)
```

- Each screen or coherent concern has **one state holder in `shared`**.
- The state holder is the **only** writer of that state. It updates in response to intents from the UI (`onPlayClicked`) or to emissions from repositories. Nothing in the UI writes domain state.
- **UseCases exist only where there is a rule.** A `getVibes()` that merely forwards to a repository does not earn a class. This is ADR-038 Decision 1 applied to the presentation layer: structure follows the rule, not the diagram.

### Decision 2 — `StateFlow` carries durable, observable state

State that a screen can be *in* is exposed as `StateFlow<UiState>`, where `UiState` is an immutable data class.

**Loading and error are fields of that state, not parallel channels:**

```kotlin
data class VibeListState(
    val items: List<Vibe> = emptyList(),
    val isLoading: Boolean = false,
    val error: DomainError? = null,
)
```

This applies to the state shapes the application already has: content loading and loaded, playback state, schedule state, authentication state, smart-home device state, and errors that are part of what a screen displays. **No new state models are introduced by this ADR** — it defines the mechanism, not the inventory.

A single `StateFlow` per state holder is preferred over several, so a screen cannot render a combination that the domain never produces.

### Decision 3 — `Channel` carries one-shot effects, and effects are never faked as state

Effects that must be consumed **exactly once** — navigation, a snackbar or toast, a dialog request, an external side effect — are emitted through a `Channel` (or an equivalently one-shot `SharedFlow`), never through `StateFlow`.

The prohibition is explicit because the shortcut is tempting: putting a `navigateTo` or `errorMessage` field in `UiState` makes it trivially observable, and then it replays on every recomposition, configuration change or view reappearance. An event that should fire once must not be reshaped into state to simplify UI integration.

**No event framework is built.** `Channel` from `kotlinx.coroutines` is the mechanism; no bus, no registry, no custom dispatcher abstraction.

### Decision 4 — State ownership follows responsibility, not location

There is deliberately **no rule that all state belongs in `shared`**. Ownership follows what the state *is*.

**`shared` owns** business state, execution state, state derived from shared rules, and any state whose behaviour must be consistent across platforms.

**The native UI owns** purely visual state, state local to one screen or component, interaction details with no domain meaning, and anything that is a mechanism of the UI framework itself — scroll position, focus, animation progress, expansion of a section, text-field cursor, transient gesture state.

Worked examples, including the ambiguous one from §2.2:

| State | Owner | Why |
| --- | --- | --- |
| Whether playback is active, and of which vibe | `shared` | Business state; must behave identically on both platforms |
| Elapsed seconds of a session | `shared` | Derived from execution state, not from the view |
| *Whether the mini player should be shown* | `shared` (as derived state) | It is a consequence of a domain fact — a session is active. **How** it is presented (bottom bar, sheet, inline) is the platform's |
| Whether a list section is expanded | Native UI | No domain meaning; survives nothing and means nothing off-screen |
| Scroll position, focus, animation | Native UI | Framework mechanism |
| Whether a form has unsaved changes | `shared` | Drives a domain-relevant decision (can the user leave?) |
| Which tab is selected | Native UI, unless a domain rule depends on it | Navigation is platform-owned (ADR-038) |

When a case genuinely does not resolve, ADR-038 Decision 6 applies: raise it rather than deciding it silently inside an implementation card.

### Decision 5 — Errors cross the boundary as values, never as exceptions

Every public API of `shared` returns a result type carrying a **sealed `DomainError`**. Exceptions are not part of the boundary contract.

This is not stylistic. An unhandled Kotlin exception crossing into Swift terminates the process: only functions annotated `@Throws` become `NSError`, and anything else is fatal. Modelling failure as a value removes a whole class of production crashes that would only appear on iOS, and makes error handling exhaustive on both sides.

Errors that a screen *displays* are additionally part of its `UiState` (Decision 2). The two are not in conflict: the result type is how a call reports failure; the state field is how a screen shows it.

### Decision 6 — Android consumption pattern

```
StateHolder (shared)
    ↓ StateFlow
collectAsStateWithLifecycle
    ↓
Composable
    ↑ intents / actions
StateHolder
```

The Android UI:

- collects state with `collectAsStateWithLifecycle`, so collection follows the lifecycle;
- renders that state and nothing it derived on its own from a repository;
- sends intents or actions **up** to the state holder;
- **must not** call a repository or data source directly to bypass the pipeline;
- **must not** re-implement a rule that lives in `shared`.

The state holder's `CoroutineScope` is owned and cancelled by the platform. On Android it is anchored to a `ViewModel`. Although `androidx.lifecycle.ViewModel` is itself multiplatform, anchoring on the Android side keeps ownership where the lifecycle actually is, and keeps `commonMain` free of a lifecycle framework.

This ADR formalizes the pattern; it does not implement it.

### Decision 7 — Swift interop contract

The goal is a Kotlin API that Swift can consume idiomatically **without `shared` knowing anything about Swift**. Rules, binding from the first file written:

1. **No exceptions cross the boundary** — Decision 5.
2. **`Flow` needs a bridge.** Swift has no equivalent. The bridge is **SKIE**, decided here rather than improvised later (Decision 8).
3. **`suspend` functions** map to Swift `async`, with cancellation nuances that SKIE narrows.
4. **Sealed classes** reach Swift without exhaustive `switch` unless bridged — which would silently discard the safety that motivated using them.
5. **Default arguments are not exposed to Swift.** Public APIs declare explicit overloads instead of relying on defaults.
6. **Generics are erased to `Any`** in Objective-C interop. Generic types are avoided on the public surface.
7. **Memory.** Kotlin/Native's current memory manager removed `freeze`, but reference cycles between Kotlin and Swift still leak. Retained callbacks across the boundary are the main hazard — another reason Decision 3 uses channels rather than listener interfaces.
8. **Threading.** `StateFlow` must emit on the main thread for SwiftUI. That is decided **in the state holder**, not left to the UI on either platform.
9. **Build.** The iOS framework is slow to link; a static framework is the default when `iosApp` is built.

No Swift code, no wrappers and no `iosApp` implementation are produced by this ADR. It fixes the contract that the future SwiftUI implementation will consume.

### Decision 8 — SKIE lives at the boundary and nowhere else

SKIE is adopted **only** as the Kotlin→Swift interop bridge:

```
Domain / UseCase / StateHolder
            ↓
       Kotlin API
            ↓
          SKIE
            ↓
         SwiftUI
```

- SKIE is **not** a domain dependency. Nothing in `domain/` or `data/` may reference it, be shaped by it, or degrade without it.
- The shared module is **not designed around SwiftUI**. If a SwiftUI convenience would require bending the domain API, the answer is a Swift-side adapter in `iosApp`, not a change in `shared`.
- SKIE is a third-party, community-maintained tool. That risk is bounded by this decision: it affects only the iOS platform layer, and the fallback — hand-written `Flow` wrappers — is well understood and replaceable without touching the domain.

Being a Gradle plugin applied at the iOS framework boundary, SKIE has **no effect on the Android build** and therefore does not block Android-first work.

### Decision 9 — Boundary rules

Binding, and enforceable by the boundary test of ADR-038 Decision 5:

- `commonMain` does not know Compose.
- `commonMain` does not know SwiftUI.
- `commonMain` does not know Swift or any Swift API.
- `shared` does not depend on Android UI, and Android UI is never a dependency of `shared`.
- `shared` does not depend on SwiftUI.
- Swift interop does not leak into the domain — Decision 8.
- The UI layer consumes contracts from `shared`; it does not reach around them.
- Platform-specific effects stay behind the abstractions ADR-038 defines.

No `SharedUI` layer is created, in any form. That prohibition belongs to ADR-039 Decision 6 and is restated here only because the state boundary is where such a layer would most plausibly be introduced by accident.

### Decision 10 — Android first; the contract is written to survive SwiftUI

- **Android is implemented and validated first.** The pattern in Decision 6 is the one that gets built.
- The contract in Decisions 1–9 must be **valid for a future SwiftUI implementation**, and any Android choice that could not be expressed through it is the wrong choice.
- **iOS is not compiled or validated in this phase**, and no artificial placeholders are created to simulate it.
- **Android work does not wait on a Mac.**

---

## 10. What acceptance would mean

Accepting this ADR means accepting:

1. State holders in `shared`, one per screen or coherent concern, as the single writer of domain state (Decision 1).
2. `StateFlow` for durable state with loading and error as fields, and `Channel` for one-shot effects, with the explicit prohibition on faking effects as state (Decisions 2 and 3).
3. Ownership by responsibility rather than by location, including that some state legitimately belongs to the native UI (Decision 4).
4. Results with a sealed `DomainError` instead of exceptions on every public API (Decision 5).
5. SKIE as the interop bridge, confined to the boundary, accepting a third-party dependency in the iOS platform layer only (Decision 8).
6. That the interop rules in Decision 7 are reasoned rather than verified, because no Mac exists (§2.3).

## Consequences

**Positive**

- Presentation logic — loading, error, derivation, sequencing — is written and tested once instead of twice.
- The one-shot/durable distinction is settled before the first screen, which is the point at which it is cheapest.
- The Swift boundary is designed rather than discovered, which is the difference between a rule and a refactor.
- The pipeline is testable end to end in `commonTest`: intents in, states out, with no device involved.

**Negative, accepted**

- Every screen gains a state holder, including the trivial ones. Decision 1's "UseCase only where there is a rule" limits the ceremony, but does not remove it.
- Decision 5 makes `Result`-style handling pervasive in code that, on an Android-only project, would simply throw.
- Decision 7's constraints — no default arguments, no generics on the public surface — make some Kotlin APIs more verbose than they would otherwise be, in service of a platform that does not yet compile.

**Risks**

- **Interop rules unverified.** Reasoned from documented Kotlin/Native behaviour, not from a build. The first iOS compilation is still expected to surface problems; this ADR reduces their number, not their existence.
- **Boundary erosion under deadline.** A screen calling a repository directly is a one-line shortcut that is invisible in review. Decision 6 makes it a rule; nothing mechanical enforces it today.
- **SKIE dependency.** Bounded by Decision 8: iOS-only, replaceable, with a known fallback.
- **Over-sharing of UI state.** The opposite failure to boundary erosion: pushing scroll position or animation state into `shared` because "state lives in shared". Decision 4 exists specifically to prevent that reading.

## Relationship to other ADRs

- **[ADR-038](ADR-038-kmp-shared-layer.md)** is the authority on what belongs to `shared`. Its matrix already places presentation state there and navigation on the platforms; this ADR does not reclassify anything, it defines the transport.
- **[ADR-039](ADR-039-native-ui.md)** is the authority on UI implementation. Decision 6 describes how Compose *consumes* state, not how it is built; the `SharedUI` prohibition originates in ADR-039 Decision 6.
- **ADR-040 (native player, K05)** is out of scope. Playback state appears here only as an example of a state shape crossing the boundary. The player's architecture, scheduler and fade semantics are ADR-040's, and nothing here anticipates them.
- **[ADR-042](ADR-042-migration-repository.md)** governs migration strategy and repository ownership; unaffected by this ADR.

## Sources

Code inspected 2026-09-23 in `front_vibes` @ `1cf858e`: `src/stores/player.store.ts` (623 lines — `PlaybackState`, elapsed clock outside the reactive tree, `showMiniPlayer` derived value), `src/composables/` (20 files — `useVibes`, `useAuth`, `usePlayerEngine`, `useSchedules`, `useDevices`, …), `src/services/player-engine.service.ts`.

Internal: [`kmp-migration-plan.md`](../architecture/mobile/kmp-migration-plan.md) (§6.5 state, §7 state architecture and data flow, §8 Kotlin↔Swift interop, §16.19 session state), [ADR-038](ADR-038-kmp-shared-layer.md), [ADR-039](ADR-039-native-ui.md), [ADR-042](ADR-042-migration-repository.md).
