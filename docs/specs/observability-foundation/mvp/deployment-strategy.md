# Observability Deployment Strategy — Phase 8.8.6

**Status:** Active  
**Replaces:** Ad hoc `git pull origin develop` as the **recommended** production deployment workflow  
**Runtime:** `collector/docker-compose.yml` (unchanged)  
**Script:** `scripts/deploy-observability.sh`

> Deployments are **immutable at the Git ref level**. The host checks out a specific release identifier, then runs the existing idempotent deploy script. Rolling `develop` on a production-like host is discouraged.

---

## 1. Philosophy

| Approach | Staging (early) | Staging (hardened) | Production |
| --- | --- | --- | --- |
| Track moving branch (`develop`) | Acceptable for initial bootstrap | Discouraged | ❌ Never |
| Release tag / semver | Recommended | **Required** | **Required** |
| Immutable artifact | Git tag at point in time | Git tag | Git tag (+ optional tarball) |

**Why immutable releases:**

- Every deployment is reproducible and auditable
- Rollback is `git checkout <previous-release>` + redeploy
- Configuration drift from unpinned branches is eliminated
- CI/CD (future) can target a single ref

---

## 2. Release naming conventions

Use one of these patterns consistently:

| Pattern | Example | When to use |
| --- | --- | --- |
| Dated release | `release-2026.07.20` | Staging cadence (weekly/biweekly) |
| Dated release | `release-2026.08.01` | Staging hotfix window |
| Semantic version | `v1.0.0` | Production-aligned milestones |
| Pre-release | `v1.0.0-rc.1` | Pre-production validation |

**Git tag creation (operator or future CI — not automated in this phase):**

```bash
git tag -a release-2026.07.20 -m "Observability release 2026.07.20"
git push origin release-2026.07.20
```

GitHub Releases are **not required** — a Git tag is sufficient. Teams may optionally attach release notes in GitHub UI.

---

## 3. Deployment workflow

### 3.1 First deploy (unchanged from Phase 8.8.5)

1. `tofu apply` — provision host
2. DNS A records → public IP (or Reserved IP if enabled)
3. Clone repository to `/opt/ixora-observability`
4. `scripts/bootstrap-collector-env.sh`
5. Deploy a **pinned release** (not `develop`)

### 3.2 Release deployment (recommended)

```bash
ssh root@<observability-host>
cd /opt/ixora-observability

# Fetch tags and checkout immutable release
git fetch --tags origin
git checkout release-2026.07.20

# Deploy (idempotent)
IXORA_GIT_REF=release-2026.07.20 ./scripts/deploy-observability.sh
```

`IXORA_GIT_REF` is optional when `git checkout` was already performed manually. The deploy script validates the ref if set.

### 3.3 What the deploy script does (unchanged core)

1. Preflight — Docker, `.env`, permissions, placeholder rejection
2. Optional `git checkout ${IXORA_GIT_REF}`
3. `docker compose config` → `pull` → `up -d`
4. Health checks on all five services
5. Optional Grafana `validate.sh`
6. Enable `ixora-observability.service`

**Never run:** `docker compose down -v`

---

## 4. Rollback

```bash
cd /opt/ixora-observability
git fetch --tags origin
git checkout release-2026.07.13   # previous known-good release
./scripts/deploy-observability.sh
```

| Rollback type | Action |
| --- | --- |
| Bad compose/config | Checkout previous Git tag + redeploy |
| Bad image pin in `.env` | Restore previous `.env` backup + redeploy |
| Bad Caddy config | `git checkout` previous release; `systemctl reload caddy` |
| Catastrophic | Restore from backup (future — see [backup-strategy.md](backup-strategy.md)) |

---

## 5. Staging vs production cadence

| Environment | Branch tracking | Release cadence | Approval |
| --- | --- | --- | --- |
| Staging observability host | Release tags from `develop` merges | Weekly or per milestone | Team lead |
| Production observability host | Release tags from vetted staging | Per release cycle | Explicit approval (ADR-031 cost review) |

---

## 6. Relationship to CI/CD

This document defines the **target deployment model**. [future-cicd.md](future-cicd.md) describes how GitHub Actions will automate the same flow. Until CI/CD exists, deployments remain **manual SSH + deploy script**.

---

## 7. Anti-patterns

| Anti-pattern | Why |
| --- | --- |
| `git pull origin develop` on staging host | Non-reproducible; may pull untested commits |
| Editing files directly on host without Git | Untracked drift; lost on re-clone |
| `docker compose down -v` | Destroys named volumes |
| Deploying without health check verification | Silent partial failures |

---

## 8. Cross-references

| Document | Link |
| --- | --- |
| Host provisioning | [observability-infrastructure-provisioning.md](observability-infrastructure-provisioning.md) |
| Operations | [runbooks/observability-host.md](../../../runbooks/observability-host.md) |
| Future automation | [future-cicd.md](future-cicd.md) |
| Hardening index | [observability-hardening.md](observability-hardening.md) |
