# ADR-013: Home Assistant as first Smart Home provider

## Status

**Accepted** — governs the **first provider implementation** under the Smart Home provider adapter architecture ([ADR-012](ADR-012-smart-home-provider-strategy.md)).

## Date

2026-06-14

## Context

[ADR-012](ADR-012-smart-home-provider-strategy.md) established that IXORA uses a **provider adapter architecture** and will not integrate directly with individual device brands. The first real provider must be chosen before any implementation begins.

Candidate evaluation criteria:

1. **Device coverage** — does it work with many device brands without requiring a separate IXORA integration for each?
2. **API stability** — does it have a documented, stable REST/WebSocket API that can be called from a backend?
3. **Open source / user-controlled** — does avoiding a proprietary cloud reduce IXORA's dependency on third-party availability and API policy changes?
4. **MVP feasibility** — can integration be built without requiring local network discovery, BLE pairing, or complex OAuth flows?
5. **User base fit** — do technically-inclined IXORA users already own instances?

Additionally, the IXORA backend runs on **DigitalOcean App Platform** — a hosted cloud environment with no local network access to the user's home. This rules out integrations that require direct LAN connectivity from the IXORA server.

### Why not Alexa or Google Home first?

- Both require **OAuth app registration** with the ecosystem vendor and impose approval processes.
- Both are **voice-assistant ecosystems** — device control is secondary to their primary purpose.
- Both require **cloud-to-cloud** callbacks and webhook registrations that add operational complexity for MVP.
- They cover fewer locally-controllable device types than Home Assistant does as an aggregator.

### Why not Matter first?

- Matter over Thread / Wi-Fi requires **local network proximity** or a Matter cloud bridge. Neither is available in the DigitalOcean App Platform environment.
- The Matter SDK and commissioning flow are complex for an MVP that primarily needs `turn_on` / `turn_off`.

### Why Home Assistant?

- **Open source** — IXORA has no dependency on HA's commercial decisions or API access policies.
- **Broad device coverage** — HA integrates with 3,000+ device types and brands out of the box, including Tuya, Zigbee, Z-Wave, LIFX, Philips Hue, and many others.
- **Stable REST API** — HA exposes a documented REST API (`/api/states`, `/api/services`) callable from any HTTPS client. No proprietary SDK required.
- **User-controlled instance** — users run their own HA instance. No HA cloud subscription is required for the local API.
- **Long-lived access token** — HA supports long-lived access tokens (LLAT) that can be issued without interactive OAuth per request. Simple, predictable credential lifecycle.
- **Avoids N direct-brand integrations** — a user's Zigbee lights, Tuya sockets, and Hue bulbs all appear as HA entities without IXORA integrating each brand separately.

---

## Decision

**Home Assistant is the first Smart Home provider. Connection is configured manually (base URL + long-lived access token). Credentials are stored encrypted on the backend. No local network discovery, no Matter/Thread/Zigbee direct support, and no auto-discovery in MVP.**

### Connection model (MVP)

| Field | Description | Security |
| --- | --- | --- |
| **`base_url`** | User's Home Assistant instance URL (e.g. `https://ha.example.com:8123`) | Stored backend-side only; never exposed to mobile |
| **`access_token`** | Long-lived access token generated in HA user profile | **Encrypted at rest** in `back_vibes` database; never returned in API responses |

Mobile provides `base_url` and `access_token` when creating a provider connection. Laravel stores them encrypted. Mobile never receives the token back.

### HA REST API surface (MVP)

| HA Endpoint | IXORA adapter use |
| --- | --- |
| `GET /api/states` | List all entity states → `listDevices()` |
| `GET /api/states/<entity_id>` | Single entity state → `readStatus()` |
| `POST /api/services/<domain>/<service>` | Call a HA service → `executeAction()` (e.g. `light.turn_on`) |
| `GET /api/` | Check API reachability → `testConnection()` |

### MVP exclusions

| Capability | MVP |
| --- | --- |
| **Local network discovery** (mDNS / Zeroconf) | ❌ Not in MVP — user enters URL manually |
| **Matter / Thread direct** | ❌ Not in MVP — handled by HA internally if user configures it |
| **Zigbee / Z-Wave direct from IXORA** | ❌ Not in MVP — devices appear as HA entities |
| **HA Cloud / Nabu Casa** | ❌ Not required — local API access assumed |
| **HA WebSocket (streaming state)** | ❌ Not in MVP — polling via REST only |
| **HA long-polling / event bus** | ❌ Not in MVP |
| **Automatic token refresh** | ❌ LLAT does not expire by default; no rotation in MVP |
| **Multiple HA instances per user** | ❌ MVP supports one provider connection per user per provider type |

### Security requirements

| Requirement | Implementation |
| --- | --- |
| **Encrypt access token at rest** | Laravel `encrypt()` / `Crypt::encryptString()` on store; decrypt on use; never in API response |
| **Never expose token to mobile** | `ProviderConnectionResource` must omit token field entirely |
| **Validate base URL** | Reject non-HTTPS URLs in MVP (optional config override for local dev) |
| **Test connection on create** | `POST /api/provider-connections` calls `testConnection()` before persisting; return 422 if unreachable |

### Known limitations documented for users

- HA instance must be reachable from the IXORA backend (DigitalOcean App Platform) — a public URL or tunnel (e.g. Cloudflare Tunnel, Tailscale) is required.
- LAN-only HA instances will not work with IXORA without a remote access setup.
- This limitation should be documented in the Devices onboarding flow UX copy.

---

## Consequences

### Positive

| Outcome | Why it matters |
| --- | --- |
| **No brand-specific OAuth per user** | One token covers all devices the user has configured in HA. |
| **Broad device coverage from day one** | Zigbee, Z-Wave, Wi-Fi, Tuya, Hue, etc. all appear as HA entities. |
| **Simple credential model** | LLAT is a single static token with no expiry by default — minimal lifecycle complexity. |
| **Stable API** | HA REST API is stable across minor versions; breaking changes are release-noted. |
| **No vendor lock-in** | HA is MIT-licensed; IXORA is not dependent on a third-party cloud service. |

### Negative / tradeoffs

| Tradeoff | Impact |
| --- | --- |
| **Requires remote-accessible HA** | Users with LAN-only HA must set up tunnelling — extra setup friction. |
| **Not viable for non-technical users** | HA itself requires setup; IXORA's first Smart Home users are technically inclined. |
| **LAN-discovery not possible** | Backend cannot reach the user's local network; URL must be entered manually. |
| **One provider per user in MVP** | Multiple HA instances (e.g. vacation home) require a follow-up spec. |

---

## Alternatives Considered

| Alternative | Why not chosen |
| --- | --- |
| **Tuya first** | Requires Tuya cloud OAuth per user; only covers Tuya-branded devices. |
| **Philips Hue first** | Hue Bridge requires local LAN pairing — not feasible from DO App Platform. |
| **Alexa first** | OAuth app approval, voice-ecosystem dependency, limited for non-voice actions. |
| **Google Home first** | Same concerns as Alexa; additionally requires Google Cloud console project setup. |
| **Matter (from backend) first** | No local network access from DO; Matter commissioning flow too complex for MVP. |
| **MQTT broker first** | Requires exposing MQTT broker endpoint; no standard device model; custom per-device setup. |

---

## Related Docs

| Document | Relationship |
| --- | --- |
| [`ADR-012`](ADR-012-smart-home-provider-strategy.md) | Provider adapter architecture — this ADR is governed by that decision |
| [`ADR-014`](ADR-014-device-abstraction-and-deduplication.md) | Device abstraction — HA `entity_id` maps to `provider_device_id` |
| [`ADR-015`](ADR-015-vibe-device-action-architecture.md) | Vibe device action model — `executeAction()` called from action executor |
| [`ADR-016`](ADR-016-smart-home-async-execution.md) | Async execution — HA calls are async, not in CRUD request path |
| [`../specs/smart-home/mvp/spec.md`](../specs/smart-home/mvp/spec.md) | Feature spec — security section, API outline |
| [`../specs/smart-home/mvp/plan.md`](../specs/smart-home/mvp/plan.md) | Phase 5 — HA adapter contract |
| [`../standards/front-vibes-auth-core.md`](../standards/front-vibes-auth-core.md) | All API calls use Firebase Bearer — applies to provider connection create |

---

When a second provider is added, create a new ADR referencing [ADR-012](ADR-012-smart-home-provider-strategy.md) and document its specific connection model, credential lifecycle, and MVP exclusions.
