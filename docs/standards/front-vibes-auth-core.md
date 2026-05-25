# front_vibes authentication core — Firebase identity, Laravel authorization

**Status:** Active engineering standard (source of truth)  
**Scope:** Mobile app authentication and API identity (`front_vibes`); backend contract shared with `back_vibes` and aligned with `ixora-admin`  
**Stack:** Ionic 8 + Vue 3 + Capacitor, Firebase Auth, Laravel API

---

## Purpose

Define the **mandatory authentication architecture** for the Ixora mobile app: how users sign in, how identity is established, how the backend is synchronized, how API requests are authorized, and how sessions behave on startup, logout, and error paths.

**Firebase Auth is the identity provider.** **Laravel validates Firebase ID tokens**, creates or updates local users, and **owns authorization and business rules.** The mobile app **never stores backend credentials** (API keys, Spaces keys, Laravel secrets).

This document is the **source of truth** for humans and AI-assisted work on auth. Cursor rules and repo copies should stay aligned.

---

## Scope

### In scope

- Sign-in flows (Google, email/password, sign-up, password reset)
- Firebase ↔ Laravel sync (`POST /api/auth/sync`)
- Bearer token usage on API calls
- Session restoration on cold start
- Token persistence strategy
- Native vs web Google Sign-In differences
- Router guards and post-auth navigation
- Error handling and failed-sync behaviour
- Security boundaries (what the client may and may not trust)

### Out of scope

- Admin panel UI specifics (`ixora-admin` — same Firebase + Laravel pattern, Nuxt middleware)
- Firebase Console / OpenTofu secret provisioning (see `ixora-infra` infra docs)
- Offline audio / vibe cache (see [`../architecture/audio/audio-cache.md`](../architecture/audio/audio-cache.md))
- Ionic tab routing layout beyond auth transitions

### Applies to

| Layer | Location |
| --- | --- |
| Mobile composable | `src/composables/useAuth.ts` |
| Auth service | `src/services/auth.service.ts` |
| Firebase init | `src/services/firebase.ts` |
| Router guards | `src/router/index.ts` |
| API services | `src/services/*.service.ts` (Bearer via `getIdToken`) |
| Backend sync | `back_vibes` — `POST /api/auth/sync`, `firebase.auth` middleware |

---

## Authentication Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│  front_vibes (Capacitor / WebView)                              │
│                                                                 │
│  SignInPage / SignUpPage / useAuth                              │
│       │                                                         │
│       ▼                                                         │
│  Firebase Auth (identity)                                       │
│       │  ID token (JWT)                                         │
│       ▼                                                         │
│  POST /api/auth/sync  ──Bearer──►  Laravel                      │
│       │                              VerifyFirebaseIdToken      │
│       │                              SyncFirebaseUser (local row) │
│       ▼                                                         │
│  laravelUser (in-memory) + Firebase session                     │
│       │                                                         │
│       ▼                                                         │
│  API calls: Authorization: Bearer <Firebase ID token>           │
└─────────────────────────────────────────────────────────────────┘
```

| Responsibility | Owner |
| --- | --- |
| Identity (who signed in) | **Firebase Auth** — UID, email, profile claims |
| Canonical identity key | **`firebase_uid`** (Firebase `sub` / `User.uid`) |
| Local user record | **Laravel** — created/updated on sync from **verified** token claims |
| Authorization (roles, admin, policies) | **Laravel** — `role`, `admin_access_status`, middleware, policies |
| API authentication | **Laravel** — `firebase.auth` verifies Bearer token, loads user by `firebase_uid` |
| Client-side “logged in” | Firebase `currentUser` + successful sync for protected app use |

**No direct trust of client-provided identity data** beyond what Laravel extracts from a **cryptographically verified** Firebase ID token. The sync endpoint accepts **no request-body identity fields** — only `Authorization: Bearer <token>`.

---

## Authentication Flow

### Mandatory sequence (all sign-in methods)

```
1. User authenticates with Firebase (Google, email/password, or sign-up)
2. App obtains Firebase ID token (user.getIdToken())
3. App calls syncUserWithBackend(idToken, firebaseUid)
   → POST /api/auth/sync with Authorization: Bearer <idToken>
4. Laravel verifies token → creates/updates User → returns profile JSON
5. App stores laravelUser in memory; useAuth persists token mirror to Preferences
6. Navigate to authenticated route (see Session Rules — window.location.replace)
```

If step 3 **fails**, the app **aborts the Firebase session** (`signOut`, native `GoogleAuth.signOut` when applicable) — partial login without a Laravel user is **not** allowed.

### Router guard flow (every navigation)

```
beforeEach:
  waitForAuthState()     ← Firebase onAuthStateChanged (cold start)
  if requiresAuth && user:
    ensureLaravelUserSynced(user)   ← sync if not cached for this UID
    on failure → logout, toast, redirect /sign-in
  if requiresAuth && !user → /sign-in
  if publicOnly && user → /home
```

### Public vs protected routes

| Meta | Behaviour |
| --- | --- |
| `requiresAuth: true` | Requires Firebase user **and** successful Laravel sync |
| `publicOnly: true` | Redirect authenticated users to `/home` |

Auth views (`/sign-in`, `/sign-up`, `/sign-in-sign-up`, forgot-password) are **public-only**. Authenticated app lives under `/` + tab children and full-screen routes (e.g. vibe player).

---

## Token Strategy

### Firebase ID token (primary)

- **All Laravel API calls** use `Authorization: Bearer <Firebase ID token>`.
- Obtained via **`user.getIdToken()`** (Firebase SDK **auto-refreshes** expired tokens when possible).
- **Sign-up:** after `updateProfile`, the app calls **`getIdToken(true)`** once to force a fresh token before sync so display-name claims are available to Laravel.

### In-memory Laravel profile

- **`laravelUser`** (`shallowRef` in `auth.service.ts`) holds the last successful sync response (`id`, `firebase_uid`, `name`, `email`, `avatar_url`, `role`, `admin_access_status`).
- **`ensureLaravelUserSynced`** caches by Firebase UID for the session — skips redundant sync when UID matches and profile is loaded.

### Preferences mirror (secondary)

| Key | Value | When |
| --- | --- | --- |
| `firebase_id_token` (`FIREBASE_TOKEN_PREFS_KEY`) | Latest ID token string | Set after successful login/sign-up in `useAuth` |
| — | Removed | On logout |

**Rules:**

- Persist tokens **only** with **`@capacitor/preferences`**. ❌ **Never `localStorage`** for auth tokens.
- **Primary session restoration** is **Firebase Auth SDK persistence** (`onAuthStateChanged`), not reading this Preferences key.
- The Preferences entry is an **auxiliary mirror** for native/offline-adjacent flows; **API authorization always uses live `getIdToken()`** from the current Firebase user.

### What the mobile app must not store

- Laravel passwords, Sanctum secrets, or session cookies as the auth mechanism
- DigitalOcean Spaces credentials
- Service account JSON or Firebase Admin SDK keys
- Self-asserted user id / email in API bodies in place of Bearer verification

---

## Firebase Integration

### Client configuration

Firebase is initialized in `src/services/firebase.ts` from **`import.meta.env`**:

- `VITE_FIREBASE_API_KEY`
- `VITE_FIREBASE_AUTH_DOMAIN`
- `VITE_FIREBASE_PROJECT_ID`
- `VITE_FIREBASE_STORAGE_BUCKET`
- `VITE_FIREBASE_MESSAGING_SENDER_ID`
- `VITE_FIREBASE_APP_ID`

`getAuth(firebaseApp)` is the single Auth instance used app-wide.

### Auth state subscription

- **`useAuth`:** `onAuthStateChanged` → updates `currentUser` ref.
- **`router`:** `waitForAuthState()` resolves once Firebase reports initial auth state (restores session on cold start before guards run).

### Supported Firebase methods (via `useAuth` / `authService`)

| Method | Purpose |
| --- | --- |
| `loginWithGoogle` | Google Sign-In (native or web) |
| `loginWithEmail` | Email/password sign-in |
| `signUpWithEmail` | Registration + optional display name |
| `requestPasswordReset` | Firebase password reset email |
| `logout` | Full sign-out (see Session Rules) |
| `getCurrentUser` | Current Firebase user |
| `getIdToken` | Token for API calls |

---

## Backend Integration

### Sync endpoint

| | |
| --- | --- |
| **Route** | `POST /api/auth/sync` |
| **Auth** | `Authorization: Bearer <Firebase ID token>` |
| **Body** | Empty — no client-supplied identity fields |
| **Success** | JSON `{ data: LaravelUser }` |
| **Failure** | `401` missing/invalid token; sync errors surfaced as `LaravelSyncError` |

**Laravel behaviour:**

1. **`VerifyFirebaseIdToken`** validates the JWT (Kreait Firebase Admin).
2. **`SyncFirebaseUser`** upserts `User` by **`firebase_uid`** from verified claims (`sub`).
3. Profile fields (`name`, `email`, `avatar_url`) come from **token claims only** (`FirebaseTokenClaims`).

### Protected API routes

| Middleware | Role |
| --- | --- |
| `firebase.auth` | Verify Bearer token; load `User` where `firebase_uid` matches claims; `Auth::login($user)` |
| `admin.approved` | Admin write routes only — not used by standard mobile vibe flows |

Mobile catalog/vibe API calls use **`firebase.auth`** only. Admin approval is relevant for **`ixora-admin`**, not typical mobile users.

### API service pattern (mobile)

Each service that calls Laravel:

```typescript
const token = await authService.getIdToken();
// fetch(..., { headers: { Authorization: `Bearer ${token}`, Accept: 'application/json' } })
```

**Backend owns authorization and business rules** — the client sends identity proof (token); Laravel enforces policies, ownership, and admin gates.

---

## Google Sign-In Rules

### Platform split (required)

| Platform | Implementation |
| --- | --- |
| **Native (Android/iOS Capacitor)** | `@codetrix-studio/capacitor-google-auth` → `GoogleAuth.signIn()` → ID token → `GoogleAuthProvider.credential(idToken)` → `signInWithCredential(auth, …)` |
| **Web / dev browser** | `signInWithPopup(auth, new GoogleAuthProvider())` |

**Do not** rely on Firebase `signInWithPopup` inside the Android WebView — native plugin path is **required** on device.

### Native configuration (mandatory)

Documented in [`../architecture/mobile/android-native-customizations.md`](../architecture/mobile/android-native-customizations.md):

1. Firebase Android app + package name
2. **SHA-1** (debug + release) in Firebase Console
3. **`android/app/google-services.json`**
4. Google provider enabled in Firebase Authentication
5. **`VITE_GOOGLE_WEB_CLIENT_ID`** = OAuth **Web Client ID** (not Android client ID)
6. `GoogleAuth.initialize({ clientId, scopes, grantOfflineAccess: false })` in **`main.ts`** at startup
7. `capacitor.config.ts` — `GoogleAuth.serverClientId` aligned with Web Client ID

**Install:** `npm install --legacy-peer-deps` for `capacitor-google-auth` peer mismatch with Capacitor 8 — intentional; test sign-in on **physical device** after dependency changes.

### Native sign-in failure modes

- Missing ID token from plugin → configuration error (`VITE_GOOGLE_WEB_CLIENT_ID`, Firebase console)
- User cancellation → friendly message (`Sign-in was cancelled.`)
- After Firebase success, **Laravel sync must still succeed** or session is rolled back

---

## Session Rules

### Post-auth navigation (critical)

After **login**, **sign-up**, or **logout**, use **`window.location.replace('/route')`**.

❌ **Do not** use `router.replace`, `ionRouter.replace`, or `router.push` for transitions between **public auth routes** and **authenticated tab/nested routes** — `ion-router-outlet` cannot reliably transition between flat public routes and nested tab routes.

```typescript
// ✅ CORRECT
await loginWithEmail(email, password);
window.location.replace('/home');

// ❌ WRONG
await loginWithEmail(email, password);
ionRouter.replace('/home');
```

**Logout:** `SettingsPage` uses `window.location.replace('/sign-in-sign-up')` after `logout()`.

### Logout flow (required order)

1. Native: **`GoogleAuth.signOut()`** (best-effort; ignore if never used Google)
2. **`clearBackendSession()`** — reset in-memory `laravelUser` / sync cache
3. **`Preferences.remove({ key: FIREBASE_TOKEN_PREFS_KEY })`**
4. **`signOut(auth)`** — Firebase session cleared

### Auth UI structure

- **`SignInPage`** and **`SignUpPage`** are **standalone views** — do not split into subcomponents without explicit product need.
- **`useAuth`** exposes `loading`, `error`, `isAuthenticated`, `laravelUser` (readonly).

---

## Security Rules

### Identity and trust boundaries

| Rule | Requirement |
| --- | --- |
| Identity provider | **Firebase Auth only** for end-user identity |
| Canonical key | **`firebase_uid`** links Firebase user ↔ Laravel `users.firebase_uid` |
| Token verification | Laravel **must** verify every Bearer token server-side |
| Sync input | **No** trusting email/uid/name from JSON body — **verified JWT claims only** |
| Partial sessions | **Forbidden** — failed Laravel sync **rolls back** Firebase login |
| Protected routes | Require Firebase user **and** successful **`ensureLaravelUserSynced`** |
| API authorization | Laravel middleware + policies — client does not decide access |
| Secrets on device | **No** backend credentials, Spaces keys, or Admin SDK material |

### Client hardening

- Do not bypass sync and call protected APIs with Firebase-only state.
- Do not store tokens in `localStorage`.
- Do not send user id or email as authoritative identity headers without Bearer token verification on the server.
- Do not embed long-lived Laravel API keys in the mobile bundle.

### Admin / elevated access

Mobile users are standard Firebase-authenticated users. **Admin write paths** (`admin.approved`) are for **`ixora-admin`**. Mobile must not assume admin role from client state alone — use Laravel-returned `role` / `admin_access_status` if UI ever gates admin features.

---

## Offline / Startup Behaviour

### Cold start (typical online)

1. App loads → Firebase SDK restores persisted auth session (platform-native Firebase persistence).
2. Router **`waitForAuthState()`** waits for first `onAuthStateChanged` before guards.
3. User navigates to protected route → **`ensureLaravelUserSynced`** runs (network **`POST /api/auth/sync`** if not cached for UID).
4. API calls use **`getIdToken()`** — Firebase refreshes token when needed.

### Sync failure on protected navigation

If Firebase user exists but **Laravel sync fails** (network, 401, invalid payload):

- Router calls **`authService.logout()`**
- Toast: **`LARAVEL_SYNC_FAILURE_MESSAGE`** (`We could not finish setting up your account. Please try again.`)
- Redirect **`/sign-in`**

This prevents authenticated routing without a valid backend user row.

### Offline considerations

- **Firebase session** may restore offline; **first protected navigation** or API call needing sync/token refresh may **fail without network**.
- **Preferences token mirror** is **not** a substitute for Firebase session restoration and is **not** read on startup for guard logic.
- Offline vibe/audio features (separate architecture) may use cached content but **do not change** the auth model — API calls still require valid Bearer tokens when online.

### Token refresh

- Default API usage: **`getIdToken()`** without force refresh — Firebase SDK refreshes when expired.
- **Force refresh:** `getIdToken(true)` used after sign-up profile update before sync; extend only with clear need (e.g. custom claims propagation).

---

## Risks

| Risk | If ignored |
| --- | --- |
| Skip Laravel sync after Firebase login | Orphan Firebase sessions; API 401 “User not found”; inconsistent app state |
| Trust client body for identity on sync | Spoofing — must verify JWT server-side only |
| `localStorage` for tokens | XSS exposure; violates platform persistence standard |
| `router.push` after login/logout | Broken Ionic outlet; stuck or blank screens |
| Web popup Google Sign-In on Android | Unreliable sign-in inside WebView |
| Wrong OAuth client ID (Android vs Web) | Native Google returns no ID token |
| Missing SHA-1 / `google-services.json` | Native Google Sign-In fails on device |
| Stale token without refresh path | 401 on API — use `getIdToken()`, not Preferences mirror alone |
| Unhandled auth errors in views | Uncaught promise rejections — `useAuth` sets `error` but views must try/catch |
| Store Spaces/Laravel secrets in app | Credential leak from APK / bundle |

---

## Validation

### Sign-in / sign-up

- [ ] Email login → Firebase user → sync → `/home` via **`window.location.replace`**
- [ ] Google **native** sign-in on physical Android device (not emulator-only assumption)
- [ ] Google **web** popup works in browser dev
- [ ] Sign-up with display name → Laravel `name` updated from synced claims
- [ ] Failed sync (stop API / invalid token) → Firebase session cleared; user returned to sign-in
- [ ] Cancelled Google sign-in → friendly error, no partial session

### Session / startup

- [ ] Kill app while logged in → reopen → Firebase restores user → protected route works after sync
- [ ] Logout → Preferences key removed → Firebase user null → public route accessible
- [ ] Protected route without user → redirect `/sign-in`
- [ ] Public auth route while logged in → redirect `/home`

### API / security

- [ ] API requests include `Authorization: Bearer <token>`
- [ ] `POST /api/auth/sync` without Bearer → **401**
- [ ] Invalid/expired token on protected route → **401**
- [ ] No backend secrets in mobile env beyond Firebase **client** config + public API base URL
- [ ] Token stored in **Preferences only**, not `localStorage`

### Error handling (views)

- [ ] Auth views wrap `login*` / `signUp*` in **try/catch** — `error.value` displayed; no unhandled rejection
- [ ] `LaravelSyncError` shows user-facing sync message

### Regression (native Android)

- [ ] Google Sign-In after `npm install --legacy-peer-deps`
- [ ] `GoogleAuth.initialize` runs at startup when `VITE_GOOGLE_WEB_CLIENT_ID` set

---

## Related Files

| Location | Path |
| --- | --- |
| **Central (this repo)** | `docs/standards/front-vibes-auth-core.md` (this file) |
| | `docs/standards/front-vibes-ionic-routing.md` |
| | `docs/standards/git-flow.md` |
| | `docs/architecture/mobile/android-native-customizations.md` — Google Sign-In native setup |
| **Cursor workspace** | `.cursor/rules/front-vibes-auth-core.mdc` — keep aligned |
| **front_vibes** | `src/composables/useAuth.ts` |
| | `src/services/auth.service.ts` |
| | `src/services/firebase.ts` |
| | `src/router/index.ts` |
| | `src/main.ts` — `GoogleAuth.initialize` |
| | `src/views/SignInPage.vue`, `SignUpPage.vue`, `SettingsPage.vue` |
| | `capacitor.config.ts` |
| **back_vibes** | `app/Http/Controllers/Api/FirebaseUserSyncController.php` |
| | `app/Http/Middleware/FirebaseAuthenticate.php` |
| | `app/Http/Middleware/EnsureAdminApproved.php` |
| | `app/Services/Auth/SyncFirebaseUser.php` |
| | `app/Services/Firebase/FirebaseTokenClaims.php` |
| | `routes/api.php` — `/auth/sync`, `firebase.auth` groups |
| | `tests/Feature/FirebaseUserSyncTest.php` |
| **ixora-admin (parallel pattern)** | `services/api/auth.service.ts`, `composables/useFirebaseAuth.ts` |

When authentication behaviour changes, update **this file first**, then sync `.cursor/rules/front-vibes-auth-core.mdc` and verify mobile + backend tests.
