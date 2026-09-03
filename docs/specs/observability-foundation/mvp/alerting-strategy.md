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
| Real contact points (email) | `collector/grafana/provisioning/alerting/contact-points.yaml` |
| Real notification policy routing tree | `collector/grafana/provisioning/alerting/notification-policies.yaml` |
| Weekly maintenance mute timing | `collector/grafana/provisioning/alerting/mute-timings.yaml` |
| Notification message template wired to email | `collector/grafana/provisioning/alerting/templates.yaml` |
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

**Operator action required before this is live:** `collector/.env` on the observability host needs real values for `GF_SMTP_ENABLED=true`, `GF_SMTP_HOST`, `GF_SMTP_USER`, `GF_SMTP_PASSWORD`, and `ALERT_EMAIL_ADDRESS`. Until then, `docker-compose.yml`'s `ALERT_EMAIL_ADDRESS:-alerts-not-configured@ixora-app.app}` default keeps `contact-points.yaml` provisioning clean and Grafana up — this default was added *because* Phase 9 testing found the opposite is not true: an **empty** `ALERT_EMAIL_ADDRESS` makes Grafana reject the email integration at provisioning time and **crash-loop the entire container**, not just fail to send (see §6, KL-S-4). With the placeholder default, alerts still show as "Firing" in the Grafana UI even with `GF_SMTP_ENABLED=false` — satisfying the Level 1 minimum — but no email is delivered until the operator sets the real values.

### 2.1 Correction: where these files actually have to live

`alerting-foundation.md` §3.2 states contact points/policies/mute timings/templates are "provisioned through their own dedicated directories" (`contact-points/`, `notification-policies/`, `mute-timings/`, `templates/`). **This is incorrect** — verified empirically in Phase 9 local testing (spin up `collector/docker-compose.yml`'s `grafana` service and inspect `docker logs`): Grafana's file-provisioning only scans the single directory configured as `[paths] provisioning` → `alerting/` (here, `collector/grafana/provisioning/alerting/`). A file placed in the sibling directories is never read — no error, no log line, just silently ignored. The resource type provisioned from a file in `alerting/` is determined by its top-level YAML key (`groups`, `contactPoints`, `policies`, `muteTimes`, or `templates`), not by the directory it's in.

All four files were moved into `collector/grafana/provisioning/alerting/` as part of this phase (`contact-points.yaml`, `notification-policies.yaml`, `mute-timings.yaml`, `templates.yaml`, alongside the alert rule group files). The original sibling directories are kept, empty except for a `README.md` pointing to the real location, so the folder structure `alerting-foundation.md` documented still resolves without dead links.

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

### 3.1 Correction: metric/label names that don't match the foundation's planning table

`alerting-foundation.md` §2.2 and §13's planning table were written before this phase cross-checked them against the actual `back_vibes` instrumentation (`app/Telemetry/**`). Three of the eight planned expressions used names that don't exist on the wire; they are fixed in the deployed rules, not in the frozen foundation doc:

| Foundation doc said | Actually emitted (verified against `back_vibes/app/Telemetry`) | Rule fixed |
| --- | --- | --- |
| `ixora_http_server_duration{http_status_code=~"5.."}` | No `http_status_code` label exists on either HTTP metric. Use `outcome="server_error"` (`HttpOutcome::fromStatusCode()`) on `ixora_http_server_request_total` | `ixora-alert-http-error-rate` |
| `ixora_scheduler_execution_total{outcome="success"}` | Metric is `ixora.scheduler.event.total` → `ixora_scheduler_event_total` (`SchedulerExecutionTelemetry::METRIC_EVENT_TOTAL`); `execution_total` does not exist | `ixora-alert-scheduler-missed` |
| `ixora_telemetry_export_failed_total` (Collector Down) | Documented in `telemetry-availability-policy.md` §3 as an **optional** local SDK counter — never actually instrumented in `back_vibes`. The real, populated signal for Collector export health is the Phase 8.9 recording rule `ixora:collector:export_failure_rate:5m` (REC-017, `collector/prometheus/rules/recording/infrastructure.rules.yml`), built from `otelcol_exporter_send_failed_*` — a genuine Collector self-metric | `ixora-alert-collector-down` (now thresholded at `> 0.9` against the recording rule, `for: 2m`, to mean "effectively down" as distinct from the existing gradual SLO burn-rate alerts in `collector/prometheus/rules/alerting/slo.alerts.yml`) |

The four rules not listed above (`ixora-alert-http-high-latency`, `ixora-alert-queue-failure-rate`, `ixora-alert-push-failure`, `ixora-alert-smart-home-failure`) were checked against the same source and match: `queue`, `outcome` (`"failed"` for queue jobs, `"failure"` for Smart Home actions — these are two different enums, not a typo), and `provider` are real metric labels with the exact string values used.

### 3.2 Correction: the `environment` label templated to nothing

Every rule originally carried `environment: "{{ $labels.environment }}"`, copied from `alerting-foundation.md` §12's label reference. This never resolves: every rule's PromQL wraps its query in `sum(...)` (or, for `ixora-alert-collector-down`, references a recording rule with no `by (...)` clause at all), which drops every label from the result — including `environment`, even though the underlying metric does carry one (e.g. `HttpRequestTelemetry::record()` sets `'environment' => $this->environment` on every sample). With no `environment` label in the query result, the template has nothing to substitute and silently renders empty. Confirmed live: a synthetic `DatasourceNoData` alert Grafana generated for these rules during local testing showed `"environment": "{{ .environment }}"` verbatim in its label set (Grafana itself normalizes the `$labels.` prefix out of *label* templates, but the underlying resolution problem is the same — no data, nothing to substitute).

Fixed by making `environment` a **static** label (`environment: staging`) on all 7 rules, consistent with every other rule label (`severity`, `service`, `team`, `category`, `dashboard_uid`, `runbook`) already being static, and consistent with this being a single-environment (staging-only) Grafana/Prometheus deployment — one Collector stack per environment, per `ixora-infra`'s OpenTofu setup, so there is exactly one correct value per deployment. This is the same reasoning already applied everywhere else on these rules; it just hadn't been applied to `environment` in the copied template.

### 3.3 Correction: `dashboard`/`runbook` annotations templated a static label — confirmed with a genuine firing alert, not a synthetic test

Every rule's `dashboard`/`runbook` annotations were `"/d/{{ $labels.dashboard_uid }}"` / `"{{ $labels.runbook }}"`, copied from `alerting-foundation.md` §12. These never resolve either, for the same root cause as §3.2 but at a different pipeline stage: Grafana evaluates **annotation** templates against the labels present in the query **result** at evaluation time — not the rule's own static labels, which are only merged onto the alert instance afterward, for matching/routing/notification purposes. Since every Phase 9 rule's query is a label-stripping `sum(...)` (or a label-less recording rule reference), the query-result label set is always empty, so `$labels.dashboard_uid` and `$labels.runbook` inside an annotation always render `[no value]` — even on a real, genuinely firing alert with real data, not just the `DatasourceNoData` case in §5.

This was proven, not assumed. Pushing real OTLP data (§5) took `ixora-alert-smart-home-failure` from `NoData` → `Pending` (06:29:00) → **`Alerting`** (06:34:00, exactly the rule's `for: 5m` later) against the *pre-fix* rule definition, and the resulting Alertmanager notification — a genuine `[FIRING:1] ... Business / Smart Home — Elevated Failure Rate ...` email, not a `DatasourceNoData` test — was captured in the operator's Mailtrap sandbox (message id `5663452958`, sent `06:34:37Z`, ~30s after the real transition) with the body reading `*Dashboard:* /d/[no value]` and `*Runbook:* [no value]`, confirming the bug reaches the actual notification a human would receive, not just an API field.

Fixed the same way as `alerting-foundation.md`'s own `summary`/`business_impact`/`expected_action` annotations already were written — as **literal strings** (e.g. `dashboard: "/d/ixora-smart-home"`, `runbook: "/runbooks/business-smart-home-failure.md"`), since the value is known at rule-authoring time and never varies per query result. Re-verified after the fix: `GET /api/alertmanager/grafana/api/v2/alerts` on the *same still-firing* alert instance showed `updatedAt` advancing past the fix's deploy time with `dashboard: /d/ixora-smart-home` and `runbook: /runbooks/business-smart-home-failure.md` correctly resolved (the alert's `repeat_interval: 1h` meant a second confirming email wasn't captured in the same session, but Grafana recomputes annotations every evaluation, and the API is the same data source a Slack/email notification would read from). Guarded by `validate.sh` check 104.

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

Done locally against `collector/docker-compose.yml`'s `prometheus`, `loki`, `tempo`, `grafana` services (empty local data — no `back_vibes` traffic — so this validates provisioning and PromQL correctness, not real thresholds):

- [x] Grafana starts cleanly with all provisioning files under `alerting/` (`docker logs ixora-grafana` shows `"finished to provision alerting"`, no error lines).
- [x] All 7 alert rules appear via `GET /api/v1/provisioning/alert-rules`, in the "Ixora Alerting" folder, with the corrected `expr` values from §3.1.
- [x] `GET /api/prometheus/grafana/api/v1/rules` shows `health: ok` (2 rules briefly `nodata` — expected with zero real HTTP/push traffic in this local stack, not a query error) and an empty `lastError` on all 7 rules — confirms every PromQL expression is syntactically valid and executes against real Prometheus.
- [x] Found and fixed: contact points/policies/mute-timings/templates left in their originally-documented sibling directories are silently never loaded (§2.1) — moved into `alerting/`.
- [x] Found and fixed: an empty `ALERT_EMAIL_ADDRESS` doesn't degrade gracefully — Grafana's alerting provisioning rejects it and the container crash-loops. Reproduced directly (stopped/removed the crash-looping test container), fixed with a non-empty `docker-compose.yml` default (§2).
- [x] Found and fixed: `templates.yaml`'s original `ixora-alert-body` template piped `.Alerts.Firing | first` (a Sprig-style function Grafana's notification template engine does not register) into `formatDate`. This didn't just fail to render — it made the *entire templates.yaml file* fail provisioning with a content-free error (`text templates: [alerting.notifications.templates.invalidFormat] Invalid format of the submitted template`, no line number), which crash-looped Grafana the same way the empty-email case did, because `contact-points.yaml`'s `ixora-email-critical` receiver's `message` field references `ixora-alert-body`. Root-caused by bisecting the template content line by line against a live container (see the comment left in `templates.yaml`); fixed by dropping the "Firing since" line — Grafana's own email notification already carries a firing timestamp.
- [x] Full clean `docker compose down && docker compose up -d prometheus loki tempo grafana` (no stale container/volume state) confirmed via the provisioning API: all 7 alert rules, both real contact points (`ixora-default`, `ixora-email-critical`, both correctly falling back to the `alerts-not-configured@...` placeholder with no `ALERT_EMAIL_ADDRESS` set locally), the full 3-branch severity routing tree, and `weekly-maintenance-window` all present with `"provenance": "file"`.
- [x] Found and fixed: the `environment` label was templated (`{{ $labels.environment }}`) against queries that strip all labels via `sum(...)`, so it always rendered empty (§3.2). Fixed as a static `environment: staging` label on all 7 rules.
- [x] **SMTP delivery confirmed against the operator's real Mailtrap sandbox** (`sandbox.smtp.mailtrap.io:2525`, credentials in the local, gitignored `collector/.env` — never committed). Set `GF_SMTP_ENABLED=true` plus the Mailtrap host/user/password, restarted Grafana (started clean, no crash-loop), then called Grafana's own contact-point test-notification endpoint (`POST /api/alertmanager/grafana/config/api/v1/receivers/test`) against `ixora-email-critical` with a synthetic `Phase9-SMTP-Test` alert. Response: HTTP 200, `"status":"ok"`, `notified_at` timestamp present, no SMTP errors in `docker logs ixora-grafana` — Grafana successfully completed the SMTP handshake and handed the message to Mailtrap. (Reading Mailtrap's own captured-inbox to visually confirm the message itself would need a separate Mailtrap API token, which wasn't provided — the SMTP-level confirmation above is what's available from this environment.)
- [x] **Routing-tree behavior partially confirmed with real Grafana-internal traffic**: with zero real `back_vibes` metrics in the local Prometheus, Grafana's own `DatasourceNoData` synthetic alerts fired for rules querying empty series and correctly routed through the severity-based tree — critical rules (e.g. `ixora-alert-smart-home-failure`) to `ixora-email-critical`, warning rules (e.g. `ixora-alert-http-high-latency`) to `ixora-default` — confirming the routing logic itself, independent of real threshold data.
- [x] **Rule state confirmed reaching genuine `Alerting` from real data, end-to-end through the real Collector pipeline.** The earlier attempt (Prometheus remote-write needs protobuf+snappy; no Python libs available; Collector's OTLP receiver looked gRPC-only from the config comments) turned out to have a simpler path: `otlp/backend` in `collector/config.yaml` actually configures *both* `grpc` (4317) and `http` (4318) protocols, and OTLP/HTTP accepts plain JSON — no protobuf tooling needed. Wrote a small script (`push_otlp_sustained.py`, not committed — a throwaway test client) that `POST`s an OTLP/HTTP JSON payload to `http://localhost:4318/v1/metrics` with `Authorization: Bearer <OTEL_INGEST_API_KEY_BACKEND>`, shaped exactly like `SmartHomeActionTelemetry`'s real `ixora.smart_home.action.total` counter (`outcome`/`provider` attributes, cumulative temporality), with the failure count climbing every 20s to hold a >20% failure ratio. Confirmed in Prometheus (`ixora_smart_home_action_total{outcome="failure",...}` present with real, growing values) and then in Grafana: `ixora-alert-smart-home-failure` went `nodata` → `Pending` (`activeAt: 06:29:00Z`) → **`Alerting`** (`06:34:00Z` — exactly `for: 5m` later) — a real state machine transition driven by real query results, not a synthetic test.
- [x] **Real (non-test) email delivery confirmed via the Mailtrap API**, using the account API token the operator provided separately from the SMTP credentials. `GET /api/accounts/{id}/inboxes/{id}/messages` on the sandbox inbox listed a genuine `[FIRING:1] staging back_vibes-worker (Business / Smart Home — Elevated Failure Rate ...)` message (id `5663452958`), `sent_at: 2026-08-25T06:34:37Z` — about 30 seconds after the rule's real `06:34:00Z` transition to `Alerting` — to `almeidaelucas500@gmail.com`, rendered through the `ixora-alert-body` template (§3.3 covers the `[no value]` bug this same email exposed and how it was fixed). This is strictly stronger evidence than the earlier `receivers/test` API call (§2): it's the actual Alertmanager pipeline notifying on a real alert state change, not a manually constructed test payload.
- [x] Each of the 7 runbook files exists at the path its rule's `runbook` label/annotation points to.
- [x] **`validate.sh` extended** with checks 99–104 (real contact point present; contact-points/notification-policies/mute-timings/templates present under `alerting/` and absent from the old sibling directories; all 7 alert rule files present; all 7 runbooks present; no rule references the three now-known-wrong metric/label names from §3.1; no annotation templates `$labels.dashboard_uid`/`$labels.runbook`, §3.3). Checks 65–67, which predated this phase and pointed at the old (wrong) sibling-directory paths, were corrected to point at `alerting/` instead of left permanently failing. Full run: **104/104 checks pass** against the local stack.

---

## 6. Known limitations (Phase 9)

| ID | Limitation | Impact | Resolution |
| --- | --- | --- | --- |
| KL-S-1 | Thresholds are not yet baselined against real staging traffic | Possible false positives/negatives until tuned | Phase 10 — Level 2 tuning, per alerting-philosophy.md §15 |
| KL-S-2 | No inhibition rules — a Collector outage can still page for every downstream alert | Alert fatigue risk during a Collector incident | Manual discipline for now: alerting-philosophy.md §26 step 3 already directs "check D-07 first"; automate in Phase 10 |
| KL-S-3 | Single email receiver for all critical/emergency alerts (no per-team routing) | Fine for single-operator staging; will not scale to a real team | Add Slack/PagerDuty receivers when a team exists |
| ~~KL-S-4~~ | ~~Email delivery unverified~~ | Resolved and **deployed to the real staging host** (§7) — `GF_SMTP_ENABLED=true` + Mailtrap credentials are live in `/opt/ixora-observability/collector/.env` on `137.184.163.187`, verified via a real test notification captured in the Mailtrap API. Mailtrap remains a sandbox, though: mail never reaches a real inbox, only the operator's Mailtrap dashboard | A real SMTP relay (not Mailtrap) is still the eventual target for this to page a human through their actual inbox — swap `GF_SMTP_HOST`/`GF_SMTP_USER`/`GF_SMTP_PASSWORD`/`ALERT_EMAIL_ADDRESS` in the host's `.env` and restart `grafana` when ready |
| KL-S-5 | `mute-timings.yaml`'s `weekly-maintenance-window` is defined but not yet attached to any route | No suppression happens automatically during the window | Attach via Grafana UI (documented in the file's header) or extend `notification-policies.yaml` schema support |
| KL-S-6 | `alerting-foundation.md` §3.2 documents contact points/policies/mute-timings/templates as living in their own sibling directories under `provisioning/` | Following that doc literally produces files Grafana never reads, with no error — a silent no-op that looks correct until an alert fails to notify anyone | Resolved — corrected in this document (§2.1) and guarded by `validate.sh` check 99; the frozen Phase 8.8 doc is left as-is per this document's stated policy, with a pointer added at the top of its §3.2 |
| KL-S-7 | Grafana's notification-template provisioning validator rejects unsupported template functions (e.g. `first`) with a single generic, line-number-free error for the whole file, and that failure crash-loops the container if any contact point's `message` references the broken template | A future template edit that uses an unsupported function is easy to ship and hard to diagnose from logs alone | Documented directly in `templates.yaml`'s header; any future template change must be smoke-tested with a real `docker compose up grafana` cycle, not just YAML-lint, before merging |
| ~~KL-S-8~~ | ~~No rule observed transitioning to genuine `Alerting` from real query results~~ | Resolved — §5 pushed real OTLP data through the actual Collector pipeline and observed `ixora-alert-smart-home-failure` transition `nodata` → `Pending` → `Alerting` on schedule, with the resulting real Alertmanager email captured via the Mailtrap API. Only one of the 7 rules was exercised this way (the other 6 share the same reduce→threshold pattern and were already confirmed PromQL-valid in the earlier local pass, but not individually pushed through with real breaching data) | Exercising the remaining 6 rules the same way is straightforward with the same script (swap the metric/attributes) but wasn't repeated for all 7 given the marginal value once the pattern was proven once |
| KL-S-9 | The synthetic test client used to push real OTLP data (`push_otlp_sustained.py`) is a throwaway script, not committed anywhere | No reusable tool for a future "prove this alert really fires" check — the next person has to re-derive the OTLP/HTTP JSON shape | Low priority — the shape is fully documented in this section (§5) if it's needed again; promote to a committed script under `collector/scripts/` only if this becomes a repeated need |

---

## 7. Real staging rollout (2026-08-25)

Everything above was validated locally first (§5). This section records deploying the same artifacts to the actual observability host, `137.184.163.187` (`ixora-observability-staging`, `grafana-staging.ixora-app.app`), and what happened on contact with a real, long-running deployment.

### 7.1 Deploy

`./scripts/deploy-observability.sh --host 137.184.163.187 --user root` — rsyncs `collector/` and `scripts/` (never `.env`), then runs the same preflight/validate/health-check sequence locally over SSH. Result: 30/30 checks passed, all 5 containers healthy, `grafana` recreated cleanly (no crash-loop — confirms the fixes in §2 hold on a real host, not just the local test stack).

**Two gaps found on this first real deploy, both fixed:**

- **Stale Phase 8.8 placeholder files.** rsync has no `--delete` flag in this script, so the old `contact-points.yaml`/`policies.yaml`/`mute-timings.yaml`/`templates.yaml` in the sibling directories (superseded by §2.1's move into `alerting/`) were still sitting on the host from the original Phase 8.8.5 deploy. Harmless (Grafana never read them either way) but confusing, and `validate.sh` check 99 correctly flagged it. Removed by hand over SSH; the repo itself only ever had the `README.md` pointers there, so nothing to fix in git.
- **`docs/runbooks/` was never deployed at all.** `deploy-observability.sh` only ever rsynced `collector/` and `scripts/` — `validate.sh` checks 96/102 and every alert rule's `runbook` annotation expect `${DEPLOY_PATH}/docs/runbooks/`, which simply didn't exist on the host. Fixed properly in the script (not just worked around on the host) — see `feature/observability-deploy-sync-runbooks`, merged and re-deployed; confirmed the second deploy synced runbooks automatically.

`validate.sh` on the real host: **checks 99–104 (Phase 9's own) all pass.** The remaining ~20 failures (checks 63–90) are pre-existing and unrelated to Phase 9 — they expect the full `docs/`/`opentofu/` tree on the host, which this deploy script deliberately never syncs (scope was always just `collector/` + `scripts/`, now plus `docs/runbooks/`). Not addressed here — out of scope for this phase.

### 7.2 SMTP activated on the real host

Same Mailtrap sandbox credentials used for local testing (§5), appended to the real host's `collector/.env` (chmod 600, `.env` untouched by the deploy script itself — added over SSH separately), `grafana` restarted. Verified with the same test-notification API call as §5, this time against `137.184.163.187` directly: HTTP 200, `status: ok`, and the Mailtrap API confirmed the message actually arrived (id `5663494648`, `07:00:46Z`). See KL-S-4.

### 7.3 Real traffic reality check — and a temporary silence

All 7 rules came up on the real host in `health: nodata` — real staging currently has no traffic hitting `ixora_smart_home_action_total`, `ixora_http_server_request_total`, etc. in the windows these rules query. Left alone, each rule's `DatasourceNoData` synthetic alert would page on its severity's `repeat_interval` (1h for critical/emergency, 4h for warning) indefinitely, which is pure noise, not a real Level 1 signal (alerting-philosophy.md §16 alert fatigue).

Created a scoped Grafana silence (`POST /api/alertmanager/grafana/api/v2/silences`) matching `alertname=DatasourceNoData` AND `grafana_folder=Ixora Alerting` — this suppresses only the no-traffic noise; a **genuine** firing alert (which carries the rule's own title as `alertname`, not `DatasourceNoData`) is unaffected and would still page normally. Confirmed all 7 current `DatasourceNoData` instances show `status.state: suppressed` with this silence's ID.

- **Silence ID:** `61a92621-c500-4119-b4b0-cf07e6255a7a`
- **Scope:** `alertname=DatasourceNoData`, `grafana_folder=Ixora Alerting` (all 7 Phase 9 rules, NoData state only)
- **Window:** 2026-08-25 → 2026-09-08 (14 days)
- **Before it expires:** either real staging traffic exists by then and the rules naturally leave `NoData`, or the silence needs a deliberate decision — extend it, or accept the NoData paging as a signal that the corresponding feature genuinely isn't exercised on staging and the rule/threshold needs rethinking (not something to silence forever without revisiting, per the retirement-strategy guidance in alerting-philosophy.md §21).

### 7.4 What's still not done

- Real SMTP relay (not Mailtrap) for staging to page an actual human inbox.
- Threshold baselining against real traffic (KL-S-1) — moot until traffic exists to baseline against.
- The remaining ~6 rules' real-data end-to-end proof (KL-S-8) — only Smart Home was exercised this way, locally, before this deploy.

---

## 8. Related documents

| Document | Relationship |
| --- | --- |
| [alerting-philosophy.md](../../../architecture/alerting-philosophy.md) | Philosophy this strategy implements |
| [alerting-foundation.md](alerting-foundation.md) | Structure/scaffold this strategy fills in |
| [dashboard-conventions.md](dashboard-conventions.md) | Dashboard UIDs referenced by every alert rule |
| [docs/runbooks/](../../../runbooks/) | Per-alert operational runbooks |
