# Mobile CDN validation — asset delivery on Capacitor

**Status:** Active architecture (source of truth)  
**Scope:** How the **mobile app** validates and consumes **public HTTPS asset URLs** from the Laravel API (CDN and legacy hosts)  
**Applies to:** `front_vibes` (Ionic + Capacitor on Android/iOS WebView + native HTTP/audio)

---

## Purpose

Define **what “CDN-ready” means for Ixora mobile**: which URL shapes and HTTP behaviours the platform expects, how validation differs between **browser dev**, **native WebView**, and **CapacitorHttp**, and how QA confirms **images, CSS backgrounds, streaming audio, and offline downloads** work reliably—**without** direct DigitalOcean Spaces access on device.

This document is **architecture + validation policy**. Upload authority and object layout live in [`storage-strategy.md`](storage-strategy.md); offline byte storage lives in [`../audio/audio-cache.md`](../audio/audio-cache.md).

---

## Context

Laravel persists **full public HTTPS URLs** on catalog and vibe rows (typically **DigitalOcean Spaces CDN** for new content). The mobile app **never** holds Spaces credentials; it only uses strings returned in JSON (`file_url`, `thumbnail_url`, `artwork_url`, etc.).

Rendering paths include:

| Mechanism | Typical asset |
| --- | --- |
| `<img :src="…">` | Thumbnails, artwork |
| CSS `background-image: url('…')` | Cards, player hero |
| `@capgo/native-audio` / ExoPlayer | Catalog **`file_url`** streaming |
| **`CapacitorHttp.request()`** | Full-file **offline download** (native stack) |

**Development vs production:** In **`npm run dev`**, the WebView origin is often **`https://localhost`**. Cross-origin **`fetch()`** to storage/CDN hosts is subject to **browser CORS** and may fail even when production would work. **Native CapacitorHttp** and **ExoPlayer** do **not** use WebView CORS for their HTTP stacks.

**Migration:** **Legacy Firebase Storage HTTPS URLs** may still appear on rows alongside CDN URLs until backend migration completes. Mobile treats all API URLs as **opaque HTTPS** (no host whitelist).

**Offline matching:** Audio offline manifests key on **exact URL string equality** with `layer.fileUrl` — URLs must stay **stable** (no rotating signed URLs on playback/download paths).

---

## Current Decision

1. **Mobile consumes only HTTPS CDN (or legacy HTTPS) URLs returned by the API** — no direct Spaces bucket access, uploads, or private object APIs on device.
2. **CDN validation** exists to ensure **Android/iOS WebViews and native stacks** can load media **reliably** in **production-like builds**.
3. **HTTPS is mandatory** for production asset URLs; mixed content and `http://` asset hosts are out of scope for supported builds.
4. CDN (or equivalent public HTTPS) URLs **must work** for:
   - **`img` `src`**
   - **CSS `background-image`**
   - **Audio streaming** (native player)
   - **`CapacitorHttp` offline downloads**
5. The app **must not rely on `localhost` (or dev-server) asset URLs in production** — catalog media comes from API-hosted HTTPS only.
6. **CORS behaviour differs** between **browser dev mode** and **native WebView/production**; do not treat dev-only CORS failures as CDN misconfiguration without a device build test.
7. **`CapacitorHttp.request()` bypasses WebView CORS** for offline full-file downloads (see audio-cache doc); WebView **`fetch()` must not** be used for that path.
8. CDN (or origin) responses for audio **must support byte-range requests** (`Accept-Ranges`, `206 Partial Content`) so **large files stream progressively** via ExoPlayer.
9. **Large audio files must stream progressively** — the app does not require full-file buffer before playback start for normal online listening (distinct from explicit “Download for offline”).
10. **No signed / private / short-lived temporary URLs** on mobile **playback or offline-download paths** — stable public URLs only, so manifests and ExoPlayer cache behaviour remain predictable.
11. **URLs should remain stable** for **offline manifest matching** and repeat playback; path or query changes require user re-download.
12. **Legacy Firebase HTTPS URLs may coexist** during migration and must remain loadable under the same rules.

---

## Architecture

```
┌─────────────────┐     JSON (HTTPS URL strings)      ┌──────────────────┐
│  Laravel API    │ ────────────────────────────────► │  front_vibes     │
│  (CDN URLs in   │     file_url, thumbnail_url, …    │  Capacitor app   │
│   DB columns)   │                                   └────────┬─────────┘
└─────────────────┘                                            │
                                                                 │ no Spaces SDK
                    ┌────────────────────────────────────────────┼────────────────────────┐
                    │                                            ▼                        │
                    │  WebView: <img>, CSS url()  ──► CDN HTTPS (same as any TLS origin)   │
                    │  NativeAudio / ExoPlayer    ──► GET + byte-range streaming           │
                    │  CapacitorHttp (offline)    ──► native GET (no WebView CORS)       │
                    └────────────────────────────────────────────────────────────────────┘
                                         │
                                         ▼
                    https://…cdn.digitaloceanspaces.com/…  (preferred)
                    https://…firebasestorage.googleapis.com/…  (legacy, allowed)
```

### Consumption matrix

| URL use | API field (examples) | Runtime | CORS note |
| --- | --- | --- | --- |
| Sound playback | `file_url` | ExoPlayer via NativeAudio | Native HTTP; byte-range expected |
| Thumbnails / lists | `thumbnail_url`, `card_image_url` | `<img>` or CSS background | WebView loads HTTPS like normal |
| Player hero | `player_background_url` | CSS `background-image` | WebView |
| Square artwork | `artwork_url` | `<img>` / notification metadata | WebView |
| Offline full file | `file_url` (manifest `remoteUrl`) | **CapacitorHttp** + Filesystem | **Not** WebView `fetch()` |

### Dev diagnostics (non-production)

With **`npm run dev`**, console may emit **`[CDNAssets]`** (hostname only, not full URLs):

| Tag | When |
| --- | --- |
| `sound` | Building execution plan (unique `fileUrl` per plan) |
| `artwork` | `playVibe()` square / notification URL |
| `offline-download` | Native offline GET starts |

Production builds strip **`import.meta.env.DEV`** — these logs must not appear in release.

### QA environment

Point **`VITE_API_BASE_URL`** at an API that returns **CDN URLs** (or validated staging equivalents) for catalog sounds, cover bundles, and vibes — typically **`https://staging-api…`** with rows backed by Spaces CDN.

---

## Rules

### URL and transport

- Use **only** HTTPS URLs from API responses for production assets.
- **Do not** hardcode Spaces keys, presigned POST policies, or bucket endpoints in mobile.
- **Do not** depend on **`http://localhost`** or Vite dev-server URLs for **production** catalog media.
- Prefer **stable public CDN URLs** from Laravel; avoid introducing **signed/expiring** URLs on paths used for playback or offline manifest keys.

### WebView vs native HTTP

- **Images and CSS backgrounds:** standard WebView loading — validate on **real device builds**, not live reload alone.
- **Online audio:** native ExoPlayer path — requires **progressive streaming** and **range support** from the CDN/origin.
- **Offline download:** **`CapacitorHttp.request()`** only — never WebView **`fetch()`** for audio bytes (CORS on `https://localhost` in dev).

### Stability and migration

- Treat **`remoteUrl === layer.fileUrl`** (exact string) as the offline playback match rule — CDN path or query changes require **re-download**.
- **Firebase legacy URLs** remain valid test cases until migration completes.
- **No host whitelist** in app code — any HTTPS origin the API returns should work if TLS and CDN headers are correct.

### Validation scope

- **CDN validation** is a **manual + release-build checklist** (below), not an automated CI gate in this doc—unless the team adds one later without changing policy.
- **Live reload** (`ionic capacitor run android -l`) is **unsuitable** for final offline/CDN sign-off — use installable builds per [`../audio/audio-cache.md`](../audio/audio-cache.md).

---

## Risks

| Risk | Impact | Mitigation |
| --- | --- | --- |
| Dev WebView CORS false negatives | “CDN broken” in browser only | Test on device; use CapacitorHttp for downloads |
| Missing `Accept-Ranges` on audio | Seek/buffer failures, poor streaming | CDN/origin config; smoke-test large MP3 |
| Signed/expiring sound URLs | Offline manifest mismatch; playback stops | Stable public CDN URLs from API |
| localhost asset URLs in prod build | Broken media in release | API-only HTTPS URLs |
| Direct Spaces access in mobile | Credential leak; policy violation | Forbidden — URLs from API only |
| URL string change without re-download | Offline play falls back to HTTPS | Document stable URL contract |
| Assuming full ExoPlayer cache = offline | False confidence | Distinguish streaming cache vs CapacitorHttp download |
| Mixed Firebase + CDN during migration | Inconsistent test data | Test both URL families in checklist |

---

## Validation

### Preconditions

- API env returns HTTPS URLs (staging or prod-like).
- **Android and/or iOS real device**, **release or debug install without live reload**.

### Manual checklist — sounds & playback

- [ ] Catalog sound **`file_url`** uses HTTPS CDN host (e.g. `…cdn.digitaloceanspaces.com/…`) — **plays** on device (native engine).
- [ ] Layer strip / editor shows **thumbnail** from CDN **`thumbnail_url`**.
- [ ] **Offline → Download for offline** with CDN **`file_url`**; **airplane mode** — vibe still **plays**.
- [ ] Leave player and **return** — offline playback still works (audio manifest + vibe snapshot).
- [ ] **Remove download** — when online, playback falls back to **HTTPS** streaming.

### Manual checklist — imagery

- [ ] **My Vibes** cards: CDN **`card_image_url` / `thumbnail_url`** (no broken images).
- [ ] **Home** “Continue” card loads CDN imagery.
- [ ] **MiniPlayer** / MediaSession: CDN **`artwork_url`** (or artwork fallback chain).
- [ ] **Player** full-screen **`player_background_url`** from CDN (or gradient fallback).

### Manual checklist — cover bundles & presets

- [ ] **Choose cover** applies CDN URLs from cover bundle into create/edit vibe form.
- [ ] **Preset import** with nested CDN cover URLs — vibe visuals and sound **`file_url`** work.

### Manual checklist — theme & build

- [ ] **Dark** and **light** theme — artwork legible (gradients unchanged).
- [ ] **Real device build without live reload** — full smoke test above passes.

### Optional CDN/origin checks (backend/infra)

- [ ] Audio object responds with **`Accept-Ranges: bytes`** and **`206`** for range GET
- [ ] Large catalog file starts playback before full download completes (progressive stream)

---

## Related Files

| Location | Path |
| --- | --- |
| **Central (this repo)** | `docs/architecture/storage/storage-strategy.md` |
| | `docs/architecture/storage/artwork-background-strategy.md` |
| | `docs/architecture/audio/audio-cache.md` |
| **front_vibes (repo copy)** | `docs/mobile-cdn-validation.md` — keep aligned with this file |
| | `docs/artwork-background-strategy.md` |
| | `src/utils/artwork.ts` |
| | `src/services/audio-engine/offline-audio-storage.ts` |
| | `src/services/audio-player.service.ts` |
| | `capacitor.config.ts` |
| **back_vibes** | `docs/storage-strategy.md` |
| | `config/filesystems.php` (`DO_SPACES_CDN_URL`) |
| **Infra** | `opentofu/staging/` — Spaces bucket + CDN |

When changing mobile asset delivery expectations, update **this file first**, then sync the `front_vibes` checklist and related architecture docs.
