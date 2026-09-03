/**
 * auth.js — Firebase + API authentication module for k6 load tests
 *
 * Replicates the exact auth flow from qa/scheduler-e2e/scripts/staging-api-qa.sh:
 *   1. POST Firebase signInWithPassword → idToken
 *   2. POST /api/auth/sync → Laravel user sync
 *
 * Usage:
 *   import { firebaseLogin, syncWithApi } from './auth.js';
 *
 *   export function setup() {
 *     const { idToken } = firebaseLogin();
 *     syncWithApi(idToken);
 *     return { idToken };
 *   }
 *
 * Called once from setup() — not per-VU — so the Firebase token is shared
 * across all VUs for the duration of the test run.
 *
 * Token lifetime: Firebase ID tokens expire after ~1 hour. For short smoke/
 * baseline runs (a few minutes), this is not an issue. For longer load runs,
 * the token will expire mid-test and calls will start returning 401. Implement
 * token refresh (via the Firebase REST API's token refresh endpoint) if runs
 * exceed 50 minutes. This is explicitly deferred for this Phase 10 foundation.
 *
 * Security (ADR-030): no credentials are logged or emitted in k6 output.
 * The idToken itself is not printed — only HTTP status codes are checked.
 */

import http from 'k6/http';
import { check } from 'k6';

const API_BASE = __ENV.K6_API_BASE || 'https://staging-api.ixora-app.app';
const FIREBASE_SIGN_IN_URL =
  'https://identitytoolkit.googleapis.com/v1/accounts:signInWithPassword';

/**
 * Sign in with Firebase REST API using email + password from environment variables.
 *
 * Required env vars:
 *   FIREBASE_API_KEY   — Firebase project API key (VITE_FIREBASE_API_KEY in front_vibes/.env)
 *   E2E_USER_EMAIL     — QA test account email
 *   E2E_USER_PASSWORD  — QA test account password
 *
 * Returns { idToken } on success. Throws (aborting the test) on failure.
 */
export function firebaseLogin() {
  const apiKey = __ENV.FIREBASE_API_KEY;
  const email = __ENV.E2E_USER_EMAIL;
  const password = __ENV.E2E_USER_PASSWORD;

  if (!apiKey || !email || !password) {
    throw new Error(
      'Missing required env vars: FIREBASE_API_KEY, E2E_USER_EMAIL, E2E_USER_PASSWORD. ' +
        'Copy .env.example to .env and fill in values before running.'
    );
  }

  const resp = http.post(
    `${FIREBASE_SIGN_IN_URL}?key=${apiKey}`,
    JSON.stringify({ email, password, returnSecureToken: true }),
    { headers: { 'Content-Type': 'application/json' }, tags: { name: 'firebase_sign_in' } }
  );

  const ok = check(resp, {
    'firebase sign-in: status 200': (r) => r.status === 200,
    'firebase sign-in: idToken present': (r) => {
      try {
        return !!JSON.parse(r.body).idToken;
      } catch {
        return false;
      }
    },
  });

  if (!ok || resp.status !== 200) {
    // Do NOT log resp.body — it may contain the idToken or error details with email.
    throw new Error(
      `Firebase sign-in failed (HTTP ${resp.status}). ` +
        'Check FIREBASE_API_KEY, E2E_USER_EMAIL, and E2E_USER_PASSWORD.'
    );
  }

  const idToken = JSON.parse(resp.body).idToken;
  return { idToken };
}

/**
 * POST /api/auth/sync — syncs the Firebase user into the Laravel user table.
 * Must be called after firebaseLogin() before any other authenticated request.
 *
 * Returns the HTTP response (caller may inspect status/body if needed).
 * Throws on non-2xx to abort the test rather than proceeding without a valid session.
 */
export function syncWithApi(idToken) {
  const resp = http.post(
    `${API_BASE}/api/auth/sync`,
    JSON.stringify({}),
    {
      headers: {
        Authorization: `Bearer ${idToken}`,
        'Content-Type': 'application/json',
        Accept: 'application/json',
      },
      tags: { name: 'auth_sync' },
    }
  );

  const ok = check(resp, { 'auth/sync: status 2xx': (r) => r.status >= 200 && r.status < 300 });

  if (!ok) {
    throw new Error(
      `POST /api/auth/sync failed (HTTP ${resp.status}). ` +
        'The token may be invalid or the API may be unreachable.'
    );
  }

  return resp;
}

/** Convenience: build the standard authenticated headers object. */
export function authHeaders(idToken) {
  return {
    Authorization: `Bearer ${idToken}`,
    Accept: 'application/json',
    'Content-Type': 'application/json',
  };
}
