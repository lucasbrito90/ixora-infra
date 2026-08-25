# Alerting Strategy — Phase 9

**Status:** In progress
**Type:** Implementation Specification
**Repo:** `ixora-infra`
**Feature ID:** `observability-foundation/mvp`
**Established:** Phase 9
**ADRs:** [ADR-028](../../../decisions/ADR-028-observability-platform.md) · [ADR-030](../../../decisions/ADR-030-observability-security-and-privacy.md)
**Philosophy:** [alerting-philosophy.md](../../../architecture/alerting-philosophy.md)
**Prerequisite:** [alerting-foundation.md](alerting-foundation.md) (Phase 8.8 — structure, categories, templates)

> **Numbering note:** this repo's `plan.md`/`tasks.md` used "Phase 9" historically for Grafana dashboard construction (now complete, folded into Phases 8.0–8.7). The current cross-repo roadmap (`docs/roadmap/ixora-roadmap-2026-08-16.md`) reassigns Phase 9 to **Alerting Strategy** — the same renumbering conflict already documented for the old "Phase 9.5". This document uses the roadmap's current numbering.

> **Rule:** This document records what Phase 9 actually deployed — real contact points, real routing, and the first tier of alert rules — against the structure `alerting-foundation.md` specified. Where a decision in the foundation's Phase 9 scaffolding changed on contact with real deployment (e.g. email instead of Slack), that change is recorded here, not by editing the frozen Phase 8.8 document.

---

## 1. Scope of this phase

Phase 9 moves the platform from **Level 0 → Level 1** of the alert maturity model (alerting-philosophy.md §15): no alerts → basic threshold alerts on Golden Signals for the services that already have dashboards and metrics.

### 1.1 Delivered

| Deliverable | Location |
| --- | --- |
| Real contact points (email) | `collector/grafana/provisioning/contact-points/contact-points.yaml` |
| Real notification policy routing tree | `collector/grafana/provisioning/notification-policies/policies.yaml` |
| Weekly maintenance mute timing | `collector/grafana/provisioning/mute-timings/mute-timings.yaml` |
| Notification message template wired to email | `collector/grafana/provisioning/templates/templates.yaml` |
| SMTP wiring (Grafana → email) | `collector/docker-compose.yml`, `collector/.env.example` |
| 7 threshold alert rules (Level 1) | `collector/grafana/provisioning/alerting/*.yaml` |
| 7 runbooks (one per alert) | `docs/runbooks/<slug>.md` |
| This strategy document | This file |

### 1.2 Explicitly deferred (not in this phase)

| Item | Reason | Target |
| --- | --- | --- |
| Slack contact points | No team channel exists yet — a personal DM webhook is not a real "team" receiver; scaffolding kept commented in `contact-points.yaml` | When a team channel exists |
| VM disk saturation alert (`ixora-alert-vm-disk`) | Node Exporter not deployed (KL-A-2, alerting-foundation.md §16) | Alongside Node Exporter deployment |
| Security alerts (§4.9 of alerting-foundation.md) | Explicitly out of scope through Phase 9 in the foundation spec | Future phase |
| Alertmanager-native inhibition rules (Collector-down suppressing downstream) | Not expressible in Grafana OSS's provisioning `policies.yaml` schema (route matchers only, no `inhibit_rules` block) | Phase 10 tuning — evaluate Grafana's native "alert rule dependency" feature or manual on-call discipline (check D-07 first, per alerting-philosophy.md §26 investigation workflow) |
| Business/Push Notifications alerts (§4.7) | Blocked on Phase 7B.5 (`ixora_push_delivery_total`) per KL-A-1 | After Phase 7B.5 ships |
| Automated escalation (paging beyond email) | Single-operator staging environment; no on-call rotation tool integrated yet | When a real on-call tool (PagerDuty/Grafana OnCall) is adopted |

---

## 2. Contact point decision: email over Slack

`alerting-foundation.md` §5.1 planned Slack as the primary critical/emergency channel. On implementation, the operator (single-person staging environment, no team Slack workspace dedicated to this yet) chose **email** as the real Phase 9 receiver:

- `ixora-default` — Grafana UI + email fallback, routed to `info`/`warning`.
- `ixora-email-critical` — real email receiver via Grafana SMTP, routed to `critical`/`emergency`.

Both currently point at the same address (`ALERT_EMAIL_ADDRESS` env var, injected via `collector/.env`, never committed — ADR-030). They are kept as **separate contact points** so that swapping `ixora-email-critical` for a Slack/PagerDuty receiver later is a one-line change in `policies.yaml`'s route, not a redesign.

**Operator action required before this is live:** `collector/.env` on the observability host needs real values for `GF_SMTP_ENABLED=true`, `GF_SMTP_HOST`, `GF_SMTP_USER`, `GF_SMTP_PASSWORD`, and `ALERT_EMAIL_ADDRESS`. Until then, `contact-points.yaml` provisions cleanly but email delivery silently no-ops (Grafana logs an SMTP error internally; alerts still show as "Firing" in the Grafana UI, satisfying the Level 1 minimum even without email — but the email leg needs verification before this is considered fully operational).

---

## 3. Alert rule inventory (deployed)

All 7 rules below implement the Level 1 target from `alerting-foundation.md` §13, using the exact metric names from that document's §2.2 inventory and the label/annotation contract from `alerting-philosophy.md` §23–24.

| Rule UID | Title | Severity | `for` | File |
| --- | --- | --- | --- | --- |
| `ixora-alert-collector-down` | Infrastructure / Collector — Collector Down | emergency | 2m | `alerting/infrastructure-collector.yaml` |
| `ixora-alert-http-error-rate` | Application / HTTP API — Elevated Error Rate | critical | 5m | `alerting/application-http.yaml` |
| `ixora-alert-http-high-latency` | Application / HTTP API — High Latency | warning | 5m | `alerting/application-http.yaml` |
| `ixora-alert-queue-failure-rate` | Application / Queue Workers — Failure Rate | warning | 5m | `alerting/application-queue.yaml` |
| `ixora-alert-scheduler-missed` | Application / Scheduler — Missed Executions | warning | 10m | `alerting/application-scheduler.yaml` |
| `ixora-alert-push-failure` | Application / Push Queue — Delivery Failure | warning | 5m | `alerting/application-push.yaml` |
| `ixora-alert-smart-home-failure` | Business / Smart Home — Elevated Failure Rate | critical | 5m | `alerting/business-smart-home.yaml` |

Each rule follows the reduce→threshold pattern from `alerting-foundation.md` §3.3 (range query → `last` reduction → threshold comparison), carries all required labels (`environment`, `severity`, `service`, `team`, `category`, `dashboard_uid`, `runbook`) and annotations (`summary`, `description`, `dashboard`, `runbook`, `business_impact`, `expected_action`), and references a runbook under `docs/runbooks/`.

**Thresholds** are taken directly from the worked examples already documented in `alerting-philosophy.md` §13.2–13.3 and §9 (HTTP 5xx > 1%, HTTP p95 > 2s, queue failure > 5%, smart home failure > 20%, push queue failure > 10%) — they are **not yet baselined against real staging traffic** (alerting-philosophy.md §17.1 "threshold based on observed baseline, not guessed" is not fully met). This is expected for a first deployment on a low-traffic staging environment; see §5 below.

---

## 4. Routing tree (deployed)

```
Root policy (ixora-default — Grafana UI + email)
├── severity =~ "critical|emergency" → ixora-email-critical
│     group_by: [service, environment]
│     group_wait: 30s / group_interval: 5m / repeat_interval: 1h
├── severity = "warning" → ixora-default
│     group_by: [category, environment]
│     group_wait: 2m / group_interval: 15m / repeat_interval: 4h
└── severity = "info" → ixora-default
      group_by: [category]
      group_wait: 5m / group_interval: 15m / repeat_interval: 24h
```

No `info`-severity rules are deployed yet in this phase — the `info` route exists so future rules (e.g. disk usage > 50%, per alerting-philosophy.md §13.1) need no policy change to land correctly.

---

## 5. Validation plan

Before this phase is marked complete:

- [ ] `docker compose -f collector/docker-compose.yml up -d grafana` restarts cleanly with the new provisioning files (no YAML/schema errors in `docker logs ixora-grafana`).
- [ ] All 7 alert rules appear in Grafana → Alerting → Alert rules, in the "Ixora Alerting" folder, with state `Normal` (not `Error`/`NoData` at rest) on staging's live Prometheus data.
- [ ] `ixora-default` and `ixora-email-critical` both appear under Contact points with no provisioning errors.
- [ ] SMTP is enabled with real credentials and a manual test alert (temporarily lower a threshold, e.g. HTTP p95 > 1ms) confirms an email is actually received.
- [ ] Each of the 7 runbook links resolves and matches its rule's `runbook` label/annotation.
- [ ] `validate.sh` is extended with checks for: real (non-placeholder) contact point present, non-empty `alerting/` directory (superseding check 58's ".gitkeep only" assumption), 7 alert rule files present, 7 runbook files present.

---

## 6. Known limitations (Phase 9)

| ID | Limitation | Impact | Resolution |
| --- | --- | --- | --- |
| KL-S-1 | Thresholds are not yet baselined against real staging traffic | Possible false positives/negatives until tuned | Phase 10 — Level 2 tuning, per alerting-philosophy.md §15 |
| KL-S-2 | No inhibition rules — a Collector outage can still page for every downstream alert | Alert fatigue risk during a Collector incident | Manual discipline for now: alerting-philosophy.md §26 step 3 already directs "check D-07 first"; automate in Phase 10 |
| KL-S-3 | Single email receiver for all critical/emergency alerts (no per-team routing) | Fine for single-operator staging; will not scale to a real team | Add Slack/PagerDuty receivers when a team exists |
| KL-S-4 | Email delivery unverified until SMTP credentials are set on the host | Alerts fire correctly in Grafana UI but the "page a human" contract (alerting-philosophy.md §1.1) is unproven | Operator must complete §2's manual step and run the §5 validation test |
| KL-S-5 | `mute-timings.yaml`'s `weekly-maintenance-window` is defined but not yet attached to any route | No suppression happens automatically during the window | Attach via Grafana UI (documented in the file's header) or extend `policies.yaml` schema support |

---

## 7. Related documents

| Document | Relationship |
| --- | --- |
| [alerting-philosophy.md](../../../architecture/alerting-philosophy.md) | Philosophy this strategy implements |
| [alerting-foundation.md](alerting-foundation.md) | Structure/scaffold this strategy fills in |
| [dashboard-conventions.md](dashboard-conventions.md) | Dashboard UIDs referenced by every alert rule |
| [docs/runbooks/](../../../runbooks/) | Per-alert operational runbooks |
