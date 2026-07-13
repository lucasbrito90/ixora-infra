# Loki Deployment — Phase 5

**Status:** Active  
**Phase:** 5 — Centralized Log Backend  
**Depends on:** [collector-deployment.md](collector-deployment.md) (Phase 3), [prometheus-deployment.md](prometheus-deployment.md) (Phase 4)  
**ADRs:** [ADR-028](../../../decisions/ADR-028-observability-platform.md), [ADR-029](../../../decisions/ADR-029-telemetry-data-model.md), [ADR-030](../../../decisions/ADR-030-observability-security-and-privacy.md), [ADR-031](../../../decisions/ADR-031-observability-operational-limits.md)  
**References:** [security-review.md](security-review.md), [collector-hardening-checklist.md](../../../operations/collector-hardening-checklist.md), [collector-validation-report.md](collector-validation-report.md), [metrics-philosophy.md](../../../architecture/metrics-philosophy.md), [telemetry-decision-guide.md](../../../architecture/telemetry-decision-guide.md), [observability-playbook.md](../../../operations/observability-playbook.md)

---

## 1. Purpose and scope

Phase 5 introduces **Loki** as the centralized log aggregation backend for the Ixora Observability Platform. Log data flows exclusively through the **OpenTelemetry Collector**, which remains the single ingestion endpoint for all telemetry signals.

**Invariants established by this phase:**

- Applications export OTLP Logs to the Collector — no change to application code.
- The Collector applies all processing (redaction, normalization, enrichment) before forwarding to Loki.
- Loki never receives data directly from any application or SDK.
- Prometheus and the metrics pipeline are completely unchanged.
- No Tempo configuration changes (Phase 6).
- No Grafana changes (Phase 9).

---

## 2. Architecture

```
back_vibes-api   back_vibes-worker   front_vibes-android
       │                 │                  │
       └────────OTLP Logs (gRPC/HTTP)───────┘
                          │
                          ▼
            ┌─────────────────────────┐
            │  OpenTelemetry Collector │
            │  ── memory_limiter      │
            │  ── resource            │  ← stamps deployment.environment
            │  ── attributes/redact   │  ← drops credentials, PII (ADR-030)
            │  ── batch               │
            │  ── loki exporter       │  ← Phase 5 (active)
            └─────────────────────────┘
                          │
              HTTP POST /loki/api/v1/push
              (ixora-observability Docker network)
                          │
                          ▼
                  ┌──────────────┐
                  │     Loki     │
                  │  3.2.0       │
                  │  port 3100   │
                  │  filesystem  │
                  │  14d retain  │
                  └──────────────┘
                          │
                    (Phase 9) Grafana ← LogQL queries
```

**Architecture invariants:**

| Rule | Rationale |
| --- | --- |
| Collector is sole Loki writer | ADR-028 — single ingestion path for auditability |
| All redaction before push | ADR-030 — Loki never stores raw credentials or PII |
| Loki on internal Docker network only | ADR-028 — no public exposure |
| Labels from resource attributes only | ADR-031 — cardinality control |
| Application code unchanged | Phase 5 boundary — OTLP emission is SDK's responsibility |

---

## 3. Container specification

| Property | Value |
| --- | --- |
| Image | `grafana/loki:${LOKI_VERSION:-3.2.0}` |
| Container name | `ixora-loki` |
| Restart policy | `unless-stopped` |
| Config | `/etc/loki/loki.yaml` (read-only bind mount) |
| Data | `/loki` (named Docker volume `loki_data`) |
| HTTP port | `3100` (internal + `127.0.0.1` host binding) |
| gRPC port | `9096` (internal only — no host binding) |
| Network | `ixora-observability` (same bridge as Collector) |

### Resource limits

| Limit | Value | Rationale |
| --- | --- | --- |
| CPU (max) | `0.5` vCPU | Loki all-in-one is not CPU-intensive at MVP scale |
| CPU (reserved) | `0.1` vCPU | Leaves headroom for Collector + Prometheus on shared VM |
| Memory (max) | `512 MiB` | Ingester + chunk cache; tune if query cache grows |
| Memory (reserved) | `128 MiB` | Minimum for startup and WAL replay |

### Healthcheck

```yaml
test: ["CMD-SHELL", "wget --no-verbose --tries=1 --spider http://localhost:3100/ready || exit 1"]
interval: 30s
timeout: 10s
retries: 3
start_period: 30s
```

Loki's `/ready` endpoint returns HTTP 200 when the ingester has joined the ring and is accepting writes. It returns 503 during startup and WAL replay.

---

## 4. Volumes and persistence

| Volume | Mount | Contents | Persist across |
| --- | --- | --- | --- |
| `loki_data` | `/loki` | Chunks, index, WAL, compactor state | Restarts, upgrades |

Loki stores all state under `/loki`:

```
/loki/
├── chunks/          ← compressed log chunk files (TSDB object store)
├── tsdb-index/      ← TSDB index files (shipper active index)
├── tsdb-cache/      ← TSDB shipper query cache
├── wal/             ← write-ahead log (ingester durability)
├── compactor/       ← compactor working directory and delete request store
└── rules/           ← alerting rule files (Phase 10+)
```

The named Docker volume `loki_data` is declared in `docker-compose.yml` and survives `docker compose down`, container replacement, and image upgrades. The volume is **never** removed unless explicitly purged (`docker volume rm loki_data`).

---

## 5. Loki configuration summary

Configuration file: `collector/loki/loki.yaml`

### Storage

| Setting | Value | Notes |
| --- | --- | --- |
| Store type | `tsdb` | Recommended for Loki 3.x; TSDB v13 schema |
| Object store | `filesystem` | Single-VM MVP; see object-storage migration note |
| Schema version | `v13` | Latest stable; supports native histograms |
| Index period | `24h` | One index file per day, aligned with retention |
| WAL | enabled | Durability for in-flight chunks before flush |
| Chunk encoding | `snappy` | CPU-efficient; standard for single-VM deployments |

### Retention

| Setting | Value | Rationale |
| --- | --- | --- |
| `limits_config.retention_period` | `336h` (14 days) | ADR-031 §MVP retention |
| `compactor.retention_enabled` | `true` | Compactor actively deletes expired chunks |
| `compactor.retention_delete_delay` | `2h` | Grace period — allows slow queries to complete |
| `limits_config.reject_old_samples_max_age` | `168h` (7 days) | Rejects delayed exports older than 7 days |

Retention is enforced by the compactor on its `compaction_interval` (10 minutes). The compactor deletes chunks whose timestamps fall outside the `retention_period` window, then removes the corresponding index entries.

### Ingestion limits (ADR-031)

| Setting | Value | Purpose |
| --- | --- | --- |
| `ingestion_rate_mb` | `16 MiB/s` | Sustained ingestion cap per tenant |
| `ingestion_burst_size_mb` | `32 MiB/s` | Short spike allowance |
| `max_label_names_per_series` | `20` | Cardinality guard — prevents label explosion |
| `max_label_value_length` | `2048` | Prevents oversized label values |
| `max_streams_per_user` | `10 000` | Active stream cap per tenant |
| `max_entries_limit_per_query` | `5 000` | Query result size cap |
| `max_query_parallelism` | `16` | Query shard parallelism |

### Loki exporter label strategy

The Collector's `loki` exporter maps OTel resource attributes to Loki stream labels:

| OTel resource attribute | Loki stream label | Cardinality |
| --- | --- | --- |
| `service.name` | `service_name` | Bounded — small set of known services |
| `deployment.environment` | `deployment_environment` | Bounded — `staging` / `production` |
| _(severity)_ | `level` | Bounded — `TRACE`/`DEBUG`/`INFO`/`WARN`/`ERROR`/`FATAL` |
| _(Grafana convention)_ | `job` | Same as `service_name` — used in LogQL patterns |

**High-cardinality values (`user_id`, `schedule_id`, `vibe_id`, etc.) are not promoted to stream labels.** They remain in the log body or as log record attributes and are queryable via LogQL label filters (`| json | user_id="..."`) after Loki 3.x structured metadata support. This is consistent with ADR-031 cardinality discipline.

---

## 6. Collector changes (Phase 5)

### Exporter added

```yaml
# collector/config.yaml
exporters:
  loki:
    endpoint: "${env:LOKI_ENDPOINT}"
    tls:
      insecure: true
    default_labels_enabled:
      exporter: false
      job: true
      instance: false
      level: true
    labels:
      resource:
        service.name: "service_name"
        deployment.environment: "deployment_environment"
```

### Logs pipeline updated

| Phase | Logs pipeline exporters | Rationale |
| --- | --- | --- |
| Phase 4 | `debug` | Loki not yet deployed |
| **Phase 5** | **`loki`** | Loki active; `debug` removed from logs |

```yaml
# collector/config.yaml — logs pipeline (Phase 5)
logs:
  receivers:
    - otlp/backend
    - otlp/mobile
  processors:
    - memory_limiter
    - resource
    - attributes/redact_secrets   # ADR-030: redact before push to Loki
    - batch
  exporters:
    - loki   # Phase 5: Loki active
```

### Metrics pipeline — unchanged

The metrics pipeline (`prometheusremotewrite` exporter) is **not modified** in Phase 5. Prometheus remains the sole metrics backend.

### Traces pipeline — unchanged

The traces pipeline (`debug` exporter, probabilistic sampler) is **not modified** in Phase 5. Tempo is deferred to Phase 6.

### Pipeline summary after Phase 5

| Signal | Pipeline | Exporter | Status |
| --- | --- | --- | --- |
| metrics | metrics | `prometheusremotewrite` | ✅ Active (Phase 4) |
| logs | logs | `loki` | ✅ Active (Phase 5) |
| traces | traces | `debug` | ⬜ Temporary (Phase 6: Tempo) |
| traces (errors) | traces/errors | _(stub)_ | ⬜ Phase 6 |

---

## 7. Security

This phase follows the security posture established in [security-review.md](security-review.md), [ADR-028](../../../decisions/ADR-028-observability-platform.md), [ADR-029](../../../decisions/ADR-029-telemetry-data-model.md), [ADR-030](../../../decisions/ADR-030-observability-security-and-privacy.md), and [ADR-031](../../../decisions/ADR-031-observability-operational-limits.md).

### Network isolation

| Component | Accessible from | Not accessible from |
| --- | --- | --- |
| Loki port 3100 | Collector (Docker network), host `127.0.0.1` | Internet, application containers on other networks |
| Loki port 9096 (gRPC) | Loki internal components | Host, internet |

Loki is on the `ixora-observability` Docker bridge network. Only containers explicitly attached to this network (Collector, Prometheus, later Grafana) can reach it. Application containers (`back_vibes`, `front_vibes`) are on separate networks and have no path to Loki.

### Write access

| Actor | Can write to Loki? | Mechanism |
| --- | --- | --- |
| OpenTelemetry Collector | ✅ Yes | `loki` exporter via Docker network |
| `back_vibes-api` | ❌ No | Not on `ixora-observability` network |
| `back_vibes-worker` | ❌ No | Not on `ixora-observability` network |
| `front_vibes-android` | ❌ No | Mobile — no internal network access |
| Any external actor | ❌ No | Port 3100 not exposed to internet |

### Redaction before storage

The `attributes/redact_secrets` processor in the Collector removes the following before the loki exporter pushes to Loki:

- Credential keys: `authorization`, `password`, `token`, `access_token`, `refresh_token`, `id_token`, `fcm_token`, `push_token`, `ha_token`, `provider_credentials`, `secret`, `api_key`, `private_key`, `encrypted_credentials`
- PII keys: `user_email`, `email`, `firebase_uid`
- Raw DB statements: `db.statement`

**Loki never stores raw credential or PII values.** Redaction is Collector-level, not application-level — it cannot be bypassed by a misconfigured SDK.

### Loki auth

`auth_enabled: false` is appropriate for single-tenant MVP on a private Docker network. Grafana (Phase 9) will query Loki via the same internal network without authentication headers. Multi-tenant auth (X-Scope-OrgID) is deferred to Phase 10+ if multi-environment isolation is required.

### No public exposure

The host port binding is `127.0.0.1:3100:3100`. The firewall on the DigitalOcean Droplet must block port 3100 from external access (same policy as port 9090 for Prometheus). Verify with:

```bash
# From an external host — should fail:
curl --connect-timeout 5 http://<VM_PUBLIC_IP>:3100/ready
# Expected: Connection refused or timeout
```

---

## 8. Object-storage migration note (Phase 10+)

The current filesystem storage is appropriate for a single-VM MVP. When the observability VM becomes a scaling bottleneck or when multi-region requirements emerge, migrate Loki to object storage (S3-compatible DigitalOcean Spaces or AWS S3):

1. Update `schema_config` to add a new schema entry with `object_store: s3` starting from the migration date (existing `filesystem` entry remains for historical data).
2. Update `storage_config` with S3 bucket credentials and endpoint.
3. Update `common.storage` to point to S3.
4. Existing chunks remain on the filesystem until they age out of retention. No data migration is required for MVP → Phase 10 if the transition is done before the oldest chunks reach the retention boundary.

No Collector or application changes are needed for an object-storage migration.

---

## 9. Validation steps

Run these checks after deploying Phase 5. Mirrors the validation checklist in [collector/README.md](../../../../collector/README.md).

### 9.1 Service health

```bash
# Loki ready
curl http://127.0.0.1:3100/ready
# Expected: "ready"

# Loki metrics exposed
curl -s http://127.0.0.1:3100/metrics | grep loki_ingester_streams_created_total
# Expected: metric line present

# Loki ring — ingester ACTIVE
curl -s http://127.0.0.1:3100/ring | grep -i "ACTIVE"
# Expected: ACTIVE state for the ingester member
```

### 9.2 Collector → Loki pipeline

```bash
# Collector logs pipeline: verify loki exporter present
docker compose logs collector --since=2m | grep -i loki
# Expected: "loki" references in startup or export logs

# Check for exporter errors
docker compose logs collector --since=5m | grep -i "error\|failed" | grep -v "debug"
# Expected: no loki-related errors
```

### 9.3 Log ingestion verification

```bash
# Query Loki for recent Collector self-logs (otel-collector emits JSON to stdout,
# captured by Docker json-file driver and eventually visible after log push):
curl -s 'http://127.0.0.1:3100/loki/api/v1/query_range' \
  --data-urlencode 'query={job="otel-collector"}' \
  --data-urlencode "start=$(date -d '5 minutes ago' +%s)000000000" \
  --data-urlencode "end=$(date +%s)000000000" \
  | jq '.data.result | length'
# Expected: > 0 after Collector emits logs and they are pushed through the pipeline
# Note: the Collector does not self-ingest its own stdout logs unless a filelog
# receiver is configured (Phase 5.5). The first application logs (Phase 7) will
# trigger this path. Use a test log send (see §9.4) for immediate validation.

# Query by deployment environment
curl -s 'http://127.0.0.1:3100/loki/api/v1/query_range' \
  --data-urlencode 'query={deployment_environment="staging"}' \
  --data-urlencode "start=$(date -d '1 hour ago' +%s)000000000" \
  --data-urlencode "end=$(date +%s)000000000" \
  | jq '.data.result[0].stream'
# Expected: stream labels including service_name and deployment_environment
```

### 9.4 End-to-end test via OTLP HTTP

Send a synthetic log record via the Collector's OTLP HTTP endpoint and verify it appears in Loki:

```bash
# Send a test log via OTLP HTTP (requires valid API key in Authorization header)
curl -X POST http://127.0.0.1:4318/v1/logs \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer <OTEL_INGEST_API_KEY_BACKEND>" \
  -d '{
    "resourceLogs": [{
      "resource": {
        "attributes": [
          {"key": "service.name", "value": {"stringValue": "test-service"}},
          {"key": "deployment.environment", "value": {"stringValue": "staging"}}
        ]
      },
      "scopeLogs": [{
        "logRecords": [{
          "timeUnixNano": "'$(date +%s%N)'",
          "severityNumber": 9,
          "severityText": "INFO",
          "body": {"stringValue": "phase-5-loki-validation-test"}
        }]
      }]
    }]
  }'
# Expected: HTTP 200

# Wait for batch flush (up to 10s) then query Loki:
sleep 12
curl -s 'http://127.0.0.1:3100/loki/api/v1/query_range' \
  --data-urlencode 'query={service_name="test-service"} |= "phase-5-loki-validation-test"' \
  --data-urlencode "start=$(date -d '1 minute ago' +%s)000000000" \
  --data-urlencode "end=$(date +%s)000000000" \
  | jq '.data.result[0].values[0][1]'
# Expected: "phase-5-loki-validation-test"
```

### 9.5 Persistence

```bash
# Restart Loki and verify data survives
docker compose restart loki
sleep 20
curl http://127.0.0.1:3100/ready
# Expected: "ready"

# Verify previous log data still queryable
curl -s 'http://127.0.0.1:3100/loki/api/v1/query_range' \
  --data-urlencode 'query={service_name="test-service"}' \
  --data-urlencode "start=$(date -d '10 minutes ago' +%s)000000000" \
  --data-urlencode "end=$(date +%s)000000000" \
  | jq '.data.result | length'
# Expected: > 0 (WAL replay restored in-flight chunks; named volume retained flushed chunks)
```

### 9.6 Retention configuration

```bash
# Confirm 14-day retention is set
grep retention_period collector/loki/loki.yaml
# Expected: retention_period: 336h

# Confirm compactor is enabled
grep -A3 'compactor:' collector/loki/loki.yaml | grep retention_enabled
# Expected: retention_enabled: true
```

### 9.7 Security verification

```bash
# 1. Loki not publicly reachable (run from external host)
# curl --connect-timeout 5 http://<VM_PUBLIC_IP>:3100/ready
# Expected: Connection refused or timeout

# 2. Applications cannot reach Loki — verify network isolation
docker network inspect ixora-observability \
  | jq '.[].Containers | to_entries[] | .value.Name'
# Expected: only ixora-otel-collector, ixora-prometheus, ixora-loki

# 3. No redacted keys in Loki (test with a log containing a password key)
# After sending a synthetic log with password="secret", query:
curl -s 'http://127.0.0.1:3100/loki/api/v1/query_range' \
  --data-urlencode 'query={service_name="test-service"} | json | password != ""' \
  --data-urlencode "start=$(date -d '5 minutes ago' +%s)000000000" \
  --data-urlencode "end=$(date +%s)000000000" \
  | jq '.data.result | length'
# Expected: 0 — the attributes/redact_secrets processor removed the key before push
```

---

## 10. Upgrade strategy

```bash
# 1. Update version in collector/.env
LOKI_VERSION=3.3.0

# 2. Review Loki release notes for schema migration requirements
#    https://grafana.com/docs/loki/latest/setup/upgrade/

# 3. Pull and restart Loki only (Collector and Prometheus unaffected)
cd collector
docker compose pull loki
docker compose up -d --no-deps loki

# 4. Validate
curl http://127.0.0.1:3100/ready
docker compose logs loki --since=2m

# 5. Confirm data survived (named volume)
curl -s 'http://127.0.0.1:3100/loki/api/v1/query_range' \
  --data-urlencode 'query={service_name=~".+"}' \
  --data-urlencode "start=$(date -d '30 minutes ago' +%s)000000000" \
  --data-urlencode "end=$(date +%s)000000000" \
  | jq '.data.result | length'
```

**Schema upgrade notes:**

- Loki 3.x uses TSDB v13 — no schema migration needed within the 3.x line.
- If a future Loki major version requires a new schema, add a new entry in `schema_config.configs` with the new `from` date. Old data is served from the previous schema entry until it ages out of retention.
- Never remove old schema entries while data from that period is within retention.

---

## 11. Remaining work

### Phase 5.5 — Collector self-log ingestion (optional fast-follow)

The current setup does not feed Collector's own stdout into Loki. To enable self-log visibility in Grafana:

1. Add a `filelog` receiver to the Collector pointing to the Docker json-file log path.
2. Wire it into the logs pipeline alongside `otlp/backend` and `otlp/mobile`.
3. This is optional for MVP — Collector logs are already available via `docker compose logs collector`.

### Phase 6 — Tempo Traces Backend

1. Create `collector/tempo/tempo.yaml`.
2. Uncomment the `tempo` service stub in `docker-compose.yml`.
3. Add `otlp/tempo` exporter in `config.yaml`.
4. Wire the traces pipeline: replace `debug` with `otlp/tempo`.
5. Consider a `tail_sampling` processor to replace the dual-pipeline (sampled + errors) design — see stub comment at the bottom of `config.yaml`.
6. Create `docs/specs/observability-foundation/mvp/tempo-deployment.md`.

### Phase 9 — Grafana Dashboards

1. Uncomment the `grafana` service stub in `docker-compose.yml`.
2. Provision Loki datasource (`http://loki:3100`).
3. Provision Prometheus datasource (`http://prometheus:9090`).
4. Create log-exploration dashboard using `{service_name=~".+"} | logfmt` as baseline.
5. Link trace exemplars (Phase 6) to log timestamps for correlation.

---

## 12. Cross-references

| Document | Relationship |
| --- | --- |
| [collector-validation-report.md](collector-validation-report.md) | Phase 3.5 — Collector baseline validation |
| [prometheus-deployment.md](prometheus-deployment.md) | Phase 4 — Metrics backend (unchanged in Phase 5) |
| [metrics-philosophy.md](../../../architecture/metrics-philosophy.md) | Cardinality discipline — applied equally to Loki labels |
| [telemetry-decision-guide.md](../../../architecture/telemetry-decision-guide.md) | When to use logs vs metrics vs traces |
| [observability-playbook.md](../../../operations/observability-playbook.md) | Operational runbook — Loki section (§Logs) |
| [security-review.md](security-review.md) | Security posture — Loki follows same rules as Prometheus |
| [collector-hardening-checklist.md](../../../operations/collector-hardening-checklist.md) | Deploy checklist — includes Loki validation items |
| [ADR-028](../../../decisions/ADR-028-observability-platform.md) | Single ingestion path — Collector only |
| [ADR-029](../../../decisions/ADR-029-telemetry-data-model.md) | Telemetry data model — log record structure |
| [ADR-030](../../../decisions/ADR-030-observability-security-and-privacy.md) | Redaction before storage |
| [ADR-031](../../../decisions/ADR-031-observability-operational-limits.md) | Retention (14d), cardinality limits |
