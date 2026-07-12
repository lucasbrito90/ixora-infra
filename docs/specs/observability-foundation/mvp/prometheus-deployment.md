# Prometheus Deployment — Phase 4

**Status:** Phase 4 complete  
**Spec:** [`spec.md`](spec.md) · **Plan:** [`plan.md`](plan.md) · **Tasks:** [`tasks.md`](tasks.md)  
**ADRs:** [ADR-028](../../../decisions/ADR-028-observability-platform.md) · [ADR-029](../../../decisions/ADR-029-telemetry-data-model.md) · [ADR-030](../../../decisions/ADR-030-observability-security-and-privacy.md) · [ADR-031](../../../decisions/ADR-031-retention-storage-and-cost-control.md)  
**References:** [infrastructure-review.md](infrastructure-review.md) · [security-review.md](security-review.md) · [collector-validation-report.md](collector-validation-report.md)  
**Implementation:** [`collector/docker-compose.yml`](../../../../collector/docker-compose.yml) · [`collector/prometheus/prometheus.yml`](../../../../collector/prometheus/prometheus.yml) · [`collector/config.yaml`](../../../../collector/config.yaml)

> **Phase 4 scope:** Deploy Prometheus as the metrics backend. Enable the `prometheusremotewrite` exporter in the Collector. Remove the debug exporter from the metrics pipeline. No application instrumentation, no Grafana, no Loki, no Tempo, no SDK changes.

---

## 1. Architecture

```
Applications (back_vibes-api, back_vibes-worker, front_vibes-android)
        │
        │  OTLP (gRPC :4317 / HTTP :4318 / HTTP :4319)
        │  Bearer token auth — security-review.md §3
        ▼
┌────────────────────────────────────┐
│   OpenTelemetry Collector          │ (Phase 3 — unchanged)
│                                    │
│   Receivers: otlp/backend          │
│              otlp/mobile           │
│              prometheus/self ──────┼─── scrapes :8888 (Collector self-metrics)
│                                    │
│   Processors:                      │
│     memory_limiter                 │
│     resource                       │
│     attributes/redact_secrets      │
│     attributes/drop_high_cardinality│
│     batch                          │
│                                    │
│   Exporter: prometheusremotewrite ─┼──► POST /api/v1/write
└────────────────────────────────────┘        │
                                              │  Docker network: ixora-observability
                                              │  http://prometheus:9090/api/v1/write
                                              ▼
                                 ┌──────────────────────┐
                                 │   Prometheus TSDB    │
                                 │   :9090 (internal)   │
                                 │   30-day retention   │
                                 │   named volume       │
                                 └──────────────────────┘
                                              │
                                    (Phase 9 — Grafana datasource)
```

### Data flow

| Step | Component | Action |
| --- | --- | --- |
| 1 | Application | Exports OTLP metrics to Collector |
| 2 | Collector — `prometheus/self` receiver | Scrapes Collector self-metrics at `:8888` every 30 s |
| 3 | Collector — processors | Memory limiter → resource stamp → redact secrets → drop high-cardinality labels → batch |
| 4 | Collector — `prometheusremotewrite` | Pushes metric batches to `http://prometheus:9090/api/v1/write` |
| 5 | Prometheus — remote write receiver | Ingests metric samples into TSDB |
| 6 | Prometheus — self scrape | Scrapes own `/metrics` endpoint every 30 s |

### What Prometheus does NOT do in Phase 4

- Does **not** scrape any application container directly
- Does **not** scrape the Collector's `:8888` directly (Collector handles its own self-metrics via `prometheus/self` receiver)
- Does **not** expose any public endpoint
- Does **not** run alert rules (Phase 10+)
- Does **not** push to any remote storage (single VM MVP)

---

## 2. Container specification

| Property | Value | Reference |
| --- | --- | --- |
| Image | `prom/prometheus:${PROMETHEUS_VERSION:-v2.54.1}` | Pin in `.env` — never `:latest` |
| Container name | `ixora-prometheus` | Consistent ops identity |
| Network | `ixora-observability` (bridge) | Shared with Collector |
| Host port binding | `127.0.0.1:9090:9090` | Internal only — ADR-028 |
| Restart policy | `unless-stopped` | Survives VM reboot |
| CPU limit | `1.0` vCPU | Headroom for query bursts |
| CPU reservation | `0.25` vCPU | Minimum guaranteed |
| Memory limit | `1G` | ~10 000 series × 30d budget |
| Memory reservation | `256M` | Baseline idle |
| Log driver | `json-file` 50 MB × 3 files | Bounded container log retention |

---

## 3. Volumes and persistence

| Volume | Type | Mount | Purpose |
| --- | --- | --- | --- |
| `prometheus_data` | Named Docker volume | `/prometheus` | TSDB blocks, WAL, chunks — persists restarts and upgrades |
| `./prometheus/prometheus.yml` | Read-only bind | `/etc/prometheus/prometheus.yml` | Prometheus configuration |

### Persistence guarantees

- `prometheus_data` is a **named Docker volume** declared in `docker-compose.yml`. It survives `docker compose restart`, `docker compose up --no-deps prometheus`, and container recreation.
- Running `docker compose down` without `-v` preserves the volume.
- Running `docker compose down -v` **destroys** the volume — only do this to reset the stack intentionally.
- Upgrading Prometheus image: `docker compose pull prometheus && docker compose up -d --no-deps prometheus` — volume is not touched; TSDB is compatible across minor versions.

---

## 4. Retention and storage

| Parameter | Value | Source |
| --- | --- | --- |
| Retention time | `30d` | ADR-031 §MVP retention |
| TSDB path | `/prometheus` (named volume) | docker-compose.yml |
| WAL compression | Enabled (`--storage.tsdb.wal-compression`) | Reduces WAL I/O on single-disk VM |
| Block compaction | Default (2h blocks) | Prometheus default |
| Remote write receiver | Enabled (`--web.enable-remote-write-receiver`) | Receives from Collector |
| Lifecycle API | Enabled (`--web.enable-lifecycle`) | Hot reload for rule files (Phase 10+) |

### Estimated disk usage

| Scenario | Series | Samples/s | 30-day estimate |
| --- | --- | --- | --- |
| MVP Phase 4 (Collector self-metrics only) | ~300 | ~10 | ≤ 200 MB |
| After Phase 7 (back_vibes instrumented) | ≤ 10 000 | ≤ 200 | ≤ 5 GB |
| Budget cap (ADR-031 §storage limits) | — | — | 40% of disk budget |

ADR-031 requires action before **85%** total VM disk utilisation.

---

## 5. Security

### Boundary enforcement (ADR-028)

| Rule | Implementation |
| --- | --- |
| Prometheus not publicly accessible | `ports: 127.0.0.1:9090:9090` — host binding restricts to localhost |
| No direct app → Prometheus writes | No remote write config in application repos; Collector is sole writer |
| No application scrape targets | `prometheus.yml` contains only `job_name: prometheus` (self-scrape) |
| No secrets in configuration | All sensitive values injected via `.env`; `prometheus.yml` has none |
| VM firewall | Port 9090 must be blocked on the DO Droplet firewall (ADR-028 §security) |

### Network isolation

```
Internet ──► (DO Firewall) ──► VM public IP
                                    │
                                    ├── Port 4317/4318/4319 → Collector (public, TLS)
                                    └── Port 9090 → BLOCKED by firewall

VM localhost / Docker network (ixora-observability):
    Collector ──► http://prometheus:9090/api/v1/write  ✅
    Grafana   ──► http://prometheus:9090               ✅ (Phase 9, same network)
    External  ──► http://<VM_IP>:9090                  ❌ (firewall blocks)
```

### ADR-030 compliance

All metrics entering Prometheus have already passed through the Collector processor chain:

| Processor | Effect on data reaching Prometheus |
| --- | --- |
| `attributes/redact_secrets` | Credential and PII keys deleted before remote write |
| `attributes/drop_high_cardinality` | `user_id`, `schedule_id`, `device_id`, `vibe_id`, `trace_id` removed |
| `resource_to_telemetry_conversion: true` | `service.name` → `service_name` label (bounded; not PII) |

---

## 6. Collector changes (Phase 3 → Phase 4)

### `collector/config.yaml`

| Change | Detail |
| --- | --- |
| Header updated | Phase 3 → Phase 4 with backend status table |
| `prometheusremotewrite` exporter enabled | `endpoint: ${env:PROMETHEUS_REMOTE_WRITE_ENDPOINT}` |
| `resource_to_telemetry_conversion: true` | Promotes OTel resource attributes to Prometheus labels |
| `remote_write_queue.enabled: true` | Explicit queue for buffering during Prometheus restarts |
| `debug` removed from **metrics pipeline** | Prometheus is now the metrics backend |
| `debug` retained in **logs and traces pipelines** | Loki and Tempo not yet deployed |
| Loki/Tempo stub endpoint comments updated | `127.0.0.1` → `loki:3100` / `tempo:4317` (Docker service names) |
| Metrics pipeline comment updated | Documents current Phase 4 state |

### `collector/.env.example`

| Change | Detail |
| --- | --- |
| `PROMETHEUS_VERSION` added | Pin Prometheus image version |
| `PROMETHEUS_REMOTE_WRITE_ENDPOINT` activated | `http://prometheus:9090/api/v1/write` |
| `PROMETHEUS_PORT` added | Host port (default `9090`) |
| Loki/Tempo stub comments updated | Docker service name endpoints |

### Why `http://prometheus:9090` and not `http://127.0.0.1:9090`

Inside Docker Compose, each service runs in its own network namespace. `127.0.0.1` inside the Collector container refers to the Collector itself, not Prometheus. The Docker bridge network `ixora-observability` provides DNS resolution by service name — `prometheus` resolves to the Prometheus container IP. Using service names is the correct Docker Compose inter-container communication pattern.

---

## 7. Prometheus configuration reference

See [`collector/prometheus/prometheus.yml`](../../../../collector/prometheus/prometheus.yml) for the full annotated configuration.

| Setting | Value | Purpose |
| --- | --- | --- |
| `global.scrape_interval` | `30s` | Balances resolution and write pressure |
| `global.evaluation_interval` | `30s` | Matches scrape interval; ready for rules (Phase 10+) |
| `global.external_labels.cluster` | `ixora-observability-staging` | Identifies Prometheus instance |
| `scrape_configs[0].job_name` | `prometheus` | Self-scrape only |
| `scrape_configs[0].targets` | `['localhost:9090']` | Prometheus own `/metrics` |
| Alert rules | None (Phase 10+) | Reserved |
| Remote write receiver | CLI flag — not in `prometheus.yml` | `--web.enable-remote-write-receiver` |
| Retention | CLI flag — not in `prometheus.yml` | `--storage.tsdb.retention.time=30d` |

### Why alerting is deferred

Phase 10 (Operational Readiness) defines thresholds, runbooks, and routing before wiring Alertmanager. Premature alert rules without validated thresholds cause alert fatigue and are explicitly out of MVP scope ([spec.md §3 Non-goals](spec.md)).

---

## 8. Healthcheck

Prometheus exposes two built-in health endpoints:

| Endpoint | Expected response | Meaning |
| --- | --- | --- |
| `GET /-/healthy` | `200 Prometheus Server is Healthy.` | Process is alive |
| `GET /-/ready` | `200 Prometheus Server is Ready.` | TSDB is ready to serve queries |

The Docker Compose `healthcheck` uses `wget` (available in the Prometheus image):

```yaml
healthcheck:
  test: ["CMD-SHELL", "wget --no-verbose --tries=1 --spider http://localhost:9090/-/healthy || exit 1"]
  interval: 30s
  timeout: 10s
  retries: 3
  start_period: 30s
```

`start_period: 30s` allows TSDB initialisation before the healthcheck begins counting failures.

---

## 9. Validation steps

Run after deploying Phase 4. Full checklist is in [`collector/README.md`](../../../../collector/README.md).

### 9.1 Container and process

```bash
# Both services running
docker compose ps collector prometheus

# Collector health
curl -s http://127.0.0.1:13133/health

# Prometheus health
curl http://127.0.0.1:9090/-/healthy
curl http://127.0.0.1:9090/-/ready
```

### 9.2 Metrics pipeline

```bash
# Collector self-metrics arrive in Prometheus via remote write
# (allow ~60 s for first scrape + batch + remote write cycle)
curl -s 'http://127.0.0.1:9090/api/v1/query?query=otelcol_process_uptime_seconds' \
  | jq '.data.result[0].metric'
# Expected: {"job":"otel-collector","service_name":"otel-collector",...}

# Prometheus self-metrics
curl -s 'http://127.0.0.1:9090/api/v1/query?query=prometheus_tsdb_head_series' \
  | jq '.data.result[0].value[1]'
# Expected: "300" (approx — Collector self-metrics series count)
```

### 9.3 Retention flag

```bash
curl -s http://127.0.0.1:9090/api/v1/status/flags \
  | jq '."storage.tsdb.retention.time"'
# Expected: "30d"
```

### 9.4 Remote write queue health

```bash
# No failed samples — remote write queue healthy
curl -s 'http://127.0.0.1:9090/api/v1/query?query=prometheus_remote_storage_failed_samples_total' \
  | jq '.data.result'
# Expected: [] or value of 0
```

### 9.5 Persistence after restart

```bash
# Record current series count
BEFORE=$(curl -s 'http://127.0.0.1:9090/api/v1/query?query=prometheus_tsdb_head_series' \
  | jq '.data.result[0].value[1]')

# Restart Prometheus
docker compose restart prometheus
sleep 15

# Verify data survived
AFTER=$(curl -s 'http://127.0.0.1:9090/api/v1/query?query=prometheus_tsdb_head_series' \
  | jq '.data.result[0].value[1]')

echo "Before: $BEFORE  After: $AFTER"
# Expected: AFTER ≥ BEFORE (data from named volume persists)
```

### 9.6 Security confirmation

```bash
# No application containers in scrape targets
curl -s http://127.0.0.1:9090/api/v1/targets | jq '.data.activeTargets[].labels.job'
# Expected: only "prometheus"

# Confirm debug exporter absent from metrics pipeline
grep -A5 'metrics:' collector/config.yaml | grep 'debug'
# Expected: no output (debug removed from metrics pipeline)
```

---

## 10. Upgrade strategy

```bash
# 1. Update PROMETHEUS_VERSION in .env
# 2. Pull new image
docker compose pull prometheus

# 3. Restart Prometheus only — Collector unaffected
docker compose up -d --no-deps prometheus

# 4. Validate health and data
curl http://127.0.0.1:9090/-/healthy
curl -s 'http://127.0.0.1:9090/api/v1/query?query=prometheus_tsdb_head_series' \
  | jq '.data.result[0].value[1]'

# 5. Check logs for TSDB compatibility warnings
docker compose logs prometheus --since=5m
```

**TSDB compatibility across Prometheus versions:** Named volumes are preserved across upgrades. Prometheus maintains TSDB backwards compatibility within major versions. Upgrading from 2.x to 3.x may require a TSDB migration — follow the Prometheus release notes.

---

## 11. Phase 5 preparation

Phase 5 (Loki) can now begin. The metrics pipeline is complete. Before Phase 5:

- [ ] Confirm `otelcol_*` series visible in Prometheus after 30 s warm-up
- [ ] Confirm retention flag `30d` active
- [ ] Confirm no `debug` exporter in metrics pipeline
- [ ] Confirm Prometheus port 9090 blocked at DO Droplet firewall

Phase 5 will:
- Enable Loki service in `docker-compose.yml`
- Create `collector/loki/loki.yaml`
- Enable `loki` exporter in `config.yaml`
- Replace `debug` with `loki` in the logs pipeline

---

## Related documents

| Document | Role |
| --- | --- |
| [ADR-028](../../../decisions/ADR-028-observability-platform.md) | Collector-only ingestion; no direct app access to Prometheus |
| [ADR-029](../../../decisions/ADR-029-telemetry-data-model.md) | Metrics data model; `ixora.*` naming |
| [ADR-030](../../../decisions/ADR-030-observability-security-and-privacy.md) | No PII; redaction before remote write |
| [ADR-031](../../../decisions/ADR-031-retention-storage-and-cost-control.md) | 30-day retention; cardinality limits |
| [infrastructure-review.md](infrastructure-review.md) | VM topology; network; disk budgets |
| [security-review.md](security-review.md) | Auth model; TLS; firewall policy |
| [collector-deployment.md](collector-deployment.md) | Phase 3 — Collector configuration reference |
| [collector-validation-report.md](collector-validation-report.md) | Phase 3.5 — hardening sign-off |
| [metrics-philosophy.md](../../../architecture/metrics-philosophy.md) | Phase 3.75 — how to think about metrics |
| [telemetry-naming-convention.md](../../../architecture/telemetry-naming-convention.md) | `ixora.*` metric naming; label allowlist |
| [telemetry-decision-guide.md](../../../architecture/telemetry-decision-guide.md) | When metrics vs logs vs traces |
| [observability-playbook.md](../../../operations/observability-playbook.md) | Investigation workflows using metrics |
| [collector/README.md](../../../../collector/README.md) | Quick start + validation checklist |
