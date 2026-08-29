# Incident: Queue Workers failure rate — P9.5-3 incident response drill

**Incident ID:** INC-20260829-001
**Detected at:** 2026-08-29 23:33:57 UTC (rule entered Pending)
**Severity:** warning
**Environment:** staging
**Status:** resolved

> **This was a deliberate drill, not a real incident.** Purpose: exercise the process defined in [incident-response-policy.md](../incident-response-policy.md) end-to-end (acknowledge → investigate via runbook → recover → document) against a genuinely firing alert on the real observability host, closing P9.5-3. Real synthetic OTLP data was pushed through the real Collector to trigger a real alert; this is the same technique used to validate Phase 9's alerting end-to-end (see [alerting-strategy.md §5](../../specs/observability-foundation/mvp/alerting-strategy.md)).

## Alert(s) fired

- [x] Alert: `Application / Queue Workers — Failure Rate` (`ixora-alert-queue-failure-rate`)
- [x] Runbook used: [application-queue-failure-rate.md](../../runbooks/application-queue-failure-rate.md)

## Dashboards / queries used

- Dashboard: D-04 Queue Workers — `/d/ixora-queue`
- Investigation PromQL (per the runbook's "Validation Steps", breakdown by queue):
  ```
  sum(rate(ixora_queue_job_total{outcome="failed"}[5m])) by (queue)
  /
  sum(rate(ixora_queue_job_total[5m])) by (queue)
  ```
  Result: `queue="default"` at `0.9` (90% failure ratio) — confirmed the condition matched the alert.

## Timeline of actions

| Time (UTC) | Actor | Action |
| --- | --- | --- |
| 23:31 | On-call (drill operator) | Started synthetic breach injection — pushed `ixora.queue.job.total` via OTLP/HTTP to the real Collector, `outcome=failed` climbing ~9× faster than `outcome=success` |
| 23:33:57 | Grafana | `ixora-alert-queue-failure-rate` entered **Pending** (query result crossed the 5% threshold) |
| 23:38:40 | Alertmanager | Alert instance `startsAt` recorded, routed to `ixora-default` (warning severity, per the routing tree) |
| 23:38:59 | Grafana | Rule transitioned **Pending → Alerting** (`for: 5m` elapsed) |
| ~23:45 | On-call | Investigation: ran the PromQL above directly (no browser available in this session), confirmed 90% failure ratio on `queue=default` — matches the runbook's expected finding |
| 23:45:43 | On-call | No notification had arrived ~7 minutes after Alerting — manually tested the `ixora-default` contact point in isolation (`receivers/test` API) to rule out a broken receiver. Result: `status: ok`, delivered immediately. Contact point itself was never the problem. |
| 23:46:18 | Alertmanager → Mailtrap | **Real FIRING notification delivered** (Mailtrap message id `5673310207`) — ~7.5 minutes after the rule entered Alerting |
| ~23:46 | On-call | Recovery: pushed healthy synthetic data (`success` climbing hard, `failed` held flat) to bring the ratio back below 5% |
| 23:47:56 | Grafana | Rule returned to **Normal / inactive** |
| (not observed by end of session) | Alertmanager → Mailtrap | RESOLVED notification not yet captured ~10+ minutes after resolution — see Root cause |

## Root cause

**Of the drill condition:** synthetic, intentional — not a real failure.

**Of the notification delay (the actual finding worth keeping):** the real FIRING notification took ~7.5 minutes to reach Mailtrap, not the ~2 minutes `group_wait` would suggest for the `warning` route (`group_by: [category, environment]`, `group_wait: 30s`... — see note below). Working theory, not fully confirmed: the notification group `category=application, environment=staging` was already "warm" — the same group has been receiving a recurring `DatasourceNoData` alert (silenced by the active 14-day silence, but still evaluated and grouped) roughly every cycle. Once a group already exists in Alertmanager, a *new* alert joining it may only flush on the group's `group_interval` (15m) rather than restart `group_wait` for a fresh group. This was not conclusively proven from the Grafana logs available in this session (no notification-attempt log lines were found at `info` level for either the successful or the delayed send) — it is a plausible, unconfirmed explanation based on the observed timing, not a verified root cause.

## Resolved at

2026-08-29 23:47:56 UTC (Grafana rule state). Notification delivery timing is tracked separately above since it visibly diverged from the state transition.

## Impact summary

- **Duration:** ~14 minutes end-to-end (Pending at 23:33:57 → resolved at 23:47:56); a human would only have been notified for the last ~9 of those minutes (23:46:18 onward), given the delay above.
- **Users / requests / jobs affected:** none — synthetic data only (`job_name=IncidentDrillJob`), no real `back_vibes` queue jobs touched.
- **Business features affected:** none (drill).

## Evidence / links

- Grafana alert rule: `ixora-alert-queue-failure-rate`, folder "Ixora Alerting"
- Dashboard: `/d/ixora-queue`
- Mailtrap messages: `5673310207` (FIRING, 23:46:18Z), `5673309545` (isolation test of `ixora-default`, 23:45:44Z)
- No real `trace_id` or Loki log lines — the synthetic OTLP push bypasses `back_vibes` application code entirely, so there is nothing to correlate on the logs/traces side for this specific drill (a real incident driven by real traffic would have both; noted as a drill limitation, not a process gap)

## Follow-up

- [x] Postmortem completed (§6 of incident-response-policy.md) — see below (not strictly required for `warning` severity with no user impact, done anyway to validate the template itself)
- [x] Runbook checked — no inaccuracy found; [application-queue-failure-rate.md](../../runbooks/application-queue-failure-rate.md)'s steps matched exactly what was needed to investigate
- [ ] Alert threshold tuned — not applicable; this was an intentional breach, not organic traffic behaving unexpectedly
- [ ] **New finding to investigate:** notification delivery delay when a `warning`-severity alert joins an already-active notification group shared with a silenced, recurring `DatasourceNoData` alert. Tracked as KL-IR-6 in [incident-response-policy.md](../incident-response-policy.md).

---

## Postmortem (§6.1 checklist, applied to this drill)

**Root cause and impact**
- Root cause: intentional synthetic drill (queue failure condition); the notable *unintentional* finding was the ~7.5 min notification delay (see Root cause above, unconfirmed hypothesis).
- Impact: none (drill, no real traffic affected).
- Scope: 1 synthetic job type (`IncidentDrillJob`) on `queue=default`.

**Alert and runbook quality**
- Right alert fired: yes — `ixora-alert-queue-failure-rate` fired exactly as designed once the >5% threshold held for `for: 5m`.
- Threshold / `for` duration: appropriate — matched the documented Level 1 threshold from `alerting-philosophy.md` §9/§13.
- Runbook accuracy: confirmed accurate and sufficient — the "Validation Steps" PromQL in [application-queue-failure-rate.md](../../runbooks/application-queue-failure-rate.md) correctly surfaced the breakdown by queue on the first try.
- Observability gap: none masked this drill (Collector, Prometheus, Grafana all healthy throughout).

**Recovery verification**
- Dashboard-equivalent query (§ above) confirmed the ratio dropped back below threshold after the recovery push.
- No real trace/log correlation possible for this synthetic drill (see Evidence section) — not a gap in the process, a property of the drill technique.
- Root cause documented in this record.

**Prevention**
- No code/config change needed for the (fake) failure itself.
- Real action item: investigate and confirm (or rule out) the notification-grouping delay hypothesis above with a second drill or by reading Alertmanager's internal group state directly, once it matters for a real Critical/Emergency alert where a 7+ minute delay would be far more consequential than for `warning`.

**Hygiene**
- No secrets or PII appear anywhere in this record — only synthetic label values, alert/rule names, and Mailtrap message IDs (not sensitive). Confirmed per [ADR-030](../../decisions/ADR-030-observability-security-and-privacy.md).
