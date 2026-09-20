# GH03c — Google Home Data Retention Compliance Review

**Task:** v1.6.0 — GH03c
**Date:** 2026-09-07
**Type:** Compliance/legal-risk review, **not** an engineering investigation. GH03b already exhausted the publicly available policy text; this document does not re-derive it, it resolves (or formally fails to resolve) the specific residual questions GH03b left open.
**Governing decisions:** [ADR-036](../../../decisions/ADR-036-google-home-execution-model.md) Decision 8, [GH03b](data-retention.md) §10.1–§10.3.
**Trello:** [GH03c](https://trello.com/c/tNXiUfNM)

Every conclusion below is labeled **CONFIRMED** (explicit official text), **INFERRED** (reasoned from official text, not stated outright — reasoning shown), or **UNRESOLVED** (documentation insufficient). No legal assumption is made. Where the evidence does not settle a question, this document says so and stops, per explicit instruction — it does not invent a conclusion to unblock the project.

---

## 1. Sources reviewed in full

- [Google Home Developer Policies](https://developers.home.google.com/policies) — last updated 2026-08-28
- [Google API Services User Data Policy](https://developers.google.com/terms/api-services-user-data-policy)
- [Terms of Service for Google Home Developers](https://developers.home.google.com/terms) ("Home Additional Terms") — last updated 2023-12-26
- [Google APIs Terms of Service](https://developers.google.com/terms)
- [Device Access Policies](https://developers.google.com/nest/device-access/policies) (Smart Device Management API — **a different program**, see §2) — last updated 2026-06-29
- [Automation API on Android](https://developers.home.google.com/apis/android/automation), [Permissions API](https://developers.home.google.com/apis/android/permissions), [Access devices and device metadata](https://developers.home.google.com/apis/android/device)

**Declared scope gap:** the Google Play Developer Policy Center, incorporated by reference, was not reviewed in full (large, multi-page corpus). No verdict below depends on it.

---

## 2. Cross-cutting finding — read before the seven questions

**An explicit carve-out for device identifiers exists elsewhere in Google's ecosystem, with textually identical 10-day language — and it is not present for the Home APIs.**

From the **Smart Device Management (SDM) API** policies — a **different program** (Nest-only, Enterprise-oriented, distinct Sandbox Terms of Service, not the Home APIs this project uses):

> "**Device-related datasets** — The following device-related datasets are excluded from the prohibition to retain data obtained from the SDM API beyond 10 trailing days: Structure ID and Name; Room ID and Name; **Device ID and Name**."
> — [Device Access Policies](https://developers.google.com/nest/device-access/policies)

This carve-out is **not** cited, linked, or incorporated by the Home APIs & Home Hub Runtime section of `developers.home.google.com/policies`, which incorporates by reference only: the Google Play Developer Policy Center, Google's OAuth API requirements, and the API Services User Data Policy. SDM is not among them.

**This cuts against a favorable reading, not toward one.** Google has demonstrated it knows how to write exactly this exception when it intends to grant it, and did not write it into the Home APIs policy. Any argument that device IDs are implicitly exempt under the Home APIs would be borrowing language from a different program's terms — a generalization the text does not authorize. If any secondary source (a summary, a blog post, an LLM) claims device IDs are retention-exempt for Google Home, its likely origin is this SDM document, misapplied.

---

## 3. The seven questions

### 3.1 — What exactly counts as "data" subject to the 10-day limit? Is there an official categorization (identifiers vs. content vs. metadata)?

**Verdict: UNRESOLVED**

> "**Data Retention:** All data may only be retained by you for a maximum of 10 days trailing from the date when the data is received, unless subject to a shorter local regulation. Data, including user data and device data, must be deleted."
> — [Policies](https://developers.home.google.com/policies), §4 "Home APIs & Home Hub Runtime Integrations" → "Security, Privacy, and Prohibitions"

No definition of "data," "user data," or "device data" exists anywhere on the page. The closest approximation is illustrative, not normative, and lives in a different section:

> "You must be transparent in how you handle user and/or device data (e.g., information provided by a user, collected about a user, and collected about a user's use of the integration or device)."
> — Policies §1 "General Policies" → "Privacy and Security"

The Home Additional Terms' "2 Definitions" section defines only *including*, *Integration*, *Your Content*, and *Your Services* — not "data," "user data," "device data," or "received." No taxonomy distinguishing identifiers from content from metadata exists for this policy. The only such taxonomy anywhere in the reviewed corpus is the SDM API's (§2 above), which belongs to a different program.

### 3.2 — Is a Google Home device identifier (e.g. the SDK's `HomeDevice.id`) subject to the 10-day limit? Does the policy treat identifiers distinctly?

**Verdict: INFERRED** (two related inferences, both reasoned below, neither stated outright)

**(a) The identifier is likely covered.** No sentence says so explicitly. The reasoning:

- The rule opens with the unrestricted quantifier **"All data"**, and its second sentence uses an open enumeration: *"Data, **including** user data and device data, must be deleted."*
- The Home Additional Terms define, in §2: **"'including' means 'including but not limited to'."** So "user data and device data" is illustrative, not exhaustive — a device identifier cannot escape the rule merely by not matching either label.
- The same §4 treats API-returned identifiers as a real, regulated category — just on a different axis (de-obfuscation, not retention):
  > "Attempting to: (1) extract PII of users..., devices, home information, or structure and devices, (2) deobfuscate identities, **including from API-returned obfuscated identities** and/or (3) share inferred data with other parties."
  > — Policies §4 → "Prohibited Actions"

  The policy acknowledges "API-returned obfuscated identities" as an existing, regulated category — regulating their *de-obfuscation*, not their *retention*. This supports "identifiers are data" but the bridge from "is data" to "therefore falls under the 10-day rule" is this document's inference, not the policy's statement.

**(b) The policy does not carve identifiers out.** Reading §4 in full finds no exception for IDs, names, or any category. This absence, read against the SDM contrast in §2 above, supports treating it as *deliberate* — but that is an inference from omission and cross-document contrast, not a Home APIs statement.

### 3.3 — If the same identifier is fetched again later, is there a documented basis for a new 10-day window starting from that re-fetch?

**Verdict: UNRESOLVED**

The word **"received"** appears exactly once in the entire policy — inside the retention clause itself — and is never defined. No definition exists in the Home Additional Terms' Definitions section, the API Services User Data Policy, or the Google APIs ToS. No official glossary or FAQ defining "received" or "trailing" for the Google Home Developer Platform was found.

This means the documentation does not permit choosing between: (a) the window is per receipt-event, and a re-fetch starts a fresh window for the newly received copy; or (b) the window anchors to the data's first receipt. **This is the single most consequential unresolved question for schema design** — it determines whether an actively-used app can ever hold "fresh enough" data, or whether staleness is unavoidable regardless of sync frequency.

### 3.4 — Does storing this data on the Ixora backend (server) carry a different obligation than storing it only locally on the user's Android device?

**Verdict: INFERRED** — the obligation is, on the best reading, indifferent to physical location.

- The rule says **"retained by you"**, with no locus qualifier — no mention of "server," "backend," or "cloud."
- Official documentation treats data cached **inside the user's own app** as data the developer holds and must delete:
  > "Each time the app starts, be sure to check that the permissions are still in effect. If they have been revoked, then be sure that all previous data are removed, **including any data cached in the application**."
  > — [Automation API on Android](https://developers.home.google.com/apis/android/automation) (identical text on [Permissions API](https://developers.home.google.com/apis/android/permissions))
- The Google APIs ToS (incorporated by the Home Additional Terms) prohibit permanent copies without a locus qualifier either:
  > "Scrape, build databases, or otherwise create permanent copies of such content, or keep cached copies longer than permitted by the cache header"
  > — [Google APIs Terms of Service](https://developers.google.com/terms), "Prohibitions on Content"

**Reasoning, stated as generalization:** the obligation's subject is the developer ("you"), not a system, and the one passage that explicitly addresses on-device storage (the revocation clause) imposes deletion on it. This document generalizes from a *permission-revocation* obligation to the *retention* rule — that step is this document's inference, not a direct policy statement. **Practical conclusion: moving the identifier from backend to the Android device does not, on the available text, change the obligation.** GH03b's originally proposed mitigation (move Google-derived identifiers to the device) reduces the backend's exposure surface but does not, by itself, resolve the retention conflict — see §5.

### 3.5 — Can Ixora indefinitely retain an Ixora-owned opaque reference that does not permit reconstructing the Google device identifier?

**Verdict: UNRESOLVED**

No official document addresses one-way mappings, hashing, pseudonymization, or tokenization in this context — neither to permit nor to forbid them.

Two passages come closest, and neither resolves it:

1. The API Services User Data Policy extends *Limited Use* to derived data: *"These requirements apply to the raw data obtained from the scopes and data aggregated, anonymized, or derived from them."* This governs **use and transfer** (feature-serving limits, transfer restrictions), not **retention duration**.
2. Policies §4's prohibition on sharing inferred data (*"share inferred data with other parties"*) governs **sharing**, not **retention**.

The question "does an internal identifier that carries no reconstructable Google content still count as 'data' under the 10-day rule?" is not answerable from documentation or reasonable inference — it depends on the definition of "data" that §3.1 already found undefined. This is exactly the kind of boundary case a security-assessment conversation with Google (already required for production certification, per GH03a) or formal legal counsel would need to settle, not public-policy reading.

### 3.6 — Is there any exception for data necessary to a feature the user explicitly configured/requested?

**Verdict: INFERRED — no such exception exists.**

Full-text search for *necessary*, *required for*, *core functionality*, *legitimate interest*, *user-configured*, *essential* across all reviewed documents returns only permission-minimization or security/legal language — never retention:

- *"Request appropriate permissions: Don't request access to data that you don't need to provide the primary features of your application or service."* (Policies §1) — a collection-scope limit, not a retention license.
- *"Permission requests should make sense to users, and should be limited to the critical information necessary to implement your application."* (API Services User Data Policy) — same category.
- The only exceptions the API Services User Data Policy grants are to the *no-human-review* rule (security investigation, legal compliance), not to retention.
- The one named categorical exception in the entire corpus belongs to a different program again: *"...with the limited exception of use cases approved by Google under additional terms applicable to the **Nest Device Access program**"* (API Services User Data Policy) — SDM, not Home APIs.

**Reasoning:** the retention clause names exactly one modifier, and it is more restrictive, not less: *"unless subject to a shorter local regulation."* A clause that enumerates its own single exception, and enumerates it in the direction of shortening the window, is best read as closed to unwritten lengthening exceptions. This is inference from textual construction, not a Google statement.

### 3.7 — Do the policies address user-created "Automations" or "Scenes" in relation to retention?

**Verdict: UNRESOLVED** (with one firm factual note: the word "Scenes" does not appear in the policy at all)

Full-text search of the Policies page: "scene" — **zero matches**. "Automation(s)" — 4 matches, none tied to retention: the section-4 scope list (*"Relevant APIs under this section include the Commissioning API, Home APIs, Automations API..."*), a device-sharing clause about automation "starters," a consent-scope mention, and a discoverability mention. None of these govern retention, and — per the explicit instruction not to conflate the two — this is about the **Google Automation API** (automations that run on Google's infrastructure), not an **Ixora Scene that merely references a Google device**. The documentation does not address the second case at all. The [Automation API page](https://developers.home.google.com/apis/android/automation) itself contains no instance of "retain," "retention," or "10 days" — its only data-deletion instruction is the revocation clause already cited in §3.4.

---

## 4. Summary table

| # | Question | Verdict | One-line summary |
| --- | --- | --- | --- |
| 1 | What is "data"? | UNRESOLVED | "All data" is never defined; no official taxonomy of identifier vs. content vs. metadata for Home APIs. |
| 2 | Device identifier covered? | INFERRED (likely yes) | "All data" + "including" = "including but not limited to," and no carve-out exists — unlike the SDM program, which has one. |
| 3 | Re-fetch resets the window? | UNRESOLVED | "received" is used once, never defined; no glossary/FAQ resolves it. |
| 4 | Backend vs. on-device storage? | INFERRED (no difference) | "Retained by you" has no locus qualifier; on-device cached data must be deleted on revocation per official text. |
| 5 | One-way opaque internal reference? | UNRESOLVED | Nothing addresses irreversible derived references; the two closest clauses govern use/transfer and sharing, not retention. |
| 6 | Exception for user-requested functionality? | INFERRED (none exists) | Every "necessary"-type clause is about permission scope, not retention; the rule's only exception shortens, not lengthens, the window. |
| 7 | Automations/Scenes addressed? | UNRESOLVED | "Scenes" absent entirely; "Automations" only appears regarding the Google-run Automation API, not an app's own references to a device. |

---

## 5. Architectural recommendation, conditioned on the evidence above

### A — What can be safely implemented now

**Interactive, ephemeral use of Google Home devices — discover, read state, execute a command, in direct response to the user's in-session action — with no Google-derived data persisted beyond that interaction.** This is exactly what GH02 already built and physically verified: every call re-queries the SDK's live flow; nothing is written to `back_vibes` or to durable device storage. Whether "data received transiently and discarded within the same session" falls under the 10-day rule at all is not even a live question — it is *not retained* by construction, so §3.1–§3.7's unresolved boundaries don't need to be crossed to ship this slice.

Concretely, safe to build without further legal input:
- Connecting a Google Home account and completing OAuth consent.
- A "control now" surface: pick a discovered device, read its state, send on/off (and, once GH04's brightness row is verified, set brightness) — with the device list and state re-fetched live each time the screen is opened, never cached into a persistent record.
- Home Assistant continues exactly as today (ADR-036 is unaffected; this section only bounds the *Google* side).

### B — What must not be persisted, until the open questions resolve

- **Any Google device identifier**, on the backend **or** on the mobile device, beyond the current session/interaction. §3.4's inference explicitly removes "just put it on the phone" as a safe harbor — locus does not appear to matter.
- **Any Google-sourced device name, room, or state**, beyond the same window, for the same reason.
- **This corrects GH03b's originally proposed mechanism.** GH03b (§6 there) proposed moving the identifier to the device and expiring backend-side cached fields from `last_seen_at`, treating that as sufic ient mitigation. It is not confirmed sufficient: that mechanism's safety implicitly assumed (a) device-side storage is treated differently from backend storage (§3.4 says likely not) and (b) a sync-driven refresh legitimately extends the window (§3.3 is undefined, not confirmed). **Do not build GH03b's originally proposed persistent-mapping mechanism as a compliant solution** — it may still be the right *shape* once §3.3/§3.4/§3.5/§3.6 are actually resolved, but it cannot be built today and labeled compliant.
- **An Ixora-internal opaque reference is not a confirmed safe harbor either** (§3.5, UNRESOLVED) — do not treat "we don't store the real Google ID, only our own pointer" as a solved problem; it is an open one.

### C — What still depends on legal/compliance interpretation

Questions 1, 3, 5, and 6 are UNRESOLVED and block the specific capability of **a persistent Scene/Vibe that keeps referencing a specific Google device across sessions, indefinitely** (the feature GH03b's §10.1 originally flagged). Recommended next step, not taken here: a direct, written inquiry to Google through the channel the program already requires for production (security assessment, consent-screen approval "in a form approved by Google" — GH03a) asking specifically: (i) does re-syncing device data reset the 10-day window; (ii) can a device identifier necessary for a user-configured persistent automation be retained beyond 10 days; (iii) does an irreversible internal reference count as retained "data." A formal legal/compliance opinion is the alternative or complementary path if that channel doesn't yield a binding answer in time.

### D — Is GH03c sufficiently resolved to release production-implementation planning?

**Not fully — the core conflict GH03b flagged (persistent Scenes referencing a specific Google device) remains genuinely open on its most load-bearing questions (§3.3, §3.5, §3.6).** Manufacturing a confident answer here would be exactly the invented conclusion this task was explicitly told not to produce.

**However, production-implementation planning does not have to wait on the full answer.** Section A above is a real, useful, legally uncomplicated slice: Google Home devices controllable interactively, with zero persistence of Google-derived data. That slice can be scoped now. What cannot yet be scoped is persistent Google-device-referencing Scenes/automations — that piece of the production backlog stays blocked on the outcome of §C's inquiry, exactly as the GH03c Trello card already states.

**Recommendation:** authorize production-implementation scoping **for the interactive-only slice (§A)** now, while keeping persistent-Scene support as an explicitly deferred, separately-gated piece of that same task (not a reason to block the whole thing, and not something to schedule a delivery date for until §C resolves).

---

## 6. What this document does not do

Per the task's explicit boundary: no migration, no model change, no persistence design finalized, no production Google Home code, and the GH02 spike branch is not merged or reused directly here.
