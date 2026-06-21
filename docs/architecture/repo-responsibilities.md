# Repository responsibilities — ownership boundaries

**Status:** Active architecture (source of truth)  
**Scope:** What **must** and **must not** live in each Ixora repository  
**Applies to:** `front_vibes`, `ixora-admin`, `back_vibes`, `ixora-infra` — all engineers and AI-assisted tooling

> **Drift prevention.** When unsure where code or config belongs, use this document **before** opening a PR. Conflicts with an ADR require a **new ADR** — not a silent exception in an app repo.

**Related:** [Platform architecture map](architecture-map.md) · [Engineer onboarding](../onboarding/onboarding.md) · [Documentation index](../README.md)

---

## Purpose

Define **hard ownership boundaries** across the four Ixora repositories so business rules, secrets, playback, uploads, infrastructure, and shared contracts stay in the correct layer as the platform grows — without duplicating authority or hiding cross-repo coupling.

---

## Ecosystem overview

```
┌─────────────────────────────────────────────────────────────────────────┐
│                         SHARED CONTRACTS (documented)                      │
│  REST JSON · Firebase JWT · CDN URL strings · Git Flow · specs · ADRs    │
└─────────────────────────────────────────────────────────────────────────┘
         ▲                    ▲                    ▲                 ▲
         │                    │                    │                 │
  ┌──────┴──────┐      ┌──────┴──────┐      ┌──────┴──────┐   ┌────┴────┐
  │ front_vibes │      │ ixora-admin │      │ back_vibes  │   │ixora-infra│
  │   MOBILE    │      │    ADMIN    │      │     API     │   │ INFRA+DOCS│
  │  runtime    │      │     UI      │      │   domain    │   │  OpenTofu │
  └─────────────┘      └─────────────┘      └─────────────┘   └───────────┘
```

| Repository | One-line role |
| --- | --- |
| **`back_vibes`** | Authoritative **business logic**, persistence, authorization, **Spaces writes**, async jobs |
| **`front_vibes`** | **Mobile runtime** — playback, execution plan, offline, user-facing vibe UX |
| **`ixora-admin`** | **Admin UI** — catalog maintenance; all mutations via API |
| **`ixora-infra`** | **Staging infrastructure** (OpenTofu) + **central documentation** (specs, ADRs, standards) |

Each repo has its **own** git history and **`main` / `develop` / `staging`** branches ([Git Flow](../standards/git-flow.md)).

---

## Boundary matrix (at a glance)

| Concern | front_vibes | ixora-admin | back_vibes | ixora-infra |
| --- | --- | --- | --- | --- |
| **Deployment** | Manual/CI app build | App Platform static (`staging` push) | App Platform API + worker | `tofu apply` (operator) |
| **Auth (identity)** | Firebase client SDK | Firebase client SDK | JWT verify + `users` sync | Firebase **env injection** only |
| **Auth (authorization)** | Route guards (UX) | Middleware (UX) | Policies, middleware, ownership | — |
| **Storage writes** | ❌ | ❌ (via API) | ✅ sole Spaces writer | Bucket resource only |
| **Storage reads** | CDN HTTPS URLs | CDN HTTPS URLs | Server SDK + CDN URLs in JSON | CDN hostname in env |
| **Playback runtime** | ✅ | ❌ | ❌ | ❌ |
| **Execution plan** | ✅ | ❌ | ❌ | ❌ |
| **Offline bytes** | ✅ | ❌ | ❌ | ❌ |
| **Catalog CRUD rules** | ❌ | Forms only | ✅ | ❌ |
| **Queue / mail jobs** | ❌ | ❌ | ✅ worker | Worker **spec** only |
| **Infrastructure** | ❌ | ❌ | ❌ | ✅ OpenTofu |
| **Feature specs / ADRs** | Copies optional | Copies optional | Copies optional | ✅ **canonical** |

---

## `front_vibes` — mobile application

**Stack:** Ionic 8, Vue 3, Capacitor 8, Pinia, Firebase client SDK.

### Responsibilities

- End-user mobile UX: browse presets, create/edit **user vibes**, attach catalog sounds, play/stop vibes.
- **Playback runtime:** Pinia `player.store`, `audio-player.service`, native audio, Android foreground service.
- **Execution plan:** `buildVibeExecutionPlan` — `VibeSound[]` → `VibeExecutionLayer[]` ([ADR-007](../decisions/ADR-007-execution-plan-runtime-contract.md)).
- **Offline:** explicit download, Preferences manifests, `file://` resolve ([ADR-004](../decisions/ADR-004-offline-audio-strategy.md)).
- Firebase sign-in UX; attach **Bearer JWT** to API calls; client-side route guards.
- Consume **opaque HTTPS CDN URLs** from API JSON — images, audio stream, offline GET.

### MUST live here

| Category | Examples |
| --- | --- |
| Player state & timers | Layer scheduling, play/pause, elapsed clock |
| Native integrations | `@capgo/native-audio`, CapacitorHttp, Filesystem, FGS |
| Mobile navigation | Ionic routes, tab shell ([routing standard](../standards/front-vibes-ionic-routing.md)) |
| Client auth UX | Google sign-in, email flows ([auth standard](../standards/front-vibes-auth-core.md)) |
| Offline manifests | `ixora_offline_audio_manifest_v1`, `offline_vibe_manifest_v1` |
| Staging/local API target | `VITE_API_BASE_URL`, `.env.staging` |

### MUST NOT live here

| Forbidden | Why |
| --- | --- |
| **`DO_SPACES_*` or bucket SDK** | [ADR-002](../decisions/ADR-002-laravel-only-storage-writes.md) · [ADR-006](../decisions/ADR-006-no-direct-mobile-uploads.md) |
| **Catalog sound/cover create** (today) | Admin + API domain |
| **Authoritative validation** (MIME, size, ownership) | Server FormRequests — client hints only |
| **Business policies** (who owns vibe, admin gates) | Laravel policies |
| **Spaces URL construction** from bucket/region | Use API-returned full URLs |
| **Backend scheduling / play endpoints** | No server play engine |
| **Preset → vibe sync listeners** | [ADR-005](../decisions/ADR-005-no-realtime-preset-sync.md) |
| **OpenTofu / App Platform config** | `ixora-infra` |
| **Canonical feature specs** | `ixora-infra/docs/specs/` (repo copy is secondary) |

### Deployment responsibility

- **Not** hosted on DigitalOcean App Platform.
- **`staging` branch** in git aligns with homologation; **binary** via `npm run build:staging` / Capacitor → device or store pipeline (team CI).
- Points at `https://staging-api.ixora-app.app` in `.env.staging`.

### Shared contracts consumed

- REST: `/api/vibes`, `/api/sounds`, `/api/preset-vibes`, `/api/auth/sync`, …
- JSON shape from Laravel **Resources** ([api-resource-patterns](../standards/api-resource-patterns.md)).
- Firebase JWT on every mutating/read request as implemented per service.

---

## `ixora-admin` — admin panel

**Stack:** Nuxt 3, Vue 3, TypeScript, Tailwind, Firebase client SDK, static generate for staging.

### Responsibilities

- Admin UX for **catalog**: sounds, cover bundles, preset vibes.
- Multipart **upload UX** — files sent to Laravel; display CDN URLs returned.
- Firebase login; **`admin.approved`** gate experienced as API **403** + redirect flows.
- Static site assets only — no server-side business runtime in production.

### MUST live here

| Category | Examples |
| --- | --- |
| Admin pages & layouts | `pages/sounds/*`, `CoverBundleForm.vue`, sidebar shell |
| Form composables | `useUpload`, client progress, preview blobs |
| API service modules | `$fetch` wrappers with Bearer token |
| Client `<input accept>` hints | `shared/upload-limits.ts` — **UX only** |
| `NUXT_PUBLIC_*` consumption | API base URL, Firebase web config |

### MUST NOT live here

| Forbidden | Why |
| --- | --- |
| **`DO_SPACES_*` / presigned PUT to bucket** | [ADR-002](../decisions/ADR-002-laravel-only-storage-writes.md) |
| **Duplicate MIME/size enforcement as source of truth** | [upload-validation](../standards/upload-validation.md) — Laravel validates |
| **Authorization rules** (is admin approved?) | Laravel middleware + policies |
| **Direct PostgreSQL** | API only |
| **Playback / execution plan / offline** | Mobile domain |
| **Queue workers, cron, schedulers** | `back_vibes` |
| **OpenTofu** | `ixora-infra` |
| **Hidden API base URL logic** bypassing `NUXT_PUBLIC_API_BASE_URL` | Breaks staging build-time contract |

### Deployment responsibility

- **App Platform static site** on push to **`ixora-admin` `staging`** branch.
- Build: `npm ci && npm run generate` → `.output/public`.
- **`NUXT_PUBLIC_*`** injected at **BUILD_TIME** via OpenTofu ([staging-digitalocean](backend/staging-digitalocean.md)).

### Shared contracts consumed

- Same Firebase + Bearer model as mobile ([ADR-001](../decisions/ADR-001-firebase-auth-laravel-sync.md)).
- Multipart routes: `POST /api/admin/sounds`, `POST /api/cover-bundles`, `POST /api/admin/uploads`, etc.
- [admin-form-patterns](../standards/admin-form-patterns.md) for UX; [create-sound](../specs/sounds/create-sound/spec.md) / [create-cover-bundle](../specs/covers/create-cover-bundle/spec.md) for behaviour.

---

## `back_vibes` — Laravel API

**Stack:** Laravel 13, PHP 8.3+, PostgreSQL, Kreait Firebase Admin, Flysystem Spaces disk, FrankenPHP Docker on staging.

### Responsibilities

- **System of record:** users, vibes, sounds, cover bundles, presets, pivots, jobs.
- **Authorization:** `firebase.auth`, `admin.approved`, policies, query scoping by `user_id`.
- **Validation:** FormRequests, `UploadAssetValidator`, canonical keys via `StoragePathBuilder`.
- **Spaces I/O:** sole **`put` / `delete`**; `publicUrl()` → CDN strings on rows ([spaces-cdn-policy](storage/spaces-cdn-policy.md)).
- **Safe deletion:** `StorageAssetReferenceService`, `SafeAssetDeletionService`.
- **Async work:** database queue, `ShouldQueue` mail (e.g. admin access requests) — **worker** on staging.
- REST JSON via **API Resources** — stable field names for all clients.

### MUST live here

| Category | Examples |
| --- | --- |
| Routes, controllers, actions | `CreateSoundWithUploadedFiles`, vibe CRUD |
| Migrations, models, policies | `VibePolicy`, `firebase_uid` mapping |
| Firebase JWT verification | `VerifyFirebaseIdToken`, sync action |
| Spaces services | `DigitalOceanSpacesService`, path builder |
| Queue jobs / mailables | Queued mail, future `ShouldQueue` jobs |
| Server env secrets | `APP_KEY`, `FIREBASE_*`, `DO_SPACES_*`, `DB_*` |
| CORS config | `CORS_ALLOWED_ORIGINS` |

### MUST NOT live here

| Forbidden | Why |
| --- | --- |
| **Mobile UI / Pinia / Capacitor** | `front_vibes` |
| **Nuxt pages / admin components** | `ixora-admin` |
| **Playback scheduler / “play vibe now” API** | No backend engine ([scheduling-model](backend/scheduling-model.md) *planning*) |
| **Execution plan generation** | Client-only ([ADR-007](../decisions/ADR-007-execution-plan-runtime-contract.md)) |
| **OpenTofu `.tf` files** | `ixora-infra` |
| **Canonical ADRs/specs** (authoring) | Author in `ixora-infra/docs/` |
| **Client-trusted identity fields** in body | JWT claims only ([ADR-001](../decisions/ADR-001-firebase-auth-laravel-sync.md)) |
| **Preset change fan-out to user vibes** | [ADR-005](../decisions/ADR-005-no-realtime-preset-sync.md) |

### Deployment responsibility

- **App Platform** Docker app on push to **`back_vibes` `staging`**.
- Two components: **`api`** (HTTP) + **`queue`** worker — same image/env ([staging-digitalocean](backend/staging-digitalocean.md)).
- **Migrations:** manual operator step after schema releases ([deploy-pipeline](backend/deploy-pipeline.md)).
- Legacy **Droplet SSH** workflow in repo is **not** current architecture.

### Shared contracts published

- OpenAPI-level behaviour in **specs** under `ixora-infra/docs/specs/`.
- JSON resources — URL columns as full HTTPS CDN strings.
- Auth: `POST /api/auth/sync`, Bearer Firebase JWT thereafter.

---

## `ixora-infra` — infrastructure & documentation

**Stack:** OpenTofu (DigitalOcean provider), markdown documentation tree.

### Responsibilities

- **Declarative staging footprint:** VPC, Postgres, Spaces bucket, App Platform apps, env vars, domains ([opentofu/staging/](../../opentofu/staging/README.md)).
- **Central documentation:** specs, architecture, standards, ADRs, onboarding — **[`docs/README.md`](../README.md)** index.
- **Git Flow standard** — [git-flow.md](../standards/git-flow.md) (workspace rules align).
- Cross-repo **coordination policy** — when to `tofu apply` vs app deploy ([deploy-pipeline](backend/deploy-pipeline.md)).

### MUST live here

| Category | Examples |
| --- | --- |
| OpenTofu staging stack | `app-api.tf`, `app-admin.tf`, `database.tf`, `spaces.tf` |
| Canonical specs & ADRs | `docs/specs/`, `docs/decisions/` |
| Architecture & onboarding | `docs/architecture/`, `docs/onboarding/` |
| `terraform.tfvars.example` | Placeholders only — never real secrets |
| `.terraform.lock.hcl` | Committed provider pins |

### MUST NOT live here

| Forbidden | Why |
| --- | --- |
| **Laravel/PHP application code** | `back_vibes` |
| **Vue/Ionic/Nuxt app source** | Client repos |
| **Runtime business logic** | API owns domain |
| **Committed secrets** | `terraform.tfvars`, keys, `APP_KEY` |
| **Duplicated “source of truth” specs** that diverge from `docs/specs/` | Single canonical tree |

### Deployment responsibility

- **`tofu apply`** by operator when infra or App Platform **env maps** change — **not** triggered by app git push alone.
- Does **not** replace App Platform **`deploy_on_push`** for application source.
- Git: merge infra changes through same **Git Flow**; apply when **`staging`** line matches intended runtime.

### Infrastructure responsibility

| Resource | Declared in |
| --- | --- |
| VPC, Postgres firewall | `vpc.tf`, `database.tf` |
| Spaces bucket (optional) | `spaces.tf` |
| API + queue worker + admin static | `app-api.tf`, `app-admin.tf` |
| Laravel/admin env injection | `local.api_worker_runtime_env`, admin BUILD_TIME vars |

---

## Shared contracts

Contracts are **documented in `ixora-infra/docs/`** and **implemented across repos**. Change the doc **in the same change set** as code when behaviour shifts.

| Contract | Definition lives | Implementers |
| --- | --- | --- |
| **Git Flow** | [git-flow.md](../standards/git-flow.md) | All four repos |
| **Firebase + Laravel auth** | [ADR-001](../decisions/ADR-001-firebase-auth-laravel-sync.md) | All clients + API |
| **Spaces write policy** | [ADR-002](../decisions/ADR-002-laravel-only-storage-writes.md) · [storage-strategy](storage/storage-strategy.md) | API writes; clients read |
| **CDN URL shape** | [spaces-cdn-policy](storage/spaces-cdn-policy.md) | API persists; clients consume |
| **Preset import semantics** | [ADR-003](../decisions/ADR-003-preset-import-independent-vibes.md) | API + mobile |
| **Offline download** | [ADR-004](../decisions/ADR-004-offline-audio-strategy.md) · [offline-download spec](../specs/vibes/offline-download/spec.md) | Mobile |
| **No preset sync** | [ADR-005](../decisions/ADR-005-no-realtime-preset-sync.md) | API must not fan-out |
| **Execution plan** | [ADR-007](../decisions/ADR-007-execution-plan-runtime-contract.md) · [execution-plan spec](../specs/vibes/execution-plan/spec.md) | Mobile |
| **API JSON shape** | [api-resource-patterns](../standards/api-resource-patterns.md) + feature specs | API publishes; clients consume |
| **Upload validation** | [upload-validation](../standards/upload-validation.md) | API enforces; admin hints only |
| **Staging URLs** | [staging-digitalocean](backend/staging-digitalocean.md) | OpenTofu + env vars |

**Versioning rule:** mobile and admin **must not** fork API field semantics locally — extend via Laravel Resources and update the spec.

---

## Anti-patterns

Explicit **do-not** list for reviews and AI-generated code.

### 1. Business logic in mobile

| Symptom | Example | Correct owner |
| --- | --- | --- |
| Ownership checks in Vue | “Hide delete if not owner” without API enforcement | `back_vibes` policies — UI may mirror, not replace |
| Catalog mutation | Creating `sounds` rows from app | Admin + API |
| Import side effects | Mutating preset rows on import | API `import` action only |
| “Smart” preset refresh | Re-fetch preset into user vibe on play | [ADR-005](../decisions/ADR-005-no-realtime-preset-sync.md) |

### 2. Direct Spaces writes from clients

| Symptom | Example | Correct owner |
| --- | --- | --- |
| Spaces keys in env | `DO_SPACES_SECRET` in Nuxt or Capacitor | Laravel runtime only |
| Presigned browser PUT | Upload straight to bucket | Multipart to Laravel |
| Mobile avatar → Spaces | SDK in app binary | Future: API route ([ADR-006](../decisions/ADR-006-no-direct-mobile-uploads.md)) |

### 3. Runtime scheduling in backend

| Symptom | Example | Correct owner |
| --- | --- | --- |
| Cron plays vibes | Laravel scheduler triggers playback | **Not shipped** — mobile manual play |
| `POST /api/vibes/{id}/play` | Server-side layer timers | Forbidden |
| Push notification “play now” | FCM → ExoPlayer on server command | Planning only ([scheduling-model](backend/scheduling-model.md)) |

### 4. Frontend-owned canonical validation

| Symptom | Example | Correct owner |
| --- | --- | --- |
| Admin rejects upload alone | JS file size check without server 422 | Laravel `UploadAssetValidator` |
| Mobile skips API | Assumes local JSON is valid vibe | Server FormRequests |
| Client-only MIME trust | Extension from filename only | Server content validation |

*Client validation is allowed for **UX** (early feedback, `accept` attributes) — never as the **only** gate.*

### 5. Hidden cross-repo coupling

| Symptom | Example | Correct owner |
| --- | --- | --- |
| Admin env var not in OpenTofu | Hand-edited DO dashboard only | `ixora-infra` + `tofu apply` |
| API expects field mobile never sends | Undocumented JSON contract | Update spec + all clients |
| Feature merged in one repo only | API schema on staging, mobile on `develop` | Coordinated [Git Flow](../standards/git-flow.md) promotion |
| Duplicate spec in app repo | `back_vibes/docs/` contradicts central spec | Fix central doc first |
| Implicit dependency on legacy deploy | SSH Droplet scripts vs App Platform | [deploy-pipeline](backend/deploy-pipeline.md) |

---

## Decision guide — where does this change go?

```
Does it need a secret (Spaces, APP_KEY, Firebase Admin)?
  └─ YES → back_vibes env (injected via ixora-infra on staging)

Does it mutate PostgreSQL or enforce who may mutate?
  └─ YES → back_vibes

Does it play audio, schedule layers, or store offline bytes?
  └─ YES → front_vibes

Does it render admin catalog forms or upload UX?
  └─ YES → ixora-admin (bytes still through API)

Does it provision DO resources or App Platform env maps?
  └─ YES → ixora-infra OpenTofu

Does it define product behaviour or architecture policy?
  └─ YES → ixora-infra/docs (spec or ADR), then implement in app repo
```

---

## Review checklist (PR authors & reviewers)

- [ ] Change lives in the **correct repository** per this document.
- [ ] No **Spaces credentials** or presigned upload paths in client repos.
- [ ] No **backend playback/scheduling** without planning doc + ADR.
- [ ] **Server validation** exists for every admin/mobile write accepted by API.
- [ ] **Cross-repo** work lists all repos + merge order in PR description.
- [ ] **Infra env** changes include `ixora-infra` OpenTofu (not dashboard-only drift).
- [ ] **Central spec/ADR** updated when contract changes.
- [ ] App-repo doc copies updated or explicitly deferred to central sync.

---

## Related documentation

| Document | Topic |
| --- | --- |
| [architecture-map.md](architecture-map.md) | Flows and component diagram |
| [../onboarding/onboarding.md](../onboarding/onboarding.md) | New engineer orientation |
| [storage/storage-strategy.md](storage/storage-strategy.md) | Storage access matrix |
| [backend/staging-digitalocean.md](backend/staging-digitalocean.md) | Staging ownership of runtime |
| [backend/deploy-pipeline.md](backend/deploy-pipeline.md) | Who deploys what |
| [../README.md](../README.md) | Full doc index |
| [../decisions/](../README.md#4-architecture-decision-records-adrs) | ADR index |

When ownership rules change, update **this file**, affected **ADRs**, and [onboarding](../onboarding/onboarding.md) in the same change set.
