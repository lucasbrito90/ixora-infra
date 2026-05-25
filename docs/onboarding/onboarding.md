# Engineer onboarding — Ixora platform

**Status:** Active onboarding guide  
**Audience:** New engineers joining Ixora (backend, admin, mobile, or infra)  
**Start here after:** Skimming the [documentation index](../README.md)

> Central docs live in **`ixora-infra/docs/`**. App repos may hold copies — **`ixora-infra` wins** when they diverge.

---

## Welcome

Ixora is a **multi-repo ambient audio platform**: admins curate **catalog sounds** and **cover bundles**, users compose **vibes** (layered playback + visuals) on **mobile**, and **Laravel** owns business rules, storage writes, and authorization.

This guide orients you in **~1–2 days**. Deep work always routes through **specs**, **standards**, and **ADRs** linked below.

**Aerial view:** [Platform architecture map](../architecture/architecture-map.md)

---

## Repository overview

| Repository | Stack | You work here when… |
| --- | --- | --- |
| [`back_vibes`](../../../back_vibes) | Laravel 13, PHP 8.3+, PostgreSQL, Spaces SDK | API routes, policies, uploads, migrations, queues, Firebase JWT verify |
| [`front_vibes`](../../../front_vibes) | Ionic 8, Vue 3, Capacitor 8, Pinia | Mobile UI, **playback runtime**, **execution plan**, offline download |
| [`ixora-admin`](../../../ixora-admin) | Nuxt 3, Vue 3, Tailwind | Admin catalog forms, multipart upload UX (bytes still go through Laravel) |
| [`ixora-infra`](../../) | OpenTofu, markdown docs | Staging infrastructure, **central specs/ADRs**, Git Flow standard |

Each repo is an **independent git remote** with its own `main`, `develop`, and **`staging`** branches.

```
feature/* ──PR──► develop ──merge──► staging ──► homologation deploy
                     │
                     └── never commit directly here
```

Full rules: [Git Flow](../standards/git-flow.md)

---

## Required tools

Install what matches your role. **All engineers** should have git and access to the GitHub org.

| Tool | Version / notes | Roles |
| --- | --- | --- |
| **Git** | 2.x+ | All |
| **PHP** | **8.3+** | Backend |
| **Composer** | 2.x | Backend |
| **Node.js** | LTS (18+ or 20+) | Admin, mobile, backend Vite if needed |
| **npm** | Comes with Node | Admin, mobile |
| **OpenTofu** or **Terraform** | ≥ 1.6 / OpenTofu 1.8+ | Infra, staging ops |
| **Android Studio + SDK** | For device/emulator | Mobile (Android primary) |
| **Java / JDK** | Capacitor Android builds | Mobile |
| **curl / jq** | Smoke tests | Backend, ops |
| **gh** | GitHub CLI (PRs) | All (recommended) |

### Optional but common

| Tool | Use |
| --- | --- |
| **Docker** | FrankenPHP image matches staging; not required for local `php artisan serve` |
| **PostgreSQL client** | Local or staging DB inspection |
| **DigitalOcean account** | If you run `tofu apply` (team credentials) |

### Backend quick start (local)

```bash
cd back_vibes
cp .env.example .env
composer install
php artisan key:generate
# SQLite default in .env.example — or configure pgsql
php artisan migrate
composer run dev   # serve + queue:listen + logs + vite (see composer.json)
```

Set **`FIREBASE_*`** and **`DO_SPACES_*`** when testing real auth or uploads — see [Local environment](#local-environment-expectations).

### Admin quick start (local)

```bash
cd ixora-admin
cp .env.example .env
# NUXT_PUBLIC_API_BASE_URL, NUXT_PUBLIC_FIREBASE_*
npm install
npm run dev
```

See [`ixora-admin/README.md`](../../../ixora-admin/README.md).

### Mobile quick start (local)

```bash
cd front_vibes
npm install
npm run dev              # web dev — not full native stack
npm run dev:staging      # points at staging API (.env.staging)
npx cap sync android     # after native dependency changes
```

Production-like playback/offline QA requires a **device build** — not live reload alone. See [mobile-cdn-validation](../architecture/storage/mobile-cdn-validation.md).

---

## OpenTofu prerequisites

Staging infrastructure is **declarative** in [`ixora-infra/opentofu/staging/`](../../opentofu/staging/README.md). You need this when changing env vars, domains, or DO resources — not for every feature PR.

| Prerequisite | Detail |
| --- | --- |
| **DigitalOcean token** | `TF_VAR_do_token` — Apps, DB, Networking, Spaces write |
| **Spaces keys (IaC only)** | `TF_VAR_spaces_access_id` / `spaces_secret_key` if `manage_spaces_bucket = true` |
| **Separate Laravel Spaces keys** | `api_do_spaces_*` in tfvars — **runtime** uploads; not the same as IaC keys |
| **GitHub ↔ DO** | App Platform must access `back_vibes` / `ixora-admin` repos (UI authorization first time) |
| **Untracked secrets** | `terraform.tfvars` from `terraform.tfvars.example` — **never commit** |

```bash
cd ixora-infra/opentofu/staging
cp terraform.tfvars.example terraform.tfvars   # edit locally
tofu init
tofu plan
tofu apply    # operator only — review plan with team
```

Deep dive: [staging-digitalocean.md](../architecture/backend/staging-digitalocean.md) · [deploy-pipeline.md](../architecture/backend/deploy-pipeline.md)

**You typically do not** run OpenTofu on day one unless you are the infra/on-call engineer for staging.

---

## Firebase setup expectations

Firebase is the **identity provider** for mobile and admin. Laravel is the **authorization and data** backend.

| Layer | Who configures | What |
| --- | --- | --- |
| **Firebase Console** | Team lead / platform | Google sign-in, email auth, OAuth clients, service account |
| **Mobile** | Compile-time env | Firebase web/Android config in `front_vibes` env files |
| **Admin** | `NUXT_PUBLIC_FIREBASE_*` | Local `.env`; staging via OpenTofu **BUILD_TIME** on App Platform |
| **API** | `FIREBASE_*` discrete vars | Local `.env`; staging via OpenTofu **RUN_TIME** secrets on API + queue worker |

**Flow every engineer must understand:**

1. Client signs in with Firebase → receives **ID token (JWT)**  
2. Client calls **`POST /api/auth/sync`** with `Authorization: Bearer <token>`  
3. All later API calls use the same Bearer token  
4. Laravel **`firebase.auth`** middleware verifies JWT and loads `users` by **`firebase_uid`**

Detail: [ADR-001](../decisions/ADR-001-firebase-auth-laravel-sync.md) · [front-vibes-auth-core](../standards/front-vibes-auth-core.md)

**Do not:** put Firebase **Admin private keys** in client repos, or trust client-sent uid/email in request bodies for auth.

---

## Staging environment overview

Homologation runs on **DigitalOcean App Platform** (Toronto), managed by OpenTofu.

| Surface | URL (default) | Deploy |
| --- | --- | --- |
| **API** | `https://staging-api.ixora-app.app` | Push `back_vibes` **`staging`** |
| **Admin** | `https://staging-admin.ixora-app.app` | Push `ixora-admin` **`staging`** |
| **Mobile target** | Same API host | `npm run build:staging` / manual install |
| **CDN assets** | `*.tor1.cdn.digitaloceanspaces.com` | Uploaded via API — not redeployed with admin |

**Runtime components:**

- **API service** — FrankenPHP Laravel (HTTP :8080)  
- **Queue worker** — same image, `queue:work`, database driver  
- **PostgreSQL** — VPC-private `ixora_staging`  
- **Spaces + CDN** — Laravel-only writes  

Health check: `curl -sf https://staging-api.ixora-app.app/api/health`

Topology: [staging-digitalocean.md](../architecture/backend/staging-digitalocean.md)  
Promotion: [deploy-pipeline.md](../architecture/backend/deploy-pipeline.md)

---

## Git Flow expectations

Non-negotiable rules ([Git Flow](../standards/git-flow.md)):

| Rule | Requirement |
| --- | --- |
| **Branch from `develop`** | `feature/<name>` for all new work |
| **No direct commits** | ❌ `develop`, ❌ `staging`, ❌ `main` |
| **Merge style** | **`git merge --no-ff`** for integrations |
| **PR target** | `feature/*` → **`develop`** (human review required) |
| **Homologation** | **`develop` → `staging`** when QA-ready — all affected repos |
| **Force push** | ❌ Never on `main`, `develop`, `staging` |
| **Delete branches** | ❌ Never delete `feature/*`, `release/*`, `hotfix/*`, or `staging` on remote |

**Cross-repo features:** same feature slug across repos; merge to `develop` everywhere; promote to `staging` together; **`tofu apply`** when infra env changes.

```bash
git checkout develop && git pull origin develop
git checkout -b feature/my-change
# … work, PR to develop …
```

---

## How specs, ADRs, and standards are used

| Doc type | Path | When to read | When to update |
| --- | --- | --- | --- |
| **Specs** | [`../specs/`](../README.md#1-specs) | **Before implementing** a feature — acceptance criteria, API shape | Feature delivery + behaviour change |
| **ADRs** | [`../decisions/`](../README.md#4-architecture-decision-records-adrs) | When touching auth, storage, offline, presets, playback contracts | Supersede with new ADR if decision changes |
| **Standards** | [`../standards/`](../README.md#3-standards) | Code review patterns — forms, uploads, Git Flow, mobile auth/routing | Team convention changes |
| **Architecture** | [`../architecture/`](../README.md#2-architecture) | Runtime boundaries, staging, CDN, playback stack | Platform behaviour changes |
| **This index** | [`../README.md`](../README.md) | Find anything | Add links when new docs land |

**Workflow:**

1. Read the **spec** for your feature.  
2. Read linked **ADRs** and **architecture** pages.  
3. Follow **standards** in code review.  
4. If the spec and ADR conflict, **stop** — clarify before coding (ADRs win on architecture; specs win on product behaviour).

Planning-only docs (**scheduling**, **future-processing-pipeline**) are **not** implementation authority.

---

## Where NOT to implement logic

Putting code in the wrong layer is the most common onboarding mistake.

| Do **not** implement here | Instead implement in |
| --- | --- |
| **Admin/mobile: Spaces upload SDK** | `back_vibes` upload actions + validators — [ADR-002](../decisions/ADR-002-laravel-only-storage-writes.md) |
| **Admin/mobile: business rules / ownership** | Laravel policies, FormRequests, actions |
| **Admin/mobile: playback scheduling** | `front_vibes` player + execution plan — no server play engine |
| **Admin/mobile: Firebase Admin verify** | `back_vibes` middleware only |
| **Laravel: UI playback state** | `front_vibes` Pinia `player.store` |
| **Laravel: offline file download** | `front_vibes` CapacitorHttp + manifests — [ADR-004](../decisions/ADR-004-offline-audio-strategy.md) |
| **OpenTofu: application business logic** | App repos |
| **Specs: one-off hacks without spec update** | Update spec or open ADR first |
| **Client: construct CDN URLs from bucket name** | Use **`publicUrl()`** URLs from API JSON only |
| **Preset observer syncing user vibes** | Forbidden — [ADR-005](../decisions/ADR-005-no-realtime-preset-sync.md) |

**Rule of thumb:** if it needs **secrets**, **reference-checked delete**, or **cross-user authorization** → **Laravel**. If it needs **timers, audio, or offline bytes** → **mobile**. If it needs **DO resources** → **OpenTofu**.

---

## Runtime architecture overview

```
Firebase Auth          back_vibes (API + queue worker)
     │                         │
     ├──── front_vibes ────────┤ REST + Bearer JWT
     └──── ixora-admin ────────┘
                │
                ├── PostgreSQL (metadata, URLs, jobs)
                └── Spaces ──► CDN ◄── GET assets (clients)
```

| Concern | Owner |
| --- | --- |
| HTTP API | `back_vibes` App Platform **service** |
| Async mail / `ShouldQueue` jobs | **Queue worker** (same env as API) |
| Static admin UI | App Platform **static site** (no Laravel runtime) |
| Mobile binary | Not on App Platform — local/CI build |

Map: [architecture-map.md](../architecture/architecture-map.md) · [staging-digitalocean.md](../architecture/backend/staging-digitalocean.md)

---

## Playback architecture overview

**Server stores `vibe_sounds` pivot config. Device builds plan and plays.**

```
GET /api/vibes/{id}  →  VibeSound[]
         │
         ▼
 buildVibeExecutionPlan()     ← client-only ([ADR-007](../decisions/ADR-007-execution-plan-runtime-contract.md))
         │
         ▼
 player.store + audio-player  ← [playback-runtime](../architecture/audio/playback-runtime.md)
         │
         ▼
 NativeAudio / ExoPlayer  ← HTTPS CDN file_url
```

| Topic | Document |
| --- | --- |
| Plan field mapping | [execution-plan spec](../specs/vibes/execution-plan/spec.md) |
| Player stack | [playback-runtime spec](../specs/vibes/playback-runtime/spec.md) · [architecture](../architecture/audio/playback-runtime.md) |
| Fades ignored | [ADR-008](../decisions/ADR-008-nativeaudio-limitations-over-unstable-dsp.md) |
| No backend scheduler | [scheduling-model](../architecture/backend/scheduling-model.md) (*planning*) |

---

## Upload architecture overview

**Single write gate: Laravel → Spaces → CDN URL on row.**

```
Client multipart + Bearer JWT
         │
         ▼
 back_vibes: validate → StoragePathBuilder → putFile
         │
         ▼
 publicUrl(key) → PostgreSQL column
         │
         ▼
 Admin/mobile render HTTPS CDN URL (read-only)
```

| Topic | Document |
| --- | --- |
| Policy | [storage-strategy](../architecture/storage/storage-strategy.md) · [spaces-cdn-policy](../architecture/storage/spaces-cdn-policy.md) |
| ADR | [ADR-002](../decisions/ADR-002-laravel-only-storage-writes.md) · [ADR-006](../decisions/ADR-006-no-direct-mobile-uploads.md) |
| Validation | [upload-validation](../standards/upload-validation.md) |
| Admin forms | [admin-form-patterns](../standards/admin-form-patterns.md) |
| Sound/cover specs | [create-sound](../specs/sounds/create-sound/spec.md) · [create-cover-bundle](../specs/covers/create-cover-bundle/spec.md) |

---

## Mobile vs admin vs backend responsibilities

| Responsibility | `front_vibes` | `ixora-admin` | `back_vibes` |
| --- | --- | --- | --- |
| Sign-in UX | ✅ Firebase | ✅ Firebase | Verifies JWT |
| User vibes CRUD | ✅ | ❌ | ✅ API + policies |
| Catalog sounds/covers | ❌ read/play | ✅ forms + multipart | ✅ validate + Spaces |
| Preset catalog | ✅ browse/import | ✅ maintain | ✅ API |
| Upload bytes to Spaces | ❌ | ❌ (via API only) | ✅ sole writer |
| Playback / layers | ✅ execution plan + player | ❌ | ❌ |
| Offline download | ✅ manifests | ❌ | ❌ (URLs only) |
| Queue / email jobs | ❌ | ❌ | ✅ worker |
| CORS | ❌ (native) / dev caveats | Browser → needs allowlist | ✅ `CORS_ALLOWED_ORIGINS` |
| Staging deploy | Manual build | App Platform push | App Platform push |

---

## Local environment expectations

| Repo | Default local DB | Typical API target | Secrets you need locally |
| --- | --- | --- | --- |
| **back_vibes** | SQLite (`.env.example`) or pgsql | `http://localhost:8000` | `APP_KEY`, optional `FIREBASE_*`, `DO_SPACES_*` for real uploads |
| **ixora-admin** | N/A (static) | `NUXT_PUBLIC_API_BASE_URL` → local or staging API | Firebase **client** config only |
| **front_vibes** | N/A | `dev` → local/proxy; `dev:staging` → staging API | Firebase client config |

**CORS:** When admin runs on `localhost:3000`, add origin to API **`CORS_ALLOWED_ORIGINS`** locally.

**Queue locally:** `composer run dev` includes `queue:listen` — needed for queued mail tests.

**Spaces:** Local API can target the **same staging bucket/CDN** as homologation for integrated upload tests — never commit keys.

**Mobile vs browser:** Web `npm run dev` does **not** validate native audio, FGS, or offline download — use device builds for those paths.

---

## Common pitfalls

| Pitfall | Why it hurts | What to do |
| --- | --- | --- |
| Committing to `develop` / `staging` | Untraceable history, bypasses review | Always `feature/*` + PR — [Git Flow](../standards/git-flow.md) |
| `DO_SPACES_*` in admin/mobile | Security incident | Upload through Laravel only |
| Storing **origin** URL instead of CDN | Breaks client policy, caching | `publicUrl()` only |
| Assuming **play** hits the API | No play endpoint exists | Mobile execution plan |
| Using ExoPlayer cache as **offline** | Incomplete files | Explicit download — [ADR-004](../decisions/ADR-004-offline-audio-strategy.md) |
| Changing `file_url` without offline thought | Breaks manifest exact match | [spaces-cdn-policy](../architecture/storage/spaces-cdn-policy.md) |
| Merging app to staging without infra env | CORS/auth/upload failures | Coordinate + `tofu apply` — [deploy-pipeline](../architecture/backend/deploy-pipeline.md) |
| Forgetting **migrations on staging** | App Platform doesn't auto-migrate | Manual `migrate --force` after schema releases |
| Trusting legacy **SSH deploy** docs in `back_vibes` | Superseded by App Platform | Use [staging-digitalocean](../architecture/backend/staging-digitalocean.md) |
| Implementing from **planning-only** docs | Out-of-scope features | Check doc status banner |
| Dev-only CORS failure → “CDN broken” | WebView ≠ native | [mobile-cdn-validation](../architecture/storage/mobile-cdn-validation.md) on device |
| Preset edit expecting **live user vibe updates** | Not supported | [ADR-005](../decisions/ADR-005-no-realtime-preset-sync.md) |

---

## Important architectural rules

Memorize these before your first merge.

1. **Firebase = identity; Laravel = authorization and domain data** — [ADR-001](../decisions/ADR-001-firebase-auth-laravel-sync.md)  
2. **Laravel is the only Spaces writer/deleter** — [ADR-002](../decisions/ADR-002-laravel-only-storage-writes.md)  
3. **Preset import = independent copy** — [ADR-003](../decisions/ADR-003-preset-import-independent-vibes.md)  
4. **Offline = explicit download + manifests, not streaming cache** — [ADR-004](../decisions/ADR-004-offline-audio-strategy.md)  
5. **No preset → vibe realtime sync** — [ADR-005](../decisions/ADR-005-no-realtime-preset-sync.md)  
6. **Mobile does not upload to Spaces** — [ADR-006](../decisions/ADR-006-no-direct-mobile-uploads.md)  
7. **Execution plan is the mobile playback contract** — [ADR-007](../decisions/ADR-007-execution-plan-runtime-contract.md)  
8. **No JS fades/crossfade on production path** — [ADR-008](../decisions/ADR-008-nativeaudio-limitations-over-unstable-dsp.md)  
9. **Persist full CDN HTTPS URLs** — [spaces-cdn-policy](../architecture/storage/spaces-cdn-policy.md)  
10. **Safe delete: exact URL reference counting** — [storage-strategy](../architecture/storage/storage-strategy.md)  
11. **OpenTofu is infra source of truth** — don't hand-edit App Platform env without IaC follow-up  
12. **No direct commits to protected branches** — [Git Flow](../standards/git-flow.md)  
13. **Specs + ADRs before code** — update docs when behaviour changes  
14. **No backend playback engine or scheduler** (today) — client-only play  

---

## Recommended first-week reading

| Day | Focus | Links |
| --- | --- | --- |
| **1** | Product + map + Git | [README](../README.md) · [architecture-map](../architecture/architecture-map.md) · [git-flow](../standards/git-flow.md) |
| **2** | Auth + your repo | [ADR-001](../decisions/ADR-001-firebase-auth-laravel-sync.md) · role-specific standard (below) |
| **3** | Storage + uploads | [storage-strategy](../architecture/storage/storage-strategy.md) · [ADR-002](../decisions/ADR-002-laravel-only-storage-writes.md) · [upload-validation](../standards/upload-validation.md) |
| **4** | Mobile playback (if mobile) | [execution-plan spec](../specs/vibes/execution-plan/spec.md) · [playback-runtime](../architecture/audio/playback-runtime.md) · [ADR-004](../decisions/ADR-004-offline-audio-strategy.md) |
| **5** | Staging + first PR | [deploy-pipeline](../architecture/backend/deploy-pipeline.md) · [staging-digitalocean](../architecture/backend/staging-digitalocean.md) |

**Role-specific standards:**

| Role | Start with |
| --- | --- |
| Backend | [api-resource-patterns](../standards/api-resource-patterns.md) · [laravel-form-request-patterns](../standards/laravel-form-request-patterns.md) |
| Admin | [admin-form-patterns](../standards/admin-form-patterns.md) |
| Mobile | [front-vibes-auth-core](../standards/front-vibes-auth-core.md) · [front-vibes-ionic-routing](../standards/front-vibes-ionic-routing.md) |
| Infra | [opentofu/staging README](../../opentofu/staging/README.md) |

---

## Checklist — ready to open your first PR

- [ ] I cloned the repo(s) I will work in and can run them locally (or against staging for mobile).  
- [ ] I read [Git Flow](../standards/git-flow.md) and will use **`feature/*` → `develop`**.  
- [ ] I found the **spec** for my task in [../specs/](../README.md#1-specs).  
- [ ] I read applicable **ADRs** (at minimum ADR-001, ADR-002 if touching files/auth).  
- [ ] I know **where not to put logic** (no client Spaces, no server playback).  
- [ ] I know whether my change needs **`ixora-infra` OpenTofu** or staging migration steps.  
- [ ] I will not commit secrets or `terraform.tfvars`.

---

## Related documentation

| Document | Purpose |
| --- | --- |
| [../README.md](../README.md) | Full documentation index |
| [../architecture/architecture-map.md](../architecture/architecture-map.md) | Platform component map |
| [../architecture/backend/staging-digitalocean.md](../architecture/backend/staging-digitalocean.md) | Staging topology |
| [../architecture/backend/deploy-pipeline.md](../architecture/backend/deploy-pipeline.md) | Deploy and promotion |
| [../standards/git-flow.md](../standards/git-flow.md) | Branching policy |
| [../decisions/](../README.md#4-architecture-decision-records-adrs) | All ADRs |
| [../../opentofu/staging/README.md](../../opentofu/staging/README.md) | OpenTofu runbook |

Questions about doc gaps → update **`ixora-infra/docs/`** first, then sync app-repo copies.
