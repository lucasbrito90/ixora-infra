# ADR-039: Native UI — Jetpack Compose and SwiftUI, with a shared design language

## Status

**Accepted** (2026-09-23) — governs how the Ixora mobile UI is implemented on each platform, and how the existing design language is preserved across that boundary.

**Approved by the PO on 2026-09-23**, confirming the direction recorded in [`kmp-migration-plan.md`](../architecture/mobile/kmp-migration-plan.md) §0 (decision D5) and §16.14, and accepting the cost quantified in §4: the user interface is written twice, once per platform.

Builds on [ADR-038](ADR-038-kmp-shared-layer.md), which is the **authority** on what belongs to the shared layer. This ADR does not re-decide that boundary — it decides what happens on the platform side of it. ADR-040 (player, card K05), ADR-041 (state and Swift interop, K06) and ADR-042 (migration strategy, K04) are referenced by number; they are not written yet.

## Date

2026-09-23

---

## 1. Problem

The mobile rebuild replaces a single WebView-rendered UI (Ionic 8 + Vue 3, 13.640 lines across `views/` and `components/`) with native user interfaces. Three questions follow, and none of them is answered by ADR-038:

1. **Which UI technology on each platform**, and whether a cross-platform UI toolkit should be used at all.
2. **What stops Android and iOS from drifting into two different products** once their interfaces are written independently — the same screen, built twice, by the same person, months apart.
3. **What happens to the design system that already exists**, since the Ixora visual language is not a blank page: it is implemented in CSS tokens today and originates in Figma.

Left unanswered, the predictable outcome is two applications that share a backend and a name but not an identity, with accessibility and visual decisions re-litigated screen by screen.

## 2. Context

### 2.1 What the migration is, and is not

The migration preserves existing behaviour and experience. The `front_vibes` application is in feature freeze for its duration (plan §0, D2). The rule that governs this ADR throughout:

```
Migration ≠ Redesign
```

Reproducing the existing visual system is **parity**. Creating a new visual experience is a product change, requires its own PO decision, and is outside the migration's scope.

### 2.2 The design system already exists

Verified in `front_vibes` @ `1cf858e`. This is not a system to be invented; it is a system to be carried across:

| Category | What exists today |
| --- | --- |
| Origin | `variables.css:3` — *"Ionic design tokens mapped from Figma Design System (node 127:2)"* |
| Semantic colours | `--app-color-bg`, `surface`, `surface-subtle`, `border`, `text-primary/secondary/muted` |
| Colour scales | `primary-100…600`, `secondary-100…500`; brand primary `#1dac92` |
| Typography | `h1…h6` (48→18px), `body-lg/md/sm/xs` (16→10px), three line heights, three weights |
| Spacing | `--app-space-1…11` (4px → 60px) |
| Radius | `sm 8px`, `md 12px`, `lg 20px` |
| Elevation | `--app-shadow-card`, `--app-shadow-soft`, with distinct dark values |
| Motion | `fast 140ms`, `base 240ms`, `slow 360ms`, two easing curves, 48ms stagger, `prefers-reduced-motion` honoured |
| Theme | `system` / `light` / `dark`, persisted, applied via `ion-palette-dark` |
| Components | `AppEmptyState`, `AppErrorState`, `AppLoadingState`, `AppAutomationBadge`, `MiniPlayer`, `CoverBundlePickerModal` |

Light, dark and system theming is therefore **parity**, not a new feature.

### 2.3 Accessibility today

Measured, and stated here as context for the architecture rather than as a defect list to fix in this ADR: 24 `aria-label`, 18 `role`, 33 `aria-hidden`, four declarations of a minimum touch target (44/48px), and **one** `:focus` rule in the entire application.

Focus states and minimum touch targets are effectively absent. That fact shapes **where** accessibility should live in the new architecture (Decision 5); it does not authorize a redesign now.

### 2.4 iOS is architecturally present, not physically buildable

There is no Mac. iOS targets are declared and `iosApp/` exists as a skeleton, but nothing SwiftUI is built or validated during the current phase (plan §0, D5).

## 3. Alternatives considered

| Option | What it means | Assessment |
| --- | --- | --- |
| **A. Compose Multiplatform** | One Compose UI rendered on both Android and iOS | Would make the UI genuinely shared. Rejected by the PO: iOS would render a Compose approximation of native rather than SwiftUI, which contradicts the reason for leaving the WebView in the first place. The project is replacing one cross-platform rendering layer; adopting another would relocate the problem, not solve it. |
| **B. Fully independent UIs, no shared language** | Each platform designs its own screens | Cheapest per screen, most expensive as a product. Produces two applications that diverge visually and in accessibility, with no mechanism to converge them. |
| **C. Native UI with a shared design language** | Compose and SwiftUI implement the same tokens, principles and component rules | **Chosen.** Keeps each platform genuinely native while giving the product one visual identity, enforced by a common language rather than by common code. |
| **D. A `design-system` KMP module** | Tokens as Kotlin code in a shared Gradle module | Deferred, not rejected outright. No measured need today: tokens are consumed by UI code, which is native on both sides, so a shared module would carry values across a boundary nothing else crosses. See Decision 4. |

---

## Decision

### Decision 1 — Native UI per platform; no Compose Multiplatform

```
KMP Shared
    │
    ├── Android → Jetpack Compose
    │
    └── iOS     → SwiftUI
```

**Compose Multiplatform is not used**, now or as a later convenience. Neither is any other cross-platform UI toolkit.

The shared layer supplies logic, state, contracts and behaviour exactly as ADR-038 defines. It does not supply the user interface, and no intermediate visual layer is introduced between the shared module and the native UIs.

### Decision 2 — Same design language, native UI implementations

The governing rule:

> **Same design language, native UI implementations.**

Shared **as concept** — one definition, applied by both platforms: design tokens (colour, typography, spacing, dimensions, radius, elevation, motion), visual states, component rules, accessibility principles, naming conventions, general interaction rules and the Ixora design language itself.

Shared **as code** — nothing. The design language is documentation and tokens, not a module.

This is the specific sense in which the UI is "not shared": the platforms share what the product should look like and how it should behave, and share no implementation of it.

### Decision 3 — Platform structure

Android, implemented in the current phase:

```
androidApp/ui/
    theme/          Colors.kt · Typography.kt · Dimensions.kt · IxoraTheme.kt
    components/
    screens/
```

iOS, **not implemented in this phase**:

```
iosApp/UI/
    Theme/          Colors.swift · Typography.swift · Dimensions.swift · IxoraTheme.swift
    Components/
    Screens/
```

The symmetry is deliberate and is itself a decision: it guarantees that the future SwiftUI implementation has a defined place for each concern without renegotiating the architecture. Any Android UI decision that could not be expressed in the iOS structure above is, by that fact, the wrong decision.

### Decision 4 — Design tokens: preserve, consolidate, never round

Tokens are ported from `variables.css` and `motion.css` into a Compose `IxoraTheme`, and later into a SwiftUI equivalent. Figma remains the visual reference and origin. **No automatic Figma → code synchronization infrastructure is built**; if that is ever justified, it will be by volume of visual change, not by elegance.

The existing token system coexists with literal values that duplicate it: `border-radius: 12px` appears 14 times while `--app-radius-md` is exactly 12px; `font-size: 18px` appears 21 times while `--app-font-size-h6` is 18px. The porting rule:

1. A literal that **exactly matches** an existing token → use the token. Same pixel, name recovered. This is consolidation.
2. A literal with **no** matching token → preserve the literal value and record the divergence. Do not invent a token for it, and **do not round it to the nearest token**.

Rounding changes a pixel, and changing a pixel is redesign. No consolidation may alter rendered output.

**No `design-system` KMP module is created.** Creating one later requires a measured, documented technical need — a value the shared domain itself must know, or a second consumer outside `ixora-app`. Symmetry with other projects is not a reason. This is the same discipline ADR-038 Decision 4 applies to splitting the `shared` module.

### Decision 5 — Accessibility is a Design System responsibility

Accessibility is built into the Design System's components, not applied as repeated per-screen corrections. A component that is accessible by construction resolves the concern for every screen that uses it; a screen-by-screen approach guarantees the opposite.

In scope where applicable: focus states, minimum touch targets, semantic labels, disabled states, scalable typography (Dynamic Type on iOS), contrast, and support for native assistive technologies — TalkBack on Android, VoiceOver on iOS.

Two boundaries on this decision:

- It establishes **architectural responsibility**, not an implementation task. Nothing is implemented by this ADR.
- The gaps measured in §2.3 are **context for how the new components are built**, not authorization to change the current application or to redesign anything.

Practical consequence for the migration: "accessibility verified" belongs in the completion criteria of each UI area, not in a separate remediation card at the end.

### Decision 6 — Prohibited abstractions

The following must not be created in the shared module, in any form:

```
SharedButton      SharedTextField      SharedCard
SharedNavigationBar   SharedScreen     SharedPlayerView
```

Nor any other cross-platform UI abstraction, nor a visual layer sitting between the shared module and the native UIs, nor Compose Multiplatform, nor a `design-system` module without the measured need of Decision 4.

These are listed explicitly because each is individually reasonable-sounding and collectively fatal to Decision 1. Ixora has already paid for a cross-platform abstraction that became a ceiling: `@capgo/native-audio` cost the product its runtime fades ([ADR-008](ADR-008-nativeaudio-limitations-over-unstable-dsp.md)).

### Decision 7 — Android first; iOS prepared, not built

- Android is the platform **implemented and validated** during the current phase.
- iOS is **architecturally prepared** — targets declared, structure defined (Decision 3), design language applicable — and **not implemented**.
- SwiftUI work is not authorized by this ADR.
- The absence of a Mac and Xcode must not block Android development.
- No UI decision may foreclose the future SwiftUI implementation. Decision 3's symmetry is the mechanism that keeps this checkable.

### Decision 8 — Feature freeze applies to the UI

Adopting native UI is not authorization for new features, new screens, or a new visual experience. The objective is to migrate the implementation while preserving existing behaviour and experience.

Concretely: `system`/`light`/`dark` theming is parity; the existing component set is parity; the existing token values are parity. Anything beyond reproduction is a product change and needs its own decision.

---

## 4. Consequences

**Positive**

- Each platform keeps a genuinely native feel, which is the reason the WebView is being left behind.
- The product keeps one visual identity across platforms, held by a shared language rather than shared code.
- Accessibility gains a single structural home instead of being distributed across 28 screens.
- The existing design system — already Figma-derived and coherent — survives the migration instead of being reinvented.

**Negative, accepted**

- **The UI is written twice.** Roughly 13.640 lines of Vue become a Compose implementation now and a SwiftUI implementation later. This is the direct, quantified cost of Decision 1, accepted by the PO.
- Visual consistency depends on discipline and review, not on a compiler. Two implementations of one language can drift, and nothing mechanical prevents it.
- Token consolidation (Decision 4) is careful, tedious work with no visible outcome when done correctly — its success looks exactly like doing nothing.

**Risks**

- **Pressure to share the UI later**, to avoid writing screens twice when iOS begins. Decision 1 and Decision 6 exist to make that a decision that must be argued and reversed explicitly, not one that happens by convenience.
- **Silent redesign during the port.** A developer rounding 13px to the 12px token, or "improving" a layout while translating it, produces drift that no test catches. Decision 4's rule 2 and Decision 8 are the mitigation; review is the enforcement.
- **iOS structure unverified.** Decision 3's symmetry is reasoned, not compiled. Like the rest of the iOS preparation, it carries residual risk until a Mac exists.

## 5. Relationship to other ADRs

- **[ADR-038](ADR-038-kmp-shared-layer.md) is the authority on the shared boundary.** Its responsibility matrix determines what belongs to `shared`; this ADR governs only the platform side. Where a question is "does this belong in shared?", ADR-038 answers it. Where it is "how is this rendered?", this one does. The matrix already places UI, theme, components, screens and navigation on the platforms, and design language as a shared *concept* rather than shared code — this ADR implements that, and does not restate the matrix.
- **ADR-041 (state and Swift interop, K06)** will define how the native UIs consume shared state. This ADR assumes only that presentation state arrives from the shared layer and that the UI renders it; the mechanism is that ADR's subject.
- **ADR-040 (player, K05)** owns the player's architecture. Player UI is native under this ADR; the playback decision layer is shared under ADR-038.
- **ADR-042 (migration strategy, K04)** owns the phasing. UI areas are migrated during Phase 6 of the plan.
- **[ADR-008](ADR-008-nativeaudio-limitations-over-unstable-dsp.md)** is cited here only as evidence for Decision 6. Its fade prohibition is reopened by ADR-040, not by this ADR.
- **[`user-experience-principles.md`](../architecture/user-experience-principles.md)** remains valid and complementary: it defines architectural UX principles for screen states and copy, explicitly not a design system or component catalogue. This ADR does not replace it.

## Sources

Code measured 2026-09-23 in `front_vibes` @ `1cf858e`: `src/theme/variables.css` (tokens, dark palette, Figma origin at line 3), `src/theme/motion.css` (motion tokens, `prefers-reduced-motion`), `src/theme/theme.css`, `src/composables/useThemeMode.ts` (`system`/`light`/`dark`, `ion-palette-dark`), `src/views/SettingsPage.vue:126` (theme selector), `src/components/ui/{AppEmptyState,AppErrorState,AppLoadingState,AppAutomationBadge}.vue`, `src/components/MiniPlayer.vue`; UI line counts across `src/views/` (28 files) and `src/components/` (7 files); accessibility and token-drift counts by repository-wide scan.

Internal: [`kmp-migration-plan.md`](../architecture/mobile/kmp-migration-plan.md) (§0 decisions, §2 inventory, §3 matrix, §5.2 structure, §16.10 accessibility, §16.14 Design System), [ADR-038](ADR-038-kmp-shared-layer.md), [ADR-008](ADR-008-nativeaudio-limitations-over-unstable-dsp.md), [`user-experience-principles.md`](../architecture/user-experience-principles.md).
