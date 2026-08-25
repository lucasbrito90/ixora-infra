# Runbook: Application / Scheduler — Missed Executions

**Alert UID:** ixora-alert-scheduler-missed
**Severity:** warning
**Dashboard:** [D-06 Scheduler](/d/ixora-scheduler)
**Phase:** 9
**Owner:** backend

## Symptoms

- Alert fires when `rate(ixora_scheduler_execution_total{outcome="success"}[10m])` is zero for 10+ minutes.
- No scheduled vibes are being dispatched even though users have active schedules.

## Likely Causes

1. The scheduler loop (Laravel Console scheduler) stopped running — cron/App Platform scheduled task not firing.
2. Every dispatch attempt is failing before recording `outcome="success"` (check `outcome="failure"` instead).
3. No schedules are currently due in this window — legitimate zero (context-dependent per alerting-philosophy.md §3).
4. Queue worker backlog preventing scheduled jobs from being processed even if dispatched.

## Validation Steps

### Step 1: Confirm via dashboard
1. Open [D-06 Scheduler](/d/ixora-scheduler).
2. Check whether `outcome="failure"` is elevated (real failure) vs. both success and failure are flat (loop stopped) vs. genuinely no schedules due (check schedule count in the admin data).

### Step 2: Check logs
```
{app="back_vibes-api"} |= "schedule"
```
Confirm whether the scheduler process is invoked at all in the window.

### Step 3: Check traces
Open Tempo Explore, filter `service.name=back_vibes-api` for `console.schedule` spans in the alert window.

## Recovery Steps

### For cause 1: Loop stopped
1. Confirm the scheduled console command is still configured in App Platform / cron.
2. Restart the scheduling process if stopped.

### For cause 2: Dispatch failures
1. Follow `application-queue-failure-rate.md` — this is the same underlying failure surfaced differently.

### For cause 3: Legitimate zero
1. Confirm via the admin panel or DB that no schedules are due; if so, this is a false positive — consider whether the 10-minute window needs adjustment (alerting-philosophy.md §21 retirement/tuning).

## Verification

After recovery:
- [ ] Alert transitions to Resolved in Grafana
- [ ] D-06 shows successful dispatches resuming
- [ ] No user reports of missed automations for the affected window

## Rollback

If a deploy disabled or broke the scheduler entry point, revert the `staging` branch.

## Escalation

Warning severity: investigate within the working day. Escalate to tech lead if confirmed real (not a legitimate zero) and unresolved beyond a few hours.

## Postmortem Checklist

- [ ] What was the root cause?
- [ ] How long was the impact and how many schedules were missed?
- [ ] Was the 10-minute `for` threshold appropriate, or too sensitive to low-traffic staging windows?
- [ ] What changes prevent recurrence?
