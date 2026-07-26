# Observability Infrastructure Hardening — Phase 8.8.6

**Status:** Complete (documentation + optional Reserved IP IaC)  
**Prerequisite:** [observability-infrastructure-provisioning.md](observability-infrastructure-provisioning.md) (Phase 8.8.5)  
**Runtime unchanged:** `collector/docker-compose.yml` remains the source of truth  
**ADRs preserved:** [ADR-028](../../../decisions/ADR-028-observability-platform.md) · [ADR-030](../../../decisions/ADR-030-observability-security-and-privacy.md) · [ADR-031](../../../decisions/ADR-031-retention-storage-and-cost-control.md)

> **Scope:** Operational hardening only. No new observability capabilities, no Collector/Prometheus/Loki/Tempo/Grafana runtime changes, no CI/CD implementation, no backups implementation.

---

## 1. Purpose

Phase 8.8.5 provisioned the observability host and documented the first deployment path. Phase 8.8.6 refines **how the host is operated in production-grade fashion** without redesigning the architecture established in Phases 2–8.8.5.

| Principle | Preserved |
| --- | --- |
| OpenTofu provisions infrastructure | ✅ |
| Docker Compose runs the stack | ✅ |
| Collector is the only ingestion point | ✅ |
| Secrets outside OpenTofu state / cloud-init | ✅ |
| Internal backends on 127.0.0.1 | ✅ |
| Grafana + OTLP via Caddy HTTPS | ✅ |

---

## 2. Hardening deliverables

| # | Topic | Document | Implementation |
| --- | --- | --- | --- |
| 1 | Release-oriented deployment | [deployment-strategy.md](deployment-strategy.md) | Philosophy + doc updates; deploy script supports `IXORA_GIT_REF` |
| 2 | Reserved / Floating IP | [storage-strategy.md](storage-strategy.md) §5 · provisioning doc | Optional OpenTofu resource (`observability_use_reserved_ip`, default `false`) |
| 3 | Backup architecture | [backup-strategy.md](backup-strategy.md) | Architecture only — no scripts or cron |
| 4 | Storage evolution | [storage-strategy.md](storage-strategy.md) | Strategy A retained; Strategy B designed |
| 5 | App Platform OTEL automation | [app-platform-otel-integration.md](app-platform-otel-integration.md) | Future design — no App Platform changes |
| 6 | Future CI/CD | [future-cicd.md](future-cicd.md) | Pipeline architecture only |
| 7 | Cloud-init review | [cloud-init-review.md](cloud-init-review.md) | Limitations + CM migration path |
| 8 | OpenTofu lifecycle review | [cloud-init-review.md](cloud-init-review.md) §6 | Lifecycle analysis — no breaking changes |

---

## 3. Architecture review (pre-implementation)

### 3.1 What Phase 8.8.5 established

```
OpenTofu (staging)
  └── Droplet + Firewall [+ optional Block Volume]
        └── cloud-init: Docker, Caddy, systemd, directories
              └── Manual: git clone → bootstrap .env → deploy-observability.sh
                    └── collector/docker-compose.yml (5 services)
```

### 3.2 Gaps identified for hardening

| Gap | Phase 8.8.5 state | Phase 8.8.6 resolution |
| --- | --- | --- |
| Deployment model | `git pull origin develop` documented | Release-tag immutable deployments |
| DNS stability on Droplet replace | Ephemeral Droplet IP | Optional Reserved IP |
| Data durability | "No backups implemented" | Backup architecture designed |
| Storage growth | Strategy A only documented briefly | Full Strategy B design + migration path |
| App Platform OTEL | Manual console step | Future OpenTofu automation design |
| Host updates | cloud-init one-shot | Documented limitations + CM path |
| CI/CD | Ad hoc SSH deploy | Documented future pipeline |

### 3.3 Explicit non-goals

- No Kubernetes, managed Grafana/Prometheus/Loki/Tempo
- No Ansible, Terraform Cloud, GitHub Actions implementation
- No Node Exporter, alert rules, recording rule activation
- No `tofu apply` in this phase

---

## 4. Integration map

```
observability-hardening.md (this file)
├── deployment-strategy.md ──────► scripts/deploy-observability.sh
├── backup-strategy.md ───────────► runbooks/observability-host.md
├── storage-strategy.md ──────────► observability-infrastructure-provisioning.md §4
├── app-platform-otel-integration.md ► Phase 8.8.5 § App Platform (manual today)
├── future-cicd.md ───────────────► deployment-strategy.md
├── cloud-init-review.md ─────────► opentofu/staging/templates/observability-cloud-init.yaml.tftpl
└── observability-infrastructure-provisioning.md (updated cross-refs)
```

---

## 5. Reserved IP summary

Optional feature controlled by `observability_use_reserved_ip` (default `false`).

| Aspect | Without Reserved IP | With Reserved IP |
| --- | --- | --- |
| DNS target | Droplet ephemeral IPv4 | Stable Reserved IPv4 |
| Droplet replacement | Update DNS A records | Reassign IP — DNS unchanged |
| Cost | Included in Droplet | + ~$4/mo (verify DO pricing) |
| Staging default | ✅ Recommended | Optional when DR testing |

See [storage-strategy.md](storage-strategy.md) §5 and [backup-strategy.md](backup-strategy.md) §8 for DR implications.

---

## 6. Validation

Grafana `validate.sh` extended to **90/90 checks** (checks 79–90 verify hardening documentation structure and cross-references).

---

## 7. Known limitations (carried forward)

| ID | Limitation | Phase |
| --- | --- | --- |
| KL-HARD-1 | Backups designed but not implemented | 8.8.6 |
| KL-HARD-2 | CI/CD designed but not implemented | 8.8.6 |
| KL-HARD-3 | App Platform OTEL still manual | 8.8.6 |
| KL-HARD-4 | Strategy B mount not automated | 8.8.5+ |
| KL-HARD-5 | cloud-init does not re-run on existing Droplet | 8.8.5+ |

---

## 8. Related documents

| Document | Role |
| --- | --- |
| [observability-infrastructure-provisioning.md](observability-infrastructure-provisioning.md) | Host provisioning (Phase 8.8.5) |
| [runbooks/observability-host.md](../../../runbooks/observability-host.md) | Day-2 operations |
| [infrastructure-review.md](infrastructure-review.md) | Original topology |
| [security-review.md](security-review.md) | Security boundaries |
| [collector/README.md](../../../../collector/README.md) | Runtime quick start |
