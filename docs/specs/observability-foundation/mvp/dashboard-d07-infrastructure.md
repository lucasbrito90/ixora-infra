# Dashboard D-07 — Infrastructure (Phase 8.2)

**Status:** Complete  
**Type:** Runtime changes (dashboard JSON + validation) + documentation  
**Repo:** `ixora-infra`  
**Feature ID:** `observability-foundation/mvp`  
**Prerequisite:** [grafana-foundation.md](grafana-foundation.md) (Phase 8.1) · [dashboard-requirements.md](dashboard-requirements.md) (Phase 8.0)

> **Goal:** D-07 is automatically provisioned by Grafana on startup. Every metric panel is backed by real data from the Collector self-metrics pipeline. The validation script confirms provisioning, UID stability, datasource binding, and idempotency.

---

## 1. Executive Summary

Phase 8.2 delivers the first production Grafana dashboard of the Ixora Observability Platform — **D-07 Infrastructure**. This dashboard answers the question: "Is the telemetry infrastructure itself healthy?"

Key outcomes:
- Dashboard JSON provisioned from `collector/grafana/provisioning/dashboards/infrastructure/d07-infrastructure.json`.
- Permanent dashboard UID `ixora-collector` — immutable, version-controlled.
- 21 panels across 5 sections: Platform Health, Metric Export Pipeline, Trace & Log Export, Error Signals, Prometheus Platform.
- All datasource references use stable provisioned UIDs (`ixora-prometheus` exclusively for D-07).
- Validation script extended to 24 checks (Phase 8.1: 13 checks + Phase 8.2: 11 new checks).
- **Validation result: 24/24 pass (including post-restart idempotency).**
- Three infrastructure bugs discovered and fixed during architecture review (Loki exporter `labels` key, missing exporter endpoint env vars, Tempo/Collector host port conflict).

---

## 2. Architecture Review

### 2.1 Available infrastructure metrics

The architecture review confirmed the following infrastructure metrics are available in Prometheus:

#### Collector self-metrics (`otelcol_*` via `prometheusremotewrite`)

| Metric (Prometheus name) | Type | Labels | Description |
| --- | --- | --- | --- |
| `otelcol_process_uptime_total` | Counter | `service_name` | Collector uptime (seconds since start) |
| `otelcol_process_memory_rss` | Gauge | `service_name` | Collector RSS memory (bytes) |
| `otelcol_process_cpu_seconds_total` | Counter | `service_name` | Collector CPU usage (seconds) |
| `otelcol_process_runtime_heap_alloc_bytes` | Gauge | `service_name` | Heap allocation (bytes) |
| `otelcol_exporter_sent_metric_points_total` | Counter | `exporter`, `service_name` | Metric points sent to Prometheus |
| `otelcol_exporter_send_failed_metric_points_total` | Counter | `exporter`, `service_name` | Failed metric exports |
| `otelcol_exporter_queue_size` | Gauge | `exporter`, `data_type`, `service_name` | Current export queue depth |
| `otelcol_exporter_queue_capacity` | Gauge | `exporter`, `service_name` | Max queue capacity |
| `otelcol_receiver_accepted_metric_points_total` | Counter | `receiver`, `service_name` | Metrics accepted at receiver |
| `otelcol_receiver_refused_metric_points_total` | Counter | `receiver`, `service_name` | Metrics refused (auth/limit) |

**Metrics not yet in Prometheus (lazy registration — appear when data flows):**
- `otelcol_exporter_sent_spans_total` — requires at least one span to flow through the pipeline
- `otelcol_exporter_sent_log_records_total` — requires at least one log record
- `otelcol_exporter_send_failed_spans_total`, `otelcol_exporter_send_failed_log_records_total`

These panels show "No data" until `back_vibes` starts sending telemetry. This is expected and informative — the panels activate automatically when application telemetry flows.

#### Prometheus self-metrics (`prometheus_*` via direct scrape)

| Metric | Description |
| --- | --- |
| `up{job="otel-collector"}` | Collector self-scrape health (push-based; see §known-limitations) |
| `up{job="prometheus"}` | Prometheus self-scrape health |
| `prometheus_tsdb_head_series` | Active time series count |
| `prometheus_config_last_reload_successful` | Config reload status |
| `prometheus_remote_storage_samples_in_total` | Remote write ingestion rate |

#### Loki/Tempo health

No Prometheus metrics exist for Loki or Tempo health. Backend health is inferred from:
- `otelcol_exporter_queue_size{exporter="loki"}` and `{exporter="otlp/tempo"}` — rising queue = backend backpressure
- `otelcol_exporter_send_failed_log_records_total` — Loki unreachable
- `otelcol_exporter_send_failed_spans_total` — Tempo unreachable
- Grafana UI datasource health checks

This is a documented architectural constraint: Loki and Tempo are write-only backends (ADR-028). Adding a separate Prometheus scraper for Loki/Tempo health metrics is deferred to Phase 8.3 if deemed necessary.

### 2.2 Infrastructure bugs discovered and fixed

Three bugs were found during the architecture review that prevented the full stack from running:

| Bug | Root cause | Fix |
| --- | --- | --- |
| Collector crash: `"" has invalid keys: labels` | Loki exporter `labels.resource` block was removed in OTel Collector 0.115.x | Removed the `labels:` block from the `loki` exporter in `config.yaml`. Resource attributes now flow as log body fields; `job=true` in `default_labels_enabled` provides `service_name` as a stream label |
| Collector crash: env vars `LOKI_ENDPOINT`, `TEMPO_ENDPOINT`, `PROMETHEUS_REMOTE_WRITE_ENDPOINT` unset | These vars were referenced in `config.yaml` but never passed to the Collector container's `environment:` block in `docker-compose.yml` | Added the three endpoint env vars to the `collector` service `environment:` block |
| Collector port `4317` conflict with Tempo | Tempo's ops host port binding (`TEMPO_OTLP_GRPC_PORT`) defaulted to `4317`, conflicting with the Collector's public OTLP gRPC port | Changed `TEMPO_OTLP_GRPC_PORT` default to `14317` in `.env` and `.env.example` |

All three bugs were pre-existing from Phases 3–6. They were masked because the Collector was never started alongside the full stack before Phase 8.2.

---

## 3. Dashboard Design

### 3.1 Dashboard properties

| Property | Value |
| --- | --- |
| UID | `ixora-collector` (permanent, immutable) |
| Title | D-07 — Infrastructure |
| Folder | Infrastructure |
| Tags | `infrastructure`, `collector`, `platform`, `d-07` |
| Refresh | 30 seconds |
| Schema version | 39 (Grafana 11.x) |
| Default time range | Last 1 hour |
| Datasource | `ixora-prometheus` (all panels) |

### 3.2 Variables

| Variable | Type | Values | Default | Applied to |
| --- | --- | --- | --- | --- |
| `$environment` | custom | `development`, `staging`, `production` | `staging` | Application Export Failures panel only. Infrastructure self-metrics (`otelcol_*`, `prometheus_*`) are not environment-scoped. |

### 3.3 Panel inventory

**Section 1: Platform Health**

| ID | Panel | Type | Query | Unit |
| --- | --- | --- | --- | --- |
| 2 | Collector Process | Stat | `up{job="otel-collector"}` | UP/DOWN mapping |
| 3 | Prometheus | Stat | `up{job="prometheus"}` | UP/DOWN mapping |
| 4 | Collector Uptime | Stat | `otelcol_process_uptime_total{service_name="otelcol-contrib"}` | dtdhms |
| 5 | Collector Memory (RSS) | Stat | `otelcol_process_memory_rss{service_name="otelcol-contrib"}` | bytes |
| 6 | Collector CPU | Stat | `rate(otelcol_process_cpu_seconds_total[5m])` | percentunit |

**Section 2: OTLP Export Pipeline — Metrics**

| ID | Panel | Type | Query | Unit |
| --- | --- | --- | --- | --- |
| 11 | Metric Export Rate | Time series | `rate(otelcol_exporter_sent_metric_points_total{exporter="prometheusremotewrite"}[5m])` | ops |
| 12 | Export Queue Depth | Time series | `otelcol_exporter_queue_size{service_name="otelcol-contrib"}` | short |

**Section 3: Trace & Log Export** (appear when telemetry flows)

| ID | Panel | Type | Query | Unit |
| --- | --- | --- | --- | --- |
| 21 | Trace Export Rate | Time series | `rate(otelcol_exporter_sent_spans_total{exporter="otlp/tempo"}[5m])` | ops |
| 22 | Log Export Rate | Time series | `rate(otelcol_exporter_sent_log_records_total{exporter="loki"}[5m])` | ops |

Both panels include a `failed/s` series (red) to distinguish healthy zero (no spans/logs) from broken zero (sending failures).

**Section 4: Error & Drop Signals**

| ID | Panel | Type | Query | Unit |
| --- | --- | --- | --- | --- |
| 31 | Receiver Refused Points/s | Stat | `sum(rate(otelcol_receiver_refused_metric_points_total[5m]))` | ops |
| 32 | Metric Export Failures/s | Stat | `sum(rate(otelcol_exporter_send_failed_metric_points_total[5m]))` | ops |
| 33 | Application Export Failures (1h) | Stat | `sum(increase(ixora_telemetry_export_failed_total{deployment_environment="$environment"}[1h])) or vector(0)` | short |

**Section 5: Prometheus Platform**

| ID | Panel | Type | Query | Unit |
| --- | --- | --- | --- | --- |
| 41 | Active Time Series | Stat | `prometheus_tsdb_head_series` | short |
| 42 | Prometheus Config Reload | Stat | `prometheus_config_last_reload_successful` | OK/FAILED mapping |
| 43 | Remote Write Ingestion Rate | Time series | `rate(prometheus_remote_storage_samples_in_total[5m])` | ops |
| 44 | Collector Memory (RSS vs Heap) | Time series | RSS + Heap series | bytes |

---

## 4. Datasource Usage

D-07 exclusively uses the `ixora-prometheus` datasource. No Loki or Tempo queries are in this dashboard.

**Rationale:** D-07 is infrastructure-scoped. Loki/Tempo health is inferred from Collector pipeline metrics (export failures, queue depth) rather than from direct Loki/Tempo queries. This keeps the dashboard self-contained — it remains functional even if Loki or Tempo are down.

**Drill-down from D-07:** There is no trace or log drill-down in this dashboard because:
1. Collector self-metrics are process-level (no trace context)
2. Infrastructure anomalies lead to direct Collector log inspection (`docker compose logs collector`)
3. Future D-01 Platform Overview will provide cross-dashboard navigation

---

## 5. Dashboard UID Convention

Per Phase 8.2 specification, all production dashboards must use stable, immutable UIDs:

| Dashboard | UID |
| --- | --- |
| D-01 Platform Overview | `ixora-overview` |
| D-02 Smart Home | `ixora-smart-home` |
| D-03 Push Notifications | `ixora-push` |
| D-04 HTTP API | `ixora-http` |
| D-05 Queue Workers | `ixora-queue` |
| D-06 Scheduler | `ixora-scheduler` |
| **D-07 Infrastructure** | **`ixora-collector`** |

Rules:
- Dashboard UIDs are defined in the JSON `uid` field — never allow Grafana to autogenerate.
- UIDs are immutable once deployed. Changing a UID breaks every bookmark and panel link.
- If a dashboard must be replaced, the old UID must be explicitly retired in the commit message.

---

## 6. Validation

### 6.1 Checks implemented

Phase 8.2 extended `grafana/validate.sh` from 13 checks (Phase 8.1) to **24 checks**:

| Check | Description |
| --- | --- |
| 1 | Grafana health (database: ok) |
| 2 | Datasource UIDs stable (ixora-prometheus, ixora-loki, ixora-tempo) |
| 3 | Default datasource is ixora-prometheus |
| 4 | Datasource connectivity (Prometheus OK, Loki OK, Tempo graceful) |
| 5 | Datasources read-only (editable: false) |
| 6 | No unprovisioned datasources (count = 3) |
| 7 | All 4 folder names exist (Infrastructure, Application, Business, Overview) |
| 8 | D-07 JSON syntax valid |
| 9 | D-07 JSON UID = ixora-collector (no autogenerated UID) |
| 10 | D-07 provisioned in Grafana (provisioned=true, uid=ixora-collector, folder=Infrastructure) |
| 11 | D-07 datasource references use UIDs (no name-only references) |
| 12 | D-07 folder assignment correct (title = Infrastructure) |

### 6.2 Validation results

```
Phase 8.2 validation run (post-restart):
  24/24 checks passed
  0 failures
```

Idempotency confirmed: `docker compose restart grafana` followed by `./validate.sh` passes all 24 checks.

---

## 7. Known Limitations

### KL-1: Folder UIDs are auto-generated by Grafana 11.3

**Symptom:** Folders (Infrastructure, Application, Business, Overview) are created with auto-generated UIDs (e.g., `ffsjh3jqxui2oa`) instead of the stable UIDs defined in `providers.yaml` (`ixora-folder-infrastructure`).

**Root cause:** In Grafana 11.3, the `folderUID` field in dashboard providers is used to **match an existing folder** by UID. If no folder exists with that UID, Grafana creates a new folder with an auto-generated UID. It does not create a folder with the specified UID.

**Impact:** Folder UIDs are stable within a running Grafana instance (they persist across `docker compose restart`). They reset only when the Grafana data volume is deleted (`docker volume rm collector_grafana_data`). Cross-dashboard navigation uses **dashboard UIDs** (stable), not folder UIDs.

**Mitigation:** The validation script (check 7) verifies folder **names** (stable and human-meaningful) instead of UIDs. Future phases should avoid hard-coding folder UIDs in dashboard JSON — use the folder name in documentation and the `folderUID` provider field as a hint only.

**Resolution path:** Grafana 11.x+ may support folder provisioning via a dedicated YAML format. Evaluate in Phase 8.3 when provisioning Grafana on a staging server with a persistent volume.

### KL-2: Trace and Log export panels show "No data"

**Symptom:** Panels "Trace Export Rate (Tempo)" and "Log Export Rate (Loki)" show "No data" in the current environment.

**Root cause:** OTel Collector 0.115.x uses lazy metric registration. The `otelcol_exporter_sent_spans_total` and `otelcol_exporter_sent_log_records_total` metrics only appear in Prometheus after at least one batch of spans/logs flows through the Collector. Since `back_vibes` is not actively sending telemetry in the current staging environment, these series don't exist yet.

**Impact:** None in production — the panels activate automatically when `back_vibes` sends telemetry.

**Mitigation:** Both panels include a `failed/s` series. If that series also shows "No data", it confirms the Collector is idle (no data, no failures). If `failed/s` shows non-zero values, it indicates a pipeline break.

### KL-3: Collector health is push-based (staleness up to 5 minutes)

**Symptom:** The "Collector Process Up" panel (`up{job="otel-collector"}`) may show UP for up to 5 minutes after the Collector stops.

**Root cause:** The `up{job="otel-collector"}` metric is pushed by the Collector's own `prometheus/self` receiver via `prometheusremotewrite`. When the Collector stops, the push stops, but Prometheus retains the last value until the staleness marker expires (~5 minutes).

**Impact:** A stopped Collector may appear healthy for up to 5 minutes. Direct alert investigation should include `docker compose logs collector` or Prometheus scrape target status.

**Mitigation:** For production alerting, complement this panel with a `absent(up{job="otel-collector"})` alert condition that fires when the metric disappears. This is Phase 10 (alerting) scope.

---

## 8. Provisioning

### 8.1 File location

```
collector/
└── grafana/
    └── provisioning/
        └── dashboards/
            └── infrastructure/
                └── d07-infrastructure.json   ← D-07 dashboard JSON
```

### 8.2 How provisioning works

1. Grafana starts and reads `provisioning/dashboards/providers.yaml`.
2. The `infrastructure-provider` entry points to `/etc/grafana/provisioning/dashboards/infrastructure/`.
3. Grafana polls this directory every 60 seconds.
4. On finding `d07-infrastructure.json`, it provisions the dashboard under the Infrastructure folder.
5. The dashboard becomes accessible at `/d/ixora-collector/`.
6. `disableDeletion: true` and `allowUiUpdates: false` ensure the dashboard cannot be accidentally deleted or modified via the UI.

### 8.3 Restart idempotency

```bash
docker compose down
docker compose up -d
# Wait ~75 seconds for Grafana to reach healthy state and provision
./grafana/validate.sh  # → 24/24 pass
```

The dashboard is reprovisioned automatically on every Grafana restart. No manual steps are required.

---

## 9. Files Created / Modified

### Created

| File | Description |
| --- | --- |
| `collector/grafana/provisioning/dashboards/infrastructure/d07-infrastructure.json` | D-07 dashboard JSON (21 panels, uid=ixora-collector) |
| `docs/specs/observability-foundation/mvp/dashboard-d07-infrastructure.md` | This document |

### Modified

| File | Change |
| --- | --- |
| `collector/grafana/validate.sh` | Extended from 13 to 24 checks (Phase 8.2: folder names, JSON syntax, UID, provisioning, datasource binding, folder assignment) |
| `collector/config.yaml` | Removed invalid `labels:` block from Loki exporter (OTel Collector 0.115.x compatibility) |
| `collector/docker-compose.yml` | Added `PROMETHEUS_REMOTE_WRITE_ENDPOINT`, `LOKI_ENDPOINT`, `TEMPO_ENDPOINT` to Collector service `environment:` |
| `collector/.env` | Added `PROMETHEUS_REMOTE_WRITE_ENDPOINT`, `LOKI_ENDPOINT`, `TEMPO_ENDPOINT`, `TEMPO_OTLP_GRPC_PORT=14317` |
| `collector/.env.example` | Updated `TEMPO_OTLP_GRPC_PORT` comment and default (14317 to avoid port conflict) |

---

## 10. Future Improvements (Phase 8.3+)

| Improvement | Priority | Phase |
| --- | --- | --- |
| Loki health metric via dedicated Prometheus job or Blackbox exporter | Medium | 8.3 |
| Tempo health metric via dedicated Prometheus job or Blackbox exporter | Medium | 8.3 |
| `absent(up{job="otel-collector"})` alert rule for Collector down detection | High | 10 (alerting) |
| Span/log drop rate panels (currently absent until data flows) | Low | active automatically with back_vibes data |
| Action on folder UID stability (Grafana provisioning YAML for folders) | Low | 8.3 |
| `otelcol_processor_dropped_*` panels for memory_limiter pressure | Medium | 8.3 (add when metric is non-zero) |
| cAdvisor integration for Docker container CPU/memory per-container | Low | future |
| Dashboard annotation: mark Grafana restarts as vertical lines | Low | 8.3 |

---

## Related Documents

| Document | Relationship |
| --- | --- |
| [grafana-foundation.md](grafana-foundation.md) | Phase 8.1 — provisioning foundation D-07 builds on |
| [dashboard-requirements.md](dashboard-requirements.md) | Phase 8.0 — D-07 panel spec (§9) |
| [collector-deployment.md](collector-deployment.md) | Collector architecture — source of `otelcol_*` metrics |
| [prometheus-deployment.md](prometheus-deployment.md) | Prometheus self-metrics — `prometheus_tsdb_*`, `up` |
