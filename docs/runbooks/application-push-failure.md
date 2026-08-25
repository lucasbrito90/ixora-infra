# Runbook: Application / Push Queue — Delivery Failure

**Alert UID:** ixora-alert-push-failure
**Severity:** warning
**Dashboard:** [D-03 Push Notifications](/d/ixora-push)
**Phase:** 9
**Owner:** backend

## Symptoms

- Alert fires when the `queue="push"` job failure rate exceeds 10% for 5+ minutes.
- This is queue-layer failure (the job itself errored before completing) — distinct from FCM-reported delivery failure, which is a Business-category alert pending Phase 7B.5 metrics.

## Likely Causes

1. FCM credentials expired or misconfigured (`FcmPushProvider`).
2. A bug in `PushNotificationService`/`PushTokenService` causing job exceptions.
3. Malformed or stale push tokens causing repeated failures at the job level (before reaching FCM's own error reporting).
4. Downstream dependency (Firebase) outage.

## Validation Steps

### Step 1: Confirm via dashboard
1. Open [D-03 Push Notifications](/d/ixora-push).
2. Check whether failures cluster around a specific notification type or are uniform.

### Step 2: Check logs
```
{app="back_vibes-worker"} |= "push" |= "failed"
```
Filter to the alert window; look for FCM SDK exceptions or credential errors.

### Step 3: Check traces
Open Tempo Explore, filter `service.name=back_vibes-worker` for push job spans.

## Recovery Steps

### For cause 1: FCM credentials
1. Verify the FCM service account key/config is valid and not expired.
2. Rotate credentials via DigitalOcean Secrets if needed; redeploy.

### For cause 2: Code bug
1. Confirm timing against recent `staging` deploys touching `PushNotifications/*`; roll back if confirmed.

### For cause 3: Bad tokens
1. Check whether failures correlate with stale/unregistered tokens; this may self-resolve as `PushTokenService` prunes them, but a spike suggests a token-invalidation event (e.g. app reinstall wave).

### For cause 4: Firebase outage
1. Check Firebase status page; if confirmed, this is expected-but-warning — no code fix, wait for recovery.

## Verification

After recovery:
- [ ] Alert transitions to Resolved in Grafana
- [ ] D-03 push failure-rate panel returns below 10%
- [ ] No new push job failures for 5 minutes

## Rollback

Revert `staging` branch to the prior commit if deploy-related.

## Escalation

Warning severity: investigate within the working day. Escalate to tech lead if it correlates with the Business/Push delivery-failure condition (once Phase 7B.5 metrics exist).

## Postmortem Checklist

- [ ] What was the root cause?
- [ ] How long was the impact and how many notifications were affected?
- [ ] Was the 10% / 5m threshold appropriate?
- [ ] What changes prevent recurrence?
