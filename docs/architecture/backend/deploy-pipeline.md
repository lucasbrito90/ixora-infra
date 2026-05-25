# Deployment pipeline — staging architecture

**Status:** Active architecture (source of truth)  
**Scope:** **Current** end-to-end delivery path to the **staging homologation environment** — Git Flow, OpenTofu, DigitalOcean App Platform, and cross-repo coordination  
**Applies to:** `ixora-infra`, `back_vibes`, `ixora-admin`, `front_vibes`

> **Current pipeline only.** Describes how code and configuration reach **staging today**. Does **not** define production deploy topology, blue/green releases, Kubernetes orchestration, or autoscaling policies.

**Companion topology doc:** [`staging-digitalocean.md`](staging-digitalocean.md)  
**Git standard:** [`../../standards/git-flow.md`](../../standards/git-flow.md)  
**IaC runbook:** [`../../../opentofu/staging/README.md`](../../../opentofu/staging/README.md)

---

## Purpose

Document the **deployment pipeline architecture**: how branches promote work, when OpenTofu applies infrastructure, how App Platform builds and publishes API/admin artifacts, how environment variables propagate to runtimes, and what operators must do manually (migrations, validation, rollback) — so staging homologation stays **deployable, traceable, and aligned** across repositories.

---

## Context

### Two delivery layers

Staging delivery splits into **infrastructure configuration** and **application releases**:

| Layer | Trigger | Tool | What changes |
| --- | --- | --- | --- |
| **Infrastructure** | Operator **`tofu apply`** after `ixora-infra` changes reach staging | OpenTofu (`opentofu/staging/`) | VPC, Postgres, Spaces bucket, App Platform apps, RUN_TIME / BUILD_TIME env on DO |
| **Application** | **Git push** to **`staging`** branch (merge from `develop`) | DigitalOcean App Platform (`deploy_on_push`) | Laravel Docker image, queue worker, Nuxt static output |

These layers are **independent pipelines**. Merging app code to `staging` does **not** run OpenTofu. Changing OpenTofu does **not** redeploy app repos unless App Platform detects a spec/env change from apply.

### What auto-deploys vs what does not

| Repository | `staging` branch push | Platform |
| --- | --- | --- |
| **`back_vibes`** | ✅ App Platform rebuild (API + queue worker) | DO App Platform |
| **`ixora-admin`** | ✅ App Platform static build | DO App Platform |
| **`ixora-infra`** | ❌ No deploy hook — operator runs **`tofu apply`** | OpenTofu CLI |
| **`front_vibes`** | ❌ No hosted staging app — **manual** `build:staging` / store install | Local / CI artifact |

### Legacy artifact (not current pipeline)

`back_vibes/.github/workflows/deploy-staging.yml` triggers on **`staging`** push and deploys via **SSH to a Droplet** (includes `migrate --force`, cache rebuild, healthcheck). **Current IaC uses App Platform**, not Droplet deploy. If both SSH workflow and App Platform remain connected to the same repo, treat that as **technical debt** — the **documented staging pipeline is OpenTofu + App Platform** per [`staging-digitalocean.md`](staging-digitalocean.md).

---

## Current Decision

1. **Git Flow governs all repos** — no direct commits to `develop`, `staging`, or `main` ([`git-flow.md`](../../standards/git-flow.md)).
2. **`staging` is the homologation deploy branch** — reflects a **testable snapshot** promoted from `develop`, not a feature workspace.
3. **OpenTofu is infrastructure source of truth** — App Platform env, VPC, DB, and domains are declared in `ixora-infra/opentofu/staging/`.
4. **App Platform deploy-on-push** is the application release mechanism for API and admin.
5. **Migrations are not automated** in the App Platform container entrypoint — operators run them **explicitly** when schema changes ship.
6. **Rollback is git- and deployment-history-based** — no blue/green or multi-region cutover.
7. **Mobile staging validation** requires a **separate build** pointing at the staging API hostname.

---

## Pipeline overview

```
┌─────────────────────────────────────────────────────────────────────────────────┐
│                         GIT FLOW (per repository)                                  │
│                                                                                  │
│   feature/* ──PR──► develop ──merge --no-ff──► staging ──(release/*)──► main   │
│        ▲                 │                          │                            │
│        │                 │                          │                            │
│   (work here)      integration              homologation branch                │
└──────────────────────────┼──────────────────────────┼────────────────────────────┘
                           │                          │
                           │                          │
         ┌─────────────────┴──────────────┐          │
         │  ixora-infra (when env/infra     │          │  back_vibes + ixora-admin
         │  changes needed)                 │          │
         ▼                                  ▼          ▼
   tofu plan / apply              App Platform deploy_on_push
   (operator, manual)             (automatic on staging push)
         │                                  │
         ▼                                  ▼
   Updates DO app spec,            API service + queue worker
   RUN_TIME / BUILD_TIME env       OR admin static site (.output/public)
         │                                  │
         └──────────────┬───────────────────┘
                        ▼
              Staging homologation environment
              (API, admin, DB, Spaces CDN)

   front_vibes: parallel promotion develop → staging in git;
                 manual npm run build:staging → device QA (not App Platform)
```

---

## Git Flow

Each Ixora repository is an **independent git remote** with its own permanent branches:

| Branch | Role in pipeline |
| --- | --- |
| **`develop`** | Integration — all feature PRs merge here |
| **`staging`** | Homologation — **deploy reference branch** for App Platform (API/admin) |
| **`main`** | Production — **out of scope** for this staging pipeline doc |

### Branch rules (preserved)

| Rule | Requirement |
| --- | --- |
| **No direct commits** | ❌ Never commit directly to `develop`, `staging`, or `main` |
| **Feature base** | ✅ Always branch `feature/*` from updated **`develop`** — never from `staging` |
| **Merge style** | ✅ **`git merge --no-ff`** for integrations |
| **Force push** | ❌ Never `git push --force` to `main`, `develop`, or `staging` |
| **Branch retention** | ❌ Never delete `feature/*`, `release/*`, `hotfix/*`, or `staging` on remote |

### Feature → develop

```bash
git checkout develop && git pull origin develop
git checkout -b feature/my-change
# … commits on feature branch …
# PR: feature/my-change → develop (human review required)
```

PR title follows **Conventional Commits** (`feat(scope): …`, `fix(scope): …`, `chore(infra): …`).

---

## feature → develop → staging

### Promotion to homologation

When a set of changes is ready for QA:

```bash
git checkout staging && git pull origin staging
git merge --no-ff develop -m "Merge branch 'develop' into staging"
git push origin staging
```

Repeat in **every affected repository** for cross-cutting work.

### What `staging` push triggers

| Repo | Automatic action |
| --- | --- |
| `back_vibes` | App Platform builds Docker image from **`staging`** → deploys **`api`** service **and** **`queue`** worker |
| `ixora-admin` | App Platform runs `npm ci && npm run generate` → publishes **`.output/public`** |
| `ixora-infra` | **Nothing** until operator runs OpenTofu |
| `front_vibes` | **Nothing** hosted — developers/CI produce staging-mode builds separately |

Optional: open a **`develop` → `staging`** PR when explicit review is required before homologation deploy; merge still uses **`--no-ff`**.

### Sequencing when infra and app depend on each other

From [`git-flow.md`](../../standards/git-flow.md):

1. Merge features to **`develop`** in each affected app repo.
2. Merge OpenTofu / env changes to **`develop`** in **`ixora-infra`** when apps depend on new configuration.
3. Promote **`develop` → `staging`** in all repos that must deploy **together**.
4. **`tofu apply`** when infra changes are on the operator’s staging stack **before or as part of** validating dependent app deploys.
5. Confirm App Platform picked up **`staging`** branch deploys; validate mobile against staging API if applicable.

**Infra-first examples:** new `CORS_ALLOWED_ORIGINS` entry, new App Platform env var, DB firewall rule, domain change.  
**App-first acceptable:** code-only bugfix with unchanged runtime config.

---

## OpenTofu apply flow

OpenTofu manages **platform configuration**, not application source code.

### When to apply

| Change type | Apply required |
| --- | --- |
| New/changed App Platform env (`api_worker_runtime_env`, admin `NUXT_PUBLIC_*`) | ✅ |
| Domain, VPC, Postgres, Spaces bucket resources | ✅ |
| CORS allowlist via `api_cors_allowed_origins` | ✅ |
| Documentation-only in `ixora-infra` | ❌ |
| Application code only in `back_vibes` / `ixora-admin` | ❌ (App Platform git deploy handles) |

### Operator workflow

```bash
cd ixora-infra/opentofu/staging
# Secrets: untracked terraform.tfvars and/or TF_VAR_* (never commit)
tofu init
tofu plan    # review diff — apps, env, DB, domains
tofu apply   # pushes spec to DigitalOcean
```

### What apply updates

| Target | Effect |
| --- | --- |
| **`digitalocean_app.api`** | Service + worker spec, RUN_TIME env, GitHub source, domains |
| **`digitalocean_app.admin`** | Static site spec, BUILD_TIME env, GitHub source, domains |
| **Postgres / VPC / Spaces** | Infrastructure resources and firewall rules |

**Not automated by apply:** Laravel migrations, `APP_KEY` rotation, Firebase credential rotation, registrar DNS (see [`opentofu/staging/README.md`](../../../opentofu/staging/README.md)).

### Git Flow for infra changes

Infra changes follow the **same branch model**:

```
feature/infra-cors ──► develop ──► staging ──► (operator tofu apply on staging stack)
```

OpenTofu code on **`staging`** should match the env/apps that homologation expects when apply runs.

---

## App Platform deployment flow

Configured in [`app-api.tf`](../../../opentofu/staging/app-api.tf) and [`app-admin.tf`](../../../opentofu/staging/app-admin.tf).

### Common settings

| Setting | Value |
| --- | --- |
| **Branch** | `staging` (default `github_branch`) |
| **Deploy trigger** | `deploy_on_push = true` |
| **Region** | `tor` (App Platform Toronto) |
| **Sizing** | `basic-xxs`, **`instance_count = 1`** — no autoscaling |

### Laravel API app (`ixora-api-staging`)

```
GitHub push staging (back_vibes)
        │
        ▼
App Platform: Docker build (Dockerfile, port 8080)
        │
        ├──► service "api"     → FrankenPHP / Laravel HTTP
        │
        └──► worker "queue"    → php artisan queue:work --tries=3 --sleep=3 --timeout=90
             (same image, same RUN_TIME env, no HTTP ingress)
```

**Container start (API service):** `docker/frankenphp/docker-entrypoint.sh` validates `APP_KEY`, runs Laravel caches, starts FrankenPHP.

### Admin app (`ixora-admin-staging`)

```
GitHub push staging (ixora-admin)
        │
        ▼
App Platform: npm ci && npm run generate
        │
        ▼
Publish .output/public → static_site "admin" (HTTPS)
```

Admin deploy is a **static asset bundle** — no Laravel runtime, no queue, no VPC attachment.

### Deploy concurrency

Only **`back_vibes`** defines a GitHub Actions workflow today (legacy SSH). App Platform manages its own build queue per app. There is **no coordinated multi-app atomic deploy** — API and admin may finish builds at slightly different times after separate `staging` pushes.

---

## Environment variable propagation

Env flows from **OpenTofu variables** → **App Platform component scope** → **runtime behaviour**.

```
terraform.tfvars / TF_VAR_*  (secrets, never in git)
            │
            ▼
    OpenTofu app-api.tf / app-admin.tf
            │
            ├── RUN_TIME (api + queue) ──► Laravel reads env() at bootstrap
            │
            └── BUILD_TIME (admin only) ──► baked into Nuxt generate output
```

### Laravel API + queue worker (RUN_TIME)

Single source: `local.api_worker_runtime_env` in `app-api.tf`. Both **`api`** and **`queue`** receive **identical** RUN_TIME keys on deploy/apply.

| Category | Examples | Scope |
| --- | --- | --- |
| App identity | `APP_ENV=staging`, `APP_URL`, `APP_KEY` | RUN_TIME SECRET/GENERAL |
| Data | `DB_*` → `private_host`, `ixora_staging` | RUN_TIME |
| Queue | `QUEUE_CONNECTION=database` | RUN_TIME |
| Storage | `DO_SPACES_*`, CDN URL | RUN_TIME SECRET/GENERAL |
| Auth | `FIREBASE_*` discrete fields | RUN_TIME SECRET |
| CORS | `CORS_ALLOWED_ORIGINS` | RUN_TIME → `config/cors.php` |
| Mail | `MAIL_*`, `ADMIN_ACCESS_REVIEW_EMAIL` | RUN_TIME |

**Propagation rule:** changing a tfvars value and running **`tofu apply`** updates App Platform env → next container start picks up values. **No `.env` file in git** for staging.

### Admin (BUILD_TIME)

| Variable | Baked at generate |
| --- | --- |
| `NUXT_PUBLIC_API_BASE_URL` | Default `https://staging-api.ixora-app.app/api` |
| `NUXT_PUBLIC_FIREBASE_*` | Firebase web client config |

**Important:** admin API base URL is **compile-time**. Updating `nuxt_public_api_base_url` in OpenTofu requires **`tofu apply`** **and** an admin **rebuild** (push to `staging` or manual redeploy).

### Mobile (outside OpenTofu staging stack)

| Variable | Source |
| --- | --- |
| `VITE_API_BASE_URL` | `front_vibes/.env.staging` → `https://staging-api.ixora-app.app` |
| Firebase client config | Mobile repo env files |

Mobile env is **not** pushed by `ixora-infra` OpenTofu. Promote **`front_vibes` `staging`** branch in git and rebuild **`npm run build:staging`** when API URL or client config changes.

### Secrets boundaries

| Credential | Used by |
| --- | --- |
| `TF_VAR_do_token` | OpenTofu provider only |
| `spaces_access_id` / `spaces_secret_key` | OpenTofu Spaces bucket management |
| `api_do_spaces_key` / `api_do_spaces_secret` | Laravel runtime (App Platform SECRET) |
| `api_app_key`, `api_firebase_*` | Laravel runtime (App Platform SECRET) |

See [`staging-digitalocean.md`](staging-digitalocean.md#secrets-management-boundaries).

---

## Backend / admin / mobile coordination

Cross-cutting features span **multiple repos**. Staging homologation is valid only when **deployed combinations match**.

| Concern | Backend (`back_vibes`) | Admin (`ixora-admin`) | Mobile (`front_vibes`) | Infra (`ixora-infra`) |
| --- | --- | --- | --- | --- |
| **Deploy trigger** | Push `staging` | Push `staging` | Manual build | `tofu apply` |
| **API contract** | Routes, validation, uploads | Consumes `/api` | Consumes `/api` | CORS, env |
| **Auth** | Firebase JWT verify | Firebase web SDK | Firebase mobile SDK | `FIREBASE_*` / `NUXT_PUBLIC_*` |
| **Assets** | Writes Spaces, returns CDN URLs | Multipart via API | Read CDN URLs only | `DO_SPACES_*`, bucket |
| **Branch alignment** | Same homologation snapshot as peers | Same | Same git promotion | Same |

### Coordination checklist (cross-repo promotion)

- [ ] Feature merged to **`develop`** in every touched repo
- [ ] **`develop` → `staging`** with **`--no-ff`** in every touched repo
- [ ] **`tofu apply`** completed if OpenTofu changed on staging line
- [ ] App Platform API + admin deploys finished (DO dashboard or health probe)
- [ ] Mobile **`build:staging`** produced for QA when mobile changed or API contract changed

**Example — new admin origin for CORS:**

1. `ixora-infra`: add origin to `api_cors_allowed_origins` → merge to `develop` → `staging` → **`tofu apply`**
2. `ixora-admin`: UI change → merge to `develop` → `staging` → App Platform rebuild
3. Validate admin browser calls API without CORS errors

---

## Migration execution expectations

**Schema migrations are manual on App Platform staging today.**

| Fact | Detail |
| --- | --- |
| **Entrypoint** | API container runs `config:cache` / `route:cache` / `view:cache` — **does not** run `migrate` |
| **OpenTofu** | Provisions Postgres; **does not** execute Laravel migrations |
| **Legacy SSH workflow** | Ran `php artisan migrate --force` on Droplet — **not** the App Platform path |

### When migrations are required

Run migrations after a **`staging`** deploy (or before traffic validation) when the release includes **new/changed files in `database/migrations/`**.

### How operators run migrations (current)

Use a **one-off operational path** with credentials to **`ixora_staging`** on the managed cluster (exact mechanism is operator choice — DigitalOcean console, temporary local tunnel, or future run-job component). The pipeline **does not** define an automated migration job in OpenTofu today.

```bash
# Example — when shell has DB reachability and Laravel env loaded:
php artisan migrate --force
```

**Ordering recommendation:**

1. Deploy API code (`staging` push → App Platform build completes)
2. Run **`migrate --force`** before relying on new schema
3. Validate `/api/health` and feature flows

If migration runs **before** code deploy, ensure backward compatibility or accept brief mismatch — prefer **code + migrate + validate** in quick succession.

### Rollback interaction

If a bad migration shipped, **`php artisan migrate:rollback`** applies **only when** the migration’s `down()` is safe. Destructive or data migrations require a **forward fix** migration, not rollback alone.

---

## Rollback expectations

There is **no blue/green deploy**, **no Kubernetes rollout controller**, and **no multi-region traffic switch** in the current staging stack.

### Application rollback (App Platform)

| Approach | When to use |
| --- | --- |
| **Git revert on `staging`** | Preferred — revert bad merge commit(s), push `staging`, let App Platform redeploy prior code |
| **DigitalOcean deployment rollback** | Operational fallback — App Platform UI can redeploy a **previous successful deployment** of the same app (API or admin) without a git change |
| **Forward fix** | Hotfix on `feature/*` → `develop` → `staging` when revert is impractical |

Rollback redeploys **API and queue worker together** (same app spec). Admin rolls back **independently** (separate App Platform app).

### Infrastructure rollback

| Approach | Detail |
| --- | --- |
| **`tofu apply` previous spec** | Revert OpenTofu commit on `staging` branch, plan, apply |
| **State caution** | Some resource changes are destructive — review `tofu plan` carefully |

### Database rollback

- **Application rollback does not automatically undo migrations.**
- Use **`migrate:rollback`** only if the bad release ran migrations **and** `down()` is safe.
- Prefer **forward migrations** for data-fix scenarios.

### Legacy Droplet rollback

`back_vibes/docs/deploy-staging.md` documents `git reset --hard` on the server — **legacy only**, not App Platform procedure.

---

## Config cache expectations

### API service (every container start)

From `docker/frankenphp/docker-entrypoint.sh`:

| Step | Command | Purpose |
| --- | --- | --- |
| 1 | `package:discover` | Register packages |
| 2 | **`config:cache`** | Compile config from env (includes `CORS_ALLOWED_ORIGINS`, `DO_SPACES_*`) |
| 3 | **`route:cache`** | Compiled routes |
| 4 | **`view:cache`** | Compiled Blade views |
| 5 | `event:cache` | When available |

**Implication:** env var changes from OpenTofu require **new containers** (apply + redeploy/restart) before cached config reflects updates. The entrypoint rebuilds cache on each API start.

### Queue worker

Worker **`run_command`** is `php artisan queue:work …` on the **same image**. Worker process bootstraps Laravel without serving HTTP. Treat worker as sharing **RUN_TIME env** with API; queued jobs (`AdminAccessRequestedMail`, future `ShouldQueue` work) use the same DB and mail config.

### Admin static site

Nuxt **`generate`** produces static HTML/JS at **build time**. No Laravel config cache. Public config is embedded from **`NUXT_PUBLIC_*`** BUILD_TIME env.

### Local file cache/session

`CACHE_STORE=file` and `SESSION_DRIVER=file` on staging — **ephemeral per container**, not shared between API and queue. Not a deploy pipeline concern except: **new deploy clears local file cache** on that component.

---

## Queue worker deployment relationship

```
staging push (back_vibes)
        │
        ▼
   Single Docker build
        │
   ┌────┴────┐
   ▼         ▼
 api       queue
 HTTP      queue:work
   │         │
   │  enqueue│  dequeue
   └────┬────┘
        ▼
  PostgreSQL jobs table
  (QUEUE_CONNECTION=database)
```

| Property | Value |
| --- | --- |
| **Coupling** | Same GitHub repo, branch, image, and RUN_TIME env |
| **Deploy unit** | One App Platform app — both components update on the same source revision |
| **Independence** | Separate processes; worker has **no public URL** |
| **Failure mode** | If worker is down, HTTP API may still respond but **queued mail/jobs stall** in `jobs` |
| **Validation** | After deploy, confirm worker logs show `queue:work` processing (e.g. admin access request email) |

OpenTofu env changes to queue/mail/DB affect **both** components on next apply + container recycle.

---

## CDN / static asset relationship

Two distinct “static” paths exist in staging:

| Asset type | Delivery | Deploy mechanism |
| --- | --- | --- |
| **Admin UI** (HTML/JS/CSS) | App Platform static site → `staging-admin.ixora-app.app` | `ixora-admin` `staging` push → `npm run generate` |
| **Catalog media** (audio, images) | DigitalOcean Spaces **CDN** HTTPS URLs | **Not** redeployed with admin/API — bytes live in bucket; Laravel writes via API |

### Pipeline interaction

```
Admin/API deploy (git)          Media bytes (runtime API uploads)
        │                                    │
        ▼                                    ▼
  .output/public                      Spaces bucket (private ACL)
  on App Platform                           │
        │                                    ▼
        │                          CDN: *.tor1.cdn.digitaloceanspaces.com
        │                                    │
        └──────────► clients read URLs from API JSON ◄────────┘
```

- **Deploying admin or API does not invalidate CDN objects** — URLs in Postgres remain valid until content is replaced or deleted via Laravel.
- **New uploads** during homologation exercise the **API → Spaces → CDN URL** path ([`../storage/storage-strategy.md`](../storage/storage-strategy.md)).
- **Admin bundle** must not embed Spaces credentials; uploads go **through Laravel** ([ADR-002](../../decisions/ADR-002-laravel-only-storage-writes.md)).

---

## Staging validation expectations

Homologation sign-off combines **automated smoke checks** (where they exist) and **manual QA**.

### API health

```bash
curl -sf https://staging-api.ixora-app.app/api/health
# Expect JSON containing "status":"ok"
```

Legacy SSH workflow ran this from GitHub Actions after Droplet deploy. On App Platform, run manually or add CI **outside** this architecture doc’s scope.

### Post-deploy operator checks

- [ ] API **`/api/health`** returns OK
- [ ] Admin loads at `https://staging-admin.ixora-app.app`
- [ ] Firebase sign-in + **`POST /api/auth/sync`** succeeds
- [ ] Queue worker running (async mail if applicable)
- [ ] Migrations applied when release included schema changes
- [ ] CORS allows admin origin for write flows ([`upload-validation.md`](../../standards/upload-validation.md))

### Admin functional checklist

From [`admin-form-patterns.md`](../../standards/admin-form-patterns.md) — staging manual checklist:

- [ ] Sound create/edit with multipart → CDN URLs on entity
- [ ] Cover bundle create/edit → CDN URLs
- [ ] **422** oversize → friendly message
- [ ] **403** non-approved admin → access-request flow
- [ ] No direct Spaces uploads from browser

### Mobile staging checklist

Mobile requires **`npm run build:staging`** (or `dev:staging` for limited dev) against `VITE_API_BASE_URL=https://staging-api.ixora-app.app`.

From [`../storage/mobile-cdn-validation.md`](../storage/mobile-cdn-validation.md):

- [ ] Real device build (not live-reload-only dev)
- [ ] CDN audio **`file_url`** streams on device
- [ ] CDN thumbnails / artwork / player backgrounds render
- [ ] Offline download + airplane mode playback
- [ ] Preset import with CDN-backed assets

### Cross-repo validation

- [ ] Git **`staging`** tips aligned across repos for the feature under test
- [ ] OpenTofu apply completed when infra PR was part of the release
- [ ] Admin `NUXT_PUBLIC_API_BASE_URL` matches live API hostname

---

## Rules

1. **Never commit directly** to `develop`, `staging`, or `main` — all work flows through **`feature/*`** (or release/hotfix branches).
2. **Treat OpenTofu as infra source of truth** — do not hand-edit App Platform env in DO UI without reconciling `ixora-infra` (drift).
3. **`staging` is homologation**, not a feature branch — promote from **`develop`** with **`--no-ff`** only.
4. **Apply OpenTofu** when staging runtime config changes; **push `staging`** when application code changes.
5. **Run migrations explicitly** after schema releases — do not assume App Platform entrypoint migrates.
6. **Coordinate multi-repo promotions** before declaring staging QA complete.
7. **Rebuild mobile** staging artifacts when API URL or mobile code changes — git promotion alone does not update installed apps.
8. **No blue/green or K8s rollback fiction** — use git revert, DO deployment history, or forward fixes.
9. **CDN media survives app deploys** — validate uploads and URL reads independently from admin static deploys.

---

## Related documentation

| Document | Topic |
| --- | --- |
| [`staging-digitalocean.md`](staging-digitalocean.md) | Staging topology, CORS, secrets, runtime sizing |
| [`../../standards/git-flow.md`](../../standards/git-flow.md) | Branch policy, multi-repo coordination |
| [`../../../opentofu/staging/README.md`](../../../opentofu/staging/README.md) | OpenTofu prerequisites and apply runbook |
| [`../storage/storage-strategy.md`](../storage/storage-strategy.md) | Spaces CDN write/read policy |
| [`../storage/mobile-cdn-validation.md`](../storage/mobile-cdn-validation.md) | Mobile asset QA |
| [`../../standards/upload-validation.md`](../../standards/upload-validation.md) | Upload limits and CORS for admin |
| [`../../standards/admin-form-patterns.md`](../../standards/admin-form-patterns.md) | Admin staging checklist |
| [`../../decisions/ADR-001-firebase-auth-laravel-sync.md`](../../decisions/ADR-001-firebase-auth-laravel-sync.md) | Auth pipeline |
| [`../../decisions/ADR-002-laravel-only-storage-writes.md`](../../decisions/ADR-002-laravel-only-storage-writes.md) | CDN upload authority |
