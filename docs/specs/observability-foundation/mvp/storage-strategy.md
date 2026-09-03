# Observability Storage Strategy — Phase 8.8.6

**Status:** Active  
**Default unchanged:** Strategy A (root disk + Docker named volumes)  
**OpenTofu:** `observability_use_block_volume = false` (default)

---

## 1. Overview

| Strategy | Name | Default | OpenTofu flag |
| --- | --- | --- | --- |
| **A** | Root disk + Docker volumes | ✅ Staging | `observability_use_block_volume = false` |
| **B** | DigitalOcean Block Storage | Optional | `observability_use_block_volume = true` |

Both strategies use the **same Docker Compose volume names**. Only the underlying block device differs.

---

## 2. Strategy A — Root disk (current default)

### 2.1 Architecture

```
DigitalOcean Droplet (160 GB SSD on s-4vcpu-8gb)
└── /var/lib/docker/volumes/
    ├── collector_prometheus_data
    ├── collector_loki_data
    ├── collector_tempo_data
    └── collector_grafana_data
```

### 2.2 Characteristics

| Aspect | Value |
| --- | --- |
| **Provisioning** | Automatic — no extra OpenTofu resources |
| **Complexity** | Low |
| **Cost** | Included in Droplet (~$48/mo for s-4vcpu-8gb) |
| **Performance** | Local SSD — sufficient for staging OTLP rates |
| **Survives container restart** | ✅ |
| **Survives host reboot** | ✅ |
| **Survives Droplet destroy** | ❌ — all TSDB data lost |
| **Resize** | Resize Droplet disk (may require power-off) |

### 2.3 Staging limitation (explicit)

> **Destroying the Droplet destroys all Prometheus, Loki, Tempo, and Grafana local data.** Grafana dashboards/datasources in Git are recoverable; time-series data is not.

### 2.4 When Strategy A is appropriate

- Staging and homologation
- Cost-sensitive environments
- Acceptable to lose historical metrics/logs/traces on host rebuild
- Disk monitoring via `df -h` and `docker system df`

---

## 3. Strategy B — Block Storage (designed, optional)

### 3.1 Architecture

```
DigitalOcean Droplet
├── Root disk (OS, Docker images, logs)
└── Attached Block Volume (128 GiB default)
    └── /mnt/ixora-observability-data/
        └── Docker volume data (via bind mount or Docker data-root relocation)
            ├── prometheus_data
            ├── loki_data
            ├── tempo_data
            └── grafana_data
```

### 3.2 OpenTofu resources (optional)

When `observability_use_block_volume = true`:

| Resource | Purpose |
| --- | --- |
| `digitalocean_volume.observability[0]` | Dedicated block storage |
| `digitalocean_volume_attachment.observability[0]` | Attach to Droplet |

**Not automated in Phase 8.8.5/8.8.6:** format, mount, fstab, Docker data-root relocation. Operator runbook required.

### 3.3 Pros

| Pro | Detail |
| --- | --- |
| **Data portability** | Volume survives Droplet destroy (when not deleted) |
| **Independent resize** | Expand block volume without resizing Droplet |
| **DR flexibility** | Reattach to replacement Droplet in same region |
| **Separation** | OS/Docker image churn isolated from TSDB data |
| **Production path** | Foundation for snapshot-based backups |

### 3.4 Cons

| Con | Detail |
| --- | --- |
| **Complexity** | Manual mount + Docker configuration |
| **Cost** | + block volume pricing (~$10/mo per 100 GiB — verify DO pricing) |
| **Performance** | Network-attached — slightly higher latency vs local SSD |
| **Single point of failure** | Volume still single-AZ; not HA |
| **Migration effort** | Moving from Strategy A requires downtime |

### 3.5 Performance expectations

| Workload | Strategy A | Strategy B |
| --- | --- | --- |
| OTLP ingest (staging) | Excellent | Good |
| Prometheus scrape | Excellent | Good |
| Dashboard queries | Excellent | Good — monitor query latency |
| Compaction I/O | Local SSD advantage | Monitor during Prometheus compaction |

For staging traffic levels documented in [infrastructure-review.md](infrastructure-review.md), Strategy B performance is **acceptable**.

---

## 4. Migration path (A → B) — manual, not automated

```
Phase 1 — Provision
  1. Set observability_use_block_volume = true in tfvars
  2. tofu apply (creates volume + attachment)
  3. SSH to host

Phase 2 — Prepare volume (one-time)
  4. Format if empty: mkfs.ext4 /dev/disk/by-id/scsi-0DO_Volume_*
  5. Mount: /mnt/ixora-observability-data
  6. Add fstab entry (use UUID, not device name)
  7. Verify idempotent mount on reboot

Phase 3 — Migrate data (maintenance window)
  8. docker compose stop
  9. rsync /var/lib/docker/volumes/collector_* → /mnt/ixora-observability-data/
  10. Reconfigure Docker Compose volume driver_opts OR bind mounts
  11. docker compose up -d
  12. Verify health + data continuity

Phase 4 — Validate
  13. Reboot host — confirm mount + stack auto-start
  14. Run validate.sh + health checks
```

**Rollback:** Restore compose volume config to Strategy A paths; rsync data back if needed.

---

## 5. Reserved IP (Floating IP) and storage

Reserved IP is a **network** concern, not a storage concern, but both improve DR:

| Feature | OpenTofu variable | Default | DR benefit |
| --- | --- | --- | --- |
| Reserved IP | `observability_use_reserved_ip` | `false` | DNS stability on Droplet replace |
| Block volume | `observability_use_block_volume` | `false` | Data survives Droplet replace |

**Recommended production combination:** Strategy B + Reserved IP + backup snapshots.

### 5.1 Reserved IP advantages

- DNS A records for `grafana-staging.ixora-app.app` and `otel-staging.ixora-app.app` remain valid
- App Platform `OTEL_EXPORTER_OTLP_ENDPOINT` unchanged after Droplet rebuild
- TLS certificates re-issue on same hostname (Caddy/Let's Encrypt)
- Faster recovery — no DNS propagation wait

### 5.2 Reserved IP — OpenTofu behavior

When `observability_use_reserved_ip = true`:

```
digitalocean_reserved_ip.observability[0]
digitalocean_reserved_ip_assignment.observability[0]
```

Output `observability_public_ipv4` returns the **Reserved IP** address (not ephemeral Droplet IP).

### 5.3 Disaster recovery with Reserved IP

```
1. Create replacement Droplet (tofu apply or manual)
2. Assign existing Reserved IP to new Droplet
3. Restore data (Strategy A: from backup; Strategy B: reattach volume)
4. Clone release + deploy
5. No DNS changes required
```

---

## 6. Cost implications

| Component | Strategy A | Strategy B | + Reserved IP |
| --- | --- | --- | --- |
| Droplet s-4vcpu-8gb | ~$48/mo | ~$48/mo | ~$48/mo |
| Block volume 128 GiB | — | ~$13/mo | ~$13/mo |
| Reserved IP | — | — | ~$4/mo |
| **Total (approx)** | **~$48/mo** | **~$61/mo** | **~$65/mo** |

Verify current DigitalOcean pricing before production budgeting ([ADR-031](../../../decisions/ADR-031-retention-storage-and-cost-control.md)).

---

## 7. Production evolution

| Milestone | Storage | Network |
| --- | --- | --- |
| Staging (now) | Strategy A | Ephemeral IP |
| Staging hardened | Strategy A + backups | Optional Reserved IP |
| Production v1 | Strategy B + snapshots | Reserved IP required |
| Production v2+ | Object storage archive (ADR future) | Reserved IP + future LB |

---

## 8. Cross-references

| Document | Role |
| --- | --- |
| [backup-strategy.md](backup-strategy.md) | Backup design per volume |
| [observability-infrastructure-provisioning.md](observability-infrastructure-provisioning.md) | Phase 8.8.5 provisioning |
| [observability-hardening.md](observability-hardening.md) | Hardening index |
