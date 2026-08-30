/**
 * read-flows-smoke.js — GET-only smoke / baseline scenario for back_vibes staging API
 *
 * Phase 10 — Performance Validation & Load Testing (Phase 10 foundation, read-only slice)
 *
 * ENVIRONMENT WARNING — READ BEFORE RUNNING WITH HIGH VUs
 * --------------------------------------------------------
 * Staging runs on App Platform basic-xxs (smallest tier, shared compute).
 * Postgres is db-s-1vcpu-1gb, node_count=1. This is NOT sized for capacity
 * testing — it is a cost-minimum environment shared with QA E2E, dashboards,
 * and real Phase 9 alerting. Default options below are deliberately conservative.
 *
 * Do NOT increase VUs / duration without reviewing staging load and confirming
 * with the operator that the environment can sustain the additional load.
 *
 * SCOPE
 * -----
 * This script exercises READ-ONLY endpoints only (GET). No data is created,
 * modified, or deleted. Safe to run against staging shared test data.
 *
 * Endpoints covered:
 *   GET /api/health          (no auth — baseline connectivity check)
 *   GET /api/vibes           (firebase.auth — returns authenticated user's vibes)
 *   GET /api/schedules       (firebase.auth — returns authenticated user's schedules)
 *   GET /api/sounds          (firebase.auth — catalog, shared read-only data)
 *   GET /api/preset-vibes    (firebase.auth — catalog, shared read-only data)
 *
 * PII SAFETY (ADR-030)
 * --------------------
 * All firebase.auth endpoints scope results to auth()->id() (confirmed in
 * back_vibes VibeController, ScheduleController, etc.). The test account's own
 * data is fetched; no other users' data is returned. No PII is logged or emitted.
 *
 * RUNNING
 * -------
 * Smoke (safe, minimal — this is what Phase 10.1 ran for acceptance):
 *   K6_VUS=1 K6_ITERATIONS=3 k6 run scripts/read-flows-smoke.js
 *
 * Baseline (conservative, a few minutes):
 *   k6 run scripts/read-flows-smoke.js  ← uses default options below
 *
 * With Prometheus remote-write output (requires k6 on the observability host,
 * or an SSH tunnel to 127.0.0.1:9090 — see README.md §Prometheus):
 *   K6_PROMETHEUS_RW_SERVER_URL=http://127.0.0.1:9090/api/v1/write \
 *   k6 run -o experimental-prometheus-rw scripts/read-flows-smoke.js
 */

import http from 'k6/http';
import { check, sleep } from 'k6';
import { firebaseLogin, syncWithApi, authHeaders } from './auth.js';

const API_BASE = __ENV.K6_API_BASE || 'https://staging-api.ixora-app.app';

// ── Options ──────────────────────────────────────────────────────────────────
//
// Default: 3 VUs × 10 iterations = 30 total requests per endpoint.
// Conservative for basic-xxs staging.
//
// Override at runtime:
//   K6_VUS=1 K6_ITERATIONS=3 k6 run ...   ← smoke
//   K6_VUS=5 K6_ITERATIONS=20 k6 run ...  ← light baseline (operator decision)
//
export const options = {
  vus: __ENV.K6_VUS ? parseInt(__ENV.K6_VUS, 10) : 3,
  iterations: __ENV.K6_ITERATIONS ? parseInt(__ENV.K6_ITERATIONS, 10) : 10,

  // Thresholds: conservative for staging.
  // p(95) < 3s: allows for basic-xxs cold-start latency.
  // error rate < 5%: a single intermittent 5xx is tolerable; sustained errors are not.
  thresholds: {
    http_req_duration: ['p(95)<3000'],
    http_req_failed: ['rate<0.05'],
    checks: ['rate>0.95'],
  },
};

// ── Setup — runs once before all VUs ─────────────────────────────────────────
//
// Firebase login + auth/sync are executed a single time here.
// The resulting idToken is returned and passed to every VU iteration.
//
// If login fails, setup() throws and k6 aborts the entire test — no calls
// are made without a valid token.
//
export function setup() {
  console.log(`[setup] Authenticating against Firebase...`);
  const { idToken } = firebaseLogin();
  console.log('[setup] Firebase login OK');

  syncWithApi(idToken);
  console.log('[setup] /api/auth/sync OK');

  return { idToken };
}

// ── Default function — one iteration per VU ──────────────────────────────────
export default function (data) {
  const headers = authHeaders(data.idToken);

  // 1. Health check (no auth — baseline connectivity)
  const health = http.get(`${API_BASE}/api/health`, {
    tags: { name: 'health' },
  });
  check(health, {
    'GET /api/health: 200': (r) => r.status === 200,
  });

  sleep(0.3);

  // 2. Vibes list (auth-scoped to the test account's own data)
  const vibes = http.get(`${API_BASE}/api/vibes`, {
    headers,
    tags: { name: 'vibes_list' },
  });
  check(vibes, {
    'GET /api/vibes: 200': (r) => r.status === 200,
    'GET /api/vibes: has data key': (r) => {
      try {
        return Array.isArray(JSON.parse(r.body).data);
      } catch {
        return false;
      }
    },
  });

  sleep(0.3);

  // 3. Schedules list
  const schedules = http.get(`${API_BASE}/api/schedules`, {
    headers,
    tags: { name: 'schedules_list' },
  });
  check(schedules, {
    'GET /api/schedules: 200': (r) => r.status === 200,
  });

  sleep(0.3);

  // 4. Sounds catalog (shared catalog data — not user-scoped, but no PII)
  const sounds = http.get(`${API_BASE}/api/sounds`, {
    headers,
    tags: { name: 'sounds_list' },
  });
  check(sounds, {
    'GET /api/sounds: 200': (r) => r.status === 200,
  });

  sleep(0.3);

  // 5. Preset vibes catalog
  const presets = http.get(`${API_BASE}/api/preset-vibes`, {
    headers,
    tags: { name: 'preset_vibes_list' },
  });
  check(presets, {
    'GET /api/preset-vibes: 200': (r) => r.status === 200,
  });

  // Pacing: short pause between iterations to avoid burst pressure on basic-xxs.
  sleep(0.5);
}

// ── Teardown — runs once after all VUs complete ───────────────────────────────
//
// Nothing to clean up: this scenario is read-only.
// Placeholder in case future slices add teardown logic.
//
export function teardown(_data) {
  console.log('[teardown] Read-only scenario — no cleanup needed.');
}
