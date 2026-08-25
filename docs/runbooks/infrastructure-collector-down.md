# Runbook: Infrastructure / Collector — Collector Down

**Alert UID:** ixora-alert-collector-down
**Severity:** emergency
**Dashboard:** [D-07 Infrastructure](/d/ixora-collector)
**Phase:** 9
**Owner:** sre

## Symptoms

- Alert fires when `sum(rate(ixora_telemetry_export_failed_total[5m])) > 0` for 2+ minutes.
- D-07 Infrastructure shows a nonzero export-failure rate, or the Collector export panels go flat/no-data.
- Downstream dashboards may show gaps in the same window (metrics never arrived) — this is a symptom, not a separate incident.

## Likely Causes

1. Collector container crashed or was OOM-killed on the observability VM.
2. Collector's export pipeline to Prometheus/Loki/Tempo is backpressured or misconfigured (e.g. bad endpoint after a config change).
3. Observability VM is out of disk/memory, preventing the Collector from writing or exporting.
4. Network partition between `back_vibes` (OTLP source) and the observability VM.
5. Prometheus/Loki/Tempo backend itself is down, causing the Collector's export attempts to fail.

## Validation Steps

### Step 1: Confirm via dashboard
1. Open [D-07 Infrastructure](/d/ixora-collector).
2. Check the Collector export-failure panel and pipeline throughput panels.
3. Confirm `ixora_telemetry_export_failed_total` is actively increasing, not a one-off blip.

### Step 2: Check logs
SSH to the observability VM:
```
docker ps | grep ixora-collector
docker logs --tail 200 ixora-collector
```
Look for export errors, connection refused, or OOM kill messages.

### Step 3: Check backend health
```
docker ps | grep -E "prometheus|loki|tempo"
```
If Prometheus/Loki/Tempo are down, the Collector failure is a downstream symptom — fix the backend first.

## Recovery Steps

### For cause 1 (crashed container)
1. `docker compose -f collector/docker-compose.yml up -d collector`
2. Confirm it stays up: `docker ps` after 60s.

### For cause 2 (backpressure/misconfig)
1. Review recent changes to `collector/otel-collector-config.yaml` or `.env`.
2. Revert the last change if it correlates with the failure onset.

### For cause 3 (disk/memory)
1. `df -h` and `free -h` on the VM.
2. Free disk (check Prometheus/Loki retention is enforcing per ADR-031) or resize the Droplet.

### For cause 4 (network)
1. Confirm the observability VM's firewall/security group still allows inbound OTLP from `back_vibes`.
2. Check DNS/connectivity from `back_vibes` App Platform to the VM's public IP.

## Verification

After recovery:
- [ ] Alert transitions to Resolved in Grafana
- [ ] D-07 export-failure panel returns to zero
- [ ] Downstream dashboards (D-01–D-06) resume receiving fresh data points
- [ ] No new errors in `docker logs ixora-collector` for 5 minutes

## Rollback

If a config change caused this, revert it via git and redeploy the Collector container; do not hand-edit config on the VM outside of `tofu apply`/documented deploy steps.

## Escalation

If unresolved within 15 minutes: this is an "all hands" condition per alerting-philosophy.md §13.4 — observability itself is blind. Escalate immediately.

## Postmortem Checklist

- [ ] What was the root cause?
- [ ] How long was the impact (data gap duration)?
- [ ] Were any real incidents masked by the observability gap?
- [ ] Was the 2-minute `for` duration appropriate, or too eager/too slow?
- [ ] What changes prevent recurrence (VM sizing, alerting on Collector container health directly, etc.)?
