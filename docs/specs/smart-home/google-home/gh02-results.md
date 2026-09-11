# GH02 — Android spike results: real device discovery and control

**Task:** v1.6.0 — GH02 (Spike: Capacitor plugin + Home SDK Android)
**Date:** 2026-09-06
**Type:** Technical spike, physically verified. Not production code.
**Governing decision:** [ADR-036](../../../decisions/ADR-036-google-home-execution-model.md).
**Precondition:** [GH03a](access-gate.md) gate — GREEN.
**Code:** `front_vibes`, branch `feature/gh02-google-home-android-spike`, commits `fcb1c4c` (scaffold: Kotlin enabled, plugin registered, bridge round-trip proven with no SDK dependency) and `3ae9f1b` (real SDK wiring, device discovery, state read, on/off execution). **`3ae9f1b` is the exact implementation that passed the physical test recorded in §5** — every JSON result and the confirmed physical lamp behavior below came from that commit, unmodified, running on the device described in §2. The branch is kept as a historical reference and is not merged into `develop` — see §9.

---

## 1. Goal and verdict

The GH02 card asked one question: can the Ixora Android app, through a Capacitor bridge, discover a real Google Home device and turn it on/off? **Yes — verified end to end on physical hardware, not simulated, not just "the API returned success".**

The device tested was a real Surplife/Tuya-ecosystem lamp already linked to the user's Google Home as a cloud-to-cloud device. This is the central strategic bet behind choosing Google Home over a direct Tuya integration (ADR-036, and the v1.6.0 card): that third-party brand devices become reachable through one aggregator integration, without a brand-specific adapter and without a Google hub. **That bet is now confirmed with a real device, not only with documentation (GH03a).**

## 2. Environment

- Device: Motorola Edge 2023, Android 15 (API 35) — physical, USB-connected. The SDK requires a real device; an emulator is not supported.
- SDK: `com.google.android.gms:play-services-home:17.1.0` and `play-services-home-types:17.1.0`, downloaded from the Google-authenticated portal per [GH03a finding B](access-gate.md#9-divergences-against-the-adr-036-3-baseline) (not on Maven), added as a local Maven repository, gitignored — each developer downloads their own copy.
- Google Cloud project with an Android OAuth client (package `app.ixora.ixora`, debug SHA-1), consent screen External/Testing, no scopes, the developer's own account as test user — per GH03a, none of this required Developer Console registration.
- OAuth Branding (Homepage, Privacy Policy, Terms of Service) published to `app-vibes-dev` Firebase Hosting to satisfy Google's verification step (see `ixora-infra` PR history for that change — out of scope for this document).

## 3. What was built

- Kotlin enabled in the `front_vibes` Android module (previously 100% Java). Real build issue found and fixed along the way: the Kotlin Gradle plugin version had to be bumped twice — first to 2.1.0 because `@capacitor/filesystem` already resolves `kotlin-stdlib` 2.1.0 transitively, then to 2.2.0 because the Home SDK's own POM requires it.
- A `GoogleHome` Capacitor plugin (`app/src/main/java/app/ixora/googlehome/GoogleHomePlugin.kt`) with five methods: `ping`, `requestGoogleHomePermissions`, `listDevices`, `readDeviceState`, `executeAction`.
- `registerPlugin(GoogleHomePlugin::class)` called before `super.onCreate()` in `MainActivity`, and `Home.getClient()` / `registerActivityResultCallerForPermissions()` wired in the plugin's `load()` — which runs during bridge init, inside `BridgeActivity.onCreate()`. This satisfies the SDK's consent-registration timing requirement **without forking `BridgeActivity`**, which was GH02's first documented stop condition. It did not need to be triggered.
- A temporary debug page (`src/views/dev/GoogleHomeDebugPage.vue`, routed at `/dev/google-home`, linked from a temporary entry at the bottom of Settings) to drive the plugin's methods interactively and see raw JSON output on screen. This was necessary because remote WebView debugging (Chrome DevTools Protocol over `adb forward`) did not respond in this environment despite the debug socket being present — not investigated further, since the UI-driven path was faster and just as conclusive. **This page is temporary and must not ship.**

## 4. API surface actually used

Confirmed by reading the SDK's own javadoc (extracted from the downloaded artifacts) and, where the docs were ambiguous, by real compiler errors against the actual `.aar` — not invented:

```kotlin
val factoryRegistry = FactoryRegistry(
    StandardTraitRegistry.traits + GoogleTraitRegistry.traits,
    StandardDeviceTypeRegistry.types + GoogleDeviceTypeRegistry.types,
)
val homeConfig = HomeConfig(
    strictOperationValidation = false,
    coroutineContext = Dispatchers.IO,
    factoryRegistry = factoryRegistry,
    serverClientId = null, // ADR-036 Decision 8 — no server-side credential requested
    homePlatformScope = HomeConfig.HomePlatformScope.HOME_PLATFORM_SCOPE_VERSION_1,
)
val client = Home.getClient(context, homeConfig)

client.registerActivityResultCallerForPermissions(activity)   // in load(), before onCreate() finishes
client.requestPermissions(ForcePermissionFlow.FORCE_LAUNCH, null)  // suspend; returns PermissionsResult(status, errorMessage, serverAuthCode)

val devices = client.devices(enableMultipartDevices = false).list()   // suspend; Set<HomeDevice>
device.has(OnOffLightDevice)                                          // Boolean
val type = device.type(OnOffLightDevice).first()                      // Flow<OnOffLightDevice>
type.standardTraits.onOff?.onOff   // Boolean? — the Matter "OnOff" cluster attribute (state)
type.standardTraits.onOff?.on()    // suspend command — distinct from the attribute above
type.standardTraits.onOff?.off()   // suspend command
```

Three concrete traps documentation alone did not surface, resolved against the real dependency:

1. **Registry access.** `StandardTraitRegistry`, `GoogleTraitRegistry`, etc. are Kotlin `object` singletons. The javadoc (a Java-view rendering) shows `.INSTANCE.traits`; from Kotlin it's just `.traits`.
2. **`Id` construction.** The javadoc shows a public `Id(String)` constructor, but Kotlin requires the factory `Id.Companion.of(deviceId)` — the class is a `value class` whose public-looking Java constructor isn't the real Kotlin call site.
3. **State vs. command naming collision.** The `OnOff` trait exposes both a readable `onOff: Boolean` attribute (the Matter cluster's "OnOff" attribute) and `on()`/`off()` suspend *commands* — same trait, different members, easy to conflate. The attribute is reached via `device.type(X).standardTraits.onOff.onOff` (state lives one level down, under `.standardTraits`, not directly on the device-type object).

## 5. Verified results (physical device, 2026-09-06)

| Step | Result |
| --- | --- |
| `ping()` | `{"ok":true,"sdkInt":35,"platformSupported":true,"clientInitialized":true}` — confirms `Home.getClient()` succeeded before any user interaction. |
| `requestGoogleHomePermissions()` | Google's real account-picker and consent screen appeared, including the "app not verified" warning GH03a predicted for an unverified OAuth client. User accepted. Result: `{"status":"SUCCESS"}`. |
| `listDevices()` | 5 real devices returned from the user's own Google Home: `Living Room TV` (no OnOff light/plug trait) and four lamps — `Banheiro_Casal`, `QuartoCasalUm`, `QuartoCasalDois`, `QuartoCasalTres` — each with `hasOnOffLight: true`. **These lamps are Surplife/Tuya cloud-to-cloud devices**, exposed through the Home APIs with no Google hub involved. |
| `readDeviceState()` (QuartoCasalUm) | `{"id":"device@a012379f-...","name":"QuartoCasalUm","onOff":true}` — real state, correctly read. |
| `executeAction(action:"off")` then `executeAction(action:"on")` | Both returned `{"ok":true}`, and **the physical lamp was confirmed, visually, to turn off and back on** — not inferred from the API response alone. |

One implementation bug was found and fixed mid-spike: `listDevices()`/`readDeviceState()` initially serialized the device id via `Id`'s auto-generated `toString()` (`"Id(id=device@...)"`) instead of the raw value (`device.id.id`), which would have broken any client that fed the id back into `Id.of()`. Fixed before the on/off step.

## 6. Answers to the card's open questions

- **Does the Capacitor bridge sustain this?** Yes, cleanly. No `BridgeActivity` fork was needed; `registerPlugin()` before `super.onCreate()` was sufficient, confirming GH02's own hypothesis about where the SDK's consent registration needs to happen.
- **Do the user's real Surplife/Tuya devices appear?** Yes — this was the card's explicit "prove or register as a finding" instruction, and it resolved positively with real evidence, not inference from Google's general documentation.
- **Kotlin Multiplatform evidence (ADR-036 §7):** unchanged at *moderate*. The implementation above is real Kotlin, coroutines/Flow-based as ADR-036 anticipated; nothing here strengthens or weakens the existing KMP evidence — it's additional confirmation of what was already recorded, not a new data point.

## 7. What this spike deliberately does not establish

- **No production shape.** `GoogleHomePlugin` does not implement `ProviderAdapter` (correct, per ADR-036 Decision 3 — Google Home isn't meant to) and is not wired to `Scene`, `Vibe`, or the scheduler in any way.
- **No persistence.** Nothing here writes a Google identifier to `back_vibes` or to any durable device-side store. Every call re-queries the SDK's in-memory flow. [GH03b](data-retention.md)'s open retention question (§10.1: how a saved automation can reference a Google device past the 10-day policy window) is **not** answered by this spike. It is now tracked as its own task, **GH03c — Google Home Data Retention Compliance Review** ([Trello](https://trello.com/c/tNXiUfNM)) — a legal/risk decision, not further engineering investigation, since GH03b already exhausted the available public policy text.
- **No production certification.** This ran entirely under GH03a's "development access" gate (unverified OAuth client, 100 test-user ceiling). The production gate (§3 of GH03a) remains externally blocked by Google, independent of this result.
- **No iOS.** Per ADR-036 Decision 11, out of scope, and nothing here was written to make an iOS port harder — no Android-specific concept reached the plugin's public contract (its method names and JSON shapes are platform-neutral).
- **No Matter, no hub.** The devices reached here were cloud-to-cloud (Surplife/Tuya). Matter-specific behavior (hub-mediated local/remote control) was not exercised.

## 8. Reuse classification — what carries forward, what is spike-only

The branch mixes code proven against real hardware with code that only exists to make the spike operable without production infrastructure. They must not be treated as one unit when a real implementation is scoped.

| Part | Classification | Why |
| --- | --- | --- |
| **Debug page and route** (`src/views/dev/GoogleHomeDebugPage.vue`, `/dev/google-home` route, the Settings entry point) | ❌ **Temporary only — do not carry forward** | Built solely to drive the plugin without a CDP/Appium setup (§3). Not gated, not styled as product UI, prints raw JSON. Has no place in `develop` under any circumstance. |
| **Local SDK/AAR wiring** (`android/google-home-sdk-repo/` local Maven repo, the hardcoded relative `url = uri('../google-home-sdk-repo')`, gitignored) | ❌ **Temporary shape — do not carry forward as-is** | Works only because each developer manually downloads and places the SDK per GH03a finding B. Not reproducible in CI or for a second developer without the same manual step. A real implementation needs a documented, reproducible dependency-provisioning story (private repository mirror, documented manual step with checksum verification, or whatever the team decides) — this spike deliberately did not solve that, it only proved the API shape works. |
| **Permission code** (`load()`'s `Home.getClient()`/`HomeConfig`/`FactoryRegistry` construction, `registerActivityResultCallerForPermissions()` before `super.onCreate()`, `requestGoogleHomePermissions()`) | ✅ **Reusable** | Physically verified: real consent screen, real `SUCCESS` status, no `BridgeActivity` fork needed. This is the answer to GH02's first stop condition and should not be re-derived. |
| **Device discovery** (`listDevices()`, the combined `StandardTraitRegistry + GoogleTraitRegistry` / `StandardDeviceTypeRegistry + GoogleDeviceTypeRegistry` factory registry) | ✅ **Reusable** | Physically verified against real cloud-to-cloud devices (the target case). The registry-combination choice is the confirmed reason Surplife/Tuya lamps were reachable at all — a real implementation should not narrow this without a deliberate reason. |
| **State read** (`readDeviceState()`, the `device.type(X).standardTraits.onOff.onOff` access pattern) | ✅ **Reusable** | Physically verified to return the device's real state. The attribute-vs-command naming trap (§4) is exactly the kind of thing worth preserving as working code rather than rediscovering. |
| **On/Off execution** (`executeAction()`, `onOff.on()` / `onOff.off()`) | ✅ **Reusable** | The one result verified beyond the API response — physical lamp behavior confirmed visually (§5). |
| **`deviceId` serialization/reconstruction** (`device.id.id` on the way out, `Id.of(deviceId)` on the way back in) | ✅ **Reusable, with the bug fix included** | The `toString()` bug (§5) is already fixed in `3ae9f1b`. The corrected round-trip (`id.id` → JSON string → `Id.of()`) is verified working, including being pasted back in through the debug page and resolving to the same device. Carry the fix, not the original mistake. |

**Net effect:** everything that touches the real Google Home SDK surface (permissions, discovery, state, execution, id handling) is reusable and verified. Everything that exists only to route around missing production infrastructure (debug UI, ad hoc local dependency wiring) is not, and must be replaced with a production-appropriate equivalent, not deleted-and-forgotten — the debug page in particular is the fastest way to re-verify a future change against real hardware and is worth keeping *as a local, uncommitted tool* even though it must never reach `develop`.

## 9. This branch does not merge into `develop` as-is

`feature/gh02-google-home-android-spike` is preserved on the remote as a **historical reference**, not as a pending contribution. No code from it — reusable or not — is to be integrated directly into `develop`. A real Google Home implementation starts as a **new branch off `develop`**, selectively reusing the code identified in §8, with:

- a reproducible dependency story for the SDK (not the gitignored local-repo hack);
- no debug UI;
- the architecture, persistence, privacy, and certification decisions still pending from ADR-036, GH03a, and GH03b actually resolved first — most importantly **GH03c** (the legal question about referencing a Google device identifier past the 10-day retention window, formalized 2026-09-07 as its own task rather than an open question inside GH03b), since that can change how device identity is represented on both sides of the mobile/backend boundary this spike deliberately left unaddressed. A production-implementation task should not be scoped until GH03c resolves; GH04 does not depend on it and may proceed in parallel.

The spike branch itself receives no further commits beyond indispensable documentation fixes — it is frozen as evidence of what was verified on 2026-09-06, not as a base to build on directly.

## 10. Recommended next steps (not started here)

Deliberately not carded yet, consistent with the original GH02 instruction to let the spike's real constraints shape the implementation plan rather than pre-committing to one:

- Design the real mobile-side storage for the id-mapping and reporting contract described in ADR-036 Decision 7, informed by this spike's confirmed API shape.
- Extend device-type/trait coverage in `GH04` using the trait names now confirmed real (`OnOffTrait`, `SimplifiedOnOffTrait`, `LevelControlTrait`, etc.) instead of the provisional list GH04 was scoped with.
- Decide, with GH03b's legal question resolved, how the confirmed `device.id.id` value is represented (or deliberately not stored) on the backend side.
- Solve the SDK dependency-provisioning story before any CI pipeline needs to build against it.
