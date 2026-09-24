# ADR-041: State contract across the shared/native boundary, and Kotlin↔Swift interop

## Status

**Accepted** (2026-09-23) — governs how application state and one-shot effects cross from the Kotlin Multiplatform shared module into the native user interfaces, and the interop rules that make that crossing survivable on iOS.

**Approved by the PO on 2026-09-23**, accepting the nine points recorded in §10. Acceptance followed a technical audit that returned *NOT READY* and produced four PO decisions, all applied before approval: the state-and-effect criterion for errors (Decision 3), `hasPresentableSession` instead of a UI-named boolean (Decision 4), `Result<T, DomainError>` confined to the domain layer rather than the Swift surface (Decisions 5 and 7), and the explicit acceptance of Decision 4 as a **new** architectural decision rather than a restatement of the plan. The same audit corrected three false attributions to ADR-038's matrix and the overstated scope of the boundary test.

Complements [ADR-038](ADR-038-kmp-shared-layer.md) and [ADR-039](ADR-039-native-ui.md); replaces neither. **ADR-038 remains the authority on what belongs to the shared layer**, and **ADR-039 remains the authority on how the native UI is implemented**. This ADR decides only what travels between them, in which direction, and in what shape.

ADR-040 (native player, card K05) is **out of scope**: the player's architecture, its scheduler and its fade semantics are that ADR's subject. This ADR treats playback state only as one consumer of the contract defined here, and does not anticipate any of its decisions. [ADR-042](ADR-042-migration-repository.md) governs the migration strategy and is unaffected.

## Date

2026-09-23

---

## 1. Problem

ADR-038 places domain, rules and repositories in `shared`, and the migration plan (§4, §7) places the state holders there too. ADR-039 places theme, components and screens in Compose and, later, SwiftUI. Between those two decisions there is an unspecified gap: **how a screen actually receives what it renders, and how it reports what the user did.**

Left unspecified, three things go wrong, and they are the ordinary failure modes of KMP projects rather than exotic ones:

1. **The UI starts reaching past the boundary.** A screen calls a repository directly "just this once", and the rule that produced the value now exists in two places.
2. **One-shot effects become sticky state.** A navigation event or an error toast is modelled as a `StateFlow` field because that is the easy way to observe it, and then fires again on every recomposition or view reappearance.
3. **The Swift boundary is discovered late.** Kotlin constructs that are perfectly idiomatic — `Flow`, sealed classes, default arguments, thrown exceptions — either do not cross to Swift at all or cross in a degraded form. Discovering this when the iOS application is first compiled means reworking an API surface that by then has many callers.

The third is the expensive one for this project specifically, because there is no Mac (§2.4) and therefore no way to learn it the cheap way.

## 2. Context

### 2.1 What today's application already does

`front_vibes` has a working state architecture, and the target is a faithful port rather than an invention. `stores/player.store.ts` (623 lines, Pinia) is the central playback state — `PlaybackState` is `'idle' | 'preparing' | 'playing' | 'paused' | 'error'`, alongside the current vibe context and an elapsed clock deliberately kept outside the reactive tree. Twenty composables (`useVibes`, `useSchedules`, `useAuth`, `useDevices`, …) hold per-domain state on top of the services.

That shape — a state holder per concern, exposing observable state, driven by explicit actions — is what this ADR formalizes in Kotlin. It is not a new architecture.

### 2.2 The hard cases already exist

`player.store.ts` exposes `showMiniPlayer` as a derived value. It is a useful test of any ownership rule: its computation reads only `currentVibeId`, `playbackState` and `hasActiveLayers` — no route, no screen, no platform API — so the **rule** is pure domain, while the **name** states a UI intent. A rule that cannot classify that is not a rule. Decision 4 answers it explicitly, and resolves it by keeping the rule in `shared` under a domain name while leaving the visual materialization to each platform.

### 2.3 A note on the word "presentation"

The term carries two meanings across these ADRs, and conflating them produces an apparent contradiction where there is none.

In this ADR, **"presentation state" means the shared StateHolder state that the native UI consumes** — what a screen is in, expressed as data. That lives in `shared`.

ADR-038 uses "presentation" in a different sense in its Decision 6 worked examples, where *"a chart on a statistics screen… is presentation"* classifies **visual rendering** as platform-owned. That remains true and is not in tension with the above: the aggregation feeding the chart is shared state; drawing the chart is platform work.

Wherever this ADR says presentation state, it means the first sense.

### 2.4 iOS is unverifiable today

There is no Mac. Every interop decision below is reasoned from the constraints of Kotlin/Native's Objective-C interop, not validated by compiling. That is stated as a limitation of this ADR, not hidden by it — and it is precisely why the interop contract is being decided **now**, before there are hundreds of callers, rather than when a Mac arrives.

## 3. Alternatives considered

| Option | What it means | Assessment |
| --- | --- | --- |
| **A. Shared state holders exposing `StateFlow`** | One state holder per screen in `shared`, platforms observe and dispatch intents | **Chosen.** The presentation logic is written once; the platforms stay thin and native. |
| **B. Platform ViewModels over shared repositories** | Each platform builds its own ViewModel layer on shared data | Rejected: duplicates the presentation logic — loading, error, derivation — on both platforms. That is the exact cost KMP was adopted to avoid, and the migration plan already places state holders in `shared` (§4, §7). |
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

**One error may legitimately produce both a state and an effect.** State and effect are not mutually exclusive representations of the same failure — they answer different questions, and the criterion is what the error does to the screen:

| Situation | Representation |
| --- | --- |
| The error **blocks or replaces** the content — the list did not load | `UiState.error` — the screen renders an error/retry state |
| The error **annotates a completed action** — saving failed, the screen stays usable | `Effect.ShowToast` |
| The error **both** blocks the content **and** warrants an immediate notice | `UiState.error` **and** `Effect.ShowToast` |

Two constraints on the third row: the pairing must be **deliberate**, decided by the state holder, never the accidental by-product of two code paths reporting the same failure. And no deduplication rule is invented here — the project has no such mechanism, and this ADR does not create one.

This formalizes behaviour already present and already compatible with the plan, not a new capability. Plan §7 states both halves — `error: DomainError?` is a field of `VibeListState`, and toast is listed among the one-shot effects. The existing application does both too: `player.store.ts` sets `playbackState = 'error'` with a timed reset (`PLAYBACK_ERROR_IDLE_MS = 2_400`) **and** raises a toast, while `AppErrorState.vue` renders persistent error states in several screens.

### Decision 4 — State ownership follows responsibility, not location

> **This is a new architectural decision introduced by this ADR.** It is not a restatement of the migration plan. The plan (§7) says the platforms hold only ephemeral UI state and names three examples — scroll, focus, animation. Read literally, that becomes the simplistic rule *"everything goes to `shared` except those three"*, which cannot classify the cases a real application produces. This decision generalizes the plan's intent into a principle that can classify a case the plan never mentions, and therefore **extends and clarifies the plan** rather than reproducing it.

**The principle:**

> State belongs to the layer that owns the responsibility for its **semantics**.

**`shared` owns** state whose meaning is domain, product rule, session, playback, schedule, authentication, smart home, content availability, or a presentation decision **derived from a business rule**.

**The native UI owns** state whose meaning is purely local interaction or rendering: scroll position, focus, animation progress, an expanded section, the selected tab, an unpersisted local draft, and equivalent visual-interaction detail.

**The tie-breaker**, for cases neither list mentions. Do not classify by appearance — not *"it looks like UI, so native"*, and not *"it is state, so shared"*. Ask instead:

> Who owns the semantic responsibility for this state?

Two practical tests follow from it. If you removed the UI entirely and the rule still made sense as product behaviour, it tends to be `shared`. If the state exists only to drive the interaction or rendering of that particular UI implementation, it tends to be native.

Worked examples — illustrations of the principle, not a closed list:

| State | Owner | Why |
| --- | --- | --- |
| Whether playback is active, and of which vibe | `shared` | Product semantics; must behave identically on both platforms |
| Elapsed seconds of a session | `shared` | Derived from execution state, not from the view |
| Whether there is a **presentable session** (§2.2) | `shared` (the rule) · Native UI (the materialization) | See below |
| Whether a form has unsaved changes | `shared` | Drives a product decision — may the user leave? |
| Whether a list section is expanded | Native UI | No semantics off-screen |
| Scroll position, focus, animation | Native UI | Framework mechanism |
| Which tab is selected | Native UI | Navigation is platform-owned (ADR-038), unless a product rule depends on it |
| An unpersisted local draft | Native UI | Becomes `shared` the moment persistence or a rule attaches to it |

**The presentable-session case, decided.** `shared` exposes a domain-named fact — **`hasPresentableSession`** — and the platform decides whether that fact becomes a mini player, a sheet, an inline bar, or nothing on a given screen.

```
Shared  ──▶  hasPresentableSession  ──▶  Platform UI  ──▶  MiniPlayer
```

The product rule stays whole in `shared`, conceptually preserved from `player.store.ts`: it derives from `currentVibeId`, `playbackState` and `hasActiveLayers`, treats `preparing` as presentable **only** when layers are active, keeps the online and offline flows consistent, and yields false on error because errors clear layers. **No new product rule is invented here** — the existing one is carried over under a domain name.

What changes is only the name and the ownership of the last step. A boolean called `showMiniPlayer` would put a UI component's name inside the domain and quietly hand `shared` a rendering decision; `hasPresentableSession` states the fact and stops there. This is the general principle applied: **`shared` owns the product semantics, the native UI owns the visual implementation** — consistent with ADR-038, which places UI and navigation on the platforms, and with ADR-039, which puts chrome and components in Compose and SwiftUI. It also avoids the opposite failure: pushing the rule itself to the platforms, where it would be implemented twice and drift.

When a case genuinely does not resolve under the tie-breaker, ADR-038 Decision 6 applies: raise it rather than deciding it silently inside an implementation card.

### Decision 5 — Errors cross the boundary as values, never as exceptions

Failure is modelled as a value, never as a thrown exception. `Result<T, DomainError>`, with a **sealed `DomainError`**, is the return contract of the domain layer inside `commonMain` — repositories, use cases and anything they call.

This is not stylistic. An unhandled Kotlin exception crossing into Swift terminates the process: only functions annotated `@Throws` become `NSError`, and anything else is fatal. Modelling failure as a value removes a whole class of production crashes that would only appear on iOS, and makes error handling exhaustive on both sides.

**`Result<T, DomainError>` does not cross the public presentation boundary.** The state holder consumes it and converts it into concrete state or a concrete effect:

```
Repository  ──▶  Result<T, DomainError>  ──▶  UseCase  ──▶  Result<T, DomainError>
                                                                   │
                                                              StateHolder
                                                                   │
                              StateFlow<ConcreteUiState>  +  Channel<ConcreteEffect>
                                                                   │
                                            Android Compose  /  SwiftUI (later)
```

Consequences of that split:

- `commonMain` uses `Result<T, DomainError>` freely, and so does Android, which can consume it directly without penalty.
- Swift never has to unwrap a generic `Result`. What it sees is a concrete `UiState` and a concrete sealed `Effect`.
- No generic casts are introduced on the Swift side, and no Swift wrappers are written now.

**On the plan's wording.** Plan §7 says *"Todo retorno público é `Result<T, DomainError>`"*. That sentence stands; this ADR fixes its scope rather than retracting it: **`Result<T, DomainError>` is the public return contract of the domain layer, and is not the presentation API exposed to SwiftUI.** This is a specialization of the presentation and interop boundary, not an abandonment of `Result`. The plan is not amended here (see Decision 7, rule 6).

Errors that a screen *displays* are part of its `UiState` (Decision 2), and errors that merely announce a failed action are effects (Decision 3). Neither contradicts this decision: `Result` is how a call reports failure inside the domain; state and effects are how a screen expresses it.

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

The state holder's `CoroutineScope` is owned and cancelled by the platform. On Android it is anchored to a `ViewModel`, which keeps ownership where the lifecycle actually is and keeps `commonMain` free of a lifecycle framework.

**Unvalidated claim, carried from the plan.** Plan §7 notes that `androidx.lifecycle.ViewModel` is itself multiplatform, which would allow the state holder to *be* a `ViewModel` inside `shared`. **That has not been verified in this project** — there is no version catalog, no Gradle build and no test to confirm it, and this ADR does not confirm it from outside knowledge. The decision above does not depend on the claim being true: anchoring on the Android side is chosen for lifecycle ownership, not because the multiplatform route is unavailable. Verification belongs to K07, when a real version catalog exists.

This ADR formalizes the pattern; it does not implement it.

### Decision 7 — Swift interop contract

The goal is a Kotlin API that Swift can consume idiomatically **without `shared` knowing anything about Swift**. Rules, binding from the first file written:

1. **No exceptions cross the boundary** — Decision 5.
2. **`Flow` needs a bridge.** Swift has no equivalent. The bridge is **SKIE**, decided here rather than improvised later (Decision 8).
3. **`suspend` functions** map to Swift `async`, with cancellation nuances that SKIE narrows.
4. **Sealed classes** reach Swift without exhaustive `switch` unless bridged — which would silently discard the safety that motivated using them.
5. **Default arguments are not exposed to Swift.** Public APIs declare explicit overloads instead of relying on defaults.
6. **Generics are erased to `Any`** in Objective-C interop, so generic types are avoided **on the public presentation surface** — the one Swift consumes. This is exactly why Decision 5 keeps `Result<T, DomainError>` inside the domain layer and has the state holder convert it: `UiState` and `Effect` are concrete, per-screen types, so nothing generic reaches Swift. The two rules are complementary, not in tension.
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
- SKIE is a third-party, community-maintained tool. That risk is bounded by this decision: it is confined to the iOS platform layer, and the fallback — hand-written `Flow` wrappers — is a known alternative that would not touch the domain.

**Unvalidated, and recorded as such.** The migration plan adopts SKIE for Kotlin/Swift interoperability, and this ADR keeps that adoption. But its exact Gradle and build impact, and the generated Swift interop behaviour, **remain unvalidated until a real KMP/iOS toolchain exists**. Specifically: the expectation is that a plugin applied at the iOS framework boundary does not affect the Android build, and therefore does not impede Android-first work — that is an expectation, not a verified fact. Validation belongs to K07 and the first real build, not to this ADR. SKIE is not removed for lacking validation; the plan recommends it and no better-supported alternative is available.

### Decision 9 — Boundary rules

All of the rules below are **binding**. Their *enforcement*, however, is only partial today, and this ADR states that limit rather than implying more than exists.

**Mechanically verifiable by the ADR-038 Decision 5 boundary test**, which scans `commonMain` for `java.*`, `javax.*`, `android.*`, `androidx.*` and `java.time`:

- `commonMain` does not reference Android or JVM-only APIs.
- `commonMain` does not know Compose — Compose lives under `androidx.compose.*`, already covered by the existing pattern.

**Binding, but verified by review today, not by machine:**

- `shared` does not depend on Android UI through Gradle, and Android UI is never a dependency of `shared`. This is a build-file relationship, not an import, so a source scan cannot see it.
- Swift interop does not leak into the domain (Decision 8). The SKIE package is not in the scanned list.
- The UI layer consumes contracts from `shared` and does not reach around them (Decision 6). The current test does not scan `androidApp` at all.
- State ownership is respected (Decision 4). Not detectable by import scanning under any formulation.
- Platform-specific effects stay behind the abstractions ADR-038 defines.

**On SwiftUI specifically:** `commonMain` cannot reference SwiftUI, because SwiftUI is not expressible in Kotlin. The rule is vacuous rather than unenforced, and **no Kotlin scanner is proposed for it** — there is nothing a scanner could find.

**Possible future extensions, recorded as possibilities and not as existing capability:** adding SKIE's package to the scanned list, and a second scanner pointed at `androidApp` to catch the Decision 6 bypass. No automatic mechanism is proposed for state ownership; it stays a review concern. None of these is authorized by this ADR.

No `SharedUI` layer is created, in any form. That prohibition belongs to ADR-039 Decision 6 and is restated here only because the state boundary is where such a layer would most plausibly be introduced by accident.

### Decision 10 — Android first; the contract is written to survive SwiftUI

- **Android is implemented and validated first.** The pattern in Decision 6 is the one that gets built.
- The contract in Decisions 1–9 must be **valid for a future SwiftUI implementation**, and any Android choice that could not be expressed through it is the wrong choice.
- **iOS is not compiled or validated in this phase**, and no artificial placeholders are created to simulate it.
- **Android work does not wait on a Mac.**

---

## 10. What acceptance meant

Accepted by the PO on 2026-09-23. Acceptance covered, specifically:

1. State holders in `shared`, one per screen or coherent concern, as the single writer of domain state (Decision 1).
2. `StateFlow` for durable state with loading and error as fields, and `Channel` for one-shot effects, with the explicit prohibition on faking effects as state (Decisions 2 and 3).
3. That one error may deliberately produce **both** a state and an effect, under the criterion in Decision 3 — blocking errors are state, action-level failures are effects, and an error that is both is represented as both.
4. **Decision 4 as a new architectural decision**, not as a restatement of the plan: ownership by semantic responsibility, with the tie-breaker that classifies cases no list mentions, and the consequence that some state legitimately belongs to the native UI.
5. That `shared` exposes `hasPresentableSession` — the product rule, under a domain name — and that each platform decides whether it becomes a mini player (Decision 4).
6. `Result<T, DomainError>` as the domain-layer return contract inside `commonMain`, **not** as the presentation API exposed to Swift, which sees concrete `UiState` and `Effect` types (Decisions 5 and 7). This specializes the scope of plan §7's wording; it does not retract it.
7. That the enforcement of Decision 9 is **partial**: two rules are mechanically checked, the rest are binding by review, and the listed scanner extensions are possibilities rather than existing capability.
8. SKIE as the interop bridge, confined to the boundary, accepting a third-party dependency in the iOS platform layer only — with its build impact and interop behaviour **unvalidated** until a real toolchain exists (Decision 8).
9. That the interop rules in Decision 7, and the multiplatform-`ViewModel` claim in Decision 6, are reasoned or inherited rather than verified, because no Mac and no Gradle build exist yet (§2.4).

## Consequences

**Positive**

- Presentation logic — loading, error, derivation, sequencing — is written and tested once instead of twice.
- The one-shot/durable distinction is settled before the first screen, which is the point at which it is cheapest.
- The Swift boundary is designed rather than discovered, which is the difference between a rule and a refactor.
- The pipeline is testable end to end in `commonTest`: intents in, states out, with no device involved.

**Negative, accepted**

- Every screen gains a state holder, including the trivial ones. Decision 1's "UseCase only where there is a rule" limits the ceremony, but does not remove it.
- Decision 5 makes `Result`-style handling pervasive in code that, on an Android-only project, would simply throw.
- Decision 7's constraints — no default arguments, no generics on the **public presentation surface** — make some Kotlin APIs more verbose than they would otherwise be, in service of a platform that does not yet compile. Internal domain code is unaffected: `Result<T, DomainError>` stays generic and idiomatic there (Decision 5).

**Risks**

- **Interop rules unverified.** Reasoned from documented Kotlin/Native behaviour, not from a build. The first iOS compilation is still expected to surface problems; this ADR reduces their number, not their existence.
- **Boundary erosion under deadline.** A screen calling a repository directly is a one-line shortcut that is easy to miss in review. Decision 6 makes it a rule, and Decision 9 is explicit that nothing mechanical catches it today — the current boundary test does not scan `androidApp`.
- **SKIE dependency, and unvalidated.** Bounded by Decision 8 to the iOS platform layer, with hand-written `Flow` wrappers as a known alternative. Its build impact and interop behaviour are expectations, not verified facts, until a real toolchain exists (K07).
- **Over-sharing of UI state.** The opposite failure to boundary erosion: pushing scroll position or animation state into `shared` because "state lives in shared". Decision 4 exists specifically to prevent that reading.

## Relationship to other ADRs

- **[ADR-038](ADR-038-kmp-shared-layer.md)** is the authority on what belongs to `shared`. Its matrix places navigation on the platforms, and it contains **no row classifying presentation state** — that classification comes from elsewhere, and this ADR does not pretend otherwise. What places state holders in `shared` is the migration plan: [§4](../architecture/mobile/kmp-migration-plan.md) (`presentation/ — StateHolders por tela — StateFlow<UiState>`) and §7 (*"Onde o estado vive: no `shared`, em um StateHolder por tela"*). ADR-038 Decision 4 supports it structurally, since its `commonMain` layout includes a `presentation/` package, and [ADR-039](ADR-039-native-ui.md)'s Relationship section states that presentation state arrives from the shared layer. This ADR reclassifies nothing; it defines the transport.
- **[ADR-039](ADR-039-native-ui.md)** is the authority on UI implementation. Decision 6 describes how Compose *consumes* state, not how it is built; the `SharedUI` prohibition originates in ADR-039 Decision 6.
- **ADR-040 (native player, K05)** is out of scope. Playback state appears here only as an example of a state shape crossing the boundary. The player's architecture, scheduler and fade semantics are ADR-040's, and nothing here anticipates them.
- **[ADR-042](ADR-042-migration-repository.md)** governs migration strategy and repository ownership; unaffected by this ADR.

## Sources

Code inspected 2026-09-23 in `front_vibes` @ `1cf858e`: `src/stores/player.store.ts` (623 lines — `PlaybackState`, elapsed clock outside the reactive tree, `showMiniPlayer` derived value), `src/composables/` (20 files — `useVibes`, `useAuth`, `usePlayerEngine`, `useSchedules`, `useDevices`, …), `src/services/player-engine.service.ts`.

Internal: [`kmp-migration-plan.md`](../architecture/mobile/kmp-migration-plan.md) (§6.5 state, §7 state architecture and data flow, §8 Kotlin↔Swift interop, §16.19 session state), [ADR-038](ADR-038-kmp-shared-layer.md), [ADR-039](ADR-039-native-ui.md), [ADR-042](ADR-042-migration-repository.md).
