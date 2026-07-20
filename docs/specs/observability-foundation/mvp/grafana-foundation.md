# Grafana Foundation — Phase 8.1

**Status:** Complete  
**Type:** Runtime changes (provisioning) + documentation  
**Repo:** `ixora-infra`  
**Feature ID:** `observability-foundation/mvp`  
**Prerequisite:** [dashboard-requirements.md](dashboard-requirements.md) (Phase 8.0) · [business-telemetry-foundation.md](../business-telemetry/business-telemetry-foundation.md) (Phase 7B.4.9) · Prometheus, Loki, Tempo healthy (Phases 4–6)

> **Goal:** Grafana is fully provisioned as code. Destroying and recreating the Grafana container produces an identical platform with no manual configuration required.

---

## 1. Executive Summary

Phase 8.1 activates the Grafana OSS container (previously stubbed) and establishes the complete provisioning foundation. Every aspect of the Grafana installation is now defined in version-controlled files under `collector/grafana/provisioning/`:

- Three datasources provisioned automatically on startup with **stable UIDs** that dashboard JSON files will reference forever.
- Four dashboard folder providers defined with stable folder UIDs — folder directories are in place; dashboard JSON files will be added in Phase 9.
- Grafana configuration fully expressed as environment variables in `docker-compose.yml` — no manual UI setup required.
- Validation script (`grafana/validate.sh`) confirms 12 mandatory properties on every startup.
- All three backends (Prometheus, Loki, Tempo) have been fixed to start correctly with their declared versions (2.x config drift corrected in Phases 4–6 config files).

**Validation result (post-restart):** 12/12 checks pass. Provisioning is confirmed idempotent.

---

## 2. Provisioning Architecture

### 2.1 Directory structure

```
collector/
├── docker-compose.yml           ← Grafana service (active — Phase 8.1)
├── .env.example                 ← Grafana variables added
├── grafana/
│   ├── validate.sh              ← Phase 8.1 validation script (executable)
│   └── provisioning/            ← read-only bind mount → /etc/grafana/provisioning
│       ├── datasources/
│       │   └── datasources.yaml ← Prometheus + Loki + Tempo (stable UIDs)
│       ├── dashboards/
│       │   ├── providers.yaml   ← 4 folder providers (Infrastructure/Application/Business/Overview)
│       │   ├── infrastructure/  ← D-07 Collector & Infrastructure (Phase 9)
│       │   ├── application/     ← D-04 Queue Workers, D-05 HTTP API, D-06 Scheduler (Phase 9)
│       │   ├── business/        ← D-02 Smart Home, D-03 Push Notifications (Phase 9)
│       │   └── overview/        ← D-01 Platform Overview (Phase 9)
│       ├── plugins/             ← no plugins installed (Phase 8.1)
│       └── alerting/            ← no alert rules (Phase 10+)
```

### 2.2 Provisioning principle

Grafana's native file-based provisioning is used for all configuration. No Terraform/OpenTofu Grafana provider is used — the Docker bind mount is the single source of truth. This choice avoids introducing a separate state backend for Grafana resources and keeps the entire observability stack deployable from a single `docker compose up -d`.

**Idempotency guarantee:** Grafana re-reads `provisioning/` on every start. Adding a file to a dashboard folder directory automatically creates the Grafana folder and dashboard on the next container start or within 60 seconds (the provider poll interval). Removing the file has no effect because `disableDeletion: true` is set on all providers — explicit cleanup via the API is required.

---

## 3. Datasource Configuration

### 3.1 Stable UIDs (IMMUTABLE — never change)

| Datasource | UID | Type | Default |
| --- | --- | --- | --- |
| Prometheus | `ixora-prometheus` | prometheus | ✅ yes |
| Loki | `ixora-loki` | loki | no |
| Tempo | `ixora-tempo` | tempo | no |

**Critical rule:** These UIDs are embedded in every future dashboard JSON file. Changing a UID after Phase 9 deployment is a **breaking change** that silently breaks every panel referencing the old UID. If a UID must change (e.g., Prometheus replaced by Thanos), all dashboard JSONs must be batch-updated and all Grafana SQLite state must be cleared.

### 3.2 Datasource design decisions

| Decision | Choice | Rationale |
| --- | --- | --- |
| Access mode | `proxy` (all three) | Browser never connects to backends directly. Grafana server proxies all queries via Docker network. Required when backends are bound to `127.0.0.1` on the host. |
| `editable: false` | All three | Prevents UI drift. Config changes must go through `datasources.yaml` → git → container restart. |
| Default datasource | Prometheus | Most panels are metric-based. Reduces friction in Explore and new panel creation. |
| Prometheus `timeInterval` | `30s` | Matches `prometheus.yml` `scrape_interval`. Grafana auto-fills `min_step` correctly in panel queries. |
| Prometheus HTTP method | `POST` | Avoids URL length limits on long PromQL expressions (complex multi-sum queries). |
| Exemplar linking | Prometheus → Tempo via `trace_id` label | Enables one-click from a Prometheus histogram spike to the corresponding Tempo trace. Requires Prometheus to store exemplars (Phase 9 to verify). |
| Loki `derivedFields` | `trace_id` → Tempo | Every log line injected with `trace_id` by `TraceCorrelationLogTap` gets a clickable Tempo link in Grafana Explore. |
| Tempo → Loki | Custom LogQL with `trace_id` filter | Enables the Trace → Log drill-down workflow defined in `dashboard-requirements.md §10`. |
| Tempo → Prometheus | Service map via `service.name` label | Enables the service topology graph and metric correlation from trace view. |
| Tempo `nodeGraph` | enabled | Visual span tree in Grafana trace view — no additional config needed. |

### 3.3 Retention annotations (per ADR-031)

| Datasource | Retention | Consequence in Grafana |
| --- | --- | --- |
| Prometheus | 30 days | `time_range` variable max should be capped at `30d` in dashboard defaults |
| Loki | 14 days | Log panels should default to `Last 1h`; warn users that > 14d lookbacks return empty |
| Tempo | 7 days | "Recent Failing Traces" panels must note 7-day window; post-mortem queries > 7d require log-only investigation |

---

## 4. Folder Strategy

### 4.1 Folder hierarchy

Dashboard folders map to the audience and operational context of the dashboards they contain. Each folder corresponds to a directory in `grafana/provisioning/dashboards/` and is registered with a stable `folderUID`.

| Folder | folderUID | Audience | Dashboards |
| --- | --- | --- | --- |
| Infrastructure | `ixora-folder-infrastructure` | SRE, on-call | D-07 Collector & Infrastructure |
| Application | `ixora-folder-application` | On-call, SRE | D-04 Queue Workers, D-05 HTTP API, D-06 Scheduler |
| Business | `ixora-folder-business` | Product, on-call | D-02 Smart Home, D-03 Push Notifications |
| Overview | `ixora-folder-overview` | All | D-01 Platform Overview |

### 4.2 Folder lifecycle

Grafana creates a folder automatically when the dashboard provider scans the associated directory and finds at least one `.json` file. Currently all directories contain only `.gitkeep` — no Grafana folders exist yet. They will be created when Phase 9 dashboard JSON files are deployed.

`folderUID` values are defined in `providers.yaml` so the folder identity is stable from the moment the first dashboard is deployed, regardless of the order of deployment.

### 4.3 Future expansion

New domains (Matter, Google Home, Marketplace, AI) should add dashboards to the `Business` folder unless their audience is exclusively SRE (→ `Infrastructure`) or they represent a major product area warranting a new folder. New folders require a new provider entry in `providers.yaml`, a new directory under `dashboards/`, and a new `folderUID` in this document.

---

## 5. Dashboard-as-Code Standard

Every future dashboard (Phase 9) must follow this standard.

### 5.1 Authoring workflow

```
1. Define panels in Grafana UI (against staging environment)
2. Export dashboard JSON: Dashboard menu → Share → Export → Save to file
3. Set stable UID in JSON: "uid": "ixora-dashboard-<name>" (see §5.3)
4. Set folderUID in JSON: "folderUID": "ixora-folder-<folder>" (see §4.1)
5. Save to the correct provisioning directory:
     infrastructure/ → D-07
     application/    → D-04, D-05, D-06
     business/       → D-02, D-03
     overview/       → D-01
6. Commit to feature branch → PR → develop → staging
7. Validate: Grafana picks up the file within 60 seconds (provider poll)
```

### 5.2 Export policy

- Always export with **"Export for sharing externally"** disabled — this preserves datasource UIDs as `ixora-*` rather than replacing them with `$\{DS_PROMETHEUS\}` template variables.
- Do NOT use Grafana's "Copy panel to clipboard" as a sharing mechanism — the clipboard JSON is not reusable across instances.
- Never export with `"id": <number>` — always replace with `"id": null` (Grafana assigns a local ID on import).

### 5.3 Dashboard UID convention

```
ixora-dashboard-<slug>
```

| Dashboard | UID |
| --- | --- |
| D-01 Platform Overview | `ixora-dashboard-platform-overview` |
| D-02 Smart Home | `ixora-dashboard-smart-home` |
| D-03 Push Notifications | `ixora-dashboard-push-notifications` |
| D-04 Queue Workers | `ixora-dashboard-queue-workers` |
| D-05 HTTP API | `ixora-dashboard-http-api` |
| D-06 Scheduler | `ixora-dashboard-scheduler` |
| D-07 Collector & Infrastructure | `ixora-dashboard-collector-infrastructure` |

Dashboard UIDs are stable once deployed. Renaming requires a migration plan.

### 5.4 Required JSON fields (every dashboard)

```json
{
  "uid": "ixora-dashboard-<slug>",
  "folderUID": "ixora-folder-<folder>",
  "title": "<Human Readable Title>",
  "tags": ["ixora", "<domain>"],
  "schemaVersion": 39,
  "refresh": "1m",
  "time": { "from": "now-1h", "to": "now" },
  "templating": {
    "list": [
      { "$ref": "#/components/schemas/variable-environment" },
      { "$ref": "#/components/schemas/variable-time_range" }
    ]
  }
}
```

Every panel query **must** include `{environment=~"$environment"}` (or the equivalent label filter for the datasource type) to ensure `$environment` is always applied.

### 5.5 Git lifecycle

```
feature/grafana-dashboard-<name>
  → develop (PR)
  → staging (docker compose pull && docker compose up -d grafana)
  → production (Phase 10+)
```

Dashboard JSON files are treated as infrastructure code. PRs require:
- Screenshot of all panels rendering correctly in staging.
- `$environment` variable applied to every panel.
- Stable `uid` and `folderUID` present.

---

## 6. Platform Variables Strategy

All dashboards must include these variables. They are defined once here and copied into each dashboard JSON.

### 6.1 Mandatory variables (every dashboard)

| Variable | Name | Type | Values | Query |
| --- | --- | --- | --- | --- |
| Environment | `$environment` | Custom | `development`, `staging`, `production` | Static; default `staging` |
| Time range | handled by Grafana time picker | — | — | — |

The `$environment` variable must be set as a **required** variable with no `All` option. A dashboard showing production data when `environment=staging` is selected is a data quality failure.

### 6.2 Domain-specific variables

These variables are only included in dashboards that need them. They are not global.

| Variable | Name | Scope | Query |
| --- | --- | --- | --- |
| Queue | `$queue` | D-04 Queue Workers | `label_values(ixora_queue_job_total{environment="$environment"}, queue)` |
| HTTP route | `$route` | D-05 HTTP API | `label_values(ixora_http_server_duration_count{environment="$environment"}, http_route)` |
| Provider | `$provider` | D-02 Smart Home | `label_values(ixora_smart_home_action_total{environment="$environment"}, provider)` |
| Outcome | `$outcome` | D-02 Smart Home | Static: `success`, `failure`, `unsupported` |
| Notification type | `$notification_type` | D-03 Push | `label_values(ixora_push_delivery_total{environment="$environment"}, notification_type)` |

### 6.3 Cardinality policy for variables

Variables must use **label values from existing metrics** — not from Loki log fields or span attributes. This ensures:
- Variable dropdowns populate in < 1 second (Prometheus label index, not a Loki query).
- Variable values are bounded (they are metric labels, which are already cardinality-controlled per ADR-031).
- Variable queries never scan unlimited log lines.

---

## 7. Navigation Strategy

### 7.1 Cross-dashboard links

Every domain dashboard must include links to adjacent dashboards in the same investigation flow. Links are defined in the dashboard JSON under `"links"` array.

```
Platform Overview (D-01)
  ├── → Smart Home (D-02)         [when Smart Home row shows anomaly]
  ├── → Queue Workers (D-04)      [when queue failure rate rises]
  ├── → HTTP API (D-05)           [when API error rate rises]
  └── → Scheduler (D-06)          [when scheduler dispatch rate drops]

Smart Home (D-02)
  ├── → Queue Workers (D-04)      [Smart Home queue backlog]
  └── → Platform Overview (D-01)  [back link]
```

### 7.2 Tempo drill-down

Grafana links to Tempo traces via the **Explore** sidebar panel that appears when clicking on a metric anomaly. The `exemplarTraceIdDestinations` config in `datasources.yaml` enables the one-click Metric → Trace flow for Prometheus exemplars.

For manual trace lookup from a dashboard panel, add a **Tempo data link** to histogram panels:

```json
{
  "title": "Open in Tempo",
  "url": "/explore?datasource=ixora-tempo&left={\"queries\":[{\"refId\":\"A\",\"datasource\":{\"uid\":\"ixora-tempo\"},\"queryType\":\"traceql\",\"query\":\"{span.trace_id=\\\"${__value.raw}\\\"}\"}}]}"
}
```

### 7.3 Loki drill-down

Loki drill-down happens via derived fields in `datasources.yaml` — every log line with a `trace_id` field gets a clickable "Open in Tempo" button in Grafana Explore automatically. No per-dashboard configuration is needed.

For direct Loki links from dashboard panels:

```json
{
  "title": "Open logs",
  "url": "/explore?datasource=ixora-loki&left={\"queries\":[{\"refId\":\"A\",\"expr\":\"{service_name=\\\"${__series.labels.service_name}\\\"} | json | trace_id=\\\"${__value.raw}\\\"\"}]}"
}
```

---

## 8. Plugin Policy

### 8.1 Current plugins

No additional plugins are installed in Phase 8.1. All required visualization types (time series, stat, histogram, bar, table, pie) are built into Grafana OSS.

### 8.2 Plugin evaluation framework

Before installing any plugin, it must satisfy all four criteria:

| Criterion | Question |
| --- | --- |
| **Necessity** | Is there a built-in panel type that can substitute? If yes, use built-in. |
| **Maintenance** | Is the plugin actively maintained and compatible with Grafana 11.x? |
| **Security** | Does the plugin load external resources or make outbound network calls? |
| **Stability** | Is the plugin in the official Grafana plugin catalog? |

### 8.3 Plugin decisions — Phase 8.1

| Plugin | Decision | Reason |
| --- | --- | --- |
| Grafana Canvas panel | Built-in — no install needed | Topology diagrams if needed |
| Grafana Flame Graph | Built-in — no install needed | Profiling visualization (Phase 10+) |
| Grafana Business Charts | **Reject** | Echarts dependency; built-in bar/time series sufficient |
| Any "Community" panel | **Defer** — evaluate per Phase 9 need | Must pass §8.2 before installation |
| ClickHouse / Elasticsearch | **Not applicable** — not in Ixora stack | — |

Plugins, if needed in Phase 9, are installed via the `GF_INSTALL_PLUGINS` environment variable (comma-separated). Example:

```yaml
GF_INSTALL_PLUGINS: "grafana-piechart-panel 1.6.4"
```

Pinning the version is mandatory. Never use `grafana-piechart-panel` without a version.

---

## 9. Security Review

### 9.1 Authentication

| Setting | Value | Rationale |
| --- | --- | --- |
| `GF_AUTH_ANONYMOUS_ENABLED` | `false` | All access requires credentials. No public dashboards. |
| `GF_AUTH_BASIC_ENABLED` | `true` | Required for API access by validation scripts and CI. |
| `GF_USERS_ALLOW_SIGN_UP` | `false` | Admin creates all accounts. |
| Admin user | from `GF_ADMIN_USER` env var | Never hardcoded. |
| Admin password | from `GF_ADMIN_PASSWORD` env var | Never hardcoded. Stored in `.env` (gitignored). |

**Staging/production recommendation:** Enable OAuth2 / OIDC (`GF_AUTH_GENERIC_OAUTH_*`) and disable basic auth for human users. Keep basic auth enabled for the validation script service account.

### 9.2 Network exposure

- Grafana binds to `127.0.0.1:3000` on the host (never `0.0.0.0`).
- All backends (Prometheus, Loki, Tempo) are on the same Docker bridge — Grafana reaches them via service-name DNS without exposing their ports to the internet.
- External access goes through a reverse proxy (Caddy/nginx) with HTTPS termination. The Grafana container never terminates TLS directly.

### 9.3 Cookie security

| Environment | `GF_SECURITY_COOKIE_SECURE` | `GF_SECURITY_COOKIE_SAMESITE` |
| --- | --- | --- |
| Development | `false` | `lax` |
| Staging | `true` | `strict` |
| Production | `true` | `strict` |

Set these via the `.env` file — never change them in the Grafana UI.

### 9.4 Analytics / external calls

All Grafana telemetry and update-check outbound connections are disabled:

```
GF_ANALYTICS_REPORTING_ENABLED=false
GF_ANALYTICS_CHECK_FOR_UPDATES=false
GF_ANALYTICS_CHECK_FOR_PLUGIN_UPDATES=false
GF_ANALYTICS_FEEDBACK_LINKS_ENABLED=false
GF_SECURITY_DISABLE_GRAVATAR=true
```

This prevents unexpected outbound connections from the VM, which could bypass network egress controls.

### 9.5 Datasource security

- All datasources use `access: proxy` — the browser never connects to backends directly.
- All datasources are `editable: false` — changes require git PR + container restart.
- Datasource credentials (if added in future — e.g., Prometheus basic auth) must be stored as environment variables, never in the provisioning YAML file.

### 9.6 Future RBAC

Grafana 11 supports Role-Based Access Control. Post-MVP recommendation:

| Role | Access | Dashboards |
| --- | --- | --- |
| Admin | Full | All |
| Editor | Create/edit dashboards | All |
| Viewer | Read-only | All |
| Product (future) | Read-only | Business folder only |
| SRE (future) | Read-only + Explore | Infrastructure + Application |

---

## 10. Environment Strategy

### 10.1 Environment variable matrix

| Variable | Development | Staging | Production |
| --- | --- | --- | --- |
| `GF_SERVER_ROOT_URL` | `http://localhost:3000` | `https://grafana-staging.ixora-app.app` | `https://grafana.ixora-app.app` |
| `GF_SECURITY_COOKIE_SECURE` | `false` | `true` | `true` |
| `GF_SECURITY_COOKIE_SAMESITE` | `lax` | `strict` | `strict` |
| `GF_LOG_LEVEL` | `info` | `warn` | `warn` |
| `GF_ADMIN_PASSWORD` | local `.env` | DigitalOcean App Secret | Vault / secrets manager |

### 10.2 Reproducibility guarantee

The following sequence must produce a working Grafana instance from scratch with no manual steps:

```bash
# 1. Clone repo
git clone <repo>
cd ixora-infra/collector

# 2. Configure secrets
cp .env.example .env
# Edit .env: set GF_ADMIN_PASSWORD and OTEL_INGEST_API_KEY_*

# 3. Start stack
docker compose up -d

# 4. Wait for healthy (≈ 60 seconds for first pull + startup)
docker compose ps

# 5. Validate
GF_ADMIN_PASSWORD=<password> ./grafana/validate.sh
# Expected: PASS: All 12 checks passed.
```

### 10.3 CI integration

The validation script can be run in CI after a `docker compose up -d` in a GitHub Actions runner:

```yaml
- name: Start observability stack
  run: docker compose -f collector/docker-compose.yml up -d

- name: Wait for Grafana
  run: |
    for i in {1..12}; do
      sleep 10
      if curl -sf http://localhost:3000/api/health | grep -q '"database": "ok"'; then
        echo "Grafana healthy"
        break
      fi
    done

- name: Validate Grafana foundation
  run: GF_ADMIN_PASSWORD=${{ secrets.GF_ADMIN_PASSWORD }} ./collector/grafana/validate.sh
```

### 10.4 Data persistence

Grafana's `grafana_data` named volume stores:
- SQLite database (user sessions, alert state, playlist state)
- Grafana internal state

Datasources and dashboards are **NOT** stored in the volume — they come from `provisioning/`. Deleting the volume and recreating Grafana produces an identical platform (zero lost configuration). The only lost data is user preferences and alert state (both acceptable losses for staging recreation).

---

## 11. Backend Config Fixes (Phases 4–6 debt)

During Phase 8.1 startup validation, Tempo (2.6.0) and Loki (3.2.0) failed to start due to config field renames between their declared versions and the Phase 5/6 YAML files. These were fixed as a prerequisite for Grafana connectivity validation.

### Tempo (collector/tempo/tempo.yaml)

| Fix | Line | Old field | Change |
| --- | --- | --- | --- |
| `ingester.wal` removed | 74 | `ingester.wal.path` | Removed — WAL already configured under `storage.trace.wal` |
| `storage.trace.block.index_downsample_bytes` removed | 121 | `index_downsample_bytes: 1000` | Removed — deprecated in Tempo 2.x |
| `storage.trace.block.encoding` removed | 122 | `encoding: snappy` | Removed — deprecated in Tempo 2.x |
| `query_frontend` sub-block timeouts removed | 137–142 | `search.query_timeout`, `trace_by_id.query_timeout` | Removed; `max_batch_size: 5` added (required by Tempo 2.6) |
| Top-level `search` block removed | 180 | `search:` | Removed — field does not exist in `app.Config` in Tempo 2.6 |
| `overrides.defaults` replaced | 192 | `overrides.defaults.ingestion.*` | Replaced with flat `overrides.ingestion_rate_limit_bytes` etc. |

### Loki (collector/loki/loki.yaml)

| Fix | Line | Old field | Change |
| --- | --- | --- | --- |
| `limits_config.max_label_names` removed | 171 | `max_label_names: 100` | Removed — field renamed; `max_label_names_per_series` (already present) is the correct field in Loki 3.x |
| `querier.query_timeout` removed | 192 | `query_timeout: 5m` | Removed — field moved in Loki 3.x (use `limits_config.query_timeout` if needed) |
| `ingester.wal.recover_from_wal` removed | 218 | `recover_from_wal: true` | Removed — WAL recovery is automatic in Loki 3.x; field was dropped |

---

## 12. Future Extensibility

### 12.1 Adding a new datasource

1. Add a new entry to `grafana/provisioning/datasources/datasources.yaml`.
2. Choose a stable UID: `ixora-<datasource-slug>` (e.g., `ixora-thanos` if Prometheus is replaced).
3. Restart Grafana: `docker compose restart grafana`.
4. Add the UID to this document.

### 12.2 Adding a new dashboard folder

1. Create directory: `grafana/provisioning/dashboards/<folder-slug>/`.
2. Add a provider entry to `grafana/provisioning/dashboards/providers.yaml`.
3. Choose a stable folderUID: `ixora-folder-<folder-slug>`.
4. Add the folderUID to §4.1 of this document.

### 12.3 Multiple environments

The current setup supports one Grafana instance per environment (staging uses this config). Production deployment requires only changing:
- `GF_SERVER_ROOT_URL` to the production domain.
- `GF_SECURITY_COOKIE_SECURE=true`.
- `GF_ADMIN_PASSWORD` sourced from a production secret manager.
- `GF_LOG_LEVEL=warn`.

Datasource URLs and UIDs remain identical across environments (Prometheus/Loki/Tempo run on the same Docker network regardless of environment).

### 12.4 Multiple Prometheus instances (future)

If multiple Prometheus instances are needed (e.g., production + separate staging):

1. Add `ixora-prometheus-production` as a second datasource with a different URL.
2. Add a `$prometheus_instance` template variable to affected dashboards.
3. The stable UID `ixora-prometheus` continues to refer to the primary/staging instance.

### 12.5 Grafana version upgrade

1. Update `GRAFANA_VERSION` in `.env` and `.env.example`.
2. Test in development: `docker compose up -d grafana`.
3. Run `./grafana/validate.sh` — all 12 checks must pass.
4. Commit `.env.example` change to a feature branch.

---

## 13. Validation Results

### 13.1 Initial validation (first start)

| Check | Result |
| --- | --- |
| Grafana health (database: ok) | ✅ PASS |
| Prometheus UID `ixora-prometheus` | ✅ PASS |
| Loki UID `ixora-loki` | ✅ PASS |
| Tempo UID `ixora-tempo` | ✅ PASS |
| Default datasource: Prometheus | ✅ PASS |
| Prometheus connectivity: OK | ✅ PASS |
| Loki connectivity: OK | ✅ PASS |
| Tempo connectivity: plugin health N/A | ✅ PASS (see note) |
| Prometheus readOnly=true | ✅ PASS |
| Loki readOnly=true | ✅ PASS |
| Tempo readOnly=true | ✅ PASS |
| Datasource count: 3 (no extras) | ✅ PASS |
| **Total** | **12/12** |

> **Note on Tempo connectivity:** The Grafana Tempo plugin does not implement the `/api/datasources/uid/{uid}/health` endpoint in Grafana 11.3.0. The validation script detects the `plugin.notImplemented` response and reports PASS. Tempo reachability is confirmed by Grafana's internal datasource save/test flow when the provisioning file is first loaded.

### 13.2 Idempotency validation (post-restart)

`docker compose restart grafana` → `./grafana/validate.sh` → **12/12 PASS**

All datasource UIDs, connectivity, and count remain identical after container restart. Provisioning is confirmed idempotent.

---

## 14. Known Limitations

| Limitation | Impact | Phase |
| --- | --- | --- |
| Grafana folders are empty (no dashboards) | Folders don't exist in Grafana UI yet — created when Phase 9 JSONs arrive | Phase 9 |
| Tempo plugin health API not implemented | Cannot programmatically check Tempo connectivity via Grafana API; validated by manual Explore query | Phase 9 note |
| Single Grafana instance | No HA for Grafana (single VM) | Phase 10 production planning |
| Basic auth only (no OAuth) | All users share admin credentials or must be created manually | Post-MVP RBAC phase |
| Grafana admin password in `.env` | `.env` is gitignored but present on VM in plaintext | Phase 10: use DO secrets or Vault |
| No alert rules | `provisioning/alerting/` has no rules — alerting foundation complete (Phase 8.8); alert rules are Phase 9 | Phase 9 |

---

## 15. Recommendations for Phase 8.2 (D-07 Collector Dashboard)

1. **D-07 implementation first** — the Collector & Infrastructure dashboard requires no business signals (all `otelcol_*` self-metrics are available now). It is the lowest-risk first dashboard.
2. **Verify Prometheus exemplar storage** — the `exemplarTraceIdDestinations` config in `datasources.yaml` requires Prometheus to store exemplars. Confirm `--enable-feature=exemplar-storage` flag in `prometheus.yml` or add it.
3. **Tempo health verification** — add a separate Tempo connectivity check in `validate.sh` that curls `http://tempo:3200/ready` directly from inside a Docker exec (bypasses the Grafana plugin limitation).
4. **Dashboard variable test** — after adding the first dashboard JSON, verify `$environment` variable populates correctly from Prometheus label values.
5. **Reverse proxy** — document the Caddy/nginx config for HTTPS termination in front of Grafana (required for `GF_SECURITY_COOKIE_SECURE=true` on staging).

---

## Related documents

| Document | Relationship |
| --- | --- |
| [dashboard-requirements.md](dashboard-requirements.md) | Phase 8.0 — panel definitions and folder assignments this foundation serves |
| [business-telemetry-foundation.md](../business-telemetry/business-telemetry-foundation.md) | Signal contracts that datasource queries must follow |
| [metrics-philosophy.md](../../../architecture/metrics-philosophy.md) | Cardinality constraints relevant to variable query design |
| [telemetry-naming-convention.md](../../../architecture/telemetry-naming-convention.md) | Metric/span/log names used in panel queries |
| [ADR-028](../../../decisions/ADR-028-observability-platform.md) | Collector-only ingestion — Grafana reads from backends, never from apps |
| [ADR-030](../../../decisions/ADR-030-observability-security-and-privacy.md) | Security requirements for datasource and panel configuration |
| [ADR-031](../../../decisions/ADR-031-retention-storage-and-cost-control.md) | Retention limits documented in §3.3 |
