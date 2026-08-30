# Production Readiness Review — Phase 11

**Status:** Complete — decision documented below
**Type:** Cross-repo readiness assessment + go/no-go decision
**Repo:** `ixora-infra` (findings span `back_vibes` and `ixora-infra`)
**Established:** Phase 11 (current roadmap numbering)
**Date:** 2026-08-30
**Prerequisite:** Phase 9 Alerting Strategy, Phase 9.5 Incident Response, Phase 10 Performance Validation — all complete

> **Scope note:** `front_vibes` and `ixora-admin` were not investigated in depth for this review — the highest-risk, highest-uncertainty areas for a backend-facing production launch are in `back_vibes` and `ixora-infra`, and that's where this review concentrated. A follow-up pass on the client apps' own release readiness (app store submission state, crash reporting, client-side security) is out of scope here and should be a separate, explicit check before a real launch.

---

## 1. Decision: **NO-GO**

Ixora is **not ready for a production launch today**. This is not a marginal call — the single largest finding of this review is that **no production infrastructure exists as code at all** (§7). Every other gap in this review (backups, rate limiting, dead CI) is a fixable problem on infrastructure that already exists; this one means there is currently no environment to evaluate "production readiness" against in the first place.

This is not a negative verdict on the work done so far. Phases 1 through 10 delivered a genuinely solid, tested foundation — real observability, real alerting with a real incident response process, real (if conservative) load testing with no bottlenecks found, and secrets management that checked out clean under scrutiny. The gap is specifically in the step this platform hasn't taken yet: standing up a production environment distinct from staging, and closing the handful of concrete gaps below before pointing real users at it.

**What "Go" requires** (see §8 for the full list): a `production/` OpenTofu environment with its own sizing decisions, real backups (not just a design doc), rate limiting on public endpoints, and the dead CI workflow either fixed or removed.

---

## 2. Method

This review was compiled from two sources:
1. A dedicated read-only investigation (2026-08-30) across `back_vibes` and `ixora-infra` covering backups, secrets, migrations, rollback, security posture, open known-limitation/tech-debt items, and disaster-recovery/single-point-of-failure exposure. No files were modified, no destructive commands were run, no staging infrastructure was touched.
2. This session's own direct, hands-on work on Phase 9 (Alerting Strategy), Phase 9.5 (Incident Response), and Phase 10 (Performance Validation) — summarized in §3, not re-investigated.

Every finding below that came from the dedicated investigation was independently re-verified before being included in this document (see inline "(verified)" notes) — this review does not simply forward an unverified report.

---

## 3. Already covered this session (not re-investigated here)

| Area | Status | Evidence |
| --- | --- | --- |
| Alerting | **Real, tested** | 7 Level-1 alert rules live on staging, real end-to-end proof (genuine `NoData → Pending → Alerting` transition, real Mailtrap-delivered email), routing/grouping bug found and fixed (KL-IR-6) | `alerting-strategy.md`, `incident-response-policy.md` |
| Incident response | **Real, tested** | Formal process document + roles + evidence template + postmortem checklist, exercised end-to-end against a real drill (`INC-20260829-001`) | `incident-response-policy.md`, `docs/operations/incidents/` |
| Performance/load | **Tested, no bottleneck found** | 4 real runs (read/write × smoke/baseline) against real staging, all passed with wide margin; formally accepted as "no bottleneck at conservative levels" given the environment's own sizing | `qa/load-testing/README.md` §Formal conclusion |

These are not reopened by this review. They inform §6 (some of their own known limitations feed the open-risk list) but are otherwise closed.

---

## 4. Findings by area

### 4.1 Backups — **Partial gap** (narrower than first assessed — see below)

- `backup-strategy.md`'s own header states: **"Status: Architecture only — no backups implemented."** No cron jobs, no scripts, no automation exist anywhere in the repo for the observability stack (Prometheus/Loki/Tempo/Grafana volumes).
- `opentofu/staging/database.tf` has no explicit backup configuration for the managed Postgres cluster — but this was live-verified 2026-08-30 via `doctl databases backups <cluster-id>`: **8 consecutive daily automatic backups exist**, one per day from 2026-08-22 through 2026-08-29 (~19:15 UTC each), confirming DigitalOcean's managed-Postgres automatic backup default is genuinely active. This was an unverified assumption when this review was first written; it is now a confirmed fact, not a gap. Not yet documented in-repo (nothing references this in `database.tf` or `backup-strategy.md`), and no restore has ever been tested.
- No restore has ever been tested or documented. The strategy doc's own "Future implementation phases" table lists a restore drill as a future, production-only item.

### 4.2 Secrets management — **Solid**

- No real secrets found committed anywhere (`git ls-files` / `git status --ignored` confirm `.tfstate`/`.tfvars` are properly excluded; only `.example` templates are tracked). One placeholder-only `FIREBASE_PRIVATE_KEY="...."` in `back_vibes/.env.example:97` is not a real key.
- 17 variables marked `sensitive = true` in `opentofu/staging/variables.tf`.
- The OTEL_* env var gap found during Phase 8.9 (dashboard-only config, not IaC-tracked — the incident that caused the TD-5 fix's `tofu apply` to silently wipe telemetry) is confirmed **fixed**: `terraform.tfvars.example` now documents `OTEL_EXPORTER_OTLP_HEADERS` explicitly as secret, alongside the rest of the OTEL config.

### 4.3 Migrations — **Documented, not automated**

- 31 migrations in `back_vibes/database/migrations/`. Only one is genuinely destructive (`2026_06_14_000002_harden_devices_table.php`), and it does it safely: nullable-first, backfill, an explicit `RuntimeException` guard against orphan rows before hardening constraints, full symmetric `down()`.
- `deploy-pipeline.md` §"Migration execution expectations" documents a real, specific manual procedure (deploy code → `migrate --force` → validate) and states migrations are a deliberate manual operator step, not automatic on deploy.
- **Gap:** this relies entirely on the operator remembering to run it — no checklist enforcement, no automation. Moot for an actual production environment until one exists (§4.7).

### 4.4 Rollback procedure — **Documented, but a real dead-CI finding surfaced**

- `deploy-pipeline.md` §"Rollback expectations" documents three real options: git revert on `staging` (preferred), DigitalOcean's native "redeploy a previous successful deployment" feature, or a forward-fix migration. No blue/green or multi-region cutover exists, and this is stated explicitly rather than silently absent.
- **New finding, independently verified:** `back_vibes/.github/workflows/deploy-staging.yml` — a legacy SSH-based deploy workflow — is still `active` in GitHub Actions, still triggers on every push to `staging`, and still attempts `php artisan migrate --force` over SSH to a Droplet. **Confirmed via `gh run list`: the 5 most recent runs (2026-08-03 through 2026-08-25) all failed**, consistently at ~37-40 seconds each — almost certainly at the SSH connection step, since the target Droplet from the pre-App-Platform deploy path most likely no longer exists. `deploy-pipeline.md` itself already flags this exact scenario as tech debt ("if both SSH workflow and App Platform remain connected to the same repo") — and they still are, three weeks later, with nobody having noticed or disabled it.
  - This is not currently causing harm (the App Platform deploy path is unaffected, and it's not silently double-migrating), but it's dead, consistently-red CI that erodes trust in CI signal generally, and it should be disabled or fixed regardless of the production timeline.

### 4.5 Security posture (back_vibes) — **Real gap: no rate limiting**

- **No rate limiting exists anywhere.** Confirmed by grepping `routes/api.php`, every middleware in `app/Http/Middleware/`, `bootstrap/app.php`, and all service providers for `throttle`/`RateLimiter::for`: zero hits. `/api/auth/firebase`, `/api/auth/sync`, and every other API route have no request-rate protection.
- CORS (`config/cors.php`) is environment-variable-driven, not a hardcoded wildcard, and `supports_credentials` is explicitly `false` — reasonable as configured.
- Staging's real `APP_DEBUG` is confirmed `false` (`staging-digitalocean.md`). No document yet states this as a **production** requirement specifically — moot today since no production environment exists, but worth a checklist line once one does.

### 4.6 Disaster recovery / single points of failure — **Blocker (see §1)**

- `ixora-infra/opentofu/` contains only a `staging/` directory. **There is no `production/` counterpart anywhere in the repo** — no separate Postgres sizing, no separate App Platform spec, nothing.
- Staging Postgres is `db-s-1vcpu-1gb`, `node_count=1` — single point of failure, no read replica, no automatic failover. The `db_node_size` variable's own description reads *"Smallest practical slug for staging (cost-aware)"* — there is no sibling production variable to contrast it with.
- The observability host is a single Droplet; Reserved IP is an optional toggle, not confirmed enabled.

### 4.7 Open known-limitation / tech-debt items — compiled, not re-litigated

Genuinely still open (carried forward from Phases 8–10, not new):

| ID | Limitation |
| --- | --- |
| KL-A-1 | Phase 7B.5 (push delivery metric) still pending — Business/Push alerts blocked on it |
| KL-A-2 / KL-RR-5 | No Node Exporter — VM disk/CPU/memory alerts and SLIs impossible |
| KL-A-6 | Single-VM observability deployment, no HA, alert history lost on VM recreation |
| KL-S-1 | Alert thresholds never baselined against real traffic (Phase 10 confirmed staging traffic is too low to move any HTTP alert out of NoData) |
| KL-S-2 | No Alertmanager-native inhibition rules |
| KL-S-3 | Single email receiver, no team routing (single-operator reality) |
| KL-IR-2 / KL-IR-3 | Single operator holds all incident-response roles; comms is Mailtrap-sandbox-only |
| KL-IR-5 | 14-day NoData silence expires 2026-09-08 |
| KL-RR-1 / KL-RR-2 | 30-day SLO windows have low statistical confidence given low staging traffic |
| KL-RR-4 | Dashboards D-01–D-07 still query raw PromQL instead of recording rules (performance/duplication, not correctness) |

Already resolved, correctly not re-flagged (per this repo's own convention of correcting via a newer doc rather than rewriting a frozen one): KL-A-3, KL-A-4, KL-A-5, KL-IR-1, KL-IR-6, TD-5, TD-6.

TD-1/TD-3/TD-4 were searched for and not found under those IDs — either they don't exist as formally numbered items in this repo, or use different terminology. Flagged as **unconfirmed**, not asserted absent.

---

## 5. Severity summary

| Finding | Severity | Blocks Go? |
| --- | --- | --- |
| No production infrastructure exists (§4.6) | **Blocker** | Yes — nothing to evaluate readiness against |
| Postgres backup undocumented + untested restore; observability stack has zero backup (§4.1) | **Medium** (downgraded 2026-08-30 — DB auto-backups confirmed active) | Not for staging; would be for a real production launch |
| No rate limiting on any endpoint (§4.5) | **High** | Yes |
| Dead CI failing for 3+ weeks (§4.4) | **Medium** | No, but should be fixed promptly regardless |
| Migration procedure manual/unenforced (§4.3) | **Low** (moot until production exists) | No |
| Open KL-*/TD-* items (§4.7) | **Low-Medium**, individually | No — already accepted/tracked risks, mostly single-operator-scale trade-offs |

---

## 6. What "Go" requires

In rough priority order:

1. **Stand up `ixora-infra/opentofu/production/`** — a real production environment definition, with its own (larger) Postgres sizing, App Platform spec, and explicit HA/failover decisions. This is the prerequisite for everything else in this section meaning anything.
2. **Document the confirmed Postgres auto-backup behavior in-repo, run a real restore drill, and back up the observability stack.** Postgres backups themselves are already happening (confirmed 2026-08-30); the remaining work is documentation, a tested restore, and closing the observability-stack gap (Prometheus/Loki/Tempo/Grafana volumes on the single Droplet currently have none).
3. **Add rate limiting** to `back_vibes`'s public API, especially `/api/auth/firebase` and `/api/auth/sync` — Laravel's built-in `RateLimiter`/`throttle` middleware is a low-effort, well-trodden path here.
4. **Disable or fix `back_vibes/.github/workflows/deploy-staging.yml`** — either remove the dead legacy SSH workflow entirely (App Platform already handles staging deploys) or fix it if there's a reason to keep it. Either way, stop leaving broken CI red and ignored.
5. Revisit this review once 1–4 are done — a second, real go/no-go pass against an actual production environment, not a hypothetical one.

---

## 7. Related documents

| Document | Relationship |
| --- | --- |
| [backup-strategy.md](backup-strategy.md) | Source for §4.1 — confirms "architecture only" status |
| [deploy-pipeline.md](../../../architecture/backend/deploy-pipeline.md) | Source for §4.3/§4.4 — migration and rollback procedures |
| [alerting-strategy.md](alerting-strategy.md) | Already-closed Phase 9 work referenced in §3 |
| [incident-response-policy.md](../../../operations/incident-response-policy.md) | Already-closed Phase 9.5 work referenced in §3 |
| [qa/load-testing/README.md](../../../../qa/load-testing/README.md) | Already-closed Phase 10 work referenced in §3 |
| [variables.tf](../../../../opentofu/staging/variables.tf) · [database.tf](../../../../opentofu/staging/database.tf) | Source for §4.2/§4.6 |
