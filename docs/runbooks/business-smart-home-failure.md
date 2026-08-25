# Runbook: Business / Smart Home — Elevated Failure Rate

**Alert UID:** ixora-alert-smart-home-failure
**Severity:** critical
**Dashboard:** [D-02 Smart Home](/d/ixora-smart-home)
**Phase:** 9
**Owner:** product

## Symptoms

- Alert fires when the ratio of `ixora_smart_home_action_total{outcome="failure"}` to total actions exceeds 20% for 5+ minutes.
- This is a product-facing failure: vibes that are supposed to control real smart home devices are not succeeding.

## Likely Causes

1. Home Assistant provider is unreachable (network, auth token expired/revoked).
2. A specific device class/integration within Home Assistant is failing (not the whole provider).
3. A deploy regression in `SmartHome/*` (adapter, dispatch resolver, DTO mapping).
4. Users' individual Home Assistant instances are down (if this is widespread across many distinct instances, likely not a platform-side bug).

## Validation Steps

### Step 1: Confirm via dashboard
1. Open [D-02 Smart Home](/d/ixora-smart-home).
2. Break down failures by provider (`provider=home_assistant`) and, if visible, by action/device type.
3. Determine whether failures are concentrated (one integration/provider) or spread (platform-wide).

### Step 2: Check logs
```
{app="back_vibes-worker"} |= "smart_home" |= "failure"
```
Filter to the alert window; look for HTTP errors from Home Assistant calls or exception traces from `HomeAssistantAdapter`.

### Step 3: Check traces
Open Tempo Explore, filter `service.name=back_vibes-worker` for `smart_home.dispatch` / `smart_home.action` / `smart_home.provider` spans in the alert window; inspect the provider span for the actual HTTP failure.

## Recovery Steps

### For cause 1: Provider unreachable
1. Confirm via the provider span whether it is a connection error, timeout, or 401/403 (expired token).
2. If auth-related, this is per-user (each user has their own Home Assistant credentials) — check whether it is one user or many.

### For cause 2: Specific integration failing
1. Isolate the failing device/action type from D-02 and cross-reference with recent Home Assistant-side changes (out of our control, but confirms root cause).

### For cause 3: Deploy regression
1. Confirm timing against recent `staging` deploys touching `SmartHome/*`; roll back if confirmed.

### For cause 4: Widespread individual outages
1. If failures are spread across many distinct provider instances with no common pattern, this is likely not fixable on our side — document and monitor; do not treat as a platform bug.

## Verification

After recovery:
- [ ] Alert transitions to Resolved in Grafana
- [ ] D-02 failure-rate panel returns below 20%
- [ ] No new elevated failures for 5 minutes

## Rollback

Revert `staging` branch to the prior commit if `SmartHome/*` deploy-related.

## Escalation

Critical severity: on-call paged, respond within 15–30 minutes. Escalate to tech lead if unresolved within 30 minutes (alerting-philosophy.md §13.3); this alert also has a product owner per alerting-philosophy.md §9.1 — loop in product on any provider-wide outage.

## Postmortem Checklist

- [ ] What was the root cause?
- [ ] How long was the impact?
- [ ] How many users/devices were affected?
- [ ] Was the 20% / 5m threshold appropriate?
- [ ] What changes prevent recurrence (retry/backoff tuning, provider health pre-check)?
