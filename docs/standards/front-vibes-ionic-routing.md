# front_vibes Ionic routing — navigation architecture

**Status:** Active engineering standard (source of truth)  
**Scope:** Route structure, Ionic navigation, auth boundaries, and tab/fullscreen layout (`front_vibes`)  
**Stack:** Ionic 8 + Vue 3 + `@ionic/vue-router` + Capacitor  
**Related:** Auth guards and sync — [`front-vibes-auth-core.md`](front-vibes-auth-core.md)

---

## Purpose

Define the **mandatory routing and navigation architecture** for the Ixora mobile app: how routes are grouped, how Ionic `ion-router-outlet` and tabs interact with Vue Router, how auth boundaries are crossed, and which navigation APIs are safe in each context.

**Mobile routing differs from standard Vue Router assumptions** because Ionic manages **page stacks, view transitions, and tab history** through its own lifecycle. Treating the app like a plain SPA (flat routes, `router.push` everywhere, duplicate outlets) breaks back navigation, tab stacks, and auth shell transitions.

This document is the **source of truth** for routing work. Cursor rules and implementation must stay aligned.

---

## Scope

### In scope

- Route table organization in `src/router/index.ts`
- Public (flat) vs authenticated (nested tabs) vs fullscreen authenticated routes
- Auth navigation rules (`window.location.replace` at boundaries)
- Ionic router outlet hierarchy and `ion-page` requirements
- Tab bar architecture and in-tab navigation
- Fullscreen routes outside tabs (vibe player)
- Router guards (`waitForAuthState`, `ensureLaravelUserSynced`)
- Route `meta` flags (`requiresAuth`, `publicOnly`, `hideMiniPlayer`, `statusBarTheme`)
- In-tab back navigation and error redirects

### Out of scope

- Firebase / Laravel auth implementation details (see [`front-vibes-auth-core.md`](front-vibes-auth-core.md))
- Player audio state (Pinia `player.store` — referenced only where it affects layout)
- Admin Nuxt routing (`ixora-admin`)

### Applies to

| Layer | Location |
| --- | --- |
| Route definitions | `src/router/index.ts` |
| Root shell | `src/App.vue` |
| Tab shell | `src/views/TabsLayout.vue` |
| Views | `src/views/*.vue` |
| Status bar sync | `src/composables/useStatusBarStyle.ts` |

---

## Routing Architecture

### Two-level outlet model (required)

```
App.vue
  └── ion-router-outlet                    ← ROOT outlet (one per app)
        ├── Public auth pages (flat)         /sign-in, /sign-up, …
        ├── TabsLayout (authenticated)     /  → nested outlet + tab bar
        └── VibePlayerPage (fullscreen)    /vibes/:id/player
```

```
TabsLayout.vue
  └── ion-page                             ← REQUIRED root for tab shell
        └── ion-tabs
              ├── ion-router-outlet        ← TAB outlet (nested stack)
              └── ion-tab-bar
```

| Outlet | Owner | Renders |
| --- | --- | --- |
| **Root** (`App.vue`) | App shell | Public routes, `TabsLayout`, or fullscreen player |
| **Tabs** (`TabsLayout.vue`) | Authenticated tab area | Home, vibes, presets, settings, and **child** sub-pages |

**Do not add duplicate root outlets.** **Do not** mount authenticated feature pages as **flat siblings** of `TabsLayout` at the root — they belong as **children** of `/` (TabsLayout) unless explicitly designed as fullscreen exceptions.

### Router implementation

- **`@ionic/vue-router`** — `createRouter` + `createWebHistory(import.meta.env.BASE_URL)`
- **Not** plain `vue-router` history alone — Ionic Vue integration expects `@ionic/vue-router` for stack behaviour.

### Ionic vs Vue Router (mental model)

| Vue Router assumption | Ionic reality |
| --- | --- |
| Route change = component swap | Pages live in a **stack** with forward/back transitions |
| One `<router-view>` enough | **`ion-router-outlet`** at root **and** inside tabs for nested stacks |
| `router.push` always works | **Auth shell changes** (public ↔ tabs) need **full document navigation** |
| Any route can nest anywhere | **Flat authenticated routes conflict** with tab nested outlet |
| Back = history -1 | Prefer **`router.back()`** on sub-pages so Ionic pops its stack correctly |

---

## Route Groups

### 1. Public-only (flat, no tab bar)

| Path | Component | Meta |
| --- | --- | --- |
| `/sign-in-sign-up` | `SignInSignUpPage` | `publicOnly` |
| `/sign-in` | `SignInPage` | `publicOnly` |
| `/sign-up` | `SignUpPage` | `publicOnly` |
| `/forgot-password` | `ForgotPasswordPage` | `publicOnly` |
| `/reset-password-success` | `ResetPasswordSuccessPage` | `publicOnly` |

- **Standalone flat routes** — not children of `TabsLayout`.
- No tab bar, no mini player shell.
- **`router-link` / `router.push` / `router.replace`** are acceptable **within the public auth group** (e.g. sign-in ↔ sign-up ↔ forgot-password).

### 2. Authenticated tab area (nested under `TabsLayout`)

Parent: **`path: '/'`** → `TabsLayout.vue`, `meta: { requiresAuth: true }`

| Path | Component | Notes |
| --- | --- | --- |
| `/home` | `HomePage` | Default redirect from `/` |
| `/vibes` | `VibesPage` | Tab root |
| `/vibes/create` | `CreateVibePage` | **Child of TabsLayout** — not flat |
| `/vibes/:id/edit` | `EditVibePage` | **Child of TabsLayout** |
| `/vibes/:id/sounds` | `VibeSoundsPage` | `hideMiniPlayer: true` |
| `/presets` | `PresetVibesPage` | Tab root |
| `/presets/:id` | `PresetVibeDetailPage` | In-tab detail |
| `/settings` | `SettingsPage` | Tab root |

**Critical rule:** Sub-pages such as **`/vibes/create`**, **`/vibes/:id/edit`**, and **`/vibes/:id/sounds`** **must remain children of `TabsLayout`**, not root-level flat routes. Flat authenticated routes cause **outlet conflicts** between the root outlet and the tab nested outlet, breaking **back navigation** and stack coherence.

### 3. Fullscreen authenticated (outside tabs, root outlet)

| Path | Component | Meta |
| --- | --- | --- |
| `/vibes/:id/player` | `VibePlayerPage` | `requiresAuth`, `hideMiniPlayer: true`, `statusBarTheme: 'dark'` |

- **Intentionally outside tab navigation** — no tab bar over immersive player UI.
- Entered via **`router.push`** from in-tab routes (e.g. vibes list, mini player).
- Exit via **`router.back()`** — returns to previous tab stack entry.

### Route `meta` (typed in `router/index.ts`)

| Flag | Meaning |
| --- | --- |
| `requiresAuth: true` | Firebase user required; **`ensureLaravelUserSynced`** must succeed |
| `publicOnly: true` | Authenticated users redirected to **`/home`** |
| `hideMiniPlayer: true` | Hide global mini player on this route (player page, sounds manager) |
| `statusBarTheme: 'dark'` | Immersive status bar on native (player); default follows shell theme |

---

## Auth Navigation Rules

### Auth boundary = full page load

When crossing between **public auth shell** and **authenticated shell** (tabs / post-login home), use:

```typescript
window.location.replace('/target-path');
```

**Required for:**

- Successful **login** → authenticated home (e.g. `/home`)
- Successful **sign-up** → `/home`
- **Logout** → public entry (e.g. `/sign-in-sign-up`)

```typescript
// ✅ CORRECT — auth boundary
await loginWithEmail(email, password);
window.location.replace('/home');

// ❌ WRONG — auth boundary
await loginWithEmail(email, password);
router.push('/home');
router.replace('/home');
ionRouter.replace('/home');
```

### Why `window.location.replace`

`ion-router-outlet` **cannot reliably transition** between:

- **Flat public routes** (`/sign-in`, `/sign-up`, …), and  
- **Nested tab routes** (`/` → `/home`, `/vibes`, …)

Using Vue Router or Ionic router helpers at this boundary leaves stale outlet state, blank screens, or broken tab stacks. **`window.location.replace`** resets the Ionic navigation tree.

### In-guard redirects (not auth boundary UX)

`router.beforeEach` may **`return '/sign-in'`** when an unauthenticated user hits `requiresAuth` — that is guard-driven redirection, not post-login UX. Failed Laravel sync also redirects to `/sign-in` after logout + toast.

Details: [`front-vibes-auth-core.md`](front-vibes-auth-core.md).

### Public-only guard

If `to.meta.publicOnly && user` → redirect **`/home`** (authenticated user must not stay on sign-in pages).

---

## Ionic Router Rules

### `ion-page` requirement

Every routable view **must** wrap content in **`<ion-page>`** at the view root.

- **`TabsLayout`** root **must** be `<ion-page>` — without it, Ionic logs *"does not have the required `<ion-page>`"* on tab switches and view transitions break.
- Auth pages, tab pages, player, and modals follow the same rule.

### Root vs tab outlets

| Do | Don't |
| --- | --- |
| One root `ion-router-outlet` in `App.vue` | Second root outlet for “convenience” |
| One tab `ion-router-outlet` inside `ion-tabs` | Authenticated pages mounted at root beside `TabsLayout` |
| Fullscreen exceptions documented above | Arbitrary flat authenticated routes |

### Back navigation on tab sub-pages

Use **`router.back()`** on toolbar back buttons — preserves Ionic stack.

```vue
<!-- ✅ CORRECT -->
<ion-button fill="clear" @click="router.back()">
  <ion-icon :icon="chevronBackOutline" />
</ion-button>

<!-- ❌ WRONG for stack pop -->
<ion-button fill="clear" router-link="/vibes">
```

### Post-submit redirects (within authenticated shell)

**Inside tabs**, `router.replace` or `router.push` to sibling tab routes is allowed when **not** crossing the public ↔ authenticated boundary — e.g. after create vibe → `/vibes`.

### 403 / load failure on sub-pages

If a protected resource fails to load (404/403), **`router.back()`** immediately — do not leave the user on a broken page with raw error text.

```typescript
onMounted(async () => {
  await fetchVibe(Number(route.params.id));
  if (error.value) router.back();
});
```

### Tab bar styling

Use design tokens — no hardcoded tab colours:

```css
.app-tab-bar {
  --background: var(--app-color-bg);
  --color: var(--app-color-text-muted);
  --color-selected: var(--ion-color-primary);
  border-top: 1px solid var(--app-color-border);
}
```

---

## Tabs Architecture

### Structure

```
TabsLayout
  ion-page
    ion-tabs
      ion-router-outlet     ← stack for ALL tab children
      MiniPlayer            ← fixed above tab bar (Pinia-driven)
      ion-tab-bar
        href="/home"
        href="/vibes"
        href="/presets"
        href="/settings"
```

### Tabs own authenticated navigation state

- The **tab `ion-router-outlet`** maintains the **forward/back stack** for authenticated pages (create, edit, sounds, preset detail, etc.).
- **Tab buttons** use **`href="/tab-root"`** — Ionic tab switching for primary destinations.
- **Deep navigation** within a tab (e.g. `/vibes/create`, `/presets/:id`) uses **`router.push`** — stack grows inside the tab outlet.
- **Root outlet** switches only between **major shells**: public auth, `TabsLayout`, fullscreen player.

### Mini player interaction

- Rendered in **`TabsLayout`** (fixed above tab bar).
- Hidden when `route.meta.hideMiniPlayer` or playback idle/error.
- **`--app-mini-player-height`** / **`--app-tab-bar-height`** CSS vars cascade from `TabsLayout` for scroll padding.
- Fullscreen **`/vibes/:id/player`** sets `hideMiniPlayer: true` so fixed mini player does not cover immersive UI.

### Tab bar height

- Visual tab bar content: **56px** (`TAB_BAR_HEIGHT` in `TabsLayout.vue`).
- Safe area handled by Ionic shadow DOM — do not double-add `padding-bottom` on `ion-tab-bar`.

---

## Fullscreen Routes

### Vibe player (`/vibes/:id/player`)

| Property | Rationale |
| --- | --- |
| **Outside `TabsLayout`** | No tab bar; immersive full-viewport UI |
| **`hideMiniPlayer: true`** | Mini player is `position: fixed; z-index: 200` — would overlay player without this flag |
| **`statusBarTheme: 'dark'`** | Light icons on dark immersive background |
| **Enter** | `router.push(\`/vibes/${id}/player\`)` from in-tab or mini player |
| **Exit** | `router.back()` |

### When to add new fullscreen routes

Only when **both** are true:

1. UI must not show tab bar or mini player clash, **and**
2. The experience is intentionally **modal/fullscreen** (like the player).

Otherwise add the route as a **`TabsLayout` child** with appropriate `meta` (e.g. `hideMiniPlayer` only).

---

## Deep Linking Rules

### Current state

- Router uses **`createWebHistory`** — paths are standard URL paths (`/home`, `/vibes/:id/player`, …).
- **No custom Capacitor `App.addListener('appUrlOpen')` / universal-link handler** is implemented in the current codebase.
- Cold start lands on URL path; **`waitForAuthState`** runs before guards resolve.

### Rules when adding deep links

1. Target paths **must exist** in `src/router/index.ts`.
2. **`requiresAuth` routes** must pass **`waitForAuthState` + `ensureLaravelUserSynced`** — unauthenticated deep links redirect to **`/sign-in`**.
3. **Do not deep-link into flat authenticated routes** that should be tab children — link to tab-nested paths only.
4. **Public auth paths** should not be default targets for marketing links if user is already signed in (guard sends to `/home`).
5. After implementing native URL schemes, **auth boundary rules still apply** if a link crosses public ↔ authenticated shells — prefer landing on a route that matches the user's session and let guards handle redirects; use **`window.location.replace`** only when programmatically completing login/logout navigation.

---

## Navigation State Rules

### Router guards (every navigation)

```
beforeEach:
  1. user = await waitForAuthState()     ← Firebase cold-start restore
  2. if requiresAuth && user:
       await ensureLaravelUserSynced(user)   ← Laravel row required
       on failure → logout, toast, return '/sign-in'
  3. if requiresAuth && !user → return '/sign-in'
  4. if publicOnly && user → return '/home'
  5. return true
```

- **Protected routes require successful Laravel sync** — Firebase alone is insufficient for `requiresAuth` routes.
- See [`front-vibes-auth-core.md`](front-vibes-auth-core.md) for sync failure behaviour.

### `afterEach`

- **`syncStatusBarWithRoute(to)`** — applies native status bar from `meta.statusBarTheme` and shell theme.

### Pinia / audio state (routing-adjacent)

- **`player.store`** persists playback across tab route changes — independent of Ionic stack.
- **`App.vue`** registers **`useAppLifecycleAudio`** once at root (never unmounted) — not tied to individual routes.

### Allowed navigation APIs by context

| Context | Allowed |
| --- | --- |
| Public ↔ authenticated boundary | **`window.location.replace` only** |
| Public ↔ public (auth wizard) | `router-link`, `router.push`, `router.replace` |
| Tab root switch | `ion-tab-button` **`href`** |
| Tab sub-page forward | `router.push` |
| Tab sub-page back | **`router.back()`** |
| Fullscreen player enter | `router.push('/vibes/:id/player')` |
| Fullscreen player exit | **`router.back()`** |
| Post-form within tabs | `router.replace` to tab route (e.g. `/vibes`) |

---

## Risks

| Risk | If ignored |
| --- | --- |
| `router.push` / `router.replace` after login/logout | Broken outlet; blank or stuck screens between auth and tabs |
| Flat `/vibes/create` at root | Outlet conflict; broken back from edit/create |
| Missing `<ion-page>` on tab layout or views | Ionic transition warnings; broken tab switches |
| Extra root `ion-router-outlet` | Duplicate stacks; unpredictable back behaviour |
| `router-link` for sub-page back | Wrong stack pop; user skips expected history |
| Fullscreen player inside `TabsLayout` | Tab bar over immersive UI |
| Player route without `hideMiniPlayer` | Mini player overlays full player |
| Protected route without Laravel sync guard | API calls fail; inconsistent auth state |
| Assuming Vue Router SPA patterns only | Ignores Ionic lifecycle; subtle navigation bugs |
| Deep link to auth-required path offline | Sync failure → forced logout redirect |

---

## Validation

### Auth boundaries

- [ ] Email login success → **`window.location.replace('/home')`** (not `router.push`)
- [ ] Sign-up success → **`window.location.replace('/home')`**
- [ ] Logout from settings → **`window.location.replace('/sign-in-sign-up')`**
- [ ] No `ionRouter.replace` for public ↔ authenticated transitions

### Guards

- [ ] Cold start → `waitForAuthState` resolves before first guarded navigation
- [ ] Protected route with Firebase user but sync failure → logout + `/sign-in`
- [ ] Unauthenticated access to `/home` → `/sign-in`
- [ ] Authenticated access to `/sign-in` → `/home`

### Tab architecture

- [ ] `/vibes/create`, `/vibes/:id/edit`, `/vibes/:id/sounds` are **children of `/`** (TabsLayout)
- [ ] Tab switches show correct pages; no missing `<ion-page>` console warnings
- [ ] Back from create/edit/sounds uses **`router.back()`**
- [ ] Tab bar uses design tokens (not hardcoded hex)

### Fullscreen player

- [ ] Navigate to `/vibes/:id/player` — no tab bar
- [ ] Mini player hidden on player route
- [ ] Back returns to previous tab page; mini player reappears when playing

### In-tab navigation

- [ ] `router.push` to player from vibes list works
- [ ] Mini player tap → `router.push` to player
- [ ] Failed vibe load on edit page → **`router.back()`**

### Regression (native)

- [ ] Status bar correct on player (`statusBarTheme: 'dark'`) vs tab pages
- [ ] Mini player padding on `ion-content` only when visible

---

## Related Files

| Location | Path |
| --- | --- |
| **Central (this repo)** | `docs/standards/front-vibes-ionic-routing.md` (this file) |
| | `docs/standards/front-vibes-auth-core.md` — guards, sync, auth navigation |
| | `docs/standards/git-flow.md` |
| **Cursor workspace** | `.cursor/rules/front-vibes-ionic-routing.mdc` — keep aligned |
| **front_vibes** | `src/router/index.ts` |
| | `src/App.vue` |
| | `src/views/TabsLayout.vue` |
| | `src/views/VibePlayerPage.vue` |
| | `src/views/SignInPage.vue`, `SignUpPage.vue`, `SettingsPage.vue` |
| | `src/components/MiniPlayer.vue` |
| | `src/composables/useStatusBarStyle.ts` |
| | `src/stores/player.store.ts` |

When routing architecture changes, update **this file first**, then sync `.cursor/rules/front-vibes-ionic-routing.mdc` and validate auth boundaries + tab back navigation on device.
