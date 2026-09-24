# ADR-038: KMP shared layer — what is shared, what is not, and how to decide

## Status

**Accepted** (2026-09-23) — governs the boundary of the Kotlin Multiplatform `shared` module in the `ixora-app` mobile rebuild: which responsibilities live there, which stay native, and the test that classifies a responsibility that does not yet exist.

**Approved by the PO on 2026-09-23**, accepting the five points recorded in §9: the three-condition SHARED test and its tie-breaker (Decision 1), the binding responsibility matrix (Decision 2), the three deliberate non-shares (Decision 3), the single `shared` module with measured split conditions (Decision 4), and boundary enforcement by automated test with a sentinel (Decision 5) — including the accepted residual iOS risk that a scan cannot replace a compiler. No pre-acceptance corrections were required.

Base ADR of the KMP track. [ADR-039](ADR-039-native-ui.md) (native UI, card K03) builds directly on the matrix this ADR fixes. ADR-040 (player, K05), ADR-041 (state and interop, K06) and ADR-042 (migration strategy, K04) do the same and are not written yet — they are referenced by number, without links, until they exist. None of them may contradict this ADR.

Does **not** touch [ADR-007](ADR-007-execution-plan-runtime-contract.md) (execution plan as the playback runtime contract) or [ADR-036](ADR-036-google-home-execution-model.md) (Google Home execution model), both reaffirmed in §7. Does **not** decide the player's internals (ADR-040), the UI (ADR-039) or the state contract (ADR-041).

Implements the direction approved by the PO and recorded in [`kmp-migration-plan.md`](../architecture/mobile/kmp-migration-plan.md) §0 (decisions D1–D5).

## Date

2026-09-23

---

## 1. Problem

The mobile application is being rebuilt from Ionic 8 / Vue 3 / Capacitor into Kotlin Multiplatform with native UI. That rebuild needs a rule for what belongs in the `shared` module — not a list, a **rule**, because a list goes stale the first time someone adds a feature the list does not mention.

Two failure modes are available, and both are common in KMP projects:

- **Over-sharing.** Something is placed in `commonMain` because it is technically possible to put it there. The result is an abstraction that satisfies neither platform, needs an `expect/actual` for most of its body, and is more expensive to maintain than two honest implementations. Ixora already lived through a version of this: `@capgo/native-audio` was a cross-platform audio abstraction, and the project had to abandon runtime fades because the abstraction could not carry them ([ADR-008](ADR-008-nativeaudio-limitations-over-unstable-dsp.md)).
- **Under-sharing.** Domain rules get reimplemented per platform, they drift, and the second platform pays the full cost of the first. At that point KMP is a build-system complication with no return.

Without a written criterion, each new component becomes an ad-hoc argument decided by whoever is typing.

## 2. Context — measured, not estimated

Counted in `front_vibes` @ `develop` (`1cf858e`), excluding test files:

| Block | Lines | Nature |
| --- | --- | --- |
| UI (`views/` + `components/`) | 13.640 | Rewritten per platform |
| Audio runtime | 2.849 | Replaced by Media3 / AVAudioEngine |
| Platform-free logic (17 services + 16 utils) | ~3.900 | Migrates to `commonMain` almost 1:1 |
| Existing Kotlin (Google Home plugin) | 493 | Migrates essentially intact |
| **Total `src/`** | **27.590** | |

Import coupling: `@ionic` in 40 files, `vue` in 49, `@capacitor` in 27, `pinia` in 7, `firebase` in 4.

**The shared module will hold roughly 15% of today's code.** That is not a defect of this decision — it follows from choosing native UI (ADR-039). It is stated here so nobody later reads the small `shared` module as a sign that the migration went wrong.

Two properties of the existing codebase make the boundary unusually clean:

1. **Playback is already device-side.** The backend has no playback engine; `buildVibeExecutionPlan` is a pure `VibeSound[] → VibeExecutionLayer[]` transformation (ADR-007). It is the single highest-value shared asset in the application.
2. **The smart-home domain is already provider-neutral.** The CSDM canonical model (ADR-037) was built so no provider dictates domain semantics, and it is protected by boundary tests. It ports to Kotlin as domain code, not as integration code.

## 3. Alternatives considered

| Option | What it means | Why not |
| --- | --- | --- |
| **A. Share everything technically shareable** | Push UI state, navigation and an audio abstraction into `commonMain` | Reproduces the `@capgo` dead-end at a larger scale; the abstraction becomes the ceiling for both platforms |
| **B. Share nothing; two native apps** | Kotlin/Android and Swift/iOS, fully separate | Domain rules drift; the execution plan and the CSDM model get implemented twice with different bugs; discards the migration's main technical payoff |
| **C. Share behaviour and domain; implement platform at the boundary** | `commonMain` holds rules, contracts and decisions; platforms hold transport, UI and OS integration | **Chosen.** Matches where the value actually is (§2) and where the cost actually is |

---

## Decision

### Decision 1 — The SHARED test: three conditions, all required

A responsibility belongs in `commonMain` when **all three** hold:

1. **It encodes a rule of the domain or a contract with the backend.** Not a convenience, not glue.
2. **The contract is identical on both platforms.** If Android and iOS would legitimately want different behaviour, it is not shared.
3. **It is testable without a platform** — no device, no emulator, no UI, no OS service.

And one negative condition that overrides the three:

4. **If implementing it requires naming a platform API inside `commonMain`, it is not shared code — it is a shared *interface* with platform implementations.**

**Tie-breaker for the hard cases.** When conditions 1–3 hold but the natural implementation would need `expect/actual` for most of its body, the thing is **platform-specific with a shared contract**, not shared code. The `expect/actual` mechanism is for small, stable surfaces (get/set/remove); anything larger belongs behind an interface injected from the platform, so it can be faked in tests.

This test is deliberately written to be applied to responsibilities that **do not exist yet**. Section 6 works through examples.

### Decision 2 — The responsibility matrix is binding

The matrix below is no longer a proposal. It is the decision. Legend: ● implements · ○ consumes · — does not participate.

| Responsibility | Shared | Android | iOS | Rationale |
| --- | --- | --- | --- | --- |
| Models / DTOs | ● | ○ | ○ | Single contract with the Laravel API; divergence here is a guaranteed bug |
| Networking (HTTP) | ● | ○ | ○ | Ktor covers both platforms; the REST contract is identical |
| API clients | ● | ○ | ○ | Eliminates duplicated routes and parsing |
| Repositories | ● | ○ | ○ | Cache and offline policy is a domain rule, not a platform one |
| Business rules | ● | ○ | ○ | The reason the module exists |
| Vibe execution plan | ● | ○ | ○ | Pure, critical function; one test set serves both platforms (ADR-007) |
| Layer scheduling (what should be playing at time *t*) | ● | ○ | ○ | Deterministic and testable; see ADR-040 |
| Relational persistence | ● | ○ | ○ | SQLDelight generates the same schema and queries on both sides |
| Non-sensitive preferences | ● | ○ | ○ | DataStore is multiplatform |
| Error types | ● | ○ | ○ | Domain errors are domain, and must not cross the boundary as exceptions (ADR-041) |
| Logging | ● | ○ | ○ | Cheap abstraction; output per platform |
| Secure storage (token) | ○ | ● | ● | Keystore and Keychain have no honest common abstraction |
| Firebase Auth | ○ | ● | ● | No official KMP SDK; native SDKs behind an interface |
| Push notifications | ○ | ● | ● | Token registration shared; delivery and display native |
| Analytics / telemetry | ○ | ● | ● | Interface shared, SDK native; scope in plan §16.13 |
| Google Home | ○ | ● | — | Android-only SDK; iOS will never have it (ADR-036) |
| **Audio transport** | — | ● | ● | Media3 and AVAudioEngine have no honest common denominator |
| Background playback | — | ● | ● | Foreground service vs. background mode: incompatible OS models |
| Navigation | — | ● | ● | Navigation is part of each platform's identity |
| Permissions | — | ● | ● | Divergent APIs and consent flows |
| Background tasks | — | ● | ● | WorkManager vs. BGTaskScheduler |
| Video / animated background | — | ● | ● | Does not exist today; if it lands, it is native |
| UI | — | ● | ● | No Compose Multiplatform (ADR-039) |
| Design language (tokens, principles) | concept | concept | concept | One rule, but **not code in `shared`** — plan §16.14.4 |
| Theme, components, screens | — | ● | ● | Compose and SwiftUI implement the same language separately |
| Home Assistant | — | — | — | Execution is **server-side** in `back_vibes` (ADR-036); the app only calls the API |

Nothing in this matrix was marked shared merely because sharing it was technically possible.

### Decision 3 — Three deliberate non-shares

These are the cases where the tempting answer was rejected, and they are recorded so the rejection is not relitigated as an oversight.

**Audio transport.** Media3/ExoPlayer and AVAudioEngine differ in threading model, buffering, lifecycle and volume control. An abstraction over both becomes the ceiling of what either can do — which is precisely how Ixora lost runtime fades under `@capgo/native-audio` (ADR-008). What **is** shared is the decision layer: the execution plan and the scheduler that says what should be playing at time *t*. The platform makes it play. See ADR-040.

**Navigation.** Back behaviour, transitions, deep-link handling and system gestures are part of what makes an app feel native. A shared navigation graph would force one platform's model onto the other. What may be shared is the *intent* ("open vibe 42"), never the mechanics.

**UI.** Decided by the PO and formalized in ADR-039. What is shared is the design language — tokens, principles, component rules — as a concept, not as code, and explicitly not as a `design-system` KMP module (plan §16.14).

The pattern across all three: **share the decision, not the mechanism.**

### Decision 4 — One `shared` module, packages by domain

The shared layer is a **single Gradle module** with internal packages:

```
shared/src/commonMain/kotlin/app/ixora/shared/
    domain/{vibe,player,smarthome,schedule,auth}/
    data/{remote,local,repository}/
    presentation/
    platform/
    di/
```

Rejected: one module per domain (`core`, `network`, `vibes`, `player`, …). For one developer and a codebase this size, eight-plus Gradle modules cost sync and configuration time every day and buy boundaries that a test can enforce for free.

**Objective condition for splitting later** — at least one must be true and **measured**, not anticipated:

1. Build or Gradle sync time has become a measured impediment, and module isolation demonstrably fixes it.
2. A domain needs a different set of targets from the rest of the module.
3. A second consumer outside `ixora-app` needs part of the module without the rest.

Symmetry with other projects, aesthetic preference, or "it will grow" are **not** sufficient conditions.

### Decision 5 — The boundary is enforced by test, not by convention

`commonMain` must not reference JVM-only (`java.*`, `javax.*`) or Android-only (`android.*`, `androidx.*`) APIs, and must use `kotlinx-datetime` rather than `java.time`.

This is enforced by an automated boundary test (K08), **with a sentinel that proves the guard actually fails** on a deliberate violation — the same pattern already proven in this codebase by `CanonicalBoundaryTest` and `ProviderExtensibilityBoundaryTest` in `back_vibes`.

The reason this is a decision rather than a nicety: **there is no Mac, so `commonMain` cannot be verified by compiling for iOS.** The test is the only mechanism standing between today and a large, late surprise at first iOS compilation. It reduces that risk; it does not eliminate it, and this ADR does not pretend otherwise.

### Decision 6 — Classifying something new, without reopening this ADR

Apply Decision 1. Worked examples, chosen to cover the shapes that will actually come up:

| New responsibility | Classification | Why |
| --- | --- | --- |
| API client for a new backend endpoint | **Shared** | Rule + identical contract + testable with a mock engine |
| Recurrence rule for a new schedule type | **Shared** | Pure domain logic; the calendar does not change per platform |
| Biometric unlock | **Interface + platform** | Fails (4): BiometricPrompt and LocalAuthentication must be named |
| A chart on a statistics screen | **Platform** | Fails (1): it is presentation. The *aggregation* feeding it is shared |
| Home-screen widget / iOS complication | **Platform** | Fails (2): the platforms' models are not the same product surface |
| "Sleep timer stops playback after N minutes" | **Split** | The rule (when to stop) is shared; stopping the audio is transport |
| Offline download queue | **Split** | Queue policy and state shared; file I/O behind an interface |
| A new smart-home provider | **Shared domain, server-side integration** | CSDM keeps the domain provider-neutral (ADR-037); the adapter lives in `back_vibes` |

When a case genuinely does not resolve under Decision 1 — the conditions conflict, or the answer would set a new precedent — **stop and raise it to the PO** rather than deciding it inside an implementation card. Judgement calls that are made silently inside a card are the ones that erode a boundary.

### Decision 7 — Relationship to existing ADRs

- **[ADR-007](ADR-007-execution-plan-runtime-contract.md) is reaffirmed.** The execution plan remains the mobile playback runtime contract, and the backend still has no playback engine. ADR-007 names the TypeScript files as the shipping implementation; it needs an addendum pointing to the Kotlin implementation once the migration's Phase 5 completes, not before.
- **[ADR-037](ADR-037-canonical-smart-home-device-model.md) and the CSDM contract are reaffirmed.** The canonical model ports to Kotlin as domain code, and `ixora-app` becomes a vendored consumer of `capability.v1.schema.json` under the rule in [`contracts/README.md`](../../contracts/README.md), with its own coherence test.
- **[ADR-036](ADR-036-google-home-execution-model.md) is reaffirmed.** Google Home stays Android-only and device-side; Home Assistant stays server-side. The shared module knows an execution interface, never a provider identity.
- **[ADR-008](ADR-008-nativeaudio-limitations-over-unstable-dsp.md) is *not* resolved here.** Its fade prohibition is reopened by ADR-040, deliberately and explicitly.

### Decision 8 — Android first; iOS declared, not built

Consistent with D5. The `shared` module declares `androidTarget`, `iosArm64` and `iosSimulatorArm64` from the start and is written free of Android-only APIs, but **only `androidApp` is built, run and validated** during the K01–K12 track. No SwiftUI work is authorized by this ADR, and no Android work waits on a Mac.

The cost of keeping `commonMain` iOS-clean while Android is the only target is small — mainly `kotlinx-datetime` over `java.time`, Ktor over raw OkHttp, SQLDelight over Room-Android. The cost of *not* doing it is rewriting the domain layer when iOS starts.

---

## 9. What acceptance meant

Accepted by the PO on 2026-09-23. Acceptance covered, specifically:

1. The three-condition SHARED test and its tie-breaker (Decision 1) as the standing rule for classification.
2. The responsibility matrix (Decision 2) as binding on ADR-039 to ADR-042 and on every implementation card.
3. That audio transport, navigation and UI are **not** shared, and that this is a choice rather than a limitation (Decision 3).
4. A single `shared` module, splittable only under the three measured conditions (Decision 4).
5. That the boundary is enforced by an automated test with a sentinel (Decision 5), accepting that without a Mac this reduces but does not eliminate the iOS risk.

No open questions blocked acceptance, and no pre-acceptance corrections were requested. The plan's remaining open items — timeline, `minSdk`, the phase in which telemetry instrumentation lands — do not affect this boundary.

## Consequences

**Positive**

- Every future classification question has a written answer, applied the same way by whoever is implementing.
- The highest-value logic — execution plan, scheduler, CSDM domain, recurrence rules — is written and tested once.
- The two historical traps are named and closed: sharing a mechanism because it is technically shareable, and reimplementing a rule per platform.
- When iOS starts, the domain layer already exists and is tested.

**Negative, accepted**

- `shared` holds only ~15% of today's code. The UI is written twice and the audio transport is written twice.
- Every `expect/actual` and every injected interface is machinery that a single-platform app would not need. Decision 1's condition (4) and the tie-breaker exist to keep that machinery small.
- The single-module choice trades enforced boundaries for build simplicity, and depends on the K08 test to stay honest.

**Risks**

- **`commonMain` drifts toward iOS-incompatibility without anyone noticing.** The boundary test is the mitigation; it is a scan, not a compiler, and it cannot prove the code compiles for iOS.
- **The matrix ages.** Mitigated by Decision 6: new cases are classified by the test, and only a genuine conflict reopens this ADR.
- **Pressure to share the UI later**, to avoid writing screens twice. That pressure is expected and is answered by ADR-039, not here.

## Sources

Code measured 2026-09-23/24 in `front_vibes` @ `1cf858e`: `src/services/player-engine.service.ts` (188 lines, pure), `src/services/audio-player.service.ts` (1.887), `src/services/audio-engine/*` (903), `src/utils/{canonical-capabilities,canonical-contract,device-action,device-status}.ts` (618), `src/stores/player.store.ts` (623), `src/theme/variables.css`, `android/app/src/main/java/app/ixora/googlehome/*.kt` (493). Boundary-test precedent: `back_vibes/tests/Unit/SmartHome/Canonical/CanonicalBoundaryTest.php`, `back_vibes/tests/Unit/SmartHome/ProviderExtensibilityBoundaryTest.php`.

Internal: [`kmp-migration-plan.md`](../architecture/mobile/kmp-migration-plan.md) (§0 decisions, §2 inventory, §3 matrix, §5 modules, §16 cross-cutting requirements), [ADR-007](ADR-007-execution-plan-runtime-contract.md), [ADR-008](ADR-008-nativeaudio-limitations-over-unstable-dsp.md), [ADR-036](ADR-036-google-home-execution-model.md), [ADR-037](ADR-037-canonical-smart-home-device-model.md), [`contracts/README.md`](../../contracts/README.md).
