# ADR-001: Firebase Authentication with Laravel user sync

## Status

**Accepted** — reflects the **current shipped architecture** across `front_vibes`, `ixora-admin`, and `back_vibes`.

## Date

2026-05-23

## Context

Ixora is a multi-client product (mobile app, admin panel, Laravel API) over a **relational domain**: vibes, catalog sounds, cover bundles, presets, ownership, and policy-gated mutations. Users need **frictionless sign-in** on mobile — including **Google Sign-In** — without the backend team operating a custom password store, email verification stack, or OAuth broker for every provider.

At the same time, **business rules must live in Laravel**: `user_id` foreign keys, `VibePolicy`, admin approval gates, catalog authorization, and PostgreSQL as the system of record for compositions and assets metadata.

The team needed a split where:

- **Identity** (who authenticated, password reset, Google flows) is delegated to a managed provider.
- **Authorization and domain data** remain under Laravel control with normal Eloquent models and policies.
- **Mobile and admin** share one backend contract — not parallel auth stacks.

Alternatives such as Laravel-only session cookies, Sanctum-first mobile tokens, or migrating to Cognito/Auth0 were considered early; **Firebase Auth + JWT verification + local user sync** was chosen and is **in production use today**.

---

## Decision

**Ixora uses Firebase Authentication as the identity provider while Laravel remains the authoritative business and API backend.**

### Identity layer — Firebase Auth

Firebase handles **end-user authentication** only:

| Capability | Owner |
| --- | --- |
| Google Sign-In | Firebase Auth (+ native Google plugin on Capacitor) |
| Email / password sign-in and sign-up | Firebase Auth |
| Password reset emails | Firebase Auth |
| Provider-linked identity (`sub` / UID) | Firebase Auth |

Clients obtain a **Firebase ID token (JWT)** after successful Firebase sign-in. Firebase is the **identity layer**, not the business data layer.

### API layer — Laravel

| Step | Behaviour |
| --- | --- |
| 1 | Mobile or admin authenticates with **Firebase first** |
| 2 | Client calls **`POST /api/auth/sync`** with **`Authorization: Bearer <Firebase ID token>`** — **empty body** |
| 3 | Laravel **`VerifyFirebaseIdToken`** (Kreait Firebase Admin) validates the JWT |
| 4 | Laravel **`SyncFirebaseUser`** creates or updates the local **`users`** row from **verified claims only** |
| 5 | Subsequent API calls send the same **Bearer Firebase ID token** |
| 6 | Middleware **`firebase.auth`** verifies JWT, loads **`User`** by **`firebase_uid`**, **`Auth::login($user)`** for the request |
| 7 | Controllers enforce **`authorize()`**, policies, and query scoping — Laravel remains **authoritative** for authorization |

### Canonical identity mapping

| Field | Role |
| --- | --- |
| **`firebase_uid`** | Canonical **external identity link** — matches Firebase JWT `sub` / `User.uid` |
| **`users.id` (`user_id`)** | Internal **primary key** for all relational FKs (`vibes.user_id`, etc.) |

Clients **must not** send trusted identity fields (email, name, uid) in request bodies for auth purposes. Laravel trusts **JWT claims only** after cryptographic verification.

### Shared client architecture

- **`front_vibes`** and **`ixora-admin`** both use Firebase client SDKs, sync via **`/api/auth/sync`**, and attach **Bearer Firebase ID tokens** to Laravel API calls.
- **Admin-only routes** add **`admin.approved`** middleware on top of **`firebase.auth`** — same identity stack, stricter authorization gate.

### Explicit non-decisions

| Topic | Stance |
| --- | --- |
| **Firebase Realtime Database / Firestore for core domain** | **Not used** — PostgreSQL + Laravel own relational data |
| **Cognito / Auth0 migration** | **Not planned currently** |
| **Client direct upload to Spaces** | Unrelated to auth — remains Laravel-only (see storage strategy) |

### API access model (request scope)

Laravel does **not** issue a separate long-lived Sanctum/API key for standard clients today. **API access** is:

- **Proof:** valid Firebase ID token on each request (SDK refresh on client).
- **Session:** request-scoped Laravel `Auth` user loaded from **`firebase_uid`** after verification.
- **Authorization:** policies, roles, and middleware on the local **`User`** record.

This is Laravel’s **auth/session model for the HTTP request** — distinct from Firebase’s **identity session**, but **coupled** via JWT verification.

---

## Consequences

### Positive

| Outcome | Why it matters |
| --- | --- |
| **Mobile-native auth simplicity** | Firebase SDKs + Capacitor Google Auth cover native and web paths |
| **Google Sign-In support** | OAuth complexity stays in Firebase/Google console configuration |
| **Reduced password handling burden** | No Laravel password hashing, reset tokens, or breach surface for primary mobile login |
| **Laravel business ownership** | Vibes, sounds, policies, and admin gates stay in familiar Laravel patterns |
| **Relational domain fit** | `user_id` PK, FKs, and transactions unchanged |
| **Policy enforcement** | `VibePolicy`, catalog gates, `admin.approved` remain authoritative |
| **Multi-platform consistency** | One sync endpoint and one Bearer scheme for mobile and admin |

### Negative / tradeoffs

| Tradeoff | Impact |
| --- | --- |
| **Token sync complexity** | Clients must sync Firebase → Laravel after every sign-in; guards call **`ensureLaravelUserSynced`**; failed sync rolls back Firebase session on mobile |
| **Dual auth lifecycle** | Two systems to reason about: Firebase session persistence + Laravel user row + token refresh |
| **Dependency on Firebase availability** | Sign-in and token refresh depend on Firebase; API calls fail if tokens cannot be refreshed or Firebase is degraded |
| **JWT verification maintenance** | Kreait/Firebase Admin credentials, clock skew, key rotation, and middleware must stay correct on every deploy |
| **No local user until sync** | **`firebase.auth`** returns **401** if JWT is valid but **`firebase_uid`** row missing — sync is mandatory |
| **Claim-driven profile** | Name/email/avatar updates on Laravel user follow Firebase token claims on sync — not arbitrary client JSON |

### Operational expectations

- Firebase Admin credentials (`FIREBASE_*` / service account) live **only on Laravel** (and CI test fakes) — never in mobile or admin builds.
- Feature specs assume **`firebase.auth`** on protected routes (e.g. vibe create) — see cross-links below.
- Changing identity provider would require a **new ADR** and migration project — not incremental drift.

---

## Alternatives Considered

| Alternative | Why not chosen (for Ixora today) |
| --- | --- |
| **Laravel-only auth (session + passwords)** | Heavier mobile cookie/session story; reinvents Google OAuth and password reset; worse Capacitor UX |
| **Laravel Sanctum personal access tokens issued at login** | Extra token lifecycle to secure and revoke; duplicates Firebase JWT if Firebase remains IdP |
| **AWS Cognito** | Additional AWS coupling; team standardized on Firebase for mobile Google + email flows |
| **Auth0 / Okta** | Viable enterprise IdP; cost and integration breadth exceed current needs; **no migration planned currently** |
| **Firebase as database for vibes/sounds** | Poor fit for relational catalog, policies, and Laravel ecosystem; rejected |
| **Trust client-supplied `user_id` / email in JSON** | Insecure — rejected; JWT verification only |

---

## Related Docs

| Document | Relationship |
| --- | --- |
| [`../standards/front-vibes-auth-core.md`](../standards/front-vibes-auth-core.md) | **Operational standard** — flows, token strategy, guards, Google native rules |
| [`../specs/vibes/create-vibe/spec.md`](../specs/vibes/create-vibe/spec.md) | Example protected API — **`firebase.auth`**, **`user_id`**, **`VibePolicy`** |
| [`../standards/api-resource-patterns.md`](../standards/api-resource-patterns.md) | JSON `{ data: … }` shapes returned after sync and on API reads |
| [`../standards/laravel-form-request-patterns.md`](../standards/laravel-form-request-patterns.md) | Request validation — identity **not** accepted from unverified body fields |
| [`../standards/git-flow.md`](../standards/git-flow.md) | Points to **`docs/decisions/`** for ADRs |
| [`../architecture/mobile/android-native-customizations.md`](../architecture/mobile/android-native-customizations.md) | Google Sign-In native prerequisites (SHA-1, `google-services.json`) |

### Implementation reference (current)

| Artifact | Path |
| --- | --- |
| Sync endpoint | `POST /api/auth/sync` — `back_vibes/routes/api.php` |
| Sync controller | `back_vibes/app/Http/Controllers/Api/FirebaseUserSyncController.php` |
| Token verification | `back_vibes/app/Services/Firebase/VerifyFirebaseIdToken.php` |
| User upsert | `back_vibes/app/Services/Auth/SyncFirebaseUser.php` |
| API middleware | `back_vibes/app/Http/Middleware/FirebaseAuthenticate.php` (`firebase.auth`) |
| Mobile auth | `front_vibes/src/services/auth.service.ts`, `src/composables/useAuth.ts` |

---

When auth architecture changes, supersede this ADR with a new numbered decision and update [`front-vibes-auth-core.md`](../standards/front-vibes-auth-core.md) in the same change set.
