# SLO & Error Budget Runbook

**Phase:** 8.9  
**Dashboard:** [D-08 SLO & Error Budget](/d/ixora-slo) (Grafana uid: `ixora-slo`)  
**Alerts:** `collector/prometheus/rules/alerting/slo.alerts.yml`  
**Recording rules:** `collector/prometheus/rules/recording/`

---

## Plain-language summary (for non-SRE engineers)

An **SLO** (Service Level Objective) is a reliability target we choose — for example, “99.5% of API requests should succeed over 30 days.”

An **SLI** (Service Level Indicator) is how we measure that target from metrics — for example, successful requests divided by total eligible requests.

The **error budget** is how much failure we can afford before missing the target. For a 99.5% SLO, we allow 0.5% bad events in the window.

**Burn rate** tells us how fast we are spending that budget. A burn rate of 2 means we are failing twice as fast as the SLO allows — at that pace the budget would run out in half the window.

**SLO compliance** means the SLI is at or above the target. **Budget exhausted** means we have used all allowed bad events (remaining budget ≤ 0).

---

## Implemented SLOs (staging initial targets)

| SLO | Service | SLI | Target | Window | Allowed error | Exclusions |
| --- | --- | --- | --- | --- | --- | --- |
| HTTP availability | `back_vibes-api` | non-5xx / eligible requests | 99.5% | 30d | 0.5% | `/up` health route |
| HTTP latency | `back_vibes-api` | requests ≤ 500 ms / eligible | 95% | 30d | 5% | `/up`; histogram bucket `le=500` |
| Queue success | `back_vibes-worker` | success / terminal jobs | 99% | 30d | 1% | retried, released |
| Scheduler success | `back_vibes-worker` | success / eligible runs | 99% | 30d | 1% | overlap_prevented, skipped |
| Smart Home actions | `back_vibes-worker` | success / all actions | 95% | 30d | 5% | none (all outcomes counted) |
| Observability pipeline | `otelcol-contrib` | successful exports / total | 99% | 30d | 1% | cluster-wide (no `environment` label) |

**Deferred:** Push notification dedicated SLO (queue-layer proxy exists on D-03); per-provider Smart Home SLO; mobile client SLO; regional SLO.

---

## Formulas

```
allowed_error_ratio = 1 - target
observed_error_ratio = 1 - SLI
burn_rate = observed_error_ratio / allowed_error_ratio
error_budget_remaining = 1 - (observed_error_ratio / allowed_error_ratio)
```

**Example:** target 99.5% (allowed 0.5%). If 10 failures in 1000 requests (1% error):

- burn_rate = 0.01 / 0.005 = **2**
- error_budget_remaining = 1 - 2 = **-1** (budget exhausted)

---

## Dashboard interpretation

Open **D-08 SLO & Error Budget** and filter by `$environment` (staging vs production).

| Panel | Healthy | At risk | Exhausted |
| --- | --- | --- | --- |
| SLI (30d) | ≥ target | within 1% of target | below target |
| Budget remaining | > 50% | 25–50% | ≤ 0 |
| Burn rate (1h) | ≤ 1 | 2–10 | > 10 |

**Low traffic:** Staging may not have enough events for a statistically meaningful 30-day SLO. Panels may show “No data” or flat lines — this is expected. Alerts include minimum event guards to avoid false pages.

---

## Alert response

### Fast burn response {#fast-burn-response}

**Alerts:** `IxoraSLO*FastBurnCritical` (5m + 1h windows both above 10, with traffic guard)

1. Acknowledge alert; note `environment` and SLO name from labels.
2. Open [D-08](/d/ixora-slo) — confirm burn rate and SLI trend.
3. Drill to domain dashboard (D-05 HTTP, D-04 Queue, D-06 Scheduler, D-02 Smart Home, D-07 Infrastructure).
4. Use Loki (logs) and Tempo (traces) with same time range — see D-08 investigation panel.
5. Determine: real outage vs telemetry gap (Collector down → check D-07 first).
6. If real failure: escalate per severity; consider rollback if deploy-related.
7. If telemetry failure: fix Collector/export path — do not treat as product outage.

### Medium burn response {#medium-burn-response}

**Alerts:** `IxoraSLO*MediumBurnWarning` (5m + 6h windows both above 2)

1. Same investigation path as fast burn, lower urgency.
2. Schedule fix before budget exhaustion; pause non-critical rollouts.
3. Document in incident notes if trend persists > 24 h.

### When to stop feature rollout

- Error budget remaining < 25% **and** burn rate > 1 for 6 h.
- Any critical fast-burn alert on production.

### When to roll back

- Fast-burn alert after a deploy correlates with SLI drop.
- Customer-impacting 5xx or Smart Home failure spike confirmed in D-05/D-02.

---

## Distinguishing real failure from telemetry failure

| Signal | Real failure | Telemetry failure |
| --- | --- | --- |
| D-05/D-04 app metrics | Degraded | Normal |
| D-07 Collector export | Normal | Failed / gaps |
| Loki logs | Error patterns | Missing recent logs |
| `ixora_telemetry_export_failed_total` | Low | Spiking |

---

## Silencing alerts safely

1. Prefer **mute timing** in Grafana for known maintenance windows.
2. Do not disable recording rules in production without approval.
3. Document who silenced, why, and expiry time.
4. After silence: verify alert clears and SLI recovers in D-08.

---

## Staging validation (non-destructive)

1. `promtool check rules` on all rule files — must pass.
2. `docker compose config` — rules volume mounted.
3. Restart Prometheus locally; `curl localhost:9090/-/rules | grep ixora`.
4. Confirm recording series appear (may take 5–30 min of traffic).
5. Open D-08 — panels render; `$environment` filter works.
6. Confirm alerts **inactive** under normal conditions (Prometheus → Alerts).
7. Optional: use Prometheus UI “Unit test” or recording rule query with historical range — do **not** inject production failures.

---

## Monthly / quarterly SLO review

- Compare SLI vs target per environment.
- Adjust targets only with product/engineering agreement.
- Review deferred items: tail sampling impact on trace SLO, push SLO, per-provider Smart Home.
- Update `recording-rules-foundation.md` catalog if SLI definitions change.

---

## Related documents

- [slo-philosophy.md](../architecture/slo-philosophy.md)
- [recording-rules-foundation.md](../specs/observability-foundation/mvp/recording-rules-foundation.md)
- [alerting-philosophy.md](../architecture/alerting-philosophy.md)
- [observability-playbook.md](../operations/observability-playbook.md)
