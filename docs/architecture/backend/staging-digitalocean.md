# Staging backend — DigitalOcean architecture

**Status:** Active architecture (source of truth)  
**Scope:** **Staging only** — managed footprint on DigitalOcean (Toronto) for `back_vibes`, queue worker, PostgreSQL, Spaces CDN, Firebase integration, and `ixora-admin`  
**Applies to:** `ixora-infra/opentofu/staging`, `back_vibes`, `ixora-admin`, `front_vibes` (client targets)

> **Current staging only.** This document describes what **OpenTofu defines and App Platform runs today**. It does **not** describe production, Kubernetes, multi-region failover, or autoscaling policies that are not implemented.

**IaC source:** [`../../../opentofu/staging/`](../../../opentofu/staging/)

---

## Purpose

Document the **live staging topology**: how DigitalOcean App Platform hosts the Laravel API and queue worker, how Nuxt admin reaches the API, how PostgreSQL and Spaces fit in the VPC, how Firebase auth integrates at runtime, and where secrets and environment variables belong — so deploys, debugging, and cross-team work stay aligned with **actual infrastructure**, not legacy or planned systems.

---

## Context

### What runs on staging today

| Component | Platform | Region slug | Notes |
| --- | --- | --- | --- |
| **VPC** | `digitalocean_vpc.staging` | `tor1` | `ixora-staging-vpc-tor1` |
| **PostgreSQL** | Managed cluster in VPC | `tor1` | Single node (`db-s-1vcpu-1gb`), PG 16 |
| **Spaces bucket** | S3-compatible object storage | `tor1` | Private ACL; optional create via `manage_spaces_bucket` |
| **Laravel API (`api`)** | App Platform **service** | `tor` | FrankenPHP Docker, port **8080**, **`basic-xxs`**, **`instance_count = 1`** |
| **Queue worker (`queue`)** | App Platform **worker** | `tor` | Same image/env as API; **no HTTP ingress** |
| **Scheduler worker (`scheduler`)** | App Platform **worker** | `tor` | Same image/env as API/queue; `php artisan schedules:dispatch-loop` — dispatches due schedules every ~60 s |
| **Nuxt admin** | App Platform **static site** | `tor` | `npm ci && npm run generate` → `.output/public` |
| **Mobile app** | **Not** on App Platform | — | Build-time `VITE_API_BASE_URL` → staging API hostname |

**Live URLs (OpenTofu outputs / defaults):**

| Surface | Custom domain (default) |
| --- | --- |
| API | `https://staging-api.ixora-app.app` |
| Admin | `https://staging-admin.ixora-app.app` |
| Spaces CDN (example) | `https://ixora-buckets.tor1.cdn.digitaloceanspaces.com` |

There is **no Kubernetes**, **no multi-region replication**, and **no App Platform autoscaling** configured — each component uses a **fixed `instance_count` of 1**.

### Legacy note (not current architecture)

`back_vibes/.github/workflows/deploy-staging.yml` and `back_vibes/docs/deploy-staging.md` describe an **older Droplet + SSH** deploy path. **Current staging IaC is App Platform + OpenTofu** (`opentofu/staging/`). Treat Droplet docs as historical unless explicitly revived.

---

## Current Decision

1. **Staging infrastructure is declarative** in OpenTofu under `ixora-infra/opentofu/staging/`.
2. **Laravel runs as one App Platform app** with three components: HTTP **`api`** service, background **`queue`** worker, and **`scheduler`** worker — **same Docker image and RUN_TIME env**.
3. **PostgreSQL is VPC-private**; App Platform connects via **`private_host`**, not a public DB endpoint.
4. **Spaces writes are Laravel-only** ([ADR-002](../../decisions/ADR-002-laravel-only-storage-writes.md)); clients read **public CDN HTTPS URLs** from API JSON.
5. **Firebase** verifies JWTs on the API via discrete **`FIREBASE_*`** secrets; admin embeds **public** `NUXT_PUBLIC_FIREBASE_*` at **build time**.
6. **CORS** is an explicit comma-separated allowlist — **no wildcard**, **`supports_credentials: false`** (Bearer tokens, not cookies).
7. **Deploys** to staging App Platform apps trigger on **Git push to the `staging` branch** (`deploy_on_push = true`).

---

## Architecture overview

```
                         ┌─────────────────────────────────────────────────────────────┐
                         │              DigitalOcean — Toronto (tor1 / tor)               │
                         │                                                              │
  Browser / Capacitor    │   ┌──────────────────────┐      ┌─────────────────────────┐ │
  ───────────────────────┼──►│ App: ixora-admin-    │      │ App: ixora-api-staging   │ │
  HTTPS                  │   │      staging           │      │  (VPC-attached)          │ │
                         │   │  static_site: admin  │      │                          │ │
                         │   │  BUILD_TIME env:     │      │  service: api :8080      │ │
                         │   │   NUXT_PUBLIC_*      │      │    FrankenPHP / Laravel  │ │
                         │   └──────────┬───────────┘      │  worker: queue           │ │
                         │              │                   │    queue:work (no HTTP)   │ │
                         │              │  HTTPS + CORS     │  worker: scheduler        │ │
                         │              └──────────────────►│    dispatch-loop ~60s     │ │
                         │                                  └───────┬─────────┬─────────┘ │
                         │              ┌───────────────────────────┘         │           │ │
                         │              │  private_host + SSL                 │           │ │
                         │              ▼                                     │ S3 API    │ │
                         │   ┌──────────────────────┐                       │ DO_SPACES │ │
                         │   │ Managed PostgreSQL     │◄──────────────────────┘           │ │
                         │   │ DB: ixora_staging      │                                   │ │
                         │   │ User: ixora_app        │                                   │ │
                         │   │ Firewall: VPC CIDR only│                                   │ │
                         │   └──────────────────────┘                                   │ │
                         │                                                                │ │
                         │   ┌──────────────────────┐         CDN read (HTTPS)            │ │
                         │   │ Spaces (private ACL) │◄───────────────────────────────────┘ │
                         │   │ ixora-buckets @ tor1 │                                     │
                         │   └──────────────────────┘                                     │
                         └─────────────────────────────────────────────────────────────┘

  Firebase Auth (Google / email)          Clients never hold Spaces keys
         │                                Admin/mobile upload via API only
         ▼
  JWT ──► POST /api/auth/sync ──► Laravel VerifyFirebaseIdToken (ADR-001)

  Scheduler worker (long-running, ~60-second loop):
  worker: scheduler ──► php artisan schedules:dispatch-loop
                    │     └── every 60s: php artisan schedules:dispatch-due
                    │ (same VPC / DB_HOST / RUN_TIME env as api + queue)
                    ▼
              schedule_executions (idempotent — ADR-010)
```

---

## OpenTofu-managed infrastructure

Stack path: **`ixora-infra/opentofu/staging/`**

| File | Resource |
| --- | --- |
| `vpc.tf` | Staging VPC |
| `database.tf` | Postgres cluster, `ixora_staging` DB, `ixora_app` user, VPC firewall |
| `spaces.tf` | Optional private bucket |
| `app-api.tf` | Laravel App Platform app (service + workers: queue + scheduler) |
| `app-admin.tf` | Nuxt static site app |
| `domains.tf` | DNS notes (manual registrar steps) |
| `outputs.tf` | Live URLs, private DB host, bucket/CDN patterns |

**Apply workflow:** copy `terraform.tfvars.example` → untracked `terraform.tfvars`, set `TF_VAR_*` secrets, then `tofu init && tofu plan && tofu apply`. See [`opentofu/staging/README.md`](../../../opentofu/staging/README.md).

**Not automated by IaC (manual / ops):**

- First-time GitHub ↔ DigitalOcean App Platform authorization
- Custom domain DNS at registrar (unless adapted from `domains.tf`)
- SSL validation after DNS propagates
- Laravel **`php artisan migrate`** on new releases
- `APP_KEY` / Spaces key / Firebase credential rotation
- Spaces CDN enablement beyond bucket + hostname pattern output

---

## Runtime separation

### Two App Platform applications

| App | Component type | Ingress | Build |
| --- | --- | --- | --- |
| **`ixora-api-staging`** | `service` **`api`** | Public HTTP → FrankenPHP :8080 | Docker (`back_vibes/Dockerfile`) |
| **`ixora-api-staging`** | `worker` **`queue`** | **None** (not routable) | Same Docker image |
| **`ixora-api-staging`** | `worker` **`scheduler`** | **None** (not routable) | Same Docker image |
| **`ixora-admin-staging`** | `static_site` **`admin`** | Public HTTPS static files | `npm ci && npm run generate` |

The **API app attaches to the VPC** so **`api`**, **`queue`**, and **`scheduler`** reach Postgres on **`private_host`**. The **admin static site does not join the VPC** — it only needs outbound HTTPS to the API and Firebase client endpoints.

### API container lifecycle

FrankenPHP entrypoint (`docker/frankenphp/docker-entrypoint.sh`):

1. Requires **`APP_KEY`** at runtime (exits if missing)
2. Runs `config:cache`, `route:cache`, `view:cache` (and `event:cache` when available)
3. Starts **`frankenphp run`** on port **8080**

### Ephemeral local state (staging trade-off)

Both **`api`** and **`queue`** set:

| Variable | Value | Implication |
| --- | --- | --- |
| `CACHE_STORE` | `file` | Cache files on **each component’s local disk** — **not shared** between web and worker |
| `SESSION_DRIVER` | `file` | Session files likewise **not shared** across replicas (only one instance each today) |

Postgres **`cache` table** is intentionally avoided on staging (ACL / migration ownership). There is **no Redis** in this stack.

---

## Queue / runtime relationship

```
┌─────────────────────────────────────────────────────────────────┐
│  App Platform app: ixora-api-staging (single GitHub repo/branch) │
│                                                                  │
│   push staging ──► build same Docker image ──► deploy both:      │
│                                                                  │
│   ┌─────────────────────┐         ┌─────────────────────────┐   │
│   │  service: api       │         │  worker: queue          │   │
│   │  HTTP requests      │         │  php artisan queue:work │   │
│   │  dispatches jobs    │         │  --queue=push,          │   │
│   │  to `jobs` table    │────────►│  smart-home,default     │   │
│   │                     │         │  --tries=3 --sleep=3    │   │
│   │                     │         │  --timeout=90           │   │
│   └─────────────────────┘  DB     └─────────────────────────┘   │
│              │                              │                    │
│              └──────────┬───────────────────┘                    │
│                         ▼                                        │
│              QUEUE_CONNECTION=database                           │
│              PostgreSQL `jobs` / `failed_jobs`                   │
└─────────────────────────────────────────────────────────────────┘
```

| Topic | Staging behaviour |
| --- | --- |
| **Queue driver** | `database` (`QUEUE_CONNECTION=database`) |
| **Worker command** | `php artisan queue:work --queue=push,smart-home,default --tries=3 --sleep=3 --timeout=90` |
| **Named queues** | `push` (FCM delivery), `smart-home` (device actions), `default` (mail and other jobs) |
| **Push provider** | `PUSH_PROVIDER=fcm` (explicit in `local.api_worker_runtime_env`) |
| **Shared config** | `local.api_worker_runtime_env` in `app-api.tf` — **identical RUN_TIME env** on `api`, `queue`, and `scheduler` |
| **Known queued mail** | `AdminAccessRequestedMail` implements `ShouldQueue` |
| **Scaling** | **`instance_count = 1`** for both service and worker — no horizontal autoscaling |

**Important:** HTTP handlers enqueue work; the **worker process** must be healthy for async mail, Smart Home actions, and push notifications to drain. API and worker deploy together on the same branch push but run as **separate processes/containers**.

---

## Push Notifications runtime validation

Use this checklist after OpenTofu apply (or any worker/env change) to confirm staging can deliver real FCM push.

- [ ] Queue worker `run_command` includes `--queue=push,smart-home,default`
- [ ] `PUSH_PROVIDER=fcm` present on worker `queue` (and shared with `api`)
- [ ] `FIREBASE_PROJECT_ID` present (SECRET)
- [ ] `FIREBASE_PRIVATE_KEY` present (SECRET)
- [ ] `FIREBASE_CLIENT_EMAIL` present (SECRET)
- [ ] Queue worker component **`queue`** status **Running** (no crash loop)

Connect to a running API or `queue` worker console:

```bash
php artisan tinker --execute="echo config('push_notifications.provider');"
# Expected: fcm

php artisan queue:monitor push,smart-home,default
```

See also [`qa/push-notifications-e2e/scripts/staging-push-send.tinker.md`](../../../../qa/push-notifications-e2e/scripts/staging-push-send.tinker.md) for a manual send harness after the worker is healthy.

---

## Scheduler worker

A dedicated **App Platform worker** (`scheduler`) runs `php artisan schedules:dispatch-loop` — a long-running process that calls `schedules:dispatch-due` approximately every 60 seconds.

**Operational runbook:** [Scheduler + Smart Home operational checklist](../../operations/scheduler-smart-home-operational-checklist.md) — failure matrix, log catalog, deploy/recovery checklists.

**Why a worker instead of a DO Scheduled Job:**

| Reason | Detail |
| --- | --- |
| **Provider gap** | `digitalocean/digitalocean` v2.87.0 does not support `SCHEDULED` job kind / `cron_expression` ([issue #1529](https://github.com/digitalocean/terraform-provider-digitalocean/issues/1529)) |
| **Platform minimum** | DO App Platform enforces a 15-minute minimum cadence for scheduled jobs; MVP requires ~60-second dispatch granularity |
| **Native Terraform support** | `worker` is fully supported by the current provider — no manual `doctl` post-steps or `lifecycle.ignore_changes` workarounds needed |

| Property | Value |
| --- | --- |
| **Component name** | `scheduler` |
| **Component type** | App Platform `worker` (long-running process, no HTTP ingress) |
| **Run command** | `php artisan schedules:dispatch-loop` |
| **Dispatch cadence** | ~60 seconds (configurable via `--interval`; default 60 s) |
| **Inner command** | `php artisan schedules:dispatch-due` (called per iteration) |
| **Image / source** | Same Docker image as `api` / `queue` — `back_vibes/Dockerfile`, `staging` branch |
| **Environment** | `local.api_worker_runtime_env` — identical RUN_TIME env as `api` and `queue` |
| **Instance size** | `basic-xxs` |
| **Instance count** | `1` |
| **Purpose** | Evaluate `schedules WHERE is_enabled = true AND next_run_at <= now() UTC`, insert idempotent `schedule_executions` rows, advance `next_run_at` — [ADR-010](../../decisions/ADR-010-scheduler-idempotency-occurrence-key.md) |
| **Idempotency** | Loop restart or brief overlap: safe — unique `(schedule_id, occurrence_key)` index deduplicates any double-dispatch |
| **Shutdown** | SIGTERM → sets `$shouldStop = true` → loop exits after current tick completes (graceful) |

**Spec reference:** [`specs/scheduler/mvp/spec.md`](../../specs/scheduler/mvp/spec.md) § Dispatcher worker strategy.  
**IaC source:** `worker` block named `scheduler` in `app-api.tf` inside `digitalocean_app.api`.

### Scheduler worker logs

- **DigitalOcean App Platform console** → `ixora-api-staging` → component **`scheduler`** → Runtime Logs
- `LOG_CHANNEL=stderr` — logs appear in the App Platform component log stream
- Each tick emits: `[schedules:dispatch-loop] tick #N @ <ISO8601>` + dispatch-due summary

### Scheduler worker runbook

#### Check the worker is running

1. Open the [DigitalOcean App Platform dashboard](https://cloud.digitalocean.com/apps) → `ixora-api-staging`
2. Navigate to component **`scheduler`** → **Runtime Logs**
3. Confirm `[schedules:dispatch-loop] starting` appears after the last deploy
4. Confirm `[schedules:dispatch-loop] tick #N` lines appear approximately every 60 seconds

#### Manually validate the dispatcher

1. Create a schedule row with `next_run_at` in the past (via API or direct DB update):

   ```sql
   UPDATE schedules
   SET next_run_at = now() - interval '5 minutes'
   WHERE id = <your_schedule_id>;
   ```

2. Wait up to 60 seconds for the next loop tick

3. Verify a `schedule_executions` row was inserted:

   ```sql
   SELECT * FROM schedule_executions
   WHERE schedule_id = <your_schedule_id>
   ORDER BY executed_at DESC LIMIT 5;
   ```

4. Verify `schedules.next_run_at` advanced to the next occurrence:

   ```sql
   SELECT id, next_run_at, last_run_at, is_enabled
   FROM schedules WHERE id = <your_schedule_id>;
   ```

5. For `once` schedules: confirm `next_run_at = NULL` and `is_enabled = false` after dispatch

#### Run a bounded dispatch test (one iteration)

Connect to a running API or scheduler container console and run:

```bash
php artisan schedules:dispatch-loop --once        # single tick, then exit
php artisan schedules:dispatch-due --dry-run      # inspect without writing
php artisan schedules:dispatch-due                # live dispatch
```

---

## PostgreSQL

| Setting | Value |
| --- | --- |
| Cluster | `ixora-staging-postgres` (default var) |
| Engine | PostgreSQL **16** |
| Size | **`db-s-1vcpu-1gb`**, **`node_count = 1`** |
| Database name | **`ixora_staging`** (`digitalocean_database_db.app`) |
| App user | **`ixora_app`** |
| Connection from apps | **`DB_HOST`** = cluster **`private_host`**, **`DB_SSLMODE=require`** |
| Firewall | **`digitalocean_database_firewall`**: allow **staging VPC CIDR only** (`ip_addr` rule) |

Apps **must** use **`private_host`**. The firewall rule alone does not expose Postgres publicly; it restricts trusted sources to the VPC.

---

## Spaces CDN and asset flow

Policy detail: [`../storage/storage-strategy.md`](../storage/storage-strategy.md), [ADR-002](../../decisions/ADR-002-laravel-only-storage-writes.md), [ADR-006](../../decisions/ADR-006-no-direct-mobile-uploads.md).

### Write path (admin → API → Spaces)

```
ixora-admin (browser)
    │  Firebase sign-in → Bearer JWT
    │  multipart upload to Laravel routes
    ▼
staging-api.ixora-app.app (Laravel)
    │  DO_SPACES_KEY / DO_SPACES_SECRET (server-only)
    │  S3 SDK → origin: https://{bucket}.tor1.digitaloceanspaces.com
    │  persists full CDN URL on entity row
    ▼
PostgreSQL (file_url, thumbnail_url, …)
```

### Read path (CDN → clients)

```
Admin / Mobile
    │  GET JSON from API (CDN URL strings)
    ▼
https://{bucket}.tor1.cdn.digitaloceanspaces.com/…
    │  img src, CSS backgrounds, native audio stream, CapacitorHttp offline
    ▼
Public HTTPS asset bytes (no Spaces credentials on client)
```

| Env (Laravel RUN_TIME) | Role |
| --- | --- |
| `DO_SPACES_BUCKET` | Bucket name (default `ixora-buckets`) |
| `DO_SPACES_REGION` | `tor1` |
| `DO_SPACES_ENDPOINT` | S3 origin base URL |
| `DO_SPACES_CDN_URL` | CDN base used when building persisted URLs |
| `DO_SPACES_KEY` / `DO_SPACES_SECRET` | **Runtime** Laravel credentials (**SECRET**) |

OpenTofu **`spaces_access_id` / `spaces_secret_key`** are for **bucket management** during `tofu apply` — **not** interchangeable with Laravel’s **`api_do_spaces_*`** runtime keys.

Mobile CDN validation expectations: [`../storage/mobile-cdn-validation.md`](../storage/mobile-cdn-validation.md).

---

## Firebase integration

Architecture decision: [ADR-001](../../decisions/ADR-001-firebase-auth-laravel-sync.md).

| Layer | Responsibility | Staging config surface |
| --- | --- | --- |
| **Firebase Auth** | Sign-in (Google, email/password), JWT issuance | Client SDK config |
| **Laravel API** | Verify JWT, `POST /api/auth/sync`, policies | Discrete **`FIREBASE_*`** env vars (**SECRET** on App Platform) |
| **PostgreSQL** | `users.firebase_uid`, domain ownership | — |

**Admin (`ixora-admin`):** `NUXT_PUBLIC_FIREBASE_*` and `NUXT_PUBLIC_API_BASE_URL` are injected at **`BUILD_TIME`** when App Platform runs `npm run generate`. Default API base: `https://staging-api.ixora-app.app/api`.

**Mobile (`front_vibes`):** not deployed by this stack; staging builds use `VITE_API_BASE_URL=https://staging-api.ixora-app.app` (see `.env.staging`). Firebase client config is compile-time in the mobile repo.

**API requirement:** `api_firebase_project_id`, `api_firebase_private_key`, and `api_firebase_client_email` must be set (via tfvars / `TF_VAR_*`) or Firebase discrete env block is omitted and token verification will fail at runtime.

---

## staging-admin → staging-api flow

```
┌─────────────────────┐
│ staging-admin       │
│ .ixora-app.app      │
│ (static Nuxt)       │
└─────────┬───────────┘
          │ 1. User signs in via Firebase (browser SDK)
          │ 2. NUXT_PUBLIC_API_BASE_URL → https://staging-api…/api
          │ 3. POST /api/auth/sync  Authorization: Bearer <Firebase JWT>
          ▼
┌─────────────────────┐
│ staging-api         │
│ .ixora-app.app      │
│ CORS: admin origin  │
│ + localhost dev     │
└─────────┬───────────┘
          │ 4. Subsequent /api/* with same Bearer token
          │ 5. Uploads: multipart → Laravel → Spaces
          ▼
     JSON with CDN URLs → admin renders assets
```

Local admin dev (`localhost:3000` / `5173`) is included in the **default CORS allowlist** when `api_cors_allowed_origins` is empty.

---

## CORS topology

**Configured in OpenTofu** → **`CORS_ALLOWED_ORIGINS`** (GENERAL, RUN_TIME) → Laravel **`config/cors.php`**.

| Default (when var empty) | Origin |
| --- | --- |
| Admin production | `https://{admin_domain}` → `https://staging-admin.ixora-app.app` |
| Local Nuxt dev | `http://localhost:3000` |
| Local Vite dev | `http://localhost:5173` |

**Laravel rules:**

- Comma-separated list; trim; drop empty entries
- **Wildcard `*` in env is ignored** (never allowed via env strings)
- **`supports_credentials: false`** — Firebase uses **`Authorization: Bearer`**, not cookies
- Paths: `api/*`, `sanctum/csrf-cookie`

**Mobile note:** Capacitor native HTTP/audio paths **do not** rely on Laravel CORS for asset CDN hosts. Browser dev mode may show CORS differences vs device builds — see mobile CDN doc.

Override all defaults by setting **`api_cors_allowed_origins`** in untracked tfvars.

---

## Environment variables

### Shared Laravel RUN_TIME (`api` + `queue` + `scheduler`)

Source: `local.api_worker_runtime_env` in [`app-api.tf`](../../../opentofu/staging/app-api.tf).

| Key | Type | Typical value / notes |
| --- | --- | --- |
| `APP_NAME` | GENERAL | `Ixora` |
| `APP_ENV` | GENERAL | `staging` |
| `APP_DEBUG` | GENERAL | `false` |
| `APP_URL` | GENERAL | `https://{api_domain}` |
| `APP_KEY` | SECRET | Laravel encryption key (`api_app_key`) |
| `CORS_ALLOWED_ORIGINS` | GENERAL | See CORS section |
| `LOG_CHANNEL` | GENERAL | `stderr` |
| `QUEUE_CONNECTION` | GENERAL | `database` |
| `CACHE_STORE` | GENERAL | `file` |
| `SESSION_DRIVER` | GENERAL | `file` |
| `DB_*` | GENERAL / SECRET | `pgsql`, `private_host`, `ixora_staging`, `ixora_app` + password |
| `DO_SPACES_*` | GENERAL / SECRET | Bucket, region, endpoint, CDN URL, runtime keys |
| `FIREBASE_*` | SECRET | Discrete Admin SDK fields when configured |
| `MAIL_PASSWORD` | SECRET | Optional SMTP |
| `ADMIN_ACCESS_REVIEW_EMAIL` | GENERAL | Admin access request routing |
| `api_env_general` | GENERAL | Extra map from tfvars |
| `api_secrets_extra` | SECRET | Extra secret map from tfvars |

App Platform **`scope = RUN_TIME`** for API components; admin uses **`BUILD_TIME`** for `NUXT_PUBLIC_*` only.

### Nuxt admin BUILD_TIME

| Key | Purpose |
| --- | --- |
| `NUXT_PUBLIC_API_BASE_URL` | API base including `/api` suffix |
| `NUXT_PUBLIC_FIREBASE_*` | Firebase web client configuration |

### Mobile (outside App Platform)

| Key | Purpose |
| --- | --- |
| `VITE_API_BASE_URL` | Staging API host (no `/api` suffix in mobile env file) |
| Firebase vars | Mobile Firebase SDK (repo env files, not OpenTofu) |

---

## Secrets management boundaries

| Secret / credential | Where it lives | Must NOT |
| --- | --- | --- |
| **`do_token`** | Operator CI / untracked tfvars / `TF_VAR_do_token` | Commit to git |
| **OpenTofu Spaces keys** (`spaces_access_id`, `spaces_secret_key`) | OpenTofu provider only (bucket CRUD) | Ship to Laravel env as substitute for `api_do_spaces_*` without intent |
| **Laravel Spaces keys** (`api_do_spaces_key`, `api_do_spaces_secret`) | App Platform SECRET on `api` + `queue` | Expose to admin, mobile, or docs |
| **`api_app_key`** | App Platform SECRET | Regenerate without coordinated redeploy |
| **`FIREBASE_*` (API)** | App Platform SECRET | Embed in client bundles |
| **`NUXT_PUBLIC_FIREBASE_*`** | Admin BUILD_TIME (public client keys) | Treat as server secrets — still avoid committing real project values in examples |
| **DB password** | OpenTofu-managed user password → App SECRET | Log in application code |
| **`terraform.tfvars`** | Local / CI secret store | Commit (gitignored by convention) |

**Principle:** OpenTofu **provisions** infrastructure and **injects** runtime env into App Platform. Application repos hold **no** staging secrets. [`storage-strategy.md`](../storage/storage-strategy.md) reinforces **no secrets in git**.

---

## Deploy expectations

### What triggers a deploy

| Repository | Branch (default) | App Platform behaviour |
| --- | --- | --- |
| `github_repo_api` (`back_vibes`) | `staging` | Rebuild Docker image → redeploy **`api`** service **and** **`queue`** worker |
| `github_repo_admin` (`ixora-admin`) | `staging` | Run static build → publish `.output/public` |

`deploy_on_push = true` on all GitHub sources in `app-api.tf` / `app-admin.tf`.

### Operator checklist after infra or app changes

1. **`tofu plan` / `tofu apply`** when changing VPC, DB, domains, or env maps in OpenTofu
2. **Push to `staging` branch** (or merge PR into `staging`) for application releases
3. **Run migrations** against `ixora_staging` when schema changes ship (not automatic in IaC)
4. **Verify** `api` health, `queue` logs processing jobs, `scheduler` worker logs show `schedules:dispatch-loop` ticks approximately every 60 seconds, admin loads with correct `NUXT_PUBLIC_API_BASE_URL`
5. **Confirm DNS** for custom domains if newly added

### Sizing (fixed — not autoscaling)

| Component | Size slug | Count |
| --- | --- | --- |
| API service | `basic-xxs` | **1** |
| Queue worker | `basic-xxs` | **1** |
| Scheduler worker | `basic-xxs` | **1** |
| Postgres | `db-s-1vcpu-1gb` | **1** node |

No HPA, no multi-instance API pool, no read replicas in this stack.

---

## Rules

1. **Treat OpenTofu + App Platform as staging source of truth** — not Droplet SSH workflows.
2. **Never commit** `terraform.tfvars`, runtime Spaces keys, `APP_KEY`, or Firebase private keys.
3. **API, queue, and scheduler share env** — changing DB, queue, or Firebase config affects **all three** worker/service components on next deploy.
4. **Use `private_host` for Postgres** from App Platform; do not open the DB firewall to `0.0.0.0/0`.
5. **CORS changes** require updating `api_cors_allowed_origins` (or defaults via `admin_domain`) and redeploying the API app.
6. **Admin API URL is build-time** — changing `nuxt_public_api_base_url` requires an **admin rebuild**, not just API env change.
7. **Asset uploads go through Laravel only** — admin and mobile never receive Spaces write credentials.
8. **Do not assume shared file cache** between `api` and `queue` on staging.

---

## Related documentation

| Document | Topic |
| --- | --- |
| [`../../../opentofu/staging/README.md`](../../../opentofu/staging/README.md) | OpenTofu usage, prerequisites, cost notes |
| [`../storage/storage-strategy.md`](../storage/storage-strategy.md) | Spaces layout, CDN URL policy |
| [`../storage/mobile-cdn-validation.md`](../storage/mobile-cdn-validation.md) | Mobile asset URL validation |
| [`../../decisions/ADR-001-firebase-auth-laravel-sync.md`](../../decisions/ADR-001-firebase-auth-laravel-sync.md) | Firebase + Laravel auth |
| [`../../decisions/ADR-002-laravel-only-storage-writes.md`](../../decisions/ADR-002-laravel-only-storage-writes.md) | Laravel-only Spaces writes |
| [`../../decisions/ADR-006-no-direct-mobile-uploads.md`](../../decisions/ADR-006-no-direct-mobile-uploads.md) | Mobile read-only storage |
| [`../../standards/git-flow.md`](../../standards/git-flow.md) | `staging` branch role in Git Flow |
