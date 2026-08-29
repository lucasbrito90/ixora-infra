# Incident Response Policy

**Status:** Active operational policy  
**Scope:** Staging incident response process — roles, communication, evidence collection, and postmortem  
**Applies to:** On-call engineer, infra operator, backend/mobile developers responding to alerts or production issues

**Architecture references:** [ADR-028](../decisions/ADR-028-observability-platform.md) · [ADR-030](../decisions/ADR-030-observability-security-and-privacy.md) · [alerting-philosophy.md](../architecture/alerting-philosophy.md) · [observability-playbook.md](observability-playbook.md) · [alerting-strategy.md](../specs/observability-foundation/mvp/alerting-strategy.md)

> **Purpose:** Define the **process** for responding to incidents: who does what, how to communicate, and how to document evidence and postmortems. This is **not** a technical troubleshooting guide — that is [observability-playbook.md](observability-playbook.md). Severity definitions, escalation paths by severity, and the investigation workflow are defined in [alerting-philosophy.md](../architecture/alerting-philosophy.md) (§13, §18, §26) and referenced here, not redefined.

**Prerequisite:** Phase 9 alerting deployed on the observability host ([alerting-strategy.md §7](../specs/observability-foundation/mvp/alerting-strategy.md)). Until an alert fires, use [observability-playbook.md](observability-playbook.md) reactively when problems are reported manually.

---

## 1. Purpose

When an alert fires or a user reports a problem, engineers need a **repeatable process** — not just technical steps, but clarity on ownership, communication, and documentation.

This policy provides:

- **Roles** during an incident (Incident Commander, On-call, Comms)
- **Severity → response** mapping (referencing the canonical severity model)
- **Communication channels** — what exists today and what is deferred
- **Evidence and timeline collection** — a single template for every incident
- **Postmortem** — a canonical checklist aligned with existing runbooks

This policy does **not** provide:

- Per-symptom investigation checklists → [observability-playbook.md](observability-playbook.md) (14 incident scenarios)
- Per-alert recovery steps → [docs/runbooks/](../runbooks/) (7 Phase 9 runbooks)
- Severity definitions, alert lifecycle, or investigation workflow → [alerting-philosophy.md](../architecture/alerting-philosophy.md) §13, §18, §26
- Alert provisioning, routing, or threshold tuning → [alerting-strategy.md](../specs/observability-foundation/mvp/alerting-strategy.md)

---

## 2. Roles

Ixora is operated today by a **single person** (Lucas). The three roles below are **functional roles** that one person accumulates during an incident. When a real team exists, these roles should be assigned explicitly (potentially to different people).

| Role | Responsibility during an incident | Who holds it today | When a team exists |
| --- | --- | --- | --- |
| **Incident Commander (IC)** | Owns the incident end-to-end: declares severity, coordinates investigation and recovery, decides when the incident is resolved, triggers postmortem for Critical/Emergency | Lucas (same person as On-call and Comms) | Dedicated IC per incident; may not be the person doing hands-on debugging |
| **On-call** | First responder: acknowledges alerts, executes the investigation workflow ([alerting-philosophy.md §26](../architecture/alerting-philosophy.md)), runs the relevant runbook, implements recovery | Lucas | Rotating on-call schedule with a primary and secondary |
| **Comms** | Keeps stakeholders informed: status updates, expected resolution time, post-incident summary | Lucas (minimal today — no external stakeholders to notify beyond the operator) | Dedicated comms lead or shared team channel for status updates |

**Single-operator note:** There is no handoff between roles today. The operator performs acknowledge → investigate → recover → document in sequence. The role table exists so future team members know what to split when headcount grows.

---

## 3. Severity → response

Severity definitions, operator expectations, and canonical escalation paths are defined in [alerting-philosophy.md §13](../architecture/alerting-philosophy.md) and [§18](../architecture/alerting-philosophy.md). The table below adds only **who responds today** given the single-operator reality.

| Severity | Response expectation (see §13) | Escalation path (see §18) | Who responds today |
| --- | --- | --- | --- |
| **Info** | Review during working hours; no page | None | Lucas — Grafana UI notification only; no email for info-level rules deployed yet |
| **Warning** | Investigate within 4 hours | No escalation unless unresolved 8 h | Lucas — email via Mailtrap sandbox (`ixora-default` contact point) |
| **Critical** | Respond within 15–30 minutes | 30 min unresolved → tech lead | Lucas — email via Mailtrap sandbox (`ixora-email-critical` contact point); no tech lead to escalate to |
| **Emergency** | Respond immediately | 15 min unresolved → product lead | Lucas — email via Mailtrap sandbox (`ixora-email-critical` contact point); no product lead to escalate to |

For the technical investigation steps after acknowledging an alert, follow [alerting-philosophy.md §26 Investigation Workflow Standard](../architecture/alerting-philosophy.md) — do not invent a parallel workflow here.

---

## 4. Communication channels

### 4.1 Active today (staging)

| Channel | What it delivers | Limitation |
| --- | --- | --- |
| **Grafana UI** | Alert state (Pending, Firing, Resolved); alert history; silences | Requires login to `grafana-staging.ixora-app.app`; not a push notification on a phone |
| **Email (Grafana SMTP → Mailtrap sandbox)** | Notification for `critical`/`emergency` → `ixora-email-critical`; `warning`/`info` → `ixora-default` | **Mailtrap is a sandbox** — messages appear in the Mailtrap dashboard only; they do **not** reach a real inbox. Documented in [alerting-strategy.md §2](../specs/observability-foundation/mvp/alerting-strategy.md) and [§7.2](../specs/observability-foundation/mvp/alerting-strategy.md). |

Routing tree, contact points, and SMTP wiring: [alerting-strategy.md §4](../specs/observability-foundation/mvp/alerting-strategy.md).

**Known staging state:** A 14-day silence on `DatasourceNoData` alerts for the Ixora Alerting folder is active until **2026-09-08** ([alerting-strategy.md §7.3](../specs/observability-foundation/mvp/alerting-strategy.md)). Genuine threshold breaches still notify normally.

### 4.2 Explicitly deferred (not in this phase)

| Item | Reason | Target |
| --- | --- | --- |
| Real SMTP relay (non-Mailtrap) | Sandbox does not page a human through their actual inbox | Swap `GF_SMTP_*` and `ALERT_EMAIL_ADDRESS` on the observability host when ready ([alerting-strategy.md KL-S-4](../specs/observability-foundation/mvp/alerting-strategy.md)) |
| Slack / team chat channel | No team workspace dedicated to incident comms | When a team channel exists ([alerting-strategy.md §1.2](../specs/observability-foundation/mvp/alerting-strategy.md)) |
| PagerDuty / Grafana OnCall / automated paging | Single-operator staging; no on-call rotation tool | When a real on-call tool is adopted ([alerting-strategy.md §1.2](../specs/observability-foundation/mvp/alerting-strategy.md)) |
| Status page or external stakeholder notifications | No external users depend on staging uptime today | When production launch requires it |

---

## 5. Evidence & timeline collection standard

Every incident — whether triggered by an alert or reported manually — should produce a written record. Use the template below. Store incident notes in a durable location the team agrees on (today: a local markdown file or issue tracker entry; future: dedicated incident repo or tool).

### 5.1 Incident record template

Copy and fill in for each incident:

```markdown
# Incident: [short title]

**Incident ID:** INC-YYYYMMDD-NNN (e.g. INC-20260829-001)
**Detected at:** YYYY-MM-DD HH:MM UTC
**Severity:** info | warning | critical | emergency
**Environment:** staging | production
**Status:** investigating | mitigated | resolved

## Alert(s) fired
- [ ] Alert name / UID (if applicable)
- [ ] Runbook used: docs/runbooks/<slug>.md

## Dashboards / queries used
- Dashboard UID or URL:
- PromQL / LogQL / Tempo queries:

## Timeline of actions
| Time (UTC) | Actor | Action |
| --- | --- | --- |
| HH:MM | | Alert acknowledged / incident declared |
| HH:MM | | Investigation step (dashboard, trace, logs) |
| HH:MM | | Root cause identified |
| HH:MM | | Recovery action taken |
| HH:MM | | Verified healthy (dashboard / alert Resolved) |

## Root cause
[One paragraph — infrastructure, application, external provider, data, or config]

## Resolved at
YYYY-MM-DD HH:MM UTC

## Impact summary
- Duration:
- Users / requests / jobs affected (if known):
- Business features affected:

## Evidence / links
- Grafana alert URL:
- Dashboard screenshot or panel link (redacted):
- Sample trace_id(s) (not full trace payloads):
- Relevant log lines (redacted):
- Related PR / deploy / config change:

## Follow-up
- [ ] Postmortem completed (§6) — required for Critical/Emergency
- [ ] Runbook updated if inaccurate
- [ ] Alert threshold tuned if false positive/negative
```

### 5.2 Privacy and security rules (ADR-030)

When filling the template:

- **Never paste secrets** — API keys, SMTP passwords, Firebase credentials, `OTEL_INGEST_API_KEY`, `.env` contents, or bearer tokens.
- **Never paste PII** — user emails, Firebase UIDs, device tokens, IP addresses tied to individuals, or raw request bodies with user data.
- **Redact before sharing** — same standard as [observability-playbook.md §16](../operations/observability-playbook.md) ("No secrets pasted in tickets or Slack") and [ADR-030](../decisions/ADR-030-observability-security-and-privacy.md).
- **Safe to include:** `trace_id`, alert name, metric names, dashboard UIDs, error codes (not tokens), infrastructure component names, timestamps.

---

## 6. Postmortem

A postmortem is required after every **Critical** or **Emergency** incident, and recommended after Warning incidents with user-visible impact. The checklist below is the **canonical template** — it generalizes the "Postmortem Checklist" sections embedded in the 7 Phase 9 runbooks and the "Recovery checklist" in [observability-playbook.md §17](../operations/observability-playbook.md).

### 6.1 Postmortem checklist

**Root cause and impact**

- [ ] What was the root cause?
- [ ] How long was the impact?
- [ ] How many users / requests / jobs / devices were affected (if measurable)?

**Alert and runbook quality**

- [ ] Did the right alert fire (if alert-driven)?
- [ ] Was the alert threshold / `for` duration appropriate, or too eager / too slow?
- [ ] Was the runbook accurate and sufficient?
- [ ] Was anything masked by an observability gap (Collector down, missing metrics)?

**Recovery verification** (from [observability-playbook.md §17](../operations/observability-playbook.md))

- [ ] Dashboards show normal rates after fix
- [ ] Spot-check Tempo trace for the fixed workflow
- [ ] Loki logs include `trace_id` on instrumented paths
- [ ] Root cause documented in incident notes (§5 template)

**Prevention**

- [ ] What changes prevent recurrence (code fix, config change, infra sizing, retry/backoff tuning, dependency circuit breaker, tests, canary deploy)?
- [ ] If instrumentation bug — fix per [telemetry-decision-guide.md](../architecture/telemetry-decision-guide.md)
- [ ] If infra change — update operational checklists when applicable

**Hygiene**

- [ ] No secrets or PII in incident notes or postmortem ([ADR-030](../decisions/ADR-030-observability-security-and-privacy.md))

### 6.2 Relationship to existing runbooks

The 7 Phase 9 runbooks already include an embedded "Postmortem Checklist" tailored to each alert (e.g. threshold-specific questions). **Do not rewrite those runbooks** — they remain valid for alert-specific context. Use this section as the **shared baseline**; runbook-specific items are additive.

| Runbook | Embedded checklist |
| --- | --- |
| [infrastructure-collector-down.md](../runbooks/infrastructure-collector-down.md) | Data gap duration, masked incidents, `for` duration |
| [application-http-error-rate.md](../runbooks/application-http-error-rate.md) | 1% / 5m threshold, runbook accuracy |
| [application-http-high-latency.md](../runbooks/application-http-high-latency.md) | 2s / 5m threshold, runbook accuracy |
| [application-queue-failure-rate.md](../runbooks/application-queue-failure-rate.md) | Queue(s) affected, 5% / 5m threshold |
| [application-scheduler-missed.md](../runbooks/application-scheduler-missed.md) | Schedules missed, 10m threshold |
| [application-push-failure.md](../runbooks/application-push-failure.md) | Notifications affected, 10% / 5m threshold |
| [business-smart-home-failure.md](../runbooks/business-smart-home-failure.md) | Devices affected, 20% / 5m threshold |

**Future runbooks** should link to this postmortem checklist (§6.1) instead of duplicating the full baseline.

---

## 7. Escalation

### 7.1 When to escalate investigation effort

Follow the criteria in [observability-playbook.md §16 Escalation checklist](../operations/observability-playbook.md):

- Business impact confirmed (users cannot use automations, API down)
- Root cause not found within 30 minutes using the playbook
- Data loss suspected (Postgres, not telemetry)
- Security incident (PII in logs/traces — [ADR-030](../decisions/ADR-030-observability-security-and-privacy.md))
- Observability VM unrecoverable without rebuild
- Production environment affected

**Include in escalation handoff:** environment, time range, `trace_id` samples, dashboard screenshots, relevant log lines (redacted) — per §5.2.

### 7.2 Escalation paths by severity

Canonical paths: [alerting-philosophy.md §18](../architecture/alerting-philosophy.md).

| Severity | Canonical path | Reality today (single operator) |
| --- | --- | --- |
| Info | No escalation | N/A |
| Warning | Slack notification; escalate if unresolved 8 h | No Slack; operator self-escalates by dedicating focused time or deferring to next working session |
| Critical | On-call → tech lead at 30 min | Lucas is on-call; **there is no tech lead to escalate to** — continue investigation or declare need for external help |
| Emergency | On-call + tech lead → product lead at 15 min | Lucas is on-call; **there is no product lead to escalate to** — same as Critical |

**Practical guidance for single operator:** "Escalation" today means **widening the investigation** (switch from runbook to full [observability-playbook.md](observability-playbook.md), involve a future teammate, or pause and schedule focused recovery time) — not paging another on-call rotation.

---

## 8. Document boundaries

| Topic | Owner document |
| --- | --- |
| Technical incident scenarios (scheduler, push, Collector, Prometheus, Loki, Tempo, CPU, disk, cardinality, mobile) | [observability-playbook.md](observability-playbook.md) |
| Per-alert recovery runbook | [docs/runbooks/](../runbooks/)`<slug>.md` |
| Severity model, alert lifecycle, investigation workflow, label conventions | [alerting-philosophy.md](../architecture/alerting-philosophy.md) |
| Alert deployment, contact points, routing, staging rollout state | [alerting-strategy.md](../specs/observability-foundation/mvp/alerting-strategy.md) |
| **Incident response process: roles, communication, evidence, postmortem** | **This document** |

---

## 9. Known limitations

| ID | Limitation | Impact |
| --- | --- | --- |
| KL-IR-1 | **No real incident response exercise has been executed in staging against this process** | The policy is documented but unvalidated — first real incident will be the first end-to-end test of roles, comms, and templates |
| KL-IR-2 | **Single operator** — all three roles (IC, On-call, Comms) held by one person | No handoff, no backup on-call, no parallel investigation |
| KL-IR-3 | **Communication is sandbox-only** — Mailtrap does not deliver to a real inbox | Alerts may go unnoticed unless the operator checks Mailtrap or Grafana UI |
| KL-IR-4 | **Thresholds not baselined** against real staging traffic ([alerting-strategy.md KL-S-1](../specs/observability-foundation/mvp/alerting-strategy.md)) | False positives/negatives possible until Phase 10 tuning |
| KL-IR-5 | **`DatasourceNoData` silence expires 2026-09-08** | After expiry, no-traffic rules may page on NoData unless real traffic exists or silence is renewed ([alerting-strategy.md §7.3](../specs/observability-foundation/mvp/alerting-strategy.md)) |

---

## 10. Related documents

| Document | Use when |
| --- | --- |
| [alerting-philosophy.md](../architecture/alerting-philosophy.md) | Severity definitions (§13), escalation paths (§18), investigation workflow (§26) |
| [observability-playbook.md](observability-playbook.md) | Technical investigation for 14 incident scenarios; escalation (§16) and recovery (§17) checklists |
| [alerting-strategy.md](../specs/observability-foundation/mvp/alerting-strategy.md) | Contact points, routing, Mailtrap sandbox state, staging rollout |
| [infrastructure-collector-down.md](../runbooks/infrastructure-collector-down.md) | Collector export failure / Emergency alert |
| [application-http-error-rate.md](../runbooks/application-http-error-rate.md) | HTTP 5xx elevated / Critical alert |
| [application-http-high-latency.md](../runbooks/application-http-high-latency.md) | HTTP p95 high / Warning alert |
| [application-queue-failure-rate.md](../runbooks/application-queue-failure-rate.md) | Queue job failure rate / Warning alert |
| [application-scheduler-missed.md](../runbooks/application-scheduler-missed.md) | Scheduler missed executions / Warning alert |
| [application-push-failure.md](../runbooks/application-push-failure.md) | Push queue failure / Warning alert |
| [business-smart-home-failure.md](../runbooks/business-smart-home-failure.md) | Smart Home failure rate / Critical alert |
| [ADR-030](../decisions/ADR-030-observability-security-and-privacy.md) | No PII/secrets in incident notes, logs, or alert notifications |
