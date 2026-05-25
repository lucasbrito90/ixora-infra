# Quality harness baseline — Ixora ecosystem

**Status:** Active engineering baseline  
**Scope:** Minimal **local validation commands** per repository before PR / staging promotion  
**Applies to:** `back_vibes`, `ixora-admin`, `front_vibes`

> **Baseline only.** No Playwright, no Cypress in CI harness, no Android instrumented tests, no PHPStan/Larastan install (unless added later by ADR). Commands verified against the workspace **May 2026**.

**Related:** [Git Flow](standards/git-flow.md) · [Onboarding](onboarding/onboarding.md) · [Deploy pipeline](architecture/backend/deploy-pipeline.md)

---

## Purpose

Give every engineer the **same minimal quality gate**: exact commands, expected tooling, pass/fail meaning, and gaps — without changing product behaviour or adding heavy E2E frameworks.

Run harness checks on **`feature/*`** before opening PR → `develop`.

---

## Quick reference

| Repository | One-shot local gate (copy/paste) |
| --- | --- |
| **back_vibes** | `composer test && composer lint:pint` |
| **ixora-admin** | `npm run typecheck && npm run build && npm run test` |
| **front_vibes** | `npm run lint && npm run typecheck && npm run test:unit && npm run build` |
| **Native sync (mobile, when plugins change)** | `cd front_vibes && npm run cap:sync:android` |

**Staging deploy** still follows [deploy-pipeline](architecture/backend/deploy-pipeline.md) — harness does **not** replace homologation QA.

---

## `back_vibes` (Laravel API)

**Path:** [`back_vibes/`](../../back_vibes)

### Prerequisites

| Tool | Version | Notes |
| --- | --- | --- |
| PHP | **8.3+** | `composer.json` requirement |
| Composer | 2.x | |
| SQLite (default) | file DB | `.env` from `.env.example`; `database/database.sqlite` for tests |
| Extensions | pdo, mbstring, … | Match Laravel 13 requirements |

```bash
cd back_vibes
cp .env.example .env   # first time
php artisan key:generate
composer install
php artisan migrate    # first time / after schema changes
```

Firebase / Spaces are **not** required for the default Pest suite (uses fakes / SQLite).

### Commands (verified)

| Check | Command | Pass | Verified |
| --- | --- | --- | --- |
| **Tests (Pest)** | `composer test` | Exit `0`; JSON line `"result":"passed"` | ✅ 100 tests |
| **Style (Pint dry-run)** | `composer lint:pint` | Exit `0` | ⚠️ **Currently fails** — 16 files need formatting (run `composer format:pint` when ready) |
| **Style (Pint fix)** | `composer format:pint` | Rewrites files | ✅ command exists |
| **Pint (direct)** | `./vendor/bin/pint --test` | Same as `lint:pint` | ✅ |
| **PHPStan / Larastan** | — | — | ❌ **Not installed** in `require-dev` — do not add without team approval |

Equivalent raw test invocation:

```bash
php artisan config:clear --ansi
php artisan test
```

### Composer scripts added (harness)

```json
"test": "config:clear + artisan test",
"lint:pint": "vendor/bin/pint --test",
"format:pint": "vendor/bin/pint"
```

### Explicitly out of scope (today)

- Larastan / PHPStan baseline
- Dusk / browser E2E
- Staging integration tests in harness
- Running migrations against staging from harness doc

### Notes

- If `composer` refuses root user: `COMPOSER_ALLOW_SUPERUSER=1 composer test` (CI images only).
- Pint failure is **style drift**, not test failure — fix with `composer format:pint` in a dedicated commit if policy requires green Pint.

---

## `ixora-admin` (Nuxt 3)

**Path:** [`ixora-admin/`](../../ixora-admin)

### Prerequisites

| Tool | Version |
| --- | --- |
| Node.js | LTS 18+ / 20+ |
| npm | 9+ |

```bash
cd ixora-admin
cp .env.example .env   # NUXT_PUBLIC_* optional for build/typecheck
npm install              # runs nuxt prepare via postinstall
```

### Commands (verified)

| Check | Command | Pass | Verified |
| --- | --- | --- | --- |
| **Typecheck** | `npm run typecheck` | Exit `0` | ✅ (`nuxt prepare && nuxt typecheck`) |
| **Unit tests (Vitest)** | `npm run test` | Exit `0` | ✅ `passWithNoTests: true` — no `*.test.ts` files yet |
| **Production build** | `npm run build` | Exit `0` | ✅ Nuxt SSR build |
| **Staging static (App Platform)** | `npm run generate` | Exit `0` | ✅ outputs `.output/public` |
| **Lint (ESLint)** | — | — | ❌ **Not configured** — no ESLint in `devDependencies` |

Direct equivalents:

```bash
npx nuxt typecheck          # after nuxt prepare
npx vitest run
npm run build
npm run generate
```

### npm scripts added (harness)

```json
"typecheck": "nuxt prepare && nuxt typecheck"
```

(`test`, `build`, `generate` already existed.)

### Proposed smallest lint addition (not done)

When the team wants ESLint:

```bash
npm install -D eslint @nuxt/eslint-config
```

Then add `"lint": "eslint ."` — **requires explicit approval**; not part of this baseline.

### Explicitly out of scope (today)

- Playwright / Cypress E2E
- ESLint (until added)
- Firebase live integration in harness (build uses empty public env defaults)

---

## `front_vibes` (Ionic + Capacitor)

**Path:** [`front_vibes/`](../../front_vibes)

### Prerequisites

| Tool | Version |
| --- | --- |
| Node.js | LTS |
| npm | 9+ |
| Android SDK | For `cap sync android` / device builds |
| Java JDK | Capacitor Android |

```bash
cd front_vibes
npm install
```

### Commands (verified)

| Check | Command | Pass | Verified |
| --- | --- | --- | --- |
| **Lint (ESLint)** | `npm run lint` | Exit `0` | ✅ |
| **Typecheck** | `npm run typecheck` | Exit `0` | ✅ `vue-tsc --noEmit` |
| **Build** | `npm run build` | Exit `0` | ✅ includes `vue-tsc` + Vite |
| **Staging build** | `npm run build:staging` | Same as build with staging env | ✅ (same toolchain) |
| **Unit tests (Vitest)** | `npm run test:unit` | Exit `0` | ✅ no tests yet (`passWithNoTests`) |
| **Capacitor Android sync** | `npm run cap:sync:android` | Exit `0` | ✅ wraps `cap sync android` |
| **E2E (Cypress)** | `npm run test:e2e` | — | ⏸️ **Not in baseline** — exists but not required |

Direct Capacitor command:

```bash
npx cap sync android
```

### Harness cleanup (May 2026)

- Removed stale scaffold `tests/unit/example.spec.ts` (referenced deleted `Tab1Page.vue`) — blocked Vitest with import error.
- Added `passWithNoTests: true` in `vite.config.ts`.
- Added scripts: `typecheck`, `cap:sync:android`; `test:unit` now runs `vitest run` (non-watch).

### Explicitly out of scope (today)

- Cypress in mandatory harness (`test:e2e` remains optional)
- Android instrumented / Espresso tests
- iOS sync in baseline (add `cap:sync:ios` when iOS is active)

---

## Cross-repo expectations

| Rule | Detail |
| --- | --- |
| **No product changes for green harness** | Harness fixes are scripts, docs, stale test removal — not feature refactors |
| **Server rules stay in Laravel** | [repo-responsibilities](architecture/repo-responsibilities.md) |
| **No client Spaces writes** | [ADR-002](decisions/ADR-002-laravel-only-storage-writes.md) |
| **Specs/ADRs unchanged by harness** | Harness does not alter acceptance criteria |
| **Per-repo Git Flow** | Run harness on `feature/*` before PR |

### Suggested PR checklist

- [ ] Harness commands for **each touched repo** pass (or documented exception, e.g. Pint drift)
- [ ] Central spec/ADR updated if behaviour changed
- [ ] Cross-repo features: harness run in **all** affected repos

---

## CI / future work (not implemented)

| Item | Status |
| --- | --- |
| GitHub Actions per repo | Not defined in this baseline |
| Shared workflow in `ixora-infra` | Future |
| PHPStan/Larastan | Not installed — propose ADR before adding |
| Admin ESLint | Not installed |
| Playwright | Explicitly deferred |
| Android automated UI tests | Explicitly deferred |

---

## Verification log

Commands executed in workspace **2026-05-23**:

| Repo | Command | Result |
| --- | --- | --- |
| back_vibes | `composer test` | 100 passed |
| back_vibes | `composer lint:pint` | Fail — 16 files need Pint |
| back_vibes | `vendor/bin/phpstan` | Binary absent |
| ixora-admin | `npm run typecheck` | Pass |
| ixora-admin | `npm run build` | Pass |
| ixora-admin | `npm run generate` | Pass |
| ixora-admin | `npm run test` | Pass (no tests) |
| front_vibes | `npm run lint` | Pass |
| front_vibes | `npm run typecheck` | Pass |
| front_vibes | `npm run build` | Pass |
| front_vibes | `npm run test:unit` | Pass (no tests) |
| front_vibes | `npm run cap:sync:android` | Pass |

---

## Related documentation

| Document | Topic |
| --- | --- |
| [README.md](README.md) | Documentation index |
| [onboarding/onboarding.md](onboarding/onboarding.md) | New engineer setup |
| [architecture/repo-responsibilities.md](architecture/repo-responsibilities.md) | Where logic belongs |
| [standards/git-flow.md](standards/git-flow.md) | Branch promotion |

When harness commands change, update **this file first**, then repo README pointers.
