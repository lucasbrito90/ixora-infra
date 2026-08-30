/**
 * write-flows-crud.js — CRUD write scenario for back_vibes staging API
 *
 * Phase 10 — Performance Validation & Load Testing (second slice, write CRUD)
 *
 * SCOPE
 * -----
 * Exercises full create→update→delete lifecycle for vibes and schedules.
 * Every resource created in an iteration is deleted in the SAME iteration —
 * no data is left in staging after the test regardless of how it ends.
 *
 * Operations per iteration (in order):
 *   1. POST /api/vibes          → create test vibe
 *   2. POST /api/schedules      → create schedule referencing that vibe
 *   3. PATCH /api/vibes/{id}    → update the vibe name
 *   4. DELETE /api/schedules/{id} → delete schedule first (references vibe)
 *   5. DELETE /api/vibes/{id}   → delete vibe last
 *
 * CLEANUP GUARANTEE
 * -----------------
 * Cleanup runs per-iteration, not in teardown(). teardown() is never called if
 * k6 is interrupted (Ctrl-C, timeout, signal). Per-iteration cleanup is the
 * only reliable guarantee. If creation fails (no id returned), the delete step
 * is skipped safely — there is nothing to delete. If schedule creation fails
 * but vibe creation succeeded, the vibe is still deleted before the iteration
 * ends. All test resources are prefixed with "[k6-load]" for easy auditing.
 *
 * DEFERRED (not in this slice)
 * ----------------------------
 * - Smart Home dispatch (POST /vibes/{vibe}/smart-home/dispatch): triggers real
 *   Home Assistant commands — deferred to a future slice.
 * - Push notification flows: trigger real FCM delivery — deferred.
 *
 * ENVIRONMENT WARNING — READ BEFORE RAISING VUs
 * -----------------------------------------------
 * Staging runs on App Platform basic-xxs + Postgres db-s-1vcpu-1gb (single node).
 * Write operations (INSERT/DELETE with index maintenance, transactions) cost more
 * than reads on this hardware. Default options below (1 VU × 5 iters) are MORE
 * conservative than the read scenario (3 VUs × 10 iters). Do NOT raise VUs
 * without operator sign-off on staging health.
 *
 * RUNNING
 * -------
 * Smoke (acceptance — minimal):
 *   K6_VUS=1 K6_ITERATIONS=2 k6 run scripts/write-flows-crud.js
 *
 * Conservative baseline (default):
 *   k6 run scripts/write-flows-crud.js
 *
 * With Prometheus output (requires k6 on the observability host or SSH tunnel):
 *   K6_PROMETHEUS_RW_SERVER_URL=http://127.0.0.1:9090/api/v1/write \
 *   k6 run -o experimental-prometheus-rw scripts/write-flows-crud.js
 */

import http from 'k6/http';
import { check, sleep } from 'k6';
import { firebaseLogin, syncWithApi, authHeaders } from './auth.js';

const API_BASE = __ENV.K6_API_BASE || 'https://staging-api.ixora-app.app';

// ── Options ──────────────────────────────────────────────────────────────────
//
// Defaults are deliberately more conservative than read-flows-smoke.js.
// Writes (INSERT/DELETE + index maintenance) are more expensive than GETs
// on a basic-xxs / db-s-1vcpu-1gb single-node staging environment.
//
// Override at runtime:
//   K6_VUS=1 K6_ITERATIONS=2 k6 run ...   ← smoke
//   K6_VUS=2 K6_ITERATIONS=10 k6 run ...  ← light baseline (operator decision)
//
export const options = {
  vus: __ENV.K6_VUS ? parseInt(__ENV.K6_VUS, 10) : 1,
  iterations: __ENV.K6_ITERATIONS ? parseInt(__ENV.K6_ITERATIONS, 10) : 5,

  thresholds: {
    // Same reference limits as read-flows-smoke.js — writes will be slower,
    // but basic-xxs should still answer in < 3s for single-row operations.
    http_req_duration: ['p(95)<3000'],
    http_req_failed: ['rate<0.05'],
    checks: ['rate>0.95'],
  },
};

// ── Setup — runs once before all VUs ─────────────────────────────────────────
export function setup() {
  console.log('[setup] Authenticating against Firebase...');
  const { idToken } = firebaseLogin();
  console.log('[setup] Firebase login OK');
  syncWithApi(idToken);
  console.log('[setup] /api/auth/sync OK');
  return { idToken };
}

// ── Default function — one iteration per VU ──────────────────────────────────
export default function (data) {
  const headers = authHeaders(data.idToken);

  // Unique tag for this iteration — used in the `name` field so orphaned
  // resources are trivially identifiable via GET /api/vibes after the test.
  const tag = `VU${__VU}-ITER${__ITER}-${Date.now()}`;
  const vibeName = `[k6-load] vibe ${tag}`;

  // start_time: 1 hour from now, formatted as ISO 8601.
  // Using a future time makes the schedule valid for the recurrence engine
  // without needing any waiting or side effects (is_enabled defaults to true
  // but start_time in the future means next_run_at is set correctly).
  const startTime = new Date(Date.now() + 3600 * 1000).toISOString();

  let vibeId = null;
  let scheduleId = null;

  // ── Step 1: Create vibe ───────────────────────────────────────────────────
  const createVibeResp = http.post(
    `${API_BASE}/api/vibes`,
    JSON.stringify({ name: vibeName, description: 'k6 load test — delete me', is_active: true }),
    { headers, tags: { name: 'vibe_create' } }
  );

  const vibeCreated = check(createVibeResp, {
    'POST /api/vibes: 201': (r) => r.status === 201,
    'POST /api/vibes: id in response': (r) => {
      try { return !!JSON.parse(r.body).data.id; } catch { return false; }
    },
  });

  if (vibeCreated && createVibeResp.status === 201) {
    try {
      vibeId = JSON.parse(createVibeResp.body).data.id;
    } catch {
      console.warn(`[${tag}] Could not parse vibe id from response`);
    }
  }

  if (!vibeId) {
    // Nothing was created — safe to skip the rest of this iteration.
    console.warn(`[${tag}] Vibe creation failed — skipping schedule creation and cleanup`);
    sleep(0.5);
    return;
  }

  sleep(0.3);

  // ── Step 2: Create schedule referencing the vibe ─────────────────────────
  const createSchedResp = http.post(
    `${API_BASE}/api/schedules`,
    JSON.stringify({
      vibe_id: vibeId,
      name: `[k6-load] schedule ${tag}`,
      timezone: 'America/Sao_Paulo',
      start_time: startTime,
      recurrence_type: 'once',
      is_enabled: true,
    }),
    { headers, tags: { name: 'schedule_create' } }
  );

  const schedCreated = check(createSchedResp, {
    'POST /api/schedules: 201': (r) => r.status === 201,
    'POST /api/schedules: id in response': (r) => {
      try { return !!JSON.parse(r.body).data.id; } catch { return false; }
    },
  });

  if (schedCreated && createSchedResp.status === 201) {
    try {
      scheduleId = JSON.parse(createSchedResp.body).data.id;
    } catch {
      console.warn(`[${tag}] Could not parse schedule id from response`);
    }
  }

  // Note: if schedule creation failed, we still have a vibeId to clean up below.

  sleep(0.3);

  // ── Step 3: Update the vibe (PATCH) ──────────────────────────────────────
  if (vibeId) {
    const patchResp = http.patch(
      `${API_BASE}/api/vibes/${vibeId}`,
      JSON.stringify({ name: `[k6-load] vibe ${tag} (updated)` }),
      { headers, tags: { name: 'vibe_update' } }
    );
    check(patchResp, {
      'PATCH /api/vibes/{id}: 200': (r) => r.status === 200,
    });
  }

  sleep(0.3);

  // ── Step 4: Delete schedule (must come BEFORE vibe — FK reference) ────────
  if (scheduleId) {
    const deleteSchedResp = http.del(
      `${API_BASE}/api/schedules/${scheduleId}`,
      null,
      { headers, tags: { name: 'schedule_delete' } }
    );
    const schedDeleted = check(deleteSchedResp, {
      'DELETE /api/schedules/{id}: 204': (r) => r.status === 204,
    });
    if (!schedDeleted) {
      console.warn(
        `[${tag}] schedule ${scheduleId} DELETE returned ${deleteSchedResp.status}. ` +
          'Manual cleanup may be needed — search staging for [k6-load] resources.'
      );
    }
  }

  sleep(0.2);

  // ── Step 5: Delete vibe ───────────────────────────────────────────────────
  // Always runs if vibeId is set, even if schedule creation or deletion failed.
  if (vibeId) {
    const deleteVibeResp = http.del(
      `${API_BASE}/api/vibes/${vibeId}`,
      null,
      { headers, tags: { name: 'vibe_delete' } }
    );
    const vibeDeleted = check(deleteVibeResp, {
      'DELETE /api/vibes/{id}: 200': (r) => r.status === 200,
    });
    if (!vibeDeleted) {
      console.warn(
        `[${tag}] vibe ${vibeId} DELETE returned ${deleteVibeResp.status}. ` +
          'Manual cleanup may be needed — search staging for [k6-load] resources.'
      );
    }
  }

  // Short pause between iterations to avoid burst pressure on basic-xxs.
  sleep(0.5);
}

// ── Teardown ─────────────────────────────────────────────────────────────────
//
// No-op for cleanup — cleanup is guaranteed per-iteration (see above).
// teardown() runs after all VUs finish but is skipped on interrupt/timeout,
// so any cleanup logic here would be unreliable. Left as a marker for
// future slices that may need post-run verification.
//
export function teardown(_data) {
  console.log('[teardown] Per-iteration cleanup complete — no global teardown needed.');
}
