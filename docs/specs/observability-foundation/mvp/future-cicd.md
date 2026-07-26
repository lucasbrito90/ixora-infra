# Future CI/CD — Observability Host Deployment — Phase 8.8.6

**Status:** Architecture only — **not implemented**  
**Target runtime:** Unchanged — `scripts/deploy-observability.sh` + `collector/docker-compose.yml`

> This document describes a future pipeline. No GitHub Actions, workflows, or secrets are created in Phase 8.8.6.

---

## 1. Pipeline overview

```
Developer
    ↓ merge to develop
GitHub (ixora-infra)
    ↓ tag release (release-YYYY.MM.DD or vX.Y.Z)
GitHub Release (optional — tag alone is sufficient)
    ↓ workflow trigger (tag push)
GitHub Actions
    ↓ SSH (deploy key / OIDC + bastion)
Observability Host (/opt/ixora-observability)
    ↓ IXORA_GIT_REF=<tag>
scripts/deploy-observability.sh
    ↓ docker compose config / pull / up -d
Docker Compose (collector/docker-compose.yml)
    ↓ health checks
Health Validation (curl + optional validate.sh)
    ↓
Success | Failure notification
```

---

## 2. Workflow triggers

| Trigger | Environment | Approval |
| --- | --- | --- |
| Tag `release-*` | Staging observability | Automatic |
| Tag `v*.*.*` | Production observability | Manual approval gate |
| `workflow_dispatch` | Either | Operator-initiated rollback/redeploy |

**Not triggered by:** every push to `develop` (avoids uncontrolled deploys).

---

## 3. GitHub Actions job design (future)

```yaml
# CONCEPTUAL ONLY — not implemented
name: Deploy Observability Staging
on:
  push:
    tags:
      - 'release-*'

jobs:
  deploy:
    runs-on: ubuntu-latest
    environment: observability-staging
    steps:
      - name: Deploy via SSH
        uses: appleboy/ssh-action@v1
        with:
          host: ${{ secrets.OBSERVABILITY_HOST }}
          username: root
          key: ${{ secrets.OBSERVABILITY_SSH_KEY }}
          script: |
            cd /opt/ixora-observability
            export IXORA_GIT_REF=${{ github.ref_name }}
            export GF_ADMIN_PASSWORD=${{ secrets.GF_ADMIN_PASSWORD }}
            ./scripts/deploy-observability.sh
```

---

## 4. Secret management (future)

| Secret | Storage | Never in |
| --- | --- | --- |
| SSH private key | GitHub Actions secret | Repository |
| `GF_ADMIN_PASSWORD` | GitHub Actions secret | Logs |
| `OTEL_INGEST_API_KEY_*` | Host `.env` only | CI logs |
| DO API token | Separate infra pipeline | Observability workflow |

**Principle:** CI triggers deploy; it does **not** regenerate `.env` on every run unless explicit rotation workflow.

---

## 5. Idempotency

The existing `deploy-observability.sh` is idempotent:

| Step | Idempotent behavior |
| --- | --- |
| `git checkout ${IXORA_GIT_REF}` | Same ref → no-op |
| `docker compose config` | Validates without mutation |
| `docker compose pull` | Pulls only changed layers |
| `docker compose up -d` | Reconciles desired state |
| Health checks | Read-only verification |

Re-running the pipeline on the same tag is safe.

---

## 6. Deployment verification

| Check | Method | Fail pipeline if |
| --- | --- | --- |
| Collector health | `curl 127.0.0.1:13133/health` | Non-200 |
| Prometheus | `curl 127.0.0.1:9090/-/ready` | Non-200 |
| Loki | `curl 127.0.0.1:3100/ready` | Non-200 |
| Tempo | `curl 127.0.0.1:3200/ready` | Non-200 |
| Grafana | `curl 127.0.0.1:3000/api/health` | Non-200 |
| External HTTPS | `curl https://grafana-staging.../api/health` | Non-200 |
| Grafana provisioning | `validate.sh` (optional) | Any failure |

---

## 7. Rollback

| Scenario | Action |
| --- | --- |
| Deploy fails health check | Re-run workflow with previous tag OR manual `git checkout` + deploy |
| Bad release tag | Deploy previous tag via `workflow_dispatch` |
| Partial container failure | `deploy-observability.sh` re-run (compose reconciles) |
| Data corruption | Restore from backup ([backup-strategy.md](backup-strategy.md)) — outside CI scope |

**Rollback command (manual or CI):**

```bash
IXORA_GIT_REF=release-2026.07.13 ./scripts/deploy-observability.sh
```

---

## 8. Failure handling

| Failure | Detection | Response |
| --- | --- | --- |
| SSH unreachable | Action timeout | Alert operator; no partial deploy |
| `git checkout` fails | Script exit 1 | Pipeline fails; host unchanged |
| `compose config` fails | Script exit 1 | Pipeline fails; containers unchanged |
| `up -d` partial | Health check failure | Log `docker compose ps`; alert |
| Health timeout | wait_http failure | Pipeline fails; operator investigates |

**Principle:** Fail fast; never run `docker compose down -v`.

---

## 9. Relationship to other documents

| Document | Role |
| --- | --- |
| [deployment-strategy.md](deployment-strategy.md) | Release naming + manual deploy today |
| [app-platform-otel-integration.md](app-platform-otel-integration.md) | Separate pipeline for App Platform env |
| [observability-hardening.md](observability-hardening.md) | Hardening index |

---

## 10. Implementation prerequisites (future phase)

- [ ] Observability host provisioned and first manual deploy successful
- [ ] GitHub Actions enabled for `ixora-infra`
- [ ] SSH deploy key or OIDC bastion pattern approved
- [ ] Secrets stored in GitHub environment
- [ ] Staging release tag convention adopted
- [ ] Rollback drill documented in runbook
