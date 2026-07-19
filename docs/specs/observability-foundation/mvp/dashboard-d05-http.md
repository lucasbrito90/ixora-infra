# Dashboard D-05 — HTTP API (Phase 8.3)

**Status:** Complete  
**Type:** Runtime changes (dashboard JSON + validation) + documentation  
**Repo:** `ixora-infra`  
**Feature ID:** `observability-foundation/mvp`  
**Prerequisite:** [dashboard-conventions.md](dashboard-conventions.md) · [grafana-foundation.md](grafana-foundation.md) (Phase 8.1) · [dashboard-d07-infrastructure.md](dashboard-d07-infrastructure.md) (Phase 8.2)

> **Goal:** D-05 answers: "Is the back_vibes HTTP API healthy?" — request rate, error rates by outcome, p95 latency, and top slow/error routes. Exclusively application-scoped.

---

## 1. Executive Summary

Phase 8.3 delivers D-05 — HTTP API, the first HTTP-layer observability dashboard for the Ixora platform.

Key outcomes:
- Dashboard JSON provisioned from `collector/grafana/provisioning/dashboards/application/d05-http.json`.
- Permanent dashboard UID `ixora-http` — immutable, version-controlled.
- 15 panels across 4 sections: Health, Throughput, Errors, Performance.
- All datasource references use `ixora-prometheus` exclusively.
- `$environment` variable applied to every panel query.
- `$http_route` variable for route-level drill-down.
- Validation: 26/26 PASS (including post-restart idempotency).

---

## 2. Architecture Review

### 2.1 Available HTTP metrics (verified against `HttpRequestTelemetry.php`)

| Metric (Prometheus name) | Type | Labels | Description |
| --- | --- | --- | --- |
| `ixora_http_server_request_total` | Counter | `environment`, `service_name`, `http_method`, `http_route`, `status_code_class`, `outcome` | Total HTTP request attempts |
| `ixora_http_server_duration_bucket/_count/_sum` | Histogram (ms) | same as above | HTTP request duration in milliseconds |

### 2.2 HTTP outcome values (verified against `HttpOutcome.php`)

| Value | Description |
| --- | --- |
| `success` | 2xx–3xx responses |
| `client_error` | 4xx responses (bad request, auth failure, not found) |
| `server_error` | 5xx responses |
| `cancelled` | Reserved for forward compatibility (never produced today) |
| `unknown` | Status codes outside 100–599 range |

### 2.3 Architectural decisions

| Decision | Choice | Rationale |
| --- | --- | --- |
| Status code granularity | `status_code_class` (2xx/4xx/5xx), not individual codes | Implementation uses bounded `status_code_class` label; individual 401/403 isolation requires Tempo drill-down |
| Auth failure monitoring | Client error rate proxy (`outcome="client_error"`) | No individual status code label exists; 401/403 investigation goes via Tempo → span attribute `http.response.status_code` |
| Route variable | `$http_route` from `label_values(ixora_http_server_request_total{}, http_route)` | Prometheus label index; fast population; bounded cardinality |
| Datasource | `ixora-prometheus` exclusively | HTTP metrics are Prometheus-scraped; no Loki/Tempo queries in panels |

### 2.4 Known limitation — individual status codes

`HttpRequestTelemetry.php` uses `status_code_class` (`2xx`, `4xx`, `5xx`) rather than the raw status code as a metric label. This is intentional cardinality control (ADR-031). Individual status codes (401, 403, 404, 500) are captured as span attributes only. Dashboard panels that need to filter by specific status codes must use Tempo.

---

## 3. Dashboard Design

### 3.1 Dashboard properties

| Property | Value |
| --- | --- |
| UID | `ixora-http` (permanent, immutable) |
| Title | D-05 — HTTP API |
| Folder | Application |
| Tags | `application`, `http`, `api`, `d-05` |
| Refresh | 30 seconds |
| Schema version | 39 (Grafana 11.x) |
| Default time range | Last 1 hour |
| Datasource | `ixora-prometheus` (all panels) |

### 3.2 Variables

| Variable | Type | Values / Query | Default | Applied to |
| --- | --- | --- | --- | --- |
| `$environment` | custom | `development`, `staging`, `production` | `staging` | Every panel query |
| `$http_route` | query | `label_values(ixora_http_server_request_total{environment="$environment"}, http_route)` | All | Route-drill-down panels |

### 3.3 Panel inventory

**Section 1: Health** (Row ID 1)

| ID | Panel | Type | Query | Unit |
| --- | --- | --- | --- | --- |
| 101 | Request Rate | Stat | `sum(rate(ixora_http_server_request_total{environment=~"$environment"}[5m]))` | reqps |
| 102 | Server Error Rate (5xx) | Stat | `sum(rate(...outcome="server_error"...)) / sum(rate(total...))` | percentunit |
| 103 | p95 Latency | Stat | `histogram_quantile(0.95, sum by(le) (rate(ixora_http_server_duration_bucket{}[5m])))` | ms |
| 104 | Client Error Rate (4xx) | Stat | `sum(rate(...outcome="client_error"...)) / sum(rate(total...))` | percentunit |

**Section 2: Throughput** (Row ID 200)

| ID | Panel | Type | Query | Unit |
| --- | --- | --- | --- | --- |
| 201 | Request Rate by Status Class | Time series | `sum by(status_code_class)(rate(ixora_http_server_request_total{}[5m]))` | reqps |
| 202 | Request Rate by Method | Time series | `sum by(http_method)(rate(...))` | reqps |

**Section 3: Errors** (Row ID 300)

| ID | Panel | Type | Query | Unit |
| --- | --- | --- | --- | --- |
| 301 | Server Error Rate by Route (5xx) | Time series | `sum by(http_route)(rate(...outcome="server_error"...))` | reqps |
| 302 | Client Error Rate by Route (4xx) | Time series | `sum by(http_route)(rate(...outcome="client_error"...))` | reqps |
| 303 | Top Error Routes (5xx) | Table | `topk(15, sum by(http_route)(increase(...outcome="server_error"...[$__range])))` | short |

**Section 4: Performance** (Row ID 400)

| ID | Panel | Type | Query | Unit |
| --- | --- | --- | --- | --- |
| 401 | p50 Latency | Stat | `histogram_quantile(0.50, ...)` | ms |
| 402 | p95 Latency | Stat | `histogram_quantile(0.95, ...)` | ms |
| 403 | p99 Latency | Stat | `histogram_quantile(0.99, ...)` | ms |
| 404 | Latency Percentiles over Time | Time series | p50, p95, p99 series | ms |
| 405 | Top Slow Routes (p95) | Table | `topk(15, histogram_quantile(0.95, sum by(le, http_route)(rate(...))))` | ms |

---

## 4. Dashboard Navigation

### 4.1 Dashboard-level links

| Link | URL | keepTime |
| --- | --- | --- |
| D-04 Queue Workers | `/d/ixora-queue` | true |
| D-06 Scheduler | `/d/ixora-scheduler` | true |
| D-07 Infrastructure | `/d/ixora-collector` | true |

### 4.2 Drill-down workflow (10.3 — "API returning 5xx errors")

```
1. D-05 Error Rate (5xx) — spike visible? Which route?
      ↓
2. D-05 Top Error Routes — isolate to one route
      ↓
3. Tempo — filter by http.route=<route>, ERROR span status
      ↓
4. Tempo trace — which child span (controller? service? DB?) has ERROR?
      ↓
5. Loki — trace_id → HTTP error context tap fields + domain error logs
      ↓
Diagnosis: DB error / queue dispatch error / domain exception
```

---

## 5. Security Review

| Category | Status |
| --- | --- |
| PII in panel queries | None — metric labels are `http_method`, `http_route`, `status_code_class`, `outcome` |
| Device/entity IDs | None |
| Credentials | None |
| Payloads | None |
| Sensitive URLs | None — routes are normalized (e.g., `/api/vibes/{vibe}/smart-home/dispatch`) |

---

## 6. Files Created / Modified

### Created

| File | Description |
| --- | --- |
| `collector/grafana/provisioning/dashboards/application/d05-http.json` | D-05 dashboard JSON (15 panels, uid=ixora-http) |
| `docs/specs/observability-foundation/mvp/dashboard-d05-http.md` | This document |

---

## Related Documents

| Document | Relationship |
| --- | --- |
| [dashboard-conventions.md](dashboard-conventions.md) | Conventions this dashboard follows |
| [dashboard-requirements.md](dashboard-requirements.md) | Phase 8.0 — D-05 panel specification (§7) |
| [grafana-foundation.md](grafana-foundation.md) | Phase 8.1 — provisioning foundation |
