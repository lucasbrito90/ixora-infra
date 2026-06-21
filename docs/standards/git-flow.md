# Git Flow — Ixora ecosystem

**Status:** Active engineering standard (source of truth)  
**Scope:** Branching, merging, releases, staging, hotfixes, and multi-repo coordination across Ixora repositories  
**Applies to:** `back_vibes`, `front_vibes`, `ixora-admin`, `ixora-infra`

---

## Purpose

Define the **mandatory Git workflow** for the Ixora ecosystem: which branches exist, how work flows from feature development through homologation to production, how **multiple repositories** stay aligned, and how **infrastructure (OpenTofu)** changes relate to application deploys.

This document is the **source of truth** for humans and AI-assisted development. Cursor workspace rules and per-repo copies should stay aligned with this file.

---

## Scope

### In scope

- Permanent and temporary branch types
- Feature, release, staging, and hotfix flows
- Pull request targets and merge conventions
- Conventional Commits
- Multi-repo coordination for cross-cutting work
- Staging as a deployable homologation line
- OpenTofu / `ixora-infra` synchronization with app repos
- AI-assisted development workflow and review requirements

### Out of scope

- CI/CD pipeline internals (see stack READMEs under `ixora-infra/opentofu/`)
- Repository hosting permissions and branch protection UI settings
- Detailed feature specifications (see `docs/specs/`)

### Repositories covered

| Repository | Responsibility | Git Flow |
| --- | --- | --- |
| `back_vibes` | Laravel API, business rules, uploads, queues | Full Git Flow |
| `front_vibes` | Ionic + Vue mobile application | Full Git Flow |
| `ixora-admin` | Nuxt admin panel | Full Git Flow |
| `ixora-infra` | OpenTofu infrastructure and central documentation | Full Git Flow |

Each repository is an **independent git remote** with its **own** `main`, `develop`, and `staging` branches. Cross-repo features require **coordinated branches and merges** in every affected repo—not a monorepo merge.

---

## Repository Model

```
Per repository:

  main      ← production (release/* and hotfix/* only)
  develop   ← integration (all feature work merges here)
  staging   ← homologation / deployable QA line (merges from develop)

  feature/*   ← temporary — new work
  release/*   ← temporary — release preparation
  hotfix/*    ← temporary — urgent production fixes
```

**Never work directly on `main`.** All new work starts on a **feature branch** (or `hotfix/*` for production emergencies) from an updated base branch as defined below.

---

## Branch Strategy

### Permanent branches

| Branch | Role |
| --- | --- |
| `main` | **Production.** Receives merges **only** from `release/*` or `hotfix/*`. Tagged releases live here. |
| `develop` | **Integration.** Base for all feature development. Accumulates completed features before staging or release. |
| `staging` | **Homologation.** Pre-production line deployed to the **staging environment** (API, admin, and mobile build targets as applicable). Reflects a **deployable, testable** snapshot—not experimental WIP on `develop`. |

### Temporary branches

| Pattern | Base branch | Merges into | Remote retention |
| --- | --- | --- | --- |
| `feature/<short-name>` | `develop` | `develop` | **Keep on remote** — historical traceability |
| `release/<semver>` | `develop` | `main` **and** `develop` | **Keep on remote** |
| `hotfix/<short-name>` | `main` | `main` **and** `develop` | **Keep on remote** |

### Branch naming

| Type | Pattern | Example |
| --- | --- | --- |
| Feature | `feature/<short-description>` | `feature/vibe-schedule` |
| Release | `release/<semver>` | `release/1.2.0` |
| Hotfix | `hotfix/<short-description>` | `hotfix/fix-token-expiry` |

- Use **kebab-case** always.
- Issue numbers are optional but welcome: `feature/42-vibe-schedule`.

### `staging` branch rules

- **Purpose:** Continuous or on-demand deploy of the **staging environment** without mixing homologation with `main`.
- **Update:** When a set of changes is ready for QA, merge **`develop` → `staging`** with **`--no-ff`**.
- **Never delete** `staging` on the remote — it is the pipeline reference branch.
- **Do not** create features from `staging`. Features **always** branch from `develop`.

```bash
git checkout staging && git pull origin staging
git merge --no-ff develop -m "Merge branch 'develop' into staging"
git push origin staging
```

If `staging` does not exist yet in a repository:

```bash
git checkout develop && git pull origin develop
git checkout -b staging
git push -u origin staging
```

---

## Development Flow

### End-to-end (single repository)

```
develop ──► feature/xxx ──► PR → develop ──► merge ──► staging ──► release/x.y.z ──► main
                              │                                              │
                              └──────────────────────────────────────────────┘
                                          ◄── hotfix/zzz ─── (main + develop; promote to staging when applicable)
```

### Daily workflow

1. **Always** create a feature branch from **updated `develop`**.
2. Open a **Pull Request** from `feature/*` → `develop` (never feature → `main`).
3. When a set is ready for homologation, merge **`develop` → `staging`** and deploy/publish staging.
4. When closing a release cycle, create **`release/*`** from `develop` (or from the commit validated on `staging`, per team release policy).
5. **`release/*`** merges to **`main`** and **`develop`** simultaneously (with version tag on `main`).
6. Production bugs become **`hotfix/*`** from **`main`**, merge to **`main`** + **`develop`**, then propagate to **`staging`** via **`develop` → `staging`** when applicable.

### Start a feature branch

```bash
git checkout develop
git pull origin develop
git checkout -b feature/vibe-schedule
```

### Finish a feature branch (merge to develop)

```bash
git checkout develop
git pull origin develop
git merge --no-ff feature/vibe-schedule -m "Merge branch 'feature/vibe-schedule' into develop"
git push origin develop
git push origin feature/vibe-schedule   # keep on remote for historical traceability
# ❌ NEVER: git branch -d feature/vibe-schedule
# ❌ NEVER: git push origin --delete feature/vibe-schedule
```

### Pull requests

- PR target: **`feature/*` → `develop`** (required pattern for feature work).
- Optional PR: **`develop` → `staging`** when the team wants explicit review before homologation deploy; otherwise local **`--no-ff`** merge per **Branch `staging` rules** above.
- **Never** open a PR from `feature/*` directly to `main`.
- PR title follows **Conventional Commits** (same as commit messages).

```bash
gh pr create --base develop --title "feat(vibes): add schedule" --body "..."
```

### Multi-repo coordination

Cross-cutting work (API + admin + mobile + infra) spans **multiple repositories**. Each repo follows the **same Git Flow independently**, but delivery must stay **logically synchronized**:

| Rule | Requirement |
| --- | --- |
| Branch per repo | Create a **named feature branch in every affected repository** (same slug when possible, e.g. `feature/cover-bundle-multipart`). |
| Develop first | Merge each repo’s feature → **`develop`** via PR (or reviewed merge) **before** promoting that repo’s `develop` → `staging`. |
| Staging alignment | **`staging` in each affected repo should reflect a deployable combination** for QA — app code and infra/env dependencies that depend on each other should reach staging **together**, not weeks apart. |
| Infra + app coupling | If `back_vibes` / `ixora-admin` / `front_vibes` require new env vars, domains, CORS, upload limits, or App Platform settings, **`ixora-infra` OpenTofu changes must land on `develop` and `staging` in sync** with the application changes that consume them. |
| Document cross-repo scope | PR descriptions (or linked issue) must list **all repos** touched and the **merge order** if order matters (see Release / Staging Flow). |
| Hotfix propagation | A production hotfix merged to `main` + `develop` in one repo may require **matching hotfix or develop merges** in other repos if the bug or config is shared. |

**Example:** New API env var wired in `ixora-infra/opentofu/staging/` and read in `back_vibes` — both feature branches merge to their respective **`develop`** branches, then both repos promote **`develop` → `staging`** before QA validates the staging deploy.

---

## Commit Rules

### Conventional Commits (required)

```
<type>(<optional scope>): <short description>
```

| Type | When to use |
| --- | --- |
| `feat` | New functionality |
| `fix` | Bug fix |
| `refactor` | Refactoring without behaviour change |
| `chore` | Build, deps, config |
| `docs` | Documentation only |
| `test` | Tests |
| `style` | Formatting, no logic change |

**Examples:**

```
feat(vibes): add schedule support to vibe creation
fix(auth): correct redirect after google signin
chore(deps): update ionic to 8.x
chore(infra): add CORS_ALLOWED_ORIGINS to staging API env
```

### Where commits are allowed

| Branch | Direct commits |
| --- | --- |
| `feature/*`, `hotfix/*`, `release/*` | ✅ Yes — all work happens here |
| `develop` | ❌ **Never** — not even one commit |
| `staging` | ❌ **Never** — only merges from `develop` (unless an explicit out-of-band policy is documented elsewhere) |
| `main` | ❌ **Never** — only merges from `release/*` or `hotfix/*` |

---

## Merge Rules

### Required merge style

- Use **`git merge --no-ff`** when integrating **`feature/*` → `develop`**, **`develop` → `staging`**, **`release/*` → `main`/`develop`**, and **`hotfix/*` → `main`/`develop`**.
- **`--no-ff`** preserves feature branch history and makes rollbacks and audits traceable.

### Rebase / squash policy

- **No separate mandated rebase or squash-merge policy** beyond **`--no-ff` merge commits** as the integration mechanism.
- **Do not** squash-merge into `develop`, `staging`, or `main` as the default integration path.
- Rebasing a **local** feature branch onto updated `develop` before opening or updating a PR is **allowed** for the branch author.
- **Do not** rebase or **force-push** branches that others are reviewing without explicit coordination.

### Force push

- ❌ **Never** `git push --force` to **`main`**, **`develop`**, or **`staging`** on any repository.

### Branch deletion

- ❌ **Never delete** `feature/*`, `release/*`, `hotfix/*`, or **`staging`** branches — **local or remote**.
- ✅ Push feature/release/hotfix branches to remote and **leave them indefinitely** for historical traceability.

---

## Release / Staging Flow

### Staging (homologation)

**`staging` reflects deployable state** — the branch App Platform (and equivalent pipelines) deploy for pre-production QA. It is not a scratch branch for direct commits.

**Typical promotion:**

```bash
# In each repository ready for QA:
git checkout staging && git pull origin staging
git merge --no-ff develop -m "Merge branch 'develop' into staging"
git push origin staging
```

**Deployment sequencing (multi-repo):**

When a change spans application and infrastructure:

1. Merge **application** features to **`develop`** in each affected app repo (`back_vibes`, `front_vibes`, `ixora-admin`).
2. Merge **OpenTofu / env / platform** changes to **`develop`** in **`ixora-infra`** when the app depends on new configuration.
3. Promote **`develop` → `staging`** in **all repos that must deploy together** for the feature to work end-to-end.
4. **Apply OpenTofu** (`tofu plan` / `tofu apply` in `ixora-infra/opentofu/staging/`) when infra changes are on `staging` — **before or as part of** validating the dependent app deploy, so staging runtime matches the merged code.
5. Confirm **App Platform** (or mobile build pipeline) picked up the **`staging`** branch deploy for API/admin; validate mobile against staging API as applicable.

If infra must exist **before** app code can boot (new env var, CORS origin, DB firewall rule), merge/apply **infra first**, then promote app repos. If app and infra are independent, parallel promotion is acceptable—document the order in the PR.

Optional: open a **`develop` → `staging`** PR in `ixora-infra` or app repos when explicit review is required before deploy.

### Release (production)

```bash
# Start from develop
git checkout develop && git pull origin develop
git checkout -b release/1.1.0

# … version bump, final fixes only — no new features …

# Finish: merge to main AND develop
git checkout main && git pull origin main
git merge --no-ff release/1.1.0 -m "Merge branch 'release/1.1.0'"
git tag -a v1.1.0 -m "release 1.1.0"
git push origin main --tags

git checkout develop && git pull origin develop
git merge --no-ff release/1.1.0 -m "Merge branch 'release/1.1.0' into develop"
git push origin develop
git push origin release/1.1.0   # keep on remote

# ❌ NEVER delete release/1.1.0 locally or on remote
```

Release branch source may be **`develop`** or the **commit validated on `staging`**, per team release policy—both are valid when homologation sign-off is required.

---

## Hotfix Flow

Production emergencies branch from **`main`**, not `develop`.

```bash
git checkout main && git pull origin main
git checkout -b hotfix/fix-auth-redirect

# … fix …

git checkout main
git merge --no-ff hotfix/fix-auth-redirect -m "Merge branch 'hotfix/fix-auth-redirect'"
git tag -a v1.0.1 -m "hotfix 1.0.1"
git push origin main --tags

git checkout develop
git merge --no-ff hotfix/fix-auth-redirect -m "Merge branch 'hotfix/fix-auth-redirect' into develop"
git push origin develop
git push origin hotfix/fix-auth-redirect   # keep on remote

# ❌ NEVER delete hotfix branch locally or on remote
```

**After hotfix:** propagate to **`staging`** when homologation should reflect production fixes:

```bash
git checkout staging && git pull origin staging
git merge --no-ff develop -m "Merge branch 'develop' into staging"
git push origin staging
```

If the hotfix touches **infra only**, follow the same pattern in **`ixora-infra`** and apply OpenTofu to staging/production stacks per runbook.

---

## AI-assisted Development Rules

AI tools (Cursor, Codex, Claude, ChatGPT, etc.) are used for implementation speed—but **Git Flow safety rules are not relaxed** for generated changes.

### Before implementing

1. Read relevant **`docs/architecture/`** documents in `ixora-infra`.
2. Read applicable **`docs/standards/`** (including this file).
3. Read related **`docs/specs/`** for the feature.
4. Follow **`docs/decisions/`** ADRs when they exist.
5. Avoid introducing architecture that conflicts with documented decisions.

### During and after implementation

- **All AI-generated changes must be human-reviewed before merge** to `develop` (via PR review or equivalent explicit approval). Do not merge unreviewed agent output.
- AI agents **must not** commit directly to `develop`, `staging`, or `main`.
- AI agents **must not** delete remote feature/release/hotfix branches or force-push protected branches.
- Cross-repo work: the human reviewer confirms **every affected repository** is updated and staging promotion order is correct.
- When AI edits **OpenTofu**, reviewer verifies **`tofu plan`** output and coupling with app env expectations.

Central documentation in **`ixora-infra`** is the **source of truth** for ecosystem architecture; app-repo doc copies should stay aligned.

---

## Risks

| Risk | If ignored |
| --- | --- |
| Direct commits to `develop` / `staging` / `main` | Untraceable history, bypassed review, production/staging incidents |
| Feature → `main` PR | Unintegrated code in production without release discipline |
| Missing `--no-ff` | Lost feature boundaries; harder rollback and audit |
| Deleting remote feature branches | Lost historical context for incidents and compliance |
| Force push on protected branches | Team history corruption; pipeline breakage |
| App merged to staging without infra env | Staging deploy fails or misbehaves (CORS, secrets, upload limits) |
| Infra applied without app on staging | False QA signal; config drift |
| Unreviewed AI merges | Subtle bugs, security issues, architecture drift |
| `staging` used as feature base | Divergent homologation line; undeployable QA state |
| Multi-repo feature merged in one repo only | Broken end-to-end flows in staging/production |

---

## Validation

### Per change (before merge to develop)

- [ ] Work is on **`feature/*`** (or **`hotfix/*`** / **`release/*`** as appropriate)—not on `develop`, `staging`, or `main`.
- [ ] Branch was created from **updated `develop`** (or **`main`** for hotfix).
- [ ] Commits follow **Conventional Commits**.
- [ ] PR targets **`develop`** (feature work) with **human review** completed.
- [ ] AI-generated diffs were **reviewed** by a human.

### Staging promotion

- [ ] **`develop` → `staging`** merge uses **`--no-ff`**.
- [ ] **No direct commits** on `staging`.
- [ ] All **affected repos** promoted when the feature is cross-cutting.
- [ ] **`ixora-infra` OpenTofu** changes applied when staging runtime depends on them.
- [ ] Staging environment **deployable and testable** end-to-end (API, admin, mobile as applicable).

### Release / hotfix

- [ ] **`release/*`** or **`hotfix/*`** merged to **`main`** with **`--no-ff`** and tag on `main` (release/hotfix).
- [ ] Same branch merged back to **`develop`** with **`--no-ff`**.
- [ ] **`release/*` / `hotfix/*` / `feature/*` branches remain on remote**.
- [ ] Hotfix propagated to **`staging`** via **`develop`** when QA should match production fix.

### Prohibited actions (must never occur)

- [ ] No direct commits to `develop`, `staging`, or `main`.
- [ ] No `git push --force` to `main`, `develop`, or `staging`.
- [ ] No deletion of `feature/*`, `release/*`, `hotfix/*`, or `staging` on remote.

---

## Related Files

| Location | Path |
| --- | --- |
| **Central (this repo)** | `docs/standards/git-flow.md` (this file) |
| | `docs/standards/front-vibes-auth-core.md` |
| | `docs/standards/front-vibes-ionic-routing.md` |
| | `docs/architecture/` — platform architecture |
| | `docs/specs/` — feature contracts |
| | `docs/decisions/` — ADRs |
| | `opentofu/staging/README.md` — staging stack apply runbook |
| **Cursor workspace** | `.cursor/rules/git-flow.mdc` — keep aligned with this standard |
| **Per-repo** | Each app/infra repo follows the same branch model independently |

When Git Flow policy changes, update **this file first**, then sync `.cursor/rules/git-flow.mdc` and notify the team before changing branch protection or pipeline defaults.
