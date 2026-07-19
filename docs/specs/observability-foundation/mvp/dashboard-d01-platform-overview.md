# D-01 — Platform Overview Dashboard

**Status:** Complete  
**Phase:** 8.5  
**UID:** `ixora-platform`  
**Folder:** Overview  
**File:** `collector/grafana/provisioning/dashboards/overview/d01-platform-overview.json`  
**Datasource:** `ixora-prometheus`  
**Refresh:** 30s  
**Time range:** Last 1 hour  

---

## 1. Purpose

D-01 is the **default landing page** for on-call engineers and SREs operating the Ixora platform. It answers one question in under 30 seconds: **"Is the entire back_vibes platform healthy right now?"**

It is not a deep investigation tool. Every panel in D-01 summarises a signal that already has a dedicated specialized dashboard. When an anomaly is detected here, the operator navigates to the appropriate specialized dashboard (D-02 through D-07) for root-cause analysis.

---

## 2. Audience

| Role | Use |
|---|---|
| On-call engineer | Primary: first screen opened during an incident or regular health check |
| SRE | Platform-level trend review, capacity overview |
| Engineering Lead | Executive health snapshot |

---

## 3. Architecture Review

### 3.1 Metrics verified directly against implementation

All metrics in D-01 are reused from existing verified dashboards. No new metric names were introduced in this phase.

| Metric | Source dashboard | Labels used in D-01 |
|---|---|---|
| `ixora_http_server_request_total` | D-05 (Phase 8.3, verified from `HttpRequestTelemetry.php`) | `environment`, `outcome` |
| `ixora_queue_job_total` | D-04 (Phase 8.3, verified from `QueueExecutionTelemetry.php`) | `environment`, `outcome`, `queue` |
| `ixora_queue_job_active` | D-04 | `environment` |
| `ixora_scheduler_event_total` | D-06 (Phase 8.3, verified from `SchedulerExecutionTelemetry.php`) | `environment`, `outcome` |
| `ixora_smart_home_action_total` | D-02 (Phase 8.4, verified from `SmartHomeActionTelemetry.php`) | `environment`, `outcome` |
| `ixora_smart_home_action_duration_bucket` | D-02 | `environment`, `le` |
| `ixora_smart_home_dispatch_total` | D-02 (Phase 8.4, verified from `SmartHomeDispatchTelemetry.php`) | `environment`, `outcome` |
| `up{job="otel-collector"}` | D-07 (Phase 8.2) | — |
| `up{job="prometheus"}` | D-07 | — |
| `otelcol_process_memory_rss` | D-07 | `service_name` |
| `otelcol_process_cpu_seconds_total` | D-07 | `service_name` |
| `otelcol_exporter_send_failed_spans_total` | D-07 | `exporter`, `service_name` |
| `otelcol_exporter_send_failed_log_records_total` | D-07 | `exporter`, `service_name` |
| `otelcol_exporter_send_failed_metric_points_total` | D-07 | `exporter`, `service_name` |
| `otelcol_exporter_sent_metric_points_total` | D-07 | `exporter`, `service_name` |
| `ixora_telemetry_export_failed_total` | D-07 | `deployment_environment` (not `environment`) |

### 3.2 Label discrepancy — `ixora_telemetry_export_failed_total`

`ixora_telemetry_export_failed_total` uses the label `deployment_environment`, not `environment`. This was already documented in D-07 (Phase 8.2) and is consistent with the existing D-07 panel:

```promql
sum(increase(ixora_telemetry_export_failed_total{deployment_environment=~"$environment"}[1h])) or vector(0)
```

D-01 uses the same pattern. No implementation change required.

### 3.3 Infrastructure metrics are not filtered by `$environment`

Collector self-metrics (`otelcol_*`, `up{job="otel-collector"}`, `up{job="prometheus"}`) are platform-wide signals — they do not carry an `environment` label. All infrastructure panels in D-01 omit the `$environment` filter for these metrics, which is documented in each panel's description.

---

## 4. UID Discrepancy from `dashboard-conventions.md §1.2`

`dashboard-conventions.md §1.2` (Phase 8.3) planned D-01's UID as `ixora-overview`. The Phase 8.5 implementation spec explicitly requires `ixora-platform`.

**Resolution:** `ixora-platform` is used as the authoritative UID for this implementation. `dashboard-conventions.md §1.2` has been updated to reflect the actual UID.

Navigation links throughout this dashboard and all future dashboard updates will use `/d/ixora-platform`.

---

## 5. Dashboard Design

### 5.1 Variables

Only `$environment` (mandatory, per `dashboard-conventions.md §6.1`). No domain-specific variables — D-01 provides cross-domain summaries only, not per-domain drill-down.

### 5.2 Tags

`overview`, `platform`, `d-01`

### 5.3 Links

Dashboard-level navigation links (top-right nav bar) to all five specialized dashboards:

| Link | UID |
|---|---|
| D-02 Smart Home | `/d/ixora-smart-home` |
| D-04 Queue Workers | `/d/ixora-queue` |
| D-05 HTTP API | `/d/ixora-http` |
| D-06 Scheduler | `/d/ixora-scheduler` |
| D-07 Infrastructure | `/d/ixora-collector` |

All links use `keepTime: true`.

---

## 6. Panel Inventory

**32 panels total: 5 row headers + 27 content panels.**

### Section 1 — Platform Health (Panel IDs 100–105)

| ID | Title | Type | Query summary |
|---|---|---|---|
| 100 | HTTP Availability | stat | `1 - server_error_rate` — percentunit, threshold green > 99% |
| 101 | Queue Health | stat | `success / completed attempts` — percentunit, threshold green > 95% |
| 102 | Scheduler Running | stat | `sum(rate(scheduler_event_total[5m]))` — ops |
| 103 | Smart Home Health | stat | `success / total actions` — percentunit, threshold green > 95% |
| 104 | Collector Up | stat | `up{job="otel-collector"}` — mapped 1=UP/0=DOWN |
| 105 | Telemetry Export Failures | stat | `increase(telemetry_export_failed_total[1h]) or 0` — short, threshold green = 0 |

### Section 2 — Business Summary (Panel IDs 200–204)

| ID | Title | Type | Query summary |
|---|---|---|---|
| 200 | Smart Home Dispatches | stat | `increase(dispatch_total{outcome=dispatched}[$__range])` — total in window |
| 201 | Action Success Rate | stat | `success / total` — percentunit (instant) |
| 202 | Action Failure Rate | stat | `failure|unknown / total` — percentunit (instant) |
| 203 | Action p95 Latency | stat | `histogram_quantile(0.95, rate(action_duration_bucket[5m]))` — ms |
| 204 | Business Health Over Time | timeseries | Success + failure rates over time — threshold lines at 80% / 95% |

### Section 3 — Application Summary (Panel IDs 300–304)

| ID | Title | Type | Query summary |
|---|---|---|---|
| 300 | HTTP Requests/s | timeseries | `sum(rate(http_request_total[5m]))` — reqps |
| 301 | HTTP Error Rate | timeseries | `server_error_rate over time` — percentunit |
| 302 | Queue Throughput (by Queue) | timeseries | `sum by(queue) rate(queue_job_total[5m])` — ops |
| 303 | Active Queue Jobs | stat | `sum(queue_job_active)` — short, threshold yellow > 10 |
| 304 | Scheduler Executions (by Outcome) | timeseries | `sum by(outcome) rate(scheduler_event_total[5m])` — ops |

### Section 4 — Infrastructure Summary (Panel IDs 400–405)

| ID | Title | Type | Query summary |
|---|---|---|---|
| 400 | Collector Process | stat | `up{job="otel-collector"}` — mapped UP/DOWN |
| 401 | Prometheus Process | stat | `up{job="prometheus"}` — mapped UP/DOWN |
| 402 | Collector Memory | stat | `otelcol_process_memory_rss` — bytes |
| 403 | Collector CPU | stat | `rate(otelcol_process_cpu_seconds_total[5m])` — percentunit |
| 404 | Collector Export Errors | timeseries | Failed spans + logs + metrics per second |
| 405 | Remote Write Status (Metrics) | timeseries | Sent vs failed metric points per second |

### Section 5 — Navigation (Panel IDs 500–504)

| ID | Title | Type | Links to |
|---|---|---|---|
| 500 | D-02 Smart Home Business | text | `/d/ixora-smart-home` |
| 501 | D-04 Queue Workers | text | `/d/ixora-queue` |
| 502 | D-05 HTTP API | text | `/d/ixora-http` |
| 503 | D-06 Scheduler | text | `/d/ixora-scheduler` |
| 504 | D-07 Infrastructure | text | `/d/ixora-collector` (full width) |

Text panels use markdown with embedded links. They contain `description` and `datasource` fields per `dashboard-conventions.md §7`, with `{"type": "datasource", "uid": "-- Dashboard --"}` as the datasource.

---

## 7. Navigation Strategy

D-01 uses two layers of navigation:

1. **Dashboard-level links** (top-right nav bar): one link per specialized dashboard, with `keepTime: true`. This is the primary navigation method for operators.

2. **Panel-level links**: every content panel includes a link to its detailed specialized dashboard. This allows operators to click directly on the anomalous panel to navigate to the appropriate specialized view.

3. **Section 5 — Navigation panels**: full descriptive text blocks for each specialized dashboard with markdown links. Useful for new team members orienting themselves.

**Invariant:** No panel link or text panel contains a numeric Grafana dashboard ID. All links use immutable UID-style URLs (`/d/ixora-*`).

---

## 8. Cross-Signal Philosophy

D-01 is **metrics-only**. No Tempo or Loki queries exist in any panel.

Drill-down path from D-01:
```
Anomaly on D-01 platform health card
      ↓
Navigate to domain-specific dashboard (D-02, D-04, D-05, D-06, D-07)
      ↓
Identify failing component using domain-level metrics
      ↓
Use domain dashboard Trace link → Tempo
      ↓
Copy trace_id → Loki for log context
```

---

## 9. Security Review

| Concern | Assessment |
|---|---|
| PII | None. No user names, emails, or user IDs in any label or panel query. |
| Device identifiers | None. No device IDs, entity IDs, or provider device IDs used. |
| Credentials | None. No tokens, API keys, or passwords. |
| Payloads | None. No request or response bodies. |
| Sensitive URLs | None. All links are relative Grafana paths (`/d/ixora-*`, `/explore`). |
| Label cardinality | All labels are bounded enums: `outcome`, `queue`, `environment`, `job` (Collector service name). |
| Infrastructure metrics | `otelcol_*` and `up{...}` metrics carry only bounded infrastructure labels (`service_name`, `job`, `exporter`). |

**Conclusion: D-01 passes the security review.**

---

## 10. Validation

Checks 34–42 were added to `collector/grafana/validate.sh`. Each emits exactly one `pass` or `fail` call.

| Check | Description | Technique |
|---|---|---|
| 34 | D-01 JSON syntax valid | `python3 -m json.tool` |
| 35 | UID `ixora-platform` in JSON file | `json.load` + field comparison |
| 36 | Provisioned in Grafana, Overview folder | Grafana API `/api/dashboards/uid/ixora-platform` |
| 37 | Datasource UID references — no name-only, ixora-prometheus present | JSON scan |
| 38 | All dashboard links use UID-style URLs (no `/d/[0-9]+`) | Regex scan across all provisioning JSON |
| 39 | D-01 panel IDs unique within dashboard | Python set comparison |
| 40 | D-01 panel IDs within reserved ranges (rows 1–99, content 100–599) | Python range check |
| 41 | Every non-row panel has `description` | Python field check |
| 42 | Every non-row panel has `datasource.uid` | Python field check |

**Result: 42/42 PASS** — confirmed on initial start and after `docker compose restart grafana`.

---

## 11. Known Limitations

| # | Limitation | Impact | Resolution |
|---|---|---|---|
| KL-1 | `ixora_telemetry_export_failed_total` uses `deployment_environment` label, not `environment` | Panel 105 uses `deployment_environment=~"$environment"` for correct filtering | Consistent with D-07 — no change needed |
| KL-2 | Infrastructure panels (`otelcol_*`, `up{job=...}`) are not filtered by `$environment` | These metrics are platform-wide; they do not carry an environment label | Documented in each panel description |
| KL-3 | HTTP Availability (panel 100): formula returns NaN when no traffic exists in `$environment` | Panel shows "No data" with empty environment — expected in development | No fix needed; correct UX |
| KL-4 | D-01 UID is `ixora-platform` but `dashboard-conventions.md §1.2` originally planned `ixora-overview` | Navigation links to D-01 must use `/d/ixora-platform` | Convention doc updated in this phase |
| KL-5 | D-03 Push Notifications is absent from D-01 (no row, no panel) | Push metrics (`ixora_push_delivery_total`) are not yet implemented (Phase 7B.5) | D-01 Section 2 Business Summary can be extended when D-03 ships |
| KL-6 | Grafana 11.3 auto-generates folder UIDs; `Overview` folder UID is not stable across volume recreation | Validation checks folder by title (`Overview`), not by UID | Documented in `dashboard-d07-infrastructure.md §KL-1` |

---

## 12. Troubleshooting

| Symptom | Cause | Action |
|---|---|---|
| Check 36 fails: `ixora-platform not found in Grafana` | Overview folder or D-01 not provisioned | `docker compose restart grafana`, wait 10s, re-run |
| All health panels show "No data" | Collector or Prometheus is down | Check `up{job="otel-collector"}` / `up{job="prometheus"}` in Explore |
| Panel 105 shows non-zero | back_vibes failed to export telemetry to Collector | Check `docker compose logs collector --tail=50` for OTLP errors |
| HTTP Availability (panel 100) shows "No data" | No HTTP traffic in selected environment | Switch `$environment` to `staging` or change time range |
| Validate.sh returns 42/42 but panels show stale data | Grafana provisioning complete but Collector not running | Navigate to D-07, check Collector process status |

---

## 13. Files Created / Modified

### Created

- `collector/grafana/provisioning/dashboards/overview/d01-platform-overview.json` — Dashboard JSON, 32 panels
- `docs/specs/observability-foundation/mvp/dashboard-d01-platform-overview.md` — This document

### Modified

- `collector/grafana/validate.sh` — Added checks 34–42, total 42 checks
- `docs/specs/observability-foundation/mvp/dashboard-conventions.md` — Updated §1.2 UID table to reflect `ixora-platform`
- `docs/specs/observability-foundation/mvp/tasks.md` — Phase 8.5 complete
- `docs/specs/observability-foundation/mvp/plan.md` — Phase 8.5 complete
- `docs/README.md` — D-01 entry added

---

## 14. Related Documents

| Document | Relationship |
|---|---|
| [dashboard-conventions.md](dashboard-conventions.md) | Permanent standards — D-01 conforms to all conventions |
| [dashboard-requirements.md](dashboard-requirements.md) | D-01 design spec (§3) — this implementation fulfils it |
| [dashboard-d02-smart-home.md](dashboard-d02-smart-home.md) | Primary domain dashboard for Business section |
| [dashboard-d04-queue.md](dashboard-d04-queue.md) | Source of queue metric patterns used in Application section |
| [dashboard-d05-http.md](dashboard-d05-http.md) | Source of HTTP metric patterns used in Application section |
| [dashboard-d06-scheduler.md](dashboard-d06-scheduler.md) | Source of scheduler metric patterns used in Application section |
| [dashboard-d07-infrastructure.md](dashboard-d07-infrastructure.md) | Source of infrastructure metric patterns used in Infrastructure section |
