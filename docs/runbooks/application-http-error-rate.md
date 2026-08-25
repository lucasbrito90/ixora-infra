# Runbook: Application / HTTP API — Elevated Error Rate

**Alert UID:** ixora-alert-http-error-rate
**Severity:** critical
**Dashboard:** [D-05 HTTP API](/d/ixora-http)
**Phase:** 9
**Owner:** backend

## Symptoms

- Alert fires when the ratio of `http_status_code=~"5.."` responses to total requests exceeds 1% for 5+ minutes.
- D-05 HTTP API shows an elevated 5xx-rate panel.
- Users (front_vibes mobile app, ixora-admin) report failed requests or app errors.

## Likely Causes

1. A recent deploy introduced a regression (unhandled exception, bad migration, misconfigured env var).
2. A downstream dependency is failing (PostgreSQL, Spaces/S3, Firebase token verification).
3. Queue backlog causing request-time synchronous work to time out.
4. Resource exhaustion (App Platform instance CPU/memory limits).
5. A specific route/endpoint is receiving malformed input at volume.

## Validation Steps

### Step 1: Confirm via dashboard
1. Open [D-05 HTTP API](/d/ixora-http).
2. Break down the error panel by route/status code to find the concentrated failure.
3. Confirm the elevation is sustained, not a single spike already recovering.

### Step 2: Check logs
```
{app="back_vibes-api"} |= "ERROR"
```
Filter to the alert's time window in Loki; look for stack traces or repeated exception messages.

### Step 3: Check traces
Open Tempo Explore. Filter by `service.name=back_vibes-api` and the failing route in the alert window; inspect span status and error attributes.

## Recovery Steps

### For cause 1: Deploy regression
1. Confirm the failure onset aligns with a recent `staging` push (App Platform deploy history).
2. Roll back to the previous known-good commit on the `staging` branch if confirmed.

### For cause 2: Downstream dependency
1. Check PostgreSQL connectivity/health, Spaces API status, Firebase status page.
2. If a dependency is down, this is expected-but-critical — communicate and wait for recovery; no code fix needed.

### For cause 3/4: Backlog or resource exhaustion
1. Open D-04 Queue Workers and D-07 Infrastructure to correlate.
2. Scale the App Platform instance or clear the backlog per its own runbook.

## Verification

After recovery:
- [ ] Alert transitions to Resolved in Grafana
- [ ] D-05 5xx-rate panel returns below 1%
- [ ] No new ERROR-level entries in Loki for 5 minutes post-recovery

## Rollback

If a deploy caused this, revert the `staging` branch to the prior commit and redeploy; do not hotfix directly on `staging` without going through `develop` first (git-flow.md).

## Escalation

If unresolved within 30 minutes: escalate to tech lead per alerting-philosophy.md §18.

## Postmortem Checklist

- [ ] What was the root cause?
- [ ] How long was the impact?
- [ ] How many users/requests were affected?
- [ ] Was the 1% / 5m threshold appropriate?
- [ ] Was the runbook accurate?
- [ ] What changes prevent recurrence (tests, canary deploy, dependency circuit breaker)?
