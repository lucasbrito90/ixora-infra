# Observability Backup Strategy — Phase 8.8.6

**Status:** Staging automation implemented — local tarball backup + restore scripts; production object-storage upload deferred  
**Prerequisite:** [observability-infrastructure-provisioning.md](observability-infrastructure-provisioning.md)  
**ADR:** [ADR-031](../../../decisions/ADR-031-retention-storage-and-cost-control.md)

> Staging backup automation is delivered in Phase 8.8.7: `scripts/backup-observability-volumes.sh` and `scripts/restore-observability-volume.sh` create local per-volume tarballs with 4-generation retention. No cron is installed by the scripts — the operator installs the weekly crontab on the observability host (see [observability-backup-restore.md](../../../runbooks/observability-backup-restore.md)). Production Spaces upload remains a future phase.

---

## 1. Current state

| Data | Location | Survives container restart | Survives Droplet destroy |
| --- | --- | --- | --- |
| Prometheus TSDB | Docker volume `prometheus_data` | ✅ | ❌ (Strategy A) |
| Loki chunks/index | Docker volume `loki_data` | ✅ | ❌ |
| Tempo WAL/blocks | Docker volume `tempo_data` | ✅ | ❌ |
| Grafana local state | Docker volume `grafana_data` | ✅ | ❌ |
| Grafana provisioning | Git (`collector/grafana/provisioning/`) | ✅ | ✅ |
| Collector config | Git (`collector/`) | ✅ | ✅ |
| Secrets (`collector/.env`) | Host filesystem | ✅ | ❌ |

---

## 2. Backup objectives

| Objective | Priority | Rationale |
| --- | --- | --- |
| Recover from accidental volume deletion | High | Operator error (`down -v`) |
| Recover from Droplet failure/replacement | High | Strategy A has no data portability |
| Recover from corruption | Medium | TSDB rare but possible |
| Long-term archival beyond retention | Low | ADR-031 caps; archive is separate phase |
| Point-in-time compliance | Future | Production only |

---

## 3. Component backup design

### 3.1 Prometheus

| Attribute | Recommendation |
| --- | --- |
| **Method** | Filesystem snapshot of Docker volume OR `promtool tsdb snapshot` |
| **Path** | `/var/lib/docker/volumes/collector_prometheus_data/_data/` |
| **Frequency (staging)** | Weekly (optional); before each release deploy |
| **Frequency (production)** | Daily + before deploy |
| **Retention** | 7 daily (staging); 30 daily + 12 monthly (production) |
| **Consistency** | Stop Prometheus or use snapshot API to avoid partial WAL |
| **Restore** | Stop Prometheus → replace volume data → start → verify `/-/ready` |

### 3.2 Loki

| Attribute | Recommendation |
| --- | --- |
| **Method** | Volume snapshot (single-binary monolithic mode) |
| **Path** | `collector_loki_data` volume |
| **Frequency** | Same as Prometheus |
| **Retention** | Match staging/production policy above |
| **Restore** | Stop Loki → restore volume → start → verify `/ready` |

### 3.3 Tempo

| Attribute | Recommendation |
| --- | --- |
| **Method** | Volume snapshot |
| **Path** | `collector_tempo_data` volume |
| **Frequency** | Same as Prometheus |
| **Note** | 7-day retention (ADR-031) limits restore window |
| **Restore** | Stop Tempo → restore volume → start → verify `/ready` |

### 3.4 Grafana

| Attribute | Recommendation |
| --- | --- |
| **Provisioning (dashboards, datasources, alerting scaffold)** | Git — no backup needed |
| **Local SQLite / plugins / user prefs** | Volume snapshot of `grafana_data` |
| **Frequency** | Weekly (staging); daily (production) |
| **Restore** | Re-clone Git + restore volume OR provisioning-only rebuild (preferred for dashboards) |

### 3.5 Docker volumes (aggregate)

| Approach | Pros | Cons |
| --- | --- | --- |
| Per-volume backup | Granular restore | Four operations |
| Full Docker data dir backup | Single operation | Larger; includes unused layers |
| DO Droplet snapshot | Simple; full disk | Includes OS noise; not portable across regions |

**Staging recommendation:** DO Droplet snapshot weekly (optional, ~cost) OR manual volume tarball before release deploy.

**Production recommendation:** Automated volume snapshots to object storage (Spaces) with encryption.

### 3.6 Secrets (`collector/.env`)

| Attribute | Recommendation |
| --- | --- |
| **Backup** | Store in team password manager / DO encrypted secrets — **not** in Git |
| **Recovery** | Re-run `scripts/bootstrap-collector-env.sh` with same or rotated keys |
| **Rotation** | Rotating OTEL keys requires App Platform header update |

---

## 4. Recovery procedures (design)

### 4.1 Single service volume restore

```
1. docker compose stop <service>
2. Restore volume from backup
3. docker compose up -d <service>
4. Run health checks (see runbook)
5. Verify data continuity in Grafana
```

### 4.2 Full host disaster (Strategy A, no Reserved IP)

```
1. tofu apply (new Droplet) OR restore Droplet from snapshot
2. Update DNS if IP changed (skip if Reserved IP — see storage-strategy.md §5)
3. Clone ixora-infra at last known-good release tag
4. bootstrap-collector-env.sh
5. Restore volume backups OR accept data loss
6. deploy-observability.sh
7. Verify all health endpoints + validate.sh
```

### 4.3 Full host disaster (with Reserved IP + volume backups)

```
1. Provision/replace Droplet; assign Reserved IP
2. DNS unchanged
3. Restore block volume OR volume tarballs
4. Clone + bootstrap + deploy
5. Verify
```

**Recovery time objective (design targets, not measured):**

| Scenario | Staging target | Production target |
| --- | --- | --- |
| Container failure | < 5 min (automatic) | < 5 min |
| Single volume restore | < 30 min (manual) | < 15 min (automated future) |
| Full host rebuild | < 2 hours | < 1 hour |

---

## 5. Backup frequency summary

| Component | Staging | Production |
| --- | --- | --- |
| Prometheus | Weekly / pre-deploy | Daily |
| Loki | Weekly / pre-deploy | Daily |
| Tempo | Weekly / pre-deploy | Daily |
| Grafana volume | Weekly | Daily |
| Grafana provisioning | Git (continuous) | Git (continuous) |
| `.env` secrets | Password manager | Secret manager + rotation policy |
| Droplet snapshot | Optional weekly | Daily |

---

## 6. Retention alignment (ADR-031)

Backups should cover **at least one full retention window** for production:

| Backend | Operational retention | Minimum backup depth |
| --- | --- | --- |
| Prometheus | 30 days | 7 daily snapshots |
| Loki | 14 days | 7 daily snapshots |
| Tempo | 7 days | 3 daily snapshots |

Backup retention can exceed operational retention for compliance; it must not contradict ADR-031 cost controls without ADR amendment.

---

## 7. Future implementation phases

| Phase | Deliverable | Status |
| --- | --- | --- |
| 8.8.7 (staging) | Backup scripts + restore runbook + weekly cron (operator-installed) | **Done** — `scripts/backup-observability-volumes.sh`, `scripts/restore-observability-volume.sh`, [observability-backup-restore.md](../../../runbooks/observability-backup-restore.md) |
| 8.8.7+ (production) | Spaces upload + encryption | Deferred |
| 9.x | Backup monitoring + alert on failure | Deferred |
| Production | Cross-region copy + restore drill quarterly | Deferred |

---

## 8. Disaster recovery and Reserved IP

When `observability_use_reserved_ip = true`:

- DNS A records remain valid after Droplet replacement
- Clients (App Platform, mobile, engineers) require **no endpoint change**
- Backup restore focuses on **data volumes**, not DNS

See [storage-strategy.md](storage-strategy.md) §5.

---

## 9. Cross-references

| Document | Role |
| --- | --- |
| [deployment-strategy.md](deployment-strategy.md) | Pre-deploy backup hook (future) |
| [runbooks/observability-host.md](../../../runbooks/observability-host.md) | Operational recovery |
| [observability-hardening.md](observability-hardening.md) | Hardening index |
