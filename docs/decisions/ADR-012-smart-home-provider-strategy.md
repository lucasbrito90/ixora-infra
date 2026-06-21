# ADR-012: Smart Home provider strategy

## Status

**Accepted** — governs **Smart Home Foundation** device integration architecture ([`specs/smart-home/mvp/spec.md`](../specs/smart-home/mvp/spec.md)).

## Date

2026-06-14

## Context

IXORA users compose **vibes** (layered audio + visuals) and play them on mobile. The next product surface is **Smart Home**: allow users to connect smart devices and, later, attach simple device actions to vibes so that playing a vibe can trigger physical effects (lights, speakers, etc.).

The smart-home space is fragmented across many device brands and protocols:

- **Brand-native clouds:** Tuya, Philips Hue, TP-Link Kasa, LIFX, Yeelight, …
- **Voice-assistant ecosystems:** Amazon Alexa, Google Home, Apple HomeKit
- **Open aggregators:** Home Assistant, openHAB, Homey
- **Open standards / protocols:** Matter, Thread, Zigbee, Z-Wave, MQTT, Bluetooth Mesh

Integrating directly with each brand would require:

- A dedicated OAuth / API key flow per vendor
- Separate refresh-token lifecycle per user × vendor
- Vendor-specific capability models and normalisation
- Ongoing maintenance as vendor APIs change

IXORA is a small team. Building N brand integrations before validating the core Smart Home UX is wasteful and operationally expensive.

Additionally, several ecosystem-level concerns must be resolved regardless of which brands are supported:

- **Where are provider credentials stored?** Mobile apps are not a secure secret store. API keys and long-lived tokens must live server-side only.
- **Who owns the device registry?** If mobile stores devices locally, conflicts arise when the user switches devices or reinstalls. The backend must be authoritative.
- **How does IXORA talk to a provider?** A normalised interface decouples vibe-action logic from provider specifics and enables future providers without changing the action model.

---

## Decision

**IXORA will use a provider adapter architecture for all Smart Home integrations.**

### Core principles

| Principle | Rule |
| --- | --- |
| **No direct brand integrations** | IXORA does not integrate with individual device brands; it integrates with provider platforms that aggregate brands. |
| **Provider adapters** | Each supported integration is a provider adapter implementing a shared interface. |
| **Backend is authoritative** | Device registry, provider connection credentials, and status live in **`back_vibes`** (PostgreSQL). |
| **Mobile never stores provider secrets** | Tokens, API keys, and base URLs for provider connections are encrypted and stored server-side only. Mobile calls the **Laravel API** exclusively. |
| **Normalised interface** | The adapter interface normalises device operations regardless of provider specifics. |

### Provider adapter interface (contract — not implemented in MVP)

Each provider adapter must implement:

| Method | Purpose |
| --- | --- |
| **`listDevices(connection)`** | Return all devices/entities accessible via this connection. |
| **`readStatus(connection, deviceId)`** | Return current state of one device (on/off, brightness, etc.). |
| **`executeAction(connection, deviceId, action, parameters)`** | Send an action to the device and return success/failure. |
| **`testConnection(connection)`** | Validate that the connection credentials are reachable and return connection health. |

### Provider examples

| Provider | Category | MVP |
| --- | --- | --- |
| **Home Assistant** | Open aggregator | ✅ **First provider** ([ADR-013](ADR-013-home-assistant-first-provider.md)) |
| Tuya | Brand-native cloud | ❌ Future phase |
| Philips Hue | Brand-native cloud | ❌ Future phase |
| Amazon Alexa | Voice ecosystem | ❌ Future phase |
| Google Home | Voice ecosystem | ❌ Future phase |
| Apple HomeKit | Voice ecosystem | ❌ Future phase |
| Matter | Open protocol | ❌ Future phase |
| Thread, Zigbee, Z-Wave | RF protocols | ❌ Future phase |
| MQTT broker | Message bus | ❌ Future phase |

### MVP scope of this ADR

The **MVP establishes the provider abstraction only**. No real device execution ships in Phase 1 (this ADR + spec + ADRs 013–016). The first real provider implementation is Home Assistant ([ADR-013](ADR-013-home-assistant-first-provider.md)).

---

## Consequences

### Positive

| Outcome | Why it matters |
| --- | --- |
| **Single integration surface** | New providers require a new adapter only — action model, device model, and UI do not change. |
| **Secrets security** | Provider tokens never leave the backend; mobile cannot exfiltrate credentials. |
| **Maintainability** | One adapter contract to maintain per provider instead of scattered brand-specific code. |
| **Validated before investment** | Smart Home UX is validated with Home Assistant before paying the cost of N integrations. |
| **Backend authority** | Device registry is consistent regardless of mobile platform, reinstall, or device change. |

### Negative / tradeoffs

| Tradeoff | Impact |
| --- | --- |
| **Adapter layer overhead** | Each new provider requires an adapter implementation, even simple ones. |
| **Provider aggregator dependency** | Users must already have Home Assistant (or future supported provider) — IXORA does not manage device onboarding directly. |
| **No direct protocol support in MVP** | Matter/Thread/Zigbee users without Home Assistant cannot use Smart Home in MVP. |

---

## Alternatives Considered

| Alternative | Why not chosen |
| --- | --- |
| **Direct brand integrations (Tuya, Hue, …)** | N × OAuth flows, N × token lifecycle, N × capability models — disproportionate cost before UX validation. |
| **Matter/Thread direct from backend** | Requires local network access or Matter cloud bridge; not compatible with current DigitalOcean App Platform deployment model. |
| **Alexa/Google Home first** | Both require voice-assistant account pairing and are locked to their ecosystems; Home Assistant covers a broader device set without voice dependency. |
| **Mobile stores provider credentials** | Insecure — mobile apps are not secret stores; rejected per platform security policy (also [ADR-002](ADR-002-laravel-only-storage-writes.md) precedent for backend-only writes). |
| **No provider abstraction (one integration, hard-coded)** | Tight coupling — adding a second provider would require changes throughout the action model and mobile UI. |

---

## Related Docs

| Document | Relationship |
| --- | --- |
| [`../specs/smart-home/mvp/spec.md`](../specs/smart-home/mvp/spec.md) | Feature spec — product goal, domain model, API outline, acceptance criteria |
| [`../specs/smart-home/mvp/plan.md`](../specs/smart-home/mvp/plan.md) | Implementation phases |
| [`../specs/smart-home/mvp/tasks.md`](../specs/smart-home/mvp/tasks.md) | Task checklist |
| [`ADR-013`](ADR-013-home-assistant-first-provider.md) | Home Assistant as first provider |
| [`ADR-014`](ADR-014-device-abstraction-and-deduplication.md) | Device abstraction and deduplication |
| [`ADR-015`](ADR-015-vibe-device-action-architecture.md) | Vibe device action architecture |
| [`ADR-016`](ADR-016-smart-home-async-execution.md) | Async execution foundation |
| [`ADR-002`](ADR-002-laravel-only-storage-writes.md) | Backend-only writes precedent |
| [`../standards/front-vibes-auth-core.md`](../standards/front-vibes-auth-core.md) | Mobile auth — all API calls require Firebase Bearer |

---

When a new provider is ready to integrate, create a new ADR (`ADR-01N-<provider>-adapter.md`) and reference this decision as the governing architecture.
