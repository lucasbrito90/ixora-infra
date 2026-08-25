# Alerting Foundation — Phase 8.8

**Status:** Complete  
**Type:** Architecture Specification + Provisioning Scaffold  
**Repo:** `ixora-infra`  
**Feature ID:** `observability-foundation/mvp`  
**Established:** Phase 8.8  
**ADRs:** [ADR-028](../../../decisions/ADR-028-observability-platform.md) · [ADR-029](../../../decisions/ADR-029-telemetry-data-model.md) · [ADR-030](../../../decisions/ADR-030-observability-security-and-privacy.md) · [ADR-031](../../../decisions/ADR-031-retention-storage-and-cost-control.md)  
**Philosophy:** [alerting-philosophy.md](../../../architecture/alerting-philosophy.md) ← read before implementing any alert rule  
**Prerequisite:** [grafana-foundation.md](grafana-foundation.md) (Phase 8.1) · [dashboard-conventions.md](dashboard-conventions.md) (Phase 8.3–8.6)

> **Rule:** This document specifies the alerting architecture — provisioning hierarchy, category definitions, severity model, runbook standard, and validation requirements. It does not contain alert rules. Alert rules are Phase 9+.

---

## 1. Overview

Phase 8.8 establishes the **Alerting Foundation** — the structural layer that all future alert rules must conform to. No alert rules are created in this phase.

### 1.1 What Phase 8.8 delivers

| Deliverable | Description |
| --- | --- |
| Alerting philosophy | [alerting-philosophy.md](../../../architecture/alerting-philosophy.md) — when to alert, severity model, lifecycle |
| Alerting foundation spec | This document — implementation standards, provisioning hierarchy, category registry |
| Provisioning scaffold | Directory structure + placeholder YAML files for Grafana alerting provisioning |
| Validation | validate.sh checks 58–67 — structural integrity of alerting foundation |
| Documentation | README.md, plan.md, tasks.md updated |

### 1.2 What Phase 8.8 explicitly excludes

- No Prometheus alert rules (`.rules.yaml`)
- No Grafana alert rules (alert group YAML)
- No contact points (Slack, email, PagerDuty, webhook)
- No notification policies with receivers
- No runtime alerts that fire
- No Loki alert rules
- No recording rules
- No SLO definitions

---

## 2. Integration with Existing Ecosystem

### 2.1 Dashboard relationship

Every alert rule (Phase 9+) must reference a dashboard from the current dashboard ecosystem.

| Dashboard | UID | Alert categories served |
| --- | --- | --- |
| D-01 Platform Overview | `ixora-platform` | Business overview; platform health summary |
| D-02 Smart Home | `ixora-smart-home` | Business / Smart Home |
| D-03 Push Notifications | `ixora-push` | Application / Push; Business / Push |
| D-04 Queue Workers | `ixora-queue` | Application / Queue |
| D-05 HTTP API | `ixora-http` | Application / HTTP |
| D-06 Scheduler | `ixora-scheduler` | Application / Scheduler |
| D-07 Infrastructure | `ixora-collector` | Infrastructure / Collector; Infrastructure / VM |

**Rule:** An alert rule without a matching deployed dashboard UID must not be deployed. Dashboard UIDs are stable and immutable per `dashboard-conventions.md §1.2`.

### 2.2 Metric relationship

All alert expressions reference the existing metric inventory from Phase 7A–7B.5.

| Service | Available metrics | Phase |
| --- | --- | --- |
| HTTP API | `ixora_http_server_duration_*` | 7B.1 |
| Queue Workers | `ixora_queue_job_total`, `ixora_queue_job_duration_*`, `ixora_queue_job_active` | 7B.2 |
| Console / Scheduler | `ixora_console_command_total`, `ixora_scheduler_execution_total`, `ixora_scheduler_dispatch_duration_*` | 7B.2–7B.3 |
| Smart Home | `ixora_smart_home_action_total`, `ixora_smart_home_action_duration_*`, `ixora_smart_home_dispatch_total` | 7B.4.6 |
| Telemetry export | `ixora_telemetry_export_failed_total` | 7A |
| Push (Phase 7B.5) | `ixora_push_delivery_total` | 7B.5 (pending) |

**Rule:** Alert expressions must only reference metrics in the above inventory, plus Prometheus built-in metrics (`up`, `prometheus_*`, `loki_*`, `tempo_*`). No speculative metric references.

### 2.3 Signal hierarchy

```
Alerts
  └── consume Metrics (PromQL expressions)
        ├── source: back_vibes instrumentation (Phase 7A–7B.5)
        │          └── OpenTelemetry → Collector → Prometheus
        └── source: infrastructure scrape (Collector self-metrics)

Alert notifications
  └── reference Dashboards (by UID)
        └── Dashboards are built on the same Metrics

Alert investigation
  ├── Dashboards (metric visualization)
  ├── Loki (log investigation)
  └── Tempo (trace drill-down)
```

---

## 3. Provisioning Hierarchy

### 3.1 Directory structure

```
collector/grafana/provisioning/
├── alerting/                          ← alert groups (Phase 9)
│   └── .gitkeep                       ← placeholder (Phase 8.8)
├── contact-points/                    ← contact point definitions
│   ├── contact-points.yaml            ← placeholder (no receivers Phase 8.8)
│   └── README.md                      ← structure documentation
├── notification-policies/             ← routing tree
│   ├── policies.yaml                  ← placeholder (Phase 9)
│   └── README.md                      ← structure documentation
├── mute-timings/                      ← maintenance windows
│   ├── mute-timings.yaml              ← placeholder (Phase 9)
│   └── README.md                      ← structure documentation
└── templates/                         ← message templates
    ├── templates.yaml                 ← placeholder (Phase 9)
    └── README.md                      ← structure documentation
```

### 3.2 Grafana alerting provisioning specification

> **Phase 9 correction:** the "Important" note below — that contact points, policies, mute timings, and templates are provisioned from their own dedicated sibling directories — was not verified against real Grafana behavior when written and turned out to be wrong. Empirically (Phase 9 local testing), Grafana only scans the single `alerting/` directory; files left in the sibling directories are silently never loaded. See [alerting-strategy.md §2.1](alerting-strategy.md#21-correction-where-these-files-actually-have-to-live) for the verified behavior and the resulting file layout. This note is left in place rather than rewriting the section below, per this repo's practice of correcting frozen specs via a pointer instead of editing history.



Grafana 11 supports provisioning all alerting resources as YAML files. Reference: [Grafana provisioning documentation](https://grafana.com/docs/grafana/latest/administration/provisioning/).

| Resource type | File location | Grafana API path |
| --- | --- | --- |
| Alert rules | `alerting/<group>.yaml` | `/api/v1/provisioning/alert-rules` |
| Contact points | `contact-points/contact-points.yaml` | `/api/v1/provisioning/contact-points` |
| Notification policies | `notification-policies/policies.yaml` | `/api/v1/provisioning/policies` |
| Mute timings | `mute-timings/mute-timings.yaml` | `/api/v1/provisioning/mute-timings` |
| Templates | `templates/templates.yaml` | `/api/v1/provisioning/templates` |

> **Important:** Grafana discovers alert files from the single `alerting/` directory configured in `grafana.ini` (`[paths] provisioning`). The `contact-points/`, `notification-policies/`, `mute-timings/`, and `templates/` sub-directories are conventions for organization. Grafana reads **all** files in the provisioning root's `alerting/` subdirectory. Other resource types (contact points, policies) are provisioned through their own dedicated directories.

### 3.3 Alert rule YAML structure (Phase 9 template)

```yaml
# collector/grafana/provisioning/alerting/<category>-<service>.yaml
#
# Format: Grafana alerting provisioning v1
# ADR-030: No PII in labels or annotations
# alerting-philosophy.md: read before adding rules
# alerting-foundation.md §4: category and severity reference

apiVersion: 1

groups:
  - orgId: 1
    name: <Category> — <Service>            # e.g. "Application — HTTP API"
    folder: Ixora Alerting                   # single folder for all alert rules
    interval: 1m                             # evaluation interval
    rules:
      - uid: ixora-alert-<slug>              # stable UID: ixora-alert-<category>-<condition>
        title: "<Category> / <Service> — <Condition>"  # alerting-philosophy.md §25
        condition: C
        data:
          - refId: A                         # metric query
            relativeTimeRange:
              from: 300
              to: 0
            datasourceUid: ixora-prometheus
            model:
              expr: <PromQL expression>
              intervalMs: 1000
              maxDataPoints: 43200
              refId: A
          - refId: B                         # reduce
            datasourceUid: __expr__
            model:
              type: reduce
              expression: A
              reducer: last
              settings:
                mode: dropNN
          - refId: C                         # threshold
            datasourceUid: __expr__
            model:
              type: threshold
              expression: B
              conditions:
                - evaluator:
                    type: gt
                    params: [<threshold>]
        noDataState: NoData
        execErrState: Error
        for: <duration>m
        labels:
          environment: "{{ $labels.environment }}"
          severity: <info|warning|critical|emergency>
          service: <service-name>
          team: <team-name>
          category: <infrastructure|application|business|security>
          dashboard_uid: <ixora-uid>
          runbook: /runbooks/<alert-slug>.md
        annotations:
          summary: "[{{ $labels.severity }}] {{ $labels.service }}: <condition summary>"
          description: "<Full description of the alert and immediate action>"
          dashboard: "/d/{{ $labels.dashboard_uid }}"
          runbook: "{{ $labels.runbook }}"
          business_impact: "<Impact on users or business processes>"
          expected_action: "<First action the engineer must take>"
```

---

## 4. Alert Categories

### 4.1 Infrastructure

**Purpose:** Monitor the observability platform itself — Collector, Prometheus, Loki, Tempo, Grafana, and VM resources. Failures here affect all other alerts (data gaps).

| Panel / Condition | Metric | Recommended severity | Dashboard |
| --- | --- | --- | --- |
| Collector export failures | `ixora_telemetry_export_failed_total` | Critical | D-07 |
| Prometheus target down | `up{job="prometheus"}` | Critical | D-07 |
| Loki unavailable | Loki ingestion health | Critical | D-07 |
| Tempo unavailable | Tempo push failures | Warning | D-07 |
| Grafana unavailable | Grafana health endpoint | Critical | D-01 |
| VM disk > 70% | Node exporter disk metric | Warning | D-07 |
| VM disk > 85% | Node exporter disk metric | Critical | D-07 |

**Typical investigation:**
1. D-07 Infrastructure dashboard
2. `docker ps` / `docker logs ixora-collector`
3. VM disk usage: `df -h`
4. Collector pipeline metrics in Grafana

**Inhibition rule:** When Collector Down (Emergency/Critical) fires, all metric-based downstream alerts must be suppressed. No data = no reliable threshold evaluation.

### 4.2 Application / HTTP API

**Purpose:** Monitor the HTTP API layer for error rate, latency, and availability.

| Panel / Condition | Metric | Recommended severity | Dashboard |
| --- | --- | --- | --- |
| 5xx error rate elevated | `ixora_http_server_duration{http_status_code=~"5.."}` rate | Critical | D-05 |
| p95 latency high | `histogram_quantile(0.95, rate(ixora_http_server_duration_bucket[5m]))` | Warning/Critical | D-05 |
| Zero request rate | `rate(ixora_http_server_duration_count[5m]) == 0` | Warning (context-dependent) | D-05 |

**Typical investigation:**
1. D-05 HTTP API dashboard
2. D-07 to confirm Collector health
3. Tempo for failing trace drill-down
4. Loki for error context

### 4.3 Application / Queue Workers

**Purpose:** Monitor queue job processing health for all queues (`smart-home`, `push`, `default`).

| Panel / Condition | Metric | Recommended severity | Dashboard |
| --- | --- | --- | --- |
| Job failure rate elevated | `ixora_queue_job_total{outcome="failed"}` rate / total | Warning/Critical | D-04 |
| Active jobs saturated | `ixora_queue_job_active` sustained above threshold | Warning | D-04 |
| Zero active jobs (unexpected) | `ixora_queue_job_active == 0` during traffic window | Warning | D-04 |
| Job p95 latency high | `histogram_quantile(0.95, rate(ixora_queue_job_duration_bucket[5m]))` | Warning | D-04 |

### 4.4 Application / Scheduler

**Purpose:** Monitor the scheduler dispatch loop for missed executions and failures.

| Panel / Condition | Metric | Recommended severity | Dashboard |
| --- | --- | --- | --- |
| Zero dispatches (unexpected) | `rate(ixora_scheduler_execution_total{outcome="success"}[5m]) == 0` | Warning | D-06 |
| Dispatch duration elevated | `histogram_quantile(0.95, rate(ixora_scheduler_dispatch_duration_bucket[5m]))` | Warning | D-06 |
| Dispatch failures | `rate(ixora_scheduler_execution_total{outcome="failure"}[5m])` | Warning | D-06 |

### 4.5 Application / Push Notifications

**Purpose:** Monitor push delivery queue health.

| Panel / Condition | Metric | Recommended severity | Dashboard |
| --- | --- | --- | --- |
| Push job failure rate elevated | `ixora_queue_job_total{queue="push",outcome="failed"}` rate | Warning/Critical | D-03 |
| Push queue saturation | `ixora_queue_job_active{queue="push"}` sustained high | Warning | D-03 |
| Push delivery failure (Phase 7B.5) | `ixora_push_delivery_total{outcome="failure"}` rate | Critical | D-03 |

### 4.6 Business / Smart Home

**Purpose:** Monitor Smart Home automation pipeline success rate from the product perspective.

| Panel / Condition | Metric | Recommended severity | Dashboard |
| --- | --- | --- | --- |
| Action failure rate elevated | `ixora_smart_home_action_total{outcome="failure"}` rate / total | Critical | D-02 |
| Provider unreachable pattern | `ixora_smart_home_action_total{outcome="failure",provider="home_assistant"}` rate | Critical | D-02 |
| Dispatch skipping all | `ixora_smart_home_dispatch_total{outcome="skipped"}` rate | Warning | D-02 |
| Zero actions (unexpected) | `rate(ixora_smart_home_action_total[5m]) == 0` | Warning (context-dependent) | D-02 |

### 4.7 Business / Push Notifications (Phase 7B.5)

**Purpose:** Monitor push notification delivery from the business perspective (per notification type).

| Panel / Condition | Metric | Recommended severity | Dashboard |
| --- | --- | --- | --- |
| Smart Home action failed notifications not sending | `ixora_push_delivery_total{notification_type="smart_home_action_failed",outcome="success"}` rate | Critical | D-03 |
| All notification types failing | `ixora_push_delivery_total{outcome="success"}` rate / total < threshold | Critical | D-03 |

> These alerts require Phase 7B.5 (`ixora_push_delivery_total`). Not deployable until that phase ships.

### 4.8 Business / Automation Pipeline

**Purpose:** Cross-domain monitoring of the full Scheduler → Smart Home → Push pipeline.

| Panel / Condition | Metric | Recommended severity | Dashboard |
| --- | --- | --- | --- |
| End-to-end automation failure | Composite: scheduler success rate + smart home action success rate | Critical | D-01 |
| Cross-domain failure spike | Rate increase across multiple domains simultaneously | Emergency | D-01 |

### 4.9 Security (Phase 9+)

**Purpose:** Detect anomalous operational patterns that indicate attack or compromise.

> Security alert rules are out of scope for Phase 8.8. The framework is documented here for Phase 9.

| Panel / Condition | Metric | Recommended severity | Dashboard |
| --- | --- | --- | --- |
| Authentication spike (401/403) | HTTP 4xx rate elevation on auth routes | Warning | D-05 |
| Push token registration spike | Push token registration rate anomaly | Warning | D-03 |
| OTLP ingest spike | Collector ingest rate 10× baseline | Warning | D-07 |

---

## 5. Contact Points (Phase 9 scaffold)

Contact points define **where** notifications are sent when an alert fires. Phase 8.8 provisions the directory structure only.

### 5.1 Planned contact points (Phase 9)

| Name | Type | Target | Severity filter |
| --- | --- | --- | --- |
| `ixora-default` | Grafana UI only | Grafana notification feed | All severities (fallback) |
| `ixora-slack-critical` | Slack | `#on-call-alerts` channel | Critical, Emergency |
| `ixora-slack-warnings` | Slack | `#infra-alerts` channel | Info, Warning |
| `ixora-email-emergency` | Email | On-call engineer | Emergency only |

**ADR-030 compliance:** Contact point configurations must never include PII. Slack webhook URLs and email addresses are environment-specific secrets — they must never be committed to the repository. They are injected via environment variables or DigitalOcean Secrets.

### 5.2 Contact point YAML structure (Phase 9 template)

```yaml
# collector/grafana/provisioning/contact-points/contact-points.yaml
# Phase 9: replace placeholder with real receiver definitions
# ADR-030: webhook URLs via env vars — never hardcoded

apiVersion: 1

contactPoints:
  - orgId: 1
    name: ixora-default
    receivers:
      - uid: ixora-receiver-default
        type: grafana_default_email
        disableResolveMessage: false

  # Phase 9: Slack receivers (webhook URL from environment)
  # - orgId: 1
  #   name: ixora-slack-critical
  #   receivers:
  #     - uid: ixora-receiver-slack-critical
  #       type: slack
  #       settings:
  #         url: "${SLACK_WEBHOOK_CRITICAL}"
  #         channel: "#on-call-alerts"
```

---

## 6. Notification Policies (Phase 9 scaffold)

Notification policies define the **routing tree** — which alerts go to which contact points.

### 6.1 Routing logic (Phase 9 design)

```
Root policy (catch-all → ixora-default)
├── severity=emergency → ixora-email-emergency + ixora-slack-critical
├── severity=critical  → ixora-slack-critical
│     group_by: [service, environment]
│     group_wait: 30s
│     group_interval: 5m
│     repeat_interval: 1h
├── severity=warning   → ixora-slack-warnings
│     group_by: [category, environment]
│     group_wait: 2m
│     group_interval: 15m
│     repeat_interval: 4h
└── severity=info      → ixora-default (Grafana UI only)
      group_by: [category]
      group_wait: 5m
      repeat_interval: 24h
```

### 6.2 Inhibition rules design

```
inhibit_rules:
  # Rule 1: Collector down → suppress all metric-based alerts
  - source_matchers: [alertname="Infrastructure / Collector — Collector Down"]
    target_matchers: [category="application", category="business"]
    equal: [environment]

  # Rule 2: Prometheus down → suppress all metric-based alerts
  - source_matchers: [alertname="Infrastructure / Prometheus — Target Missing"]
    target_matchers: [category="application", category="business"]
    equal: [environment]
```

---

## 7. Mute Timings (Phase 9 scaffold)

Mute timings define **planned maintenance windows** when alerts should be suppressed.

### 7.1 Standard mute timing definitions (Phase 9 template)

```yaml
# collector/grafana/provisioning/mute-timings/mute-timings.yaml
apiVersion: 1

muteTimes:
  - orgId: 1
    name: weekly-maintenance-window
    time_intervals:
      - weekdays: ["sunday"]
        times:
          - start_time: "02:00"
            end_time: "04:00"

  - orgId: 1
    name: deploy-window
    # Applied manually via Grafana UI during deployments
    time_intervals: []
```

---

## 8. Templates (Phase 9 scaffold)

Message templates control the **content and format** of alert notifications.

### 8.1 Standard template design

```yaml
# collector/grafana/provisioning/templates/templates.yaml
apiVersion: 1

templates:
  - orgId: 1
    name: ixora-alert-title
    template: |
      {{ define "ixora-alert-title" }}
      [{{ .CommonLabels.severity | upper }}] {{ .CommonLabels.service }}: {{ .CommonLabels.alertname }}
      {{ end }}

  - orgId: 1
    name: ixora-alert-body
    template: |
      {{ define "ixora-alert-body" }}
      *Alert:* {{ .CommonLabels.alertname }}
      *Severity:* {{ .CommonLabels.severity }}
      *Service:* {{ .CommonLabels.service }}
      *Environment:* {{ .CommonLabels.environment }}
      *Category:* {{ .CommonLabels.category }}

      *Summary:* {{ .CommonAnnotations.summary }}
      *Description:* {{ .CommonAnnotations.description }}

      *Dashboard:* {{ .CommonAnnotations.dashboard }}
      *Runbook:* {{ .CommonAnnotations.runbook }}

      *Business Impact:* {{ .CommonAnnotations.business_impact }}
      *Expected Action:* {{ .CommonAnnotations.expected_action }}
      {{ end }}
```

---

## 9. Runbook Standard

### 9.1 Required runbook sections

Every alert rule deployed to production must have a corresponding runbook in `docs/runbooks/<alert-slug>.md`.

```markdown
# Runbook: <Category> / <Service> — <Condition>

**Alert UID:** ixora-alert-<slug>
**Severity:** <severity>
**Dashboard:** [<Dashboard title>](/d/<uid>)
**Created:** <date>
**Owner:** <team>

## Symptoms

What the on-call engineer sees when this alert fires:
- Alert name and message
- Dashboard panel showing anomalous values
- Expected values vs observed values

## Likely Causes

Ordered from most to least common:
1. <Most common cause — specific and actionable>
2. <Second cause>
3. <Third cause>
4. <Rare but possible cause>

## Validation Steps

Confirm the root cause before taking action.

### Step 1: Confirm via dashboard
1. Open [<Dashboard>](/d/<uid>)
2. Navigate to section <section name>
3. Confirm <metric> is <value>

### Step 2: Check logs
```
{app="ixora-backend"} |= "<error pattern>"
```

### Step 3: Check traces
Open Tempo Explore. Filter by `service.name=<service>` in the alert time window.

## Recovery Steps

### For cause 1: <Description>
1. <Step 1>
2. <Step 2>

### For cause 2: <Description>
1. <Step 1>

## Verification

After recovery:
- [ ] Alert transitions to Resolved in Grafana
- [ ] Dashboard panel returns to healthy range
- [ ] No new errors in Loki for 5 minutes post-recovery

## Rollback

If recovery steps cause regression:
1. <Rollback procedure>

## Escalation

If unresolved within <N> minutes:
- Escalate to: <name/team>
- Via: <Slack channel / phone>

## Postmortem Checklist

- [ ] What was the root cause?
- [ ] How long was the impact?
- [ ] How many users were affected?
- [ ] Was the alert threshold appropriate?
- [ ] Was the runbook accurate?
- [ ] What changes prevent recurrence?
```

### 9.2 Runbook location convention

| Scope | Location |
| --- | --- |
| All runbooks | `docs/runbooks/<alert-slug>.md` |
| Alert slug format | `<category>-<service>-<condition>` (kebab-case) |
| Examples | `infrastructure-collector-down.md`, `application-http-error-rate.md` |

### 9.3 Runbook reference in alert rule

The runbook path must be consistent across:
- Alert rule `labels.runbook` field
- Alert rule `annotations.runbook` field
- Grafana dashboard panel description (investigation hint)

---

## 10. Naming Convention Reference

Full naming specification is in [alerting-philosophy.md §25](../../../architecture/alerting-philosophy.md). Summary:

| Pattern | Example |
| --- | --- |
| `<Category> / <Service> — <Condition>` | `Application / HTTP API — Elevated Error Rate` |
| Alert UID | `ixora-alert-http-error-rate` |
| Runbook file | `application-http-error-rate.md` |

---

## 11. Severity Reference

Full severity specification is in [alerting-philosophy.md §13](../../../architecture/alerting-philosophy.md). Summary:

| Severity | `for` guidance | Page? | Response window |
| --- | --- | --- | --- |
| `info` | 15–30 min | No | Next business day |
| `warning` | 5–15 min | No | Within business hours |
| `critical` | 2–5 min | Yes | 15–30 minutes |
| `emergency` | 0–2 min | Yes (all hands) | Immediate |

---

## 12. Label and Annotation Reference

Full specification in [alerting-philosophy.md §23–24](../../../architecture/alerting-philosophy.md). Summary:

### Required labels

```yaml
labels:
  environment: staging|production
  severity: info|warning|critical|emergency
  service: back_vibes-api|back_vibes-worker|ixora-collector
  team: backend|sre|product
  category: infrastructure|application|business|security
  dashboard_uid: ixora-platform|ixora-http|ixora-queue|ixora-scheduler|ixora-smart-home|ixora-push|ixora-collector
  runbook: /runbooks/<slug>.md
```

### Required annotations

```yaml
annotations:
  summary: "[{{ $labels.severity }}] {{ $labels.service }}: <summary>"
  description: "<Full description with action>"
  dashboard: "/d/{{ $labels.dashboard_uid }}"
  runbook: "{{ $labels.runbook }}"
  business_impact: "<User impact>"
  expected_action: "<Immediate first action>"
```

---

## 13. Alert Rule Inventory Placeholder

This section will be populated in Phase 9 as alert rules are implemented.

| Rule ID | Title | Category | Severity | Metric | `for` | Phase |
| --- | --- | --- | --- | --- | --- | --- |
| ixora-alert-collector-down | `Infrastructure / Collector — Collector Down` | infrastructure | emergency | `ixora_telemetry_export_failed_total` | 2m | Phase 9 |
| ixora-alert-http-error-rate | `Application / HTTP API — Elevated Error Rate` | application | critical | `ixora_http_server_duration{status_code=~"5.."}` | 5m | Phase 9 |
| ixora-alert-http-high-latency | `Application / HTTP API — High Latency` | application | warning | `histogram_quantile(0.95, ixora_http_server_duration_bucket)` | 5m | Phase 9 |
| ixora-alert-queue-failure-rate | `Application / Queue Workers — Failure Rate` | application | warning | `ixora_queue_job_total{outcome="failed"}` | 5m | Phase 9 |
| ixora-alert-scheduler-missed | `Application / Scheduler — Missed Executions` | application | warning | `ixora_scheduler_execution_total{outcome="success"}` | 10m | Phase 9 |
| ixora-alert-push-failure | `Application / Push Queue — Delivery Failure` | application | warning | `ixora_queue_job_total{queue="push",outcome="failed"}` | 5m | Phase 9 |
| ixora-alert-smart-home-failure | `Business / Smart Home — Elevated Failure Rate` | business | critical | `ixora_smart_home_action_total{outcome="failure"}` | 5m | Phase 9 |
| ixora-alert-vm-disk | `Infrastructure / VM — Disk Saturation` | infrastructure | warning | Node exporter disk metric | 15m | Phase 9 |

> No rules in the above table are deployed in Phase 8.8. This is a planning inventory only.

---

## 14. Validation Framework

`validate.sh` checks 58–67 verify the structural integrity of the Alerting Foundation.

| Check | Description |
| --- | --- |
| 58 | `alerting/` directory exists under provisioning |
| 59 | `contact-points/` directory exists under provisioning |
| 60 | `notification-policies/` directory exists under provisioning |
| 61 | `mute-timings/` directory exists under provisioning |
| 62 | `templates/` directory exists under provisioning |
| 63 | `alerting-philosophy.md` exists in `docs/architecture/` |
| 64 | `alerting-foundation.md` exists in `docs/specs/observability-foundation/mvp/` |
| 65 | `contact-points/contact-points.yaml` is valid YAML |
| 66 | `notification-policies/policies.yaml` is valid YAML |
| 67 | `mute-timings/mute-timings.yaml` is valid YAML |

All checks must pass before Phase 9 alert rule deployment.

---

## 15. Phase 9 Readiness Checklist

Before deploying the first alert rule in Phase 9:

- [ ] All Phase 8.8 validate.sh checks pass
- [ ] Contact points provisioned with real receivers (Slack webhook / email)
- [ ] Notification policies routing tree configured
- [ ] Mute timing for weekly maintenance window defined
- [ ] Message templates reviewed and customized
- [ ] At least one runbook written and reviewed
- [ ] Inhibition rules for Collector-down cascade defined
- [ ] Alert budget agreed by team (max pages/day)
- [ ] On-call rotation defined
- [ ] Escalation path documented and agreed
- [ ] Grafana admin verified: alerting → provisioning enabled in `grafana.ini`

---

## 16. Known Limitations

| ID | Limitation | Impact | Resolution |
| --- | --- | --- | --- |
| KL-A-1 | Phase 7B.5 (`ixora_push_delivery_total`) not yet implemented | Business/Push alerts cannot use per-notification-type breakdowns | Implement Phase 7B.5; update alert rule inventory |
| KL-A-2 | No node exporter deployed (Phase 8.8) | VM disk, CPU, memory alerts cannot use Node Exporter metrics | Phase 9: deploy Node Exporter as part of alert rule implementation |
| KL-A-3 | No recording rules | Complex multi-metric expressions must be computed in real-time by Grafana | Phase 9: add recording rules to Prometheus config for expensive alert expressions |
| KL-A-4 | `provisioning/alerting/` is empty (only `.gitkeep`) | No alert rules fire in Grafana | Expected — Phase 8.8 is foundation only |
| KL-A-5 | Contact points have no real receivers | Alerts would only appear in Grafana UI if rules existed | Phase 9: inject receiver credentials via environment |
| KL-A-6 | Single-VM deployment | No HA for alerting state; alert history lost on VM recreation | Phase 10 production planning |

---

## 17. Related Documents

| Document | Relationship |
| --- | --- |
| [alerting-philosophy.md](../../../architecture/alerting-philosophy.md) | Philosophy — read before implementing any alert rule |
| [dashboard-conventions.md](dashboard-conventions.md) | Dashboard UIDs referenced in all alert labels |
| [grafana-foundation.md](grafana-foundation.md) | Grafana provisioning infrastructure this alerting foundation builds on |
| [metrics-philosophy.md](../../../architecture/metrics-philosophy.md) | Source signals for alert expressions |
| [telemetry-naming-convention.md](../../../architecture/telemetry-naming-convention.md) | Canonical metric names in alert expressions |
| [telemetry-availability-policy.md](../../../architecture/telemetry-availability-policy.md) | Best-effort export — data gaps possible; use `noDataState: NoData` |
| [ADR-028](../../../decisions/ADR-028-observability-platform.md) | Platform architecture |
| [ADR-030](../../../decisions/ADR-030-observability-security-and-privacy.md) | No PII in alert labels or annotations |
| [ADR-031](../../../decisions/ADR-031-retention-storage-and-cost-control.md) | Metric retention (30 days) governs max alert lookback window |
