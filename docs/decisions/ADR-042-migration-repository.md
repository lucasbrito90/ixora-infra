# ADR-042: Migration strategy and repository responsibilities for the KMP rebuild

## Status

**Accepted** (2026-09-23) — governs how the mobile layer moves from Ionic/Capacitor to Kotlin Multiplatform, and which repository owns what while that transition is in flight.

**Approved by the PO on 2026-09-23**, confirming decisions D1, D2, D3 and D5 recorded in [`kmp-migration-plan.md`](../architecture/mobile/kmp-migration-plan.md) §0: the destination repository, the feature freeze, the absence of local-data migration, and Android-first with iOS architecturally prepared.

Adds a **fifth repository** to the ecosystem and therefore amends [`repo-responsibilities.md`](../architecture/repo-responsibilities.md), [`architecture-map.md`](../architecture/architecture-map.md) and the workspace `CLAUDE.md`, which described four.

[ADR-038](ADR-038-kmp-shared-layer.md) (shared layer) and [ADR-039](ADR-039-native-ui.md) (native UI) remain **binding** and are not reopened here. ADR-040 (player, card K05) and ADR-041 (state and Swift interop, K06) are referenced by number; they are not written yet. This ADR decides **where work happens and in what order** — not how the player, the state contract or the UI are built.

## Date

2026-09-23

---

## 1. Problem

ADR-038 and ADR-039 settled the target architecture. Neither answers the operational questions that must be settled before a single line is written:

1. **Where does the new application live** — inside `front_vibes`, replacing it in place, or in a repository of its own?
2. **What happens to `front_vibes`** during a rebuild measured in months, and what happens to it afterwards?
3. **How does a solo developer avoid the dominant failure mode** of a long rewrite: abandonment halfway, leaving one application frozen and the other incomplete?
4. **What is explicitly out of scope**, so that "while we are rewriting it anyway" does not silently expand into a redesign.

The ecosystem documentation currently describes four repositories and names `front_vibes` as the mobile runtime. That will be wrong in stages, and stale documentation about ownership is precisely what `repo-responsibilities.md` exists to prevent.

## 2. Context

### 2.1 What is being replaced, measured

Counted in `front_vibes` @ `1cf858e`: 27.590 lines in `src/`, of which ~13.640 are Vue UI, ~2.849 are the audio runtime, and ~3.900 are platform-free logic that migrates to `commonMain` almost unchanged. The shared module will hold roughly 15% of today's code — a consequence of choosing native UI (ADR-039), not a defect.

### 2.2 The destination repository already exists

`git@github.com:lucasbrito90/ixora-app.git` was created on 2026-09-23. It is private and **empty** — no commits, no branches, no lists of files. Nothing in this ADR has been started.

### 2.3 Deployment reality

`front_vibes` is the only repository not deployed by DigitalOcean App Platform: it ships through `npm run build:staging` → Capacitor → device or store pipeline. `ixora-app` inherits that property — a Gradle/Android build pipeline, not an App Platform service. This matters because it means the new repository introduces **no infrastructure change** in `ixora-infra`, and no `tofu apply`.

### 2.4 The constraint that shapes everything

One developer, working with an AI coding assistant, on a project that has no deadline. The dominant risk is not technical difficulty — it is a rewrite that stalls at 60%.

## 3. Alternatives considered

| Option | What it means | Assessment |
| --- | --- | --- |
| **A. Rebuild in place, inside `front_vibes`** | Add the KMP module and Compose screens to the existing Capacitor Android project, replacing the WebView screen by screen (*strangler*) | Technically viable — a Capacitor app is an ordinary Gradle project, and the repository already contains native Kotlin. Rejected: the npm/Vite root and the Gradle root conflict, the Capacitor-generated `android/` collides with `androidApp/`, and the repository would carry two stacks for months. |
| **B. Parallel rebuild in a new repository** | `ixora-app` is built alongside a frozen `front_vibes` | **Chosen.** See Decision 1. |
| **C. Hybrid — prove the core in place, then move** | Phases 1–2 inside `front_vibes`, remainder in the new repository | This was the migration plan's original recommendation, and its **only** argument was avoiding a long period without shipping. The feature freeze (Decision 2) removes that argument entirely: with `front_vibes` frozen and publishable as-is, there is no delivery pressure to protect, and the cost of maintaining two stacks in one APK stops paying for itself. |

Recording C's rejection matters: it was the earlier recommendation, and it was overturned by a decision made afterwards, not by an error in the original reasoning.

---

## Decision

### Decision 1 — `ixora-app` is the destination; the rebuild is parallel

The KMP mobile application is developed in **`git@github.com:lucasbrito90/ixora-app.git`**. `front_vibes` is not converted in place.

```
front_vibes (feature-frozen)
        │
        │  behaviour and contracts preserved; no code carried over except
        │  the Google Home Kotlin plugin and the platform-free logic, ported
        ▼
ixora-app (KMP)
        │
        ├── shared/      Kotlin Multiplatform — ADR-038
        ├── androidApp/  Jetpack Compose — ADR-039, built and validated now
        └── iosApp/      SwiftUI — ADR-039, structure only, not built
```

The ecosystem grows from four repositories to five. `ixora-app` follows the same Git Flow as every other repository ([git-flow](../standards/git-flow.md)): `main`, `develop`, `staging`, and branches that are never deleted.

### Decision 2 — `front_vibes` is feature-frozen, and remains the shipping app until cutover

For the entire duration of the migration:

- **No new features** enter `front_vibes`. The objective is to reproduce existing behaviour, not to evolve the product while copying it.
- Changes are limited to what is necessary for the native/KMP architecture or to recover existing functionality. Anything that looks like new functional scope is out of scope for the migration and needs its own PO decision.
- `front_vibes` remains the **real, installable application** until the cutover of Decision 6. It is a reference for behaviour, not a museum piece.
- It is **never deleted**, consistent with the project's standing practice of preserving history.

### Decision 3 — The other four repositories are unaffected

Stated explicitly so the migration is not read as an ecosystem-wide event:

- **`back_vibes`** remains the authoritative Laravel API — business logic, persistence, authorization, sole Spaces writer, async jobs. It is **not** part of the KMP migration. Its API contract does not change because of it; a mobile rewrite that needed a backend change would be a redesign, not a migration.
- **`ixora-admin`** remains the Nuxt admin panel, unchanged and untouched.
- **`ixora-infra`** remains infrastructure plus the canonical documentation and decision tree, under its existing structure. `ixora-app` adds **no** infrastructure: it is not an App Platform service (§2.3).
- **`qa`** remains the evidence and probe-script tree. Its WebView-based WDIO specs do not survive the migration and will need native selectors — recorded as risk 5 in the plan, not resolved here.

### Decision 4 — No migration of local application data

Offline audio, playback cache and the SQLite schedules mirror are **not** migrated from `front_vibes` to `ixora-app`. They are reconstructed by download and synchronization on first use of the new application.

No local-database migration mechanism is implemented without an explicit, demonstrated need. The backend remains the source of truth, which is what makes this safe: nothing unique to the device is lost.

This deliberately reduces migration scope.

### Decision 5 — Android first; iOS prepared, not built

- **Android** is the platform implemented and validated during the current phase (cards K01–K12 and beyond).
- **iOS** is architecturally prepared: targets declared in Gradle, `iosApp/UI` structure defined by ADR-039, `commonMain` kept free of Android-only APIs and enforced by the boundary test of ADR-038 Decision 5.
- **SwiftUI implementation waits for a Mac and Xcode**, which do not exist yet and have no date.
- The absence of that environment **must not block Android work**, and must not be used as an argument to abandon the KMP architecture.

The residual risk is stated plainly: without a Mac, iOS compatibility is reasoned and scanned, never compiled. The first real iOS build is expected to surface problems in series.

### Decision 6 — Cutover criteria

`ixora-app` replaces `front_vibes` as the distributed application only when:

1. Functional parity is verified **area by area** against the frozen `front_vibes`, on a real device.
2. The application ships with `applicationId` **`app.ixora.ixora`** and the **same signing key**. Without both, the new build does not update existing installations and appears in the store as a different application.
3. `front_vibes` is marked archived/reference in its own documentation — and not deleted.

Until all three hold, `front_vibes` remains the shipping application.

### Decision 7 — Installability is a phase gate, not a milestone

Because the parallel strategy removes the strangler's natural protection against abandonment (§3, option C), one mitigation is **mandatory**:

> `ixora-app` must be installable and demonstrable on a real device from the plan's **Phase 5 (installable shell)** onward. Every phase after that ends with something running on the phone — not with a green test suite alone.

This is a decision, not advice. A phase that ends with passing tests and nothing installable has not ended.

### Decision 8 — Migration, not redesign

```
Migration ≠ Redesign
```

The migration is an **architectural replacement** that preserves behaviour, contracts and existing user experience. It is not an opportunity to change the product.

Concretely, and consistent with ADR-039 Decision 8: the existing visual language is parity; `system`/`light`/`dark` theming is parity; the existing component set is parity. New features, new screens and a new visual experience each require their own PO decision and are outside this migration.

### Decision 9 — Documentation that this ADR amends

The following are updated in the same change set as this ADR, because ownership documentation that lags reality is the specific failure `repo-responsibilities.md` exists to prevent:

| Document | Amendment |
| --- | --- |
| [`repo-responsibilities.md`](../architecture/repo-responsibilities.md) | `ixora-app` added as the fifth repository, with its boundaries; `front_vibes` marked feature-frozen with its transition status |
| [`architecture-map.md`](../architecture/architecture-map.md) | `ixora-app` added to the component overview with its current status |
| Workspace `CLAUDE.md` | Fifth repository and the feature freeze recorded |
| [`contracts/README.md`](../../contracts/README.md) | `ixora-app` listed as a **planned** consumer of `capability.v1.schema.json` — not a vendored one, because it has no code yet |

Both maps continue to describe `front_vibes` as the mobile runtime, because **that is still true today**. Rewriting them as though `ixora-app` were the shipping application would make the documentation wrong in the opposite direction. They are updated again at cutover (Decision 6).

---

## 4. Consequences

**Positive**

- The new application starts with a clean Gradle root, free of Capacitor's generated layout and of npm/Vite tooling conflicts.
- The feature freeze removes the delivery pressure that would otherwise push the rebuild toward shortcuts.
- Dropping local-data migration (Decision 4) removes an entire class of work and an entire class of bugs.
- `front_vibes` stays installable and intact throughout, so behavioural questions always have an authoritative answer available on a device.

**Negative, accepted**

- **The player improvement arrives later.** Under the strangler, a native player could have shipped inside the existing app early. With the parallel rebuild it arrives only when `ixora-app` is installable. This was weighed and accepted.
- The workspace grows to five repositories, each with its own Git Flow and its own quality gates.
- Users reinstalling or updating will re-download their offline audio once.

**Risks**

- **Abandonment mid-rebuild** — the dominant risk, leaving `front_vibes` frozen and `ixora-app` incomplete. Mitigated by Decision 7, and only by Decision 7.
- **The freeze becomes a bottleneck** if something genuinely urgent needs to reach users during a long migration. Decision 2 allows changes needed to recover existing functionality; anything beyond that is a PO call, taken explicitly.
- **iOS surprises at first compilation** — accepted under Decision 5.
- **Cutover blocked by signing** — if the original signing key were unavailable, the new application could not update existing installations. Decision 6 makes this a gate rather than a discovery.

## 5. Relationship to other ADRs

- **[ADR-038](ADR-038-kmp-shared-layer.md)** is the authority on what belongs to the shared layer. This ADR does not classify responsibilities; it decides where and in what order the work happens.
- **[ADR-039](ADR-039-native-ui.md)** is the authority on how the UI is implemented. Decision 8's parity rule is the migration-strategy expression of ADR-039 Decision 8.
- **ADR-040 (player, K05)** and **ADR-041 (state and Swift interop, K06)** are not affected by this ADR and are not anticipated by it.
- **[ADR-036](ADR-036-google-home-execution-model.md)** is reaffirmed: Google Home stays Android-only and device-side, and its existing Kotlin plugin is the one piece of `front_vibes` that migrates essentially intact.
- **[ADR-007](ADR-007-execution-plan-runtime-contract.md)** is reaffirmed: playback stays device-side and the backend gains no playback engine. Its reference to the TypeScript implementation needs an addendum at cutover, not before.

## Sources

Repository state verified 2026-09-23: `ixora-app` exists, is private, and has no commits (`gh repo view lucasbrito90/ixora-app`); `front_vibes` @ `develop` `1cf858e` with a clean working tree; five repositories present in the workspace. Code measured in `front_vibes` @ `1cf858e` as recorded in [`kmp-migration-plan.md`](../architecture/mobile/kmp-migration-plan.md) §2.

Internal: [`kmp-migration-plan.md`](../architecture/mobile/kmp-migration-plan.md) (§0 decisions D1–D5, §5.3 repository options, §11 migration strategy, §14 risks), [ADR-038](ADR-038-kmp-shared-layer.md), [ADR-039](ADR-039-native-ui.md), [ADR-007](ADR-007-execution-plan-runtime-contract.md), [ADR-036](ADR-036-google-home-execution-model.md), [`repo-responsibilities.md`](../architecture/repo-responsibilities.md), [`architecture-map.md`](../architecture/architecture-map.md), [`git-flow.md`](../standards/git-flow.md).
