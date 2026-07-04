# Mobile E2E Testing — Real-Device Android with Appium

**Status:** Active testing guide  
**Scope:** Official Ixora standard for real-device mobile end-to-end validation  
**Applies to:** `front_vibes` (Android-first); iOS follow-up when parity work begins  
**Tooling:** [Appium](https://appium.io/) 2.x + [WebdriverIO](https://webdriver.io/) via UiAutomator2

> **Rule of thumb:** Unit, feature, and integration tests prove that code behaves correctly in isolation. **Real-device E2E** proves that the shipped Android app — Capacitor runtime, native plugins, OS permissions, and staging API — behaves correctly for the user.

**Related:** [quality-harness.md](../quality-harness.md) · [user-experience-principles.md](../architecture/user-experience-principles.md) · [notification-architecture.md](../architecture/notification-architecture.md)

---

## 1. Introduction

Ixora mobile ships as a **Capacitor Android app** wrapping a Vue/Ionic WebView. Much of the product runs in the browser layer, but release confidence depends on behaviour that automated unit tests cannot fully exercise:

| Dimension | Why unit tests are insufficient |
| --- | --- |
| **Native plugins** | Capacitor bridges (Local Notifications, Push, Preferences, Filesystem, SQLite) run in the Android runtime — not in Vitest |
| **Capacitor runtime** | WebView context switching, app lifecycle, background/foreground transitions |
| **Android permissions** | Notification channels, post-notification permission (API 33+), network state |
| **Local notifications** | OS alarm scheduling, channel creation, tap handling while app is killed |
| **Push notification tap routing** | FCM payload → native handler → Vue router navigation |
| **Offline behaviour** | SQLite mirror, cached assets, offline banners, sync on reconnect |
| **Navigation** | Ionic tabs, deep links, hardware back, WebView ↔ native context |
| **Accessibility labels** | `content-desc`, `aria-label`, TalkBack traversal on real UI |
| **Real rendering** | Ionic components, safe areas, dark mode, device-specific WebView quirks |

### What this guide answers

1. **When** should we use Appium?
2. **What** should Appium test (and what it should not)?
3. **What** makes a mobile feature release-ready?

This document is the **official reference** for real-device Android validation in Ixora. Feature specs and QA reports should link here when on-device steps are required.

### Relationship to other test layers

| Layer | Tooling | Purpose |
| --- | --- | --- |
| **Unit** | Vitest | Pure functions, services, composables |
| **Component** | Vitest + Vue Test Utils | Isolated Vue component behaviour |
| **Backend integration** | Pest (PHPUnit) | API, jobs, scheduler, push pipeline |
| **Web E2E (optional)** | Playwright / Cypress (`tests/e2e/`) | Browser-only flows — **not** a substitute for Appium |
| **Real-device E2E** | Appium + WebdriverIO (`qa-android-native/`) | Native Android validation against staging |

The [quality harness](../quality-harness.md) covers unit/lint/typecheck/build. **Appium is a separate, intentional gate** for features that touch native or release-critical mobile behaviour.

---

## 2. When Appium is required

Use Appium when a feature or release touches any of the following:

| Trigger | Examples |
| --- | --- |
| **Native Android plugins** | Local Notifications, Push, Preferences, Filesystem, SQLite, Network |
| **Local notifications** | Schedule reminders, channel setup, tap → player navigation |
| **Push notifications** | FCM registration, foreground/background receive, tap routing |
| **Deep links / tap routing** | Notification payload → `/schedules`, `/devices`, `/vibes/:id/player` |
| **Capacitor storage** | Preferences (auth tokens), Filesystem (offline assets), SQLite (schedule mirror) |
| **Offline sync** | Download vibes, offline playback, reconnect sync, offline banners |
| **Device APIs** | Camera, microphone, audio focus, media session, headset events |
| **Complex authenticated flows** | Login → tab navigation → CRUD → background → notification tap |
| **Release-critical user journeys** | Scheduler due reminder, Smart Home automation surfacing, vibe playback |

### When Appium is optional

Appium is **not required** for changes that are purely:

- Copy or microcopy updates with no navigation change
- CSS/token adjustments with no new interactive elements
- Backend-only API changes with no mobile contract change
- Read-only UI that already has Appium coverage in the same screen

When in doubt, ask: *Does this change how the app interacts with Android OS, native plugins, or staging in a way Vitest cannot see?* If yes → Appium.

---

## 3. What Appium should test

Appium suites should cover **user-visible critical paths** — not every edge case (those belong in unit/integration tests).

### Authentication and navigation

- Sign in with staging Firebase test account
- Tab navigation (Vibes, Schedules, Devices, Settings)
- Back navigation and route persistence after background/foreground

### Scheduler and automations

- Schedule list — loading, empty, error states
- Schedule creation and edit form
- Local notification registration after schedule sync
- Notification tap → vibe player route (no auto-play)
- Smart Home automation badges on schedule and vibe surfaces

### Smart Home

- Device list and connection status
- Device Actions screen (read-only automation summary on schedule form)
- Push tap routing → `/devices` for failure notifications

### Playback and media

- Vibe player launch from list or notification tap
- Foreground/background playback (where instrumented)
- Media notification controls (pause/resume smoke)

### Offline and sync

- Offline banner visibility
- Cached vibe playback when network unavailable
- Reconnect behaviour

### UX states (per [user-experience-principles](../architecture/user-experience-principles.md))

- Loading states — title + description visible
- Empty states — actionable copy and CTA
- Error states — retry affordance
- Accessibility — critical controls have labels; badges are not colour-only

### Smoke checks

- Dark mode — no broken contrast on primary screens (smoke, not pixel-perfect)
- App launch — no crash on cold start against staging

### Existing suites in `front_vibes`

| Script | Spec | Focus |
| --- | --- | --- |
| `npm run test:smoke:android` | `wdio.android.conf.ts` | General smoke |
| `npm run test:native-scheduler-e2e:android` | `qa-android-native/scheduler-e2e.spec.ts` | Scheduler MVP on device |
| `npm run test:native-offline-qa:android` | `qa-android-native/offline-native-qa.spec.ts` | Offline playback |
| `npm run test:native-pause-resume-qa:android` | `qa-android-native/pause-resume-instrumentation.spec.ts` | Media pause/resume |
| `npm run test:native-media-notification-qa:android` | `qa-android-native/media-notification-qa.spec.ts` | Media notification |

New features should add specs alongside these — not replace them.

---

## 4. What Appium should NOT test

| Anti-pattern | Why |
| --- | --- |
| **Duplicate every unit test** | Business logic belongs in Vitest/Pest — Appium is slow and flaky if misused |
| **Laravel business logic** | Recurrence calculation, validator rules, push payload assembly — test in `back_vibes` |
| **Provider HTTP internals** | Home Assistant REST details — test with fakes in Pest; Appium may assert user-visible outcome only |
| **Fragile pixel comparisons** | Visual regression belongs in dedicated tools; Appium asserts presence, text, and navigation |
| **Random sleeps** | Use explicit waits (`waitForDisplayed`, `waitUntil`, WebdriverIO `browser.waitUntil`) |
| **Credentials in committed files** | Secrets in `.env.e2e` or CI — never in specs or config committed to git |
| **Production accounts** | Staging Firebase + dedicated E2E test user only |
| **Full catalog CRUD matrix** | Admin catalog flows are out of mobile Appium scope |

### Flake prevention

- Prefer **accessibility labels** over XPath
- Reset app state between specs where possible (`noReset: false` or explicit logout)
- Document **manual-only** steps when automation is impractical (see §9)
- Capture **screenshots + logcat** on failure (existing pattern in `qa-android-native/`)

---

## 5. Test IDs and accessibility

Stable selectors reduce flake and align with Ixora accessibility standards ([user-experience-principles](../architecture/user-experience-principles.md) §8).

### Preferred selector strategy (in order)

1. **Accessibility ID** — Android `content-desc` / iOS `accessibility id`; maps from Vue `aria-label` on interactive elements
2. **Stable test identifier** — `data-testid` or equivalent where WebView DOM is accessible (use sparingly; prefer a11y labels)
3. **Visible text** — only when copy is stable and not localized in the near term
4. **CSS / XPath** — last resort; document why if used

### Conventions for test identifiers

| Rule | Detail |
| --- | --- |
| **Stable** | Do not tie to auto-generated IDs, timestamps, or list index |
| **User-safe** | Labels must make sense to screen reader users — not `test-btn-1` |
| **No secrets** | Never encode tokens, emails, or API keys in labels |
| **No unnecessary DB IDs** | Prefer semantic labels (`schedule-form-save`) over `vibe-4821` unless routing requires it |
| **Theme-agnostic** | Same selector works in light and dark mode |
| **Badges and icons** | Text label required; decorative icons `aria-hidden="true"` |

### Examples

| Element | Good | Avoid |
| --- | --- | --- |
| Save schedule button | `aria-label="Save schedule"` | XPath `//ion-button[3]` |
| Automation badge | Visible text "Smart Home automation enabled" | Colour-only dot |
| Loading state | `role="status"` + title text | Bare spinner with no label |
| Empty schedules | Heading + description text | Generic "No data" |

Appium lookup (WebdriverIO):

```typescript
// Preferred — accessibility id (content-desc)
await $('~Save schedule').click();

// Fallback — stable text when copy is pinned by spec
await $('android=new UiSelector().text("Loading your schedules…")').waitForDisplayed();
```

---

## 6. Recommended project structure

### Current structure (`front_vibes`)

The repo already uses Appium via WebdriverIO. **Extend this layout** — do not introduce a parallel framework.

```
front_vibes/
  wdio.android.conf.ts                    ← smoke config
  wdio.android.scheduler-e2e.conf.ts      ← scheduler E2E config
  wdio.android.offline-qa.conf.ts           ← offline QA config
  wdio.android.*.conf.ts                    ← one config per suite / concern
  qa-android-native/
    scheduler-e2e.spec.ts                 ← feature spec
    offline-native-qa.spec.ts
    media-notification-qa.spec.ts
    helpers/
      logcat.ts
      playback-bridge.ts
      offline-menu.ts
    output/                                 ← gitignored run artifacts
  tests/smoke/android/helpers/              ← shared auth, webview helpers
  tests/e2e/                                ← Playwright/Cypress (browser only — not Appium)
```

### Conventions for new specs

| Item | Convention |
| --- | --- |
| **Spec files** | `qa-android-native/<feature>-e2e.spec.ts` or `<feature>-qa.spec.ts` |
| **WDIO config** | `wdio.android.<feature>.conf.ts` at repo root (matches existing pattern) |
| **npm script** | `test:native-<feature>-e2e:android` → `wdio run wdio.android.<feature>.conf.ts` |
| **Evidence output** | `qa/<feature>-e2e/evidence/` or `qa-android-native/output/<feature>/` — gitignored |
| **Shared helpers** | `qa-android-native/helpers/` or `tests/smoke/android/helpers/` |

### Proposed consolidation (optional future)

If the number of suites grows, consider consolidating under:

```
e2e/
  appium/
    README.md           ← run instructions local to front_vibes
    config/             ← wdio configs
    helpers/
    specs/
      scheduler-smart-home.e2e.ts
      push-notifications.e2e.ts
```

Migration is **not required today** — the existing `qa-android-native/` + root `wdio.android.*.conf.ts` pattern is the active standard until an ADR or team decision says otherwise.

---

## 7. Environment and secrets

Real-device E2E requires a controlled staging environment. **Never run destructive E2E against production.**

### Required

| Item | Purpose |
| --- | --- |
| **Staging API** | `https://staging-api.ixora-app.app` (or `VITE_API_BASE_URL` override) |
| **Staging Firebase project** | Auth for E2E test user — `VITE_FIREBASE_*` vars |
| **Android device** | Physical device or emulator with Google Play services; connected via `adb` |
| **Debug APK** | Built from `develop` / feature branch with staging env baked in |
| **E2E test account** | Dedicated Firebase user — not a team member's personal account |

### Optional (feature-dependent)

| Item | When needed |
| --- | --- |
| **Home Assistant sandbox** | Smart Home device action E2E — real HA state change |
| **FCM / push capability** | Push notification receive and tap routing on device |
| **Pre-seeded staging data** | Vibes, schedules, device actions for deterministic flows |

### Secrets handling

| Location | Allowed content |
| --- | --- |
| **`.env.e2e`** (local, gitignored) | `E2E_USER_EMAIL`, `E2E_USER_PASSWORD`, `VITE_FIREBASE_API_KEY`, device overrides |
| **CI secrets** | Same keys — injected by pipeline, never logged |
| **Spec files** | ❌ No credentials, tokens, or API keys |
| **Git** | ❌ Never commit `.env.e2e`, APKs with prod keys, or Firebase service accounts |

Existing scheduler E2E reads credentials from environment or local `.env` via helper — follow that pattern:

```typescript
// Pattern from qa-android-native/scheduler-e2e.spec.ts — env first, then local file
const email = process.env.E2E_USER_EMAIL ?? envVar('E2E_USER_EMAIL');
```

Document required env vars in the spec header comment and in the feature QA report.

---

## 8. Execution commands

Run from `front_vibes/` unless noted. Commands reflect **what exists today**; proposed aliases are marked.

### Device prep

```bash
# Verify device connected
adb devices

# Optional: target a specific device
export ANDROID_DEVICE_UDID=<serial-from-adb-devices>
```

### Build and install

```bash
cd front_vibes

# Staging build (API URL + Firebase config for staging)
npm run build:staging

# Sync Capacitor native project
npx cap sync android

# Build debug APK
npm run android:apk:debug

# Install / reinstall on connected device
adb install -r android/app/build/outputs/apk/debug/app-debug.apk
```

Override APK path when testing a pre-built artifact:

```bash
export ANDROID_APK_PATH=/path/to/app-debug.apk
```

### Appium setup (first time per machine)

```bash
npm run appium:setup    # installs uiautomator2 driver
```

### Run suites (existing scripts)

```bash
# General Android smoke
npm run test:smoke:android

# Scheduler native E2E
npm run test:native-scheduler-e2e:android

# Offline QA
npm run test:native-offline-qa:android

# Pause/resume instrumentation
npm run test:native-pause-resume-qa:android

# Media notification QA
npm run test:native-media-notification-qa:android
```

### Proposed unified entry (not yet in package.json)

```bash
# Proposed — aggregate critical-path suites before release
npm run test:e2e:appium
```

When adding `test:e2e:appium`, it should run the **minimum critical path** for the release (smoke + feature-specific specs documented in the feature QA report).

### Evidence and debugging

```bash
# Logcat while reproducing manually
adb logcat | grep -iE 'ixora|capacitor|chromium|firebase'

# Screenshot on failure — handled by spec; artifacts under qa-android-native/output/
```

---

## 9. Release criteria

A feature that touches **mobile or native behaviour** is **release-ready** only when all of the following are true:

| Gate | Command / check | Required |
| --- | --- | --- |
| **Unit tests** | `npm run test:unit` | ✅ Always |
| **Lint** | `npm run lint` | ✅ Always |
| **Typecheck** | `npm run typecheck` | ✅ Always |
| **Production build** | `npm run build` or `npm run build:staging` | ✅ Always |
| **Android APK builds** | `npm run android:apk:debug` | ✅ When native/plugins touched |
| **Capacitor sync** | `npm run cap:sync:android` | ✅ When plugins or native config touched |
| **Appium critical path** | Feature-specific WDIO suite(s) | ✅ When §2 triggers apply |
| **Backend harness** | `back_vibes`: `composer test` | ✅ When API contract touched |
| **Known device limitations documented** | Feature QA report or spec | ✅ When automation skips exist |
| **Manual-only checks listed with reason** | QA report § remaining issues | ✅ When Appium cannot cover (e.g. exact HA hardware) |

### Conditional PASS

A release may ship with **CONDITIONAL PASS** when:

- All automated gates pass
- Remaining gaps are **environment-only** (no device connected, no HA sandbox) and documented
- Manual checklist is assigned with owner and target date

Example: [scheduler-smart-home-e2e QA report](../qa/scheduler-smart-home-e2e/summary.md) — automated ✅, on-device ⏸ pending.

### Not release-ready

- Appium critical path fails with a **product bug**
- Push or local notification tap routes to wrong screen
- Crash on cold start against staging
- Secrets exposed in test artifacts or logs

---

## 10. Failure triage

When an Appium run fails, classify before fixing:

| Classification | Symptoms | Action |
| --- | --- | --- |
| **Product bug** | App behaviour wrong on device; reproducible manually | Document in QA report; fix in Phase X.x — **do not** weaken the test |
| **Test bug** | App correct; selector stale, wrong wait, bad assertion | Fix spec or helper |
| **Environment issue** | Staging API down, wrong `VITE_API_BASE_URL`, Firebase misconfig | Fix env; re-run |
| **Device issue** | `adb` disconnect, WebView driver crash, low storage | Reboot device, re-install APK |
| **Staging data issue** | Missing seed vibe, schedule deleted, wrong test user state | Re-seed or reset test account |
| **Provider sandbox issue** | HA unreachable, sandbox token expired | Fix sandbox; mark manual SKIP with reason |

### Workflow

1. Capture **screenshot**, **logcat snippet**, and **spec timeline** (existing `qa-android-native` pattern).
2. Reproduce **manually on device** once to separate product vs test bug.
3. File finding in feature QA report with ID (e.g. `QA-004`).
4. **Product bugs** → Phase X.x fix branch — not silent test deletion.
5. **Environment skips** → document in acceptance report; do not mark feature Done until resolved or explicitly deferred.

---

## 11. Relationship with other docs

| Document | Relationship |
| --- | --- |
| [quality-harness.md](../quality-harness.md) | Baseline unit/lint/typecheck/build — Appium is **additional**, not a replacement |
| [user-experience-principles.md](../architecture/user-experience-principles.md) | Loading, empty, error, a11y, microcopy — Appium should assert these on device |
| [notification-architecture.md](../architecture/notification-architecture.md) | Local vs push channels, tap routing, no duplicate notifications |
| [scheduler-smart-home-operational-checklist.md](../operations/scheduler-smart-home-operational-checklist.md) | Backend workers and push pipeline — Appium validates mobile side of same flows |
| [feature-design-checklist.md](../architecture/feature-design-checklist.md) | Pre-spec review — flag native/mobile E2E needs early |
| [feature-spec-template.md](../templates/feature-spec-template.md) | Acceptance criteria should state Appium-required paths when §2 triggers apply |
| [mobile-cdn-validation.md](../architecture/storage/mobile-cdn-validation.md) | Complementary device QA for HTTPS assets |
| [qa/scheduler-smart-home-e2e/summary.md](../qa/scheduler-smart-home-e2e/summary.md) | Example QA report with automated vs on-device pending |

### Feature author checklist

Before marking a mobile feature **Done**:

- [ ] §2 triggers evaluated — Appium required or explicitly waived with reason
- [ ] Critical-path spec exists or existing suite extended
- [ ] Selectors use accessibility-first strategy (§5)
- [ ] Secrets in `.env.e2e` / CI only (§7)
- [ ] Release criteria (§9) met or CONDITIONAL PASS documented
- [ ] QA report links to this guide

---

*Last updated: 2026-07-03. Tooling reference: Appium 2.x, WebdriverIO 9.x, UiAutomator2 — as declared in `front_vibes/package.json`.*
