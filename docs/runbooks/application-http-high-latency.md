# Runbook: Application / HTTP API — High Latency

**Alert UID:** ixora-alert-http-high-latency
**Severity:** warning
**Dashboard:** [D-05 HTTP API](/d/ixora-http)
**Phase:** 9
**Owner:** backend

## Symptoms

- Alert fires when p95 request duration (`histogram_quantile(0.95, ixora_http_server_duration_bucket)`) exceeds 2s for 5+ minutes.
- Requests are still succeeding (this is not the error-rate alert) but users perceive the app as slow.

## Likely Causes

1. A slow query or N+1 pattern introduced in a recent deploy.
2. Queue/worker contention delaying synchronous request-time work.
3. VM/App Platform resource pressure (CPU throttling).
4. A downstream call (Spaces upload, Firebase verification, Home Assistant dispatch) is slow.
5. Increased traffic volume beyond normal capacity.

## Validation Steps

### Step 1: Confirm via dashboard
1. Open [D-05 HTTP API](/d/ixora-http).
2. Identify which route(s) are driving the p95 elevation.

### Step 2: Check logs
```
{app="back_vibes-api"} |= "slow"
```
Also check for repeated warnings around timeouts or retries in the alert window.

### Step 3: Check traces
Open Tempo Explore, filter `service.name=back_vibes-api` for the slow route; inspect the span breakdown to find which segment (DB, external call, app logic) dominates duration.

## Recovery Steps

### For cause 1: Slow query
1. Identify the query via trace span attributes or `EXPLAIN ANALYZE` against staging DB.
2. Add missing index or fix eager-loading; ship as a normal PR (not a hotfix — this is a warning, not an outage).

### For cause 2: Queue contention
1. Open D-04 Queue Workers; if active jobs are saturated, that is the shared root cause.

### For cause 3/4: Resource pressure or slow downstream
1. Open D-07 Infrastructure to correlate VM load.
2. If a specific external provider is slow, note it — no fix on our side beyond timeout tuning.

## Verification

After recovery:
- [ ] Alert transitions to Resolved in Grafana
- [ ] D-05 p95 latency panel returns below 2s
- [ ] No regression in error rate as a side effect of any fix

## Rollback

If a deploy caused the regression, revert the `staging` branch to the prior commit.

## Escalation

Warning severity: investigate within the current working day; no page. Escalate to tech lead only if it degrades into the error-rate alert.

## Postmortem Checklist

- [ ] What was the root cause?
- [ ] How long was the impact?
- [ ] Was the 2s / 5m threshold appropriate?
- [ ] Was the runbook accurate?
- [ ] What changes prevent recurrence?
