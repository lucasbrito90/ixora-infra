# Runbook: Application / Queue Workers — Failure Rate

**Alert UID:** ixora-alert-queue-failure-rate
**Severity:** warning
**Dashboard:** [D-04 Queue Workers](/d/ixora-queue)
**Phase:** 9
**Owner:** backend

## Symptoms

- Alert fires when the ratio of `ixora_queue_job_total{outcome="failed"}` to total jobs exceeds 5% for 5+ minutes, across `smart-home`, `push`, and `default` queues.

## Likely Causes

1. A job class has a bug causing consistent exceptions (deploy regression).
2. A downstream dependency the job calls (Home Assistant, FCM, Spaces) is failing.
3. Job payload data issue (e.g. stale/invalid references) causing repeated failures.
4. Worker process crashed and jobs are timing out rather than completing.

## Validation Steps

### Step 1: Confirm via dashboard
1. Open [D-04 Queue Workers](/d/ixora-queue).
2. Break the failure rate down by queue name to isolate which queue is affected.

### Step 2: Check logs
```
{app="back_vibes-worker"} |= "failed"
```
Filter to the affected queue and time window; look for a repeated exception class.

### Step 3: Check traces
Open Tempo Explore, filter `service.name=back_vibes-worker` for the failing job class in the alert window.

## Recovery Steps

### For cause 1: Deploy regression
1. Confirm timing against recent `staging` deploys; roll back if confirmed.

### For cause 2: Downstream dependency
1. Cross-check D-02 Smart Home (if `smart-home` queue) or D-03 Push (if `push` queue) for provider-specific failure patterns.

### For cause 3: Bad payload
1. Identify the failing job IDs from Loki; inspect payload for the specific bad data.
2. Consider whether a data migration or cleanup is needed.

### For cause 4: Worker crashed
1. `docker ps` / App Platform worker service status; restart if stopped.

## Verification

After recovery:
- [ ] Alert transitions to Resolved in Grafana
- [ ] D-04 failure-rate panel returns below 5%
- [ ] No new failure spikes in the affected queue for 5 minutes

## Rollback

Revert `staging` branch to the prior commit if deploy-related.

## Escalation

Warning severity: investigate within the working day. Escalate to tech lead if failure rate keeps climbing or crosses into a Business-category alert (Smart Home, Push).

## Postmortem Checklist

- [ ] What was the root cause?
- [ ] How long was the impact?
- [ ] Which queue(s) and how many jobs were affected?
- [ ] Was the 5% / 5m threshold appropriate?
- [ ] What changes prevent recurrence?
