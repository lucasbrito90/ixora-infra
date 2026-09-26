# ADR-044: Firebase Authentication port for the KMP shared layer

## Status

**Proposed** (2026-09-26) — governs how Firebase Authentication is integrated in the `ixora-app` Kotlin Multiplatform rebuild: which concerns live in `shared/commonMain`, which stay in the native app modules, and the contract between them.

PO authorised Phase 2 on 2026-09-25. This ADR is written as part of K13 (Phase 2 backlog definition) and is **pending PO approval**; no implementation should start before approval.

## Date

2026-09-26

---

## 1. Problem

The `shared/commonMain` module needs to call the backend API with a valid Firebase ID token as a Bearer credential on every authenticated request. That token lives inside the Firebase SDK, which cannot be placed in `commonMain`:

- The Android Firebase SDK requires the `google-services` Gradle plugin, which must be applied at the **app module** level, not at a KMP library level.
- The iOS Firebase SDK is an Apple-platform artifact — there is no `commonMain`-compatible distribution.
- The `CommonMainBoundaryTest` (K08, ADR-038 Decision 5) rejects any import of `android.*`, `androidx.*`, `java.*` or `javax.*`, so no Android-SDK call can appear in `commonMain` source.

At the same time:

- The HTTP layer lives in `commonMain` (Ktor client, K14). It must attach `Authorization: Bearer <token>` to every authenticated request and handle token expiry (401 → renew once → retry).
- Tests in `commonTest` must be able to exercise authenticated request paths without a real Firebase project — i.e., the token provider must be fakeable.

The question is: **how does `commonMain` obtain a valid, potentially refreshed Firebase ID token without depending on any Firebase SDK directly?**

---

## 2. Context

### 2.1 What Firebase does in Ixora today

Verified in `front_vibes` @ `1cf858e`:

| Concern | Owner | Evidence |
| --- | --- | --- |
| Google Sign-In, email/password sign-in, sign-up | Firebase Auth SDK | `auth.service.ts` — `GoogleAuth.signIn()`, `createUserWithEmailAndPassword`, `signInWithEmailAndPassword` |
| ID token issuance and automatic refresh | Firebase Auth SDK | `user.getIdToken()` (line 112), `user.getIdToken(true)` for force-refresh (line 213) |
| Token persistence | `@capacitor/preferences` (`firebase_id_token` key) | `useAuth.ts` line 58 (`Preferences.set`), line 54 (`Preferences.remove`); `auth.service.ts` line 297 (`Preferences.remove`) |
| Token read-back | **None found** | `grep -rn "Preferences.get" front_vibes/src` returns no result for the `firebase_id_token` key; the token is written and removed but never read back from Preferences. The Firebase SDK is the source of truth for the current token. |
| Backend sync after sign-in | `POST /api/auth/sync` | `auth.service.ts` line 143 `syncUserWithBackend` |
| Session state | `laravelUser` reactive ref in `auth.service.ts` | Composable `useAuth.ts` |
| Logout | `signOut()` + `Preferences.remove` | `auth.service.ts` line 297 |

### 2.2 Backend contract

Verified in `back_vibes` source:

**`POST /api/auth/sync`** (`routes/api.php` lines 34–36 `throttle:auth` group; `FirebaseUserSyncController.php`)

- No `firebase.auth` middleware on this route — the controller verifies the token itself.
- Rate limit: **10 requests per minute per IP** (`AppServiceProvider.php` lines 37–39).
- Bearer token absent → `401 {"message":"Missing Firebase ID token."}` (`FirebaseUserSyncController.php` line 26).
- Bearer token invalid → `401 {"message":"Invalid Firebase ID token."}` (`FirebaseUserSyncController.php` line 34).
- Success → `200` with `SyncedUserResource`: `id`, `firebase_uid`, `name`, `email`, `avatar_url`, `role`, `admin_access_status` (`SyncedUserResource.php` lines 20–26).

**All other authenticated routes** (`routes/api.php` line 39 `firebase.auth` + `throttle:api` group; `FirebaseAuthenticate.php`)

- Rate limit: **60 requests per minute per authenticated user** (or per IP if no user; `AppServiceProvider.php` lines 49–50).
- Bearer token absent → `401 {"message":"Unauthenticated."}` (`FirebaseAuthenticate.php` line 24).
- Bearer token invalid → `401 {"message":"Invalid Firebase token."}` (`FirebaseAuthenticate.php` line 30). Note: the wording differs from the sync endpoint ("Firebase token." vs "Firebase ID token.").
- Token valid but user not yet synced → `401 {"message":"User not found."}` (`FirebaseAuthenticate.php` line 36).

**The client must not depend on the text of any 401 message**, only on the status code. All three 401 bodies are documented here as observable API facts; none of them drives client logic.

**`POST /api/auth/firebase`** (`routes/api.php` line 35; `FirebaseAuthController.php`)

This is an earlier endpoint that also verifies a Firebase ID token and syncs the user, but returns a simpler response body (`message`, `user.id`, `user.firebase_uid`, `user.name`, `user.email`) rather than `SyncedUserResource`. Phase 2 uses only `POST /api/auth/sync`, which returns the complete resource needed to populate the local user model. `POST /api/auth/firebase` is not used by the new client and is noted here to avoid confusion.

**Identity vs. authorisation rule (`CLAUDE.md`):** the client sends the Firebase ID token exclusively as `Authorization: Bearer <token>`. No trusted identity fields (UID, email, name) appear in the request body on any endpoint.

### 2.3 Token storage in `front_vibes` and what the new app does differently

`front_vibes` stores the Firebase ID token in `@capacitor/preferences` (unencrypted) as a side effect of `onAuthStateChanged`, but **never reads it back** — the token is always obtained from the Firebase SDK at call time. The write exists to allow the native background audio service to read the token outside the WebView; that use case disappears with the native rebuild.

With the Firebase SDK owning the session in `androidApp`, the app no longer needs to store the token at all. §16.7 of the migration plan requires "never store tokens in common storage"; the new architecture meets this requirement **by not storing the token** rather than by adding encrypted storage. A `SecureStorage expect/actual` abstraction is therefore not needed in Phase 2 and will be considered only when a concrete consumer requires it (ADR-038 Decision 4: no anticipatory infrastructure).

This reduces the scope attributed to ADR-043 in the migration plan §13: the "armazenamento seguro do token" part of ADR-043 is not needed in Phase 2 or Phase 3, because the Firebase SDK holds the session natively. ADR-043 remains relevant for other persistent data (SQLDelight schema, DataStore for user preferences); the token storage concern is closed by this ADR.

---

## 3. Alternatives considered

### Option A — Interface in `commonMain`, native implementation injected (chosen)

`commonMain` defines a minimal port `AuthTokenProvider` that returns an ID token string (or a `DomainError` on failure) and accepts a `forceRefresh` parameter. Each app module provides the implementation via dependency injection, delegating to the platform Firebase SDK.

**Pros:**
- No Firebase SDK in `shared`; `CommonMainBoundaryTest` stays green.
- `commonTest` uses a fake implementation; no real Firebase project needed for unit tests.
- Login, Google Sign-In, logout and all UI flows that need `Activity` or `Context` remain in the app modules where they belong.
- The interface is small and stable; it does not leak Firebase types into `commonMain`.

**Cons:**
- Each app module must implement the interface (two implementations at cutover: Android in Phase 5/6, iOS in Phase 10). A test-only implementation is also needed for K16.
- The interface contract must be precise about threading and error semantics (see Decision 2).

### Option B — `expect/actual` in `shared` with the Firebase SDK

`commonMain` declares `expect fun getIdToken(forceRefresh: Boolean): String`, with `actual` implementations in `androidMain` (Firebase Android SDK) and `iosMain` (Firebase iOS SDK).

**Rejected because:**
- The `google-services` plugin must be applied at the app-module level; applying it to a KMP library produces build errors.
- The iOS `actual` cannot be compiled or verified on Windows (no Mac, no Apple toolchain for linking). The `commonMain` boundary cannot be tested end to end.
- This binds `shared` to the Firebase SDK's version and API surface, making the module harder to test and heavier to build.

The migration plan §6.7 says "`expect/actual` sobre os SDKs nativos" for Firebase Auth; the migration plan §9 says "Interface + injeção". **This ADR resolves the apparent conflict in favour of §9.** The phrase "`expect/actual` sobre os SDKs nativos" in §6.7 means "bridge to the native SDKs" — the *intent* (no third-party KMP Firebase library) — not the Kotlin `expect/actual` mechanism. §9 is the binding architectural table; §6.7 is context.

### Option C — GitLive `firebase-kotlin-sdk`

A community-maintained library that wraps Firebase SDKs and exposes a unified KMP API.

**Rejected because:** this was already rejected in the migration plan (§6.7): "wrapper comunitário; atrasa em relação aos SDKs oficiais; dependência crítica fora do controle." Placing a community wrapper at the heart of the authentication layer is an unacceptable risk.

---

## 4. Decision

### Decision 1 — `AuthTokenProvider` interface in `commonMain`

`commonMain` defines:

```kotlin
interface AuthTokenProvider {
    /**
     * Returns a valid Firebase ID token for the currently authenticated user,
     * or a [DomainError.Unauthorized] if no session exists.
     *
     * [forceRefresh] instructs the platform SDK to bypass its local cache and
     * request a fresh token from Firebase. The HTTP layer calls this only after
     * receiving a 401 on an authenticated request.
     */
    suspend fun idToken(forceRefresh: Boolean = false): Result<String, DomainError>
}
```

**Name rationale:** `AuthTokenProvider` is descriptive and domain-neutral; `idToken` is the Firebase-documented name for the credential this interface returns. No `java.*`, `android.*` or `androidx.*` type appears in the signature.

**What this interface does not do:**
- It does not expose a `Flow` of auth state — that belongs to a future `SessionStateHolder` (ADR-041 pattern) in Phase 5.
- It does not perform login, Google Sign-In or logout — those require `Activity` or iOS `UIViewController` and stay in the app modules.
- It does not know about user identity fields (name, email, UID); those come from `POST /api/auth/sync`.

### Decision 2 — Threading and error contract

`idToken` is `suspend`; it may perform network I/O when `forceRefresh = true`. Callers must be on a coroutine context that permits suspension. The implementation must:

- Return `Result.Success(token)` when a valid (or freshly obtained) token is available.
- Return `Result.Error(DomainError.Unauthorized)` when no user is signed in, or when token refresh fails after a network attempt.
- Never throw an unchecked exception across the boundary (ADR-041 Decision 5).
- Emit on whatever dispatcher is natural for the platform SDK; the Ktor auth plugin (K14) will call it from a background dispatcher.

### Decision 3 — 401 handling rule in the HTTP layer (K14)

On a 401 response from an authenticated endpoint:

1. Call `idToken(forceRefresh = true)` **once**.
2. If successful, retry the original request **once** with the new token.
3. If the retry also returns 401, or if `idToken` returns `DomainError.Unauthorized`, propagate `DomainError.Unauthorized` to the caller. No further retries.

Concurrent requests that all receive a 401 simultaneously must produce a **single** token-refresh call (single-flight / coalescing), not N parallel refreshes. The implementation of coalescing belongs to K14; this ADR fixes the rule.

No retry logic applies to any other HTTP status code.

### Decision 4 — Fake implementation for `commonTest`

A `FakeAuthTokenProvider` is provided in `commonTest` source. It is configurable: callers can set a fixed token string, force it to return `DomainError.Unauthorized`, or simulate a refresh that changes the token. This fake is the only mechanism for testing authenticated request paths without a real Firebase project in unit tests.

A separate, real-credential implementation against the Firebase Auth REST API is produced in K16 for integration testing against staging. That implementation is test-only and never ships in the production app.

### Decision 5 — `google-services.json` and credentials stay out of `shared`

`google-services.json` (Android) and `GoogleService-Info.plist` (iOS) are placed in the respective app modules. They must never appear in the `shared` module or in any file tracked by `shared`'s build configuration. The `google-services` Gradle plugin is applied at the app-module level only.

### Decision 6 — Scope of Phase 2

Phase 2 implements:
- `AuthTokenProvider` interface in `commonMain` (this ADR, K13).
- Ktor client in `commonMain` with the Bearer plugin that calls `idToken(forceRefresh = false)` on every authenticated request and applies the 401 rule (K14).
- Read-only repositories: user sync (`POST /api/auth/sync`), vibes list, sounds list (K15).
- Integration proof against staging (K16).

Phase 2 does **not** implement:
- Login UI or Google Sign-In (Phase 5/6, requires Compose and `Activity`).
- Logout (Phase 5/6).
- Token storage of any kind (not needed; Firebase SDK holds the session).
- `SecureStorage expect/actual` (deferred to when a concrete consumer exists — ADR-043 or later).
- OTel instrumentation (question 5 of §15 remains open; premissa desta fase: nenhuma instrumentação OTel entra na Fase 2).

---

## 5. Consequences

**Positive**

- `shared` remains free of Firebase types; `CommonMainBoundaryTest` continues to enforce the boundary.
- Authenticated request paths are fully testable in `commonTest` without network access.
- The interface is small and has one implementation per platform — a manageable maintenance surface.
- The 401-handling rule is fixed before the first HTTP call is written, which is the cheapest moment to fix it.
- Token storage is eliminated as a Phase 2 concern, simplifying the implementation and closing the §16.7 gap without adding new abstractions.

**Negative, accepted**

- Two real implementations of `AuthTokenProvider` will exist at cutover (Android in Phase 5/6, iOS in Phase 10); a third test-only implementation is needed for K16. This is the direct cost of Option A.
- Integration tests against staging (K16) require a disposable Firebase account or a REST-API-based token and cannot be run in CI without secrets management.
- The Ktor plugin that calls `idToken` adds a small latency cost on the first authenticated call if the SDK needs to refresh the cache — accepted, because it happens transparently and infrequently.

**Risks**

- **SDK threading model.** The Firebase Android SDK's `getIdToken` is asynchronous; the implementation must bridge it to a `suspend` function correctly (via `suspendCancellableCoroutine` or `Tasks.await`). Getting this wrong causes coroutine leaks. Addressed in K14.
- **Concurrent 401 storms.** Without single-flight coalescing, multiple simultaneous requests can each trigger a token refresh. The rule in Decision 3 requires coalescing; K14 owns the mechanism.
- **No login in Phase 2.** Authenticated requests in Phase 2 can only be tested with a manually provisioned token (K16) or a fake (unit tests). This is a deliberate scope decision, not an oversight.

---

## 6. Relationship to other ADRs

- **[ADR-001](ADR-001-firebase-auth-laravel-sync.md)** — the identity/authorisation split and the Firebase+Laravel contract this ADR implements: Firebase issues the JWT; Laravel verifies it and owns authorisation. This ADR extends ADR-001 to the KMP context without changing the contract.
- **[ADR-038](ADR-038-kmp-shared-layer.md)** — the boundary authority. Decision 5 of ADR-038 prohibits `android.*`, `androidx.*`, `java.*` and `javax.*` in `commonMain`; this ADR is consistent: no Firebase SDK type appears in the `AuthTokenProvider` interface.
- **[ADR-041](ADR-041-state-swift-interop.md)** — the state and error contract. `Result<T, DomainError>` is the domain-layer return type (ADR-041 Decision 5); `AuthTokenProvider` uses it.
- **ADR-043** — the migration plan §13 listed "armazenamento seguro do token" as part of ADR-043's scope. Decision 6 of this ADR reduces that scope: token storage is not needed because the Firebase SDK holds the session. ADR-043 remains relevant for other persistence concerns (SQLDelight, DataStore).
- **[ADR-042](ADR-042-migration-repository.md)** — migration strategy. This ADR is consistent with Phase 2 scope and does not alter the migration sequence.

---

## 7. Sources

Code inspected 2026-09-26 in `front_vibes` @ `1cf858e` (confirmed: `git -C front_vibes rev-parse --short HEAD`):

- `src/services/auth.service.ts` — `getRequiredIdToken` (line 100), `user.getIdToken()` (line 112), `user.getIdToken(true)` force-refresh (line 213), `syncUserWithBackend` (line 143), `FIREBASE_TOKEN_PREFS_KEY` (line 22), `Preferences.remove` (line 297).
- `src/composables/useAuth.ts` — `Preferences.set` (line 58), `Preferences.remove` (line 54). Confirmed by `grep -rn "Preferences.get" front_vibes/src`: no `get` call for `firebase_id_token`; token is never read back from Preferences.

Code inspected 2026-09-26 in `back_vibes`:

- `routes/api.php` lines 34–36: `throttle:auth` group containing `POST /api/auth/firebase` and `POST /api/auth/sync`; line 39: `firebase.auth` + `throttle:api` group for all other authenticated routes.
- `app/Http/Controllers/Api/FirebaseUserSyncController.php` lines 22–40: `bearerToken()`, 401 messages ("Missing Firebase ID token." / "Invalid Firebase ID token."), `SyncedUserResource::make`.
- `app/Http/Controllers/Api/FirebaseAuthController.php` lines 19–46: older endpoint at `POST /api/auth/firebase`; returns simpler body (`message`, `user.id/firebase_uid/name/email`).
- `app/Http/Middleware/FirebaseAuthenticate.php` lines 23–36: 401 messages ("Unauthenticated." / "Invalid Firebase token." / "User not found.").
- `app/Http/Resources/SyncedUserResource.php` lines 20–26: `id`, `firebase_uid`, `name`, `email`, `avatar_url`, `role`, `admin_access_status`.
- `app/Providers/AppServiceProvider.php` lines 37–50: `auth` limiter 10/min per IP; `api` limiter 60/min per user (or IP).

Internal: [`kmp-migration-plan.md`](../architecture/mobile/kmp-migration-plan.md) §6.7 (Firebase strategy), §9 (integration table), §11.2 (Phase 2 scope), §13 (ADR list), §16.7 (secure storage requirement), §16.19–16.21 (session state, logout, security), §17.1 (Phase 2 authorisation). [ADR-001](ADR-001-firebase-auth-laravel-sync.md), [ADR-038](ADR-038-kmp-shared-layer.md), [ADR-041](ADR-041-state-swift-interop.md), [ADR-042](ADR-042-migration-repository.md). `CLAUDE.md` (workspace root): identity vs. authorisation split rule.
