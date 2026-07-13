# Tempo Deployment — Phase 6

**Status:** Active  
**Phase:** 6 — Distributed Tracing Backend  
**Depends on:** [collector-deployment.md](collector-deployment.md) (Phase 3), [prometheus-deployment.md](prometheus-deployment.md) (Phase 4), [loki-deployment.md](loki-deployment.md) (Phase 5)  
**ADRs:** [ADR-028](../../../decisions/ADR-028-observability-platform.md), [ADR-029](../../../decisions/ADR-029-telemetry-data-model.md), [ADR-030](../../../decisions/ADR-030-observability-security-and-privacy.md), [ADR-031](../../../decisions/ADR-031-observability-operational-limits.md)  
**References:** [security-review.md](security-review.md), [collector-hardening-checklist.md](../../../operations/collector-hardening-checklist.md), [collector-validation-report.md](collector-validation-report.md), [metrics-philosophy.md](../../../architecture/metrics-philosophy.md), [logs-philosophy.md](../../../architecture/logs-philosophy.md), [telemetry-decision-guide.md](../../../architecture/telemetry-decision-guide.md), [observability-playbook.md](../../../operations/observability-playbook.md), [loki-deployment.md](loki-deployment.md)

---

## 1. Purpose and scope

Phase 6 introduces **Tempo** as the centralized distributed tracing backend for the Ixora Observability Platform. Trace data flows exclusively through the **OpenTelemetry Collector**, which remains the single ingestion endpoint for all telemetry signals.

**Invariants established by this phase:**

- Applications export OTLP Traces to the Collector — no change to application code.
- The Collector applies all processing (sampling, redaction, normalization, enrichment) before forwarding to Tempo.
- Tempo never receives data directly from any application or SDK.
- Prometheus (metrics) and Loki (logs) pipelines are completely unchanged.
- The `debug` exporter is **fully removed** from all Collector pipelines. All three signals now route to their respective backends.
- No Grafana changes (Phase 9).
- No SDK implementation (Phase 7 / Phase 8).

---

## 2. Architecture

```
back_vibes-api   back_vibes-worker   front_vibes-android
       │                 │                  │
       └────────OTLP Traces (gRPC/HTTP)─────┘
                          │
                          ▼
            ┌─────────────────────────────┐
            │   OpenTelemetry Collector   │
            │   ── memory_limiter         │
            │   ── resource               │  ← stamps deployment.environment
            │   ── attributes/redact      │  ← drops credentials, PII (ADR-030)
            │   ── transform/normalize    │  ← normalizes http.url → http.route
            │   ── probabilistic_sampler  │  ← 10% success (ADR-031)
            │   ── batch                  │
            │   ── otlp/tempo exporter    │  ← Phase 6 (active)
            └─────────────────────────────┘
                          │
              OTLP gRPC → tempo:4317
              (ixora-observability Docker network)
                          │
                          ▼
                  ┌──────────────┐
                  │    Tempo     │
                  │   2.6.0      │
                  │  port 3200   │
                  │  filesystem  │
                  │   7d retain  │
                  └──────────────┘
                          │
                    (Phase 9) Grafana ← TraceQL queries
```

**Architecture invariants:**

| Rule | Rationale |
| --- | --- |
| Collector is sole Tempo writer | ADR-028 — single ingestion path for auditability |
| All redaction before push | ADR-030 — Tempo never stores raw credentials or PII |
| Sampling in Collector | ADR-031 — 10% success traces; errors: see §7 |
| Tempo on internal Docker network only | ADR-028 — no public exposure |
| Application code unchanged | Phase 6 boundary — OTLP emission is SDK's responsibility (Phase 7) |

### Full pipeline map (Phase 6 complete)

| Signal | Pipeline | Exporter | Status |
| --- | --- | --- | --- |
| metrics | metrics | `prometheusremotewrite` → Prometheus | ✅ Active (Phase 4) |
| logs | logs | `loki` → Loki | ✅ Active (Phase 5) |
| traces | traces | `otlp/tempo` → Tempo | ✅ Active (Phase 6) |
| debug | *(all)* | `debug` | ❌ Removed (Phase 6) |

---

## 3. Container specification

| Property | Value |
| --- | --- |
| Image | `grafana/tempo:${TEMPO_VERSION:-2.6.0}` |
| Container name | `ixora-tempo` |
| Restart policy | `unless-stopped` |
| Config | `/etc/tempo/tempo.yaml` (read-only bind mount) |
| Data | `/var/tempo` (named Docker volume `tempo_data`) |
| HTTP query port | `3200` (internal + `127.0.0.1` host binding) |
| OTLP gRPC receiver port | `4317` (internal Docker network; `127.0.0.1` host binding for ops) |
| gRPC internal port | `9095` (Tempo internal components — no host binding) |
| Network | `ixora-observability` (same bridge as Collector, Prometheus, Loki) |

### Resource limits

| Limit | Value | Rationale |
| --- | --- | --- |
| CPU (max) | `0.5` vCPU | Tempo all-in-one — modest CPU at MVP scale |
| CPU (reserved) | `0.1` vCPU | Leaves headroom for Collector + Prometheus + Loki |
| Memory (max) | `512 MiB` | Ingester buffer + block cache; tune after Phase 7 SDK traffic |
| Memory (reserved) | `128 MiB` | Minimum for startup and WAL replay |

### Healthcheck

```yaml
test: ["CMD-SHELL", "wget --no-verbose --tries=1 --spider http://localhost:3200/ready || exit 1"]
interval: 30s
timeout: 10s
retries: 3
start_period: 30s
```

Tempo's `/ready` endpoint returns HTTP 200 when the ingester has initialized and is accepting writes.

---

## 4. Volumes and persistence

| Volume | Mount | Contents | Persists across |
| --- | --- | --- | --- |
| `tempo_data` | `/var/tempo` | Trace blocks, WAL, compactor state | Restarts, upgrades |

Tempo stores all state under `/var/tempo`:

```
/var/tempo/
├── blocks/    ← completed trace blocks (Parquet format, 7-day retention)
└── wal/       ← write-ahead log (ingester durability before flush)
```

The named Docker volume `tempo_data` is declared in `docker-compose.yml` and survives `docker compose down`, container replacement, and image upgrades. The volume is **never** removed unless explicitly purged (`docker volume rm tempo_data`).

---

## 5. Tempo configuration summary

Configuration file: `collector/tempo/tempo.yaml`

### Storage

| Setting | Value | Notes |
| --- | --- | --- |
| Backend | `local` (filesystem) | Single-VM MVP; see object-storage migration note below |
| Block encoding | `snappy` | CPU-efficient; standard for single-VM |
| WAL | enabled | Ingester durability — survives unclean shutdown |
| Bloom filter false positive | `0.05` | 5% false positive rate — balanced for MVP query speed |

### Retention

| Setting | Value | Rationale |
| --- | --- | --- |
| `compactor.compaction.block_retention` | `168h` (7 days) | ADR-031 §MVP retention |
| Compactor enforces | Block-level deletion after retention expiry | Automated — no manual intervention |

**Why 7 days, not 14 (Loki) or 30 (Prometheus)?**

Traces are the most storage-intensive signal — each span contains timing, attributes, and event data. With 10% sampling, a single day of staging traffic can accumulate significant block storage. 7 days provides enough retention for post-incident investigation while keeping the storage budget manageable on the MVP single-VM (ADR-031). Older incidents are covered by Prometheus metrics trends (30 days) and Loki logs (14 days) for context.

**Why traces are sampled:**

Traces capture every step of every request. At production scale, storing 100% of traces would require terabytes of storage. Probabilistic head sampling (10% of successful traces) keeps storage within budget while preserving statistical accuracy for dashboards and p95 latency analysis. Error traces are not explicitly filtered out — see §7 for the sampling discussion.

### Ingester

| Setting | Value | Purpose |
| --- | --- | --- |
| `max_block_duration` | `5m` | Flush after 5 minutes of idle time |
| `max_block_bytes` | `1 GiB` | Flush if block exceeds 1 GiB before timeout |
| `trace_idle_period` | `10s` | Close a trace after 10s of no new spans |

### Limits (per-tenant, single tenant in MVP)

| Setting | Value | Purpose |
| --- | --- | --- |
| `ingestion.rate_limit_bytes` | `15 MiB/s` | Sustained ingestion cap |
| `ingestion.burst_size_bytes` | `20 MiB/s` | Short-burst allowance |
| `ingestion.max_traces_per_user` | `10 000` | Active traces in ingester |
| `read.max_bytes_per_trace` | `5 MiB` | Max trace size returned by query |

---

## 6. Collector changes (Phase 6)

### Exporter added

```yaml
# collector/config.yaml
exporters:
  otlp/tempo:
    endpoint: "${env:TEMPO_ENDPOINT}"
    tls:
      insecure: true
```

### Debug exporter removed

The `debug` exporter is **fully removed** from `collector/config.yaml` in Phase 6. It was the last remaining pipeline to retain it.

| Phase | State |
| --- | --- |
| Phase 3 | `debug` in metrics + logs + traces |
| Phase 4 | `debug` removed from metrics |
| Phase 5 | `debug` removed from logs |
| **Phase 6** | **`debug` removed from traces — fully eliminated** |

### Traces pipeline updated

| Phase | Traces pipeline exporter | Rationale |
| --- | --- | --- |
| Phase 5 | `debug` | Tempo not yet deployed |
| **Phase 6** | **`otlp/tempo`** | Tempo active; `debug` removed |

```yaml
# collector/config.yaml — traces pipeline (Phase 6)
traces:
  receivers:
    - otlp/backend
    - otlp/mobile
  processors:
    - memory_limiter
    - resource
    - attributes/redact_secrets   # ADR-030: redact before push to Tempo
    - transform/normalize_http    # normalize http.url → http.route
    - probabilistic_sampler       # 10% success (ADR-031)
    - batch
  exporters:
    - otlp/tempo   # Phase 6: Tempo active
```

### Metrics and logs pipelines — unchanged

The metrics pipeline (`prometheusremotewrite` → Prometheus) and logs pipeline (`loki` → Loki) are **not modified** in Phase 6.

---

## 7. Sampling

### Current architecture (Phase 6)

The Collector uses a **probabilistic head sampler** (`probabilistic_sampler` processor) at 10% for all traces passing through the `traces` pipeline. This is configured in `config.yaml` and documented in ADR-031.

| Trace type | Sampling rate | Mechanism |
| --- | --- | --- |
| Successful traces | 10% | `probabilistic_sampler` (hash-based) |
| Error traces | ~10% | Same probabilistic sampler — no explicit error policy |

**Limitation:** The probabilistic sampler operates before span status is fully resolved in some SDKs (e.g., PHP OTel SDK may not set error status on root spans consistently). As a result, error traces are not guaranteed to be 100% sampled under the current architecture.

### Tail sampling — Phase 7+ evolution

The Phase 3 design stub noted that a `tail_sampling` processor would provide proper 100% error coverage. This is deferred to Phase 7 because:

1. Tail sampling requires active application traces to validate policies.
2. The `tail_sampling` processor requires a decision wait window (e.g., 5s) and additional memory for the in-progress trace buffer.
3. There are no application SDKs yet (Phase 7 / Phase 8) — no real error traces to sample.

**Phase 7 tail sampling design (documented here for forward reference):**

```yaml
# Proposed Phase 7 tail_sampling processor (not yet active)
tail_sampling:
  decision_wait: 5s
  num_traces: 50000
  expected_new_traces_per_sec: 100
  policies:
    - name: errors-policy
      type: status_code
      status_code: { status_codes: [ERROR] }   # 100% error traces
    - name: success-sampling
      type: probabilistic
      probabilistic: { sampling_percentage: 10 } # 10% success traces
```

When implemented, remove `probabilistic_sampler` from the traces pipeline and replace with `tail_sampling`. The pipeline will then provide exact guarantees: 100% errors + 10% success.

---

## 8. Security

This phase follows the security posture established in [security-review.md](security-review.md), [ADR-028](../../../decisions/ADR-028-observability-platform.md), [ADR-029](../../../decisions/ADR-029-telemetry-data-model.md), [ADR-030](../../../decisions/ADR-030-observability-security-and-privacy.md), and [ADR-031](../../../decisions/ADR-031-observability-operational-limits.md).

### Network isolation

| Component | Accessible from | Not accessible from |
| --- | --- | --- |
| Tempo port 3200 (HTTP) | Host `127.0.0.1`, Grafana (Phase 9) via Docker network | Internet, application containers on other networks |
| Tempo port 4317 (OTLP gRPC) | Collector (Docker network), Host `127.0.0.1` for ops | Internet, application containers |
| Tempo port 9095 (gRPC internal) | Tempo internal components only | Host, internet |

### Write access

| Actor | Can write to Tempo? | Mechanism |
| --- | --- | --- |
| OpenTelemetry Collector | ✅ Yes | `otlp/tempo` exporter via Docker network |
| `back_vibes-api` | ❌ No | Not on `ixora-observability` network |
| `back_vibes-worker` | ❌ No | Not on `ixora-observability` network |
| `front_vibes-android` | ❌ No | Mobile — no internal network access |
| Any external actor | ❌ No | Ports not exposed to internet |

### Redaction before storage

The `attributes/redact_secrets` processor removes all ADR-030 forbidden fields before the `otlp/tempo` exporter pushes to Tempo. Tempo never stores raw credential or PII values.

### No metrics_generator

Tempo's `metrics_generator` (which can generate service graph metrics from traces) is **disabled**. Prometheus handles all metrics via the Collector's `prometheusremotewrite` exporter. Enabling `metrics_generator` would create duplicate series and conflict with the existing Prometheus setup.

---

## 9. Validation steps

Run these checks after deploying Phase 6. Mirrors the validation checklist in [collector/README.md](../../../../collector/README.md).

### 9.1 Service health

```bash
# Tempo ready
curl http://127.0.0.1:3200/ready
# Expected: "ready"

# Tempo metrics exposed
curl -s http://127.0.0.1:3200/metrics | grep tempo_ingester_traces_created_total
# Expected: metric line present
```

### 9.2 Collector → Tempo pipeline

```bash
# Collector logs: verify otlp/tempo exporter present
docker compose logs collector --since=2m | grep -i tempo
# Expected: "tempo" references in startup or export logs

# Check for exporter errors
docker compose logs collector --since=5m | grep -E "error|failed" | grep -v "#"
# Expected: no tempo-related errors
```

### 9.3 Debug exporter fully removed

```bash
# Confirm no active debug exporter in any pipeline
grep 'debug' collector/config.yaml | grep -v '#'
# Expected: empty output (debug only appears in comments)
```

### 9.4 End-to-end trace validation

```bash
# Send a test span via Collector OTLP HTTP (replace API key)
curl -X POST http://127.0.0.1:4318/v1/traces \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer <OTEL_INGEST_API_KEY_BACKEND>" \
  -d '{
    "resourceSpans": [{
      "resource": {
        "attributes": [
          {"key": "service.name", "value": {"stringValue": "test-service"}},
          {"key": "deployment.environment", "value": {"stringValue": "staging"}}
        ]
      },
      "scopeSpans": [{
        "spans": [{
          "traceId": "4bf92f3577b34da6a3ce929d0e0e4736",
          "spanId": "00f067aa0ba902b7",
          "name": "phase-6-tempo-validation",
          "startTimeUnixNano": "'"$(date +%s%N)"'",
          "endTimeUnixNano": "'"$(( $(date +%s%N) + 5000000 ))"'",
          "status": {}
        }]
      }]
    }]
  }'
# Expected: HTTP 200

# Wait for batch flush then query Tempo by trace ID
sleep 12
curl -s "http://127.0.0.1:3200/api/traces/4bf92f3577b34da6a3ce929d0e0e4736" | jq .
# Expected: JSON trace with phase-6-tempo-validation span name
```

### 9.5 Persistence

```bash
# Restart Tempo and verify data survives
docker compose restart tempo
sleep 20
curl http://127.0.0.1:3200/ready
# Expected: "ready"

# Confirm trace still queryable after restart (WAL replay)
curl -s "http://127.0.0.1:3200/api/traces/4bf92f3577b34da6a3ce929d0e0e4736" | jq .traces
# Expected: trace data present (WAL + block storage survived restart)
```

### 9.6 Retention configuration

```bash
# Confirm 7-day retention
grep block_retention collector/tempo/tempo.yaml
# Expected: block_retention: 168h
```

### 9.7 Security verification

```bash
# Tempo not publicly reachable (run from external host)
# curl --connect-timeout 5 http://<VM_PUBLIC_IP>:3200/ready
# Expected: Connection refused or timeout

# Network isolation — only observability containers on internal network
docker network inspect ixora-observability \
  | jq '.[].Containers | to_entries[] | .value.Name'
# Expected: ixora-otel-collector, ixora-prometheus, ixora-loki, ixora-tempo

# Verify no active debug exporter
grep '^  - debug' collector/config.yaml
# Expected: empty (no pipeline references debug exporter)
```

---

## 10. Object-storage migration note (Phase 10+)

The current filesystem storage is appropriate for a single-VM MVP. To migrate to object storage (DigitalOcean Spaces or AWS S3):

1. Update `storage.trace.backend: s3` in `tempo.yaml`.
2. Add `storage.trace.s3` block with bucket, endpoint, and credentials.
3. Existing local blocks remain readable until they age out of the 7-day retention window. No data migration is required if the transition is done within 7 days of deployment.
4. No Collector or application changes are needed.

---

## 11. Upgrade strategy

```bash
# 1. Update version in collector/.env
TEMPO_VERSION=2.7.0

# 2. Review Tempo release notes for breaking changes
#    https://grafana.com/docs/tempo/latest/setup/upgrade/

# 3. Pull and restart Tempo only (Collector, Prometheus, Loki unaffected)
cd collector
docker compose pull tempo
docker compose up -d --no-deps tempo

# 4. Validate
curl http://127.0.0.1:3200/ready
docker compose logs tempo --since=2m

# 5. Confirm trace data survived (named volume)
curl -s http://127.0.0.1:3200/api/search \
  --data-urlencode "minDuration=0ms" \
  | jq '.traces | length'
# Expected: > 0 if traces were ingested before upgrade
```

---

## 12. Remaining work

### Phase 6.5 — Traces Philosophy (optional documentation phase)

A `traces-philosophy.md` architectural guide — analogous to `metrics-philosophy.md` and `logs-philosophy.md` — should be created before Phases 7 and 8 ship application instrumentation. It would cover:

- When to start a new trace vs add a span vs add a span event
- Span naming conventions and attribute expectations
- Sampling rationale and implications for error investigation
- Cross-signal correlation (`trace_id` in logs, exemplars in metrics)
- Anti-patterns: logging inside spans, over-instrumentation, PII in span attributes

This is not strictly required for Phase 7 since `telemetry-decision-guide.md` and `telemetry-naming-convention.md` cover the basics, but a dedicated guide would improve instrumentation consistency.

### Phase 7 — Backend SDK (`back_vibes`)

1. Integrate OpenTelemetry PHP SDK (or a Laravel-compatible package).
2. Auto-instrument HTTP requests, queue jobs, console commands.
3. Manual spans for Smart Home adapter calls, push delivery jobs.
4. Inject `trace_id` into Laravel `Log::` context for Loki ↔ Tempo correlation.
5. Validate: traces reach Collector → Tempo; logs contain `trace_id`; no forbidden fields.
6. Implement `tail_sampling` processor in Collector to replace `probabilistic_sampler` (guaranteed 100% error coverage).
7. Env: `OTEL_EXPORTER_OTLP_ENDPOINT`, `OTEL_SERVICE_NAME`, `OTEL_EXPORTER_OTLP_HEADERS`.
8. Follow `logs-philosophy.md` and `metrics-philosophy.md` before adding instrumentation.

### Phase 9 — Grafana Dashboards

1. Uncomment the `grafana` service stub in `docker-compose.yml`.
2. Provision Tempo datasource (`http://tempo:3200`).
3. Provision Loki datasource (`http://loki:3100`).
4. Provision Prometheus datasource (`http://prometheus:9090`).
5. Create trace-exploration panel using TraceQL.
6. Link Loki log lines to Tempo traces via `trace_id` field.

---

## 13. Cross-references

| Document | Relationship |
| --- | --- |
| [collector-validation-report.md](collector-validation-report.md) | Phase 3.5 — Collector baseline validation |
| [loki-deployment.md](loki-deployment.md) | Phase 5 — Logs backend (unchanged in Phase 6) |
| [prometheus-deployment.md](prometheus-deployment.md) | Phase 4 — Metrics backend (unchanged in Phase 6) |
| [metrics-philosophy.md](../../../architecture/metrics-philosophy.md) | Cardinality and retention discipline for metrics |
| [logs-philosophy.md](../../../architecture/logs-philosophy.md) | Log design — complements trace correlation |
| [telemetry-decision-guide.md](../../../architecture/telemetry-decision-guide.md) | Signal choice — when traces beat logs or metrics |
| [observability-playbook.md](../../../operations/observability-playbook.md) | Investigation runbook — metrics → traces → logs |
| [security-review.md](security-review.md) | Security posture — Tempo follows same rules as Loki |
| [collector-hardening-checklist.md](../../../operations/collector-hardening-checklist.md) | Deploy checklist |
| [ADR-028](../../../decisions/ADR-028-observability-platform.md) | Single ingestion path — Collector only |
| [ADR-029](../../../decisions/ADR-029-telemetry-data-model.md) | Telemetry data model — span and trace structure |
| [ADR-030](../../../decisions/ADR-030-observability-security-and-privacy.md) | Redaction before storage |
| [ADR-031](../../../decisions/ADR-031-observability-operational-limits.md) | Retention (7d traces), sampling (10%), cardinality limits |
