# GH03c §C — Draft inquiry to Google (Home APIs data retention)

**Status:** 📄 **Drafted and parked, not sent.**
**Decision (PO, 2026-09-19):** Ixora is not publishing to production and will remain in development for the foreseeable future. The retention question blocks production only, so it is **documented and deferred**, not pursued now. This draft exists so that whoever picks the production track up later does not have to reconstruct the questions — they were derived from [GH03c](gh03c-retention-compliance-review.md) §C while the analysis was fresh.
**Governing documents:** [ADR-036](../../../decisions/ADR-036-google-home-execution-model.md) Decision 8 · [GH03b](data-retention.md) §10.1–§10.3 · [GH03c](gh03c-retention-compliance-review.md) §3, §5
**Trello:** GH-COMPLIANCE — Google Home Device Data Retention Before Production

---

## Why this draft exists

GH03c resolved what the public policy text can resolve and stopped where the text runs out. Four of its seven questions came back **UNRESOLVED** — not because the analysis was incomplete, but because Google's published documentation does not answer them. The only paths left are a direct written inquiry to Google through the channel the program already requires for production, or a formal legal opinion. The questions below are the same either way.

**What is actually at stake:** a saved Scene that keeps referencing a specific Google Home device across sessions — the central capability of the feature. Interactive, session-scoped control (discover, read, command, discard) is not affected and was already judged safe in GH03c §A.

## How to send it, when the time comes

Through the official Home APIs developer support / program access channel, from the account associated with project `project-443152571832`. Ask for a **written** answer: the point is to have something archivable as compliance evidence. If no binding answer arrives in reasonable time, the same text is the basis for a legal opinion request.

Fill in `[nome]`, `[cargo]` and `[e-mail de contato]` before sending.

---

## Draft

**Subject:** Home APIs — data retention policy clarification: device identifiers required for user-configured persistent automations

Hello,

We are building an Android application that integrates with the Home APIs. Before we finalize our production data model, we need clarification on how the 10-day retention rule in the Google Home Developer Policies applies to a specific, central use case. We have reviewed the Home APIs & Home Hub Runtime policies, the Google API Services User Data Policy, the Home Additional Terms and the Google APIs Terms of Service, and we could not resolve these questions from the published text.

**Our use case.** A user connects their Google Home account and configures a scene: "when I start my *Deep Sleep* mix, turn on the bedroom lamp." That configuration is saved and must keep working weeks or months later, every time the user starts that mix. To honour it, our system has to keep some durable reference to the specific device the user chose.

**The tension.** The policy states that all data obtained from the Home APIs may be retained for a maximum of 10 trailing days. A saved automation, by definition, needs a device reference that outlives that window. We note that the Smart Device Management API policies contain an explicit carve-out excluding Device ID and Name from the equivalent 10-day prohibition, but that carve-out is not present in, or incorporated by, the Home APIs policies. We are not assuming it applies here.

**Our questions.**

1. **Scope of "data."** Does the 10-day retention limit apply to device identifiers specifically, or only to device state and user content? Is there an official categorization distinguishing identifiers, metadata and content for the Home APIs?

2. **Does re-fetching reset the window?** If our app re-reads a device from the Home APIs within the 10-day period, does the retention clock restart from that most recent read? The policy uses the word "received" but does not define it, and the practical consequence is significant: if re-reading resets the window, an app that periodically refreshes would remain compliant indefinitely.

3. **Storage location.** Does it make any difference whether the data is stored on our backend servers or only locally on the user's own Android device? The phrase "retained by you" carries no locus qualifier, so we assume no difference — please confirm.

4. **Irreversible internal references.** If we do not store the Google device identifier itself, but instead a one-way, irreversible internal reference derived from it (from which the original identifier cannot be recovered), is that internal reference still considered retained data under the policy?

5. **Functionality explicitly requested by the user.** Is there any provision allowing a device identifier to be retained beyond 10 days when it is strictly necessary for a persistent automation the user themselves configured and expects to keep working? If such retention is permissible under conditions, we would like those conditions stated explicitly so we can implement against them.

6. **If none of the above applies:** is there a Google-endorsed pattern for implementing persistent, user-configured automations that reference a specific Home API device, without retaining any device-derived data beyond 10 days? If the intended answer is that such automations must be built through the Automation API rather than through an app's own references, we would appreciate that being confirmed, since it materially changes our architecture.

**What we do today, for transparency.** Our current development build discovers devices on the Android device via the SDK and stores the device identifier on our backend so that saved scenes remain executable. We have not shipped this to production and will not do so until this question is settled — which is why we are asking before launch rather than after.

We would appreciate a written answer we can retain for our own compliance records. We are happy to provide additional detail about our implementation if that helps.

Thank you,
[nome] — [cargo]
Ixora / project-443152571832
[e-mail de contato]

---

## Notes on the drafting choices

- **It discloses current behaviour instead of hiding it.** Asking "may we do X?" while already doing X tends to cost more later than being upfront. The disclosure is paired with the fact that nothing has shipped to production.
- **Question 6 exists to make a "no" useful.** If the answer is that app-held device references are simply not the intended pattern, that redirects the architecture — a negative answer that is still actionable.
- **It asks for a written reply** because the value of the exercise is producing an archivable compliance artifact, not just an opinion in a support chat.
- Questions map to GH03c: 1 → §3.1, 2 → §3.3, 3 → §3.4, 4 → §3.5, 5 → §3.6, 6 → §3.7.

## What happens meanwhile

Per the PO decision above, development continues with the current implementation. `ReportedDeviceSyncService` remains the single authorized write site for `provider_device_id` on a client-reported provider, carrying the `GH-COMPLIANCE` comment that marks it as a development-time decision rather than a confirmed compliant solution. The v1.6.0 release note records this as a production blocker; nothing about it blocks development or staging QA.
