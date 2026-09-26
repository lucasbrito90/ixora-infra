# ADR-042: Migration strategy and repository responsibilities for the KMP rebuild

## Status

**Accepted** (2026-09-23) — governs how the mobile layer moves from Ionic/Capacitor to Kotlin Multiplatform, and which repository owns what while that transition is in flight.

**Approved by the PO on 2026-09-23**, confirming decisions D1, D2, D3 and D5 recorded in [`kmp-migration-plan.md`](../architecture/mobile/kmp-migration-plan.md) §0: the destination repository, the feature freeze, the absence of local-data migration, and Android-first with iOS architecturally prepared.

**Post-acceptance factual and operational addendum (2026-09-23).** A technical audit after acceptance found seven factual or terminological inaccuracies — all of them about the *state of the project*, none about the decisions themselves — and surfaced one operational gap: the migration assumed a release signing key that does not exist. The corrections are applied in place and marked where they matter; the release-keystore requirement is folded into the existing cutover criteria (Decision 6) as an **operational prerequisite**. **No architectural decision was reopened or changed, and the status remains Accepted.**

Adds a **fifth Git repository** to the ecosystem and therefore amends [`repo-responsibilities.md`](../architecture/repo-responsibilities.md), [`architecture-map.md`](../architecture/architecture-map.md) and the workspace `CLAUDE.md`, which described four.

[ADR-038](ADR-038-kmp-shared-layer.md) (shared layer) and [ADR-039](ADR-039-native-ui.md) (native UI) remain **binding** and are not reopened here. [ADR-041](ADR-041-state-swift-interop.md) (state and Swift interop, card K06) was written and accepted on 2026-09-23 and is likewise binding; ADR-040 (player, card K05) is referenced by number and is not written yet. This ADR decides **where work happens and in what order** — not how the player, the state contract or the UI are built.

## Date

2026-09-23

---

## 1. Problem

ADR-038 and ADR-039 settled the target architecture. Neither answers the operational questions that must be settled before a single line is written:

1. **Where does the new application live** — inside `front_vibes`, replacing it in place, or in a repository of its own?
2. **What happens to `front_vibes`** during a rebuild measured in months, and what happens to it afterwards?
3. **How does a solo developer avoid the dominant failure mode** of a long rewrite: abandonment halfway, leaving one application frozen and the other incomplete?
4. **What is explicitly out of scope**, so that "while we are rewriting it anyway" does not silently expand into a redesign.

At the time of writing, the ecosystem documentation described four Git repositories and named `front_vibes` as the mobile runtime. That would become wrong in stages, and stale documentation about ownership is precisely what `repo-responsibilities.md` exists to prevent — which is why Decision 9 amends those documents in the same change set.

## 2. Context

### 2.1 What is being replaced, measured

Counted in `front_vibes` @ `1cf858e`: 27.590 lines in `src/`, of which ~13.640 are Vue UI, ~2.849 are the audio runtime, and ~3.900 are platform-free logic that migrates to `commonMain` almost unchanged. The shared module will hold roughly 15% of today's code — a consequence of choosing native UI (ADR-039), not a defect.

### 2.2 The destination repository already exists

`git@github.com:lucasbrito90/ixora-app.git` was created on 2026-09-23. It is private and **empty** — no commits, no branches, no files. Nothing in this ADR has been started.

### 2.3 Deployment reality

Only two repositories are deployed by DigitalOcean App Platform: `back_vibes` (API and queue worker) and `ixora-admin` (static site). `ixora-infra` is applied by an operator through `tofu apply`, which is infrastructure provisioning rather than an App Platform deploy, and the QA workspace is not deployed at all. `front_vibes` ships through `npm run build:staging` → Capacitor → device or store pipeline.

`ixora-app` inherits that last property — a Gradle/Android build pipeline, not an App Platform service. **`ixora-app` therefore adds no infrastructure to the existing deployment model**: no App Platform component, no `tofu apply`, no change in `ixora-infra`.

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

The ecosystem grows from four Git repositories to five — `back_vibes`, `front_vibes`, `ixora-app`, `ixora-admin`, `ixora-infra`. The QA workspace is a codebase of evidence and probe scripts, not a Git repository, and is not counted here. `ixora-app` follows the same Git Flow as every other repository ([git-flow](../standards/git-flow.md)): `main`, `develop`, `staging`, and branches that are never deleted.

### Decision 2 — `front_vibes` is feature-frozen, and remains the shipping app until cutover

For the entire duration of the migration:

- **No new features** enter `front_vibes`. The objective is to reproduce existing behaviour, not to evolve the product while copying it.
- Changes are limited to what is necessary for the native/KMP architecture or to recover existing functionality. Anything that looks like new functional scope is out of scope for the migration and needs its own PO decision.
- `front_vibes` remains the **real, installable application** until the cutover of Decision 6. It is a reference for behaviour, not a museum piece.
- It is **never deleted**, consistent with the project's standing practice of preserving history.

### Decision 3 — The rest of the ecosystem is unaffected

Stated explicitly so the migration is not read as an ecosystem-wide event:

- **`back_vibes`** remains the authoritative Laravel API — business logic, persistence, authorization, sole Spaces writer, async jobs. It is **not** part of the KMP migration. Its API contract does not change because of it; a mobile rewrite that needed a backend change would be a redesign, not a migration.
- **`ixora-admin`** remains the Nuxt admin panel, unchanged and untouched.
- **`ixora-infra`** remains infrastructure plus the canonical documentation and decision tree, under its existing structure. `ixora-app` adds **no** infrastructure: it is not an App Platform service (§2.3).
- The **QA workspace** (`qa/`) remains the evidence and probe-script tree. It is a workspace component, not a Git repository. Its WebView-based WDIO specs do not survive the migration and will need native selectors — recorded as risk 5 in the plan, not resolved here.

### Decision 4 — No migration of local application data

Offline audio, playback cache and the SQLite schedules mirror are **not** migrated from `front_vibes` to `ixora-app`. They are reconstructed by download and synchronization on first use of the new application.

No local-database migration mechanism is implemented without an explicit, demonstrated need. The backend remains the source of truth, which is what makes this safe: nothing unique to the device is lost.

This deliberately reduces migration scope.

### Decision 5 — Android first; iOS prepared, not built

- **Android** is the platform implemented and validated during the current phase (cards K01–K12 and beyond).
- **iOS** is the architectural target of the KMP project, not yet a declared one: `ixora-app` is still empty, so no Gradle targets exist today. The preparation that this ADR commits to is that, when the project is created, the iOS targets **will be** declared, the `iosApp/UI` structure follows ADR-039, and `commonMain` is kept free of Android-only APIs under the boundary test of ADR-038 Decision 5. Implementation follows the Android-first phase, when a Mac/Xcode environment exists.
- **SwiftUI implementation waits for a Mac and Xcode**, which do not exist yet and have no date.
- The absence of that environment **must not block Android work**, and must not be used as an argument to abandon the KMP architecture.

The residual risk is stated plainly: without a Mac, iOS compatibility is reasoned and scanned, never compiled. The first real iOS build is expected to surface problems in series.

### Decision 6 — Cutover criteria

`ixora-app` replaces `front_vibes` as the distributed application only when all of the following hold:

1. Functional parity is verified **area by area** against the frozen `front_vibes`, on a real device.
2. The **release signing prerequisites** below are satisfied.
3. `front_vibes` is marked archived/reference in its own documentation — and not deleted.

Until all three hold, `front_vibes` remains the shipping application.

#### Release signing — an operational prerequisite

*Added by the post-acceptance addendum. This is an operational gate, not a change to the migration decision.*

The audit found that `front_vibes/android/app/build.gradle` declares **no `signingConfigs` and no `storeFile`**, and that no keystore file exists in the repository. The platform has never been published, so there is **no existing release key to preserve and no production installation to update**. An earlier wording of this decision assumed both; that assumption was wrong and is corrected here.

What remains true is the forward-looking requirement. Android identifies an application by `applicationId` **plus** signing key: once a build is published, any later build that changes either is treated as a different application and cannot update the installed one. The key therefore has to be created deliberately, before the first published build, and kept for the lifetime of the application.

```
Create release keystore
        ↓
Store it securely outside Git
        ↓
Configure signing for ixora-app
        ↓
Validate a signed release build
        ↓
Cutover
```

**The cutover must not proceed until:**

1. a release keystore exists;
2. the keystore is stored securely **outside Git**;
3. a backup and recovery procedure for it exists and has been checked;
4. `ixora-app` builds with the intended `applicationId` — **`app.ixora.ixora`**, preserved from `front_vibes` as the Android identity of the product;
5. release signing is configured in the build;
6. a signed release build has been produced and validated.

Constraints on how this is done:

- The keystore is **never** committed, never placed in any repository, and never included in documentation.
- Its passwords and credentials do not appear in this ADR or in any other document in this tree.
- Where it is stored is an operational choice, deliberately left open here — this ADR records the requirement, not the tool.
- Losing the keystore after publication is unrecoverable: the application can never be updated again under the same identity. That is why item 3 is a gate and not a recommendation.

**Creating the keystore is a separate operational task.** No keystore is created by this ADR.

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
- The workspace grows to five Git repositories, each with its own Git Flow and its own quality gates.
- Users reinstalling or updating will re-download their offline audio once.

**Risks**

- **Abandonment mid-rebuild** — the dominant risk, leaving `front_vibes` frozen and `ixora-app` incomplete. Mitigated by Decision 7, and only by Decision 7.
- **The freeze becomes a bottleneck** if something genuinely urgent needs to reach users during a long migration. Decision 2 allows changes needed to recover existing functionality; anything beyond that is a PO call, taken explicitly.
- **iOS surprises at first compilation** — accepted under Decision 5.
- **Signing key lost after publication** — unrecoverable: the application could never be updated under the same identity again. There is no key today and nothing published, so this is a future risk created by the first release, not a present one. Decision 6 turns it into a gate — keystore, secure storage and verified recovery — rather than something discovered later.

## 5. Relationship to other ADRs

- **[ADR-038](ADR-038-kmp-shared-layer.md)** is the authority on what belongs to the shared layer. This ADR does not classify responsibilities; it decides where and in what order the work happens.
- **[ADR-039](ADR-039-native-ui.md)** is the authority on how the UI is implemented. Decision 8's parity rule is the migration-strategy expression of ADR-039 Decision 8.
- **ADR-040 (player, K05)**, not yet written, and **[ADR-041](ADR-041-state-swift-interop.md)** (state and Swift interop, K06), accepted on 2026-09-23, are not affected by this ADR and are not anticipated by it.
- **[ADR-036](ADR-036-google-home-execution-model.md)** is reaffirmed: Google Home stays Android-only and device-side, and its existing Kotlin plugin is the one piece of `front_vibes` that migrates essentially intact.
- **[ADR-007](ADR-007-execution-plan-runtime-contract.md)** is reaffirmed: playback stays device-side and the backend gains no playback engine. Its reference to the TypeScript implementation needs an addendum at cutover, not before.

## Sources

Repository state verified 2026-09-23: `ixora-app` exists on GitHub, is private, and has no commits (`gh repo view lucasbrito90/ixora-app`) — it is **not cloned into the local workspace** at this date; `front_vibes` @ `develop` `1cf858e` with a clean working tree. The local workspace holds five codebases — the Git repositories `back_vibes`, `front_vibes`, `ixora-admin` and `ixora-infra`, plus the `qa` workspace component, which is not a Git repository. Android signing state verified in `front_vibes/android/app/build.gradle`: `applicationId app.ixora.ixora`, and **no `signingConfigs`, no `storeFile` and no keystore file anywhere in the repository**. Code measured in `front_vibes` @ `1cf858e` as recorded in [`kmp-migration-plan.md`](../architecture/mobile/kmp-migration-plan.md) §2.

Internal: [`kmp-migration-plan.md`](../architecture/mobile/kmp-migration-plan.md) (§0 decisions D1–D5, §5.3 repository options, §11 migration strategy, §14 risks), [ADR-038](ADR-038-kmp-shared-layer.md), [ADR-039](ADR-039-native-ui.md), [ADR-007](ADR-007-execution-plan-runtime-contract.md), [ADR-036](ADR-036-google-home-execution-model.md), [`repo-responsibilities.md`](../architecture/repo-responsibilities.md), [`architecture-map.md`](../architecture/architecture-map.md), [`git-flow.md`](../standards/git-flow.md).
