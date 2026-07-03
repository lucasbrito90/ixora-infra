# User Experience Principles

**Status:** Active architecture guide  
**ADRs:** [ADR-024](../decisions/ADR-024-automation-notifications-and-observability.md) · [ADR-025](../decisions/ADR-025-automation-mobile-ux.md)  
**Complements:** [`feature-design-checklist.md`](feature-design-checklist.md) · [`notification-architecture.md`](notification-architecture.md) · [`domain-validation.md`](domain-validation.md) · [`asynchronous-orchestration.md`](asynchronous-orchestration.md)  
**Applies to:** All Ixora surfaces — mobile app, admin panel, API error responses visible to users, and push/local notification copy

> **Rule of thumb:** Every screen state — loading, empty, error, success — should answer **what is happening**, **what the user can do next**, and **whether anything needs their attention** — without exposing how the system works internally.

This is **not** a design system, Figma library, or component catalogue. It defines **architectural UX principles** that every feature should follow before and during implementation.

---

## 1. Introduction

User experience in Ixora is **not only visual**. Typography, colour, and spacing matter — but UX architecture also covers every moment the user waits, fails, succeeds, or receives feedback.

| UX dimension | What the user experiences |
| --- | --- |
| **Loading** | Confidence that the app is working; clarity about what is being fetched |
| **Errors** | Understandable failure with a sensible next step — never raw system output |
| **Navigation** | Predictable paths — lists open lists, details open details, taps go where expected |
| **Feedback** | Confirmation that an action succeeded or is in progress |
| **Notifications** | Timely, purposeful alerts — not noise |
| **Consistency** | Same patterns, vocabulary, and components across features |
| **Microcopy** | Short, neutral, human language — not backend terminology |
| **Accessibility** | Information available to screen readers; never colour-only or icon-only meaning |

### Why this guide exists

Good UX **reduces cognitive load**. When every feature handles loading, empty states, and errors differently, users must re-learn the product on every screen. Platform-wide principles keep Ixora feeling like **one cohesive product** — especially as Scheduler, Smart Home, playback, and catalog features intersect.

### What this guide is not

| In scope | Out of scope |
| --- | --- |
| Principles for states, copy, navigation, a11y | Pixel specs, Figma components, brand guidelines |
| When to show loading / empty / error | CSS token values (see app theme files) |
| Vocabulary and tone rules | Individual screen mockups |
| Reusable UX checklist before shipping | Animation or motion design specs |

---

## 2. Loading Principles

Loading states tell the user **the app is working** and **what is being loaded**. A silent spinner with no context increases anxiety and abandonment.

### Principles

| Principle | Detail |
| --- | --- |
| **Always explain what is loading** | Title + optional short description — e.g. "Loading your schedules…" |
| **Avoid silent spinners** | Bare `<ion-spinner>` with no label fails accessibility and clarity |
| **Prefer contextual messages** | Match copy to the screen — "Getting this vibe's details" not generic "Loading…" |
| **Avoid layout jump** | Reserve space for loading slots; use consistent containers (`AppLoadingState`) |
| **Reuse shared components** | `AppLoadingState`, `AppErrorState`, `AppEmptyState` — do not invent one-off loaders |
| **Do not block unnecessarily** | Inline/spinner on submit buttons for mutations; full-screen load for initial fetch only |

### Good vs bad

| ✅ Good | ❌ Bad |
| --- | --- |
| "Loading your schedules…" + "Fetching your reminders and Smart Home automations." | Spinner alone, no text |
| Compact loading in list slot while tab content loads | Entire page blank white with no feedback |
| Submit button shows spinner + "Save" hidden during save | Button disabled with no visual progress |
| `role="status"` / `aria-busy="true"` on loading region | Loading region invisible to screen readers |

### Shipped pattern (mobile)

```
AppLoadingState
  title     → what is loading (required for full-screen / first paint)
  description → optional context (encouraged for list/detail screens)
  compact   → tighter padding in list slots
```

Reference: Scheduler and Vibes list pages, Edit Vibe / Schedule form detail loads.

---

## 3. Empty States

Empty states appear when there is **nothing to show yet** — not when loading failed. They should **teach** and **guide**, not merely report absence.

### Principles

| Principle | Detail |
| --- | --- |
| **Teach, don't dismiss** | Explain *why* the list is empty and *what creates content* |
| **Never stop at "No data."** | Always add context and a next step when the user can act |
| **Actionable copy** | Primary action label matches intent — "New schedule", "Create vibe" |
| **Avoid blame language** | Not "You haven't created anything" — prefer neutral "No schedules yet" |
| **Distinguish offline empty** | Cached/offline empty may differ from online empty — say so clearly |
| **Reuse `AppEmptyState`** | Icon + title + description + optional action — consistent card variant |

### Good vs bad

| ✅ Good | ❌ Bad |
| --- | --- |
| "No schedules yet" + "Schedule a vibe to start on time…" + **New schedule** | "No data." |
| "No vibes to schedule" + "Create a vibe first…" + **Create vibe** | Empty list with no explanation |
| "No cached schedules" (offline) + explanation of sync requirement | Same copy online and offline when behaviour differs |

---

## 4. Error States

Errors are inevitable — network loss, validation failure, server errors. The user should see **human language**; engineers should see **structured logs**.

### Principles

| Principle | Detail |
| --- | --- |
| **Friendly language** | "Couldn't load schedules" — not "HTTP 500" or exception class names |
| **No stack traces in UI** | Never surface `Throwable`, SQL, or Laravel messages to users |
| **No provider names** | Not "Home Assistant unreachable" in display copy — use "Smart Home connection" |
| **No internal terminology** | Avoid execution, occurrence, job, queue, validator in user-visible text |
| **Retry when meaningful** | Transient fetch failures → Retry button; validation errors → fix the form |
| **Log technical details server-side** | `Log::warning` with safe IDs — never tokens or credentials ([ADR-021](../decisions/ADR-021-notification-security-and-privacy.md)) |
| **Use `AppErrorState`** | Title + description + retry — `role="alert"` for screen readers |

### Good vs bad

| ✅ Good | ❌ Bad |
| --- | --- |
| "Couldn't load vibe" + server-safe message + **Retry** | Raw `$e->getMessage()` in toast |
| Inline form error under the field | Modal with JSON error payload |
| Offline banner: "You're offline — changes won't sync" | Silent failure with no feedback |

### Retry policy

| Error type | User action |
| --- | --- |
| Network / server fetch failure | **Retry** button |
| Form validation | Fix field; no generic Retry |
| Permission denied (notifications) | Explain + link to settings if applicable — no infinite Retry loop |
| Expected skip (validator) | **No error UI** — log only ([`domain-validation.md`](domain-validation.md)) |

---

## 5. Notifications

Notification UX spans **local reminders**, **push failure alerts**, and **security notices**. Each channel serves a **different purpose** — they must not duplicate or conflict.

Full architecture: [`notification-architecture.md`](notification-architecture.md) · [ADR-024](../decisions/ADR-024-automation-notifications-and-observability.md)

### Channel purposes

| Channel | When | User sees | Tap goes to |
| --- | --- | --- | --- |
| **Local reminder** | Schedule due (device) | Schedule name + "Time to start your scheduled vibe." | Vibe player |
| **Push — schedule failure** | Backend dispatcher failed | "Schedule failed" | Schedules list |
| **Push — Smart Home action failed** | Device action failed | "Device action failed" | Devices |
| **Push — provider unreachable** | Connection/sync failed | "Smart Home unavailable" | Devices |
| **Push — security** | Auth/security event | Dynamic title/body | Settings |

```
Local reminders          ← due-time, offline-capable, primary schedule UX
        ↓
Push failure alerts      ← cross-device, server-initiated, failure-only
        ↓
Security notices         ← rare, high-attention
```

### UX rules

| Rule | Detail |
| --- | --- |
| **No duplicate notifications** | Local due reminder ≠ push failure — different triggers, different moments |
| **No notification fatigue** | No success push by default; no push on validator skip |
| **Success notifications are exceptional** | Opt-in future setting only — never default-on |
| **Short, neutral push copy** | Title + body in builders; no secrets, no provider slugs in display text |
| **Tap routing is stable** | Mobile routes by `data.type` only — changing types breaks clients |

---

## 6. Microcopy

Microcopy is the small text that carries most of the UX — labels, hints, empty states, badges, notification bodies.

### Writing rules

| Rule | Example |
| --- | --- |
| **Short** | One line title; one or two lines description max |
| **Neutral** | No blame, no exclamation overload |
| **Action-oriented** | "Create a vibe first, then come back to schedule" |
| **Privacy-safe** | No emails, tokens, or internal IDs in visible copy |
| **Consistent vocabulary** | "Schedule", "Vibe", "Smart Home" — same terms everywhere |

### Backend terms → user language

| Avoid in user-visible copy | Prefer |
| --- | --- |
| execution / executed | run / ran / completed |
| provider (when meaning HA/connection) | Smart Home / connection |
| job / queue / worker | *(omit — not user-facing)* |
| occurrence_key | *(omit — internal only)* |
| dispatch / dispatcher | schedule / reminder |
| validator / validation failed | *(log only — not user toast unless form field)* |
| device_id / vibe_id in sentences | Use names when available; IDs only in routing payload |

### Good vs bad

| ✅ Good | ❌ Bad |
| --- | --- |
| "One of your schedules could not run." | "One of your scheduled executions failed." |
| "Your Smart Home connection is temporarily unavailable." | "home_assistant provider unreachable." |
| "Used by 2 active schedules" | "active_schedules_count: 2" |

---

## 7. Badges

Badges communicate **status at a glance** — automation active, schedule enabled, offline mode. They are not buttons and must not be the only way to convey critical information.

### Principles

| Principle | Detail |
| --- | --- |
| **Status, not action** | Badges inform; buttons act |
| **Always include visible text** | Icon + label — never icon-only status |
| **Never rely on colour alone** | Enabled/disabled, automation on/off need words ([ADR-025](../decisions/ADR-025-automation-mobile-ux.md)) |
| **Reuse shared components** | `AppAutomationBadge` + `automation-badges.ts` metadata |
| **Accessible labels** | `a11yLabel` when visible text is abbreviated |

### Good vs bad

| ✅ Good | ❌ Bad |
| --- | --- |
| Badge: icon + "Automation Enabled" + `a11yLabel` for screen readers | Green dot only |
| Consistent tone (success / warning / neutral) via shared helper | Ad-hoc CSS per screen |
| "Used by 1 active schedule" summary line | Colour-only schedule indicator |

---

## 8. Accessibility

Accessibility is an architectural requirement — not a polish pass at the end.

### Requirements

| Area | Requirement |
| --- | --- |
| **ARIA labels** | Icon buttons, badge regions, detail summaries — meaningful `aria-label` |
| **Screen readers** | Loading: `role="status"`; errors: `role="alert"`; decorative icons: `aria-hidden="true"` |
| **Contrast** | Text and badges readable in light and dark mode — use design tokens |
| **Keyboard / focus** | Admin panel and web surfaces — logical tab order (mobile: platform handles focus) |
| **No colour-only state** | Enabled/disabled, automation, errors — always paired with text or icon+text |
| **No icon-only state** | Every icon conveying meaning has visible text or aria-label |
| **Headings hierarchy** | Card titles as headings; section labels for detail summaries |
| **Loading announcements** | Busy regions announced; not silent spinners |
| **Error announcements** | Error states use alert semantics where appropriate |

### Detail summaries (read-only)

Schedule and vibe detail screens use labeled `<section aria-label="…">` regions for automation summaries — user sees vibe name, schedule count, badge status without entering edit controls.

---

## 9. Navigation Consistency

Navigation should feel **predictable**. Users build a mental model once and reuse it across features.

### Principles

| Principle | Detail |
| --- | --- |
| **Tap routing matches intent** | Failure push → relevant list (Schedules, Devices) — not random screens |
| **Local schedule tap → player** | Due reminder opens vibe player; user presses Play ([ADR-011](../decisions/ADR-011-scheduler-local-notifications-vs-future-fcm.md)) |
| **Back navigation preserves context** | `router.back()` from forms; no surprise redirects on error |
| **Read-only summaries on edit screens** | Show vibe name, automation status before editable fields |
| **Lists open lists; details open details** | Schedule list → schedule form; vibe list → vibe edit |
| **Never surprise the user** | No auto-play on notification cold start; no mystery redirects |

### Push tap routing (shipped)

| `data.type` | Route |
| --- | --- |
| `schedule_execution_failed` | `/schedules` |
| `smart_home_action_failed` | `/devices` |
| `smart_home_provider_unreachable` | `/devices` |
| `account_security_notice` | `/settings` |

Changing these mappings requires a coordinated mobile release — treat as public API.

---

## 10. Progressive Disclosure

Show **essentials first**; reveal complexity only when the user asks for it or navigates deeper.

### Principles

| Principle | Detail |
| --- | --- |
| **Summary on list cards** | Schedule name, vibe, recurrence, next run, automation badge |
| **Detail on edit/detail screens** | Full automation summary, device actions count |
| **Avoid overwhelming forms** | Core fields first; cover visuals, advanced options grouped |
| **Prefer summaries over dumps** | "Used by 2 active schedules" not raw JSON or counts without context |
| **Advanced belongs in detail** | Smart Home device picker, cover bundle — not on first-create minimal path unless required |

### Good vs bad

| ✅ Good | ❌ Bad |
| --- | --- |
| List card: name + vibe + badge + next run | List card: every recurrence config key |
| Edit screen: read-only automation summary section | Hide automation status entirely |
| Empty state with one primary CTA | Empty state with five equal buttons |

---

## 11. Visual Consistency

Visual consistency supports UX consistency — users recognize patterns before reading words.

### Principles

| Principle | Detail |
| --- | --- |
| **Reuse existing components** | `AppLoadingState`, `AppEmptyState`, `AppErrorState`, `AppAutomationBadge`, `app-surface-card` |
| **Reuse spacing** | `--app-space-*` tokens — no magic pixel margins per screen |
| **Reuse typography** | `--app-font-size-*`, `--app-font-weight-*` |
| **Reuse icons** | Ionicons already used on Schedules/Vibes — match metaphors (alarm, repeat, time) |
| **Avoid one-off components** | New shared component only when ≥2 screens need the same pattern |
| **Presentation phases stay presentation-only** | Polish phases change copy/spacing/badges — not data flow or API |

This guide does **not** define colours or component APIs — those live in app theme files and shared Vue components.

---

## 12. UX Checklist

Use this checklist when designing a feature spec or reviewing a PR that touches user-facing surfaces.

### States

| # | Question | Pass criteria |
| --- | --- | --- |
| 12.1 | **Loading state?** | Contextual message; shared component; accessible |
| 12.2 | **Empty state?** | Teaches + next step; not "No data." |
| 12.3 | **Error state?** | Human language; retry if transient; `role="alert"` where appropriate |
| 12.4 | **Offline state?** | Banner or copy if behaviour differs when offline |

### Copy and feedback

| # | Question | Pass criteria |
| --- | --- | --- |
| 12.5 | **Microcopy reviewed?** | No backend jargon; short; neutral; privacy-safe |
| 12.6 | **Badges/status?** | Visible text; not colour-only; shared component if automation-related |
| 12.7 | **Notification impact?** | If feature emits alerts — see [`notification-architecture.md`](notification-architecture.md); no duplicates/fatigue |

### Navigation and a11y

| # | Question | Pass criteria |
| --- | --- | --- |
| 12.8 | **Navigation consistent?** | List → detail; tap routes documented if new push type |
| 12.9 | **Accessibility?** | Labels, headings, aria-hidden decorative icons, loading/error semantics |
| 12.10 | **Shared components reused?** | No ad-hoc spinner-only or empty div patterns |

### Block merge if

- User-visible text contains stack traces, provider slugs, or internal IDs in sentences
- Loading is silent (spinner only, no accessible status)
- Empty state is only "No data." with no guidance
- Status conveyed by colour or icon alone
- New notification type added without architecture review
- Push tap route changed without spec + mobile coordination

---

## 13. Relationship with Other Documents

| Document | Role | How this guide fits |
| --- | --- | --- |
| **[feature-design-checklist.md](feature-design-checklist.md)** | Pre-spec product/architecture review | §12 UX checklist extends checklist §6 (failure) and §7 (product) with presentation rules |
| **[feature-spec-template.md](../templates/feature-spec-template.md)** | Mandatory spec structure | Spec acceptance criteria should reference loading/empty/error expectations |
| **[notification-architecture.md](notification-architecture.md)** | Notification system design | §5 here — user-facing notification UX; architecture doc — pipeline and payloads |
| **[domain-validation.md](domain-validation.md)** | Background validation security | Validator skips → log only, no user error spam |
| **[asynchronous-orchestration.md](asynchronous-orchestration.md)** | Async layering | Failures isolated — UX shows friendly message; domain continues |
| **[ADR-024](../decisions/ADR-024-automation-notifications-and-observability.md)** | Automation notification policy | No success push; local + push roles |
| **[ADR-025](../decisions/ADR-025-automation-mobile-ux.md)** | Automation mobile surfacing | Badges, summaries, read-model display |

### When to read which document

| Question | Start here |
| --- | --- |
| *What should every feature feel like?* | **This guide** |
| *Should we add a notification?* | [notification-architecture.md](notification-architecture.md) |
| *Pre-spec review before writing spec?* | [feature-design-checklist.md](feature-design-checklist.md) |
| *How do async failures affect the user?* | [asynchronous-orchestration.md](asynchronous-orchestration.md) + §4 here |
| *Writing the feature spec?* | [feature-spec-template.md](../templates/feature-spec-template.md) |

### Recommended workflow

```
Feature idea
    ↓
feature-design-checklist.md     ← product, domain, architecture
    ↓
user-experience-principles.md   ← §12 UX checklist for states/copy/a11y
    ↓
feature-spec-template.md        ← acceptance criteria include UX states
    ↓
Domain-specific architecture    ← notification-architecture, domain-validation, etc.
    ↓
Implement + PR review against §12
```

---

*Last updated: 2026-07-02 — initial guide (platform-wide UX architecture).*
