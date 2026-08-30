# Load Testing — Phase 10 Foundation

**Phase:** 10 — Performance Validation & Load Testing (first slice, read-only)  
**Status:** Foundation delivered — smoke tested 2026-08-29; operator baseline run + Prometheus output validated 2026-08-30  
**Tooling:** [k6](https://k6.io/) v1.0.0-rc1  
**Target:** `https://staging-api.ixora-app.app`

---

## Git home

`qa/` at the workspace root is not a git repository. This load-testing folder lives inside `ixora-infra/qa/load-testing/` so it is tracked by the `ixora-infra` repo alongside Phase 10 docs and tracking files. Scripts are authored as plain JavaScript (same `.js` convention used across other k6 deployments) — not TypeScript, which is consistent with the existing `qa/` evidence scripts in this workspace.

---

## Staging environment — critical constraints

| Component | Spec | Implication |
| --- | --- | --- |
| App Platform tier | `basic-xxs` (smallest available) | Shared compute; not sized for throughput ceiling tests |
| Postgres | `db-s-1vcpu-1gb`, `node_count=1` | Single-node; connection exhaustion is a real risk at high VUs |
| Shared usage | QA E2E, Phase 9 alerts, developer staging | Load tests run at the same time as other staging activity |

**Do NOT run with more than 5-10 VUs without explicit operator sign-off.** The default options in `read-flows-smoke.js` (3 VUs × 10 iterations) are deliberately conservative. Raising these without reviewing staging health is the single most likely way to degrade the QA environment for other work.

---

## Directory structure

```
qa/load-testing/
├── README.md              ← this file
├── .env.example           ← credential template (copy to .env, never commit)
├── scripts/
│   ├── auth.js            ← reusable Firebase login + /api/auth/sync module
│   └── read-flows-smoke.js ← GET-only scenario (Phase 10.1 acceptance test)
└── evidence/
    └── smoke-YYYY-MM-DD.txt  ← one file per test run
```

---

## Prerequisites

1. **k6** — install the Grafana-distributed binary (no sudo required):

   ```bash
   curl -L https://github.com/grafana/k6/releases/latest/download/k6-linux-amd64.tar.gz \
     | tar -xzf - --strip-components=1 -C ~/.local/bin k6-*/k6
   chmod +x ~/.local/bin/k6
   k6 version
   ```

   Tested with **k6 v1.0.0-rc1**. The `experimental-prometheus-rw` output is built-in from v0.42.0+; no extension build required.

2. **Credentials** — copy `.env.example` to `.env` and fill in values:

   ```bash
   cp .env.example .env
   # edit .env — FIREBASE_API_KEY, E2E_USER_EMAIL, E2E_USER_PASSWORD
   ```

   These are the same credentials used by `qa/scheduler-e2e/scripts/staging-api-qa.sh`. Read them from `front_vibes/.env`:
   - `VITE_FIREBASE_API_KEY` → `FIREBASE_API_KEY`
   - `E2E_USER_EMAIL` → `E2E_USER_EMAIL`
   - `E2E_USER_PASSWORD` → `E2E_USER_PASSWORD`

---

## Running

Source credentials, then run:

```bash
# Source env vars
set -a && source .env && set +a

# Smoke (acceptance — minimal, equivalent to a manual curl):
K6_VUS=1 K6_ITERATIONS=3 k6 run scripts/read-flows-smoke.js

# Conservative baseline (default options, ~40s at 3 VUs):
k6 run scripts/read-flows-smoke.js
```

Expected output: all thresholds green, 0% `http_req_failed`, p(95) < 3s.

---

## Firebase token limitation

`setup()` logs in once and shares the token across all VUs. Firebase ID tokens expire after approximately **1 hour**. For this scenario's durations (seconds to a few minutes), expiry is not a concern. If you run a long-duration test (> 50 minutes), calls will start returning 401 as the token ages out. Token renewal (Firebase REST API `/token` endpoint) is **explicitly deferred** as unnecessary complexity for this Phase 10 foundation — add it if sustained multi-hour runs become a requirement.

---

## Prometheus remote-write output

k6 can push metrics to Prometheus in real time using the built-in experimental output:

```bash
K6_PROMETHEUS_RW_SERVER_URL=http://127.0.0.1:9090/api/v1/write \
k6 run -o experimental-prometheus-rw scripts/read-flows-smoke.js
```

**Known blocker:** the observability host (`137.184.163.187`) binds Prometheus to `127.0.0.1:9090` only — port 9090 is firewall-blocked from the internet (confirmed in `ixora-infra/collector/docker-compose.yml` and `prometheus.yml`). Remote-write output therefore requires one of:

1. Running k6 **on the observability host** (SSH in, install k6 there, run tests from there)
2. An **SSH tunnel**: `ssh -L 9090:127.0.0.1:9090 root@137.184.163.187` then run k6 locally pointing at `http://127.0.0.1:9090/api/v1/write`

For the Phase 10 acceptance smoke test (2026-08-29), Prometheus output was **not used** — the volume (3 iterations) produces no meaningful time-series data.

**Validated 2026-08-30 (operator baseline run):** used the SSH tunnel approach (option 2 above) and confirmed 16 `k6_*` metrics landed in the real Prometheus, tagged `testrun="phase10-baseline-2026-08-30"` with a per-endpoint `name` label. See `evidence/baseline-2026-08-30.txt`. No Grafana dashboard/panel has been built for these yet — the data is queryable but not yet visualized; that's a follow-up, not a blocker.

Prometheus remote-write is already enabled on the host: `--web.enable-remote-write-receiver` is present in `docker-compose.yml` line 180.

---

## Scope — what this slice does NOT cover

| Deferred | Why |
| --- | --- |
| Write flows (POST /api/schedules, POST /api/vibes, etc.) | Shared staging data — mutations need careful cleanup strategy |
| Sustained load / ramp-up curves, VUs beyond ~5-10 | Needs explicit operator sign-off on staging capacity before every increase — not something to automate |
| Grafana dashboard/panel for the k6 metrics | Data is in Prometheus (validated 2026-08-30) but not yet visualized |
| Token refresh for long runs | Not needed for short runs; implement when needed |
| Smart Home / push notification flows | Separate Phase 10 slice |

---

## Evidence

| Date | Scenario | Result | File |
| --- | --- | --- | --- |
| 2026-08-29 | Smoke (1 VU, 3 iters) | **PASS** — 21/21 checks, 0% errors, p(95)=822.9ms | `evidence/smoke-2026-08-29.txt` |
| 2026-08-30 | Baseline (3 VUs, 10 shared iters, default options), Prometheus output enabled | **PASS** — 63/63 checks, 0% errors, p(95)=645.19ms. No alert fired; staging unaffected post-run. | `evidence/baseline-2026-08-30.txt` |

---

## Related documents

| Document | Purpose |
| --- | --- |
| `ixora-infra/docs/roadmap/ixora-roadmap-2026-08-16.md` Phase 10 | Phase 10 tracking |
| `ixora-infra/docs/specs/observability-foundation/mvp/tasks.md` Phase 10 | Task-level tracking |
| `qa/scheduler-e2e/scripts/staging-api-qa.sh` | Auth pattern source (Firebase login + auth/sync) |
| `ixora-infra/collector/prometheus/prometheus.yml` | Prometheus config (remote-write receiver enabled) |
| `ixora-infra/docs/decisions/ADR-030-observability-security-and-privacy.md` | No PII in test output |
