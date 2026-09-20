# GH03a — Google Home access gate: development, certification and production path

**Task:** v1.6.0 — GH03a (first half of GH03; retention and data classification are GH03b)
**Date:** 2026-09-06
**Type:** Investigation. No production code, migrations or configuration were changed.
**Governing decision:** [ADR-036](../../../decisions/ADR-036-google-home-execution-model.md) — Hybrid Provider Execution Model.

Every normative claim below carries an official Google source. Where the documentation does not answer, the item says **"não encontrado na documentação oficial"** and is listed as an open risk. Nothing here is inferred by analogy with other Google APIs.

---

## 1. Executive conclusion

There are **two different gates**, and merging them into one verdict would be misleading:

| Gate | Verdict | Why |
| --- | --- | --- |
| **Can GH02 (the Android spike) start?** | 🟢 **GREEN** | Developer Console registration is explicitly *not* required to test and use the Home APIs. An unverified app gets access to **all** supported device types. No certification blocks discovery or commands in development. |
| **Can v1.6.0 be launched to production?** | 🔴 **RED — external, no published date** | The Google Home Developer Console **is not open for registration**. Verified state requires it. No app can reach production today, regardless of anything IXORA does. |

**Recommendation:** proceed with GH02, and do **not** commit to a v1.6.0 launch date. The spike is cheap relative to the release, validates the ADR-036 architecture, and answers the one question documentation cannot (whether the user's own Surplife/Tuya devices are reachable). But planning a launch against a third-party gate with no published date would be planning on a wish.

The production prerequisites that are **not** blocked by Google (public homepage, privacy policy on a verified domain, Search Console verification, release-key SHA-1) are entirely within IXORA's control and can proceed in parallel — see §7.

---

## 2. GH02 gate — evidence

Verbatim, from the official OAuth setup page:

> "Google Home Developer Console registration is not required to test and use the Home APIs."

The Permissions API page **inverts** the assumption carried into this investigation — verification *restricts* access, it does not grant it:

> "An unverified app will have access to devices of any device types that are supported by OAuth for the Home APIs (the list of device types in the Developer Console). **All devices in a structure will be granted.**"

> "If an app is registered in the Developer Console and has been approved for access to one or more device types, and brand verification has been completed for OAuth, it will be in a verified state. […] The user can only grant permission to the device types that were approved in the Developer Console."

Constraint that applies while unverified:

> "Only users registered as test users in the OAuth console can grant permissions for the app. There is a limit of 100 test users for an unverified app."

100 test users is ample for a spike and a closed beta; it is not a launch.

**Not found:** any documented restriction on *sending commands* tied to the unverified state.

Sources: [OAuth setup](https://developers.home.google.com/apis/android/oauth) · [Permissions API](https://developers.home.google.com/apis/android/permissions)

---

## 3. Production gate — the blocker

Confirmed **verbatim on two independent official pages** ([Android OAuth setup](https://developers.home.google.com/apis/android/oauth), [Android overview](https://developers.home.google.com/apis/android/overview)):

> "The Google Home Developer Console is not yet available for registration."

The get-started flow marks the final steps as **"Coming soon"**:

- Step 7 — "In the Developer Console, get approved for user devices you'd like to access" — *Coming soon*
- Step 8 — "Launch your app in the Play Store" — *Coming soon*

The Console is described as covering "all stages of a Home APIs project, from brand verification, to developing, testing, and certifying to ultimately launching". Since verified state requires registration, and registration is closed, **production is unreachable today**.

**Not found:** any date, waitlist, or opening criteria.

⚠️ **Documentation is self-contradictory on this point.** The "not yet available for registration" text coexists with a linked, login-capable `console.home.google.com` and with quota documentation that refers to "your app's registration in Google Home Developer Console". The real state cannot be settled from documentation alone — **attempting the registration is the only way to know**, and that is a concrete recommended action (§9).

---

## 4. Development requirements — required for dev vs required for production

| Item | Development | Production | Source |
| --- | --- | --- | --- |
| Google Cloud project | ✅ | ✅ | oauth |
| OAuth client, type **Android (native)** | ✅ | ✅ | oauth |
| **SHA-1 fingerprint** (debug key is sufficient for dev) | ✅ | ✅ (release key) | oauth |
| OAuth scopes | ❌ none — "You don't need to add any scopes" | não encontrado | oauth |
| Test users on the consent screen (≤100) | ✅ | — | permissions |
| **Google Home Developer Console registration** | ❌ **not required** | ✅ **closed today** | oauth, overview |
| Device-type approval | ❌ (unverified gets all) | ✅ | permissions |
| Brand verification | ❌ | ✅ | brand-verification |
| Android Studio 2024.2.1 "Ladybug"+, adb | ✅ | ✅ | sdk |
| Physical Android device, **Android 10+** | ✅ | ✅ | sdk |
| Play Console / Play Store listing | não encontrado | Step 8, *Coming soon* | get-started |
| Backend credential of any kind | ❌ **none found** | ❌ none found | see §8 |

---

## 5. OAuth, consent and structures

- Mechanism: OAuth 2.0 with an Android client bound to package name + SHA-1. Consent screen with **no scopes added**.
- **One structure at a time**: *"An application can only be granted permission to one structure at any given time."* Switching requires `requestPermissions()` with `ForcePermissionFlow.FORCE_LAUNCH`.
- Granularity is three-level: structure → device type → individual device (for sensitive types). *"If a user has three locks, they can grant access to only one of those locks."*
- Revocation detection: `hasPermissions()` returns a `Flow` of `PermissionsState` (`GRANTED`, `NOT_GRANTED`, `PERMISSIONS_STATE_UNAVAILABLE`). Users revoke via Google MyAccount → Data & privacy → Third-party apps, or Google Home app → Linked Apps.
- Explicit obligation on revocation: *"Each time the app starts, be sure to check that the permissions are still in effect. If they have been revoked, then be sure that all previous data are removed, including any data cached in the application."* Also: *"all existing automations will stop working."*
- **IXORA login vs Google Home authorization:** the consent flow begins with *"The user is prompted to select the Google Account they want to use"*, which evidences account selection at consent time, independent of the app's own login. Explicit confirmation that this may be a **different** account from the Firebase login is **não encontrado na documentação oficial** — treat as probable, verify empirically in GH02.
- **Open risk — 7-day refresh token:** Google Identity documents that a project with an external consent screen in "Testing" publishing status is issued a refresh token expiring in 7 days, except when only basic scopes are requested. Since Home APIs instruct adding *no* scopes, applicability cannot be determined from documentation. Not inferred. If it applies, the POC may need re-consent weekly — an annoyance, not a blocker.
- Device moving between structures, or structure deletion: **não encontrado na documentação oficial**.

---

## 6. Device accessibility

The baseline claim is **confirmed verbatim**:

> "This data model covers all types of devices (from Google Nest or 3rd party manufacturers), regardless of the underlying smart home technology (such as Matter or Cloud-to-cloud)."

> "A Matter device type or trait takes precedence over a Cloud-to-cloud analog."

Real conditions that determine availability:

1. The device must be in the **granted structure** (one at a time).
2. In verified state, its **device type** must be approved in the Console. (Unverified: all types.)
3. Sensitive types require per-device grants.
4. Trait/attribute/command support varies **per device** and must be checked at runtime — *"Each trait has methods to check whether a trait supports a specific attribute or command… since not all devices in a device type are expected to have all the same features."*
5. *"Provisional Matter device types and clusters are not supported."*

**Surplife / Tuya specifically:** documentation supports that third-party cloud-to-cloud devices enter the unified model, but it **cannot** establish that a particular Surplife product is reachable — that depends on its device type being in the supported list and on which traits it exposes. This is an **empirical question for GH02**, not answerable here. Any definitive answer at this stage would be invention.

Sources: [Data model](https://developers.home.google.com/apis/android/data-model) · [Supported device types](https://developers.home.google.com/apis/android/supported-device-types)

---

## 7. Production path — what IXORA still lacks

Blocked by Google (cannot be started today): Developer Console registration; device-type approval; brand verification completion.

**Not blocked — IXORA can do these in parallel, and they are the real critical path once the Console opens:**

- Public **homepage** describing the app, on a domain IXORA owns.
- **Privacy policy published on the same domain** as the homepage. (The known `staging-api.ixora-app.app` is an API host, not a public homepage.)
- **Domain ownership verified** in Google Search Console.
- **Video** demonstrating the end-to-end OAuth consent flow.
- **Release-key SHA-1** registered (development uses the Android Studio debug key).

Terms of service: optional. Third-party **security assessment** applies to *restricted scopes*; since Home APIs add no scopes, there is no evidence it is triggered — **não encontrado na documentação oficial**, recorded as an open risk rather than dismissed.

Sources: [Brand verification](https://developers.google.com/identity/protocols/oauth2/production-readiness/brand-verification) · [Verification requirements](https://support.google.com/cloud/answer/13464321)

---

## 8. Secrets and configuration boundary

| Item | Lives in | Note |
| --- | --- | --- |
| OAuth client (native/Android) | Google Cloud configuration | — |
| SHA-1 fingerprint | Google Cloud config, derived from the app keystore | debug key for dev, release key for prod |
| Package name | mobile app ↔ Cloud config | `app.ixora.ixora` |
| Test user emails | Google Cloud config (consent screen) | ≤100 |
| Client secret | **not applicable** — the Android client is described with package name + SHA-1 only | — |
| App Check / Play Integrity / attestation | **não encontrado na documentação oficial** for Android Home APIs | — |

**`back_vibes` requires no Google credential for this integration.** No server-side credential requirement was found anywhere in the Home APIs documentation, consistent with the absence of a server-side surface. Recorded as *confirmed by absence*, not by positive statement — which is the strongest form available and is sufficient for ADR-036 Decision 8.

---

## 9. Divergences against the ADR-036 §3 baseline

Four findings that the ADR must absorb. Items 1 and 2 are material.

1. 🔴 **The Developer Console is closed for registration.** ADR-036 §3 treats production certification as a process IXORA can start. It cannot. This is an external roadmap blocker with no published date. **ADR-036 §3 needs an addendum.**
2. 🟠 **The Android SDK is not distributed through Maven.** *"The Home APIs in this open beta are not yet part of the standard libraries provided by Google for development"* — the libraries must be downloaded and hosted locally (artifact `home.android.sdk_GHP_1_10_1` in a GCS bucket of project `home-api-public-beta`). GA quality, non-standard distribution channel. **Direct impact on GH02 setup and on build reproducibility / supply chain.**
3. 🟢 **Device-type approval does not block development** (favourable divergence). The earlier reading suggested certification could block the spike. It does not: unverified grants all supported device types and all devices in the structure.
4. ⚠️ **Risk of conflation.** Three distinct processes sit close together in the policy pages: Matter **hardware** certification, **Cloud-to-cloud** integration certification (for manufacturers), and **device-type approval** for Home APIs in the Developer Console. Google states it "only certifies hardware devices and not, for example, apps, software, or IoT systems". ADR-036 and all derived cards must name which one they mean.

**Recommended action:** amend ADR-036 §3 with an addendum recording items 1 and 2, rather than silently leaving a known-wrong assumption in an Accepted ADR. Not done here — amending an Accepted ADR is a PO call.

---

## 10. GH02 preparation

So GH02 does not repeat this investigation.

**Accounts and console setup (before the spike):**
1. Create/choose a Google Cloud project.
2. Configure the OAuth consent screen, **External**, adding **no scopes**.
3. Add the developer's own Google account as a **test user**.
4. Create an OAuth client of type **Android**, with package name `app.ixora.ixora` and the **debug keystore SHA-1**.
5. Do **not** attempt Developer Console registration as a prerequisite — it is not required, and it is closed. (Attempting it once, to resolve the documentation contradiction in §3, is worthwhile as a separate 10-minute check.)

**Hardware — nothing needs to be purchased:**
- Physical Android device, Android 10+ — the project's Motorola Edge 2023 qualifies. Emulator is **rejected**; a real device is required.
- Google account, Wi-Fi, a Google Home structure with at least one supported device.
- **A Google hub is required only for Matter devices.** Cloud-to-cloud devices work without one. This matters because Nest/Home hubs are **not sold in Brazil** — Brazil does not appear on Google's official list of countries where Nest/Home devices are sold. If the user's existing Surplife/Tuya devices are linked as cloud-to-cloud, the spike runs on existing hardware at zero cost.
- Android Studio 2024.2.1 "Ladybug"+ and adb.

**Build setup caveat:** the SDK must be downloaded and hosted locally (§9.2) — budget time for this; it is not a one-line Gradle dependency.

**Stop conditions for GH02:**
- If consent cannot be registered in the Capacitor lifecycle without forking `BridgeActivity` — stop and report (carried from the GH02 card).
- If the user's Surplife/Tuya devices do **not** appear through the Home APIs despite being visible in the Google Home app — stop and report. This changes the strategic premise of the whole initiative and would strengthen the case for Tuya Cloud.
- If the 7-day refresh token expiry (§5) makes iterative development impractical — report, do not work around it.

---

## 11. Impact on v1.6.0 and open risks

| # | Risk | Severity | Note |
| --- | --- | --- | --- |
| 1 | Production path closed by Google, no published date | 🔴 | Largest roadmap risk. Entirely outside IXORA's control. Requires an explicit product decision on whether to build ahead of an unknown opening date. |
| 2 | SDK outside the standard distribution channel | 🟠 | Affects build reproducibility and supply chain; needs a hosting decision. |
| 3 | 100 test-user ceiling while unverified | 🟠 | Fine for POC and closed beta; blocks public launch. |
| 4 | Data retention ≤10 days; no AI training on the data | 🟠 | Confirmed policy. Detailed treatment is **GH03b**. |
| 5 | Google hubs not sold in Brazil | 🟡 | Only matters if Matter is in scope. Cloud-to-cloud avoids it. |
| 6 | Home APIs regional availability in Brazil | 🟡 | No documented restriction **and** no documented confirmation. Open. |
| 7 | 7-day refresh token in "Testing" status | 🟡 | Applicability undetermined. |
| 8 | Google documentation self-contradictory on Console state | 🟡 | Resolve empirically. |
| 9 | Workspace vs personal account; billing; dev account = test account; structure deletion behaviour | ⚪ | Not found; low impact. |

**Does anything make Google Home unviable?** No — but risk 1 means v1.6.0 can be *built* and cannot yet be *shipped*. The evidence also modestly strengthens the Tuya Cloud fallback (ADR-036 §4 re-entry triggers), because Tuya's server-side API has no equivalent third-party launch gate. It does not change the KMP evidence, which stays *moderate*.

---

## 12. Official references

[Home APIs overview](https://developers.home.google.com/apis) · [Android overview](https://developers.home.google.com/apis/android/overview) · [Android get started](https://developers.home.google.com/apis/android/get-started) · [Android SDK setup](https://developers.home.google.com/apis/android/sdk) · [OAuth setup](https://developers.home.google.com/apis/android/oauth) · [Permissions API](https://developers.home.google.com/apis/android/permissions) · [Data model](https://developers.home.google.com/apis/android/data-model) · [Supported device types](https://developers.home.google.com/apis/android/supported-device-types) · [Connectivity](https://developers.home.google.com/apis/android/connectivity) · [Automation API](https://developers.home.google.com/apis/android/automation) · [Quota management](https://developers.home.google.com/apis/android/quota-management) · [Android release notes](https://developers.home.google.com/apis/android/release-notes) · [Developer Policies](https://developers.home.google.com/policies) · [Sample app authorization](https://developers.home.google.com/apis/android/sample-app/authorization) · [HomeGraph REST reference](https://developers.home.google.com/reference/home-graph/rest) · [Google Identity OAuth 2.0](https://developers.google.com/identity/protocols/oauth2) · [Brand verification](https://developers.google.com/identity/protocols/oauth2/production-readiness/brand-verification) · [OAuth verification requirements](https://support.google.com/cloud/answer/13464321) · [Where Nest/Home devices are sold](https://support.google.com/product-documentation/answer/9718161)
