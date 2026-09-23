# GH03b — Google Home data retention, classification and analytics boundary

**Task:** v1.6.0 — GH03b (second half of GH03; the access gate is [GH03a](access-gate.md))
**Date:** 2026-09-06
**Type:** Investigation. No production code, migrations or schema changes were made.
**Governing decision:** [ADR-036](../../../decisions/ADR-036-google-home-execution-model.md) Decision 8.

Policy claims carry an official source and, where possible, a verbatim quote. Where the policy is silent, the item says **"não encontrado na documentação oficial"** and moves to §10 as engineering judgement or a legal question. Interpretation is always labelled as interpretation.

---

## 1. Executive conclusion

Two findings, pulling in opposite directions.

**The good news is structural.** IXORA persists almost nothing Google-derived outside a single table. Execution records, application logs, metrics and traces carry only internal integer identifiers — a consequence of [ADR-030](../../../decisions/ADR-030-observability-security-and-privacy.md), which forbade provider entity IDs in telemetry long before Google Home was considered. That decision now confines the entire retention problem to the `devices` row. `scene_action_executions` (90-day retention, ADR-034) and Loki logs (14-day retention, ADR-031) both exceed the 10-day policy window and are **both fine**, because neither contains data received from the Home APIs.

**The bad news is that there is no safe harbour for core functionality.** The policy states *"All data may only be retained by you for a maximum of 10 days trailing from the date when the data is received"*, and adds *"Data, including user data and device data, must be deleted."* No exception exists — documented anywhere — for data required for the product to function. A saved Scene that acts on a Google Home device must retain a Google device identifier to remain executable. That is a direct conflict, and it is not resolvable by engineering alone.

**Recommendation:** exploit the architecture already chosen. ADR-036 put Google Home execution on the device; put the Google-derived identifiers there too. The backend keeps an IXORA-authored device record and never becomes the durable home of Google data. Details in §6. This narrows the legal exposure to something defensible, but **does not eliminate the open question in §10.1, which needs a legal opinion, not an architectural one.**

---

## 2. What IXORA stores today — verified in code

| Store | Google-derived content | Current retention |
| --- | --- | --- |
| `devices` — `name`, `type`, `provider_device_id`, `status`, `last_seen_at`, `metadata` (json), `capabilities` (json) | **yes — all of it** | **indefinite** ⚠️ |
| `scene_action_executions` — `device_id` (internal FK), `provider` slug, `provider_connection_id`, `action_type`, `outcome`, `failure_category`, `http_status_code`, `duration_ms`, `trace_id`, `attempt`, `executed_at` | **none** | 90 days, scheduled purge (ADR-034 §4) |
| Application logs — `SceneActionJob` context is `scene_action_id`, `scene_id`, `device_id`, `provider_connection_id`, `provider`, `action_type`, `outcome`, `status_code` | **none** | 14 days, Loki (ADR-031) |
| Metrics / traces — `SmartHomeProviderDeviceDomain` emits a bounded device *category*, documented as *"never a `provider_device_id` or `entity_id`"* | **none** | 30 days / 7 days (ADR-031) |
| `provider_connections` — `user_id`, `name`, `provider`, `config`, `encrypted_credentials`, `status` | none today (Google Home holds no server credential — ADR-036 Decision 8) | indefinite |

What the Home Assistant adapter writes into `devices.metadata` today: `domain`, `raw_state`, and conditionally `supported_features` and `device_class`. A Google adapter would write the equivalent Google-derived payload into the same column.

**How the data currently refreshes:** `ProviderDeviceSyncService::sync()` performs `Device::updateOrCreate`, overwriting `name`, `type`, `status`, `metadata` and `capabilities` on every sync, and marks devices absent from the response as offline. **A refresh mechanism therefore already exists.** What does not exist is any behaviour for when the refresh *stops* happening — rows persist unchanged and indefinitely.

---

## 3. The policy — what it says unambiguously

| Rule | Verbatim | Source |
| --- | --- | --- |
| Retention ceiling | *"All data may only be retained by you for a maximum of 10 days trailing from the date when the data is received, unless subject to a shorter local regulation. Data, including user data and device data, must be deleted."* | [policies](https://developers.home.google.com/policies) |
| AI/ML prohibition | *"Using data from any Google Home Developer Platform integration, including the Home APIs & Home Hub Runtime, for training artificial intelligence models or any other related tools is prohibited."* | [policies](https://developers.home.google.com/policies) |
| …and it reaches derived data | *"These requirements apply to the raw data obtained from the scopes and data aggregated, anonymized, or derived from them."* | [API Services User Data Policy](https://developers.google.com/terms/api-services-user-data-policy) |
| Monetisation / redistribution | *"Without the prior written consent of Google, (1) sharing, sublicensing, reselling, or redistributing to any other party any information provided by the Home APIs & Home Hub Runtime, (2) otherwise monetizing any information provided by the Home APIs & Home Hub Runtime…"* | [policies](https://developers.home.google.com/policies) |
| Advertising / data brokers | *"Transferring or selling user data to third parties like advertising platforms, data brokers, or any information resellers."* · *"Transferring, selling, or using user data for serving ads, including retargeting, personalized or interest-based advertising."* | [API Services User Data Policy](https://developers.google.com/terms/api-services-user-data-policy) |
| De-obfuscation | *"Attempting to: (1) extract PII of users…, (2) deobfuscate identities, including from API-returned obfuscated identities and/or (3) share inferred data with other parties."* | [policies](https://developers.home.google.com/policies) |
| Deletion on revocation | *"Each time the app starts, be sure to check that the permissions are still in effect. If they have been revoked, then be sure that all previous data are removed, including any data cached in the application."* | [Permissions API](https://developers.home.google.com/apis/android/permissions) |
| Name/room write-back | *"If the customer has the ability to change the name of a device, or the association between a device and a room in your application, this information must be replicated to the Home APIs & Home Hub Runtime so that the view of a customer's home remains consistent across clients."* | [policies](https://developers.home.google.com/policies) |
| Privacy policy | Must be linked in the Developer Center and comprehensively disclose collection, use and sharing. | [policies](https://developers.home.google.com/policies) |

The Home APIs policy **incorporates the API Services User Data Policy by reference**, so Limited Use restrictions apply cumulatively — they are not alternatives.

**No definition of "data" or "user data" exists on the policies page**, and there is **no documented exception** to the 10-day ceiling for aggregated data, anonymised data, operational necessity, error logs, audit records, or legal-hold. The only modifier in the text makes the window *shorter*, never longer.

---

## 4. Data classification matrix

`Persist?` and `Max retention` below are **recommendations**, not policy quotes. Classification as Google-derived vs IXORA-authored is the load-bearing distinction.

| Data | Source | Persist? | Max retention | IXORA DB target | Notes |
| --- | --- | --- | --- | --- | --- |
| Google structure id | Google-derived | **No (backend)** | — | — | Keep on device only (§6). Not stored today. |
| Structure name | Google-derived | **No** | — | — | Display from device-held copy. |
| `provider_device_id` (Google) | Google-derived | **No (backend)** | — | — | **The crux — see §5.** Device-held mapping. |
| Device name (from Google) | Google-derived | Yes, transient | 10 days from last sync | `devices.name` | Blanked on expiry; row survives. |
| Device type | Google-derived (mapped to IXORA vocabulary) | Yes, transient | 10 days | `devices.type` | Mapping is IXORA logic; the *input* is Google's. Conservative: treat as derived. |
| Traits → capabilities | Google-derived (mapped, ADR-033) | Yes, transient | 10 days | `devices.capabilities` | Same reasoning as type. |
| Current state / `status` | Google-derived | Yes, transient | 10 days (shorter is better) | `devices.status` | Lowest value, highest sensitivity. Prefer read-through, no persistence. |
| `last_seen_at` | Google-derived (timestamp of a Google read) | Yes | — | `devices.last_seen_at` | **Becomes the expiry anchor (§6).** A timestamp of *our* observation, not Google content. |
| Raw provider payload | Google-derived | Yes, transient | 10 days | `devices.metadata` | Highest-risk column; purge first. |
| Room | Google-derived | **No** | — | — | Not stored today. Do not start. |
| Device row identity (`devices.id`) | IXORA-authored | Yes | indefinite | `devices.id` | Internal surrogate key. |
| User-typed alias | IXORA-authored (**contested — §10.2**) | Yes | indefinite (proposed) | new column, not `devices.name` | Must be separated from the Google name, and write-back applies (§3). |
| `user_id`, `provider_connection_id`, `provider` slug | IXORA-authored | Yes | indefinite | `devices`, `provider_connections` | No Google content. |
| Scene / Scene action configuration | IXORA-authored | Yes | indefinite | `scenes`, `scene_actions` | References `devices.id`, never a Google id. |
| Vibe and Schedule references | IXORA-authored | Yes | indefinite | `vibes`, `schedules` | Unaffected. |
| Execution outcome records | IXORA-authored | Yes | 90 days (ADR-034) | `scene_action_executions` | **Contains no Google data — unchanged.** |
| Command result / failure category / status code | IXORA-authored | Yes | 90 days | `scene_action_executions` | Outcome of *our* call, not Google content. |
| Execution timestamps, `trace_id` | IXORA-authored | Yes | 90 days | `scene_action_executions` | — |
| Application logs | IXORA-authored | Yes | 14 days | Loki | Verified: internal ids only (§2). |
| Metrics / traces | IXORA-authored | Yes | 30d / 7d | Prometheus / Tempo | ADR-030 already forbids entity ids. |
| Google authorization state / tokens | Google | **Never on backend** | — | — | ADR-036 Decision 8. Device-side, encrypted storage. |

---

## 5. The core conflict: no safe harbour for core functionality

A Scene action stores `device_id` — an internal key. To *execute* it against Google Home, something must map that key to a Google `provider_device_id`. If the backend holds that mapping beyond 10 days, it retains Google data beyond the ceiling. If nothing holds it, a Scene configured today stops working in eleven days.

The policy offers no way out. There is no documented exception for "data necessary to deliver the functionality the user asked for" — which is unusual, and is the single most important finding of this task. The conflict is equally real for:

- a saved automation pointing at a specific lamp;
- a device's last known state shown in the UI for long-term UX;
- the device name, if IXORA treats the Google-provided name as durable.

**Not found in the documentation, and decisive:** whether the 10-day clock **restarts on each re-read**. If it does, an app in regular use never holds stale Google data and the problem largely dissolves in practice. If it does not, even active use cannot cure it. The policy defines neither "data received" nor the behaviour of the clock on repeated reads (§10.3).

---

## 6. Recommended mechanism — put Google data where the architecture already put execution

ADR-036 Decision 7 already places Google Home execution, authorization and the SDK on the device. **Place the Google-derived identifiers there too.** This is not a workaround invented for the policy; it is the consistent conclusion of a decision already taken.

**Proposed shape (to be specified by an implementation task, not built here):**

1. **The backend never durably stores Google identifiers.** `devices` holds an IXORA-authored row: internal id, `user_id`, `provider_connection_id`, `provider` slug, and a user-authored alias.
2. **The device holds the mapping** `internal device id ↔ Google provider_device_id`, in encrypted device storage, refreshed from the SDK on app start — which is required anyway, since permissions must be re-checked at every start and revoked data purged.
3. **Google-derived display fields on the backend are cache, not record.** `name`, `type`, `capabilities`, `status`, `metadata` are refreshed by sync and **expire from `last_seen_at`**, which already exists. **No `expires_at` column is needed** — a scheduled purge blanking Google-derived columns where `last_seen_at < now() - 10 days`, leaving the row and its IXORA-authored fields intact, is simpler and reuses the daily purge pattern ADR-034 already established for `scene_action_executions`.
4. **The user-authored alias is the durable display name**, so the UI degrades gracefully when the Google name expires: the Scene still reads "Abajur do quarto" and remains editable. Note the write-back obligation in §3 — if IXORA lets the user rename a device, that change must be replicated to the Home APIs.
5. **Revocation purges immediately**, not on the 10-day schedule, per the Permissions API obligation.

**Accepted cost:** a Scene configured on one phone will not resolve its Google devices on a second phone until that phone syncs. This is consistent with Google consent being per-device and per-structure anyway, and with ADR-036's device-side execution model.

**Explicitly rejected:** inventing a "legitimate interest" or "operational necessity" exception that the policy does not grant. ADR-036 §8 already forbids designing bypasses for platform constraints, and this would be one.

---

## 7. Observability boundary

**Current logging, metrics and tracing require no change.** Verified in code: no Google-derived identifier or content reaches any of them.

The boundary to hold going forward — a rule for implementation tasks, since the policy does not address it (§10.4):

- ✅ Permitted, retained normally: *"command failed at 22:00 for internal device #57, provider google_home, outcome failure, status 502"* — internal identifiers only.
- ❌ Forbidden: the Google `provider_device_id`, the Google device name, structure id or name, raw trait payloads, or device state, in any log line, span attribute, metric label or exception message.

This extends ADR-030's existing rule (which *discouraged* Home Assistant entity IDs) into a hard prohibition for Google-derived identifiers, and should be enforced the way the project already enforces provider neutrality — by a test, not by convention.

**Interpretation, stated as such:** a log line containing no data received from the Home APIs falls outside the literal scope of a rule about retaining *"data… received"*. The policy does not address this case; this is IXORA's engineering judgement, and it is recorded here so it can be revisited rather than silently assumed.

---

## 8. Analytics boundary — matters for v1.5.0

v1.5.0 (Analytics) is planned separately and its scope is unchanged by this document. The constraint it inherits:

- ❌ **No Google-derived data may feed Analytics.** The prohibition on AI/ML training explicitly reaches *"data aggregated, anonymized, or derived"*, so anonymising or aggregating Google data does **not** make it usable for model training. Selling, sharing or advertising use is prohibited outright.
- ⚪ **Internal product analytics is not addressed by the policy.** It names sharing with third parties, advertising and monetisation; it neither permits nor forbids first-party product metrics by name. **Not found in the documentation** — engineering and legal judgement.
- ✅ **Safe by construction:** analytics over IXORA-authored facts — how many Scenes a user has, how often a Vibe runs, execution success rates by provider slug — uses no Google data at all. **Recommendation: scope Analytics to IXORA-authored facts and keep Google-derived fields out of the analytics pipeline entirely.** That removes the question rather than answering it.

---

## 9. Storage classification — backend and mobile

**`back_vibes`**
- *Safe persistent:* internal device id, `user_id`, `provider_connection_id`, provider slug, user-authored alias, Scene/Vibe/Schedule configuration, execution outcome records, internal-id logs and telemetry.
- *Persistent with restrictions:* `devices.name`, `type`, `capabilities`, `status`, `metadata` — cache only, expiring from `last_seen_at`.
- *Ephemeral / cache:* current device state — prefer read-through over persistence.
- *Do not store:* Google OAuth tokens, structure id, structure name, room, `provider_device_id` (per §6).

**`front_vibes` (Android)**
- *Secure storage required:* Google authorization state (held by the SDK), the internal-id ↔ `provider_device_id` mapping.
- *Ephemeral:* device state, trait payloads.
- *Purge triggers:* permission revoked (checked at every app start, mandatory), provider disconnected, user logout.
- *Do not store:* anything Google-derived in plain `localStorage`. Note the existing project rule that token persistence uses `@capacitor/preferences`, never `localStorage`.

---

## 10. Open questions — engineering judgement and legal

1. 🔴 **Is there any lawful way to keep a saved automation working past 10 days?** §6 minimises exposure by moving identifiers to the device, but the device still retains a Google identifier beyond 10 days. **This needs a legal opinion, not an architectural one.** It is the highest-severity item in this document.
2. 🟠 **Is a user-typed alias "data received" from the Home APIs?** The user typed it, but it exists only to label a Google device. The policy neither confirms nor excludes it. §4 treats it as IXORA-authored — the more permissive reading. Flagged so the choice is visible.
3. 🟠 **Does the 10-day clock restart on each re-read?** Undefined. Decisive for whether normal app use cures staleness (§5).
4. 🟡 **Are internal-only logs outside scope?** §7 says yes by literal reading; the policy is silent.
5. 🟡 **Is first-party product analytics permitted?** Not addressed (§8). Sidestepped by scoping Analytics to IXORA-authored facts.
6. 🟡 **Is deletion required on app uninstall or structure deletion?** The documented obligation attaches to *revoked permissions checked at app start*. Uninstall without revocation is not covered.
7. 🟡 **Does mapped/derived data inherit the 10-day ceiling?** Device type and capabilities are IXORA vocabulary computed from Google input. §4 treats them conservatively as derived.
8. ⚪ Must the retention period be disclosed to end users? Only general transparency is required; the "10 days" figure is not explicitly mandated.

---

## 11. Consequences for v1.6.0

- **No change to `scene_action_executions`, logs, metrics or traces.** The 90-day and 14-day windows stand.
- **`devices` needs a purge job and a column split** (Google-derived cache vs IXORA-authored alias). Both are implementation tasks, deliberately not carded here.
- **ADR-036 Decision 8 is confirmed and sharpened**: the "facts obtained from the Home APIs expire; facts the user authored do not" boundary survives contact with the actual policy text, with the alias question (§10.2) as its one soft edge.
- **This does not block GH02.** The spike stores nothing durably.
- **Item §10.1 should be resolved before the implementation backlog is built**, since it can change the schema.

---

## 12. Sources

[Google Home Developer Policies](https://developers.home.google.com/policies) · [Google API Services User Data Policy (Limited Use)](https://developers.google.com/terms/api-services-user-data-policy) · [Permissions API on Android](https://developers.home.google.com/apis/android/permissions) · Internal: [ADR-030](../../../decisions/ADR-030-observability-security-and-privacy.md), [ADR-031](../../../decisions/ADR-031-retention-storage-and-cost-control.md), [ADR-034](../../../decisions/ADR-034-partial-execution-outcome.md), [ADR-036](../../../decisions/ADR-036-google-home-execution-model.md), [GH03a](access-gate.md)

**Verification caveat:** §3's privacy-policy row was extracted via search summary rather than a confirmed verbatim fetch. Before drafting IXORA's user-facing privacy policy, re-fetch that subsection directly.
